# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction -->

Define paint here; layout and game art establish the focal area.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number) return { r = r / 255, g = g / 255, b = b / 255 } end
local display, plain = "rbxasset://fonts/families/Michroma.json", "rbxasset://fonts/families/BuilderSans.json"
local typography: { [string]: Facet.TypographyPatch } = {}
local sizes: { [string]: number } = { caption = 15, label = 18, body = 18, control = 18, strong = 18, numeral = 24, heading = 22, title = 28 }
for role, size in sizes do
  typography[role] = { size = size, font = {
    family = if role == "title" or role == "heading" then display else plain,
    weight = if role == "label" then "SemiBold" else nil,
  } }
end
local definition: Facet.ThemeDefinition = {
  base = Facet.themes.neutralPackage(),
  identity = { id = "canyon-rally", displayName = "Canyon Rally" },
  style = { defaultTheme = "Dusk", themes = {
    { name = "Dusk",
     colors = {
      surface = rgb(36, 24, 20), surfaceStrong = rgb(54, 38, 30),
      content = rgb(246, 232, 210),
      accent = rgb(255, 140, 48), onAccent = rgb(40, 18, 8),
     },
     extra = {
      control = rgb(76, 54, 42), controlSelected = rgb(122, 58, 26),
      contentSecondary = rgb(206, 182, 152),
      hairline = rgb(206, 182, 152), hairlineOpacity = 0.8, dimDisabledPlates = true,
     } },
  } },
  metrics = { typography = typography },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game theme")
local app = Facet.app({ name = "Game", theme = theme })
script.Destroying:Connect(app.dispose)
```

These values describe one desert rally at dusk.  Derive yours from your game's direction with [Theme-identity](Theme-identity.md).  Add shape and motion from [Themes.metrics](Themes.metrics.md).
Next: [Themes.tokens](Themes.tokens.md).
