# Picker.card

Choose one value from fixed options.

Inside an app mount, set `local UI = app.UI`.

```luau
local selected = Facet.Compose.cell("solo")
UI.Picker "Mode" { selected = selected, options = { { value = "solo", label = "Solo" } }, style = "segmented" }
```

Key options: `selected`, `options`, `style`, `query`.

A segmented picker cannot take query.

Related controls: [Controls](Controls.md).

Open:

- [Picker.reference](Picker.reference.md)
