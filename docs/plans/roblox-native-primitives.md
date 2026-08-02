# Plan: leaning on Roblox's built-in UI primitives in LuauUI

> **2026-07-22 correction:** Read
> [`roblox-native-audit-corrections.md`](roblox-native-audit-corrections.md) first.
> It adds native drag detection, touch gesture events, `Path2D`, and
> `UIPageLayout`; corrects safe-area, text-scaling, selection, and preload
> assumptions; and governs wherever this older audit conflicts with it.

- **Status:** ADOPTION IN PROGRESS (2026-07-23, gate `native-substrate`). The
  Step-1 build implemented the corrected recommendations; per-row evidence lives in
  `artifacts/native-substrate/acceptance-ledger.md` (+ `feasibility/` spikes) and the
  decisions in `docs/adr/ADR-0017-native-substrate-adoption.md`. Landed 2026-07-23:
  §4 native `ScrollingFrame` host (scenario `scroll_host`; fallback separately),
  §6 Table/VirtualList re-point (native canvas), §8 four-edge `GetInsetArea` facts +
  `deviceSafeContent` (scenario `safe_area`), §5 measure/paint seam split + engine
  calibration (scenario `preferred_text`; the engine paints the player preference —
  LuauUI no longer multiplies it into TextSize), §7 modal-only selection bridge
  (opt-in `engineSelectionBridge`; passive surfaces stay `SelectedObject=nil`;
  physical-pad row pending), §9 `PreloadAsync` transport + `AsyncImage` (scenario
  `async_images`; stale-rejection only, never in-flight cancellation), corrections
  §1 `UIDragDetector` capability (CustomOffset keeps Position authority; spike
  m3), §2 native touch normalization seam (firing pending physical touch), §3
  `UI.Path`/Path2D (scenario `path_ring`; 100-point limit, no Transparency), §4-of-
  corrections `UIPageLayout` REJECTED with measured authority-conflict evidence
  (ADR-0017 §3). Measured engine truths that CORRECT this document's text: GuiState
  idle value is `Idle` (not `None`, §0); `ImageLabel.LoadingImageFailed` does not
  exist (§9 — use PreloadAsync status / `GetAssetFetchStatus*`); selection is NOT
  auto-cleared when scrolled offscreen programmatically and selecting an offscreen
  object natively autoscrolls its ScrollingFrame (§7; spike m9).
- **Author brief:** the game director has ruled that **LuauUI is a Roblox-only
  framework** and that engine-agnosticism is no longer a design goal. LuauUI was
  originally built with a discipline that kept its core, layout, rendering, focus,
  and environment code free of Roblox APIs, touching the engine only through thin
  adapters in `src/client/`. This document asks: now that portability is off the
  table, **what hand-rolled machinery in LuauUI duplicates something Roblox already
  ships, and where should we hand that work to the engine?**
- **The one constraint that survives the ruling:** *headless testability* (defined
  below). It is load-bearing and non-negotiable. Every recommendation is weighed
  against it explicitly.
- **Scope note — read this first.** Styling (colour, surfaces, corners, strokes,
  shadows) and **state-driven motion via stylesheets** are covered by a separate,
  already-accepted plan: `docs/plans/roblox-native-stylesheets.md` (Revision 2).
  That plan owns the decision to hand paint and hover/press/selection animation to
  native `StyleSheet`/`StyleRule`/Styling-Transitions. **This document does not
  revisit any of that.** Its scope is everything else: layout, rendering,
  scrolling and clipping, text measurement, focus and selection, safe-area and
  viewport facts, images and async loading, non-style animation, and render
  targets.

---

## 0. Terms a reader outside this project needs

This plan is written for a competent engineer who has not worked inside LuauUI.
The following terms recur; each is defined once here.

- **Lune** — a standalone runtime that executes Luau (Roblox's Lua dialect) on a
  developer machine *without* a Roblox game process. It has no `game`, no
  `Instance`, no rendering. LuauUI's automated library suite (**595 tests on
  2026-07-22**) plus the game suite, its correctness gates, and its property-based
  **fuzzer** all run under Lune. Running under Lune is what makes LuauUI's
  autonomous, no-human-in-the-loop development workflow possible: an agent can
  change layout code and get a definitive pass/fail in seconds without launching
  Studio.
- **Headless / headless testability** — "headless" means "with no Roblox engine
  present." A piece of logic is *headlessly testable* if its behaviour can be
  asserted under Lune. LuauUI's rule is that everything except the client adapters
  must run headlessly. This is verified structurally: `src/core`, `src/layout`,
  `src/render`, `src/present`, and `src/env` contain **zero** `game:GetService` or
  `Instance.new` calls; only `src/client/*` touches the engine
  (`docs/plans/roblox-native-stylesheets.md` §2.6).
- **The flat renderer** — LuauUI's rendering strategy. Instead of building a nested
  tree of engine `Frame`s that mirror the UI's logical nesting, the renderer
  creates **every node as a direct child of one root container**, each positioned
  by an absolute pixel rectangle the layout solver computed
  (`src/client/screen_target.luau:548`, `instance.Parent = rootHandle.gui`). The
  engine tree is "flat" — one level deep — and nesting exists only in the solved
  geometry, not in the instance hierarchy. Paint order is assigned by an explicit
  `ZIndex` write per node (`src/render/renderer.luau:419-437`) precisely because a
  flat sibling set has no natural nesting order.
- **The layout solver** — `src/layout/solver.luau`, a pure, non-yielding, two-pass
  (measure then arrange) layout engine that takes an immutable snapshot of the UI
  tree and a viewport size and returns an absolute rectangle for every node. It
  never reads a live signal or an `Instance`. It is the *source of truth* for all
  geometry and the thing nearly every layout test asserts against.
- **The adapter / render target** — the object implementing the
  `RenderTargetAdapter` contract (`src/render/target_contract.luau`): a set of
  methods (`createRoot`, `create`, `setRect`, `setProp`, `remove`, …) the renderer
  calls to actually draw. `ScreenTarget` (`src/client/screen_target.luau`) is the
  real, engine-touching implementation; `FakeTarget` (`tests/lib/fake_target.luau`)
  is a headless one that records the same calls as data so tests can assert on them.
- **The Input Action System (IAS)** — Roblox's first-party input-binding system
  (`InputAction`/`InputBinding` instances). LuauUI wires its controls to it for
  activation and navigation. It is a *parallel* system to Roblox's gamepad UI
  selection (`GuiService.SelectedObject` + `NextSelection*`); the two were
  deliberately not driven together (ADR-0014). This distinction matters in §5.4.
- **`GuiState`** — an engine enum (`None`/`Hover`/`Press`/`NonInteractable`) that
  Roblox `GuiButton`s expose, roughly the equivalent of CSS pseudo-classes. It is
  referenced by the stylesheets plan, not this one, but appears in cross-references.
