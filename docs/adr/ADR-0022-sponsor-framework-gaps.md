# ADR-0022 — Sponsor framework gaps: motion authority, structural transitions, toast presentation, unified collection, public drag/drop, paint extensions, semantic feedback

**Date:** 2026-07-27
**Status:** Accepted (finalized 2026-07-28 at gate close, director-closed same day after six review rounds; suite 2567; evidence in `artifacts/sponsor-framework-gaps/`)
**Stage:** `sponsor-framework-gaps` (roadmap Step 5)
**Companions:** `artifacts/sponsor-framework-gaps/responsibility-ledger.md` (ownership),
`artifacts/sponsor-framework-gaps/acceptance-ledger.md` (SF rows), ADR-0017 (native substrate),
ADR-0018 (native stylesheets), ADR-0008 (pointer seam), ADR-0009 (billboard), ADR-0015
(interaction classes).

## Context

The 2026-07-27 re-audit of the Sponsor capability ledger against v0.7.0 found the
remaining framework holes cluster into: no value/structural motion model, no exit
transitions, no toast surface, no unified virtualized+reorderable+droppable list, drag
policy without a public blueprint contract (no velocity, no promotion tokens, no edge
autoscroll), missing authored paint escapes (continuous color, image tint, stroke,
zIndex override, fractional markers), no semantic feedback seam, and async-avatar
gaps. One live defect was also found: the **presentation transform channel is a
silent no-op on the real adapter** — `presenter` drives keyboard keep-visible through
`controller.setPresentationOffset` → `adapter.setProp(root, "transform", …,
"presentation")`, `FakeTarget` records the prop generically so headless suites pass,
but `screen_target.setProp` has no `transform` (or `transparency`) branch, so on
device the shift never lands (SF-M9).

## Decision 1 — one motion authority in pure Luau, stepped by an injectable clock

`src/motion/` owns all value motion. It is engine-free; the client binds it to
`RunService.PreRender` at the adapter edge; headless tests step a fake clock.

- **Spring solver** (`motion/spring.luau`): semi-implicit Euler parameterized by
  `dampingRatio` + `response` (`omega = 2π/response`, `k = omega²`,
  `c = 2ζω`), `MAX_DT = 0.1`, substep `1/120`, settle eps `1e-3` on value AND
  velocity. `setTarget` never touches value/velocity (interruptibility);
  `setVelocity` seeds handoff; `snap()` is the reduced-motion primitive. 2-D motion
  is two scalar springs, never one vector spring.
- **Motion classes** (`motion/classes.luau`): named `{dampingRatio, response}`
  registry — `container {1.0, 0.35}`, `object {1.0, 0.28}`, `reward {0.7, 0.18}`,
  `decay {1.0, 0.5}` — the shapes ratified by the Sponsor motion spec, renamed
  game-agnostically. Overshoot is earned: `reward` is the only under-damped class;
  registration validates new classes. Feel-carrying consumers cite a class, never
  inline numbers.
- **Clock** (`motion/clock.luau`): `newMotionClock(core, { now?, motionPolicy? })`.
  `clock:step(dt)` advances every active motion and commits all output writes in
  **one core transaction per frame** (one flush, cheap frames). Settled motions
  leave the active set — **rest costs zero**. The clock exposes
  `activeCount()` for leak/perf assertions.
- **MotionValue**: `clock:spring(initial, class, opts?)` returns a `Readable<number>`
  (a backing signal) plus `setTarget(number | () -> number)`, `setVelocity`,
  `onSettle`, `stop`. A **function target is re-read every step** — live-target
  chase is the default capability, not a special case (flights land on moving rows).
- **Arrival** (`motion/chase.luau`): pairs X/Y springs against a live target with a
  **perceptual arrival radius (default 4 px)**; settle is the fallback when the
  target vanished. Arrival fires the semantic `arrive`/`land` event on the frame the
  radius is crossed (the settle epsilon trails perceived landing by ~0.7 s — measured
  in the legacy implementation).
- **Timeline** (`motion/timeline.luau`): ordered beats on the clock
  (`{ at, run }`), `interrupt()` (stop, run each remaining beat's declared
  `terminal` so no half-painted state), `skip()` (jump to end state). Deterministic
  under the fake clock.
- **Reduced motion**: the clock consults `motionPolicy`. Under `reduced`, class
  resolution substitutes the declared RM form — instant placement (`snap`) or a
  short fade — and **timelines still fire every beat** with zeroed durations.
  Information parity is an invariant of the authority, not a caller's courtesy:
  the same semantic events fire in both modes.
- Momentum projection (flick-to-detent) is an explicit **non-goal** this stage: the
  ratified Sponsor spec rejected it for dense moving target lists; no consumer
  exists (responsibility ledger RG-9).

## Decision 2 — motion writes ride the existing presentation authority, per node

The authority manifest already declares `transform` and `transparency` as
**presentation** properties. Step 5 makes them real per-node:

