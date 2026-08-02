# authoring-adaptive-ui — summary

**Roadmap Step 3 · 2026-07-24 · gate `authoring-adaptive-ui` → PENDING (17 PASS, 2 PENDING;
no release-blocking check open)**

**Outcome: every construct in Milestones 0, A and B is delivered. The live five-view
matrix, the live orientation change, both native-input halves, the intentional-failure
proof, the write-once demonstration and the fresh-context review are all closed. Two
PENDING rows remain and neither is release-blocking: one preferred-text evidence sweep,
and the irreducible physical/human gates. Per contract §10: _automation complete;
release evidence pending._**

## Verified (re-run for this summary)

| | |
|---|---|
| Library suite | **672 → 919** green (`./tools/test.sh 919`) |
| Drift checkers | `check_prop_parity` PASS (22 classes, 308 properties, 338 typed fields) · `check_registration` PASS (14 controls, 64 exports, 13 interactive controls proving four-input) |
| Prior gates | **11/11 PASS** |
| Game suite | RascalRally **2404** green, zero game-code edits |
| Fresh-context review | **run** — verdict `ACCEPT_WITH_FINDINGS`, 21 findings, all fixed or corrected |

## What landed

- **Milestone 0** — strict authoring. One schema is the single source of truth;
  construction rejects unknown props (with suggestions), wrong types, bare numbers where
  a dimension belongs, unknown enum values, Signals on mount-time-only props, missing
  required props and children on leaves. 19 exported spec types, complete conformance
  registration, version 0.5.0.
- **Milestone A** — `ScrollView` horizontal axis + engine-read offset +
  `scrollToVisible` as one shared keep-visible substrate; `AdaptiveStack`,
  `ViewThatFits`, `LuauUI.adaptive`; `Grid` fill, `Spacer` default, seven layout
  modifiers, axis-aware `Divider`.
- **Milestone B** — `Button` completed (content, roles, enforced hit floor, working
  disabled); `Stepper` + `Slider` over one shared value model, the Slider's live drag on
  `UIDragDetector` with the Grip capture path as the mandated fallback; `ProgressView`,
  `Label`, `Picker`, `DisclosureGroup`; PopupButton rows inheriting the floor.

## Live evidence (`matrix/`)

All five view rows PASS with presets **resolved at runtime** from the 42-entry catalog.
The **ten-foot density floor fired** (1920 px → `regular`, not `wide`). A live
portrait→landscape change preserved state *and* focus while the axis and Picker
presentation both flipped. A real injected `MouseButton1` produced the full chain: raw
event → Activate → focus → value 8→9 → geometry → capture. The intentional-failure
proof (D-6) shows all three load-bearing assertions reject a broken fixture.

**Boundary, stated in the artifact:** device *selection* and `VirtualInput`'s send
methods are absent at `execute_luau`'s security level, so each preset's *facts* were
driven through the verification surface's declared `setEnv` seam while the engine window
kept its own size. The console capture is cropped by that; its geometry trace is the
evidence.

## Fifteen defects this work found

1. Reactive `surface`/`role`/`shadow`/`corners` scheduled paint the adapter dropped.
2. Reactive `active` never updated after mount.
3. Unrecognised enum values painted nothing — which had left **the PopupButton's floating
   panel and the word-game results modal with no background at all**.
4. `Grid` rendered at zero width (found in a live capture).
5. Horizontal `ScrollView` painted a column and reported an unscrollable canvas.
6. `Grip` — focusable and pointer-handling — was invisible to the four-input rule.
7. `Text.color` / `Text.font` were declared, documented, and never painted.
8. Layout modifiers bypassed validation entirely (`withProps` did not check).
9. **`enabled = false` disabled nothing but paint** — a disabled control stayed
   focusable and still activated on tap, Return and ButtonA.
10. A hidden `ViewThatFits` candidate **still painted** (zero size is not invisibility).
11. **The Slider was invisible** — its fill and thumb were never in the blueprint.

