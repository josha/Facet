# task-solver-split — REVIEW

**Verdict: PASS WITH FINDINGS.** The behaviour claim — the thing this review exists
to guard — is clean and independently proved. `f0fc77e` is a byte-identical move
and `435dade` is byte-identical geometry plus a strictly-additive diagnostic and
one deliberate, reproduced plate change. Nothing found is a behaviour defect.

Every finding is record integrity: **the report certifies a gate PASS that was RED
at both commits under review and was made red BY the split**, and the ledger row
the mission exists to re-record carries a trigger that had already fired when it
was written.

| severity | count |
|---|---|
| HIGH | 2 |
| MEDIUM | 2 |
| LOW | 2 |

All measurement in private `git archive` exports of the named commits and their
**actual** parents (`c6c6260` → `f0fc77e`, `847ff3e` → `435dade`). The shared tree
was read only.

---

## 1. Behaviour identity of the split — CONFIRMED

### 1.1 The move is textual

Removed-code from `solver.luau` diffed against the new module, comments and blanks
stripped: **identical apart from type annotations and module scaffolding** —
`Node`→`any`, `Ctx`→`MeasureCtx`, the `measure_facts.*` export block and
`return measure_facts`. No expression, no constant, no branch changed. `axisAbsorbs`
moved verbatim in Phase B by the same test. `themeSnapshot` is still used by the
solver (line 3600), so the split left no dead require.

### 1.2 The verdict sets

Full suite run in all four exports. Verdict lines carried with their `describe`
header, sorted, diffed:

| | passed | failed | removed verdicts | added |
|---|---|---|---|---|
| `c6c6260` → `f0fc77e` | 6,926 → 6,939 | 0 → 0 | **0** | 13 |
| `847ff3e` → `435dade` | 6,982 → 6,991 | 0 → 0 | **0** | 9 |

**Zero removals, zero edits, 22 additions across the mission** — the report's
claim, confirmed. Every one of the 22 belongs to the three new/extended specs
(13 `measure-facts seam`, 7 `containment`, 2 `EXPAND 19`). No existing spec text
appears in either diff: the only edit to an existing spec is
`measure_facts_seam.spec.luau`'s own `toBe(10)` → `toBe(11)` pin, which is the
mission's own pin moving because `axisAbsorbs` joined the module in Phase B.
`tests/region_expand.spec.luau` is `99 insertions, 0 deletions`.

> **Observation (not a finding).** The report's *absolute* numbers (6,915 → 6,928
> → 6,937) are relative to a content-pinned `50a7940`, five commits older than
> `f0fc77e`'s real parent. Against the real parents they are 6,926 → 6,939 and
> 6,982 → 6,991. The **deltas and the zero-removal claim are exact**; the gap is
> concurrent rounds, not drift. Worth stating because a reader diffing the report
> against `main` will not reproduce the absolute figures.

### 1.3 The differential oracle — re-run independently

I did not reuse the implementer's harness (none is checked in). Wrote my own:
800 seeded trees over the whole vocabulary (`fits`, `hwrap`/`vwrap`,
`grid`/`gridrow`, `scroll`, `anchor`, `region`, `zstack`, `shrinkWeight`,
`compactText`, `lineLimit`, `reveal`, `disclose`, `containerRelative`, `aspect`,
`percent`+offset, `minMax`, margins, padding, gaps, `align`/`lineAlign`), at seven
viewports × random safe insets × three root policies × random scrollbar reserve.
Canonical dump of rects (x/y/w/h/visible/kind), `contentSize`, `padding`,
`compact`, `textState`, `overflow`, **all thirteen published text facts**, the
work counters and the sorted diagnostic set. **58,012 lines, 3,186 text-fact
lines, 6,563 diagnostic lines, 0 solve errors.**

