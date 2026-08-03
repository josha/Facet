--!strict
-- "Studio Neutral — Light" (native-stylesheets stage, ledger NSS-A1/A6): the
-- built-in second theme proving runtime theming through StyleDerive swaps.
-- Same restrained-professional principles as default_style (the dark floor),
-- inverted: near-white cool surface ramp, the SAME brand accent, dark content.
-- Every surface/content pair must clear the 4.5:1 contrast gate exactly like
-- the dark theme — tokens.compile asserts it below; sheet_model re-gates every
-- theme before it can be selected (§6.7).

local tokens = require("./tokens")

local function rgb(r: number, g: number, b: number): tokens.Rgb
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local SCHEMA = {
	colors = {
		surface = rgb(242, 244, 248), -- app background / scrim base
		surfaceStrong = rgb(255, 255, 255), -- raised panels, modals
		content = rgb(28, 32, 41), -- primary text on surface
		contentStrong = rgb(12, 14, 20), -- titles on surfaceStrong
		accent = rgb(44, 98, 210), -- brand accent (shared with dark; 4.5:1+ with white)
		onAccent = rgb(255, 255, 255),
		-- destructive semantic role (B-BTN2): a destructive button must read as
		-- dangerous without relying on colour ALONE (the role also carries a tag and
		-- its own sheet rule). Gated for contrast like every other pair.
		danger = rgb(185, 28, 28),
		onDanger = rgb(255, 255, 255),
	},
	extra = {
		control = rgb(228, 231, 238),
		controlHover = rgb(219, 223, 233),
		controlPressed = rgb(206, 211, 224),
		controlSelected = rgb(205, 219, 245), -- accent-washed control
		contentSecondary = rgb(90, 98, 114),
		hairline = rgb(10, 12, 18), -- used at 8% opacity (dark hairline on light)
		scrimOpacity = 0.45,
		hairlineOpacity = 0.92,
		disabledContentOpacity = 0.4,
		focusRingThickness = 2,
		pressedScale = 0.985,
		tenFootFocusRingThickness = 4,
		tenFootFocusScale = 1.05,
	},
	-- the same ladder the dark style declares (control stated, weight roles
	-- derived by tokens.compile) — a light variant changes colour, never metrics
	type = { caption = 12, label = 14, body = 16, heading = 20, title = 24, control = 18 },
	space = { xs = 4, s = 8, m = 16, l = 24, xl = 40 },
	radii = { control = 8, panel = 12, pill = 999 },
	shadows = {
		raised = {
			blurRadius = { scale = 0, offset = 12 },
			color = { r = 0, g = 0, b = 0 },
			transparency = 0.75,
			offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 2 } },
			spread = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
			zIndex = -1,
			enabled = true,
		},
		overlay = {
			blurRadius = { scale = 0, offset = 24 },
			color = { r = 0, g = 0, b = 0 },
			transparency = 0.65,
			offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 8 } },
			spread = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
			zIndex = -1,
			enabled = true,
		},
	},
	strokes = { hairline = 1 },
	targetSizes = { minimum = 44 },
	motion = { fast = 0.12, normal = 0.2 },
}

local compiled, report = tokens.compile(SCHEMA)
assert(
	compiled ~= nil,
	"light style failed its own contrast/completeness gate: "
		.. (report and table.concat(report.missing or {}, ",") or "?")
)

local style = table.clone(compiled) :: any
style.extra = table.freeze(table.clone(SCHEMA.extra))
style.report = report

return table.freeze(style)
