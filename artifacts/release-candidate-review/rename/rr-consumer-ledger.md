# Rascal Rally consumer-impact ledger — the LuauUI → Facet rename (2026-08-17)

The root constitution's standing rider: *"LuauUI and Rascal Rally move together."*
This rename changes the framework's name, its home on disk, its Rojo node, its
StyleSheet name, its schema strings, its profiler labels and its asset file names —
so the game half is not optional and is not deferred. It landed in the same task.

Framework commits: `44b9e62` (in-repo rename), plus the stage-5 evidence commit.
Game commit: `b92b606`.

## Changed contract → game files touched → tests run → result

| # | Framework contract that changed | Rascal Rally files touched | Proof run | Result |
|---|---|---|---|---|
| 1 | **Home on disk** `GameStudio/ui/LuauUI` → `GameStudio/ui/Facet` | `default.project.json`, `places/debug.project.json`, `tools/suite_transcript.sh` (fingerprint roots), `.gitignore`, 44 `tests/facet_*.spec.luau` require paths, `tests/hud_zone_model.spec.luau` | `rojo build default.project.json` / `rojo build places/debug.project.json` | exit 0 / exit 0 |
| 2 | **Rojo node** `ReplicatedStorage.LuauUI` → `ReplicatedStorage.Facet` | both project files; every `require(ReplicatedStorage:WaitForChild("Facet"))` and `ReplicatedStorage.Facet.client.*` in `FacetRacerListGui`, `FacetSettingsGui`, `GaragePilotGui`, `FacetSponsor/init` | `rojo sourcemap default.project.json` then `./run-tests.sh` | sourcemap names `Facet`; suite 3374 passed |
| 3 | **Module identifier** `LuauUI` → `Facet` in game code | 48 files under `src/`, 54 under `tests/` | `./run-tests.sh` | 3374 passed, exit 0 |
| 4 | **Client package name** `src/client/LuauUISponsor/` → `src/client/FacetSponsor/` (30 modules) | `git mv` of the directory; `require(script.FacetSponsor)` in `init.client.luau` | `./run-tests.sh` + `stylua --check src tests` | green / clean |
| 5 | **Client modules** `LuauUI{RacerList,Settings}{Gui,Screen}.luau` → `Facet*` | 4 `git mv`s + every citation | `./run-tests.sh` | green |
| 6 | **Spec file names** `tests/luauui_*.spec.luau` → `tests/facet_*` (44) and `tests/lib/luauui_*` → `facet_*` (2) | `tests/run.luau` registrations | `./run-tests.sh` — an unregistered spec is a silent zero, so the count is the check | 3345 → 3374, every case accounted for |
| 7 | **StyleSheet name** `LuauUIStyle` → `FacetStyle` | citations only (the game never names the sheet in code; it passes `nativeStyle`) | `tests/facet_theme_paint_contract.spec.luau` | green |
| 8 | **Five workspace flags** — migrated, NOT renamed (see the table below) | NEW `src/client/FacetFlags.luau`; 9 call sites in `init.client.luau`, `FacetSponsor/init.luau`, `FacetSettingsGui.luau`, `FacetRacerListGui.luau`, `GaragePilotGui.luau` | NEW `tests/facet_flag_migration.spec.luau` (29 cases) | green |
| 9 | Pinned invariants the migration moved | `tests/edge_case_hardening.spec.luau:119` (was: grep the raw `GetAttribute` line; now: the named call `FacetFlags.sponsorOn()`), `tests/facet_theme_paint_contract.spec.luau` (the nativeStyle gating sweep now recognises `FacetFlags.nativeStyleOn()`, excludes the owner module, and asserts the owner names BOTH spellings) | `./run-tests.sh` | green; both pins still bite |
| 10 | Pinned SORTED file lists whose order the rename moved | `tests/facet_motion_and_scroll_contract.spec.luau` (3 paths), `tests/facet_help_callout_contract.spec.luau` (13 paths) | `./run-tests.sh` | green; same SETS, new alphabetical order (`FacetSponsor/*` sorts where `LuauUISponsor/*` did not) |
| 11 | Framework gate rows that assert the game side | `tools/lune/gate_manifest.luau` rows in `phase-2-settings-parity`, `phase-4-hardening`, `part-2-director` re-pointed from the raw attribute read to `FacetFlags.<flag>On()` **plus** a second grep proving `FacetFlags.luau` still names the attribute — the whole original claim, in two halves | full prior-gate sweep | see `commands.md` |
| 12 | Game docs the code cites by path | `docs/{FACET_SPONSOR_PARALLEL,FACET_SETTINGS_PORT,facet-sponsor,facet-sponsor-scenarios,facet-sponsor-command-shapes}.md`, `docs/ui/UI_SPEC_sponsor_facet.md` — all `mv`d with their citations | framework gate row `large-text-accessibility` greps `../../../games/RascalRally/docs/ui/UI_SPEC_sponsor_facet.md` | resolves |

