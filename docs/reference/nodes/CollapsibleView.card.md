# CollapsibleView.card

Expand a panel from a pill trigger, over the page.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.CollapsibleView "CollapsibleView" { expanded = Facet.Compose.cell(false), content = function() return UI.Text { text = "Ready" } end }
```

Key options: `label`, `expanded`, `content`. The page does not move. Use
DisclosureGroup to expand content in the reading flow.

Keep local expansion in a component cell.

Related controls: [Controls](Controls.md).

Open:

- [DisclosureGroup-and-CollapsibleView](DisclosureGroup-and-CollapsibleView.md)
