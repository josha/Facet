# D8 — the playlist table sorts and resizes, and `table_columns` is retired

**Date:** 2026-08-16. **Brief:** `docs/plans/navigation-and-menus-brief.md` §2 D8,
§6 ruling 7. **Evidence level:** E1 (headless) throughout; the gesture rows below
that need a real finger are named as pending at the end.

Both capabilities already shipped in `src/controls/table.luau`, so nothing in
`src/` changed except two comments that named a file this commit deletes. This is
an example task.

---

## 1. The measurement that decided the third column

The brief made the third column conditional on repeating a measurement, because
the playlist had *deleted* a third column on 2026-08-13 for a measured reason: a
third **fixed** 70px column plus edit mode's two leading gutters left the Name cell
6px wide at 320x640 and the solver filed *"content box collapses to 0px on x"*.
Whether a third **`fill`** column behaves differently was explicitly a hypothesis.

**Instrument.** The shipped example module, mounted through the real presenter and
`fake_target`, at `viewportRect 320x640`, `capabilities = { touch = true, mouse =
false, keyboard = false, gamepad = false }`, then `api.editing:set(true)`. Cell and
`Value` rects read off the adapter; collapse diagnostics counted from
`handle.controller.diagnostics()`.

**Instrument validated against the historical failure first.** Re-running the
deleted shape reproduces the file's own recorded numbers exactly — 6px cell, 0px
text — so the harness can see the defect it is being asked about.

| Shape @ 320x640, touch, EDIT MODE | Name cell / text | Artist cell / text | Rating | collapse diagnostics |
|---|---|---|---|---|
| two columns (what shipped) | **76 / 60** | — | 144 | 0 |
| third **FIXED** 70px (deleted 2026-08-13) | **6 / 0** | 70 / 54 | 144 | **3** |
| third **FILL** weight 2, minWidth 72 (**shipped**) | **46 / 30** | **30 / 14** | 144 | **0** |

Two viewports up, same mode: `359x718` gives Name 69/53 and Artist 46/30;
`390x844` gives Name 88/72 and Artist 58/42. Outside edit mode at 320x640 the
three columns are Name 86/70, Artist 58/42, Rating 144.

**Verdict: the third column was KEPT.** The hypothesis holds where it was posed —
the `fill` column does not reproduce the collapse, and the row's *subject* keeps
30px of text where the fixed column left it none. The price is the Artist cell at
14px of text, at that one viewport, in that one mode. It is paid rather than
hidden: both text columns carry `disclose = true` so a truncated value stays
reachable, and both truncate to **one line** (`lines = 1/1, truncated = true`)
rather than wrapping into a row that cannot hold them. Every number above is
pinned in `tests/playlist_columns.spec.luau` so it cannot drift in silence.

**`minWidth` floors a RESIZE, not the LAYOUT.** Measured, not assumed:
`resolveDim` (`table.luau:1140-1144`) applies `minWidth` only to an *override* and
to a `percent` band, so a plain `fill` column is divided by weight with no floor —
90/72 requested, 46/30 delivered. `{ type = "minMax" }` was tried instead and is
wrong here for the reason `hug` was wrong: the header resolved 90/70 while the body
resolved 175/137, so the grids disagreed. The declared 90/72 is therefore the
narrowest a *player* may drag to, and it is explicit because the default is 24px.

## 2. Why a third column was structurally required

`resolveDim` turns any resized column into `{ type = "fixed", px }`. Measured at
800x600, pinning Name to 200:

| columns | header spans after the pin | cells region |
|---|---|---|
| two (`fill` Name + fixed Rating) | `name 16..216`, `rating 216..360` | `16..784` — **424px of dead space** |
| three (`fill` Name + `fill` Artist + fixed Rating) | `name 16..216`, `artist 216..640`, `rating 640..784` | `16..784` — fills |

That is the "degenerate resize" the brief refused to ship, measured rather than
argued, and the three-column row is the fix.

## 3. Reorder versus sort — the rule, and where it is enforced

