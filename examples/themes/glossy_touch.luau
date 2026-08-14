--!strict
-- "GLOSSY TOUCH" — the TOUCH half of the platform pair (ADR-0020 R7, ledger row
-- RS-A14). Its sibling is `compact_pointer.luau`, and the pair only means
-- anything together:
--
--   theme_controller.install(adapter, defaultPackage, {
--       env = env, core = core,
--       selectBy = { touch = glossyTouch, pointer = compactPointer, gamepad = compactPointer },
--   })
--
-- One game, one view tree, two packages. On a phone the player gets 44px gel
-- rows; when the same player docks to a monitor the paradigm fact changes, the
-- controller swaps atomically, and the tree re-solves against the OTHER metric
-- snapshot — ~22px pointer controls with hairlines — without being edited,
-- rebuilt, or told. The view tree never observes the mechanism.
--
-- Written as a CLEAN CONSUMER: `themes.define` + `themes.neutralPackage()` and
-- nothing else. No internal require.
--
-- ORIGINAL WORK, NO TRADE DRESS. "iOS-6-class" names a CATEGORY of chrome —
-- glossy skeuomorphic touch controls, vertical gradients with a hard gloss step,
-- gel highlights, capsule switches, 44px rows. The palette, the geometry, the
-- gradient stops and the stripe period are invented in
-- `assets/themes/glossy-touch/source/generate_art.py` from the fixed seed
-- `0x6E27` (bumped from `0x6E11` in the director art round 2026-07-25, which
-- re-cut the bar trough, the bar fill and the stripe tile); provenance.md records
-- the whole construction and `upload-manifest.json` records the content IDs this
-- file uses.
--
-- THE ONE RULE THE ART FOLLOWS (provenance): the house "gel" is a two-segment
-- vertical gradient with a hard VALUE STEP at 48% height plus a white sheen and
-- a 1px inner rim. Because it is a function of Y ONLY, it is nine-slice safe —
-- nothing varies along a stretched axis. That is also why every source is
-- authored AT the 44px row height rather than square: a 64x64 source with a
-- 16px border squeezes the gloss step into the stretched centre band and the
-- whole look degrades to a soft gradient.

local glossy_touch = {}

glossy_touch.id = "glossy-touch"
glossy_touch.displayName = "Glossy Touch"
glossy_touch.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })
-- the pairing this package is half of, declared as DATA so the fixture, the
-- specs and a reading human all take it from one place
glossy_touch.pairRole = "touch"

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- Nunito ships with the engine: a rounded, friendly face for a touch skin
-- without bundling a font asset.
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

-- Sky: a bright daylight phone palette. The art is painted in cool blues and
-- chrome greys, so the palette stays out of its way and carries the text.
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
	},
	extra = {
		control = rgb(232, 238, 246),
		controlHover = rgb(242, 247, 255),
		controlPressed = rgb(196, 210, 228),
		-- THE SELECTED SURFACE, AND IT HAS TO DESCRIBE THE ART (director round 8).
		-- This is not decoration: `$ControlSelected` is what the framework paints
		-- for an unskinned selected row AND the colour it derives `$OnSelected`
		-- from, so a package whose palette claims one selected surface while its
		-- ART paints another gets an unreadable label. This package's selection
		-- plate is `glossy_selection_selected` under `$ChromeTintSelected`, and
		-- its glyph band measures rgb(20, 81, 194) live (median over the 25 rows
		-- the lifted label occupies). The old pale rgb(188, 214, 250) described
		-- nothing this package draws, and it is why "Balanced" was painting
		-- $Content at 3.74:1 on a saturated blue gel.
		controlSelected = rgb(20, 81, 194),
		contentSecondary = rgb(88, 100, 120),
		hairline = rgb(36, 56, 86),
		hairlineOpacity = 0.8,
		scrimOpacity = 0.35,
		disabledContentOpacity = 0.4,
		-- focus is a soft blue halo: a hard ring reads as a foreign UI element on
		-- gel, and a fingertip needs a big soft target cue rather than a hairline
		focusGlow = rgb(64, 152, 244),
	},
}