- **The authority manifest** — `src/render/authority.luau`, a table declaring
  exactly which subsystem is allowed to write each engine property (layout vs style
  vs binding vs presentation), enforced by `authority.assertWrite`. It exists
  because a Roblox spike proved the engine silently lets conflicting writers stomp
  each other. It is the map of "who owns what" that several recommendations reuse.

---

## 1. The headless-testability constraint, stated precisely

Because this constraint gates every decision, it is worth stating exactly what it
does and does not forbid, in the same terms the stylesheets plan settled on
(`roblox-native-stylesheets.md` §2.6, under the same director ruling):

- **Forbidden:** making anything the headless suite touches *depend on a live
  Roblox process* — an `Instance`, a `game:GetService` call, a yielding engine API
  like `TextService:GetTextBoundsAsync`. The moment layout, focus, or list logic
  needs the engine to produce a result, that logic can no longer be tested under
  Lune, and the fuzzer and gates go dark for it.
- **Allowed (and now encouraged):** *modelling* Roblox concepts in headless code,
  and *handing engine-only behaviour to the engine at the adapter edge*. Moving a
  behaviour into the adapter does not break headless testing of the surrounding
  logic — it just means that one behaviour is verified in Studio instead of Lune.

So "use native primitives more" is desirable **wherever the native behaviour lives
naturally at the adapter edge** (scroll physics, native selection, engine text
metrics, image decoding) and is **dangerous wherever it would pull a decision the
headless solver/graph/list currently makes into the engine** (geometry, focus
identity, windowing math). Every entry below is sorted by which side of that line
it falls on.

A useful sharpening: the current flat renderer already draws a hard boundary
between **the geometry a node has** (owned by the headless solver, written as an
explicit rect) and **the pixels a node shows** (owned by the adapter). The
recommendations that follow almost never move geometry into the engine; they move
*behaviour that the engine performs on top of geometry* — scrolling a region,
clipping overflow, animating a selection cursor, decoding an image — out of
hand-rolled Luau and into the primitive Roblox already ships.

---

## 2. Summary of recommendations

| Area | Recommendation | One-line reason |
|---|---|---|
| **2-pass layout solver** vs `UIListLayout`/`UIGridLayout`/`UIFlexLayout`/`AutomaticSize` | **Keep custom** | The solver is the headless source of truth every layout test and the fuzzer assert against; native layout objects make geometry emergent and engine-only. |
| `UIPadding`/`UICorner`/`UIAspectRatioConstraint`/`UISizeConstraint` (leaf constraints) | **Keep solver-authoritative; do not add more native constraint objects** | Padding is already double-tracked (solver + one native `UIPadding` on Buttons); adding constraint objects that feed geometry would fight the solver invisibly. |
| **Scrolling & clipping** (flat renderer) vs `ScrollingFrame` + `ClipsDescendants` | **Adopt native (hybrid): solver owns content layout, a native `ScrollingFrame` owns scroll + clip** | *The single biggest change.* Fixes the recorded "ScrollView cannot scroll or clip" gap (sponsor-parity A1) and deletes repeated hand-rolled scrolling. Roblox supplies touch momentum, elastic behavior, and scroll bars; LuauUI explicitly keeps logical focus visible for keyboard/gamepad. |
| Explicit `ZIndex` paint-order walk | **Keep, revisit opportunistically** | Cheap and deterministic; only worth reconsidering once native containers exist. |
| **Headless text measurement** (`text_metrics`) vs `TextService`/`GetTextBoundsAsync`/`AutomaticSize` | **Hybrid: keep the headless estimator as the solver's measurer; add an engine-side correction at the edge** | The solver must measure text under Lune, so the estimator stays; the engine can *refine* it (the calibration the code already promises) but must never become the sole source or measure/paint diverge. Do **not** adopt `AutomaticSize`. |
| **Logical focus graph** (`src/focus`) vs `GuiService.SelectedObject`/`Selectable`/`NextSelection*` | **Keep custom; test an opt-in modal/menu bridge only** | Gameplay and passive HUDs must not reserve controls. Native selection is allowed only while a responder owns UI input and only after gamepad proof; otherwise keep `SelectedObject=nil`. |
| **`VirtualList` windowing** vs native `ScrollingFrame` canvas + `CanvasPosition` | **Hybrid: keep windowing, back it with the native `ScrollingFrame` from the scroll decision** | Roblox has no built-in virtualization, so windowing stays; but it should ride a real canvas instead of the current `Anchor` + `offsetY` trick. |
| **Environment facts** (safe areas, viewport, notch) vs `GuiService`/`ScreenInsets` APIs | **Keep the injectable fact seam; adopt the modern inset APIs in the adapter; fill the unpopulated notch fact** | The env fact seam is required for headless tests; but the adapter reads only legacy insets and never populates `deviceSafeInsets` (notch), a real gap. |
| **Async image/resource loading** (`src/async`) vs `ContentProvider:PreloadAsync`/`rbxthumb://` | **Keep the provider state machine; ship a native transport + wire `Image` to load states** | The provider is a good engine-free state machine with no transport; Roblox ships the transport (`PreloadAsync`, thumbnail URLs) and image load/failure signals it should consume. |
| **Drag acquisition** vs raw `UI.Grip` capture | **Adopt `UIDragDetector` at the adapter edge; keep LuauUI payload/drop policy** | Roblox already owns cross-input drag motion; LuauUI should own composable drag sessions, legal targets, cancellation, fallback, and tests. |
| **Touch gestures** vs raw sample recognition | **Adopt native `GuiObject` touch events; normalize and compose them in LuauUI** | Long press, pan, pinch, rotate, swipe, and tap are native events; framework value types and arbitration remain useful. |
| **Stroked paths/arcs** vs rotated-frame constructions | **Adopt `Path2D` where it fits** | Roblox supplies a Studio-editable 2D path; keep bespoke drawing only for unsupported filled/general-canvas cases. |
| **Paged full-screen navigation** | **Evaluate `UIPageLayout` for paged `TabView`** | It owns cross-input page changes, but does not replace general view transitions or Sponsor choreography. |
| **Non-style animation choreography** (timelines, springs, value-driven motion) | **Keep a deterministic framework model when built (mostly absent today)** | Native Styling Transitions can own supported style-state changes when publishable. Timeline, spring, value, and structural choreography still need a reduced-motion-aware model plus a Roblox adapter. |
| **Render targets** (`ScreenGui`, `BillboardGui`) | **Keep; already native** | The billboard target is already a thin root-swap over the native `BillboardGui`; nothing to reclaim. |

**The single biggest proposed change** is the scrolling/clipping one (§4): replace
the flat renderer's hand-rolled scroll math with a **native `ScrollingFrame` mounted
as a clip-and-scroll host**, while the solver continues to own all content geometry.
Everything else is smaller and several items depend on that one landing first.

---

## 3. Layout: the two-pass solver vs native layout objects

