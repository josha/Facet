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

A new page selects its first content control, not Back or its own NavBar; set `initialFocus` on a destination to start on another control.

Related controls: [Controls](Controls.md).

Open:

- [NavigationStack.reference](NavigationStack.reference.md)
