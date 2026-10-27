--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number): { r: number, g: number, b: number }
	return { r = r / 255, g = g / 255, b = b / 255 }
end
local typography: { [string]: Facet.TypographyPatch } = {
	title = { size = 36, font = { family = "rbxasset://fonts/families/Merriweather.json", weight = "Regular" } },
	heading = { size = 24, font = { family = "rbxasset://fonts/families/Merriweather.json", weight = "Regular" } },
	numeral = { size = 32, font = { family = "rbxasset://fonts/families/Merriweather.json", weight = "Bold" } },
}
local colors: { [string]: { r: number?, g: number?, b: number? } } = {
	surface = { r = 244 / 255, g = 237 / 255, b = 217 / 255 },
	surfaceStrong = { r = 226 / 255, g = 217 / 255, b = 192 / 255 },
	content = { r = 39 / 255, g = 43 / 255, b = 34 / 255 },
	accent = { r = 45 / 255, g = 83 / 255, b = 64 / 255 },
	onAccent = { r = 1, g = 252 / 255, b = 239 / 255 },
}
local definition: Facet.ThemeDefinition = {
	base = Facet.themes.neutralPackage(),
	identity = { id = "field-station", displayName = "Field Station" },
	style = {
		defaultTheme = "Paper",
		themes = {
			{
				name = "Paper",
				colors = colors,
				extra = {
					control = rgb(231, 224, 202),
					controlHover = rgb(216, 218, 191),
					controlPressed = rgb(195, 204, 176),
					controlSelected = rgb(202, 219, 192),
					contentSecondary = rgb(79, 77, 60),
					onSelected = rgb(39, 43, 34),
					hairline = rgb(95, 95, 65),
					hairlineOpacity = 0.3,
				},
			},
		},
	},
	metrics = { typography = typography, motion = { distances = { parallax = 0 } } },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid Field Station theme")
return theme
