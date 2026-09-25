--!strict

local glossy_touch = {}

glossy_touch.id = "glossy-touch"
glossy_touch.displayName = "Glossy Touch"
glossy_touch.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })

glossy_touch.pairRole = "touch"

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/Nunito.json"
local SIZES = { caption = 13, label = 15, body = 17, control = 17, heading = 24, title = 30 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY, weight = "Medium" }, size = size, lineHeight = 1.3 }
	end
	out.title.font = { family = FAMILY, weight = "Bold" }
	return out
end

local SKY = {
	colors = {
		surface = rgb(226, 233, 242),
		surfaceStrong = rgb(248, 251, 255),
		content = rgb(24, 30, 42),
		contentStrong = rgb(8, 12, 20),
		accent = rgb(18, 92, 190),
		onAccent = rgb(255, 255, 255),
		danger = rgb(178, 26, 40),
		onDanger = rgb(255, 255, 255),

		success = rgb(16, 112, 70),
		onSuccess = rgb(255, 255, 255),
		warning = rgb(212, 148, 14),
		onWarning = rgb(18, 12, 2),
	},
	extra = {
		control = rgb(232, 238, 246),
		controlHover = rgb(242, 247, 255),
		controlPressed = rgb(196, 210, 228),

		controlSelected = rgb(20, 81, 194),
		onSelected = rgb(255, 255, 255),
		contentSecondary = rgb(88, 100, 120),
		hairline = rgb(36, 56, 86),
		hairlineOpacity = 0.8,
		scrimOpacity = 0.35,
		disabledContentOpacity = 0.4,

		focusGlow = rgb(64, 152, 244),
	},
}

local ASSETS = {
	glossy_panel = {
		content = "rbxassetid://107047113527598",
		sliceCenter = { x0 = 28, y0 = 28, x1 = 68, y1 = 68 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_button_default = {
		content = "rbxassetid://112434784235062",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 28 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_button_pressed = {
		content = "rbxassetid://109576289121111",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 28 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_field = {
		content = "rbxassetid://132031958681203",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 28 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_selection_default = {
		content = "rbxassetid://80851150247066",
		sliceCenter = { x0 = 18, y0 = 18, x1 = 54, y1 = 26 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_selection_selected = {
		content = "rbxassetid://92935254088612",
		sliceCenter = { x0 = 18, y0 = 18, x1 = 54, y1 = 26 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_bar_track = {
		content = "rbxassetid://90291950996149",
		sliceCenter = { x0 = 10, y0 = 10, x1 = 86, y1 = 14 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},

	glossy_bar_fill = {
		content = "rbxassetid://121908556097885",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 88, y1 = 16 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},

	glossy_stripe_tile = { content = "rbxassetid://131357884608814", preload = "install", fallback = "native" },
	glossy_toggle_track_off = {
		content = "rbxassetid://133407056790088",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},

	glossy_toggle_track_on = {
		content = "rbxassetid://98206529376640",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_toggle_knob = { content = "rbxassetid://126375261384779", preload = "install", fallback = "native" },
	glossy_stepper_plate_default = {
		content = "rbxassetid://133233140281994",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 30, y1 = 30 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	glossy_stepper_plate_pressed = {
		content = "rbxassetid://70897473278181",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 30, y1 = 30 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
}

function glossy_touch.definition(themes: any): any
	local assets = table.clone(ASSETS)

	assets.search = { content = "rbxassetid://85188541706347", tintRole = "content" }
	return {
		base = themes.neutralPackage(),
		identity = {
			id = glossy_touch.id,
			displayName = glossy_touch.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = { defaultTheme = "Sky", themes = { { name = "Sky", colors = SKY.colors, extra = SKY.extra } } },
		metrics = {
			typography = typography(),
			space = { xs = 6, s = 10, m = 18, l = 28, xl = 44 },

			controlSizes = {
				compact = { height = 44, paddingX = 14, iconSize = 22 },
				regular = { height = 44, paddingX = 18, iconSize = 24 },
				large = { height = 56, paddingX = 22, iconSize = 28 },
			},
			iconSizes = { small = 20, medium = 28, large = 40 },
			radii = { control = 10, panel = 14, pill = 999, selection = 10 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.16, normal = 0.28 },
			controls = {

				popup = { triggerHeight = 40, shadeInset = 4 },

				progress = {
					trackHeight = 24,
					rowMinHeight = 32,
					circularSize = 40,
					circularThickness = 6,
					spinnerDotSize = 12,
				},
			},
			insets = {
				panel = { top = 16, right = 16, bottom = 16, left = 16 },
				control = { top = 10, right = 16, bottom = 10, left = 16 },
				field = { top = 10, right = 16, bottom = 10, left = 16 },
				selection = { top = 8, right = 10, bottom = 8, left = 10 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		chrome = {
			panel = {
				kind = "nineSlice",
				asset = "glossy_panel",
				contentInsets = { top = 14, right = 14, bottom = 14, left = 14 },
				fallback = "native",
				shadow = "raised",
			},

			control = {
				kind = "nineSlice",
				asset = { default = "glossy_button_default", pressed = "glossy_button_pressed" },
				contentInsets = { top = 8, right = 14, bottom = 8, left = 14 },
				fallback = "native",
			},
			field = {
				kind = "nineSlice",
				asset = "glossy_field",
				contentInsets = { top = 8, right = 14, bottom = 8, left = 14 },
				fallback = "native",
			},
			selection = {
				kind = "nineSlice",
				asset = { default = "glossy_selection_default", selected = "glossy_selection_selected" },
				contentInsets = { top = 6, right = 10, bottom = 6, left = 10 },
				fallback = "native",
			},
			focus = {
				kind = "glow",
				color = "$FocusGlow",
				blurRadius = { scale = 0, offset = 22 },
				transparency = 0.3,
				zIndex = -1,
			},

			barTrack = {
				kind = "layered",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
				layers = {
					{ kind = "fill", asset = "glossy_bar_track" },

					{
						kind = "tile",
						asset = "glossy_stripe_tile",
						tileSize = { w = 24, h = 24 },
						mask = "pill",
						inset = { x = 2, y = 2 },
					},
				},
			},
			barFill = { kind = "nineSlice", asset = "glossy_bar_fill", direction = "ltr", fallback = "native" },

			toggleTrack = {
				kind = "nineSlice",
				asset = { default = "glossy_toggle_track_off", selected = "glossy_toggle_track_on" },
				fallback = "native",
			},
			toggleKnob = { kind = "nineSlice", asset = "glossy_toggle_knob", sliced = false, fallback = "native" },

			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "glossy_stepper_plate_default", pressed = "glossy_stepper_plate_pressed" },
				sliced = true,
				contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
				fallback = "native",
			},
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},

		icons = { ["facet:search"] = "search" },
		assets = assets,
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function glossy_touch.build(themes: any): (any, any)
	return themes.define(glossy_touch.definition(themes))
end

return glossy_touch
