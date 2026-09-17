# Signals and component authoring: implementation evidence

The implementation replaces the custom dependency graph with Roblox Signals
0.9.0, pinned at `7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60`. Facet retains
its ordered transactions, change-only observers, lifecycle ownership, error
recovery and diagnostics around that graph. The vendor inventory is content
pinned; its MIT notice travels in the package. The previous graph is absent
from the shipped source. `core/custom` is a compatibility import only.

The native-Luau rehearsal is recorded in
`docs/plans/2026-09-16-showcase-authoring-mock.md`; the final user-facing model,
before/after examples, commands, row identity and lifetime rules are in
`docs/guide/15-components.md`. The showcase Motion settings and Settings Sync
screen now use the new API. Persistent model state stays outside components.

## What was exercised

- Components set up once per mount, automatically own state and subscriptions,
  and support tracked property functions without rerendering the component.
- Dense numeric children are validated and visited in index order. Native Luau
  shorthand compiled in Studio; arrow-function syntax was rejected.
- Tests cover keyed row reuse with current item getters, virtualization,
  controlled commands, cleanup on failure, manual watch cancellation, modifiers,
  confirmation metadata, Alert/Sheet ownership and official Signals interop.
- All 29 public control entries now expose spec types. Positive and negative
  type witnesses cover property values, child shapes, callback metadata and
  controlled getters. The targeted public type gate passes; this does not claim
  that the entire existing dependency graph is free of analyzer diagnostics.
- Studio mouse input drove Settings Sync through pending, accepted and rejected
  server decisions. An authored counter handled mouse and keyboard activation;
  confirmation invoked the action once with pointer metadata, and Sheet opened
  and closed through the existing presenter. A world SurfaceGui displayed the
  component and responded to an actual click. Screen and world canvas sizes
  were inspected in the live engine.

## Headless performance

The final isolated `tools/perf.sh` run passes all **135 runs / 27 scenes** with
the existing budgets. `tools/bench.sh` passes its **15 scenes**. The control-motion
probe now follows the existing DisclosureGroup `Reveal` wrapper; its previous
path reported zero observed flips on both the original and candidate trees.
The fix makes the probe observe the exercised content; no budget was loosened.

The separate FacetBench comparison used its clean
`3a98f9df833be5056d9f3e85c6ce79ebed512042` harness in an isolated copy, the
exact Facet baseline `c71a1610ba020450eb53aa54f5bb9c6725f8b586`, and the candidate.
The order was before, after, after, before: 750 samples, 50 warmup, all five size-L
workloads. Values below are the median of the two per-arm p95 measurements.
All 20 rows passed their behavioral/unmount checks, with yardstick drift below
10%. Earlier runs overlapping a background suite were discarded.

| Large workload | Before p95 ms | After p95 ms | Change |
|---|---:|---:|---:|
| Battle HUD | 1.777 | 1.986 | +11.8% |
| Damage fountain | 1.663 | 1.773 | +6.6% |
| Killfeed/nameplates | 2.220 | 2.300 | +3.6% |
| Nameplates | 5.793 | 6.286 | +8.5% |
| War room inventory | 19.422 | 19.923 | +2.6% |

Signals has a measurable cost; the result is within Facet's existing budgets,
not a claim of zero overhead. Retained virtualization and memo binding reuse
avoid adding a second component-level rerender loop. Heap swing is allocation
churn plus collector phase on this host, not a retention measurement.

Raw local evidence is under `artifacts/signals-migration/`: four isolated
FacetBench JSON files, `headless-comparison.json`, the final perf and bench JSON
and logs, and the Studio authoring readbacks. Artifacts are ignored build outputs;
the results and limitations are recorded here for a reader of the repository.

## Live Studio benchmark

The isolated place was built with candidate runtime marker `fff3a15a768f` and a
test-only copy of the old Core. All four runs used the same candidate renderer
and adapter, changing only the Core selected at mount. Marker, source byte counts
and selector were read from the live place before running. The temporary baseline
module is not in Facet's repository or package. Order was before/after/after/before,
300 samples and 30 warmup per size-L workload, one update per rendered frame.

The Studio server relay did not reach the client through this connection (zero
rows and no replicated arm attribute). Actual measurements used temporary
`RunContext.Client` scripts calling the normal client module cache. Each printed
its selected arm before calling the runner. No MCP-VM direct `main.run` calls
were used. Each matrix finished before the next began. The console contains four
matching source markers, four `FACETBENCH_DONE 5` records, and 20 status-ok rows.
The temporary benchmark Studio window was stopped and closed afterward.

