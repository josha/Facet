# Headline report

For the historical Claude paired slice measurement, with a reused Plain run
and a fresh Facet run, see the [slice report](reports/slice.md). The
[first fresh Sol pair](reports/slice-sol61-medium.md) passed required Facet
behavior but failed the efficiency and memory goals. A separate Sol judge
preferred Facet overall, while Plain won polish. The Claude judge reached its
quota. This pair does not prove the overhead bounds below.
The [second attempt](reports/slice-sol61-medium-2.md) ended with a Facet author
capacity error. Its missing usage and incorrect adapter success status prevent
an efficiency claim. Native checks still found memory limits unmet and changes
in frame pacing that need separate timing validation.
The [third fresh pair](reports/slice-sol61-medium-3.md) completed both authors.
Facet passed 13/13 universal checks versus Plain's 1/13, but used 4.568 times
the tokens and 3.062 times the author wall time. Diagnostic coverage and
memory limits remain unmet; frame samples measure cadence. The completed blind
judge preferred Plain on both devices in both image orders, including all
four polish judgments. Required-check success does not establish the headline
goals or a visual-quality win for this pair.
The [fourth fresh pair](reports/slice-sol61-medium-4.md) again passed 13/13
Facet universal checks versus Plain's 1/13. Facet used 1.426 times the tokens
and 1.084 times the author wall time. The ratios narrowed as Facet's run
shortened and Plain's grew; this does not isolate a causal improvement.
Efficiency and memory goals remain unmet, and the diagnostic Plain phone
return has missing final memory. Plain again won both blind comparisons in
both image orders, including all four polish judgments; Facet retained
fitness strengths without an overall visual-quality win for this pair.
To diagnose a saved Sol workspace, repeat its hidden checks without invoking
an agent:
`lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/slice.json --checks-only --parallel 1`.
Verify archives the previous check evidence and preserves agent metrics,
transcripts, timestamps and build files. To generate its headline, use
`lute run eval/tools/report.luau artifacts/facetbench/slice-sol61-medium --suite eval/slice.json`.
These commands use the current Sol suite, not the historical Claude workspaces.
Rechecking cannot measure author efficiency improvements. The first Sol pair's
recorded turn-event gaps are not model latency evidence; see its report before
interpreting timing percentiles. Run both arms fresh after shared fixes.

The headline suite is `extended.json`: 22 runs and
55 blind task/device/seed comparisons. The hub and ten follow-ups use short
player prompts. `extended-spec.json` keeps the detailed briefs. The headline
run pass rate uses the universal tier, contract integrity, completion and
budgets. Spec failures do not gate it. Universal audits and the blind judge
remain in the quality rules. The limits are in `overhead.json` and `thresholds.json`. Missing universal scores fail closed. Both tier fractions appear
in `headline.md`; diagnostic captures stay outside the judge's image set.

