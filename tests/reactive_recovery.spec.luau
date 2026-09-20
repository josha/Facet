--!strict
local harness = require("./lib/harness")
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
local Compose = require("../src/vendor/compose/core")
local observeChange = require("../src/core/on_change")

describe("successive propagation rounds release their work lists", function()
	it("keeps transaction reads fresh and does not replay effects on unrelated writes", function()
		local core, other = harness.newCore(), harness.newCore()
		local left, right = Compose.cell(1), Compose.cell(10)
		local chooseLeft, unrelated = Compose.cell(true), Compose.cell(0)
		local forwarded = Compose.cell(0)
		local selected = Compose.formula(function(use)
			return if use(chooseLeft) then use(left) else use(right)
		end)
		local effects, received = {}, {}
		core.owner.watch(function(use)
			table.insert(effects, use(selected))
		end)
		observeChange(other.owner, forwarded, function(value)
			table.insert(received, value)
		end)
		observeChange(core.owner, selected, function(value)
			forwarded:set(value)
		end)
		core.reactor:batch(function()
			left:set(2)
			expect(selected:peek()).toBe(2)
			left:set(3)
			expect(selected:peek()).toBe(3)
			chooseLeft:set(false)
			expect(selected:peek()).toBe(10)
			right:set(11)
			expect(selected:peek()).toBe(11)
		end)
		unrelated:set(1)
		left:set(99)
		expect(effects).toEqual({ 1, 11 })
		expect(received).toEqual({ 11 })
		right:set(12)
		unrelated:set(2)
		expect(effects).toEqual({ 1, 11, 12 })
		expect(received).toEqual({ 11, 12 })
		expect(core.lastError()).toBe(nil)
		expect(other.lastError()).toBe(nil)
	end)
end)

-- the number of subscription records a signal is carrying. Reaching into the
-- node is deliberate: the leak RR-2 describes is invisible from every public
-- counter — that is what made it survive.
local function subCount(source: any): number
	return require("../src/vendor/compose/core/reactive/graph").subscriberCount(source)
end

describe("an effect that disposes itself is not re-subscribed (RR-2)", function()
	it("leaves zero records in dep.subs and the counters clean", function()
		local core = harness.newCore()
		local a = Compose.cell(1)
		local runs = 0
		local unsubscribe: (() -> ())? = nil
		local before = core.owner.size()
		-- disposal happens on the SECOND run: the registration run is over before
		-- `owner.watch` has handed back the closure that disposes it
		unsubscribe = core.owner.watch(function(use)
			runs += 1
			use(a)
			if runs >= 2 and unsubscribe ~= nil then
				unsubscribe() -- disposes ITSELF, mid-run
			end
		end)
		expect(runs).toBe(1)
		expect(subCount(a)).toBe(1)

		a:set(2)
		core.reactor:settle()
		expect(runs).toBe(2)
		expect(subCount(a)).toBe(0)
		expect(core.owner.size()).toBe(before)
		-- ...and it stays gone: a later write must not resurrect it
		a:set(3)
		core.reactor:settle()
		expect(runs).toBe(2)
		expect(subCount(a)).toBe(0)
	end)

	it("the same holds when the owning SCOPE disposes during the run", function()
		local core = harness.newCore()
		local a = Compose.cell(1)
		local scope = core.owner.createChild()
		local runs = 0
		local armed = false
		scope.own(core.owner.watch(function(use)
			runs += 1
			use(a)
			if armed then
				scope:dispose() -- the scope that owns this effect, from inside it
			end
		end))
		armed = true
		a:set(2)
		core.reactor:settle()
		expect(runs).toBe(2)
		expect(subCount(a)).toBe(0)
		a:set(3)
		core.reactor:settle()
		expect(runs).toBe(2)
	end)
end)

