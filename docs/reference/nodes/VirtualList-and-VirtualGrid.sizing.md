# VirtualList-and-VirtualGrid.sizing

For a short, bounded collection inside a content-sized surface, such as a set
of upgrade cards in a `hug` Sheet, use `mode = "all"` and `hug = true`. The
collection then takes the height of its rows (the width of its columns on a
horizontal list), including its paint gutters, and does not scroll. An empty
collection keeps its layout and refills.

On a VirtualGrid, give `minColumnWidth` rather than `columns`, and let the grid
own the width. The available width sets the column count. With `hug`, a grid
never makes more columns than it has items, so three cards share a wide panel
with no empty column at the end, and they wrap into rows on a narrow screen. Do
not compute item sizes or columns from the viewport or the outer width in game
code: the scrollbar inset, the paint gutters and the surface padding all
reduce the space for columns, and a size clamped to a fixed range leaves dead
space beside the items when the surface is wider than they are.

Objects that players compare need at least two columns on a portrait phone.
A phone about 400 pixels wide leaves about 340 to 370 pixels for the grid, so
keep `minColumnWidth` near 150 to 160 scaled pixels; near 180, the grid falls
to one column and shows about one object at a time.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app({})
local UI = app.UI
app.mount(function()
  local env = UI.environment()
  local spec: Facet.KeyedCollectionSpec<string, string> = {
    from = { "Amber", "Blue", "Coral" }, key = function(item) return item end,
    mode = "all", hug = true, measure = true,
    minColumnWidth = env.scaled(200), itemSize = env.scaled(132), gap = env.scaled(16),
    render = function(current) return UI.Text { text = current } end,
  }
  return UI.VirtualGrid(spec)
end)
```

`hug` requires `mode = "all"`; a windowed collection refuses it. For large or
unbounded collections, keep `mode = "windowed"`, give the viewport a bounded
height and let the collection scroll. Do not size it to all items.
`AutomaticCanvasSize` changes canvas size, not viewport size; native child
measurement cannot measure unmounted rows.
