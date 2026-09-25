--!strict

local compact_pointer = {}

compact_pointer.id = "compact-pointer"
compact_pointer.displayName = "Compact Pointer"
compact_pointer.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })
compact_pointer.pairRole = "pointer"

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local SIZES = { caption = 11, label = 12, body = 13, control = 13, heading = 17, title = 22 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.25 }
	end
	out.title.font = { family = FAMILY, weight = "SemiBold" }
	return out
end

local AQUA = {
	colors = {
		surface = rgb(238, 240, 243),
		surfaceStrong = rgb(252, 253, 255),
		content = rgb(26, 30, 36),
		contentStrong = rgb(10, 12, 16),
		accent = rgb(20, 92, 186),
		onAccent = rgb(255, 255, 255),
		danger = rgb(172, 26, 38),
		onDanger = rgb(255, 255, 255),

		success = rgb(18, 110, 66),
		onSuccess = rgb(255, 255, 255),
		warning = rgb(214, 152, 16),
		onWarning = rgb(16, 12, 2),
	},
	extra = {
		control = rgb(246, 247, 250),
		controlHover = rgb(238, 244, 252),
		controlPressed = rgb(220, 226, 234),

		controlSelected = rgb(163, 191, 230),
		contentSecondary = rgb(96, 104, 116),
		hairline = rgb(140, 148, 160),
		hairlineOpacity = 0.9,
		scrimOpacity = 0.3,
		disabledContentOpacity = 0.4,
	},
}

local ASSETS = {
	compact_panel = {
		content = "rbxassetid://113956274031174",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 36, y1 = 36 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_button_default = {
		content = "rbxassetid://125945402308792",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 14 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_button_hover = {
		content = "rbxassetid://119001630381133",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 14 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_button_pressed = {
		content = "rbxassetid://109265822114166",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 14 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_field = {
		content = "rbxassetid://90201834768221",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 14 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_bar_track = {
		content = "rbxassetid://139498496637253",
		sliceCenter = { x0 = 4, y0 = 4, x1 = 44, y1 = 6 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_bar_fill = {
		content = "rbxassetid://117421457462709",
		sliceCenter = { x0 = 3, y0 = 3, x1 = 45, y1 = 5 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_toggle_track_off = {
		content = "rbxassetid://140310035261723",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 28, y1 = 10 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_toggle_track_on = {
		content = "rbxassetid://75560406065820",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 28, y1 = 10 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_toggle_knob = { content = "rbxassetid://75181583166364", preload = "install", fallback = "native" },
	compact_stepper_plate_default = {
		content = "rbxassetid://96206949435730",
		sliceCenter = { x0 = 7, y0 = 7, x1 = 15, y1 = 15 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	compact_stepper_plate_pressed = {
		content = "rbxassetid://129313878988790",
		sliceCenter = { x0 = 7, y0 = 7, x1 = 15, y1 = 15 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
}

function compact_pointer.definition(themes: any): any
	local assets = table.clone(ASSETS)

	assets.search = { content = "rbxassetid://85188541706347", tintRole = "content" }
	return {
		base = themes.neutralPackage(),
		identity = {
			id = compact_pointer.id,
			displayName = compact_pointer.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = { defaultTheme = "Aqua", themes = { { name = "Aqua", colors = AQUA.colors, extra = AQUA.extra } } },
		metrics = {
			typography = typography(),
			space = { xs = 2, s = 6, m = 10, l = 16, xl = 24 },

			controlSizes = {
				compact = { height = 22, paddingX = 8, iconSize = 14 },
				regular = { height = 24, paddingX = 10, iconSize = 16 },
				large = { height = 30, paddingX = 12, iconSize = 18 },
			},
			iconSizes = { small = 12, medium = 16, large = 24 },
			radii = { control = 4, panel = 6, pill = 999 },

			strokes = { hairline = 1 },

			targetSizes = { minimum = 44 },
			motion = { fast = 0.1, normal = 0.16 },
			controls = {

				progress = {
					trackHeight = 10,
					rowMinHeight = 16,
					circularSize = 18,
					circularThickness = 2,
					spinnerDotSize = 5,
				},

				slider = { railHeight = 4, thumbSize = 14, readoutMinWidth = 32 },
			},
			insets = {
				panel = { top = 8, right = 8, bottom = 8, left = 8 },
				control = { top = 2, right = 6, bottom = 2, left = 6 },
				field = { top = 2, right = 6, bottom = 2, left = 6 },
				selection = { top = 2, right = 4, bottom = 2, left = 4 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		chrome = {
			panel = {
				kind = "nineSlice",
				asset = "compact_panel",
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
				fallback = "native",
			},

			control = {
				kind = "nineSlice",
				asset = {
					default = "compact_button_default",
					hover = "compact_button_hover",
					pressed = "compact_button_pressed",
				},
				contentInsets = { top = 2, right = 8, bottom = 2, left = 8 },
				fallback = "native",
			},
			field = {
				kind = "nineSlice",
				asset = "compact_field",
				contentInsets = { top = 2, right = 6, bottom = 2, left = 6 },
				fallback = "native",
			},

			selection = {
				kind = "nineSlice",
				asset = { default = "compact_button_default", selected = "compact_button_hover" },
				contentInsets = { top = 2, right = 4, bottom = 2, left = 4 },
				fallback = "native",
			},

			focus = { kind = "ring" },
			barTrack = {
				kind = "nineSlice",
				asset = "compact_bar_track",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},
			barFill = { kind = "nineSlice", asset = "compact_bar_fill", direction = "ltr", fallback = "native" },
			toggleTrack = {
				kind = "nineSlice",
				asset = { default = "compact_toggle_track_off", selected = "compact_toggle_track_on" },
				fallback = "native",
			},
			toggleKnob = { kind = "nineSlice", asset = "compact_toggle_knob", sliced = false, fallback = "native" },

			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "compact_stepper_plate_default", pressed = "compact_stepper_plate_pressed" },
				sliced = true,
				contentInsets = { top = 2, right = 2, bottom = 2, left = 2 },
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

function compact_pointer.build(themes: any): (any, any)
	return themes.define(compact_pointer.definition(themes))
end

return compact_pointer
