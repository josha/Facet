# LuauUI performance stress places

**Date:** 2026-07-24
**Status:** Proposed implementation and profiling plan.

## Outcome

Produce at least one self-contained, publish-ready Roblox place that makes LuauUI
performance problems easy to reproduce, profile, optimize, and compare on the weakest
supported Android device.

The place is not a visual demo and the existing Lune runner is not device evidence.
It is the engine/device half of the performance system: deterministic workloads,
stable MicroProfiler labels, repeatable capture windows, matched baselines, and enough
telemetry to tell whether a change improved LuauUI or merely changed the workload.

Follow the evidence rules in
[`agent-execution-contract.md`](agent-execution-contract.md). Reuse
the Studio matrix in
[`studio-device-verification.md`](studio-device-verification.md) for layout and
repeatability checks, while keeping it explicitly separate from physical performance.
Exercise the public package and metric contract from
[`theme-packages-and-skinning.md`](theme-packages-and-skinning.md); a palette-only
swap is not enough to measure theme cost.
Reuse
`bench/perf_scenes.luau`, `bench/perf_profiles.luau`,
`bench/perf_runner.luau`, `tools/lune/perf.luau`, the gallery's Studio scenario
surface, and the existing artifact/gate conventions.

## Place strategy

Start with one scenario-driven place:

- source under `examples/performance/`;
- a checked-in Rojo project file;
- built output at `examples/places/LuauUI-PerformanceLab.rbxl`;
- a deterministic scenario registry shared with headless scenes where their
  decisions overlap;
- a small launcher/status overlay that can be hidden completely during capture.

One place keeps the engine, content, rendering settings, and capture workflow
comparable. Add another place only if a measured isolation problem requires it—for
example, if a minimal native reference cannot be kept dormant without affecting the
LuauUI capture. If a second place is needed, give it a single documented purpose and
never compare MicroProfiler dumps from different places as though they were the same
workload.

Every emitted `.rbxl` must open and run without Rojo, local filesystem paths, private
assets, secrets, universe IDs, or a plugin. It must be safe for the user to open and
choose **Publish to Roblox** manually. The build work must not publish, upload, or
attach a place to a universe.

## Principal workload: dense interactive scrolling

The required centerpiece is a production-shaped scrolling list:

- a vertical scrolling collection with a configurable logical row count;
- each row is an `HStack` containing an image, a `VStack` of primary/secondary text,
  and representative controls such as a button, toggle, and value control;
- stable keys, varied but deterministic text, and a deterministic image set;
- native scrolling and clipping through the framework's current scroll substrate;
- virtualized and deliberately bounded non-virtualized variants;
- pointer wheel, touch pan, keyboard/gamepad focus traversal, and programmatic
  repeatable scrolling, each labeled separately;
- row selection, one-row updates, batched updates, insertion/removal/reorder, and
  focus keep-visible;
- cold-resource and warm/preloaded variants so network/decoding cost is not confused
  with steady-state framework cost.

The scenario must prove the row count, mounted/visible window, live Instances,
connections, layout/commit work, and scroll position. It must fail if “virtualized”
mounts the full logical collection.

Include a matched raw-Roblox reference for the principal workload using the same
dataset, images, approximate presentation, viewport, and interactions. Exactly one
implementation mounts during a capture. The reference is not expected to have every
LuauUI feature; it exists to separate unavoidable Roblox UI work from framework
overhead.

Run the LuauUI workload under both Studio Neutral and the most expensive shipped
asset-backed reference theme. Keep dataset, content, geometry contract, interactions,
and capture sequence identical. Record the package/snapshot version, active decoration
layers, preloaded assets, and effective metrics. Capture cold install, warm swap and
reflow, steady scroll, and teardown separately so ornate chrome is not confused with
LuauUI's ordinary flat-theme cost.

## Additional scenarios

Keep each scenario focused enough that a profile has an interpretable cause:

| ID | Scenario | Primary question |
|---|---|---|
| `idle-baseline` | Place and hidden launcher with no stress UI mounted | What does the place cost before LuauUI work? |
| `mount-ramp` | Increase a deterministic tree through safe row-count steps | How do initial mount, layout, Instance creation, and memory scale? |
| `dense-scroll` | Principal virtualized interactive list | Is steady scrolling smooth and windowing bounded? |
| `dense-scroll-native` | Matched raw-Roblox reference | Which cost is engine work versus LuauUI overhead? |
| `collection-churn` | Selection, edits, insert/remove/reorder while scrolling | Do updates stay proportional to changed/visible content? |
| `layout-style-churn` | Preferred text, locale length, resize/orientation, palette-only and metric/chrome theme swaps | Which invalidations cause unnecessary whole-tree work? |
| `async-image-churn` | Cold/warm image acquire, stale completion, failures, rapid reuse | Are decoding, resource lifecycle, and UI updates separated and bounded? |
| `lifecycle-soak` | Repeated mount/dismiss/reset plus a long scrolling run | Do Instances, connections, memory, or stale work trend upward? |

Add a scenario only when it isolates a distinct framework cost. Do not create a giant
“everything churns” workload that produces an uninterpretable profile.

