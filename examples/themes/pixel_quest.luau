--!strict

local pixel_quest = {}

pixel_quest.id = "pixel-quest"
pixel_quest.displayName = "Pixel Quest"
pixel_quest.themeClasses = table.freeze({ "palette", "metrics", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local INK = rgb(22, 18, 31)
local SHADE = rgb(58, 44, 79)
local WOOD = rgb(168, 114, 47)
local TAN = rgb(215, 168, 96)
local CREAM = rgb(244, 230, 192)
local RED = rgb(122, 31, 34)
local GRN = rgb(79, 168, 63)

local LEAF = rgb(44, 104, 44)
local GOLD = rgb(224, 160, 40)

local UNIT = 4
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local SIZES = { caption = 12, label = 12, body = 16, control = 16, heading = 20, title = 28 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.25 }
	end
	return out
end

local ASSETS = {
	pixel_panel = {
		content = "rbxassetid://122249249524085",
		sliceCenter = { x0 = 24, y0 = 24, x1 = 28, y1 = 28 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_plate_default = {
		content = "rbxassetid://70509734376718",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 20, y1 = 20 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_plate_selected = {
		content = "rbxassetid://140498947277552",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 20, y1 = 20 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},

	pixel_plate_ornament = { content = "rbxassetid://112667248840646", preload = "install", fallback = "native" },
	pixel_blank = { content = "rbxassetid://98713013227633", preload = "install", fallback = "native" },
	pixel_field = {
		content = "rbxassetid://88009742569643",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 20, y1 = 20 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_stepper_plate_default = {
		content = "rbxassetid://115416309466713",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 16, y1 = 16 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_stepper_plate_pressed = {
		content = "rbxassetid://73383523712450",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 16, y1 = 16 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_bar_track = {
		content = "rbxassetid://133548434345857",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 12, y1 = 24 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_bar_fill = {
		content = "rbxassetid://118968463549709",
		sliceCenter = { x0 = 4, y0 = 4, x1 = 8, y1 = 12 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_bar_cap_heart = { content = "rbxassetid://100115790671157", preload = "install", fallback = "native" },
	pixel_toggle_track_off = {
		content = "rbxassetid://82727713033159",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 16, y1 = 20 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_toggle_track_on = {
		content = "rbxassetid://94324416211669",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 16, y1 = 20 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	pixel_toggle_knob = { content = "rbxassetid://134826235649025", preload = "install", fallback = "native" },

	pixel_icon_plus = {
		content = "rbxassetid://137937473154830",
		preload = "install",
		fallback = "native",
		tintRole = "accent",
	},
	pixel_icon_minus = {
		content = "rbxassetid://139370520867356",
		preload = "install",
		fallback = "native",
		tintRole = "accent",
	},
	pixel_icon_chevron_right = { content = "rbxassetid://135535101730897", preload = "lazy", fallback = "native" },
	pixel_icon_chevron_down = { content = "rbxassetid://135945017045204", preload = "lazy", fallback = "native" },
	pixel_icon_check = { content = "rbxassetid://93821473650946", preload = "lazy", fallback = "native" },
	pixel_icon_cross = { content = "rbxassetid://76283014616825", preload = "lazy", fallback = "native" },

	pixel_icon_chevron_left = { content = "rbxassetid://124829299432358", preload = "lazy", fallback = "native" },
	pixel_icon_chevron_up = { content = "rbxassetid://104690805635224", preload = "lazy", fallback = "native" },
	pixel_icon_chevron_up_down = { content = "rbxassetid://70666797550533", preload = "lazy", fallback = "native" },
	pixel_icon_more = { content = "rbxassetid://102030667154109", preload = "lazy", fallback = "native" },
	pixel_icon_edit = { content = "rbxassetid://120712594727107", preload = "lazy", fallback = "native" },
	pixel_icon_radio_off = { content = "rbxassetid://109254322652994", preload = "lazy", fallback = "native" },
	pixel_icon_radio_on = { content = "rbxassetid://102134502378061", preload = "lazy", fallback = "native" },
	pixel_icon_check_off = { content = "rbxassetid://111516067571262", preload = "lazy", fallback = "native" },
}

local QUEST = {
	colors = {
		surface = INK,
		surfaceStrong = SHADE,
		content = CREAM,
		contentStrong = rgb(255, 250, 235),
		accent = GRN,
		onAccent = INK,
		danger = RED,
		onDanger = CREAM,
		success = LEAF,
		onSuccess = CREAM,
		warning = GOLD,
		onWarning = INK,
	},
	extra = {
		control = WOOD,
		controlHover = TAN,
		controlPressed = rgb(107, 67, 38),

		controlSelected = rgb(163, 148, 71),
		onSelected = INK,
		contentSecondary = TAN,
		hairline = INK,
		hairlineOpacity = 0.2,
		scrimOpacity = 0.5,
		disabledContentOpacity = 0.45,

		["gauge:needle"] = rgb(142, 222, 106),
	},
}

function pixel_quest.definition(themes: any): any
	local assets = table.clone(ASSETS)

	assets.search = { content = "rbxassetid://85188541706347", tintRole = "content" }
	assets.menu = { content = "rbxassetid://119066409501208", tintRole = "content" }
	assets.flag = { content = "rbxassetid://109067109704366", tintRole = "content" }
	local inset = { top = 16, right = 16, bottom = 16, left = 16 }
	return {
		base = themes.neutralPackage(),
		identity = {
			id = pixel_quest.id,
			displayName = pixel_quest.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",

			rendering = "pixel",
			pixelUnit = UNIT,

			standardIcons = false,
		},
		style = { defaultTheme = "Quest", themes = { { name = "Quest", colors = QUEST.colors, extra = QUEST.extra } } },
		metrics = {
			typography = typography(),
			space = { xs = 4, s = 8, m = 16, l = 24, xl = 40 },
			controlSizes = {
				compact = { height = 36, paddingX = 8, iconSize = 16 },
				regular = { height = 44, paddingX = 12, iconSize = 20 },
				large = { height = 56, paddingX = 16, iconSize = 24 },

				["gauge:dial"] = { height = 48, paddingX = 12, iconSize = 20 },
			},

			iconSizes = { small = 16, medium = 32, large = 48 },
			radii = { control = 4, panel = 0, pill = 12, selection = 0, ["gauge:ring"] = 4 },
			strokes = { hairline = 4 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.08, normal = 0.14 },

			controls = {

				progress = {
					trackHeight = 28,
					rowMinHeight = 40,
					circularSize = 32,
					circularThickness = 4,
					spinnerDotSize = 8,
				},

				textInput = { fieldHeight = 76 },
			},
			insets = {
				panel = inset,
				control = inset,
				field = inset,
				selection = { top = 8, right = 8, bottom = 8, left = 8 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		chrome = {
			panel = {
				kind = "nineSlice",
				asset = "pixel_panel",
				fallback = "native",
				contentInsets = { top = 24, right = 24, bottom = 24, left = 24 },
			},

			control = {
				kind = "nineSlice",
				asset = "pixel_plate_default",
				fallback = "native",
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			},
			field = {
				kind = "nineSlice",
				asset = "pixel_field",
				fallback = "native",
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			},

			selection = {
				kind = "layered",
				fallback = "native",
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
				layers = {
					{
						kind = "fill",
						asset = { default = "pixel_plate_default", selected = "pixel_plate_selected" },
					},
					{
						kind = "corners",
						asset = { default = "pixel_blank", selected = "pixel_plate_ornament" },
						size = 8,
					},
				},
			},

			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "pixel_stepper_plate_default", pressed = "pixel_stepper_plate_pressed" },
				sliced = true,
				fallback = "native",

				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			},
			barTrack = {
				kind = "nineSlice",
				asset = "pixel_bar_track",
				fallback = "native",
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			},
			barFill = { kind = "nineSlice", asset = "pixel_bar_fill", direction = "ltr", fallback = "native" },

			barCap = {
				kind = "nineSlice",
				asset = "pixel_bar_cap_heart",
				startAsset = "pixel_bar_cap_heart",
				sliced = false,
				size = { w = 40, h = 40 },
				fallback = "native",
			},
			toggleTrack = {
				kind = "nineSlice",
				asset = { default = "pixel_toggle_track_off", selected = "pixel_toggle_track_on" },
				fallback = "native",
				contentInsets = { top = 12, right = 12, bottom = 12, left = 12 },
			},
			toggleKnob = { kind = "nineSlice", asset = "pixel_toggle_knob", sliced = false, fallback = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},

		icons = {
			["facet:search"] = "search",
			menu = "menu",
			flag = "flag",
			increment = "pixel_icon_plus",
			decrement = "pixel_icon_minus",
			["chevron.leading"] = "pixel_icon_chevron_left",
			["chevron.trailing"] = "pixel_icon_chevron_right",
			["chevron.up"] = "pixel_icon_chevron_up",
			["chevron.down"] = "pixel_icon_chevron_down",
			["chevron.up.chevron.down"] = "pixel_icon_chevron_up_down",
			checkmark = "pixel_icon_check",
			close = "pixel_icon_cross",
			more = "pixel_icon_more",
			edit = "pixel_icon_edit",
			["facet:selection.radio.off"] = "pixel_icon_radio_off",
			["facet:selection.radio.on"] = "pixel_icon_radio_on",
			["facet:selection.check.off"] = "pixel_icon_check_off",
		},
		assets = assets,
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function pixel_quest.build(themes: any): (any, any)
	return themes.define(pixel_quest.definition(themes))
end

function pixel_quest.buildWithoutIcons(themes: any): (any, any)
	local def = pixel_quest.definition(themes)
	def.identity.id = pixel_quest.id .. "-noicons"
	def.identity.standardIcons = false
	def.icons = nil
	return themes.define(def)
end

return pixel_quest
