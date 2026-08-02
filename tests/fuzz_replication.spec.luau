--!strict
-- Phase 4 seeded property fuzzing of replication reconciliation (design
-- §15.2, §17 Phase 4; UI-REPL-001/002). A model server mutates a keyed
-- collection; a hostile network delays, duplicates, reorders, and drops
-- patches before they reach the client adapters; mutations confirm/reject
-- out of order and duplicated. Invariants: the client converges to the
-- authoritative state once the network quiesces (gap -> resnapshot recovery
-- included), revisions stay monotonic, duplicate/stale ingests are refused,
-- mutation status transitions stay legal (pending never implies success),
-- and optimistic state reconciles. Failures carry a replayable seed.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fuzz = require("./lib/fuzz")
local replication_fuzzer = require("./lib/fuzzers/replication")

describe("replication property fuzz (seeded)", function()
	it("converges through delay/duplication/reorder/drop over 60 seeded cases", function()
		local report = fuzz.run({
			name = "replication",
			baseSeed = 471120,
			cases = 60,
			case = replication_fuzzer.case,
		})
		if #report.failures > 0 then
			local first = report.failures[1]
			error(`replication fuzz failed: seed={first.seed} err={first.error}`)
		end
		expect(#report.failures).toBe(0)
	end)

	it("is replayable: identical base seed, identical fingerprint", function()
		local a = fuzz.run({ name = "replication", baseSeed = 8, cases = 10, case = replication_fuzzer.case })
		local b = fuzz.run({ name = "replication", baseSeed = 8, cases = 10, case = replication_fuzzer.case })
		expect(a.fingerprint).toBe(b.fingerprint)
	end)
end)
