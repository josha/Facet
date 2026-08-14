--!strict
-- REFERENCE THEME PACKAGE — "Sci-Fi HUD".
--
-- Angular and cold: zero radii everywhere, a thin display face, hairline
-- strokes, and directional `::UIGradient` washes on the panel, control and
-- selection slots. It carries the FONT-CHANGING class with a family that is
-- nothing like Builder Sans, which is what makes it useful — a package that
-- changes the family by a hair proves nothing about measurement.
--
-- ORIGINAL WORK. The palette, the gradient ramps and the type ladder are chosen
-- here; nothing is taken from, or imitates the trade dress of, any published
-- game or its HUD. No bundled assets: every effect is native paint.
--
-- Written against the PUBLIC API only (`themes.neutralPackage`, `themes.define`).

local scifi_hud = {}

scifi_hud.id = "scifi-hud"
scifi_hud.displayName = "Sci-Fi HUD"
scifi_hud.themeClasses = table.freeze({ "palette", "metrics", "font" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- Michroma ships with the engine: a wide, square display face. Its glyphs are
-- much wider than Builder Sans at the same size, so this package is also the
-- proof that the solver measures the EFFECTIVE font rather than a cached
-- assumption — under-measuring here clips visibly.
local FAMILY = "rbxasset://fonts/families/Michroma.json"
local SIZES = { caption = 11, label = 12, body = 14, control = 14, heading = 18, title = 22 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		-- airy leading: a wide face needs room or the lines fuse
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = 1.45 }
	end
	return out
end

-- A directional scan wash. Rotation is a per-theme token, so an "alert" variant
-- could re-aim it without touching a rule.
--
-- `alpha` is engine `UIGradient.Transparency`, and UIGradient fades the parent's
-- ENTIRE rendering — the HUD's own text with it. The wash therefore lives in the
-- COLOUR ramp (cyan falling to near-black) while alpha only ever hints at a
-- fade; the compiler caps a stop at 0.9 and these stay far below. The 0.4–0.96
-- ramp this file used to carry ghosted the whole HUD in the stored captures.
local function wash(topA: number, bottomA: number): any
	return {
		rotation = 115,
		stops = {
			{ t = 0, r = 0.36, g = 0.86, b = 1 },
			{ t = 0.35, r = 0.16, g = 0.44, b = 0.66 },
			{ t = 1, r = 0.04, g = 0.1, b = 0.18 },
		},
		alpha = {
			{ t = 0, v = topA },
			{ t = 0.35, v = (topA + bottomA) / 2 },
			{ t = 1, v = bottomA },
		},
	}
end

-- A gradient's COLOUR ramp MULTIPLIES the parent's rendering — including its
-- label's glyphs. The deep ramp above is therefore legal only on slots that
-- draw no text of their own (the panel; LuauUI content is flat-tree siblings,
-- never panel children). Text-bearing slots take this near-white sheen: the
-- CONTROL FILL carries the darkness, the gradient only hints cyan, and the
-- label keeps its contrast. Found live: the deep ramp on controls crushed
-- every label toward black in the stored capture.
local function sheen(topA: number, bottomA: number): any
	return {
		rotation = 115,
		stops = {
			{ t = 0, r = 1, g = 1, b = 1 },
			{ t = 0.5, r = 0.86, g = 0.96, b = 1 },
			{ t = 1, r = 0.68, g = 0.86, b = 0.95 },
		},
		alpha = {
			{ t = 0, v = topA },
			{ t = 1, v = bottomA },
		},
	}
end

local NIGHTWATCH = {
	colors = {
		surface = rgb(6, 11, 18),
		surfaceStrong = rgb(12, 20, 30),
		content = rgb(198, 232, 246),
		contentStrong = rgb(232, 250, 255),
		accent = rgb(64, 214, 236),
		onAccent = rgb(4, 12, 18),
		danger = rgb(255, 110, 96),
		onDanger = rgb(20, 4, 2),
	},
	extra = {
		control = rgb(18, 30, 44),
		controlHover = rgb(26, 44, 62),
		controlPressed = rgb(12, 20, 30),
		controlSelected = rgb(20, 58, 78),
		contentSecondary = rgb(126, 164, 184),
		hairline = rgb(96, 214, 236),
		hairlineOpacity = 0.6, -- a HUD wants its edges visible, not hinted
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.5,
		chromeGradient = {
			panel = wash(0.12, 0.34),
			control = sheen(0.05, 0.2),
			selection = sheen(0.02, 0.14),
		},
	},
}

function scifi_hud.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = scifi_hud.id,
			displayName = scifi_hud.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Nightwatch",
			themes = { { name = "Nightwatch", colors = NIGHTWATCH.colors, extra = NIGHTWATCH.extra } },
		},
		metrics = {
			typography = typography(),
			space = { xs = 4, s = 8, m = 14, l = 22, xl = 36 },
			controlSizes = {
				compact = { height = 32, paddingX = 12, iconSize = 16 },
				regular = { height = 40, paddingX = 16, iconSize = 20 },
				large = { height = 52, paddingX = 20, iconSize = 24 },
			},
			-- ANGULAR: every corner is square, including the pill
			radii = { control = 0, panel = 0, pill = 0 },
			strokes = { hairline = 2 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.09, normal = 0.18 },
			-- THE TWO THEME-SIZED INDICATORS (director round 2026-08-14). A HUD ring
			-- is WIDE AND THIN — a targeting reticle, not a gauge — so this package
			-- takes the second-largest diameter in the corpus and the thinnest stroke
			-- allowed beside it, which is also exactly this skin's own `strokes.hairline`
			-- of 2. Left unauthored it would have been a 22px ring with a 4px stroke:
			-- a chunky little donut, in the one package whose whole voice is thin
			-- angular light.
			controls = {
				progress = { circularSize = 36, circularThickness = 2, spinnerDotSize = 6 },
			},
			insets = {
				panel = { top = 14, right = 14, bottom = 14, left = 14 },
				control = { top = 8, right = 16, bottom = 8, left = 16 },
				field = { top = 8, right = 16, bottom = 8, left = 16 },
				selection = { top = 4, right = 8, bottom = 4, left = 8 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		-- native everywhere: the gradients are phantom modifiers (m7), so this
		-- theme looks expensive and creates ZERO decoration instances
		chrome = {
			-- A COOL GLOW, not a drop shadow (director review 2026-07-25). The
			-- HUD family reads as emissive glass, so its depth cue is a tight
			-- cyan-dark halo rather than the library's neutral black `raised`
			-- preset — same machinery, explicit parameters. zIndex is NEGATIVE
			-- because a shadow renders below its parent (engine rule, enforced by
			-- styling.normalizeShadow, which `themes.define` validates against).
			-- Retuned in the same round: the first pass (blur 10-18, transparency
			-- 0.45-0.5, y-offset 1) measured near-invisible in the live capture.
			-- A glow is CENTERED (no offset) and needs opacity + reach to read.
			panel = {
				kind = "native",
				shadow = {
					blurRadius = { scale = 0, offset = 24 },
					color = { r = 0.05, g = 0.42, b = 0.5 },
					transparency = 0.3,
					offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
					zIndex = -1,
				},
			},
			control = {
				kind = "native",
				shadow = {
					blurRadius = { scale = 0, offset = 16 },
					color = { r = 0.05, g = 0.42, b = 0.5 },
					transparency = 0.28,
					offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
					zIndex = -1,
				},
			},
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
			-- A HUD focuses by lighting up. `$Accent` is already this family's
			-- cyan, so the glow needs no role of its own — which is the case the
			-- token reference exists for: one word, and it follows every theme's
			-- accent for free. Tighter and more transparent than Parchment's:
			-- emissive glass reads as a rim, not as a bloom.
			focus = {
				kind = "glow",
				color = "$Accent",
				blurRadius = { scale = 0, offset = 20 },
				transparency = 0.3,
				zIndex = -1,
			},
		},
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function scifi_hud.build(themes: any): (any, any)
	return themes.define(scifi_hud.definition(themes))
end

return scifi_hud
