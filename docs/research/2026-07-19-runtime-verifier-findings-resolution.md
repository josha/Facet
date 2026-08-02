# Reactive-runtime verifier findings — resolution log (2026-07-19)

Fresh-context Opus review of the custom core + conformance suite (pre-gate).
Verdict was FINDINGS: 1 major, 6 minor. All resolved or explicitly dispositioned; each fix carries a corrective conformance check (suite now 26 checks; custom passes 26/26; full suite 54).

| # | Finding | Resolution | Corrective check |
|---|---|---|---|
| 1 | MAJOR: stale `changed` flag on unobserved intermediate memos caused a spurious observer fire on an unchanged recompute | Observer model rewritten: per-observer `lastSeen` compared with the node's equality at notify time; the `changed` flag is gone (src/core/custom.luau) | `no-spurious-fire-on-unchanged-recompute` |
| 2 | Mid-transaction derived reads were stale (partially-propagated graph observable) | Writes eagerly mark downstream memos stale; pulls inside the transaction recompute; observers still fire only at flush | `mid-transaction-derived-reads-fresh` |
| 3 | Double disposal idempotent but undetected (§6.3 requires detection) | `scope_impl.factory` takes an `onDoubleDispose` hook; all three cores surface it via `lastError()` | `double-dispose-detected` |
| 4 | Fusion adapter claimed `cycleDetection=true` while failing the cycle check | Claim corrected to false (report goes to Fusion's external logger, unqueryable); cli now FAILS any core whose claims contradict its scorecard | cli `claimsMismatches` (exit 1 on mismatch) |
| 5 | 20-round cap misdiagnosed a legitimate 25-hop effect chain and silently discarded writes | Cap raised to 100 (effect-write generations, not depth); cap error now reports the number of discarded writes. Discarding remains the halt mechanism — documented in-code | existing `feedback-loop-hits-iteration-cap` (still passes) |
| 6 | Observer-set mutation mid-flush: undefined iteration, nondeterministic order, mid-flush subscriber received in-progress notification | `notify()` snapshots observers sorted by registration seq; disposed observers skipped; late-added observers baseline at current value and fire next change | `observer-disposed-by-sibling-does-not-fire`, `observer-added-mid-flush-fires-next-flush-only` |
| 7 | Mutation confirm-before-snapshot left permanent optimistic divergence; multi-send raw assert; expectedRevision unthreaded | `confirm()` re-syncs optimistic state from current authoritative truth; send-while-pending is a structured error; envelope test pins requestId+expectedRevision (server-side validation per §4.2) | 3 new tests in tests/replication.spec.luau |
| — | NaN equality blind spot | NaN-safe `defaultEq` in custom core | `nan-equal-write-skipped` |
| — | Set-then-revert transactions fired observers with unchanged values | Free with the lastSeen model | `transaction-revert-produces-no-fire` |

Dirty classes (§6.4) confirmed out of Phase 0 scope by the verifier (they concern mounted layout nodes; requirements mapped to phase-1 in requirements.json).
