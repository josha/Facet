# The unified collection — the shape decision, what it cost, and what is left

**Asked by the game director, 2026-08-14:** *"should we have a container that
unifies virtualization/reordering/selection? we're doing variable item extents
now, so maybe we add these?"*

**Decided and Stage 1 built the same day.** `docs/reference/swiftui-parity.md`
§13 carried **"No container unifying virtualization + reorder + selection"** as a
durable gap, and §4.2 recorded `newTable` virtualization as blocked behind
variable item extents *because* Table ships `rowHeight(item)`. Stage 1 of that
work shipped the running-offset index (`src/virtual_extents.luau`) and its own
report named this consumer as **"now unblocked, its stated blocker was this
substrate."**

---

## What the gap actually was, measured rather than quoted

§13's sentence is *literally* stale, and finding that out changed the decision.
`newVirtualList` already virtualizes, reorders and selects. The capability
matrix, read off both controls:

| | virtualization | reorder | selection | multi/range | columns + header | row actions | reorder **and** row actions |
|---|---|---|---|---|---|---|---|
| `newVirtualList` | ✅ | ✅ (public drag contract) | single only | ❌ | ❌ | ✅ (hosted) | ❌ — refused at construction, v1 |
| `newTable` | **❌** | ✅ | ✅ | ✅ | ✅ | ✅ (wrapped) | ✅ |

So the real gap is not "no container does all three". It is that **the rich
container cannot window**, and it is the only hole in that row. Everything a
player-facing list of any size wants — columns, a header, shift-range and
cmd-toggle selection, reorder by pointer, handle, gamepad grab and verb — lived
on the one control that mounted every row.

## The three honest options, and why two lose

### 3. A new third container — rejected

Neither existing control could be retired behind it: Table owns columns, the
header, edit mode and multi-selection; VirtualList owns `axis = "x"` and hosted
row actions. A third container therefore **adds a row to the capability matrix
instead of removing the hole in it**, and every future feature is then built
two-and-a-bit times. Recorded because it was the shape the question implies, not
because it was close.

### 2. One collection substrate both controls are thin presentations over — rejected, with the specific reasons

This is what §13 literally describes, and it is the largest. It loses on five
measured conflicts, not on size:

1. **Height authority is INVERTED between the two.** VirtualList's contract is
   "the consumer PREDICTS the extent and the solver checks the promise"
   (`virtualSlot` / `slotDeclaration`, and the lying-`itemExtent` guard that
   exists because consumers get it wrong). Table's is the reverse: `rowHeightOf`
   DERIVES the row from the theme metrics, the typography scale, the
   accessibility text offset and the input paradigm, and an authored `rowHeight`
   is FLOORED by one line of its own cell text. A shared substrate must pick one,
   and picking either breaks the other's shipped contract.
2. **Row-actions hosting is opposite BY DESIGN, and each control's other
   capabilities depend on which side it took.** VirtualList *hosts* (one shared
   dispatcher, lazy per-row engines born at a gesture's axis lock, one tray
   overlay per list) and therefore refuses `reorderable + rowActions`. Table
   *wraps* each actionable row in its own composite and therefore supports both
   at once. Unifying deletes a shipped capability from one side or the other.
3. **Selection cardinality differs in kind**, not degree: a single `selectedKey`
   against a key SET plus a range anchor, `rangeKeys`, and a grab key folded into
   the same per-row memo.
4. **The focus contribution shape differs.** VirtualList contributes ONE vertical
   group for the whole list; Table contributes a `headers` group, a `toolbar`
   group and one HORIZONTAL group per row (its cells are focus stops).
5. **`ENGINEERING.md` forbids smuggling it.** "Executing a broad refactor is its
   own approved mission, never folded silently into feature work."

And the argument that actually settles it: **the part of these two controls that
CAN be shared already is.** `src/virtual_extents.luau` (all row geometry),
`src/row_capability.luau` (the three per-row opt-outs), and
`solverLib.keepVisibleOffset` (the minimum-distance rule) are one implementation
with two callers each. What is left after those is not shared arithmetic wearing
two names — it is two different products.

### 1. `Table` gains virtualization on the existing index — **CHOSEN**

It closes the only hole in the matrix, it is the thing round 3 named as blocked
and the variable-extents report named as unblocked, and it adds **one public
prop**.

---

## What Stage 1 shipped

`newTable{ virtualized = true }` — construction-only.

