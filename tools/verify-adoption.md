# Verify adoption receipt

Facet uses the same testing platform as Compose. Verify owns execution,
reports, deadlines, receipts, the case census, tier scope, benchmark sampling
and the acceptance verdict. Facet keeps its tests, its workloads, its project
policy and small bindings.

## What Verify owns

- `Gate.define` and `Lune.gate.run` run every producer as one plan. They bound
  each process group, keep the logs, apply the selection and compute the scope
  and the verdict. `tools/lune/producers.json` declares the producers.
  `tools/lune/gate.luau` binds the tier, the deferral policy and the build
  identity.
- The `suite` producer is a `tests` producer. Verify runs each source in its
  own Lune worker, four at a time, with a deadline for each source and a
  run-bound receipt. Its `cases` field is the committed census. A missing, an
  unexpected or a duplicate case fails the producer.
- A case with the tag `tier:release` runs only in the release tier. Below that
  tier, Verify records the case as deselected, and the run is not complete.
- The gate outcome carries the build binding: commit, tree, clean state and
  package source hash. `tools/package.py` reads that outcome.
- `Roblox.fixtureBridge` composes reflection, UI fakes, clone state and the
  engine seam for `tests/lib/native_engine.luau`. The fixture installs no
  validator for each property write, so the cost of a write did not change.
- `Benchmark.collect` owns warmup, sampling, hooks and the shared yardstick
  for `tools/lune/bench.luau`.

## What Facet keeps and why

- Architecture and historical coverage checks are project policy. They are
  `tools/check_architecture.py` and `tools/check_coverage.py`, and the gate
  runs them as producers. `replacement-cases` checks that each mapped case is
  in the census that the `suite` producer must pass.
- `tests/lib/native_engine.luau` keeps the Facet facade: Compose signal
  adapters, `TweenInfo` attribute tokens, reflected default values, the
  `UIShadow` class, selection rejection records and text measurement
  callbacks. About 4,000 call sites in the specs read this facade. The fixture
  is a native double. It does not prove engine behavior.
- `tools/lune/bench.luau` keeps the comparison as a `judge`: the yardstick p95
  mean, the 1.5 factor, the millisecond floor, the p50 scenes, the drift limit
  and the heap checkpoints. The samples, the baseline and the thresholds are
  unchanged.
- `tools/lune/perf.luau` and the `check_perf_*` and `check_live_evidence`
  validators are Facet workloads and recorded evidence policy.

## Verdicts

| Run | Verify verdict | Exit |
|---|---|---|
| `release`, every producer passed | `release` | 0 |
| `release` with an environment deferral | `deferred` | 1 |
| `full` or `fast`, complete tier | `selected` | 0 |
| `--rerun` or `spec` | `selected`, not tier evidence | 0 |
| A failed, timed-out or blocked producer | `failed` | 1 |

A studio, device or timing producer that exits 2 is `deferred` by name in the
gate policy. `--reference-host` removes the timing deferrals. A deferral is
never releasable.

## Failure injection

`tools/lune/verify_integration.luau` runs on the shared path. It covers a
missing source, a load failure, a registration failure, a value that is not a
function and an empty source. It covers case and cleanup failures, duplicate
IDs, an unapproved skip, census drift and the release-only tier. It covers a
missing, empty, malformed, foreign, stale, invalid and contradictory worker
receipt, and the same faults for a producer report. It covers a deadline that
stops the descendants of a worker and of a producer, a blocked dependent, each
exit class, the reference host and each verdict.
`tools/tests/test_project_checks.py` covers the architecture and coverage
policy. `tools/check_live_evidence.py --selftest` covers incorrect host and
device claims in the recorded evidence.

## Limits

Historical assertion parity is not established. Read the
[verification scope](../docs/guide/18-verification-scope.md). No library
source, example, benchmark workload, baseline or threshold changed. No Studio
check was necessary, because no geometry or input behavior changed.

Two baseline limits are not regressions. On a loaded host, the
`table-mutation` scene is at the 1.5 factor on main and on this change. Two
swipe cases in `native_parity_weaker_rows` fail in some parallel runs on a
loaded host: 4 of 48 runs on main and 2 of 48 runs on this change.