-- Slice geometry is package data, straight from the upload manifest:
-- `SliceCenter = Rect(border, border, W - border, H - border)`, `SliceScale = 1`.
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
	-- 96x24 since the director art round: authored AT the package's own
	-- `controls.progress.trackHeight`, so the gel's hard gloss step is never
	-- inside a vertically stretched band (provenance note 1, one control down
	-- from the button it was written for).
	glossy_bar_fill = {
		content = "rbxassetid://121908556097885",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 88, y1 = 16 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	-- THE STRIPE, and the one asset in this package that is never nine-sliced.
	-- Diagonals cannot survive a stretched centre band, so it repeats through
	-- `ScaleType = Tile` + `TileSize` (rs-m1) as a `tile` LAYER.
	glossy_stripe_tile = { content = "rbxassetid://131357884608814", preload = "install", fallback = "native" },
	glossy_toggle_track_off = {
		content = "rbxassetid://133407056790088",
		sliceCenter = { x0 = 14, y0 = 14, x1 = 58, y1 = 18 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	-- RE-CUT 2026-07-26 (director round 8, seed 0x6E43): the ON capsule is now
	-- the package's own BLUE, not green. See generate_art.py's `toggle_track`.
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
	return {
		base = themes.neutralPackage(),
		identity = {
			id = glossy_touch.id,
			displayName = glossy_touch.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
			-- DECLINES THE FRAMEWORK ICON SET (compact-label stage), which is the
			-- case that opt-out exists for. This package ships no `icons` ON
			-- PURPOSE, so that the same stepper draws ASCII glyphs here and
			-- pictures under Fantasy Ornate — a controlled comparison, and the
			-- only place the framework's ASCII floor is visible in a shipped
			-- package. Letting the framework's own art fill in would quietly
			-- delete the demonstration.
			standardIcons = false,
		},
		style = { defaultTheme = "Sky", themes = { { name = "Sky", colors = SKY.colors, extra = SKY.extra } } },
		metrics = {
			typography = typography(),
			space = { xs = 6, s = 10, m = 18, l = 28, xl = 44 },
			-- THE 44px TOUCH ROW, and the number the swap is measured on: the pair
			-- exists to prove that metrics MOVE GEOMETRY, so this and its sibling's
			-- 22 are the two ends of the live dock/undock delta.
			controlSizes = {
				compact = { height = 44, paddingX = 14, iconSize = 22 },
				regular = { height = 44, paddingX = 18, iconSize = 24 },
				large = { height = 56, paddingX = 22, iconSize = 28 },
			},
			iconSizes = { small = 20, medium = 28, large = 40 },
			radii = { control = 10, panel = 14, pill = 999 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.16, normal = 0.28 },
			controls = {
				-- the trough is authored 24px tall; rendering it at the library's
				-- default 6 would squeeze a 10px slice border into a 6px box and
				-- leave the gel's gloss step nowhere to land
				-- ...and the two theme-sized indicators, sized off the SAME gel weight
				-- (director round 2026-08-14). This is the touch half of the platform
				-- pair, so its ring is the second-largest in the corpus and its 6px
				-- stroke matches the gloss step on the trough beside it; a 12px bead
				-- is the smallest dot that still carries this skin's rim highlight.
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
			-- TWO real states. There is deliberately no `hover` art: a finger does
			-- not hover, and inventing a hover picture for a touch package would be
			-- art that the platform it is for can never show. `hover` therefore
			-- falls back to `default` WITH the theme's hover tint, which is exactly
			-- what the pointer half is for.
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
			-- THE STRIPED PROGRESS TROUGH. `barTrack` is the one slot in this
			-- package with a layer STACK, and the reason is the stripe: the gel
			-- trough is a nine-slice `fill`, and the diagonal barber-pole rides
			-- above it as a `tile` layer at the art's own 24px repeat. It cannot be
			-- part of the FILL: rs-m4 made the fill one clipped image at full track
			-- size, which is what keeps it byte-stable at every percent, and a
			-- diagonal baked into a sliced fill would smear in the stretched band.
			barTrack = {
				kind = "layered",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
				layers = {
					{ kind = "fill", asset = "glossy_bar_track" },
					-- MASKED TO THE TROUGH'S SILHOUETTE (director round 5c, probe
					-- rs-m9). A tile is a rectangle of repeats: full-bleed it painted
					-- its square corners over the trough's rounded ends and the bar
					-- read blocky. Round 5b stopped the hatch short (`inset.x = 10`,
					-- the trough's corner radius) which fixed the corner but left a
					-- bare gap at each end. `mask = "pill"` is the real answer: the
					-- adapter wraps this layer in a CanvasGroup with a scale-0.5
					-- UICorner, so the hatch runs to the tip and is CLIPPED along the
					-- arc — the stripes follow the silhouette instead of avoiding it.
					--
					-- The inset therefore drops from 10 to 2 and now means only what
					-- an inset should: hold the hatch off the trough's two lines. The
					-- well's rim is a 1px hard EDGE ring and its bottom lip a 1px lit
					-- bevel (`generate_art.py`, `bar_track`), so 2px clears both on
					-- every side. A 20px-tall pill at radius 10 is a full capsule, so
					-- the mask also sits inside the trough's own arc rather than
					-- crossing it. Both numbers are the ART's, not taste.
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
			-- THE SLIDING SWITCH: ON is a BLUE gel capsule, OFF is a grey inset
			-- one — a different picture, not a tint. The knob is one chrome token
			-- and its TRAVEL stays solver-owned. (It was green until the director
			-- round of 2026-07-26; blue is this package's accent identity, and the
			-- one every other "active" surface here already paints.)
			toggleTrack = {
				kind = "nineSlice",
				asset = { default = "glossy_toggle_track_off", selected = "glossy_toggle_track_on" },
				fallback = "native",
			},
			toggleKnob = { kind = "nineSlice", asset = "glossy_toggle_knob", sliced = false, fallback = "native" },
			-- `sliced = true`: `stepperPlate` is a WHOLE-image slot by default (a
			-- glyph plate is usually a fixed-size token) and this one is not — it is
			-- a 44x44 chrome plate with a 14px border that the live stepper renders
			-- taller than it is wide. Without the flag the gloss step stretches.
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
		-- NO `icons`, on purpose and in both halves of the pair. R4's framework
		-- fallback table draws an ASCII-safe glyph through the theme's own font,
		-- which is the right look for chrome this clean — and it makes the pair a
		-- controlled comparison against Fantasy Ornate, where the same stepper
		-- draws pictures. `identity.standardIcons = false` above is what KEEPS
		-- that true now that the framework ships art of its own.
		assets = ASSETS,
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function glossy_touch.build(themes: any): (any, any)
	return themes.define(glossy_touch.definition(themes))
end

return glossy_touch
