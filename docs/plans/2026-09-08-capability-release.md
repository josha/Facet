# Capability release acceptance — 2026-09-08

Starting point: clean Facet HEAD `9054c0d3` (the merged themed-controls Goal 1).
Baseline `tools/verify.sh full`: PASS, 7.4 seconds, identity `e5d8d62e8a38`.
Raw baseline: `artifacts/capability-release-2026-09-08/goal1-full.log`.
No publish is authorized. Existing unrelated changes and historical evidence stay intact.

Acceptance criteria:

- NavigationStack owns a caller-observable route path, root and destinations,
  push/pop/root/back operations, scoped page eviction, deterministic state and
  legal focus restoration. It composes existing structural regions, navBar,
  presenter contributions and motion. Nested controls receive Cancel first.
- One Showcase flow demonstrates adaptive chrome, arrangement, controls, input,
  interaction and reduced motion across compact portrait/landscape, tablet,
  desktop and ten-foot facts. Suitable reference flows migrate to the public API.
- Horizontal first/last text guides and Spacer.minLength compose with nested and
  wrapped layouts, theme metrics, reactive values and preferred text size. The
  semantic baseline approximation and fallback/overflow diagnostics are explicit.
- State-driven numeric motion earns its addition through existing repeated recipes;
  theme color blending uses existing tint authority. No speculative animation system.
- Every public addition has registration, focused meaningful tests, API/guide/
  extending documentation, and Showcase coverage. The controls guide covers the
  actual configuration surface. The current gap audit ranks release vs later.
- Studio Neutral is renamed Facet Neutral in active source, docs, fixtures,
  examples and consumers; `facet-neutral` is the canonical package identity.
- Rascal Rally relevant callers are inspected, compatibility tests updated, suites
  and an affected Studio canary pass. Game behavior and feature flags are preserved.
- Final full verification, relevant Studio drives, package build/status and rebuilt
  places pass. Before/after repository benchmark comparisons retain raw conditions
  and deltas; budgets are never rebased to hide a regression.
- The private comparison is freshly derived from current code and current Apple
  documentation. FACT, MEASURED and INFERENCE remain distinct. User-confirmed
  physical testing is separate from captured measurements. Archive checksums match.

Evidence is accumulated in `artifacts/capability-release-2026-09-08/`. Full checks,
Studio evidence and performance are separate instruments; none substitutes for another.

Known unrelated documentation defect: the constitution's historical execution-contract
link points to an absent `docs/plans/agent-execution-contract.md`. Reported, not repaired.
