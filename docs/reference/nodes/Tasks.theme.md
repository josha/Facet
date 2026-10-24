# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction -->

Express the direction in every theme layer, not just color.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number) return { r = r / 255, g = g / 255, b = b / 255 } end
local display, plain = "rbxasset://fonts/families/Michroma.json", "rbxasset://fonts/families/BuilderSans.json"
local sizes: { [string]: number } = { caption = 15, label = 18, body = 18, control = 18, numeral = 24, heading = 22, title = 28 }
local typography: { [string]: Facet.TypographyPatch } = {}
for role, size in sizes do
  typography[role] = { size = size, font = { family = if role == "title" or role == "heading" then display else plain } }
end
local definition: Facet.ThemeDefinition = {
  base = Facet.themes.neutralPackage(),
  identity = { id = "canyon-rally", displayName = "Canyon Rally" },
  style = { defaultTheme = "Dusk", themes = { { name = "Dusk",
    colors = { surface = rgb(36, 24, 20), surfaceStrong = rgb(54, 38, 30), content = rgb(246, 232, 210),
      accent = rgb(255, 140, 48), onAccent = rgb(40, 18, 8) },
    extra = { control = rgb(76, 54, 42), controlSelected = rgb(122, 58, 26), contentSecondary = rgb(206, 182, 152) },
  } } },
  metrics = { typography = typography, radii = { control = 3, panel = 4, tab = 3 },
    strokes = { hairline = 2 }, motion = { fast = 0.1, normal = 0.18 } },
  chrome = { panel = { kind = "native", shadow = "raised" }, focus = { kind = "brackets", corner = "square" } },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game theme")
local app = Facet.app({ name = "Game", theme = theme })
script.Destroying:Connect(app.dispose)
```

One direction: a dusk desert rally: tight corners, a wide display face, bracket focus and quick motion.  Derive yours with [Theme-identity](Theme-identity.md).
Next: [Themes.metrics](Themes.metrics.md), [Themes.chrome](Themes.chrome.md).
