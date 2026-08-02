--!strict
-- Phase 4 fault injection (design §17 Phase 4; UI-RUNTIME-003, UI-LIFE-001/002,
-- UI-INPUT-002, UI-ENV-001): deliberately breaks the async, teardown, locale,
-- accessibility, and input-switch paths and asserts the framework degrades the
-- way the design promises — quarantined errors, detected double disposal,
-- stale async completions rejected, garbage environment facts clamped, input
-- switches never remounting. Scenarios live in tests/lib/fault_scenarios.luau
-- and are shared with tools/lune/faults (scaled runs + artifact). All
-- randomized scenarios are seeded and replayable.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local scenarios = require("./lib/fault_scenarios")

describe("fault injection (seeded, deterministic)", function()
	for _, scenario in scenarios.list do
		it(`{scenario.name}: {scenario.summary}`, function()
			-- raises with a replayable seed on any invariant violation
			scenario.run(scenarios.SPEC_ITERATIONS)
			expect(true).toBeTruthy()
		end)
	end
end)
