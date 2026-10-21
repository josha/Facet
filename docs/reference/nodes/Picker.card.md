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

The default picker fills its parent width. Put form fields in a bounded
VStack, or allocate each field's width when sharing a row. For secondary
filters, `style = "menu"` keeps attention and room for the collection;
segmented options suit a few primary peer choices.

Related controls: [Controls](Controls.md).

Open:

- [Picker.reference](Picker.reference.md)
