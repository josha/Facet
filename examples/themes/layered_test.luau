--!strict
-- TEST FIXTURE THEME PACKAGE — "Layered Test" (rich-skinning-v2 package P2).
--
-- NOT a reference package. The shipping **Fantasy Ornate** package — the full
-- art pass, every v2 capability, provenance, the five-view matrix — is P5's, and
-- nothing here should be mistaken for it. This is the minimum LAYERED package
-- the adapter's ladder can be tested against at all: one slot that declares the
-- whole R1 vocabulary in one stack, one slot with per-state art (R2), one
-- selection slot whose SELECTED state is a different picture rather than a tint,
-- and one layered field so the stack-yield rule has a TextBox to yield for.
--
-- It exists so the acceptance rows RS-A1..RS-A4 are falsifiable on a running
-- screen: a census that counts nothing, a suppression that misses a slot, a
-- state that paints the wrong art, or a yield that never flips all show up here
-- rather than in a capture nobody can diff.
--
-- Art is the repository's own `assets/themes/fantasy-ornate/` PNGs (provenance
-- in that folder); content IDs come from its `upload-manifest.json` and are
-- never hardcoded anywhere but this package's `assets` table.
--
-- Variants:
--   build(themes)           the working layered package
--   buildBadLayer(themes)   identical, one bogus content ID on a MIDDLE layer —
--                           the whole stack must fall back as a unit, because a
--                           half-painted ladder reads as broken rather than
--                           degraded

local layered_test = {}

layered_test.id = "layered-test"
layered_test.displayName = "Layered Test"
layered_test.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })
-- said out loud so no reader, and no later package sweep, mistakes this for the
-- Fantasy Ornate reference package
layered_test.testOnly = true

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

