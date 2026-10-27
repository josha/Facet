--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number): { r: number, g: number, b: number }
	return { r = r / 255, g = g / 255, b = b / 255 }
end
local colors: { [string]: { r: number?, g: number?, b: number? } } = {
	surface = { r = 241 / 255, g = 246 / 255, b = 228 / 255 },
	surfaceStrong = { r = 218 / 255, g = 232 / 255, b = 204 / 255 },
	content = { r = 29 / 255, g = 60 / 255, b = 48 / 255 },
	accent = { r = 34 / 255, g = 102 / 255, b = 74 / 255 },
	onAccent = { r = 1, g = 1, b = 240 / 255 },
}
local typography: { [string]: Facet.TypographyPatch } = {
	title = { size = 34, font = { family = "rbxasset://fonts/families/Nunito.json", weight = "Bold" } },
	heading = { size = 28, font = { family = "rbxasset://fonts/families/Nunito.json", weight = "Bold" } },
	label = { size = 20, font = { family = "rbxasset://fonts/families/BuilderSans.json", weight = "Bold" } },
	strong = { size = 20 },
	numeral = { size = 44, font = { family = "rbxasset://fonts/families/Nunito.json", weight = "Bold" } },
	body = { size = 18 },
	caption = { size = 16 },
}
local definition: Facet.ThemeDefinition = {
	base = Facet.themes.neutralPackage(),
	identity = { id = "riverbank", displayName = "Riverbank" },
	style = {
		defaultTheme = "Meadow",
		themes = {
			{
				name = "Meadow",
				colors = colors,
				extra = {
					control = rgb(201, 220, 184),
					controlHover = rgb(188, 210, 170),
					controlPressed = rgb(175, 199, 156),
					controlSelected = rgb(160, 204, 130),
					onSelected = rgb(29, 60, 48),
					contentSecondary = rgb(68, 91, 71),
					hairline = rgb(75, 111, 76),
					hairlineOpacity = 0.25,
				},
			},
		},
	},
	metrics = { typography = typography, motion = { distances = { parallax = 0 } } },
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid Riverbank theme")
return theme
