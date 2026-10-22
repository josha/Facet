# Performance verification

## Running the benchmarks

Run `lute run tools/facet bench` when no verification or build runs at the same time.

When you change the implementation, keep the population, mutation and
lifecycle intent of each workload. Do not compare headless workload time
directly to the total native frame time. Engine layout is outside the
headless CPU measurement.

## Workloads

The benchmarks measure:

- binding storms,
- settings churn,
- keyed collection mutation,
- sparse updates,
- mount ramps,
- table mutation and resizing,
- nameplates,
- typing,
- motion.

Use the native performance scenarios for live geometry and for the work from
input to visible result.

Run `lute run tools/facet perf footprint` to count Instances, connections and
Compose resources for each control fixture. The census checks each fixture
without a theme and with a plain reactive theme. It includes closed and open
ColorPicker fixtures. The committed ceilings apply to each variant. All
resources must be released after teardown.

The October 2026 control audit compared the same fixtures with `6714507d`.
Deferring unused theme decoration reduced these connection counts:

| Reactive-theme fixture | Before | After |
| --- | ---: | ---: |
| Button | 14 | 3 |
| TextInput | 14 | 4 |
| Toggle | 23 | 3 |
| Slider | 43 | 14 |
| Open Picker | 104 | 68 |
| Open ColorPicker | 1045 | 616 |

These counts come from the engine double. They do not measure frame time.
The same audit checked Menu, Sheet, Dialog, Card and VirtualList fixtures,
and reviewed lazy content in TabView, NavigationStack and DisclosureGroup.
Those page and disclosure controls already defer content through Compose.
ColorPicker, automatic Picker and Pagination now retain responsive content
through temporary zero bounds.

Run `lute run tools/facet studio live ports_pickers --only color-open-readiness`
to measure ColorPicker construction and reveal separately. The case records
milliseconds and frames, checks the first visible layout, checks swatch identity,
and checks panel cleanup. It starts from the presentation state change. It does
not include touch dispatch latency. Device simulation does not measure physical
phone CPU speed.

ColorPicker now constructs only the selected mode and value format. The other
controls mount on first visit and remain until close. Against `6aaaf6a8`, the
open picker with a plain reactive theme uses 460 instances instead of 700,
616 connections instead of 840, and 3062 Compose holdings instead of 4074.
The resource ceilings record these lower counts. The Lab's "all colour modes"
state includes all four modes in one picker.

In a paired Studio run with a 390 by 844 touch layout, three openings had a
median construction time of 21.54 ms instead of 30.49 ms, and a median reveal
time of 50.28 ms instead of 66.85 ms. Both used three readiness frames. These
are host measurements, not physical iPhone measurements.

Run `lute run tools/facet studio live ports_pickers --only color-first-visit`
to check first visits with native input. This case measures from pointer
release to visible content, checks that the panel stays in place, and checks
that returning to a mode or format keeps the same controls.
In the same comparison, first visits to Spectrum, Sliders, HSV and Hex took
35–38 ms instead of 34–35 ms. Each visit appeared in two frames. Returning to
Swatches and RGB also took two frames and retained the original controls.

## Baselines and failures

Keep the checked-in baselines. Report preexisting failures separately from
regressions. The old baseline already failed typing-storm on this host. That
fact does not permit you to reset a threshold or to remove the workload.

## CI host

CI runs portable checks on Linux, macOS and Windows. It also requires the full
tier on a calibrated native reference host. The CPU and the architecture affect
wall-clock measurements. Confirm same-source timing spread before selecting
reference hardware. Compare captured timings with their host context. A change
of runner does not prove a runtime speedup.

The timing budgets block a run only on a reference host, which runs
`lute run tools/facet gate full --reference-host`. On every other host, the
`bench` timing producer requires the reference host, so the gate reports it as
`deferred` without running it. A failed `perf` timing budget is a `deferred`
producer; `perf` still runs, because `perf-scenes` and `perf-memory` read its
records. A release run blocks on both everywhere. The workload checks
(`perf-scenes`) do not measure time. They block on every host.

The required native CI job also supplies `--studio-host --require-complete`.
It fails when a full-tier producer is deferred or unsupported, or when the run
is narrowed. See the [native CI guide](../../tools/studio/CI.md) for host setup.

The budgets and workloads stay checked in. Each full run makes its own
performance report before it validates that report.
