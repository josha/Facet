# TextInput.card

<!-- aliases: TextInput | UI.TextInput | TextField | TextField.card | text field | search field -->

Edit text with TextInput.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.TextInput "TextInput" { value = Facet.Compose.cell(""), placeholder = "Filter" }
```

Key options: `value`, `placeholder`, `onCommit`, `presentation`.

`presentation = "search"` adds the search glyph and an in-field Clear (×)
that empties only the text. Do not add a separate Clear button. Offer Clear
search or Reset filters in the no-matches state instead.

Use a writable cell or provide onChange.

Related controls: [Controls](Controls.md).

Open:

- [TextInput.reference](TextInput.reference.md)
