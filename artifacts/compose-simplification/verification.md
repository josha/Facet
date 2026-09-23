# Engine cutover verification

`tools/verify.sh full`: PASS. 593 tests across 30 executable specs; all 24 producers passed. Types, negative type probes, formatting, boundary/coverage checks, gallery/showcase builds, distributable package checks, microbenchmarks and controlled performance passed.

Controlled performance: 135 records, unchanged budgets. The reference comparison measures Luau/control work, not native Engine rendering. Main could not initialize three original transient-surface workloads; those reference values remain unavailable.

Controlled p95 increases above 10% against the recorded same-host main reference:
- scroll-focus-traversal: 0.0852 → 0.1094 ms (1.28×); budget 0.1503 ms.
- theme-swap-assets: 0.3127 → 0.5397 ms (1.73×); budget 0.5593 ms.

See [performance values](final-performance.json), [complete tier report](final-full-report.json), and [Studio interaction evidence](gap-closure-live.json). Studio screenshots were inspected inline; this is not an exhaustive automated pixel comparison or physical-device certification. The Studio text preference was restored to Medium.
