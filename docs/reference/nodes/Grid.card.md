# Grid.card

Arrange a small collection in columns.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Grid "Grid" { columns = 2, UI.Text { text = "Item" } }
```

Key options: `columns`, `gap`.

Use VirtualGrid for an interactive collection.

Related controls: [Controls](Controls.md).

Open:

- [Grid.reference](Grid.reference.md)
