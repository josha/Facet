--!strict
-- ASYNC COMPLETENESS (acceptance rows SF-A1, SF-A2, SF-A3).
-- Everything here is scripted: a fake transport answers the provider's pending
-- window, and a fake clock decides when a spaced retry is due — so "two attempts,
-- half a second apart, then give up" is a proposition and not a hope.
--
-- What each block is really guarding:
--   * RETRY IS BOUNDED. It ends. A key that spends its budget is failed for the
--     session and no later acquire quietly starts it over — the failure mode a
--     retry loop has is that it never stops.
--   * A SPACED RETRY IS INVISIBLE UNTIL IT IS DUE. It is not in the transport's
--     window, so a transport that drains everything it sees cannot burn the
--     spacing by asking immediately.
--   * LOGICAL CANCEL IS UNCHANGED BY PRELOAD. Releasing a warm set prevents work
--     that has not started; a completion that lands after it is stale.
--   * FAILURE STAYS SILENT (SF-A1). The placeholder persists; nothing renders a
--     spinner or a broken glyph, and the dim treatment rides the authored tint.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local customFactory = require("../src/core/custom")
local resources = require("../src/async/resources")
local async_image = require("../src/controls/async_image")

type Fixture = {
	core: any,
	provider: any,
	scope: any,
	advance: (seconds: number) -> (),
	window: () -> { any },
	failAll: (message: string) -> number,
}

local function fixture(opts: any?): Fixture
	local core = customFactory.new()
	local now = 0
	local options: any = opts or {}
	options.now = function()
		return now
	end
	local provider = resources.newProvider(core, options)
	return {
		core = core,
		provider = provider,
		scope = core:scope("async"),
		advance = function(seconds: number)
			now += seconds
			provider.tick()
		end,
		window = function()
			return provider.pendingRequests()
		end,
		failAll = function(message: string): number
			local n = 0
			for _, request in provider.pendingRequests() do
				provider.fail(request.key, request.generation, message)
				n += 1
			end
			return n
		end,
	}
end

