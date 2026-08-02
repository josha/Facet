--!strict
-- QUARANTINE REGRESSIONS from the sponsor-framework-gaps fresh-context reviews
-- (verifiers RR-1/RR-2/RR-4): user code that throws inside the motion clock, a
-- teardown arriving mid-step, and a throwing scope cleanup — each used to wedge,
-- crash, or corrupt the runtime; each now costs one recorded error and nothing
-- else. These are runtime-integrity pins: the assertions are about what still
-- WORKS afterwards.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any

describe("motion clock: a throwing callback cannot wedge the clock (RR-1)", function()
	it("after a throwing onSettle, later motions still run and the error is recorded", function()
		local core = LuauUI.newCore()
		local clock = LuauUI.motion.newClock(core, {
			now = function()
				return 0
			end,
		})
		local bad = clock:spring(0, "object")
		bad:onSettle(function()
			error("boom in a settle handler")
		end)
		bad:setTarget(1)
		for _ = 1, 120 do
			clock:step(1 / 60)
		end
		expect(type(clock:lastError())).toBe("string")
		-- the clock is NOT wedged: a fresh spring still animates to its target
		local good = clock:spring(0, "object")
		good:setTarget(100)
		for _ = 1, 240 do
			clock:step(1 / 60)
		end
		expect(math.abs(good:get() - 100) < 1).toBe(true)
		expect(clock:activeCount()).toBe(0)
		clock:dispose()
	end)

	it("a throwing onSettle subscriber does not starve the ones after it (RR-12-R1)", function()
		-- settle fires once per arrival: without the per-subscriber quarantine the
		-- first throw skipped every later subscriber's ONLY notification
		local core = LuauUI.newCore()
		local clock = LuauUI.motion.newClock(core, {
			now = function()
				return 0
			end,
		})
		local v = clock:spring(0, "object")
		local laterFired = 0
		v:onSettle(function()
			error("boom in the first settle subscriber")
		end)
		v:onSettle(function()
			laterFired += 1
		end)
		v:setTarget(1)
		for _ = 1, 240 do
			clock:step(1 / 60)
		end
		expect(laterFired).toBe(1)
		expect(type(clock:lastError())).toBe("string")
		clock:dispose()

		-- same guarantee on the reduced-motion announce path, which fires settle
		-- SYNCHRONOUSLY from setTarget, outside the step pcall — the quarantine
		-- must be fireSettle's own, not the frame's
		local core2 = LuauUI.newCore()
		local policy = core2:signal("reduced")
		local clock2 = LuauUI.motion.newClock(core2, {
			motionPolicy = policy,
			now = function()
				return 0
			end,
		})
		local w = clock2:spring(0, "object")
		local placeLater = 0
		w:onSettle(function()
			error("boom on the announce path")
		end)
		w:onSettle(function()
			placeLater += 1
		end)
		w:setTarget(50)
		expect(placeLater).toBe(1)
		expect(type(clock2:lastError())).toBe("string")
		clock2:dispose()
	end)

	it("a throwing live-target function quarantines the frame, not the clock", function()
		local core = LuauUI.newCore()
		local clock = LuauUI.motion.newClock(core, {
			now = function()
				return 0
			end,
		})
		local v = clock:spring(0, "object")
		-- the FIRST read happens synchronously inside setTarget (the seed); the
		-- quarantine under test is the STEP-time read, so throw on read two
		local reads = 0
		v:setTarget(function(): number
			reads += 1
			if reads == 2 then
				error("target read failed")
			end
			return 50
		end)
		for _ = 1, 240 do
			clock:step(1 / 60)
		end
		expect(math.abs(v:get() - 50) < 1).toBe(true)
		clock:dispose()
	end)
end)

describe("motion clock: dispose during a step defers, never crashes (RR-2)", function()
	it("an onSettle handler disposing the clock is safe and completes at the step tail", function()
		local core = LuauUI.newCore()
		local clock = LuauUI.motion.newClock(core, {
			now = function()
				return 0
			end,
		})
		local v = clock:spring(0, "object")
		v:onSettle(function()
			clock:dispose() -- the RR-2 shape: teardown from inside the step
		end)
		v:setTarget(1)
		for _ = 1, 240 do
			if clock:isDisposed() then
				break
			end
			clock:step(1 / 60)
		end
		expect(clock:isDisposed()).toBe(true)
		-- disposed cleanly: counters return through the ordinary path
		expect(clock:activeCount()).toBe(0)
	end)
end)

