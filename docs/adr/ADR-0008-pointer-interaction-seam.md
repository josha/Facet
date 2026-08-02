# ADR-0008: Pointer interaction seam (grips, cursor hints, overlays, activate meta)

- **Status:** Accepted (2026-07-19, director Part-2 workstream 1 — Table Phase B per ADR-0007).
- **Use case (named, per the expansion gate):** Table Phase B interactions — mouse column-resize on grip zones, row drag-and-drop with a drop indicator, modifier-key multi-select, and gamepad/keyboard resize equivalents. No shipped primitive could express any of these: the adapter had no pointer stream (taps only), no cursor semantics, and no overlay container outside stack flow.

## Decision

Five additive seams, all optional for adapters (feature-detected with `~= nil`):

1. **`UI.Grip`** — a non-button, Active pointer zone. Engine truth (platform research 2026-07-19): the engine force-overrides `UserInputService.MouseIcon` while the pointer is over any `GuiButton`, so cursor-hinted zones MUST be Frames. Props: `cursorHint` (semantic string), `focusable` (opt-in; grips sort to the END of the presenter focus order so list navigation stays content-first), pointer callbacks.
2. **`UI.Anchor`** — overlay container (solver kind `anchor`, shipped in the P1.2 spike, now exposed): children place by `anchor` + `offsetX/offsetY` and never join stack flow. Fill children stretch (content layers under overlays). `Box.offsetX/offsetY` are **arrange-dirty dynamic props**: a moving guide line re-solves and writes rects only — no remount (proven in `tests/pointer.spec.luau`).
3. **Adapter pointer capture** — `adapter.setPointerHandlers(handle, {down, move, up})`. Down on the zone captures; moves/up route to the captured node until release wherever the pointer goes. The renderer wraps handlers with `(path, pos, rectOf)` where `rectOf` is its live solved-rect lookup (`controller.rectOf`), which is how drag math learns a fill column's rendered width without the composite ever touching the engine.
4. **Semantic cursor requests** — the framework only names intents (`cursorHint = "colResize"`); the platform adapter owns art. ScreenTarget keeps a hover hint + capture hint (capture persists off-node during drags) and maps through `CURSOR_ART` to `UserInputService.MouseIcon` (`""` restores the default). **Rider:** no first-party cursor set exists — `CURSOR_ART` is empty until cursor assets are uploaded; the seam is live either way. The gamepad virtual cursor likely ignores MouseIcon → the gamepad affordance is focus-based, not cursor-based.
5. **Activate meta + Adjust action** — `onActivate(path, meta)` now carries `{source, pointer = "mouse"|"touch"|"gamepad", shift, toggle}` (ScreenTarget reads held modifiers at `Activated`; the headless action system tracks them from `deviceKey`; `roblox_input` reads `UserInputService:IsKeyDown`). The presenter gains **`Adjust`** (Direction1D: Left/Right, DPadLeft/DPadRight, ButtonL1/R1) routed as `onAdjust(focusedPath, dir, rectOf)` — the horizontal "change the focused thing" semantic (grip resize now, sliders later).

## Alternatives rejected

- **Live per-pixel column resize** (re-commit each move): each commit remounts every row — instance churn per mouse-move in-engine. Chosen: preview guide line (arrange-only) + one commit on release. NSTableView-style live tracking can come later via reactive row cell dims if a consumer needs it.
- **Buttons as grips**: engine overrides the cursor over GuiButtons (spike-verified) — dead on arrival.
- **Routing pointer moves through the presenter** like activates: a per-move semantic hop buys nothing; capture is an adapter concern and composites receive callbacks directly via blueprint props.

## Contract additions

- Adapter (optional): `setPointerHandlers(handle, handlers)`; `setProp(handle, "cursorHint", v, "binding")`; activate handler now receives `meta`.
- Renderer: `controller.rectOf(path)`; wires pointer props + cursorHint at create.
- FakeTarget test surface: `pointerDown/pointerMove/pointerUp` (capture semantics), `hover/unhover`, `cursorHint()`, `tap(path, meta)`.
- Authority: `Grip.cursorHint = binding`.

## Conformance/tests

`tests/pointer.spec.luau` (seam: hover hints, capture routing, capture-persistent hints, rectOf, overlay minimal writes) + `tests/table.spec.luau` Phase B describes (resize preview/commit/clamp, drag-drop indicator + onReorder + activate suppression + threshold, modifier semantics per device, focus+Adjust resize) + `tests/input.spec.luau` modifier tracking.

