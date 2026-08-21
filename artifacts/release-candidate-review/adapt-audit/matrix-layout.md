# Wave ADAPT-AUDIT — Part 2: the layout-primitive matrix

**Anchor:** commit `e25ad06339ba8ebc158368a52c0fed549b39e8c6` (2026-08-20 20:51 -0700,
*"the fifth control the new guard found, documented where the reader is"*), measured
from a private `git archive HEAD | tar -x` export. Writers were active on the live
tree throughout; nothing below was measured against a working copy.

**Seat:** supplemental fresh-context audit. This document **appends to**
`artifacts/release-candidate-review/adapt-audit/matrix.md` (Part 1, anchored at
`d6c5b3c4`) and does not restate its cells. Part 1 asked whether the *interaction
paradigm* is right per combo; this part asks the director's 2026-08-20 question:
**how do the LAYOUT PRIMITIVES adapt by default across every screen-size × input
combo — `HStack`/`VStack` named explicitly.**

**Part 1 findings that have LANDED since its anchor, re-measured here** so no cell
below is stale:

| Part 1 finding | status at `e25ad06` | how I checked |
|---|---|---|
| ADAPT-1 (facts must be handed to controls) | **fixed** — `src/env/surface_env.luau` publishes the environment against the core, and `tests/adaptive_defaults.spec.luau` is the standing guard | read at anchor |
| ADAPT-2 (tablet took the phone bar) | **fixed** — `adaptive.navPlacement` asks the SHORT SIDE; my tablet row now resolves `topBar` | probe 1 |
| ADAPT-5 (no TV-safe content width) | **fixed** — `environment.luau:223-246` defaults 60/90 overscan at `displaySize == "Large"`; measured live | probe 4 · L-G2 |
| ADAPT-22 (`UI.Grid` = one lane) | **STILL OPEN** — `grid.luau:gridLaneCount` returns `1` | probe 2 · L-B1 |
| ADAPT-23 (ten-foot lane cap) | **fixed in the pure function, INERT on the default path** — see ADAPT-L1. **RE-VERDICTED 2026-08-20: LIVE on the default path** (wave TEN-FOOT) | probe 11 |
| ADAPT-17 (no scroll snapping) | **STILL OPEN** — `grep -rn "snapTo\|scrollSnap\|snapping" src/` finds only motion's `snap` curve and `containerRelativeFrame`'s paging *arithmetic* | grep at anchor |
| ADAPT-17 — annotation, appended 2026-08-20 | **OVERTAKEN by wave CAROUSEL, `f3d2fe8` (2026-08-20).** `snap = "none" \| "item"` ships on `newVirtualList` and `newVirtualGrid` over `src/controls/scroll_snap.luau`; the grep above now finds it. The measurement above stands as of this artifact's anchor and is not rewritten | `fixes.md` CAROUSEL addendum |

**Language rule observed.** Reference-platform comparisons appear inside this
artifact only; every recommendation is expressed in Facet/Roblox terms.

**One cell is knowingly overtaken.** At the moment of writing, the live working tree
carries uncommitted `src/controls/scroll_snap.luau`, `src/controls/card_rail.luau`,
`tests/scroll_snap.spec.luau` and `tests/paradigm_cards.spec.luau`, plus edits to
`src/layout/adaptive.luau` — another writer is landing the carousel/snapping work.
**ADAPT-L10 is measured at the anchor and is expected to be stale on arrival**; the
controller should re-check it rather than route it. I read that uncommitted diff to
scope the collision: the `adaptive.luau` change is purely **additive**
(`CARD_MIN_WIDTH`, `CARD_PEEK` and a cards-per-view decision) and does not touch
`axisFor`, `DEFAULT_STACK_ABOVE`, `columnsFor` or `conditions`, so every other cell in
this matrix stands. My own single write is this artifact.

---

## The columns

Same six combos as Part 1, same facts, set on `tests/lib/world.luau`:

| Combo | viewport | capabilities | preferredInput | displaySize | resolves to |
|---|---|---|---|---|---|
| compact touch (portrait) | 390×844 | touch | Touch | Small | `compact` × `medium`, portrait, `axisFor = y` |
| compact touch (landscape) | 844×390 | touch | Touch | Small | `regular` × `short`, landscape, `axisFor = x` |
| regular touch (tablet) | 1024×768 | touch | Touch | Small | `wide` × `medium`, `axisFor = x` |
| desktop pointer + keyboard | 1600×900 | mouse, keyboard | KeyboardAndMouse | Medium | `wide` × `medium`, `axisFor = x` |
| ten-foot gamepad | 1920×1080 | gamepad | Gamepad | Large | `regular` (capped) × `medium`, `axisFor = x`, overscan 90/60 |
| hybrid (pointer+touch) | 1280×800 | mouse, touch, keyboard | KeyboardAndMouse | Medium | `wide` × `medium`, `axisFor = x` |

The anchor row, measured (probe 1):

```
DEFAULT_STACK_ABOVE = 600   BREAKPOINTS regular=600 wide=1000
compact-touch-portrait    390x844  sizeClass=compact  heightClass=medium  axisFor=y  cols(min160,gap12)=2  nav=bottomBar
compact-touch-landscape   844x390  sizeClass=regular  heightClass=short   axisFor=x  cols=4             nav=bottomBarCompact
regular-touch-tablet     1024x768  sizeClass=wide     heightClass=medium  axisFor=x  cols=6             nav=topBar
desktop-pointer          1600x900  sizeClass=wide     heightClass=medium  axisFor=x  cols=9             nav=sidebar
ten-foot-gamepad        1920x1080  sizeClass=regular  heightClass=medium  axisFor=x  cols=5 (pure)      nav=topBar
hybrid-pointer-touch     1280x800  sizeClass=wide     heightClass=medium  axisFor=x  cols=7             nav=sidebar
```

**Instruments.** Every cell below cites one of: `probe N` — a headless mount on
`tests/lib/world.luau` at the six combos, reading solved rects through
`adapter.node(path).rect`, the solver's own findings through
`controller.diagnostics()`, the composition resolution through
`controller.compositionAt(path)` and the text facts through `controller.textAt(path)`;
`census` — a brace-matched scan of every `UI.<Primitive>{…}` call site in `examples/`
and `src/`, cross-checked against a raw `grep -c` (all eleven primitives × both roots
agree bit-for-bit); or a direct source read at the anchor. Probe scripts lived only in
the private export.

---

# Family L-A · Stack axis adaptation

## The census that frames the family

| primitive | `examples/` | `src/` |
|---|---|---|
| `UI.HStack` | **162** | 14 |
| `UI.VStack` | **247** | 15 |
| `UI.AdaptiveStack` | **9** | 2 |
| `UI.ViewThatFits` | 14 | 0 |
| `UI.Composition` | 8 | 0 |

