--!strict
-- "PIXEL QUEST" — the rich-skinning-v2 pixel-art reference package (ADR-0020
-- R5, ledger row RS-A13). P4 built this file as a throwaway test fixture for
-- the three pixel generation rules; P5 PROMOTED it in place rather than
-- shipping a near-copy beside it, because two pixel packages differing in a
-- selection recipe would be one package and one liability.
--
-- Written as a CLEAN CONSUMER: the only framework contact is `themes.define`
-- and `themes.neutralPackage()`. No internal require, ever.
--
-- It proves the three R5 generation rules on a running screen:
--
--   1. every image-bearing rule the package emits carries
--      `ResampleMode = Pixelated`, censused so `pixelatedRules == imageRules`;
--   2. `SliceScale` is an integer on every sliced asset (the compiler rejects
--      anything else for a pixel package — fractional is sharp-but-UNEVEN, which
--      reads as crisp in a capture and wrong on the grid);
--   3. the resolved snapshot's lengths are multiples of `pixelUnit`.
--
-- It also carries the SEMANTIC ICON map (R4), because the stepper's +/- is where
-- an icon request actually lands on a control, and because pixel art is the case
-- that makes the difference visible: a 32px glyph drawn nearest-neighbour.
--
-- AND IT CARRIES THE PIXEL REFERENCE'S OWN IDIOM (RS-A13): **selection changes
-- the whole style**, not the tint. The selected row is a different plate AND
-- four ruby jewels that are not there when it is unselected — a `corners` layer
-- whose `default` is 24×24 of pure transparency, which is how a per-state layer
-- says "nothing here" in a grammar that requires a `default`.
--
-- ART: the repository's own `assets/themes/pixel-quest/` PNGs — original,
-- procedurally generated, provenance in that folder. Content IDs come from its
-- `upload-manifest.json` and are never hardcoded anywhere but this table.
--
-- THE AUTHORING RULE THAT MAKES IT CORRECT (provenance.md): every sliced source
-- is `2*border + 1` DESIGN pixels on each sliced axis, so the stretched centre
-- is exactly ONE design pixel and any target size replicates one uniform colour.
-- That is what structurally prevents "sharp but unevenly sized pixels"; the
-- slice centres below are `Rect(border, border, W - border, H - border)`.

local pixel_quest = {}

pixel_quest.id = "pixel-quest"
pixel_quest.displayName = "Pixel Quest"
pixel_quest.themeClasses = table.freeze({ "palette", "metrics", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- the 12-colour palette the generator paints with (provenance.md)
local INK = rgb(22, 18, 31)
local SHADE = rgb(58, 44, 79)
local WOOD = rgb(168, 114, 47)
local TAN = rgb(215, 168, 96)
local CREAM = rgb(244, 230, 192)
local RED = rgb(122, 31, 34) -- RED_D, the palette's dark red: the mid RED fails the 4.5:1 gate against CREAM
local GRN = rgb(79, 168, 63)

-- PIXEL UNIT 4. Art is authored in design pixels and saved at 4 image px per
-- design px, so every length below is a multiple of 4 — and the snapshot snaps
-- anything that is not (ADR-0020 R5 generation rule 3).
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

-- SliceCenter = Rect(border, border, W - border, H - border); SliceScale = 1,
-- integer, which for a pixel package is a compile-time requirement rather than
-- a preference.
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
	-- the selected row's jewels, and the NOTHING that stands in for them in every
	-- other state. `pixel_blank` is 24x24 of pure transparency: the per-state
	-- grammar requires a `default`, and an author who has no art for a state
	-- should be able to say so rather than ship a dimmed ornament.
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
	-- THE ICON SET. `tintRole` is declared on the two STEPPER glyphs and on
	-- nothing else, deliberately: it makes "the icon tinted with the role its
	-- asset named" a comparison against an untinted sibling rather than a claim.
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
	},
	extra = {
		control = WOOD,
		controlHover = TAN,
		controlPressed = rgb(107, 67, 38),
		-- `pixel_plate_selected` as it is actually painted — the plate sampled and
		-- multiplied by `$ChromeTintSelected` (director finding 12). TAN was the
		-- untinted art colour, which is not what a selected row shows.
		controlSelected = rgb(163, 148, 71),
		contentSecondary = TAN,
		hairline = INK,
		hairlineOpacity = 0.2,
		scrimOpacity = 0.5,
		disabledContentOpacity = 0.45,
		-- A CONTRIBUTED CONTROL'S ROLE (ADR-0020 R8, rung 3): the second package
		-- that covers `examples/themes/ornate_gauge.luau`, so the rung-3 example
		-- can be re-themed between two packages rather than shown under one.
		-- Poison-green, from this palette rather than the gauge's own brass.
		["gauge:needle"] = rgb(142, 222, 106), -- GRN_L from the generator palette
	},
}

