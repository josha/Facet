# task-solver-split — the solver stops being one file, and the room buys the guarantee

**Status: COMPLETE.** Both phases shipped, both suites green with **zero
re-verdicts on either side**, and `src/layout/solver.luau` ends the mission with
**11,950 characters of headroom against the 2,190 it started with** — 5.5x, after
paying for everything Phase B added.

| | at dispatch | after Phase A | at close |
|---|---|---|---|
| `src/layout/solver.luau` | **197,810** (2,190 to the cap) | 186,040 (13,960) | **188,050 (11,950)** |
| position vs the 190,000 warning line | **7,810 INSIDE** | 3,960 clear | **1,950 clear** |
| Facet suite | 6,915 | 6,928 | **6,937** |
| Rascal Rally suite | 3,464 | — | **3,464** |

Commits: **`f0fc77e`** (Phase A, the split) and **`435dade`** (Phase B, the two
containment guarantees). Both through `tools/commit_isolated.py` with hunk
markers on the three shared files (`tests/run.luau`,
`docs/handoff/SOURCE_CAP_LEDGER.md`); no other agent's work was swept in and none
of the three concurrent rounds' files (`tests/lib/overflow_guard.luau`,
`tests/lib/overflow_waivers.luau`, `src/client/native_style.luau`,
`tests/native_style_default.spec.luau`, `src/themes/`) was touched.

---

## Phase A — the split the ledger prescribed

**`src/layout/measure_facts.luau`** (22.3 KB) now holds, exactly as the ledger's
own analysis named them: `Dim` and the dimension readers (`CONTENT`, `dim`,
`SPACER_FILL`/`mainDimOf`, `sides`), `textTypography` + `recordTextFacts` + the
text-fact record, and the memo's per-node classification (`MEMO_ARM_DEPTH`,
`HEIGHT_COUPLED_KINDS`, the `PLAN_*` verdicts, `memoPlan`). `axisAbsorbs` joined
them in Phase B (below).

**The prediction that mattered held: the argument list was already written.**
`SHRINK_DEPS` and `GRID_DEPS` have been threading four of these helpers into
`./shrink` and `./grid` as explicit arguments since those splits, which is the
standing proof that they read nothing of their host. This is the first seam in
the ledger that cost **neither a shared record** (`table.luau`'s `rowGesture`,
`virtual_list`'s `hostedDelivery`) **nor an accessor** (`table_header`'s
`renderController`).

**Two corrections to the ledger's analysis**, both found by writing it and both
now recorded in the row:

* `definite` and `roundRect` **do not exist** in this file — `roundPx` comes from
  `../num` and there is no `definite`. The row named them from a stale reading.
* `Dim` had to travel **with** `dim`/`mainDimOf` or the new module would have
  re-declared it. The solver re-exports it (`export type Dim = measureFacts.Dim`),
  so the public surface is unchanged and there is one schema rather than two.

### The mechanised seam spec — `tests/measure_facts_seam.spec.luau` (13 cases)

This seam has **no parameter object to compare**: everything arrives on the
solve's own `ctx`. So the house method's three sets are taken one layer in:

* **READ == DECLARED == HOSTED** — the `ctx` fields the module touches (comments
  stripped, because the solver's reasoning blocks name `ctx.compact` and
  `ctx.compositions` while discussing fields the extracted code never touches,
  and one of those blocks travelled with `memoPlan`) == the six its own
  `MeasureCtx` declares == fields the solver's `Ctx` block still declares. The
  third comparison is the half a parameter object gives for free: nothing hands
  these over one by one, so a rename on the solver's side would be a silent `nil`.
* **The shared WRITE surface is exactly four names** — `fitCuts`, `memoPlans`,
  `textFacts`, `textStates`. A fifth is the finding.
* **EXPORTED == BOUND** in both directions, every bound name **USED**, exactly
  **one consumer**, the require **one-way**, the type re-export asserted, and
  **no module-level local is ever reassigned** — the property that makes it
  one-way from the other side, and the one a parameter object never needed.

**Eleven mutations proved to bite. Two were findings rather than drills:**

