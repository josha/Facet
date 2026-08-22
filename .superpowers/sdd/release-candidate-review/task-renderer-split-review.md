# task-renderer-split — review

**Verdict: ACCEPT WITH FIXES.** The split is behaviour-identical and the proof
survives an independent re-run: the 800-tree oracle is byte-identical at 328,839
lines across the whole chain, the verdict set loses nothing, the hit-floor rule
reproduces red-first at 960/828 px², and the brief's prescribed hard clamp
reproduces as *wrong* on exactly the five viewports the report names. The
engineering is sound and the paperwork is unusually honest about its own
numbers — with one class of exception, and it is the finding of this review: the
blast radius of the shipped rule was measured on ONE fixture at ONE viewport, and
on the suite's own swept matrix it is roughly forty times larger, with half of it
caused by the framework blocking itself.

| | |
|---|---|
| Commits reviewed | `4cc5cb0`, `935f9a2`, `5c407cc`, `2e6c7d9`, `753e088` |
| Parent chain | `b5732d0` → `4cc5cb0` → (6 other agents' commits) → `935f9a2` → (2) → `5c407cc` → `2e6c7d9` → `753e088` |
| Facet HEAD at review | `3eee945` (suite 7,036 / 0) |
| RR pin | `c3c8d49` (RR HEAD, confirmed identical sha) — 3,466 / 0 |
| Findings | **0 blocker, 1 major, 5 medium, 8 minor** |

All measurement in private `git archive` exports under
`scratchpad/rsplit-review/<sha>/`; RR through `tools/mkpair.sh` with refs
resolved at call time. The shared tree was read-only for this review.

---

## 1. What reproduced, exactly

### 1.1 Suite and verdict sets — independently re-run at every commit

| ref | suite | note |
|---|---|---|
| `b5732d0` (parent) | 7,005 | pre-split baseline |
| `4cc5cb0` | **7,021** | +16, **zero removals** |
| `6d6fd3d` (Phase B parent) | 7,022 | |
| `935f9a2` | 7,035 **+ 1 FAILED** | the marker-filter miss |
| `05aeeea` | 7,035 + 1 FAILED | another agent's commit, on the red |
| `5c51cb4` | 7,035 + 1 FAILED | another agent's commit, on the red |
| `5c407cc` | **7,036** | repaired |
| `2e6c7d9` / `753e088` / HEAD | **7,036 / 0** | |

**Phase A verdict-set diff (`b5732d0` → `4cc5cb0`): zero removals, sixteen
additions, every one the seam spec's own.** Reproduced line-for-line off my own
runs, not the report's. The report's "7,000 → 7,016" is the same +16 measured
from a different baseline (`aa46cda`), and the delta matches exactly.

**Phase B verdict-set diff (`6d6fd3d` → `935f9a2`): exactly ONE removal**, and it
is the round's own seam-spec case renaming itself *twenty* → *twenty-one*, which
is what the report discloses. Fifteen additions. Nothing else moved.

**No existing spec was edited in Phase A.** `4cc5cb0` touches
`tests/lib/renderer_source.luau` (the instrument) and `tests/run.luau`
(registration) and nothing else under `tests/`. Phase B edits
`tests/region_expand.spec.luau` (EXPAND 15), disclosed separately, and that edit
*strengthens* the case — "bound the overhang" becomes "assert the list of thefts
is empty". Held files (`native_style.luau`, `screen_target.luau`,
`native_style_default.spec.luau`, `overflow_guard.luau`, `overflow_waivers.luau`,
`mkpair.sh`) were untouched by all five commits: confirmed against
`git show --name-only`. No concurrent work was swept in.

### 1.2 The differential oracle — re-run, 4 pins, 3 negative controls

The harness was recovered from the scratchpad and run by me at four pins:

```
b5732d0  800 cases, 328839 lines   ┐
4cc5cb0  800 cases, 328839 lines   ├─ diff exit 0 on ALL pairs
935f9a2  800 cases, 328839 lines   │  (pre-split↔A, A↔B, pre-split↔final)
753e088  800 cases, 328839 lines   ┘  0 ERROR, 0 REFUSED, rerun deterministic
```

**328,839 lines, byte-identical, confirmed.** The claim holds for Phase A *and*
across Phase B and both exemption sweeps.

Three negative controls, my formulations (the report's mutation text is not
recorded, so the specific line counts 456/6/86 are **not reproducible as
stated**):

