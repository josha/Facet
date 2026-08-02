# ADR-0011: Semantic versioning and deprecation policy

- Status: accepted
- Date: 2026-07-20
- Phase: 4 (Hardening), design §17
- Requirement: UI-AGENT-001

## Decision

LuauUI adopts semantic versioning (`MAJOR.MINOR.PATCH`) exposed as
`LuauUI.VERSION`, starting at **0.4.0** with this ADR (the scaffold-era
`0.1.0-phase1` suffix form is retired; the minor tracks the completed design
phase while the library is pre-1.0).

### Version rules

- **Pre-1.0 (now):** `0.MINOR.PATCH`. A MINOR bump may change public behavior
  or remove deprecated surfaces, but only with the deprecation notice below.
  A PATCH bump is fully compatible (fixes, docs, performance).
- **1.0.0** is cut when the §20 success criteria hold and a second production
  game consumes the library. From then on: MAJOR = breaking, MINOR =
  additive, PATCH = fixes — strict semver.
- The version lives in exactly one place, `src/init.luau` (`VERSION`); docs
  and tests read it from there (drift is mechanically checked by
  `tests/api_surface.spec.luau` and the API-reference checker).

### Public surface

The public surface is what `src/init.luau` exports (plus the documented
client entry points under `src/client/`). Everything else is internal and may
change without notice. Games must not require library-internal modules.

### Deprecation policy

- Deprecations are declared in the machine-readable ledger
  `LuauUI.DEPRECATIONS` (array of `{ surface, since, removeNoEarlierThan,
  replacement, note? }`), kept in `src/init.luau` next to the exports.
- A deprecated surface keeps working for **at least one MINOR version** after
  `since`; `removeNoEarlierThan` names the earliest version that may delete
  it.
- Every entry names its `replacement` (an API or a migration note in the
  docs). The API reference marks deprecated surfaces and the registration
  checker (Phase 4 agentic-maintainability tooling) fails the gate when a
  ledger entry is missing any required field.
- Removal happens only in a MINOR (pre-1.0) or MAJOR (post-1.0) bump, with
  the ledger entry moved into the version-history section of the developer
  docs.

## Consequences

- `tests/api_surface.spec.luau` enforces the semver shape, the ledger schema,
  and that this ADR names the current version (update BOTH on every bump —
  the test fails otherwise, which is the point).
- Current version: **0.7.0** — rich skinning v2 (ADR-0020): fully image-driven
  UI. Layered decoration slots (`fill`/`frame`/`corners`/`edges`/`plaque`/`tile`,
  with the plaque's `text` nameplate sub-slot), per-state asset variants at both
  rungs under one normalizer, image value displays (bar family, stepper plates,
  toggle track/knob), semantic icon assets with an ASCII fallback-glyph table,
  pixel-art rendering mode, `content` as the canonical asset field, the
  profile-conditional `theme_controller.install` option `selectBy`, and the
  three-rung customization ladder. Additive MINOR: a package published against
  0.6.0 compiles and installs unchanged, flat themes render byte-identically
  apart from the characterized deltas recorded in
  `artifacts/rich-skinning-v2/rs-a1-image-is-element.json`, and every new field
  is optional.
- Previous: **0.6.0** — theme packages and skinning (ADR-0019): the
  public versioned `LuauUI.themes` contract (define / resolve / neutral /
  neutralPackage / lintProperty / checkCoverage), one frozen metric snapshot on
  the `themeMetrics` environment fact, semantic metric names in public props,
  the client theme controller with atomic package/theme swapping, bounded
  nine-slice/gradient chrome with decoration slots and the chrome text lift,
  and the Style Editor sync workflow (`theme_sync_cli`). Additive MINOR: every
  existing screen renders byte-identically under the default Studio Neutral
  snapshot (proven by the checked-in baseline dump comparison).
- Earlier: **0.5.0** — Milestone 0 of the SwiftUI-parity plan: strict
  public authoring. Construction is validated against
  `src/blueprint_schema.luau`, so an unknown, wrongly typed, missing-required,
  or never-implemented property is now an immediate error instead of a value
  frozen into the node and dropped downstream. This is a behavior change under
  the pre-1.0 MINOR rule, and it is deliberately not softened to a warning: a
  property that silently did nothing is the failure the change exists to
  remove.

### Diagnosed-not-preserved

The policy's "keeps working for at least one MINOR" clause protects surface
that WORKED. A property that never reached a render target has no working
behavior to preserve, and accepting it for another minor version would preserve
only the silent failure. Those entries stay in `DEPRECATIONS` for the record
and are **diagnosed at construction** — the error names the replacement.
Current entries: `UI.Text.color` (dropped entirely by every adapter) and
`UI.Text.font` (reached the measure seam only, so measured and painted bounds
silently disagreed; fonts are style authority).

The ledger itself is now GENERATED from the property schema
(`schema.deprecations()`), so an entry cannot go missing when a property is
retired.
