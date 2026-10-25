# Text.card

Show text.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Text "Text" { text = "Ready" }
```

Key options: `text`, `textRole`, `wrap`, `truncate`, `lines`.

For a paragraph, use `wrap = true`. Wrapped text fills its parent's width and
grows vertically by default. Give the parent a numeric width, or
`width = "fill"` inside a bounded parent. Explicit native `Size` and
`AutomaticSize` override these defaults. Short readouts can hug their text
without wrapping.
Text has no width option. See [Layout-options](Layout-options.md) for native sizing.
Hugging text ignores `UI.fill()`. For a label and its value at opposite ends,
put `UI.Spacer()` between them in an HStack with `width = "fill"`.

Related controls: [Controls](Controls.md).

Open:

- [Text.reference](Text.reference.md)
