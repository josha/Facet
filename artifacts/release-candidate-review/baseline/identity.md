# Release-candidate review — frozen pre-edit identity (2026-08-17)

The plan (docs/plans/release-candidate-review.md) requires the source/build
identity, public API, test/gate results, representative Studio scenarios,
lifecycle counters, and performance baselines frozen before any edit. This file
is the identity anchor; the sibling files are the raw artifacts.

| Surface | Frozen state | Artifact |
|---|---|---|
| LuauUI source | branch `main`, commit `fe920dc` ("step 13 begins: freeze the plans that name Facet") | git |
| Rascal Rally source | `games/RascalRally/code`, branch `main`, commit `02df98c` | git |
| LuauUI remote | `https://github.com/josha/LuauUI.git` (origin, unmutated) | git |
| Full LuauUI suite | 6188 passed, exit 0 | `suite-luauui.txt` |
| Full Rascal Rally suite | 3345 passed, exit 0 | `suite-rr.txt` |
| Public API surface | VERSION 0.9.0 dump, 188 lines, stable sorted order | `public-surface.txt` |
| Headless performance gate | PASS (100 runs, 20 scenes); budgets in `bench/perf_budgets.json`; artifact `artifacts/phase-4/perf.json` | `perf.txt` |
| Rename inventory (before) | 1031 files carry the old name; content matches: 10788 current-source, 1964 generated-output, 2062 immutable-evidence; 94 storage-flavoured lines flagged | `rename-inventory-before.json` (scanner: `rename_inventory.py`) |
| Studio scenarios | PENDING — captured in `studio/` when a Rojo-connected session is available; no mass source edit before that capture | `studio/` |

Storage-flavoured lines that decide the migration boundary: Rascal Rally reads
the workspace attributes `UseLuauUISponsor` (production selector; `~= false`,
so the default is ON with `false` as the legacy rollback), `UseLuauUISettings`,
`UseLuauUIGaragePilot`, `UseLuauUIRacerList`, and `UseLuauUINativeStyle`. The
checked-in place files contain zero old-name attributes, but a saved value on
the published place can outlive this checkout, so these five migrate through
the one dual-read/single-write manifest instead of a blind rename. The
`LuauUI_SourceStamp` / `LuauUI_SourceStale` workspace attributes are
development-session stamps written fresh by `tools/studio/inject.luau` each
sync and rename outright.
