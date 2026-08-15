# The lazy grid — what shipped, what it cost, and what is left

**Built 2026-08-15.** Closes the `LazyVGrid` half of
[`swiftui-parity.md`](../reference/swiftui-parity.md) §4's
`LazyHGrid`/`LazyVGrid` row. The full argument lives in that document's **§4.2.2**
and is not repeated here; this file carries the decision, the trades and the
remainder.

---

## The gap, and what it actually asked

The parity row said it plainly: *"Neither grid mode is lazy: every cell is
measured and arranged … LuauUI ships only the eager half."* And its last clause
was the real brief — **the windowing substrate a lazy grid would need already
existed, and only the two collection controls consumed it.**

So the question was never *how do you window a grid*. It was **whether a grid
could become a third consumer of the one index without becoming a second
implementation of it** — and, once the band had to be laid out in columns,
whether it could avoid becoming a second implementation of the *column*
arithmetic as well. Two "do not fork this" constraints, not one.

## The decision

**Ship `newVirtualGrid` as a control, changing nothing underneath it.**
`src/layout/solver.luau` was not touched; neither was `src/virtual_extents.luau`,
`src/controls/virtual_list.luau`, `src/blueprint.luau` or the schema. The
framework gained one new module and one new export.

### The extent index served AS-IS — a change of UNIT, not a generalisation

This was the question the mission was told to answer explicitly, and the answer
is **as-is**.

`virtual_extents` is a prefix sum over a list of numbers with a gap between them.
The word "item" appears throughout its prose and **nowhere in its interface** —
`count`, `content`, `offsetOf`, `extentOf`, `window`, `slotAt`, `boundaryOffset`
are all about *entries*. A grid decides one entry means one **line of cells**:

```
count   = ceil(#items / columns)
extents = the per-line extents
gap     = rowGap
```

and every query answers in line units with no edit. The cell↔line mapping that
sits on top is `line = floor((index - 1) / columns) + 1` — an **index transform**,
not windowing: no offsets, no search, no extents, exact for the same reason
integer division is.

Two facts make this a fit rather than a coincidence:

- **The interface is UNDER-used, never widened.** `slotAt` and `boundaryOffset`
  are the index's *insertion* vocabulary — which slot does a drop land in, where
  is the hairline drawn — and a grid asks neither, because it has no reorder. A
  primitive a new consumer uses less of than it offers is a primitive that was
  general enough already.
- **The recorded uniform-vs-variable divergence arrives unchanged.** At a 200px
  viewport over 40px lines the uniform rule names 7 lines and the variable rule
  names 8, because the variable rule asks the exact containing-slot question and
  is a strict superset. That is
  [`variable-item-extents.md`](variable-item-extents.md)'s documented trade
  showing up in a second consumer, in the same direction, and
  `tests/virtual_grid.spec.luau` pins the *superset relationship* rather than
  only the number.

### The mounted band IS a `UI.Grid` — no second column arithmetic

The windowed lines are a contiguous run of items that always starts on a line
boundary, which is exactly what a row-major flow grid wraps. So the control mounts
**one** `UI.Grid { columns }`, absolutely positioned at `offsetOf(firstLine)`
inside a full-extent canvas. `floor((innerW − gap × (columns − 1)) / columns)` is
therefore the flow grid's own formula *executing*, and the short-last-line rule
comes free because the flow grid derives its column from the OFFER and the lane
count, never from how many cells turned up.

## What it cost