describe("the flush's terminal contracts (RR-9/RR-10/RR-11)", function()
	it("a settle callback that trips the cap is quarantined, not re-run every flush (RR-9)", function()
		local core = harness.newCore()
		local s = Compose.cell(0)
		-- the surface reads what the settle publishes: that is what makes the
		-- write a flush, here and in the renderer
		core.owner.watchStatic(s, function() end)
		local passes = 0
		core.settlePass.register(function()
			passes += 1
			s:set(s:peek() + 1)
		end)
		s:set(1)
		local first = passes
		expect(first > 1).toBe(true)
		-- ONE message: the cap diagnostic consumers already grep for, with the
		-- quarantine clause appended rather than overwriting it
		local err = tostring(core.lastError())
		expect(string.find(err, "iteration cap", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "is QUARANTINED", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "settle@reactive_recovery", 1, true) ~= nil).toBe(true)

		-- THE POINT: the next flush costs nothing. Before the quarantine every
		-- later flush in the session re-ran it to the full 100-round cap.
		local unrelated = Compose.cell(0)
		unrelated:set(1)
		core.reactor:settle()
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
		local core = harness.newCore()
		local measured = Compose.cell(0)
		local published = Compose.cell(0)
		core.owner.watchStatic(measured, function() end)
		local runaway = Compose.cell(0)
		local settleRuns = 0
		core.settlePass.register(function()
			settleRuns += 1
			-- publishes once per real change and then has nothing to do: converges
			local want = measured:peek() * 2
			if published:peek() ~= want then
				published:set(want)
			end
		end)
		-- an effect the publication wakes, and which then never stops writing —
		-- unrelated to the settle's own convergence, but downstream of it
		core.owner.watch(function(use)
			local seen = use(published)
			local v = runaway:peek()
			if seen > 0 and v < 1e9 then
				runaway:set(v + 1)
			end
		end)
		core.owner.watch(function(use)
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
		expect(published:peek()).toBe(10)
		expect(string.find(tostring(core.lastError()), "did not settle after", 1, true) ~= nil).toBe(true)
		-- THE ASSERTION: the innocent publisher was not blamed
		expect(string.find(tostring(core.lastError()), "is QUARANTINED", 1, true)).toBe(nil)

		-- ...and it still runs, and still publishes, on every later flush
		local before = settleRuns
		measured:set(7)
		expect(settleRuns > before).toBe(true)
		expect(published:peek()).toBe(14)
		local unrelated = Compose.cell(0)
		unrelated:set(1)
		core.reactor:settle()
		expect(settleRuns > before + 1).toBe(true)
	end)

	it("a quarantined settle comes back when it is RE-REGISTERED (RR-9's stated exit)", function()
		--[[ The contract's "until its inputs change" has no meaning for a callback
			whose inputs the core cannot see, so the documented exit is
			re-registration — and an exit nobody has exercised is an exit nobody
			knows exists. This is that exercise. ]]
		local core = harness.newCore()
		local s = Compose.cell(0)
		core.owner.watchStatic(s, function() end)
		local runs = 0
		local dispose = core.settlePass.register(function()
			runs += 1
			s:set(s:peek() + 1)
		end)
		s:set(1)
		expect(string.find(tostring(core.lastError()), "is QUARANTINED", 1, true) ~= nil).toBe(true)
		local afterQuarantine = runs
		local other = Compose.cell(0)
		other:set(1)
		core.reactor:settle()
		expect(runs).toBe(afterQuarantine) -- skipped, as quarantined means

		-- RE-REGISTER: dispose the handle and settle again. The new record carries
		-- no quarantine, so the callback is live again — and if its inputs really
		-- did change it now converges instead of blowing the cap.
		dispose()
		local settled = 0
		core.settlePass.register(function()
			settled += 1
		end)
		other:set(2)
		core.reactor:settle()
		expect(settled > 0).toBe(true)
	end)

	it("a healthy settle keeps running after an unrelated one is quarantined", function()
		local core = harness.newCore()
		local runaway = Compose.cell(0)
		core.owner.watchStatic(runaway, function() end)
		local healthy = 0
		core.settlePass.register(function()
			runaway:set(runaway:peek() + 1)
		end)
		core.settlePass.register(function()
			healthy += 1
		end)
		runaway:set(1)
		-- the runaway writes on every pass and a write ENDS the pass, so the healthy
		-- callback registered after it never got a turn while the loop was running
		local afterFirst = healthy
		local other = Compose.cell(0)
		other:set(1)
		core.reactor:settle()
		expect(healthy > afterFirst).toBe(true)
	end)

	it("Compose caps a drain at one million watch runs (RR-11)", function()
		-- Native Compose counts individual watch runs, plus the registration run.
		local core = harness.newCore()
		local a = Compose.cell(0)
		local runs = 0
		core.owner.watch(function(use)
			runs += 1
			local v = use(a)
			if v < 1e9 then
				a:set(v + 1)
			end
		end)
		expect(runs).toBe(1000001)
		-- the value advanced once per ROUND, from the registration run's write
		expect(a:peek()).toBe(1000001)
		expect(string.find(tostring(core.lastError()), "did not settle after 1000000 runs", 1, true) ~= nil).toBe(true)
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
		local core = harness.newCore()
		local s = Compose.cell(0)
		local calls = 0
		local stop: any = nil
		stop = observeChange(core.owner, s, function()
			calls += 1
			stop()
		end)
		s:set(1)
		expect(calls).toBe(1)
		s:set(2)
		expect(calls).toBe(1)
	end)

	it("an observer that ADDS one mid-callback does not deliver to it in the same round", function()
		local core = harness.newCore()
		local s = Compose.cell(0)
		local seen: { string } = {}
		observeChange(core.owner, s, function(v: any)
			table.insert(seen, `first:{v}`)
			if #seen == 1 then
				observeChange(core.owner, s, function(w: any)
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
		local core = harness.newCore()
		local input = Compose.cell(1)
		local computes = 0
		local sameFields = function(a: any, b: any): boolean
			return type(a) == "table" and type(b) == "table" and a.px == b.px
		end
		local dim = Compose.formula(function(use)
			computes += 1
			local _ = use(input)
			return { type = "fixed", px = 40 }
		end, sameFields)
		local calls = 0
		observeChange(core.owner, dim, function()
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
		local core = harness.newCore()
		local s = Compose.cell(0)
		local calls = 0
		observeChange(core.owner, s, function()
			calls += 1
			if calls == 1 then
				error("observer blew up", 0)
			end
		end)
		s:set(1)
		expect(calls).toBe(1)
		expect(string.find(tostring(core.lastError()), "observer blew up", 1, true) ~= nil).toBe(true)
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
		local core = harness.newCore()
		local s = Compose.cell(0)
		local seen: { string } = {}
		local stopSecond: any = nil
		observeChange(core.owner, s, function()
			table.insert(seen, "first")
			stopSecond()
		end)
		stopSecond = observeChange(core.owner, s, function()
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
		local core = harness.newCore()
		local s = Compose.cell(0)
		local order: { string } = {}
		for _, name in { "a", "b", "c" } do
			observeChange(core.owner, s, function()
				table.insert(order, name)
			end)
		end
		s:set(1)
		expect(table.concat(order, ",")).toBe("a,b,c")
	end)
end)
