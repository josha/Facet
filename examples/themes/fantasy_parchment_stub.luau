--!strict

local fantasy_parchment_stub = {}

fantasy_parchment_stub.testOnly = true

fantasy_parchment_stub.id = "fantasy-parchment-stub"
fantasy_parchment_stub.displayName = "Fantasy Parchment (stub)"
fantasy_parchment_stub.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/Fondamento.json"
local SIZES = { caption = 12, label = 14, body = 16, control = 17, heading = 22, title = 28 }

local function typography(family: string): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = family }, size = size, lineHeight = 1.35 }
	end
	return out
end

local ASSETS = {
	parchment_panel = {
		contentId = "rbxassetid://78012779616687",
		sliceCenter = { x0 = 40, y0 = 40, x1 = 104, y1 = 104 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	parchment_button = {
		contentId = "rbxassetid://87220434497053",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	parchment_field = {
		contentId = "rbxassetid://73053023436561",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,

		preload = "lazy",
		fallback = "native",
	},
}

local PARCHMENT = {
	colors = {
		surface = rgb(48, 36, 26),
		surfaceStrong = rgb(72, 55, 38),
		content = rgb(242, 228, 198),
		contentStrong = rgb(252, 244, 224),
		accent = rgb(196, 148, 62),
		onAccent = rgb(32, 22, 10),

		danger = rgb(150, 40, 30),
		onDanger = rgb(255, 242, 232),

		success = rgb(132, 158, 74),
		onSuccess = rgb(32, 22, 10),
		warning = rgb(206, 152, 58),
		onWarning = rgb(32, 22, 10),
	},
	extra = {
		control = rgb(86, 66, 44),
		controlHover = rgb(102, 80, 54),
		controlPressed = rgb(66, 50, 34),
		controlSelected = rgb(112, 86, 44),
		contentSecondary = rgb(196, 176, 142),
		hairline = rgb(226, 200, 150),
		hairlineOpacity = 0.7,
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.45,
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

function fantasy_parchment_stub.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = fantasy_parchment_stub.id,
			displayName = fantasy_parchment_stub.displayName,
			schemaVersion = themes.SCHEMA,
			version = "0.1.0",
		},
		style = {
			defaultTheme = "Parchment",
			themes = { { name = "Parchment", colors = PARCHMENT.colors, extra = PARCHMENT.extra } },
		},
		metrics = {
			typography = typography(FAMILY),
			space = { xs = 4, s = 8, m = 16, l = 26, xl = 42 },
			controlSizes = {
				compact = { height = 38, paddingX = 14, iconSize = 18 },
				regular = { height = 46, paddingX = 18, iconSize = 22 },
				large = { height = 58, paddingX = 22, iconSize = 26 },
			},
			radii = { control = 6, panel = 10, pill = 999 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.14, normal = 0.24 },

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
			panel = {
				kind = "nineSlice",
				asset = "parchment_panel",
				contentInsets = { top = 18, right = 18, bottom = 18, left = 18 },
				fallback = "native",
			},
			control = {
				kind = "nineSlice",
				asset = "parchment_button",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
			},
			field = {
				kind = "nineSlice",
				asset = "parchment_field",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
			},
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		assets = copy(ASSETS),
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function fantasy_parchment_stub.build(themes: any): (any, any)
	return themes.define(fantasy_parchment_stub.definition(themes))
end

fantasy_parchment_stub.BOGUS_CONTENT_ID = "rbxassetid://1"

function fantasy_parchment_stub.buildBadAsset(themes: any): (any, any)
	local def = fantasy_parchment_stub.definition(themes)
	def.identity.id = fantasy_parchment_stub.id .. "-badasset"
	def.identity.displayName = fantasy_parchment_stub.displayName .. " — missing asset"
	def.assets.parchment_panel.contentId = fantasy_parchment_stub.BOGUS_CONTENT_ID
	return themes.define(def)
end

fantasy_parchment_stub.UNKNOWN_FONT_FAMILY = "rbxasset://fonts/families/NotAShippedFamily.json"

function fantasy_parchment_stub.buildBadFont(themes: any): (any, any)
	local def = fantasy_parchment_stub.definition(themes)
	def.identity.id = fantasy_parchment_stub.id .. "-badfont"
	def.identity.displayName = fantasy_parchment_stub.displayName .. " — missing font"
	def.metrics.typography = typography(fantasy_parchment_stub.UNKNOWN_FONT_FAMILY)
	return themes.define(def)
end

fantasy_parchment_stub.INCOMPATIBLE_SCHEMA = "facet-theme/99"

function fantasy_parchment_stub.buildIncompatible(themes: any): (any, any)
	local def = fantasy_parchment_stub.definition(themes)
	def.identity.id = fantasy_parchment_stub.id .. "-incompatible"
	def.identity.schemaVersion = fantasy_parchment_stub.INCOMPATIBLE_SCHEMA
	def.compatibility = { requiresSchema = fantasy_parchment_stub.INCOMPATIBLE_SCHEMA }
	return themes.define(def)
end

return fantasy_parchment_stub
