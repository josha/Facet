# Picker.card

Choose one value from fixed options.

Inside an app mount, set `local UI = app.UI`.

```luau
local selected = Facet.Compose.cell("solo")
local options: { Facet.PickerOption<string> } = { { value = "solo", label = "Solo" } }
UI.Picker "Mode" { selected = selected, options = options, style = "segmented" }
```

Key options: `selected`, `options`, `style`, `query`.

A segmented picker cannot take query. Its strip never wraps: when it does not
fit, it scrolls to the chosen segment, and `ViewThatFits { segmented, menu }`
shows the menu.

The default picker fills its parent width. Put form fields in a bounded
VStack, or allocate each field's width when sharing a row. Segmented options
suit a few primary peer choices. In a filter bar, put unlabelled menu pickers
whose options name themselves ("All classes") in an `HStack { wrap = true }`,
or set `valueAlignment = "start"`.

Related controls: [Controls](Controls.md).

Open:

- [Picker.reference](Picker.reference.md)
