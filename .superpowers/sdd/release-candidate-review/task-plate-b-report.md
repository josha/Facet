# PLATE-B — the corner disc gets its arithmetic, and the plate stops leaving the screen

Director choice **Option B** of `task-plate-design-spec.md`, built with the DIR5
review's two HIGHs and its `formCarriesMeaning` MEDIUM folded in (coordinator
addendum), plus the one-hunk comment correction the DIR5 fix round could not reach.
Landed on `435dade` — the expand-plate round's commit, which this round waited for
and then built on top of rather than racing.

## 1. Option B — the geometry, measured at both rungs

The plate reserved the close disc's own metric (36) as its RIGHT padding while its
left was `space.s` (8) — a 36px dead band trailing the content — and then pushed the
disc `space.m` (16) outside the box on both axes, a number unrelated to the disc it
carried. Both causes are gone:

* the plate's padding is **uniform `space.m`** on all four sides, so nothing in
  content flow is reserved for chrome and the content sits centred in its own frame;
* the straddle is **derived from the disc** — `space.xs + disc/2` — so the disc's
  centre and the plate's corner are the same point *by construction* at every ladder.

Measured headlessly on the shipped default package. **The coordinates below came
from this round's own probe (a 360/1920 sweep), NOT from the `plateAt()` fixture the
spec pins, which yields `110.00,30.00` and `303.00,33.00`** — corrected in fix round 1
(review LOW-6). The EQUALITY is the whole claim and it reproduces exactly in both.

| | near (`Medium`, 360 and 390 viewports) | ten-foot (`Large`) |
|---|---|---|
| plate padding, all four sides | 16 / 16 / 16 / 16 | 24 / 24 / 24 / 24 |
| straddle (plate margin top + trailing) | 22 | 33 |
| disc | 36 | 54 |
| **disc centre vs plate corner** | `160,22` vs `160,22` | `648,33` vs `648,33` |
| disc inset from the panel box | 4,4 | 6,6 |
| effective target (hit rect) | 44x44 | 66x66 |

**Zero hand literals.** Every number above is a resolution of `space.m`,
`space.xs` or `controlSizes.compact.height`, declared once in
`src/layout/expand_plate.luau` and read by the three layers that need it.

**The one number the vocabulary could not spell.** A metric name can be SUMMED
(`{ "space.xs", "space.m" }`) and NEGATED (`"-space.m"`), but it cannot be HALVED —
and half the disc is exactly the offset a disc centred on a corner sits at. Rather
than widen that grammar for one ornament, `expand_plate.discHalf(metrics)` resolves
it against the same live snapshot the solver resolves the disc's size against, and it
rides to the declaration on the plate record beside `max` — the seam that already
exists for precisely this class of number (`solver` -> `composition` -> `panelOf`).
The declaration then spends it as `{ CLOSE_INSET, discHalf }`, so the inset half of
the straddle stays a live token name and only the irreducible half is a resolved px.

**R18 is an inequality now, not a reservation.** The disc reaches `disc/2` inward
from the plate's corner; the content box's nearest point is the padded corner,
`padding * sqrt(2)` away. The guarantee is
`controlSizes.compact.height <= 2 * sqrt(2) * space.m` (36 <= 45.2 near, 54 <= 67.9
ten-foot — both sides scale together), exposed as `expand_plate.r18Clearance` and
asserted on **all nine shipped packages at both rungs** (18 checks) so a package that
breaks it reddens with the two distances named.

**The R18 fence is a CIRCLE, and that is the honest instrument.** `shape = "circle"`
paints a disc, and the one part of its bounding box that paints nothing is exactly
the corner that reaches furthest into the plate — a box-overlap sweep reports a 2x2px
incursion no player can see, and would go green on a package whose disc genuinely
covered a word diagonally. The rebuilt case measures centre-to-rect distance against
the radius, over every author node on the plate, at both rungs.

## 2. Review H2 — the plate that hung off the screen

