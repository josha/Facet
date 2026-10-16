# Text.Facet.richText.escape

To put player names or server strings into rich text, escape them with
`Facet.richText.escape(s)`. It replaces `&`, `<`, `>`, `"` and `'` with their
RichText entities. It does not filter the text; the game still uses the
platform filtering rules.

```luau
local name = "Ann <3"
UI.Text { rich = true, text = "<b>" .. Facet.richText.escape(name) .. "</b> joined" }
```
