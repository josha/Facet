# Rascal Rally consumer impact (EQ-21)

**Date:** 2026-08-06. Execution contract §"Rascal Rally consumer lockstep".

Rascal Rally's normal and debug Rojo projects mount `GameStudio/ui/LuauUI/src` directly,
so every LuauUI source change in this stage is a change to the live game. Six `src/`
files moved. Each is audited against the game's callers below.

## Verification run at the judged source

| Command | Result |
|---|---|
| `./run-tests.sh` (LuauUI) | **3559 passed**, exit 0 |
| `./run-tests.sh` (games/RascalRally/code, no arguments) | **3090 passed**, exit 0 (3089 passed before this stage added the compatibility case below) |
| `lune run tools/lune/check_example_drift_cli` | clean — 8 files, 2969 lines, 83 semantic role uses, 2 allowlisted |
| `lune run tools/lune/check_flat_baseline` | PASS — 1773 flat nodes byte-compared; `control-vocabulary` sha256 unchanged |
| `tools/bench.sh` | interleaved A/B: `textinput-typing-storm` at parity with the pre-stage loop (see `bench-textinput-ab.json`) |
| `lune run tools/lune/check_docs_cli` | exit 0 |

## Per-change caller audit

### F-1 — `renderer.assertEnumValue`: a bound enum value outside its closed set now ERRORS

**This is the one change that can break a running game**, because it converts a silent
no-op into a hard error at the write site. Audited rather than assumed.

Every site in the game that binds `surface` was enumerated:

| Site | Bound value | Verdict |
|---|---|---|
| `src/client/LuauUISponsor/HandDock.luau:385` `surface = plate` | `plate` is `CardState`'s, whose complete value set is `"plain"`, `"chip"`, `"control"` (grepped: lines 119, 126, 135, 159, 172, 186, 199, 210) | **all three are members of the surface enum — safe** |
| `RolePickScreen.luau:499` and `ResultsScreen.luau:2724` `surface = tokens.ROLE_CTA_SURFACE` | `TableMetrics.ROLE_CTA_SURFACE = "control"` — a constant, not a binding | **safe** |

The near miss worth recording: the game **does** carry a `plate = "highlighted"`
(`RowState.luau:177`), which is *not* a surface enum member. It never reaches `surface`.
It is a key into `TableMetrics.plateColor` / `pillColor`, which return colours. Two
different vocabularies that happen to share a variable name, and only one of them is the
enum. Had it flowed to `surface`, this change would have thrown in production.

### F-2 — `focus_map.linkGridBoundaries`: a Grid's boundary rows gain exits

Two game files use `UI.Grid` (`GaragePilotScreen.luau`, `LuauUISponsor/ResultsScreen.luau`).
The change only ADDS an exit where a boundary row previously had none, and never
overwrites an authored one, so a grid alone on a surface is byte-unchanged (pinned by
`tests/auto_input_screens.spec.luau` "a grid alone on a screen is unchanged"). Where a
grid has a neighbour, focus can now leave it — which is the standing "every control on
every input" principle, not a behaviour the game relied on the absence of. Game suite green.

### F-3 — `screen_target.recoverPressDip`

Strictly a bug fix: the release path previously threw on every bespoke-path press
(`TweenService:Create failed because Instance is null`) and the pressed dip never
recovered on release. No caller contract changes.

### F-4 — `newTable.rowGap` also accepts a theme metric name

**Widening only. The default is unchanged (0).** `LuauUIRacerListScreen.luau:176` passes
`rowGap = LuauUIRacerListScreen.ROW_GAP`, a number, which takes the identical path it
always did. Pinned by `tests/table.spec.luau` "a number behaves exactly as it always has".

### F-5 — `text_metrics`: a run of spaces reserves its own width

