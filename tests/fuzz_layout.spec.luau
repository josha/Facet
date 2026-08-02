--!strict
-- Phase 4 seeded property fuzzing of the pure layout solver (design §15.2,
-- §17 Phase 4; UI-LAYOUT-001/002). Random node trees over the full V1 sizing
-- algebra — including adversarial combinations the algebra defines
-- diagnostics for (percent on an unbounded axis, aspect on both axes) — are
-- solved at random viewports. Invariants: the solver never throws, every
-- node gets a finite non-negative rect, identical inputs solve identically
-- (determinism), stack children never overlap along the stack axis, and
-- generated undefined-combination patterns surface as diagnostics rather
-- than garbage geometry. Failures carry a replayable seed.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fuzz = require("./lib/fuzz")
local layout_fuzzer = require("./lib/fuzzers/layout")

describe("layout property fuzz (seeded)", function()
	it("upholds solver invariants over 80 seeded random trees", function()
		local report = fuzz.run({
			name = "layout",
			baseSeed = 260720,
			cases = 80,
			case = layout_fuzzer.case,
		})
		if #report.failures > 0 then
			local first = report.failures[1]
			error(`layout fuzz failed: seed={first.seed} err={first.error}`)
		end
		expect(#report.failures).toBe(0)
	end)

	it("is replayable: identical base seed, identical fingerprint", function()
		local a = fuzz.run({ name = "layout", baseSeed = 42, cases = 12, case = layout_fuzzer.case })
		local b = fuzz.run({ name = "layout", baseSeed = 42, cases = 12, case = layout_fuzzer.case })
		expect(a.fingerprint).toBe(b.fingerprint)
	end)

	it("flags generated undefined combinations as diagnostics, not crashes", function()
		-- dedicated case generator that forces adversarial dims into every tree
		local report = fuzz.run({
			name = "layout-adversarial",
			baseSeed = 999331,
			cases = 30,
			case = layout_fuzzer.adversarialCase,
		})
		if #report.failures > 0 then
			local first = report.failures[1]
			error(`adversarial layout fuzz failed: seed={first.seed} err={first.error}`)
		end
		expect(#report.failures).toBe(0)
	end)
end)