### What LuauUI does today

`src/layout/solver.luau` is a complete, deterministic layout engine. `solver.solve`
(`solver.luau:505`) runs a **measure** pass (`measure`, `:218`) that computes each
node's desired size within a bound, then an **arrange** pass (`arrange`, `:284`)
that assigns absolute rectangles. It implements vertical/horizontal/z stacks, a
grid, a scroll container, an anchor container, text, box, and spacer; the dimension
algebra covers fixed / content / fill-with-weight / percent / min-max / aspect
(`:28-38`); it handles padding and per-side margins, cross-axis alignment, and emits
diagnostics for undefined combinations (e.g. percent size on an unbounded axis,
`:94-100`). Fill distribution uses largest-remainder rounding so widths sum exactly
(`:453-471`). The renderer translates the mounted graph into solver nodes
(`toLayoutNode`, `renderer.luau:44-153`) and writes the resulting rects to the
adapter (`solveAndApply`, `renderer.luau:377-414`), writing **only rects that
actually changed** (`rectsEqual`, `:155-157`).

Roblox ships parallel machinery: `UIListLayout` (auto-flow stacks with padding and
alignment), `UIGridLayout` (uniform grid), `UIFlexLayout`/`UIFlexItem` (flexbox-style
grow/shrink), `AutomaticSize` (a container sizes itself to its content), `UIPadding`,
`UIAspectRatioConstraint`, and `UISizeConstraint`.

### Recommendation: **keep the custom solver.** Do not adopt native layout objects for geometry.

This is the load-bearing "keep" of the whole document, and it is the counterweight
to the "adopt" recommendations below. The reasoning:

1. **Determinism and headless testability.** The solver produces an exact rectangle
   for every node as a plain Luau value, with no engine present. `tests/layout_v1.spec.luau`,
   `tests/layout.spec.luau`, and the property-based `tests/fuzz_layout.spec.luau`
   assert on those rectangles directly — the fuzzer has already found and pinned
   real bugs by seed (see the inline clamp comments at `solver.luau:171-173`,
   `:481-483`, `:518-519`, each citing a fuzz seed). Native layout objects compute
   geometry **inside the engine, asynchronously, after a frame**. Adopting them
   would make every node's position and size an emergent engine result that can only
   be read back in Studio via `AbsolutePosition`/`AbsoluteSize`. The 595-test suite
   is not "some tests" here — layout is the framework's spine, and this move would
   invalidate essentially all of it while removing the fuzzer's ability to run at
   all. The current baseline is 595 library tests (2026-07-22).

2. **The flat renderer depends on the solver owning geometry.** Because every node
   is a flat sibling positioned by an absolute rect, there is no nested engine tree
   for a `UIListLayout` to flow. Adopting native layout would force adopting native
   nesting too — a far larger rewrite than "swap the solver," touching the renderer,
   the z-order model, the pointer-capture model, and the clip model simultaneously.

3. **`AutomaticSize` specifically fights the model.** `AutomaticSize` means "the
   instance decides its own size from its children at runtime." The solver's entire
   contract is the opposite: the framework decides size and writes it. The two
   cannot both be authoritative for one property — the same conflict the authority
   manifest exists to prevent (`authority.luau:2-7`). `AutomaticSize` would silently
   override solved rects.

4. **The value native layout adds is small here.** `UIListLayout`'s selling points
   are auto-flow and free reordering — but LuauUI already re-solves and writes only
   changed rects incrementally, so it is not paying a re-layout cost native would
   save. There is no free lunch on the table, only a testability loss.

**One honest nuance — padding is already double-tracked, and that is fine.** The
solver subtracts padding when placing children (`sides`, `solver.luau:72-80`), *and*
the adapter puts a real `UIPadding` on Buttons to inset the text glyph
(`screen_target.luau:500-503`), with an explicit comment that "the engine text inset
must MATCH the solver's padding" (`renderer.luau:207-211`). This is not a
contradiction to fix — it is the correct division: the solver owns the *box*
geometry (headless, testable), and the engine owns *intra-instance text layout*
(which the solver deliberately does not model). The lesson generalises: native leaf
constraints are acceptable only where they operate *strictly inside a single node's
painted content* and never feed a decision the solver makes. `UIAspectRatioConstraint`
and `UISizeConstraint` fail that test — the solver already computes aspect and
min/max bands as first-class dims (`solver.luau:105-112`, `:220-258`) and other
nodes' layout depends on those results, so handing them to the engine would make
sibling geometry depend on an engine-computed size the solver can't see. **Keep
those in the solver.**

- **Headless-test impact:** none (status quo). Adopting native would be catastrophic.
- **Cross-input impact:** none.
- **Migration risk / size:** N/A (no change). Adopting would be **XL** and is rejected.

---

## 4. Scrolling and clipping — the flat renderer vs `ScrollingFrame` + `ClipsDescendants`

**This is the single most important decision in the document.**

### What LuauUI does today

The flat renderer cannot natively scroll or clip, and the codebase says so
repeatedly. There are three separate hand-rolled scroll implementations, plus a
partial clip mechanism:

1. **`UI.ScrollView` does essentially nothing.** In the solver, `kind == "scroll"`
   measures its children on the scroll axis as unbounded, sums their heights, and
   annotates `contentSize` and `overflow = "scroll"` when content exceeds the
   viewport (`solver.luau:302-320`). It applies **no offset** and performs **no
   clip**. The API doc is blunt: "It does not scroll by itself… Every consumer
   re-implements scrolling" (`docs/reference/swiftui-parity.md:360-364`). This is
   also the top gap in the sponsor-view parity analysis (gap A1,
   `docs/reference/sponsor-view-parity.md:127-135`).

2. **A partial clip mechanism exists via re-parenting.** A node whose blueprint sets
   `clipChildren = true` becomes a "clip host": the adapter sets `ClipsDescendants =
   true` on it and *re-parents* its descendants inside it, re-basing their positions
   to be relative to the host (`screen_target.luau:442-470`, `:540-549`). This is a
   deliberate, narrow break in the flat model — it is the only place descendants
   nest — and it is how the engine crops partial overflow. It provides clipping but
   not scrolling; scrolling is still the consumer's job.

