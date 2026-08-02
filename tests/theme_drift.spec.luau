--!strict
-- Theme DRIFT lint (ADR-0019 §2). A hardcoded metric inside a reusable control
-- is invisible in review and invisible to the suite — 44 is still 44 under
-- Studio Neutral — while quietly making that control immune to every theme. So
-- the check runs here, and it is proven to FAIL: a lint nobody has watched fail
-- is a lint nobody knows works.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local drift = require("../tools/lune/check_theme_drift")

describe("no reusable framework control hardcodes a theme-owned metric", function()
	it("the framework surface is clean", function()
		local result = drift.check()
		local detail = if result.ok then "" else "\n" .. table.concat(result.problems, "\n")
		expect(result.ok and true or error(`theme drift lint FAILED:{detail}`, 2)).toBe(true)
	end)

	it("it actually scanned the surface it claims to cover", function()
		local result = drift.check()
		-- src/controls/* plus the renderer and the presenter
		expect(result.counts.files >= 15).toBe(true)
		expect(result.counts.lines > 5000).toBe(true)
	end)

	-- NEGATIVE PROOF: inject each shape of violation and watch the lint catch it
	it("catches a hardcoded dimension in a control", function()
		local result = drift.check({
			injectFile = "src/controls/chip.luau",
			injectLine = 'local synthetic = { type = "fixed", px = 44 }',
		})
		expect(result.ok).toBe(false)
		expect(#result.violations).toBe(1)
		expect(result.violations[1].file).toBe("src/controls/chip.luau")
		expect(result.violations[1].what).toBe("dimension px")
		-- the message tells the author what to do instead
		expect(string.find(result.problems[1], "theme metric name", 1, true) ~= nil).toBe(true)
		expect(string.find(result.problems[1], "ALLOWLIST", 1, true) ~= nil).toBe(true)
	end)

	it("catches a hardcoded text size, gap, padding and named metric constant", function()
		for _, case in
			{
				{ line = 'local x = UI.Text({ id = "T", text = "x", textSize = 15 })', what = "textSize" },
				{ line = "local x = { gap = 12 }", what = "gap" },
				{ line = "local x = { padding = 9 }", what = "padding" },
				{ line = "local ROW_HEIGHT = 36", what = "named metric constant" },
			}
		do
			local result = drift.check({ injectFile = "src/controls/label.luau", injectLine = case.line })
			expect(result.ok).toBe(false)
			expect(result.violations[1].what).toBe(case.what)
		end
	end)

	it("catches drift in the renderer and the presenter too, not only in controls", function()
		for _, file in { "src/render/renderer.luau", "src/present/presenter.luau" } do
			local result = drift.check({ injectFile = file, injectLine = "local HIT_FLOOR = 44" })
			expect(result.ok).toBe(false)
			expect(result.violations[1].file).toBe(file)
		end
	end)

	it("zero is not a metric: 'this container adds no spacing' stays legal", function()
		local result =
			drift.check({ injectFile = "src/controls/chip.luau", injectLine = "local x = { gap = 0, padding = 0 }" })
		expect(result.ok).toBe(true)
	end)

	it("a comment describing a literal is not a violation", function()
		local result =
			drift.check({ injectFile = "src/controls/chip.luau", injectLine = "-- the old height = 44 literal" })
		expect(result.ok).toBe(true)
	end)

	it("every allowlist entry carries a real justification", function()
		expect(#drift.ALLOWLIST > 0).toBe(true)
		for _, entry in drift.ALLOWLIST do
			expect(type(entry.file)).toBe("string")
			expect(type(entry.match)).toBe("string")
			expect(#entry.why > 40).toBe(true) -- a reason, not a shrug
		end
	end)
end)
