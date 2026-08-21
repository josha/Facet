# Wave THEME-UNBUNDLE — acceptance ledger

Registered BEFORE implementation, per `docs/plans/agent-execution-contract.md` §2.
A row closes only on evidence from a tool run in this wave. Statuses:
PASS_AUTOMATED / PASS_HUMAN / FAIL_PRODUCT / FAIL_ENVIRONMENT / PENDING.

The product claim this wave makes falsifiable: **Facet ships studio-neutral, and a
theme is a package you pick.** The eight player-facing reference packages become
eight independently installable artifacts; the library proves it does not need any
of them; the catalog tells a consumer which one to take and what it costs.

| ID | User-visible behavior | Risk if skipped | Evidence | Driver | Artifact | Status |
|---|---|---|---|---|---|---|
| **TU-1** | Each shippable reference package builds to its own `build/themes/<Name>.rbxm` — the package ModuleScript plus any runtime data it owns — carrying its `identity.version` + `schemaVersion` stamp | A theme is only obtainable by cloning the whole examples tree; a consumer cannot take one skin | E1 | `tools/build_themes.sh` | `artifacts.md` | PENDING |
| **TU-2** | The shippable set is DERIVED from the one theme enumerator, and every excluded module is excluded by name with a reason | A hand list drifts; a broken-on-purpose fixture ships to a player | E1 | `tools/lune/theme_packages.luau` + suite | `artifacts.md` | PENDING |
| **TU-3** | Every built artifact installs against a BARE library surface — require Facet, require the artifact, define + `checkCoverage` + `theme_controller.install`, one control mounts headlessly — with no `examples/` in reach | A theme that secretly reaches into gallery code is undeliverable, and nobody finds out until a consumer installs it | E1 | `tools/check_theme_artifacts.py` | `self-containment.md` | PENDING |
| **TU-4** | The same proof runs once per package at a TEN-FOOT snapshot, so a package's `metrics.tenFoot` declarations (wave TEN-FOOT, ADR-0039) travel in the artifact and resolve there | The ladder is proved only for in-repo requires; a distributed artifact could lose a declaration silently | E1 | `tools/check_theme_artifacts.py` | `self-containment.md` | PENDING |
| **TU-5** | `build/Facet.rbxm` and `src/` contain no reference-package identifier in CODE (comments exempt), and `studio-neutral` is the only package stamp in the model | The "library ships neutral" claim is rhetoric; a shipped diagnostic points a consumer at a file they do not have | E1 | `tools/check_library_purity.py` | `library-purity.md` | PENDING |
| **TU-6** | Every guard above FAILS on a planted defect: a package that requires gallery code, a package artifact that lost its stamp, a library that requires a package, a model whose stamp set grew | A guard that cannot fail proves nothing (gate-integrity sweep) | E1 | `--selftest` on both checks | `library-purity.md`, `self-containment.md` | PENDING |
| **TU-7** | `docs/guide/13-theme-catalog.md` names the neutral built-in and all eight optional packages: one-screenshot description, install steps, metric/chrome character, honest cost line; `api.md` and the guide index cross-reference it | A consumer cannot tell which package to take, or what an asset-backed skin costs | E0 | doc build + `check_docs` | `docs/guide/13-theme-catalog.md` | PENDING |
| **TU-8** | Suite/gate integrity unchanged: the theme-axis sweeps still consume `examples/themes` in-repo, no coverage narrows, and the Step 14 public-boundary section records the per-theme artifacts as distribution outputs | Unbundling quietly deletes the test corpus | E1 | full suite + diff review | suite tail in report | PENDING |
| **TU-9** | RascalRally's SHIPPED surfaces require no `examples/themes` module; its two test-corpus requires are recorded, and a game-side guard keeps it that way | The consumer silently acquires a dependency on an optional package | E1 | RR suite + new RR spec | `rr-lockstep.md` | PENDING |

## Deliberately NOT in this wave

- The T15 memory table (per-package install cost in KB/instances). The cost line in
  the catalog carries a named placeholder that the T15 wave fills; inventing a
  number here would be the "unsupported claim" the distribution plan forbids.
- Executing any Step 14 work. This wave adds ONE line to that plan's public-boundary
  section recording the artifacts as distribution outputs.
- Any narrowing of the theme-axis sweeps. `examples/themes/` stays the in-repo test
  corpus, all thirteen modules, unchanged.