3. **`Table` hand-rolls scroll** with a per-row `offsetY` arrange adjustment, a
   `scrollOffset` signal, a mouse-wheel handler, a touch-pan handler, and
   **row-granularity culling** because "the flat renderer cannot clip" — a row whose
   top crosses the body edge is "parked far off-screen"
   (`src/controls/table.luau:103-119`, and the comment there admits "Bottom overflow
   pokes past the body edge (v1 limitation)").

4. **`VirtualList` hand-rolls scroll a third time**, independently, and does not even
   use `UI.ScrollView`: it uses an `Anchor` viewport with `clipChildren`, a per-row
   `offsetY` memo `(index-1)*rowHeight - scrollTop`, its own wheel handler, and its
   own touch-pan handler (`src/controls/virtual_list.luau:8-13`, `:285-341`).

The scroll offset is applied by adding `child.offsetY` at arrange time
(`solver.luau:333-336`) — an arrange-only adjustment so a same-window scroll is
rect-writes-only. It works, but it is a manual re-implementation of what a
`ScrollingFrame` does natively, and it lacks touch momentum/inertia, elastic
overscroll bounce, scroll bars, and gamepad scrolling entirely.

Roblox ships `ScrollingFrame`: a container with a `CanvasSize` (the scrollable
content extent) and a `CanvasPosition` (the current scroll offset), with built-in
touch drag + momentum, elastic bounce, rendered scroll bars (`ScrollBarThickness`,
`ScrollBarImageColor3`), `AutomaticCanvasSize`, `ElasticBehavior`, and gamepad
scroll support when a selected object scrolls out of view.

### Recommendation: **adopt native — as a hybrid.** The solver keeps owning content geometry; a native `ScrollingFrame`, mounted as a clip-and-scroll host, owns scroll physics and clipping.

This is the cleanest possible application of the §1 principle: **geometry stays
headless; the engine performs scrolling on top of that geometry.** Concretely:

- Extend the existing clip-host mechanism (`screen_target.luau:442-470`) so a node
  whose kind is `scroll` (or whose blueprint declares a scroll region) is created as
  a **`ScrollingFrame`** rather than a `Frame`, with `ClipsDescendants` already
  implied. Its descendants parent inside it (exactly as clip hosts do today), with
  positions relative to the canvas — the re-basing code already exists (`applyRect`,
  `:459-470`).
- The **solver keeps computing the content layout** exactly as it does now,
  including `contentSize` (`solver.luau:317`). The adapter maps `contentSize` to the
  `ScrollingFrame`'s `CanvasSize` and lets the engine own the offset. Where LuauUI
  needs programmatic scroll (scroll-a-focused-row-into-view), it writes
  `CanvasPosition` instead of poking per-row `offsetY`.
- **Retire the hand-rolled scroll code** in `Table` and `VirtualList`: the
  `offsetY`-per-row trick, the row-parking cull, the three wheel handlers, and the
  three touch-pan handlers all collapse into "let the `ScrollingFrame` scroll." The
  wheel/pan/momentum/elastic/scroll-bar behaviours become free and correct.

**What this fixes:** sponsor-parity gap A1 (the racer list and results standings have
no scroll home), the "settings form taller than the viewport is a dead end" caveat
(`swiftui-parity.md:350`), the `.wheel` Picker gap (`swiftui-parity.md:226`), and the
"scrolling re-implemented per surface" redundancy (`sponsor-view-parity.md:372-374`).

**What becomes engine-only-testable, and how the plan compensates:** scroll *physics*
— momentum curves, elastic bounce, scroll-bar drag, the exact `CanvasPosition` after
a fling — become engine-owned and can only be verified in Studio. **But note what is
actually lost:** those behaviours are *not* headlessly tested today either, because
they do not exist today — the current tests assert on the hand-rolled `scrollTop`
signal and the resulting `offsetY` rects (`tests/virtualization.spec.luau`,
`tests/table.spec.luau`). Under the recommendation, the framework still owns and can
headlessly test **what content exists, its geometry, which rows are windowed, and the
programmatic scroll target** (scroll-into-view still computes a target
`CanvasPosition` in Luau). What moves to the engine is only the *interpolation
between offsets and the input-to-offset mapping*, which is exactly the kind of
engine behaviour §1 says belongs at the edge. The compensation is a small in-Studio
verification harness (see §11) that drives a wheel/touch/gamepad scroll and asserts
the canvas moved and clipped — a handful of Studio-MCP checks, not a test-suite
rewrite. The headless tests that assert *geometry and windowing* keep passing
unchanged; only the tests that assert the *manual offset arithmetic* are replaced by
"the adapter set `CanvasSize`/`CanvasPosition` correctly" conformance checks on the
fake target.

**Cross-input impact — positive, but not automatic.** Today scroll is mouse-wheel +
touch-pan only, hand-wired; gamepad scroll does not exist in the scroll primitive
(VirtualList notes it has "NO navigateIntercept," `virtual_list.luau:34`). A native
`ScrollingFrame` gives LuauUI the correct canvas and clipping mechanism, while the
presenter keeps logical focus visible by computing and writing `CanvasPosition`.
Correct gamepad scrolling must not depend on an engine `SelectedObject` mirror. An
engaged modal/menu may separately test whether a safe bridge adds native behavior,
but passive/gameplay UI keeps engine selection nil.

- **Determinism:** geometry stays deterministic; scroll interpolation becomes
  engine-timed (acceptable — it was never deterministic, it was absent).
- **Migration risk:** **Medium.** The clip-host re-parenting path already exists and
  is battle-tested, so this extends a proven mechanism rather than inventing one. The
  risk is that `Table`/`VirtualList` have subtle behaviours entangled with their
  manual offset math (e.g. VirtualList's window memo keys off `clampedTop`,
  `virtual_list.luau:112-124`); those must be re-pointed at the native canvas
  carefully, ideally one control at a time behind the existing adapter-capability
  fallback so an old code path stays available during migration.
- **Size:** **L.**

---

## 5. Text measurement — `text_metrics` vs `TextService` / `AutomaticSize`

### What LuauUI does today

`src/layout/text_metrics.luau` is a **headless, non-yielding text measurer**. It
estimates a string's wrapped width and height from an average-glyph-width fraction
(`AVG_GLYPH_FRACTION = 0.62`, `text_metrics.luau:13`), a line-height factor, and a
greedy word-wrap (`wrap`, `:41-63`), with a wider full-em fallback for unknown fonts
and CJK ranges (`:33-39`, `:70-81`). It returns a `ready`/`pending`/`failed` state
so the solver knows when a measurement is an estimate. The file's own header states
the design intent plainly: these are "screening approximations calibrated later
against Studio fixtures (UI-FID-001)… deliberately conservative (over-estimate) so
fallback layout never under-reserves," and "the engine premeasurement queue
(`TextService`) lives behind the same interface in the Roblox platform adapter, NOT
here" (`text_metrics.luau:1-7`). The solver calls it during measure
(`solver.luau:126-128`).

The adapter compensates for the estimator's imprecision by **centring** text
vertically rather than top-pinning it, with an explicit comment: "the headless
measurer deliberately over-reserves… so the engine text can be shorter than its
solved box — centering splits that error evenly" (`screen_target.luau:481-485`).

Roblox ships `TextService:GetTextBoundsAsync` (exact wrapped text bounds for a
font/size/width — but it *yields*, i.e. requires the engine and a frame), and
`TextLabel.AutomaticSize` (the label sizes itself to its text).

### Recommendation: **hybrid.** Keep the headless estimator as the solver's measurer; add an engine-side measurement *correction* at the adapter edge. Do **not** adopt `AutomaticSize`.

The tension here is real and the resolution is subtle:

- **The solver must measure text headlessly**, so the estimator cannot be removed.
  `GetTextBoundsAsync` yields and needs the engine, so it can never be the measurer
  the solver calls under Lune. This half is forced.
- **But the estimator is deliberately imprecise**, and the codebase already carries
  two workarounds for that imprecision (the conservative over-reserve and the
  centring hack). The engine can measure text exactly. The right move is the one the
  code header already anticipates (UI-FID-001): the adapter measures the real bounds
  with `GetTextBoundsAsync` and feeds a **correction** back so the estimator's
  fraction table is calibrated per font, tightening the over-reserve. This is
  "modelling refined by the engine," not "depending on the engine": the headless
  path still works standalone; the engine just makes it more accurate when present.

- **The danger to avoid: measure/paint divergence.** LuauUI has a hard-won invariant
  that the size the solver *measures* and the size the adapter *paints* must agree —
  the whole `applyTextScale` design (`renderer.luau:352-368`) and its "verifier F1:
  measure and paint must agree" comment (`renderer.luau:113-115`) exist to enforce
  it. An engine correction must therefore feed back into the **same** value the
  solver uses on the next solve (i.e. update the calibration table, then re-solve),
  never silently resize the painted label out from under the solver. That is exactly
  why **`AutomaticSize` is rejected**: it resizes the label at the engine edge with
  no path back to the solver, guaranteeing the divergence the framework works hard to
  prevent (same failure mode as `AutomaticSize` in §3).

- **Headless-test impact:** minimal. The estimator and all its tests stay. The
  calibration table becomes a data input the tests can pin; the correction path is
  adapter-only and verified in Studio.
- **Cross-input impact:** none.
- **Migration risk / size:** **S–M.** The interface seam the header promises already
  exists conceptually; the work is the async correction loop and the calibration
  feedback, plus care around the measure/paint invariant. Lower priority than scroll.

---

## 6. `VirtualList` windowing vs native `ScrollingFrame` canvas + `CanvasPosition`

### What LuauUI does today

`VirtualList` (`src/controls/virtual_list.luau`) mounts **only the visible rows plus
a small overscan buffer** ("windowing"): a `windowItems` memo computes which keyed
rows fall in view for the current `scrollTop` (`:112-124`), a keyed `ForEach` mounts
just those, and each row's vertical position is a per-row `offsetY` memo relative to
`clampedTop` (`:305-311`). The viewport is an `Anchor` with `clipChildren`
(`:285-292`) — the manual clip host from §4. This exists because Roblox has **no
built-in list virtualization**: a native `ScrollingFrame` with 10,000 rows would
instantiate 10,000 frames.

### Recommendation: **hybrid — keep the windowing, back it with the native `ScrollingFrame` from §4.**

Windowing is genuinely valuable and has no native equivalent, so it stays and stays
headlessly tested (`tests/virtualization.spec.luau`, `tests/virtual_list_input.spec.luau`).
But the *scroll mechanism underneath it* should be the native `ScrollingFrame` from
§4, not the bespoke `Anchor` + `offsetY` trick:

- Set the `ScrollingFrame`'s `CanvasSize` to the **full virtual height**
  (`totalRows * rowHeight`), so the engine renders a correctly-sized scroll bar and
  supports touch/gamepad scroll across the whole list even though only a window is
  mounted.
- Position each windowed row by its absolute canvas offset `(index-1)*rowHeight`
  (which the code already computes, `:310`) rather than relative to `scrollTop`.
- Drive the window from the engine's `CanvasPosition` (observe it) instead of a
  hand-managed `scrollTop` signal fed by hand-wired wheel/pan handlers.

This gives VirtualList real momentum, elastic bounce, a correctly-proportioned
scroll bar, and gamepad scroll — none of which it has today — while keeping the
mount-only-what's-visible behaviour that is its reason to exist.

- **Headless-test impact:** the windowing math and its tests are unchanged; what
  changes is that `scrollTop` becomes a mirror of engine `CanvasPosition` at the
  edge. The window-computation tests keep asserting "given this scroll offset, these
  keys are mounted."
- **Cross-input impact:** positive (adds gamepad + momentum scroll).
- **Migration risk / size:** **M**, and it is **downstream of §4** — do the scroll
  primitive first, then re-point VirtualList and Table at it.

---

## 7. Focus and selection — the logical focus graph vs `GuiService.SelectedObject`

### What LuauUI does today

`src/focus/focus_graph.luau` is a **logical focus model** that LuauUI owns entirely.
It maintains a stack of focus scopes (flat rings and grouped 2-D navigation with
axes, wrap policy, containment, and per-direction exits), modal focus trapping with
restore-on-pop, and nearest-surviving-neighbour recovery when a focused node
disappears (`focus_graph.luau:1-16`, `navigateDirection` `:232-266`, `remove`
`:382-409`). The file header is explicit about the relationship to the engine:
"LuauUI owns focus identity and movement; **Roblox SelectedObject/NextSelection* are
render outputs applied by the platform adapter (not here — engine-free)**"
(`focus_graph.luau:2-4`). Focus *visuals* are drawn by the adapter's `setFocusVisual`
(`screen_target.luau:856-939`) driven by the logical focus path
(`renderer.luau:519-538`).

Critically, **the "render output" the header promises is not actually wired.**
`setFocusVisual` draws a `UIStroke` ring and a ten-foot `UIScale` lift, but nothing
in the codebase writes `GuiService.SelectedObject` or sets `Selectable`/
`NextSelectionUp/Down/Left/Right`. This was a deliberate deferral: ADR-0014 declined
to drive `SelectedObject` alongside LuauUI's own graph and the Input Action System
because "`SelectedObject` and IAS are parallel systems… risks a double-drive"
(quoted in `sponsor-view-parity.md:380-385`).

Roblox ships gamepad UI selection: `GuiService.SelectedObject` (the currently
selected GUI), `GuiObject.Selectable`, and `NextSelectionUp/Down/Left/Right` for the
selection graph. These APIs participate in native navigation and highlighting. Their
interaction with IAS, offscreen scrolling, platform sound, and haptics is not a
LuauUI contract until Q3 records it without double-driving focus.

### Recommendation: **keep the custom graph; test an opt-in modal/menu bridge only.**

The correction addendum supersedes the unconditional mirror proposed below. Passive
gameplay UI, including the normal Sponsor race surface, must leave
`GuiService.SelectedObject` nil. A modal or menu may mirror logical focus only while
it owns UI input and only after Studio plus physical-gamepad verification proves
there is no IAS double drive or control theft. Native selection sounds, haptics, and
scrolling are possible benefits to measure, not acceptance assumptions.

The director's ruling explicitly asks to reassess the deferral, so here is the
reassessment:

- **The logical graph must stay.** It is headlessly tested (`tests/focus.spec.luau`,
  `tests/focus_structural.spec.luau`) and it expresses things native selection
  cannot: a four-input paradigm model (ADR-0015/0016), modal focus trapping with
  restore, grouped 2-D navigation with declared exits and containment, and
  nearest-neighbour recovery. `GuiService.SelectedObject` is a single object pointer
  with a fixed four-direction next-selection graph; it cannot represent scopes,
  traps, or paradigm-derived reachability. Handing focus *identity* to the engine
  would delete the framework's most distinctive capability and its tests.

- **Do not wire a general mirror.** `controller.setFocusPath(path)` continues to
  drive LuauUI's own focus visual and explicit scroll-to-visible command. Passive
  HUDs and gameplay screens set or leave `GuiService.SelectedObject = nil` so UI does
  not reserve controls the game needs.

- **An engaged modal/menu may opt into a narrowly scoped experiment.** Only while
  that responder owns UI input, the adapter may reflect the logical path to the
  corresponding instance. It must clear selection before the responder releases
  ownership. Leaving `Selectable` and `NextSelection*` disabled is not assumed to
  make the engine passive; Q3 must prove no self-navigation, IAS double delivery,
  offscreen clearing, or control theft on a physical gamepad.

- **Sounds, haptics, and native autoscroll are observations, not the contract.** If
  they occur safely they are optional benefits. Logical focus visibility still uses
  LuauUI's explicit keep-visible calculation so every surface works with the bridge
  off.

- **Headless-test impact:** none. The logical graph, focus visual, and keep-visible
  policy remain headlessly driven. The optional bridge is adapter-only and requires
  Studio plus physical-gamepad evidence.
- **Risk / size:** **S–M** for the experiment. The safe outcome may be “no bridge.”

---

## 8. Environment facts — safe areas, viewport, notch insets

### What LuauUI does today

`src/env/environment.luau` is an engine-free store of observable client facts
(viewport rect, safe insets, preferred input, capabilities, reduced motion, display
size, overscan) with derived policy memos (typography scale, size class, interaction
classes, distance profile). It is populated at runtime by the client adapter
`src/client/roblox_env.luau`, which is "the ONE place allowed to read
UserInputService/GuiService facts" (`roblox_env.luau:1-6`). This split is correct and
must stay: tests inject fake facts through the same `env:set` seam
(`environment.luau:156-160`) so every layout/policy behaviour is headlessly testable
across device profiles.

The adapter reads: `camera.ViewportSize` for the viewport, `GuiService:GetGuiInset()`
for core insets, `GuiService.TopbarInset` for the topbar, `GuiService.ViewportDisplaySize`
(pcall-guarded) for the console display class, and the accessibility facts
(`roblox_env.luau:17-38`, `:57-66`).

### Recommendation: **keep the fact seam; modernise which engine APIs the adapter reads; fill the unpopulated notch fact.**

The seam is right and stays. Two concrete gaps in *what the adapter reads*:

1. **The notch/safe-area fact is modelled but never populated.** `environment.luau:19`
   declares `deviceSafeInsets` (distinct from the CoreGui `coreSafeInsets`), and a
   grep confirms **it has zero producers and zero consumers** — `roblox_env.luau`
   never sets it. On phones with a notch or rounded corners, device-safe insets and
   CoreGui insets differ, and the sponsor view had to reach for raw
   `GuiService:GetGuiInset` / `TopbarInset` itself to compensate
   (`sponsor-view-parity.md:89`). The adapter should populate `deviceSafeInsets` from
   Roblox's safe-area API (`GuiService`'s screen-inset / safe-area surface), so notch
   avoidance is a first-class env fact the solver's root policy can consume.