REPRODUCED at the landed tree before the fix, and the review's own numbers: three
wrapping text rows at a 390 viewport, the plate HUGGING to 374 against a cap of **342**
(fix round 1, review LOW-1: 336 is the POST-fix cap — the straddle moved 16 -> 22 in the
same commit, which is what moved it — and the EXPAND 19 comment's 342 was the correct
one all along), panel `8..398` — 8px past the viewport, with 8 of the close disc's 36px
off-screen; at a 20px safe inset the whole disc outside the safe area.

The fixed-width arm was closed by the landed round (the chrome is subtracted from the
cap). The WRAPPING arm was not, and it takes neither route: `measure` answers the
WRAPPED width, which is always <= the cap, so `sheet` stays false — and then the
plate hugs, and a hug is the CONTENT's width, not the number that was measured.

**Fix:** the plate carries its own cap — `{ type = "minMax", max = plate.max }`, the
hug with the cap written down. `plate.max` is already the panel's allowance minus the
straddle, so a plate at the cap makes a panel exactly at the allowance and never past
it. Measured after, every content width from 30 to 60 characters: `OFF = false` at both
the zero-inset and 20px-inset arms, allowance 358 — and the panel span is `8..366` from
35 characters up, `8..360` at 30 where the hug is still under the cap (fix round 1,
review LOW-2: the safety claim was universal, the literal span was not).

The review's other half is confirmed and kept in the code: the clamp cannot save it —
`present/anchored` REPOSITIONS a surface, it does not shrink one — so a panel wider
than the space is pinned at the near edge and the far edge runs.

## 3. Review H1 — the cover's floor over its neighbours: MECHANISM CORRECTED, NOT FIXED

**The review's mechanism is wrong, measured.** It attributes the outranking to
`src/render/hit_lift.luau` ("it lifts the Clock branch past both neighbours"). With
the lift's constraint set for that host emptied, the z values do not move: First 5,
After's Last 8, Clock 9, its cover 11. The composition arranges its regions by RANK
(Before 1, After 2, Clock 3) and paint order follows the ARRANGED order, so the Clock
branch is already above both neighbours before any lift is considered. **The lift
never fires for a cover.** A `hit_lift` change was prototyped, measured to move
nothing, and discarded rather than shipped as churn.

**The defect is real and is NOT fixed.** A cover is the region's whole box, so a 44px
floor on a 20px region necessarily leaves the region: 12px above and below, the full
width, 960 px2 of `Before/First` and 828 px2 of `After/Last` — 26% of each button.

**Why it is not fixed here.** The expander is built in `renderer.luau`'s
`pushHitRects`, which inflates around the solved rect from
`effectiveHitFloor(node.class, metrics)` — a CLASS-keyed floor with no per-node input.
Every lever that could clamp it is behind a lock: the rect is the solver's region
branch (extraction-locked), the floor pass is `renderer.luau` (1,018 characters from
the 200,000 write cap, with its extraction OWED BEFORE any change of any size).
`layout_node.effectiveHitFloor` is unlocked but is handed only `node.class`, so it
cannot see the `expandTarget` the node already carries. **The one-line fix, for
whoever takes the renderer extraction:** clamp `want` to the host's parent rect, or
pass `node` rather than `node.class` and return nil for a cover.

**What DID change: the suite stops ratifying it.** EXPAND 15 asserted
`the overhang lift delivered it: true` — green *because* the theft happens, so
nothing in the suite could redden on it (the review's own objection). That assertion
is replaced by a BOUND: the overhang is the floor's own arithmetic
(`(floor - rect.h) / 2` each way) and nothing beyond it, so the exposure cannot grow
silently, and the case now carries the measurement above and the blocked fix by name.

## 4. Review M3 — `active = true` is an input sinker

`UI.Box{ active = true }` is public, documented as "an input-sinking panel (modal
backdrops)", and the adapter writes `instance.Active = value == true`. `Box` is in the
passive class set, so a reduced form holding one was classified passive, got a cover
UNDERNEATH it, and the Active Frame above sank the press — the cover unreachable over
that rect. It is `UI.Foreign`'s failure arriving through the framework's own
vocabulary, so it takes the same answer: `formCarriesMeaning` reads the PROP, and such
a form gets the chevron beside it. `active = false` is still an ordinary passive Box
(both arms pinned).

