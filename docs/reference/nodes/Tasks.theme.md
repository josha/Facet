# Tasks.theme

<!-- aliases: themePackage | ThemeDefinition | custom theme | theme definition | visual identity | art direction -->

Define paint here; layout and game art establish the focal area.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number) return { r = r / 255, g = g / 255, b = b / 255 } end
local typography: { [string]: Facet.TypographyPatch } = {}
local sizes: { [string]: number } = { caption = 15, label = 18, body = 18, control = 18, strong = 18, numeral = 24, heading = 22, title = 28 }
for role, size in sizes do
  typography[role] = { size = size, font = {
    family = "rbxasset://fonts/families/BuilderSans.json",
    weight = if role == "label" then "SemiBold" else nil,
  } }
end
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
  metrics = { typography = typography },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid game theme")
local app = Facet.app({ name = "Game", theme = theme })
script.Destroying:Connect(app.dispose)
```

Choose a palette and type hierarchy for the game. Use accent for commitment,
quiet surfaces for comparison, and object art for recognition. Theme paint does
not supply composition: give the selected object a focal area, keep its terms
beside its action, and let decoration yield on short screens.
Next: [Theme-identity](Theme-identity.md), [Themes.tokens](Themes.tokens.md).
