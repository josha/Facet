--!strict
--[[ THE TWO `newX` FACTORIES THAT HELD SESSION STATE AND COULD NOT BE PUT DOWN
	(architecture review ARCH-12 / ARCH-13; constitution §2 and §8).

	The constitution's rule is "who disposes it", in order of preference: pass a
	scope and the helper owns its resources there; else `scope:own(handle)` the
	returned object; else the return IS the unsubscribe. `newActionSystem` and
	`newResourceProvider` were in none of those categories. Both are `newX`
	factories, both hold real per-session state — contexts and their signals; a
	cache, in-flight requests, an LRU, a `gaveUp` ledger, and one signal triple per
	live key — and neither had a teardown seam or a stated lifetime. A consumer
	standing a surface up and tearing it down had no way to give either back.

	WHAT THE COUNTERS ARE FOR. The reactive core counts live signals and
	subscriptions, and this repository's discipline is that a teardown claim is
	made against those counters and not against a comment: build, use, dispose,
	and the numbers return to where they started. That is the only instrument that
	can tell "disposed" from "the reference went out of scope and the signals are
	still in the graph".

	RED-FIRST: every case here was written and run before the two `dispose`
	methods existed, and each failed on the missing method; then again with each
	`dispose` stubbed as a no-op, where the counter assertions are what fail.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local actionsLib = require("../src/input/actions")
local resources = require("../src/async/resources")

describe("newActionSystem has a lifetime (ARCH-12)", function()
	it("dispose destroys every context it created and returns the core to baseline", function()
		local core = customCore.new()
		local baseline = core:counters()

		local system = actionsLib.newSystem(core)
		local gameplay = system.createContext({ name = "Gameplay", priority = 1000 })
		local a = gameplay.createAction("Fire", "Bool")
		local ui = system.createContext({ name = "UI", priority = 1500, sink = true })
		ui.createAction("Cancel", "Bool")
		a.bind({ keyCode = "Space" })
		expect(system.contextCount()).toBe(2)

		system.dispose()
		expect(system.contextCount()).toBe(0)
		expect(gameplay.destroyed).toBe(true)
		expect(ui.destroyed).toBe(true)
		--[[ THE POINT OF THE COUNTERS. Every action holds a state signal; a
			"disposed" system that merely dropped its table would leave those signals
			in the graph, alive, for the lifetime of the core — which is the leak
			shape a comment cannot rule out. ]]
		expect(core:counters()).toEqual(baseline)
		expect(core:lastError()).toBe(nil)
	end)

	it("dispose is idempotent, and a disposed system delivers nothing", function()
		local core = customCore.new()
		local system = actionsLib.newSystem(core)
		local ctx = system.createContext({ name = "UI", priority = 1000 })
		local action = ctx.createAction("Fire", "Bool")
		local fired = 0
		action.onPressed(function()
			fired += 1
		end)
		action.bind({ keyCode = "Space" })

		system.deviceKey("Space", true)
		expect(fired).toBe(1)

		system.dispose()
		system.dispose() -- ...and again
		expect(system.contextCount()).toBe(0)
		--[[ A DISPOSED SYSTEM IS INERT, NOT BROKEN. The engine's own input stream
			does not stop the instant a consumer calls dispose — a queued key event
			can arrive after it — so the device entry points must be safe to call and
			must do nothing, rather than throw into the render thread. ]]
		system.deviceKey("Space", true)
		system.deviceKey("Space", false)
		system.deviceAxis("Move", 1, 0)
		expect(fired).toBe(1)
		expect(core:lastError()).toBe(nil)
	end)

	it("a context destroyed by hand before dispose is not destroyed twice", function()
		local core = customCore.new()
		local baseline = core:counters()
		local system = actionsLib.newSystem(core)
		local ctx = system.createContext({ name = "UI", priority = 1000 })
		ctx.createAction("Fire", "Bool")
		ctx.destroy() -- the consumer got there first
		expect(system.contextCount()).toBe(0)
		system.dispose()
		expect(core:counters()).toEqual(baseline)
		expect(core:lastError()).toBe(nil)
	end)
end)

describe("newResourceProvider has a lifetime (ARCH-13)", function()
	local function scopeOf(core: any)
		return core:scope()
	end

	it("dispose drops the cache, the in-flight requests and the give-up ledger", function()
		local core = customCore.new()
		local baseline = core:counters()
		local provider = resources.newProvider(core, { maxConcurrent = 1 })
		local scope = scopeOf(core)

		provider.acquire(scope, "a")
		provider.acquire(scope, "b") -- queued behind the concurrency limit
		local pending = provider.pendingRequests()
		expect(#pending).toBe(1)
		provider.complete("a", pending[1].generation, "A")
		expect(provider.counters().cached).toBe(1)

		provider.dispose()
		local after = provider.counters()
		expect(`cached {after.cached} active {after.active} queued {after.queued} handles {after.handles}`).toBe(
			"cached 0 active 0 queued 0 handles 0"
		)
		expect(#provider.pendingRequests()).toBe(0)
		expect(provider.gaveUp("a")).toBe(false)

		scope:dispose()
		--[[ THE SIGNAL TRIPLE PER LIVE KEY is the state a dropped reference leaks:
			`state`, `value` and `error` are core signals held in `keyState`, so a
			provider that is merely forgotten leaves three per key alive in the graph
			forever. ]]
		expect(core:counters()).toEqual(baseline)
		expect(core:lastError()).toBe(nil)
	end)

	it("dispose is idempotent, and a disposed provider accepts no new work", function()
		local core = customCore.new()
		local provider = resources.newProvider(core, {})
		local scope = scopeOf(core)
		provider.acquire(scope, "a")
		provider.dispose()
		provider.dispose()

		--[[ INERT, NOT BROKEN, for the same reason the action system is: an
			in-flight fetch's completion callback is already scheduled somewhere else
			and will land after teardown. It must be a no-op, not a throw. ]]
		provider.tick()
		expect(provider.complete("a", 1, "late")).toBe("stale")
		expect(provider.fail("a", 1, "late")).toBe("stale")
		expect(provider.counters().cached).toBe(0)

		-- ...and an acquire after dispose does not resurrect the session
		local handle = provider.acquire(scope, "b")
		expect(handle.state:get()).toBe("failed")
		expect(#provider.pendingRequests()).toBe(0)
		scope:dispose()
		expect(core:lastError()).toBe(nil)
	end)
end)