**A manual reorder wins and takes the sort with it (the iTunes rule).** It is
implemented as a *bake*, not a refusal: `bakeManualOrder()` writes the currently
displayed order into `baseRows` and sets `sortOrder` to `nil`, so a drop's slot
means exactly what was on screen when the player let go. Enforced in
`examples/gallery/examples/02_playlist_table.luau` at the two order-writing
commands — `reorder` (the Table's `onReorder`) and `moveToTop` (the leading swipe
action). `removeTrack` deliberately does **not** bake: deleting a row from a sorted
list leaves a sorted list.

**The guard runs before the bake**, and that is a defect this stage found in its own
first draft rather than a design note. Baking *writes*, so a `moveToTop` naming a
track already removed — or a drop carrying no keys — would have dropped the player's
sort on the way to doing nothing at all. "A manual reorder clears the sort" has to
mean a reorder that actually happens. One case covers both shapes, and **both
mutations** (deleting either guard) redden it by name.

The composition it rests on is the derivation order: **sort is a derivation over
the source, filter is a derivation over the sorted view.** Filtering first would
leave the full ordered list existing nowhere, and both "move to top" and the bake
need it. Both memos hand back the array they were given when they have nothing to
do, so an unsorted, unfiltered playlist costs a comparison rather than a copy.

The pre-existing **reorder-under-filter** rule is unchanged and is the opposite
answer to a deliberately different question: under a filter the drop is ambiguous
against the hidden rows, so it is refused (and the sort is left alone); under a
sort every row is on screen and the drop is well defined, so it is honoured.

Ties break on the **source index**, because `table.sort` is not stable in Luau —
two tracks share the artist "Nine Volt" precisely so that is observable.

## 4. The spec re-pointing, done before the deletion

| Was | Now |
|---|---|
| `tests/table_columns.spec.luau` (19 cases, 6 `describe` blocks) | `tests/playlist_columns.spec.luau` (**38 cases**, 11 blocks), registered in `tests/run.luau` |
| `tests/hit_expander_overhang.spec.luau:43` **required the scenario module** | requires `examples/gallery/examples/02_playlist_table`; header root `/TableColumns/TablePane/Entrants/Main/Header` → `/Playlist/Page/Tracks/Main/Header`; neighbour column `team` → `artist`; a second `mountExample` helper carries the example's different build signature |
| `tests/scroll_window_clip.spec.luau:59` cited it by name | re-pointed with the rename recorded |
| `tests/measure_publish_settle.spec.luau:419` cited it by name | re-pointed with the rename recorded |
| `tests/table_themed_header.spec.luau`, `tests/table.spec.luau`, `tests/layout.spec.luau` | citations updated |
| `tests/overflow_sweep.spec.luau:356` swept it (RULE 4: sweep list == scenario registry) | removed, with a note that the header is still swept at every viewport x text preference by `example_readouts.spec` (which walks the tutorials) and pinned by `playlist_columns.spec` |
| `tests/gallery_demo_picker.spec.luau` pinned 32 demos / 25 fixtures / a `table-columns` root | 31 / 24, root removed |
| `docs/lessons/` x4, `docs/reference/api.md`, `src/controls/table.luau`, `src/render/hit_lift.luau` | citations updated (comments only in `src/`) |
| `artifacts/table-columns/mutations.md` | marked historical, with the new runner named |

**Every block carried over, none dropped.** The scenario-runner `steps` block became
"the device funnels each move the model" driving `api.handleActivate({source =
"action"})` and `api.handleGrabNavigate` directly — the same funnels the steps
called. The header-boundaries invariant kept its own scrolling three-column table,
because the playlist is a **block** table (`scrolls = false`) and reserves no bar of
its own. Two new blocks were added: the sort/composition cases, and the 320x640
measurement above.

Then, and only then: `examples/gallery/scenarios/table_columns.luau`,
`tests/table_columns.spec.luau` and the two registrations were deleted.

## 5. The three stale claims this closes

1. `table_columns.luau:30` called `02_playlist_table` "the shipped tutorial for
   sorting, filtering and reordering" — `grep -c sortOrder` on it returned **0**.
   File deleted; the claim is true of the surviving file.
2. The playlist's own header comment did not mention sorting or resizing. It does
   now, with the measurement.