2. **Core insets come from the legacy `GetGuiInset()`** (`roblox_env.luau:20-26`),
   which returns only top/bottom and is hardcoding `right = 0`. Roblox's newer inset
   surface (`ScreenInsets` / the `SafeAreaCompatibility` and current-inset APIs)
   reports all four edges including landscape-notch left/right. Adopting it makes the
   left/right insets real on landscape phones instead of assumed zero.

Neither change touches headless code — both are adapter reads feeding the existing
facts. The env store, its derived memos, and their tests are unchanged.

- **Headless-test impact:** none (the facts already exist; only the producer changes).
- **Cross-input / device impact:** positive (correct notch avoidance on modern phones).
- **Migration risk / size:** **S.** Standalone; do it independently.

---

## 9. Async images and resource loading — `src/async` vs `ContentProvider` / `rbxthumb://`

### What LuauUI does today

`src/async/resources.luau` is an **engine-free async-state machine**: it tracks
`ready`/`pending`/`failed` per cache key with bounded concurrency, an LRU cache
budget, request generations for stale-completion rejection, retry policy, and
scope-owned cancellation (`resources.luau:1-11`, `acquire` `:152-204`, `complete`/
`fail` `:221-283`). It deliberately owns *no transport* — "the TRANSPORT is game- or
adapter-owned" (`resources.luau:7-8`): the caller drains `pendingRequests()` and
answers with `complete`/`fail`. This is a clean, testable design and it is exercised
headlessly.

