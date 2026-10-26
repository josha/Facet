# NavigationSplitView.card

Show two related panes.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.NavigationSplitView "Panes" { sidebar = function() return UI.Text { text = "Items" } end, detail = function() return UI.Text { text = "Details" } end }
```

Key options: `sidebar`, `detail`, `axis`, `resizable`, `detailLabel`, `compactBack`.

Keep durable detail state in the model.

When the page owns a `NavBar`, pass the same writable boolean cell to its
`onBack` and the split view's `compactBack`. Set `detailLabel = false` only
when sidebar activation opens detail. See the [integrated example](NavigationSplitView.NavigationSplitView.md).

Related controls: [Controls](Controls.md).

Open:

- [NavigationSplitView.reference](NavigationSplitView.reference.md)
