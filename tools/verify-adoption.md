# Verify adoption receipt

Facet uses the same testing platform as Compose. Verify owns execution,
reports, deadlines, receipts and the acceptance verdict. Facet keeps its tests,
its workloads, its project policy and small bindings.

## What Verify owns

- `Gate.define` and `Lune.gate.run` run every producer as one plan. They
  bound each process group, keep the logs, apply the selection and compute the
  verdict. `tools/lune/producers.json` declares the producers.
  `tools/lune/gate.luau` binds the tier, the deferral policy and the build
  identity.
- `Lune.host` and `Lune.worker` run each source in its own Lune process with a
  run-bound receipt. `tests/worker.luau` passes the tier to each spec.
  `tools/lune/suite.luau` runs the committed plan and applies the committed
  case census.
- The gate outcome carries the build binding: commit, tree, clean state and
  package source hash. `tools/package.py` reads that outcome. The
  `facet-release-gate/1` record is removed.
- Verify UI fakes copy style, transition and path state on `Clone`.
  `tests/lib/native_engine.luau` no longer copies that state.

## What Facet keeps and why

- Architecture and historical coverage checks are project policy. They are now
  `tools/check_architecture.py` and `tools/check_coverage.py`, and the gate
  runs them as producers.
- `tests/lib/native_engine.luau` keeps the Facet facade: Compose signal
  adapters, `TweenInfo` attribute tokens, reflected default values, the
  `UIShadow` class, selection rejection records, text measurement callbacks
  and the eager record of cloned instances. The existing tests read these.
  It composes `Roblox.reflection`, `Roblox.uiFakes` and
  `Roblox.environmentEngine` directly. `Roblox.fixtureBridge` composes the
  same parts, but it also validates `SelectedObject` on each property write.
  The benchmark scenes run on this fixture, and that check measured about
  3 percent on a property write. The fixture is a native double. It does not
  prove engine behavior.
- `tools/lune/bench.luau` keeps its sampler and its comparison.
  `Verify.benchmark` declares a budget before the run and compares a raw
  baseline. The Facet comparison divides each scene by a yardstick that is
  measured before and after all scenes, and it applies a millisecond floor
  together with the ratio. The scenes also own setup, teardown and heap
  checkpoints. The samples, the baseline and the 1.5 factor are unchanged.
  Verify runs the benchmark as a gate producer with a deadline and an
  explicit deferral.
- `tools/lune/perf.luau` and the `check_perf_*` and `check_live_evidence`
  validators are Facet workloads and recorded evidence policy.

## Verdicts

| Run | Verify verdict | Exit |
|---|---|---|
| `release`, every producer passed | `release` | 0 |
| `release` with an environment deferral | `deferred` | 1 |
| `full` or `fast`, complete tier | `selected` | 0 |
| `--rerun <producer>` | `selected`, not tier evidence | 0 |
| A failed, timed-out or blocked producer | `failed` | 1 |

A studio, device or timing producer that exits 2 is `deferred` by name in the
gate policy. `--reference-host` removes the timing deferrals. A deferral is
never releasable.

The suite report that the gate adopts contains the cases that the tier must
run. The release-only case reports `skipped` with `tier:release` in
`artifacts/verify/native/suite.json` below the release tier. The gate expects
3,730 named cases in `full` and 3,731 in `release`.

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

Lune exits 1 when a required module raises, also inside `pcall`. Thus a source
that raises while it loads reports `unit:<source>:faulted`, not a load case.
The source still fails by name.

## Limits

Historical assertion parity is not established. Read the
[verification scope](../docs/guide/18-verification-scope.md). No library
source, example, benchmark workload, baseline or threshold changed. No Studio
check was necessary, because no geometry or input behavior changed.

Two baseline limits are not regressions. On a loaded host, the
`table-mutation` scene is at the 1.5 factor on main and on this change. Two
swipe cases in `native_parity_weaker_rows` fail in some parallel runs on a
loaded host: 4 of 48 runs on main and 2 of 48 runs on this change.
