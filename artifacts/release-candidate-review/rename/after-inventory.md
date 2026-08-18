# Rename inventory — after (2026-08-17, regenerated at the fix-round tree)

Scanner: `.superpowers/sdd/release-candidate-review/rename_inventory.py` (unchanged;
it auto-detects `GameStudio/ui/Facet`). Machine-readable output beside this file as
`after-inventory.json`. Pattern: `luau[\s._-]?ui`, case-insensitive, over the tracked
files of both git repos plus the untracked studio surfaces (`.claude/agents`,
`GameStudio/specialists`, `games/RascalRally/docs`, both `CLAUDE.md`).

**This file is regenerated LAST, after every source fix in the round it describes.**
An earlier revision was written before the round's final commit and under-reported by
ten matches; that is why the rule is now written down here.

## Counts by class

| Class | Before (`fe920dc`) | After | Δ |
|---|---:|---:|---:|
| current-source | 10788 | **205** | −10583 |
| generated-output | 1964 | **0** | −1964 |
| immutable-evidence | 2062 | **2228** | +166 |
| files carrying the name | 1031 | 215 | |

**generated-output is zero.** Every place file, the model, and both Rojo trees were
REBUILT from renamed source, never text- or binary-patched. Re-verified after the fix
round: `grep -c` for `LuauUI|luauui|LUAUUI` over `build/Facet.rbxm` and all 15 tracked
`examples/places/*.rbxl` returns zero on every file.

### Why immutable-evidence went UP, decomposed to the file

Gains **+257**, losses **−91**, net **+166**. Neither half is a regression, and the
losses are the interesting half:

- **+211 — the release-candidate baselines.** The before-scan was taken at `fe920dc`;
  the controller then committed the RC baselines at `2a1823a`:
  `baseline/suite-rr.txt` (+159), `baseline/suite-luauui.txt` (+15),
  `baseline/identity.md` (+12), `baseline/rename_inventory.py` (+10),
  `baseline/studio/README.md` (+9), `facet-collision-check.md` (+5),
  `acceptance.md` (+1). New frozen artifacts that by definition record the old name.
- **+46 — this task's own evidence**, in the carve-out the brief grants
  (`artifacts/release-candidate-review/rename/`): `rr-consumer-ledger.md` (+17),
  this file (+15), `commands.md` (+14). `prior-gates-after.txt` contributes zero.
- **−82 — `docs/lessons/**`.** The scanner classifies `/docs/lessons/` as
  immutable-evidence, but the brief's §1d lists lessons under the documentation to
  rename, so 27 framework lesson files and one Rascal Rally lesson lost their
  old-name lines. Largest: `the-camera-still-owns-the-arrow-keys.md` (−15),
  `the-200k-source-cap-is-on-writing-not-loading.md` (−7),
  `an-invisible-surface-declares-its-invisibility.md` (−6).
- **−9 — three LIVE GATE-STATE artifacts**, and this one deserves its own paragraph.

### The live-artifact class: gate-state files regenerate on every run and are not frozen evidence

`artifacts/navigation-and-menus/gate.json` (−3),
`artifacts/navigation-and-menus/grep-match-check.md` (−3) and
`artifacts/performance-stress-places/place.json` (−3) lost their old-name lines, and so
did `artifacts/code-simplicity-cleanup/public-surface.txt` (no brand strings, but four
new exports). **They were not edited. They are written by the checks that read them,
on every run**, and this task was required to run those checks.

The distinction was decided on their git history rather than by assertion
(`git log --oneline <file>`), and all four are the same class:

| File | Commits touching it | Verdict |
|---|---:|---|
| `code-simplicity-cleanup/public-surface.txt` | 7, four of them from unrelated later stages (virtual-grid, row-actions, Step 11, a docs sweep) | live gate-state — the `public-surface-unchanged` row REWRITES it every run |
| `navigation-and-menus/gate.json` | 5 | live gate-state — `tools/gate.sh` writes it |
| `navigation-and-menus/grep-match-check.md` | 4, two of them before that gate closed | live gate-state — the grep-match checker writes it |
| `performance-stress-places/place.json` | 3, two of them AFTER that phase closed | live gate-state — `check_perf_place.py` writes it |

None was written once at its phase close and left alone, which is what a frozen record
looks like; every one has been rewritten by later, unrelated runs. So the regenerated
version is kept. **Frozen raw evidence was not rewritten**: no Studio capture, spike
JSON, feasibility row, device matrix, review packet, consumer-impact ledger, acceptance
ledger or prior-gates roll-up under `artifacts/**` changed — which is exactly why
`tools/lune/gate_manifest.luau` and five python checkers still hold pre-rename literals
aimed at them (below). Confirmed empirically in the fix round: re-running eight gates
re-modified only `navigation-and-menus/gate.json` and `performance-stress-places/place.json`,
and `code-simplicity-cleanup/public-surface.txt` came back byte-identical to what the
previous run had written.

## The 205 remaining current-source matches — every file, with its reason

Every row the scanner reports, none merged, summing to exactly 205 across 25 files.