| piece | where |
|---|---|
| Table's three hand-rolled O(N) row-geometry loops (a key→cumulative-top memo, a `contentHeight()` that re-summed the same numbers, an `insertSlotAt` that walked them a third time with its own midpoint rule) replaced by ONE `virtual_extents.variable` index — for the **flowing** table as well as the windowed one | `src/controls/table.luau` |
| the window: only the rows the viewport touches, plus `OVERSCAN = 2` on each side, absolutely positioned on a full-extent `Canvas` | same |
| the viewport measured through `syncGeometry`, seeded from the SCREEN height so frame one over-mounts rather than under-mounts | same |
| scroll anchoring on the item under the viewport's leading edge, plus a clamp correction when the content shrinks under the engine | same |
| `api.revealRow(key)` — the verb virtualization makes necessary, since the row a screen wants to show may have no path at all | same |
| two construction refusals, each naming why: `scrolls = false` and `rowActions` | same |
| `dump().windowRows` / `.contentExtent`, present only under `virtualized` so every recorded dump is byte-identical | same |
| the control's spec (21 cases) | `tests/table_virtualized.spec.luau` |
| the showcase: 2 000 rows, a status line reporting how many are in the tree, three verbs that each act on row 1500 | `examples/gallery/scenarios/table_virtualized.luau` |
| the consumer proof, both halves (a differential oracle on the FLOWING racer list, and a use-proof under `virtualized`) | `games/RascalRally/code/tests/luauui_racer_list.spec.luau` |
| mutation evidence (25 mutations, 23 killed) and the perf numbers | `artifacts/unified-collection/` |

**§13's row is closed by this**: `newTable{ virtualized = true }` unifies
virtualization, reorder and selection (single, multi, range and toggle), with
columns and a header.

## What was traded — plainly

- **Row actions are refused with `virtualized`, in v1.** Table WRAPS each
  actionable row in its own `row_actions` composite, and that composite's
  lifecycle is pruned by the DATA, never by the window: a row scrolling out would
  unmount its blueprint and strand its engine, its coordinator claim and any
  in-flight gesture. Teaching Table to HOST (VirtualList's answer) is Stage 2.
  So "the container that unifies everything" is still two controls: a swipeable
  virtualized list is `newVirtualList`.
- **A cell's own state dies when its row leaves the window.** Selection, focus,
  order and sort are model state and survive — each pinned by a case. Anything a
  CELL holds (a live `UI.TextInput` mid-edit) is the consumer's to hoist. That is
  why virtualization is opt-in rather than automatic, and it is the whole reason
  a flowing table keeps every byte of its old behaviour.
- **Scroll anchoring is virtualized-only.** Generalizing it to the flowing table
  would change what every shipped table does when a row above the viewport grows.
  Flagged, not smuggled — the same follow-up `newVirtualList` already carries for
  its uniform path.
- **The insertion-slot rule changed shape, and only at `rowGap > 0`.** The index
  splits the gutter (the midpoint of the SLOT, not of the ROW) and clamps the
  last boundary into the canvas; the old form returned `content + gap/2` for the
  trailing slot, half a gutter outside the host that clips it. At the default
  `rowGap = 0` — every table that ships today — the two rules are equal
  everywhere. Recorded so it is a decision rather than a surprise.
- **`OVERSCAN` is not public.** VirtualList exposes it; Table does not, because
  nothing has asked. One prop, not two.

## Two defects this work found, and fixed

Both were found by mutation-testing the checks, not by reading the code.

1. **The first frame mounted three rows.** Seeded at zero, the window before any
   measurement was `1 .. 1 + OVERSCAN` — three rows in a 600px body, and a
   visible pop on the next frame. Every window assertion passed anyway, because
   "≤ ceiling" is also satisfied by mounting nothing. The seed is now the screen
   height (a sound upper bound on any body inside it), so frame one over-mounts;
   the checks now carry a FLOOR as well as a ceiling.
2. **A shrinking content extent left the engine scrolled past the end.** The
   anchor's re-apply compared its target against `clampedTop` — what the
   FRAMEWORK believes — instead of `scrollTop`, where the ENGINE actually is. A
   list hard against its end whose rows then shrank looked already-correct while
   the real `CanvasPosition` was 1 200px past the last row. Measured, then fixed,
   then pinned.

## Stage 2 — what remains, in order

1. **Row actions on a virtualized Table**, by teaching Table to HOST rather than
   wrap (`docs/plans/row-actions-hosted-mode-design.md` is the design, one
   control over). This is the refusal above, and closing it is what would let the
   two controls' row-actions strategies converge — which is the only credible
   path to option 2, and it should be attempted from this end rather than by
   extracting a substrate first.
2. **Multi-selection on `newVirtualList`**, the mirror hole: it is single-only.
   Table's `api.select` modes are the reference.
3. **Generalize scroll anchoring to the flowing table** (and to VirtualList's
   uniform path — the same follow-up, already flagged there).
4. **Only then re-ask option 2.** After 1 and 2 the two controls differ by
   columns/header/edit-mode and by `axis = "x"`, which is a much smaller and much
   more honest extraction than the one refused above.