## 5. The DIR5 fix round's comment hand-off

`src/region_expand.luau`'s scrim paragraph claimed the opaque catcher came from "the
CLASS DEFAULT rule". Restated to match the artifact AND its controller
reconciliation: the catcher earns NO `facet-surface-*` tag at all, so no sheet rule
matches it and an unmatched Frame paints its INSTANCE default (0) — not a rule leaving
a value, but no rule, on the one node that covers the entire screen. The artifact's
"a plain catcher resolves to 1" measured a node a bare-CLASS rule reaches (a
TextButton), which the catcher Frame is not; the artifact's ~3-frame create-flash
window stands on its own as a separate open item. The product argument is unchanged.
One hunk, no behaviour.

## 6. Files

| file | what |
|---|---|
| `src/layout/expand_plate.luau` | the declaration: `PADDING` uniform, `CLOSE_DISC`/`CLOSE_INSET`, `discHalf`, `straddleX` = inset + half, `r18Clearance`. `SHEET_PADDING` keeps a trailing reserve — a sheet is edge-to-edge and has no corner to straddle. **FALSIFIED AND FIXED IN FIX ROUND 1 (review HIGH-1): the reserve was `CLOSE_DISC` alone, and the shared close affordance's new `CLOSE_INSET` margin moved the disc 4px (near) / 6px (ten-foot) INTO it, onto the author's words. It is `{ CLOSE_INSET, CLOSE_DISC }` now — see the fix-round section** |
| `src/layout/solver.luau` | `expandPlateDiscHalf = expandPlate.discHalf(ctx.metrics)` beside the two it already resolved |
| `src/layout/composition.luau` | courier only: reads it off the ctx, carries `discHalf` on the plate record and through the dump (the one field the dump does not round, and the comment says why) |
| `src/blueprint.luau` | uniform padding, the derived straddle margin, the `minMax` cap (H2), `formCarriesMeaning` reads `active` (M3) |
| `src/region_expand.luau` | the `Plate` type gains `max`/`discHalf`; the scrim mechanism paragraph corrected |
| `tests/region_expand.spec.luau` | EXPAND 17 rebuilt (5 cases), EXPAND 19 + the wrapping/safe-inset arm and its straddle pin re-verdicted, EXPAND 5 + the `active` case, EXPAND 15's lift ratification replaced by a bound |
| `docs/reference/api.md` | the plate paragraph redescribed (uniform padding, the derived straddle, the token inequality, the cap) |

## 7. Suite tails

| | baseline (content-pinned) | after |
|---|---|---|
| Facet | **6991 passed, 0 failed** — `git archive 435dade`, private copy | **6996 passed, 0 failed** — same copy, this round's files only |
| Rascal Rally | 3463 at dispatch | **3464 passed, 0 failed** — pinned pair (this Facet tree + RR working tree) |

