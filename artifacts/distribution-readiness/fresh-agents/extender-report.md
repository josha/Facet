# Fresh-agent bounded extension (DR-30) — 2026-08-31: SUCCESS, with findings

A fresh agent with only the public clone added a Reset button to
examples/consumer through the documented workflow: README → CONTRIBUTING →
MAINTAINERS → the example's own README → the shared screen module. Test-first
honored (red at "expected 2 to be 0", then 16/16 green), fast tier 7165/0, the
change exactly three files, every applicable checker green on its files. The
registration guard caught a sibling agent's stray spec within minutes — working
as designed.

Findings adopted as the public-clone honesty round (verification agent):
RR-coupled checkers (check_brand_drift, check_call_shape_drift,
check_input_authority, suite_cache_selftest, one graph row, one
manifest-integrity pin) hard-fail when ../../../games/RascalRally is absent
instead of reporting the external consumer as missing; check_perf_metrics and
check_perf_scenes traceback on gitignored evidence; the affected tier selected
the place builders off overly-broad inputs and rewrote 14 tracked .rbxl (their
build stamps carry the build time — documented nondeterminism for DR-25);
rokit's trust prompt and the stale fast-tier timing note are doc fixes; the
fake target's tap() no-ops on an unknown path where driveActivate returns
false. MAINTAINERS §3 should name examples/consumer as the third example tree.
The live-Studio check on the new button is owed only if the change is adopted;
it remains a clone-side proof artifact.
