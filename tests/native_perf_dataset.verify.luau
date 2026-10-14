--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local expect = Verify.expect
	local dataset = require("../examples/performance/lab/dataset")
	verifyHarness:suite("perf lab: the dataset is deterministic (PL-2)", function()
		verifyHarness:case("the same seed, count and content produce a byte-identical row set", {
			id = "native_perf_dataset::perf lab: the dataset is deterministic (PL-2)::the same seed, count and content produce a byte-identical row set",
			run = function()
				local a = dataset.build({ count = 250, seed = 42, content = "normal" })
				local b = dataset.build({ count = 250, seed = 42, content = "normal" })
				expect(#a):toBe(250)
				expect((dataset.digest(a))):toBe(dataset.digest(b))
			end,
		})

		verifyHarness:case("a different seed produces a different row set, and the digest says so", {
			id = "native_perf_dataset::perf lab: the dataset is deterministic (PL-2)::a different seed produces a different row set, and the digest says so",
			run = function()
				local a = dataset.build({ count = 250, seed = 42 })
				local b = dataset.build({ count = 250, seed = 43 })
				expect(dataset.digest(a) == dataset.digest(b)):toBe(false)
			end,
		})

		verifyHarness:case("each content variant is its own workload, not a relabelling of the same one", {
			id = "native_perf_dataset::perf lab: the dataset is deterministic (PL-2)::each content variant is its own workload, not a relabelling of the same one",
			run = function()
				local normal = dataset.build({ count = 60, seed = 9, content = "normal" })
				local locale = dataset.build({ count = 60, seed = 9, content = "locale" })
				local identity = dataset.build({ count = 60, seed = 9, content = "identity" })
				expect(dataset.digest(normal) == dataset.digest(locale)):toBe(false)
				expect(dataset.digest(locale) == dataset.digest(identity)):toBe(false)

				expect(#locale[1].detail > #normal[1].detail):toBe(true)
			end,
		})

		verifyHarness:case("an unknown content variant is refused, naming it", {
			id = "native_perf_dataset::perf lab: the dataset is deterministic (PL-2)::an unknown content variant is refused, naming it",
			run = function()
				local ok, err = pcall(function()
					dataset.build({ count = 4, content = "klingon" })
				end)
				expect(ok):toBe(false)
				expect(string.find(tostring(err), "klingon") ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("the ramp ladder is bounded by a declared ceiling (PL-11)", {
			id = "native_perf_dataset::perf lab: the dataset is deterministic (PL-2)::the ramp ladder is bounded by a declared ceiling (PL-11)",
			run = function()
				expect(#dataset.RAMP_STEPS > 0):toBe(true)
				for _, step in dataset.RAMP_STEPS do
					expect(step <= dataset.MAX_ROWS):toBe(true)
				end
			end,
		})
	end)
end