## Measured cost

`bench/scenarios.luau` `table-resize-drag` — full gesture (down + 8 preview moves with re-solve + release commit over an 8-row table): p50 2.56ms, p95 3.94ms headless (per preview move ≈0.3ms; the release commit's row remount dominates, same cost class as `table-mutation` p50 0.32ms per row-churn step). Recorded in `artifacts/bench.json`.

## Post-review hardening (same day, verifier + live-drive findings)

- **Deterministic z-order**: the flat sibling render relied on instance creation order, which is NOT deterministic across a structural sync (live-found: remounted row hits painted over their cell text). The renderer now assigns explicit z from the tree walk each structural sync via optional `adapter.setZOrder` (authority: layout). Pinned by a headless test.
- **Drag suppression redesign**: armed at the drag THRESHOLD and keyed to the origin row path (was: armed on release, one-shot). Ordering-independent (engine does not guarantee Activated-vs-InputEnded order) and leak-free (a release off the origin row no longer swallows the next tap elsewhere). Known benign imperfection: after an off-row release, the first later tap on the ORIGIN row is swallowed once.
- **Pointer cancel**: a captured zone that unmounts mid-drag now cancels (`handlers.cancel` → `onPointerCancel`) — no commit, indicator resets; both adapters implement it identically.
- **Selection pruning**: removed rows are pruned from `selectedKeys` and the range anchor (no phantom selections; a re-added key never returns pre-selected).
- **Pattern-safe ids**: `tableId` is pattern-escaped before path matching (`id = "results-list"` works).
- **`toIndex` contract**: the insertion slot counts ALL current rows above the insertion point, the dragged row INCLUDED (pre-removal). Consumers splicing must decrement when the source index is below the slot (see `examples/table_phaseb`). Pinned by the one-step-down test.
- **Keyboard reorder**: `api.moveRow(key, delta)` + presenter shift+Navigate → `onReorderNav` (opt-in). Adjust/reorder key bindings now bind ONLY when the screen opts in (`onAdjust`/`onReorderNav`), so plain screens never shadow gameplay arrow/bumper bindings.
- **Selected-row hover fix (ScreenTarget)**: hover-leave restores `controlSelected` for selected rows, not plain `control`.

## Hand-test revision (2026-07-20, director findings)

- **Drag-and-drop is a LIFT**: at the threshold the dragged row leaves the flow (the keyed-items memo filters it; the gap closes), a ghost chip (`dragLabel(item)`, default the key) follows the pointer, and the drop indicator tracks slots over the REMAINING rows. A drop outside the table root (or after the row vanished from the data) returns the row to its original position and commits nothing.
- **Slot contract CHANGED to post-removal**: `onReorder(key, toIndex)` now counts the remaining rows above the insertion point — consumers splice with `table.remove(from)` then `table.insert(toIndex + 1, moved)`, no adjustment. `moveRow` matches (`slot = i + delta - 1`). (Supersedes the pre-removal contract recorded above; changed before any reorderable game consumer exists.)
- **Capture keep-alive**: the lift unmounts the origin row's instances, which normally cancels the capture. `handlers.cancel(reason)` may now return `true` for reason `"removed"` to keep the capture (its UIS connections and closured handlers outlive the instance); `"destroyed"` (root teardown) never keeps. Both adapters implement identically; suppression is armed at the threshold and cleared by any activate, a fresh pointer-down, or cancel.
- **Focus wraps in every scope** (the spike clamped non-traps; clamping at a list's end reads as "focus went nowhere").
- **`opts.sinkNavigation`** (presenter): a focus-driven screen sinks its nav context so arrows stop reaching the character controls; base screens still never sink by default (HUD overlays must not eat gameplay input).
- **Cells inset + center**: `cellPadding` (default 8) pads cells horizontally; cell/header ZStacks set `alignV = "center"` which children now INHERIT from their stack unless they set their own (solver: zstack parent-default alignment). Header titles render at full contrast (the secondary tint was unreadable over world backgrounds) with the grip still at the true column boundary. The solver's `padding` now accepts per-side tables, same shape as margins.
- **ScreenTarget**: `MouseLeave` restores the pressed-dip `UIScale` to 1 (release-off-button left rows visibly shrunken).

## Hand-test round 2 revision (2026-07-20, director findings)

- **The drag does NOT lift the row** (round 1's lift made the table jump): the row stays in place; the ghost chip + drop line carry the "picked up" read. Slots compute over the full list and convert internally — the `onReorder` POST-removal contract is unchanged. Self-drops are suppressed. The capture keep-alive contract remains in both adapters (any future draggable that unmounts its own zone needs it) though the table no longer exercises it.
- **Menu-open aborts every pointer capture** (adapter-level): Escape cannot be intercepted (engine truth D1 — core-reserved), so the moment `GuiService.MenuOpened` fires, the active capture cancels with reason `"interrupted"` — no drag ever wedges behind the Roblox menu. This is the standing pattern for ALL drag interactions, not just tables.
- **Apple focus/selection model**: clicking a focusable moves keyboard focus there (`focus_graph.focusOn`, wired in the presenter's tap path); keyboard/gamepad navigation reports focus moves via `opts.onFocusNav`, and list screens route that to `api.handleFocusMoved` — the selection follows focus (replace + anchor). Tap selection still rides the activate meta (touch additive, mouse replace/toggle/range) — pointer focus moves never double-select. Consequence: keyboard ranges collapse to the focused row (shift+arrows = reorder by design; range extension is pointer territory).
- **`Adjust` gains `,` / `.` bindings**: Left/Right arrows are eaten upstream by camera scripts on some control stacks (hand-test + injection probes both dead while Down/Up deliver) — comma/period always reach IAS.
- **shift+Navigate always consumes the key when `onReorderNav` is wired** (an impossible edge reorder no longer falls through and wraps focus to the far end).

## Group drag (2026-07-20, director)

Dragging a SELECTED row picks up the entire selection as a contiguous block in document order; an unselected row drags alone (selection untouched). `onReorder` now receives `keys: { string }` (document order) + the post-removal slot counted over the rows NOT being dragged — consumers remove all keys, then insert the block at `toIndex + 1`. The ghost is a CHIP STACK — up to three chips, each offset (2,2) behind the one in front (drag 2 -> 2 chips, drag 5 -> 3), the front chip carrying `dragLabel(origin)`; multiplicity is always visual, never a `+N` suffix. This is the standing pattern for dragging multiple items anywhere in the framework. Drops that reproduce the current order are suppressed via the precomputed documented splice. Contract changed before any reorderable game consumer exists; `moveRow` wraps its single key. Canonical example: rows 1,2,3,4,5 with 1,3,5 selected, drag 3, drop after 2 → `onReorder({1,3,5}, 1)` → `2,1,3,5,4`.

## Engine truths (verified live 2026-07-19, Place1 probes)

1. **`InputObject.Position` is inset-subtracted** (topbar excluded) while IgnoreGuiInset AbsolutePositions are window space — the ScreenTarget pointer seam adds `GuiService:GetGuiInset()` before handing positions to drag math (symptom: drop indicator landed one row high).
2. **Direction1D composite slots are named by AXIS SIGN**: a key in the `Up` slot emits +1, `Down` emits −1 — NOT by which arrow key they hold. `roblox_input` maps `direction > 0 → Up slot`. (Symptom: live keyboard navigation ran backward/clamped; latent since P1.7 because prior live drives used scriptable Fire.)
3. **Modifier chords are not delivered to IAS key bindings under Studio VIRTUAL input**: with Shift held, neither composite nor Bool bindings fire (probed on both). Real-hardware behavior is UNVERIFIED autonomously — see riders.

## Riders

- Cursor art upload (asset set for `colResize`, future `rowDrag`) — seam structured, art pending.
- Engine-side ScreenTarget paths (InputBegan capture, MouseEnter hints, Activated meta) are client-only and Studio-verified rather than headless-tested.
- **Modifier-chord live confirmation** (shift+click range verified live via mouse; shift+Return / shift+Navigate keyboard chords unverifiable via injected input — needs one manual/physical pass; fallback design if real hardware also suppresses: dedicated non-modifier bindings or a grab-mode toggle).
- Touch reorder vs. scroll: reorderable + scrolling lists conflict (finger-drag both scrolls and drags). Named consumers are ≤8 rows (no scroll). Before any scrolling reorderable consumer ships: long-press-to-drag or dedicated drag handles.
- Headerless tables expose no resize UI even for `resizable` columns (the model API `setColumnWidth` still works); by design for borderless lists.
- Gamepad row-reorder (no shift key): needs a grab-mode design when a console reorder consumer exists.
- Bench watch item: `table-resize-drag` heapΔ is commit-remount dominated; revisit if row counts grow before virtualization.
