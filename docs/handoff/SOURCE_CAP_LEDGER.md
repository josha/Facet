# Source-cap ledger — the modules inside the warning band

**What this file is.** `tools/check_source_size.py` fails any module in `src/`
that reaches **190,000** characters unless it has a row here, and fails outright
at **200,000** — the length at which Roblox refuses a `Script.Source` write and
a module silently stops live-syncing into an open Studio session
(`docs/lessons/the-200k-source-cap-is-on-writing-not-loading.md`).

**Why a ledger rather than a warning.** A warning is a thing you scroll past.
Before the band existed (release-candidate review MAINT-1, 2026-08-17) the
check's only size branch was `>= CAP`, so the first signal was the commit that
made a file unsyncable — and the remedy the checker's own header prescribes
(find a seam by the mutable-upvalue test, prove it with a live Studio A/B) is a
multi-hour mission, not an edit. Five modules were inside 10 KB of the cap and
`renderer.luau` was **350 characters** from it. The band converts that cliff
into a requirement to have done the thinking while it is still cheap.

**What a row must carry**, all three mechanically enforced:

1. **its size when the row was last touched** — within 2,000 characters of the
   file's current size, or the check fails and asks for both the number and a
   re-read of the analysis. A file that moved is a file whose seam analysis is
   worth looking at again;
2. **a seam analysis** — the one-way extraction candidates by name, or the
   recorded reason none exists. "One-way" is the checker header's own test: a
   block that reads no mutable upvalue of its host, so moving it cannot create a
   require back;
3. **the trigger that ends the deferral** — the condition under which the next
   extraction happens, not a date.

## The band

| module | size | seam analysis | next-extraction trigger |
|---|---|---|---|
| `src/controls/table.luau` | 198,764 | **One seam TAKEN, 2026-08-17:** the column-width RESOLUTION rule (the DIR-4 clamp) went to `controls/table_columns.luau` — pure, every input an argument, one-way by construction. It was extracted the same day it was written, because writing it in place put this file at 202,200 and over the cap. **Beyond it, no one-way seam exists, and this records why.** The file is ~250 lines of module-level types and constants followed by ONE `newTable` closure that is everything else. Every large block inside it (`rowBlueprint` 19 KB, the sort/column region 23 KB, `dump` 11 KB, `handleActivate` 10 KB, `screenSeed` 10 KB, `rowPointerHandlers` 8 KB) reads mutable instance upvalues — `spec`, `state`, `scope`, `core`, the signals — so extracting any of them means passing a state object, which is a refactor of the control rather than a move. The genuinely pure decisions ALREADY left: `virtual_extents`, `row_capability`, `row_actions_state`, `native_scroll_binding`, `text_fit`. The one module-level candidate left, `ROW_ART`, is four lines of data under 45 lines of device-round reasoning — moving it would separate the two and buy ~1 KB. | The row/cell BUILDER (`rowBlueprint` + `rowPointerHandlers`, ~27 KB together) becomes one-way the moment the row's inputs are a parameter object rather than upvalues, which is the same change `newVirtualList` needs for MAINT-14's duplicated axis-lock predicate. **1,236 chars of headroom, and this file has now taken two consecutive rounds of work** (DIR-4, then its gap/padding correction) — each time paying for itself only by extracting the new rule and trimming prose, which is a technique with a floor. THE NEXT CHANGE OF ANY SIZE MUST BE PRECEDED BY THE BUILDER EXTRACTION, not accompanied by it: `rowBlueprint` + `rowPointerHandlers` behind a parameter object, ~27 KB, the same change `newVirtualList` needs for MAINT-14's duplicated axis-lock predicate. |
| `src/controls/row_actions.luau` | 192,979 | `dump()` is 42 KB — 22% of the file — and is the strongest candidate in the framework: a dump builder reads state and writes nothing, so a `row_actions_dump.luau` taking the tray/edge/commit records as arguments cannot require back. It is NOT yet one-way as written (it closes over ~a dozen live upvalues), but unlike table's builders it needs no behavioural change, only an argument list. `doCommitAction` (10 KB) and `commitDestructive` (7 KB) share the irrevocable-commit state machine and must stay together with it. | Extract `dump()` on the next mission that changes the dump schema — the argument list is written for free when the fields are already being touched — or immediately if this file passes 196,000. |
| `src/render/renderer.luau` | 194,791 | **One seam TAKEN, 2026-08-17:** the prop-channel manifest (`BINDING_PROPS`, `STYLE_PROPS`, `STYLE_PROP_ORDER`, `BINDING_PROP_CLASSES`, `emitsBinding`, `DIRECT_PROPS` and their two load-time completeness assertions) moved to `render/prop_channels.luau` — 8.1 KB, module-level data plus one pure predicate, reading no `attach` upvalue at all. Remaining candidates, in order of honesty: `sameGeometryValue` (pure, ~600 chars — real but small); `findNode`/`rectsEqual`-class helpers (pure, ~1 KB combined). Everything else is the three entangled blocks the campaign already named — `solveAndApply` (28 KB), `ensureTree` (22 KB), `structuralSync` (10 KB) — each reading `handles`, `lastRects`, `lastZ`, `stats` and the solve caches, i.e. the mutable-upvalue test fails by construction. | The next extraction is `rect_pass`-shaped: lift the RECT WRITE half of `solveAndApply` (the diff-and-write loop, not the solve) once `lastRects` is owned by a record object rather than a closure upvalue. Trigger: this file passes 197,000, or the next mission that touches the rect diff. |
| `src/present/presenter.luau` | 190,326 | `makeHandle` is 84,819 characters — 45% of the file — and the checker's own header already records the judgement that it is too entangled to split (it is the surface lifecycle: mount, render, focus, transitions, dismissal and the critical-screen fallback, all reading the presenter's live stacks). That judgement stands and is re-confirmed here. The one-way candidates outside it are small and real: `syncFocusVisuals` (7 KB) reads `focus` and the controller only; `refreshBody` (6 KB) reads the surface list. Neither is worth a file on its own; together with the dismissal region they would be a "surface lifecycle helpers" module of ~20 KB. | Extract the focus-visual + refresh pair when a third member joins them, or immediately if this file passes 195,000. `makeHandle` is not a candidate at any size — if the presenter needs room, it comes from around `makeHandle`, never from inside it. |

## Modules approaching the band

Not required to have a row, listed so the next reader knows where the pressure
is going next. Re-measure with `python3 tools/check_source_size.py`.

- `src/client/screen_target.luau` — 187,353. Splits five siblings already
  (`screen_chrome`, `screen_paint`, `screen_scroll_indicators`,
  `screen_presentation`, `screen_pointer`); the same rule applies, and
  `tests/lib/adapter_source.luau` must gain a part for every new one.
- `src/layout/solver.luau` — 179,850, three blocks already out
  (`placement`, `shrink`, `grid`).
- `src/controls/virtual_list.luau` — 179,338.
