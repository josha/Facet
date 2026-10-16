# PageView.card

Switch between pages with page controls.

Inside an app mount, set `local UI = app.UI`.

```luau
local selection = Facet.Compose.cell("home")
UI.PageView "Pages" { selection = selection, pages = { { id = "home", label = "Home", content = function() return UI.Text { text = "Home" } end } } }
```

Key options: `selection`, `pages`, `indicators`.

Selection must name a declared page.

Related controls: [Controls](Controls.md).

Open:

- [PageView.reference](PageView.reference.md)
