--!strict
--[[ NO SCRATCH EXPERIMENT SURVIVES IN `src/` (2026-09-07).

	Two lines of a throwaway experiment reached `src/client/screen_target.luau`
	inside a feature commit that had nothing to do with that file — a
	`ZZ_NO_PATH2D = true` constant and the `and not ZZ_NO_PATH2D` that switched the
	whole `Path2D` creation branch off. Every `UI.Path` therefore drew nothing on
	the real adapter, and the suite could not see it: the headless target builds its
	own Path2D model, so 8,824 checks passed over a framework that painted no
	strokes.

	The checker is `tools/lune/check_experiment_markers.luau`; this file is what
	makes it fail a SUITE rather than only a command someone remembers to type, and
	the second case is what makes it trustworthy — it plants the exact line that
	shipped and requires the checker to name it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local checker = require("../tools/lune/check_experiment_markers")

-- the file the real defect landed in, and the exact line it landed as
local THE_FILE = "src/client/screen_target.luau"
local THE_LINE = "local ZZ_NO_PATH2D = true -- ZZ-EXPERIMENT"

describe("experiment markers: src/ carries no scratch flag", function()
	it("the shipped tree is clean", function()
		local result = checker.check()
		local detail = ""
		if not result.ok then
			local lines: { string } = {}
			for _, v in result.violations do
				table.insert(lines, checker.describe(v))
			end
			detail = "\n" .. table.concat(lines, "\n")
		end
		expect(result.ok and true or error(`scratch experiment marker in src/:{detail}`, 2)).toBe(true)
	end)

	it("it really scanned src/, not an empty tree", function()
		local result = checker.check()
		expect(result.counts.files > 100).toBe(true)
		expect(result.counts.lines > 10000).toBe(true)
	end)

	--[[ THE NEGATIVE CONTROL, and it is the LINE THAT ACTUALLY SHIPPED rather than a
		synthetic one. A guard nobody has watched catch its own defect is decoration
		(the gate-integrity sweep's standing rule), and the plant goes through the
		checker's inject seam so the tree on disk is never written to. ]]
	it("NEGATIVE CONTROL: the line that shipped is caught, and named", function()
		local result = checker.check({ injectFile = THE_FILE, injectLine = THE_LINE })
		expect(result.ok).toBe(false)
		local found = false
		for _, v in result.violations do
			if v.file == THE_FILE and v.token == "ZZ_NO_PATH2D" then
				found = true
				expect(string.find(checker.describe(v), "scratch experiment marker", 1, true) ~= nil).toBe(true)
			end
		end
		expect(found).toBe(true)
	end)

	it("...and the bare comment marker beside an innocuous name is caught too", function()
		local result = checker.check({ injectFile = THE_FILE, injectLine = "local ok = true -- ZZ-EXPERIMENT" })
		expect(result.ok).toBe(false)
		expect(result.violations[1].token).toBe("ZZ")
	end)

	it("a word that merely CONTAINS zz is not a marker", function()
		for _, benign in { "local buzzer = 1", 'local s = "fizzbuzz"', "-- the BUZZER rings" } do
			local result = checker.check({ injectFile = THE_FILE, injectLine = benign })
			expect(`{benign}: {result.ok}`).toBe(`{benign}: true`)
		end
	end)
end)
