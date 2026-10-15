# Headline report

Run from the repository root after all 30 runs and all 75 blind comparisons finish:

```sh
lute run eval/tools/report.luau artifacts/facetbench/games
```

The command writes `headline.md` and `quality.json` in that directory. It reads
`index.json`, the indexed `result.json` files and `judgments.json`. If
`labels.json` exists there, it also records Verify judge calibration. It does
not need the generated arm kits, the saved workspaces, an agent or Studio.
Exit 0 means that all approved quality rules, completeness checks and confirmed
overhead rules pass. Exit 1 means that one failed. Invalid input exits nonzero.
The headline is PASS only when every quality and overhead rule passes and
nothing is missing. Otherwise it is FAIL. Failed rules and missing evidence
appear first. Synthetic evidence does not establish live engine behavior.

Verify provides result decoding, judgment loading, quality rules, calibration,
means, medians and paired bootstrap intervals. The FacetBench command owns the
game manifest, overhead policy and markdown layout. No general statistics or
rendering capability is missing for this report. No Verify change is needed.
Any future general capability belongs upstream in Verify, without Facet names.

## Inventory at PR3

| Measurement | Recorded evidence | Measurement host |
| --- | --- | --- |
| Hidden check pass rate per device | `result.scores["play.fraction.<device>"]`; `checks[].cases` keeps case outcomes. `passRate` in Verify is the fraction of whole runs that pass, not the case fraction. | Cases run in the real Studio client and server. Verify aggregates headlessly. |
| UI audit violations | `result.audits[].rules`; Verify uses mean violations per audited screen. The dump is in `checks/dumps/<device>/<screen>.json`. | Properties come from Studio. Audit analysis is headless. |
| Blind comparison | Exists. `judgments.json` and `judgments/` record a task, device and seed comparison in both image orders. | External model judges Studio captures. No headless rendering. Human calibration is separate. |
| Tokens | `metrics.inputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `outputTokens`, `totalTokens`. Input excludes cached input. | Headless transcript parser. |
| Wall and turn latency | `metrics.wallSeconds`, `turnLatencies`, `turnIntervals`, `agentSeconds`, `toolSeconds`. Verify computes p50 and p95. | Host wall clock and time-stamped agent output. Not an engine measurement. |
| Type check | `scores["types.passed"]`, `scores["types.errors"]`, the `types` check result and logs. It is non-required. | Headless luau-lsp with pinned Roblox definitions. |
| Control usage | `eval/tools/coverage.luau` scans saved client source and writes `usage.json`. It counts Facet calls and helpers. It is descriptive and does not enter a verdict. Plain has no Facet controls by definition. | Headless static scan, not runtime activation coverage. |
| Instances | `play.perf.<device>.baseGuiObjects`, `baseComponents`, `peakGuiObjects`, `peakComponents`, `instanceDelta`, `guiObjectDelta`. PR3 has no total game UI instance count. | Real Studio census. `Stats.InstanceCount` covers the whole client; the UI census excludes engine and probe roots. |
| Mount | `play.perf.<device>.mountSeconds`: play start through probe readiness and UI geometry settling. Includes joining, host calls and fixed host waits. It is not isolated `Interface.mount` CPU time. | Studio play host wall time plus engine settle observation. |
| Steady and active frames | `idleFrameP50Ms`, `idleFrameP95Ms`; `activeFrameP50Ms` is the mean of screen medians and `activeFrameP95Ms` is the maximum screen p95. Raw windows are in `checks/perf.json`. | Real Studio `RunService.RenderStepped` delta. Whole-client frame pacing, not isolated UI CPU time or physical device evidence. |
| Memory return | PR3 has `heapDeltaKb`, `guiMbDelta` and instance deltas from mounted idle to immediate session end. It does not establish a returned hub or wait for collection. | Real Studio `gcinfo()`, `Stats.InstanceCount`, and `Stats:GetMemoryUsageMbForTag`. |
| Seed dollar cost | `metrics.costUsd` when an adapter supplies it. Codex does not supply it. | Headless adapter data. Missing USD remains unpriced. Seed token totals and wall time are always shown; billing needs external cost evidence. |

All eight rules in `thresholds.json` already have producers. Judge rules need
the separate `judge` stage. A report must not turn absent judgments into ties
or absent audits into zero violations.

## Added measurements and rules

The shared play host now counts all descendants and roots of the game UI as
`baseInstances`. It stops frame sampling between windows. This keeps the
probe's frame array from growing across the whole scenario.

At device end the host activates visible Close or Back buttons, using mouse
or gamepad selection as appropriate. It allows at most eight actions, waits
five seconds, then records the same two-second idle window used at mount.
`returned` records whether no further Close or Back control was found.
`heapReturnRatio` and `guiReturnRatio` divide final memory by mounted memory.
A failed return leaves these measurements absent. Disabled category memory
tracking also leaves GUI memory absent. No forced collection is used.

This is a hub retention check. It is not an unmount test. The owner must verify
that Close and Back return each implementation to the hub in Studio. Controls
with other labels, a confirmation or a route without a return control need
review. The same procedure applies to both arms.

> **Confirmed by the owner on 2026-10-15.** These limits are in
> `overhead.json`; they are separate from the approved quality rules.
> Require the upper 95% bound of Facet/plain to be at most **1.10 for mount
> time**, and **1.05 for idle frame p50 and p95** on every
> device. Require **1.05 for heap and GUI memory return ratios**, with every seed
> of each arm also at most **1.05 of its own mounted baseline**.
> `baseInstances` is **reported, not gated**, with a ratio and 95% interval
> for each device. It also stays in the per-task overhead cells.

Ten percent gives a small allowance for launch noise.
Five percent is stricter for continuous frame cost and retained memory. At a
16.67 ms frame interval it is about 0.83 ms. These are confirmed practical
bounds, not a measured noise floor. Vsync can hide CPU differences; the frame
claim covers observed pacing only. Validate noise on the target host.
A favorable ratio alone cannot excuse both
arms retaining memory, so the memory check also has an absolute per-arm bound.

The report requires every configured task, arm, agent and seed exactly once.
It checks audit counts, per-device case fractions, token provenance, latencies
and two valid judge presentations in opposite orders. Missing overhead data
fails the headline even if a partial bootstrap estimate looks favorable.
Overhead uses Verify's paired task bootstrap with the same configuration as
the quality rules. Each task value is the mean of its three seeds. Each device
gets its own rule. Per-task display values are medians, with separate run pass
rates. Follow-up tasks share history, so the interval does not establish five
independent games. The report states this limitation.

## Studio validation

No Studio was launched for this change. On an authenticated Studio host with
the MCP enabled, run these commands from the repository root:

```sh
lute run eval/tools/shared-kit.luau
lute run tools/facet kit --out artifacts/facetbench/arm-facet --force
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/games.json --parallel 1 --seed 1 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/games.json --parallel 1 --seed 2 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/games.json --parallel 1 --seed 3 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau judge --suite eval/games.json --transport api
lute run eval/tools/report.luau artifacts/facetbench/games
```

For each device and both arms, inspect the indexed run's `checks/perf.json` and
scores. Check positive mount time and frame sample counts, matching initial
and final idle windows, and a total UI count that equals roots plus GUI objects,
components and other descendants. Check `returned`, and observe that Close
and Back reach the same hub state before the final memory sample. Check that
heap and GUI ratios use positive mounted denominators. Disable memory tracking
for a diagnostic run and confirm that missing GUI memory fails the report.
Repeat a run on the same host to measure launch and heap noise. Confirm that
strong and weak reference behavior remains separated. Review human judge labels
before using the preference claim.

To recheck the play host against an existing workspace without rerunning an agent:

```sh
lute run eval/tasks/racing-hub/hidden/play.luau --workspace artifacts/facetbench/games/runs/racing-hub/plain/codex-sol/seed-1/workspace --outputs artifacts/facetbench/play-plain/out --captures artifacts/facetbench/play-plain/captures --report artifacts/facetbench/play-plain/report.json --run report-plain --scores artifacts/facetbench/play-plain/scores.json --devices desktop,phone-portrait,phone-landscape,tablet,console
lute run eval/tasks/racing-hub/hidden/play.luau --workspace artifacts/facetbench/games/runs/racing-hub/facet/codex-sol/seed-1/workspace --outputs artifacts/facetbench/play-facet/out --captures artifacts/facetbench/play-facet/captures --report artifacts/facetbench/play-facet/report.json --run report-facet --scores artifacts/facetbench/play-facet/scores.json --devices desktop,phone-portrait,phone-landscape,tablet,console
```

These diagnostic outputs do not update Verify's indexed results. Use the suite
commands for headline evidence. Do not reuse old results after changing the
play host: the suite digest does not include every host dependency. The explicit
`--fresh` commands above regenerate the measurements.

## Synthetic evidence

```sh
lute run tools/facet gate spec tools/headline
lute run eval/tools/report.luau artifacts/facetbench/synthetic-pass
lute run eval/tools/report.luau artifacts/facetbench/synthetic-instances
lute run eval/tools/report.luau artifacts/facetbench/synthetic-fail
lute run eval/tools/report.luau artifacts/facetbench/synthetic-missing
```

The Verify spec writes 30-result directories and 75 judgments. It covers passing
data, an instance count 100 times plain with a PASS verdict, failed mount
limits, each gated metric failing on each device, missing third-seed mount data, failed quality
rules, incomplete seeds, retention failure in both arms and absent judgments.
The first two report commands exit 0; the last two exit 1. Synthetic reports
use the confirmed headline rules. They prove report policy, not engine behavior.
