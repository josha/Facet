# Rascal Rally consumer-impact ledger — distribution-readiness

Rascal Rally consumes `GameStudio/ui/Facet/src` directly through both Rojo projects
(`games/RascalRally/code/default.project.json`, `places/debug.project.json`). The
Package is an additional consumer, not a migration; the game stays on direct source.

| Facet change in this stage | Effect on the game | Game-side action |
|---|---|---|
| `src/**` edits since `27c0afd`: comment rewrites only (citations moved from retired comparison documents to `docs/reference/api.md` / ADR-0033 / ADR-0034), `src/core/README.md` rewritten | none at runtime — no public contract, default, or behavior changed (`git diff 27c0afd..HEAD -- src` has no non-comment line outside the two removed files) | none |
| `src/core/fusion_adapter.luau` removed; `src/core/imperative.luau` moved to `bench/cores/` | none — `Facet.newCore` always returned the custom core; the game never required either arm (`check_boundary` refuses `src/core/*` from consumers) | none |
| `vendor/` removed | none — not mounted in either game project | none |
| `tools/build_model.sh` gains the `Distribution` metadata child and manifest | none — the game maps `src/`, not the built model | none |
| Docs, root files, `AGENTS.md`, skill, CI, verification graph, package tooling | none at runtime | none |
| Retired comparison documents | three game test COMMENTS cited them | repointed to `docs/reference/api.md` §When / §Foreign: `tests/facet_branch_scope_contract.spec.luau:5`, `tests/run.luau:595` (commit `f82aa1d`), `tests/facet_foreign_seam_contract.spec.luau:5` (commit `848dfa8`) |

Game suite: `cd games/RascalRally/code && ./run-tests.sh` → **3541 passed / 0 failed**
after the comment edits (workstream K, 2026-08-30). The release coordinator runs the
game suite once more at the final Facet identity; that line is recorded in
`verification/timings.md` when the stage closes.

Result: **no caller change**. No new game-side contract test is required because no
Facet contract moved; the existing `facet_*_contract` specs remain the currency check
and passed.
