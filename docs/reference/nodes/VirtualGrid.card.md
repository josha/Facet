# VirtualGrid.card

Virtual tiles.

Inside an app mount, set `local UI = app.UI`. Use a bounded stack:

```luau
local spec: Facet.KeyedCollectionSpec<string, string> = {
    UI.fill(), from = { "Kart" }, key = function(item) return item end,
    minColumnWidth = 180, minColumns = 2, itemSize = 64,
    render = function(current) return UI.Text { text = current } end,
}
local grid: ScrollingFrame = UI.VirtualGrid "Tiles" (spec)
UI.VStack "Browser" { height = "fill", gap = "s",
    UI.Text { text = "Parts" },
    grid,
}
```

With `minColumns = 2`, a grid of objects that players compare keeps at least
two columns on a phone.

Put [fill](fill.md) in the grid spec, not `render`, to use the height left after
headers and gaps.

`measure = true` sizes each row to its tallest native tile, for wrapping or
changing text Cards.

For explicit positions and multi-cell items, use [SpatialGrid](SpatialGrid.card.md).
[Options](VirtualList-and-VirtualGrid.md) or
[content sizing](VirtualList-and-VirtualGrid.sizing.md).
