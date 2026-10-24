# HStack.card

Arrange children horizontally.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.HStack "HStack" { gap = "s", UI.Text { text = "Ready" } }
```

Key options: `width`, `gap`, `padding`, `surface`, `corners`.

Use fill for remaining space.

With `surface = "panel"` and `corners = "pill"`, Facet rounds the plate and
keeps the content out of its curve, so do not add a `UICorner`.

Related controls: [Controls](Controls.md).

Open:

- [VStack-and-HStack](VStack-and-HStack.md)