3. **The most public one, and it was not in the brief:** the demo picker's blurb
   for `ex02` read *"Sortable, reorderable, filterable table"* — verbatim in the
   live `LuauUIShowcaseAPI.list` response — so the example had been advertising
   sorting to every device pass and every human reviewer while not having it. It
   now reads *"Sort, filter, reorder — and drag a divider to resize a column"*, and
   it is true.

## 6. A behaviour change worth naming

A sortable, resizable header is **focusable**, so the playlist gained a focus stop.
The measured walks:

- **D-pad:** filter field → header band (ONE stop; Left/Right walks the columns) →
  toolbar → rows.
- **Tab (document-order rank):** … → `Head-name` → `Head-artist` → `Head-rating` →
  the row's tray/content.

Three cases in `tests/examples_gallery.spec.luau` were updated to assert the new
order explicitly rather than to skip past it — a header a pad cannot reach would be
a sort a pad cannot perform.

## 7. Results

| Command | Result |
|---|---|
| `lune run tests/run` (LuauUI) | **5685 passed**, 4 failed — all four are another agent's in-flight `SelectionIndicator` (D4); zero D8 failures |
| `lune run tests/run_one playlist_columns` | **38 passed / 0 failed** |
| `lune run tests/run_one examples_gallery` | 135 passed / 0 failed |
| `lune run tests/run_one hit_expander_overhang` | 5 passed / 0 failed |
| `lune run tests/run_one gallery_demo_picker` | 37 passed / 0 failed |
| `cd games/RascalRally/code && lune run tests/run` | **3285 passed / 0 failed** |
| `python3 tools/check_source_size.py` | PASS, `KNOWN_OVER` empty |
| `python3 tools/check_manifest_integrity.py` | PASS — 1128 suite greps, all anchored |
| `lune run tools/lune/check_prop_parity_cli` | PASS (27 classes, 666 properties) |
| `lune run tools/lune/check_docs` | PASS |
| `lune run tools/lune/check_theme_drift` | PASS |
| `lune run tools/lune/check_example_drift_cli` | clean — 74 files, 440 semantic role uses |
| `stylua --check src tests examples` | clean for every D8 path |
| `lune run tools/lune/check_registration_cli` / `check_surface_ledger` | fail **only** on `newSelectionIndicator` (D4's in-flight export) |

## 8. Rascal Rally consumer ledger

No production-game edit was correct, and that is a finding rather than an omission:
the only `src/` changes in this deliverable are **two comments** (`table.luau`'s
`columnWidthOverrides` note and its gutter-convergence note, plus `hit_lift.luau`'s
measurement citation). No contract, default, behaviour, asset or distribution
output moved.

- **Caller survey.** `grep` across `games/RascalRally/code` for `table_columns`,
  `02_playlist_table`, `columnWidthOverrides` and `sortOrder`: the game never
  mounts the gallery, and its only dependency on this area is
  `api.columnWidthOverrides`, which is untouched.
- **The live-consumer test already exists and is green.**
  `code/tests/luauui_racer_list.spec.luau` asserts `columnWidthOverrides` is a
  **Readable on the game's own table** (`type(...) == "table"`, `.get` is a
  function, reads empty) — the contract the framework comment describes, exercised
  through `LuauUIRacerListScreen`.
- **Citation updated:** `code/tests/luauui_hit_expander_overhang_contract.spec.luau`
  named the retired fixture; it now names the surface the measurement moved to.
- **Suite:** 3285 passed / 0 failed.

## 9. What this does NOT claim

- **No physical-device claim.** A divider is 8px against a 44px touch floor
  (`docs/lessons/an-eight-pixel-divider-on-a-forty-four-pixel-finger.md`, pinned
  again here as `grip8x28` under Touch), so whether a finger can land on it is a
  `PENDING_PHYSICAL` row, unchanged by this deliverable.
- **No Studio claim.** Every number here is headless E1. The live drives this file
  cites (the arrow keys the camera sinks, the 44px band per pixel) were measured on
  2026-08-14 on the retired fixture and are carried forward as history, not
  re-measured.
- **The mutation ledger was not re-run.** `artifacts/table-columns/mutations.md`
  records mutations against files that no longer exist; it is marked historical
  rather than re-executed.