| Matches | File | Why it stays |
|---:|---|---|
| 65 | `games/RascalRally/docs/missions/racer-sort-parity-delta.md` | dated history; the brief leaves `docs/missions/**` alone |
| 13 | `games/RascalRally/docs/missions/HANDOFF_recap_marquee_and_rolepick_pop.md` | ditto |
| 5 | `games/RascalRally/docs/missions/HANDOFF_2026-08-04_black_screen.md` | ditto |
| 37 | `games/RascalRally/docs/DECISIONS.md` | append-only ledger. Old entries keep the name they were written under; the 2026-08-17 entry is appended and nothing above it edited |
| 21 | `GameStudio/ui/Facet/tools/lune/gate_manifest.luau` | 16 `grep`/`assert` literals aimed at files under `artifacts/**` (immutable evidence), restored one by one after the mechanical pass, plus 5 in prose notes that quote them. Every one verified to still match |
| 14 | `games/RascalRally/docs/migrations/facet-attribute-migration.md` | the five pre-rename attribute names ARE the migration: the doc lists each pair and the Studio snippet that licenses removing the fallback |
| 13 | `games/RascalRally/code/tests/facet_flag_migration.spec.luau` | the 29-case behavioural proof of the dual read — it must name the old attributes to assert they are still honored |
| 9 | `GameStudio/ui/Facet/tools/lune/check_flat_baseline.luau` | the six characterization entries added for the three renamed example titles: each `why` quotes the BEFORE text (`LuauUI Tiles` → `Facet Tiles`, and the same for Wordle and Match-3). A characterization that cannot name what changed is not a characterization |
| 7 | `games/RascalRally/code/src/client/FacetFlags.luau` | the `NAMES` table's five `old =` fallbacks plus the header explaining why they exist. Read only; never written |
| 4 | `GameStudio/ui/Facet/tools/check_perf_gate_evidence.py` | reads the FROZEN `perf-lab.json`: the `luauui` comparison key, and the `LuauUI/` → `Facet/` prefix normalisation applied to that capture's microprofiler bar names before comparing them to the live scope set |
| 2 | `GameStudio/ui/Facet/phases.json` | the Step-13 phase title ("the LuauUI-to-Facet rename" — the contrast is the subject), and the frozen design-spec path |
| 2 | `GameStudio/ui/Facet/tools/lune/theme_sync_cli.luau` | `LEGACY_SCHEMA = "luauui-theme-sync/1"` and its comment. Moved OUT of `src/themes/token_sync.luau` in the fix round so the shipped `build/Facet.rbxm` carries no old-brand string; it lives with its only consumer, which must still read Studio dumps recorded before the rename |
| 1 | `GameStudio/ui/Facet/docs/INVENTORY.md` | cites the frozen design spec `docs/superpowers/specs/2026-07-19-luauui-crossplatform-ui-design.md`, which the brief forbids touching. A citation must name the file that exists |
| 1 | `GameStudio/ui/Facet/requirements.json` | same frozen spec path |
| 1 | `games/RascalRally/docs/FACET_SETTINGS_PORT.md` | same frozen spec path |
| 1 | `GameStudio/ui/Facet/tests/theme_reference_packages.spec.luau` | the comment recording why the fantasy-parchment stamp was re-pinned (`luauui-theme/1` → `facet-theme/1`) |
| 1 | `GameStudio/ui/Facet/tools/check_device_captures.py` | reads a frozen device capture; keeps its `luauui-device-perf/1` schema |
| 1 | `GameStudio/ui/Facet/tools/check_perf_captures.py` | accepts BOTH spellings of one schema: frozen captures carry the old, the renamed lab emits the new, anything else is still refused |
| 1 | `GameStudio/ui/Facet/tools/check_sf_rows.py` | 34 frozen row artifacts carry `luauui-sf-row/1` |
| 1 | `GameStudio/ui/Facet/tools/check_xp_matrix.py` | the frozen `matrix.json` carries `luauui-device-matrix/1` |
| 1 | `games/RascalRally/code/src/client/init.client.luau` | the comment above the `FacetFlags` require, naming the pre-rename attributes it falls back to |
| 1 | `games/RascalRally/code/tests/run.luau` | the registration comment for the migration spec |
| 1 | `games/RascalRally/code/tests/facet_help_callout_contract.spec.luau` | one comment: why a pinned SORTED list's order moved |
| 1 | `games/RascalRally/code/tests/facet_motion_and_scroll_contract.spec.luau` | ditto |
| 1 | `games/RascalRally/code/tests/facet_theme_paint_contract.spec.luau` | one comment: where the flag read went |

**Closed in the fix round, and no longer in this table:** the 54 `vendor/Fusion/**`
files carrying `[LuauUI vendor patch]` (renamed to `[Facet vendor patch]`, and
`VENDOR.md`'s verbatim quote updated with them — they are OUR provenance annotations,
not Fusion's code); both `__pycache__/generate_art.cpython-314.pyc` (untracked with
`git rm --cached`; `__pycache__/` was already gitignored); `docs/plans/distribution-readiness.md`
(its two old-URL literals now reference `artifacts/release-candidate-review/step14-remote-packet.md`,
the one maintained holder of that string outside frozen evidence); and
`src/themes/token_sync.luau` (the legacy schema spelling moved to the dev tool that
consumes it, so nothing old-brand ships in `build/Facet.rbxm`).

## Persistent / external identifiers

The scanner's storage-flavoured heuristic flags 11 lines. **Every one is inside
`artifacts/**` or `games/RascalRally/docs/missions/**`** — both frozen. Zero live
sources write an old-name attribute, which is the single-write half of the migration
and is separately asserted by `tests/facet_flag_migration.spec.luau`
("SINGLE-WRITE: the shipped module never writes an attribute at all", using a fake
workspace whose `SetAttribute` fails the test).