Use safe ramp controls and an emergency stop. A stress tool should reveal the knee of
the curve without making Studio or a low-memory phone unrecoverable.

## In-place controls and reproducibility

The development overlay must provide:

- scenario, implementation, dataset size, seed, and run-mode selectors;
- warm-up, run, pause, reset, and automatic-sequence actions;
- visible source/build/scenario/device labels;
- a countdown and stable “capture now” period;
- current frame, LuauUI update, layout/commit, Instance, connection, memory, logical
  row, mounted row, and stale-resource counters where measurable;
- active theme package/snapshot, metric revision, decoration-layer, asset-fallback,
  and theme-swap/reflow counters;
- automatic export of scenario settings and telemetry;
- a clean capture mode that hides the launcher and unrelated overlays;
- one action that returns to the idle baseline and proves teardown.

The same seed and settings must reproduce the same data and scripted workload. Store a
version with every scenario contract. If a dataset or sequence changes, version it
instead of silently comparing it with older captures.

## MicroProfiler observability

Use current Roblox-supported profiling facilities. Verify their status before
implementation:

- [Roblox MicroProfiler documentation](https://create.roblox.com/docs/performance-optimization/microprofiler)
- [Roblox LibMP and its AI skill](https://github.com/Roblox/libmp)

Add stable, low-cardinality `debug.profilebegin()` / `debug.profileend()` scopes for
the scenario driver and the LuauUI phases that profiles need to distinguish, such as
model mutation, reactive propagation, layout/measure, arrangement, adapter commit,
resource completion, and scenario reset. Do not create a label per row, key, or node.
Balance scopes on every exit/error path and cover the wrapper with tests.

Use the Roblox-provided performance-profiling/LibMP skill through Studio MCP when it
is available. Capture binary `.gprx` data for automated/offline analysis where
supported; never expand every frame into a giant raw JSON artifact. Preserve the
original capture alongside derived summaries.

Studio captures are development evidence. A low-end Android capture comes from the
retail mobile client. Record at least:

- place/scenario version and framework version;
- device model, operating system, Roblox client version, orientation, graphics
  quality, target frame rate, and power/thermal conditions;
- implementation, dataset, seed, warm/cold resource state, warm-up, capture length,
  and repeat number;
- frame-time distribution and spikes;
- named LuauUI scope inclusive/exclusive times where the tooling exposes them;
- memory, live Instances/connections, mounted window, and stale/dropped resources;
- capture and derived-summary paths.

Do not invent a device budget from desktop or Studio numbers. Establish or ratify the
supported floor and frame target from real captures, then version the device budget.

## Optimization loop

For every investigated bottleneck:

1. reproduce it with one named scenario and stable settings;
2. capture multiple baseline runs on the same place, device, and conditions;
3. use the current Roblox profiling skill to identify the worst relevant scope and
   distinguish script, engine UI preparation, render, resource, and unrelated place
   cost;
4. state a falsifiable cause before changing code;
5. make the smallest framework change that addresses it without weakening behavior,
   row count, fidelity, or the budget;
6. run focused and full LuauUI tests plus the headless perf gate;
7. rebuild the same place and recapture the same scenario/settings;
8. compare multiple before/after captures and check other scenarios for regression;
9. record the result, including inconclusive or negative optimizations.

Never “optimize” by reducing the workload, hiding required content, lowering capture
quality, dropping accessibility/input behavior, or silently rebaselining. A changed
workload is a new scenario version.

## Publishing and review workflow

Extend `tools/build_places.sh` or add a clearly named companion builder so one command
rebuilds every performance `.rbxl`. Add a doctor/gate check that builds from a clean
source state and verifies the expected scripts, modules, scenario registry, and
version markers exist in the resulting place.

Document:

1. how to rebuild and open the place;
2. how the user can manually publish it as a private test place;
3. how to run the scripted Studio capture;
4. how to run and capture on Android through the mobile MicroProfiler;
5. how to invoke the Studio performance-profiling skill and compare captures;
6. how to return the place to idle and verify no retained work.

The agent must not perform the publish action.

## Evidence and completion

Register a canonical `performance-stress-places` gate using the existing manifest.
It must verify:

- publish-ready place sources and built `.rbxl` artifacts;
- deterministic scenario registry and reset/teardown;
- the principal dense-scroll workload and matched native reference;
- matched flat/ornate theme workloads and isolated install, swap/reflow, steady-state,
  asset-failure, and teardown costs;
- bounded virtualization and instrumentation correctness;
- MicroProfiler labels and capture metadata;
- headless scenario linkage without mislabeling it as device evidence;
- Studio preflight and representative captures;
- canonical Studio device-matrix smoke results for layout and scenario controls,
  labeled as emulation rather than low-end-device evidence;
- full LuauUI suite, registration, architecture, and existing perf gates;
- fresh-context architecture, runtime, Roblox-platform, and evidence review.

If no low-end Android is available, the gate may report automation complete with the
physical row explicitly pending and the publish/review packet ready. It may not claim
that LuauUI meets the low-end-device budget. Full completion requires repeated
physical captures on the declared floor device and resolution of framework-attributed
bottlenecks against the versioned budget.
