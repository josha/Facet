--!strict
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local dataset = require("../examples/performance/lab/dataset")
describe("perf lab: the dataset is deterministic (PL-2)", function()
	it("the same seed, count and content produce a byte-identical row set", function()
		local a = dataset.build({ count = 250, seed = 42, content = "normal" })
		local b = dataset.build({ count = 250, seed = 42, content = "normal" })
		expect(#a).toBe(250)
		expect(dataset.digest(a)).toBe(dataset.digest(b))
	end)

	it("a different seed produces a different row set, and the digest says so", function()
		local a = dataset.build({ count = 250, seed = 42 })
		local b = dataset.build({ count = 250, seed = 43 })
		expect(dataset.digest(a) == dataset.digest(b)).toBe(false)
	end)

	it("each content variant is its own workload, not a relabelling of the same one", function()
		local normal = dataset.build({ count = 60, seed = 9, content = "normal" })
		local locale = dataset.build({ count = 60, seed = 9, content = "locale" })
		local identity = dataset.build({ count = 60, seed = 9, content = "identity" })
		expect(dataset.digest(normal) == dataset.digest(locale)).toBe(false)
		expect(dataset.digest(locale) == dataset.digest(identity)).toBe(false)

		expect(#locale[1].detail > #normal[1].detail).toBe(true)
	end)

	it("an unknown content variant is refused, naming it", function()
		local ok, err = pcall(function()
			dataset.build({ count = 4, content = "klingon" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "klingon") ~= nil).toBe(true)
	end)

	it("the ramp ladder is bounded by a declared ceiling (PL-11)", function()
		expect(#dataset.RAMP_STEPS > 0).toBe(true)
		for _, step in dataset.RAMP_STEPS do
			expect(step <= dataset.MAX_ROWS).toBe(true)
		end
	end)
end)
