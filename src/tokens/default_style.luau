--!strict
-- "Studio Neutral" — Facet's built-in default style (director brief
-- 2026-07-19: "if Apple made a game UI system — minimal but polished,
-- affordances always clear, professional/neutral, renders quickly, motion in
-- key areas by default"). Design principles:
--   * one dark neutral surface ramp with a slight cool cast; ONE restrained
--     accent; hairline strokes instead of borders; generous radii;
--   * every affordance states itself: interactive surfaces are visibly
--     raised, focus is an accent ring, pressed is a quick dip, disabled is
--     40% content — never color-only state (a11y §8.4);
--   * cheap by default: flat fills, one stroke, no gradients; shadows exist
--     ONLY as the two depth-hierarchy presets below (§17 Phase 4 — raised
--     controls and overlay panels), inside the perf budget the style lint
--     and performance runner watch;
--   * motion only where it informs (toggle knob, pressed dip, modal enter),
--     always through motion tokens, always honoring reducedMotion.
-- Games override any of this via tokens.compile with their own schema; this
-- module is the neutral floor every Facet app gets for free.

local tokens = require("./tokens")

local function rgb(r: number, g: number, b: number): tokens.Rgb
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local SCHEMA = {
	colors = {
		-- surface ramp (cool near-black; flat fills only)
		surface = rgb(18, 20, 26), -- app background / scrim base
		surfaceStrong = rgb(28, 31, 40), -- raised panels, modals
		content = rgb(236, 239, 245), -- primary text on surface
		contentStrong = rgb(250, 251, 253), -- titles on surfaceStrong
		accent = rgb(44, 98, 210), -- restrained professional blue (4.5:1+ with white)
		onAccent = rgb(255, 255, 255),
		-- destructive semantic role (B-BTN2): a destructive button must read as
		-- dangerous without relying on colour ALONE (the role also carries a tag and
		-- its own sheet rule). Gated for contrast like every other pair.
		danger = rgb(176, 42, 42),
		onDanger = rgb(255, 255, 255),
	},
	-- extended (non-contract) roles the renderer may read
	extra = {
		control = rgb(41, 45, 58), -- interactive rows/buttons at rest
		controlHover = rgb(49, 54, 69),
		controlPressed = rgb(34, 37, 48),
		controlSelected = rgb(45, 58, 92), -- selected rows: accent-washed control
		contentSecondary = rgb(158, 165, 182),
		hairline = rgb(255, 255, 255), -- used at 8% opacity
		scrimOpacity = 0.45, -- backdrop dim behind modals
		hairlineOpacity = 0.92, -- as Transparency value (8% visible)
		disabledContentOpacity = 0.4,
		focusRingThickness = 2,
		pressedScale = 0.985,
		-- ten-foot focus strengthening (input-paradigms expansion, matrix D.4):
		-- a hairline ring vanishes across a room, so on a Large display class the
		-- focused control gets a thicker ring PLUS a slight scale-up. Near
		-- displays keep focusRingThickness / no scale (byte-identical).
		tenFootFocusRingThickness = 4,
		tenFootFocusScale = 1.05,
	},
	-- the typography ramp. `control` (18) is stated here rather than left to the
	-- theme snapshot's literal fallback so ONE table describes the ladder every
	-- role name resolves through — and so the `numeral` size `tokens.compile`
	-- derives (control-or-heading) is the same 18 the theme snapshot derives.
	-- `strong`/`numeral` themselves stay derived (tokens.compile DERIVED_TYPE):
	-- Studio Neutral takes the same defaults a game schema does.
	type = { caption = 12, label = 14, body = 16, heading = 20, title = 24, control = 18 },
	space = { xs = 4, s = 8, m = 16, l = 24, xl = 40 },
	radii = { control = 8, panel = 12, pill = 999 },
	-- engine-true UIShadow presets (verified platform facts 2026-07-20:
	-- blurRadius is a UDim {scale = fraction of parent's SHORTEST dim,
	-- offset = px}; offset/spread are UDim2 shapes; zIndex negative only)
	shadows = {
		-- raised interactive surfaces: a tight drop that actually READS.
		-- 0.55/12/y2 measured near-invisible against a mid sky (max pixel delta
		-- 18/255 over the Quality row, director fix round 2026-07-25) — a depth
		-- cue nobody can see is cost without information.
		raised = {
			blurRadius = { scale = 0, offset = 14 },
			color = { r = 0, g = 0, b = 0 },
			transparency = 0.35,
			offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 3 } },
			spread = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
			zIndex = -1,
			enabled = true,
		},
		-- overlay panels/modals: soft, wider halo for depth hierarchy
		overlay = {
			blurRadius = { scale = 0, offset = 24 },
			color = { r = 0, g = 0, b = 0 },
			transparency = 0.45,
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
	"default style failed its own contrast/completeness gate: "
		.. (report and table.concat(report.missing or {}, ",") or "?")
)

-- re-attach the extended roles (tokens.compile keeps only contract sections)
local style = table.clone(compiled) :: any
style.extra = table.freeze(table.clone(SCHEMA.extra))
style.report = report

return table.freeze(style)