describe("scope disposal: a throwing cleanup is quarantined (RR-4)", function()
	it("siblings still release, counters stay exact, and no false double-dispose follows", function()
		local core = LuauUI.newCore()
		local scope = core:scope("quarantine")
		local released: { string } = {}
		scope:own(function()
			table.insert(released, "first-owned") -- runs LAST (reverse order)
		end)
		scope:own(function()
			error("cleanup boom")
		end)
		scope:own(function()
			table.insert(released, "last-owned") -- runs FIRST
		end)
		local before = core:counters().scopes
		scope:dispose()
		-- both healthy cleanups ran despite the throw between them
		expect(released).toEqual({ "last-owned", "first-owned" })
		expect(core:counters().scopes).toBe(before - 1)
		-- the quarantined error is visible
		expect(string.find(tostring(core:lastError()), "cleanup", 1, true) ~= nil).toBe(true)
		-- a genuine double dispose is STILL detected (the detector survived)
		scope:dispose()
		expect(string.find(tostring(core:lastError()), "double disposal", 1, true) ~= nil).toBe(true)
	end)

	-- RR-5-R1 (Step 5.5 disposition): the residual reported the detector as a
	-- FALSE positive. Measured, it is not: it fires only when the same child is
	-- owned TWICE — by the parent's own child list AND by a cleanup closure —
	-- which is the §6.3 aliasing violation ARCH-F4 names, and reporting it is the
	-- detector doing its job. Both directions are pinned so the decision cannot
	-- be quietly reversed into a suppressed diagnostic.
	it("the double-dispose report fires for an ALIASED child and stays silent otherwise (RR-5-R1)", function()
		local core = LuauUI.newCore()
		local parent = core:scope("p")
		local child: any = nil
		parent:own(function()
			child:dispose() -- second owner of a scope the parent already owns
		end)
		child = parent:child("c")
		local before = core:counters().scopes
		parent:dispose()
		expect(string.find(tostring(core:lastError()), "double disposal", 1, true) ~= nil).toBe(true)
		-- and the walk is still SOUND: no double free, both scopes released
		expect(core:counters().scopes).toBe(before - 2)

		-- the same cleanup SHAPE over a scope the parent does not own is silent
		local core2 = LuauUI.newCore()
		local owner = core2:scope("owner")
		local standalone = core2:scope("standalone")
		owner:own(function()
			standalone:dispose()
		end)
		owner:dispose()
		expect(core2:lastError()).toBe(nil)
	end)
end)

-- F-13. `own` used to insert whatever it was handed and `dispose` used to fall
-- through anything it could not release, with no diagnostic — so an ownership
-- statement over an unreleasable table read as correct, reviewed as correct, and
-- did nothing. The library's own shipped gallery scenario did exactly that. The
-- accepted-but-ignored class is the failure this diagnoses AT own(), where the
-- mistake is, rather than never.
describe("scope ownership: an unreleasable resource is refused at own() (F-13)", function()
	it("a table with no dispose() is refused, naming the scope and the fix", function()
		local core = LuauUI.newCore()
		local scope = core:scope("ownership")
		local ok, err = pcall(function()
			scope:own({ pendingRequests = function() end }) -- a provider-shaped table
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "LuauUI scope:", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "ownership", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "dispose", 1, true) ~= nil).toBe(true)
		-- refusing is not corrupting: the scope never took it, and still works
		local released = false
		scope:own(function()
			released = true
		end)
		scope:dispose()
		expect(released).toBe(true)
	end)

	it("functions, child scopes, and dispose-bearing objects all stay legal", function()
		local core = LuauUI.newCore()
		local before = core:counters()
		local scope = core:scope("legal")
		local order: { string } = {}
		scope:own(function()
			table.insert(order, "function")
		end)
		scope:own(core:signal(1)) -- a Readable disposes itself
		scope:own(core:memo(function()
			return 1
		end))
		scope:child("kid")
		scope:own({
			dispose = function()
				table.insert(order, "object")
			end,
		})
		scope:dispose()
		expect(order).toEqual({ "object", "function" })
		expect(core:counters()).toEqual(before)
	end)

	it("`use` still borrows anything — only OWNERSHIP implies releasability", function()
		local core = LuauUI.newCore()
		local scope = core:scope("borrow")
		local borrowed = { name = "not mine to release" }
		expect(scope:use(borrowed)).toBe(borrowed)
		scope:dispose()
	end)
end)

describe("motion clock: the stats contract under a quarantined frame (RR-1-R2)", function()
	it("transactions counts frames that really committed, never the aborted ones", function()
		local core = LuauUI.newCore()
		local clock = LuauUI.motion.newClock(core, {
			now = function()
				return 0
			end,
		})
		local v = clock:spring(0, "object")
		local reads = 0
		v:setTarget(function(): number
			reads += 1
			if reads >= 2 then
				error("live target keeps throwing")
			end
			return 10
		end)
		for _ = 1, 30 do
			clock:step(1 / 60)
		end
		local stats = clock:stats()
		-- the documented invariant is `transactions <= steps`, equality exactly
		-- when no frame aborted BEFORE the commit phase: a `pre` throw aborts
		-- there, so that frame opened no transaction and must not be counted.
		-- (Not "equality when lastError is nil" — a quarantined POST-phase
		-- subscriber error sets lastError without costing a transaction;
		-- verifier RT-2.)
		-- `<= steps` was the original assertion and it pinned NOTHING (verifier
		-- PG-1, mutation-proven): counting the aborted frames satisfies it too.
		-- The exact measured value is the pin — every one of the 30 steps aborts
		-- in `pre`, so a correct clock opens zero transactions
		expect(stats.steps > 0).toBe(true)
		expect(stats.transactions).toBe(0)
		expect(type(clock:lastError())).toBe("string")
		clock:dispose()

		-- healthy clock: the two agree exactly, which is what the batching claim rests on
		local core2 = LuauUI.newCore()
		local clock2 = LuauUI.motion.newClock(core2, {
			now = function()
				return 0
			end,
		})
		local w = clock2:spring(0, "object")
		w:setTarget(100)
		for _ = 1, 30 do
			clock2:step(1 / 60)
		end
		local healthy = clock2:stats()
		expect(clock2:lastError()).toBe(nil)
		expect(healthy.transactions).toBe(healthy.steps)
		clock2:dispose()
	end)
end)
