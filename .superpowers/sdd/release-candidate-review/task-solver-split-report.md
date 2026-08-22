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