## The flag migration, exactly

Dual-read, single-write, one owner: `src/client/FacetFlags.luau`. Removal trigger and
the live-place check that licenses it: `games/RascalRally/docs/migrations/facet-attribute-migration.md`.

| Facet-era name (written) | Pre-rename name (read as fallback) | Predicate | Absent means | Call sites |
|---|---|---|---|---|
| `UseFacetSponsor` | `UseLuauUISponsor` | `~= false` | **ON** — the Facet Sponsor presenter (production default, 2026-08-03 cutover). Explicit `false` = the legacy `SponsorController` rollback | `init.client.luau` |
| `UseFacetSettings` | `UseLuauUISettings` | `== true` | off — the legacy `SettingsGui` | `init.client.luau` |
| `UseFacetGaragePilot` | `UseLuauUIGaragePilot` | `== true` | off — no entry point until the Paddock lobby | `init.client.luau` |
| `UseFacetRacerList` | `UseLuauUIRacerList` | `== true` | off — the legacy `SponsorRacerList` | `init.client.luau` |
| `UseFacetNativeStyle` | `UseLuauUINativeStyle` | `== true` | `nil` → the **library** default | `FacetSponsor/init.luau`, `FacetSettingsGui.luau`, `FacetRacerListGui.luau`, `GaragePilotGui.luau` |

**Why a migration and not a rename.** The Sponsor selector reads `~= false`, so ABSENT
MEANS ON. A published place saved with `UseLuauUISponsor = false` is a deliberate
rollback to the legacy presentation. Renaming the attribute would have made that saved
value invisible and turned the rollback OFF on exactly the build somebody was rolling
back FROM. The other four fail softer — an opt-in quietly switching off — but ride the
same reader for one seam instead of five.

**What proves it** (`tests/facet_flag_migration.spec.luau`, 29 cases). The module
touches exactly one engine global, so the spec loads the SHIPPED source with a fake
`workspace` injected as its environment — a behavioural test of the file the client
requires, not a source grep. Cases: the map is complete and nothing else is in it; an
unknown flag errors naming the offender; **single-write** (a workspace whose
`SetAttribute` fails the test, plus "no `SetAttribute` appears in the source at all");
for each of the four opt-ins — neither set → off, old alone → honored, new alone → on,
both disagreeing → **new wins in both directions**, a non-boolean is not truthy; and
for the Sponsor selector — neither set → ON, `false` under EITHER spelling → OFF, the
old rollback re-flagged under the new name comes back ON, and a negative control that
only `false` rolls back (`0` and the string `"false"` are ON).

## Game behaviour and flags: unchanged

No product change was made or authorized. The legacy Sponsor modules
(`SponsorController`, `SponsorRacerList`, `SponsorGui`, `SponsorWidgetKit`) are
untouched in behaviour, so the rollback path still works. Every flag's default and
predicate is preserved to the letter, including the Sponsor cutover default.

## What this ledger does NOT claim

No Studio canary was run for the game. The controller owns the open Studio session and
this task was instructed not to touch it. A device/Studio pass on the renamed game
tree — mount the Facet Sponsor presenter from the new `ReplicatedStorage.Facet` node,
and confirm the legacy rollback under `UseFacetSponsor = false` — remains owed and is
listed as a follow-up in `task-4-report.md`.
