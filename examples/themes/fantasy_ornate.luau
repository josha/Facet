--!strict

local fantasy_ornate = {}

fantasy_ornate.id = "fantasy-ornate"
fantasy_ornate.displayName = "Fantasy Ornate"

fantasy_ornate.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/Fondamento.json"
local SIZES = { caption = 12, label = 14, body = 16, control = 17, heading = 22, title = 28 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.35 }
	end
	return out
end

local GRAND_HALL = {
	colors = {
		surface = rgb(46, 34, 24),
		surfaceStrong = rgb(66, 50, 34),
		content = rgb(246, 234, 206),
		contentStrong = rgb(255, 250, 236),
		accent = rgb(214, 170, 82),
		onAccent = rgb(32, 22, 8),
		danger = rgb(158, 46, 34),
		onDanger = rgb(255, 242, 232),

		success = rgb(84, 108, 44),
		onSuccess = rgb(255, 242, 232),
		warning = rgb(214, 150, 54),
		onWarning = rgb(38, 26, 8),
	},
	extra = {
		control = rgb(84, 62, 42),
		controlHover = rgb(104, 80, 52),
		controlPressed = rgb(64, 48, 32),

		controlSelected = rgb(38, 74, 50),
		contentSecondary = rgb(206, 186, 148),
		hairline = rgb(226, 200, 150),
		hairlineOpacity = 0.7,
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.45,

		focusGlow = rgb(248, 206, 108),

		["gauge:needle"] = rgb(255, 214, 128),
	},
}

local CRYPT = {
	colors = {
		surface = rgb(26, 30, 38),
		surfaceStrong = rgb(40, 46, 56),
		content = rgb(222, 230, 240),
		contentStrong = rgb(242, 248, 255),
		accent = rgb(126, 176, 178),
		onAccent = rgb(10, 18, 20),
		danger = rgb(154, 52, 62),
		onDanger = rgb(255, 238, 240),

		success = rgb(92, 150, 110),
		onSuccess = rgb(10, 18, 20),
		warning = rgb(198, 158, 78),
		onWarning = rgb(16, 20, 26),
	},
	extra = {
		control = rgb(52, 60, 72),
		controlHover = rgb(66, 76, 90),
		controlPressed = rgb(38, 44, 54),

		controlSelected = rgb(33, 75, 58),
		contentSecondary = rgb(168, 184, 200),
		hairline = rgb(150, 176, 186),
		hairlineOpacity = 0.6,
		scrimOpacity = 0.62,
		disabledContentOpacity = 0.45,
		focusGlow = rgb(146, 214, 232),

		["gauge:needle"] = rgb(168, 226, 240),
	},
}

