--!strict
-- Phase 4 seeded property fuzzing of the reactive scheduler (design §15.2,
-- §17 Phase 4; UI-RUNTIME-001/003, UI-LIFE-002). Random-but-seeded programs of
-- signals/memos/observers/effects/transactions run against a pure model;
-- invariants: glitch-free post-flush values, observers fire only on real
-- change (set-then-revert fires nothing), no internal core error for legal
-- programs, and full disposal returns every registry counter to baseline.
-- The same generator scales up in tools/lune/fuzz.luau; failures always
-- carry a replayable seed.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fuzz = require("./lib/fuzz")
local scheduler_fuzzer = require("./lib/fuzzers/scheduler")

describe("scheduler property fuzz (seeded)", function()
	it("upholds invariants over 60 seeded cases and leaves registries at baseline", function()
		local report = fuzz.run({
			name = "scheduler",
			baseSeed = 94651,
			cases = 60,
			case = scheduler_fuzzer.case,
		})
		if #report.failures > 0 then
			local first = report.failures[1]
			error(`scheduler fuzz failed: seed={first.seed} err={first.error}`)
		end
		expect(report.cases).toBe(60)
		expect(#report.failures).toBe(0)
	end)

	it("is replayable: the same base seed yields an identical run fingerprint", function()
		local a = fuzz.run({ name = "scheduler", baseSeed = 12345, cases = 10, case = scheduler_fuzzer.case })
		local b = fuzz.run({ name = "scheduler", baseSeed = 12345, cases = 10, case = scheduler_fuzzer.case })
		expect(a.fingerprint).toBe(b.fingerprint)
		local c = fuzz.run({ name = "scheduler", baseSeed = 54321, cases = 10, case = scheduler_fuzzer.case })
		expect(a.fingerprint == c.fingerprint).toBeFalsy()
	end)

	it("reports a replayable per-case seed on failure, and that seed reproduces", function()
		local trip = function(rng: any)
			-- deterministic 'bug': fail whenever the case draws a large value
			if rng:range(1, 100) > 60 then
				error("injected invariant violation")
			end
		end
		local report = fuzz.run({ name = "trip", baseSeed = 777, cases = 30, case = trip })
		expect(#report.failures).toBeGreaterThan(0)
		local seed = report.failures[1].seed
		local replayFailed = false
		local ok, err = pcall(function()
			fuzz.replayCase(seed, trip)
		end)
		if not ok then
			replayFailed = true
			expect(tostring(err):find("injected invariant violation") ~= nil).toBeTruthy()
		end
		expect(replayFailed).toBeTruthy()
	end)
end)
