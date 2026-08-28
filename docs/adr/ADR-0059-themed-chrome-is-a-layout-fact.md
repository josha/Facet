# ADR-0059 — themed chrome is a layout fact wherever it is painted

**Date:** 2026-08-27
**Status:** Accepted
**Number:** 0059 (0058 went to the concurrent INPUT lane's physical-size-aware ten-foot classing, committed `47b4930` while this was being written; renumbered here rather than beside it, because a pin binds an ID and its text together). A defect-class fix across five seams — no new public prop and no
new theme key, so Decision 3's shape instrument (the required set and the
documented defaults) has nothing to record. It DOES move painted geometry under
every package that carves a border, and that earns it
**[ADR-0040](ADR-0040-unreleased-breaking-changes.md) row B-32** on the same
precedent B-18/B-21/B-25/B-30/B-31 set: a geometry change is a row even where the
change is a repair.
**Companions:** [ADR-0019](ADR-0019-theme-package-schema.md) §5 (the promise this
keeps in two more places — "a nine-slice skin has a carved border that content
must clear"), [ADR-0020](ADR-0020-rich-skinning-v2.md) R4/R5 (semantic icons and
the pixel rules), the containment invariant's own charter in
`tests/lib/overflow_guard.luau`.
**Home:** `src/tokens/chrome_slots.luau` (`spendInset`, `liftGeometry`, `Hint.footprint`),
`src/render/layout_node.luau` (the chrome block, the bounded circle icon floor),
`src/client/screen_chrome.luau` (the lift's floor),
`src/controls/selection_indicator.luau` (the pill's inset),
`src/controls/row_actions_metrics.luau` + `src/controls/row_actions_root.luau`
(`EDIT_FOOTPRINT`, Decision 6), `src/themes/snapshot.luau` (`resolveTotal`),
`src/layout/solver.luau` (`sizeRefused`),
`examples/gallery/scenarios/hud.luau` (the task panel's body padding),
`examples/themes/pixel_quest.luau` (the package's own numbers).
**Guards:** `tests/themed_containment.spec.luau` (18 cases — the four
photographed surfaces, the four measurements, item 9 as a PROPERTY over a swept
package metric, and each new rule shown biting and silent),
`tests/chrome_inset_yield.spec.luau`, `tests/theme_layer_application.spec.luau`
(the lift's source pin).
**Instrument:** `tools/lune/theme_containment_census` — every corpus number in
this document is one run of it, with its dedup rule named (fix round 2026-08-28;
see the amendment at the foot).

## Context

The director photographed four defects on a physical handheld, all under the
Pixel Quest package, and asked one question about them:

> 6. Pixel Quest theme, screen-anchored HUD: top buttons show no labels.
> 7. Pixel Quest, same HUD: task list overflows its box.
> 8. Pixel Quest, tabs-nested: tab font has no padding, overlaps edge.
> 9. Pixel Quest, playlist table edit mode: delete control overlaps row.
> For 6-9: why doesn't the solver/containment system prevent themed overflow?
> Fix the CLASS, not four symptoms — the containment invariant should catch
> themed geometry.

**The answer, measured.** The containment invariant had never been run under a
theme, and would not have seen two of the four if it had.

`tests/overflow_sweep.spec.luau` swings all eight shipped packages onto every
swept surface — and on those passes it collects `controller.diagnostics()` and
nothing else. `overflow_guard.violations` runs once per viewport, on the freshly
mounted NEUTRAL tree, before the first `env:set("themeMetrics")`. So the one
instrument in this repository that asks *"is this rect inside the box it lives
in"* was structurally blind to every package that carves a border, which is every
ornate package the library ships. Measured by `tools/lune/theme_containment_census`
over the whole showcase corpus (63 surfaces × 9 viewports × 8 packages = 4,536
cells), **2026-08-28**:

| arm | total | distinct by (surface, node) |
|---|---|---|
| neutral — no package installed, what the suite asked | **0** | **0** |
| every package installed, judged against the plain RECT (the vocabulary before this round) | **270** | **42** |
| every package installed, judged against the THEMED box and the sibling plate | **2,472** | **103** |

The distinct rule the backlog is booked against is **(surface, node)**: one
construction is one defect, and the same leaf on the same plate at nine viewports
under five carving packages is one thing to fix. The other rules the instrument
prints — 369 by (surface, package, node), 654 by (surface, view, node) — are
there so a reader can see what the choice costs.

*(The figures 92 / 601 / 494 / 484 / 253 stood here and in the task report until
2026-08-28. They came from a probe that was never committed and none of them
reproduces; the table above is the committed instrument's own output. Review
finding I1.)*

And the invariant's vocabulary was neutral-shaped in two ways that matter:

1. **A themed panel's visible edge is not its rect.** A nine-slice skin carves a
   border out of its own box (`ThemeSnapshot.chromeInsets[slot]`), so the box a
   player sees content inside is the rect MINUS that. Judging against the outer
   rect pardons a child painted over the whole frame — item 7.
2. **A plate is often a SIBLING, not an ancestor.** The library's idiom for a
   tinted panel is `ZStack{ Box(surface, fill×fill), content }`, because the tint
   channel belongs to a `Box` and a stack cannot carry one. The HUD's `glass()`
   builds one, `selection_indicator`'s pill builds one, and a consumer reaching
   for a tinted panel builds one. `boundaryFor` only ever walked UP, so the node
   carrying the surface was never on its path — items 7 and 8.

Under those two blind spots sat two arithmetic defects the framework owned:

3. **`spendInset` asked the wrong question.** A chrome inset is spent only if the
   content box survives it, and "survives" was `> 0`. A Pixel Quest chip is
   `controlSizes.compact.height` = 36 wearing a 16px frame per side: four pixels
   left, which is a positive number, so the solver reserved a 4×4 content box and
   the paint seam drew a 16px glyph into it. That is item 6 — three round HUD
   buttons showing no mark at all — and it is invisible to every instrument in the
   suite, because a Button's own text is a PROP and not a node, so the zero-box
   rule cannot see it either.
4. **Two theme facts decided one distance and nothing made them agree.** The
   edit-mode delete disc is `shape = "circle"` + `icon`, and the icon floor raises
   its authored diameter to `iconSizes.medium` PLUS the node's own padding — which
   by then included the chrome inset: 32 + 32 = 64. The gutter `row_actions`
   reserves for it is `controls.rowActions.editAffordance + rowGutter` = 36. That
   is item 9, a 28px overlap onto the row's leading edge.

...and one of the numbers was simply wrong in the package. Pixel Quest wrote every
`contentInsets` equal to its art's NINE-SLICE BORDER, which its own authoring rule
(`2·border + 1` design pixels, so the stretched centre is exactly one) forces to
be large. Read off the art design pixel by design pixel, `pixel_plate_default` is
one INK outline and one bevel — a TWO design-pixel frame around five design pixels
of flat face, with the corner rivets sitting on the bevel. Four was reserving half
the plate.

## Decision

**1. A chrome inset may not eat through the node's own line box.**
`chrome_slots.spendInset(extent, authored, inset, minContent?)` takes a floor, and
`render/layout_node` passes the node's resolved `textSize` for a leaf that draws a
string and ZERO for everything else — which is byte-for-byte the rule that shipped
before. Below the floor the WHOLE inset comes back (the give-back is still all or
nothing), the content draws, and the solver's existing `chromeYield` diagnostic
reports that the control is smaller than its theme expects. Refuse-or-catch,
never a silently blank control.

**1a. An `aspect` axis is as knowable as the one it follows.** `extentOf` read
only a literal px, so on every disc in the library (`shape = "circle"` is a fixed
px on one axis and `aspect ratio = 1` on the other) the rule half-applied: the
height gave its frame back and the width, seen as unbounded, kept charging for it.
The solver's own arithmetic (`w = h · ratio`, `h = w / ratio`) is copied at this
seam rather than approximated.

**1b. The paint seam takes the same floor.** `chrome_slots.liftGeometry` gains
`minContentW`/`minContentH` and `screen_chrome` passes the host's live `TextSize`.
The lift is a COPY of the node's engine text and its own header already promised
it "must never be smaller than that text's own box"; the promise was enforced
against zero.

**2. A sibling plate's carved border is REPORTED, not repaired — and the repair
was built and measured before it was rejected.**

The obvious fix is to hand the plate's inset to the stack's other children.
Measured: it turns the HUD's objective pill from **116x41 into 92x85** under
Fantasy Ornate, and drops the `ViewThatFits` ladder to its short rung, because a
package's `panel` recipe is a WINDOW frame (30px per side there) and this idiom
wears it on chips and pills as well as on panels. Making every small plate grow by
a window's border is a worse answer than the defect. Deciding that a `raised` chip
is not a window is a THEME question — which slot a small plate should classify
into — and belongs to a round that can re-spec the packages.

So the framework's answer here is CATCH: `tests/lib/overflow_guard` treats a
full-bleed surfaced sibling as the boundary its stack really has, every one of the
103 escapes is now a finding a spec can fail on, and the fixtures that can afford
their own frame spend it at their declaration. The HUD's task panel — 288px wide,
the one plate in that fixture that IS a panel, and the one the director
photographed — now takes `math.max(10, chromeInsets.panel.<side>)` as its body
padding: flat packages are byte-identical (`max(10, 0)`) and Pixel Quest spends its
24. The rest of the HUD's pills are enumerated in
`tests/themed_containment.spec.luau`'s HUD plate ledger, one row per construction,
each with the largest overhang measured, and a row that stops firing fails the
suite so the list can only shrink.

**3. The selection indicator's pill gives its own inset to the frame first.**
`inset` is decoration — "stand this chip off the segment edge" — and a package's
carved border is not. `skinOpts.inset` is now `max(0, declared − carved)`, where
`carved` is the largest side of the bar's own slot inset. Zero on every flat
package, so shipped geometry cannot move there. It does not make a 16px frame fit
a 44px tab; it stops the framework spending pixels making it worse.

**4. The containment invariant learns themed geometry, and is RUN under packages.**
`overflow_guard.violations(adapter, ledger, snapshot?)`: with a snapshot, a
boundary's box is its THEMED CONTENT box, and a full-bleed surfaced sibling plate
is the boundary its stack really has (never the branch the question came up —
without that exclusion every plate in the library reports overflowing itself by
exactly its own inset). Without a snapshot nothing changes by a byte, so every
existing caller keeps the neutral rules it had.

`tests/themed_containment.spec.luau` is the always-on floor, at the MEASURED
MINIMUM that catches the class rather than the whole cross product: the three
surfaces the director photographed (plus the playlist in the STATE he photographed
it in, entered through the shipped Edit affordance), under the two packages with
the fattest and second-fattest carved borders, at three viewports — including the
narrowest, where a frame costs the largest fraction of the screen.

**5. Pixel Quest's `contentInsets` are the frame its art carves.** `control`,
`field` and `selection` 16 → 8 and `stepperPlate` 12 → 8, each read off the PNG.
`panel` stays 24 against a measured 20: on a 52-design-pixel window one design
pixel of extra clearance costs nothing, where on a 9-design-pixel control it cost
the entire content box.

## What moves

* **Every disc under a package that carves a `control` border** loses the frame
  it was reserving twice: Fantasy Ornate's HUD chip goes 60 → 52, Fantasy
  Parchment's 44 → 38, Pixel Quest's stays 36 with a 20px interior instead of 4.
* **The showcase HUD's task panel** insets its rows by the installed package's
  `panel` border where that is larger than its own 10px (Pixel Quest 24, Fantasy
  Ornate 30); flat packages are unmoved.
* **Every `pill` selection indicator under an ornate package** covers its whole
  segment instead of an inset chip.
* **Pixel Quest's controls, fields, rows and stepper plates** gain 8px of interior
  per side.
* **Studio Neutral and every flat package are byte-identical** — `chromeInsets`
  is all-zero for them, so Decisions 1-4 are no-ops and `check_flat_baseline` has
  nothing to compare that moved.
* Rascal Rally does not install a carving package on any shipped surface; its
  selection-indicator contract pins the neutral inset (`second.w - 8`) and holds.

**6. A SIZE FLOOR IS A REQUEST, NOT A RIGHT** *(fix round, 2026-08-28; review
finding C1).*

Decision 1 bounded one number in the chrome block and left the other unbounded.
`render/layout_node`'s `shape = "circle"` icon floor raises a disc to hold its
picture at full size — `iconSizes[role]` PLUS whatever padding the chrome block
just wrote — and it grew with no limit at all. Decision 5 moved Pixel Quest onto
the side where the floor happens to fit; it did not make the two numbers agree, so
director item 9 reproduces under a package one design pixel thinner. Measured
2026-08-28, `02_playlist_table` in edit mode at compact-phone-portrait, Pixel
Quest with only its `control`/`field`/`selection`/`stepperPlate` insets at 4 per
side — every value still a multiple of its own `pixelUnit`, its package gate
green:

| `control` inset/side | disc | row starts | overlap |
|---|---|---|---|
| **4** | **40x40 @ x=16** | x=52 | **+4 onto every row — IMG_3788** |
| 5, 6, 7, 8 (shipped) | 32x32 @ x=16 | x=52 | −4 clear |
| 9, 12 | 32x32 @ x=16 | x=52 | −4 clear |

At 4 the inset is SPENDABLE (32 − 8 = 24, above the 16px line-box floor of
Decision 1), the disc's padding becomes 4, the floor wants 32 + 8 = 40, and the
gutter `row_actions` reserved is 36.

So the floor takes the same shape `spendInset` already has one screen up.
`chrome_slots.Hint.footprint` is the host declaring what it RESERVED, in the
grammar a padding side and a dimension field already take (a px, a metric name, or
a list that SUMS — `themeSnapshot.resolveTotal`, extracted here rather than copied
a third time). Above it the floor is refused: the control keeps the room it was
given, `chrome_slots.iconBoxPx` draws the picture at the size that fits, and the
solver files `sizeRefused` naming both numbers. **Refuse-or-catch, never a silent
overlap.**

**One expression, not two that agree.** `row_actions_metrics.EDIT_FOOTPRINT` is
`{ editAffordance, rowGutter }`. `editGutterPx` resolves it to reserve the room
(replacing its own `editAffordancePx + rowGutterPx` pair) and `row_actions_root`
hands the identical list to `attachHint` as the disc's ceiling, so the reservation
and the bound cannot be edited apart.

**What moves:** at inset 4 the disc is 36x36 (capped at the gutter, ending exactly
where the row begins) with one `sizeRefused` per row; at every shipped inset it is
32x32 with zero findings. **No shipped geometry moves.** `chrome_slots.hintKey`
carries `footprint` BY CONTENT, because it decides geometry and a recycled node
carrying another one would solve to another size.

The guard for it is a PROPERTY rather than two rects: `themed_containment`'s last
group sweeps the one package metric that decides item 9 and asserts "the
affordance never exceeds the gutter the row reserved for it", with anti-vacuity
row counts and the assertion that only the arm which used to overflow files.

## What is NOT decided here

The census above reports **103 distinct escapes remaining** across the corpus
after this round (2,472 hits) — overwhelmingly leaves laid directly on a sibling
plate (`UI.background(tile, plate)` with a `Text` base is the commonest shape),
which Decision 2 deliberately does not repair. **22 of the 2,472 are `zero-box`**
— a visible string solving to nothing — and those are a different and worse defect
than the plate overhangs; they are named here rather than folded into one total.
That is a real backlog and it is recorded rather than waived: the honest repair is
either a leaf-side padding seam that reaches paint, or those fixtures wrapping
their ink. Booked for the campaign's next round; this ADR's guard is a floor under
the four the director reported, not a claim about the library.

**Three of the eight packages carve nothing and still report 14 hits between them**
(`glossy_mobile` 11, `scifi_hud` 3). Those are NOT this class: a flat package still
moves geometry through its metrics, so the escapes are ordinary containment
defects the neutral pass cannot see because the neutral tree is a different tree.
An earlier draft of this ADR and of `layout_node`'s comment claimed "0 under every
flat one"; that was never measured and is not true.

## Amendment log

* **2026-08-27** — decisions 1-5, as landed by the round this ADR was written for.
* **2026-08-28 (fix round)** — Decision 6 added (review finding C1: item 9's class
  was not closed by Decision 5); every corpus number replaced with one run of the
  now-committed `tools/lune/theme_containment_census` (finding I1); the flat-package
  and `zero-box` claims corrected against that run.
* **2026-08-28 (extraction round)** — Decision 1b's own comment claimed the measure
  and paint seams "can never drift"; review finding I5 traced the one window they
  still could (a `TextSize`-only write with no rect change, which
  `render/rect_pass.luau`'s unchanged-rect skip left unrefit until the next
  `applyRect`). The fix was booked against `src/client/screen_target.luau`'s
  SOURCE_CAP_LEDGER row (the file was inside the band) and lands in the same round
  the row's named extraction (`src/client/screen_props.luau`) does: the `textSize`
  branch — now in `screen_props.luau` — calls `refitIconArt(handle)`, pinned by
  `tests/chrome_inset_yield.spec.luau`.
