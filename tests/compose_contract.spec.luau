--!strict
--[[ WHAT FACET RELIES ON FROM THE VENDORED RUNTIME, AND FROM ITS OWN SERVICES.

	THE COVERAGE THIS REPLACES. `tests/conformance/suite.luau` used to run 28
	scheduler/lifetime checks against every core candidate, because a core was a
	PLUGGABLE CONTRACT and a second implementation had to be certifiable against
	the first. That contract is gone: there is one runtime now, vendored read-only
	under `src/vendor/compose`, and `src/core/services.luau` builds one core on it.
	The checks that certified the PLUGGABILITY went with it and are not restored —
	they had no subject left.

	THE REST OF THEM STILL HAVE ONE. Facet does not implement propagation any
	more, but it PROMISES behaviour on top of it: every control in this repository
	is written as if a diamond cannot glitch, as if one batch delivers once, as if
	a failing formula does not corrupt its neighbours, and as if an owner's
	disposal is final and idempotent. Vendored code is still code that can move —
	`src/vendor/compose/UPSTREAM.lock` pins a version, and a bump is a normal
	change — so those promises are asserted HERE, against the runtime Facet
	actually ships and through the services that wrap it, rather than assumed from
	an upstream README.

	TWO LAYERS, DELIBERATELY:

	  * the RUNTIME's own properties, read through `Compose` exactly as a control
	    reads them (`cell`, `formula`, `watch`, `createOwner`);
	  * FACET's, which are the ones no upstream test can hold: the containment
	    `services.new` installs (a failure is reported and `lastError` records it,
	    rather than thrown into whoever wrote), and `render/settle_pass.luau`'s
	    100-round cap with the quarantine of the callback that would not converge.

	EVERY CASE DRIVES A REAL REACTOR. No stubs stand in for propagation, because a
	stub cannot glitch and a check that cannot fail is decoration. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Compose = require("../src/vendor/compose/core")
local services = require("../src/core/services")
local settle_pass = require("../src/render/settle_pass")

-- A core with its warnings captured rather than printed: containment is the
-- SUBJECT of several cases below, and a subject that writes to the suite's own
-- transcript is unreadable.
local function newCore(): (any, { string })
	local warnings: { string } = {}
	local core = services.new({
		warn = function(message: string)
			table.insert(warnings, message)
		end,
		-- a clock that never advances keeps the repeat-suppression window closed,
		-- so a case that expects two announcements gets two
		now = function()
			return 0
		end,
	})
	return core, warnings
end

-- ===========================================================================
-- (a) PROPAGATION — the properties every control is written against
-- ===========================================================================

describe("compose contract: propagation", function()
	it("a DIAMOND is glitch-free: the join never sees one leg updated and the other not", function()
		local core = newCore()
		-- a -> b, a -> c, d(b, c): a reader of d must never observe a state where
		-- b reflects the new write but c the old one.
		local a = Compose.cell(1)
		local b = Compose.formula(function(use)
			return use(a) + 1
		end)
		local c = Compose.formula(function(use)
			return use(a) * 10
		end)
		local d = Compose.formula(function(use)
			return { fromB = use(b), fromC = use(c) }
		end)
		local observed: { any } = {}
		core.owner.watch(function(use)
			table.insert(observed, use(d))
		end)
		expect(#observed).toBe(1)
		a:set(5)
		-- ONE delivery for one write, and it is CONSISTENT: b and c both describe
		-- a = 5. Two deliveries here would be the glitch made visible; one
		-- delivery carrying fromB = 6 with fromC = 10 would be the glitch hidden.
		expect(#observed).toBe(2)
		expect(`b={observed[2].fromB} c={observed[2].fromC}`).toBe("b=6 c=50")
	end)

	it("a BATCH delivers once, however many writes it contains", function()
		local core = newCore()
		local a = Compose.cell(1)
		local seen: { number } = {}
		core.owner.watch(function(use)
			table.insert(seen, use(a))
		end)
		expect(#seen).toBe(1)
		core.reactor:batch(function()
			a:set(2)
			a:set(3)
			a:set(4)
		end)
		expect(#seen).toBe(2)
		expect(seen[2]).toBe(4)
	end)

	it("an EQUAL write is not a write: nothing is delivered and nothing recomputes", function()
		local core = newCore()
		local a = Compose.cell(7)
		local runs, deliveries = 0, 0
		local doubled = Compose.formula(function(use)
			runs += 1
			return use(a) * 2
		end)
		core.owner.watch(function(use)
			use(doubled)
			deliveries += 1
		end)
		local runsAfterMount, deliveriesAfterMount = runs, deliveries
		a:set(7)
		expect(deliveries).toBe(deliveriesAfterMount)
		expect(runs).toBe(runsAfterMount)
		-- ...and a real change still gets through, so the case above is a skip
		-- rather than a graph that stopped working
		a:set(8)
		expect(deliveries).toBe(deliveriesAfterMount + 1)
	end)

	it("a formula recomputes ONCE per write however many readers it has", function()
		local core = newCore()
		local a = Compose.cell(1)
		local runs = 0
		local shared = Compose.formula(function(use)
			runs += 1
			return use(a) + 1
		end)
		for _ = 1, 3 do
			core.owner.watch(function(use)
				use(shared)
			end)
		end
		local before = runs
		a:set(2)
		expect(runs).toBe(before + 1)
	end)
end)

-- ===========================================================================
-- (b) CONTAINMENT — Facet's promise, not the runtime's
-- ===========================================================================

describe("compose contract: containment", function()
	it("a formula that THROWS does not corrupt its siblings, and the failure is reported", function()
		local core, warnings = newCore()
		local a = Compose.cell(1)
		local bad = Compose.formula(function(use)
			if use(a) > 1 then
				error("boom")
			end
			return use(a)
		end)
		local good = Compose.formula(function(use)
			return use(a) * 2
		end)
		local lastGood, lastBad = nil :: any, nil :: any
		core.owner.watch(function(use)
			lastGood = use(good)
		end)
		core.owner.watch(function(use)
			lastBad = use(bad)
		end)
		expect(lastBad).toBe(1)
		a:set(5)
		-- THE HEALTHY SIBLING IS UNTOUCHED, which is the half a thrown error
		-- destroys: one failing node must not take the surface down with it
		expect(lastGood).toBe(10)
		-- ...THE FAILING ONE KEEPS THE LAST VALUE IT HAD rather than publishing a
		-- nil that every reader downstream then has to defend against
		expect(lastBad).toBe(1)
		-- ...and it was REPORTED, both stickily and out loud, because a contained
		-- failure nobody can see is indistinguishable from no failure
		expect(core.lastError() ~= nil).toBe(true)
		expect(string.find(tostring(core.lastError()), "boom", 1, true) ~= nil).toBe(true)
		expect(#warnings > 0).toBe(true)
		expect(string.find(warnings[1], "boom", 1, true) ~= nil).toBe(true)
	end)

	it("a failure in a WATCH is contained too: it never reaches whoever wrote the cell", function()
		local core = newCore()
		local a = Compose.cell(1)
		core.owner.watch(function(use)
			if use(a) > 1 then
				error("watch boom")
			end
		end)
		-- the writer is ordinary application code with no way to handle another
		-- node's failure, so the write RETURNS rather than throwing
		local ok = pcall(function()
			a:set(2)
		end)
		expect(ok).toBe(true)
		expect(string.find(tostring(core.lastError()), "watch boom", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- (c) LIFETIME — an owner's disposal is final, and idempotent
-- ===========================================================================

describe("compose contract: lifetime", function()
	it("a watch stops the moment its owner is disposed", function()
		local core = newCore()
		local a = Compose.cell(1)
		local seen: { number } = {}
		local scope = core.owner.createChild()
		scope.watch(function(use)
			table.insert(seen, use(a))
		end)
		a:set(2)
		expect(table.concat(seen, ",")).toBe("1,2")
		scope.dispose()
		a:set(3)
		expect(table.concat(seen, ",")).toBe("1,2")
	end)

	it("DOUBLE DISPOSE is safe, on an owner and on the handle a watch hands back", function()
		local core = newCore()
		local a = Compose.cell(1)
		local runs = 0
		local scope = core.owner.createChild()
		local stop = scope.watch(function(use)
			use(a)
			runs += 1
		end)
		stop()
		stop() -- the second call is a no-op, not a throw and not a second release
		a:set(2)
		expect(runs).toBe(1)
		scope.dispose()
		scope.dispose()
		expect(scope.isDisposed()).toBe(true)
		-- ...and the core it hung off is still usable, which is what "safe" means
		a:set(3)
		expect(core.lastError()).toBeNil()
	end)

	it("a child owner dies with its parent, and the parent's size returns to baseline", function()
		local core = newCore()
		local a = Compose.cell(1)
		local seen = 0
		local parent = core.owner.createChild()
		local before = core.owner.size()
		local child = parent.createChild()
		child.watch(function(use)
			use(a)
			seen += 1
		end)
		a:set(2)
		expect(seen).toBe(2)
		parent.dispose()
		expect(child.isDisposed()).toBe(true)
		a:set(3)
		expect(seen).toBe(2)
		-- the parent released its slot on the core owner: a disposal that runs the
		-- cleanups but leaves the entry behind is the leak this asserts against
		expect(core.owner.size()).toBe(before - 1)
	end)

	it("a cleanup that THROWS is contained, and the owner still releases the rest", function()
		local core = newCore()
		local released = 0
		local scope = core.owner.createChild()
		Compose.withOwner(scope, function()
			Compose.cleanup(function()
				released += 1
			end)
			Compose.cleanup(function()
				error("bad cleanup")
			end)
			Compose.cleanup(function()
				released += 1
			end)
		end)
		pcall(scope.dispose)
		expect(released).toBe(2)
		expect(scope.isDisposed()).toBe(true)
	end)
end)

-- ===========================================================================
-- (d) THE SETTLE PASS — Facet's own loop, its cap and its quarantine
-- ===========================================================================

describe("compose contract: the settle pass", function()
	-- a bare reactor plus a pass on it: the pass's own loop is the subject, so
	-- nothing else may be writing into it
	local function newPass(): (any, any, { string })
		local reactor = Compose.reactor()
		local failures: { string } = {}
		local pass = settle_pass.install(reactor, function(message: string)
			table.insert(failures, message)
		end)
		return reactor, pass, failures
	end

	it("a callback that publishes is re-run until the pass converges, inside one flush", function()
		local reactor, pass = newPass()
		local source, published = Compose.cell(0), Compose.cell(-1)
		local runs = 0
		pass.register(function()
			runs += 1
			if published:peek() ~= source:peek() then
				published:set(source:peek())
			end
		end, "publish")
		reactor:batch(function()
			source:set(4)
		end)
		-- the publication landed INSIDE the flush that caused it, which is the
		-- whole reason this pass exists: a surface must not be one frame behind
		expect(published:peek()).toBe(4)
		-- ...and the pass stopped as soon as nothing wrote, rather than spinning
		expect(runs).toBe(2)
	end)

	it("a callback that will NEVER converge hits the 100-round cap and is QUARANTINED", function()
		local reactor, pass, failures = newPass()
		local churn = Compose.cell(0)
		local runs = 0
		pass.register(function()
			runs += 1
			churn:set(churn:peek() + 1) -- always writes: a fixed point that is not one
		end, "runaway")
		reactor:batch(function()
			churn:set(-1)
		end)
		-- THE CAP IS A NUMBER, not "eventually": a loop that will not converge is
		-- a loud error on a bounded budget, never a hang and never a silent frame
		expect(runs).toBeLessThanOrEqual(101)
		expect(#failures).toBe(1)
		expect(string.find(failures[1], "100-round iteration cap", 1, true) ~= nil).toBe(true)
		expect(string.find(failures[1], "runaway", 1, true) ~= nil).toBe(true)
		-- ...AND IT IS QUARANTINED: the next settle does not pay for it again,
		-- which is what stops one bad callback costing 100 rounds every frame
		local runsAfterCap = runs
		reactor:batch(function()
			churn:set(-2)
		end)
		expect(runs).toBe(runsAfterCap)
	end)

	it("a healthy callback registered beside the offender keeps running", function()
		local reactor, pass = newPass()
		local churn, healthy, runaway = Compose.cell(0), 0, 0
		--[[ REGISTRATION ORDER IS THE SUBJECT HERE. A pass restarts from the FIRST
			callback the moment one of them writes, so a callback registered AFTER a
			runaway is never reached at all while the runaway is live — which is
			exactly why the runaway has to be taken out rather than merely stopped
			once. The healthy one is registered first so it is reached on every
			round, and the assertion below is that it is STILL reached after the cap
			has quarantined its neighbour. ]]
		pass.register(function()
			healthy += 1
		end, "healthy")
		pass.register(function()
			runaway += 1
			churn:set(churn:peek() + 1)
		end, "runaway")
		reactor:batch(function()
			churn:set(-1)
		end)
		local healthyAfterCap, runawayAfterCap = healthy, runaway
		expect(healthyAfterCap > 0).toBe(true)
		expect(runawayAfterCap > 0).toBe(true)
		reactor:batch(function()
			churn:set(-2)
		end)
		-- the quarantine took the offender out and left everything else in place
		expect(runaway).toBe(runawayAfterCap)
		expect(healthy).toBe(healthyAfterCap + 1)
	end)

	it("a callback that THROWS is reported and does not end the pass", function()
		local reactor, pass, failures = newPass()
		local later = 0
		pass.register(function()
			error("callback boom")
		end, "thrower")
		pass.register(function()
			later += 1
		end, "after")
		reactor:batch(function() end)
		expect(later > 0).toBe(true)
		expect(#failures).toBe(1)
		expect(string.find(failures[1], "callback boom", 1, true) ~= nil).toBe(true)
	end)

	it("unregistering is idempotent, and a disposed pass runs nothing again", function()
		local reactor, pass = newPass()
		local runs = 0
		local stop = pass.register(function()
			runs += 1
		end, "counted")
		reactor:batch(function() end)
		expect(runs).toBe(1)
		stop()
		stop()
		reactor:batch(function() end)
		expect(runs).toBe(1)
		pass.register(function()
			runs += 1
		end, "second")
		reactor:batch(function() end)
		expect(runs).toBe(2)
		pass.dispose()
		pass.dispose()
		reactor:batch(function() end)
		expect(runs).toBe(2)
	end)
end)