| control | my mutation | lines differing |
|---|---|---|
| the floor stops inflating | `if false and (r.w < floor …)` | 28,676 |
| the indicator opt-out ignored | `indicators = "auto"` | 990 |
| the text scale dropped | `scale = 1` at the walk head | 6,223 |

Non-vacuity is confirmed *a fortiori*. One structural caveat worth recording:
the generator's vocabulary contains **no `UI.Region` and no `expandTarget`**, so
Phase B's byte-identity is a control against the rule firing where it should not
(it would catch a broken `isCover`), not evidence that it fires where it should.
The report's phrase "the rule reaches covers and nothing else" gets the second
half from the oracle and the first half from the spec.

### 1.3 The hit-floor rule — red-first, mutations, and the F1 control

**Red-first reproduces at the review's numbers.** The final spec run against an
unmodified export of `4cc5cb0`:

```
✗ it takes NO part of either neighbouring Button — 960 and 828 px2 become 0
    expected First 960 px2 to be First 0 px2
✗ ...and in THIS fixture there is no room at all, so it grows nothing
    expected outside its region: 9360 px2, expander: table … to be … 0 px2, expander: nil
```

Both numbers — 960, 828 — and the 9,360 px² outside-the-region figure land
exactly. At `753e088` the same spec is **14 passed**. (The report's "6 failed, 2
passed" is not reproducible: the final spec is 14 cases and gives 10/4 at the
parent. The spec grew during the mutation work, so the count is a chronology
artefact rather than an error — see MINOR-1.)

**Eight mutations, all bite.** Built against copies of `753e088`, run over
`hit_floor_region_clamp.spec` + `region_expand.spec` (control: 90 passed):

| # | mutation | my reds | report |
|---|---|---|---|
| B-M1 | `isCover` → `false` (rule dropped) | 5 | 3 |
| B-M2 | `isCover` → `true` (every expander) | 2 (both F1 controls) | 2 |
| B-M4 | `growWithin` ignores blockers | 9 | 7 |
| B-M5 | the post-loop `granted <= 0` guard dropped | 2 | 2 |
| B-M6 | `solverHidden` filter dropped | 1 | 1 |
| **B-M7** | **the four far-side skips removed** | **4** | 3 |
| B-M8 | the other-axis overlap skips removed | 2 | 2 |
| B-M9 | `pressableRects` returns `{}` | 5 | 3 |

My counts are ≥ the report's on every row (I ran two specs, they ran a narrower
scope). **Every one of the eight is caught.**

**B-M7's fix is verified directly, not just by a red.** With the far-side skips
removed, the shipped HUD's three covers collapse to `NO FLOOR` on every viewport
and `overflow_sweep` emits **46** dead-end findings — byte-for-byte the same
damage as the refused hard clamp. The skip is what prevents it.

**The F1 case is pinned and holds.** `a 20x20 Button still asks for the full
44x44, and it still leaves its parent` and `a sub-floor Button keeps its WHOLE
floor over a pressable node in ANOTHER subtree` are green at the parent, green at
HEAD, and are the two cases B-M2 reddens — so the exemption is proved by a
mutation, not asserted. Confirmed.

### 1.4 The brief-refusal — reproduced exactly

I implemented the brief's prescribed rule (clamp a cover's floor to its region's
bounds, keeping the retraction) on top of `753e088` and measured:

* the shipped HUD's three stepped-down covers go from `75x44 | 44x44 | 80x44`
  to **`NO FLOOR | NO FLOOR | NO FLOOR`**;
* `overflow_sweep` fails on **exactly five viewports** —
  `compact-phone-portrait (359x718)`, `compact-phone-landscape (705x338)`,
  `narrow-portrait (320x640)`, `narrow-landscape (640x320)`,
  `phone-390x844 (390x844)` — with 46 "under the thumb's floor" findings.

**The refusal is justified. The measurement is exactly as reported, to the
viewport count.** This is the strongest single piece of work in the round: the
implementer was told to ship a rule, measured it against a shipped fixture,
found it wrong, and said so.

### 1.5 The two exemption sweeps

Verified by an independent seat (real clones, because both checkers walk
`git ls-files`):

