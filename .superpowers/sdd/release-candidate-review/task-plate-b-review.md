# PLATE-B review — `099e28f` against its parent `c93e80e`

**Verdict: REQUEST CHANGES.** The plate itself is right and the round's measurement
discipline is the best in this review series — every headline number reproduced to the
pixel, red-first reproduced exactly, and all six mutations bite exactly as claimed.
But the same commit moved the SHARED close affordance and put the disc **4px (near) /
6px (ten-foot) on top of the author's own content on the SHEET** — the exact R18 paint
violation this round built a fence to prevent, on the one presentation the fence does
not sweep. It is live at today's HEAD. The plate work should land; the sheet must be
fixed before release.

**Findings: 1 HIGH, 4 MEDIUM, 6 LOW.**

Everything below was measured in private `git archive` exports (`x_<sha>`), never in the
shared tree. Refs used: parent `c93e80e`, target `099e28f`, the round's own measurement
base `435dade`, and the two later HEADs `37cdb97` and `3eee945` (HEAD moved during this
review; every "still live" claim below was re-run on `3eee945`).

---

## What reproduced (the round's own claims)

### 1. Geometry — reproduced exactly, at both rungs

Probe: the spec's own `plateAt()` construction, `ringScreen(false)`, `x_099e28f`.

| | Medium | Large |
|---|---|---|
| tokens | pad 16, disc 36, inset 4, discHalf 18, straddleX 22 | pad 24, disc 54, inset 6, discHalf 27, straddleX 33 |
| plate rect | `8,30 102x112` | `150,33 153x164` |
| close rect | `92,12 36x36` | `276,6 54x54` |
| **disc centre** | **`110.00,30.00`** | **`303.00,33.00`** |
| **plate corner** | **`110.00,30.00`** | **`303.00,33.00`** |
| padding L/T/R/B | 16 / 16 / 16 / 16 | 24 / 24 / 24 / 24 |
| disc inset from panel | 4,4 | 6,6 |
| effective target | 44x44 | 66x66 |

Disc centre and plate corner are the **same point, exactly**, at both rungs — the
construction claim holds. Uniform `space.m` padding holds at both rungs. Inset and
effective target match the report.

**Zero hand literals — confirmed.** Scanning every `+` line of the `src/` diff for bare
numbers leaves exactly four: `bottom = 0, left = 0` on the disc's margin (degenerate),
`else 0` twice (documented absent-snapshot defaults), `/ 2` in `discHalf` (the
irreducible half the vocabulary cannot spell, documented at length), and `math.sqrt(2)`
in `r18Clearance` (a geometry constant, not a metric). No pixel literal survives in
shipped source. The test additions are the same: every asserted metric is a
`themeSnapshot.resolveNumber` of a name; the only bare numbers are fixture inputs
(viewport 390/1200, safe insets 20) and the 44 target floor asserted as an independent
oracle.

### 2. H2 — the parent's red and the fix, both reproduced

`x_c93e80e`, three wrapping text rows, 390 viewport, content widths 30–60 chars,
both inset arms:

```
inset 0  chars 40: plate.max=342 plateBox=374 panel 8..398 (w 390) safe 0..390
                   panelOK=false  disc 362..398  discOK=false  OFF=true
inset 20 chars 40: plate.max=302 plateBox=374 panel 20..410  safe 20..370
                   disc 374..410  discOK=false  OFF=true      <- whole disc outside
```

Plate **374**, panel **8..398** on a 390 viewport, **8 of the disc's 36px off-screen**,
and at a 20px safe inset the **whole** disc outside the safe area. The review's numbers,
to the pixel.

`x_099e28f` and both later HEADs, same sweep: `OFF=false` at every width on both arms,
panel `8..366` (= the 358 allowance at the 8px gutter), `plateBox` never above
`plate.max` (336 at zero inset, 296 at 20px). The `minMax` cap does the work; the hug is
preserved below the cap (30 chars still hugs to 330).

### 3. The R18 circle fence — asserted on 9 packages x 2 rungs, and the mutations bite

