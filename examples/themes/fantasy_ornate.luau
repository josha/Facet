--!strict
-- "FANTASY ORNATE" — the rich-skinning-v2 centerpiece reference package
-- (ADR-0020, ledger row RS-A12). The claim it exists to make falsifiable:
--
--   a heavily stylized game can make EVERY visible part of its UI artwork
--   through the public `Facet.themes` surface alone.
--
-- Written as a CLEAN CONSUMER, exactly like `fantasy_parchment.luau`: the only
-- framework contact is `themes.define` and `themes.neutralPackage()`. There is
-- no internal require in this file, and there must never be one — a reference
-- package that reaches into `src/` proves the public API is insufficient rather
-- than sufficient, which is the opposite of the acceptance claim.
--
-- WHERE EACH v2 CAPABILITY IS EXERCISED (the cross-reference the gate and the
-- verifiers read is `artifacts/rich-skinning-v2/rs-a12-fantasy-ornate.json`;
-- this list is the same map in the place an author reads it):
--
--   R9  image-is-the-element   every skinned slot below; the native plate,
--                              corner and stroke are suppressed under all of it
--   R1  layered slots          `panel` — six layers, the WHOLE vocabulary:
--                              tile → fill → frame → edges → corners → plaque
--   R1  layered slots (again)  `control`, `field`, `selection` — smaller stacks,
--                              so the ladder is proven on more than one shape
--   R2  per-state variants     `control` (default/hover/pressed/error),
--                              `selection` (default/selected), `toggleTrack`,
--                              `toggleKnob`, `stepperPlate`
--   R3  image value displays   `barTrack` + `barFill` + `barCap` (two ends) +
--                              `barCenter`; `stepperPlate`; `toggleTrack`/`Knob`
--   R4  semantic icons         `icons` below: six framework names, one
--                              NAMESPACED name, and two names left UNMAPPED on
--                              purpose so the fallback glyph is proven here too
--   R5  pixel mode             deliberately NOT this package (it is a smooth,
--                              painterly skin). `pixel_quest.luau` owns R5.
--   R6  content adoption       every asset below uses the canonical `content`
--                              field; `contentId` is the alias and
--                              `content_alias_test.luau` proves they agree
--   R7  selectBy               deliberately NOT this package. The platform pair
--                              (`glossy_touch` + `compact_pointer`) owns R7.
--   R8  the ladder             rung 1 IS this file; rung 2 is a per-view prop
--                              and rung 3 is `ornate_gauge.luau`, whose
--                              namespaced roles THIS package covers
--   R11 tiled textures         `panel`'s velvet `tile` layer and the tiled
--                              `edges` rail
--
-- ART: `assets/themes/fantasy-ornate/` — original, repository-owned,
-- procedurally generated (provenance.md records the generator, the seed and how
-- to regenerate; upload-manifest.json records the content IDs this file uses).
-- No third-party imagery and no trade dress. Another project uploads the same
-- PNGs under its own account and substitutes its own IDs.
--
-- TWO THEMES, one art set (ADR-0019: art is package data, palette is per theme).
-- "Grand Hall" is the torch-lit great room; "Crypt" is the same architecture
-- underground — colder, dimmer, blue-lit. Both clear the 4.5:1 gate `define`
-- enforces, and each names its own `focusGlow`, because a halo has to out-value
-- the surface it sits on and those two surfaces are nothing alike.

local fantasy_ornate = {}

fantasy_ornate.id = "fantasy-ornate"
fantasy_ornate.displayName = "Fantasy Ornate"
-- all four theme classes: palette, metrics, font (Fondamento) and assets
fantasy_ornate.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local FAMILY = "rbxasset://fonts/families/Fondamento.json"
local SIZES = { caption = 12, label = 14, body = 16, control = 17, heading = 22, title = 28 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		-- a calligraphic face needs more air between lines than a UI sans
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.35 }
	end
	return out
end

-- ===== the palettes ========================================================