* **`2e6c7d9`** — `check_comment_codes` PASS at `2e6c7d9`, `753e088`, HEAD;
  `--selftest` PASS. The tuple goes from four modules / 171 locked codes to
  three / 130 (`--json`: `lockedOrphans` 138→105 = 33, `lockedResolvable` 33→25 =
  8, total Δ41). **Every number in the report reproduces from the checker's own
  output.** The disclosed trap reproduces too: at `4cc5cb0` on a *tracked* tree
  the checker **FAILS** on `ADAPT-7`, `RS-A16`, `NS-A2` in `commit_walks.luau`.
* **`753e088`** — `check_brand_drift` PASS + `--selftest` PASS. The red genuinely
  predates the renderer split: green at `c6c6260`, **RED from `f0fc77e` (the
  solver split, which created `measure_facts.luau` and carried the `SwiftUI`
  reference out with it)**, still red at `4cc5cb0` (now 2 matches — the second is
  this round's own `iOS contentInset` in `commit_walks.luau`) and at `935f9a2`,
  swept at `753e088`. The attribution is correct. The *duration* is not — see
  MEDIUM-2.

### 1.6 Guards at the final commit

All twelve named guards PASS at `753e088` and HEAD, plus twelve more
`check_*.py`, all six `check_perf_gate_evidence` sections, `stylua --check`, and
five lune checkers I ran myself (`check_prop_parity` PASS 27 classes/673
properties, `check_docs` PASS, `check_registration` PASS, `check_example_drift`
clean, `check_maintainer_map` PASS). One guard outside the report's list is red —
see MINOR-7.

### 1.7 Rascal Rally

Pinned pairs, refs resolved at measurement time (RR HEAD **is** `c3c8d49`):

| pair | result |
|---|---|
| Facet `753e088` + RR `c3c8d49` | **3,466 / 0** ✓ claim |
| Facet HEAD + RR HEAD | 3,466 / 0 |
| Facet `b5732d0` (pre-round) + RR HEAD | 3,465 / 1 |

**Verdict-set diff across the whole round (pre-round → HEAD): zero removals, zero
additions, one verdict change** — `facet_theme_paint_contract`'s "the ROLLBACK
survives" flipping red→green, which is another round's fix landing. The
consumer-visible hit-floor pins hold unchanged:
`facet_hit_expander_overhang_contract.spec` (4 cases, green) and
`facet_racer_list.spec:213` (`hitRectOf(rowHit("KartRazz")).h == 44`, green,
verbatim). RR's only `expand =` site is `ResultsScreen.luau:2837`
(`spec.expand = "none"`); no `role = "cover"`, no `ExpandPanel`/`ExpandPlate`
anywhere. **The exemption claim is correct and the lockstep is real.**

### 1.8 The ledger's arithmetic

Every character count checks out against `wc -c`:

```
b5732d0 198,974   4cc5cb0 182,003   935f9a2 182,030   2e6c7d9 182,471   753e088 182,522
                              (+27 Phase B)    (+441 comments)   (+51 vendor)
```

182,522 → 17,478 to the cap, 7,478 clear of 190,000. **Correct to the
character.** The trigger is stated by SHAPE ("the next mission that changes the
recycle pool, the removal sweep or the parked-props record takes the drag bridge
first") with 190,000 as a backstop that has *not* already fired — which is
precisely the rule the solver row learned the hard way. This row passes its own
document's test.

---

## 2. Findings

### MAJOR-1 — the rule's blast radius is ~40x what the ADR row records, and half of it is the framework blocking itself

ADR-0040 B-19 states the blast radius as: *"on every shipped fixture the only hit
rects that move are covers'; the 800-tree differential oracle over every other
walk's output is byte-identical; the HUD demo's three stepped-down covers keep
44px."* The first and second clauses are true. The third is true **only at
359x718 with the default package** — the one configuration the spec pins.

Measured on the suite's own `overflow_sweep` matrix (viewport × theme package ×
strip × chrome), reading the same `<region>/Expand` route box the sweep's
dead-end guard reads:

| | before Phase B (`4cc5cb0`) | after (`753e088`) |
|---|---|---|
| route boxes below the 44px floor | **0** of 382 | **42** of 382 |
| smallest route | 44px | **25px** (`Tasks`, compact-phone-landscape, glossy-touch) |
| covers with the expander retracted entirely | 0 | **32** |

Before Phase B every one of the 382 route boxes in the swept matrix was ≥44px.
After it, 42 are not, the worst sits **1px above `overflow_sweep`'s 24px
dead-end bar**, and nothing pins any of it.

Worse, I instrumented `growWithin` to report which blocker cut each side. Across
the sweep there are **110 distinct cover-cut events**, and:

* **55 of 110 are cut ONLY by another framework affordance** (`…/Expand`);
* 29 by a mix; **20 by author nodes alone**.

The clearest case is a shipped fixture with no author content in the way at all:

```
COVERCUT /CompositionScreen/Body/OfferFrame/Summary/Bait/Expand
  own=283x18  floor=283x44  grown=283x18
  blockers=…/Summary/Sponsors/Expand[T], …/Summary/Tease/Expand[B]
```

A cover is boxed in by two *other covers* and retracted to an 18px-tall target.
R18's ruling — "exempt over passive content, banned over interactive" — was made
about a framework floor landing on the author's controls. It was never asked
whether the framework should surrender the F1 floor to *its own* synthesized
affordance, and `hit_lift`'s own doctrine takes the opposite line on the same
question: *"expander-vs-expander is left to the existing host z order… another
expander's invisible rect never [creates a lift]."* `pressableRects()` makes no
such distinction; `inputSinks` is a flat census.

The related symptom: because the blocker set holds *painted* rects, two adjacent
covers each grow into the whole gap between them and their hit rects overlap.
Measured on the sweep: **15 overlapping affordance pairs** after (down from 16
before, max depth 8px from 16px) — the change halves it, it does not close it,
and B-19's "stops at the first rect outside it that can sink a press" reads as if
it did.

None of this is caught by anything: EXPAND 15 asserts emptiness on a fixture with
one cover; the hit-floor spec pins one viewport with one package; the sweep's bar
is 24px, not 44.

**What is wanted.** (a) Correct the B-19 blast-radius sentence to the measured
figures. (b) A director call on whether a framework affordance may block another
framework affordance's F1 floor — my read is it should not, and excluding
synthesized affordances from `pressableRects` would recover most of the 42. (c) A
pin over the swept matrix ("no stepped-down region's route falls below the F1
floor except where an AUTHOR node is in the way"), because the 25px row is 1px
from turning a silent accessibility regression into a suite red.

*Repro:* patch `overflow_sweep.spec`'s `deadEndViolations` threshold to 9999 and
run the sweep at `4cc5cb0` and `753e088`; the `COVERCUT` instrumentation is a
four-line insert after the `growWithin` call in `commit_walks.hitRects`.

### MEDIUM-1 — ADR-0041 does not exist, and eight places cite it

`docs/adr/ADR-0041*` is not in the repository. Citations pointing at it:
`src/render/commit_walks.luau:60`, `:506`;
`tests/hit_floor_region_clamp.spec.luau:2`; `tests/run.luau:670`;
`tests/region_expand.spec.luau:1995`, `:2094`, `:2115`; and
`docs/adr/ADR-0040-unreleased-breaking-changes.md:94` ("see also ADR-0041"). The
report's Phase B is headed "(ADR-0041)". What actually landed is the B-19 row in
ADR-0040 — which may well be the right record, but then the number should not be
cited as if a file existed. This is the exact failure `check_comment_codes`
excludes `ADR-nnnn` *because of*: "a decision record that ships in docs/adr/ — a
reader can open it." Here the reader cannot. (`ADR-0031` is also dangling; that
one predates this round.)

### MEDIUM-2 — "red for three days" is wrong by a factor of ~24, and it is in a permanent record

`753e088`'s subject is *"the same debt was on two lists, and the second one was
red for three days"*; the report and the `SOURCE_CAP_LEDGER` row both say the
escape rode out of its locked host *"three days earlier."* Measured:

```
f0fc77e  2026-08-21 17:53   created src/layout/measure_facts.luau, carrying the SwiftUI line
753e088  2026-08-21 21:03   swept
```

`git log --diff-filter=A` and `git log -S "SwiftUI"` both put the file's creation
and the string's arrival in the same commit, on the same day. The guard was red
for **3 hours 10 minutes**, not three days — and this round's own `4cc5cb0` added
the second violation 1h54m into that window. Everything *substantive* about the
claim is confirmed (it was red; the solver split caused it; no guard caught it at
the causing commit; both lists are now closed). It is the durability figure that
is invented, and it now sits in the cap ledger, which is the document this
project treats as ground truth. It has already propagated into the review brief.

### MEDIUM-3 — a comment describing the abandoned clamp shipped inside the shipped rule

`src/render/commit_walks.luau:611-613`, introduced by `935f9a2` (absent at
`b5732d0` and `4cc5cb0`):

```lua
-- the box a child's floor may not leave. A node the solve did not reach
-- passes its own ancestor's down rather than nil, which widens the bound
-- rather than removing it.
```

`pushHitRects(node: any, hidden: boolean)` takes two parameters and passes only
`isHidden` down. There is no bound and nothing is threaded. This is residue of
the refused region-clamp design, sitting directly above the recursion of the
function the round rewrote, and it tells the next reader that a mechanism exists
which does not. Delete it.

### MEDIUM-4 — `renderer_source.luau`'s prose now over-claims what `PARTS` scans

`4cc5cb0` rewrote the instrument's header to say the renderer *"has shed seam
after seam since: … the ordered rect apply (`render/rect_pass.luau`) and the
commit walks"* — and added only `commit_walks.luau` to `PARTS`. `rect_pass.luau`
has never been in `PARTS` (`git log -p` over the file confirms it). The header's
own standing order is *"ADD A PART HERE WHENEVER MORE OF THE RENDERER MOVES
OUT — otherwise the pins quietly stop seeing the code they name."*

No pin is blind today (`rect_pass.luau` contains no `adapter.setProp(` at all, so
`authored_presentation.spec`'s exact-count pins are unaffected) — this is latent,
not live. But the sibling instrument already solved it:
`tools/lune/check_prop_parity.luau` reads `src/render` as a **directory**, with a
header explaining that it "used to be a HAND LIST of three" and that a hand list
went stale "exactly … the next time a split landed." Make `PARTS` the directory,
or assert `PARTS` ⊇ every module its own prose names.

Judging the disclosed instrument change itself: **acceptable**. Adding the part
is what the file exists for, `button_shape.spec`'s pin reads the same line in its
new home, and no spec verdict moved. The residual cost — a positive source pin
nominally about `renderer.luau` can now be satisfied by any of five files — is
inherent to the instrument and pre-dates this round.

### MEDIUM-5 — the red window is wider than Concern 1 states

Concern 1 says "HEAD was red for one commit." Measured:

* **Suite** red at `935f9a2`, `05aeeea`, `5c51cb4` — **three commits**, 20:36 to
  20:43. Two of them belong to other agents, and `05aeeea`'s subject asserts
  *"green at 7022"* while the tree it committed onto was 7,035 + 1 failed.
* **`check_comment_codes`** red at `4cc5cb0` and through six other agents'
  commits until `935f9a2` repaired it — **seven commits**, 19:47 to 20:36. (The
  repair landed inside Phase B, which the report does not say.)
* **`check_brand_drift`** red at every commit in the chain until `753e088`, with
  one of the two matches contributed by `4cc5cb0` itself.

The disclosure is honest in kind and understated in degree; the marker-filter
lesson and the `--dry-run` recommendation are both right. Worth recording
accurately because the same window is what let another agent certify green on a
red tree.

### MINOR findings

1. **Red-first "6 failed, 2 passed" is not reproducible.** The final 14-case spec
   gives 10/4 at `4cc5cb0`. The 8-case figure was measured before the mutation
   work grew the spec; the *numbers* it cites (960, 828, 9,360) all reproduce.
2. **The RR A/B's "mine + Phase B → 3465 passed, 1 failed" arm does not
   correspond to `935f9a2`**, which measures 3,466 / 0 (an intervening commit,
   `c3eec58`, had already fixed the shared red). Read as "4cc5cb0 + my patch" it
   is fine and the neutrality conclusion is independently confirmed by the
   pre-round → HEAD verdict diff; the pin labels are just wrong.
3. **The negative-control line counts (456 / 6 / 86) are not reproducible** from
   the descriptions given; the mutation text was not recorded. Non-vacuity is
   confirmed with much larger deltas.
4. **The ledger row is stale by one and by 9 KB**: it still says "all twenty
   names that cross" after `5c407cc` made it twenty-one, and calls
   `commit_walks.luau` "26.7 KB", which is its Phase A size (35,474 bytes at
   close).
5. **"the one HUD region that IS boxed in (landscape `Tasks`) grows 42 of its
   44" is unpinned and not reproducible from the bare fixture** — at 705x338 the
   HUD does not step down at all (`activeForm = 1`, every `Expand` 0x0). It is
   reproducible only under the sweep's own chrome, where 42px routes do occur
   (`Tasks 116x42`, `167x42`, `Health 44x42`). The claim is true; the fixture it
   names is not the one that produces it.
6. **Concern 6 under-counts the stale old-name prose.** Besides
   `screen_target.luau`, six other files still spell the moved walks the old way
   (`tools/lune/check_prop_parity.luau:95`,
   `tools/lune/check_flat_baseline.luau:705`,
   `tests/ten_foot_metrics.spec.luau:833`, `tests/region_expand.spec.luau:2091`,
   `examples/gallery/scenarios/hud.luau:1632`,
   `.../runner.luau:974`). All resolve through the module header; cosmetic. No
   *code* reference to a moved name exists anywhere — verified by grep.
7. **A thirteenth guard is red at HEAD and is not on the report's list.**
   `tools/check_theme_artifacts.py` fails (18 problems, `error requiring module
   "./overflow_guard"`) because `tests/lib/world.luau` gained that require in
   `19dc1cb` and the checker's hand-maintained `COPIED_FILES` list never
   followed. `19dc1cb` predates `b5732d0`, so this is **not** this round's
   breakage — but "every guard PASS" was asserted over a list, not over
   `tools/check_*.py`, and the difference hid a red.
8. **`inputSinks` is a per-solve linear scan per standing cover** (report's
   Concern 5). Confirmed as written; no regression is visible in suite timings.
   Lifecycle is sound: the census is cleared and rebuilt in `structuralSync`'s
   `livePaths` walk, which precedes the commit span, and `hit_lift.refresh`
   already consumed it on the same contract before this round.

---

## 3. Claim ledger

| claim | measured | verdict |
|---|---|---|
| Suite 7,000 → 7,036, zero removals | +16 then +15/−1 (own rename), 7,036 / 0 at final | CONFIRMED |
| No existing spec edited (Phase A) except the instrument | only `renderer_source.luau` + `run.luau` | CONFIRMED |
| 800-tree oracle, 328,839 lines, byte-identical | exact, at 4 pins, deterministic, 0 errors | CONFIRMED |
| Three negative controls bite | all three bite; counts differ | CONFIRMED (counts UNVERIFIABLE) |
| Red-first at 960 / 828 / 9,360 px² | exact | CONFIRMED |
| 14 passed after | exact | CONFIRMED |
| 8 mutations bite, incl. B-M7's arithmetic defect | all 8 bite; B-M7's damage reproduced and its fix verified | CONFIRMED |
| Hard clamp loses 3 covers' floor; sweep reports 5 viewports | exact, to the viewport names | CONFIRMED |
| HUD's three covers keep 44px | true at 359x718 / default package only | CONFIRMED-BUT-NARROW (MAJOR-1) |
| Ordinary sub-floor control keeps its whole floor (F1) | pinned twice, proved by B-M2 | CONFIRMED |
| `check_comment_codes` 41 / 33 / 8 / 171→130, tuple 4→3 | every number reproduces from `--json` | CONFIRMED |
| The `4cc5cb0` untracked-file trap | reproduced: FAIL on a tracked clone | CONFIRMED |
| `check_brand_drift` red predates, caused by the solver split | green at `c6c6260`, red from `f0fc77e` | CONFIRMED |
| …"red for three days" | 3h10m | **REFUTED** (MEDIUM-2) |
| Every guard PASS at the final commit | 12 named + 12 more + 6 sections + 5 lune tools | CONFIRMED (one guard off-list is red — MINOR-7) |
| `5c407cc` repair caught by the seam spec's own count | `expected 21 to be 20`, exactly | CONFIRMED |
| HEAD red for one commit | suite 3, `check_comment_codes` 7 | PARTIALLY REFUTED (MEDIUM-5) |
| Ledger 182,522 measured last; trigger by shape | correct to the character; trigger not fired | CONFIRMED |
| RR 3,466 via pinned pair; hit-rect pins green and unchanged | exact; zero removals, zero additions | CONFIRMED |
| ADR-0041 | does not exist; 8 dangling citations | **REFUTED** (MEDIUM-1) |

---

## 4. Not verified

* The prose quality of the 41 rewritten comments (counts only).
* Anything on a real device. The hit floor is a touch-target change and the
  25px / 18px routes in MAJOR-1 are the kind of thing the device round exists
  for.
* `check_sf_rows` / `check_spike` / `check_verdicts` — each needs a per-round
  artifact argument with no canonical no-arg form.
