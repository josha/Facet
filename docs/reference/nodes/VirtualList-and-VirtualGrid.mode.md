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

For a short collection inside a content-sized Sheet, bind its viewport height
to its published `CanvasSize`. Do not calculate rows from the outer width:
the native scrollbar inset and the grid's paint gutters reduce the space for
columns. `mode = "all"` changes row lifetime, not viewport size.

In one Compose owner, use the app's `UI`, `runtime`, `Compose` and `env`.
Supply `items` and `renderItem`. Keep the scrollbar inset stable:

```luau
local height = Compose.cell(1)
local grid = UI.VirtualGrid "Items" {
  from = items, key = "id", minColumnWidth = env.scaled(220),
  itemSize = env.scaled(132), gap = env.scaled(16), render = renderItem,
  VerticalScrollBarInset = Enum.ScrollBarInset.Always,
  Size = function(use: Facet.Use): UDim2
    return UDim2.new(1, 0, 0, use(height))
  end,
}
local canvas = runtime.observe(grid, "CanvasSize")
Compose.watch(function(use: Facet.Use)
  local size = use(canvas)
  assert(typeof(size) == "UDim2")
  height:set(size.Y.Offset)
end)
return grid
```

`CanvasSize` includes paint gutters. Compose owns the observation and watch.
For large collections, keep a bounded viewport and let the collection scroll.
`AutomaticCanvasSize` changes canvas size, not viewport size; native child
measurement cannot measure unmounted rows.