describe("bounded retry: the schedule", function()
	it("a failure retries up to `count` times and then reports failed", function()
		local f = fixture({ retry = { count = 2 } })
		local handle = f.provider.acquire(f.scope, "avatar")
		expect(handle.state:get()).toBe("pending")
		local first = f.window()[1]
		expect(first.attempt).toBe(1)
		expect(f.provider.fail("avatar", first.generation, "boom")).toBe("retrying")
		local second = f.window()[1]
		expect(second.attempt).toBe(2)
		expect(handle.state:get()).toBe("pending") -- still trying: nothing visible changed
		expect(f.provider.fail("avatar", second.generation, "boom")).toBe("retrying")
		local third = f.window()[1]
		expect(third.attempt).toBe(3)
		expect(f.provider.fail("avatar", third.generation, "gone")).toBe("failed")
		expect(handle.state:get()).toBe("failed")
		expect(handle.error:get()).toBe("gone")
	end)

	it("a retry that succeeds resolves normally, and the failed attempt stays stale", function()
		local f = fixture({ retry = { count = 1 } })
		local handle = f.provider.acquire(f.scope, "avatar")
		local first = f.window()[1]
		f.provider.fail("avatar", first.generation, "flaky")
		local retry = f.window()[1]
		expect(f.provider.complete("avatar", first.generation, "zombie")).toBe("stale")
		expect(f.provider.complete("avatar", retry.generation, "real")).toBe("applied")
		expect(handle.state:get()).toBe("ready")
		expect(handle.value:get()).toBe("real")
	end)

	it("a spaced retry is invisible to the transport until its delay has elapsed", function()
		local f = fixture({ retry = { count = 1, delaySeconds = 0.5 } })
		f.provider.acquire(f.scope, "avatar")
		local first = f.window()[1]
		f.provider.fail("avatar", first.generation, "boom")
		expect(#f.window()).toBe(0) -- waiting, not askable
		f.advance(0.4)
		expect(#f.window()).toBe(0)
		f.advance(0.2)
		expect(#f.window()).toBe(1)
		expect(f.window()[1].attempt).toBe(2)
	end)

	it("releasing the last waiter cancels a retry that is still waiting out its delay", function()
		local f = fixture({ retry = { count = 1, delaySeconds = 0.5 } })
		local handle = f.provider.acquire(f.scope, "avatar")
		local first = f.window()[1]
		f.provider.fail("avatar", first.generation, "boom")
		handle.release()
		f.advance(1)
		expect(#f.window()).toBe(0) -- it never reached the transport
		expect(f.provider.counters().queued).toBe(0)
	end)
end)

describe("bounded retry: the give-up is permanent for the session", function()
	it("a spent budget fails the key, and a later acquire does not start it over", function()
		local f = fixture({ retry = { count = 1 } })
		local handle = f.provider.acquire(f.scope, "avatar")
		f.failAll("boom")
		f.failAll("boom again")
		expect(handle.state:get()).toBe("failed")
		expect(f.provider.gaveUp("avatar")).toBe(true)

		-- a fresh consumer of the same key inherits the failure instead of
		-- re-opening the transport
		local later = f.provider.acquire(f.scope, "avatar")
		expect(later.state:get()).toBe("failed")
		expect(later.error:get()).toBe("boom again")
		expect(#f.window()).toBe(0)
	end)

	it("invalidate is the explicit reset", function()
		local f = fixture({ retry = { count = 0 } })
		f.provider.acquire(f.scope, "avatar")
		f.failAll("boom")
		expect(f.provider.gaveUp("avatar")).toBe(true)
		f.provider.invalidate("avatar")
		expect(f.provider.gaveUp("avatar")).toBe(false)
		local again = f.provider.acquire(f.scope, "avatar")
		expect(again.state:get()).toBe("pending")
		expect(#f.window()).toBe(1)
	end)

	it("the LEGACY retryAttempts option keeps its old promise: a failed key re-requests", function()
		local f = fixture({ retryAttempts = 1 })
		local handle = f.provider.acquire(f.scope, "avatar")
		f.failAll("boom")
		f.failAll("boom")
		expect(handle.state:get()).toBe("failed")
		expect(f.provider.gaveUp("avatar")).toBe(false)
		local again = f.provider.acquire(f.scope, "avatar")
		expect(again.state:get()).toBe("pending")
	end)

	it("a per-acquire retry overrides the provider's policy for that key", function()
		local f = fixture({ retry = { count = 0 } })
		f.provider.acquire(f.scope, "generous", { retry = { count = 2 } })
		local first = f.window()[1]
		expect(f.provider.fail("generous", first.generation, "boom")).toBe("retrying")
		local second = f.window()[1]
		expect(f.provider.fail("generous", second.generation, "boom")).toBe("retrying")
	end)
end)

-- F-12. The sibling four files away in the same public surface (`valueModel.new`)
-- raises named errors for an impossible range; this constructor took the same
-- class of impossible option in silence. `maxConcurrent = 0` is the sharp one:
-- `promote()` can never activate anything, so every request queues forever and
-- the UI simply never loads, with no diagnostic anywhere — not even
-- `core:lastError()`. Refusing it at construction IS the fix.
describe("provider construction is strict (F-12)", function()
	local function build(opts: any): (boolean, string)
		local core = customFactory.new()
		local ok, err = pcall(function()
			resources.newProvider(core, opts)
		end)
		return ok, tostring(err)
	end

	it("maxConcurrent = 0 is refused instead of silently wedging every request", function()
		local ok, err = build({ maxConcurrent = 0 })
		expect(ok).toBe(false)
		expect(string.find(err, "Facet resource provider:", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "maxConcurrent", 1, true) ~= nil).toBe(true)
	end)

	it("maxConcurrent must be a positive INTEGER", function()
		expect((build({ maxConcurrent = -2 }))).toBe(false)
		expect((build({ maxConcurrent = 2.5 }))).toBe(false)
		expect((build({ maxConcurrent = "4" }))).toBe(false)
		expect((build({ maxConcurrent = 0 / 0 }))).toBe(false)
		expect((build({ maxConcurrent = 1 }))).toBe(true)
		expect((build({ maxConcurrent = 8 }))).toBe(true)
	end)

	it("cacheBudget must be a non-negative integer (0 is legal: cache nothing)", function()
		local ok, err = build({ cacheBudget = -1 })
		expect(ok).toBe(false)
		expect(string.find(err, "cacheBudget", 1, true) ~= nil).toBe(true)
		expect((build({ cacheBudget = 1.5 }))).toBe(false)
		expect((build({ cacheBudget = 0 }))).toBe(true)
		expect((build({ cacheBudget = 32 }))).toBe(true)
	end)

	it("a negative retry count or delay is reported, not silently discarded", function()
		local ok, err = build({ retry = { count = -1 } })
		expect(ok).toBe(false)
		expect(string.find(err, "retry.count", 1, true) ~= nil).toBe(true)
		local ok2, err2 = build({ retry = { delaySeconds = -0.5 } })
		expect(ok2).toBe(false)
		expect(string.find(err2, "retry.delaySeconds", 1, true) ~= nil).toBe(true)
		expect((build({ retry = { count = 0, delaySeconds = 0 } }))).toBe(true)
		expect((build({ retry = { count = 3, delaySeconds = 1 } }))).toBe(true)
		expect((build({ retry = { count = "3" } }))).toBe(false)
	end)

	it("no opts at all, and an empty opts table, still build the documented defaults", function()
		expect((build(nil))).toBe(true)
		expect((build({}))).toBe(true)
	end)
end)

describe("preload: warming a declared set", function()
	it("preloads exactly the keys it was handed, under the same concurrency window", function()
		local f = fixture({ maxConcurrent = 2 })
		local warm = f.provider.preload({ "a", "b", "c", "d" })
		expect(#f.window()).toBe(2)
		expect(f.provider.counters().queued).toBe(2)
		expect(#warm.keys).toBe(4)
	end)

	it("a released preload skips work that has not started", function()
		local f = fixture({ maxConcurrent = 1 })
		local warm = f.provider.preload({ "a", "b", "c" })
		local started = f.window()[1]
		warm.release()
		expect(#f.window()).toBe(0)
		expect(f.provider.counters().queued).toBe(0)
		-- and the started one's completion is stale, exactly as a released acquire's is
		expect(f.provider.complete(started.key, started.generation, "late")).toBe("stale")
	end)

	it("a warmed key is already ready when the view finally acquires it — no placeholder", function()
		local f = fixture()
		local warm = f.provider.preload({ "avatar" })
		local request = f.window()[1]
		f.provider.complete("avatar", request.generation, "content://avatar")
		local handle = f.provider.acquire(f.scope, "avatar")
		expect(handle.state:get()).toBe("ready")
		expect(handle.value:get()).toBe("content://avatar")
		warm.release()
	end)

	it("a live view keeps a preloaded request alive after the warm set is released", function()
		local f = fixture()
		local warm = f.provider.preload({ "avatar" })
		local handle = f.provider.acquire(f.scope, "avatar")
		warm.release()
		local request = f.window()[1]
		expect(request ~= nil).toBe(true)
		f.provider.complete("avatar", request.generation, "content://avatar")
		expect(handle.state:get()).toBe("ready")
	end)

	it("preload never re-opens a cached or given-up key", function()
		local f = fixture({ retry = { count = 0 } })
		f.provider.acquire(f.scope, "dead")
		f.failAll("boom")
		local warm = f.provider.preload({ "dead" })
		expect(#f.window()).toBe(0)
		expect(#warm.keys).toBe(1) -- it was asked for, and deliberately not started
	end)

	it("preload churn returns the provider's counters to baseline", function()
		local f = fixture({ maxConcurrent = 2 })
		local baseline = f.provider.counters()
		for _ = 1, 20 do
			local warm = f.provider.preload({ "a", "b", "c" })
			warm.release()
			warm.release() -- idempotent
		end
		local after = f.provider.counters()
		expect(after.active).toBe(baseline.active)
		expect(after.queued).toBe(baseline.queued)
		expect(after.handles).toBe(baseline.handles)
	end)
end)

describe("AsyncImage: silent failure and the dim treatment", function()
	local function build(spec: any)
		local core = customFactory.new()
		local provider = resources.newProvider(core, spec.providerOpts)
		local scope = core:scope("img")
		local image = async_image.build(Facet, core, {
			id = "Avatar",
			scope = scope,
			provider = provider,
			key = "rbxthumb://user",
			retry = spec.retry,
			dimmed = spec.dimmed,
		})
		return core, provider, image
	end

	local function nodeById(bp: any, id: string): any
		if bp.id == id then
			return bp
		end
		for _, child in bp.children or {} do
			local found = nodeById(child, id)
			if found ~= nil then
				return found
			end
		end
		return nil
	end

	it("failure keeps the placeholder — there is no spinner and no broken glyph", function()
		local _, provider, image = build({})
		local request = provider.pendingRequests()[1]
		provider.fail(request.key, request.generation, "no such user")
		expect(image.state:get()).toBe("failed")
		-- the placeholder branch's condition is still true, and the content stays empty
		local content = nodeById(image.blueprint, "Content")
		expect(content.props.image:get()).toBe("")
	end)

	it("a retry option reaches the provider for that key alone", function()
		local _, provider, image = build({ retry = { count = 1 } })
		local first = provider.pendingRequests()[1]
		expect(provider.fail(first.key, first.generation, "flaky")).toBe("retrying")
		local retry = provider.pendingRequests()[1]
		expect(retry.attempt).toBe(2)
		provider.complete(retry.key, retry.generation, "content://ok")
		expect(image.state:get()).toBe("ready")
	end)

	it("a bound `dimmed` blends the image toward the surface, and back", function()
		local core = customFactory.new()
		local provider = resources.newProvider(core)
		local scope = core:scope("img")
		local dimmed = core:signal(false)
		local image = async_image.build(Facet, core, {
			id = "Avatar",
			scope = scope,
			provider = provider,
			key = "rbxthumb://user",
			dimmed = dimmed,
		})
		local content = nodeById(image.blueprint, "Content")
		expect(content.props.tint:get().blend).toBe(0) -- the identity blend
		dimmed:set(true)
		expect(content.props.tint:get().blend).toBe(0.35)
		expect(content.props.tint:get().role).toBe("surface")
		dimmed:set(false)
		expect(content.props.tint:get().blend).toBe(0)
	end)

	it("an image with no `dimmed` declaration claims no continuous colour at all", function()
		local _, _, image = build({})
		expect(nodeById(image.blueprint, "Content").props.tint).toBeNil()
	end)
end)