`checked 18` is real: `studio_neutral` + the 8 shippable reference packages, `Medium`
and `Large`. The geometric sweep (centre-to-rect distance vs radius over every author
node on the plate) is the honest instrument, and the report's *first* reason for it is
right — see MEDIUM-3 for the second reason, which is not.

### 4. Red-first and the mutation battery — all eight reds reproduced

Red-first, the committed spec against the parent tree: **5 failed, 71 passed**, and the
five names are the five the report lists. Control at the target: **76 passed**.

| mutation | claimed | measured |
|---|---|---|
| M1 `PADDING.right` back to `CLOSE_DISC` | 1 | **1** (uniform-padding case) |
| M2 `PADDING.left = "space.s"` | 1 | **1** (same case) |
| M3 straddle loses its half | 2 | **2** (centre case + R18 fence) |
| M4 `minMax` -> `hug` | 1 | **1** (wrapping/off-screen case) |
| M5 `active` unseen | 1 | **1** (chevron case) |
| M6 `PLATE_PADDING = "space.xs"` | 2 | **2** (R18 fence + token inequality) |

8 for 8. Every red lands on the case the report names and on no other.

### 5. Suite arithmetic — verified from archives, and it closes

| ref | measured |
|---|---|
| `435dade` (the round's measurement base) | **6991 passed, 0 failed** |
| `c93e80e` (the actual parent) | **6995 passed, 0 failed** |
| `099e28f` (the target) | **7000 passed, 0 failed** |

6991 + 4 (the two rounds that landed between base and parent) + 5 (this round) = 7000.
The report's 6991 -> 6996 pinned pair and its "+4 from `9cce13e`/`c93e80e`" reconciliation
are both correct. Note the report says it landed "on `435dade`"; the commit's real parent
is `c93e80e`, five commits later — the intervening commits touch none of this round's
files (`diff -rq` on `src/`: only `screen_paint.luau` and `styling.luau`), so the
measurement is sound, but the base named is not the parent.

`stylua --check` clean on all seven files. `check_source_size` **PASS**, with
`renderer.luau` at **198,974 (1,026 to the cap)** — the report's number exactly.
`check_doc_style` **PASS**. `check_comment_codes` now **PASS** in the real tree (0
orphans, 25 resolvable, ceiling 25) — the four private codes the report booked were
closed by later rounds, not by this one, and are no longer a finding.

### 6. RR lockstep — non-consumer confirmed, zero regression attributable

Whole-game grep, no extension filter: `ExpandPanel` **0**, `ExpandPlate` **0**,
`ExpandClose` **0**. `expandTarget` has 7 hits, all inside RR's own
`facet_composition_collision_contract.spec.luau`, whose positive control pins
`role == "cover"` on a passive `UI.Text` ladder (untouched by M3, which only moves a form
that holds a literal `active = true`). `ResultsScreen.luau:2837` forces
`spec.expand = "none"` on every multi-form region, and the contract spec pins
`expandTargets:[]` — no plate is ever built in the game.

The report's "3464 passed, 0 failed" is not reproducible (it was RR's working tree at
dispatch; RR has since gained cases). Rebuilt with `tools/mkpair.sh` against RR `c3c8d49`:

| pair | result |
|---|---|
| Facet `c93e80e` (parent) + RR HEAD | 1 failed, 3465 passed |
| Facet `099e28f` (target) + RR HEAD | 1 failed, 3465 passed |
| Facet HEAD + RR HEAD | **3466 passed, 0 failed** |

Parent and target are **identical**, so this round contributes zero RR breakage. The one
red is `facet_theme_paint_contract.spec:450` ("the ROLLBACK survives") — a Facet-vintage
mismatch against RR's expectation of the later flip round, closed by `05aeeea`, not by
anything here.

---

## HIGH-1 — the same commit put the disc ON the author's content, on the SHEET

**Severity: HIGH. Confidence: certain (measured, both rungs, live at HEAD `3eee945`).**

`closeAffordance()` in `src/blueprint.luau` is **shared by `panelOf` and `sheetOf`**. This
round added to it:

```lua
margin = { top = CLOSE_INSET, right = CLOSE_INSET, bottom = 0, left = 0 },
```

