# Table.card

Show rows with columns.

Inside an app mount, set `local UI = app.UI`.

```luau
local columns: { Facet.TableColumn<string, string> } = { { id = "name", label = "Name", value = function(item) return item end } }
UI.Table "Items" { from = { "Kart" }, key = function(item) return item end, columns = columns }
```

Key options: `from`, `key`, `columns`, `sort`, `onCellChange`.

Keep durable row and edit state in the model.

Related controls: [Controls](Controls.md).

Open:

- [Table.reference](Table.reference.md)
