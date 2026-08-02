--!strict
-- Motion solver + class registry (ADR-0022 Decision 1; acceptance rows SF-M1,
-- SF-M5). Everything here is pure: the spring never reads a clock, so every
-- assertion is a scripted dt away from being reproducible forever.
--
-- The two claims worth the most scrutiny:
--   * `setTarget` NEVER touches value or velocity — the interruptibility
--     invariant. Asserted directly, and then again through the "no brick wall"
--     comparison against a twin whose velocity WAS cut.
--   * a class name is the only currency. An inline `{ dampingRatio, response }`
--     literal is refused at the call site, so a feel cannot be re-invented per
--     screen.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local spring = require("../src/motion/spring")
local classes = require("../src/motion/classes")

local FRAME = 1 / 60

-- step a spring N frames, returning the value after each frame
local function trace(s: any, frames: number, dt: number?): { number }
	local out: { number } = {}
	for _ = 1, frames do
		s:step(dt or FRAME)
		table.insert(out, s:get())
	end
	return out
end

describe("motion classes (the vocabulary)", function()
	it("ships the four ratified shapes under framework-neutral names", function()
		expect(classes.resolve("container").dampingRatio).toBe(1.0)
		expect(classes.resolve("container").response).toBe(0.35)
		expect(classes.resolve("object").dampingRatio).toBe(1.0)
		expect(classes.resolve("object").response).toBe(0.28)
		expect(classes.resolve("reward").dampingRatio).toBe(0.7)
		expect(classes.resolve("reward").response).toBe(0.18)
		expect(classes.resolve("decay").dampingRatio).toBe(1.0)
		expect(classes.resolve("decay").response).toBe(0.5)
		expect(classes.names()).toEqual({ "container", "decay", "object", "reward" })
	end)

	it("overshoot is earned: reward is the ONLY under-damped built-in", function()
		local underDamped: { string } = {}
		for _, name in classes.names() do
			if classes.resolve(name).dampingRatio < 1 then
				table.insert(underDamped, name)
			end
		end
		expect(underDamped).toEqual({ "reward" })
	end)

	it("refuses an inline params table and names registerClass instead", function()
		local ok, err = pcall(function()
			classes.resolve({ dampingRatio = 1, response = 0.3 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "not an inline params table", 1, true) ~= nil).toBeTruthy()
		expect(string.find(tostring(err), "registerClass", 1, true) ~= nil).toBeTruthy()
	end)

	it("an unknown class name is an error with a did-you-mean, never a fallback", function()
		local ok, err = pcall(function()
			classes.resolve("objekt")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Did you mean 'object'?", 1, true) ~= nil).toBeTruthy()
		-- and the message always carries the full registered set
		expect(string.find(tostring(err), "container, decay, object, reward", 1, true) ~= nil).toBeTruthy()
	end)

	it("registers a game class, validates its range, and resets back to the built-ins", function()
		classes.registerClass("gameChip", { dampingRatio = 0.9, response = 0.2 })
		expect(classes.isRegistered("gameChip")).toBe(true)
		expect(classes.resolve("gameChip").response).toBeCloseTo(0.2)

		-- out of range on either axis is an authoring error
		expect(function()
			classes.registerClass("tooBouncy", { dampingRatio = 0, response = 0.2 })
		end).toThrow()
		expect(function()
			classes.registerClass("tooBouncy", { dampingRatio = 2.5, response = 0.2 })
		end).toThrow()
		expect(function()
			classes.registerClass("tooFast", { dampingRatio = 1, response = 0.01 })
		end).toThrow()
		expect(function()
			classes.registerClass("tooSlow", { dampingRatio = 1, response = 5 })
		end).toThrow()
		expect(classes.isRegistered("tooBouncy")).toBe(false)

		-- re-registering a built-in is the sanctioned ±30 % tuning dial
		classes.registerClass("object", { dampingRatio = 1.0, response = 0.36 })
		expect(classes.resolve("object").response).toBeCloseTo(0.36)

		classes.reset()
		expect(classes.isRegistered("gameChip")).toBe(false)
		expect(classes.resolve("object").response).toBe(0.28)
	end)

	it("a registered class is frozen (nobody re-tunes a shared shape by reference)", function()
		local class = classes.resolve("object")
		expect(function()
			(class :: any).response = 9
		end).toThrow()
	end)
end)

describe("spring solver (semi-implicit Euler)", function()
	it("a critically damped class never overshoots its target", function()
		local s = spring.new(0, classes.resolve("object"))
		s:setTarget(100)
		local values = trace(s, 120)
		local previous = 0
		for _, v in values do
			expect(v).toBeLessThanOrEqual(100)
			expect(v).toBeGreaterThanOrEqual(previous - 1e-9) -- monotone approach
			previous = v
		end
		expect(s:isSettled()).toBe(true)
		expect(s:get()).toBeCloseTo(100, 1e-3)
	end)

	it("the one under-damped class overshoots (earned, and only there)", function()
		local s = spring.new(0, classes.resolve("reward"))
		s:setTarget(100)
		local peak = 0
		for _, v in trace(s, 120) do
			peak = math.max(peak, v)
		end
		expect(peak).toBeGreaterThan(100)
		expect(s:get()).toBeCloseTo(100, 1e-3) -- and it still comes to rest ON target
	end)

	it("setTarget touches neither value nor velocity (the interruptibility invariant)", function()
		local s = spring.new(0, classes.resolve("object"))
		s:setTarget(100)
		trace(s, 10)
		local valueBefore, velocityBefore = s:get(), s:getVelocity()
		expect(velocityBefore).toBeGreaterThan(0)
		s:setTarget(-500)
		expect(s:get()).toBe(valueBefore)
		expect(s:getVelocity()).toBe(velocityBefore)
		expect(s:getTarget()).toBe(-500)
	end)

	it("an interrupted flight carries its velocity: no brick wall against a cut twin", function()
		-- two identical springs, both mid-flight, both re-aimed further along on
		-- the same frame. One has its velocity hard-cut — what a re-targeted tween
		-- does. The spring that KEPT its momentum must travel further on the very
		-- next frame, and the gap is the seam a tween would show the player.
		local carried = spring.new(0, classes.resolve("object"))
		local cut = spring.new(0, classes.resolve("object"))
		carried:setTarget(100)
		cut:setTarget(100)
		trace(carried, 10)
		trace(cut, 10)
		expect(carried:get()).toBeCloseTo(cut:get(), 1e-12) -- identical to here
		local from = carried:get()

		carried:setTarget(200)
		cut:setTarget(200)
		cut:setVelocity(0) -- the seam
		carried:step(FRAME)
		cut:step(FRAME)
		local carriedDelta = carried:get() - from
		local cutDelta = cut:get() - from
		expect(carriedDelta).toBeGreaterThan(cutDelta)
		expect(cutDelta).toBeGreaterThan(0) -- both still move: this is the gap, not a stall
	end)

	it("a seeded release velocity produces a continuous first frame (no seam)", function()
		local seeded = spring.new(0, classes.resolve("object"))
		local resting = spring.new(0, classes.resolve("object"))
		seeded:setVelocity(600) -- px/s, as a release tracker would report
		seeded:step(FRAME)
		resting:step(FRAME)
		expect(resting:get()).toBe(0) -- nothing aimed, nothing seeded: nothing moves
		local delta = seeded:get()
		expect(delta).toBeGreaterThan(0)
		-- the frame's travel is bounded above by the undamped v·dt and is a real
		-- fraction of it: a seam would show up as ~0 travel or as a jump past it
		expect(delta).toBeLessThan(600 * FRAME)
		expect(delta).toBeGreaterThan(0.25 * 600 * FRAME)
		-- velocity is DAMPED, never cut
		expect(seeded:getVelocity()).toBeGreaterThan(0)
		expect(seeded:getVelocity()).toBeLessThan(600)
	end)

	it("clamps a frame spike and substeps it: no NaN, and a spike equals MAX_DT", function()
		local spiked = spring.new(0, classes.resolve("container"))
		local clamped = spring.new(0, classes.resolve("container"))
		spiked:setTarget(250)
		clamped:setTarget(250)
		spiked:step(100) -- tab-out / debugger pause
		clamped:step(spring.MAX_DT)
		expect(spiked:get()).toBe(clamped:get())
		expect(spiked:get() == spiked:get()).toBeTruthy() -- not NaN
		expect(spiked:get()).toBeLessThanOrEqual(250)
	end)

	it("rejects non-finite input and keeps the last good state", function()
		local s = spring.new(0, classes.resolve("object"))
		s:setTarget(100)
		trace(s, 5)
		local value, velocity = s:get(), s:getVelocity()
		s:setTarget(0 / 0)
		s:setVelocity(math.huge)
		s:snap(0 / 0)
		expect(s:getTarget()).toBe(100)
		expect(s:get()).toBe(value)
		expect(s:getVelocity()).toBe(velocity)
	end)

	it("snap sets value and target and zeroes velocity (the reduced-motion primitive)", function()
		local s = spring.new(0, classes.resolve("object"))
		s:setTarget(100)
		trace(s, 5)
		s:snap(42)
		expect(s:get()).toBe(42)
		expect(s:getTarget()).toBe(42)
		expect(s:getVelocity()).toBe(0)
		expect(s:isSettled()).toBe(true)
	end)

	it("settles within eps on BOTH value and velocity, and a coarser eps settles sooner", function()
		local function framesToSettle(eps: number?): number
			local s = spring.new(0, classes.resolve("object"), eps)
			s:setTarget(100)
			for frame = 1, 600 do
				if s:step(FRAME) then
					-- the settle contract, verbatim
					expect(math.abs(s:get() - 100)).toBeLessThanOrEqual(eps or spring.DEFAULT_EPS)
					expect(math.abs(s:getVelocity())).toBeLessThanOrEqual(eps or spring.DEFAULT_EPS)
					return frame
				end
			end
			return -1
		end
		local fine = framesToSettle(nil)
		local coarse = framesToSettle(1)
		expect(fine).toBeGreaterThan(0)
		expect(coarse).toBeGreaterThan(0)
		expect(coarse).toBeLessThan(fine)
	end)

	it("a zero or negative dt advances nothing (a rewound clock is not motion)", function()
		local s = spring.new(0, classes.resolve("object"))
		s:setTarget(100)
		s:step(0)
		s:step(-1)
		expect(s:get()).toBe(0)
		expect(s:getVelocity()).toBe(0)
	end)
end)
