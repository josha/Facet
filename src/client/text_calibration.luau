--!strict
-- Engine text calibration (native-substrate NS-A10, UI-FID-001; CLIENT-ONLY):
-- measures a reference corpus with TextService:GetTextBoundsAsync (which
-- honors PreferredTextSize — grounded 2026-07-23) and feeds a per-font
-- average-glyph fraction into the headless estimator's calibration seam
-- (src/layout/text_metrics.calibrate), TIGHTENING its deliberate over-reserve
-- without ever under-reserving:
--   * a 1.08 safety margin rides every measured fraction;
--   * text_metrics clamps to [0.30, 0.62] (tighten-only, sane floor);
--   * measure/paint agreement is preserved because the SAME calibrated value
--     feeds the solver's next solve — calibrate BEFORE presenting, or
--     re-solve after (the caller owns that ordering; the gallery calibrates
--     at boot).
-- Yields (GetTextBoundsAsync); call from a task, not the render path.
--
-- FONT DESCRIPTORS (ADR-0019 §6): a name here may be a short family
-- ("BuilderSans", which means Regular/Normal) or the canonical descriptor
-- "family#weight#style" a theme package declares. Both address ONE calibration
-- entry through text_metrics' canonical keys, and the descriptor form is what
-- the theme controller preflights at install so a theme-declared face measures
-- as itself instead of as its family's Regular.

-- lazily, and via the library's ordinary relative requires, so the module is
-- require-safe off the engine (the theme controller pulls it in for install-time
-- font preflight and the headless suite exercises that lifecycle)
local function textService(): any
	return game:GetService("TextService")
end

local text_metrics = require("../layout/text_metrics")
local text_premeasure = require("./text_premeasure")

local text_calibration = {}

local SAFETY = 1.08
-- mixed-width Latin reference: narrow (i,l), wide (m,w), digits, punctuation
local REFERENCE = "The quick brown fox jumps over 12 lazy dogs, weighing 3.7kg!"
local REFERENCE_GLYPHS = utf8.len(REFERENCE) :: number

-- calibrate the named fonts (default: every known font); returns the applied
-- table for evidence artifacts, keyed by the name the caller passed
function text_calibration.run(fonts: { string }?): { [string]: number }
	local applied: { [string]: number } = {}
	for _, fontName in fonts or { "BuilderSans", "GothamSSm", "SourceSans" } do
		local font = text_premeasure.fontFor(fontName)
		if font == nil then
			continue
		end
		local params = Instance.new("GetTextBoundsParams")
		params.Text = REFERENCE
		params.Font = font
		params.Size = 100 -- large size minimizes rounding in the fraction
		params.Width = 100000 -- unwrapped: a single line's true advance width
		local ok, bounds = pcall(function()
			return textService():GetTextBoundsAsync(params)
		end)
		if ok and typeof(bounds) == "Vector2" and bounds.X > 0 then
			local fraction = (bounds.X / 100 / REFERENCE_GLYPHS) * SAFETY
			text_metrics.calibrate(fontName, fraction)
			applied[fontName] = text_metrics.calibrationTable()[text_metrics.canonicalFont(fontName)]
		end
	end
	return applied
end

return text_calibration
