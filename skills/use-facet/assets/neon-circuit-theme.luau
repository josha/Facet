--!strict
-- Neon Circuit: one example identity for a night-time sci-fi game. Display type
-- leads titles, values and control labels; body text stays readable. Cyan marks
-- action and focus, magenta marks the current choice, and panels glow softly.
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number): { r: number, g: number, b: number }
	return { r = r / 255, g = g / 255, b = b / 255 }
end
local DISPLAY = "rbxasset://fonts/families/Michroma.json"
local CONDENSED = "rbxasset://fonts/families/TitilliumWeb.json"
local typography: { [string]: Facet.TypographyPatch } = {
	title = { size = 36, font = { family = DISPLAY, weight = "Bold" } },
	heading = { size = 24, font = { family = DISPLAY, weight = "Bold" } },
	numeral = { size = 44, font = { family = DISPLAY, weight = "Bold" } },
	label = { size = 18, font = { family = CONDENSED, weight = "Bold" } },
	control = { size = 20, font = { family = CONDENSED, weight = "Bold" } },
	strong = { size = 19 },
	body = { size = 18 },
	caption = { size = 15 },
}
local colors: { [string]: { r: number?, g: number?, b: number? } } = {
	surface = rgb(8, 12, 26),
	surfaceStrong = rgb(16, 24, 46),
	content = rgb(232, 246, 255),
	accent = rgb(40, 232, 255),
	onAccent = rgb(4, 12, 22),
	success = rgb(70, 240, 150),
	onSuccess = rgb(2, 16, 10),
	warning = rgb(255, 196, 60),
	onWarning = rgb(20, 12, 0),
	danger = rgb(255, 84, 104),
	onDanger = rgb(24, 2, 6),
}
local GLOW = {
	color = rgb(20, 200, 235),
	transparency = 0.55,
	blurRadius = { scale = 0, offset = 18 },
	offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
	zIndex = -1,
}
local chrome: { [string]: Facet.SkinLayerPatch } = {
	panel = { kind = "native", shadow = GLOW },
	control = { kind = "native", shadow = GLOW },
	focus = {
		kind = "glow",
		color = "$Accent",
		blurRadius = { scale = 0, offset = 18 },
		transparency = 0.3,
		zIndex = -1,
	},
}
local extra: Facet.PaletteExtra = {
	control = rgb(24, 38, 70),
	controlHover = rgb(32, 52, 92),
	controlPressed = rgb(18, 28, 54),
	controlSelected = rgb(64, 36, 110),
	onSelected = rgb(255, 255, 255),
	selection = rgb(255, 64, 196),
	onSelection = rgb(255, 255, 255),
	contentSecondary = rgb(150, 182, 214),
	hairline = rgb(40, 232, 255),
	hairlineOpacity = 0.4,
	chromeGradient = {
		panel = {
			rotation = 115,
			stops = { { t = 0, r = 0.16, g = 0.9, b = 1 }, { t = 1, r = 0.03, g = 0.05, b = 0.12 } },
			alpha = { { t = 0, v = 0.1 }, { t = 1, v = 0 } },
		},
	},
}
local definition: Facet.ThemeDefinition = {
	base = Facet.themes.neutralPackage(),
	identity = { id = "neon-circuit", displayName = "Neon Circuit" },
	style = {
		defaultTheme = "Night",
		themes = {
			{
				name = "Night",
				colors = colors,
				extra = extra,
			},
		},
	},
	metrics = {
		typography = typography,
		radii = { control = 6, panel = 10 },
		strokes = { hairline = 1.5 },
		motion = { distances = { parallax = 0 } },
	},
	chrome = chrome,
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid Neon Circuit theme")
return theme
