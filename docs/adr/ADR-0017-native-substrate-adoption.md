# ADR-0017 — Roblox-native substrate adoption (roadmap Step 1)

**Date:** 2026-07-23 · **Status:** Accepted (evidence-gated per
`artifacts/native-substrate/acceptance-ledger.md`)
**Governing docs:** `docs/plans/roblox-native-audit-corrections.md` (wins over older
text) → `docs/plans/roblox-native-primitives.md` → the feasibility artifacts under
`artifacts/native-substrate/feasibility/`.

The product rule: Facet keeps deterministic, headlessly-testable decisions; the
engine owns mechanisms it already ships, at the adapter edge, behind the existing
capability seam with a fallback that is exercised separately.

## Decisions

### 1. Native `ScrollingFrame` is the scroll/clip host (NS-A2)

`UI.ScrollView` mounts as a `ScrollingFrame` (`CLASS_TO_INSTANCE`), always a clip
host (`clipChildren` defaults true in the blueprint). The solver keeps owning
content geometry; the renderer maps solved `contentSize` + the node's own padding to
`CanvasSize` via the optional adapter seam `setScrollRegion`; the engine owns the
live offset (wheel/touch/momentum/elastic/bars). Programmatic scrolling is
`controller.scrollTo`; engine offsets are observable via `controller.observeScroll`
(windowing consumes this). Fallback: an adapter without the seam (or with
`forceScrollFallback = true` — billboards, A/B evidence runs) renders a plain
`Frame` clip host: geometry identical, no user scrolling, `scrollTo` a safe no-op.
Billboard targets keep the fallback until a live billboard drive proves canvas
coordinate mapping.

Evidence: spike `m1-scroll-host.json`/`m2-canvas-window.json` (clip parity,
600k-px canvas, clamping); live slice `a2-scroll-host.json` (real wheel moved a
running Facet list's canvas; fallback run separately); headless
`tests/native_scroll.spec.luau`.

### 2. `Path2D` backs the new `UI.Path` leaf (NS-A7)

Stroked rings/arcs/needles use the engine's `Path2D` inside a transparent holder
frame. The framework owns the SHAPE MATH pure (`src/controls/path_shapes.luau`,
exact circular-arc bezier handles, normalized unit-box points, headlessly tested);
the adapter scales points into the solved rect and re-scales on rect changes.
`points` is reactive and paint-only (a progress ring never re-solves layout).
Stroke color rides the style role hint. Measured engine limits encoded: 100 control
points max; stroke-only (no fill); **no `Transparency` property** (the docs-grounding
disagreement, confirmed live).

Evidence: spike `m5-path2d.json` + captures; `tests/path.spec.luau`; live slice
`a7-path.json` (scenario `path_ring`).

### 3. `UIPageLayout` is REJECTED for the flat renderer's TabView (NS-A8)

Measured (spike `m6-pagelayout.json`): parenting a `UIPageLayout` immediately
repositions EVERY sibling child to full-container page slots and **silently defeats
subsequent explicit `Position` writes** — the same authority failure class as
`AutomaticSize` (audit §3) and StyleRule-vs-explicit-write. That is incompatible
with solver-owned rects in the flat model. Its page mechanics do work (JumpToIndex,
PageEnter/Leave/Stopped traced), so a FUTURE isolated page host — a dedicated
container whose children the solver deliberately does not position, mirroring the
clip-host nesting break — may revisit this with its own spike. Until then, paged
TabView (when built) uses solver-owned page slots plus the choreography model.

### 4. Safe-area facts come from `GuiService:GetInsetArea` with one authority (NS-A1)

The adapter reads four-edge `CoreUISafeInsets` AND `DeviceSafeInsets` (converting
the inset-subtracted Rect to window-space distances), populating the previously
producer-less `deviceSafeInsets` fact. `rootPolicy = "deviceSafeContent"` composes
per-edge `max(core, device)`; the default `coreSafeContent` is unchanged. Exactly
one inset authority applies: env facts feed the solver; the `ScreenGui` renders
`IgnoreGuiInset = true`. The synthetic `phoneNotchLandscape` preview profile
exercises the notch path headlessly and in Studio (the emulator camera pre-excludes
real notches); hardware values remain a physical review row.

Evidence: spike `m8-safe-area.json`; live slice `a1-safe-area.json`; renderer/
preview specs.

### 5. Engine selection policy (NS-A11/NS-A12) — measured constraints

Spike `m9-selection-bridge.json` measured: selecting a `Selectable=false` object is
NOT passive (engine warns and reassigns selection elsewhere); a selected object's
`GuiState` becomes `Hover`; selection is NOT auto-cleared when scrolled offscreen
programmatically (docs said it resets — measured otherwise); selecting an offscreen
object inside a `ScrollingFrame` NATIVELY AUTOSCROLLS the canvas. Passive/gameplay
targets therefore keep `GuiService.SelectedObject = nil` (adapter sets
`Selectable = false` on scroll hosts; scenarios assert nil). The modal-only bridge
is opt-in, reversible, must mark its mirrored instance `Selectable = true`, must
clear on responder release, and stays non-contract until the physical-gamepad row
(NS-P1) closes.

### 6. Resource transport honesty (NS-A13)

`ContentProvider:PreloadAsync` yields and reports per-asset `AssetFetchStatus`
(measured: Success/Failure fidelity, 298 ms batch). There is no cancellation API;
`ImageLabel.LoadingImageFailed` DOES NOT EXIST (measured; use PreloadAsync status +
`GetAssetFetchStatus`/`GetAssetFetchStatusChangedSignal`). The provider's release
semantics stay logical: stale completion ignored, queued-unstarted work skipped —
never "the in-flight fetch stopped".

## Consequences

- Three hand-rolled scroll implementations converge on one native substrate
  (Table/VirtualList re-point in this stage's Phase 3).
- The billboard target intentionally lags on native scroll until proven.
- No headless assertion moved into the engine; new engine behavior is covered by
  the scenario surface (`examples/gallery/scenarios/`) + ledger evidence.
