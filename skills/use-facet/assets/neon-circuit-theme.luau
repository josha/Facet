--!strict
-- Neon Circuit: one example identity for a night-time sci-fi game. Every panel
-- carries a cyan neon edge and a soft glow, controls are a saturated blue step
-- above the dark surface, magenta marks the current choice, and display type
-- leads titles and values while body text stays readable.
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function rgb(r: number, g: number, b: number): { r: number, g: number, b: number }
	return { r = r / 255, g = g / 255, b = b / 255 }
end
local DISPLAY = "rbxasset://fonts/families/Michroma.json"
local NUMERALS = "rbxasset://fonts/families/Zekton.json"
local CONDENSED = "rbxasset://fonts/families/TitilliumWeb.json"
local typography: { [string]: Facet.TypographyPatch } = {
	title = { size = 36, font = { family = DISPLAY, weight = "Bold" } },
	heading = { size = 22, font = { family = DISPLAY, weight = "Bold" } },
	numeral = { size = 40, font = { family = NUMERALS, weight = "Bold" } },
	label = { size = 18, font = { family = CONDENSED, weight = "Bold" } },
	control = { size = 20, font = { family = CONDENSED, weight = "Bold" } },
	strong = { size = 20, font = { family = CONDENSED, weight = "Bold" } },
	body = { size = 18 },
	caption = { size = 15 },
}
local colors: { [string]: { r: number?, g: number?, b: number? } } = {
	surface = rgb(9, 12, 30),
	surfaceStrong = rgb(18, 26, 56),
	content = rgb(236, 248, 255),
	accent = rgb(0, 229, 255),
	onAccent = rgb(2, 10, 20),
	success = rgb(70, 240, 150),
	onSuccess = rgb(2, 16, 10),
	warning = rgb(255, 190, 50),
	onWarning = rgb(24, 12, 0),
	danger = rgb(255, 70, 100),
	onDanger = rgb(24, 2, 6),
}
local extra: Facet.PaletteExtra = {
	control = rgb(30, 46, 92),
	controlHover = rgb(42, 64, 124),
	controlPressed = rgb(22, 34, 70),
	controlSelected = rgb(90, 30, 120),
	onSelected = rgb(255, 255, 255),
	selection = rgb(255, 46, 196),
	onSelection = rgb(255, 255, 255),
	contentSecondary = rgb(150, 190, 225),
	hairline = rgb(0, 229, 255),
	hairlineOpacity = 0.55,
	chromeGradient = {
		panel = {
			rotation = 90,
			stops = { { t = 0, r = 0.1, g = 0.5, b = 0.9 }, { t = 1, r = 0.04, g = 0.06, b = 0.16 } },
			alpha = { { t = 0, v = 0.22 }, { t = 0.5, v = 0 }, { t = 1, v = 0 } },
		},
	},
}
local chrome: { [string]: Facet.SkinLayerPatch } = {
	panel = {
		kind = "native",
		shadow = {
			color = rgb(0, 200, 255),
			transparency = 0.35,
			blurRadius = { scale = 0, offset = 22 },
			offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
			zIndex = -1,
		},
	},
	control = { kind = "native" },
	focus = {
		kind = "glow",
		color = "$Accent",
		blurRadius = { scale = 0, offset = 18 },
		transparency = 0.2,
		zIndex = -1,
	},
}
-- The neon edge: every panel and page surface draws a stroke in the accent.
local function edge(selector: string, thickness: number, transparency: number): Facet.ThemeRule
	local properties: Facet.ThemeRuleProperties = {}
	properties.Color = { role = "accent" }
	properties.Thickness = thickness
	properties.Transparency = transparency
	return { selector = selector, properties = properties }
end
local rules: { Facet.ThemeRule } =
	{ edge(".facet-panel::UIStroke", 1.5, 0.3), edge(".facet-surface::UIStroke", 1, 0.6) }
local definition: Facet.ThemeDefinition = {
	base = Facet.themes.neutralPackage(),
	identity = { id = "neon-circuit", displayName = "Neon Circuit" },
	style = { defaultTheme = "Night", themes = { { name = "Night", colors = colors, extra = extra } } },
	metrics = {
		typography = typography,
		radii = { control = 6, panel = 12 },
		strokes = { hairline = 1.5 },
		motion = { distances = { parallax = 0 } },
	},
	chrome = chrome,
	rules = rules,
}
local theme, report = Facet.themes.define(definition)
assert(report.ok and theme, "Invalid Neon Circuit theme")
return theme
