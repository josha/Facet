--!strict
-- Time-based easing (ADR-0033; fusion-comparison.md §5 G-1): the curve registry,
-- the tween driver behind the shared `MotionValue` handle, and the engine seam.
--
-- What this file is really guarding, in order of how expensive the defect is:
--
--   * A TWEEN ARRIVES ON TIME. That is the entire reason the primitive exists —
--     a spring approaches asymptotically, so a cooldown built on one is late by
--     an amount nobody can state. The duration assertions are exact, not "close
--     enough": the value is AT its terminus on the frame the duration elapses
--     and NOT before.
--   * THE PURE TWIN IS THE ENGINE'S CURVE. Production evaluates through
--     `TweenService:GetValue`; Lune cannot, so a twin ships and is pinned here
--     against a FROZEN CORPUS captured from the live engine
--     (artifacts/time-based-easing/engine-oracle.md). A twin that drifts is a
--     headless suite testing something the player never runs.
--   * REDUCED MOTION IS INHERITED, NOT RE-DECIDED. Decorative snaps and fires
--     the same settle event; informational keeps running to the same terminus on
--     the quantized tick. Both asserted here rather than assumed from the value
--     layer, because "it goes through newValue" is a claim about code, not
--     behavior.
--   * THE CLOCK ENTRY DOES NOT LEAK. A tween is a clock participant like any
--     other, so build/aim/settle/dispose churn must return `core:counters()` to
--     baseline exactly as the spring cases do.
--   * A CURVE IS A NAME. An inline spec table is refused, exactly as an inline
--     spring params table is, and for the same drift reason.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local clockLib = require("../src/motion/clock")
local curves = require("../src/motion/curves")

local FRAME = 1 / 60
-- exact in binary, so accumulated elapsed lands on a duration without drift
local TICK = 1 / 64

