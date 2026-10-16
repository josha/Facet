# TabView.card

Switch between peer destinations.

Inside an app mount, set `local UI = app.UI`.

```luau
local selection = Facet.Compose.cell("home")
local tabs: { Facet.Tab } = { { id = "home", label = "Home", content = function() return UI.Text { text = "Home" } end } }
UI.TabView "Pages" { selection = selection, tabs = tabs }
```

Key options: `selection`, `tabs`, `placement`, `retention`.

Keep durable page state in the model.

Related controls: [Controls](Controls.md).

Open:

- [TabView.reference](TabView.reference.md)
