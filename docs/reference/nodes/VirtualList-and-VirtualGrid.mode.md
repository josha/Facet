# VirtualList-and-VirtualGrid.mode

VirtualList-and-VirtualGrid.mode option values and behavior.

| Option | Default and meaning |
|---|---|
| `mode` | `windowed`; `all` deliberately mounts the entire collection. |
| `direction` | `vertical`; `horizontal` changes the scrolling axis. |
| `itemSize` | `40`, the estimated main-axis extent. On a horizontal list, `"cards"` sizes the cards from the space the rail gets. A compact touch rail (under 600 px) shows one card with a peek of the next and snaps to cards. Wider rails show as many whole cards of at least 200 px as fit. `cards = { perView?, minWidth?, peek? }` overrides the count, the floor or the peek. `cards` is refused without `"cards"`. |
| `gap`, `crossGap` | `0`; the cross gap defaults to the gap. A VirtualGrid keeps half of each gap (rounded up) at its outer edges, as a `UIPadding` on its `Items` frame and in its canvas extent. Thus content that paints past its cell, such as a lifted Card, is not cut by the scroll clip. |
| `contentOverflow` | `visible` by default. `clip` uses the native cell content clip to keep oversized paint and pointer targets inside their cell. |
| `columns` | The grid column count, default `1`; can be reactive. |
| `minColumnWidth` | VirtualGrid only: a positive minimum tile width. Computes columns from the available cross-axis space and gaps. Do not combine it with `columns`. |
| `hug` | `false`. `true` with `mode = "all"` sizes the collection to its rows on its main axis, so it lays out as content in a hugging surface and does not scroll. A `minColumnWidth` grid with `hug` makes no more columns than items. See [sizing](VirtualList-and-VirtualGrid.sizing.md). |
| `rowActions` | The same action factory and permission rules as Table. |
| `overscan` | `2`. |
| `measure` | Set `true` to observe the rendered native `AbsoluteSize`, or `false` to keep fixed estimates. Without it, an automatic list row with a native UIListLayout, text or button can grow past `itemSize`. It never shrinks below the estimate. |
| `measured` | An optional readable map from key to extent; overrides observed measurements. |
| `follow` | `none` or `end`, or a readable of one, with an optional `followThreshold`. |
| `status` | An optional writable Compose collection status cell. A cell that holds `nil` is filled with the empty status record. |
| `controls` | An optional table that the control fills with the Compose `indexOfKey`, `placementOf` and `offsetOf`. |
| `maxRetained` | The pool keeps at most `32` row hosts by default. |

Rows prepare inside a native CanvasGroup. A new row stays transparent until
its visible text has positive native bounds and its layout is stable. A filter
or data replacement keeps removed painted rows until the replacement rows
in the viewport are ready. Equal keys retain their native instances. An empty
result removes the old rows. Offscreen overscan does not delay visible rows.
Use `ZIndexBehavior = Enum.ZIndexBehavior.Sibling` on the ScreenGui or SurfaceGui.

For a short grid inside a content-sized Sheet, use
[VirtualList-and-VirtualGrid.sizing](VirtualList-and-VirtualGrid.sizing.md).