function pixel_quest.definition(themes: any): any
	local inset = { top = 16, right = 16, bottom = 16, left = 16 }
	return {
		base = themes.neutralPackage(),
		identity = {
			id = pixel_quest.id,
			displayName = pixel_quest.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
			-- THE TWO FIELDS THIS PACKAGE EXISTS FOR
			rendering = "pixel",
			pixelUnit = UNIT,
			-- ...AND THE FIELD THAT FOLLOWS FROM THEM. The framework's own icon
			-- set (compact-label stage) fills in below a package's art, which is
			-- right for a smooth theme and wrong for this one: a 128px antialiased
			-- silhouette in a 4px-unit pixel grid reads as a mistake, and
			-- `ResamplerMode.Pixelated` only makes it a NEAREST-NEIGHBOUR mistake.
			-- This package draws its own art for the six names it cares about and
			-- the ASCII glyph for the rest, which is what it did before the set
			-- existed and what it should keep doing.
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
				-- the contributed control's METRIC. Every number here is a
				-- multiple of `pixelUnit` already, so R5's snap-up leaves them
				-- alone — a contributed metric is on the grid like every other.
				["gauge:dial"] = { height = 48, paddingX = 12, iconSize = 20 },
			},
			-- ICON SIZES (ADR-0020 R4). 32px is the art's native size — 8 design
			-- pixels at 4x — so a stepper glyph draws 1:1 and stays on the grid.
			-- These ride the SNAPSHOT, which is what makes them a metric a package
			-- can move rather than a constant a control holds.
			iconSizes = { small = 16, medium = 32, large = 48 },
			radii = { control = 4, panel = 4, pill = 12, ["gauge:ring"] = 4 },
			strokes = { hairline = 4 }, -- one design pixel; the thinnest line that exists here
			targetSizes = { minimum = 44 },
			motion = { fast = 0.08, normal = 0.14 },
			-- THE TROUGH'S OWN HEIGHT (RS-A16-D3, found live: the fill solved to
			-- ZERO px). This package's `barTrack` recipe declares a 2-design-pixel
			-- carved frame — `contentInsets = 8` on all four sides — while the
			-- framework's default trackHeight is 6, which this package's own pixel
			-- snap raises to 8. Eight minus two eights is nothing: the bar drew its
			-- trough and both heart end-caps and no value at all, at every viewport.
			--
			-- 28 is picked against the ART, on the 4px grid, from three floors: the
			-- track texture is 32px tall with an 8px slice border, so it needs
			-- 2*8+1 = 17px before its carving draws at all; the FILL texture's border
			-- is 4px, so the 28-16 = 12px of content it gets clears its own
			-- 2*4+1 = 9px; and 12px is three whole design pixels of fill, which reads
			-- as a value rather than as a hairline. The 40px heart caps then overhang
			-- (40-28)/2 = 6px per edge, which `chromeOutsets` already reserves.
			controls = {
				-- ...and the two theme-sized indicators, ON THE DESIGN GRID (director
				-- round 2026-08-14). Every length this package publishes snaps UP to
				-- its 4px pixel unit, so an indicator inherited off the space scale
				-- was a 24px ring with a 4px stroke that happened to land on the grid
				-- by luck rather than by decision. These three are grid multiples by
				-- construction: 32 = 8 design pixels across, 4 = ONE design pixel of
				-- stroke, and the 8px dot is a 2x2 block — which is what makes the
				-- travelling pulse read as a marching sprite rather than a soft glow.
				progress = {
					trackHeight = 28,
					rowMinHeight = 40,
					circularSize = 32,
					circularThickness = 4,
					spinnerDotSize = 8,
				},
				--[[ ...AND THE FIELD IS THE SAME DEFECT AS THE TROUGH, found the same
					way and fixed the same way (theme sweep, 2026-08-14). `chrome.field`
					carves 16px of border a side and `controls.textInput.padding` spends
					another 12 inside it, which is 56px of a 44px field: every TextField in
					the corpus solved to a ZERO content box under this package — ten of the
					theme ledger's rows, on ten different surfaces, all one number.

					76 is that arithmetic and nothing else: 16 border + 12 padding, twice,
					plus one line of `control` type (16px at this package's 1.25 line
					height = 20). On the 4px grid, so R5's snap leaves it alone. Anything
					smaller silences the guard — it only fires at zero — while still
					leaving no room for the line, which is the check-that-proves-nothing
					class rather than a fix. ]]
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
			--[[ CONTENT INSETS ARE THE CARVED FRAME, NOT THE SLICE BORDER (task
				THEME, 2026-08-27, and it is the one number this package had wrong).

				Every inset here was written equal to its art's NINE-SLICE BORDER,
				which for this package is forced large by the authoring rule at the
				head of this file: a sliced source is `2·border + 1` DESIGN pixels so
				the stretched centre is exactly one. That makes the border a statement
				about STRETCHING, and `contentInsets` is a statement about PAINT — "how
				far in does the frame reach" — and the two are not the same number.

				Read off the art, design pixel by design pixel (`pixel_plate_default`
				is 9x9 dp): one INK outline, one TAN/WOOD_D bevel, then five design
				pixels of flat WOOD face, with the corner rivets sitting AT the bevel.
				The frame is TWO design pixels, and 4 dp was reserving half the face.
				`pixel_field` is the same shape (INK, WOOD_D/TAN, then the SHADE well)
				and `pixel_plate_selected` too (INK, the CREAM ring, then the gilt
				face with its ruby studs on the ring) — which is what keeps R2's
				identical-inset rule between the two selection states.

				WHAT IT COST WHILE IT WAS WRONG. `controlSizes.compact.height` is 36
				and `regular` 44, so 4 dp per side left a 36px control FOUR pixels of
				interior for a 16px glyph: the director's item 6 (three round HUD
				buttons painting no mark at all, IMG_3785) and 448 of the framework's
				own "could not be spent" reports on one keyboard fixture. Two design
				pixels leave 20 and 28. ]]
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
			-- SELECTION CHANGES THE WHOLE STYLE (RS-A13, the pixel reference's own
			-- idiom) — a LAYERED slot, not a tint and not one swapped picture:
			--
			--   layer 1  the plate itself: mid wood → light gilt with a double
			--            ring and notched corners, a different picture entirely;
			--   layer 2  four ruby jewels that exist only while the row is
			--            selected. They are a `corners` layer rather than part of
			--            the plate art because the plate's side bands STRETCH and
			--            a baked ornament would smear (provenance note 3), and
			--            their `default` is `pixel_blank` — 24x24 of nothing.
			--
			-- The chrome inset is 2 design pixels in BOTH states, which is what
			-- makes the swap legal: a variant may change its art, never its
			-- reservation. The row therefore does not move when it is chosen.
			-- (It read 4 dp until 2026-08-27; see `control` above for why the slice
			-- border is the wrong number to reserve. Both plates carve two: INK plus
			-- a bevel on the default, INK plus the CREAM ring on the selected.)
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
						size = 24,
					},
				},
			},
			-- `sliced = true` EXPLICITLY. `stepperPlate` is a whole-image slot by
			-- default (a glyph plate is usually a fixed-size token), and this art
			-- is a 7x7 design-pixel nine-slice with a 3 dp border — so the flag is
			-- the difference between a stretched 28px token and a plate that grows
			-- to the button with its rivets intact.
			stepperPlate = {
				kind = "nineSlice",
				asset = { default = "pixel_stepper_plate_default", pressed = "pixel_stepper_plate_pressed" },
				sliced = true,
				fallback = "native",
				-- ...and the same correction: 7x7 dp, one INK outline and one TAN /
				-- WOOD_D bevel, so the frame is two design pixels and the 3 dp slice
				-- border was never the reservation (see `control` above).
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			},
			barTrack = {
				kind = "nineSlice",
				asset = "pixel_bar_track",
				fallback = "native",
				contentInsets = { top = 8, right = 8, bottom = 8, left = 8 },
			},
			barFill = { kind = "nineSlice", asset = "pixel_bar_fill", direction = "ltr", fallback = "native" },
			-- the heart end-cap is a SEPARATE layer, never part of the clipped
			-- fill art (rs-m4): it has to survive every percent
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
		-- SEMANTIC ICONS (R4). Names are the framework's own vocabulary, so a
		-- control asks for a MEANING and this table answers with art.
		icons = {
			increment = "pixel_icon_plus",
			decrement = "pixel_icon_minus",
			["chevron.trailing"] = "pixel_icon_chevron_right",
			["chevron.down"] = "pixel_icon_chevron_down",
			checkmark = "pixel_icon_check",
			close = "pixel_icon_cross",
		},
		assets = ASSETS,
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function pixel_quest.build(themes: any): (any, any)
	return themes.define(pixel_quest.definition(themes))
end

-- A variant with NO icon map at all, same art everywhere else. The RS-A7
-- comparison: the stepper's glyphs must fall back to the framework's ASCII
-- characters and stay legible, rather than becoming empty plates.
function pixel_quest.buildWithoutIcons(themes: any): (any, any)
	local def = pixel_quest.definition(themes)
	def.identity.id = pixel_quest.id .. "-noicons"
	def.icons = nil
	return themes.define(def)
end

return pixel_quest
