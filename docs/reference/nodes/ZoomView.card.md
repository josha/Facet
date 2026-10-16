# ZoomView.card

Pan and zoom one stable content tree.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.ZoomView "Board" { contentSize = Vector2.new(800, 600), content = function() return UI.Text { text = "Board" } end }
```

Key options: `contentSize`, `content`, `zoom`, `focus`.

The content factory runs once.

Related controls: [Controls](Controls.md).

Open:

- [ZoomView.reference](ZoomView.reference.md)
