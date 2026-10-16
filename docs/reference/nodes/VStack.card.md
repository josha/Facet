# VStack.card

Arrange children vertically.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.VStack "VStack" { width = "fill", gap = "s", UI.Text { text = "Ready" } }
```

Key options: `width`, `gap`, `padding`.

Bound the parent before adding a virtual collection.

Related controls: [Controls](Controls.md).

Open:

- [VStack-and-HStack](VStack-and-HStack.md)
