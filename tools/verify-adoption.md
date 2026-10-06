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
- `tools/lune/bench.luau` keeps the comparison as a `judge`: the yardstick p95
  mean, the 1.5 factor, the millisecond floor, the p50 scenes, the drift limit
  and the heap checkpoints. The samples, the baseline and the thresholds are
  unchanged.
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

The benchmark comparison did not move. The stored-run comparison of Verify
uses raw samples. The Facet comparison divides by the yardstick, and a move
needs new baselines.

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

The live suites ran once in a Studio that Verify started. These results are
not compared with the removed relay path, because no Studio ran that path on
this commit. A failed case is a content check of the suite, not a harness
fault.

- All cases passed: `layout_geometry`, `primitives`, `table_resize`,
  `classb_themes`, `paint_live`, `scroll_live`, `text_live`, `weak3_geometry`,
  `haptics_setup`.
- Some cases failed: `mobile_regressions` 7 of 8, `needs_live` 8 of 12,
  `needs_live_b` 8 of 12, `needs_live_c` 5 of 13, `native_mechanisms` 4 of 6,
  `motion_continuity` 7 of 10, `navigation_split_view` 9 of 10,
  `classb_collections` 5 of 8, `classb_examples` 8 of 10, `classb_keyboard`
  15 of 17, `classb_navigation` 8 of 12, `in24` 18 of 32, `ports_content` 12
  of 15, `ports_foundation` 7 of 8, `ports_overlays` 11 of 15,
  `ports_pickers` 13 of 23, `sweep_b` 2 of 7, `weak3_surfaces` 13 of 15,
  `gallery` 0 of 4, `focus_probe` 0 of 19.
- No result in 600 seconds: `classb_showcase`, `in47`, `live_bugs`.
- The gamepad suites `focus_walk`, `focus_opened`, `gamepad_walk` and
  `haptics_verify` need the Controller Emulator. A new Studio process does not
  have it. They ran with `--studio ID` in a Studio with the emulator on, and
  `PreferredInput` was `Gamepad`. `focus_walk` passed but recorded no stops,
  and its atlases were not kept. `focus_opened` failed 15 of 15,
  `gamepad_walk` 12 of 12 and `haptics_verify` 1 of 1. `gamepad_walk` and the
  committed atlases name Showcase pages that the gallery does not have now.
  These suites need new content. That is not a harness fault.
- `native_mechanisms_input`, `needs_live_input` and `weak3_pointer` have only
  interactive cases.

A Studio that Verify started writes the progress file. An attached run has no
progress file at the pinned commit. Thus the key loop for D-pad Up of the
focus walk cannot read the `focus-upstream` step in an attached Studio yet.

On a loaded host, the `table-mutation` scene is at the 1.5 factor on main and
on this change.
