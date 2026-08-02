--!strict
-- Perceptual arrival (ADR-0022 Decision 1; acceptance rows SF-M2, SF-M3). Two
-- scalar springs, one live target, and the claim that matters: arrival fires on
-- the frame the object visually LANDS, not when the solver's epsilon trips.
--
-- The headline case reproduces the trailing measured in the shipped
-- implementation: the same flight, timed twice — once to the 4 px radius, once
-- to settle. Radius arrival lands at frame 20 (0.333 s) and settle at frame 63
-- (1.050 s), so a beat fired on settle would reach the player 0.717 s after they
-- saw the thing land — the ~0.7 s the ADR cites, reproduced here.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local clockLib = require("../src/motion/clock")

local FRAME = 1 / 60

local function fixture()
	local core = customCore.new()
	local policy = core:signal("full")
	local clock = clockLib.new(core, {
		motionPolicy = policy,
		now = function()
			return 0
		end,
	})
	return core, policy, clock
end

-- step until `predicate` is true, returning the frame count (or -1)
local function stepUntil(clock: any, predicate: () -> boolean, limit: number?): number
	for frame = 1, limit or 900 do
		clock:step(FRAME)
		if predicate() then
			return frame
		end
	end
	return -1
end

describe("motion chase: perceptual arrival", function()
	it("fires on the radius frame, well before the settle epsilon would", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local arrivals: { any } = {}
		local flight = clock:chase({
			x = x,
			y = y,
			target = function()
				return 400, 300
			end,
			onArrive = function(info)
				table.insert(arrivals, info)
			end,
		})
		local arriveFrame = stepUntil(clock, function()
			return flight:isDone()
		end)
		expect(arriveFrame).toBeGreaterThan(0)
		expect(#arrivals).toBe(1)
		expect(arrivals[1].how).toBe("radius")
		expect(arrivals[1].targetLost).toBe(false)
		-- the object really is on top of the target when we say it arrived
		expect(math.abs(x:get() - 400)).toBeLessThanOrEqual(4)
		expect(math.abs(y:get() - 300)).toBeLessThanOrEqual(4)

		-- and the same flight, timed to settle instead
		local settleFrame = stepUntil(clock, function()
			return x:isSettled() and y:isSettled()
		end) + arriveFrame
		expect(settleFrame).toBeGreaterThan(arriveFrame)
		-- the trailing an arrival-on-settle contract would ship to the player
		expect((settleFrame - arriveFrame) * FRAME).toBeGreaterThan(0.6)
		expect(#arrivals).toBe(1) -- and it never fires a second time
	end)

	it("the chase detaches on arrival: nothing keeps stepping for it", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local flight = clock:chase({
			x = x,
			y = y,
			target = function()
				return 40, 40
			end,
			onArrive = function() end,
		})
		expect(clock:activeCount()).toBe(3) -- two springs and the chase
		stepUntil(clock, function()
			return flight:isDone()
		end)
		expect(clock:activeCount()).toBeLessThanOrEqual(2) -- the chase is gone
		stepUntil(clock, function()
			return clock:activeCount() == 0
		end)
		expect(clock:activeCount()).toBe(0) -- and the springs sleep after it
	end)

	it("a wider radius arrives earlier than a tight one (the knob is real)", function()
		local function framesToArrive(radius: number?): number
			local _, _, clock = fixture()
			local x = clock:spring(0, "object")
			local y = clock:spring(0, "object")
			local flight = clock:chase({
				x = x,
				y = y,
				target = function()
					return 400, 300
				end,
				arriveRadius = radius,
				onArrive = function() end,
			})
			return stepUntil(clock, function()
				return flight:isDone()
			end)
		end
		local tight = framesToArrive(2)
		local wide = framesToArrive(40)
		expect(wide).toBeGreaterThan(0)
		expect(wide).toBeLessThan(tight)
	end)

	it("chases a target that moves mid-flight and lands on the MOVED one", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local targetX, targetY = 400, 300
		local arrivals: { any } = {}
		local flight = clock:chase({
			x = x,
			y = y,
			target = function()
				return targetX, targetY
			end,
			onArrive = function(info)
				table.insert(arrivals, info)
			end,
		})
		for _ = 1, 8 do
			clock:step(FRAME)
		end
		expect(flight:isDone()).toBe(false)
		targetX, targetY = 120, 700 -- the row re-sorted under the flight
		stepUntil(clock, function()
			return flight:isDone()
		end)
		expect(#arrivals).toBe(1)
		expect(arrivals[1].how).toBe("radius")
		expect(math.abs(x:get() - 120)).toBeLessThanOrEqual(4)
		expect(math.abs(y:get() - 700)).toBeLessThanOrEqual(4)
	end)

	it("a target that keeps running is never declared arrived at a stale pixel", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local position = 0
		local arrivals: { any } = {}
		clock:chase({
			x = x,
			y = y,
			target = function()
				return position, 0
			end,
			onArrive = function(info)
				table.insert(arrivals, info)
			end,
		})
		-- a target moving faster than the spring can close: it must not "arrive"
		for _ = 1, 60 do
			position += 40 -- 2400 px/s
			clock:step(FRAME)
		end
		expect(#arrivals).toBe(0)
		expect(x:get()).toBeLessThan(position)
		-- when it stops, the chase catches up and reports the radius honestly
		stepUntil(clock, function()
			return #arrivals > 0
		end)
		expect(#arrivals).toBe(1)
		expect(arrivals[1].how).toBe("radius")
		expect(math.abs(x:get() - position)).toBeLessThanOrEqual(4)
	end)

	it("a vanished target resolves by SETTLE and says so (targetLost)", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local live = true
		local arrivals: { any } = {}
		local flight = clock:chase({
			x = x,
			y = y,
			target = function()
				if not live then
					return nil, nil
				end
				return 500, 500
			end,
			onArrive = function(info)
				table.insert(arrivals, info)
			end,
		})
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		live = false -- the row unmounted mid-flight
		stepUntil(clock, function()
			return flight:isDone()
		end)
		expect(#arrivals).toBe(1)
		expect(arrivals[1].how).toBe("settle")
		expect(arrivals[1].targetLost).toBe(true)
		-- it parks on the last good read rather than freezing where it was
		expect(x:get()).toBe(500)
		expect(y:get()).toBe(500)
	end)

	it("cancel abandons the chase without an arrival event", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local arrivals = 0
		local flight = clock:chase({
			x = x,
			y = y,
			target = function()
				return 400, 300
			end,
			onArrive = function()
				arrivals += 1
			end,
		})
		for _ = 1, 5 do
			clock:step(FRAME)
		end
		flight:cancel()
		expect(flight:isDone()).toBe(true)
		stepUntil(clock, function()
			return clock:activeCount() == 0
		end)
		expect(arrivals).toBe(0)
		flight:cancel() -- idempotent
		expect(arrivals).toBe(0)
	end)

	it("under reduced motion the flight is instant and the arrival still fires", function()
		local _, policy, clock = fixture()
		policy:set("reduced")
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local arrivals: { any } = {}
		local flight = clock:chase({
			x = x,
			y = y,
			target = function()
				return 400, 300
			end,
			onArrive = function(info)
				table.insert(arrivals, info)
			end,
		})
		-- no step at all: placement and the semantic event both landed
		expect(x:get()).toBe(400)
		expect(y:get()).toBe(300)
		expect(flight:isDone()).toBe(true)
		expect(#arrivals).toBe(1)
		expect(arrivals[1].how).toBe("radius")
		expect(arrivals[1].targetLost).toBe(false)
		expect(clock:activeCount()).toBe(0)
		expect(clock:stats().steps).toBe(0)
	end)

	it("under reduced motion a vanished target still reports the honest outcome", function()
		local _, policy, clock = fixture()
		policy:set("reduced")
		local x = clock:spring(0, "object")
		local y = clock:spring(0, "object")
		local arrivals: { any } = {}
		clock:chase({
			x = x,
			y = y,
			target = function()
				return nil, nil
			end,
			onArrive = function(info)
				table.insert(arrivals, info)
			end,
		})
		expect(#arrivals).toBe(1)
		expect(arrivals[1].how).toBe("settle")
		expect(arrivals[1].targetLost).toBe(true)
	end)

	it("requires both axes and a target function (2-D motion is two springs)", function()
		local _, _, clock = fixture()
		local x = clock:spring(0, "object")
		expect(function()
			clock:chase({
				x = x,
				target = function()
					return 0, 0
				end,
			} :: any)
		end).toThrow()
		expect(function()
			clock:chase({ x = x, y = clock:spring(0, "object") } :: any)
		end).toThrow()
	end)
end)