local ASSETS = {

	ornate_velvet_tile = { content = "rbxassetid://117354814510719", preload = "install", fallback = "native" },
	ornate_panel_fill = {
		content = "rbxassetid://81048500362779",
		sliceCenter = { x0 = 32, y0 = 32, x1 = 96, y1 = 96 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_panel_frame = {
		content = "rbxassetid://104827392559065",
		sliceCenter = { x0 = 40, y0 = 40, x1 = 120, y1 = 120 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_edge_rail = { content = "rbxassetid://138849576571840", preload = "install", fallback = "native" },
	ornate_corner_tl = { content = "rbxassetid://83669367091366", preload = "install", fallback = "native" },
	ornate_corner_tr = { content = "rbxassetid://108150811338158", preload = "install", fallback = "native" },
	ornate_corner_bl = { content = "rbxassetid://130569583845489", preload = "install", fallback = "native" },
	ornate_corner_br = { content = "rbxassetid://86251498610726", preload = "install", fallback = "native" },
	ornate_plaque = { content = "rbxassetid://117707325909741", preload = "install", fallback = "native" },

	ornate_button_default = {
		content = "rbxassetid://112835782358182",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_button_hover = {
		content = "rbxassetid://127234850374967",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_button_pressed = {
		content = "rbxassetid://90667263700535",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_field = {
		content = "rbxassetid://106727123624605",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_selection_default = {
		content = "rbxassetid://101901876687967",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_selection_selected = {
		content = "rbxassetid://74679464509477",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},

	ornate_bar_track = {
		content = "rbxassetid://92904178783883",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 84, y1 = 16 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_bar_fill = {
		content = "rbxassetid://111942785128400",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 88, y1 = 12 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_bar_cap_start = { content = "rbxassetid://113767043260178", preload = "install", fallback = "native" },
	ornate_bar_cap_end = { content = "rbxassetid://86593934806842", preload = "install", fallback = "native" },
	ornate_bar_center = { content = "rbxassetid://73806369333659", preload = "install", fallback = "native" },
	ornate_toggle_track_off = {
		content = "rbxassetid://79434491980979",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_toggle_track_on = {
		content = "rbxassetid://108473944163690",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_toggle_knob_default = { content = "rbxassetid://75192659975960", preload = "install", fallback = "native" },
	ornate_toggle_knob_pressed = { content = "rbxassetid://119648517302972", preload = "install", fallback = "native" },
	ornate_stepper_plate_default = {
		content = "rbxassetid://99012630527588",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 28, y1 = 28 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_stepper_plate_pressed = {
		content = "rbxassetid://78661159227432",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 28, y1 = 28 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},

	ornate_icon_plus = {
		content = "rbxassetid://137432148053328",
		preload = "install",
		fallback = "native",
		tintRole = "accent",
	},
	ornate_icon_minus = {
		content = "rbxassetid://85685383372532",
		preload = "install",
		fallback = "native",
		tintRole = "accent",
	},
	ornate_icon_chevron_right = {
		content = "rbxassetid://105245349364481",
		preload = "lazy",
		fallback = "native",
		tintRole = "content",
	},
	ornate_icon_chevron_down = {
		content = "rbxassetid://115385031782859",
		preload = "lazy",
		fallback = "native",
		tintRole = "content",
	},
	ornate_icon_check = {
		content = "rbxassetid://107294339133126",
		preload = "lazy",
		fallback = "native",
		tintRole = "content",
	},
	ornate_icon_cross = {
		content = "rbxassetid://102422912531329",
		preload = "lazy",
		fallback = "native",
		tintRole = "content",
	},
	ornate_icon_gear = {
		content = "rbxassetid://136119216057736",
		preload = "lazy",
		fallback = "native",
		tintRole = "content",
	},
}

local PANEL_LAYERS = {
	{ kind = "tile", asset = "ornate_velvet_tile", tileSize = { w = 64, h = 64 } },
	{ kind = "fill", asset = "ornate_panel_fill" },
	{ kind = "frame", asset = "ornate_panel_frame" },

	{ kind = "edges", asset = "ornate_edge_rail", sides = { "top", "bottom" }, thickness = 12, margin = 44, tile = 64 },
	{
		kind = "corners",
		asset = "ornate_corner_tl",
		size = 30,

		topLeft = "ornate_corner_tl",
		topRight = "ornate_corner_tr",
		bottomLeft = "ornate_corner_bl",
		bottomRight = "ornate_corner_br",
	},

	{
		kind = "plaque",
		asset = "ornate_plaque",
		size = { w = 176, h = 40 },
		edge = "top",
		overhang = 20,
		text = true,
		textInsets = { top = 8, right = 16, bottom = 6, left = 16 },
	},
}

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out: any = {}
	for k, inner in v do
		out[k] = copy(inner)
	end
	return out
end

function fantasy_ornate.definition(themes: any): any
	return {

		base = themes.neutralPackage(),
		identity = {
			id = fantasy_ornate.id,
			displayName = fantasy_ornate.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Grand Hall",
			themes = {
				{ name = "Grand Hall", colors = GRAND_HALL.colors, extra = GRAND_HALL.extra },
				{ name = "Crypt", colors = CRYPT.colors, extra = CRYPT.extra },
			},
		},
		metrics = {
			typography = typography(),

			space = { xs = 4, s = 8, m = 16, l = 26, xl = 42 },
			controlSizes = {
				compact = { height = 38, paddingX = 14, iconSize = 18 },
				regular = { height = 46, paddingX = 18, iconSize = 22 },
				large = { height = 58, paddingX = 22, iconSize = 26 },

				["gauge:dial"] = { height = 56, paddingX = 18, iconSize = 22 },
			},

			iconSizes = { small = 20, medium = 32, large = 48 },

			radii = { control = 6, panel = 10, pill = 999, selection = 0, ["gauge:ring"] = 8 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.14, normal = 0.24 },

			controls = {

				progress = {
					trackHeight = 28,
					rowMinHeight = 36,
					circularSize = 44,
					circularThickness = 8,
					spinnerDotSize = 12,
				},
				slider = { railHeight = 24, thumbSize = 28, readoutMinWidth = 44 },
			},
			insets = {
				panel = { top = 8, right = 8, bottom = 8, left = 8 },
				control = { top = 4, right = 8, bottom = 4, left = 8 },
				field = { top = 4, right = 8, bottom = 4, left = 8 },
				selection = { top = 4, right = 6, bottom = 4, left = 6 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		chrome = {

			navigation = {
				kind = "nineSlice",
				asset = "ornate_selection_default",
				contentInsets = { top = 6, right = 12, bottom = 6, left = 12 },
				fallback = "native",
			},

			panel = {
				kind = "layered",
				contentInsets = { top = 30, right = 30, bottom = 30, left = 30 },
				fallback = "native",
				layers = copy(PANEL_LAYERS),

				shadow = "raised",
			},

			control = {
				kind = "layered",
				contentInsets = { top = 10, right = 14, bottom = 10, left = 14 },
				fallback = "native",
				layers = {
					{
						kind = "fill",
						asset = {
							default = "ornate_button_default",
							hover = "ornate_button_hover",
							pressed = "ornate_button_pressed",
							error = "ornate_selection_selected",
						},
					},

					{
						kind = "corners",
						asset = "ornate_corner_tl",
						size = 14,
						topLeft = "ornate_corner_tl",
						topRight = "ornate_corner_tr",
					},
				},
				shadow = "raised",
			},

			field = {
				kind = "layered",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
				layers = { { kind = "fill", asset = "ornate_field" } },
			},

			selection = {
				kind = "layered",
				contentInsets = { top = 6, right = 8, bottom = 6, left = 8 },
				fallback = "native",
				layers = {
					{
						kind = "fill",
						asset = { default = "ornate_selection_default", selected = "ornate_selection_selected" },
					},
				},
			},

			focus = {
				kind = "glow",
				color = "$FocusGlow",
				blurRadius = { scale = 0, offset = 26 },
				transparency = 0.25,
				zIndex = -1,
			},

			sliderTrack = {
				kind = "nineSlice",
				asset = "ornate_bar_track",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},
			sliderThumb = {
				kind = "nineSlice",
				asset = "ornate_toggle_knob_default",
				sliced = false,
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},

			badge = {
				kind = "nineSlice",
				asset = "ornate_bar_center",
				sliced = false,
				contentInsets = { top = 5, right = 5, bottom = 5, left = 5 },
				fallback = "native",
			},

			barTrack = {
				kind = "nineSlice",
				asset = "ornate_bar_track",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},
			barFill = { kind = "nineSlice", asset = "ornate_bar_fill", direction = "ltr", fallback = "native" },
			barCap = {
				kind = "nineSlice",
				asset = "ornate_bar_cap_start",
				startAsset = "ornate_bar_cap_start",
				endAsset = "ornate_bar_cap_end",
				size = { w = 28, h = 36 },
				fallback = "native",
			},
			barCenter = {
				kind = "nineSlice",
				asset = "ornate_bar_center",
				size = { w = 36, h = 28 },
				fallback = "native",
			},

			toggleTrack = {
				kind = "nineSlice",
				asset = { default = "ornate_toggle_track_off", selected = "ornate_toggle_track_on" },
				fallback = "native",
			},
			toggleKnob = {
				kind = "nineSlice",
				asset = { default = "ornate_toggle_knob_default", pressed = "ornate_toggle_knob_pressed" },
				fallback = "native",
			},

			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "ornate_stepper_plate_default", pressed = "ornate_stepper_plate_pressed" },
				sliced = true,
				contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
				fallback = "native",
			},

			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},

		icons = {
			increment = "ornate_icon_plus",
			decrement = "ornate_icon_minus",
			["chevron.trailing"] = "ornate_icon_chevron_right",
			["chevron.down"] = "ornate_icon_chevron_down",
			checkmark = "ornate_icon_check",
			close = "ornate_icon_cross",
			["ornate:settings"] = "ornate_icon_gear",
		},
		assets = copy(ASSETS),
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function fantasy_ornate.build(themes: any): (any, any)
	return themes.define(fantasy_ornate.definition(themes))
end

fantasy_ornate.BOGUS_CONTENT_ID = "rbxassetid://1"
fantasy_ornate.BROKEN_ASSET = "ornate_panel_frame"

function fantasy_ornate.buildBadLayer(themes: any): (any, any)
	local def = fantasy_ornate.definition(themes)
	def.identity.id = fantasy_ornate.id .. "-badlayer"
	def.identity.displayName = fantasy_ornate.displayName .. " — broken layer"
	def.assets[fantasy_ornate.BROKEN_ASSET].content = fantasy_ornate.BOGUS_CONTENT_ID
	return themes.define(def)
end

return fantasy_ornate