12. The destructive fill lost the sheet cascade to `Control fill` — white text on a
    neutral button.
13. **`UI.aspectRatio` produced zero height** against a fill sibling — a 16:9 media box
    measured 592×0. The `aspect` dim was an accepted-and-ignored declaration.
14. **`UI.overlay` collapsed its base** — a badged grid tile rendered 12 px wide, the
    width of its badge.
15. Plus the three the fresh-context verifier found (below), each inside a row already
    marked PASS.

## What the fresh-context verifier caught (all fixed)

Three MAJOR code defects, each sitting **inside a row already marked PASS** and each
invisible to the suite:

- **V12** the consumer `opts.onActivate` override was dispatched *before* the disabled
  gate — so B-BTN4's headline fix did not hold on the gallery's own integration path.
- **V11** the hit expander used raw window space while every other instance is re-based
  by its clip host — inside a `ScrollView` the invisible activation surface landed off by
  the host origin.
- **V10** `structuralSync` leaked `lastVisible`/`lastHitRects` across a path remount,
  reopening the "losing candidate paints" defect and silently dropping expanders.

Also fixed: **V13** a disabled Slider stayed focusable; **V14** roles had no hover/press
rules, so hovering a destructive button repainted it neutral. Every documentation finding
(V1–V9, V15–V19) is corrected, including a ledger that contradicted itself, five rows
whose PASS overstated their evidence level, and a "SLIDER IS NOT STARTED" note that was
false when written.

## Closed since the first report

- **`A-SV1` live geometry** — real host geometry (a 928 px-wide canvas in a 280 px band),
  keep-visible moving the far row *into* the band, and a real injected **wheel** moving
  `CanvasPosition` 0→300 with descendants clipped. The engine-owned half.
- **`D-4`'s keyboard half** — three real key events drove two Activates on the focused
  control (volume 6→4) with the full chain. Closed the verifier's V20.
- **`D-2`/`D-3` captures** — all five view rows now carry one.
- **`A-SV2`** — delivered, but not as worded: `scrollToVisible` reads a *solved rect*, and
  a virtualized or culled row has none, so the controls were never duplicating the
  substrate. The **clamp** was duplicated three times; it is now `solver.keepVisibleOffset`.
- **`B-DSP3`** — the presentation now adapts (menu / inline / sheet) from option count,
  space class and live touch, with the transient-surface machinery proven untouched.
- **`A-AL4`/`A-LV4`** — one tree now carries both a settings surface and a genuinely dense
  HUD, and every recipe shape is fixtured with no manual pixel positioning.

## Outstanding (neither is release-blocking)

- **Preferred-text sweep.** The enlarged-text *compression result* for the recipe shapes
  is undefined, and the three surfaces added last have geometry evidence but no capture —
  the engine window returned to `1×1` before captures could be taken.
- **`P1`–`P5`** physical and human rows remain `PENDING_PHYSICAL` / `PENDING_HUMAN`.

## Files

Ledger `acceptance-ledger.md` · handback `HANDBACK.md` · review packet
`review-packet.md` · instrument log `environment-log.md` · verifier
`verifier-phase-gate.json` · gate `gate.json` · `game-suite.txt`, `prior-gates.txt`

Evidence: `m0-a1-unknown-props.json`, `m0-a4-dead-props.json`, `m0-a2-a7.json`,
`a-lv1-grid-spacer.json`, `a-sv1-scrollview.json`, `a-al2-adaptive.json`,
`a-lv2-modifiers.json`, `b-btn-button.json`, `b-val-value-controls.json`,
`b-dsp-display-controls.json`, and `matrix/{five-view-matrix,orientation-change,native-input,intentional-failure}.json`

New lessons: `docs/lessons/enum-props-accept-any-string.md`, and the `open -a` recovery
added to `docs/lessons/studio-viewport-1x1-instrument-trap.md`
