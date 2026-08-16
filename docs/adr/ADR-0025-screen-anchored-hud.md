# ADR-0025 — The screen-anchored HUD: zones that PARTITION, and the collision alarm

**Date:** 2026-08-14
**Status:** Accepted (stage 1 shipped; stage 2 named in Consequences)
**Commissioned by:** the game director, 2026-08-14, from two screenshots of a shipped Roblox FPS
(*Rivals*, built on NativeUI, not LuauUI). Verbatim: *"note things are largely pinned to the top,
upper left, middle left, upper right, upper center, and lower right parts of the screens and should
stay that way as the screen changes"* and *"if not, what would be needed--we should build that."*
**Companions:** ADR-0023 (`UI.Composition` — this is its second consumer shape and the reason it
needed no fork), ADR-0022 (motion/paint escapes), `docs/lessons/the-solver-already-told-you.md`
(why a new failure class must be *reported*, not merely *avoided*).

## Context — what the screenshots actually show

Fullscreen, the HUD is right. Open a browser URL bar — **same width, ~200px less height** — and it
collapses into itself: the "Beginner Tasks" panel climbs into the round buttons above it, the weapon
rail at top-right runs into the fps/ping readout and the player nametags, and the right-hand action
buttons overlap each other.

The director asked two questions.

**(1) Can LuauUI build these controls?** Yes, and it was verified rather than assumed
(`tests/hud_composition.spec.luau` builds the same shapes out of the public surface): round icon
buttons are `UI.Button` + `corners`, pill badges are `newChip`, the bars are `newProgressView`, the
ring indicators are the round-3 circular `newProgressView`, and the rest is `UI.Text` / `UI.Image` /
stacks. The one element on screen that is not a UI control is the virtual joystick, which is a
Roblox touch-control concern and not a layout one.

**(2) Would a LuauUI build have adapted instead of overlapping?** **No — and the reason was
structural, not a bug.**

- `UI.Composition` is a **FLOW**: "lanes sit side by side; a lane stacks its groups down the cross
  axis" (`src/layout/composition.luau` header). It was built for pages and documents — the five
  reference apps, the RascalRally results surface.
- `alignment` already gives the nine anchors the director listed
  (`topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight`,
  `src/blueprint_schema.luau` `anchor`), so **pinning was already expressible** through `UI.Anchor`.