That is correct for the plate — the plate's own margin is `CLOSE_INSET + discHalf`, so
the inset is what makes the two corners coincide. On the **sheet** there is no straddle:
`SHEET_PADDING.right` still reserves exactly `CLOSE_DISC` and nothing more, and the sheet
comment (unchanged by this commit) still says *"the content box ends where the disc
begins"*. Adding a `space.xs` margin moves the disc **inward by the inset**, straight
into the reservation.

Measured, `probe_sheet2` — a rich form that fills the sheet's content box, at both rungs:

| tree | rung | disc left edge | content-box right edge | box overlap | **circle distance to the AUTHOR node** | radius | **COVERED** |
|---|---|---|---|---|---|---|---|
| `c93e80e` (parent) | near | 354 | 354 | 0 | 18.00 | 18 | **false** (tangent) |
| `c93e80e` (parent) | ten-foot | 1056 | 1056 | 0 | 27.00 | 27 | **false** (tangent) |
| `099e28f` (target) | near | **350** | 354 | **4** | **14.00** | 18 | **TRUE** |
| `099e28f` (target) | ten-foot | **1050** | 1056 | **6** | **21.00** | 27 | **TRUE** |
| `3eee945` (HEAD) | near / ten-foot | 350 / 1050 | 354 / 1056 | 4 / 6 | 14.00 / 21.00 | 18 / 27 | **TRUE / TRUE** |

The parent's construction was exactly tangent — distance equal to the radius, on both
rungs, which is what "the content box ends where the disc begins" means. This commit
broke it. The painted circle now reaches 4px (near) / 6px (ten-foot) past the content
box's right edge at the disc's own vertical centre, over the author's node.

**This is the exact violation the round's new fence exists to catch.** Run EXPAND 17's
own circle sweep over `ExpandSheet/ExpandSheetPlate/` instead of
`ExpandPanel/ExpandPlate/` and it goes red: `14.00 < 18 - 0.5`. The fence sweeps the
plate only, so the round's own instrument never looked at the presentation the round's
own change regressed.

It also falsifies three statements shipped in this commit:

* report §6 — *"`SHEET_PADDING` keeps the disc reserve — a sheet is edge-to-edge, has no
  corner to straddle, and the spec keeps its silhouette"*: the reserve is kept but the
  disc no longer respects it;
* report §10 concern 4 — *"the sheet keeps the old silhouette"*: it does not, it moved
  4/6px;
* the design spec's Option B ruling — *"the disc sits INSIDE the sheet's top-trailing
  padding (`space.m`), as shipped today"*.

**Fix (one line, no new grammar).** The metric vocabulary sums names, so:

```lua
expand_plate.SHEET_PADDING = { top = "space.m", right = { CLOSE_INSET, CLOSE_DISC },
                               bottom = "space.m", left = "space.m" }
```

and extend the EXPAND 17 R18 sweep over the sheet subtree so the fence covers both
presentations. (The alternative — a sheet-local close without the margin — costs the
sheet the focus-ring room the plate just gained, so the padding fix is the right one.)

No game impact today: RascalRally builds no plates. This is a framework release-candidate
defect on a shipped, tested fallback path.

---

## MEDIUM-1 — the M3 fix only sees the literal spelling

**Severity: MEDIUM. Confidence: certain (measured, live at HEAD `3eee945`).**

`active` is declared `Bound<boolean>` on both `BoxSpec` and `ContainerProps` — a plain
value **or a Signal/Memo**. `formCarriesMeaning` tests:

```lua
if (node.props or {}).active == true then
```

which is false for every reactive spelling. Measured:

```
literal active = true      -> chevron   (interactive[2]=true)
literal active = false     -> cover     (interactive[2]=false)
SIGNAL  active = s(true)   -> cover     (interactive[2]=false)   <-- the defect survives
SIGNAL  active = s(false)  -> cover
VStack  literal active     -> chevron
```

`UI.Box{ active = core:signal(true) }` is the framework's own primary idiom for a prop
that varies, the adapter resolves the bound and writes `instance.Active = value == true`,
and the reduced form still gets a cover **underneath** an Active Frame — DIR5's M3
verbatim, unfixed. The round's own argument ("an author asking the adapter to sink input
has declared an actionable host") applies identically to a bound value.