Both Facet numbers are `git archive`-pinned at the same commit (`435dade`, the
expand-plate round's landing). +5 = the four new/rebuilt cases plus the `active` case.
The measured tree's Luau files are **byte-identical to what landed** (`099e28f`) — only
`docs/reference/api.md` was re-patched at land time, because that file had moved
underneath and nothing executes it.

**Confirmed after the commit**: a fresh `git archive` of `099e28f` runs **7000 passed,
0 failed**. The four cases above 6996 are the two rounds that landed between the
measured base and this commit (`9cce13e`, `c93e80e`), not this round's.
`stylua --check` clean on all seven files; `check_source_size` PASS (`blueprint.luau`
113,596 — nowhere near the band; no band file touched); `check_doc_style` PASS.
`check_comment_codes` reports `FAIL_ENVIRONMENT git ls-files` inside a `git archive`
export (no repository there); in the real tree it is **FAIL with 4 unresolvable
private codes, none of them in this round's files** — `src/client/roblox_env.luau`
(INPUT-100 x2, the flip round) and `src/layout/measure_facts.luau` (NS-A2, LTN-4, the
solver split). Reported here rather than repaired: they are those rounds' files.

## 8. Red-first and mutations

**RED-FIRST**, the new spec against unmodified `435dade`: **5 failed, 71 passed** —
`the plate's padding is UNIFORM`, `the disc's CENTRE is the plate's corner`, `the
guarantee is a TOKEN inequality`, `a WRAPPING form cannot hug past the cap`, `a Box
that declares active SINKS input`. Green after: 76 passed.

| # | mutation | red |
|---|---|---|
| M1 | the reservation restored (`PADDING.right` back to the disc's metric) | **1** — the uniform-padding case |
| M2 | the padding made asymmetric (`left = "space.s"`) | **1** — same case |
| M3 | the disc pushed into content (the straddle loses its half) | **2** — the centre case AND **the R18 fence** |
| M4 | the plate's cap dropped (`minMax` back to `hug`) | **1** — the wrapping/off-screen case |
| M5 | `active` unseen again by `formCarriesMeaning` | **1** — the chevron case |
| M6 | the padding shrunk under the guarantee (`space.m` -> `space.xs`) | **2** — the R18 fence AND the token inequality across all nine packages |

Every mutation applied to a copy of the measured tree, run, and discarded; the
unmutated control is 76 passed on the same runner.

## 9. RR lockstep

**Non-consumer of the plate geometry**, whole game folder, no extension filter:
`ExpandPanel` 0, `ExpandPlate` 0, `ExpandClose` 0. `expandTarget` has 7 hits, all in
RR's own `facet_composition_collision_contract.spec.luau`, whose positive control
builds a passive `UI.Text` ladder and pins `role == "cover"` — untouched by M3, which
only moves a form holding a `Box{ active = true }`. RR's one multi-form screen
(`FacetSponsor/ResultsScreen`) declares `expand = "none"` on every region that would
get one, so no plate is ever built in the game. The pinned pair runs **3464 passed, 0
failed**. No churn.

## 10. Concerns

1. **H1 IS NOT FIXED** and cannot be from any unlocked file — see §3. It needs a clamp
   in `renderer.luau`'s `pushHitRects`, or a node-aware `effectiveHitFloor` (two call
   sites, `renderer.luau:2092` and `:2484`, both passing `node.class`). The extraction
   that landed on 2026-08-21 was the SOLVER's, not the renderer's: `renderer.luau` is
   **198,974 characters, 1,026 from the write cap**, with its own extraction still owed
   BEFORE any change of any size — so the fix is gated on that round, not on this one.
   The suite no longer ratifies the defect, but 960 + 828 px2 of two neighbouring
   Buttons are still contested by the cover's floor.
2. **The disc's hit floor contests a corner of the plate's own content box** — the
   spec's own "one real con", and its arithmetic in the spec is off: it says ten-foot
   has none (comparing the NEAR floor's 22 against the ten-foot padding's 24).
   Measured: 6x6 px near, **9x9 px at ten-foot** (the floor's half, 33, minus the
   padding, 24). It bites only if an author puts an interactive control exactly in the
   plate's top-trailing corner; topmost wins, so the close takes it. Booked, not fixed.
3. **`discHalf` is a resolved px on a blueprint built at open time.** If the ten-foot
   ladder changed WHILE a plate is open, the straddle would be one solve stale — the
   same property `plate.max` already has, and the epoch check closes the plate on any
   anchor-rect change, which a display-class change produces. Stated rather than
   defended: the alternative is a halving term in the metric vocabulary, which is new
   public grammar for one ornament.
4. ~~**The sheet keeps the old silhouette**~~ — **THIS WAS FALSE WHEN WRITTEN**
   (fix round 1, review HIGH-1). The sheet's silhouette moved: `closeAffordance()` is
   shared by both presentations, so the `space.xs` margin that centres the disc on the
   *plate's* corner also moved it inward on the *sheet*, where no straddle absorbs it —
   4px near, 6px at ten-foot, over the author's own content, measured on both rungs. The
   reserve is `space.xs + controlSizes.compact.height` now and the tangency is restored
   exactly; the R18 fence sweeps BOTH presentations, which is the defect underneath the
   defect. See the fix-round section.
5. **Focus-ring room is asserted as the inset, not as an inequality.** The ring
   thickness lives in `style.extra.focusRingThickness`, a different authority from the
   metric snapshot, so a spec case cannot compare the two without reaching across
   them. The inset is `space.xs` (4 near, 6 ten-foot) against a 2/4 ring, unchanged
   from the spec's own arithmetic.
6. **This round waited for, then built on, the expand-plate round** rather than racing
   it: at dispatch that work was uncommitted in the shared tree and rewrote the exact
   declarations Option B changes. A prototype was measured against its working-tree
   state, then rebased onto `435dade` when it landed and re-measured end to end.

---

# Fix round 1 — the shared helper's blind spot, and the floor that was still owed

Review: `task-plate-b-review.md` (`195c5f9`) — REQUEST CHANGES, 1 HIGH, 4 MEDIUM, 6 LOW.
Every claim the review made against this round reproduced; nothing in it is contested.
Built and measured on `20148ef`.

## HIGH-1 — the disc on the sheet's words: FIXED

**Reproduced first, with the reviewer's own instrument** (circle distance from the
disc's centre to the nearest author rect, on a form that FILLS the sheet's content box):

