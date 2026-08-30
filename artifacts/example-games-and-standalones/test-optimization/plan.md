# Making verification practical — the plan, and what it is aimed at

Stage `example-games-and-standalones`, first half. Binding scope:
`docs/plans/example-games-and-standalones.md`, "Optimize the test suites before the
example pass". This is test and gate infrastructure work. It is **not** permission to
remove coverage, weaken an assertion, skip a prior requirement, reduce a meaningful
fault or soak repetition, or let a focused run stand in for release evidence.

The repository already has `run-tests.sh --fast`, a full-suite transcript cache, a
cache self-test, manifest checks, and a prior-gate recursion guard. The job is to
verify and improve **those**, not to add a second cache, runner, manifest, or
source-of-truth list.

---

## 1. What the system looks like today

Measured and enumerated at `7bcc30a`, on the machine recorded in `baseline.md`.

### The gate graph

`phases.json` now carries **32** stages, this one last. `tools/lune/gate_manifest.luau`
carries **504** check rows across the 31 existing stages: 487 with a `run` string and
17 that are honest literal `PENDING`/`FAIL_ENVIRONMENT` device-or-human rows.

`tools/prior_gates.sh` re-runs every gate that precedes a stage in `phases.json`
order. This stage sits at the end, so its `prior-gates-unregressed` row sweeps **all
31** prior gates — the first row in the repository's history to do so; the largest
sweep before it was `swiftui-parity-round4` at 28. One sweep therefore executes the
union of every stage's rows: all 487 `run` strings, once each, plus a load-settle wait
before each gate.

### What the sweep actually spends its time on

**The suite is already solved.** 228 rows call `tools/suite_transcript.sh` and 33 call
`tools/test.sh` directly — 261 trigger points across 30 stages. Without the cache that
is 261 full suite runs; with it, one run per tree state and 261 cheap reads. That fix
landed 2026-08-16 and it holds.

**The static-analysis battery never got the same treatment**, and it is now the
repeated work. Across one full sweep, with byte-identical arguments each time:

| Producer | Rows | Stages |
|---|---:|---:|
| `lune run tools/lune/check_registration_cli` | 26 | 18 |
| `lune run tools/lune/check_docs_cli` | 22 | 17 |
| `lune run tools/lune/check_boundary` | 14 | 13 |
| `python3 tools/check_manifest_integrity.py` | 12 | 12 |
| `lune run tools/lune/check_prop_parity_cli` | 12 | 11 |
| `stylua --check src tests tools bench examples` | 11 | 11 |
| `lune run tools/lune/check_surface_ledger` | 11 | 9 |
| `lune run tools/lune/check_flat_baseline` | 9 | 8 |
| `lune run tools/lune/check_example_drift_cli` | 8 | 6 |
| `tools/bench.sh` | 8 | 8 |
| `tools/doctor.sh` (runs `rojo build` of the showcase) | 2 | 2 |
| `tools/soak.sh` / `tools/render.sh` / `tools/perf.sh` | 2 each | 2 each |

From `api-architecture-consistency` onward, most stages carry one row that chains the
same nine-producer battery verbatim. That chain, not the suite, is where the sweep's
repeated work now lives.

**The settle wait is real cost.** `prior_gates.sh` waits for the one-minute load
average to fall below 2 before each gate, up to 45 s each. Across 31 gates that is up
to 23 minutes of deliberate idling. It exists for a good reason — `phase-3-pilot`
failed in-batch 2/2 and passed standalone 2/2 with nothing changed, because
`tools/bench.sh` measured the previous gate's tail — but it is charged to every gate,
including the great majority that measure nothing timing-sensitive.

### What is deliberately not cacheable

Recorded here so no later pass "optimizes" one of them by mistake:

- `check_flat_baseline` — its own manifest comment says the neutral dump is
  "REGENERATED and compared, never read from store". Caching a baseline is precisely
  the anti-pattern (PG-2, ledger C-08) the gate-integrity work existed to remove.
- `bench.sh`, `perf.sh`, `soak.sh`, `faults.sh`, `fuzz.sh` — these measure time,
  memory, and randomness. A cached timing is not a timing.
- Anything Studio, physical-device, moderation, or network. These keep their evidence
  classes and can never be upgraded by a headless cache.

### Concurrency hazards already on disk

Every repeatedly-invoked producer except the suite cache writes one fixed path
non-atomically and holds no lock: `artifacts/test.json` (`tools/test.sh:229`),
`artifacts/bench.json` (`tools/lune/bench.luau:282`), `artifacts/doctor.json` and
`build/Facet-Gallery.rbxl` (`tools/doctor.sh:40,51`), `artifacts/phase-4/perf.json`,
`artifacts/phase-4/faults.json`. `prior_gates.sh`'s `/tmp/facet_prior_gates.lock`
serialises sweep against sweep, but not a sweep against a standalone `tools/gate.sh`.
Any parallelism added here must not make that worse.

### The suite itself has regressed, badly

`tools/test.sh`'s own header records the measurement the cache was built against:
**83.4 s a run, 5618 passed**, 2026-08-16. At `7bcc30a` the suite is **7638 passed** —
36 % more cases — and a cold run on the documented machine takes **over twenty
minutes** while holding **13 GB** resident, pinned at 100 % of one core. That is
roughly fourteen times the wall clock for 1.36 times the work.

