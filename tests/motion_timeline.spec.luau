--!strict
-- Timeline (ADR-0022 Decision 1; acceptance rows SF-M4, SF-M5). A choreographed
-- sequence that a scripted clock can drive frame by frame, that can be
-- interrupted at ANY frame, and that always resolves to a declared end state.
--
-- The interrupt matrix is the point of this file: the sequence is interrupted at
-- every beat boundary AND mid-beat, and each time the log must read as
-- "everything that had already happened, then every remaining beat's declared
-- terminal, in order" — never a half-painted state, never a dropped beat.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local clockLib = require("../src/motion/clock")

local FRAME = 1 / 64 -- exact in binary: beat times land where they are declared

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

-- three beats that log their run and their terminal, so every exit path is
-- readable as a single string
local function celebration(log: { string })
	return {
		{
			at = 0,
			run = function()
				table.insert(log, "flash")
			end,
			terminal = function()
				table.insert(log, "flash-end")
			end,
		},
		{
			at = 0.25,
			run = function()
				table.insert(log, "count")
			end,
			terminal = function()
				table.insert(log, "count-end")
			end,
		},
		{
			at = 0.5,
			run = function()
				table.insert(log, "banner")
			end,
			terminal = function()
				table.insert(log, "banner-end")
			end,
		},
	}
end

local function stepN(clock: any, frames: number)
	for _ = 1, frames do
		clock:step(FRAME)
	end
end

describe("motion timeline: playing out", function()
	it("fires beats in order at their declared clock times", function()
		local _, _, clock = fixture()
		local log: { string } = {}
		local done: { string } = {}
		local timeline = clock:timeline({
			beats = celebration(log),
			onDone = function(reason)
				table.insert(done, reason)
			end,
		})
		clock:step(FRAME) -- a beat at 0 fires on the first step
		expect(log).toEqual({ "flash" })
		stepN(clock, 15) -- t = 0.25
		expect(log).toEqual({ "flash", "count" })
		expect(timeline:elapsed()).toBeCloseTo(0.25, 1e-12)
		stepN(clock, 16) -- t = 0.5
		expect(log).toEqual({ "flash", "count", "banner" })
		-- natural completion runs no terminals: they are the interrupt/skip form
		expect(done).toEqual({ "complete" })
		expect(timeline:isDone()).toBe(true)
		expect(clock:activeCount()).toBe(0)
	end)

	it("is deterministic: the same scripted clock produces the same log twice", function()
		local function run(): { string }
			local _, _, clock = fixture()
			local log: { string } = {}
			clock:timeline({ beats = celebration(log) })
			stepN(clock, 40)
			return log
		end
		expect(run()).toEqual(run())
	end)

	it("onDone fires exactly once, and a late interrupt is a no-op", function()
		local _, _, clock = fixture()
		local log: { string } = {}
		local done: { string } = {}
		local timeline = clock:timeline({
			beats = celebration(log),
			onDone = function(reason)
				table.insert(done, reason)
			end,
		})
		stepN(clock, 40)
		timeline:interrupt()
		timeline:skip()
		expect(done).toEqual({ "complete" })
		expect(log).toEqual({ "flash", "count", "banner" })
	end)
end)

