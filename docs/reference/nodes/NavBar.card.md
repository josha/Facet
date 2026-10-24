# NavBar.card

Show page commands and a title.

Inside an app mount, set `local UI = app.UI`.

```luau
UI.NavBar "NavBar" { title = "Inventory" }
```

Key options: `title`, `onBack`, `leading`, `trailing`.

Do not show Back on a root page.

`onBack` can be a boolean cell: Facet shows Back while it is true and writes false on Back, such as the `compactBack` cell of a NavigationSplitView.

Related controls: [Controls](Controls.md).

Open:

- [NavBar.reference](NavBar.reference.md)