See [the tier table and calibration commands](README.md#check-tiers-and-calibration). The slice report contains two-device checks and blind comparisons; it does not record human judge calibration. The Facet CLI is available only in the Facet arm. Runtime rescoring is sequential. Missing scoped Studio tools cause setup failure.

Before console mount settling and captures, the shared host selects a native
control, when available, and sends one Right directional key through VirtualInput. The Xbox
simulator preset alone does not establish the last input type. This prepares
the emulated navigation path; it does not prove physical controller input.

Run from the repository root after all 22 runs and 55 blind comparisons finish:

```sh
lute run eval/tools/report.luau artifacts/facetbench/extended
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

## Measurement inventory

| Measurement | Recorded evidence | Measurement host |
| --- | --- | --- |
| Hidden check pass rate per device | `result.scores["play.universal.<device>.fraction"]`; `checks[].cases` keeps case outcomes. `passRate` in Verify is the fraction of whole runs that pass, not the case fraction. | Cases run in the real Studio client and server. Verify aggregates headlessly. |
| UI audit violations | `result.audits[].rules`; Verify uses mean violations per audited screen. The dump is in `checks/dumps/<device>/<screen>.json`. | Properties come from Studio. Audit analysis is headless. |
| Blind comparison | Exists. `judgments.json` and `judgments/` record a task, device and seed comparison in both image orders. | External model judges Studio captures. No headless rendering. Human calibration is separate. |
| Tokens | `metrics.inputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `outputTokens`, `totalTokens`. Input excludes cached input. | Headless transcript parser. |
| Wall and turn latency | `metrics.wallSeconds`, `turnLatencies`, `turnIntervals`, `agentSeconds`, `toolSeconds`. Verify computes p50 and p95. | Host wall clock and time-stamped agent output. Not an engine measurement. |
| Type check | `scores["types.passed"]`, `scores["types.errors"]`, the `types` check result and logs. It is non-required. | Headless luau-lsp with pinned Roblox definitions. |
| Control usage | `eval/tools/coverage.luau` scans saved client source and writes `usage.json`. It counts Facet calls and helpers. It is descriptive and does not enter a verdict. Plain has no Facet controls by definition. | Headless static scan, not runtime activation coverage. |
| Instances | `play.perf.<device>.baseGuiObjects`, `baseComponents`, `peakGuiObjects`, `peakComponents`, `instanceDelta`, `guiObjectDelta`. `baseInstances` counts all game UI roots and descendants. | Real Studio census. `Stats.InstanceCount` covers the whole client; the UI census excludes engine and probe roots. |
| Mount | `play.perf.<device>.mountSeconds`: play start through the start of the first complete layout run that stays stable for one second of rendered frames, excluding only each element's own live content or fill changes. Includes joining, probe readiness, host calls and fixed host waits. | Studio play host wall time plus per-object engine layout observations. |
| Steady and active frames | `idleFrameP50Ms`, `idleFrameP95Ms`; `activeFrameP50Ms` is the mean of screen medians and `activeFrameP95Ms` is the maximum screen p95. Raw windows are in `checks/perf.json`. | Real Studio `RunService.RenderStepped` delta. Whole-client frame pacing, not isolated UI CPU time or physical device evidence. |
| Memory return | `heapDeltaKb`, `guiMbDelta` and instance deltas compare mounted idle with the returned-hub sample after the return wait. | Real Studio `gcinfo()`, `Stats.InstanceCount`, and `Stats:GetMemoryUsageMbForTag`. |
| Retained usage | `finalHeapKb` and `finalGuiMb` record positive heap and GUI memory in the returned hub. | The same final Studio sample; whole-client usage, not isolated UI allocation. |
| Seed dollar cost | `metrics.costUsd` when an adapter supplies it. Codex does not supply it. | Headless adapter data. Missing USD remains unpriced. Seed token totals and wall time are always shown; billing needs external cost evidence. |

All eight rules in `thresholds.json` already have producers. Judge rules need
the separate `judge` stage. A report must not turn absent judgments into ties
or absent audits into zero violations.

## Overhead measurements and rules

Mount compares every measured UI object's identity, parent, absolute position
and absolute size each frame. Structure changes restart the stable run. A
TextLabel or TextButton with a Text change in that frame is live content. An
element can change size on one axis inside a fixed-size parent if its own
position stays fixed. Other geometry changes, including two-axis reflow and
neighbour movement from a live counter, restart the run. The same rules apply
to both arms and to strong and weak references. An empty screen cannot settle.

The settle limit is 20 seconds. Failure-bound captures keep `mount.timedOut`,
the `mountTimedOut` score and a host log entry. Their value uses the bound.
The raw bound stays in `perf.json`. A timeout emits no valid `mountSeconds`
score, so the existing missing-evidence rule fails closed.
`checks/perf.json` keeps excluded element paths, reasons, frame counts and first
and last observation times in `mount.liveContent`. The saved-workspace command
`lute run tools/facet facetbench mount WORKSPACE OUTPUT` records both definitions
on the same frames as `mountSeconds` and `legacyMountSeconds`, with separate
timeout flags. The mount ratio limit is 1.10.

The shared play host counts all descendants and roots of the game UI as
`baseInstances`. It stops frame sampling between windows. This keeps the
probe's frame array from growing across the whole scenario.

After the universal cases the host activates visible Close or Back buttons, using mouse
or gamepad selection as appropriate. It allows at most eight actions, waits
five seconds, then records the same two-second idle window used at mount.
`returned` records whether no further Close or Back control was found.
`heapReturnRatio` and `guiReturnRatio` divide final memory by mounted memory.
A failed return leaves these measurements absent. Disabled category memory
tracking also leaves GUI memory absent. No forced collection is used.
Before each idle window, the probe waits at most 20 seconds for the first
positive finite GUI memory reading, unless tracking is disabled. This wait is
outside mount timing and the fixed sample window. `memoryReadiness` records
attempts, elapsed time, tracking and timeout. The actual window's memory sample
is preserved, including zero or missing values.
`finalHeapKb` and `finalGuiMb` report positive post-return samples only after
a successful return. Their Facet/plain ratios compare retained usage directly.
Return ratios compare growth against each arm's own mounted hub; equal return
ratios do not imply equal retained usage.
The spec producer uses fresh game sessions with separate performance evidence.
A diagnostic failure or timeout cannot change the headline memory result.

This is a hub retention check. It is not an unmount test. Verify
that Close and Back return each implementation to the hub in Studio. Controls
with other labels, a confirmation or a route without a return control need
review. The same procedure applies to both arms.

> These limits are in
> `overhead.json`; they are separate from the approved quality rules.
> Require the upper 95% bound of Facet/plain to be at most **1.10 for mount
> time**, and **1.05 for idle and active frame p50 and p95** on every
> device. Require **1.05 for post-return heap and GUI memory usage** and
> **1.05 for heap and GUI memory return ratios**, with every seed
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
the quality rules. Each task value is the mean of its configured seeds. Each device
gets its own rule. Per-task display values are medians, with separate run pass
rates. Follow-up tasks share history, so the interval does not establish five
independent games. The report states this limitation.

## Studio validation

Use the 11-turn reference calibration loop in [the evaluation guide](README.md#studio-calibration-commands). Use an authenticated Studio host with the MCP enabled:

```sh
lute run eval/tools/shared-kit.luau
lute run tools/facet kit --out artifacts/facetbench/arm-facet --force
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/validation/games.json --parallel 1 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau run --suite eval/extended.json --parallel 1 --seed 1 --fresh
lute run tools/vendor/verify/tools/agent-eval.luau judge --suite eval/extended.json --transport api
lute run eval/tools/report.luau artifacts/facetbench/extended
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
lute run eval/tasks/racing-hub/hidden/play.luau --workspace artifacts/facetbench/extended/runs/racing-hub/plain/codex-sol/seed-1/workspace --outputs artifacts/facetbench/play-plain/out --captures artifacts/facetbench/play-plain/captures --report artifacts/facetbench/play-plain/report.json --run report-plain --scores artifacts/facetbench/play-plain/scores.json --devices desktop,phone-portrait,phone-landscape,tablet,console
lute run eval/tasks/racing-hub/hidden/play.luau --workspace artifacts/facetbench/extended/runs/racing-hub/facet/codex-sol/seed-1/workspace --outputs artifacts/facetbench/play-facet/out --captures artifacts/facetbench/play-facet/captures --report artifacts/facetbench/play-facet/report.json --run report-facet --scores artifacts/facetbench/play-facet/scores.json --devices desktop,phone-portrait,phone-landscape,tablet,console
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