describe("motion timeline: interrupt and skip", function()
	it("interrupt at EVERY beat boundary leaves the declared end state, in order", function()
		local expected = {
			-- interrupt before any beat has fired
			[0] = { "flash-end", "count-end", "banner-end" },
			-- after beat 1, after beat 2: the beat MID-PLAY terminalizes too
			-- (ui-designer §8.2 / P5-F6 ruling — its run fired, so only its
			-- terminal guarantees nothing is half-painted on the interrupt frame)
			[1] = { "flash", "flash-end", "count-end", "banner-end" },
			[2] = { "flash", "count", "count-end", "banner-end" },
		}
		for fired = 0, 2 do
			local _, _, clock = fixture()
			local log: { string } = {}
			local done: { string } = {}
			local timeline = clock:timeline({
				beats = celebration(log),
				onDone = function(reason)
					table.insert(done, reason)
				end,
			})
			-- land exactly on the boundary: beat n fires at frame 1 + 16*(n-1)
			if fired > 0 then
				stepN(clock, 1 + 16 * (fired - 1))
			end
			expect(#log).toBe(fired)
			timeline:interrupt()
			expect(log).toEqual(expected[fired])
			expect(done).toEqual({ "interrupt" })
			expect(timeline:isDone()).toBe(true)
			expect(clock:activeCount()).toBe(0)
			-- and nothing fires afterwards, however long the clock runs
			stepN(clock, 60)
			expect(log).toEqual(expected[fired])
		end
	end)

	it("interrupt MID-beat resolves the PLAYING beat and the remaining beats to terminals", function()
		local _, _, clock = fixture()
		local log: { string } = {}
		local timeline = clock:timeline({ beats = celebration(log) })
		stepN(clock, 9) -- t ≈ 0.14: after "flash", before "count"
		expect(log).toEqual({ "flash" })
		timeline:interrupt()
		expect(log).toEqual({ "flash", "flash-end", "count-end", "banner-end" })
	end)

	it("skip fast-forwards the remaining content with zero elapsed time", function()
		local _, _, clock = fixture()
		local log: { string } = {}
		local done: { string } = {}
		local timeline = clock:timeline({
			beats = celebration(log),
			onDone = function(reason)
				table.insert(done, reason)
			end,
		})
		clock:step(FRAME)
		local elapsedAtSkip = timeline:elapsed()
		timeline:skip()
		-- every remaining beat happened AND landed on its declared end state
		expect(log).toEqual({ "flash", "count", "count-end", "banner", "banner-end" })
		expect(done).toEqual({ "skip" })
		expect(timeline:elapsed()).toBe(elapsedAtSkip) -- no time passed
		expect(clock:activeCount()).toBe(0)
	end)

	it("a beat may skip its own timeline without double-firing anything", function()
		local _, _, clock = fixture()
		local log: { string } = {}
		local done: { string } = {}
		local timeline
		timeline = clock:timeline({
			beats = {
				{
					at = 0,
					run = function()
						table.insert(log, "first")
						timeline:skip()
					end,
				},
				{
					at = 0.1,
					run = function()
						table.insert(log, "second")
					end,
					terminal = function()
						table.insert(log, "second-end")
					end,
				},
			},
			onDone = function(reason)
				table.insert(done, reason)
			end,
		})
		stepN(clock, 40)
		expect(log).toEqual({ "first", "second", "second-end" })
		expect(done).toEqual({ "skip" })
	end)

	it("a beat may start motion on the same clock, and it runs from that frame", function()
		local core, _, clock = fixture()
		local baseline = core:counters()
		local moved: { number } = {}
		local value: any = nil
		clock:timeline({
			beats = {
				{
					at = 0.25,
					run = function()
						value = clock:spring(0, "reward")
						value:setTarget(100)
						value:onSettle(function()
							table.insert(moved, value:get())
						end)
					end,
					terminal = function()
						if value ~= nil then
							value:snap(100)
						end
					end,
				},
			},
		})
		stepN(clock, 16) -- the beat fires on the frame elapsed reaches 0.25
		expect(value).never().toBeNil()
		expect(value:get()).toBeGreaterThan(0) -- it advanced in the SAME step
		stepN(clock, 200)
		expect(moved).toEqual({ 100 })
		expect(clock:activeCount()).toBe(0)
		clock:dispose()
		expect(core:counters()).toEqual(baseline)
	end)

	it("beats with no declared terminal are simply not painted over by interrupt", function()
		local _, _, clock = fixture()
		local log: { string } = {}
		local timeline = clock:timeline({
			beats = {
				{
					at = 0,
					run = function()
						table.insert(log, "a")
					end,
				},
				{
					at = 0.2,
					run = function()
						table.insert(log, "b")
					end,
				},
			},
		})
		clock:step(FRAME)
		timeline:interrupt()
		-- interrupt does not PLAY remaining content; it only lands declared end
		-- states, and beat b declared none
		expect(log).toEqual({ "a" })
		-- skip is the verb that plays it (already interrupted here, so inert)
		timeline:skip()
		expect(log).toEqual({ "a" })
	end)
end)

describe("motion timeline: reduced motion", function()
	it("fires every beat immediately, in order, with durations zeroed", function()
		local _, policy, clock = fixture()
		policy:set("reduced")
		local log: { string } = {}
		local done: { string } = {}
		local timeline = clock:timeline({
			beats = celebration(log),
			onDone = function(reason)
				table.insert(done, reason)
			end,
		})
		-- no step required: the whole sequence and all of its events are already
		-- delivered (information parity, not "skip the animation")
		expect(log).toEqual({
			"flash",
			"flash-end",
			"count",
			"count-end",
			"banner",
			"banner-end",
		})
		expect(done).toEqual({ "reduced" })
		expect(timeline:isDone()).toBe(true)
		expect(clock:activeCount()).toBe(0)
		expect(clock:stats().steps).toBe(0)
	end)

	it("every beat's run fires in BOTH modes: the run sets match exactly", function()
		local function runs(reduced: boolean): { string }
			local _, policy, clock = fixture()
			if reduced then
				policy:set("reduced")
			end
			local log: { string } = {}
			clock:timeline({
				beats = {
					{
						at = 0,
						run = function()
							table.insert(log, "one")
						end,
					},
					{
						at = 0.2,
						run = function()
							table.insert(log, "two")
						end,
					},
					{
						at = 0.4,
						run = function()
							table.insert(log, "three")
						end,
					},
				},
			})
			stepN(clock, 40)
			return log
		end
		expect(runs(true)).toEqual(runs(false))
	end)
end)

describe("motion timeline: authoring errors", function()
	it("rejects beats declared out of order", function()
		local _, _, clock = fixture()
		expect(function()
			clock:timeline({
				beats = {
					{ at = 0.5, run = function() end },
					{ at = 0.1, run = function() end },
				},
			})
		end).toThrow()
	end)

	it("rejects a negative or non-finite beat time and a non-function run", function()
		local _, _, clock = fixture()
		expect(function()
			clock:timeline({ beats = { { at = -1, run = function() end } } })
		end).toThrow()
		expect(function()
			clock:timeline({ beats = { { at = 0, run = 7 } } :: any })
		end).toThrow()
	end)

	it("an empty timeline is done immediately (and still reports it)", function()
		local _, _, clock = fixture()
		local done: { string } = {}
		local timeline = clock:timeline({
			beats = {},
			onDone = function(reason)
				table.insert(done, reason)
			end,
		})
		expect(timeline:isDone()).toBe(true)
		expect(done).toEqual({ "complete" })
		expect(clock:activeCount()).toBe(0)
	end)
end)
