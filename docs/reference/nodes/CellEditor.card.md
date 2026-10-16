# CellEditor.card

Edit a value in a collection cell.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.CellEditor "Name" { editor = "text", value = "Kart", onChange = function(value) print(value) end }
```

Key options: `editor`, `value`, `onChange`, `draft`, `validate`.

Check an unknown value before reading its fields.

Related controls: [Controls](Controls.md).

Open:

- [CellEditor.reference](CellEditor.reference.md)
