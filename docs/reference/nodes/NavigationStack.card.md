# NavigationStack.card

Move through child pages with Back.

Inside an app mount, set `local UI = app.UI`.

```luau
local initial: { Facet.NavigationEntry<string> } = {}
local path = Facet.Compose.cell(initial)
UI.NavigationStack "Pages" { path = path, root = { title = "Home", content = function() return UI.Text { text = "Home" } end }, destinations = {} }
```

Key options: `path`, `root`, `destinations`, `backLabel`.

The root has no Back command.

Related controls: [Controls](Controls.md).

Open:

- [NavigationStack.reference](NavigationStack.reference.md)