* **Phase A (`c6c6260` vs `f0fc77e`): `diff` exit 0 — BYTE-IDENTICAL.**
* **Phase B (`847ff3e` vs `435dade`): 0 removed, 125 added, and every one of the
  125 is a containment finding.** Zero geometry lines, zero text-fact lines, zero
  work-counter lines, zero `compact`/`textState` lines moved. The diagnostics
  channel is **strictly additive**, on 92 of the 800 trees. (My 125/92 vs the
  report's 60/33 is a different fuzz corpus, not a discrepancy.)

### 1.4 The seam spec matches the house pattern, and every rule reports

Structure matches `tests/table_rows_seam.spec.luau` (`READ == DECLARED == PASSED`
+ shared WRITE surface + one-way require) and correctly substitutes `HOSTED` for
`PASSED`, because this seam has no parameter object. Every scanner carries a
negative control, as the house pattern does.

**All eleven mutations re-run against a private copy. All eleven bite:**

| # | mutation | reds |
|---|---|---|
| M1 | undeclared `ctx` read in the module | 1 |
| M2 | a `MeasureCtx` field nothing reads | 2 |
| M3 | a field the solver's `Ctx` no longer declares | 1 |
| M4 | a fifth shared write (`ctx.compact`) | 2 |
| M5 | an export removed | 1 |
| M6 | an export nobody takes | 1 |
| M7 | a bound name whose last use left | 1 |
| M8 | `require("./solver")` added to the module | 1 |
| M9 | a module-level local reassigned | 1 |
| M10 | `Dim` re-declared in the solver | 1 |
| M11 | a second consumer appears | 1 |

(Counts differ from the report on M2/M3 because my mutation shapes differ — M2's
ghost field is also absent from the solver's `Ctx`, M3's rename only breaks the
HOSTED comparison. The property under test — that each rule reports — holds in
every case.)

**The M7 repair is real, proved both ways.** Reverting line 233 to the pre-repair
form (binding block NOT excluded from its own count) and applying M7 leaves the
spec at **13 passed, 0 red** — the check genuinely could not fail. And the
`PLAN_KEYED` removal evidence stands: re-exporting `PLAN_KEYED` and binding it in
the solver with no reader reddens **2** cases, one of them the repaired rule.
`PLAN_KEYED` is correctly still an internal local of `measure_facts.luau` and is
exported nowhere.

### 1.5 Ledger sizes — verified with my own `wc -c`

| commit | `solver.luau` | `measure_facts.luau` | `expand_plate.luau` |
|---|---|---|---|
| `c6c6260` (parent) | **197,810** | — | — |
| `f0fc77e` | **186,040** | 19,261 | — |
| `435dade` | **188,050** | 22,285 | 5,186 |

Every ledger figure reproduces exactly. `tools/check_source_size.py` **PASS** at
both commits, and the solver is no longer among the five modules inside the
warning band. The row moved from "The band" (line 31) to "Cleared the band"
(line 41); both analysis corrections (`definite`/`roundRect` do not exist; `Dim`
travelled with `dim`/`mainDimOf` and is re-exported) are recorded verbatim, and
the next candidates are named — `solver.flowPartition` is indeed already exported
(line 3698). `stylua --check` clean on all nine touched files.

---

## 2. Phase B.1 — the plate, independently reproduced

**Red at the parent, at the predicted numbers.** The EXPAND 19 block applied
verbatim to a `847ff3e` copy fails. It trips first on `plate.max` (358 vs 342), so
I removed that pin and instrumented the case to see the headline number:

```
PRE  (847ff3e):  plate.max=358  plate.w=320  sheet=false  panel=380   ← 22px past a 358 allowance
POST (435dade):  plate.max=342  plate.w=298  sheet=true   panel=nil   ← falls back to the sheet
```

**Exactly the report's numbers.** Green at HEAD (71 passed in
`region_expand.spec` at `435dade`, unmodified).

**The two-numbers-by-design reasoning holds, and the arithmetic closes.** At a 390
viewport: gutter 16 → allowance 358; straddle (`space.m`) 16 → `plateMax` 342;
padding `space.s` 8 + disc reserve 36 = 44 → content cap 298. Padding is inside
the declared box, straddle is outside it; `blueprint` writes the straddle as a
**margin** (`{ top, right }`) and `composition` subtracts **one** `straddleX`, so
the two sides agree. A single combined figure would mis-size hug or fill by
exactly the straddle, as the module's header states.

**Three layers, one declaration, no duplicated literal — verified by grep.**
`src/layout/expand_plate.luau` is the only place in `src/` that spells the plate's
chrome. `blueprint` BUILDS from `PADDING`/`STRADDLE`/`SHEET_PADDING` (both
hard-coded padding tables are gone). `solver` RESOLVES via
`expandPlate.insetX`/`straddleX` into `resolveCtx`. `composition` SPENDS the px
and deliberately does **not** require the module — it owns no theme, which is the
same split `expandGutter` and `floorOf` already make. Correct.

`plate.max`'s change of meaning is confined to one write and one relational
assertion, as claimed.

