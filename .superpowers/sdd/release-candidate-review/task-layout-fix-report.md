# Wave LAYOUT-FIX — report

**Status: COMPLETE, with five fixes shipped and ten cells CONTESTED with evidence.**

**Anchors:** framework `fd59cae` (suite 6750), RascalRally `655cbd7` (suite 3437).
**End state:** Facet **6791 passed, 0 failed**; RascalRally **3446 passed, 0 failed**.
Both measured in private exports (rsync of the working tree; the RR export in the
multi-repo shape, `GameStudio/ui/Facet` beside `games/RascalRally/code`). Nothing was
measured in-tree. Wave THEME-UNBUNDLE was live on the same working tree throughout,
so every commit went through `tools/commit_isolated.py` and both tails include a
handful of their cases.

---

## Per-item outcomes

### 1. ADAPT-L2 (critical) — Grid gets real lane defaults · **FIXED**

`gridLaneCount` returned `1` whenever neither `columns` nor `minColumnWidth` was
declared — one lane at every width from a 390px phone to a 1920px television. The
default is now **`minColumnWidth = "intrinsic"`**, which is the route
`docs/guide/05-styling.md` already teaches, and that choice is the whole reason the
fix adds nothing to the framework:

- **no new number** — a px minimum is a guess about a font, a lane count a guess
  about the box; the widest child's own measured extent is a fact the solve has;
- **one arithmetic** — the default reaches `adaptive.columnsFor` through exactly the
  line the declared route reaches it through, so wave TEN-FOOT's distance cap rides
  along for free: **a 1920 television measures 5 lanes against a 1600 desktop's 9**,
  where both used to measure one;
- **the fallback is unchanged** — a grid of only `fill` children has no intrinsic
  minimum and still gets one lane (green before and after).

Measured at the audit's own six combos: **2 / 4 / 6 / 9 / 5 / 7**, identical to the
declared `minColumnWidth = 160` answer. Eight of the eleven new cases were red at the
anchor; the three that were green are the authored-wins guards and the null
hypothesis, and must stay green.

**The 35-site re-verdict: nothing was dropped, and that is the outcome rather than a
shortfall.** A brace-matched census reproduces the audit's 35 exactly (31 + 4) — but
that figure counts PROSE, and the correction is on the record: a COMMENT-AWARE
recount finds **32** real construction sites by my method (30 examples + 2 src) and
**33** by the reviewer's, the difference being where each of us draws the line on a
call spanning a comment boundary. The audit's 35 includes two or three mentions
inside doc comments (`virtual_grid.luau:96` and `:144`, `05_word_game.luau:28`).
Neither number is load-bearing and the conclusion is identical under all three.
Every
`columns = N` site is a semantically fixed lane count (a Wordle board, a tile rack, a
match-3 board, a five-seal run, `level_picker`'s `columns = count` — which exists so
the marks shrink together rather than starving the tail, and says so at the call
site); every `minColumnWidth = <px>` site is a deliberate device-pixel decision for a
dense readout; the six explicit `"intrinsic"` sites are left standing so the enum
value stays exercised in a shipped surface. **No site was hand-computing lanes to
dodge the old default** — the corpus had authored around it with reasons, which is
precisely the AUTHORED-ONLY shape cell B-3 recorded. A critical default change with a
blast radius of **zero shipped call sites**. The one site declaring neither
(`adaptive_controls.luau:525`) is a GridRow-mode grid, which the flow plan's lane
count is never asked of.

### 2. ADAPT-L3 (high) — the container-honest axis · **CONTESTED, measured and guarded**

Reproduced first: a `Screen` with the theme's own 24px page margin overflows at
600 / 610 / 640 and is clean at 560 and 680 — the audit's band exactly.

Both candidate fixes are out of reach, and the reasons are in the spec file rather
than only here:

