--!strict
-- FIXTURE THEME PACKAGE — "Fantasy Parchment (stub)".
--
-- NOT the shipping Fantasy Parchment package. That one is a later task and owns
-- the full art pass, the provenance record and the five-view Studio matrix.
-- THIS is the minimum asset-backed package the chrome substrate needs in order
-- to be tested at all: three nine-slice recipes over the three PNGs already
-- uploaded from `assets/themes/fantasy-parchment/`, plus the deliberate failure
-- variants the scenario drives.
--
-- It carries the ASSET-BACKED theme class, and it is the only reference package
-- that creates decoration instances — which is what makes the census
-- proposition ("a flat theme costs zero, an ornate one costs exactly N")
-- falsifiable rather than rhetorical.
--
-- Content IDs come from assets/themes/fantasy-parchment/upload-manifest.json.
-- Another project uploads the same repository-owned PNGs under its own account
-- and substitutes its IDs; nothing here hardcodes an ID outside package data.
--
-- Variants:
--   build(themes)            the working package
--   buildBadAsset(themes)    identical, one bogus content ID — the asset
--                            RESOLVES as style and never loads (m2), which is
--                            precisely the failure the fallback tag exists for
--   buildBadFont(themes)     identical, one unknown font family — measurement
--                            must degrade to the conservative path, never clip
--   buildIncompatible(themes) a schemaVersion this build does not speak; it
--                            must be REJECTED with a useful error, and the
--                            screen that asked for it must stay usable

local fantasy_parchment_stub = {}

-- A FIXTURE, AND IT HAS TO SAY SO. `theme_picker.isPickable` filters modules
-- that declare `testOnly`, and this one never did — so "Fantasy Parchment
-- (stub)" appeared in the showcase's theme list on a real device, one row below
-- the shipping Fantasy Parchment, offering a player a package whose whole point
-- is that some of its variants are broken on purpose. The acceptance scenarios
-- install it BY NAME, which this does not affect.
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

-- Slice geometry per the upload manifest: SliceCenter = Rect(border, border,
-- size - border, size - border), SliceScale = 1.
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
		-- lazy: a field skin is not needed until a screen with a field mounts
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
		-- the danger pair clears 4.5:1 against sheet_model's gate, which checks
		-- danger/onDanger even though `tokens.compile` (and therefore
		-- `themes.define`) does not — see the report's decision packet
		danger = rgb(150, 40, 30),
		onDanger = rgb(255, 242, 232),
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
			-- the slot's own padding; the recipes' contentInsets are ADDED to
			-- these by the snapshot, because the carved border of the art has to
			-- be cleared on top of whatever padding the slot already wanted
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

-- A content ID that resolves through the style system and never loads — the
-- exact shape feasibility m2 measured (`styledImage` set, `IsLoaded` false).
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

fantasy_parchment_stub.INCOMPATIBLE_SCHEMA = "luauui-theme/99"

function fantasy_parchment_stub.buildIncompatible(themes: any): (any, any)
	local def = fantasy_parchment_stub.definition(themes)
	def.identity.id = fantasy_parchment_stub.id .. "-incompatible"
	def.identity.schemaVersion = fantasy_parchment_stub.INCOMPATIBLE_SCHEMA
	def.compatibility = { requiresSchema = fantasy_parchment_stub.INCOMPATIBLE_SCHEMA }
	return themes.define(def)
end

return fantasy_parchment_stub
