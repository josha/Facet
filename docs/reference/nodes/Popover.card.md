# Popover.card

Show anchored content.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.Popover "Popover" { isPresented = Facet.Compose.cell(true), source = { rect = { x = 0, y = 0, w = 44, h = 44 } }, content = function() return UI.Text { text = "Ready" } end }
```

Key options: `trigger`, `source`, `edge`, `compact`.

Use a live trigger or a source rectangle.

Related controls: [Controls](Controls.md).

Open:

- [Popover.reference](Popover.reference.md)
