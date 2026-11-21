### Pagination

<!-- aliases: Pagination | pagination -->

Pagination selects one page of numbered results. It does not fetch data.
It requires `page` (a number or a readable) and `onChange(nextPage)`.

- `pageCount` is a whole number of 0 or more, or a readable of one. `nil`
  means that the count is unknown.
- `hasNext` and `hasPrevious` (default false) set the arrows for an unknown
  count. A known `pageCount` ignores them.
- `siblingCount` and `boundaryCount` are whole numbers from 0 to 20. The
  default of each is 1.
- `showFirstLast` (default false) adds First and Last arrows. Last shows only
  for a known count.
- `form` is `numbers` (default), `arrows`, `label` or `step`. `direction` is
  `ltr` (default) or `rtl`. `controlSize` and `enabled` are optional.
- `step` moves through a short set, such as cars or characters. It shows
  Previous, a label and Next. Its root has the width of that row, so it also
  fits a hugging stack or a Region form. The label is "2 / 6".
- `label` is a function `(page, count)` that returns the text of the label,
  such as a name. `count` is `nil` for an unknown count. The function must
  give the same text for the same page. The label keeps the width of the
  widest text of the first 64 pages, so the arrows do not move. A value that
  is not a string shows the page number, with a diagnostic line.
- `controls` is an optional table. The control sets `controls.diagnostics()`,
  which returns the refusal lines.

The caller owns `page`. A press proposes one page through `onChange`. The row
changes only when your value changes. Thus a refused proposal changes nothing.
A page outside the range shows clamped, with a warning and a diagnostic line.
The control never writes it back. A late value that is not legal keeps the
last legal value. A malformed value at construction causes an error.

The numbers form shows the boundary pages, the current page and
`siblingCount` pages on each side. An ellipsis replaces a gap of two or more
pages. The work is bounded by the two counts, not by `pageCount`. The control
measures the width of its root (`AbsoluteSize.X`). When the row does not fit,
the farthest boundary page goes first, then the farthest neighbour (the higher
page on a tie). When only the current page and the arrows do not fit, the row
shows "Page n of m". An unknown count always shows "Page n". Zero pages shows
"No pages" with no stops. One page has no enabled arrow.

Each page is a compact Button in a slot that is at least the target size
(`targetSizes.minimum`) wide. The arrows are icon Buttons of the same size.
The label keeps the width of the widest label that the count can make, so the
arrows do not move when the page gains a digit. Page nodes are keyed by page
number. When the selected page leaves the window, or a selected arrow becomes
disabled at an edge, the selection moves to the current page. When the row has
no live page or arrow, for example when the count drops to zero, the selection
moves to the nearest selectable object outside the row. `rtl` reverses
the row once. Except in the `step` form, the root is a Frame that fills its width.
`AutomaticSize` on X causes an error, because the window narrows to the
width that it gets.

The root has the attributes `FacetCurrent`, `FacetCount`, `FacetForm` and
`FacetDirection`. Use Pagination for results that you load one page at a time.
Use VirtualList for one long list and PageView to swipe between screens.
