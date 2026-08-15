# `table_columns` — mutation ledger

Every check added by this mission, broken on purpose, watched to redden by NAME,
and restored. Run with `lune run tests/run_one table_columns` (13 cases).

Baseline: **13 passed / 0 failed**.

| # | Mutation | File | Case(s) that reddened |
|---|---|---|---|
| M1 | `header = true` → `false` | `examples/gallery/scenarios/table_columns.luau` | 10 of 12 — every case in the file except the two that do not touch the band |
| M2 | `team` column drops `resizable = true` | fixture | `a resizable column grows a divider and a locked one refuses…` |
| M3 | `api.columnWidthOverrides` reverted to a zero-arg getter | `src/controls/table.luau` | `a resizable column grows a divider…`, `a pointer drag on the divider MOVES the column…`, `disposes clean…` |
| M4 | `ADJUST_STEP = 16` → `8` | `src/controls/table.luau` | `a KEYBOARD reaches it…`, `a GAMEPAD reaches it…`, `its steps drive the DEVICE funnels…` |
| M5 | grip `px = "s"` → `"m"` | `src/controls/table.luau` | `the grip is the theme's small spacing step in every paradigm…` |
| M7 | `widthsVersion` bump removed from `setColumnWidth` | `src/controls/table.luau` | `a committed width remounts the WINDOWED rows…` |
| M8 | the hint memo stops reading `selectedColumn` | fixture | `SELECTING A COLUMN PAINTS NOTHING…` |
| M9b | `Grip` loses its `minHitSize` declaration | `src/controls/contract.luau` | `asks for 44x44 centred on an 8x28 grip…` |
| M10c | the LOCKED column (`best`) becomes `resizable` | fixture | `a resizable column grows a divider…`, `a LOCKED column binds no Adjust key at all…` |
| M11 | `"table_columns"` removed from `ORDER` | `examples/gallery/scenarios/init.luau` | `RULE 4: the sweep list and the scenario registry are the same set` (`overflow_sweep`) + `every fixture the picker offers is registered…` (`gallery_demo_picker`) |

## Three mutations that did NOT bite on the first attempt, and what they exposed

**M6 / M6b — `stepColumnWidth`'s `resizable ~= true` guard, and `adjustTargets`'
`isResizableId` filter, removed one at a time: the suite stayed green.**
Breaking either alone changes nothing, because a locked column is refused at
*three* independent gates (`adjustTargets` never binds the key, `stepColumnWidth`
declines, `api.setColumnWidth` declines again). Breaking all three at once still
did not redden — which sent me back to the check itself, and the check was the
problem (below). Recorded because "I broke the guard and the suite stayed green"
read, for twenty minutes, like a missing test rather than like defence in depth.

**M9 — `Grip.minHitSize = 44` → `0`: the suite stayed green.** The floor is
`math.max(declared, metrics.targetSizes.minimum)`
(`src/render/layout_node.luau:182-186`) and Studio Neutral's own `targetSizes.
minimum` is also 44, so zeroing the declaration changes nothing at all. The
mutation that bites is *removing the key*, which turns the floor into `nil`. A
mutation that lowers a value under a `max` is not a mutation.

**M10 — the original `a LOCKED column binds no Adjust key` case could not fail.**
It pressed `ButtonR1` and then `ButtonL1` and compared the widths to the ones
before both. `+16` followed by `−16` nets to zero, so the case passed identically
whether the key was bound or not — a check satisfied by the thing it was supposed
to detect. Rewritten to one press, plus a positive control on a resizable heading
in the same session; it now reddens under M10c. This is the class the round-3
brief names ("`≤ a ceiling` was also satisfied by mounting nothing"), met again.