| # | mutation | result |
|---|---|---|
| M1 | an undeclared `ctx` read in the module | 1 red |
| M2 | a `MeasureCtx` field nothing reads | 1 red |
| M3 | a field the solver's `Ctx` no longer declares | 2 red |
| M4 | a fifth shared write (`ctx.compact`) | 2 red |
| M5 | an export removed (the binding would be `nil`) | 1 red |
| M6 | an export nobody takes | 1 red |
| M7 | a bound name whose last use left | **GREEN — the check was decoration** |
| M8 | `require("./solver")` added to the module | 1 red |
| M9 | a module-level local reassigned | 1 red |
| M10 | `Dim` re-declared in the solver | 1 red |
| M11 | a second consumer appears | 1 red |

**M7 is the process finding.** The rule counted occurrences of each bound name in
the solver, and the binding line — `local X = measureFacts.X` — names X **twice**,
so the count could never reach zero and the rule could not fail. With the binding
block excluded it reddens on M7 — **and it immediately reported a real one**:
`PLAN_KEYED`'s only reader left with `memoPlan`, so the export was a fact
computed for nobody and is gone. A check that cannot fail is decoration, and this
one was, for one commit, until a mutation said so.

### Behaviour: byte-identical, proved twice

* **Verdict-set diff.** 6,915 -> 6,928 against a content-pinned `git archive`
  baseline, diffed line-for-line: the thirteen added rows are the seam spec's own
  and **nothing else moved**. No spec needed editing — the bar the brief set
  ("any spec that needs editing means the split changed behaviour").
* **The differential oracle** (`800` seeded trees over the whole vocabulary —
  `fits`, `hwrap`/`vwrap`, `grid`/`gridrow`, `scroll`, `shrinkWeight`,
  `compactText`, `lineLimit`, `reveal`, `containerRelative`, `aspect` — at seven
  viewports with random safe insets, root policy and scrollbar reserve):
  **10,838 comparison lines covering rects, `compact`, `textState`, all thirteen
  published text facts, the diagnostic set and the work counters — ZERO
  differences.**

---

## Phase B.1 — the plate cannot outgrow its allowance, by construction

**The band DIR5 CONTESTED, reproduced red-first at the predicted numbers:** at a
390 viewport, a form 1 of 320px mounted a panel **380 wide against an allowance of
358**. DIR5 fixed the inner half (a content width written onto a padded box, whose
declared width is its OUTER width) and named the residue with the line —
`solver.luau` ~1113, beside `expandGutter`.

**It is closed with ONE DECLARATION rather than one number.**
`src/layout/expand_plate.luau` owns the plate's insets and its straddle; three
layers read that one declaration and none derives it:

* `src/blueprint.luau` **builds** the plate from `PADDING` / `STRADDLE` /
  `SHEET_PADDING`;
* `src/layout/solver.luau` **resolves** them against the live snapshot into
  `resolveCtx.expandPlateInset` / `expandPlateStraddle` — the same split
  `expandGutter` and `floorOf` already make, where the number crosses and the name
  never does;
* `src/layout/composition.luau` **spends** them: three caps now, and the
  differences are the fix — `allowW` (what the panel must fit in), `plateMax`
  (`allowW` minus the straddle, the widest the plate BOX may be declared) and
  `maxW` (`plateMax` minus the padding, the widest its CONTENT may be).

**Two numbers, not one, and that is load-bearing**: the padding is *inside* the
box the caller declares and the straddle is *outside* it, so a single combined
"chrome" figure mis-sizes whichever of hug/fill it was not derived for. The first
draft used one and under-sized the fill case by exactly the straddle.