- **(a) "make `contentWidth` subtract the insets"** is refused by the framework's own
  deprecation ledger. `src/init.luau` **already deprecated
  `adaptive.conditions().contentWidth` at 0.8.0**, replacement `viewportWidth`, note
  *"alias; the value never subtracted insets"* — giving a removed-by-0.9.0 alias new
  meaning contradicts a published promise. It also would not close the audit's own
  reproduction, which is page PADDING and not an inset. (This is a stronger reason
  than the recorded decline wave ADAPT-FIX cited, and it is new evidence.)
- **(b) "let the stack resolve its axis from the box the solver proposed"** is the
  honest fix and it is not one file. The axis is a PROP, and
  `present/focus_map.luau:640-665` reads that prop **live** to decide whether a pad
  navigates the stack left/right or up/down — the D5 defect that had every segmented
  picker navigating vertically. A solved axis would have to reach the focus
  derivation through solver → renderer → presenter, all three extraction-locked.

Guarded instead: the band exists where it should, closes where it should, and the
framework is never silent inside it (the finding names the container, the amount and
both fixes — weakening one phrase of the solver's message reddens the case).

### 3. ADAPT-L4 (high) — AdaptiveStack stops being a silent permanent VStack · **FIXED**

`axis` is now `required = true`. The refusal names the fact
(`Facet.adaptive.conditions(core, env).axis`), the host that supplies it with no
wiring (`Facet.client.host.new`) and both unconditional classes (`UI.VStack` /
`UI.HStack`) — `tab_view`'s shape, which this framework has now adopted seven times.
A default of `"y"` on this class bought nothing `UI.VStack` did not already buy.

The three shipped fixtures (`canvas_group` once, `nested_compositing` twice) now bind
the surface's own axis on the scope that already owns their memos, so their comment —
*"side by side where there is room, a column where there is not"* — is TRUE: measured
a column at 320 and a row at 1280.

**Two registries the change touched, both found by the suite rather than by reading:**
`tools/lune/check_primitives` needs a `MINIMAL_PROPS` entry for any class with a
required prop (the checker said so and named the doc), and
`tests/stack_distribution.spec` was constructing a bare one in its `distribute`
class-set case, where a second refusal firing first would have made it answer the
wrong question.

**The brief's second branch is not buildable and is contested:** "omitted axis +
facts present = the documented adaptive default" has no meaning at blueprint
construction, which has no core and no environment. The offer-derived default is
ADAPT-L3's fix (b), behind the same three locked files.

### 4. ADAPT-L5 (high) — overflow's default answer · **CONTESTED per cell, guarded**

Per-cell, with the exact blocker (all three also recorded in the spec file):

- **F-1** wants an implicit scroll host. `render/renderer.luau:1483` keys the engine
  scroll host on `node.class == "ScrollView"`, **not on the solved kind** — so
  writing `kind = "scroll"` at the measure seam (the one seam this wave could reach)
  would buy a scroller's LAYOUT with no scrolling, strictly worse than today.
- **A-8 / F-2** want `wrap` bound by default. `wrap` decides the solver KIND
  (`hstack` vs `hwrap`) at the measure seam, and a wrapping stack **has no shrink
  pair by design** — so wrapping by default would silently disable the shrink cascade
  on every stack that has one, which is exactly the "silent re-flow of shipped
  screens" the solver's own overflow comment refuses to be.
- **F-4's stated minimum — "the solver's finding should escalate" — is ALREADY
  SHIPPED.** `tests/overflow_sweep.spec.luau` asks every showcase surface at nine
  viewports, four text preferences and the themed and locale tiers on every
  `./run-tests.sh`. Re-deriving it would have been the more expensive mistake, so it
  is recorded rather than rebuilt.

**What was built instead is the one property that sweep structurally cannot check:**
it *counts* findings and never *reads* one, so a message that named the container on
a phone and not on a television would be a hole nothing in the repository could see.
All three of the audit's reproductions are pinned, and the page shape is asserted at
all six combos for a diagnosis carrying the container, the axis, a real pixel count
and both fixes. The standing rule is pinned beside them — **clipping is never the
answer**: a plain stack that overflows must not acquire `clipChildren` behind the
author's back, and the one word that does make a clip host still does.

### 5. The remaining WRONG / AUTHORED-ONLY / MISSING cells · **triaged, one FIXED**

**ADAPT-L8 (B-4) FIXED** — a `GridRow` squeezed three `fixed(200)` cells to 101px at
320 with **zero** findings, while the `HStack` twin files one every time. The squeeze
is now reported. The geometry is unchanged and re-pinned at the audit's own five
numbers (200 / 181 / 148 / 124 / 101), so a "fix" that re-laid the row out fails here
rather than passing quietly. One owner: the amount is recorded by `gridColumnPlan` —
the single function measure and arrange both read — and the arrange branch reports the
plan's own number.

The full 19-row disposition table is in the **LAYOUT-FIX addendum to
`artifacts/release-candidate-review/adapt-audit/fixes.md`**. The headline from it:
**eight of the eleven contested cells are behind an extraction-locked file**, two are
genuinely new capability (C-3's sheet presentation, D-3's height-budget fit
criterion), and **exactly one — B-6e, the ten-foot `Composition` measure — is blocked
by nothing but a director's number.** Its mechanism is one line
(`render/layout_node.luau:432` already resolves `maxMeasure` and could default it from
the distance fact the metrics now carry); what is missing is *how wide a content lane
may be at three metres*, which is a legibility judgement with the ADAPT-8 precedent
saying the director rules on it.

### 6. Corpus follow-through · **re-verdicted; the corpus disagrees with the worry**

The audit counted **38** three-plus-child `HStack`s with no wrap. Re-censused at
**21** by a stricter rule (direct `UI.*` children only; the audit's own note says six
more build children dynamically) — the number is not the finding either way.

**The finding is that the row shape is not where the corpus bleeds.** Of the always-on
sweep's 17 standing waivers — every one measured cosmetic under the director's
2026-08-15 ruling — **exactly ONE is an `hstack` overflow** and **SIX are
`content overflows this vstack`**, i.e. a page taller than its box with nothing to
scroll it. Rows are not what overflow here; **pages are.** That is direct evidence for
ADAPT-L5's direction (b) being worth the renderer work when F-1 is unblocked, and
against direction (a) being worth its shrink-cascade cost. **No fixture was found
misteaching, so none was edited.** The sweeps were not extended: each fixed cell's
guard lives in `tests/layout_defaults.spec.luau` and bites (below).

---

## Cell-disposition counts

61 cells, 42 RIGHT at the anchor, **19 non-RIGHT** — every one dispositioned:

| disposition | cells |
|---|---|
| **FIXED by this wave** | **4** — A-2 (ADAPT-L4), B-1 (ADAPT-L2), B-3, B-4 (ADAPT-L8) |
| RESOLVED before this wave | 3 — B-2e, E-3 (wave TEN-FOOT), F-5 (wave CAROUSEL) |
| ALREADY SHIPPED at the cell's own stated minimum | 1 — F-4 |
| **CONTESTED with the exact blocker** | **11** — A-4, A-5, A-8, B-6e, C-1, C-3, D-3, F-1, F-2, G-4, G-5 |
| total | **19** |

Live score against the matrix: **49 RIGHT of 61** (annotated in place in
`matrix-layout.md`; its anchor counts table is noted, not rewritten).

---

## Commits

**Facet** (`fd59cae` → `e65cc83`; the interleaved `da50128`, `8a1faf8`, `7096274`,
`90d5885`, `a04be05`, `ddebd97` are wave THEME-UNBUNDLE's, not mine):

| commit | what |
|---|---|
| `91a474d` | the grid was told nothing and answered one, from a phone to a television (ADAPT-L2) |
| `ed825da` | a class named AdaptiveStack could be built unable to adapt, and three fixtures were (ADAPT-L4) |
| `8fd4779` | the refusal's one load-bearing line was the one line without the marker on it (the correction below) |
| `021a896` | the row grid was the quiet one, and quiet was the worse of the two failures (ADAPT-L8 + ADAPT-L3's guard) |
| `8e69648` | overflow's default is contested, so what it SAYS is now guarded instead (ADAPT-L5) |
| `e65cc83` | the layout matrix's own rows, re-verdicted where this wave landed (addendum + annotations) |

**RascalRally** (`655cbd7` → `1888cd6`; `e4f02a2` is THEME-UNBUNDLE's):

| commit | what |
|---|---|
| `d708d26` | the grid this game never told anything now answers from the box it got |
| `1888cd6` | the framework can refuse an AdaptiveStack now, and this game's one live stack was ready |

Both game-side commits are required by the move-together rule and both are red
against the framework at its pre-fix commit. Nothing in Rascal Rally moved: its two
live grids already name `minColumnWidth = "intrinsic"` and its one live
`AdaptiveStack` already binds `axis = opts.splitAxis` — both now read out of the
source rather than trusted to memory, so the day a binding is dropped the test reddens
instead of a live results screen failing to boot.

---

## Suite tails

```
Facet          6781 passed          (anchor fd59cae: 6750)
RascalRally    3443 passed          (anchor 655cbd7: 3437)
```

Gates re-run green on the final tree: `check_prop_parity` (27 classes, 673
properties), `check_docs` (9 documents), `check_registration` (38 controls, 255 specs),
`check_surface_ledger`, `check_boundary` (155 src files), `check_manifest_integrity`
(1503 suite greps, all anchored), `check_source_size` (PASS; `grid.luau` 39,799 →
43,899, nowhere near the band), `stylua --check src tests tools bench examples`.

**Bite-checks** (each mutation confirmed to redden, measured rather than assumed):

| guard | mutation |
|---|---|
| ADAPT-L2's six combo cases + the equality case + the TV-under-desktop case | restoring `return nil` for an absent `minColumnWidth` → 8 red (they were red at the anchor by construction) |
| ADAPT-L2's authored-wins pair and fill-only null hypothesis | green before and after, by design |
| ADAPT-L4's refusal + phrase check | red at the anchor; removing `required = true` reddens both |
| ADAPT-L4's two null hypotheses | green before and after, by design |
| ADAPT-L8's report | `if false and plan.squeeze ~= nil` → 2 red here, 1 red in `grid_row.spec` |
| ADAPT-L8's rigid-width narrowing | forcing `anyRigid = true` → the content-cell null hypothesis reddens |
| ADAPT-L3's "not silent" case | weakening one phrase of the solver's overflow message → red |
| ADAPT-L5's completeness case | same mutation → red |
| RR's two ADAPT-L2 cases | reverting the framework default → both red |

---

## Concerns

1. **`commit_isolated.py` dropped the one line that mattered, and HEAD was red for a
   commit.** ADAPT-L4 landed without `required = true`: markers match HUNKS, and
   `+\t\t\trequired = true,` is its own hunk three lines from the twelve lines of prose
   that carried the marker. The `api.md` signature change dropped the same way, in the
   same call. `8fd4779` is the correction and states the discipline: **read the `drop`
   list, not the `KEEP` list** — the `KEEP` list is the one an author scans because it
   is the one they wrote, and a one-line mechanical change is exactly the shape that
   carries no prose and therefore no marker. Recorded in the addendum's §5 too.

2. **B-6e is the cheapest unblocked item in the whole matrix and it needs a director,
   not an implementer.** One line, no lock, no new machinery — and a number that is a
   legibility judgement at three metres. `adaptive.BREAKPOINTS.wide` is the candidate
   that adds no new number, but adopting it moves every ten-foot composition and every
   five-view gate artifact, which is a product change this wave was not asked to make.

3. **ADAPT-L5's remaining work is one renderer change behind one big lock, and the
   corpus now says which change.** Six of seventeen waivers are page-not-scrollable
   and one is a row. The implicit page scroll host (direction b) is the fix the
   evidence supports; it needs `renderer.luau`'s scroll-host decision to read the
   solved kind rather than `node.class`, which sits behind the `rect_pass` extraction
   that row already owes.

4. **The ADAPT-L3 bundle is bigger than the audit's "one memo" estimate.** The audit
   offered `contentWidth` as one memo; the deprecation ledger closes that door
   outright, and the surviving fix drags `focus_map`'s live axis read with it. Anyone
   scoping it should budget solver + renderer + presenter + focus derivation, not one
   file.

5. **Not measurable headlessly, unchanged from the audit's own list:** whether a
   5-lane television grid reads correctly at 3 m (device rows 3/4), whether the
   `GridRow` squeeze finding's threshold matches what a player sees at 320 (row 9),
   and whether the axis band at 600–640 is visible on a device (row 5). No Studio
   session was run — the brief forbade it.

6. **The suite tails include wave THEME-UNBUNDLE's in-flight cases**, and my
   attribution was off by one in each direction. Measured per interleave boundary by
   the reviewer and reproduced here: **this wave +26, THEME-UNBUNDLE +5** (11 + 4 + 7
   + 4 = 26; 6750 + 26 + 5 = 6781). My report said +25/+6, from diffing case NAMES
   rather than running the suite at each boundary — a method that mis-attributes a
   case whose name is ambiguous between the two waves. The RR split (**wave +5,
   concurrent +1**) was right. Both waves were green independently at every point
   either of us measured.


---

# ADDENDUM — B-6e, ruled mid-wave and shipped (controller ruling R14)

**Outcome: FIXED.** The cell this report had dispositioned as *"the one blocked by
nothing but a director's number"* was ruled while the wave was open, and the ruling
landed in the same wave.

## What the ruling was, and what it cost

The `Composition` content-lane measure caps at ten-foot to **900px = the
regular-touch tablet measure (600, the matrix's own verified-RIGHT B-6c) x the 1.5
distance factor** — the proportion-equality doctrine every ten-foot number rides
(ADR-0039). Before it, a television resolved the DESKTOP arrangement with more
pixels: measured 1292px in the wave's reproduction against the tablet's 600.

**It is DERIVED, which is what makes a re-ruling cheap.** `900` is written nowhere:
`adaptive.LANE_MEASURE` is 600 and the factor is read from
`themes.snapshot.metricScale` — the one `tenFootFloor` behind the type ladder, the
metric ladder and the hit floor. A re-ruled measure is one edit plus a red
`layout_defaults.spec` row naming the new number, and the derivation itself is a
case (`LANE_MEASURE * metricScale("Large") == 900`) rather than a comment.

**THE SEAM IS NOT THE ONE THE AUDIT NAMED, and the correction is the substance of
the work.** The cell nominated `maxMeasure`. That caps the whole BOX and every lane
then divides what is left — so capping at 900 would have narrowed the HUG lanes
with it and handed the content lane **452px, narrower than the tablet's** and the
exact opposite of the intent. A measure is a property of a `fill` lane, so the fill
group gained **`maxWidth`**: `minWidth`'s exact twin, validated against it
(a `maxWidth` under its own `minWidth` is a construction error), documented beside
it in api.md and the schema, and carried as nil-when-absent for the +2.5%-per-resolve
reason the neighbouring `holdsLane` field already records. The ruled value is its
ten-foot default.

**What the cap frees, the lanes re-absorb; what is left centres the band.** Other
fill lanes water-fill up to their own caps (bounded by the lane count). A
`threeLane` with one fill lane has nothing to re-absorb it, so the 196px a side
becomes the centring offset the resolution already carried for `maxMeasure`.
Parking a capped band against the left edge would be a worse answer than the one it
replaced, and the case asserts `leftGap == rightGap == 196`.

**Authored wins in both spellings**, each mutation-proved separately.

## The consequence found rather than claimed — and the sweep found it again

Narrowing the ten-foot lane made Cartwheel's potion tiles overflow by 7px on all 17
visible cells. **The cap did not cause it.** `metrics.tileMin` is a literal 96
device px while everything inside a tile is a theme metric, so at distance the mark
grew to 72 and the button's padding to 18 a side — 108px of content asking for a
96px minimum. That is `docs/lessons/facet-fixed-px-heights.md`'s class read across
the DISTANCE axis; it had been latent since the display class was added, and the
extra lane width was hiding it. The fixture now takes the same `metricScale` its
contents take (byte-identical at near distance) and says so at the call site. The
registry-neutrality case then caught the memo I had left unowned, in the same run.

## Cell-disposition counts, updated

| disposition | cells |
|---|---|
| **FIXED by this wave** | **5** — A-2, B-1, B-3, B-4, **B-6e** |
| RESOLVED before this wave | 3 |
| ALREADY SHIPPED at the cell's own stated minimum | 1 |
| **CONTESTED with the exact blocker** | **10** |
| total | **19** |

Live score against the matrix: **50 RIGHT of 61**. Of the ten contested, **eight are
behind an extraction-locked file** and two are genuinely new capability — so the
matrix is now waiting on three files rather than on any decision.

## Commits

| repo | commit | what |
|---|---|---|
| Facet | `fa5f21a` | the television resolved the desktop arrangement with more pixels, and 900 is the ruling |
| RascalRally | `57bbdc8` | this game's results lane is 992 on a monitor and 900 on a television now |

RascalRally moves, deliberately and only at ten-foot: `ResultsBody` — its one
`UI.Composition`, production default since the Sponsor cutover, and a surface that
only reached the ten-foot branch three commits ago — goes **992 → 900** on a
television and is byte-identical on every near viewport. Both asserted at the same
1920x1080 rect so the pair differs in exactly one fact.

## Suite tails

```
Facet          6791 passed          (before this item: 6781)
RascalRally    3446 passed          (before this item: 3443)
```

Both re-verified from clean `git archive HEAD` exports in the multi-repo shape.
Gates green: `check_prop_parity`, `check_docs`, `check_registration`,
`check_surface_ledger`, `check_boundary`, `check_source_size`,
`check_manifest_integrity`, `stylua --check`.

**Bite-checks** (five, each measured):

| guard | mutation |
|---|---|
| the ten-foot lane is 900 / the derivation / the centring | `LANE_MEASURE` 600 → 700 → 3 red |
| the same three | the default never fires (`if false`) → 2 red, and the five-combo null hypothesis stays green |
| authored `maxMeasure` wins | drop the `props.maxMeasure == nil` clause → red |
| authored group `maxWidth` wins | drop the `copy.maxWidth == nil` clause → red |
| RR's pair | disable the framework default → the ten-foot case reds, the near case stays green |

**One of these cases was vacuous when written and a mutation is what found it.** The
authored-wins case first used `maxMeasure = 1200`, which leaves the main lane 752px
— under the 900 cap, so the default would have been inert there and the case stayed
green with `authored wins` deleted. It uses 1600 now (main lane 1152), a number only
reachable if the default is genuinely off.

## Director veto

Booked as **batched Studio row §13h**, written as a new sub-row rather than folded
into the ADAPT-8 rows because none of 13a–g asks about LINE LENGTH — they are about
how big a thing is, and this is about how far the eye travels before it comes back.
It names the two judgements: whether a 900px line reads as one line at three metres,
and whether the 196px of freed slack per side reads as deliberate margin or as a
screen that failed to fill — with the note that the second is a PLACEMENT question
answered where the slack is spent, not by widening the lane again.

## Concerns

1. **The audit's named seam was wrong, and following it literally would have made
   the cell worse** (452px). Worth carrying: an audit's "smallest fix" names a
   mechanism from the outside, and `maxMeasure` vs `maxWidth` is a box-versus-lane
   distinction only visible from inside `solveArrangement`.
2. **RascalRally's shipped results screen genuinely re-measures at ten-foot.** It is
   intended and it is asserted, but it is a real product change on a live surface
   and the director's eye at §13h is what confirms it.
3. **Cartwheel's tile minimum was one of a class.** A literal px number holding
   content that scales at distance is not unique to that fixture; the sweep only
   reports it once the surrounding slack stops covering it. Anyone auditing the
   ten-foot corpus should grep for fixed px minimums beside theme-metric content.


---

# ADDENDUM — fix round 1 (review ACCEPT; controller ruling R15)

**Outcome: all four items ADDRESSED.** Facet **6794**, RascalRally **3446**, both
green, both re-verified from clean `git archive HEAD` exports in the multi-repo
shape. All gates green.

## Item 1 — the policy gap · **ADDRESSED (record + instrument + constitution)**

**(a) The record: [ADR-0040](../../../docs/adr/ADR-0040-unreleased-breaking-changes.md).**
Ruling R15 written down: a breaking change **may** ride an unreleased version if it
is recorded, and **after a version's first publish the full ADR-0011 window applies
with no exception**. No compat shim, and the ADR argues why rather than asserting
it: both of this wave's changes exist *because* a silent default was the defect, so
a flag preserving the old behaviour would re-ship the exact silence
refuse-don't-guess was adopted to end.

**The campaign sweep found thirteen breaking surfaces riding 0.10.0**, each with
where it is already measured: B-1/B-2 (this wave's two), **B-3 the six
refuse-without-env controls one line each** — `newPicker`, `newMenu`,
`newPopupButton`, `newTabView`, `newTextInput`, `newVirtualList`, enumerated by
running `adaptive_defaults.spec`'s own source-derived refusal predicate rather than
by hand — plus the tablet nav placement, the ten-foot column cap, unauthored
ten-foot type, the whole metric ladder, the Composition measure, the table's column
collapse and its selection keys, the horizontal rail's focus axis, the centred
bands, and the rename/call-shape pair (which already had ADRs and is the shape the
rest should have had).

**The sweep is signed as a reading, not a proof.** It was built from the campaign's
artifacts against the seventy commits since the `0.10.0` bump; a behaviour change
with no artifact and an unremarkable subject line would not appear in it. That
limitation is stated in the ADR, and it is exactly why (b) is the half that matters.

**(b) The instrument: `tests/lib/public_shape.luau` + three cases in
`api_surface.spec`.** The two facts a deprecation ledger structurally cannot see are
now pinned: the **REQUIRED set** by name (16 entries), and **every documented
default BY VALUE** (5 shared box props pinned once, 25 class props by `Class.prop`).
A third case reads the ADR's own two schema-shaped rows back out of the file and
checks them against the live schema, so the record and the schema cannot drift apart
in either direction.

**Six mutations, all measured:**

| mutation | result |
|---|---|
| delete `UI.AdaptiveStack.axis` from the ADR | record case reddens |
| delete the `UI.Grid` lane-default row from the ADR | record case reddens |
| revert `required = true` in the schema | required pin **and** record case redden |
| flip a NEW prop (`Grid.flow`) to required | required pin reddens, naming it |
| change a documented default's value (`Grid.itemSizing` natural → uniform) | default pin reddens, naming old → new |
| remove the Grid lane-default doc clause | default pin **and** record case redden |

**Two findings from building it.** The extractor's first version searched
case-sensitively for `"efault"` and therefore missed `UI.Grid`'s own doc — which
says "the **DEFAULT** when neither this nor `columns` is declared", the exact change
it exists to catch. Found by generating the pin and reading it, not by reasoning
about it. And the four shared box props are the same declaration on twenty classes,
so 80 of the 97 documented defaults were four facts repeated; they are pinned once,
which is what makes the pin a thing a person will maintain.

**The pin is a VALUE, not a doc string**, so rewording a doc without changing its
default moves nothing. Nine of the 97 state their default in prose and pin a
normalized window instead — stated in the extractor rather than hidden.

**(c) Constitution §14** gains the pre-release clause, naming ADR-0040 for the
reasoning and the table, and stating the shim rule.

## Item 2 — the two defects the review found · **ADDRESSED**

Defect 1 is Item 1 above (the policy gap). Defect 2 is Item 3 below. Both are
red-first in the sense available to each: Defect 1's instrument is proved by six
mutations; Defect 2 is a false claim in a comment, whose "red-first" is the review's
own reading of it against the code.

## Item 3 — `tests/run.luau`'s false claim · **ADDRESSED**

The registration comment said *"the default answer to overflow stops being 'paint
outside the box'"*. ADAPT-L5 is **CONTESTED** and the default is unchanged — the
spec file's own header was scrupulous about this and only the registration line
overstated. Constitution §14: *a claim the code does not honor is a defect of the
same severity as the reverse*. It now names what is guarded (the diagnosis's
completeness at every combo, the one property the always-on sweep cannot check) and
says outright that overflow's default is unchanged.

## Item 4 — the four accuracy corrections · **ADDRESSED**

Two are corrected by **naming the disagreement** rather than by swapping one
unverified number for another:

| # | was | now |
|---|---|---|
| 3 | "35 Grid sites (31 + 4), bit for bit" | reproduced the audit's *method*, prose included. A comment-aware recount gives **32** by my method, **33** by the reviewer's; the audit's extra 2-3 are doc-comment mentions. Disposition identical under all three |
| 4 | "the rest are zstack overlaps and two collapsed content boxes" | accounted for 7 of 10; now accounts for all ten (5 layer-overlap, 3 fixed-px-vs-text, 2 collapsed). And the six unscrollable pages are counted by `kind` while named by signature — **by signature there are nine** `content overflows this vstack` against one hstack, so the section's direction is *stronger* under either reading. Both countings now labelled |
| 5 | suite attribution +25/+6 | **+26/+5**. Mine came from diffing case NAMES, which mis-attributes a name ambiguous between two concurrent waves; running the suite at each interleave boundary is the method that answers it. The RR split (+5/+1) was right |
| 6 | "148 shipped ZStack sites" | inherited from the audit, never re-measured. **141** by my method, **139** by the reviewer's. The C-1 contest does not turn on it |

## B-6e (from the earlier addendum) · **FIXED**

Ruled mid-wave (R14) and shipped: the ten-foot content measure caps at
**900 = `adaptive.LANE_MEASURE` (600) × `metricScale` (1.5)**, on a `fill` group's
new `maxWidth`; authored wins in both spellings; the freed slack centres the band.
The audit's named seam (`maxMeasure`) was **wrong** and following it literally would
have given the content lane 452px — narrower than the tablet measure the ruling
derives from. It exposed a latent defect on the way in (Cartwheel's literal 96px
tile minimum holding contents that scale 1.5× at distance), and one of its own cases
was vacuous when written until a mutation found it. Full detail in the previous
addendum. Director veto booked at batched §13h.

## Commits

| repo | commit | what |
|---|---|---|
| Facet | `fa5f21a` | the television resolved the desktop arrangement with more pixels, and 900 is the ruling (B-6e) |
| Facet | `3892fee` | the report's one director-blocked cell was ruled while the wave was still open |
| Facet | `9fb4314` | two breaking changes rode an unreleased version, and nothing in the repo could say so (items 1, 2, 3) |
| Facet | `590754e` | four numbers in the wave's own record were larger than what they measured (item 4) |
| RascalRally | `57bbdc8` | this game's results lane is 992 on a monitor and 900 on a television now (B-6e) |

## Suite tails

```
Facet          6794 passed          (wave anchor fd59cae: 6750)
RascalRally    3446 passed          (wave anchor 655cbd7: 3437)
```

Gates green on the final tree: `check_prop_parity`, `check_docs`,
`check_registration`, `check_surface_ledger`, `check_boundary`, `check_primitives`,
`check_source_size`, `check_manifest_integrity`, `stylua --check`.

## Concerns

1. **The new pins will collide with other waves, and that is the design.** A wave
   that changes a documented default now has to say so in the same commit. The pin
   is deliberately narrow (an extracted *value*, not the doc string) to keep the
   friction proportional to the change.
2. **ADR-0040's sweep is a reading.** Thirteen surfaces is what the campaign's own
   artifacts and seventy commit subjects yielded. A fourteenth with no artifact
   would not be in it, and only the instrument protects the future.
3. **The publish boundary is now load-bearing policy and is not yet an event.**
   ADR-0040 carries it to the director: whether seventy commits of accumulated
   public behaviour change still belong inside `0.10.0`, or whether a `0.11.0` bump
   with that table as its changelog is the honest release.