-- Slice geometry per assets/themes/fantasy-ornate/upload-manifest.json:
-- SliceCenter = Rect(border, border, W - border, H - border), SliceScale = 1.
-- A tile/ornament/plaque asset declares no slice centre because it is never
-- sliced (guessing one smears the centre pixel across the middle).
local ASSETS = {
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
	ornate_velvet_tile = { content = "rbxassetid://117354814510719", preload = "install", fallback = "native" },
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
		sliceCenter = { x0 = 12, y0 = 12, x1 = 52, y1 = 52 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	ornate_selection_selected = {
		content = "rbxassetid://74679464509477",
		sliceCenter = { x0 = 12, y0 = 12, x1 = 52, y1 = 52 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	-- ===== IMAGE VALUE DISPLAYS (ADR-0020 R3, package P3) ==================
	-- The track and the fill STRETCH, so both are nine-sliced; the caps, the
	-- crown, the knob and the plates are fixed-size tokens painted whole (a slice
	-- centre on a 28px jewel smears its one centre pixel across the middle).
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
}

local ORNATE = {
	colors = {
		surface = rgb(34, 26, 20),
		surfaceStrong = rgb(58, 44, 32),
		content = rgb(244, 232, 204),
		contentStrong = rgb(254, 248, 232),
		accent = rgb(202, 158, 72),
		onAccent = rgb(30, 20, 8),
		danger = rgb(150, 40, 30),
		onDanger = rgb(255, 242, 232),
	},
	extra = {
		control = rgb(80, 60, 40),
		controlHover = rgb(98, 76, 50),
		controlPressed = rgb(62, 46, 30),
		controlSelected = rgb(110, 84, 42),
		contentSecondary = rgb(198, 178, 142),
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

-- THE STACK. Every R1 kind in one slot and in a deliberate order, so the ZIndex
-- ladder is visible as a picture rather than as a number: velvet under the
-- parchment fill, the carved frame above both, rails inside it, four DIFFERENT
-- corner ornaments (per-corner overrides — the compound-tag isolation rs-m2
-- measured), and a plaque that overhangs the top edge by half its height.
local PANEL_LAYERS = {
	{ kind = "tile", asset = "ornate_velvet_tile", tileSize = { w = 64, h = 64 } },
	{ kind = "fill", asset = "ornate_panel_fill" },
	{ kind = "frame", asset = "ornate_panel_frame" },
	{ kind = "edges", asset = "ornate_edge_rail", sides = { "top", "bottom" }, thickness = 12, margin = 40, tile = 64 },
	{
		kind = "corners",
		asset = "ornate_corner_tl",
		size = 28,
		topLeft = "ornate_corner_tl",
		topRight = "ornate_corner_tr",
		bottomLeft = "ornate_corner_bl",
		bottomRight = "ornate_corner_br",
	},
	-- the NAMEPLATE. `text = true` moves the decorated node's own label onto the
	-- plaque (ADR-0020 R1's sub-slot), and `textInsets` keeps the carved border
	-- off it: the plate is 176x40 with a ~14px scrolled edge left and right and a
	-- little more headroom above the baseline than below.
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

function layered_test.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = layered_test.id,
			displayName = layered_test.displayName,
			schemaVersion = themes.SCHEMA,
			version = "0.1.0",
		},
		style = {
			defaultTheme = "Ornate",
			themes = { { name = "Ornate", colors = ORNATE.colors, extra = ORNATE.extra } },
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
			-- the whole R1 vocabulary, one slot (RS-A2)
			panel = {
				kind = "layered",
				contentInsets = { top = 28, right = 28, bottom = 28, left = 28 },
				fallback = "native",
				layers = copy(PANEL_LAYERS),
			},
			-- PER-STATE ART, not a tint (RS-A3). A two-layer ladder so the state
			-- swap is proven ON a stack rather than only on a single decoration.
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
							-- `error` has no engine state: it rides facet-state-error
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
					-- THE PLAQUE NAMEPLATE (R1's `text` sub-slot). It rides the
					-- CONTROL slot rather than the panel because a nameplate needs a
					-- node that actually has text, and a panel is a Frame — which is
					-- precisely why the sub-slot could ship "validated, documented
					-- and read by nothing" (architecture verifier F2). Here a
					-- Button's own label lifts onto the plate, inset off its border.
					{
						kind = "plaque",
						asset = "ornate_plaque",
						size = { w = 120, h = 28 },
						edge = "top",
						overhang = 10,
						text = true,
						textInsets = { top = 4, right = 12, bottom = 3, left = 12 },
					},
				},
			},
			-- "selection changes the whole style", the pixel reference's idiom:
			-- a different PICTURE for `selected`, with the tint rule still on top
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
			-- a LAYERED field, so the stack-yield rules have a TextBox to yield for
			field = {
				kind = "layered",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
				layers = { { kind = "fill", asset = "ornate_field" } },
			},
			-- a THEMED slider thumb, so the rung-2 comparison (RS-A4) is
			-- "the view's art beat the THEME's art on this node", not
			-- "the view's art appeared where the theme had none"
			sliderThumb = { kind = "nineSlice", asset = "ornate_button_default", sliced = false, fallback = "native" },
			sliderTrack = {
				kind = "nineSlice",
				asset = "ornate_field",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},
			-- ===== IMAGE VALUE DISPLAYS (RS-A5, RS-A6) =====================
			-- THE BAR FAMILY. The track is a carved rail; the fill is a sliced
			-- gold band revealed through the adapter's clip window at FULL TRACK
			-- SIZE, so its texture and its slice geometry are byte-stable from 1%
			-- to 100% (rs-m4). The caps and the crown are anchored to the TRACK, so
			-- they survive every percent — which is the whole reason they are
			-- separate ornaments rather than part of the fill art.
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
			-- THE SLIDING SWITCH. Per-state art on BOTH slots: the track's ON state
			-- is a different PICTURE (not a tint), and the knob has its own pressed
			-- art. `togglePalette` remains the flat truth — a package that declares
			-- neither of these renders exactly today's palette-true switch.
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
			-- THE STEPPER PLATE, per state. The glyph itself stays TEXT: semantic
			-- icons are ADR-0020 R4 and build package P4.
			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "ornate_stepper_plate_default", pressed = "ornate_stepper_plate_pressed" },
				contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
				fallback = "native",
			},
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		assets = copy(ASSETS),
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function layered_test.build(themes: any): (any, any)
	return themes.define(layered_test.definition(themes))
end

-- The layer whose art is deliberately broken, and the asset NAME the scenario
-- reports to the adapter's resource seam. A MIDDLE layer on purpose: a stack
-- that fails only at its back would hide the "one broken layer fails the stack"
-- rule behind the layer that happens to carry the native fallback fill.
layered_test.BOGUS_CONTENT_ID = "rbxassetid://1"
layered_test.BROKEN_ASSET = "ornate_panel_frame"

function layered_test.buildBadLayer(themes: any): (any, any)
	local def = layered_test.definition(themes)
	def.identity.id = layered_test.id .. "-badlayer"
	def.identity.displayName = layered_test.displayName .. " — broken layer"
	def.assets[layered_test.BROKEN_ASSET].content = layered_test.BOGUS_CONTENT_ID
	return themes.define(def)
end

return layered_test
