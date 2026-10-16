# TextInput.card

Edit text.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.TextInput "TextInput" { value = Facet.Compose.cell(""), placeholder = "Filter" }
```

Key options: `value`, `placeholder`, `onCommit`, `clearButton`.

Use a writable cell or provide onChange.

Related controls: [Controls](Controls.md).

Open:

- [TextInput.reference](TextInput.reference.md)