- **But anchored siblings do not reserve space from each other.** `UI.Anchor` places every child
  against the same box independently; nothing in the solver forbids two of them growing into one
  another. That is exactly the screenshot, and it is the same bargain SwiftUI makes: a `ZStack` "is
  a view that overlays its subviews, aligning them in both axes"
  ([ZStack](https://developer.apple.com/documentation/swiftui/zstack), read 2026-08-14), and
  `overlay(alignment:)` "layers the views that you specify in front of this view"
  ([overlay(alignment:content:)](https://developer.apple.com/documentation/swiftui/view/overlay(alignment:content:)),
  read 2026-08-14). *Overlay* is the word. Neither framework's corner vocabulary reserves anything.
- The viewport change itself is handled correctly already — a URL bar shrinking the height moves
  `viewportRect` and the surface re-solves once (optimization log L-29). **The re-layout fires. The
  layout simply has no rule that forbids collision.**

## Decision 1 — a HUD is a `UI.Composition`. No new vocabulary, no sibling module.

The brief posed the architecture question explicitly: is a screen-anchored HUD a **new arrangement
vocabulary inside `composition.luau`** (anchored zones instead of lanes), or a **sibling module
sharing its rank/form-ladder core**?

**It is neither, and that is the finding.** A nine-anchor HUD is *already* expressible in the lane
vocabulary, exactly:

- **the three screen columns are three lanes** — lanes sit side by side and never overlap, which is
  the partition the director asked for, by construction and not by a new rule;
- **the three vertical bands are three groups per lane**, with the placement vocabulary the lane
  band already has: `place = "start" | "center" | "end"` is top / middle / bottom;
- **`topLeft … bottomRight` are the nine group ids** — the same nine words `anchor` already uses.

So `composition.HUD` and `composition.HUD_GROUPS` ship as **frozen data**, the way
`composition.ARRANGEMENTS` already does. There is no new solver kind, no new blueprint class, no
second resolution procedure, and — the point — **no second copy of the rank / form-ladder /
step-down-before-drop machinery**. It is reused *literally*, not shared by extraction.

**Why this beats the two options the brief named.**

- *A new arrangement vocabulary inside `composition.luau`.* `solveArrangement`'s `pass()` is
  lane-shaped in every line — `laneIntrinsic`, `laneW`, `laneX`, `laneBudget`, the span band. A
  second geometry inside it means a `if hud then` beside each, which is the round-2 trap standing
  rule 2 names by name ("when you find yourself writing a second `if` for a sibling case, the first
  one was the bug"). The file is 1700 lines; this would have taken it past the "within an agent's
  reach" ceiling ENGINEERING.md draws.
- *A sibling module sharing the rank core.* Requires extracting the ladder out of a shipped,
  byte-for-byte-pinned module (ADR-0023's additivity pins are literal resolution comparisons), which
  is a broad refactor — flagged, not smuggled, per ENGINEERING.md — for a mechanism that turns out
  not to need it.

**What the framework was genuinely missing was three small, additive bits, not a vocabulary** —
Decisions 2 and 3, plus a group `align`.

**`align`: across the lane, where `place` is down it.** A region's rect is its whole lane (regions
are allotments), so a right-hand cluster had no way to sit on the right of its column without
declaring `width = fill` and aligning inside itself — and a form that fills its box also *hides* its
intrinsic width from the composition, which is precisely what Decision 3 needs to see. `align =
"start" | "center" | "end"` on a group gives its regions their own measured width inside the lane and
places them at that end. Absent, the region takes the whole lane, unchanged. Stating the alignment is
what asks for the content width, because aligning a box that already fills its lane would mean
nothing.

**The width half of the ladder, found by the showcase rather than by design.** Rule 2 asks whether
the *hug* lanes fit the offer, which is the only width question a lane whose width IS its content can
fail. A HUD's lanes are `fill` — a share of the box — so a cluster wider than its share could fail
nothing: it painted over the column next door and the rank ladder never ran. On a 320px phone each
column is 106px, which is where every horizontal cluster in the showcase met it at once. A lane's
width overflow is now an overflow like any other and goes to the same rule-3 ladder, with the same
"must buy a pixel" filter (here: be the region that is actually over) and the same scroll-region
exclusion.

**What we gave up, said plainly.**

1. **The columns are thirds of the box, not content-hugged.** A left cluster wider than a third does
   not push its neighbour aside; it overflows and Decision 3 reports it. This is deliberate: a
   column that widened because its neighbour emptied would *move* the other clusters, which is the
   one thing the director forbade. A HUD's columns are a **coordinate system**, not a content flow.
   An author who wants a different split copies the preset and changes the group weights (the lane's
   share is the sum of its `fill` groups' weights) — it is data.
2. **The vertical bands are per-column, not shared rows.** "Top" in the left column and "top" in the
   right column are independent heights. For corners this is right; a HUD that wants one full-width
   band across the top uses a composition **span** group, which already exists and already takes its
   height out of the same budget.
3. **A zone's form must fill its column and align itself.** The region rect is the whole column
   (regions are allotments — ADR-0023 Decision 4), so a right-hand cluster is authored
   `UI.VStack{ width = "fill", align = "end" }`. Forgetting it left-aligns the cluster inside its
   column rather than breaking it. Documented in the guide and shown in the showcase; not enforced,
   because the honest enforcement would be a horizontal `place` on a group and that is a second way
   to say what `align` already says.

## Decision 2 — `holdsLane`: rule 9's declared counterpart

ADR-0023 rule 9 (**empty-lane release**) collapses a lane whose every region resolves to nothing
paintable and gives its width to the fill lanes. It exists because a results screen must not spend a
third of a landscape phone on a column with nothing in it.

**A HUD needs the exact opposite, for the exact same reason it needs the lanes at all.** Measured on
the fixture before the flag existed: with the centre column empty, the three lanes became
`left w=450 @ x=0`, `centre collapsed`, `right w=450 @ x=450` — and the top-right cluster moved from
x=600 to x=450. The column's width **is** the coordinate; releasing it moves everything the director
said must stay put.

So a group may declare **`holdsLane = true`**: *this group's lane keeps its place in the band even
when nothing in it is paintable.* It is refused on a `span` group (a span row has no lane to hold),
it is additive (absent = today's behaviour, byte-for-byte), and it is the *declared* counterpart to
rule 9 rather than a HUD special case — any composition whose lane positions are load-bearing can
reach for it.

In the preset it rides one extra group per lane whose only job is the column itself:
`{ id = "leftColumn", lane = "left", sizing = "fill", holdsLane = true }`. A group with no regions
declaring its lane's width reads as what it is — **the column group states the column, the zone
groups state the bands** — and it keeps `sizing`'s two jobs from colliding: the column group's
`fill` buys the lane its third of the width, while the nine zone groups stay `hug` so the `place`
spacer run still does top/middle/bottom. One flag, two facts, no new sizing axis.

## Decision 3 — the collision alarm: `resolution.collisions`, filed by the solver

The partition makes zones unable to overlap **as boxes**. It does not make their *content* unable to
paint outside those boxes — a row of five buttons that cannot shrink still measures wider than the
column it was given, and then it is drawing over the column next door. That is the screenshot's
"weapon rail runs into the fps/ping readout", and **nothing in the repo could see it**: the
composition is perfectly *legal*, so no `fallback` finding fires, and the inner stack's own overflow
sentence says "this content is too wide for its box" without ever saying *and therefore it is on top
of your neighbour*.

So `composition.resolve` now also answers **who is on top of whom**. For every mounted region it
takes the *painted* box — the rect it was allotted, grown to the size its chosen form actually
measured at that box — and reports every unordered pair whose painted boxes intersect:

```
collisions = { { a = "WeaponRail", b = "Readout", dx = 24, dy = 61 }, … }
```

It is a **general Composition output**, not a HUD one (standing rule 2): any composition whose
regions paint into each other has always had this defect and has never had a word for it. It is
computed in the pure module, so a whole device matrix is a headless sweep rather than a screenshot
review — ADR-0023 Decision 2's bargain, unchanged. The solver files one diagnostic per pair:

```
region 'WeaponRail' paints over region 'Readout' by 24x61px — a composition's regions
partition the box, so a region drawing outside its own is drawing on top of its neighbour
(give it a form that fits, let it shrink, or let it drop)
```

**It is a defect finding, not a `designed = true` report.** The fallback finding beside it describes
the author's instruction being followed; this one describes two things on screen at once, which no
author asked for.

**And it is visible to the always-on sweep by construction.** `tests/overflow_sweep.spec.luau` has
asserted since 2026-08-13 that a swept surface produces *no solver findings at all* over an
enumerated waiver list — the filter that used to make new diagnostics structurally invisible is
gone. A finding filed into `ctx.diagnostics` is therefore swept at every viewport, in both
orientations, at all four accessibility text sizes, on every `./run-tests.sh`, with nobody deciding
to run it. That was checked rather than assumed: the new class was introduced deliberately into the
showcase HUD and the sweep reddened.

## Decision 4 — elision must DISCLOSE, not delete: `recover`, `elided`, `unshown` (2026-08-16, D7)

**Adaptation may change how much of something is shown, and what it costs to reach it. It may not
change whether it can be reached at all.**

Decisions 1–3 gave a HUD a ladder that steps a region down and then drops it, in descending rank,
and the mechanism does exactly that. What it had no vocabulary for was **where the content the
reduced form stopped showing went** — so from the player's side "step down" and "delete" were the
same operation. Measured on this ADR's own showcase fixture before the repair
(`artifacts/navigation-and-menus/d7-hud-baseline.md`, and the sweep in
`artifacts/navigation-and-menus/d7-elision-discloses.md`): **39 elided-or-dropped occurrences across
nine viewports and two URL-bar states, every one a dead end** — including the `…` button that might
have hosted a recovery, which lived in a FORM the ladder never chose and was therefore
`Visible = false` at every viewport the fixture had ever been swept at.

So a region with more than one form must now state one of three things, and it is a closed spec:

| `recover` | meaning |
|---|---|
| `"none"` | every form below the richest still shows everything — a poorer *layout*, not less content |
| `"self"` | the reduced form **is** the route; the player taps what is left to get the rest |
| `"overflow"` | the screen's overflow surface is the route, and it reads `Resolution.unshown` |

**Required where it means something, refused where it does not.** Required on a region with more
than one form (`composition.normalize`); refused on a region with one (`blueprint.Region`) — such a
region can only stop showing content by being *dropped*, and a dropped region has no form left to be
its own route, so the sink is the only possible answer and `mayDrop` is already that declaration.
`"none"` together with `mayDrop` is refused for the same reason: dropping shows nothing.

The two halves are enforced in **different modules**, and that is a measurement rather than a
preference: `forms` reaching the solver is the count of MOUNTED forms, and a form behind a `UI.When`
is absent while its condition reads false, so the pure normalizer would reject a good declaration on
the frame a condition flipped (measured: three regions of `scenarios/composition`). `UI.Region` sees
the DECLARED count, which is what the "refused" rule is about.

**A `"self"` route is checked against every form BELOW the richest, not only the last.** The ladder
can stop at any rung, so checking only the terminal form leaves a dead end on exactly the
middle-sized devices nobody fixtures. A form with nothing focusable in it is an authoring error at
construction: a route nobody can reach is the defect wearing the fix's clothes.

**The seam is the list, not the flag.** `RegionResolution.elided` sits beside `dropped`, and
`Resolution.unshown` carries one entry per thing the screen has stopped showing, in declaration
order, with the route already resolved. Without it every consumer re-derives elision by hand and gets
it wrong three ways — a dropped region is not `form > 1`; a `recover = "none"` region is missing
nothing; a one-form region can only be missing by being dropped. A dropped region's route is
**always** `"overflow"`, whatever its `recover` said, which is the half `mayDrop` has always implied
and now states.

**What this ADR does NOT decide.** The framework supplies the list; the screen supplies the surface.
A `recover = "overflow"` declaration says the screen owes a route, and nothing here proves one
exists — that is a per-surface sweep (`tests/elision_recovery.spec.luau` does it for the HUD
showcase, asserting the sink is `visibleOf` true rather than merely present). Extending that sweep to
the whole showcase corpus is the natural follow-on and is deliberately not smuggled in here.

## Consequences

- **Public surface added (D7, 2026-08-16):** the `recover` field on `UI.Region` — **required** on a
  region with more than one form, which is a **breaking change to every multi-form Region author**
  (51 declarations migrated: 18 in the showcase and reference apps, 15 in the framework suite, 18 in
  RascalRally). `elided` on `RegionResolution` and `unshown` on `Resolution`, both additive and both
  on `luauui-composition-dump/1` — empty/`false` on every declaration that resolved cleanly before
  this shipped. Required-rather-than-defaulted is the deliberate call: a default would mean every
  existing declaration silently claimed a route nobody had thought about, which is the
  accepted-and-ignored class this boundary exists to remove.
- **Public surface added:** the `holdsLane` group field; `composition.ZONES`, `composition.HUD_GROUPS`
  and `composition.HUD` (frozen presets); `collisions` on the resolution and on
  `luauui-composition-dump/1`. MINOR bump; additive in both directions — a declaration with no
  `holdsLane` and no colliding region resolves and dumps byte-identically, pinned by a test.
- **Cost, measured — tier: HEADLESS LUNE, which is a regression signal and never a device claim.**
  The instrument is `composition.resolve` driven directly against the pre-change module read out of
  git, strictly alternating arms, 15 pairs, min per arm (`tests/_hudbench`, scratch):

  | | per resolve | note |
  |---|---|---|
  | the commissioning 8-region / 3-arrangement declaration, **before** | 129.6–132.5 µs | the off-path case: no HUD, no `align`, no `holdsLane` |
  | ...the same declaration, **after** | 131.7–134.2 µs | **+1.3% / +1.6%**, against a same-arm spread of **3.2–6.4%** — the delta is inside the harness's own noise and this instrument cannot resolve it |
  | the HUD declaration (7 regions, 12 groups, 3 lanes) | 49–51 µs | a HUD re-solve is ~⅓ of what a shipped results screen already pays, because it declares ONE arrangement instead of three |

  Two things were done to get there rather than asserted. The collision scan is behind a cheap
  precondition — a `#regions` loop asking whether *anything* paints outside its own box, since with
  every region inside its allotment there is nothing to intersect — so its two tables and its pair
  loop are never built on a clean solve; unconditional, it cost +3.5%. And `holdsLane` normalizes to
  `nil` rather than `false` when it was not declared, so an existing group table does not gain a
  ninth key.

  The scan itself is O(mounted²) per *resolution*, and a resolution is computed once per node per box
  and cached on the solve context. Twelve regions is 66 rect intersections of pure arithmetic.
- **Stage 2, named and not shipped:**
  1. **Whole-pixel fill shares.** Three lanes of a 359px box are 119.666px each, and a row shrunk to
     fill one lands ~0.0004px past its own edge — which the solver honestly reports as "overflows by
     0px". Rounding the shares to whole pixels (remainder to the last fill lane) removes it, and,
     measured on 2026-08-14, also removes **six waived findings** across `composition` and
     `p2_cartwheel`: a fractional lane box is what several of them are made of. That is a corpus-wide
     geometry change carrying its own waiver-list deletions, so it is flagged as its own scoped
     change rather than smuggled into a HUD mission (ENGINEERING.md, *"Flag refactors; don't smuggle
     them"*).
  2. A **physical-device** run. The Studio canary is DONE (below); a phone is still the only thing
     that supports a device claim.
  3. A `dense-hud` **perf-lab scene** row, if the measured cost below ever stops being noise.
  4. The **RascalRally consumer pass**. Nothing in the game declares a `UI.Composition` HUD today, so
     the lockstep obligation here is a compatibility proof (the game's compositions resolve and dump
     byte-identically), not a port.

## The Studio canary — real engine, 2026-08-14

Driven on `LuauUI-Showcase` in Play, viewport **735 x 413**, Studio Neutral, through the demo
picker. The oracle is the ENGINE's own `AbsolutePosition` / `AbsoluteSize`, not the solver's rects,
so it cannot agree with the solver by construction.

| | HUD box | what is on screen |
|---|---|---|
| URL bar **closed** | 735 x 261 | all seven zones: rounds `@0,62`, tasks `@0,150`, kill feed `@0,308`, clock `@345,62` (centred in its own column), weapon rail `@699,62` (right edge exactly on 735), fps readout `@668,93`, actions `@673,173` |
| URL bar **open** (200px of height gone) | 735 x 61 | tasks (rank 8), kill feed (rank 9), readout (rank 7) and the rail (rank 4) dropped; the clock stepped to its timer-only form (77px → 40px); the actions stepped to one button. Rounds still `@0,62`, clock still `@345,62`, actions still hard on the bottom-right at `bottom = 123` = the HUD's own bottom. **Pairwise overlap across every mounted zone: NONE.** |

**The canary earned its keep twice**, which is the argument for running it rather than trusting the
sweep. At 61px the right column first held a 31px rail over a 46px button with neither able to give,
so the arrangement went illegal and rule 8 showed the declared fallback — correct by contract, and
16px of HUD painted below its own box. Then the centre column did the same thing with a 77px
clock+score pair that had only one form. Both are authoring facts about the *fixture*, not framework
defects, and neither was visible to the swept viewports (none of which is 61px tall). The fix in both
cases is what a real HUD does: the rail is droppable (it ranks below the action buttons), and the
clock has a second form that is the clock without the score.

**Delivery caveat, recorded rather than glossed:** the showcase place's Rojo session was stale, so
the current `composition.luau` and the fixture were pushed into the datamodel over a local HTTP fetch
rather than by live sync. `solver.luau` exceeds Studio's 200 000-character `Source` limit, so the
**collision diagnostic itself was not live in this session** — its evidence is headless
(`tests/hud_composition.spec.luau` and the always-on sweep). The geometry above is real-engine.

## Alternatives considered

- **A `UI.Hud` blueprint class with `UI.Zone` children.** Sugar over exactly this declaration. It
  buys an author nine group lines and costs a public class, a schema entry, a blueprint validator, a
  solver kind and a second place for the nine anchor names to drift from `anchor`'s. Rejected at
  rung 1 of the simplicity ladder; the preset is data and an author who wants sugar can write a
  four-line local helper, which the showcase does.
- **Making `UI.Anchor` reserve space from its siblings.** It is the *layering* primitive — overlays
  over content is its job, and half the shipped chrome depends on it. Changing it would silently
  reflow shipped screens.
- **A pairwise-overlap diagnostic on `UI.Anchor` itself.** Tempting, because that is the class that
  can genuinely overlap today. Rejected for this stage: overlap under an Anchor is usually
  *intentional*, so the finding would be noise at exactly the volume that teaches people to skim the
  suite — the failure mode the waiver list's rule 3 exists to prevent. Recorded as a candidate for a
  measured pass (count it across the corpus first, then decide), not shipped on a guess.