Eighteen plain `HStack`s for every `AdaptiveStack`. **38 of those `HStack`s lay out
three or more literal children in a row, declare no `wrap`, and are not inside a
horizontal `ScrollView`** — the shape that overflows a 390 px phone. (Thirteen more
have ≥3 children *and* `wrap = true`, so they reflow; those are excluded.) Six more
build their children dynamically and cannot be counted statically; the strongest of
them is `examples/gallery/examples/05_word_game.luau:630`, one row of a ten-key
on-screen keyboard.

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **A-1** | is a plain `HStack`/`VStack` fixed-axis by design, and is that the right default? | fixed axis, at all six combos. `blueprint_schema.luau:1361-1371` gives them `gap`/`align`/`distribute`/`wrap` and **no** axis prop. A 4×160 px row at 390 stays a row and overflows by 274 px (probe 2 · L-F1) | fixed. A stack that silently re-oriented itself would make every row's geometry a function of a fact the author never named, and the remount-free adaptive route exists beside it | **RIGHT** |
| **A-2** | `UI.AdaptiveStack{}` with `axis` omitted | **a permanent VStack at every combo.** `axis` defaults to `"y"` (`blueprint_schema.luau:1576-1583`); `render/layout_node.luau:254-257` resolves `kind = if props.axis == "x" then "hstack" else "vstack"`. Probe 1 · L-A2: the bare stack solved 160×200 (a column) at all six combos, including ten-foot 1920 | a class named `AdaptiveStack` must not be able to silently not adapt. `tab_view.luau:344-350` is the in-repo precedent: it REFUSES to construct when its adaptive fact is absent, naming the fix | **WRONG** (ADAPT-L4) |
| **A-3a** | `conditions.axis` at compact touch portrait (390) | `y` — column | column | **RIGHT** |
| **A-3b** | at compact touch landscape (844) | `x` — row | row | **RIGHT** |
| **A-3c** | at regular touch tablet (1024) | `x` | row | **RIGHT** |
| **A-3d** | at desktop pointer (1600) | `x` | row | **RIGHT** |
| **A-3e** | at ten-foot gamepad (1920) | `x` | row | **RIGHT** |
| **A-3f** | at hybrid (1280) | `x` | row | **RIGHT** |
| **A-4** | is `DEFAULT_STACK_ABOVE = 600` the right breakpoint? | **content- and typography-blind.** Probe 6 · L-A4 swept a real three-button row (`Continue` / `Settings` / `Quit to menu`) against viewport width: the row measures **410 px** and fits from **420**, but `axisFor` keeps it a column until **599** — up to 180 px of unused width on every viewport in that band. At `preferredTextOffset = 14` the same row measures **653 px** and **overflows at 600**, where the threshold has already answered `"x"` | a threshold that flips a row is a claim about content and type, and this one knows neither. The framework already owns the honest instrument — `ViewThatFits` measures the real candidate against the real offer | **WRONG** (ADAPT-L6) |
| **A-5** | is the axis fact the CONTAINER's width or the SCREEN's? | **the raw viewport**, by construction: `adaptive.luau:356-364` — *"this is the RAW viewport width — it does NOT subtract safe insets or overscan"*. Probe 5 · L-A3: viewport 620 with 60 px insets each side ⇒ content 500, `conditions.axis = "x"`, and the bound `AdaptiveStack` **overflows by 56 px**. Probe 10 · L-A3b, with nothing but ordinary page padding (`padding = "l"`, 24 px): viewport 610 ⇒ **overflows by 62 px**; 640 ⇒ **32 px**; clean from 680 | the adaptive route must not produce a row that paints outside its box. `api.md:3852-3857` documents the gap and points at `ViewThatFits` — but the class the guide teaches for a toolbar is `AdaptiveStack`, so the documented workaround is not the taught route | **WRONG** (ADAPT-L3) |
| **A-6** | does an axis flip remount its children? | **no.** Probe 10 · L-A6: 400 → 900 px live, axis `y` → `x`, live node count 4 → 4, **zero removes**. The class's whole promise holds | exactly this | **RIGHT** |
| **A-7** | does the guide teach the right primitive where adaptation is wanted? | **yes.** `docs/guide/01-concepts.md:295` states the rule outright — *"The first two are enough for a toolbar or an action row"* — over a table listing only `AdaptiveStack`, `ViewThatFits` and `Composition` as the adapting primitives (`01-concepts.md:289-293`). The canonical toolbar samples use the adaptive route: `api.md:669-674` (a `ViewThatFits` row→column ladder), `api.md:643-648` (an `AdaptiveStack` literally named `"Toolbar"`), `guide/01-concepts.md:307-328` (a `Composition` action region). The guide also states the failure mode plainly (`01-concepts.md:630-632`): *"if they run past the edge they run past the edge — the row paints outside its own box and the solver complains about it"*. The one genuine counter-sample is a bare `HStack` of filter chips at `docs/guide/07-input.md:438`, a snippet about `sensoryFeedback` rather than about layout | this | **RIGHT** |
| **A-8** | should MORE composition adapt automatically — is `wrap` ever a default or a bound fact? | `wrap` is reactive and bindable (`blueprint_schema.luau:1035-1043`; `guide/01-concepts.md:648-651` shows binding it to `conditions`), and **no shipped surface binds it to a size class** — 13 sites set the literal `true`, none bind. Probe 2 · L-F2: `wrap = true` does the right thing at every combo (390 reflows onto two lines; wider combos stay one line) | one of two things, and the controller should pick: either `wrap` binds by default on a stack whose children do not fit, or the diagnostic is promoted to a construction-time refusal the way `tab_view` refuses. Silence is the option that has produced 38 overflow-shaped call sites | **AUTHORED-ONLY** |

**Family L-A: 13 cells — RIGHT 9, WRONG 3, AUTHORED-ONLY 1.**

### ADAPT-L4 · `AdaptiveStack` without `axis` is a VStack forever, and three shipped fixtures prove it

**Severity: high. Confidence: high.** The census found 11 `AdaptiveStack` call sites.
Eight bind `axis` to a reactive readable (six to `adaptive.conditions(...).axis`, two
to a scope-owned memo — `tab_view.luau:582`, `picker.luau:619`). **Three omit `axis`
entirely**, and each carries a comment stating the opposite of what it does:

- `examples/gallery/scenarios/canvas_group.luau:222-236` — *"side by side where there
  is room, a column where there is not: the two panels are only a comparison while
  both are visible, and a 320px phone cannot hold two 132px plates in one line"* —
  then `UI.AdaptiveStack{ id = "Panels", gap = 8, width = fill, children = { … } }`,
  with no `axis`.
