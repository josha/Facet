--!strict

local scifi_hud = {}

scifi_hud.id = "scifi-hud"
scifi_hud.displayName = "Sci-Fi HUD"
scifi_hud.themeClasses = table.freeze({ "palette", "metrics", "font" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/Michroma.json"
local SIZES = { caption = 11, label = 12, body = 14, control = 14, heading = 18, title = 22 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.45 }
	end
	return out
end

local function wash(topA: number, bottomA: number): any
	return {
		rotation = 115,
		stops = {
			{ t = 0, r = 0.36, g = 0.86, b = 1 },
			{ t = 0.35, r = 0.16, g = 0.44, b = 0.66 },
			{ t = 1, r = 0.04, g = 0.1, b = 0.18 },
		},
		alpha = {
			{ t = 0, v = topA },
			{ t = 0.35, v = (topA + bottomA) / 2 },
			{ t = 1, v = bottomA },
		},
	}
end

local function sheen(topA: number, bottomA: number): any
	return {
		rotation = 115,
		stops = {
			{ t = 0, r = 1, g = 1, b = 1 },
			{ t = 0.5, r = 0.86, g = 0.96, b = 1 },
			{ t = 1, r = 0.68, g = 0.86, b = 0.95 },
		},
		alpha = {
			{ t = 0, v = topA },
			{ t = 1, v = bottomA },
		},
	}
end

local NIGHTWATCH = {
	colors = {
		surface = rgb(6, 11, 18),
		surfaceStrong = rgb(12, 20, 30),
		content = rgb(198, 232, 246),
		contentStrong = rgb(232, 250, 255),
		accent = rgb(64, 214, 236),
		onAccent = rgb(4, 12, 18),
		danger = rgb(255, 110, 96),
		onDanger = rgb(20, 4, 2),

		success = rgb(86, 236, 158),
		onSuccess = rgb(2, 16, 10),
		warning = rgb(255, 196, 74),
		onWarning = rgb(20, 12, 0),
	},
	extra = {
		control = rgb(18, 30, 44),
		controlHover = rgb(26, 44, 62),
		controlPressed = rgb(12, 20, 30),
		controlSelected = rgb(20, 58, 78),
		contentSecondary = rgb(126, 164, 184),
		hairline = rgb(96, 214, 236),
		hairlineOpacity = 0.6,
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.5,
		chromeGradient = {
			panel = wash(0.12, 0.34),
			control = sheen(0.05, 0.2),
			selection = sheen(0.02, 0.14),
		},
	},
}

function scifi_hud.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = scifi_hud.id,
			displayName = scifi_hud.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Nightwatch",
			themes = { { name = "Nightwatch", colors = NIGHTWATCH.colors, extra = NIGHTWATCH.extra } },
		},
		metrics = {
			typography = typography(),
			space = { xs = 4, s = 8, m = 14, l = 22, xl = 36 },
			controlSizes = {
				compact = { height = 32, paddingX = 12, iconSize = 16 },
				regular = { height = 40, paddingX = 16, iconSize = 20 },
				large = { height = 52, paddingX = 20, iconSize = 24 },
			},

			radii = { control = 0, panel = 0, pill = 0 },
			strokes = { hairline = 2 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.09, normal = 0.18 },

			controls = {
				progress = { circularSize = 36, circularThickness = 2, spinnerDotSize = 6 },
			},
			insets = {
				panel = { top = 14, right = 14, bottom = 14, left = 14 },
				control = { top = 8, right = 16, bottom = 8, left = 16 },
				field = { top = 8, right = 16, bottom = 8, left = 16 },
				selection = { top = 4, right = 8, bottom = 4, left = 8 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},

		chrome = {

			panel = {
				kind = "native",
				shadow = {
					blurRadius = { scale = 0, offset = 24 },
					color = { r = 0.05, g = 0.42, b = 0.5 },
					transparency = 0.3,
					offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
					zIndex = -1,
				},
			},
			control = {
				kind = "native",
				shadow = {
					blurRadius = { scale = 0, offset = 16 },
					color = { r = 0.05, g = 0.42, b = 0.5 },
					transparency = 0.28,
					offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
					zIndex = -1,
				},
			},
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },

			focus = {
				kind = "glow",
				color = "$Accent",
				blurRadius = { scale = 0, offset = 20 },
				transparency = 0.3,
				zIndex = -1,
			},
		},
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function scifi_hud.build(themes: any): (any, any)
	return themes.define(scifi_hud.definition(themes))
end

return scifi_hud