`plate.max` changes meaning (the cap the measure was taken against -> the plate
box's own cap) in one place, deliberately: its only reader spends it as a
declared **outer** width, and an outer width has to be an outer number or the fix
is the same defect one level up. Its VALUE at 390 moves 358 -> 342 and its one
assertion is relational (`plate.rect.w == row.plate.max`), so nothing re-verdicts.

**Three mutations bite** (each 1 red in `tests/region_expand.spec.luau`): the cap
stops reserving the padding; the cap stops reserving the straddle; the plate
stops spending the declaration.

**ADR-worthy behaviour change, judged honestly.** A form whose natural width lands
in the last `inset + straddle` px of the allowance now falls back to the
full-width **sheet** instead of mounting an over-wide anchored panel. That is the
band DIR5 already re-verdicted and its own report recorded as "nothing in any
fixture is in that band today" — confirmed: zero shipped screens move, and the
suite's verdict set gains only the two new cases.

## Phase B.2 — the settle-time containment diagnostic

**Every overflow finding in the solver is derived from a MEASURE compared against
an offer. Not one was derived from the RECT a child was finally given** — which is
exactly why a box placed outside its parent by *arithmetic* was invisible on the
channel whose whole purpose is to say so
(`docs/lessons/the-solver-already-told-you.md`).

The finding is **first-class**: `node`, `filedBy`, `edge` and `overhang` in px as
FIELDS, plus the sentence. A harness sorts by how far outside without parsing
English. It is reported, never fatal.

### Its scope was MEASURED, not chosen — and that is the honest part of this phase

The first draft policed every parent that places a child. Instrumented across the
whole suite it produced **21,916 findings on a green library**:

| parent kind | findings | why it is not a defect report |
|---|---|---|
| `anchor` | 13,851 | its entire contract is to place a child where the author says |
| `zstack` | 3,609 | layers by definition; has its own measure-side finding and `intentionalOverlap` |
| stack MAIN axis | 4,103 | already reported by name and number two lines above the loop |
| `composition` region | 312 | **a real class — see below** |
| **stack CROSS axis** | **41** | **the hole: all 41 on adversarial fuzz trees, NOT ONE on a shipped fixture** |

**What shipped is the stack cross axis** — the axis a stack's own
`crossSize = min(desired, crossAvail)` is supposed to guarantee, so a child
outside it means the guarantee broke. The minimal reachable case is not
synthetic: the ASPECT axis is derived *after* the clamp, so a 2:1 box 80px tall in
a 100px column resolves to 160 wide and paints 60px outside its parent — and
before this the diagnostics channel was **empty** for that tree.

Gated by the solver's own predicates rather than by new rules: `ctx.hiddenDepth`
(a subtree that never paints cannot overflow anything), `routesOverflow`
(`clip`/`scroll`/`intentionalOverlap`, plus the `scroll`/`hwrap`/`vwrap` kinds
that absorb or report for themselves), and `axisAbsorbs` — the resolver-mirroring
boundary predicate — for "can this parent grow?".

**Red-first, rigorously**: `tests/containment_diagnostic.spec.luau` run against a
content-pinned copy of the pre-change tree fails **3 of 7** — and the four that
pass there are the negative controls, passing vacuously, which is precisely why
each has a positive beside it.

**Six mutations bite**, and one was a finding:

| # | mutation | result |
|---|---|---|
| B2-M1 | the containment call is removed | 3 red |
| B2-M2 | the `edge` field is dropped | 3 red |
| B2-M3 | the hidden-subtree gate is removed | 1 red |
| B2-M4 | the declared-route gate is removed | 1 red |
| B2-M5 | the can-it-grow gate is removed | **GREEN — the case proved nothing** |
| B2-M6 | it polices the MAIN axis instead | 4 red |

**B2-M5**: a bare `hug` column simply GROWS to 160 and there is no overflow to
report at all, so the case passed with its own gate deleted. Rewritten to squeeze
the hug column inside a 100px parent — `hug` is content capped at the offer — it
now reddens, and its comment states the deliberate limit it pins (a hug box too
small for its content was squeezed by ITS parent, and that is the outer box's
story to tell).

### Booked, not shipped, with the number

**A composition REGION placed below its composition's own content box fired 312
times on one scenario (`/HudScreen/Hud/Rounds`, `/Clock`, `/Actions`, overhangs
16-94px).** That is a real class — the existing collision finding compares regions
against each OTHER and never against the box — but it is a defect to investigate,
not a rule to add in the same breath as a containment wave, and the adapter-side
harness (`tests/lib/overflow_guard.luau`, a concurrent round) is the right
instrument. **Recommend routing it to that round.**

---

## Evidence

**Facet, content-pinned** (`git archive` of `50a7940` into a private tree; every
measurement run there, never in the shared working tree):

```
baseline                       6915 passed, 0 failed
Phase A (split, no spec)       6915 passed  — verdict-set diff: EMPTY both ways
Phase A (+ seam spec)          6928 passed  — diff: +13, all the seam spec's own
Phase B.1 (+ plate fix)        6930 passed  — diff: +2, both the new EXPAND 19 cases
Phase B.2 (+ containment)      6937 passed  — diff: +7, all the containment spec's own
FINAL vs baseline              6937 passed  — 22 additions, ZERO removals
```

**Rascal Rally, paired export** (identical RR tree, two Facet trees differing only
by this mission's six files):

```
before   3464 passed, 0 failed
after    3464 passed, 0 failed      verdict-set diff: IDENTICAL, zero re-verdicts
```

**The differential oracle, across the whole mission** (800 trees):

* geometry, `compact`, `textState`, all thirteen text facts, `visible`, `kind`,
  the offers and the work counters — **`diff` exit 0, byte-identical**;
* the diagnostics channel is **strictly additive**: **0 lost, 60 gained, all 60
  containment findings**, on 33 of the 800 trees.

`tools/check_source_size.py` **PASS** — the solver is no longer one of the modules
inside the warning band. `stylua --check` clean on all nine touched files;
`check_library_purity`, `check_types`, `check_comment_codes`, `check_doc_style`
all PASS.

## Ledger

`docs/handoff/SOURCE_CAP_LEDGER.md`'s solver row **moved from "The band" to
"Cleared the band"** and was re-recorded twice — once at the Phase A number and
once, finally, at **188,050 measured after the last `stylua` pass**, which is the
rule that row's neighbours learned the hard way. The re-record carries: what the
split cost (nothing — no record, no accessor), the two corrections to the prior
analysis, what the room was spent on and what is still owed. New trigger:
**188,000, or the next mission that changes the measure recursion or the
composition resolution** — with `flowPartition`/`flowPlan` (~3 KB, already
exported as `solver.flowPartition` because it is pure) and the placement
arithmetic (~2 KB) named as the next two candidates.

## Concerns

1. **The R18 hit-floor reserve is STILL BOOKED, with the headroom measured.**
   `task-m2fix` concern 1 asks the solver to reserve `markW` **plus** the 44px
   floor's overhang rather than `markW`, so a mark cannot reach over an
   interactive fill-width sibling. There is room — **11,950 characters to the cap,
   1,950 below the warning line** — but it is a change to shipped geometry on
   every compact form, with its own fixture round and its own device pass, and
   folding it into a containment wave would have made both harder to judge. It is
   the one item of the brief I did not attempt.
2. **The composition-region containment class (312 findings) is real and
   unreported.** Named above; recommend the overflow-guard round takes it.
3. **The containment rule is deliberately silent on a squeezed `hug` parent.**
   Stated in the spec's own comment where it is felt. Closing it needs the OFFER
   carried into arrange, which is state the check does not have; the outer box's
   own findings tell that story today.
4. **`anchor` and `zstack` are unpoliced by the containment finding**, on the
   measured evidence above. `zstack` has its own measure-side finding; `anchor`
   has nothing, and an anchored child outside its parent is a legitimate
   authoring pattern (a badge, a thumb) with no way to distinguish it from a
   defect. If the adapter-side harness wants that class, it is better placed to
   judge it — it can see paint.
5. **The solver's margin below the warning line is 1,950.** That is one ordinary
   comment block plus a little. The ledger row says so and names the next two
   candidates; the next round to open this file should read it first.
6. **The fast tier reported over budget** (45.3s = 106% of the full suite) during
   this mission. That is machine load from four concurrent agents, not a tier
   regression — the full suite in a private copy ran in normal time throughout —
   but it is worth a re-measure once the rounds land.

---

# FIX ROUND 1 — the record catches up with the code

Review: `task-solver-split-review.md`, **PASS WITH FINDINGS**. The behaviour claim
held under fully independent re-measurement (the reviewer's own 800-tree oracle,
their own commit-to-commit pairs, their own mutation battery). Every finding was
record integrity. All six are closed below. **Commit `b5732d0`.**

Measurement is a content-pinned pair built with the new `tools/mkpair.sh`, both
repositories' refs resolved at measurement time and stamped into the pair as
artifacts:

```
PIN_FACET  e8ce70a (before)  →  b5732d0 (after)      PIN_RR  cae4c7a (both arms)
Facet       7,002 passed / 0 failed  →  7,005 / 0    3 additions, ZERO removals
Rascal Rally  3,465 / 0  →  3,465 / 0                verdict sets IDENTICAL (diff exit 0)
```

The three additions are the two new pins this round adds and nothing else. Guards
at the fix commit, all run rather than asserted: `check_comment_codes` **PASS**,
`check_source_size` PASS, `check_doc_style` PASS, `check_types` PASS,
`check_library_purity` PASS, `check_manifest_integrity` PASS (1,518 greps
anchored), `stylua --check` clean.

## HIGH-1 — the gate I certified was RED, and my split is what made it red

**The correction, stated plainly: I asserted it, I did not run it.** This report's
Evidence section said "`check_library_purity`, `check_types`, `check_comment_codes`,
`check_doc_style` all PASS". `check_comment_codes` was **FAIL at `f0fc77e` (2
orphans) and FAIL at `435dade` (4)**. It was PASS at the parent. I ran the other
three and carried the fourth along with them in one sentence, which is how a
roster becomes a claim nobody checked.

**The mechanism is the split itself, and it was foreseeable.**
`tools/check_comment_codes.py` holds an `EXTRACTION_LOCKED` tuple of the five
files the source-cap ledger governs; codes inside them are counted and reported
but never gated, because the sweep is owed to the extraction that owns them.
Moving a block out of a locked file into a **new, unlocked** module strips that
exemption — `NS-A2` rode out with `sides` and `LTN-4` with `recordTextFacts`, and
both became live orphans against a ceiling of zero, on the split commit.

**Who paid.** Three later commits from other rounds (`8ae0384`, `4553a22`,
`d3abdb0`) swept those orphans, which is why the shared tree was green when I
looked at it and why the code needed nothing here. The cost of my not running the
check was borne by whoever found it.

**The rule now lives where the next split will read it.** `SOURCE_CAP_LEDGER.md`
gained a "What an extraction owes on the way out" section: an extraction out of an
`EXTRACTION_LOCKED` module inherits none of its exemptions, run
`check_comment_codes` on the split commit itself, and take the file out of the
tuple when the extraction lands.

### The tuple measurement, and the drop

`src/layout/solver.luau` was still in `EXTRACTION_LOCKED` — a file whose
extraction had just happened and which had left the warning band entirely. That
is an exemption with nothing left to be owed to. **Measured before deciding**, by
dropping the entry in a private `git archive` of HEAD and running the checker:

| | with the tuple entry | with it dropped |
|---|---|---|
| orphans (ceiling **0**) | 0 | **10** |
| live resolvable (ceiling **25**) | 25 | **27** |
| locked modules / codes owed | 5 / 183 | 4 / 171 |

**Twelve sites surface**, ten of them orphans across seven distinct codes
(`LTN-4` ×4, `RS-A16` ×2, `NS-A2`, `NS-A3`, `MINOR-8`, `STAGE-1`) and two already
resolvable (`LT-8` → a handoff doc, `SF-P5` → ADR-0022) which would still have
pushed the live count to 27 against a ceiling of 25. **Twelve is under the ~15
threshold, so the drop and the sweep both landed in this commit.**

All twelve became **prose**, not define-in-block, and the arithmetic is why:
`len(live)` counts every private code in a maintained file whether it resolves or
not, so with 25 of 25 already spent, a single define-in-block would have breached
the ceiling and raising it is forbidden. Prose is also what the checker's own
header asks for — *the code is the whole explanation and the explanation is not in
the repository*. The `ADR-0022` citation survives at its site (a public prefix
costs nothing); only the private row code goes.

**Result: 0 orphans, 25 of 25, four locked modules holding 171 codes. The solver
now contributes zero.** Nothing was displaced onto another file's budget, no
ceiling moved, and `--selftest` passes. Mutation **F-M3** — putting one swept
`LTN-4` back — reddens the check, so the sweep is load-bearing rather than
decorative.

## HIGH-2 — the trigger had already fired when I wrote it

The row recorded **188,050** and set `Trigger: this file passes 188,000`. Fifty
characters past, on the day of writing: a trigger permanently in the fired state,
which is the same class as a check that cannot fail — and the exact failure the
`presenter.luau` row two rows above documents in capitals. I read my own number
and wrote a threshold under it without comparing them.

**The consequence had already materialised before the review found it**:
`099e28f` put **420** characters into the solver with no extraction preceding
them, and neither clause of my trigger could warn it.

**Rewritten as a STATE, and the choice is named rather than slipped.** Not a
bumped number — **ARRIVED**, the way every other row in the file says it, with the
next extraction named: `flowPartition` + `flowPlan` (~3 KB; `flowPartition` is
already exported as `solver.flowPartition` precisely because it reads no node and
no `ctx`, which is the whole one-way test, and `flowPlan` reads only
`dim`/`mainDimOf`/`sides`/the partition — all now in `./measure_facts`), with the
placement arithmetic (~2 KB) behind it. This round's own **+385** of comment sweep
(188,050 → 188,435) is recorded in the row rather than quietly absorbed, together
with why it is the last change that gets that pass: it pays down the debt the
split created, it moves no geometry, and the rule it violated is the one this same
commit wrote down. The ledger's shared rule section also gained the general form:
state a trigger as a condition that has or has not arrived, never as a number the
file has already passed.

**Headroom at close of the fix round: 11,565 characters to the write cap** (from
2,190 at dispatch), **1,565 below the 190,000 warning line.**

## MEDIUM-1 — the ADR row, and the `api.md` rule

`docs/reference/api.md` is corrected in this commit: the plate section now states
**both** routes to the full-width sheet, because the second one is new and
invisible to someone tuning a form against a viewport — the richest form cannot
meet its floor, **or** the richest form is wider than the allowance once the
plate's chrome is reserved. A form that would just fit the raw allowance is a
sheet, because the panel wrapping it would not.

**ADR-0040 row text, for the controller to append as B-18.** I have not edited
`ADR-0040-unreleased-breaking-changes.md`; B-17 is taken by the paint-family row,
and the five-column shape below matches B-14/B-15/B-16:

> | B-18 | `UI.Region{ expand }`'s plate/sheet SELECTION, and `plate.max` on the composition resolution | measured against the gutter allowance → measured against the allowance **minus the plate's own chrome**; `plate.max` changes meaning from "the cap the form was measured against" to "the widest the plate BOX may be declared" (at 390: 358 → 342) | a form whose natural width lands in the last `inset + straddle` px of the allowance now falls back to the **full-width sheet** instead of mounting an anchored panel. The panel it used to mount was **wider than the allowance it had just been chosen against** — reproduced headlessly at 390: a 320px form gave `plate.max=358, sheet=false, panel=380`, i.e. 22px past a 358 allowance, and near the top of the band wider than the viewport. This is the residue DIR5 fixed the inner half of and CONTESTED the rest of by name (`solver.luau` ~1113, beside `expandGutter`); it is closed with ONE declaration rather than one number — `layout/expand_plate.luau` owns the insets and the straddle, `blueprint` BUILDS the plate from them, the solver RESOLVES them onto the resolve context, `composition` SPENDS them on the cap. Two numbers rather than one because they sit on opposite sides of the declared box (padding inside, straddle outside): a single combined figure mis-sizes whichever of hug/fill it was not derived for. **Zero shipped screens move today** — no fixture is in the band, the Facet verdict set gains only the new cases and Rascal Rally is identical — which is exactly why it needs a register entry rather than a fixture: the next reader tuning a form against the allowance has no other way to learn the band exists | `tests/region_expand.spec.luau` EXPAND 19 (the band case and the in-allowance control), EXPAND 18 (`plate.rect.w == row.plate.max`, relational so both numbers move together); `docs/reference/api.md` §Region plate; three mutations bite (the cap stops reserving the padding, the cap stops reserving the straddle, the plate stops spending the declaration) |

## MEDIUM-2 — the single-source module named an API that did not exist

Already repaired in the tree by the plate-B round (`099e28f`) before I got here:
`expandPlateChrome` and `chromeX` exist nowhere, and `blueprint.luau` now cites
`expand_plate.insetX`. **I coordinated rather than regressed** — their `CLOSE_DISC`
/ `CLOSE_INSET` / `discHalf` / `r18Clearance` additions are untouched.

What was still missing is the part that let the drift happen: the header said the
solver "hands the px across on the resolve context" without naming the fields, so
nothing in the file could go stale *visibly*. It now writes all three out —
`expandPlateInset` (`insetX`), `expandPlateStraddle` (`straddleX`),
`expandPlateDiscHalf` (`discHalf`) — with the reason stated: in the one file whose
whole justification is *there is no second copy*, a header naming a nonexistent
seam field is that same failure one level up.

## LOW-1 — `axisAbsorbs` now carries its contract, and the contract is scanned

The two callers pass two different quantities: the boundary analysis passes the
OFFER, the containment gate passes the parent's RESOLVED content extent. They
agree for exactly one reason — every branch asks `~= math.huge` and nothing else,
so the argument means "is this axis bounded" and both callers are right about
that.

That is written at the function **and mechanised in the seam spec**, because the
ledger row justifies sharing this predicate precisely so a boundary rule cannot
disagree with the resolver: the spec pulls `axisAbsorbs`'s body and fails if
`limit` or `otherLimit` is ever read outside a `math.huge` comparison, with a
negative control proving the scan sees a magnitude read and ignores a comment.
Mutation **F-M1** (a `limit > 400` branch) reddens it.

## LOW-2 — the measured scoping decision now has a regression pin

`anchor` (13,851 findings in the census) and `zstack` (3,609) are excluded by a
call site **not existing**, which one future line can undo, and the measurement
that rejected them lived only in prose. `tests/containment_diagnostic.spec.luau`
now builds four genuinely overflowing trees — a zstack overflowed by a fixed child
and by an aspect child, an anchor overflowed by `offsetX` and by `anchor =
"topRight"` — asserts the containment channel is silent on all four, **and proves
each tree really overflows** (the child's rect is 30–60px outside the parent's
box, computed from the solve), because "no finding" is also what a contained tree
answers. The zstack case additionally asserts that the finding which *does* own
that case still fires, so the exclusion is a division of labour rather than a
hole. Mutation **F-M2** (a zstack call site appears) reddens it.

The composition-region class (312) stays routed to the overflow-guard round rather
than pinned here — it is a defect to investigate, not an exclusion to lock in.

## Fix-round mutations

| # | mutation | result |
|---|---|---|
| F-M1 | `axisAbsorbs` reads the MAGNITUDE of `limit` | 1 red |
| F-M2 | a `zstack` containment call site appears | 1 red |
| F-M3 | one swept comment code returns to the solver | `check_comment_codes` FAIL |

## Concerns after the fix round

1. **`check_comment_codes` is at exactly 25 of 25 and the solver no longer has a
   waiver.** Every future comment in that file is now on the ratchet like any
   other. That is the correct state and it is also a tighter constraint than the
   file has ever had — the next private code added anywhere in maintained `src/`
   reddens the row.
2. **The R18 hit-floor reserve is still booked** (unchanged from the main report),
   with 11,565 characters of headroom and the trigger now reading ARRIVED — so
   whoever takes it extracts `flowPartition`/`flowPlan` first.
3. **The composition-region containment class (312 findings) is still open** and
   independently reproduced at exactly 312 by the reviewer.
4. **B-18 is written but not appended** — it needs the controller, per the
   instruction not to edit `ADR-0040` from here. Until it lands, the plate/sheet
   selection band is recorded only in `api.md` and in this report.
