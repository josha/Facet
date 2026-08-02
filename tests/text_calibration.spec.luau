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
