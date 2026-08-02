# ADR-0009: BillboardTarget behind the RenderTargetAdapter seam

- **Status:** Accepted (2026-07-19, director Part-2 workstream 3). Relationship to ADR-0003: ADR-0003 deferred the (SurfaceGui-shaped) WorldTarget behind the §17 Phase 5 expansion gate. The BILLBOARD case ships here under a direct director mandate naming the use case (the gate's activation condition); the SurfaceGui WorldTarget itself remains deferred behind the Phase 5 gate untouched.
- **Use case:** world-anchored UI — racer nameplates, kart callouts, track markers — rendered through the SAME blueprint/solver/style pipeline as screens, so world UI and screen UI cannot drift visually or behaviorally.

## Decision — a root swap, not a second renderer

`src/client/billboard_target.luau :: billboard_target.new({ parent, adornee, canvas, studsOffset?, alwaysOnTop?, maxDistance?, style? })` returns a RenderTargetAdapter by calling `screen_target.new` with a **rootFactory** — the only ScreenGui-specific piece of ScreenTarget was root creation; everything below the root (flat instance rendering, style application, interactive states, binding writes, deterministic z-order) is target-agnostic and shared, so the targets track each other by construction. The root pins `ZIndexBehavior = Sibling` (Instance.new LayerCollectors keep the legacy Global behavior, under which nested control internals sort behind their opaque parents — verifier F1).

**Deliberately NOT shared: pointer capture.** The shared drag math compares screen-space `InputChanged` positions (plus the ScreenGui inset correction) against solver rects; a billboard's rects live in its own camera-projected canvas space, so capture would be silently wrong. `billboard_target.new` removes `setPointerHandlers` from the adapter — the renderer degrades honestly (no grip/drag wiring; taps/Activated still work). Canvas-space pointer mapping is a future ADR when a consumer needs draggable billboard UI.

**Adapter lifetime invariant:** one adapter per root — `instancesByPath` and the capture/cursor state are adapter-scoped, so an adapter must never host two roots. `billboard_target.new` mints a fresh adapter per billboard (N nameplates = N adapters).

The seam itself is now a checked contract: `src/render/target_contract.luau` names REQUIRED and OPTIONAL adapter methods; the FakeTarget passes it headless (`tests/render_target_contract.spec.luau`), engine adapters are checked at runtime in their Studio drives.

## Platform truths encoded (research 2026-07-19)

1. **Pixel canvas is offset-Size ONLY** — scale units mean studs on billboards. `canvas = {w, h}` fixes `Size = UDim2.fromOffset(w, h)` at construction; the solver's `viewportRect` is set to exactly that canvas (`billboard_target.canvasRect`).
2. **Input requires PlayerGui-parent + `Adornee` + `Active = true`** — part-parented billboards drop input silently. `new()` takes parent and adornee explicitly; display-only billboards may parent elsewhere.
3. **`ClipsDescendants` defaults true on billboards today** (and `LightInfluence` defaults 0) — the explicit writes are default-PINS, not behavior changes: they keep the contract stable if platform defaults ever move.
4. **No cross-billboard ZIndex** — engine depth orders billboards against each other; in-canvas z-order still applies (the ADR-0008 `setZOrder` walk).
5. Gamepad selection into billboards is UNCONFIRMED platform-wide — rider; do not design console-critical interactions onto billboards yet.

## Alternatives rejected

- **A parallel BillboardRenderer**: guaranteed drift with ScreenTarget styling/interaction; rejected on maintenance grounds.
- **SurfaceGui target**: different anchoring/canvas semantics; no named consumer; deferred per ADR-0003 discipline.
- **Scale-sized billboards (studs canvas)**: text metrics and the solver are pixel-based; studs canvases would need a second measurement model.

## Conformance / gate

`tests/render_target_contract.spec.luau` (contract + billboard-shaped canvas renders and updates with prop+rect-only writes); Studio drive `artifacts/studio/part2-billboard.json` (instance half: offset Size, Active, ClipsDescendants, Adornee, PlayerGui parenting, child rects, runtime contract check); gate check `ws3-billboard-target`.

## Measured cost

`bench/scenarios.luau` `billboard-nameplate-storm` — a signal storm (50 coalescing sets) + one frame refresh on a 300×96 canvas per iteration, over the shared headless pipeline (FakeTarget). This is a PROXY: billboard_target adds no per-frame code beyond that pipeline, so the headless number bounds the framework cost; engine-side BillboardGui paint/TextService cost is not captured here (device passes own that). p50 ≈ 0.03ms per canvas-frame headless (artifacts/bench.json).

## Riders

- Gamepad-selection-into-billboards unconfirmed (platform).
- Billboard-vs-billboard paint order is engine depth — if a consumer needs forced ordering (e.g. focused nameplate always on top), AlwaysOnTop or adornee-distance tricks are the only levers; document per consumer.
- No presenter/input-context wiring ships with the target itself; interactive billboards compose the existing presenter seam when a consumer needs it.
- Live billboard CLICK delivery (PlayerGui+Adornee+Active topology) is doc-corroborated and the Activated path is the shared one live-verified on screens, but a live billboard click itself is unverified (input channel wedged this session) — one manual tap when convenient.
- Pointer capture on billboards intentionally absent (see Decision) — future canvas-space mapping ADR.
