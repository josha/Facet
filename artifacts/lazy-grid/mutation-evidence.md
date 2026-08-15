# The lazy grid — mutation evidence

Every check `newVirtualGrid` added was broken on purpose, the suite run, and the
NAMED case that reddened recorded. A check nobody has watched fail is a check
nobody has any reason to believe.

Method: the module is copied to a byte-verified backup (`shasum`), one mutation is
applied to the working copy, `tests/virtual_grid.spec.luau` +
`tests/virtual_grid_input.spec.luau` are run, the reddened case names are
captured, and the backup is restored and its hash re-checked. No `git reset`, no
`git checkout`, no `git stash` at any point.

Baseline: **33 passed, 0 failed** (21 layout/laziness cases + 12 four-input
cases).

---

## Round 1 — twelve mutations, nine bit

| # | mutation | verdict |
|---|---|---|
| M1 | the window goes EAGER (`window` returns `1..count`) | **9 cases** reddened, incl. `10 000 items, 4 lanes: the EXACT cells of the windowed lines are built and no others` and `the build count does not depend on N` |
| M2 | the line count becomes the ITEM count (the index's unit forgotten) | **4 cases**, incl. `the canvas extent IS virtual_extents.uniform over ceil(N / lanes) lines — a differential` |
| M3 | the band's `UI.Grid` is given one column too many | **3 cases**, incl. `cell width equals a plain UI.Grid's column at the same width, gap and count` |
| M4 | the anchor keys on the LINE instead of the ITEM (reflow-blind) | **2 cases**: both scroll-stability cases, incl. `when the COLUMN COUNT changes, the item at the top of the viewport stays at the top` |
| M5 | the focus group is emitted as `vertical` (reachable, wrong SHAPE) | **2 cases**, incl. `VirtualGrid keyboard: Left/Right steps cell-by-cell ACROSS a line` |
| M6 | the up/down intercept is not contributed at all | **5 cases**, incl. `VirtualGrid keyboard: Down moves a whole LINE, not one cell` |
| M7 | the cell's focusable hit is withheld (the focus black hole) | **9 cases** across both files |
| M11 | the per-line extent function is never validated at construction | **1 case**: `a per-line itemExtent that returns garbage fails at CONSTRUCTION, naming the line` |
| M12 | `columns` accepts a fraction | **1 case**: `columns must be a positive INTEGER — 0, a fraction and a negative are all refused` |

## Round 1 — the three that did NOT bite, and what each one meant

This is the part worth reading. Three mutations changed the module and reddened
nothing, and **each one meant something different**.

### M9 — a non-mutation. Rewritten, then it bit.

Changing `break` to `continue` at the short last line reddened nothing because it
is not a behaviour change: every remaining lane in that line is also `nil`, so
both spellings insert nothing. The mutation was wrong, not the check. Rewritten as
**M9′ — the short last line is PADDED with the last item** (`items[math.min(index, #items)]`),
which is a real defect, it reddened **2 cases**: `the LAST line is short, and the
index still spans exactly the lines that exist` and `a SHORT last line keeps its
column width and stays left-aligned`.

### M10 — a real hole in the checks. Closed, then it bit.

Pinning the cell's height to a **literal 40** instead of its line's extent passed
everything, because every layout case in the file used a 40px line. A cell that
ignored its line's extent entirely was invisible. Closed by adding
**`each mounted cell is exactly its own LINE's extent tall, and the lines stack at
the index's offsets`** — ragged extents `{40, 249, 40, 120}`, asserting both the
heights and the stacked offsets. Re-run as M10′: **1 case** reddened, the new one.

### M8 — dead code in the module, not a hole in the checks.

Neutering the keep-visible inside the `focusMoved` contribution reddened nothing.
The first response was to assume a missing check and add one — `VirtualGrid
keyboard: Right off the END of a line scrolls the next line into view`, the
group's own axis, which never reaches the intercept. **It still did not bite.**

So the module was instrumented directly instead of reasoned about. With
`focusMoved`'s scroll removed, a 60-press Right walk produced a
**byte-identical** scroll trace (`scrollTop` 0 → 40 → 120 → 240 at presses
10/40/50/60). Withholding the whole `focusMoved` seam from the bundle: **33 passed,
identical trace.** The presenter's own keep-visible already reacts to a focus move
it observes; the control's copy was pure duplication.

The seam was **deleted** (ENGINEERING.md: delete dead code the moment it is dead)
and the reason recorded in the module header, because the neighbouring seam is
*not* dead and the difference is the mechanism:

| | withheld | result |
|---|---|---|
| `focusMoved` (the whole contribution field) | ✅ | **33 passed** — no path changed |
| the keep-visible inside `navigateIntercept` | ✅ | **1 failed**: `VirtualGrid keyboard: focus past the window edge scrolls the line into view` |
| both | ✅ | **1 failed**, the same one |

`navigateIntercept` moves focus **programmatically**, so the presenter never sees
the move and nothing else brings the ±`lanes` target into view. `focusMoved`
mirrors a move the presenter already handled. The new Right-off-the-end case was
kept anyway: it covers the group's own axis, which no other case did.

**Final state: 12 of 12 mutations bite** (M1–M7, M8-as-a-deletion, M9′, M10′, M11, M12).

---

## Round 2 — the consumer side, from inside Rascal Rally

The game's own contract test was mutation-proved independently, from the game
repo, against the framework source it consumes: the window memo was made eager
(`{ first = 1, last = count }`) and **both** game-side laziness cases reddened —

```
✗ expected window=1..500 to be window=1..6
✗ expected 2000 to be 40
```

— then the file was restored and its `shasum` confirmed byte-identical. That
matters because it proves the game's copy is not a stale snapshot: a future
LuauUI change that made the grid eager reddens in `RascalRally`'s suite too, not
only in the framework's.
