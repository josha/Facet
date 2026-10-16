# RowActions.card

Expose actions beside a row.

Inside an app mount, set `local UI = app.UI`.

```luau
local actions: { Facet.RowAction } = { { id = "remove", label = "Remove", onActivate = function() print("Remove") end } }
UI.RowActions "Item" { content = function() return UI.Text { text = "Kart" } end, trailing = actions }
```

Key options: `content`, `leading`, `trailing`, `editing`.

Keep an explicit action reachable without a swipe.

Related controls: [Controls](Controls.md).

Open:

- [RowActions.reference](RowActions.reference.md)