But it is not connected to anything native. `UI.Image` (`blueprint.luau:162`) maps to
an `ImageLabel` whose `Image` property is set directly (`screen_target.luau:1073-1076`)
with **no async state, no placeholder, no failure handling, and no tint**. The
provider has no shipped Roblox transport, and there is no `AsyncImage` control wiring
the two together (`sponsor-view-parity.md:196-202`, gap A9).

Roblox ships the transport the provider lacks: `ContentProvider:PreloadAsync` (batch
preload with a per-asset success/failure callback), `rbxthumb://` and
`Players:GetUserThumbnailAsync` (avatar/asset thumbnails), and the image load
signals `ImageLabel.IsLoaded` and `ImageLabel.LoadingImageFailed`.

### Recommendation: **keep the provider state machine; ship a native transport adapter and wire `Image` to native load states.**

The provider is exactly the kind of headless machinery worth keeping — it is
deterministic, tested, and transport-agnostic by design. The gap is purely at the
edge, and Roblox fills it:

- Ship a **client transport adapter** that drains `provider.pendingRequests()` and
  fulfils them with `ContentProvider:PreloadAsync` (and `GetUserThumbnailAsync` /
  `rbxthumb://` for player thumbnails), calling `provider.complete`/`fail` with the
  request generation. This is the "adapter-owned transport" the provider's header
  already anticipates.
- Add an `AsyncImage` control (or async props on `Image`) binding the provider's
  per-key `state`/`value` signals to placeholder / loaded / failure visuals, and let
  the adapter consume `ImageLabel.LoadingImageFailed` / `IsLoaded` so even
  directly-set images get honest load states.

- **Headless-test impact:** none — the provider and its tests stay; the transport is
  adapter-only and verified in Studio.