The conservative reading is the correct one here: a passive Box has no reason to declare
`active` at all, so `active ~= nil and active ~= false` (i.e. anything but an explicit
literal `false`) should carry meaning. Add a signal arm to the EXPAND 5 case — today both
pinned arms are literals, so no mutation can catch this.

---

## MEDIUM-2 — concern 2 is a finding, not a footnote, and `935f9a2` does not reach it

**Severity: MEDIUM. Confidence: certain (measured on `099e28f`, `37cdb97` and `3eee945`,
byte-identical results).**

The round's arithmetic is right and the design spec's is wrong. Measured on the default
package, `hitRectOf` vs the plate's content box:

| rung | close hit rect | overlap with the plate's content box |
|---|---|---|
| Medium | 44x44 | **6 x 6** |
| Large | 66x66 | **9 x 9** |

The spec's *"Ten-foot: 22 < 24 → no incursion"* compares the **near** floor's half (22)
against the **ten-foot** padding (24). The floor scales too: 66/2 = 33, minus 24 = **9**.
The round is correct to flag it.

**Answering the review's question: it is not padding-only.** The floor crosses the
padding entirely and lands **inside the content box**. Under R18 as it was actually ruled
(quoted verbatim in EXPAND 15: the 44px floor is *"EXEMPT over PASSIVE content"* and
*"BANNED over INTERACTIVE content"*), that makes it legal over text and **illegal over an
interactive control**. Measured with an interactive control in the plate's top-trailing
corner (`probe_r18hit`, HEAD `3eee945`):

```
Medium: close hit 115,0 44x44  z=14   corner Button 74,38 47x46  z=10
        CLOSE-HIT vs CORNER-PAINT overlap 6x6 = 36 px2   -> CLOSE wins
Large:  close hit 310,0 66x66  z=14   corner Button 249,57 70x69 z=10
        CLOSE-HIT vs CORNER-PAINT overlap 9x9 = 81 px2   -> CLOSE wins
```

Two overlapping actionable targets, the framework's on top, the player unable to see
which won — the tap-ambiguity class R18 was ruled on. Nothing in the suite guards it:
EXPAND 15's sweep is about the region's affordance mark, and EXPAND 17's R18 case
measures **paint** (circle vs rects), never `hitRectOf`.

**And the "blocked" argument has expired.** The renderer commit `935f9a2` shipped exactly
the mechanism this needs — a floor that grows one side at a time and stops at the first
pressable thing — but scoped it by

```lua
local target = if props ~= nil then props.expandTarget else nil
return type(target) == "table" and target.role == "cover"
```

The close is a `Button`, not a cover, so the clamp does not reach it: my probes return
identical numbers on `099e28f`, `37cdb97` and `3eee945`. The concern the round booked as
"needs the renderer extraction" now needs one predicate widened in a file that has
already been opened for this purpose. Recommend: reclassify from "booked" to "owed", and
add a `hitRectOf`-vs-interactive-author-node arm to EXPAND 17.

---

## MEDIUM-3 — the fence's stated justification contains a claim that cannot be true

**Severity: MEDIUM (documentation/reasoning, in shipped source). Confidence: certain
(proved analytically and measured on 10 packages x 2 rungs).**

The commit message, the report §1 and the shipped comment in
`tests/region_expand.spec.luau` all say a box-overlap sweep

> reports an incursion of 2x2 px that no player can see, **and — worse — would go green
> on a package whose disc genuinely covered a word diagonally.**

The second half is impossible. A circle's bounding box strictly contains the circle, so
the box test's red set is a strict **superset** of the circle test's. In this
construction, with disc `D` and padding `P`: box overlap per axis is `max(0, D/2 - P)`,
positive iff `D > 2P`; circle incursion is `D/2 - P·sqrt2`, positive iff `D > 2·sqrt2·P`.
Since `2·sqrt2·P > 2P`, the box fires **strictly earlier**. There is no configuration
where the circle is red and the box is green — no false negative is reachable.

