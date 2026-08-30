# Timings — cold, warm, and the twenty-minute budget

Workstream T, D10. Every number here was taken from a run in this session.

## The machine, and where the numbers were taken

| | |
|---|---|
| Model | `sysctl -n hw.model` → **Mac16,11**; `hw.ncpu` → **14** |
| Memory | 64 GB |
| OS | Darwin 25.6.0 |
| Lune | 0.10.4 |
| StyLua | 2.5.2 |
| Python | 3.14.4 |
| Concurrency cap | `min(4, floor(cores / 4))` = **3** parallel producers; serialized ones never overlap |

**The release timings were taken in a frozen copy of the tree, and that is not a
convenience — it is the only way the measurement means anything.** Six agents
share the working tree during this stage, and the suite's identity is a content
hash over `src/ tests/ examples/`: a sibling landing one commit mid-run moves the
identity, so every producer that reaches the suite through the old front door
re-runs it. Measured directly: one `tools/verify.sh full` in the live tree spent
**two** full suite runs inside `tools/suite_cache_selftest.sh` alone, because the
tree moved under it twice. The copy is at
`/tmp/facet-mutation-parity/GameStudio/ui/Facet`, laid out with that path prefix
and a `games` symlink beside it so `../../../games/RascalRally/code` still
resolves; it is `rsync -a --delete` of the working tree minus
`artifacts/verify/`, `artifacts/suite_cache/` and `build/`.

## Headline

| Tier | Cold (empty result store) | Warm (nothing changed) | Producers | Reused warm |
|---|---:|---:|---:|---:|
| `full` | **308.4 s** (5 m 08 s) | **23.4 s** | 128 | 121 / 128 |
| `release` | **534.7 s** (8 m 55 s) | **146.5 s** (2 m 26 s) | 133 | 119 / 133 |

**The release run finishes in 8 minutes 55 seconds against a twenty-minute
budget** — 55 % of it, with 11 minutes to spare. Warm, the same run costs
2 minutes 26 seconds, and the two producers that dominate the cold number (the
suite at 266.6 s and the Rascal Rally suite) are both served from the store.

`/usr/bin/time -l` for each:

```
release cold   534.75 real   410.95 user   15.65 sys
release warm   146.48 real    62.34 user    5.77 sys
full    cold   308.38 real   365.51 user   13.78 sys
full    warm    23.42 real    49.51 user    4.90 sys
```

Row verdicts on the release run: **401 PASS, 34 FAIL_RECOVERABLE, 57 PENDING,
16 FAIL_ENVIRONMENT, 2 RETIRED, 0 unevaluated** across 510 rows and 33 phase
views. (The 57 PENDING are the distribution-readiness registration block and the
other stages' honest device/human rows; the FAIL_RECOVERABLE set is discussed in
`README.md`.)

Time by evidence class, cold, from the run record — Studio, device, performance
and external are reported here rather than folded into the headless number:

| Class | Producers | Seconds |
|---|---:|---:|
| deterministic | 96 | 336.8 |
| perf | 4 | 44.3 |
| studio (declared receipts, read not run) | 24 | 1.1 |
| device (declared receipts, read not run) | 7 | 0.3 |
| package | 1 | 6.0 |
| external (the Rascal Rally suite) | 1 | 0.3 warm / 42.6 cold |


## The ten slowest producers

From the cold release run:

```
 1. 266.63s  suite
 2.  22.62s  prove_perf_gate
 3.  10.42s  bench
 4.   9.88s  perf
 5.   7.15s  suite_cache_selftest
 6.   6.64s  check_boundary
 7.   5.91s  check_brand_drift
 8.   5.82s  package-verify
 9.   5.70s  check_brand_drift-skip-builds
10.   5.68s  check_brand_drift-selftest
```

The suite is 50 % of the cold release run on its own. Everything else together
is under 90 seconds.


## One run per producer per identity

`artifacts/verify/invocation-trace.json` is written one JSON line per producer
START, live, so a killed run still leaves its trace. The count below is that
file's own answer, not a claim from the design.

```
runId 20260830T214649Z-5741   release, cold    run 133   reuse   0   133 lines
runId 20260830T215543Z-2619   release, warm    run  14   reuse 119   133 lines
```

**No producer appears twice in either run.** The cold release run traced 133
starts for 133 producers; the warm one traced 14 runs and 119 reuses, again 133
lines, again with no repeats. That is the structural claim D10 asks for —
measured from the trace, not asserted from the design.

The trace also carries the reason a producer was NOT reused, which is how the
three defects in this workstream's own machinery were found: an input a producer
rewrote, a transcript path that did not survive a `cd`, and a canonical float
that did not parse back to itself.


## Irreducible producers

Two producers dominate and neither can be reduced by this workstream.

| Producer | Owner | Class | Cost | Trigger to revisit |
|---|---|---|---|---|
| `suite` | the library's own test suite | deterministic | 266.6 s | it is 50 % of a cold release run and 0 s of a warm one. It was 1,587 s at the Step 13.5 baseline and is 266 s now, after that stage's retention fix. The trigger is a spec set that grows the run past ~400 s: the per-spec ranking (`lune run tools/lune/time_specs`) is the instrument, and the standing answer is the tier mechanism, not a weaker suite |
| `suite_cache_selftest` | the transcript cache's own negative controls | deterministic | 7.2 s warm, up to 315 s when it has to start from a cold legacy cache | it proves the cache can refuse a stale, red, truncated or fast-tier entry, and to do that honestly it needs a real cached run to start from. The coordinator now hands it one out of the result store, which is what took it from 315 s to 7 s. The trigger is the legacy cache going away with the manifest, at which point this producer goes with it |

Nothing else in the graph costs more than 23 seconds. The four measurement
producers (`bench`, `perf`, `render`, `prove_perf_gate`) total 44 s and each
waits for the machine to go quiet FIRST — but only when it is actually going to
run, which is what took the warm release run from 502 s to 146 s.


## Against the Step 13.5 baseline

Step 13.5 measured the pre-conversion sweep on this same machine
(`artifacts/example-games-and-standalones/test-optimization/`): the suite at
1,587 s cold before its retention fix and 260 s after, the static battery at
about **140 s per sweep**, `tools/bench.sh` invoked eight times, `check_boundary`
fourteen, `stylua` eleven, and **261 trigger points** into the suite front door
across one 31-gate sweep — with `prior_gates.sh` replaying every earlier gate on
top of that.

| | Step 13.5 sweep | This release run | Change |
|---|---:|---:|---|
| Static battery (unique scanners) | ~140 s | **~68 s**, each command once | **−51 %** |
| Suite front-door triggers | 261 | **1** | one run per identity |
| Prior-gate replay | factorial in the regenerating gates | **0 s** — a lookup over rows already judged | removed |
| Whole headless run | not completable inside the budget (the suite alone was 26 minutes at the stage's open) | **534.7 s** | inside the budget with 11 minutes to spare |

The honest comparison for the battery is producer-by-producer, because the old
sweep's 140 s was 266 invocations of 124 distinct commands and the new run's 68 s
is 128 producers run once each; the difference is smaller than the invocation
count suggests precisely because the commands were cheap and the WASTE was in
repetition, which is what Step 13.5's own producer census concluded.