---

## 3. Phase B.2 — the scoping is a measured decision, and I re-measured it

I instrumented the solver at every parent-that-places-a-child site with an
**ungated** census (both axes, no `hiddenDepth`, no `routesOverflow`, no
`axisAbsorbs`) and ran the whole suite:

| parent kind | reviewer's ungated census | report's first draft |
|---|---|---|
| stack MAIN axis | 39,694 | 4,103 |
| `zstack` | 27,160 | 3,609 |
| `anchor` | 17,780 | 13,851 |
| stack CROSS axis | 2,178 | 41 (gated) |
| **`composition` region** | **312** | **312** |
| `hwrap`/`vwrap` | 18 | — |
| **total** | **87,142** | 21,916 |

Mine is larger because it has no gates at all; the **ordering is identical** and
the `composition` region count is **312 on the nose**, which is strong evidence
the report's census came from a real instrumented run rather than an estimate.

**The shipped rule's 41 reproduces exactly.** Counting what the shipped rule
actually files across the whole suite and attributing each filing by node id:

```
SHIPPED RULE (filed)   44
  3   vstack Col -> Wide          ← the containment spec's OWN fixture
  41  hstack/vstack n1 -> n2 …    ← machine-generated fuzz ids, every one
```

**44 − 3 = 41 on fuzz, and not one filing carries a shipped-fixture or example
node id.** The claim is confirmed by direct attribution, not by inference from a
green suite.

**Eight mutations, all bite** (the report's six at the report's exact red counts,
plus two of mine):

| # | mutation | expected | actual |
|---|---|---|---|
| B2-M1 | the containment call removed | 3 | 3 |
| B2-M2 | the `edge` field dropped | 3 | 3 |
| B2-M3 | the hidden-subtree gate removed | 1 | 1 |
| B2-M4 | the declared-route gate removed | 1 | 1 |
| B2-M5 | the can-it-grow gate removed | 1 | 1 |
| B2-M6 | polices the MAIN axis instead | 4 | 4 |
| B2-M7 (mine) | `CONTAIN_SLOP` widened past the 60px overhang | — | 3 |
| B2-M8 (mine) | `overhang` reports a constant | — | 1 |

**The B2-M5 repair is real.** Restoring the pre-repair hug case (a bare `hug`
column with nothing squeezing it) and deleting its own gate leaves the spec at
**7 passed, 0 red** — the case proved nothing, exactly as the report says. The
shipped case squeezes the hug column inside a 100px parent and reddens.

**The in-spec statements for the deliberately-silent cases are honest.** The `hug`
case states the limit where it is felt and names the state it would need (the
offer carried into arrange). `intentionalOverlap` is a real authored `overflow`
value (`blueprint_schema.luau:937` enum), not a fiction the spec invented. The
`filedBy` stamp is correct for the incremental-replay gate: the parent files, and
a skipped parent means an unwalked child, so no double-file.

**Hot-path cost, measured (the report does not carry this).** `noteContainment`
runs on every stack child placement. ABBA-interleaved A/B at `435dade` against the
same tree with only the call removed, placement-heavy tree, best-of-5 × 3 rounds:
OFF mean 4.763 ms/solve, ON mean 4.744 ms/solve — **inside the noise**. No
regression.

---

## 4. Rascal Rally — paired exports, identical verdict sets

Four paired trees (one content-pinned RR export at `cae4c7a`, four Facet trees):

| pair | before | after | verdict-set diff |
|---|---|---|---|
| `c6c6260` → `f0fc77e` | 3,459 passed / 6 failed | 3,459 / 6 | **IDENTICAL (exit 0)** |
| `847ff3e` → `435dade` | 3,464 passed / 1 failed | 3,464 / 1 | **IDENTICAL (exit 0)** |

