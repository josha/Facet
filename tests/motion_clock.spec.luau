--!strict
-- The motion clock and MotionValue (ADR-0022 Decision 1; acceptance rows SF-M1,
-- SF-M5, SF-M8). Every case here steps a SCRIPTED clock, so "the same frame"
-- means the same frame forever.
--
-- What this file is really guarding:
--   * ONE transaction per stepped frame — proven by a cross-read inside an
--     observer (if two values committed in two flushes, the observer for the
--     first would see the second's stale value), not by trusting a counter.
--   * REST COSTS ZERO — a settled value leaves the active set, and the writes
--     counter stops moving. This is the SF-M8 shape at unit scale.
--   * REDUCED MOTION IS PARITY, NOT DELETION — decorative values snap and fire
--     the same settle event; informational ones keep running to the same
--     wall-clock terminus with quantized (250 ms) writes.
--   * CHURN IS CLEAN — 50 build/step/dispose cycles return the core's counters
--     to baseline.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local clockLib = require("../src/motion/clock")
local blueprint = require("../src/blueprint")

local FRAME = 1 / 60
-- exact in binary, so accumulated elapsed lands on a duration without drift
local TICK = 1 / 64

type Fixture = {
	core: any,
	policy: any,
	clock: any,
	setNow: (seconds: number) -> (),
	advance: (seconds: number) -> (),
	reduce: () -> (),
}

local function fixture(): Fixture
	local core = customCore.new()
	local policy = core:signal("full")
	local now = 0
	local clock = clockLib.new(core, {
		motionPolicy = policy,
		now = function()
			return now
		end,
	})
	return {
		core = core,
		policy = policy,
		clock = clock,
		setNow = function(seconds: number)
			now = seconds
		end,
		-- move the injected wall clock, then let the clock derive its own dt
		advance = function(seconds: number)
			now += seconds
			clock:step()
		end,
		reduce = function()
			policy:set("reduced")
		end,
	}
end

local function stepN(clock: any, frames: number, dt: number?)
	for _ = 1, frames do
		clock:step(dt or FRAME)
	end
end

describe("motion clock: stepping and the active set", function()
	it("a value is a Readable the rest of the framework already knows how to bind", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		expect(value.kind).toBe("signal")
		expect(blueprint.isReadable(value)).toBe(true)
		local doubled = f.core:memo(function(use)
			return use(value) * 2
		end)
		value:setTarget(10)
		stepN(f.clock, 120)
		expect(value:get()).toBe(10)
		expect(doubled:get()).toBe(20)
	end)

	it("derives dt from the injected now() when step() is called bare", function()
		local scripted = fixture()
		local explicit = fixture()
		local a = scripted.clock:spring(0, "object")
		local b = explicit.clock:spring(0, "object")
		a:setTarget(100)
		b:setTarget(100)
		-- TICK is exact in binary, so the derived dt is bit-identical to the
		-- explicit one and the two paths can be compared without slack
		for _ = 1, 10 do
			scripted.advance(TICK)
			explicit.clock:step(TICK)
		end
		expect(a:get()).toBe(b:get())
		expect(a:get()).toBeGreaterThan(0)
		expect(scripted.clock:stats().steps).toBe(10)
	end)

	it("commits every value in ONE transaction per stepped frame", function()
		local f = fixture()
		local a = f.clock:spring(0, "object")
		local b = f.clock:spring(0, "object")
		a:setTarget(100)
		b:setTarget(100)
		local fires = 0
		local bSeenFromA: { number } = {}
		f.core:observe(a, function()
			fires += 1
			table.insert(bSeenFromA, b:get())
		end)
		f.clock:step(FRAME)
		-- one observer notification for the frame...
		expect(fires).toBe(1)
		-- ...and b's write for the SAME frame was already visible: two
		-- transactions would have shown a's observer b's previous value
		expect(bSeenFromA[1]).toBe(b:get())
		expect(bSeenFromA[1]).toBeGreaterThan(0)

		stepN(f.clock, 20)
		local stats = f.clock:stats()
		expect(stats.transactions).toBe(stats.steps)
		expect(fires).toBe(21)
	end)

	it("settled values leave the active set: rest costs zero steps and zero writes", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		expect(f.clock:activeCount()).toBe(0) -- built, not moving
		value:setTarget(100)
		expect(f.clock:activeCount()).toBe(1)
		stepN(f.clock, 200)
		expect(f.clock:activeCount()).toBe(0)
		expect(value:isSettled()).toBe(true)
		local resting = f.clock:stats()
		stepN(f.clock, 60) -- a whole second of a driver running over nothing
		local after = f.clock:stats()
		expect(after.writes).toBe(resting.writes)
		expect(after.steps).toBe(resting.steps) -- a step at rest is not a step
		expect(after.transactions).toBe(resting.transactions)
	end)

	it("lands EXACTLY on the target and fires onSettle exactly once per flight", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		local settles = 0
		value:onSettle(function()
			settles += 1
		end)
		value:setTarget(100)
		stepN(f.clock, 200)
		expect(value:get()).toBe(100) -- not 99.9997
		expect(settles).toBe(1)
		stepN(f.clock, 60)
		expect(settles).toBe(1) -- resting fires nothing

		value:setTarget(0) -- a second flight is a second arrival
		stepN(f.clock, 200)
		expect(value:get()).toBe(0)
		expect(settles).toBe(2)
	end)

	it("a mid-flight re-target continues from the current value and velocity", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		value:setTarget(100)
		stepN(f.clock, 10)
		local atInterrupt = value:get()
		local velocity = value:getVelocity()
		expect(velocity).toBeGreaterThan(0)

		value:setTarget(200)
		expect(value:get()).toBe(atInterrupt) -- the aim moved; the value did not
		expect(value:getVelocity()).toBe(velocity)

		-- frame by frame: no discontinuity across the interrupt, and it keeps
		-- climbing (momentum carried into the new flight)
		local previous = atInterrupt
		for _ = 1, 10 do
			f.clock:step(FRAME)
			expect(value:get()).toBeGreaterThan(previous)
			expect(value:get() - previous).toBeLessThan(30) -- no jump
			previous = value:get()
		end
		stepN(f.clock, 200)
		expect(value:get()).toBe(200)
	end)

	it("a function target is re-read every step, so a moved target still lands", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		local target = 100
		value:setTarget(function()
			return target
		end)
		stepN(f.clock, 10)
		expect(value:get()).toBeLessThan(100)
		target = 500 -- the row re-sorted mid-flight
		stepN(f.clock, 300)
		expect(value:get()).toBe(500) -- never a stale pixel
	end)

	it("a vanished live target freezes the aim on the last good read and settles", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		local target: number? = 100
		value:setTarget(function()
			return target
		end)
		stepN(f.clock, 5)
		target = nil -- the row unmounted
		stepN(f.clock, 300)
		expect(value:get()).toBe(100)
		expect(value:isSettled()).toBe(true)
	end)

	it("stop abandons the aim where the value stands, and fires no arrival", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		local settles = 0
		value:onSettle(function()
			settles += 1
		end)
		value:setTarget(100)
		stepN(f.clock, 5)
		local mid = value:get()
		value:stop()
		expect(f.clock:activeCount()).toBe(0)
		stepN(f.clock, 60)
		expect(value:get()).toBe(mid)
		expect(settles).toBe(0) -- nothing was reached
	end)

	it("snap is placement, not arrival: value+target set, no settle event", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		local settles = 0
		value:onSettle(function()
			settles += 1
		end)
		value:setTarget(100)
		stepN(f.clock, 5)
		value:snap(42)
		expect(value:get()).toBe(42)
		expect(value:getTarget()).toBe(42)
		expect(value:getVelocity()).toBe(0)
		expect(f.clock:activeCount()).toBe(0)
		expect(settles).toBe(0)
	end)

	it("refuses inline class params at the call site", function()
		local f = fixture()
		local ok, err = pcall(function()
			f.clock:spring(0, { dampingRatio = 1, response = 0.3 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "registerClass", 1, true) ~= nil).toBeTruthy()
	end)

	it("refuses an unknown motion kind", function()
		local f = fixture()
		expect(function()
			f.clock:spring(0, "object", { kind = "decoration" })
		end).toThrow()
	end)
end)

describe("motion clock: reduced motion (information parity)", function()
	it("a decorative value snaps to the target and fires the SAME settle event", function()
		local f = fixture()
		f.reduce()
		local value = f.clock:spring(0, "container")
		local settles = 0
		value:onSettle(function()
			settles += 1
		end)
		value:setTarget(100)
		-- instant: no step needed at all, because RM parity must not depend on a
		-- driver being attached
		expect(value:get()).toBe(100)
		expect(settles).toBe(1)
		expect(f.clock:activeCount()).toBe(0)
		expect(f.clock:stats().steps).toBe(0)
		expect(f.clock:stats().writes).toBe(1)
	end)

	it("a velocity seed is inert under reduced motion (there is no seam to smooth)", function()
		local f = fixture()
		f.reduce()
		local value = f.clock:spring(0, "object")
		value:setTarget(100)
		value:setVelocity(900)
		expect(value:get()).toBe(100)
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("the policy is read LIVE: a flight in progress snaps on its next re-target", function()
		local f = fixture()
		local value = f.clock:spring(0, "object")
		value:setTarget(100)
		stepN(f.clock, 5)
		expect(value:get()).toBeLessThan(100)
		f.reduce()
		value:setTarget(250)
		expect(value:get()).toBe(250)
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("an informational value KEEPS RUNNING under RM, quantized to 250 ms writes", function()
		local full = fixture()
		local reduced = fixture()
		reduced.reduce()
		local a = full.clock:spring(0, "object", { kind = "informational" })
		local b = reduced.clock:spring(0, "object", { kind = "informational" })
		local settlesA, settlesB = 0, 0
		a:onSettle(function()
			settlesA += 1
		end)
		b:onSettle(function()
			settlesB += 1
		end)
		a:setTarget(100)
		b:setTarget(100)
		expect(b:get()).toBe(0) -- it did NOT snap: informational motion steps
		expect(reduced.clock:activeCount()).toBe(1)

		stepN(full.clock, 200)
		stepN(reduced.clock, 200)
		-- same terminus, same event...
		expect(a:get()).toBe(100)
		expect(b:get()).toBe(100)
		expect(settlesA).toBe(1)
		expect(settlesB).toBe(1)
		-- ...far fewer writes: the sweep is stepped, not per-frame
		local fullWrites = full.clock:stats().writes
		local reducedWrites = reduced.clock:stats().writes
		expect(reducedWrites).toBeLessThan(fullWrites // 4)
		expect(reducedWrites).toBeGreaterThanOrEqual(3) -- ~4 ticks per second of flight
	end)
end)

describe("motion clock: informational timers", function()
	it("depletes linearly and reaches its terminus on the exact wall-clock frame", function()
		local f = fixture()
		local timer = f.clock:timer({ from = 1, to = 0, duration = 1 })
		local settles = 0
		timer:onSettle(function()
			settles += 1
		end)
		expect(timer:get()).toBe(1)
		expect(timer:motionKind()).toBe("informational") -- a timer's content IS time
		stepN(f.clock, 32, TICK) -- half way
		expect(timer:get()).toBeCloseTo(0.5, 1e-9)
		stepN(f.clock, 31, TICK)
		expect(timer:get()).toBeGreaterThan(0) -- not there yet: 63/64
		expect(settles).toBe(0)
		f.clock:step(TICK) -- frame 64 of 64
		expect(timer:get()).toBe(0)
		expect(settles).toBe(1)
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("under RM it still reaches the terminus at the same moment, with stepped writes", function()
		local f = fixture()
		f.reduce()
		local timer = f.clock:timer({ from = 1, to = 0, duration = 1 })
		local settles = 0
		timer:onSettle(function()
			settles += 1
		end)
		expect(timer:get()).toBe(1) -- still running: nothing was deleted
		stepN(f.clock, 15, TICK)
		expect(timer:get()).toBe(1) -- inside the first 250 ms tick: no write yet
		f.clock:step(TICK) -- crosses 0.25 s
		expect(timer:get()).toBeCloseTo(0.75, 1e-9)
		stepN(f.clock, 48, TICK)
		expect(timer:get()).toBe(0) -- same wall-clock terminus as the full path
		expect(settles).toBe(1)
		local writes = f.clock:stats().writes
		expect(writes).toBeLessThanOrEqual(5) -- four ticks plus the terminal write
		expect(writes).toBeGreaterThanOrEqual(4)
	end)

	it("a DECORATIVE timer is over immediately under RM (declared, not defaulted)", function()
		local f = fixture()
		f.reduce()
		local settles = 0
		local timer = f.clock:timer({ from = 1, to = 0, duration = 5, kind = "decorative" })
		timer:onSettle(function()
			settles += 1
		end)
		expect(timer:get()).toBe(0) -- the terminal STATE is instant
		expect(timer:isSettled()).toBe(true)
		-- ...and the arrival is still announced, on the next step, so a consumer
		-- wiring onSettle up on the following line cannot miss it
		f.clock:step(FRAME)
		expect(settles).toBe(1)
		expect(f.clock:activeCount()).toBe(0)
		stepN(f.clock, 60)
		expect(settles).toBe(1)
	end)

	it("a zero-duration timer is already at its terminus and still announces it", function()
		local f = fixture()
		local settles = 0
		local timer = f.clock:timer({ from = 3, to = 7, duration = 0 })
		timer:onSettle(function()
			settles += 1
		end)
		expect(timer:get()).toBe(7)
		f.clock:step(FRAME)
		expect(settles).toBe(1)
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("a timer has no target and no velocity to seed", function()
		local f = fixture()
		local timer = f.clock:timer({ from = 1, to = 0, duration = 1 })
		expect(function()
			timer:setTarget(5)
		end).toThrow()
		expect(function()
			timer:setVelocity(5)
		end).toThrow()
	end)
end)

describe("motion clock: counters (the numeral a player reads)", function()
	it("publishes WHOLE numbers on the way, and lands exactly on the count", function()
		local f = fixture()
		local counter = f.clock:counter(120, "object")
		local seen: { number } = {}
		f.core:observe(counter, function(v: number)
			table.insert(seen, v)
		end)
		expect(counter:get()).toBe(120)
		counter:setTarget(150)
		stepN(f.clock, 240)
		expect(counter:get()).toBe(150)
		expect(counter:isSettled()).toBe(true)
		expect(#seen > 3).toBe(true) -- it COUNTED; it did not jump
		for _, v in seen do
			expect(v).toBe(math.floor(v)) -- never a fraction, on any frame
			expect(v >= 120 and v <= 150).toBe(true)
		end
	end)

	it("NEVER overshoots the count, even on an under-damped class", function()
		-- `reward` overshoots by design (0.7 damping). A wallet that flashes 130
		-- on its way to 120 reads as a bug, so the numeral is clamped to the side
		-- it started on while the class keeps owning the pacing.
		local f = fixture()
		local counter = f.clock:counter(0, "reward")
		local peak = -math.huge
		f.core:observe(counter, function(v: number)
			peak = math.max(peak, v)
		end)
		counter:setTarget(100)
		stepN(f.clock, 240)
		expect(peak).toBe(100)
		expect(counter:get()).toBe(100)
		-- ...and the same going DOWN
		local down = f.clock:counter(100, "reward")
		local trough = math.huge
		f.core:observe(down, function(v: number)
			trough = math.min(trough, v)
		end)
		down:setTarget(40)
		stepN(f.clock, 240)
		expect(trough).toBe(40)
		expect(down:get()).toBe(40)
		-- the RAW spring under it really did overshoot: without the clamp this
		-- assertion is what fails
		expect(f.clock:stats().writes > 0).toBe(true)
	end)

	it("writes ONCE PER CHANGED NUMERAL, not once per frame", function()
		-- a text node re-measures on every write, so a 60 Hz count-up over a small
		-- span must cost the number of visible changes and not the frame count
		local f = fixture()
		local counter = f.clock:counter(0, "object")
		local before = f.clock:stats().writes
		counter:setTarget(12)
		stepN(f.clock, 120)
		local writes = f.clock:stats().writes - before
		expect(counter:get()).toBe(12)
		expect(writes).toBeLessThanOrEqual(13) -- 12 steps up, at most
		expect(writes).toBeGreaterThanOrEqual(2)
	end)

	it("re-aims mid-count without restarting, and lands on the LAST count asked for", function()
		local f = fixture()
		local counter = f.clock:counter(0, "object")
		counter:setTarget(200)
		stepN(f.clock, 10)
		local mid = counter:get()
		expect(mid > 0 and mid < 200).toBe(true)
		counter:setTarget(60) -- the payload changed under the flight
		expect(counter:get()).toBe(mid) -- the aim moved; the value did not
		stepN(f.clock, 240)
		expect(counter:get()).toBe(60)
	end)

	it("under reduced motion the FINAL COUNT is instant, and the settle event still fires", function()
		local f = fixture()
		f.reduce()
		local counter = f.clock:counter(120, "object")
		local settles = 0
		counter:onSettle(function()
			settles += 1
		end)
		counter:setTarget(150)
		expect(counter:get()).toBe(150) -- the information, with no count-up
		expect(settles).toBe(1) -- ...and the same event on the same frame
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("a fractional target still lands on a numeral, and getTarget says which", function()
		local f = fixture()
		local counter = f.clock:counter(0, "object")
		counter:setTarget(10.4)
		expect(counter:getTarget()).toBe(10)
		stepN(f.clock, 240)
		expect(counter:get()).toBe(10)
	end)

	it("snap places the count with no arrival, and rest costs zero", function()
		local f = fixture()
		local counter = f.clock:counter(0, "object")
		local settles = 0
		counter:onSettle(function()
			settles += 1
		end)
		counter:snap(88)
		expect(counter:get()).toBe(88)
		expect(settles).toBe(0) -- a placement is not an arrival
		expect(f.clock:activeCount()).toBe(0)
	end)
end)

describe("motion clock: lifetime", function()
	it("dispose releases every value it built (and is idempotent)", function()
		local core = customCore.new()
		local baseline = core:counters()
		local clock = clockLib.new(core, {
			now = function()
				return 0
			end,
		})
		local a = clock:spring(0, "object")
		local b = clock:timer({ from = 0, to = 1, duration = 1 })
		a:setTarget(10)
		clock:step(FRAME)
		expect(core:counters().signals).toBe(baseline.signals + 2)
		clock:dispose()
		clock:dispose()
		expect(clock:isDisposed()).toBe(true)
		expect(core:counters()).toEqual(baseline)
		-- and a disposed clock refuses to hand out new motion rather than leaking
		expect(function()
			clock:spring(0, "object")
		end).toThrow()
		-- a disposed value still READS its last committed value: teardown never
		-- hands a binding a nil
		expect(b:get()).toBeCloseTo(FRAME, 1e-9)
	end)

	it("a scope owns the clock (surface teardown disposes motion with everything else)", function()
		local core = customCore.new()
		local baseline = core:counters()
		local scope = core:scope("surface")
		local clock = clockLib.new(core, {
			now = function()
				return 0
			end,
		})
		scope:own(clock)
		clock:spring(0, "object"):setTarget(5)
		scope:dispose()
		expect(clock:isDisposed()).toBe(true)
		expect(core:counters()).toEqual(baseline)
	end)

	it("50 build/step/dispose cycles return the core counters to baseline", function()
		local core = customCore.new()
		local policy = core:signal("full")
		local baseline = core:counters()
		for cycle = 1, 50 do
			local clock = clockLib.new(core, {
				motionPolicy = policy,
				now = function()
					return 0
				end,
			})
			local springs: { any } = {}
			for index = 1, 5 do
				local value = clock:spring(0, "object")
				value:setTarget(index * 10)
				value:onSettle(function() end)
				table.insert(springs, value)
			end
			clock:timer({ from = 1, to = 0, duration = 0.1 })
			local x = clock:spring(0, "object")
			local y = clock:spring(0, "object")
			clock:chase({
				x = x,
				y = y,
				target = function()
					return 50, 50
				end,
			})
			clock:timeline({
				beats = { { at = 0.05, run = function() end, terminal = function() end } },
				onDone = function() end,
			})
			stepN(clock, 20)
			if cycle % 2 == 0 then
				springs[1]:dispose() -- an early individual release must not double-free
			end
			clock:dispose()
		end
		expect(core:counters()).toEqual(baseline)
		expect(core:lastError()).toBe(nil)
	end)
end)