| Large workload | Update p95 before/after ms | Whole-frame p95 before/after ms | GUI objects, both |
|---|---:|---:|---:|
| Battle HUD | 5.838 / 5.080 | 18.068 / 18.083 | 5,150 |
| Damage fountain | 4.020 / 4.070 | 18.102 / 18.241 | 202 |
| Killfeed/nameplates | 7.477 / 2.991 | 18.092 / 18.147 | 790 |
| Nameplates | 5.460 / 5.663 | 18.171 / 18.057 | 1,242 |
| War room inventory | 14.836 / 15.060 | 22.837 / 23.264 | 7,234 |

These are raw median-of-two p95 values, not normalized scores. Studio's yardstick
drift is too large to support normalized comparisons. Whole-frame time includes
the entire engine frame, not just Facet; the largest workload exceeded a 60 Hz
frame budget on both backends. This supports comparable live performance, not
a universal speedup claim. The runner's behavior, live geometry and teardown
checks passed. Raw rows and ordered arm markers are saved in
`artifacts/signals-migration/studio-benchmark-console.txt` and
`artifacts/signals-migration/studio-benchmark.json`.

## Scope and limitations

Billboard host construction, fixed canvas, reactive text and Adornee assignment
were inspected in Studio. A follow-up actual pointer click changed its counter
from 0 to 1. The billboard itself did not appear in the captured viewport,
including probes using the unchanged pre-migration target and a plain native
Roblox BillboardGui. The Mac was locked, preventing an independent native
viewport screenshot. Billboard visual appearance therefore remains unproven;
pointer activation passed. The existing conservative world-target fallbacks are
preserved. SurfaceGui visual and pointer validation passed. This does not promote billboard drag,
native scrolling or native styling, which were already withheld by that target.

Physical phone/console performance is outside this desktop Studio measurement;
existing physical-device receipts remain pending. Package verification/build
passed locally, with no publish or release approval claimed. The complete final
coordinator result is in `artifacts/verify/latest-full.json`; declared historical
evidence and unmeasured physical-device rows retain their existing classification.

## Consuming-game findings

The full coordinator's Rascal Rally suite found a stale hit-geometry bug in armed
navigation: the focus ring correctly skipped an ineligible racer, but the drag
verdict still used target rectangles captured before keep-visible scrolling.
`armTo` now refreshes target geometry before aiming. The new public drag case
failed before the fix and passes afterward; all 62 sponsor-card integration cases
pass, including the unchanged skip-and-commit assertion. Pointer acquisition and
the per-frame hot path are unchanged.

Signals also avoids work previously caused by equal memo results. The game's
minimap contract now asserts zero remainder solves with name tags enabled and,
for a one-dot move on its arm-only fixture, seven clean root skips and one reused
placement. It arranges 3 nodes, translates 2 and skips 22 (27 total). All-dot and
geometry-change assertions remain separate, and the differential geometry,
diagnostic and adapter-output checks pass. These are tighter work assertions,
not widened performance budgets. No game production behavior was changed.

The ABBA tables above predate only this armed-navigation correction; its code
path is outside the measured update workloads. Facet's performance and benchmark
gates are repeated after that correction, alongside final full verification.

The final source has **10,066 passing Facet tests** and **3,636 passing Rascal
Rally tests**. All **135 performance runs** and **15 benchmark scenes** pass.
One intervening benchmark overlapped a Studio restart and exceeded the typing
scene's normalized threshold; the quiet repeat passes at 1.43x its historical
baseline, below the unchanged 1.5x threshold, with 9.0% yardstick drift. The failed
run is retained as `bench-studio-restart-overlap.json/.log`, not silently dropped.

A live Studio canary used the new component syntax to arm, move and aim at a drop
target through an actual mouse activation. It reported Slot A as legal, and the
canary's normal-client commit call delivered exactly one drop to A. Its readback
is `studio-armed-geometry.json`. All temporary probes were removed by stopping
Play; the final showcase source stamp is `6fd5f453-9456019`, with zero stale modules.

The dependency scanner's new negative control proves that only the coordinator's
`artifacts/verify/tmp` source copies are excluded. Unexpected vendor directories
elsewhere still fail, and the shipped source pin, notices and built model remain
checked. The provenance receipt now includes the Signals addendum and hashes of
its complete MIT notice and source pin.
