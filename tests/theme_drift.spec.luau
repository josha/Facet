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

	--[[ NEGATIVE PROOF: inject each shape of violation and watch the lint catch it.

		SCOPED TO THE PLANTED FILE, ALWAYS (MAINT-4, 2026-08-17). These cases used
		to assert ABSOLUTE global counts — `#result.violations == 1`, `result.ok ==
		true` — which made every one of them a second, silent copy of "the
		framework surface is clean". One real violation ANYWHERE in `src/` reddened
		four unrelated mutation cases with messages naming the wrong file, so the
		instrument that exists to prove the lint works became the loudest source of
		misdirection the moment the lint had something to say.

		A mutation case has exactly one question: did the lint see THE LINE I
		PLANTED? So each case takes a baseline, plants its line, and asserts the
		DELTA in the planted file. Whether the rest of the tree is clean is the
		first case's job, and it says so by name. ]]
	local function inPlantedFile(result: any, file: string): { any }
		local mine: { any } = {}
		for _, violation in result.violations do
			if violation.file == file then
				table.insert(mine, violation)
			end
		end
		return mine
	end

	-- how many violations this file ALREADY has, so a planted one is a delta
	local function baselineFor(file: string): number
		return #inPlantedFile(drift.check(), file)
	end

	local function plantedIn(file: string, line: string): { any }
		local before = baselineFor(file)
		local result = drift.check({ injectFile = file, injectLine = line })
		local mine = inPlantedFile(result, file)
		expect(`{file}: planted violations {#mine - before}`).toBe(`{file}: planted violations 1`)
		return mine
	end

	it("catches a hardcoded dimension in a control", function()
		local file = "src/controls/chip.luau"
		local before = baselineFor(file)
		local result = drift.check({
			injectFile = file,
			injectLine = 'local synthetic = { type = "fixed", px = 44 }',
		})
		expect(result.ok).toBe(false)
		local mine = inPlantedFile(result, file)
		expect(#mine - before).toBe(1)
		expect(mine[#mine].what).toBe("dimension px")
		-- the message tells the author what to do instead
		local message: string? = nil
		for _, problem in result.problems do
			if string.find(problem, file, 1, true) ~= nil then
				message = problem
			end
		end
		expect(message ~= nil).toBe(true)
		expect(string.find(message :: string, "theme metric name", 1, true) ~= nil).toBe(true)
		expect(string.find(message :: string, "ALLOWLIST", 1, true) ~= nil).toBe(true)
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
			local mine = plantedIn("src/controls/label.luau", case.line)
			expect(mine[#mine].what).toBe(case.what)
		end
	end)

	it("catches drift in the renderer and the presenter too, not only in controls", function()
		for _, file in { "src/render/renderer.luau", "src/present/presenter.luau" } do
			local mine = plantedIn(file, "local HIT_FLOOR = 44")
			expect(mine[#mine].file).toBe(file)
		end
	end)

	it("zero is not a metric: 'this container adds no spacing' stays legal", function()
		local file = "src/controls/chip.luau"
		local before = baselineFor(file)
		local result = drift.check({ injectFile = file, injectLine = "local x = { gap = 0, padding = 0 }" })
		-- the DELTA is what this case is about: `result.ok` would also answer for
		-- every other file in the tree
		expect(#inPlantedFile(result, file) - before).toBe(0)
	end)

	it("a comment describing a literal is not a violation", function()
		local file = "src/controls/chip.luau"
		local before = baselineFor(file)
		local result = drift.check({ injectFile = file, injectLine = "-- the old height = 44 literal" })
		expect(#inPlantedFile(result, file) - before).toBe(0)
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
