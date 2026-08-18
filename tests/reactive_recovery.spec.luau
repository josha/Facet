--!strict
--[[
	REACTIVE-CORE RECOVERY AND DIAGNOSTICS — the release-candidate reactive-runtime
	review's RR-1..RR-11 contracts, pinned.

	Every case here is about the SECOND thing that happens after something goes
	wrong. The core's quarantine story was already good at the first thing: a
	throwing compute, a throwing observer, a runaway effect all record one error
	and leave the scheduler running. What none of them said is whether the node
	that failed can ever work again — and for three shapes the honest answer was
	"no, for the rest of the session", with no diagnostic to say so:

	  · a memo whose FIRST evaluation threw kept an empty dependency set, so
	    nothing in the graph could mark it stale and it answered `nil` forever
	    (RR-1, and RR-4 which is the same path reached through an illegal write);
	  · an effect that disposed itself during its own run was re-subscribed by the
	    run it was disposed in, stranding a record in `dep.subs` that nothing ever
	    removes while `counters().effects` reads clean (RR-2);
	  · a settle callback that tripped the round cap was re-run to the full cap on
	    every later flush of the session (RR-9).

	And two diagnostics could not be acted on: cycle paths printed
	`memo -> memo -> memo` because `Node.name` was never written (RR-3), and
	disposing a node with live subscribers froze all of them silently (RR-7).

	THE ROUND CAP IS PINNED HERE RATHER THAN CHANGED. The review read
	`rounds <= FEEDBACK_ROUND_CAP` as an off-by-one permitting 101 rounds. Measured,
	it permits exactly 100: `rounds` is incremented BEFORE the test, so the value
	101 is the refusal, never an executed round. The 101 the review measured is
	effect RUNS — the registration run plus 100 rounds. The last case below is the
	instrument that says which of those two numbers moved, because until it existed
	the cap had no test at all (MAINT-18).
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any

-- the number of subscription records a signal is carrying. Reaching into the
-- node is deliberate: the leak RR-2 describes is invisible from every public
-- counter — that is what made it survive.
local function subCount(source: any): number
	local n = 0
	for _ in (source :: any)._node.subs do
		n += 1
	end
	return n
end

describe("a memo that fails on its FIRST evaluation can recover (RR-1/RR-4)", function()
	it("subscribes to the deps it reached before the throw, and retries when one changes", function()
		local core = Facet.newCore()
		local input = core:signal(1)
		local explode = true
		local m = core:memo(function(use)
			local v = use(input)
			if explode then
				error("first evaluation throws", 0)
			end
			return v * 10
		end)

		expect(m:get()).toBe(nil)
		expect(string.find(tostring(core:lastError()), "first evaluation throws", 1, true) ~= nil).toBe(true)
		-- the edge that makes recovery possible at all
		expect(subCount(input)).toBe(1)

		explode = false
		input:set(2)
		expect(m:get()).toBe(20)
	end)

	it("a throw before any use leaves the node stale, so the next pull retries", function()
		local core = Facet.newCore()
		local explode = true
		local m = core:memo(function()
			if explode then
				error("threw before reading anything", 0)
			end
			return "recovered"
		end)

		expect(m:get()).toBe(nil)
		explode = false
		core:flush()
		expect(m:get()).toBe("recovered")
	end)

	it("an illegal write during a first evaluation is the same recovery (RR-4)", function()
		local core = Facet.newCore()
		local input = core:signal(1)
		local victim = core:signal(0)
		local misbehave = true
		local m = core:memo(function(use)
			local v = use(input)
			if misbehave then
				victim:set(99) -- illegal: a write during memo evaluation
			end
			return v * 3
		end)

		expect(m:get()).toBe(nil)
		expect(string.find(tostring(core:lastError()), "writing state during memo", 1, true) ~= nil).toBe(true)

		misbehave = false
		input:set(4)
		expect(m:get()).toBe(12)
	end)

	it("a memo that already SUCCEEDED keeps its previous deps when a later run throws", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		local explode = false
		local m = core:memo(function(use)
			local v = use(a)
			if explode then
				error("later evaluation throws", 0)
			end
			return v + 1
		end)
		expect(m:get()).toBe(2)
		explode = true
		a:set(5)
		expect(m:get()).toBe(2) -- quarantined: the last good value is kept
		expect(subCount(a)).toBe(1)
		explode = false
		a:set(9)
		expect(m:get()).toBe(10)
	end)
end)

describe("an effect that disposes itself is not re-subscribed (RR-2)", function()
	it("leaves zero records in dep.subs and the counters clean", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		local runs = 0
		local unsubscribe: (() -> ())? = nil
		local before = core:counters().effects
		-- disposal happens on the SECOND run: the registration run is over before
		-- `core:effect` has handed back the closure that disposes it
		unsubscribe = core:effect(function(use)
			runs += 1
			use(a)
			if runs >= 2 and unsubscribe ~= nil then
				unsubscribe() -- disposes ITSELF, mid-run
			end
		end)
		expect(runs).toBe(1)
		expect(subCount(a)).toBe(1)

		a:set(2)
		core:flush()
		expect(runs).toBe(2)
		expect(subCount(a)).toBe(0)
		expect(core:counters().effects).toBe(before)
		-- ...and it stays gone: a later write must not resurrect it
		a:set(3)
		core:flush()
		expect(runs).toBe(2)
		expect(subCount(a)).toBe(0)
	end)

	it("the same holds when the owning SCOPE disposes during the run", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		local scope = core:scope("owner")
		local runs = 0
		local armed = false
		scope:own(core:effect(function(use)
			runs += 1
			use(a)
			if armed then
				scope:dispose() -- the scope that owns this effect, from inside it
			end
		end))
		armed = true
		a:set(2)
		core:flush()
		expect(runs).toBe(2)
		expect(subCount(a)).toBe(0)
		a:set(3)
		core:flush()
		expect(runs).toBe(2)
	end)
end)

describe("diagnostics name the nodes they are about (RR-3/RR-7)", function()
	it("a forced cycle's path names BOTH memos, not 'memo -> memo'", function()
		local core = Facet.newCore()
		local s = core:signal(1)
		local forward: any = nil
		-- both computes TOLERATE a quarantined dep's nil, so the recorded error is
		-- the cycle itself rather than the arithmetic failure that follows it
		local m1 = core:memo(function(use)
			local extra = if forward ~= nil then use(forward) else nil
			return use(s) + (if type(extra) == "number" then extra else 0)
		end)
		local m2 = core:memo(function(use)
			local v = use(m1)
			return if type(v) == "number" then v else 0
		end)
		forward = m2
		local _ = m1:get()
		s:set(2)
		core:flush()

		local err = tostring(core:lastError())
		expect(string.find(err, "Facet cycle:", 1, true) ~= nil).toBe(true)
		-- the path is usable: each hop carries the creation site of its compute,
		-- so the two memos are distinguishable
		local hops: { string } = {}
		for hop in string.gmatch(string.match(err, "Facet cycle: (.*)$") or "", "[^ ]+") do
			if hop ~= "->" then
				table.insert(hops, hop)
			end
		end
		expect(#hops >= 2).toBe(true)
		local distinct: { [string]: boolean } = {}
		for _, hop in hops do
			expect(string.find(hop, "reactive_recovery", 1, true) ~= nil).toBe(true)
			distinct[hop] = true
		end
		local n = 0
		for _ in distinct do
			n += 1
		end
		expect(n >= 2).toBe(true)
	end)

	it("reading a memo frozen by its dep's disposal says so, and changes nothing else", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		local doubled = core:memo(function(use)
			return use(a) * 2
		end)
		expect(doubled:get()).toBe(2)

		a:dispose()
		-- the disposal itself is silent: severing an edge during teardown is the
		-- normal case, not the defect
		expect(core:lastError()).toBe(nil)

		-- ...the READ is what is diagnosed, because that is the moment a value
		-- that can never change again is being trusted
		expect(doubled:get()).toBe(2)
		local err = tostring(core:lastError())
		expect(string.find(err, "can no longer update", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "memo@reactive_recovery", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "'signal'", 1, true) ~= nil).toBe(true)
	end)

	it("a memo with another live dep re-derives and is never called frozen", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		local b = core:signal(10)
		local sum = core:memo(function(use)
			return use(a) + use(b)
		end)
		expect(sum:get()).toBe(11)
		a:dispose()
		b:set(20)
		expect(sum:get()).toBe(21)
		expect(core:lastError()).toBe(nil)
	end)

	it("a clean disposal is silent", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		a:dispose()
		expect(core:lastError()).toBe(nil)
	end)
end)

describe("the flush's terminal contracts (RR-9/RR-10/RR-11)", function()
	it("observe()'s baseline pull routes a cycle error through lastError (RR-10)", function()
		--[[ The ONE shape that reaches `observe`'s own pcall. Every cycle thrown
			below a compute is caught by that compute's `pull` and reported there;
			the error escapes to the baseline pull only when the node being observed
			is ALREADY evaluating — i.e. when `core:observe` is called from inside
			that memo's own compute. That path swallowed the diagnostic entirely:
			`node.failed = true` and nothing on `lastError`. ]]
		local core = Facet.newCore()
		local m: any = nil
		local observed = false
		m = core:memo(function()
			if not observed then
				observed = true
				core:observe(m, function() end)
			end
			return 1
		end)
		expect(m:get()).toBe(1)
		expect(observed).toBe(true)
		expect(string.find(tostring(core:lastError()), "Facet cycle:", 1, true) ~= nil).toBe(true)
	end)

	it("a settle callback that trips the cap is quarantined, not re-run every flush (RR-9)", function()
		local core = Facet.newCore()
		local s = core:signal(0)
		local passes = 0
		core:settle(function()
			passes += 1
			s:set(s:get() + 1)
		end)
		s:set(1)
		local first = passes
		expect(first > 1).toBe(true)
		-- ONE message: the cap diagnostic consumers already grep for, with the
		-- quarantine clause appended rather than overwriting it
		local err = tostring(core:lastError())
		expect(string.find(err, "iteration cap", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "is QUARANTINED", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "settle@reactive_recovery", 1, true) ~= nil).toBe(true)

		-- THE POINT: the next flush costs nothing. Before the quarantine every
		-- later flush in the session re-ran it to the full 100-round cap.
		local unrelated = core:signal(0)
		unrelated:set(1)
		core:flush()
		expect(passes).toBe(first)
	end)

	it("a healthy settle keeps running after an unrelated one is quarantined", function()
		local core = Facet.newCore()
		local runaway = core:signal(0)
		local healthy = 0
		core:settle(function()
			runaway:set(runaway:get() + 1)
		end)
		core:settle(function()
			healthy += 1
		end)
		runaway:set(1)
		-- the runaway writes on every pass and a write ENDS the pass, so the healthy
		-- callback registered after it never got a turn while the loop was running
		local afterFirst = healthy
		local other = core:signal(0)
		other:set(1)
		expect(healthy > afterFirst).toBe(true)
	end)

	it("the feedback cap permits exactly FEEDBACK_ROUND_CAP rounds (RR-11)", function()
		--[[ The instrument is effect RUNS, which is the only observable count the
			core exposes for rounds. `core:effect` runs the body once at REGISTRATION,
			outside the flush and before any dep is subscribed, so a runaway effect
			registered on a quiet core costs 1 + cap runs. That decomposition is the
			whole finding: the "101" the review measured is 1 + 100, not 101 rounds. ]]
		local core = Facet.newCore()
		local a = core:signal(0)
		local runs = 0
		core:effect(function(use)
			runs += 1
			local v = use(a)
			if v < 1e9 then
				a:set(v + 1)
			end
		end)
		expect(runs).toBe(101)
		-- the value advanced once per ROUND, from the registration run's write
		expect(a:get()).toBe(101)
		expect(string.find(tostring(core:lastError()), "100-round iteration cap", 1, true) ~= nil).toBe(true)
	end)
end)
