# Rename inventory — after (2026-08-17)

Scanner: `.superpowers/sdd/release-candidate-review/rename_inventory.py` (unchanged;
it auto-detects `GameStudio/ui/Facet`). Machine-readable output beside this file as
`after-inventory.json`. Pattern: `luau[\s._-]?ui`, case-insensitive, over the tracked
files of both git repos plus the untracked studio surfaces (`.claude/agents`,
`GameStudio/specialists`, `games/RascalRally/docs`, both `CLAUDE.md`).

## Counts by class

| Class | Before (`fe920dc`) | After | Δ |
|---|---:|---:|---:|
| current-source | 10788 | **252** | −10536 |
| generated-output | 1964 | **0** | −1964 |
| immutable-evidence | 2062 | **2191** | +129 |
| files carrying the name | 1031 | 270 | −761 |

**generated-output is zero.** Every place file, the model, and both Rojo trees were
REBUILT from renamed source, never text- or binary-patched.

**immutable-evidence went UP, and the reason is not a regression.** The before-scan
was taken at `fe920dc`; the controller then committed the release-candidate
baselines at `2a1823a` — `artifacts/release-candidate-review/baseline/{suite-rr.txt
(+159), suite-luauui.txt (+15), identity.md (+12), rename_inventory.py (+10),
studio/README.md (+9), facet-collision-check.md (+5)}` — new frozen artifacts that
by definition record the pre-rename name. That is +210. Against it, the framework's
`docs/lessons/**` (which this scanner classifies as immutable-evidence but which the
brief lists under §1d as documentation to rename) lost 81. Net +129.

## The 252 remaining current-source matches, every one with its reason

| Matches | Where | Why it stays |
|---:|---|---|
| 83 | `games/RascalRally/docs/missions/**` (3 files) | dated history; the brief leaves `docs/missions/**` and `docs/playtests/**` alone |
| 37 | `games/RascalRally/docs/DECISIONS.md` | append-only ledger. Old entries keep the name they were written under; the new entry (2026-08-17) is appended, nothing above it edited |
| 21 | `tools/lune/gate_manifest.luau` | the immutable-evidence quotes — 13 `grep`/`assert` literals that aim at files under `artifacts/**`, restored one by one after the mechanical pass (listed in `commands.md`) |
| 60 | `vendor/Fusion/**` (60 files, 1 each) | our `[LuauUI vendor patch]` provenance markers **inside licensed third-party sources**. The brief's do-not-touch list names `vendor/**` content, with the exception carved only for "OUR wrapper docs" — and `vendor/Fusion/VENDOR.md`'s single match *quotes that marker*, so renaming it would make the doc false. **Flagged as judgment call J-1: one `sed` reverses this if the controller wants it** |
| 36 | the attribute migration itself: `docs/migrations/facet-attribute-migration.md` (14), `tests/facet_flag_migration.spec.luau` (13), `src/client/FacetFlags.luau` (7), `src/client/init.client.luau` (1), `tests/run.luau` (1) | the five pre-rename attribute names ARE the migration. They are read as fallbacks and never written |
| 8 | `tools/check_perf_gate_evidence.py` (4), `check_device_captures.py`, `check_perf_captures.py`, `check_sf_rows.py`, `check_xp_matrix.py` (1 each) | checkers that read **frozen** capture artifacts, which carry the schema strings and key names they were written with. Same rule as the gate manifest |
| 3 | `games/RascalRally/code/tests/facet_{help_callout,motion_and_scroll,theme_paint}_contract.spec.luau` | one comment each explaining why a pinned list's ORDER moved / where the flag reader went |
| 1 | `tests/theme_reference_packages.spec.luau` | the comment recording why the fantasy-parchment stamp was re-pinned (`luauui-theme/1` → `facet-theme/1`) |
| 3 | `docs/plans/distribution-readiness.md` (2), `tools/lune/gate_manifest.luau`'s Step-14 note (counted above) | the git remote is still `https://github.com/josha/LuauUI`. The brief holds the remote until the owner's Step 14 checkpoint, so the "rename FROM" side of those sentences must keep the literal or the instruction becomes `Facet → Facet` |
| 2 | `phases.json` | the Step-13 phase title, "the LuauUI-to-Facet rename" — the contrast is the subject |
| 3 | `phases.json` / `requirements.json` / `docs/INVENTORY.md` (1 each) + 1 in `games/RascalRally/docs/FACET_SETTINGS_PORT.md` | the path of the frozen design spec, `docs/superpowers/specs/2026-07-19-luauui-crossplatform-ui-design.md`, which the brief forbids touching. A citation must name the file that exists |
| 2 | `assets/themes/{fantasy-parchment,glossy-touch}/source/__pycache__/generate_art.cpython-314.pyc` | tracked Python **bytecode caches** that embed the absolute source path they were compiled from. Not brand identifiers, not read by anything, regenerated on the next run of `generate_art.py`. `__pycache__/` is already gitignored for new files; deleting these two from the index is out of this task's scope. **Flagged as judgment call J-2** |

Sum: 83+37+21+60+36+8+3+1+2+2+3+2 = **256** by category, 252 by the scanner's own
count — the four-line difference is double-counting between the remote/Step-14 row
and the gate-manifest row, which the table notes.

## Persistent / external identifiers

The scanner's storage-flavoured heuristic flagged 11 lines. **Every one is inside
`artifacts/**` or `games/RascalRally/docs/missions/**`** — both frozen. Zero live
sources write an old-name attribute, which is the single-write half of the migration
and is separately asserted by `tests/facet_flag_migration.spec.luau`
("SINGLE-WRITE: the shipped module never writes an attribute at all", using a fake
workspace whose `SetAttribute` fails the test).