- `examples/gallery/scenarios/nested_compositing.luau:355-368` and `:385` — the same
  comment, the same omission, twice.

On a 1920 television those comparison panels are stacked vertically, forever. The
author reached for the adaptive class, said out loud what they wanted, and got the
non-adaptive default with no warning. That is the ADAPT-1 shape one layer down, and
the fix is the same one Part 1 recommended: adopt `tab_view`'s refusal. **Smallest
fix:** make `axis` **required** on `AdaptiveStack`, or make its absence an error
naming `adaptive.conditions(core, env).axis`. A default of `"y"` on this particular
class buys nothing — an author who wants a column has `UI.VStack`.

### ADAPT-L3 · The adaptive axis is a screen fact applied to a container that got less

**Severity: high. Confidence: high.** Reproduced with nothing exotic — a `Screen` with
`padding = "l"` (the theme's own 24 px page margin) and an `AdaptiveStack` bound to
`conditions.axis` (probe 10 · L-A3b):

| viewport | content box | `conditions.axis` | solved row | solver finding |
|---|---|---|---|---|
| 610 | 562 | `x` | 562×44 | *content overflows this hstack by 62px on the main axis* |
| 640 | 592 | `x` | 592×44 | *…by 32px* |
| 680 | 632 | `x` | 624×44 | — |

The module documents its own hazard (`adaptive.luau:356-360`, verifier finding V16)
and `api.md:3852-3857` repeats it, so this is not a hidden defect — it is a **known
gap between the fact the docs warn about and the class the docs teach**. The band is
narrow but it is exactly the band where the decision matters, and it widens with every
inset: 180 px of it at ten-foot overscan, 94 px on a notched landscape phone under
`deviceSafeContent`, 48 px from ordinary page padding.

**Smallest fix (two candidates, controller's call).** (a) Give `conditions` a
`contentWidth` that actually subtracts the resolved insets and leave `viewportWidth`
as the raw alias — the names already exist and are currently the same signal, which is
what makes the trap invisible. (b) Let `AdaptiveStack` resolve its own axis from the
box the solver proposed to it, which is the `ViewThatFits` contract applied to one
prop. (a) is one memo; (b) removes the class of defect.

---

# Family L-B · Grid, lanes, GridRow and the arrangement presets

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **B-1** | `UI.Grid{}` with neither `columns` nor `minColumnWidth` | **one lane at every combo, 390 through 1920.** Probe 2 · L-B1: six 160×100 cards stacked in a single column at all six combos. Source: `grid.luau:174-193` `gridLaneCount` returns `1` when both are absent | the most-reached-for card container should lane itself from the space it got. A one-lane default on a 1920 TV is a column of cards down the left edge | **WRONG** (ADAPT-L2; Part 1's ADAPT-22, still open) |
| **B-2a** | `Grid{minColumnWidth = 160}` at compact touch portrait | 2 lanes, 160 px cells | 2 | **RIGHT** |
| **B-2b** | at compact touch landscape | 4 lanes | 4 | **RIGHT** |
| **B-2c** | at regular touch tablet | 6 (child-count bound) | ≥6 | **RIGHT** |
| **B-2d** | at desktop pointer | 9 lanes | 9 | **RIGHT** |
| **B-2e** | **at ten-foot gamepad** | **10 lanes — one MORE than the desktop's 9.** Probe 11, 14 cards, `minColumnWidth = 160`, `gap = 12` | 5 — `adaptive.columnsFor(1920, 160, 12, {distanceProfile = "ten-foot"})` answers 5, and the solver is documented to call the same function | **WRONG** (ADAPT-L1) — **RE-VERDICTED 2026-08-20: RIGHT.** A bare default-path mount at 1920×1080 now measures 5 lanes against a 1600px desktop's 9 (wave TEN-FOOT) |
| **B-2f** | at hybrid | 7 lanes | 7 | **RIGHT** |
| **B-3** | how the corpus actually reaches lanes | **0 of 35 `UI.Grid` call sites bind `columns` reactively or through `columnsFor`.** 8 pass a fixed integer or build-time constant; 20 pass a static px minimum or `"intrinsic"` (7 sites use `"intrinsic"`, the route `guide/05-styling.md:335-359` teaches); the only live binding in the repository is `virtual_grid.luau:704`, internal. `newVirtualGrid` **refuses** `minColumnWidth` outright (`virtual_grid.luau:263-268`) and tells the caller to pre-derive `columns` from `columnsFor` — and no caller does | the adaptive lane route is exported, documented, arithmetically identical to the solver's, and chosen by nothing. Same shape as Part 1's picker census (0 of 17) | **AUTHORED-ONLY** |
| **B-4** | `GridRow` at compact | **silently squeezes past declared fixed widths, with no diagnostic.** Probe 9 · L-B3b, three cells each `width = fixed(200)`: at 1024 → 200 px each; at 560 → 181; at 460 → 148; at 390 → **124**; at 320 → **101**. Zero solver findings at every width | a row-mode grid needs an answer at compact — collapse to fewer columns, wrap, scroll, or *at minimum* the finding an `HStack` files at the same width. Two containers in one family with opposite failure modes (`HStack` overflows loudly, `GridRow` squeezes silently) is the worse of the two options in both directions | **WRONG** (ADAPT-L8) |
| **B-5** | `GridRow` with text cells at compact | wraps gracefully — probe 9 · L-B3c: `"Total time elapsed"` is one line at 1024/560/390 and two lines at 320, `truncated = false`, `policy = wrap` throughout | wrap, not cut | **RIGHT** |
| **B-6a** | `Composition` arrangement at compact touch portrait | **`column`** (probe 5 · L-B4), lanes stacked full width | the tall offer | **RIGHT** |
| **B-6b** | at compact touch landscape | `threeLane`, lead 200 · main 420 · trail 200 | the short, wide offer | **RIGHT** |
| **B-6c** | at regular touch tablet | `threeLane`, main 600 | `threeLane` | **RIGHT** |
| **B-6d** | at desktop pointer | `threeLane`, main 1176 | `threeLane` | **RIGHT** |
| **B-6e** | **at ten-foot gamepad** | `threeLane`, **main lane 1316 px wide**, `fallback = false`. Identical to the desktop answer with more pixels | a distance profile should cap the measure the way `sizeClass`, `heightClass` and (in the pure function) `columnsFor` all do. `maxMeasure` and the per-arrangement `eligible` gate both exist and are both unset by default | **AUTHORED-ONLY** |
| **B-6f** | at hybrid | `threeLane`, main 856 | `threeLane` | **RIGHT** |
| **B-7** | can a `Composition` be silently non-adaptive? | **no** — `arrangements` and `groups` are `required = true` (`blueprint_schema.luau:1607-1626`), and every one of the 8 shipped sites declares 2–3 rungs. Nothing is reactive on the class, deliberately: *"a Composition decides FOR the author from the box it was given"* (`blueprint_schema.luau:1597-1602`) | exactly this — it is the one primitive in the family that cannot fail the way A-2 fails | **RIGHT** |

**Family L-B: 17 cells — RIGHT 12, WRONG 3, AUTHORED-ONLY 2.**

### ADAPT-L1 · The ten-foot lane cap is real in the pure function and inert on the default path · **TOP FINDING**

**Severity: critical. Confidence: high.** ADAPT-23 was fixed by moving the cap into
`adaptive.columnsFor` and having the solver pass the distance fact
(`grid.luau:180-192`). The fact it passes is `ctx.metrics.density`. That value is set
in exactly one place — `themes/snapshot.luau:745`:

```lua
out.density = if f.displaySize == "Large" then "ten-foot" else "near"
```

…from the facts a snapshot was **resolved** with. The environment's default
`themeMetrics` is `themeSnapshot.neutral()` (`env/environment.luau:137`), resolved
with **no facts at all**, so its `density` is `"near"` — permanently, on a television,
forever, unless something re-resolves it. The only thing that re-resolves it is
`client/theme_controller.luau:936`, whose `factsForResolve()` does read
`displaySize` (`:624`) — but the theme controller is an **opt-in install**
(`theme_controller.install(...)`, called by `examples/gallery/client/init.client.luau:132`
and by nothing in `src/`). A surface presented through plain
`Facet.newPresenter` never gets one.

Measured (probe 11), 14 cards, `minColumnWidth = 160`, `gap = 12`:

```
neutral snapshot density                     = near
resolve({ displaySize = "Large" }).density   = ten-foot

desktop 1600 (default themeMetrics)          lanes = 9
ten-foot 1920 (default themeMetrics)         lanes = 10   <-- the TV gets MORE
ten-foot 1920 (themeMetrics resolved Large)  lanes = 5    <-- the cap, when fed
```

**The television still gets more columns than the desktop.** The number moved (11 → 10,
because the overscan narrowed the inner extent) and the defect did not.

The asymmetry that makes this silent is worth naming precisely: the ten-foot **type**
floor works on the default path, because the renderer reads `displaySize` from the
environment at its own measure seam (measured — ten-foot text solved 1.5× larger in
every probe, e.g. the same label 169×39 at desktop and 164×87 at ten-foot). Only the
**density** half routes through the theme snapshot. So a TV surface with no theme
package installed gets big type in dense lanes — the worst of both.

**Smallest fix.** Read the distance fact where every other distance decision reads it:
from the environment. `grid.luau`'s `gridLaneCount` already receives `ctx`; the solve
already carries `displaySize` to the text seam. Passing `distanceProfile` on the same
channel as the type floor removes the theme snapshot from a decision that is not about
theming. If the snapshot must stay the source, then `themeSnapshot.neutral()` cannot be
the environment's default — a default metric authority that is wrong about the display
class is a default that silently disables every distance rule built on it. **Check the
rest of that blast radius before closing:** any other consumer of `metrics.density`
is inert on the same path.

---

# Family L-C · ZStack, overlay and Anchor

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **C-1** | where does a ZStack put an overlay child by default? | **the top-left corner, at all six combos.** Probe 8 · L-C4: a 200×100 panel in a fill ZStack solves at the container origin at 390, 844, 1024, 1600, 1920 and 1280. `alignH`/`alignV` (`blueprint_schema.luau:749-766`) are per-child, default absent | an overlay layer's natural default is centred; `guide/04-tutorial-examples.md:624-636` records the framework's own tutorial pass having to fix exactly this ("centering a card requires a full-bleed ZStack wrapper", `alignH` "accepted and silently ignored" on `Screen`/`VStack`) | **WRONG** (ADAPT-L11) |
| **C-2** | an overlay wider than its ZStack | **a finding, naming the fix.** Probe 4 · L-C2, a 360 px panel in a 320 px box: *"this child overflows its zstack by 40x0px and nothing clips a zstack, so it paints over whatever sits beside it (give the box room — a `minMax` FLOOR rather than a fixed CAP — or set overflow = "intentionalOverlap")"* | exactly this — the message names both the cause and the two legitimate answers | **RIGHT** |
| **C-3** | does overlaid content have a COMPACT answer as the viewport shrinks? | **no.** A ZStack overlay neither re-places, re-sizes, scrolls, nor becomes a sheet at any combo; it keeps its declared box and, past the box, files C-2's finding. There is no size-driven presentation on the class | at compact an overlay that no longer fits should become the combo's full-surface presentation. Part 1's ADAPT-25 (no general sheet presentation) is the same hole seen from the transient-surface side; this is its layout-primitive face | **MISSING** |
| **C-4** | `Anchor` placement as the viewport shrinks, per combo | **correct at all six.** Probe 4 · L-C3, a `bottomRight` 200×64 plate: bottom gap 0 and right gap 0 at every combo, measured against the **resolved content rect** — so at ten-foot it lands at 1630,956 inside the 90/60 overscan, not at 1720,1016 against the raw window | this | **RIGHT** |
| **C-5** | is "chrome over a scrolling body" an overlay problem at all? | **no, and the corpus agrees.** Of 148 `ZStack` and 36 `Anchor` sites, **zero** layer interactive content over a live scroll region; the three that contain a `ScrollView` (`sponsor_celebration.luau:229`, `p3_sipworks/views/detail.luau:572`, `rewards.luau:173`) are all *backgrounds behind* one. The shipped idiom is `Region{ mayScroll = true }` inside a `Composition` (which enforces exactly one scroller — `composition.luau:950-953`) or a `fill`-weighted `ScrollView` beside a pinned sibling (`adaptive_controls.luau:614-635`) | this — the declared-content route is the right home for the decision | **RIGHT** |

**Family L-C: 5 cells — RIGHT 3, WRONG 1, MISSING 1.**

---

# Family L-D · ViewThatFits ladders

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **D-1a…f** | does the rung choice track the combo? (structural ladder: 3-up row → 2-up row → column) | probe 5 · L-D2: **compact touch portrait → `Col`; all five other combos → `Row3`** | the compact column, the roomier row | **RIGHT** ×6 |
| **D-2** | does the rung respond to the combo's TYPOGRAPHY when the host constrains the cross axis? | **yes.** Probe 6 · L-D3, a 200×44 chip: `preferredTextOffset = 0` → the rich rung ("Round 3 · Capture the flag", 169×39); `+10` → **`Terse`**; `+14` → **`Terse`**. The ladder skipped the mid rung because it too would have wrapped | this — the rung is a function of measured type, not of width alone | **RIGHT** |
| **D-3** | …and when the host does NOT constrain the cross axis? | **no.** Probe 5 · L-D1, the same ladder in a width-200 chip with no height cap, at all six combos and four text preferences: the rich rung wins **24 times out of 24**, growing 169×**39** at `+0` to 168×**108** at `+14` — one line becoming three, 2.8× the height, and still "fitting" | the DIR contract-7 rule *"wrapping is still fitting"* is the correct narrow reading, but its consequence at the accessibility preferences is a chip three times its budget with no rung able to say so. This is not a bug in contract 7; it is the boundary of what a width-plus-cut test can see | **WRONG** (ADAPT-L12) |
| **D-4** | is the post-contract-7 cut-driven step-down actually live? | **yes.** Probe 12 · D-4b, an unwrappable label (`"Reconfiguration"`) against a shrinking chip: 300 → rich (`truncated = false`); 180 → rich; **120 → the terse rung wins** (`truncated = true`, `policy = "truncate"`); 80 → terse. The clamped cut is counted (`solver.luau:534-559`) and the honest shorter rung undercuts it | this | **RIGHT** |
| **D-5** | …and its documented exclusion | an author's own `lineLimit` cut is deliberately NOT a fit failure (`solver.luau:531-544`: *"refusing a candidate for obeying its own declaration … trades a cut label for an overflowing screen"*), measured on the shipped corpus at 24–138 px of overflow. Probe 6 · L-D4 confirms it in situ: with `lineLimit = 1` on every rung the rich rung keeps winning while ellipsized, at every preference | the exclusion is right and the measurement behind it is on the record. Recorded here so the controller knows the shape: a rung that declares `lineLimit = 1` opts *out* of the ladder's ability to protect it | **RIGHT** |
| **D-6** | are the shipped ladders real, or cosmetic? | 14 sites; **8 differ structurally** (a row rung and a column rung, or a beside-card and a full-bleed card — `adaptive_controls.luau:218`, `preferred_text.luau:124`, `p1_glade/init.luau:895`, `p1_glade/ui/overview.luau:303` (the one 3-rung ladder), `p3_sipworks/views/detail.luau:140`, `shell.luau:139`/`:162`, `p4_foyer/init.luau:936`); **6 differ only in copy or `compactLabel`** | a ladder whose rungs are the same layout with shorter words is a legitimate use — but 0 sites in `src/` means no framework control offers one | **RIGHT** |

**Family L-D: 10 cells — RIGHT 9, WRONG 1.**

---

# Family L-E · Spacer, gap and padding as layout results

*(Part 1's Family I owns the metric ladder itself; these cells are about what the
tokens DO to a layout.)*

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **E-1** | does a `[A][Spacer][B]` row distribute correctly per combo? | **yes, all six.** Probe 4 · L-E1: B lands flush at the content right edge at 390, 844, 1024, 1600, 1920 (inside the overscan) and 1280; the Spacer absorbs 134 / 588 / 768 / 1344 / 1484 / 1024 px respectively | this | **RIGHT** |
| **E-2** | does a Spacer-driven layout collapse sensibly at compact? | **the Spacer collapses correctly and then the row overflows.** Probe 4 · L-E2, `[200][Spacer][200]` at 390: `Sp` resolves 0×0 — the right behaviour — and the row then overflows by 26 px with the solver's finding. The Spacer does its job; nothing does the next one | the collapse is right. The step after it belongs to Family L-F | **RIGHT** |
| **E-3** | do spacing tokens resolve differently per combo? | **no — byte-identical at all six.** Probe 8 · L-E3b: `gap = "m"` → **16 px** and `padding = "l"` → **24 px** at 390×844 and at ten-foot 1920×1080 alike | a television at 3 m should not lay out on a 390 px phone's 24 px page margin and 16 px gutter, when its type is already 1.5× larger. Part 1's ADAPT-8 flagged the ten-foot ladder's scope as a **director call**; this is the specific missing rung, measured | **WRONG** (ADAPT-L9, and a director call rather than a defect if ADAPT-8 is decided that way) — **RE-VERDICTED 2026-08-20: RIGHT.** The director decided it that way; `gap = "m"` is 16 near and 24 at ten-foot |
| **E-4** | is there a route that avoids hand-placed Spacers for a variable-count row? | **yes** — `distribute` (`start\|center\|end\|spaceBetween\|spaceAround\|spaceEvenly`, `api.md:462-480`), documented specifically because `UI.ForEach` cannot interleave separators: *"A tab bar whose tab count varies is otherwise inexpressible"* | this | **RIGHT** |

**Family L-E: 4 cells — RIGHT 3, WRONG 1.**

---

# Family L-F · Scroll hosts as layout — what answers when content exceeds the viewport

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **F-1** | content taller than the viewport, no author action, per combo | **it paints outside its box at all six.** Probe 5 · L-F3, twenty 80 px rows: the last row solves at y = 1672 against a 844 px screen and the solver files *"content overflows this vstack by 908px on the main axis; it will paint outside its box (wrap it in a ScrollView, or give it room)"* — 908 / 1362 / 984 / 852 / 792 / 952 px across the six combos. Nothing wraps. Nothing scrolls. Nothing clips: `ClipsDescendants` is unset on both the stack and the `Screen` (probe 2 · L-F1) | the default answer to "more content than room" is a scroll on every combo, and a focus-driven scroll at ten-foot. Post-DIR the framework's own position is that clip is not an answer either (`api.md:294-295` — `overflow = "clip"` is opt-in; `ScrollView` is the only container that clips by default) — so today the default is the third thing, which is worse than both | **WRONG** (ADAPT-L5) |
| **F-2** | `wrap = true` as the authored answer for a row | works at every combo (probe 2 · L-F2). Never bound to a size class anywhere in the corpus | should be reachable without the author naming a width | **AUTHORED-ONLY** |
| **F-3** | `ScrollView` as the authored answer, and is its LAYOUT input-aware? | **yes, and correctly so.** Probe 8 · L-F4/L-F5: the vertical host reserves an 8 px indicator lane on the touch and pointer combos (window 382 inside a 390 host) and **reserves nothing at ten-foot gamepad** (window 1740 inside a 1740 host; the x-rail likewise 140 vs 132). Zero findings at every combo | a pad has no scrollbar to grab, so reserving a lane for one would spend TV pixels on nothing. This is the family's best cell | **RIGHT** |
| **F-4** | is a scroll host ever the DEFAULT? | **never.** 104 `ScrollView` sites, all authored; `axis` is construction-only by contract (`blueprint_schema.luau:1407-1413`, and `authoring.luau:47` is a standing negative test proving a reactive axis is refused) | at minimum the solver's finding should escalate: it already knows the overflow, the amount, the axis and the fix, and it says so to a diagnostics call nobody is obliged to make. `docs/lessons/the-solver-already-told-you.md` is the repository's own record of what that costs | **AUTHORED-ONLY** |
| **F-5** | the compact-touch card carousel | **unreachable.** No scroll snapping exists at HEAD (Part 1's ADAPT-17, re-checked). `containerRelativeFrame`'s paging form gives the card *widths* (`blueprint.luau:2008-2095`, SwiftUI's arithmetic verbatim) and nothing settles the scroll on a card boundary | a single-view swipe/carousel is the compact-touch paradigm for a card set; the director named it as the example | **MISSING** |
| **F-5** — annotation, appended 2026-08-20 | as above | **OVERTAKEN by wave CAROUSEL, `f3d2fe8` (2026-08-20).** The carousel is reachable and is now the DEFAULT at compact touch rather than an authored route: `itemExtent = "cards"` resolves one card per view with a peek and turns snapping on, and `containerRelativeFrame` is no longer the way to size the page (`fixes.md` re-verdicts B-8 SUPERSEDED for that reason). The cell above is left as measured at the anchor | as above | **FIXED elsewhere** |
| **F-6** | the declared-content answer | `Region{ mayScroll = true }` inside a `Composition`, with rule 5's *"exactly one scroll"* enforced by refusal (`composition.luau:950-953`) — two scrollable regions is a construction error naming both | this is the right home: the decision sits beside the ranks and the step-down ladder | **RIGHT** |

**Family L-F: 6 cells — RIGHT 2, WRONG 1, AUTHORED-ONLY 2, MISSING 1.**

### ADAPT-L5 · The default answer to overflow is to paint outside the box

**Severity: high. Confidence: high.** This is the family's spine, and it is the same
sentence at all six combos. Three separate probes reached it from three directions —
a row of fixed boxes (274 px over at compact), a Spacer layout whose ends alone exceed
the width (26 px over), and a twenty-row page (792–1362 px over at every combo) — and
the outcome was identical each time: the content is placed past the edge, nothing
clips it, and a finding is filed on a channel that must be asked.

The framework is *unusually* good at knowing this: the message names the container,
the axis, the pixel count and both legitimate fixes. `tests/overflow_sweep.spec.luau`
then asks the question of every showcase surface at every swept viewport on every
`./run-tests.sh` — which is why the corpus is as clean as it is. But a sweep over the
fixtures is not a default: a consumer's screen gets the diagnostic only if the consumer
reads diagnostics.

**Smallest fix directions, cheapest first.** (a) Bind `wrap` by default on a stack that
overflows its main axis — one boolean, already reactive, already measured to be
correct at every combo, and it is the answer for a *row*. (b) For a *page*, escalate:
the solve already computes everything the finding needs, so a `Screen` whose content
exceeds its content rect on the cross axis is the one case where an implicit scroll
host is defensible — `Composition`'s rule 5 shows how to keep it to exactly one. (c) If
neither, promote the finding to the `tab_view` treatment and refuse loudly at
construction where the shape is statically knowable. Doing nothing is the option that
produced 38 overflow-shaped `HStack` call sites in the framework's own examples.

---

# Family L-G · Safe-area and inset interaction with layout

| id | question | measured today | expected paradigm | verdict |
|---|---|---|---|---|
| **G-1** | the default root policy at the five near-distance combos | `coreSafeContent` (`renderer.luau:189`, `presenter.luau:1709`). Probe 4 · L-G1 with `coreSafeInsets = 44/34`: every near combo solves its `Screen` inset by exactly that | inset-by-default, edge-to-edge opt-in | **RIGHT** |
| **G-2** | …and at ten-foot | the same policy **plus** overscan: `Screen = 90,104 1740×882` at 1920×1080 — 60 top + 44 core. `environment.luau:314-326` composes them additively, `:242-245` supplies the 60/90 defaults when nothing was authored, and `"none"` opts out | both are real reservations; adding them is right, and the tvOS-equivalent 60/90 at 1080p is the right default | **RIGHT** |
| **G-3** | is the ten-foot overscan reachable without authoring? | **yes** — probe 4 · L-G2, with no insets declared at all, only the ten-foot combo comes back inset (`90,60 1740×960`); every other combo is flush. Part 1's ADAPT-5 is closed | this | **RIGHT** |
| **G-4** | does the DEFAULT policy honour `deviceSafeInsets` (a notch / home indicator)? | **no.** Probe 12 · G-4 at 844×390 with `deviceSafeInsets = {left = 47, right = 47}`: `coreSafeContent` → `Screen = 0,0 844×369` (full width, content **under the cutout**); `deviceSafeContent` → `47,0 750×369`; `edgeToEdge` → `0,0 844×390`. The device area is a real engine fact (`client/roblox_env.luau:133-136`, from the engine's device inset area) and the default policy is the one that ignores it | a content surface should honour a physical cutout without the author naming a policy. `deviceSafeContent` is documented as *"per-edge max of CoreGui and device insets"* (`api.md:2930-2933`) — a strict superset of the default, so making it the default cannot reduce anyone's content rect below what they have | **WRONG** (ADAPT-L7) |
| **G-5** | is there a title-safe full-bleed policy at ten-foot? | **no.** Probe 8 · L-G3: `edgeToEdge` at 1920×1080 returns the whole `0,0 1920×1080` — `renderer.luau:1884-1885` zeroes the insets, overscan included. Right for a scrim (the policy's stated purpose); there is no third option for a full-bleed *content* surface on a TV | a background that must bleed and content that must stay title-safe are two different requests, and today they share one word | **MISSING** |
| **G-6** | do the insets compose with layout correctly? | yes — `Anchor`, `Composition`, `Grid` and every stack measured above all resolved against the inset content rect at ten-foot, not the raw window (probes 2, 4, 5) | this | **RIGHT** |

**Family L-G: 6 cells — RIGHT 4, WRONG 1, MISSING 1.**

---

# Verdict counts

**Counting rule** (same as Part 1, stated so the number is auditable): one *cell* is one
default-paradigm decision about a layout primitive — resolved once where the answer is
combo-invariant (which it very often is in this family), and per combo where it is not.
Cells are the rows of the tables above. A finding spanning several combos is counted
once per affected combo-group.

| verdict | cells | share |
|---|---|---|
| **RIGHT** | **42** | 69% |
| **WRONG** | **11** | 18% |
| **AUTHORED-ONLY** | **5** | 8% |
| **MISSING** | **3** | 5% |
| total | **61** | |

Per family:

| family | cells | RIGHT | WRONG | AUTHORED-ONLY | MISSING |
|---|---|---|---|---|---|
| L-A Stack axis adaptation | 13 | 9 | 3 | 1 | — |
| L-B Grid / lanes / GridRow / arrangements | 17 | 12 | 3 | 2 | — |
| L-C ZStack / overlay / Anchor | 5 | 3 | 1 | — | 1 |
| L-D ViewThatFits ladders | 10 | 9 | 1 | — | — |
| L-E Spacer / gap / padding results | 4 | 3 | 1 | — | — |
| L-F Scroll hosts as layout | 6 | 2 | 1 | 2 | 1 |
| L-G Safe-area / inset interaction | 6 | 4 | 1 | — | 1 |
| **total** | **61** | **42** | **11** | **5** | **3** |

**How to read this against Part 1.** Part 1 scored 51% RIGHT over 114 interaction
cells; this part scores 69% over 61 layout cells, and the difference is real rather
than generous: the *mechanisms* here are almost all correct and well-tested — the axis
flip does not remount, the composition ladder picks the right arrangement at all six
combos, contract 7's cut-driven step-down is live, `Anchor` respects the overscan,
`ScrollView`'s indicator reserve is input-aware, the overflow diagnostics name the
container and the fix. What fails is narrower and more consistent: **eight of the
eleven WRONG cells are the same defect shape — an adaptive rule that exists, is
correct, is unit-tested, and is not reached on the default path.** `AdaptiveStack`
defaults to not adapting. `Grid` defaults to one lane. The ten-foot cap defaults to
off. The axis defaults to the wrong width. The root policy defaults to ignoring the
notch. This is Part 1's spine finding (ADAPT-1) restated in layout terms, and the
remedy is the same one Part 1 recommended and the framework already owns:
`tab_view.luau:344-350` refuses to construct rather than silently substituting the
large-screen answer.

## Findings, ranked

| id | finding | severity | confidence |
|---|---|---|---|
| **ADAPT-L1** — annotation, appended 2026-08-20 | **FIXED by wave TEN-FOOT** (ADAPT-8's build, [ADR-0039](../../../../docs/adr/ADR-0039-ten-foot-metric-ladder.md) Decision 2). This row's "smallest fix" offered two routes and named the second as the real one — *"if the snapshot must stay the source, then `themeSnapshot.neutral()` cannot be the environment's default"*. The route taken is that one, generalised: the snapshot stays the AUTHORED authority and the environment's `themeMetrics` READ applies the display class's distance policy, so the density fact and the metric ladder both fire from the live `displaySize`. The row's own reproduction is now a case in `tests/ten_foot_metrics.spec.luau` — a bare default-path mount at 1920×1080 measures FEWER lanes than a 1600px desktop, and its metrics are scaled — and it is red at the anchor by construction (the mutation that reverts the memo reddens 10 cases). The blast-radius check the row asked for was run: `metrics.density` has three consumers (`grid.luau`, `text_fit.luau`, `table.luau`) and all three now read a fact that is true on every surface | — |
| **ADAPT-L1** | ADAPT-23's ten-foot lane cap is inert on the default metric path: `metrics.density` comes from the theme snapshot, the environment's default snapshot is resolved with no facts, and a theme controller is an opt-in install — so a television still gets **10 lanes against a desktop's 9**. The ten-foot TYPE floor works on the same path, which makes it big type in dense lanes | **critical** | high |
| **ADAPT-L2** | `UI.Grid` still defaults to **one lane at every combo**, 390 through 1920 (Part 1's ADAPT-22, open at HEAD); and 0 of 35 shipped `Grid` sites bind lanes reactively | **critical** | high |
| **ADAPT-L3** | the adaptive axis is a **viewport** fact applied to a container that got less: an `AdaptiveStack` bound to `conditions.axis` inside a `Screen` with ordinary `padding = "l"` overflows by 62 px at 610 and 32 px at 640. The module and `api.md` both document the hazard; the class the guide teaches for a toolbar is the one that trips over it | **high** | high |
| **ADAPT-L4** | `UI.AdaptiveStack` with `axis` omitted is a **permanent VStack**, silently — and three shipped fixtures declare it with a comment saying *"side by side where there is room, a column where there is not"* and never go side by side | **high** | high |
| **ADAPT-L5** | the default answer to overflow at every combo is **paint outside the box**: no wrap, no scroll, no clip — only a finding on a channel nobody is obliged to read. Reproduced three ways, 26–1362 px over | **high** | high |
| **ADAPT-L6** | `DEFAULT_STACK_ABOVE = 600` is content- and typography-blind: a real 3-button row fits from **420** but stays a column to 599, and at `+14` the same row **overflows at 600** where the threshold has already said "row" | **high** | high |
| **ADAPT-L7** | the default root policy ignores `deviceSafeInsets`, so a default surface places content **under a physical cutout** unless the author picks `deviceSafeContent` — which is a per-edge superset and could not shrink anyone's content rect | **medium-high** | medium (see device list #1) |
| **ADAPT-L8** | `GridRow` **silently squeezes past declared fixed cell widths** at compact (200 px → 101 px at 320) with **zero** diagnostics — the opposite failure mode from `HStack`'s, in the same primitive family | **medium** | high |
| **ADAPT-L9** — annotation, appended 2026-08-20 | **FIXED by wave TEN-FOOT.** The row measured `gap = "m"` at 16 px on a 390 px phone and 16 px at ten-foot 1920×1080; it is 16 and **24** now, and the case that says so drives it through a real solve rather than through the snapshot. The row's own framing was exactly right — "the specific missing rung behind Part 1's ADAPT-8 director call" — and the director ruled BUILD | — |
| **ADAPT-L9** | spacing tokens are combo-invariant: a television lays out on a 390 px phone's 24 px page margin and 16 px gutter while its type is already 1.5× larger. The specific missing rung behind Part 1's ADAPT-8 director call | **medium** | high |
| **ADAPT-L10** | no scroll snapping at HEAD, so the compact-touch card-carousel paradigm is unreachable even by an author (Part 1's ADAPT-17, re-confirmed) | **medium** | high |
| **ADAPT-L10** — annotation, appended 2026-08-20 | **OVERTAKEN by wave CAROUSEL, `f3d2fe8` (2026-08-20)** — the same finding as Part 1's ADAPT-17, and closed by the same commit. This row's own preamble predicted it ("measured at the anchor and expected to be stale on arrival"); the annotation is the re-check it asked the controller for, appended rather than substituted | — |
| **ADAPT-L11** | `ZStack` children default to the **top-left corner** at every combo; the framework's own tutorial quality pass records having to fix exactly this | **medium** | high |
| **ADAPT-L12** | a `ViewThatFits` ladder whose host does not constrain the cross axis never steps down for typography: the rich rung wraps 39 px → **108 px** at `+14` and still wins, 24 times out of 24. Not a bug in contract 7 — the boundary of what a width-plus-cut test can see | **medium** | high |
| **ADAPT-L13** | no title-safe full-bleed policy: `edgeToEdge` at ten-foot returns the whole 1920×1080 and discards the overscan. Right for a scrim; there is no option for a full-bleed *content* surface on a TV | **low** | high |
| **ADAPT-L14** | *Positive, recorded:* the axis flip is a re-solve with **zero removes**; `Composition` picks `column` at compact and `threeLane` at the other five; contract 7's clamped-cut step-down is live; `Anchor` respects the overscan at ten-foot; `ScrollView` reserves an indicator lane on pointer/touch and **none** on a pad; the ten-foot overscan now defaults without authoring | — | high |

## The one systemic recommendation

Eight of the eleven WRONG cells and both `AUTHORED-ONLY` scroll cells share a single
root, and the framework already contains its own fix. Four separate adaptive rules —
`AdaptiveStack.axis`, `Grid`'s lane count, `columnsFor`'s distance cap, and the root
policy's inset source — are each **correct, exported, unit-tested, and off by
default**. Each one substitutes the large-screen / near-distance / no-cutout answer
when its fact is absent, and none of them says so.

`tab_view.luau:344-350` is the pattern: it refuses to construct when its adaptive fact
is missing, with an error naming the remedy. Applying it here is small and mechanical:

1. `AdaptiveStack.axis` becomes required (or its absence an error naming
   `adaptive.conditions(core, env).axis`) — ADAPT-L4, one schema flag;
2. `Grid` with neither `columns` nor `minColumnWidth` derives lanes from the box it
   was proposed, or refuses — ADAPT-L2;
3. the distance profile reaches `gridLaneCount` from the environment, on the same
   channel the ten-foot type floor already uses, rather than through the theme
   snapshot — ADAPT-L1;
4. `conditions` gains a `contentWidth` that actually subtracts the resolved insets,
   leaving `viewportWidth` as the honest raw alias — ADAPT-L3.

(1) and (2) are refusals; (3) and (4) are one memo each. Together they convert five of
this matrix's thirteen findings, and — as in Part 1 — every one of them would have been
caught at construction time rather than in an audit.

## Not measurable headlessly — for the batched Studio/device pass

| # | claim | the exact step that settles it |
|---|---|---|
| 1 | **ADAPT-L7's confidence.** Whether Roblox's *core* inset area already subsumes the *device* safe area on a notched phone, which would make the default policy adequate in practice | Physical notched device (or an emulated notch), landscape: `execute_luau` reading `GuiService:GetInsetArea` for both areas, compared against `env:get("coreSafeInsets")` and `env:get("deviceSafeInsets")`. If core ⊇ device on every edge, ADAPT-L7 drops to low |
| 2 | **ADAPT-L1 on a live client.** Whether a real session with a theme package installed always resolves the snapshot with `displaySize` before the first grid solve, and whether a display-class change re-resolves it | Studio at `ViewportDisplaySize = Large` with a package installed: read `env:get("themeMetrics"):get().density` at first paint and after a class change; then count lanes on a `minColumnWidth` grid |
| 3 | Whether a 10-lane card grid on a real 1080p television is legible at 3 m, i.e. how much of ADAPT-L1 is a *legibility* defect versus an arithmetic one | Console/TV or `ViewportDisplaySize = Large`, `screen_capture` viewed at equivalent angular size, director sign-off — the same instrument as Part 1's device row 1 |
| 4 | Whether the 24 px page margin and 16 px gutter (ADAPT-L9) read as cramped at ten-foot distance, and what the right rung would be | Ten-foot matrix row, zoomed capture of a padded page under two theme packages; director call, tied to Part 1's ADAPT-8 |
| 5 | Whether content that paints outside its box (ADAPT-L5) is genuinely visible off-surface on the engine, or whether some ancestor `ClipsDescendants` hides it in practice | Studio Play: mount an overflowing `HStack`, `inspect_instance` the last child's `AbsolutePosition`/`AbsoluteSize` against the ScreenGui, and capture |
| 6 | Whether `wrap = true` reflows identically on `UIListLayout.Wraps` to the headless solve at every swept viewport (the fix direction for ADAPT-L5 depends on this) | Five-view matrix, a `wrap` row at 320/390/640/1080/1920, compare engine rects to the solved rects |
| 7 | Whether a fling on a card rail settles on a card boundary anyway through engine momentum, masking ADAPT-L10 | Device: a `ScrollView{axis="x"}` of 200 px cards on a phone; fling and release, record settle position across 10 trials (Part 1's device row 11, unchanged) |
| 8 | Whether `edgeToEdge` at ten-foot (ADAPT-L13) actually paints into a physical TV's overscan on real hardware, or whether the set compensates | Console/TV run, full-bleed surface, capture the corners against the physical bezel |
| 9 | Whether a `GridRow` squeezed to 101 px (ADAPT-L8) shows an ellipsis, a hard clip, or a legible cell on the engine | Studio at 320: `inspect_instance` the row's cell `AbsoluteSize` and capture zoomed |
| 10 | Whether the ZStack top-left default (ADAPT-L11) reads as a mistake to the eye on each combo, or whether the corpus's `alignH` discipline makes it moot in practice | Director review of the five-view matrix on a surface with an unaligned ZStack child |

## Method and provenance

Measured from a private `git archive` export of `e25ad06339ba8ebc158368a52c0fed549b39e8c6`.
Instruments: twelve headless probe scripts on `tests/lib/world.luau` at the six combos
(and at swept widths of 320–1920 and text preferences 0/+4/+10/+14 where a cell needed
them), reading solved rects through `adapter.node(path).rect`, findings through
`controller.diagnostics()`, composition resolutions through `controller.compositionAt`,
and text facts through `controller.textAt`; a brace-matched census of every
`UI.<Primitive>{…}` call site in `examples/` and `src/`, cross-checked against raw
`grep -c` (eleven primitives × two roots, identical); and direct source reads at the
anchor. Probe scripts lived only in the private export and are not part of the tree.

Two measurement caveats, stated rather than buried. **First**, headless text widths come
from the solver's own calibrated measurer, not the engine — so the *thresholds* in
ADAPT-L6 and ADAPT-L12 (420 px, 653 px, 108 px) are the solver's numbers and the
device list carries the confirmations. The *directions* they establish do not depend on
the exact widths. **Second**, ADAPT-L1's default-path measurement is definitive for any
surface presented without a theme controller — which is every headless surface and
every consumer that has not installed a package — and device row 2 settles the
live-client half rather than the finding itself.

Reference-platform comparisons are cited inside this artifact only; every
recommendation above is expressed in Facet/Roblox terms.
