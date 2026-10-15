--!strict
type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)
type ThemeDefinition = typeof(require("@repo/examples/types").ThemeDefinition)
type Extra = typeof(require("@repo/tools/typecheck/aliases").ThemePackage.style.themes[1].extra)
type RGB = { r: number, g: number, b: number }
type Palette = { colors: { [string]: RGB }, extra: Extra }
type Typography = typeof(require("@repo/tools/typecheck/aliases").ThemePackage.metrics.typography.body)

local classic_desktop = {}

classic_desktop.id = "classic-desktop"
classic_desktop.displayName = "Classic Desktop"

classic_desktop.themeClasses = table.freeze({ "palette", "metrics" })

local function rgb(r: number, g: number, b: number): RGB
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local LINE_HEIGHT = 1.15
local SIZES: { [string]: number } = { caption = 11, label = 12, body = 13, control = 13, heading = 15, title = 18 }

local function typography(): { [string]: Typography }
	local out: { [string]: Typography } = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = LINE_HEIGHT }
	end
	return out
end

local DAY: Palette = {
	colors = {
		surface = rgb(212, 208, 200),
		surfaceStrong = rgb(240, 238, 232),
		content = rgb(24, 24, 24),
		contentStrong = rgb(8, 8, 8),
		accent = rgb(16, 54, 122),
		onAccent = rgb(255, 255, 255),
		danger = rgb(140, 20, 20),
		onDanger = rgb(255, 255, 255),

		success = rgb(20, 94, 48),
		onSuccess = rgb(255, 255, 255),
		warning = rgb(196, 138, 16),
		onWarning = rgb(24, 24, 24),
	},
	extra = {
		control = rgb(226, 223, 216),
		controlHover = rgb(238, 236, 230),
		controlPressed = rgb(198, 194, 186),
		controlSelected = rgb(180, 198, 226),
		contentSecondary = rgb(88, 88, 88),
		hairline = rgb(96, 94, 90),
		hairlineOpacity = 0.55,
		scrimOpacity = 0.4,
		disabledContentOpacity = 0.45,
	},
}

local NIGHT: Palette = {
	colors = {
		surface = rgb(38, 38, 36),
		surfaceStrong = rgb(52, 52, 49),
		content = rgb(232, 230, 224),
		contentStrong = rgb(250, 249, 245),
		accent = rgb(122, 168, 236),
		onAccent = rgb(12, 16, 26),
		danger = rgb(228, 116, 116),
		onDanger = rgb(28, 10, 10),

		success = rgb(126, 204, 140),
		onSuccess = rgb(10, 26, 14),
		warning = rgb(232, 188, 104),
		onWarning = rgb(28, 20, 4),
	},
	extra = {
		control = rgb(64, 64, 60),
		controlHover = rgb(78, 78, 73),
		controlPressed = rgb(48, 48, 45),
		controlSelected = rgb(56, 74, 104),
		contentSecondary = rgb(168, 166, 158),
		hairline = rgb(255, 255, 255),
		hairlineOpacity = 0.86,
		scrimOpacity = 0.5,
		disabledContentOpacity = 0.45,
	},
}

function classic_desktop.definition(themes: Themes): ThemeDefinition
	return {
		base = themes.neutralPackage(),
		identity = {
			id = classic_desktop.id,
			displayName = classic_desktop.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Day",
			themes = {
				{ name = "Day", colors = DAY.colors, extra = DAY.extra },
				{ name = "Night", colors = NIGHT.colors, extra = NIGHT.extra },
			},
		},
		metrics = {
			typography = typography(),

			space = { xs = 2, s = 4, m = 8, l = 12, xl = 20 },

			controlSizes = {
				compact = { height = 22, paddingX = 6, iconSize = 12 },
				regular = { height = 26, paddingX = 8, iconSize = 14 },
				large = { height = 32, paddingX = 10, iconSize = 16 },
			},

			radii = { tab = 2, control = 2, panel = 0, pill = 4 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },

			motion = { fast = 0.06, normal = 0.1 },

			controls = {
				progress = { circularSize = 20, circularThickness = 2, spinnerDotSize = 6 },
			},
		},

		chrome = {
			panel = { kind = "native" },
			control = { kind = "native" },
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		assets = {},
	}
end

function classic_desktop.build(themes: Themes)
	return themes.define(classic_desktop.definition(themes))
end

return classic_desktop