| | |
|---|---|
| **A cell's state dies with the window** | Stated, not hidden — the same honesty `newTable { virtualized = true }` owes. Keep anything that must survive a scroll in the consumer's model |
| **`axis = "x"` (`LazyHGrid`) is REFUSED, not built** | `UI.Grid` wraps row-major only. There is no column-major mode to give a horizontal grid its lanes, and hand-rolling one is precisely the second column arithmetic the whole design avoids. A refusal with a stated reason, not an absence |
| **`minColumnWidth` is refused, with a route** | It needs the cross-axis size in px — a second measured seam beside `viewportExtent`. `adaptive.columnsFor` is the flow grid's own arithmetic and is already exported, so `columns` binds to a memo over it |
| **Anchoring is unconditional here** | `newVirtualList` scopes anchoring to variable extents, to avoid moving a shipped list's behaviour. This control has no shipped behaviour to preserve, and the reflow case needs the anchor on the UNIFORM path, so the exception has no reason to exist |
| **A full-cell focusable hit per mounted cell** | One extra instance per *mounted* cell (tens, not thousands). It is not decoration: `focus_map.autoGroups` does not descend into a contribution, so a focusable the control never NAMES is unreachable by Tab and by the D-pad alike |
| **The vertical focus axis rides `navigateIntercept`** | A `NavigationGroup` axis is `"vertical"` or `"horizontal"`; a grid's ring is two-dimensional. Down = ±`columns` therefore arrives through an existing seam rather than by widening `focus_graph.luau` from inside a control. Widening the focus graph is a real option, and a better one — it is deliberately **not** taken from here (`ENGINEERING.md`: flag refactors, don't smuggle them) |

## The two defects the work found in itself

Both were found by **mutation testing**, not by reading — the full ledger is
[`artifacts/lazy-grid/mutation-evidence.md`](../../artifacts/lazy-grid/mutation-evidence.md).

1. **The focus black hole.** The first draft attached an input contribution purely
   to learn its own mounted path and returned no focus groups. Because a
   contribution owns its subtree's focus, that would have made every focusable in
   every cell unreachable by keyboard and gamepad — a lazy grid nobody could
   operate without a mouse. The four-input gate is what surfaced it.
2. **A dead contribution seam.** The control was written with a `focusMoved`
   mirroring `newVirtualList`'s, and withholding it changed the scroll behaviour on
   *no path at all* (verified with a 60-press walk producing a byte-identical
   scroll trace) — the presenter's own keep-visible already handles a move it
   observes. Deleted. The neighbouring keep-visible inside `navigateIntercept` is
   **not** dead, because that seam moves focus programmatically and the presenter
   never sees it; removing that one reddens a named case.

The showcase found two more, in the fixture rather than the control: a themed
`surface` on a cell brings its package's chrome `contentInsets` (40px a side under
`fantasy-ornate`, which collapses a 70px cell's content box to zero and files 790
findings), and a 640×320 landscape phone at `preferredTextOffset = 14` has no room
for a page title above a scroll host that cannot delegate its scrolling. Both were
fixed in the fixture — **no waiver was added**, which is the direct lesson of
`variable_extents`' 418 findings.

## What is left

- **`LazyHGrid`.** The other half. It needs either a column-major mode in the flow
  grid or an explicit cross-axis lane pitch — a solver change, and its own
  mission.
- **A grid axis in the focus graph.** Down-as-±`columns` works and is proved on
  both keyboard and gamepad, but it lives in a control rather than in the focus
  system. A real two-dimensional `NavigationGroup` axis would let the grid delete
  its intercept and would serve any future 2-D surface. Flagged, scoped, not
  taken.
- **A perf-lab arm on the real engine.** The headless numbers
  ([`artifacts/lazy-grid/perf.md`](../../artifacts/lazy-grid/perf.md)) are a
  regression signal only. The engine-tier question they cannot answer: does a band
  that is ONE `UI.Grid` re-measured on each window slide cost more or less than
  `newVirtualList`'s N absolutely-positioned rows? Headlessly the two sit inside
  the control band, which is exactly why it needs Studio.
- **The reflow clamp, recorded rather than fixed.** Narrowing the lane count
  multiplies the canvas, and the anchor's scroll write goes through the render
  controller, which clamps against the *previous* solve's canvas. An item in the
  last screenful of the old canvas therefore cannot be restored on the frame the
  lanes change; everywhere else, and in the widening direction at any offset, the
  item is held exactly. The showcase's `narrow`/`widen` steps report both anchor
  keys so a drive shows which happened instead of asserting one.
- **Selection and reorder**, if a consumer ever wants them. `newVirtualList` has
  single selection and `newTable` has multi/range; a grid has neither, on purpose,
  until something asks.