| tree | rung | disc left | nearest author point | radius | COVERED |
|---|---|---|---|---|---|
| `20148ef` (before) | Medium | 350 | **14.00** | 18 | **true** |
| `20148ef` (before) | Large | 1050 | **21.00** | 27 | **true** |
| after | Medium | 350 | **18.00** | 18 | **false** (tangent) |
| after | Large | 1050 | **27.00** | 27 | **false** (tangent) |

The fix is the review's one-liner: `SHEET_PADDING.right = { CLOSE_INSET, CLOSE_DISC }`.
`closeAffordance()` is shared, so the `space.xs` margin that makes the plate's two
corners coincide also moves the disc inward on the sheet, where no straddle absorbs it;
the reserve was exactly `CLOSE_DISC` and nothing more. The sum restores the tangency the
comment always claimed — the content box ends exactly where the disc begins, at both
rungs, to the pixel.

**The real defect was the blind spot, and that is what the fence change addresses.** The
R18 circle sweep now runs on BOTH presentations from one helper (`r18Sweep(w, close,
subtree)`), so a change to the shared affordance is measured on every presentation it
reaches. The sheet arm additionally asserts TANGENCY rather than mere clearance —
nearest == radius, not `>=` — because the sheet's reserve is exact by construction and a
`>=` there would have gone green on the 4px incursion.

## MEDIUM-2 — the 9x9: BUILT AND MEASURED, LANDING IN THE FOLLOW-UP COMMIT

**Held out of this commit deliberately, not deferred.** The fix edits
`render/commit_walks.luau`, and the renderer round is mid-flight in that same file with
ruling R23 (its `pressableRects` is already renamed `authorPressableRects` in the shared
working tree). My one-line scope change sits on the line ADJACENT to their rename, so
git would put both in one hunk and `commit_isolated`'s marker filter would carry their
uncommitted work in with mine — the exact accident that tool exists to prevent. It lands
as its own commit once theirs is in. Everything below is built, green and mutation-tested
against `20148ef`; only the landing is sequenced.

The review is right that this was a finding rather than a footnote, and right that the
blocked argument had expired. `render/commit_walks.growWithin` (ADR-0041) is exactly the
mechanism — a floor that grows one side at a time and stops at the first pressable thing
— and it was scoped `role == "cover"`, so it never reached the close.

**Chosen fix: widen the scope, not reserve extra padding.** The close disc is framework
chrome exactly as a cover is, and R18's ruling is about what a floor LANDS ON, not about
which node asked for it — so the predicate is now "did the framework synthesize this
node", spelled as `expandTarget.role == "cover" or == "close"`, with the close declaring
`expandTarget = { role = "close" }`. A `chevron` is deliberately excluded: it reserves
its own column out of the form's measure, so its floor overlaps nothing it did not
already own. Reserving extra plate padding at ten-foot was rejected — it would move the
content box for every plate to answer a case that only exists when an author puts a
control in one corner, and it would leave the same overlap on any package whose ladder
put the floor further in.

