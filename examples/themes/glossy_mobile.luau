--!strict
-- REFERENCE THEME PACKAGE — "Glossy Mobile".
--
-- Big touch targets, generous radii, a bright palette, a rounded type family,
-- and a native gloss: the control and panel slots declare `::UIGradient` ramps,
-- which feasibility m7 proved render as PHANTOM modifiers — zero child
-- instances for the gloss, so an ornate-looking theme still costs nothing in
-- the decoration census. It carries the FONT-CHANGING and the METRIC-CHANGING
-- classes, and it is the package that COVERS the namespaced custom-control
-- conformance fixture (see `examples/themes/custom_control.luau`).
--
-- ORIGINAL WORK. The palette and the gloss ramp are chosen here. Nothing is
-- sampled from, and nothing imitates the trade dress of, any shipping phone OS.
-- No bundled assets: the gloss is a gradient, not an image.
--
-- Written against the PUBLIC API only (`themes.neutralPackage`, `themes.define`).

local glossy_mobile = {}

glossy_mobile.id = "glossy-mobile"
glossy_mobile.displayName = "Glossy Mobile"
glossy_mobile.themeClasses = table.freeze({ "palette", "metrics", "font" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- Nunito ships with the engine, so this package changes the family without
-- shipping a font asset — the cheapest possible font-class proof.
local FAMILY = "rbxasset://fonts/families/Nunito.json"
local SIZES = { caption = 13, label = 15, body = 17, control = 18, heading = 24, title = 30 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY, weight = "Medium" }, size = size, lineHeight = 1.3 }
	end
	-- the title carries the family's heavier cut; measurement keys on the FULL
	-- descriptor, so this is a different font as far as the solver is concerned
	out.title.font = { family = FAMILY, weight = "Bold" }
	return out
end

-- The gloss: a bright top half falling to neutral, so a control reads as a
-- lit plastic plate. Declared per theme because it is COLOUR — a chrome recipe
-- cannot carry it, and should not: a palette swap has to move it.
--
-- `alpha` is engine `UIGradient.Transparency`, which fades the parent's ENTIRE
-- rendering — its engine-drawn LABEL included, not just the fill. So the gloss
-- is carried by the COLOUR ramp (white at the top falling to a cool grey) and
-- the alpha ramp only ever adds a hint of fade: the compiler caps a stop at 0.9
-- and these stay far below it. The 0.55–0.95 ramp this file used to carry
-- ghosted every themed screen in the stored captures.
local function gloss(topAlpha: number, bottomAlpha: number): any
	return {
		rotation = 90,
		stops = {
			{ t = 0, r = 1, g = 1, b = 1 },
			{ t = 0.48, r = 1, g = 1, b = 1 },
			{ t = 0.52, r = 0.86, g = 0.88, b = 0.92 },
			{ t = 1, r = 0.94, g = 0.96, b = 1 },
		},
		alpha = {
			{ t = 0, v = topAlpha },
			{ t = 0.48, v = topAlpha + 0.12 },
			{ t = 0.52, v = bottomAlpha },
			{ t = 1, v = bottomAlpha },
		},
	}
end

local DAYLIGHT = {
	colors = {
		surface = rgb(238, 243, 250),
		surfaceStrong = rgb(255, 255, 255),
		content = rgb(22, 28, 40),
		contentStrong = rgb(8, 12, 20),
		accent = rgb(12, 96, 200),
		onAccent = rgb(255, 255, 255),
		danger = rgb(184, 26, 44),
		onDanger = rgb(255, 255, 255),
	},
	extra = {
		control = rgb(226, 236, 250),
		controlHover = rgb(238, 245, 255),
		controlPressed = rgb(202, 216, 236),
		controlSelected = rgb(190, 216, 250),
		contentSecondary = rgb(92, 104, 124),
		hairline = rgb(40, 60, 90),
		hairlineOpacity = 0.82,
		scrimOpacity = 0.35,
		disabledContentOpacity = 0.4,
		chromeGradient = {
			control = gloss(0.02, 0.22),
			panel = gloss(0.06, 0.3),
		},
		-- namespaced custom-control needs (see examples/themes/custom_control.luau)
		["demo:gaugeTint"] = rgb(12, 96, 200),
	},
}

function glossy_mobile.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = glossy_mobile.id,
			displayName = glossy_mobile.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Daylight",
			themes = { { name = "Daylight", colors = DAYLIGHT.colors, extra = DAYLIGHT.extra } },
		},
		metrics = {
			typography = typography(),
			space = { xs = 6, s = 10, m = 18, l = 28, xl = 44 },
			-- thumb-first: every row clears the touch floor by design rather
			-- than by the presenter's hit expansion
			controlSizes = {
				compact = { height = 44, paddingX = 14, iconSize = 22 },
				regular = { height = 52, paddingX = 18, iconSize = 26 },
				large = { height = 64, paddingX = 22, iconSize = 30 },
				-- the NAMESPACED custom-control metric (examples/themes/
				-- custom_control.luau). `controlSizes` is the one metric section
				-- `define` leaves open to names outside the v1 vocabulary, so it
				-- is the public path a contributed control has today; the
				-- snapshot carries it through and `resolveNumber` finds it at
				-- "controlSizes.demo:gauge.height".
				["demo:gauge"] = { height = 28, paddingX = 12, iconSize = 18 },
			},
			radii = { control = 16, panel = 24, pill = 999 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 48 },
			motion = { fast = 0.16, normal = 0.28 },
			insets = {
				panel = { top = 18, right = 18, bottom = 18, left = 18 },
				control = { top = 10, right = 18, bottom = 10, left = 18 },
				field = { top = 10, right = 18, bottom = 10, left = 18 },
				selection = { top = 8, right = 10, bottom = 8, left = 10 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		chrome = {
			-- DEPTH, not imagery (director review 2026-07-25: "buttons should
			-- have shadows"). This family is glossy-flat: every slot is native
			-- paint, so it creates zero decoration instances — but a card and a
			-- button now sit ABOVE the surface instead of being drawn on it. The
			-- shadow is adapter-owned (::UIShadow rules are inert, feasibility
			-- m7) and rides the library's own `raised` preset, which is inside
			-- the perf budget the style lint watches.
			panel = { kind = "native", shadow = "raised" },
			control = { kind = "native", shadow = "raised" },
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function glossy_mobile.build(themes: any): (any, any)
	return themes.define(glossy_mobile.definition(themes))
end

return glossy_mobile
