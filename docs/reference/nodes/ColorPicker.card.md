# ColorPicker.card

Choose a color.

Inside an app mount, set `local UI = app.UI`.

```luau
local paint = Facet.Compose.cell(Color3.fromRGB(230, 57, 70))
UI.ColorPicker "Paint" { label = "Paint", value = function(use: Facet.Use) return use(paint) end, onChange = function(value) if value then paint:set(value) end end }
```

Key options: `value`, `onChange`, `onCommit`, `modes`.

Use Picker for a few named colors.

Related controls: [Controls](Controls.md).

Open:

- [ColorPicker.reference](ColorPicker.reference.md)