Measured over an author Button in the plate's top-trailing corner:

| rung | close hit rect before | overlap before | after | overlap after | disc's own box |
|---|---|---|---|---|---|
| Medium | 44x44 | **36 px2** | **40x40** | **4 px2** | 4 px2 |
| Large | 66x66 | **81 px2** | **60x60** | **9 px2** | 9 px2 |

**The residue is not the floor's.** A hit rect is a RECTANGLE and the disc is a CIRCLE,
so the disc's own box already reaches `discHalf - padding` into the content box at its
corner (2px near, 3px at Large) while the painted circle clears it. The new case asserts
the honest rule — the floor grants nothing over the control that the disc's own box did
not already have — and the paint half is the circle fence above.

## MEDIUM-1 — `active` only saw the literal: FIXED

`active` is `Bound<boolean>`, so `== true` was false for every reactive spelling and
`UI.Box{ active = core:signal(true) }` — the framework's own primary idiom for a varying
prop — still got a cover underneath an Active Frame. Now: any spelling but an explicit
literal `false` carries meaning. A signal arm joins the two literal arms in EXPAND 5, so
the mutation that would have caught it now exists.

## MEDIUM-3 — the false half of the fence's justification: REMOVED

The shipped comment said a box sweep "would go green on a package whose disc genuinely
covered a word diagonally". It cannot: a circle's bounding box strictly contains the
circle, so the box test's red set is a strict superset — box fires iff `D > 2P`, circle
iff `D > 2*sqrt(2)*P`. The comment now states the proof and the corpus measurement (20
of 20 rows: box red, circle green), and keeps only the argument that is true — the false
POSITIVE is the box sweep's only error mode. The "2x2 px" is now qualified as the default
package at Medium (3x3 at Large, 1-6px across the corpus).

## MEDIUM-4a — the ring-room claim: CORRECTED IN SOURCE AND ASSERTED

