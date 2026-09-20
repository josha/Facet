--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local coreLib = harness.coreFactory
local clockLib = require("../src/motion/clock")
local curves = require("../src/motion/curves")
local Facet = require("../src")
local Compose = require("../src/vendor/compose/core")

describe("state-driven motion", function()
	it("starts at state, retargets a memo without jumps, and rests with no clock work", function()
		local core = coreLib.new()
		local source = Compose.cell(0)
		local target = Compose.formula(function(use)
			return use(source) * 2
		end)
		local clock = Facet.motion.newClock(core)
		local painted = clock:animate(target, "object")
		expect(painted:peek()).toBe(0)
		expect(clock:activeCount()).toBe(0)
		source:set(5)
		expect(painted:getTarget()).toBe(10)
		expect(painted:peek()).toBe(0)
		clock:step(1 / 64)
		local before = painted:peek()
		local velocity = painted:getVelocity()
		source:set(-2)
		expect(painted:peek()).toBe(before)
		expect(painted:getVelocity()).toBe(velocity)
		for _ = 1, 256 do
			clock:step(1 / 64)
		end
		expect(painted:peek()).toBe(-4)
		expect(source:peek()).toBe(-2)
		expect(clock:activeCount()).toBe(0)
		clock:dispose()
		target:dispose()
	end)

	it("uses named curves and snaps state-driven theme tint under reduced motion", function()
		curves.registerCurve("state-test", { duration = 0.25, style = "linear" })
		local core = coreLib.new()
		local policy = Compose.cell("full")
		local amount = Compose.cell(0)
		local clock = clockLib.new(core, { motionPolicy = policy })
		local painted = clock:animate(amount, "state-test")
		local tint = Compose.formula(function(use)
			return { from = "control", role = "accent", blend = math.clamp(use(painted), 0, 1) }
		end)
		amount:set(1)
		clock:step(0.125)
		expect(tint:peek().blend).toBe(0.5)
		policy:set("reduced")
		amount:set(0.25)
		expect(tint:peek().blend).toBe(0.25)
		expect(clock:activeCount()).toBe(0)
		tint:dispose()
		clock:dispose()
		curves.reset()
	end)

	it("disposes the observer with the value, scope, or clock and never owns source state", function()
		for _, owner in { "value", "scope", "clock" } do
			local core = coreLib.new()
			-- the census is taken before anything is built, so "back to baseline"
			-- is the whole surface, not one registry of it
			local baseline = core.owner.size()
			local source = Compose.cell(0)
			local scope = core.owner.createChild()
			local clock = clockLib.new(core)
			local painted = clock:animate(source, "object", { scope = scope })
			source:set(1)
			if owner == "value" then
				painted:dispose()
			elseif owner == "scope" then
				scope:dispose()
			else
				clock:dispose()
			end
			source:set(2)
			expect(source:peek()).toBe(2)
			expect(clock:activeCount()).toBe(0)
			expect(core.lastError()).toBe(nil)
			painted:dispose()
			clock:dispose()
			if not scope:isDisposed() then
				scope:dispose()
			end
			expect(core.owner.size()).toBe(baseline)
		end
	end)

	it("refuses malformed sources/options before allocating and quarantines invalid live targets", function()
		local core = coreLib.new()
		local source = Compose.cell(0)
		local clock = clockLib.new(core)
		local scope = core.owner.createChild()
		scope:dispose()
		local baseline = core.owner.size()
		for _, create in
			{
				function()
					clock:animate(0, "object")
				end,
				function()
					clock:animate(source, "unknown")
				end,
				function()
					clock:animate(source, "object", { scpoe = scope })
				end,
				function()
					clock:animate(source, "object", { scope = scope })
				end,
				function()
					clock:animate(source, "object", { scope = {} })
				end,
			}
		do
			expect(create).toThrow()
			expect(core.owner.size()).toEqual(baseline)
		end
		local painted = clock:animate(source, "object")
		source:set(0 / 0)
		expect(painted:getTarget()).toBe(0)
		expect(clock:lastError() ~= nil).toBe(true)
		source:set(1)
		expect(painted:getTarget()).toBe(1)
		clock:dispose()
	end)
end)
