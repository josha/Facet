# Implementation-package briefs — swiftui-reference-app-validation

Lead-authored 2026-08-08. Three disjoint sample packages (Opus 5, thinking on,
xhigh) plus the lead's own pair (P4/P5). Common contract for every package:

- Binding inputs, in order: `build-decisions.md` (this directory),
  `specs/p<n>-<name>.md`, `capability-ledger.md` (§A + your section),
  `responsibility-ledger.md`, `docs/reference/api.md`, and
  `docs/guide/README.md` chapters as needed.
- Deliverables: your `examples/reference/<proof>/` folder (blueprints, fake
  services, content/strings incl. `xa` pseudo-locale), the contents of your
  pre-created `tests/reference/<name>_spec.luau` (E1 loop pins: every
  representative-loop state transition, rejection path, reset, determinism
  pin = same seed ⇒ identical dump), and your scenario body in the pre-created
  `examples/gallery/scenarios/ref_<name>.luau` (fill the stub's marked region
  only; select/reset/report/step drives).
- The full suite must be green at your close, stylua-clean; run
  `lune run tools/lune/check_example_drift_cli` (your folder is drift-scanned).
- Deliver scope exactly; routine decisions yourself; a materially different
  architecture/product choice found live → a short decision packet back to the
  lead, never silent redesign.
- Touch ONLY your folder + your two pre-created files. Never: tests/run.luau,
  scenarios/init.luau, gate manifest, src/, docs/, other proofs' folders.

## Package 1 — Glade (P1, spec p1-glade.md)

Scope: the ten surfaces + fake services (SupplyService, CommerceService with
scripted rejection fixtures, VisitScheduler with seeded windows) + the
GladeScene composition + supply rings + commerce lifecycle + toasts + wisp
fly-in timeline. Spec's two proposed `extra.*` tokens: do NOT add theme tokens;
use the nearest existing roles and note the substitution in your report (token
additions are a lead decision).

## Package 2 — Cartwheel (P2, spec p2-cartwheel.md)

Scope: split-nav shell + dashboard four cards + orders table/list + detail
status machine + countdown + completion modal + gallery/editor + top-five chart
+ entitlement-gated feed + locked history chart + sign-up form (unmasked
variant with disclosure note UNLESS the lead has landed masked entry by your
start — check `git log` for a `TextField` masking change; if absent, build the
fallback variant the spec declares). The city hero: build against
`controller.stageHost` per api.md's Stage section (landing this stage); if the
host returns nil in your headless runs that is the CORRECT stub behavior — your
scenario provides the client-side content mount via the marked region, and the
fallback plate must render headlessly.

## Package 3 — Sipworks (P3, spec p3-sipworks.md)

Scope: catalog/search/favorites/detail with the declared card approximation +
order/redeem + rewards stamps + recipe unlock + recipe view + I18nService with
plural fixtures + pseudo-locale + THE COMPACT ENTRY FLOW as a second scenario
entry (`ref_sipworks` takes a `mode` fact: full | compact-link + item id) —
same folder, both entries share the same blueprints.

## Lead pair — Foyer (P4) + Wardrobe (P5)

Built by the lead after `UI.Stage` lands (Wardrobe needs stageHost; Foyer has
no dependency). Same obligations as the packages.
