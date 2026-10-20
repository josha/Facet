# VirtualGrid.card

Show a virtual tile collection.

Inside an app mount, set `local UI = app.UI`.

```luau
local spec: Facet.KeyedCollectionSpec<string, string> = { from = { "Kart" }, key = function(item) return item end, minColumnWidth = 180, itemSize = 64, render = function(current) return UI.Text { text = current } end }
UI.VirtualGrid "Tiles" (spec)
```

Key options: `from`, `key`, `render`, `minColumnWidth`, `itemSize`, `measure`.

`itemSize` is the initial tile height. Set `measure = true` for text Cards
whose heights change with wrapping or state. Native measurements replace the
estimate; each grid row uses its tallest tile. Without measurement, the grid
keeps the estimated spacing even when a tile is shorter or taller.

Related controls: [Controls](Controls.md).

Open:

- [VirtualList-and-VirtualGrid](VirtualList-and-VirtualGrid.md)
- [VirtualList-and-VirtualGrid.sizing](VirtualList-and-VirtualGrid.sizing.md)
