# Benchmarks

Run `lute run tools/facet bench` from the repository root. The command runs
microbenchmarks with Verify sampling and compares them with `baseline.json`.
Run `lute run tools/facet perf run` for the performance scene matrix.

The full gate audits every scene and profile for resources, work and metric
provenance. Away from the reference host, it runs only the instrumented pass
and records historical timing as unchecked. `gate full --reference-host` also
runs the separate timing pass and checks the historical budgets. The required
paired CI comparisons keep their separate timing passes on all three platforms.
Physical-device budgets remain enforced when their captures are supplied.

## Scope

Headless durations include Compose reconciliation, bindings, control policy,
engine-boundary property writes, and simulated events. Roblox performs native
layout, text measurement, selection, image loading, and StyleSheet resolution.
The engine double does not perform that work. Faster headless numbers do not
prove total interface speed or physical device performance.

The benchmark fixture keeps mutable properties, events, and ownership separate
for each node. It caches immutable reflected defaults. It releases destroyed
nodes from diagnostic history and allocates ancestry and destruction signals
only when observed. Authored nodes and updates remain in the workload.

A CPU yardstick median drift above 15 percent makes the microbenchmark verdict
`FAIL_ENVIRONMENT`. This checks typical CPU rate, not tail stability. The raw
samples and p95 drift stay in the artifact. Paired workload p50 and p95 use
the same 5 percent rule. Heap samples depend on collector phase. Use deterministic
workload cases to check sampling, state changes, image ownership, and teardown.
Read the recorded baseline metric and regression factor before comparing rows.

Use [paired performance](../docs/guide/19-paired-performance.md) to compare two
source trees. Engine geometry, frame pacing, and physical device costs need
separate live evidence. A passing benchmark does not replace that evidence.