Two of the three transcripts sitting in `artifacts/suite_cache/` are **truncated** —
8375 and 10920 lines with no `N passed` summary line against a complete run's 11449.
`tools/test.sh` refuses both, correctly, so nothing false was served; but a suite that
sometimes dies partway is a suite that costs twenty minutes and returns nothing.

This changes the shape of the problem. Before the measurement, the working hypothesis
was that the sweep's structure was the dominant cost. It is not: **one suite run is.**
A twenty-minute suite cannot fit inside a twenty-minute headless budget that also has
to hold 487 gate rows, and no amount of caching helps, because the budget requires the
suite to run at least once at the final source identity.

So the first question this pass has to answer is not "how do we run the suite fewer
times" — that is already answered — but **"why does one run cost twenty minutes and
13 GB, when it cost 83 seconds six weeks ago"**. `tools/lune/time_specs` is the
instrument, and its output lands in `spec-timings-before.json`.

---

## 2. What will be changed, in order

Each item names what it costs today, what it will cost, and the negative control that
proves it still bites. Nothing here lands without the mutation beside it.

### 2.1 Find and fix the suite regression *(first, because everything else is downstream)*

Attribute the twenty minutes per spec file and per case with `time_specs`, then treat
the top contributors as ordinary defects: measure the running system, find the cause,
fix the cause. A test whose implementation is slower than the behaviour it proves is
explicitly in scope; a test whose *coverage* is inconvenient is not.

The 13 GB resident figure is a lead in its own right. Luau's collector runs where it
runs, so a spec that retains everything it builds can charge its cost to whichever
spec happens to allocate next — which is also why the fix has to be found by
measurement rather than by reading the slowest name in the list.

### 2.2 Give the static-analysis battery the same treatment the suite already has

One shared mechanism, extending `tools/test.sh`'s design rather than competing with
it: a result is keyed by the **content** of the inputs it reads plus the exact command
and the pinned toolchain, written transcript-then-metadata by atomic rename into a
fingerprint-named file, and re-derived on every serve rather than trusted from its own
bookkeeping. Only exit-zero results are stored — a failure always re-runs, so a
producer that failed for an environmental reason cannot cache its own bad day.

The producers that get it are the deterministic scanners listed in §1, and only those.
The ones §1 names as un-cacheable stay exactly as they are.

Negative controls, each proven by breaking it on purpose in the existing
`tools/suite_cache_selftest.sh`: a changed input file, a changed command string, a
changed toolchain version, a truncated stored result, a stored result edited after the
fact, a failing producer, and a half-written entry.

### 2.3 Charge the settle wait only where something is being measured

`prior_gates.sh` settles before every gate. It will settle before the gates that
actually invoke a timing-sensitive producer — derived from the manifest, not from a
hand-maintained list, so a new bench row is covered the day it lands. The negative
control is a gate that gains a `bench.sh` row and must start settling again without
anyone editing the sweep.

### 2.4 Give Rascal Rally the tiers Facet already has

Rascal Rally has 219 spec files and 3,538 cases in one `lune run tests/run`, a
transcript cache that mirrors Facet's, and **no fast tier and no affected loop** — its
own `suite_transcript.sh` says so. Its cache fingerprint already spans Facet's `src`
and `tests`, which is correct and means every Facet edit invalidates it.

It gets the same tier mechanism Facet has, derived from the one `require` list in
`tests/run.luau` rather than a second list, printing a marker its own transcript
front-door refuses. The marker check is a bash match, never a pipeline: `printf | grep
-q` returns 141 under `pipefail` **when it matches**, and that exact mistake passed a
fast-tier transcript straight through once already.

### 2.5 Only then, parallelism

Parallelism is last on purpose. It is the change most likely to buy speed by creating
flakiness, and §1 lists six fixed, unlocked, non-atomically-written artifact paths that
would collide. It will be applied only to independent pure producers, with isolated
temporary and artifact paths and a concurrency cap taken from measured machine
capacity — and only if §2.1–§2.4 leave the budget unmet.

---

## 3. How the result is judged

- **Timings.** Cold and warm wall and CPU for both suites' fast/affected and full
  tiers, every unique deterministic producer, one attempt at this stage's gate, and
  the full prior-gate sweep. Before, after, and percentage. Studio, performance,
  device, and network time reported separately — never folded into the headless
  number.
- **One run per producer per identity.** Measured from an invocation trace over a real
  gate attempt, not asserted from the design.
- **Verdict parity.** Over a frozen pass/fail corpus, gate row by gate row, the
  optimized system returns what the old one returned.
- **The mutations bite.** Failed test, missing registration, changed result ID, stale
  cache, partial cache, changed source/tool/fixture input, failed producer, truncated
  artifact.
- **Every removal is mapped.** Requirement, producer, result, and negative control,
  for every execution removed or merged.
- **The budget.** The deterministic headless work this stage's gate requires finishes
  inside twenty minutes on the documented machine. If it does not, the honest outcome
  is to keep profiling — or to record the irreducible producers with owner, evidence
  class, cost, and the trigger that would make them worth optimizing — never to drop a
  required producer or relabel it external.