- **Cross-input impact:** none.
- **Migration risk / size:** **M.** Independent of the scroll work; schedulable on its
  own. (Note: this overlaps sponsor-parity A9; this document endorses the "keep the
  provider, add native transport" shape rather than re-deciding it.)

---

## 10. Non-style animation, and render targets — two short entries

### 10.1 Non-style animation choreography — **keep bespoke (mostly not yet built)**

The stylesheets plan owns **state-driven** motion (hover/press/selection/theme),
handing it to native Styling Transitions
(`roblox-native-stylesheets.md` §6.10). What remains in *this* document's scope is
**non-state motion**: timelines, springs, choreographed sequences, and
**value-driven** animation (a gauge needle sweeping, a bar filling a number).

The finding: **the framework ships almost none of this today.** A grep for
`TweenService`/`RunService`/`task.delay` across `src/` returns only the state-motion
tweens in `screen_target.luau` (hover/press fills, the toggle knob, the focus lift —
all owned by the stylesheets plan) and one `RunService.Heartbeat` in the Edit-mode
preview harness (`edit_preview.luau:98`). All the timeline/spring/value motion the
sponsor view needs lives in *game* code, invisible to LuauUI
(`sponsor-view-parity.md:216-238`, gap B1, rated XL).

Roblox's native offering here is `TweenService` (already used for state motion) and
nothing for springs or value-driven interpolation. So there is no native primitive to
adopt for the hard part: value-driven and spring motion have **no native equivalent**,
and also no obviously headless-safe home (interpolation is inherently time-and-frame
based). **Recommendation: no change now.** When an animation substrate is eventually
built (sponsor-parity B1), it should use `TweenService` for tween-shaped motion and a
bespoke spring integrator for spring motion, honour reduced-motion, and keep its
*scheduling/target* logic headlessly testable while the *interpolation* runs at the
edge — but designing that substrate is out of scope here and is flagged, not
specified.

### 10.2 Render targets — **keep; already native**

LuauUI's render targets are already thin wrappers over native surfaces. `ScreenTarget`
creates a native `ScreenGui` (`screen_target.luau:433-439`). `BillboardTarget`
(`src/client/billboard_target.luau`) is "a thin root swap over ScreenTarget" that
renders into a native `BillboardGui`, with the platform truths (offset-only canvas,
input requires PlayerGui-parenting + `Adornee` + `Active`, `ClipsDescendants` default)
encoded in its header. This is the correct shape — the flat renderer is
target-agnostic below the root, so new native surfaces (a `SurfaceGui` target for
in-world panels, a `ViewportFrame`-backed target) plug in as further root swaps
(`docs/extending/new-render-target.md`). **Nothing to reclaim; no change.**

---

## 11. Dependency-ordered adoption sequence

**Corrected sequence.** The detailed older phases below remain useful for their
scroll/text/resource acceptance notes, but run work in this order:

1. Studio evidence matrix from `roblox-native-audit-corrections.md`, including
   scroll/clip, `UIDragDetector`, native touch events, `Path2D`, `UIPageLayout`,
   preferred text, safe areas, modal selection, and resource status.
2. Four-edge safe-area facts with one inset authority, plus preferred-text
   measurement/paint correction if the evidence confirms double application.
3. Native `ScrollingFrame` host, then Table/VirtualList migration while keeping
   windowing pure and tested.
4. Native drag/touch adapter capabilities and pure drag-session/drop policy; prove
   Slider and Sponsor-shaped drop fixtures.
5. Native rotation/`Path2D` and the narrow `UIPageLayout` experiment.
6. Modal/menu-only selection bridge if it passes; passive/gameplay targets remain
   logical-focus-only.
7. Engine text calibration not already covered by step 2.
8. Native async image transport with logical stale rejection, not in-flight
   cancellation claims.

Each item is reversible and independently gated. Do not wait for every optional
experiment before shipping a proven earlier item.

Each phase is independently shippable, has a verification gate, and states its risk.
The ordering is driven by the fact that the scroll primitive (Phase 2) unblocks the
most downstream work.

### Phase 0 — Studio feasibility spike (no production code)
- **Scope:** answer the open questions in §12 in a throwaway Studio place via the
  Studio MCP, the same method the stylesheets plan's Phase 0 uses. The load-bearing
  ones are the `ScrollingFrame`-as-clip-host behaviour (Q1), programmatic
  `CanvasPosition` + windowing interaction (Q2), and modal-only `SelectedObject`
  bridge non-interference (Q3).
- **Gate:** every question in §12 answered with machine evidence, or explicitly
  deferred with its bespoke fallback named. No later phase starts on an unproven
  capability.
- **Risk:** a capability may not behave as assumed (e.g. the engine drives navigation
  off `SelectedObject` regardless of `Selectable`) → that sub-feature stays bespoke;
  the scroll work still proceeds.

### Phase 1 — Environment safe-area modernisation (§8)
- **Scope:** populate `deviceSafeInsets` from the native safe-area API; move core
  insets to the modern four-edge inset API. Adapter-only.
- **Gate:** a notched-phone Studio drive shows content clearing the notch on all four
  edges; headless env/policy tests unchanged and green; the fake target and its
  device-profile tests untouched.
- **Risk:** **Low.** Fully additive; smallest independent win; good warm-up.

### Phase 2 — Native `ScrollingFrame` scroll-and-clip primitive (§4) — the headline
- **Scope:** create scroll regions as native `ScrollingFrame`s (extending the
  existing clip-host re-parenting), map solver `contentSize` → `CanvasSize`, let the
  engine own the offset, and expose a programmatic scroll (`CanvasPosition`) for
  scroll-into-view. Behind the existing adapter-capability fallback so the old path
  survives during migration.
- **Gate:** an in-Studio harness (Studio MCP) drives wheel, touch-drag, and gamepad
  scroll on a real overflowing list and confirms the canvas moves, clips partial
  rows, shows a scroll bar, and carries momentum; the headless conformance test
  asserts the adapter set `CanvasSize`/`CanvasPosition` and `ClipsDescendants`
  correctly on the fake target; all geometry tests green.
- **Risk:** **Medium.** Entangled manual-offset behaviours in `Table`/`VirtualList`
  must be re-pointed carefully; mitigated by keeping the old path behind the flag and
  migrating one consumer at a time.

### Phase 3 — Re-point `Table` and `VirtualList` onto the native canvas (§4, §6)
- **Scope:** delete the hand-rolled `offsetY`/park-cull/wheel/pan code in `Table`
  (`table.luau:103-119`) and `VirtualList` (`virtual_list.luau:285-341`); drive the
  window from engine `CanvasPosition`; set `CanvasSize` to the full virtual height.
- **Gate:** windowing tests (`tests/virtualization.spec.luau`, `tests/table.spec.luau`)
  green with `scrollTop` now a mirror of `CanvasPosition`; Studio drive shows a
  10,000-row VirtualList scrolling with momentum, a correct scroll bar, and explicit
  logical-focus keep-visible; no row-park artefacts at the bottom edge (the "v1 limitation" the
  old code admitted is gone).
- **Risk:** **Medium.** Downstream of Phase 2; the window-memo re-pointing is the
  delicate part.

### Phase 4 — Modal/menu engine-selection bridge experiment (§7)
- **Scope:** keep passive/gameplay targets at `SelectedObject=nil`. In an engaged
  modal/menu only, experiment with mirroring the logical focus path while LuauUI
  remains the authority; verify no engine self-navigation or IAS double drive. Composes
  with Phase 2 for gamepad scroll-into-view.
- **Gate:** Studio and physical-gamepad drives prove the logical graph remains the
  sole mover (no double move, fight, control theft, or offscreen selection loss), and
  record whether selection sound, haptics, or native autoscroll actually occur. The
  explicit keep-visible path passes with the bridge disabled. Focus tests remain
  green and the bridge clears selection on teardown and is reversible via a flag.
- **Risk:** **Medium**, gated on Q3. Falls back to today's visuals-only focus if the
  engine won't stay passive.

### Phase 5 — Engine text-metrics calibration (§5)
- **Scope:** add the `GetTextBoundsAsync` correction loop feeding the estimator's
  calibration table (UI-FID-001), tightening the conservative over-reserve; keep the
  measure/paint invariant.
- **Gate:** Studio comparison shows tighter text boxes than the estimator alone with
  no clipping and no measure/paint divergence (verifier-F1-style check); headless
  estimator tests green with the calibration table pinned as data.
- **Risk:** **Low–Medium.** Must not break the measure/paint agreement; otherwise
  self-contained.

### Phase 6 — Native async image transport + `AsyncImage` (§9)
- **Scope:** ship the `ContentProvider`/`rbxthumb` transport draining the provider;
  add `AsyncImage` (placeholder/loaded/failure) and consume native image load
  signals.
- **Gate:** Studio drive shows an avatar list loading through the provider with
  placeholder → image, a forced-failure path showing the failure visual, and
  cancellation on scroll-away (the provider's stale-rejection working end to end);
  provider tests unchanged and green.
- **Risk:** **Low–Medium.** Independent of the scroll chain; schedulable in parallel
  after Phase 0.

*(The layout solver, §3, and render targets, §10.2, have no phase — the recommendation
there is "no change.")*

---

## 12. Open questions requiring a Studio experiment

Each carries a concrete verification step. None should be assumed; a wrong confident
answer here would mis-scope Phase 2 or Phase 4.

| # | Question | Why it matters | Verification |
|---|---|---|---|
| Q1 | When a `ScrollingFrame` is used as the clip host and descendants are re-parented into it with canvas-relative positions, does clipping + native scroll behave exactly as the current `Frame` + `ClipsDescendants` host does for the non-scroll case? | Phase 2 extends the existing clip-host mechanism; a behavioural difference would ripple into every clipped surface. | Studio place: build a clipped region both ways (Frame host vs ScrollingFrame host), overflow it, confirm identical clipping and that scroll only engages on the ScrollingFrame. |
| Q2 | Can LuauUI set `CanvasSize` to the full virtual height while only a *window* of rows is mounted, drive scroll-into-view via `CanvasPosition`, and read `CanvasPosition` back to slide the window — without the engine fighting an `AutomaticCanvasSize`? | The VirtualList re-point (Phase 3) depends on a full-height canvas over a partial row set. | Studio: a ScrollingFrame with `CanvasSize` = 10,000×rowHeight but only ~15 mounted rows; scroll via drag and via `CanvasPosition`; confirm the bar is proportioned to 10,000 rows and the window can be repositioned from `CanvasPosition`. |
| Q3 | Can an engaged modal/menu mirror logical focus to engine selection without IAS double drive, engine-cleared offscreen selection, or control theft? | Decides whether an opt-in bridge is safe. Passive/gameplay targets stay visuals-only regardless. | Studio and physical gamepad: exercise focus, offscreen rows, scrolling, teardown, and return to gameplay. Treat sounds/haptics/autoscroll as observed results, not promised behavior. |
| Q4 | Does the native safe-area / four-edge inset API report distinct left/right insets on a landscape notched phone (where `GetGuiInset` assumes zero), and does it update on orientation change? | Phase 1's `deviceSafeInsets` population depends on the API actually differing from the legacy inset. | Studio device emulator (notched phone, landscape): read both APIs, confirm the safe-area API reports non-zero left/right and updates on rotate. |
| Q5 | Does `GetTextBoundsAsync` calibration, fed back into the estimator table and re-solved, converge to tighter boxes without ever under-reserving (text clipping) across the known fonts and CJK? | Phase 5's correction must not trade the estimator's safe over-reserve for clipped text. | Studio: measure a corpus (Latin wrap, CJK, unknown font) both ways; confirm corrected boxes are ≥ actual text bounds and < estimator bounds. |
| Q6 | Does `ContentProvider:PreloadAsync`'s per-asset callback give enough signal to drive `provider.complete`/`fail` with the right generation? | Phase 6's transport correctness. Roblox exposes no in-flight cancellation. | Studio: preload a batch including a bad asset id; confirm per-asset status maps cleanly to complete/fail. Release mid-flight and prove stale completion is ignored; prove queued-but-unstarted work does not begin. |

---

## 13. What becomes engine-only-testable under these recommendations — the honest ledger

Collecting the testability costs in one place, because this is the question the
director asked to be answered straight:

- **Scroll physics** (momentum, elastic bounce, scroll-bar drag, the input→offset
  mapping) — moves to the engine. *But it is not tested headlessly today because it
  does not exist today*; the framework still headlessly owns content geometry,
  windowing, and the programmatic scroll target. Net: a small in-Studio scroll
  harness replaces nothing that currently runs under Lune.
- **Optional native selection bridge behavior** (whether an engaged modal/menu gets
  selection sound, haptic, or native autoscroll without interference) — engine-only
  and unclaimed until Studio plus physical-gamepad proof. Focus logic and explicit
  keep-visible behavior stay fully headless and do not depend on the bridge.
- **Engine text bounds** — the *correction* runs at the edge and is Studio-verified;
  the estimator and its calibration table stay headless and pinned.
- **Native image decode / load-failure** — engine-only; the provider state machine
  stays headless.

Everything the framework's 595-test suite and fuzzer currently assert — layout
geometry, fill distribution, focus identity and navigation, windowing, async state
transitions, environment-derived policy — **remains headlessly testable and
unchanged**. Not one "keep" or "hybrid" recommendation moves an existing headless
assertion into the engine; the "adopt" recommendations only move behaviour that is
already either absent or already at the adapter edge. That is the deliberate shape of
the plan: hand the engine the things it does natively *on top of* geometry, and keep
the geometry, identity, and state decisions in Luau where the autonomous workflow can
prove them.
