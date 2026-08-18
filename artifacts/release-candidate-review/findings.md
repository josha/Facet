# Release-candidate finding ledger (RC-9)

Sources: `reviews/architecture.md` (ARCH-1..26), `reviews/reactive-runtime.md`
(RR-1..15), `reviews/roblox-platform.md` (PLAT-1..26),
`reviews/maintainability.md` (MAINT-1..41, 893 lines, on disk),
`input/ias-inventory.md` (INPUT-1..116, DF-1..9), `reviews/reuse.md`
(REUSE-1..125: 40 High / 55 Medium / 30 Low; 15 keep-separate with recorded
reasons), and the dead-code interim (recorded in the controller ledger).
Severity/confidence live in the source files; this ledger owns triage,
reproduction status, and disposition. Every Blocker/High is fixed and rerun in
a wave below or carries an explicit disposition with owner, risk, reason,
trigger.

## Reproductions performed before fixing (plan rule)

- ARCH-1/ARCH-2 — REPRODUCED by controller probe
  (`.superpowers/sdd/release-candidate-review/probe_arch1.luau`): row-factory
  throw with no boundary leaves the disposed row in `children`, the new row
  absent, ZERO dirty entries, and the error swallowed into `core:lastError()`
  (the caller's `set()` returns normally). The next good update rebuilds, so
  the corruption window ends at the next items change. Severity High
  confirmed; silent-swallow aspect added to the fix contract.
- MAINT-1 — verified by the auditor with `wc -c` (renderer 199,650 of 200,000)
  and by reading `check_source_size.py`'s single `>= CAP` branch.
- MAINT-3 — the auditor ran the scaffold end-to-end and hit the failure.
- PLAT-1/RR-6 — two independent reviewers converged on the same defect at the
  same lines; code read confirms the `false and X or nil` bind-time
  short-circuit. Device-only to OBSERVE, deterministic to prove headlessly by
  unit-testing the bind table construction.

## Wave assignment

| Wave | Contents | Status |
|---|---|---|
| R1 correctness (src/) | ARCH-1, ARCH-2, ARCH-3, RR-1, RR-2, RR-4, PLAT-1/RR-6, PLAT-2, PLAT-3, MAINT-6 + addendum: the two live divergence defects (VirtualList/VirtualGrid clamped-anchor blank-screen class; RR surfaces missing presenter.tick + the guide section that taught it) | DISPATCHED |
| R2 safe maintenance (tools/tests/docs) | MAINT-1 (warning band + headroom analysis), MAINT-3, MAINT-4, MAINT-5, MAINT-7, MAINT-8b, MAINT-8c, MAINT-8d, ARCH-7, gate.luau empty-detail half of MAINT-2 | DISPATCHED (with R1) |
| R3 input authority | INPUT-90..93, INPUT-105, DF-1..4 (RR Priority/Sink scheme), DF-7, DF-9 + flag declarations, legacy-input drift check, allowlist | QUEUED |
| R4 haptics | task-11 brief (press/release/select Custom defaults) | QUEUED |
| R5 naming + consolidation | ADR-0037 implementation; ARCH-17 (Levenshtein ×4); the reuse consolidations (headline: num/paths/rect leaf modules ~50 sites + latent prefix-test tap-routing bug; the framework client host closing four hand-rolled bootstraps; tests/lib/world.luau over 106 spec-local builders); dead-code batch (4 motion aliases, oracle_easing pointer, vendor bake-off decision) | QUEUED |
| Docs wave | ARCH-4, ARCH-5, ARCH-6, ARCH-9, ARCH-21, ARCH-22, PLAT-15, PLAT-16, PLAT-23, MAINT docs items + T12 catalog/product-language/comments | QUEUED |
| Perf wave | RR-5 (fresh-`{}` memo identity, 25 sites — measure first), RR-12, PLAT-20 + T15 requalification | QUEUED |

## Dispositions recorded so far (owner · risk · reason · trigger)

- MAINT-2 (gate-manifest restructure, 757 KB / 2,270 pins): the empty-failure-
  detail defect is fixed in R2; the structural redesign is ALREADY OWNED by the
  Step 14 plan's "Test and gate simplification" section (structured results,
  one coordinator, archived prose). Owner: Step 14. Risk while open: slow
  sweeps, weak failure localization. Trigger: distribution-readiness stage
  start. Doing it mid-Step-13 would rebuild the evidence system under the
  release review that depends on it.
- MAINT-1 renderer extraction beyond the warning band: R2 delivers the warning
  band, headroom records, and a seam analysis; an actual extraction happens
  ONLY if the analysis finds a one-way seam (the previous split's history shows
  growth returns to entangled blocks). Owner: this stage R2, else dispositioned
  to a dedicated refactor mission. Risk: a future edit crossing the cap is now
  LOUD (warning band) instead of silent. Trigger: warning-band alarm.
- ARCH-15/16 (`luau-*` public theme tag vocabulary): naming decision deferred
  to the R5/naming wave with the ADR-0037 work — renaming a public authoring
  vocabulary needs the same deprecation treatment as call shapes. Risk: brand
  incoherence only; no behavior. Trigger: R5.
- PLAT-10 (native StyleSheet default OFF) + the stale promotion tracker
  (dead-code interim): a PRODUCT flag decision, not a defect fix — the
  promotion-readiness artifact is refreshed in the docs wave and the default
  flip needs the owner's call at the Step 14 checkpoint. Owner: user.
  Risk: theme packages needing `nativeStyleSheets` fail on default targets
  (documented). Trigger: Step 14 owner checkpoint.
- Vendor bake-off artifacts (vendor/Fusion + fusion_adapter + imperative +
  historical gate): retire-or-document is a product/history decision — R5
  presents both costs; default recommendation: keep, with a one-paragraph
  signpost (they are provenance for ADR-0002's benchmark), because deleting a
  frozen bake-off makes its ADR unverifiable. Owner: controller at R5.

Every finding not named in a wave or disposition above is Medium/Low and is
triaged into the R5/docs/perf waves' briefs; the final whole-branch review
checks this ledger against the review files for silent drops.
