--!strict
-- "COMPACT POINTER" — the DESKTOP half of the platform pair (ledger row RS-A14). Its sibling is `glossy_touch.luau`; see that file for the
-- one-line `selectBy` authoring the pair exists to prove.
--
-- Written as a CLEAN CONSUMER: `themes.define` + `themes.neutralPackage()` and
-- nothing else. No internal require.
--
-- ORIGINAL WORK, NO TRADE DRESS. "desktop-pointer-class" names a CATEGORY of chrome —
-- compact ~22px pointer controls, near-flat surfaces, 1px hairline borders,
-- subtle top-lit gradients, cool greys. Palette, geometry, gradient stops and
-- border construction are invented in
-- `assets/themes/compact-pointer/source/generate_art.py` from the fixed seed
-- `0xC0DE`; provenance.md records the construction and `upload-manifest.json`
-- records the content IDs used here.
--
-- THE ONE RULE THE ART FOLLOWS (provenance): a hairline is
-- `outer_shape − outer_shape_inset_by_1px`, so straight runs come out fully
-- opaque — a true 1px line — while corners stay smooth. Everything is authored
-- AT the target control height, which is why this package must never be scaled:
-- at `SliceScale ≠ 1`, or stretched from a bigger source, the hairlines become
-- 1.4px of grey mush and the identity is gone.
--
-- MINIMUM RENDERED SIZES ARE METRICS HERE, not advice. `2·border` has to fit
-- inside the rendered control or the sliced centre rect is empty, so the
-- provenance's floors — buttons/fields ≥ 22, `barTrack` ≥ 10, `barFill` ≥ 8,
-- `toggleTrack` ≥ 18, `stepperPlate` ≥ 22, `panel` ≥ 24 — are what the metric
-- section below is chosen against, and every number is called out where it
-- lands.

local compact_pointer = {}

compact_pointer.id = "compact-pointer"
compact_pointer.displayName = "Compact Pointer"
compact_pointer.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })
compact_pointer.pairRole = "pointer"

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- BuilderSans at desktop sizes: the art is designed for a near-white window and
-- a dense, quiet type stack.
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

-- Aqua: the near-white window this art is drawn for. Hairlines are invisible on
-- a dark sheet — the palette and the art were chosen together.
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
	},
	extra = {
		control = rgb(246, 247, 250),
		controlHover = rgb(238, 244, 252),
		controlPressed = rgb(220, 226, 234),
		-- the hover wash this package reuses as its selection art
		-- (`compact_button_hover`), sampled and tinted — see the provenance note on
		-- the `selection` recipe, and director finding 12
		controlSelected = rgb(163, 191, 230),
		contentSecondary = rgb(96, 104, 116),
		hairline = rgb(140, 148, 160),
		hairlineOpacity = 0.9,
		scrimOpacity = 0.3,
		disabledContentOpacity = 0.4,
	},
}

-- Slice geometry is package data, straight from the upload manifest:
-- `SliceCenter = Rect(border, border, W - border, H - border)`, `SliceScale = 1`.
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
	return {
		base = themes.neutralPackage(),
		identity = {
			id = compact_pointer.id,
			displayName = compact_pointer.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
			-- DECLINES THE FRAMEWORK ICON SET, for the same reason its touch half
			-- does (compact-label stage). The pair exists to prove that ONE design
			-- at two densities is two snapshots and not two palettes, so the two
			-- halves have to answer identically about everything that is not
			-- density — including what a stepper draws. Opting out on one side
			-- only would have made the pair asymmetric in exactly the dimension it
			-- is supposed to hold constant.
			standardIcons = false,
		},
		style = { defaultTheme = "Aqua", themes = { { name = "Aqua", colors = AQUA.colors, extra = AQUA.extra } } },
		metrics = {
			typography = typography(),
			space = { xs = 2, s = 6, m = 10, l = 16, xl = 24 },
			-- THE ~22px POINTER ROW — the other end of the pair's live delta (the
			-- touch half is 44). `compact` sits exactly at the art's authored
			-- height and `regular` one notch above it, so no button ever renders
			-- below the 22px floor `2·8` of border needs.
			controlSizes = {
				compact = { height = 22, paddingX = 8, iconSize = 14 },
				regular = { height = 24, paddingX = 10, iconSize = 16 },
				large = { height = 30, paddingX = 12, iconSize = 18 },
			},
			iconSizes = { small = 12, medium = 16, large = 24 },
			radii = { control = 4, panel = 6, pill = 999 },
			-- THE IDENTITY. One physical pixel, everywhere.
			strokes = { hairline = 1 },
			-- the HIT floor is not the DRAW floor: a 22px button still has to be
			-- hittable, and the framework clamps this UP to 44 no matter what a
			-- package asks for (the accessibility floor)
			targetSizes = { minimum = 44 },
			motion = { fast = 0.1, normal = 0.16 },
			controls = {
				-- `barTrack` ≥ 10 and `barFill` ≥ 8: 10 is the art's authored height,
				-- so the trough draws 1:1 with its 4px borders intact
				-- ...and the two theme-sized indicators, the SMALLEST in the corpus,
				-- which is this package's whole job (it is the dense pointer half of
				-- the `selectBy` pair — see the header). 18/2 keeps the ring one step
				-- under the 22px compact control it sits beside, and a 5px dot is the
				-- smallest square this skin's 1px hairline can still outline.
				progress = {
					trackHeight = 10,
					rowMinHeight = 16,
					circularSize = 18,
					circularThickness = 2,
					spinnerDotSize = 5,
				},
				-- a desktop slider is a thin rail; no slider ART ships here (see the
				-- chrome section), so this is only the native rail's geometry
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
			-- THREE real states, which is the pointer half's whole point: a mouse
			-- can hover and this package has art for it. Its touch sibling has no
			-- `hover` art at all, because a finger cannot produce that state.
			-- All three reserve the same 8px chrome, so the no-reflow rule holds.
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
			-- SELECTION IS THE HOVER WASH, deliberately reused rather than invented
			-- (provenance note 5). On a near-flat pointer surface the honest
			-- selected affordance is a tinted control plus the framework's focus
			-- ring; a decorative selection plate would fight the identity, and
			-- shipping art that contradicts the style to fill a slot is worse than
			-- reusing one that does not.
			selection = {
				kind = "nineSlice",
				asset = { default = "compact_button_default", selected = "compact_button_hover" },
				contentInsets = { top = 2, right = 4, bottom = 2, left = 4 },
				fallback = "native",
			},
			-- FOCUS IS A RING here — the desktop idiom, and the deliberate contrast
			-- with the touch half's soft halo. Stated rather than inherited: `ring`
			-- IS the default, and a reader of the pair should be able to see that
			-- the two packages disagree about focus on purpose.
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
			-- `sliced = true` for the same reason the touch half needs it: a
			-- whole-image default would stretch a 22x22 plate with a 7px hairline
			-- border, and a stretched hairline is the one thing this package
			-- cannot survive.
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
		-- NO `icons` (provenance note 6): R4's ASCII-safe fallback glyph through
		-- this theme's font is exactly the right look for near-flat desktop chrome.
		assets = ASSETS,
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function compact_pointer.build(themes: any): (any, any)
	return themes.define(compact_pointer.definition(themes))
end

return compact_pointer
