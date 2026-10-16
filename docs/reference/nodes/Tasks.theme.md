# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition -->

Mount a themed game root.

Controls: Screen, Text, Button.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local definition: Facet.ThemeDefinition = {
    base = Facet.themes.neutralPackage(),
    identity = { id = "game", displayName = "Game" },
    style = { defaultTheme = "Dark", themes = {
        { name = "Dark", colors = {
            accent = { r = 0.4, g = 0.8, b = 1 }, onAccent = { r = 0, g = 0, b = 0 },
        } },
    } },
    metrics = { typography = { body = { size = 18 } }, space = { m = 16 } },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game theme")
local app = Facet.app({ name = "Game", theme = theme })
local UI = app.UI

app.mount(function()
    return UI.Screen "Root" {
        UI.Text "Title" { text = "Ready", textRole = "title" },
        UI.Button "Play" { label = "Play", appearance = "emphasis" },
    }
end)
script.Destroying:Connect(app.dispose)
```

Facet.app installs the native StyleSheet and StyleLink. A definition derives from its base. Put palettes in `style.themes` as a list. Colors use `r`, `g`, `b` channels from 0 to 1. Type roles go in `metrics.typography`; each role has `size` and an optional `font = { family, weight, style }`. Check the report before passing the package to the app. Use semantic roles and tokens for paint, type, spacing and motion.

Open:

- [Mounting](Mounting.md)
- [Themes.index](Themes.index.md)
- [Themes.tokens](Themes.tokens.md)
