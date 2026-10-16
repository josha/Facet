# CollapsibleView.card

Expand inline content.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.CollapsibleView "CollapsibleView" { expanded = Facet.Compose.cell(false), content = function() return UI.Text { text = "Ready" } end }
```

Key options: `expanded`, `content`.

Keep local expansion in a component cell.

Related controls: [Controls](Controls.md).

Open:

- [DisclosureGroup-and-CollapsibleView](DisclosureGroup-and-CollapsibleView.md)
