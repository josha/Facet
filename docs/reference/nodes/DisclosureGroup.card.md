# DisclosureGroup.card

Show details in place.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.DisclosureGroup "DisclosureGroup" { label = "Details", expanded = Facet.Compose.cell(false), content = function() return UI.Text { text = "Ready" } end }
```

Key options: `expanded`, `content`, `appearance`.

Use Sheet when the task needs a modal surface.

Related controls: [Controls](Controls.md).

Open:

- [DisclosureGroup-and-CollapsibleView](DisclosureGroup-and-CollapsibleView.md)
