# Verify adoption receipt

Facet uses the same testing platform as Compose. Verify owns execution,
reports, deadlines, receipts, the case census, tier scope, benchmark sampling
and the acceptance verdict. Facet keeps its tests, its workloads, its project
policy and small bindings.

## What Verify owns

- `Lune.gate.cli` defines and runs the gate from `tools/lune/producers.json`.
  It owns the command line, the selection, process bounds, logs, scope and the
  verdict. `tools/lune/gate.luau` adds the tier names, the deferral policy and
  the build identity.
- The `suite` producer is a `tests` producer. Verify runs each source in its
  own Lune worker, four at a time, with a deadline for each source and a
  run-bound receipt. Its `cases` field is the committed census. A missing, an
  unexpected or a duplicate case fails the producer.
- A case with the tag `tier:release` runs only in the release tier. Below that
  tier, Verify records the case as deselected, and the run is not complete.
- The gate outcome carries the build binding: commit, tree, clean state and
  package source hash. `tools/package.py` reads
  `artifacts/verify/native/gate/latest.json`.
- `Roblox.fixtureBridge` is the test fixture. The specs use its simulated
  instances directly. `tests/lib/native_engine.luau` holds only the Facet
  configuration: the reshaped class database, the method doubles, the default
  lookup and the datatype table. The instance facade is removed.
- `Benchmark.collect` owns warmup, sampling, hooks and the shared yardstick
  for `tools/lune/bench.luau`.
- The fixture uses the virtual clock of Verify. A case controls the time that
  a control reads, and host load does not change a result.
- `Lute.studio.run` runs the live suites of `tools/studio/live`. It starts a
  new Studio process for each suite, runs the cases in the Client data model
  and returns the report. `tools/lute/studio_live.luau` builds the place and
  calls it. A case sends JSON to the host with `context:attach`, and
  `Lute.attachments.materialize` writes the files. The sync server, the inject
  script, the HTTP relay and the Facet receipt format are removed.

## What Facet keeps and why

- Architecture and historical coverage checks are project policy. They are
  `tools/check_architecture.py` and `tools/check_coverage.py`, and the gate
  runs them as producers. `replacement-cases` checks that each mapped case is
  in the census that the `suite` producer must pass.
- `tools/lune/bench.luau` maps each row of `bench/baseline.json` to a Verify
  `baseline`: the 1.5 factor as a tolerance, the yardstick p95 statistic, the
  p50 metric for the scenes that use it and the 0.05 millisecond floor on p95.
  Verify makes the comparison. The ratios are the same as the removed `judge`
  gave. Facet keeps the drift limit, the heap checkpoints and the report
  rows. The samples, the baseline and the thresholds are unchanged.
- `tools/lune/perf.luau` and the `check_perf_*` and `check_live_evidence`
  validators are Facet workloads and recorded evidence policy.
- `tools/lune/build.luau`, `release.luau` and `mkpair.luau` replace the shell
  scripts. `tools/studio/capture_viewport.sh` stays, because it drives the
  screen capture of the host.

## Fixture change and the benchmark

The benchmark scenes run on the test fixture. Without the facade, the cost of
the fixture changed: a property read is faster and a property write is slower.
Thus scene timings differ from earlier runs in both directions. The baseline
and the thresholds are unchanged, and the benchmark passes against them. Do
not compare a scene timing from before this change with one from after it.

## Verdicts

| Run | Verify verdict | Exit |
|---|---|---|
| `release`, every producer passed | `release` | 0 |
| `release` with an environment deferral | `deferred` | 1 |
| `full` or `fast`, complete tier | `selected` | 0 |
| `--only`, `--rerun` or `spec` | `selected`, not tier evidence | 0 |
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
[verification scope](../docs/guide/18-verification-scope.md). No example,
benchmark workload, baseline or threshold changed.

The topbar change of `UI.Composition` has live evidence. The case
`topbar-regions-side-by-side` of `mobile_regressions` fails without the change
and passes with it in a Studio that Verify started.

The fixture clock removed the load-dependent failure of the two swipe cases in
`native_parity_weaker_rows`. The source passed 48 of 48 parallel runs.

The release tier is not proven. The release-only source
`native_parity_weak3_rows` did not finish in its 600 second deadline on a
host with no free swap. It also did not finish in 25 minutes on main before
the cutover. The other release producers gave 74 passes and 4 timing
deferrals.

The live suites have failed cases that are older than the Verify migration.
The Showcase changed to task demos before the migration started. The live
suites did not change after that, and the committed results in
`artifacts/studio-live` are older than the Showcase change. Those results
show `classb_keyboard` 17 of 17, `classb_navigation` 12 of 12,
`classb_examples` 10 of 10 and `gallery` 4 of 4. In a Studio that Verify
started, the same suites give 15 of 17, 8 of 12, 8 of 10 and 2 of 4. No
Studio ran the removed relay path on this commit, thus the two paths are not
compared case by case.

The gamepad suites need the Controller Emulator. A new Studio process does
not have it. They ran with `--studio ID` in a Studio with the emulator on:
`focus_opened` 9 of 15, `gamepad_walk` 10 of 12, `haptics_setup` 1 of 1 and
`focus_walk` 1 of 1. `haptics_verify` needs real input between the two
haptics suites in one playtest. Run it by hand.

The focus walk recorded atlases for the six Showcase pages, with the D-pad Up
pass. The atlases of `hud` and `garage` agree with `UI.focusQuery` and are
committed. The atlases of `arcade`, `sipworks`, `files` and `ex02` disagree
with `UI.focusQuery` (1, 3, 6 and 37 problems). They are not committed, and
the committed `ex02` atlas is the earlier one. The atlases of the pages that
the Showcase does not have now are unchanged.

`native_mechanisms_input`, `needs_live_input` and `weak3_pointer` have only
interactive cases.

A Studio that Verify started and an attached Studio write the progress file.
`tools/lute/focus_up.luau` reads it and supplies D-pad Up for the focus walk.

On a loaded host, the `table-mutation` scene is at the 1.5 factor on main and
on this change.
