--!strict

local foundation = {}

foundation.id = "foundation"
foundation.displayName = "Foundation"
foundation.themeNames = table.freeze({ "foundation-dark", "foundation-light" })

local function hex(value: number)
	return {
		r = bit32.extract(value, 16, 8) / 255,
		g = bit32.extract(value, 8, 8) / 255,
		b = bit32.extract(value, 0, 8) / 255,
	}
end

local DARK = {
	colors = {
		surface = hex(0x121215),
		surfaceStrong = hex(0x191A1F),
		content = hex(0xD5D7DD),
		contentStrong = hex(0xF7F7F8),
		accent = hex(0x3C5EF6),
		onAccent = hex(0xFFFFFF),
		danger = hex(0xDE523F),
		onDanger = hex(0x121215),
		success = hex(0x3FB871),
		onSuccess = hex(0x121215),
		warning = hex(0xF2B01E),
		onWarning = hex(0x121215),
	},
	extra = {
		control = hex(0x28292F),
		controlHover = hex(0x303138),
		controlPressed = hex(0x202127),
		controlSelected = hex(0x23316F),
		contentSecondary = hex(0xBCBEC7),
		hairline = hex(0xFFFFFF),
		hairlineOpacity = 0.87,

		scrim = hex(0x000000),
		scrimOpacity = 0.65,
		disabledContentOpacity = 0.5,

		selection = hex(0xF7F7F8),
		onSelection = hex(0x121215),

		dimDisabledPlates = true,

		strongHairlineOpacity = 0.6,
	},
}

local LIGHT = {
	colors = {
		surface = hex(0xFFFFFF),
		surfaceStrong = hex(0xF7F7F8),
		content = hex(0x191A1F),
		contentStrong = hex(0x121215),
		accent = hex(0x3C5EF6),
		onAccent = hex(0xFFFFFF),
		danger = hex(0xC8321F),
		onDanger = hex(0xFFFFFF),
		success = hex(0x1E7A45),
		onSuccess = hex(0xFFFFFF),
		warning = hex(0x9A5B00),
		onWarning = hex(0xFFFFFF),
	},
	extra = {
		control = hex(0xEEEFF1),
		controlHover = hex(0xE4E5E8),
		controlPressed = hex(0xD9DADF),
		controlSelected = hex(0xDFE5FE),
		contentSecondary = hex(0x4A4D59),
		hairline = hex(0x000000),
		hairlineOpacity = 0.85,
		scrim = hex(0x000000),
		scrimOpacity = 0.65,
		disabledContentOpacity = 0.5,
		selection = hex(0x121215),
		onSelection = hex(0xFFFFFF),
		dimDisabledPlates = true,
		strongHairlineOpacity = 0.6,
	},
}

function foundation.definition(themes: any, defaultTheme: string?): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = foundation.id,
			displayName = foundation.displayName,
			schemaVersion = themes.SCHEMA,
			version = "0.1.0",
		},
		style = {
			defaultTheme = defaultTheme or "foundation-dark",
			themes = {
				{ name = "foundation-dark", colors = DARK.colors, extra = DARK.extra },
				{ name = "foundation-light", colors = LIGHT.colors, extra = LIGHT.extra },
			},
		},
		metrics = {

			typography = {
				title = { size = 24, font = { weight = "Bold" } },
				heading = { size = 20, font = { weight = "Bold" } },
				body = { size = 16 },
				label = { size = 13 },
				caption = { size = 12 },
			},

			controls = {
				textInput = { fieldHeight = 40 },
				shortcutHint = { capStroke = 0, capGap = 2 },
				badge = { markScale = 0.4 },
			},

			controlSizes = {
				xsmall = { height = 24, paddingX = 8, iconSize = 12 },
				compact = { height = 32, paddingX = 12, iconSize = 16 },
				regular = { height = 40, paddingX = 16, iconSize = 20 },
				large = { height = 48, paddingX = 20, iconSize = 24 },
			},
			radii = { control = 8, panel = 12, pill = 999 },

			strokes = { hairline = 1, utility = 0 },

			targetSizes = { minimum = 44, pointer = 24 },
		},
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function foundation.build(themes: any, defaultTheme: string?): (any, any)
	return themes.define(foundation.definition(themes, defaultTheme))
end

return foundation
