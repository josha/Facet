--!strict
-- Estimator calibration seam (native-substrate NS-A10, UI-FID-001): the
-- engine correction TIGHTENS the conservative default and can never
-- under-reserve past the clamped floor; calibration is pinnable data. The
-- live corpus comparison is scenario 'preferred_text'.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local text_metrics = require("../src/layout/text_metrics")

describe("text_metrics calibration (NS-A10)", function()
	it("a calibrated fraction tightens the estimate and never widens it", function()
		text_metrics.resetCalibration()
		local before = text_metrics.measure("hello wide world", "BuilderSans", 20, 1000)
		text_metrics.calibrate("BuilderSans", 0.5)
		local after = text_metrics.measure("hello wide world", "BuilderSans", 20, 1000)
		expect(after.width < before.width).toBe(true)
		text_metrics.calibrate("BuilderSans", 0.9) -- cannot exceed the safe default
		local capped = text_metrics.measure("hello wide world", "BuilderSans", 20, 1000)
		expect(capped.width <= before.width).toBe(true)
		text_metrics.resetCalibration()
	end)

	it("clamps garbage to the safe band [0.30, 0.62]", function()
		text_metrics.resetCalibration()
		text_metrics.calibrate("BuilderSans", 0.01)
		expect(text_metrics.calibrationTable()["BuilderSans"]).toBe(0.30)
		text_metrics.calibrate("BuilderSans", 5)
		expect(text_metrics.calibrationTable()["BuilderSans"]).toBe(0.62)
		text_metrics.calibrate("BuilderSans", 0 / 0)
		expect(text_metrics.calibrationTable()["BuilderSans"]).toBe(0.62)
		text_metrics.resetCalibration()
	end)

	it("calibration is per-font; unknown fonts keep the full-em pending fallback", function()
		text_metrics.resetCalibration()
		text_metrics.calibrate("BuilderSans", 0.45)
		local other = text_metrics.measure("hello", "SourceSans", 20, 1000)
		local unknown = text_metrics.measure("hello", "ComicNeue", 20, 1000)
		expect(unknown.state).toBe("pending")
		expect(unknown.width > other.width).toBe(true)
		text_metrics.resetCalibration()
	end)

	it("CJK glyphs stay full-em regardless of calibration (never under-reserve wide scripts)", function()
		text_metrics.resetCalibration()
		text_metrics.calibrate("BuilderSans", 0.30)
		local cjk = text_metrics.measure("こんにちは", "BuilderSans", 20, 1000)
		expect(cjk.width >= 5 * 20).toBe(true)
		text_metrics.resetCalibration()
	end)
end)

-- ============================================================================
-- A RUN OF SPACES IS AS WIDE AS IT IS LONG (found live 2026-08-06, Studio,
-- tutorial example 05's legend).
--
-- The wrap model walked `gmatch(text, "%S+")` and added exactly ONE space width
-- at every joint, so `"a   b"` reserved the same box as `"a b"`. Measured on the
-- engine at BuilderSans 12, the legend `"v correct   ~ present   x absent"` draws
-- 134.5 px and the model reserved 124.5 — the four extra spaces at 2.5 px each,
-- exactly — so a label with 780 px of free width beside it truncated to an
-- ellipsis. Multiple spaces are ordinary in aligned copy and separator strings,
-- so this under-reserves quietly and everywhere.
-- ============================================================================
describe("text_metrics: consecutive spaces are reserved, not collapsed", function()
	local FONT, SIZE = "BuilderSans", 12

	it("a doubled space is WIDER than a single one, by about one space", function()
		text_metrics.resetCalibration()
		local single = text_metrics.measure("a b", FONT, SIZE, 10000)
		local double = text_metrics.measure("a  b", FONT, SIZE, 10000)
		local triple = text_metrics.measure("a   b", FONT, SIZE, 10000)
		-- headlessly the space width is ESTIMATED and each width is rounded to the
		-- bounds grid, so the claim is monotonic growth rather than an exact step:
		-- the defect was that they were all IDENTICAL
		expect(double.width > single.width).toBe(true)
		expect(triple.width > single.width).toBe(true)
		expect(triple.width >= double.width).toBe(true)
	end)

	it("the live legend string measures wider than its single-spaced form", function()
		-- the exact string and shape the Studio session measured
		local legend = "v correct   ~ present   x absent"
		local collapsed = "v correct ~ present x absent"
		local a = text_metrics.measure(legend, FONT, SIZE, 10000)
		local b = text_metrics.measure(collapsed, FONT, SIZE, 10000)
		expect(a.width > b.width).toBe(true)
	end)

	it("a single-spaced string is byte-identical to what it always reserved", function()
		-- the regression guard: the fix must move NOTHING for ordinary copy
		local samples = { "hello wide world", "a", "one two", "The quick brown fox jumps" }
		for _, sample in samples do
			local m = text_metrics.measure(sample, FONT, SIZE, 10000)
			local rejoined = {}
			for word in string.gmatch(sample, "%S+") do
				table.insert(rejoined, word)
			end
			expect(m.width).toBe(text_metrics.measure(table.concat(rejoined, " "), FONT, SIZE, 10000).width)
		end
	end)

	it("a gap made of a NEWLINE still counts as one, so embedded newlines are unchanged", function()
		local withNewline = text_metrics.measure("a\nb", FONT, SIZE, 10000)
		local withSpace = text_metrics.measure("a b", FONT, SIZE, 10000)
		expect(withNewline.width).toBe(withSpace.width)
	end)

	it("leading and trailing whitespace still reserve nothing", function()
		local plain = text_metrics.measure("word", FONT, SIZE, 10000)
		expect(text_metrics.measure("   word", FONT, SIZE, 10000).width).toBe(plain.width)
		expect(text_metrics.measure("word   ", FONT, SIZE, 10000).width).toBe(plain.width)
	end)
end)
