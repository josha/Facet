# VirtualGrid.card

Show a virtual tile collection.

Inside an app mount, set `local UI = app.UI`. A bounded VStack can hold a header
and a grid:

```luau
local spec: Facet.KeyedCollectionSpec<string, string> = {
    UI.fill(), from = { "Kart" }, key = function(item) return item end,
    minColumnWidth = 180, itemSize = 64,
    render = function(current) return UI.Text { text = current } end,
}
local grid: ScrollingFrame = UI.VirtualGrid "Tiles" (spec)
UI.VStack "Browser" { height = "fill", gap = "s",
    UI.Text { text = "Parts" },
    grid,
}
```

Put [fill](fill.md) in the grid spec, not `render`, to use the height left after
headers and gaps. Without flex, the grid uses the full parent height.

`itemSize` estimates tile height. Set `measure = true` for wrapping or changing
text Cards. Native measurements replace estimates; a row uses its tallest tile.
Otherwise spacing stays at the estimate.

Open [options](VirtualList-and-VirtualGrid.md) or
[content sizing](VirtualList-and-VirtualGrid.sizing.md).