Measured over every package the guarantee runs on, plus the stub:

```
package                  class     pad   disc   boxOvl   circIn  boxRed circRed
studio_neutral           Medium   16.0   36.0     2.00    -4.63   true   false
studio_neutral           Large    24.0   54.0     3.00    -6.94   true   false
glossy_mobile            Medium   18.0   44.0     4.00    -3.46   true   false
...
classic_desktop          Medium    8.0   22.0     3.00    -0.31   true   false
compact_pointer          Large    15.0   33.0     1.50    -4.71   true   false
```

**20 of 20 rows: boxRed true, circRed false.** The box sweep's only error mode is the
false positive, in every shipped configuration. The circle is still the right instrument
— the false-positive argument alone justifies it, and it is the argument that is true —
but the sentence that does the persuading is wrong, and it is now a permanent comment in
the spec file plus the commit message plus the report.

Two smaller inaccuracies in the same paragraph: the "2x2 px" is the **default package at
Medium only** (at Large it is 3x3; across the corpus the false positive ranges 1.0–6.0px),
and the report repeats it unqualified.

---

## MEDIUM-4 — package-independent claims verified on the default package only

**Severity: MEDIUM. Confidence: certain (measured).**

**(a) Focus-ring room — the concern-5 statement is understated.** `expand_plate.luau`
states as fact, in shipped source:

> It is what leaves room for the focus ring outside the disc (4 >= the 2px ring; 6 >= 4
> at ten-foot)

Measured across the corpus:

| package | `space.xs` Medium | `space.xs` Large | ring | ten-foot ring |
|---|---|---|---|---|
| studio_neutral | 4 | 6 | 2 | 4 |
| classic_desktop | **2** | **3** | 2 | 4 |
| compact_pointer | **2** | **3** | 2 | 4 |

On `classic_desktop` and `compact_pointer` the inset at ten-foot is **3 against a 4px
strengthened ring**, so the close's outward Border ring overruns the panel's surface box
by 1px — on 2 of the 8 shipped reference packages. At Medium both sit at exactly 2 vs 2,
zero slack.

Concern 5's *reason* is real, not a dodge: I probed
`themeSnapshot.resolveNumber(snap, "extra.focusRingThickness")` and
`"extra.tenFootFocusRingThickness"` on the metric snapshot at both rungs and both return
**nil** — the thickness genuinely lives on the style side (`styling.luau`'s `focusRing`
alias over `activeStyle.extra`), so `r18Clearance`'s runtime-guarantee shape is not
available to it. But a **spec case** can require `src/tokens/default_style` and the
snapshot in the same file and assert the inequality without any runtime plumbing, and
that is what the round's own standard ("a package that breaks it reddens in a named spec
case") calls for. Verdict: real constraint, but the claim should not be stated as a fact
in source while unchecked and false on shipped packages.

**(b) The R18 headroom quoted everywhere is the loosest package, not the binding one.**
`36 <= 45.2` (9.2px of room) is `studio_neutral`. The binding shipped package is
`classic_desktop`: `space.m` 8, `compact.height` 22, so `22 <= 22.627` — the guarantee
clears by **0.63px on the inequality, 0.31px on the distance**, at both rungs. It holds,
and the `checked 18` case does watch it. But the geometric sweep that measures *real
solved rects* only ever runs the default package, the renderer rounds rects to pixels
(`roundPx`), and 0.31px is below that rounding granularity. Recommend either a tolerance
term in `r18Clearance`'s contract or running the geometric sweep on the tightest package
as well; at minimum, stop quoting the default's headroom as the guarantee's headroom.

---

## LOW findings

**LOW-1 — the "before" cap is misquoted.** Report §2 and commit-message §4 both say
*"plate 374 against a 336 cap"*. Measured at the parent, the cap was **342**; 336 is the
**post-fix** cap (the straddle moved 16 -> 22 in the same commit, which is what changed
it). The spec's own comment in EXPAND 19 says 342 and is correct. Two of the three
records carry the wrong number.

