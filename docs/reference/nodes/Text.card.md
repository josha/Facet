# Text.card

Show text.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Text "Text" { text = "Ready" }
```

Key options: `text`, `textRole`, `wrap`, `truncate`, `lines`.

Text fills the width that its parent gives and grows vertically, so a title in
a fixed-width cell keeps the cell's width. In a horizontal stack or a parent
that hugs its width, one-line text hugs its words. For a paragraph, use
`wrap = true`. Give the parent a numeric width, or `width = "fill"` inside a
bounded parent. Explicit native `Size` and `AutomaticSize` override these
defaults; `AutomaticSize = Enum.AutomaticSize.XY` makes the text hug in any
parent.
Text has no width option. See [Layout-options](Layout-options.md) for native sizing.
Hugging text ignores `UI.fill()`. For a label and its value at opposite ends,
put `UI.Spacer {}` between them in an HStack with `width = "fill"`.

Related controls: [Controls](Controls.md).

Open:

- [Text.reference](Text.reference.md)
