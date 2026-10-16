# Tasks.theme

Mount a themed game root.

Controls: Screen, Text, Button.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game", theme = Facet.themes.neutralPackage() })
local UI = app.UI

app.mount(function()
    return UI.Screen "Root" {
        UI.Text "Title" { text = "Ready", textRole = "title" },
        UI.Button "Play" { label = "Play", appearance = "emphasis" },
    }
end)
script.Destroying:Connect(app.dispose)
```

Facet.app installs the neutral theme, native StyleSheet and StyleLink. Choose a game-owned package from Themes.index. Pass it as the app theme. Use semantic roles and tokens for paint, type, spacing and motion.

Open:

- [Mounting](Mounting.md)
- [Themes.index](Themes.index.md)
- [Themes.tokens](Themes.tokens.md)