type Fixture = {
	core: any,
	policy: any,
	clock: any,
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

describe("motion curves: the registry is the only dial", function()
	it("refuses an inline spec table and names registerCurve instead", function()
		curves.reset()
		local ok, err = pcall(function()
			curves.resolve({ duration = 0.4, style = "quad", direction = "out" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "not an inline spec table", 1, true) ~= nil).toBeTruthy()
		expect(string.find(tostring(err), "registerCurve", 1, true) ~= nil).toBeTruthy()
	end)

	it("ships EMPTY — there is no built-in duration to inherit by accident", function()
		curves.reset()
		expect(#curves.names()).toBe(0)
		expect(curves.isRegistered("banner")).toBe(false)
		-- and the refusal SAYS so, rather than listing nothing and looking broken
		local ok, err = pcall(function()
			curves.resolve("banner")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "ships EMPTY", 1, true) ~= nil).toBeTruthy()
	end)

	it("registers, resolves, defaults direction to out, and freezes the result", function()
		curves.reset()
		local c = curves.registerCurve("banner", { duration = 0.4, style = "quad", direction = "out" })
		expect(c.duration).toBe(0.4)
		expect(c.style).toBe("quad")
		expect(c.direction).toBe("out")
		expect(curves.isRegistered("banner")).toBe(true)
		expect(table.isfrozen(c)).toBe(true)
		-- direction is the one optional field: `out` is the overwhelmingly common
		-- UI shape (fast, then settle)
		expect(curves.registerCurve("sweep", { duration = 0.2, style = "sine" }).direction).toBe("out")
		expect(curves.names()).toEqual({ "banner", "sweep" })
	end)

	it("refuses an out-of-range duration, an unknown style and an unknown direction", function()
		curves.reset()
		expect(function()
			curves.registerCurve("tooLong", { duration = 2.5, style = "quad" })
		end).toThrow()
		expect(function()
			curves.registerCurve("negative", { duration = -0.1, style = "quad" })
		end).toThrow()
		expect(function()
			curves.registerCurve("nonsense", { duration = 0.3, style = "wobble" })
		end).toThrow()
		expect(function()
			curves.registerCurve("sideways", { duration = 0.3, style = "quad", direction = "sideways" })
		end).toThrow()
		-- a zero duration IS legal: it is how a data-driven table says "instant"
		expect(curves.registerCurve("instant", { duration = 0, style = "linear" }).duration).toBe(0)
		-- and the style error names the engine's vocabulary rather than a private one
		local ok, err = pcall(function()
			curves.registerCurve("nonsense", { duration = 0.3, style = "wobble" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Enum.EasingStyle", 1, true) ~= nil).toBeTruthy()
	end)

	it("suggests the curve you meant", function()
		curves.reset()
		curves.registerCurve("banner", { duration = 0.4, style = "quad" })
		local ok, err = pcall(function()
			curves.resolve("bannre")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Did you mean 'banner'?", 1, true) ~= nil).toBeTruthy()
	end)
end)

describe("motion curves: the pure twin IS the engine's curve", function()
	--[[ THE FROZEN ENGINE CORPUS. Captured from `TweenService:GetValue` in a live
		Studio session on 2026-08-15 (LuauUI-Showcase.rbxl, Edit datamodel) and
		recorded with its method in artifacts/time-based-easing/engine-oracle.md. The
		live oracle compares 33,033 samples and reports max |twin - engine| = 4.73e-7;
		this is the subset that travels with the suite, so a twin that drifts reddens
		HERE rather than only in a session nobody re-runs.

		Read across: alpha = 0.125, 0.25, 0.5, 0.75, 0.875. ]]
	local ENGINE: { [string]: { number } } = {
		["linear/in"] = { 0.125, 0.25, 0.5, 0.75, 0.875 },
		["quad/out"] = { 0.234375, 0.4375, 0.75, 0.9375, 0.984375 },
		["cubic/inOut"] = { 0.0078125, 0.0625, 0.5, 0.9375, 0.9921875 },
		["sine/in"] = { 0.0192147195, 0.076120466, 0.292893231, 0.617316544, 0.804909706 },
		["back/out"] = { 0.492924631, 0.817409694, 1.08769751, 1.06413651, 1.02131069 },
		["exponential/in"] = { 0.00232267007, 0.00552427163, 0.03125, 0.176776692, 0.420448214 },
		["circular/out"] = { 0.484122932, 0.661437809, 0.866025388, 0.968245864, 0.992156744 },
		["quint/in"] = { 3.05175781e-05, 0.0009765625, 0.03125, 0.237304688, 0.512908936 },
		["elastic/out"] = { 1.34958994, 0.932350516, 1.02209711, 1.00510371, 0.998709619 },
		["bounce/out"] = { 0.118164062, 0.47265625, 0.765625, 0.97265625, 0.961914062 },
	}

	it("matches the frozen engine corpus at every sampled alpha", function()
		local ALPHAS = { 0.125, 0.25, 0.5, 0.75, 0.875 }
		local checked = 0
		for key, expected in ENGINE do
			local style, direction = string.match(key, "^(%a+)/(%a+)$")
			for i, alpha in ALPHAS do
				local mine = curves.evaluate(alpha, style :: string, direction :: string)
				-- 1e-4 is the oracle's own threshold: below it no player and no
				-- pixel can tell the two evaluators apart
				expect(`{key}@{alpha} = {string.format("%.5f", mine)}`).toBe(
					`{key}@{alpha} = {string.format("%.5f", expected[i])}`
				)
				checked += 1
			end
		end
		-- the ANTI-VACUUM check: a corpus that silently emptied would pass every
		-- assertion above by making none of them
		expect(checked).toBe(50)
	end)

	it("carries Roblox's eleven styles, not a private vocabulary", function()
		expect(#curves.STYLES).toBe(11)
		local set: { [string]: boolean } = {}
		for _, s in curves.STYLES do
			set[s] = true
		end
		-- exactly `Enum.EasingStyle:GetEnumItems()`, read live 2026-08-15
		for _, name in
			{
				"linear",
				"sine",
				"back",
				"quad",
				"quart",
				"quint",
				"bounce",
				"elastic",
				"exponential",
				"circular",
				"cubic",
			}
		do
			expect(`{name} in vocabulary: {set[name] == true}`).toBe(`{name} in vocabulary: true`)
		end
		expect(curves.DIRECTIONS).toEqual({ "in", "out", "inOut" })
	end)

	it("every style is anchored at both ends, in all three directions", function()
		-- an easing curve that does not start at 0 and end at 1 does not land on
		-- the value it promised — the defect that survives every mid-curve check
		for _, style in curves.STYLES do
			for _, dir in curves.DIRECTIONS do
				expect(`{style}/{dir} @0 = {string.format("%.6f", curves.evaluate(0, style, dir))}`).toBe(
					`{style}/{dir} @0 = 0.000000`
				)
				expect(`{style}/{dir} @1 = {string.format("%.6f", curves.evaluate(1, style, dir))}`).toBe(
					`{style}/{dir} @1 = 1.000000`
				)
			end
		end
	end)

	it("clamps an alpha outside [0,1] rather than extrapolating", function()
		expect(curves.evaluate(-1, "quad", "out")).toBe(0)
		expect(curves.evaluate(2, "quad", "out")).toBe(1)
	end)

	it("hands the adapter the engine's own enum spelling", function()
		curves.reset()
		local c = curves.registerCurve("banner", { duration = 0.4, style = "quad", direction = "inOut" })
		local style, direction = curves.engineNames(c)
		expect(style).toBe("Quad")
		expect(direction).toBe("InOut")
	end)
end)

describe("clock:tween — a duration that means what it says", function()
	it("ARRIVES EXACTLY ON TIME, and not one frame early", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "half")
		v:setTarget(100)
		-- 0.5 s at 1/64 s ticks is 32 ticks exactly
		stepN(f.clock, 31, TICK)
		expect(v:isSettled()).toBe(false)
		expect(v:get() < 100).toBeTruthy()
		stepN(f.clock, 1, TICK)
		-- the whole point of the primitive: AT the terminus on the frame the
		-- duration elapses. A spring is still ~0.7 s from here.
		expect(v:isSettled()).toBe(true)
		expect(v:get()).toBe(100)
	end)

	it("a curve is not a straight line — quad/out is ahead of linear at the midpoint", function()
		curves.reset()
		curves.registerCurve("lin", { duration = 0.5, style = "linear" })
		curves.registerCurve("qout", { duration = 0.5, style = "quad", direction = "out" })
		local f = fixture()
		local a = f.clock:tween(0, "lin")
		local b = f.clock:tween(0, "qout")
		a:setTarget(100)
		b:setTarget(100)
		stepN(f.clock, 16, TICK) -- halfway
		expect(math.abs(a:get() - 50) < 1e-6).toBeTruthy()
		-- ease-out covers 75% of the distance in the first half
		expect(math.abs(b:get() - 75) < 1e-6).toBeTruthy()
		-- ...and they still land together, which is what "same duration" means
		stepN(f.clock, 16, TICK)
		expect(a:get()).toBe(100)
		expect(b:get()).toBe(100)
	end)

	it("a re-aim mid-flight redirects from where it IS, with no jump", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "half")
		v:setTarget(100)
		stepN(f.clock, 16, TICK)
		local mid = v:get()
		v:setTarget(0)
		-- the interruptibility invariant: aiming NEVER moves the value
		expect(v:get()).toBe(mid)
		--[[ ...AND THE FIRST PAINTED FRAME AFTER THE AIM MUST CONTINUE FROM `mid`.
			Added because a mutation survived without it (M13, artifacts/…/mutations.md):
			re-basing the ramp's origin on `target` instead of `current` still lands on
			0 at the right time, so an endpoint-only check passes while the value
			VISIBLY JUMPS to ~97 on the frame after the interrupt. The defect lives
			entirely in the first frame, so that is where the check has to look. ]]
		stepN(f.clock, 1, TICK)
		expect(v:get() < mid).toBeTruthy() -- moving toward 0...
		expect(v:get() > mid - 10).toBeTruthy() -- ...from where it was, not from 100
		-- and it runs a FULL duration from here, so it is not back at 0 early
		stepN(f.clock, 30, TICK)
		expect(v:isSettled()).toBe(false)
		stepN(f.clock, 1, TICK)
		expect(v:get()).toBe(0)
	end)

	it("refuses setVelocity: a curve's speed is its shape", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "half")
		expect(function()
			v:setVelocity(100)
		end).toThrow()
	end)

	it("reports the curve's INSTANTANEOUS slope, not its average", function()
		curves.reset()
		curves.registerCurve("qout", { duration = 1, style = "quad", direction = "out" })
		local f = fixture()
		local v = f.clock:tween(0, "qout")
		v:setTarget(100)
		stepN(f.clock, 1, TICK)
		local early = v:getVelocity()
		stepN(f.clock, 40, TICK)
		local late = v:getVelocity()
		-- quad/out opens fast and decays; an average would report both the same
		expect(early > late).toBeTruthy()
		expect(early > 150).toBeTruthy() -- ~200 px/s at the start of a quad/out
		expect(late < 100).toBeTruthy()
	end)

	it("a zero-duration curve lands on the NEXT step, never on an intermediate value", function()
		curves.reset()
		curves.registerCurve("instant", { duration = 0, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "instant")
		v:setTarget(42)
		--[[ `setTarget` NEVER writes synchronously — the whole authority commits
			inside the clock's one transaction, and reduced motion's `placeNow` is the
			single documented exception. So a zero-duration curve is SETTLED the moment
			it is aimed and PAINTS on the next step. Asserted rather than assumed,
			because the tempting expectation (that it lands on the calling frame) would
			have made `clock:tween` the one primitive that writes outside the step. ]]
		expect(v:isSettled()).toBe(true)
		expect(v:get()).toBe(0)
		stepN(f.clock, 1, TICK)
		expect(v:get()).toBe(42)
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("rests for free: a fresh tween attaches nothing to the clock", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "half")
		expect(f.clock:activeCount()).toBe(0)
		v:setTarget(10)
		expect(f.clock:activeCount()).toBe(1)
		stepN(f.clock, 33, TICK)
		-- settled motions leave the active set (SF-M8); rest costs zero
		expect(f.clock:activeCount()).toBe(0)
	end)

	it("fires settle EXACTLY ONCE per arrival, after the writes are committed", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "half")
		local fires, seen = 0, -1
		v:onSettle(function()
			fires += 1
			seen = v:get()
		end)
		v:setTarget(100)
		stepN(f.clock, 40, TICK)
		expect(fires).toBe(1)
		expect(seen).toBe(100) -- the handler read the terminus, not the frame before
	end)

	it("advances by RAW dt: a frame spike does not stretch the duration", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		local v = f.clock:tween(0, "half")
		v:setTarget(100)
		-- one 0.6 s stall. A spring clamps dt to 0.1 because it is target-seeking;
		-- a tween owes a wall-clock terminus and must be DONE.
		f.clock:step(0.6)
		expect(v:isSettled()).toBe(true)
		expect(v:get()).toBe(100)
	end)

	it("refuses an unknown curve, an inline spec, and a non-finite initial", function()
		curves.reset()
		local f = fixture()
		expect(function()
			f.clock:tween(0, "nope")
		end).toThrow()
		expect(function()
			f.clock:tween(0, { duration = 0.4, style = "quad" })
		end).toThrow()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		expect(function()
			f.clock:tween(0 / 0, "half")
		end).toThrow()
		-- and the opts key set is CLOSED: a misspelled `kind` would silently drop
		-- an accessibility declaration
		expect(function()
			f.clock:tween(0, "half", { knid = "informational" } :: any)
		end).toThrow()
	end)
end)

describe("clock:tween — reduced motion is inherited, not re-decided", function()
	it("DECORATIVE (the default) places the terminus instantly and fires the same settle", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local f = fixture()
		f.reduce()
		local v = f.clock:tween(0, "half")
		expect(v:motionKind()).toBe("decorative") -- same default as clock:spring
		local fires = 0
		v:onSettle(function()
			fires += 1
		end)
		v:setTarget(100)
		-- no step at all: the write and the event land on the calling frame, so
		-- RM parity never depends on a driver being attached
		expect(v:get()).toBe(100)
		expect(fires).toBe(1)
	end)

	it("INFORMATIONAL keeps running to the same terminus, quantized — a frozen cooldown is a hung game", function()
		curves.reset()
		curves.registerCurve("sweep", { duration = 1, style = "linear" })
		local f = fixture()
		f.reduce()
		local v = f.clock:tween(0, "sweep", { kind = "informational", quantum = 0.25 })
		v:setTarget(100)
		-- it did NOT jump: the information (how much time is left) survives
		expect(v:get()).toBe(0)
		f.advance(0.1)
		expect(v:get()).toBe(0) -- inside the quantum: no write yet
		f.advance(0.2)
		expect(v:get() > 0).toBeTruthy() -- the 250 ms tick landed
		expect(v:get() < 100).toBeTruthy()
		f.advance(1.0)
		-- and the terminal write ALWAYS lands, on time
		expect(v:get()).toBe(100)
		expect(v:isSettled()).toBe(true)
	end)

	it("writes far fewer times under reduced motion, and lands on the same number", function()
		curves.reset()
		curves.registerCurve("sweep", { duration = 1, style = "linear" })
		local full = fixture()
		local a = full.clock:tween(0, "sweep", { kind = "informational", quantum = 0.25 })
		a:setTarget(100)
		stepN(full.clock, 64, TICK)
		local fullWrites = full.clock:stats().writes

		local reduced = fixture()
		reduced.reduce()
		local b = reduced.clock:tween(0, "sweep", { kind = "informational", quantum = 0.25 })
		b:setTarget(100)
		stepN(reduced.clock, 64, TICK)
		local reducedWrites = reduced.clock:stats().writes

		expect(a:get()).toBe(b:get()) -- same terminus: nothing was deleted
		expect(reducedWrites < fullWrites).toBeTruthy()
		expect(reducedWrites <= 6).toBeTruthy() -- ~4 quanta plus the terminal write
	end)
end)

describe("clock:tween — the clock entry cannot leak", function()
	it("a scope owns the clock, and a tween dies with it", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local core = customCore.new()
		local baseline = core:counters()
		local scope = core:scope("surface")
		local clock = clockLib.new(core, {
			now = function()
				return 0
			end,
		})
		scope:own(clock)
		clock:tween(0, "half"):setTarget(5)
		scope:dispose()
		expect(clock:isDisposed()).toBe(true)
		expect(core:counters()).toEqual(baseline)
	end)

	it("build/aim/settle/dispose churn returns the graph to baseline", function()
		curves.reset()
		curves.registerCurve("quick", { duration = 0.1, style = "quad" })
		local core = customCore.new()
		local baseline = core:counters()
		for _ = 1, 50 do
			local clock = clockLib.new(core, {
				now = function()
					return 0
				end,
			})
			local v = clock:tween(0, "quick")
			v:setTarget(10)
			stepN(clock, 10, FRAME)
			clock:dispose()
		end
		expect(core:counters()).toEqual(baseline)
		expect(core:lastError()).toBe(nil)
	end)

	it("a disposed clock refuses to build a tween rather than leaking one", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "linear" })
		local core = customCore.new()
		local clock = clockLib.new(core, {
			now = function()
				return 0
			end,
		})
		clock:dispose()
		expect(function()
			clock:tween(0, "half")
		end).toThrow()
	end)
end)

describe("clock:setEasing — the engine owns the curve", function()
	it("routes every evaluation through the installed evaluator", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "quad", direction = "out" })
		local f = fixture()
		local calls = 0
		local sawStyle, sawDirection = "", ""
		f.clock:setEasing(function(alpha: number, style: string, direction: string): number
			calls += 1
			sawStyle, sawDirection = style, direction
			return alpha -- a deliberately LINEAR stand-in for the engine
		end)
		local v = f.clock:tween(0, "half")
		v:setTarget(100)
		stepN(f.clock, 16, TICK)
		expect(calls > 0).toBeTruthy()
		expect(sawStyle).toBe("quad")
		expect(sawDirection).toBe("out")
		-- the installed evaluator DECIDED the shape: quad/out would read 75 here,
		-- the linear stand-in reads 50. If this were still the pure twin the
		-- installation would be decoration.
		expect(math.abs(v:get() - 50) < 1e-6).toBeTruthy()
	end)

	it("is read per evaluation, so a bind upgrades values built before it", function()
		curves.reset()
		curves.registerCurve("half", { duration = 0.5, style = "quad", direction = "out" })
		local f = fixture()
		local v = f.clock:tween(0, "half") -- built BEFORE the install
		f.clock:setEasing(function(alpha: number): number
			return alpha
		end)
		v:setTarget(100)
		stepN(f.clock, 16, TICK)
		expect(math.abs(v:get() - 50) < 1e-6).toBeTruthy()
	end)

	it("refuses a non-function rather than failing on the first frame of motion", function()
		local f = fixture()
		expect(function()
			f.clock:setEasing(nil :: any)
		end).toThrow()
	end)
end)
