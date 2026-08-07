# Prior gates re-run (EQ-20) — result and analysis

`tools/prior_gates.sh artifacts/example-quality-pass/prior-gates.txt example-quality-pass`,
run at the judged source.

**First sweep: 13 PASS, 9 FAIL. Final sweep at the judged source: 17 PASS, 5 FAIL.**

Every one of the original nine was re-run STANDALONE and diagnosed: three were pure load noise,
four had real causes that are now fixed, one was a phantom that pre-dated every stage, and one
is a bimodal instrument.

**All five remaining failures are the same instrument.** Not "mostly" — every one of the five
runs `tools/bench.sh`, and `phase-2-settings-parity`'s `ui-cost-budget` *is* literally
`tools/bench.sh`:

| Gate | Failing check | What it runs |
|---|---|---|
| `phase-2-settings-parity` | `ui-cost-budget` | `tools/bench.sh` |
| `phase-3-pilot` | `no-leak-regression` | game suite grep + `tools/soak.sh` + `tools/bench.sh` |
| `expansion-textinput` | `expansion-adr-bench-rollback` | ADR file + `tools/bench.sh` |
| `code-simplicity-cleanup` | `performance-unregressed` | `tools/bench.sh` |
| `api-architecture-consistency` | `performance-unregressed` | `tools/bench.sh` |

And `prior-gates-unregressed` — red in five gates before this work — is now green in all of
them. So is `large-text-accessibility`, red since 2026-08-03.

**16 bench runs were recorded during this stage. Every single FAIL was
`textinput-typing-storm`, and nothing else ever flagged.** The pre-stage code failed it in 1 run
of 3. See §2.

**A caution about that file, worth keeping.** `tools/prior_gates.sh` takes a lock and REFUSES to
start a second sweep, printing why and exiting non-zero. A run launched while a stale lock was
held therefore left the previous `prior-gates.txt` untouched — and reading that file afterwards
looks exactly like reading a fresh result. Check the lock and the file's mtime before believing
a sweep ran.

## The discriminator this repo requires

`performance-stress-places`' own gate records the rule: a `FAIL` in the sweep must be re-run
**standalone**, because the sweep runs everything back to back and a check that shells out to a
full suite can lose to load. Every FAIL in the first sweep carried a `[load at start: N]`
annotation between **2.32 and 4.25**, and that sweep ran concurrently with the LuauUI suite, a
live Studio session and two reviewer agents. **The sweep result alone is not a verdict.**

So all nine were re-run standalone, one at a time.

## What the standalone runs found

| Gate | Standalone verdict | Cause |
|---|---|---|
| `phase-3-pilot` | **PASS** | load noise in the sweep — nothing wrong |
| `part-2-director` | **PASS** | load noise |
| `expansion-textinput` | **PASS** | load noise |
| `phase-1-minimal-screen` | FAIL → **PASS** | `bench-reproducible`; see *the bench*, below |
| `input-adaptation-audit` | FAIL → **PASS** | `examples-no-input-boilerplate`; see *the line cap* |
| `theme-packages-and-skinning` | FAIL → **PASS** | `metric-snapshot-single-source`; see *the flat baseline* |
| `rich-skinning-v2` | FAIL → **PASS** | `layered-slots-and-posture` + `circle-button`; same flat baseline |
| `api-architecture-consistency` | FAIL (bench only) | `performance-unregressed`; `studio-evidence` passes standalone, re-run assertion-by-assertion |
| `large-text-accessibility` | FAIL → **PASS** | a stale grep; see *the phantom test* |

Both theme gates were confirmed PASS standalone and then PASS in the final sweep. The
`physical-*` `FAIL_ENVIRONMENT` riders remain on nine gates: they are the standing rider this
repo carries and no Studio session can close them.

**Two gates failed in the final sweep that had passed in the first** — `phase-2-settings-parity`
and `code-simplicity-cleanup`. Neither is a new regression: both are bench-only checks (table
above), and the tally in §2 shows the scenario they flag is the one that flips independently of
the source.

## Four causes, in full

### 1. The flat baseline — three checks, one artifact

`metric-snapshot-single-source`, `layered-slots-and-posture` and `circle-button` all end in
`lune run tools/lune/check_flat_baseline`, so all three were one failure wearing three hats.

The checker renders **eight** fixtures: `control-vocabulary` — the framework's own controls,
which is what the ADR-0020 R9 byte-compatibility claim is actually about — and the **seven
tutorial examples**, which are content this repo is chartered to rewrite. This stage rewrote
six of the seven (05, 06 and 07 down to their board structure, from hand-rolled
`VStack`-of-`HStack` to `UI.Grid`), and the check reported 1920 findings.

**The decisive measurement: all 1920 were example nodes. Zero were on `control-vocabulary`.**
Independently, diffing a freshly generated dump against the 0.6.0 baseline gave 93
`control-vocabulary` differences of which **rect/hit/class differences numbered 0** — every one
was a props-only string (post-3.5 `textFont` + explicit `textSize` emission) or one of 12 new
Disclosure header nodes from a later stage. The flat SOLVE, which is the substance of R9, has
not moved.

