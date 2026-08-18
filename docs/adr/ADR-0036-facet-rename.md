# ADR-0036 — The framework is named Facet

**Date:** 2026-08-17 · **Status:** Accepted · **Stage:** release-candidate review

## Decision

The framework previously named **LuauUI** is renamed **Facet** before public
distribution. `Facet` is the product, repository, root folder, ModuleScript, and
public Luau binding; lowercase `facet` appears only where a tool requires a slug.
The plain-language promise is "One interface, shaped for every player." This ADR is
the one maintained document that names both brands; everywhere else the old name is
migration input, permitted only in frozen evidence (`artifacts/**`, the frozen
design spec under `docs/superpowers/`) and in the explicit allowlist carried inside
`tools/check_brand_drift.py`, each entry with a reason and a removal rule.

## Why

- The old name described the implementation language, not the product. Facet names
  what the framework does: one semantic interface, presented in the shape each
  player's device, input class, and accessibility settings require.
- A collision and rights check (2026-08-17, evidence in
  `artifacts/release-candidate-review/facet-collision-check.md`) found the GitHub
  target available and no active same-ecosystem product or squarely-covering live
  trademark; one dormant zero-adoption Wally package of the same name is recorded
  for the owner's review.

## What moved (commits `44b9e62`, `a97336f`, `664d974`, `871cd30` framework; `b92b606` Rascal Rally)

- Every tracked file and path carrying the old brand, via history-preserving
  `git mv`; the repository folder is `GameStudio/ui/Facet`.
- The root ModuleScript and every Rojo tree node: `ReplicatedStorage.Facet`.
- Studio object names (`FacetStyle`, `FacetTheme <package>`, `Facet_*` screens),
  scenario/dev surfaces (`FacetScenarioAPI`, `FacetShowcaseAPI`,
  `FacetMatrixDriver`, `Facet_Scenario`, `Facet_SourceStamp`), profiler scopes,
  environment variables (`FACET_*`), the fast-tier banner, and the requirements
  schema string.
- Generated outputs were REBUILT from renamed source (`build/Facet.rbxm`,
  `examples/places/Facet-*.rbxl`), never text-patched.
- Both Rascal Rally Rojo projects, sources, tests, and docs in the same change.

## What deliberately did not move

- `artifacts/**` and `docs/superpowers/**`: frozen evidence keeps the name it was
  earned under; rewriting it would forge history.
- The GitHub remote is still the pre-rename URL. Renaming it is a Step 14
  owner-checkpoint action; the exact procedure and the old URL live in
  `artifacts/release-candidate-review/step14-remote-packet.md`.
- The five `UseLuauUI*` workspace attributes are not renamed in place: a value
  saved on the published place can outlive this checkout. They migrate dual-read /
  single-write through `FacetFlags` in Rascal Rally, with owner and removal
  trigger in `games/RascalRally/docs/migrations/facet-attribute-migration.md`.
  The Sponsor selector's exact default (on unless explicitly `false`) and the
  legacy Sponsor rollback are preserved through both names.

### One item on that list moved later

The public theme-authoring tag vocabulary (`luau-*` / `luau-slot-*`) was not on
the list above at all — an omission, not a decision, and the reason it survived
is instructive: `BRAND` is `luau[\s._-]?ui`, and there is no "ui" after "luau" in
`luau-chrome-panel`, so the guard that exists to notice exactly this could not
see it (ARCH-15/ARCH-16, release-candidate architecture review). The tags renamed
outright to `facet-*` / `facet-slot-*` in wave R5 — no alias, no dual vocabulary
— and this ADR's coherence argument is the reason: see
[`ADR-0038`](ADR-0038-theme-tag-vocabulary.md).

## Enforcement

`tools/check_brand_drift.py` scans both repos' tracked trees, the current-facing
studio surfaces, and the serialized object names of every buildable place; its
`--selftest` proves a planted old-name line, a planted old-name path, a planted
`luau-*` theme tag, and an allowlisted pattern outside its allowlisted file each
fail the scan — while `luau-analyze` / `luau-lsp` and the Open Cloud
`luau-execution-session` scope, which name the LANGUAGE and not the retired
product, deliberately do not. The gate row `rename-drift-guard-bites` records the
proof.
