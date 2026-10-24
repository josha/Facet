# VStack.card

Arrange children vertically.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.VStack "VStack" { width = "fill", gap = "s", UI.Text { text = "Ready" } }
```

Key options: `width`, `gap`, `padding`, `surface`, `corners`.

Bound the parent before adding a virtual collection.

With `surface` and `corners`, Facet rounds the plate and keeps the content out
of its corners, so do not add a `UICorner`.

Related controls: [Controls](Controls.md).

Open:

- [VStack-and-HStack](VStack-and-HStack.md)