So the seven example fixtures were re-baselined and `control-vocabulary` was left untouched —
asserted rather than assumed: the sha256 of its fixtures is identical before and after
(`c38aa64851fe2ce8`), and the rewrite script refused to proceed otherwise. Both halves are still
enforced. Record: `flat-baseline-rebaseline.json`; the reasoning is also in the checker's own
header, where the next reader will find it.

### 2. The bench — a real regression, then a bimodal instrument

`bench-reproducible` (phase-1) and `performance-unregressed` (api-architecture-consistency)
both flagged `textinput-typing-storm`.

**Half of it was real and is fixed.** This stage's change to `src/layout/text_metrics.luau`
(space runs reserve their own width) was written
`for gap, word in string.gmatch(text, "(%s*)(%S+)")`, which allocates a throwaway `gap` string
for every word of every measured label — and every keystroke re-measures the field. That ran
1.57–1.84x the pinned baseline with a heap delta of **-42 MB**, on every run, never once near
zero. The pattern is now `"()(%S+)"`: the word's start index is captured as a NUMBER and the
gap is counted out of `text` in place, so the loop allocates exactly what the pre-existing
`"%S+"` loop did and nothing more.

**The residual flag is the instrument.** Interleaved A/B (this repo's own rule), the pre-stage
loop against the shipped loop, three pairs, same machine, same session:

| pair | OLD p95 norm | NEW p95 norm |
|---|---|---|
| 1 | 1.138 **flagged** | 0.939 |
| 2 | 0.778 | 0.737 |
| 3 | 0.865 | 1.097 **flagged** |

Means: OLD `p50 0.0824ms / p95 norm 0.927`, NEW `p50 0.0828ms / p95 norm 0.924`. The
**unchanged pre-stage code trips the REGRESSION flag in one run of three**, and heap deltas for
identical code range from +10 MB to -38 MB. The flag keys on a p95 whose tail is decided by when
the collector happens to run inside the measured window. Full data: `bench-textinput-ab.json`.
This is not an argument to relax the scenario — it is the measurement the repo's own rule asks
for, and it says the shipped code is at parity.

**The whole-stage tally, 16 recorded `tools/bench.sh` runs:** every FAIL was
`textinput-typing-storm`; **no other scenario flagged even once**. Within the interleaved pairs
— the only comparison that controls for machine drift — the pre-stage loop and the shipped loop
each flagged exactly once in three. Sequential runs are confounded (the first run after an idle
period passes far more often than the second or third, for identical code), which is why the
interleave, not a run count, is the evidence.

### 3. The line cap — a proxy that stopped tracking its subject

`examples-no-input-boilerplate` asserts two things: a grep (no example passes any `present()`
input opt) and a line ceiling of 1644. **The grep is the check's subject and it has never
failed.** The ceiling was a proxy for it, and this stage is where the proxy came apart: the plan
required adding the mechanics the examples were MISSING — example 05's
dictionary/validation/keyboard-state/restart/non-colour cues, example 03's player-reachable
server with accept/reject/rollback/reset, 06's instructions/completion/reset, 07's
scoring/hints/legal-move dealing, 04's visible outcome and Restore — so 1644 → 2908 is required
domain content, and a ceiling that forbade it would forbid the plan.

Raised to 3100 with that reason on the record, and the weak proxy is no longer carrying the
claim alone: `tools/lune/check_example_drift_cli` now runs in the same step. Its R4 rule is the
real assertion (no engine or adapter reach-around in an example) and R1–R3 additionally pin
style authority, which a line count never could.

### 4. The phantom test — red since a director ruling, on nobody's account

`large-text-accessibility` runs a 14-grep FORM A chain against the Rascal Rally suite. Exactly
one grep missed:

```
✓.*the position numeral never truncates at any preference
```

The game suite is **fully green**. No test of that name exists — and reading the file explains
why: the director **deleted the Pos cell** on 2026-08-03 ("we know their places based on where
they are in the list"), because at raised preferences its fixed box could only be bought back
from the name. **A numeral that does not exist cannot truncate**, so the claim the grep asks for
became unassertable the day the ruling landed, and the gate has been red on a phantom ever since
— independently of any stage.

The successor claim is present, is the same subject, and is strictly stronger:
`no row carries a position numeral — the list's own order is the place`, swept over every view ×
every offset, plus the assertion that the name cell it paid into is present on every row. The
grep now points there, with the history recorded in the check's own note.

This is deliberately NOT the "point it at a differently-named test" move that this repo has been
burned by before: the old claim is *entailed* by the new one, and the new one covers more.

## What is NOT claimed

- **The `physical-*` `FAIL_ENVIRONMENT` rows are untouched and stay red.** Real hardware — a
  physical phone, a real gamepad, a designer's eye — is the only thing that closes them, and
  Studio emulation may not. They are the standing rider on every gate in this repo.
- **`prior-gates-unregressed` inside other gates is nested recursion**, not an independent
  signal: it re-runs this same set. It goes green when the leaves do.
- **`api-architecture-consistency` still exits non-zero in the sweep.** Its two recoverable rows
  both pass standalone — `studio-evidence` was re-run assertion-by-assertion against its pinned
  `sourceStamp efbe185e-2570354` artifacts and every one holds; `performance-unregressed` is the
  bimodal bench above. It is reported here rather than declared green from a lucky run.
