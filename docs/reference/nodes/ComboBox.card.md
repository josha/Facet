# ComboBox.card

Choose a value or accept custom text.

Inside an app mount, set `local UI = app.UI`.

```luau
local value = Facet.Compose.cell("")
local text = Facet.Compose.cell("")
UI.ComboBox "Name" { value = value, text = text, options = {}, acceptCustom = function(input: string): (boolean, string?) return true, input end }
```

Key options: `value`, `text`, `options`, `acceptCustom`.

Keep text and the committed value in separate cells.

Related controls: [Controls](Controls.md).

Open:

- [ComboBox.reference](ComboBox.reference.md)
