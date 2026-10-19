# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction -->

Give the game its own look: palette, font, plates and strokes.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number) return { r = r / 255, g = g / 255, b = b / 255 } end
local definition: Facet.ThemeDefinition = {
    base = Facet.themes.neutralPackage(),
    identity = { id = "neon-hub", displayName = "Neon Hub" },
    style = { defaultTheme = "Neon", themes = {
        { name = "Neon",
          colors = {
            surface = rgb(10, 14, 24), surfaceStrong = rgb(16, 22, 36),
            content = rgb(220, 240, 250),
            accent = rgb(40, 220, 255), onAccent = rgb(4, 12, 20),
          },
          extra = {
            control = rgb(30, 44, 66), controlSelected = rgb(60, 40, 110),
            contentSecondary = rgb(150, 185, 205),
            hairline = rgb(40, 220, 255), hairlineOpacity = 0.4, dimDisabledPlates = true,
          } },
    } },
    metrics = {
        typography = {
            body = { size = 16, font = { family = "rbxasset://fonts/families/Michroma.json" } },
        },
    },
    rules = {
        { selector = ".facet-sheet::UIStroke",
          properties = { Color = { role = "accent" }, Transparency = 0.5, Thickness = 1 } },
    },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game theme")
local app = Facet.app({ name = "Game", theme = theme })
local UI = app.UI

app.mount(function()
    return UI.Screen "Root" {
        UI.VStack "Card" { surface = "panel", padding = "m", gap = "s",
            UI.Text "Title" { text = "Ready", textRole = "title" },
            UI.Button "Play" { label = "Play", appearance = "emphasis" },
        },
    }
end)
```

Next: [Theme-identity](Theme-identity.md), [Themes.tokens](Themes.tokens.md).
