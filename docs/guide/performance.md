# Performance

Measure the same workload on the same host with no competing build, test or
Studio work. Headless CPU timing does not measure engine layout or paint.

## Local checks

```sh
lute run tools/facet bench
lute run tools/facet perf footprint
```

The benchmark covers binding, collection, mutation and lifecycle workloads.
The footprint check counts Instances, connections and Compose resources through
mount, interaction and teardown. Preserve workload intent when implementation
changes. All owned resources must be released.

For native frame and memory behavior, use the performance lab and Studio
capture commands documented by `lute run tools/facet perf --help`. Compare
settled idle, an active task, repeated navigation and successful return.
Keep viewport, frame cap, graphics settings, warm-up and sample count equal.
A failed return is not a low-memory result.

## Paired source comparison

Prepare isolated source trees using the same toolchain and engine fixture:

```sh
lute run tools/facet perf paired run --out artifacts/paired --rounds 5 base=<base-tree> candidate=<candidate-tree>
lute run tools/facet perf paired report artifacts/paired base candidate --rounds 5 --gate
```

The runner interleaves arms and reverses order between rounds. Both trees use
the same measurement code while loading their own source. CI supplies the
candidate engine reflection fixture to both temporary trees; source remains
at each recorded revision.

Missing rounds, failed commands, unstable calibration and unavailable samples
fail as incomplete evidence. A consistent slowdown is a separate failure.
The report requires a ratio above 1.05 and every paired ratio above 1 to flag
a slowdown. p50 and p95 are medians of per-run percentiles.

CI compares complete scenes and microbenchmarks on Linux, macOS and Windows.
The required Verify check rolls them up. A statistical slowdown gets a complete
six-round recheck; an execution failure cannot become a narrowed passing run.
CPU calibration compares median yardstick rate before and after the run with
a 15% drift limit. CI permits one complete calibration retry, preserving the
failed attempt. A second calibration failure fails the job.

Use the current workflow and producer catalog for exact CI commands and
required scenes. A selected local run is not complete CI evidence.

## Interpret results

A ratio below 1 means the candidate takes less time. Keep workload differences,
host load and measurement limits visible. Headless results require separate
Studio evidence for native behavior; whole-client frame cadence includes the
authored world and can hide UI cost. Do not claim library savings from omitted
features or an easier scene.

Keep run data under artifacts. The current reports are evidence; old guide
narratives are not performance baselines.