**Zero re-verdicts on the live consumer from either commit.** The reds are
pre-existing and belong to other rounds: the one at `435dade` ("a corner this game
authors BY NAME still re-derives at ten-foot") is fixed by the very next Facet
commit — RR against Facet `41e6829` is **3,465 passed, 0 failed**. The five extra
at the Phase A pair are RR contract specs written against Facet features that land
in the intervening commits (RR is ahead of Facet there).

The report's "3464 / 0 failed both sides" was measured against an older RR tree.
The claim under test — **identical verdicts** — holds exactly on both pairs.

---

## 5. New-breakage scan and guards at HEAD-of-commits

Both diffs read end to end. Phase A touches five files, Phase B eleven; nothing
from the three concurrent rounds (`tests/lib/overflow_guard.luau`,
`overflow_waivers.luau`, `src/client/native_style.luau`,
`native_style_default.spec.luau`, `src/themes/`) appears in either. Facet's public
surface (`src/init.luau`) is unchanged by both. Every spec file at `435dade` is
registered in `tests/run.luau`.

| guard | `c6c6260` | `f0fc77e` | `435dade` |
|---|---|---|---|
| `check_source_size` | PASS | **PASS** (solver out of the band) | PASS |
| `check_manifest_integrity` | — | PASS (1,518 greps anchored) | PASS |
| `check_types` | — | — | PASS |
| `check_library_purity` | — | — | PASS |
| `check_doc_style` | — | — | PASS |
| **`check_comment_codes`** | **PASS** | **FAIL (2)** | **FAIL (4)** |
| `stylua --check` (9 files) | — | — | CLEAN |

---

## FINDINGS

### HIGH-1 — the report certifies `check_comment_codes` PASS; the split made it FAIL

`tools/check_comment_codes.py` is **PASS at the parent** ("0 orphans, ceiling 0")
and **FAIL at `f0fc77e`**, with exactly two new orphans, both in the file the
split created:

```
src/layout/measure_facts.luau:128: NS-A2   -- the SAME padding semantics the arrange pass uses — native-substrate NS-A2)
src/layout/measure_facts.luau:162: LTN-4   --[[ THE TRUNCATION FACTS ARE PUBLISHED WHERE THE MEASURE HAPPENS (LTN-4).
```

Still FAIL at `435dade` (4; the other two arrive from a different round's
`roblox_env.luau` work). The report says: *"`check_library_purity`, `check_types`,
`check_comment_codes`, `check_doc_style` all PASS."*

**The mechanism is the split itself.** The checker's `EXTRACTION_LOCKED` tuple
names `src/layout/solver.luau`; codes inside it are counted and reported but never
gate ("185 more in the 5 extraction-locked modules, counted separately and owed to
that extraction"). Moving code out of a locked file into a **new, unlocked** module
strips the exemption and the codes become live orphans against a ceiling of zero.
This is a foreseeable, mechanical consequence of any extraction out of a locked
file, and it is the first one this ledger has taken.

**It was not measured.** `tools/check_comment_codes.py` and its `EXTRACTION_LOCKED`
tuple are byte-identical between the implementer's pinned baseline `50a7940` and
`435dade`, so the private tree would have produced the same FAIL. The claim was
asserted.

Not live today: `8ae0384`, `4553a22` and `d3abdb0` — three later commits from other
rounds — swept these orphans, and the check is PASS on the shared tree now. The
cost was paid by whoever found it.

**Ask:** the report's gate roster is corrected, and the extraction rule in
`SOURCE_CAP_LEDGER.md` gains the line the next split needs — *an extraction out of
an `EXTRACTION_LOCKED` module inherits none of its exemptions; run
`check_comment_codes` on the split commit.*

### HIGH-2 — the re-recorded ledger trigger had already fired when it was written

The solver row records **188,050** and sets `Trigger: this file passes **188,000**`.
The file is **50 characters past its own trigger at the moment of writing**. A
trigger permanently in the fired state carries no signal about when to act, which
is the same class as a check that cannot fail.

It is the **only numeric trigger in the file** — every other row states its trigger
narratively ("Treat the trigger as ARRIVED", "OWED BY THE NEXT ROUND THAT OPENS
THIS FILE"). And the `presenter.luau` row two rows above documents this exact
failure in capitals: *"THE CONSEQUENCE IS THE POINT: the 195,000 trigger had
ALREADY FIRED before wave TABLE opened, so those 739 went in WITHOUT the extraction
preceding them, which this row's own words forbid. The writer read the stale
recorded size and believed the trigger was 437 away."*

**The consequence has already materialised.** Measured per commit since:

```
435dade  188,050
099e28f  188,470   +420   "the disc is centred on the corner it decorates, and the plate stops hugging"
```

420 characters went into the solver with no extraction preceding them, past a
trigger that could not warn anyone. The row's second clause ("or the next mission
that changes the measure recursion or the composition resolution") did not catch it
either.

**Ask:** restate the trigger the way its neighbours do — *treat it as ARRIVED; the
next round that opens this file takes `flowPartition`/`flowPlan` first* — or set a
number above the recorded size.

### MEDIUM-1 — the "ADR-worthy behaviour change" is registered nowhere

The report names it correctly: a form whose natural width lands in the last
`inset + straddle` px of the allowance now falls back to the full-width **sheet**
instead of mounting an anchored panel. I reproduced it (§2): at 390, a 320px form
goes panel@380 → sheet. Then the record was not made.

`docs/adr/ADR-0040-unreleased-breaking-changes.md` is the register for exactly this
— it already carries row **B-16** for this same `UI.Region{ expand }` family,
including a "shipped geometry moves" note and the fixtures that pin it. `435dade`
touches no document but `SOURCE_CAP_LEDGER.md`.

`docs/reference/api.md:911` is now incomplete: *"where the richest form cannot meet
its floor in a plate, the same content is presented as a full-width sheet
instead."* The sheet is now also chosen when the form **does** meet the allowance
but not the allowance minus the plate's own chrome.

Zero shipped screens move today (zero re-verdicts, RR identical) — which is exactly
why it needs the register entry rather than a fixture: the next reader tuning a
form against the allowance has no way to learn the band exists.

### MEDIUM-2 — the single-source-of-truth module names an API that does not exist

`src/layout/expand_plate.luau:17`, in its own **public-interface header**:

> `src/layout/solver.luau` RESOLVES them … and hands the px across as
> `resolveCtx.expandPlateChrome`

There is no `expandPlateChrome` anywhere in the tree. The real fields are
`resolveCtx.expandPlateInset` and `resolveCtx.expandPlateStraddle`.

`src/blueprint.luau:1250` compounds it:

> the composition's content cap is `expand_plate.chromeX` of these exact three names

There is no `chromeX` — the module exports `insetX` and `straddleX` — and the cap
reserves **two** names (`PADDING.left` + `PADDING.right`), not three.

Both are residue of the combined-chrome first draft the report admits to
("The first draft used one and under-sized the fill case by exactly the
straddle"); the split into two numbers was not carried into the prose. In the one
file whose entire justification is *"there is no second copy here"*, a header that
names a nonexistent seam field is the failure mode one level up.

### LOW-1 — `axisAbsorbs` is now called with two meanings of `limit`

At its original site the solver's own comment states the argument's meaning:
*"recorded where the OFFER is in hand, because that is what decides it for a
percent or fill dimension"* (`solver.luau:1938`, `maxW`/`maxH`). The containment
gate passes the parent's resolved **content extent** (`innerW`/`innerH`,
`solver.luau:2238`).

Identical today — every branch that reads `limit` only asks `~= math.huge`, and a
resolved rect is always finite — and the call site argues why. But the ledger row
justifies sharing this predicate precisely so *"a boundary rule cannot end up
disagreeing with the resolver"*, and nothing pins that its two callers mean the
same quantity. A future branch comparing `limit` to anything but `math.huge`
silently changes the containment gate. A parameter rename or one assertion closes
it.

### LOW-2 — the measured scoping decision has no regression pin

Four of the rule's five constraints are pinned by a case that bites (`hiddenDepth`,
`routesOverflow`, `axisAbsorbs`, main-axis-not-twice — B2-M3/M4/M5/M6). The three
exclusions the census bought — `anchor` (17,780), `zstack` (27,160), composition
region (312) — are call-site absences, documented only in `placement_audit.luau`'s
header. A future round adding a call site would go green; the 21,916/87,142
measurement that rejected them lives in prose. A cheap pin (assert the finding
count on an anchored-overflow tree and a layering zstack is zero) would make the
scoping decision as mechanised as the gates are.

---

## Concerns in the report, judged

1. **R18 hit-floor reserve still booked** — agreed and correctly deferred. It is
   shipped geometry on every compact form and does not belong in a containment wave.
2. **Composition-region containment (312)** — independently reproduced at exactly
   312. Real class, correctly routed to the overflow-guard round rather than shipped.
3. **Silent on a squeezed `hug` parent** — stated in the spec where it is felt, and
   the case that pins it now bites. Accepted.
4. **`anchor`/`zstack` unpoliced** — accepted on the measured evidence; see LOW-2
   for the missing pin.
5. **1,950 below the warning line** — accurate, and see HIGH-2: 420 of it is
   already spent.
6. **Fast tier over budget** — not re-measured here; four exports ran the full
   suite in normal time throughout, consistent with the machine-load reading.
