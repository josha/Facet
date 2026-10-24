# NavigationSplitView.card

Show two related panes.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.NavigationSplitView "Panes" { sidebar = function() return UI.Text { text = "Items" } end, detail = function() return UI.Text { text = "Details" } end }
```

Key options: `sidebar`, `detail`, `axis`, `resizable`, `detailLabel`, `compactBack`.

Keep durable detail state in the model.

On a phone, Facet shows the compact Back in the page `UI.NavBar` through `compactBack`, and `detailLabel = false` removes Show detail, so the page keeps one header.

Related controls: [Controls](Controls.md).

Open:

- [NavigationSplitView.reference](NavigationSplitView.reference.md)
