# ADR-0002: Which reactive foundation implements the LuauUI core contract? (design §3, §17 Phase 0)

- **Status:** Accepted (2026-07-19)
- **Decision:** `custom` (weighted 144.00)
- **Context:** Three candidates behind the identical public contract (src/core/contract.luau) ran the identical 26-check conformance suite (artifacts/conformance-<core>.json) and 12 bench scenarios (artifacts/bench.json). Selection rules from the design: custom if it materially wins; Fusion if it conforms better; imperative if reactivity complexity is unjustified.

## Scores (0-5, weighted; evidence per cell)

| criterion (weight) | custom | fusion | imperative |
|---|---|---|---|
| semantic-correctness (5) | 5 — 26/26 conformance incl. verifier-driven corrective checks (artifacts/conformance-custom.json) | 3 — 19/26: no transaction batching, no per-signal equality, write-during-memo silent, revert-fires, error surfacing opaque (artifacts/conformance-fusion.json) | 4 — 21/26: dynamic-dependency skip impossible, write-during-memo silent, NaN refires, revert-fires (artifacts/conformance-imperative.json) |
| lifecycle-safety (4) | 5 — all UI-LIFE checks + memory-neutral-churn pass | 4 — scope + churn checks pass via per-resource fusion scopes | 5 — all UI-LIFE checks pass |
| deterministic-behavior (4) | 5 — synchronous flush, no external scheduler; suite deterministic across runs | 3 — external-scheduler dependent; observer delivery needs provider stepping | 5 — synchronous ordered recompute |
| update-cost (4) | 5 — sparse-update p50 0.0006ms vs 0.0020 (fusion) / 0.0170 (imperative), artifacts/bench.json | 4 — sparse-update p50 0.0020ms; hud-storm 0.288ms (worst of three) | 1 — sparse-update p50 0.0170ms = O(all live derivations) per write; 28x custom with only 200 memos |
| allocations (3) | 4 — heap deltas smallest-or-comparable across scenarios (headless trend only) | 3 — settings-churn heap delta 1223KB (largest) | 4 — small heap deltas |
| source-maintenance-complexity (3) | 4 — ~380 owned lines, no vendor pin to track | 2 — 3k+ vendored lines + require transform + upstream 0.3 pin | 5 — ~260 trivial lines |
| diagnostics (4) | 5 — cycle path, write-during-memo, feedback cap, quarantine all queryable via lastError() | 2 — errors routed to external logger, not queryable; cycle check produced no observable diagnostic | 2 — no cycle/write detection by design |
| public-api-fit (3) | 5 — implements the contract natively incl. transactions and custom equality | 3 — contract's transaction()/eq params accepted but semantically inert | 3 — contract accepted but use() tracking is a no-op; UI-RUNTIME-001 scaling requirement unmet |

## Totals

- custom: 144.00
- imperative: 108.00
- fusion: 91.00

**custom:** Minimal custom transactional push-pull core (src/core/custom.luau, ~380 lines, zero dependencies).

**fusion:** Thin adapter over vendored Fusion 0.3 state subset (src/core/fusion_adapter.luau + vendor/Fusion).

**imperative:** Retained imperative recompute-all baseline (src/core/imperative.luau), the pattern the games use today.

- **Consequences:** Public API unchanged (contract holds). Fusion stays vendored for reference; the adapter and baseline remain as conformance foils and rubric evidence. UI-RUNTIME-001's no-rerun guarantee at scale requires O(affected) updates, which only the custom core provides with queryable diagnostics.
