--!strict

local glossy_mobile = {}

glossy_mobile.id = "glossy-mobile"
glossy_mobile.displayName = "Glossy Mobile"
glossy_mobile.themeClasses = table.freeze({ "palette", "metrics", "font" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/Nunito.json"
local SIZES = { caption = 13, label = 15, body = 17, control = 18, heading = 24, title = 30 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY, weight = "Medium" }, size = size, lineHeight = 1.3 }
	end

	out.title.font = { family = FAMILY, weight = "Bold" }
	return out
end

local function gloss(topAlpha: number, bottomAlpha: number): any
	return {
		rotation = 90,
		stops = {
			{ t = 0, r = 1, g = 1, b = 1 },
			{ t = 0.48, r = 1, g = 1, b = 1 },
			{ t = 0.52, r = 0.86, g = 0.88, b = 0.92 },
			{ t = 1, r = 0.94, g = 0.96, b = 1 },
		},
		alpha = {
			{ t = 0, v = topAlpha },
			{ t = 0.48, v = topAlpha + 0.12 },
			{ t = 0.52, v = bottomAlpha },
			{ t = 1, v = bottomAlpha },
		},
	}
end

local DAYLIGHT = {
	colors = {
		surface = rgb(238, 243, 250),
		surfaceStrong = rgb(255, 255, 255),
		content = rgb(22, 28, 40),
		contentStrong = rgb(8, 12, 20),
		accent = rgb(12, 96, 200),
		onAccent = rgb(255, 255, 255),
		danger = rgb(184, 26, 44),
		onDanger = rgb(255, 255, 255),

		success = rgb(14, 116, 72),
		onSuccess = rgb(255, 255, 255),
		warning = rgb(216, 152, 16),
		onWarning = rgb(20, 14, 2),
	},
	extra = {
		control = rgb(226, 236, 250),
		controlHover = rgb(238, 245, 255),
		controlPressed = rgb(202, 216, 236),
		controlSelected = rgb(190, 216, 250),
		contentSecondary = rgb(92, 104, 124),
		hairline = rgb(40, 60, 90),
		hairlineOpacity = 0.82,
		scrimOpacity = 0.35,
		disabledContentOpacity = 0.4,
		chromeGradient = {
			control = gloss(0.02, 0.22),
			panel = gloss(0.06, 0.3),
		},

		["demo:gaugeTint"] = rgb(12, 96, 200),
	},
}

function glossy_mobile.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = glossy_mobile.id,
			displayName = glossy_mobile.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Daylight",
			themes = { { name = "Daylight", colors = DAYLIGHT.colors, extra = DAYLIGHT.extra } },
		},
		metrics = {
			typography = typography(),
			space = { xs = 6, s = 10, m = 18, l = 28, xl = 44 },

			controlSizes = {
				compact = { height = 44, paddingX = 14, iconSize = 22 },
				regular = { height = 52, paddingX = 18, iconSize = 26 },
				large = { height = 64, paddingX = 22, iconSize = 30 },

				["demo:gauge"] = { height = 28, paddingX = 12, iconSize = 18 },
			},
			radii = { control = 16, panel = 24, pill = 999 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 48 },
			motion = { fast = 0.16, normal = 0.28 },

			controls = {
				progress = { circularSize = 32, circularThickness = 5, spinnerDotSize = 10 },
			},
			insets = {
				panel = { top = 18, right = 18, bottom = 18, left = 18 },
				control = { top = 10, right = 18, bottom = 10, left = 18 },
				field = { top = 10, right = 18, bottom = 10, left = 18 },
				selection = { top = 8, right = 10, bottom = 8, left = 10 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		chrome = {

			panel = { kind = "native", shadow = "raised" },
			control = { kind = "native", shadow = "raised" },
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function glossy_mobile.build(themes: any): (any, any)
	return themes.define(glossy_mobile.definition(themes))
end

return glossy_mobile
