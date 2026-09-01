# FacetBench — carried items for Plans 2 & 3 (from Plan 1 final review, 2026-08-31)

Plan 1 complete at FacetBench `6addcde` (14+1 commits, check.sh green, Phase-1 gate satisfied).

## Plan 2 opening chores (small, do first)
- tests/facet_adapter.spec.luau:53 — dead guard: `#before` must be `#beforeOrder` (canary never fires).
- matrix_util.acceptChild — require the decoded last line to be a JSON OBJECT (array currently passes the table check).
- tools/check.sh runs the ~10-window selftest twice (spec + check_runner) — dedupe if gate time matters.
- matrix_util.parseArgs: a trailing flag with no value silently falls back to defaults — make it loud.
- stable_json emits bare nan/inf for non-finite numbers (invalid JSON); schema only checks type=="number".

## Plan 2 entry criteria / design inputs
- AUDIT every vendored rival's hot paths for bare accumulate-only numeric loops — the Luau loop-shape bimodality (~2.6x sticky regimes; see fixture burn comment + CONTRIBUTING methodology) applies and the yardstick cannot normalize it.
- war_room_inventory should actually emit `reorder` steps (today no workload does; both adapters now assert-strict on it).
- Consider a CROSS-ADAPTER comparable digest (list lengths, key order, bound scalar values) — today snapshots are per-adapter-shaped, so a framework doing LESS work than another cannot be caught mechanically; the defect class that motivated the cycle-safety wave was found by accident.
- run_one heapNetKb reads at whatever script phase samplesN lands on (small samplesN-dependent offset) — note in methodology or fix when adding rivals.
- CI workflow (check.sh on every PR) once the repo goes public.

## Plan 3 / Phase 4 bookings
- Gate committed baselines on yardstickDriftPct (S-size rows showed 12-19% drift under load; nothing gates on it yet).
- Fixture absolute cost changed at f5b8184 (BURN_SPIN 400 + immune loop shape) and 6addcde-era semantics — results predating them are not comparable; baselines must postdate.
- SPEC CORRECTION for Part 2 / D2: "heap delta via gcinfo with GC quiesced" is NOT achievable — Lune's collectgarbage accepts "count" only; D2 needs a different allocation instrument (counters, not heap quiescence).
