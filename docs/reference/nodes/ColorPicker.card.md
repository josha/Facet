# ColorPicker.card

Choose a visible color. For a fixed palette, start with labeled swatches.
Inside an app mount, set `local UI = app.UI`.

```luau
local paint = Facet.Compose.cell(Color3.fromRGB(230, 57, 70))
local palette: { Facet.ColorSwatch } = {
    { color = Color3.fromRGB(230, 57, 70), label = "Red" },
    { color = Color3.fromRGB(40, 90, 220), label = "Blue" },
}
UI.ColorPicker "Paint" {
    label = "Paint", value = paint, style = "inline", modes = { "swatches" },
    swatches = palette,
}
```

Named swatches show color and label together; a check marks selection.
The model owns the draft. Bind a [Stage](Stage.card.md) scene to the same
value. Add spectrum or sliders for free color editing. Use Picker when the
choice is a text category rather than a visible color.

Open:

- [ColorPicker.reference](ColorPicker.reference.md)
- [Preview and color](Tasks.appearance.md)
