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
		-- the disposed node is NAMED, which for a signal means its creation order —
		-- the bare kind named nothing, and a signal is every case this reaches
		expect(string.match(err, "'signal#%d+'") ~= nil).toBe(true)
	end)

	it("a memo with another live dep is never called frozen — READ BEFORE it recomputes", function()
		--[[ THE ORDER IS THE TEST (review NEW-4). The first version of this case did
			`a:dispose()`, then `b:set(20)`, then `sum:get()` — so the recompute
			cleared the flag before any read, and the case certified the property only
			in the ordering where it happened to hold. Read FIRST and the old detector
			produced an affirmatively false message ("it will answer this value
			forever") about a node that updates on the very next line, and overwrote
			whatever real error was on the channel to say it. ]]
		local core = Facet.newCore()
		local a = core:signal(1)
		local b = core:signal(10)
		local sum = core:memo(function(use)
			return use(a) + use(b)
		end)
		expect(sum:get()).toBe(11)

		a:dispose()
		expect(core:lastError()).toBe(nil)
		-- the read the old detector lied about
		expect(sum:get()).toBe(11)
		expect(core:lastError()).toBe(nil)
		-- ...and it demonstrably DOES update, which is what makes the message false
		b:set(20)
		expect(sum:get()).toBe(21)
		expect(core:lastError()).toBe(nil)
	end)

	it("a real error on the channel is not overwritten by a benign read (NEW-4)", function()
		local core = Facet.newCore()
		local a = core:signal(1)
		local b = core:signal(10)
		local sum = core:memo(function(use)
			return use(a) + use(b)
		end)
		expect(sum:get()).toBe(11)
		local boom = core:memo(function()
			error("a genuine failure the operator needs to see", 0)
		end)
		expect(boom:get()).toBe(nil)
		a:dispose()
		expect(sum:get()).toBe(11)
		expect(string.find(tostring(core:lastError()), "a genuine failure", 1, true) ~= nil).toBe(true)
	end)

	it("a memo frozen behind ANOTHER memo is reported on the transitive read (NEW-4)", function()
		--[[ The false NEGATIVE, and the common case: memos chain into memos, so the
			frozen one is usually consumed through `use()` and never through the
			public `get`. The check lived only in `get`, so the ordinary shape served
			stale data forever with `lastError` nil. ]]
		local core = Facet.newCore()
		local a = core:signal(1)
		local inner = core:memo(function(use)
			return use(a) * 2
		end)
		local outer = core:memo(function(use)
			return use(inner) + 100
		end)
		expect(outer:get()).toBe(102)
		a:dispose()
		expect(core:lastError()).toBe(nil)

		-- the ONLY read is transitive: `outer` is stale-free, so force a recompute
		-- through a second live input rather than touching `inner` directly
		local nudge = core:signal(0)
		local reader = core:memo(function(use)
			return use(inner) + use(nudge)
		end)
		expect(reader:get()).toBe(2)
		local err = tostring(core:lastError())
		expect(string.find(err, "can no longer update", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "memo@reactive_recovery", 1, true) ~= nil).toBe(true)
		-- ...and the disposed SIGNAL is named distinguishably, not as its kind
		expect(string.match(err, "'signal#%d+'") ~= nil).toBe(true)
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

	it("an INNOCENT settle survives a cap blown by an unrelated effect (NEW-2)", function()
		--[[ The shape the first version of this quarantine broke. A settle that
			publishes ONCE and converges is the measure→publish cycle the settle phase
			exists for — and its legitimate publication is exactly what can arm a
			runaway effect. Keeping only "who wrote last" quarantined the publisher;
			the discriminator is how many PASSES it wrote on, because a converging
			settle writes at most once per flush and a non-converging one writes on
			every pass. In the framework itself the victim would have been
			`renderer.luau`'s geometry-feedback solve, dead for the life of the
			surface after one cap hit anywhere in the session. ]]
		local core = Facet.newCore()
		local measured = core:signal(0)
		local published = core:signal(0)
		local runaway = core:signal(0)
		local settleRuns = 0
		core:settle(function()
			settleRuns += 1
			-- publishes once per real change and then has nothing to do: converges
			local want = measured:get() * 2
			if published:get() ~= want then
				published:set(want)
			end
		end)
		-- an effect the publication wakes, and which then never stops writing —
		-- unrelated to the settle's own convergence, but downstream of it
		core:effect(function(use)
			local seen = use(published)
			local v = runaway:get()
			if seen > 0 and v < 1e9 then
				runaway:set(v + 1)
			end
		end)
		core:effect(function(use)
			local v = use(runaway)
			if v > 0 and v < 1e9 then
				runaway:set(v + 1)
			end
		end)

		--[[ ONE top-level write. The settle publishes (once), the publication is
			what ARMS the runaway effect, and the cap then blows inside the propagate
			loop with the innocent publisher standing as "the settle that wrote last
			in this flush". That ordering is the whole finding. ]]
		measured:set(5)
		expect(published:get()).toBe(10)
		expect(string.find(tostring(core:lastError()), "iteration cap", 1, true) ~= nil).toBe(true)
		-- THE ASSERTION: the innocent publisher was not blamed
		expect(string.find(tostring(core:lastError()), "is QUARANTINED", 1, true)).toBe(nil)

		-- ...and it still runs, and still publishes, on every later flush
		local before = settleRuns
		measured:set(7)
		expect(settleRuns > before).toBe(true)
		expect(published:get()).toBe(14)
		local unrelated = core:signal(0)
		unrelated:set(1)
		core:flush()
		expect(settleRuns > before + 1).toBe(true)
	end)

	it("a quarantined settle comes back when it is RE-REGISTERED (RR-9's stated exit)", function()
		--[[ The contract's "until its inputs change" has no meaning for a callback
			whose inputs the core cannot see, so the documented exit is
			re-registration — and an exit nobody has exercised is an exit nobody
			knows exists. This is that exercise. ]]
		local core = Facet.newCore()
		local s = core:signal(0)
		local runs = 0
		local dispose = core:settle(function()
			runs += 1
			s:set(s:get() + 1)
		end)
		s:set(1)
		expect(string.find(tostring(core:lastError()), "is QUARANTINED", 1, true) ~= nil).toBe(true)
		local afterQuarantine = runs
		local other = core:signal(0)
		other:set(1)
		core:flush()
		expect(runs).toBe(afterQuarantine) -- skipped, as quarantined means

		-- RE-REGISTER: dispose the handle and settle again. The new record carries
		-- no quarantine, so the callback is live again — and if its inputs really
		-- did change it now converges instead of blowing the cap.
		dispose()
		local settled = 0
		core:settle(function()
			settled += 1
		end)
		other:set(2)
		core:flush()
		expect(settled > 0).toBe(true)
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

--[[ RR-12 — THE ONE-OBSERVER NOTIFY PATH.

	The review priced per-flush allocation: a snapshot table and a `table.sort`
	PER NOTIFIED NODE, three tables per round, a closure and a dependency set per
	pull. Measured on this host, one flush is 0.0005 ms bare and 0.0508 ms with a
	fan-out of fifty observed memos, and the allocation is a lower bound of about
	half a kilobyte to four kilobytes depending on shape (Lune has no forced
	collection, so a heap NET is worthless here — see tools/lune/bench.luau's
	header; the estimator sums only POSITIVE gcinfo window deltas and therefore
	under-reports).

	The snapshot exists for one reason, recorded at the code: observers added or
	disposed BY A CALLBACK must not corrupt the iteration, and the order must be
	registration order. At a fan-out of ONE — which is the overwhelmingly common
	shape in a mounted tree, one binding per property — there is no order to
	establish and nothing to sort, and the snapshot buys only its own allocation.
	So the fast path reads the single observer into a local and calls it with no
	table and no sort.

	MEASURED IN SCENES, which is the bar the wave's brief set for touching this at
	all: perf.sh p95, five interleaved samples a side — `animation-interruption`
	0.347 -> 0.106 ms (-69%), `collection-mutation` 1.214 -> 0.864 (-29%),
	`hud-binding-storm` 0.220 -> 0.206 (-6%). `screen-lifecycle-churn` also fell
	(3.11 -> 1.73 median) but that scene swings by more than the difference on
	this host and is not claimed.

	EVERY CASE BELOW IS AT FAN-OUT ONE ON PURPOSE, and the last one is the
	crossover: it proves the snapshot path is still reached, so a fast path that
	swallowed the general case would fail here rather than silently. ]]
describe("the one-observer notify path keeps every snapshot guarantee (RR-12)", function()
	it("an observer that disposes ITSELF mid-callback is not called again", function()
		local core = Facet.newCore()
		local s = core:signal(0)
		local calls = 0
		local stop: any = nil
		stop = core:observe(s, function()
			calls += 1
			stop()
		end)
		s:set(1)
		expect(calls).toBe(1)
		s:set(2)
		expect(calls).toBe(1)
	end)

	it("an observer that ADDS one mid-callback does not deliver to it in the same round", function()
		local core = Facet.newCore()
		local s = core:signal(0)
		local seen: { string } = {}
		core:observe(s, function(v: any)
			table.insert(seen, `first:{v}`)
			if #seen == 1 then
				core:observe(s, function(w: any)
					table.insert(seen, `second:{w}`)
				end)
			end
		end)
		s:set(1)
		-- the newcomer was registered DURING this round and does not receive it
		expect(table.concat(seen, ",")).toBe("first:1")
		s:set(2)
		-- ...and does receive the next one, in registration order behind the first
		expect(table.concat(seen, ",")).toBe("first:1,first:2,second:2")
	end)

	it("a memo that RECOMPUTED to an equal value delivers nothing to its lone observer", function()
		--[[ The eq check has to live at the OBSERVER, not only at the write: a
			signal write already short-circuits on eq and never reaches `notify` at
			all, so a case built on `s:set(7)` when s is 7 would pass with the check
			deleted. The shape that reaches it is a MEMO with a value eq whose
			dependency moved and whose result did not — which is the whole of RR-5
			one layer down. ]]
		local core = Facet.newCore()
		local input = core:signal(1)
		local computes = 0
		local sameFields = function(a: any, b: any): boolean
			return type(a) == "table" and type(b) == "table" and a.px == b.px
		end
		local dim = core:memo(function(use)
			computes += 1
			local _ = use(input)
			return { type = "fixed", px = 40 }
		end, sameFields)
		local calls = 0
		core:observe(dim, function()
			calls += 1
		end)
		expect(computes).toBe(1)
		input:set(2)
		-- it DID recompute (so this is not a case about a memo that never ran)…
		expect(computes).toBe(2)
		-- …and delivered nothing, because the value it produced was equal
		expect(calls).toBe(0)
	end)

	it("a THROWING lone observer is quarantined and still works on the next write", function()
		--[[ The quarantine this pins is `propagateRound`'s own `pcall(notify, …)`,
			not the one inside the loop — measured by mutation: deleting the fast
			path's inner pcall changes nothing at fan-out one, because there is no
			next observer for it to protect. What the fast path must not do is
			bypass the outer one, and the failure mode if it did is not the error
			message but the SECOND write: an escape out of `flush` strands
			`flushing = true` and every later write in the session goes nowhere. ]]
		local core = Facet.newCore()
		local s = core:signal(0)
		local calls = 0
		core:observe(s, function()
			calls += 1
			if calls == 1 then
				error("observer blew up", 0)
			end
		end)
		s:set(1)
		expect(calls).toBe(1)
		expect(string.find(tostring(core:lastError()), "observer blew up", 1, true) ~= nil).toBe(true)
		-- the flush did not wedge: the next write reaches the same observer
		s:set(2)
		expect(calls).toBe(2)
	end)

	it("at fan-out two, an observer DISPOSED by the one before it is not called", function()
		--[[ Where the `disposed` flag is actually reachable, and therefore where it
			has to be pinned. At fan-out one it is unreachable by construction — the
			disposer removes the record from `node.observers` before the next round
			can see it — so only the snapshot path, which captured the record before
			the callback ran, can hold a stale one. ]]
		local core = Facet.newCore()
		local s = core:signal(0)
		local seen: { string } = {}
		local stopSecond: any = nil
		core:observe(s, function()
			table.insert(seen, "first")
			stopSecond()
		end)
		stopSecond = core:observe(s, function()
			table.insert(seen, "second")
		end)
		s:set(1)
		expect(table.concat(seen, ",")).toBe("first")
	end)

	it("THE CROSSOVER: at fan-out two the order is registration order, not hash order", function()
		--[[ The negative control for everything above. `node.observers` is a hash
			table, so iteration order is not registration order and cannot be relied
			on — that is what the sorted snapshot is for. Three observers registered
			in a deliberately unhelpful order must still fire 1, 2, 3. ]]
		local core = Facet.newCore()
		local s = core:signal(0)
		local order: { string } = {}
		for _, name in { "a", "b", "c" } do
			core:observe(s, function()
				table.insert(order, name)
			end)
		end
		s:set(1)
		expect(table.concat(order, ",")).toBe("a,b,c")
	end)
end)
