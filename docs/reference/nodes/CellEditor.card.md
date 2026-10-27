# CellEditor.card

Edit a value in a collection cell.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.CellEditor "Name" { editor = "text", value = "Kart", onChange = function(value) print(value) end }
```

Key options: `editor`, `value`, `onChange`, `draft`, `validate`.

`onChange` proposes a value; check its type before reading fields. Keep a draft
per record and field outside recycled rows. Read [CellEditor.draft](CellEditor.draft.md)
for rejection, conflicts and cancellation.

Related controls: [Controls](Controls.md).

Open:

- [CellEditor.reference](CellEditor.reference.md)
