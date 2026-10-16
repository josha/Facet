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
| Open ColorPicker | 1045 | 840 |

These counts come from the engine double. They do not measure frame time.
The same audit checked Menu, Sheet, Dialog, Card and VirtualList fixtures,
and reviewed lazy content in TabView, NavigationStack and DisclosureGroup.
Those page and disclosure controls already defer content through Compose.
ColorPicker, automatic Picker and Pagination now retain responsive content
through temporary zero bounds.

Run `lute run tools/lute/studio_live.luau ports_pickers --only color-open-readiness`
to measure ColorPicker construction and reveal separately. The case records
milliseconds and frames, checks the first visible layout, checks swatch identity,
and checks panel cleanup. It starts from the presentation state change. It does
not include touch dispatch latency. Device simulation does not measure physical
phone CPU speed.

## Baselines and failures

Keep the checked-in baselines. Report preexisting failures separately from
regressions. The old baseline already failed typing-storm on this host. That
fact does not permit you to reset a threshold or to remove the workload.

## CI host

CI runs the full tier on the `ubuntu-latest` runner. The CPU and the
architecture of the host affect these wall-clock measurements. Compare captured
timings together with their host context. A change of runner does not prove a
runtime speedup.

The timing budgets block a run only on a reference host, which runs
`lute run tools/facet gate full --reference-host`. On every other host, CI included, the
`bench` timing producer requires the reference host, so the gate reports it as
`deferred` without running it. A failed `perf` timing budget is a `deferred`
producer; `perf` still runs, because `perf-scenes` and `perf-memory` read its
records. A release run blocks on both everywhere. The workload checks
(`perf-scenes`) do not measure time. They block on every host.

The budgets and workloads stay checked in. Each full run makes its own
performance report before it validates that report.
