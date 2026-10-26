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
The report requires the median ratio and every paired ratio to be above 1.05
to flag a slowdown. p50 and p95 are medians of per-run percentiles. A round
within the 5% tolerance does not confirm a regression. This rule rejects a
stable slowdown above 5%; a variable slowdown can remain unflagged. Inspect
the full measurements when investigating such a change.

CI compares complete scenes and microbenchmarks on Linux. A release also runs
the full suite on macOS and Windows before it publishes.
The required Verify check rolls them up. A statistical slowdown gets a complete
six-round recheck. A slowdown that remains after six rounds gets one fresh
complete confirmation run, and the gate fails only for a scene or measurement
that is slower in both runs. An execution failure cannot become a narrowed
passing run.
CPU calibration compares median yardstick rate before and after the run with
a 25% drift limit. CI permits one complete calibration retry, preserving the
failed attempt. A second calibration failure fails the job.

Use the current workflow and producer catalog for exact CI commands and
required scenes. A selected local run is not complete CI evidence.

## Published results

Each push to `main` publishes the pr arm of its paired performance shards to
the `perf-results` branch. `lute run tools/facet perf publish` keeps one file
for each commit under `results/`. It writes `README.md` with the p50, p95 and
retained heap of every scene, the p50 and p95 of every microbenchmark, the
change from the previous commit and scene trend charts. The values come from
the CI Ubuntu runner, so compare them only within that history.

## Measure runner noise

Run the CI workflow manually with `diagnostic` set to `true`. Set `base` and
`candidate` to the same full commit SHA. This runs three independent A/A samples
on Linux, even when the source trees match. Each sample uses the normal
complete performance gate, including its three-round checkpoint and six-round
continuation. The diagnostic does not retry failed samples or replace the
required Verify check.

Keep every sample and its exit status. Exit 0 is a valid pass. Exit 1 is a
complete false positive because both arms contain the same source. Exit 75
means invalid CPU calibration; exit 2 or a setup failure means unusable evidence.
Count false positives over valid samples and report unusable samples separately.
Keep platforms separate. Three samples per platform are a pilot, not a precise
estimate of the failure rate.

Inspect absolute times and p50 and p95 separately before changing the gate.
The median CPU calibration does not prove stable tail latency. Do not infer
an absolute timing floor from one noisy run. Any proposed threshold must also
reject a planted slowdown in the affected workload. Retain the first failure;
a passing rerun alone does not prove that a slowdown was noise.

## Interpret results

A ratio below 1 means the candidate takes less time. Keep workload differences,
host load and measurement limits visible. Headless results require separate
Studio evidence for native behavior; whole-client frame cadence includes the
authored world and can hide UI cost. Do not claim library savings from omitted
features or an easier scene.

Keep run data under artifacts. The current reports are evidence; old guide
narratives are not performance baselines.
