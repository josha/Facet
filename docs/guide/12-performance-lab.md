# Performance verification

Run `tools/bench.sh` without concurrent verification or builds. Preserve each
workload's population, mutation and lifecycle intent when changing implementation.
Do not compare a removed Facet layout phase directly to total native frame time:
engine layout moved outside the headless CPU measurement.

Measure binding storms, settings churn, keyed collection mutation, sparse updates,
mount ramps, table mutation/resizing, nameplates, typing and motion. Use the native
performance scenarios for live geometry and input-to-visible work.

Keep checked-in baselines intact. Report preexisting failures separately from
regressions. The old baseline already failed typing-storm on this host; that fact
is not permission to reset a threshold or omit the workload.
