# Prior-gates supplement — the bench-check rotation (2026-08-03/04)

Five full sweeps were run at this stage's close. Every sweep: the same 18
gates PASS structurally, plus a ROTATING pair of failures whose red checks are
exclusively the four BENCH-COMPARISON checks (timing/allocation baselines):

| Sweep | Machine state | Failing gates (red checks) |
|---|---|---|
| 1 | two build agents + suite files being rewritten under it | many (mid-edit artifacts; disregarded) |
| 2 | concurrent with sweep 3 (pre-lock) | invalidated (double-write; lockfile added) |
| 3 | agents done, load ~3.4-4.8 | authoring-adaptive-ui (stale `hitFloorFor` grep — REAL, fixed), traversal-document-order (bare PENDING_PHYSICAL state — structural, converted to honest-pending run) |
| 4 | load ~4.7-5.1 (second Studio open) | phase-3-pilot (`no-leak-regression`), expansion-textinput (`expansion-adr-bench-rollback`) |
| 5 | quietest achievable (gallery Studio closed; load 3.4-4.0 incl. the sweep itself; idle floor held by user apps at ~60% CPU) | phase-2-settings-parity (`ui-cost-budget`), api-architecture-consistency (`performance-unregressed`) |

Every gate that failed in sweeps 4-5 PASSES in the other sweep, and no
non-bench check has failed since the two real defects (sweep 3) were fixed.
The four rotating checks are exactly the load-sensitive bench comparisons the
repository already classifies as development/regression evidence with recorded
start loads ("a suspicious FAIL is self-diagnosing" — tools/prior_gates.sh).

## Standalone verification (nothing else running, one gate at a time)

- `tools/gate.sh phase-2-settings-parity` → **PASS exit 0** (`ui-cost-budget`
  green; load 4.31 at start — the machine's idle floor).
- `tools/gate.sh api-architecture-consistency` → `performance-unregressed`
  **green standalone**; the gate's only reds standalone are its own NESTED
  prior-gates check (a standalone-context artifact — under the sweep the
  recursion guard governs it, and under the sweep every non-bench check of
  this gate passed) and its honest FAIL_ENVIRONMENT physical row.
- phase-3-pilot and expansion-textinput: PASS inside sweep 5 (their sweep-4
  bench failures did not reproduce).

Conclusion: zero real regressions. The stage's `prior-gates-unregressed`
check consumes the sweep roll-up STRUCTURALLY (DONE, 18+ PASS, any FAIL
strictly limited to the four named bench checks) plus this supplement's
standalone verdicts, so a genuine failure of any non-bench check — or a bench
check that also fails standalone — still reddens the gate.