- `controller.setPresentationTransform(path, { x, y, scale?, rotation? })` and
  `controller.setPresentationTransparency(path, alpha)` — the renderer's only
  motion write sites, `authority.assertWrite(..., "presentation")` enforced.
- `screen_target` implements them: offset composes onto the solver's last rect
  (re-applied on `setRect`), `scale` materializes a transient `FacetMotionScale`
  `UIScale` (declared bespoke instance family), `rotation` maps to
  `GuiObject.Rotation` (paint-only in Roblox). Presentation transparency is
  supported on nodes declared `canvasGroup = true` — the node itself
  materializes as a `CanvasGroup` and the fade drives `GroupTransparency`, which no
  sheet rule owns, so native paint ownership is never contested; undeclared nodes
  reject the write with an authoring error naming the fix. The declaration lives on
  `UI.Box` (fade one plate) **and on `UI.ZStack`** (fade a SUBTREE): the group's
  whole value is that it is its descendants' real instance parent, and `Box` is a
  leaf with no descendants — every fading structural transition, toast and modal
  needs the container form (amended during Decision 3's implementation; the
  renderer's `createOpts` branch and the adapter's `create` were already
  class-agnostic, so this is a schema completion rather than a new mechanism). (Supersedes this ADR's
  earlier transient-wrapper sketch: the client instance tree is flat, so wrapping
  in place would re-parent mounted instances and break handle paths. For the same
  flatness reason the transform offset **accumulates down the solved subtree**,
  stopping at real instance parents that already carry their children — cached per
  handle so a 60 Hz motion costs its subtree, not the tree.)
  This also **fixes SF-M9**: the keyboard keep-visible root shift finally lands on
  device, and `FakeTarget` mirrors the composition rule so the fake and live
  adapters cannot diverge silently again (a conformance test pins the mirrored
  handler list).
- Motion **never** writes solver geometry (no `Size`, no layout re-solve per frame)
  and never writes a native-sheet-owned property. Layout-affecting animation
  (collapsing a stack slot) is out of scope and documented as such.

## Decision 3 — structural transitions are a mount-layer retire model

`mount.luau` gains an optional `transitions` collaborator (supplied by the
renderer/presenter layer, scripted in headless tests):

- On structural removal (`When` off, `ForEach` key removed, surface dismissed) a
  subtree with a declared transition **retires** instead of disposing: it stays in
  the children array (its layout slot holds), turns non-interactive, the coordinator
  drives the exit motion, and disposal + the `structure` dirty push happen at exit
  complete — bounded by a **hard cap** so a wedged motion can never leak a tree.
- **Re-entry mid-exit reuses the retiring subtree** (same mounted identity, same
  instances): the retire cancels and the enter motion runs from the current
  presentation values — smooth reversal falls out of the model instead of being a
  special case.
- Enter transitions seed presentation values (transparency/offset/scale) at mount
  and animate to rest through the same coordinator.
- Declaration: `UI.When { transition = { enter, exit, class? } }`, same on
  `ForEach`, `PresentOpts.transition`, and toasts. Vocabulary: `fade`,
  `slide-up/down/left/right`, `materialize` (scale 0.96→1 + fade, per the Apple
  skill); enter/exit default to symmetric forms. RM: exit = instant or short fade;
  never a dropped beat.
- Exiting stack items hold their slot until removal (no layout morph); overlay/
  ZStack/Anchor hosts (toasts, captions, ghosts) reflow nothing — the recommended
  authoring pattern for slide-outs.

## Decision 4 — toasts are a presenter surface kind with a pure scheduler

- `presenter.presentToast(blueprint, opts)`: an **input-transparent**, self-retiring
  surface above base surfaces (below critical), stacked, never focus-trapping, never
  touching the responder chain or `SelectedObject`.
- A pure `toast_schedule` model owns priority ordering, a max-queue cap, per-toast
  minimum dwell (read floor), duration, and same-key supersede — fully headless-
  testable; the presenter is a thin driver. RM substitutes static presentation with
  identical scheduling (information parity).

## Decision 5 — drag/drop becomes a public blueprint contract; the list unifies

- `UI.draggable(bp, { payload, … })` and `UI.dropTarget(bp, { accepts, onDrop,
  onEnter, onLeave })` wire the existing pure `drag_session` (payload, legality,
  exactly-once enter/leave, predicted verdict, cancel, retarget) to acquisition:
  `UIDragDetector` where available, the ADR-0008 Grip capture as fallback — one
  policy path. Legality stays a game-supplied predicate; reasons flow back through
  the reject event.
- **Promotion tokens**: shared per-input-class thresholds (mouse 6 px, touch 14 px)
  in one token module; release under threshold stays a tap. Table's magic `6`
  migrates to the token.
- **Velocity tracker** (`input/drag_velocity.luau`): rolling time-windowed samples
  (0.1 s), first-vs-last estimate, read at release before state reset, seeded into
  the settle motion; non-gestural cancels seed zero through the same path.
