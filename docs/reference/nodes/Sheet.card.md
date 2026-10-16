# Sheet.card

Show temporary modal details.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Sheet "Sheet" { title = "Details", isPresented = Facet.Compose.cell(true), content = function() return UI.Text { text = "Ready" } end }
```

Key options: `detents`, `placement`, `actions`, `closeButton`.

The content factory takes no arguments. Sheet owns scrolling and Back.

Related controls: [Controls](Controls.md).

Open:

- [Sheet.reference](Sheet.reference.md)