**LOW-2 — "every content width from 30 to 60 characters: panel 8..366" is not universal.**
Measured: 30 chars gives `8..360` (the hug is still under the cap there); 35–60 give
`8..366`. The safety claim (`OFF=false` at every width, both arms) is fully correct; the
literal panel span is not.

**LOW-3 — the R18 package list is a third hand-maintained copy.** The repo has an
enumerator (`tools/lune/theme_packages.REFERENCE_ORDER`, 9 reference packages) and a
drift check (`tests/theme_package_enumeration.spec.luau`) whose CONSUMERS list names six
files. The new EXPAND 17 case hand-writes an eighth-plus-neutral list and pins
`checked 18`, which is a **count**, not a derivation — a tenth reference package would
enter `REFERENCE_ORDER`, redden the enumeration spec elsewhere, and silently escape the
R18 guarantee here with `checked 18` still green. (The omission of
`fantasy_parchment_stub` is correct: it is `reference`-role but explicitly not
shippable, and the list matches `ten_foot_metrics.spec`'s house convention.)

**LOW-4 — the RR number in §9 is unreproducible by construction.** "3464 passed, 0
failed" was RR's working tree, not a pin; `PIN_RR` is the artifact that would have made
it durable. The differential I rebuilt (parent vs target, both against RR `c3c8d49`)
shows identical results, which is stronger evidence than the absolute number anyway —
but it is evidence this review had to produce, not evidence the round left behind.

**LOW-5 — the sheet fallback is still unreachable for a wrapping form, and the cap now
squeezes instead.** `sheet` is `measured > maxW`, and a wrapping form's measure is by
construction `<= maxW` — the round names this as H2's root cause but fixes only the
overflow half. Measured at a 90px viewport: parent gave the content 30px (overflowing);
target gives it **4px** (contained but unreadable) rather than promoting to the
edge-to-edge sheet. No shipping device is that narrow, so this is informational — but the
"either answer is legal, painting past the allowance is not" framing in EXPAND 19 now has
a third outcome it does not name.

**LOW-6 — the report's headline coordinates do not reproduce from the committed spec.**
Report §1's table gives `160,22` (near) and `648,33` (Large) for both disc centre and
plate corner. The committed `plateAt()` fixture yields `110.00,30.00` and `303.00,33.00`.
The **equality** — the only thing the claim is about — reproduces exactly at both rungs;
the coordinates came from a different fixture (§1 says "`region_expand` fixture") than the
one the spec pins. Harmless, but a reader reconciling report against suite will not find
those numbers.

---

## New-breakage scan of the diff (nothing further found)

* `formCarriesMeaning`'s single call site is `blueprint.luau:1101` (`formInteractive[i]`);
  no framework-built node sets `active = true`, so no internal form flips role. Sound
  apart from MEDIUM-1.
* `elseif capped then { type = "minMax", max = plate.max }` also changes the `fills` path
  when `plate.max <= plate.w` (previously `hug`). Measured safe at every width; the
  degenerate `plate.max == 0` case at <= 40px viewports collapses the plate to 0, but the
  parent's content was already 0 wide there. See LOW-5.
* `discHalf` rides the plate record and the dump unrounded, with the reason stated. No
  golden-dump case reddens; suite is 7000/0.
* `expand_plate.STRADDLE` was removed and has no remaining consumer (`grep` over
  `src/`, `tests/`, `docs/`).
* `Plate` gains two optional fields; RR does not consume the type.
* `SHEET_PADDING` is the only remaining reservation in content flow — correctly kept per
  the design spec, incorrectly undermined by HIGH-1.

## Answering the review's H1 question directly

The round's claim that DIR5's H1 mechanism was misattributed to `hit_lift` is
independently corroborated: `935f9a2`'s own commit message reproduces the round's 960 and
828 px2 figures, and its fix is in `render/commit_walks.luau` (the floor pass), not in the
lift. The round was right to correct the mechanism, right to discard the prototyped
`hit_lift` change rather than ship churn, and right to replace EXPAND 15's
green-because-the-theft-happens assertion with a bound. That work is now superseded by
`935f9a2` and needs nothing further — except that the same clamp should be widened to
reach the close disc (MEDIUM-2).
