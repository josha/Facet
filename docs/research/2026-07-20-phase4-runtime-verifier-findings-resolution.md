# Phase 4 reactive-runtime verifier findings — resolution (2026-07-20)

Fresh-context Opus review of the Phase 4 runtime/lifecycle changes (core
quarantine, async provider, env clamps, presenter dismiss, solver clamps,
fuzz/fault models). Seven findings; all requirement-affecting ones fixed the
same session, each behind a failing test first (tests/lib/fault_scenarios.luau
unless noted).

| # | Severity | Finding | Resolution |
|---|---|---|---|
| F1 | critical | a throwing custom `eq` escaped `notify`, stranded `flushing=true`, silently killed all observers/effects, no `lastError` | `safeEq` wraps every user `eq` (quarantine → lastError, reads as "changed"); belt: `notify` itself pcalled in the flush loop. Test: `core-eq-quarantine` (1) |
| F2 | major | async retry swapped the request OBJECT, so releasing the last handle no longer cancelled → leaked concurrency slot, stale completion "applied", starvation | waiter accounting moved to a `Wave` shared across retries; release cancels against `requests[key]` when `current.wave == handle.wave`. Tests: `async-fixed` retry-then-release block; `async-storm` now asserts `active==0`/`queued==0` after dispose |
| F3 | major | `presenter.dismiss` of a NON-top handle popped the TOP focus scope → focus stranded on a disposed screen, live modal unreachable | `focus_graph.removeScope(name)` removes the handle's own scope (trap-restore entry included); presenter uses it. Test: `presenter-dismiss-non-top` |
| F4 | minor | throwing `eq` on a plain `set()` escaped to the writer | same `safeEq` path. Test: `core-eq-quarantine` (2) |
| F5 | minor | node `dispose()` left live observers counted in the registry | dispose marks each observer disposed and reclaims its counter; unsubscribe becomes a safe no-op. Test: `core-eq-quarantine` (3) |
| F6 | minor/uncertain | observers of a node disposed mid-notify still fired from the snapshot | resolved by the F5 fix (disposed flag now set, snapshot checks it). Ruling: snapshot iteration itself stays (deterministic order) |
| F7 | testing | fuzz/fault models never exercised custom-eq, feedback-cap, or effect-write paths; async storm never asserted slot neutrality | `scheduler-feedback` scenario locks effect-write convergence + loud cap; storm asserts active/queued zero; eq faults covered by `core-eq-quarantine` |

Verification after fixes: `./run-tests.sh` 230 passed; `tools/fuzz.sh`,
`tools/faults.sh`, `tools/perf.sh` all exit 0.
