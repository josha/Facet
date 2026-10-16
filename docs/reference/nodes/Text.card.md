# Text.card

Show text.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Text "Text" { text = "Ready", wrap = true }
```

Key options: `text`, `textRole`, `wrap`, `truncate`, `lines`.

For wrapped text, set `width = "fill", align = "stretch"` on the parent VStack.
Text has no width option. See [Layout-options](Layout-options.md) for native sizing.

Related controls: [Controls](Controls.md).

Open:

- [Text.reference](Text.reference.md)
