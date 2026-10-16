# NumberInput.card

Edit a number.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.NumberInput "NumberInput" { value = Facet.Compose.cell("1"), numericValue = Facet.Compose.cell(1) }
```

Key options: `value`, `min`, `max`, `step`.

The game validates the value on the server.

Related controls: [Controls](Controls.md).

Open:

- [NumberInput.reference](NumberInput.reference.md)
