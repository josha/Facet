# Picker.card

Choose one value from fixed options.

Inside an app mount, set `local UI = app.UI`.

```luau
local selected = Facet.Compose.cell("solo")
local options: { Facet.PickerOption<string> } = { { value = "solo", label = "Solo" } }
UI.Picker "Mode" { selected = selected, options = options, style = "segmented" }
```

Key options: `selected`, `options`, `style`, `query`.

A segmented picker cannot take query.

Related controls: [Controls](Controls.md).

Open:

- [Picker.reference](Picker.reference.md)
