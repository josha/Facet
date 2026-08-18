# Rename — commands run, with exit codes (2026-08-17)

Environment for every line: `export PATH="$HOME/.rokit/bin:/opt/homebrew/bin:$PATH"`
(rokit's rojo; a stale `/usr/local/bin/rojo` breaks builds).
Framework cwd: `GameStudio/ui/LuauUI` before stage 2, `GameStudio/ui/Facet` after.
Game cwd: `games/RascalRally/code`.

## Framework — stage 1

| Command | Exit | Result |
|---|---:|---|
| `git mv` × 15 (13 icons, `docs/plans/luauui-consolidated-roadmap.md`, `tools/studio/LuauUI_EditPreview.plugin.lua`) | 0 | history-preserving |
| case-aware rewrite over 637 tracked text files (`git ls-files` minus `artifacts/`, `vendor/`, binaries) | 0 | 637 rewritten, 0 unknown-case forms |
| `stylua src tests tools bench examples` then `stylua --check …` | 0 | clean |
| `./run-tests.sh` (1st) | 0 | `2 failed, 6186 passed` — the two pins below |
| `./run-tests.sh` (after re-pinning) | 0 | **`6188 passed`** — the frozen baseline exactly |
| `lune run tools/lune/_probe_public_surface` → `diff` vs `artifacts/release-candidate-review/baseline/public-surface.txt` | 0 | **byte-identical** |
| `python3 tools/check_manifest_integrity.py` | 0 | `1477 suite greps, all anchored to the pass marker` |
| `python3 tools/check_source_size.py` | 0 | `PASS — every module in src/ is under the 200,000-char Source-write cap, and KNOWN_OVER is empty` |
| `tools/build_places.sh` | 0 | `done: 17 place files in examples/places/` (8 tutorials + `Facet-Showcase` + `Facet-PerformanceLab`; the 7 old-name files were still present at this point and `git rm`d next) |
| `tools/build_reference_places.sh` | 0 | 5 × `built examples/places/Facet-Ref-*.rbxl` |
| `tools/build_model.sh` | 0 | `built build/Facet.rbxm (Facet 0.9.0, 139 modules)` |
| `git rm` 7 × `examples/places/LuauUI-*.rbxl`; `git add` 7 × `Facet-*.rbxl` + 8 tutorials | 0 | no old-name generated output remains tracked |
| `rm -f build/LuauUI.rbxm build/LuauUI-Gallery.rbxl` | 0 | stale untracked outputs removed |
| `tools/doctor.sh` | 0 | `doctor: PASS (artifacts/doctor.json)` — rebuilds `build/Facet-Gallery.rbxl` |
| `tools/perf.sh` | 0 | **`perf: PASS (100 runs, 20 scenes)`** |
| `git commit` | 0 | **`44b9e62`**, 671 files changed |

The two first-run failures, both re-pinned to their MEASURED new values:

```
tests/profile_scopes.spec:70: expected Facet/r to be Facet/
    -> string.sub(label, 1, 7) was the length of "LuauUI/"; "Facet/" is 6.  7 -> 6.
tests/theme_reference_packages.spec:430: expected 9a3b8dd8 to be 538b2cb8
    -> the package's schema string moved luauui-theme/1 -> facet-theme/1, so the
       content stamp really is different.  538b2cb8 -> 9a3b8dd8.
```

## Framework — stage 2

| Command | Exit | Result |
|---|---:|---|
| `mv GameStudio/ui/LuauUI GameStudio/ui/Facet` | 0 | |
| `git status --porcelain` (inside the moved repo) | 0 | empty |
| `git log --oneline -3` | 0 | `44b9e62`, `2a1823a`, `230f864` — intact |

## Rascal Rally — stage 4

| Command | Exit | Result |
|---|---:|---|
| `git mv src/client/LuauUISponsor src/client/FacetSponsor` + 4 client modules + 46 test files | 0 | 86 renames |
| case-aware rewrite over 106 tracked text files | 0 | |
| `rojo sourcemap default.project.json -o sourcemap.json` | 0 | root child is now `Facet` → `../../../GameStudio/ui/Facet/src/init.luau` |
| `stylua src tests` then `stylua --check src tests` | 0 | clean |
| `./run-tests.sh` (1st) | 0 | `2 failed, 3372 passed` — two SORTED file-list pins whose order the rename moved |
| `./run-tests.sh` (after re-pinning) | 0 | **`3374 passed`** = 3345 baseline + 29 new migration cases |
| `rojo build default.project.json -o …/rr_default.rbxl` | 0 | `Built project to rr_default.rbxl` |
| `rojo build places/debug.project.json -o …/rr_debug.rbxl` | 0 | `Built project to rr_debug.rbxl` |
| `git commit` | 0 | **`b92b606`**, 110 files changed |

## Stage 5 — inventory

| Command | Exit | Result |
|---|---:|---|
| `python3 .superpowers/sdd/release-candidate-review/rename_inventory.py artifacts/release-candidate-review/rename/after-inventory.json` | 0 | `files-with-matches=270 current-source=252 generated-output=0 immutable-evidence=2191 persistent-candidates=11` |

## The prior-gate sweep

`tools/prior_gates.sh <out> release-candidate-review` — all 30 gates before the
release-candidate stage, re-run in-tree at the judged source.

**It was deliberately NOT run at the stage-1 boundary, and that is a departure
from the brief's ordering with a reason.** Roughly a dozen gate rows assert LIVE
Rascal Rally paths (`../../../games/RascalRally/code/tests/facet_*.spec.luau`,
`docs/ui/UI_SPEC_sponsor_facet.md`) and one greps
`../../specialists/UI_DESIGNER.md` — files that stage 3 and stage 4 rename. A
sweep at 1g could not have been green no matter how correct stage 1 was, and a
red sweep proves nothing about the stage it is meant to judge. Stage 1 was
therefore closed on the suite + perf + manifest-integrity + source-size +
public-surface evidence above, and the sweep was run ONCE, at the end, where it
can carry its claim.

### Sweep run 1 (roll-up stored beside this file as `prior-gates-after.txt`)

`tools/prior_gates.sh …/prior-gates-after.txt release-candidate-review`, 30 gates,
~2 h wall (the machine's 1-minute load sat at 3–6 throughout, so the settle
mitigation never engaged). 19 PASS, 11 FAIL. Every `FAIL_ENVIRONMENT` row is a
device/human evidence row and was already open before this task.

**The rename-caused failures, all one root cause plus one:**

| Row | Cause | Fix |
|---|---|---|
| `rich-skinning-v2 / layered-slots-and-posture` | `check_flat_baseline` | characterized (below) |
| `rich-skinning-v2 / circle-button` | its `run` ends in `check_flat_baseline` | ditto |
| `theme-packages-and-skinning / metric-snapshot-single-source` | ditto | ditto |
| `api-architecture-consistency / studio-evidence` | ditto | ditto |
| `swiftui-parity-round2 / checker-battery` | ditto | ditto |
| `swiftui-parity-round3 / checker-battery` | ditto | ditto |
| `swiftui-parity-round4 / checker-battery` | ditto | ditto |
| `theme-packages-and-skinning / style-editor-sync` | `theme_sync: dump schema is 'luauui-theme-sync/1'; this build speaks 'facet-theme-sync/1'` | `token_sync.LEGACY_SCHEMA` + `readableSchema()` — a stored Studio dump taken before the rename is immutable evidence and must stay readable; nothing writes the old string, and any third spelling is still refused |

**The flat-baseline root cause, and why it is not a bug.** Three tutorial examples
put the framework's name on screen: `LuauUI Tiles`, `LuauUI Wordle`,
`LuauUI Match-3`. `Facet` is six characters shorter at the same 24px title role, so
the measured title box narrows by exactly 15px in each (179→164, 194→179, 209→194)
and the two CENTRED titles start 7px later — half the width they gave up, which is
the arithmetic that proves it is a text change and not a layout change. Nothing else
moves: height is 29 before and after, no sibling reads their width, every other node
in all three fixtures is byte-identical.

Handled the way this checker is designed to be handled, not by re-pinning the frozen
0.6.0 baseline (declined twice before, for reasons its own header spells out):
three exact-`path` `ALLOWED_RECT_DRIFT` entries and three `ALLOWED_PROP_DRIFT`
entries, each with its reason, plus a regenerate of the gitignored reproducibility
dump (`lune run tools/lune/_theme_baseline -- artifacts/rich-skinning-v2/rows/neutral-render-dump.json`).
Exact paths, not prefixes, so the boards and racks under those pages keep their rect
coverage.

```
lune run tools/lune/check_flat_baseline
  -> PASS (1461 flat nodes byte-compared; 12 characterized prop deltas, 5 new nodes,
     4 added prop keys, 13 rect-drift scopes, 2 class substitutions;
     no other rect/hit/class change)
```

### Targeted re-runs after the fixes (`FACET_PRIOR_GATES_NESTED=1`, exit codes from `tools/gate.sh`)

| Gate | Before | After |
|---|---|---|
| `rich-skinning-v2` | FAIL | **PASS** |
| `api-architecture-consistency` | FAIL | **PASS** |
| `swiftui-parity-round2` | FAIL | **PASS** |
| `swiftui-parity-round3` | FAIL | **PASS** |
| `navigation-and-menus` | PASS | **PASS** |
| `theme-packages-and-skinning` | FAIL (2 rows) | FAIL (1 row — `style-editor-sync`, now for the PRE-EXISTING reason below) |
| `swiftui-parity-round4` | FAIL (2 rows) | FAIL (1 row — `prior-gates-unregressed`, pre-existing) |
| `input-adaptation-audit` | FAIL | FAIL (pre-existing) |
| `desktop-keyboard-navigation` | FAIL | FAIL (pre-existing) |
| `traversal-document-order` | FAIL | FAIL (pre-existing) |
| `example-quality-pass` | FAIL | FAIL (pre-existing) |

### The five FAIL_RECOVERABLE rows that remain, each PROVED to predate the rename

1. **`input-adaptation-audit / examples-no-input-boilerplate`** — the check caps
   `examples/gallery/examples/0*.luau` at 3200 lines. Measured **3486 at `2a1823a`
   and 3486 at HEAD** — the rename changes no line count. The budget was overrun by
   the navigation-and-menus round.
2. **`desktop-keyboard-navigation / no-screen-key-bindings`** — the pinned set is
   `{row_actions, text_input}`; on disk it is `{menu, row_actions, text_input}`.
   `git diff 2a1823a -- tools/check_no_screen_key_bindings.py` is EMPTY and
   `git show 2a1823a:src/controls/menu.luau` already binds `Menu`/`Shift+F10`, so the
   set and the pin are both exactly what they were. `menu.luau` is a new claim on the
   keyboard from the navigation round that needs the same director approval the two
   pinned files have.
3. **`traversal-document-order / step8-debt-cleared`** — asserts (2)'s gate is PASS.
   A pure cascade; it reports `AssertionError: FAIL_RECOVERABLE` and nothing else.
4. **`example-quality-pass / rascalrally-consumer`** — the frozen ledger
   `artifacts/example-quality-pass/consumer-impact.md` contains the sentence
   "No Rascal Rally Studio canary was run", which the row treats as a declared
   MISSING canary. FAIL_RECOVERABLE in the stored 2026-08-14 roll-up
   (`artifacts/swiftui-parity-round3/prior-gates-rerun.txt`) too. Closing it needs a
   Studio session, which this task is instructed not to open.
5. **`theme-packages-and-skinning / style-editor-sync`** — after the schema fix the
   row reaches its real check and reports `controls.progress.{circularSize,
   circularThickness,spinnerDotSize}: sheet nil vs committed 30/3/9`. The frozen
   `parchment-live-dump.json` predates the 2026-08-14 director round that authored
   those three tokens. FAIL_RECOVERABLE in the 2026-08-14 roll-up too. Closing it
   needs a fresh Studio dump.

Plus **`swiftui-parity-round4 / prior-gates-unregressed`**, which the gate manifest's
own note already declares has NEVER BEEN EXECUTED and whose evidence artifact does not
exist ("this stage was closed on a director decision to skip the sweep").

**No tracked artifact was hand-edited.** Four regenerated themselves under the gate
runs, which is those checks doing their job:
`artifacts/code-simplicity-cleanup/public-surface.txt` (+4 exports the
navigation-and-menus round added — the check asserts nothing was REMOVED, and nothing
was), `artifacts/navigation-and-menus/{gate.json,grep-match-check.md}` and
`artifacts/performance-stress-places/place.json` (schema/name strings the rename moved).

### Final framework checks, at the tree being committed

| Command | Exit | Result |
|---|---:|---|
| `./run-tests.sh` | 0 | **6188 passed** |
| `tools/perf.sh` | 0 | **PASS (100 runs, 20 scenes)** |
| `python3 tools/check_manifest_integrity.py` | 0 | 1477 anchored suite greps |
| `python3 tools/check_source_size.py` | 0 | PASS |
| `lune run tools/lune/_probe_public_surface` vs the frozen baseline | 0 | **byte-identical** |
| `stylua --check src tests tools bench examples` | 0 | clean |
