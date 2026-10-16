# VirtualList.card

Show a virtual row collection.

Inside an app mount, set `local UI = app.UI`.

```luau
local spec: Facet.KeyedCollectionSpec<string, string> = { from = { "Kart" }, key = function(item) return item end, itemSize = 44, render = function(current) return UI.Text { text = current } end }
UI.VirtualList "Rows" (spec)
```

Key options: `from`, `key`, `render`, `itemSize`, `measure`.

Give the viewport a bounded parent.

Related controls: [Controls](Controls.md).

Open:

- [VirtualList-and-VirtualGrid](VirtualList-and-VirtualGrid.md)
