# VirtualGrid.card

Show a virtual tile collection.

Inside an app mount, set `local UI = app.UI`.

```luau
local spec: Facet.KeyedCollectionSpec<string, string> = { from = { "Kart" }, key = function(item) return item end, minColumnWidth = 180, itemSize = 64, render = function(current) return UI.Text { text = current } end }
UI.VirtualGrid "Tiles" (spec)
```

Key options: `from`, `key`, `render`, `minColumnWidth`, `itemSize`.

itemSize is the estimated tile height.

Related controls: [Controls](Controls.md).

Open:

- [VirtualList-and-VirtualGrid](VirtualList-and-VirtualGrid.md)
