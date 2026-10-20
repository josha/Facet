# VirtualGrid.card

Virtual tiles.

Inside an app mount, set `local UI = app.UI`. Use a bounded stack:

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

`measure = true` replaces `itemSize` estimates with native heights for
wrapping or changing text Cards. Each row uses its tallest tile. Otherwise
estimates set spacing.

For explicit positions and multi-cell items, use [SpatialGrid](SpatialGrid.card.md).
[Options](VirtualList-and-VirtualGrid.md) or
[content sizing](VirtualList-and-VirtualGrid.sizing.md).