- **Edge autoscroll** (`input/autoscroll.luau`): pure model — pointer-point band
  membership (40 px landscape / 44 px portrait defaults), 300 ms same-band dwell
  (jitter inside the band accrues; crossing/leaving resets), penetration-linear
  speed 100→500 px/s, 150 ms quad ease-out start ramp, 80 ms exit decay, canvas-end
  clamp that stays armed, permanently inert on short content. The host re-runs the
  drop hit-test **every frame immediately after the scroll write** while active.
  Wired to the native scroll host via `controller.scrollTo`; all numbers are
  overridable options within the ratified ranges.
- **Non-pointer paradigm**: arm→navigate→commit/cancel drives the **same session**
  (grab-mode precedent from Table), skipping ineligible targets via the focus-skip
  predicate. No second legality path exists.
- **Unified collection**: `VirtualList` gains `selection`/`selectedKey`,
  `reorderable`/`onReorder`, drop-surface integration, autoscroll, and a
  `navigateIntercept` grab-mode — the racer-list shape in one construct. `Table`
  keeps its own richer column feature set; folding the two is Step 5.5 material if
  the cleanup gate judges it waste.
- **Focus-skip predicate**: `focus_graph` accepts a per-node `focusable` predicate
  evaluated at navigation time, with an **active-interaction exemption** — the node
  currently targeted by a live session never loses focusability mid-gesture.

## Decision 6 — authored paint escapes, each with declared authority

- **Continuous color**: a `tint` prop (binding authority) on `Box`/`Text`/`Image`/
  `Path` accepting `{ r, g, b }` (0–1) or `"#rrggbb"`, for values a finite selector
  cannot express (hue identity, energy washes). Two value forms: role-blend
  `{ role, blend, from? }` (themable — blends from the class's identity paint, or
  a named `from` role, toward the target role) and `{ direct }` (declared
  theming-exempt escape). A node binding `tint` **claims** the engine property
  from the native sheet: the claim is recorded on the handle and published as the
  `Facet_PaintClaims` instance attribute the scenario dump reports, so defeat
  detection audits the hand-off instead of tripping on it. Claims do **not**
  strip the node's tags (a surface tag also carries corner/stroke/state chrome
  the author never surrendered — the explicit write already wins on exactly the
  claimed property, and the claim record is the audit trail). Finite-state color
  stays tags + rules (ADR-0018); the linter/docs state the boundary.
- **Image props**: `scaleMode` (`fit`/`fill`/`crop`/`stretch`) joins `tint` on
  authored `Image` (slice stays theme-owned chrome).
- **`UI.stroke(bp, { thickness, color?, transparency? })`**: reactive bespoke
  `UIStroke` (precedent: `UI.corners`/`UI.shadow` sanctioned overrides), coexisting
  with theme chrome strokes under the existing bespoke-instance rules.
- **`zIndex` override**: deterministic paint-order override **within the parent's
  stacking scope** — `walkZ` orders siblings by `(zIndex or 0, tree order)`.
  Cross-surface lifting stays structural (overlay layers), not numeric.
- **Fractional anchors + markers**: `Anchor` child offsets accept
  `{ scale, offset }`; high-frequency marker layers (minimap dots) ride keyed
  `ForEach` + presentation transforms so a dot update costs a presentation write,
  not a re-solve.

## Decision 7 — one semantic feedback seam

`src/present/feedback.luau`: a per-presenter event bus. Controls, drag sessions,
motion arrivals, and toasts emit named events (`activate`, `select`, `commit`,
`land`, `reject`, `dismiss`, `arrive`, `celebrate`) with source path and optional
game-supplied reason/context, on their causal frames. `presenterHandle.onFeedback(fn)`
subscribes. Facet plays nothing — haptics, sound, and their policies stay game-side
(corrections §13).

## Decision 8 — async-avatar completeness stays in the provider/control layer

`newAsyncImage`/`newResourceProvider` gain: bounded retry (`retry = { count, delay }`,
session give-up), a `preload(keys)` seam for declared imminent identity sets
(logical-cancel rules unchanged: releasing prevents unstarted work, ignores stale
completions), and a dim treatment via the new `tint`. Failure remains a silent,
presentable placeholder — never a spinner or broken-image glyph.

## Consequences

- The Sponsor gallery scenarios (`sponsor_*` in the shared registry) can express
  every framework-owned ledger row through public API with zero game policy.
- The keyboard keep-visible defect class (fake adapter records what the live
  adapter ignores) gets a pinned conformance check; the lesson lands in
  `docs/lessons/`.
- New public exports: `Facet.motion` (classes/clock/springs/chase/timeline),
  `UI.draggable`/`UI.dropTarget`, `presenter.presentToast`, `UI.stroke`, `tint`/
  `scaleMode`/`zIndex`/fractional offsets, `onFeedback`, AsyncImage retry/preload.
  All documented in `docs/reference/api.md` with authority notes.
- Physical rows (touch drag feel, real gamepad drag, low-end perf, motion feel)
  remain external gates in the review packet.