-- GRAND HALL: torch-lit oak and burnished gold. The accent is bright enough to
-- read as gilding against the dark timber the art is painted in.
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
	},
	extra = {
		control = rgb(84, 62, 42),
		controlHover = rgb(104, 80, 52),
		controlPressed = rgb(64, 48, 32),
		-- WHAT THE SELECTED ART ACTUALLY PAINTS (director finding 12, 2026-07-26).
		-- This declared a burnished gold while `ornate_selection_selected.png` — the
		-- picture the `selection` recipe names for `selected` — is a dark emerald
		-- field. The framework resolves the selected LABEL's colour by contrast
		-- against this number, so the pairing was computed against a plate nobody
		-- sees, and this is also the colour painted when the art is absent. It is now
		-- the art's sampled centre (`tools/sample_plates.py`, rgb(40, 84, 65))
		-- multiplied by this theme's own `$ChromeTintSelected`, which is the tint
		-- every selected skinned plate carries.
		controlSelected = rgb(38, 74, 50),
		contentSecondary = rgb(206, 186, 148),
		hairline = rgb(226, 200, 150),
		hairlineOpacity = 0.7,
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.45,
		-- FOCUS GLOW, per theme. A ring is a UI element; this skin is carved and
		-- painted, so focus is a halo of the same light the room is lit with.
		focusGlow = rgb(248, 206, 108),
		-- A CONTRIBUTED CONTROL'S ROLE (ADR-0020 R8, rung 3). `examples/themes/
		-- ornate_gauge.luau` is not a framework control, so it asks for its paint
		-- by a NAMESPACED name and this package answers. Torchlight amber here.
		["gauge:needle"] = rgb(255, 214, 128),
	},
}

-- CRYPT: the same masonry below ground. Cold slate, verdigris bronze, and a
-- pale blue witch-light — re-picked rather than inherited, which is the whole
-- reason `focusGlow` is a per-theme role.
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
	},
	extra = {
		control = rgb(52, 60, 72),
		controlHover = rgb(66, 76, 90),
		controlPressed = rgb(38, 44, 54),
		-- the same emerald plate under Crypt's colder tint (see Grand Hall above)
		controlSelected = rgb(33, 75, 58),
		contentSecondary = rgb(168, 184, 200),
		hairline = rgb(150, 176, 186),
		hairlineOpacity = 0.6,
		scrimOpacity = 0.62,
		disabledContentOpacity = 0.45,
		focusGlow = rgb(146, 214, 232),
		-- the same contributed role, re-picked rather than inherited: witch-light
		["gauge:needle"] = rgb(168, 226, 240),
	},
}

-- ===== the art table (R6: `content` is the canonical field) =================
--
-- Slice geometry is package data and comes straight from the upload manifest:
-- `SliceCenter = Rect(border, border, W - border, H - border)`, `SliceScale = 1`.
-- An asset with NO slice centre is never sliced — an ornament, a cap, a knob and
-- a plaque are fixed-size tokens, and guessing a centre for one smears its
-- middle pixel across the whole middle band.
local ASSETS = {
	-- ---- the panel stack --------------------------------------------------
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
	-- ---- interactive chrome ------------------------------------------------
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
	-- ---- the value displays ------------------------------------------------
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
	-- ---- the icon set (R4) -------------------------------------------------
	-- Near-white glyphs on transparency, so `tintRole` can take them the whole
	-- way to the theme's colour rather than half of it. The two STEPPER glyphs
	-- name `accent` and the rest name `content`: a stepper's +/- is an action and
	-- the theme's gilding is where the eye goes, while a chevron or a tick is
	-- part of the sentence it sits in and should read as text.
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

-- ===== THE PANEL STACK (R1: the whole layer vocabulary in one slot) ========
--
-- Z-ORDER IS ARRAY ORDER. Read top to bottom and it is the picture: velvet
-- behind everything, the parchment field over it, the carved frame over that,
-- rails inset from the frame, four DIFFERENT corner ornaments pinned at the
-- corners, and a title board that OVERHANGS the top edge by half its height.
--
-- Six layers, not eight. The cap is 8 and every layer is a real instance per
-- decorated node (RS-A17 counts them), so a stack is a budget rather than a
-- canvas: the constant parts of an ornate frame belong in one painted asset.
local PANEL_LAYERS = {
	{ kind = "tile", asset = "ornate_velvet_tile", tileSize = { w = 64, h = 64 } },
	{ kind = "fill", asset = "ornate_panel_fill" },
	{ kind = "frame", asset = "ornate_panel_frame" },
	-- the rail is TILED (`tile = 64`), not stretched: a repeating gilt pattern
	-- that is nine-sliced turns into one smeared centre run
	{ kind = "edges", asset = "ornate_edge_rail", sides = { "top", "bottom" }, thickness = 12, margin = 44, tile = 64 },
	{
		kind = "corners",
		asset = "ornate_corner_tl",
		size = 30,
		-- per-corner overrides: four ornaments that are genuinely different
		-- pieces, which is what the compound-tag isolation exists for
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
		-- start from the library's own package, so roles a later Facet adds are
		-- inherited through a diagnosed upgrade rather than missing silently
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
			-- a rounder rhythm than Studio Neutral's: carved borders need room
			space = { xs = 4, s = 8, m = 16, l = 26, xl = 42 },
			controlSizes = {
				compact = { height = 38, paddingX = 14, iconSize = 18 },
				regular = { height = 46, paddingX = 18, iconSize = 22 },
				large = { height = 58, paddingX = 22, iconSize = 26 },
				-- A CONTRIBUTED CONTROL'S METRIC (rung 3). `define` passes a
				-- namespaced key through unvalidated on purpose, and
				-- `themes.checkCoverage` is what tells the gauge's author, before
				-- Play, that this package covers it. 56 because the gauge's brass
				-- rails need more room than a button does.
				["gauge:dial"] = { height = 56, paddingX = 18, iconSize = 22 },
			},
			-- ICON SIZES (R4) ride the SNAPSHOT, so a metric package resizes every
			-- icon at once. 32px is this art's authored size — 1:1, no resample.
			iconSizes = { small = 20, medium = 32, large = 48 },
			-- `gauge:ring` is the third contribution kind (`number`): a plain
			-- namespaced value in a metric section the schema leaves open.
			radii = { control = 6, panel = 10, pill = 999, ["gauge:ring"] = 8 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.14, normal = 0.24 },
			-- THE ART'S OWN HEIGHTS. Both of these default to 6 in Studio Neutral,
			-- which is thinner than this package's carved rail is even ALLOWED to
			-- draw: the track PNG is 28px tall with a 12px slice border, so at 6 the
			-- two borders have 6px between them and the engine squeezes the whole
			-- carving into a smear. A rail that is art rather than a coloured line
			-- has a minimum height, and it is a metric.
			controls = {
				-- ...and the two theme-sized indicators, at the SAME weight as the
				-- carved rail above (director round 2026-08-14). Everything this
				-- package draws is heavy — a 28px trough, a 28px jewelled thumb — and
				-- an indicator inherited off the space scale came out 26px with a 4px
				-- stroke, which reads as a different package's ring dropped into this
				-- one. 44 is the largest ring in the corpus and 8 is the thickest
				-- stroke the geometry allows (the arc sits at 0.8 of the half-extent,
				-- so 0.2 x 44 is the stroke's whole budget); the 12px dot is the
				-- gilded stud that budget implies.
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
			-- THE SIX-LAYER PANEL. `contentInsets` clears the frame's painted
			-- border AND the rails inside it, so content never sits on the gilding.
			panel = {
				kind = "layered",
				contentInsets = { top = 30, right = 30, bottom = 30, left = 30 },
				fallback = "native",
				layers = copy(PANEL_LAYERS),
				-- a carved panel lying ON the wall, not printed into it
				shadow = "raised",
			},
			-- PER-STATE ART, not a tint (R2). Three real states plus `error`,
			-- which has no engine GuiState and rides the adapter's error tag.
			-- Every variant reserves the SAME chrome, which is what makes the swap
			-- legal: art may change, a reservation may not (no reflow on hover).
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
					-- two small ornaments on the upper corners: enough to read as
					-- metalwork at a glance, cheap enough to pay for on every button
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
			-- a LAYERED field, so a TextBox's editing YIELD is proven over a stack
			-- rather than only over a single decoration
			field = {
				kind = "layered",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
				layers = { { kind = "fill", asset = "ornate_field" } },
			},
			-- "SELECTION CHANGES THE WHOLE STYLE": a different PICTURE for
			-- `selected`, with the theme's tint rules still applying on top.
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
			-- FOCUS IS A GLOW on this skin (ADR-0019). `$FocusGlow` resolves per
			-- theme, so Grand Hall gets torchlight and Crypt gets witch-light; the
			-- ten-foot profile derives its own stronger variant from these numbers.
			focus = {
				kind = "glow",
				color = "$FocusGlow",
				blurRadius = { scale = 0, offset = 26 },
				transparency = 0.25,
				zIndex = -1,
			},
			-- ---- value displays (R3) ------------------------------------------
			-- The rail stretches, so it is sliced; the jewel does not, so it is
			-- painted whole. This package has no dedicated slider art and says so
			-- rather than inventing a look: the bar's carved rail and the toggle's
			-- knob are the right pieces for a slider on this material.
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
			-- the counter seal behind a badge's number; its inset lifts the number
			-- off the seal's raised rim
			badge = {
				kind = "nineSlice",
				asset = "ornate_bar_center",
				sliced = false,
				contentInsets = { top = 5, right = 5, bottom = 5, left = 5 },
				fallback = "native",
			},
			-- THE BAR FAMILY. The fill is revealed through the adapter's clip
			-- window at FULL TRACK SIZE, so its texture and its slice geometry are
			-- byte-stable from 1% to 100%; the caps and the crown are anchored to
			-- the TRACK, which is the whole reason they are separate ornaments.
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
			-- THE SLIDING SWITCH. ON is a different picture, not a tint; the knob
			-- has its own pressed art. Travel stays solver-owned — art never moves
			-- geometry — and a package that declared neither of these would still
			-- render today's palette-true switch.
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
			-- the plate behind each stepper glyph; the glyph itself is an ICON
			-- REQUEST answered by the `icons` table below.
			--
			-- `sliced = true` EXPLICITLY. `stepperPlate` is a WHOLE-image slot by
			-- default, because a glyph plate is usually a fixed-size token — and
			-- this art is not: it is a 40x40 carved plate with a 12px border, and
			-- the live stepper renders it at 44x55. Without the flag it came back
			-- `ScaleType = Stretch` with an empty SliceCenter and the plate's
			-- bevel stretched with it (found on the first live drive, not in a
			-- test: the compiler cannot know an author's art is nine-sliceable).
			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "ornate_stepper_plate_default", pressed = "ornate_stepper_plate_pressed" },
				sliced = true,
				contentInsets = { top = 4, right = 4, bottom = 4, left = 4 },
				fallback = "native",
			},
			-- ink lines on carved wood read best as flat paint
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		-- ===== SEMANTIC ICONS (R4) ==========================================
		--
		-- A control asks for a MEANING ("increment"), never for an asset id, and
		-- this table answers with art. Two deliberate demonstrations:
		--
		--   * `ornate:settings` is a NAMESPACED name — the same `ns:name`
		--     convention a contributed control declares its roles with. A package
		--     may ship art for a meaning the framework has never heard of.
		--   * `menu` and `more` are framework names this package leaves UNMAPPED,
		--     although it could easily have pointed them at the gear. That is the
		--     fallback half of R4 proved inside the centerpiece rather than only
		--     in a stripped-down variant.
		--
		--     WHAT THOSE TWO NOW DRAW CHANGED (compact-label stage, 2026-07-27).
		--     The framework ships icon art of its own, resolving BELOW a package's
		--     and ABOVE the ASCII glyph, so an unmapped name here draws the
		--     framework's picture tinted by this theme's `content` role rather
		--     than a character. This package deliberately does NOT opt out
		--     (`identity.standardIcons`), because that makes it the demonstration
		--     of the middle rung: six names this package drew itself, one it
		--     invented, and two it left to the library — every rung of the ladder
		--     visible in one shipped centerpiece. The ASCII floor is still proved,
		--     in the pair that declines the set.
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

-- The failure fixture the live drive needs: ONE middle layer of the panel stack
-- pointed at an id that styles and never loads. A stack has to fall back as a
-- UNIT — a half-painted ladder reads as broken rather than degraded — and the
-- recovery has to put all six layers back.
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
