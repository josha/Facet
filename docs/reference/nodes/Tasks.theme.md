# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction -->

Define paint here; layout and game art establish the focal area.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number) return { r = r / 255, g = g / 255, b = b / 255 } end
local typography: { [string]: Facet.TypographyPatch } = {}
local sizes: { [string]: number } = { caption = 15, label = 18, body = 18, control = 18, strong = 18, numeral = 24, heading = 24, title = 40 }
for role, size in sizes do
  typography[role] = { size = size, font = { family = "rbxasset://fonts/families/BuilderSans.json",
    weight = if role == "label" then "SemiBold" else nil } }
end
local definition: Facet.ThemeDefinition = {
  base = Facet.themes.neutralPackage(),
  identity = { id = "field-station", displayName = "Field Station" },
  style = { defaultTheme = "Day", themes = { { name = "Day",
    colors = { surface = rgb(245, 241, 229), surfaceStrong = rgb(225, 226, 209),
      content = rgb(25, 43, 36), accent = rgb(24, 91, 67), onAccent = rgb(255, 255, 248) },
    extra = { control = rgb(219, 225, 209), controlHover = rgb(201, 217, 193), controlPressed = rgb(184, 204, 176),
      controlSelected = rgb(186, 214, 193), contentSecondary = rgb(73, 88, 73),
      hairline = rgb(24, 91, 67), hairlineOpacity = 0.4, dimDisabledPlates = true } } } },
  metrics = { typography = typography, motion = { distances = { parallax = 0 } } },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game theme")
local app = Facet.app({ name = "Game", theme = theme })
script.Destroying:Connect(app.dispose)
```

Use the game's palette, type and subject art. This theme keeps covered pages
still (`parallax = 0`); omit that patch for the base page-to-page movement.
It applies to all default stacks using the theme. See [Theme-identity](Theme-identity.md)
and [Themes.tokens](Themes.tokens.md).