The source stated "4 >= the 2px ring; 6 >= 4 at ten-foot" as universal fact. It is the
default package's arithmetic. Measured across the corpus, the ring read from the
authority that actually holds it (`style.extra.focusRingThickness`, strengthened to
`tenFootFocusRingThickness`, defaulted through `default_style` exactly as
`tokens/sheet_model`'s `fill` does):

| package | inset Medium | ring | inset Large | ten-foot ring |
|---|---|---|---|---|
| studio_neutral | 4 | 2 | 6 | 4 |
| classic_desktop | **2** | 2 | **3** | **4** |
| compact_pointer | **2** | 2 | **3** | **4** |

Concern 5's *reason* was right and its *conclusion* was wrong: the metric snapshot really
does return nil for `extra.focusRingThickness` at both rungs, so no runtime derivation
can make the inset ring-aware — but a SPEC CASE can require both authorities, which is
the standard this feature set for R18. It is asserted now, and the two short packages are
a named RATCHET checked in both directions: a third package joining reddens, and one of
them being repaired reddens too.

**Not fixed in geometry, and why.** Raising the inset moves the straddle
(`CLOSE_INSET + disc/2`) and therefore the plate's corner — the construction the director
settled — and those two packages' own `space.xs` is their decision, not the framework's.
The honest answer is the measurement standing where a change to either side walks past
it. Closing it for real needs either a ring metric the layout side can name (new theme
vocabulary) or those packages' own spacing.

## MEDIUM-4b — the headroom quoted was the loosest package's: CORRECTED

`36 <= 45.2` is `studio_neutral` (9.2px of room). The binding shipped package is
`classic_desktop`: `space.m` 8 against a 22px disc, clearing the inequality by **0.63px**
and the distance by **0.31px** — below the whole-pixel granularity a solve rounds rects
to. The source comment says so now, and the geometric sweep runs on `classic_desktop` as
well as the default, at both rungs.

## LOW findings

* **LOW-1 (the "336 cap")** — the pre-fix cap was **342**; 336 is the post-fix number
  (the straddle moved 16 -> 22 in the same commit). Corrected in report §2 below. The
  commit message of `099e28f` carries the wrong number permanently and cannot be edited.
* **LOW-2 ("every content width ... 8..366")** — 30 chars gives `8..360` (the hug is
  still under the cap there); 35-60 give `8..366`. Corrected in §2. The safety claim
  (`OFF=false` at every width, both arms) was and is correct.
* **LOW-3 (a third hand-maintained package list)** — the corpus is DERIVED now, from
  `tools/lune/theme_packages.shippable()`, and the assertion is `#packages * 2` rather
  than a pinned `checked 18`, with a non-vacuity guard on the corpus size. A tenth
  reference package enters the R18 guarantee automatically.
* **LOW-4 (the unreproducible RR number)** — rebuilt with `tools/mkpair.sh` at refs
  resolved AT measurement time; the pins ride in the pair as `PIN_FACET`/`PIN_RR`. See
  the suite table.
* **LOW-5 (the fourth outcome)** — EXPAND 19's "either answer is legal" framing now names
  it: a WRAPPING form can never reach the sheet (`sheet` is `measured > maxW` and a
  wrap's measure is `<= maxW`), so at a degenerate width the cap squeezes rather than
  promotes — measured 4px of content at a 90px viewport. Informational, no device is that
  narrow.
* **LOW-6 (the headline coordinates)** — §1's `160,22` / `648,33` came from the round's
  own probe fixture, not from the committed `plateAt()`, which yields `110.00,30.00` and
  `303.00,33.00`. The EQUALITY — the only thing the claim is about — reproduces exactly
  at both rungs either way. §1 below now says which fixture produced which.

## Suite tails, mutations, RR

| | measured |
|---|---|
| Facet baseline `20148ef` (content-pinned `git archive`) | **7036 passed, 0 failed** |
| Facet, this commit's content | **7037 passed, 0 failed** (+1: the ring-room case) |
| Facet, with the held MEDIUM-2 commit applied | **7038 passed, 0 failed** (+1: the hit-floor case) |
| Rascal Rally, `tools/mkpair.sh` at refs resolved AT measurement time | **3466 passed, 0 failed** (`PIN_FACET 7131565`, `PIN_RR c3c8d49`) |

**Red-first**, the fix round's spec against unfixed `20148ef` source: **3 failed, 75
passed** — the sheet fence, the hit floor, and the `active` signal arm. Green after.

| # | mutation | red |
|---|---|---|
| F1 | `SHEET_PADDING.right` back to `CLOSE_DISC` alone | **1** — the both-presentations fence |
| F2 | the close's `expandTarget = { role = "close" }` removed | **1** — the hit-floor case |
| F3 | `isFrameworkChrome` back to cover-only | **1** — the hit-floor case |
| F4 | `active` back to `== true` | **1** — the chevron case |
| F5 | the ring waiver emptied | **1** — the ring case, naming the two packages |
| F6 | the derived corpus truncated to neutral | **1** — the ring case's non-vacuity guard |

Six for six, one case each. F2/F3 belong to the held commit and were run in its tree.

## Concerns carried forward

1. **The close's ring room is still short on two packages** — `classic_desktop` and
   `compact_pointer` at ten-foot, 3 against a 4px strengthened ring. Now measured and
   ratcheted rather than claimed away. Closing it needs either a ring metric the layout
   side can name (new theme vocabulary, and every package would have to declare it) or
   those two packages' own `space.xs`; neither is this round's to decide.
2. **The disc's own bounding box still overlaps the content box's corner** by 2px near
   and 3px at ten-foot, because a hit rect is a rectangle and the disc is a circle. The
   painted circle clears it (the fence proves that), and the floor no longer adds to it,
   but a press in that 2x2 corner goes to the close. Irreducible without a circular hit
   test, which the engine does not offer.
3. **`SHEET_PADDING` is still the one reservation in content flow.** That is the design
   spec's ruling for B — a sheet has no corner to straddle — and it is now correct rather
   than merely kept: the reserve is the disc PLUS its inset, which is what the shared
   affordance actually spends.