Geometry-affecting for any string containing **consecutive** spaces. Grepped the Sponsor
surfaces for multi-space literals: **no matches**. Single-spaced strings are byte-identical
by construction and that is pinned as a test ("a single-spaced string is byte-identical to
what it always reserved"). Game suite green, including the Sponsor layout suites.

### F-6 — `newRating`: the star strip is a uniform `UI.Grid`

**The game does not use `newRating`** (grepped `src/`: no matches). Framework-only change.

### F-5 — `UI.Table`'s header band became preference-driven

`newTable`'s header cell was `{ type = "fixed", px = "controls.table.headerHeight" }` and
is now a `minMax` FLOOR, so the band grows with the player's text preference instead of
letting a one-line column title paint out of it.

**Rascal Rally's only `newTable` caller is `src/client/LuauUIRacerListScreen.luau`, and it
passes `header = false`** — the band never mounts, so this change is structurally
unreachable from the game. That is not left as an inspection result: a new case in
`games/RascalRally/code/tests/luauui_racer_list.spec.luau` asserts, at BOTH the shipped and
the Largest preference, that `/S/RacerList/Main/Header` does not exist and that the first
racer row starts at the table's own top — the exact number a taller header band would have
moved. Game suite 3089 -> 3090.

### F-6 — `text_metrics` wrap loop: an allocation removed

The space-run reservation added in this stage originally captured the whitespace gap as a
string per word. Rascal Rally measures text on every HUD tick, so this reached the game
directly. It is now a position capture with an in-place byte count, measured at parity with
the pre-stage loop over an interleaved three-pair A/B (`bench-textinput-ab.json`). Reserved
widths are unchanged — the reservation tests pin the numbers, and the game suite is green.

## What this ledger does NOT claim

- **The Rascal Rally Studio canary RAN on 2026-08-22** (deferred with authorization on
  2026-08-06; the gate row stayed red on purpose until this line could be written
  honestly). The director opened the place with Rojo connected; the sponsor scenario rig
  armed and drove `results-sponsor` → `story` (stamp
  `rascal-sponsor-scenario/1:results-sponsor`, held at `results`): **ResultsScreen — the
  deferral's own named surface — rendered live** (standings with cast avatars, the drama
  recap lines, Rally Points/Coins, Race + Sponsor Again with the focus ring), under the
  post-flip SHEET-PAINT DEFAULT (4 StyleLinks, FacetStyle/FacetTheme sheets installed,
  no attributes set — ruling R21's absent-flag arm, live), with ZERO effective-visible
  zero-box text nodes. Capture: `rr-canary-2026-08-22.png` beside this ledger. The
  canary's first finding preceded its first frame: all three DataStore backend
  constructors called `GetDataStore` bare — upstream of their own pcall'd loads — so an
  unpublished place killed `SponsorService.start` at boot; fixed in RR `829b382`
  (degrade-at-the-constructor, matching each module's stated contract).
  The ORIGINAL deferral record follows, kept as history. The game suite was green at the
  judged source, the caller audit above is exhaustive for the changed contracts, and the
  one layout change with a plausible game-side consequence (F-5) now has a game-side test
  proving it cannot reach the live screen. But a live Sponsor session was not driven.
  **This is an environment limit, not a decision:** the only Studio instance connected in
  this session is `LUIPerfLab`, and nothing in the toolchain can open a different place —
  the Rascal Rally place has to be opened by a human before the canary can run.

  **The director was asked and ruled on it (2026-08-06):** *"I can't access my computer
  right now so we'll have to proceed without rascal rally or a human test."* So this row is
  deferred with authorization, NOT closed, and the gate check that demands the canary is
  deliberately left RED rather than rewritten to accept its absence — a check that stops
  asking for the canary would never ask again. F-2 (focus exits around a Grid) is the change
  most likely to be visible in one, and `ResultsScreen` is the surface to look at; F-5 is the
  one with a game-side test already proving it cannot reach the live screen.
- No game file was edited. No production edit was manufactured for a compatible change,
  which is the contract's own instruction; the audit above is the evidence that none was
  correct.
