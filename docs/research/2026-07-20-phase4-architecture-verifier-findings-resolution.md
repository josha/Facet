# Phase 4 architecture verifier findings — resolution (2026-07-20)

Fresh-context Opus review of the Phase 4 public API, layering, property
authority, optional-feature containment, and playbook accuracy; plus decisive
verdicts on 20 forwarded API-roughness/newcomer items. Layering, property
authority, and containment: PASS. Findings and dispositions:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| F1 | major (gate-invalidating) | scaffold registry anchor `^}$` matched the export-type block's close, corrupting controls_registry.luau — the popup dry run hit it live | sentinel anchor inside the registry array; apply logic extracted to pure `scaffold.applyEdit` shared by the CLI; regression test applies the real plan to the real registry source (tests/extension_checker.spec.luau) |
| F2 | major | NavigationGroups unreachable through the public presenter (flat scope only; no direction routing) | `PresentOpts.navigationGroups` pushes a grouped scope; Up/Down route `navigateDirection("down"/"up")`; Left/Right(+dpad) bound to a NavigateH action on grouped screens; end-to-end deviceKey test in tests/navigation_groups.spec.luau |
| F3 | minor/major | `Grid` in the §10.1 v1 list had no blueprint constructor / renderer mapping | `UI.Grid` constructor + `Grid -> grid` renderer kind + mount/render test (tests/layout_v1.spec.luau) + api.md entry |
| F4 | minor | presenter opts untyped `any` | exported `PresentOpts` type; present/presentModal/presentCritical annotated |
| F5 | minor | `newTable`/`newVirtualList` take `Facet` first, unlike other `new*` | DEFERRED: documented shape (api.md); breaking change queued for the 0.5.0 window via the ADR-0011 deprecation ledger rather than churning three consumers late in the phase |
| — | — | no text-input control (tutorial examples model entry as a signal) | recorded as a Phase 5 expansion-gate use case: the §10.1 v1 control list contains no editable text control by design; examples document the workaround |

Docs-acceptable verdicts (colon-call convention, refresh loop discoverability,
renderer-vs-presenter guidance, Escape reservation, dual-sink base-screen
footgun, ErrorBoundary-vs-presentCritical guidance, scope-ownership idiom)
are covered in docs/guide/ and docs/reference/api.md; not-an-issue verdicts
(client adapters off the public table, activation path model, mutation
terminal status, path shapes, Image/Grip tap policy) stand as designed.
