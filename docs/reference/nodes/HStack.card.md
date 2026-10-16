# HStack.card

Arrange children horizontally.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.HStack "HStack" { gap = "s", UI.Text { text = "Ready" } }
```

Key options: `width`, `gap`, `padding`.

Use fill for remaining space.

Related controls: [Controls](Controls.md).

Open:

- [VStack-and-HStack](VStack-and-HStack.md)
