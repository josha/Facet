--!strict
--[[
	value_reveal — the five rules, each pinned by the DEFECT it was extracted from.
	Every one of these was a real bug in a hand-rolled copy of this machine, found
	by a director in a play session rather than by a suite.
]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local valueReveal = require("../src/motion/value_reveal")

local function harness(withAnimator: boolean?)
	local state = { held = false, counting = false, snapped = nil :: number?, target = nil :: number? }
	local animator = {
		snap = function(_: any, v: number)
			-- the ORDER check: a seed that lands after `counting` is the "pop to a
			-- new value" defect, so record whether anything was counting first
			state.snapped = v
			state.snappedWhileCounting = state.counting
		end,
		setTarget = function(_: any, v: number)
			state.target = v
		end,
	}
	local reveal = valueReveal.new({
		held = {
			set = function(_: any, v: boolean)
				state.held = v
			end,
		},
		counting = {
			set = function(_: any, v: boolean)
				state.counting = v
			end,
		},
		animator = if withAnimator == false then nil else animator :: any,
	})
	return reveal, state
end

local function cue(o: any): any
	local c = { epoch = "tail#1", open = false, past = false, abandoned = false, from = 0, to = 100 }
	for k, v in o or {} do
		c[k] = v
	end
	return c
end

describe("value_reveal — rule 1: NOT YET KNOWN is not an abandon", function()
	it("a sync before the payload exists leaves the hold ALONE", function()
		--[[ THE DEFECT: the machine ran once at construction, before its payload
			existed, and that path released the hold — so the final value painted for
			a few frames, the payload arrived, the hold went back up, and the bar
			visibly EMPTIED before filling. ]]
		local reveal, state = harness()
		state.held = true
		reveal:sync(cue({ from = nil, to = nil }))
		expect(`held={state.held}`).toBe("held=true")
		reveal:sync(cue({ epoch = nil }))
		expect(`stillHeld={state.held}`).toBe("stillHeld=true")
		expect(`nothingSeeded={state.snapped}`).toBe("nothingSeeded=nil")
	end)
end)

describe("value_reveal — rule 2: SEED, then count", function()
	it("the animator holds the START value before anything reads it", function()
		--[[ THE DEFECT: `counting` was set before the counter was seeded, and a
			counter is created at zero, so one frame painted 0. ]]
		local reveal, state = harness()
		reveal:sync(cue({ open = true, from = 120, to = 150 }))
		expect(`seeded={state.snapped}`).toBe("seeded=120")
		expect(`target={state.target}`).toBe("target=150")
		expect(`seededFirst={state.snappedWhileCounting}`).toBe("seededFirst=false")
		expect(`counting={state.counting}`).toBe("counting=true")
		expect(`released={state.held}`).toBe("released=false")
	end)
end)

describe("value_reveal — rule 3: every abandon path lands the truth", function()
	it("an explicit abandon releases, and cannot be restarted by a later cue", function()
		local reveal, state = harness()
		reveal:sync(cue({ abandoned = true }))
		expect(`held={state.held}`).toBe("held=false")
		expect(`counting={state.counting}`).toBe("counting=false")
		-- a cue that arrives after the caller gave up must not start a ceremony
		reveal:sync(cue({ open = true }))
		expect(`stillSettled={state.counting}`).toBe("stillSettled=false")
	end)

	it("a window already PAST releases instead of holding — the late-arrival path", function()
		local reveal, state = harness()
		reveal:sync(cue({ open = false, past = true }))
		expect(`held={state.held}`).toBe("held=false")
	end)

	it("a window still COMING holds", function()
		local reveal, state = harness()
		reveal:sync(cue({ open = false, past = false }))
		expect(`held={state.held}`).toBe("held=true")
	end)

	it("`rest` releases and rearms", function()
		local reveal, state = harness()
		reveal:sync(cue({ open = true }))
		reveal:rest()
		expect(`released={state.held == false and state.counting == false}`).toBe("released=true")
		-- rearmed: the same epoch may run again after a rest
		reveal:sync(cue({ open = true, from = 5, to = 9 }))
		expect(`reran={state.target}`).toBe("reran=9")
	end)
end)

describe("value_reveal — rule 4: once per epoch", function()
	it("runs once, and a repeated cue is a no-op", function()
		local reveal, state = harness()
		reveal:sync(cue({ open = true, from = 1, to = 2 }))
		state.snapped = nil
		reveal:sync(cue({ open = true, from = 1, to = 2 }))
		expect(`noSecondRun={state.snapped}`).toBe("noSecondRun=nil")
	end)

	it("a NEW epoch rearms on the settled state of the last one", function()
		local reveal, state = harness()
		reveal:sync(cue({ open = true, from = 1, to = 2 }))
		reveal:sync(cue({ epoch = "tail#2", open = true, from = 7, to = 9 }))
		expect(`reseeded={state.snapped}`).toBe("reseeded=7")
		expect(`retargeted={state.target}`).toBe("retargeted=9")
	end)
end)

describe("value_reveal — rule 5: degrading is not withholding", function()
	it("with NO animator the fact is stated immediately, never held", function()
		--[[ The property that makes the hold safe at all: there is no configuration
			in which a number is withheld by a beat that can never run. ]]
		local reveal, state = harness(false)
		state.held = true
		reveal:sync(cue({ open = false }))
		expect(`released={state.held}`).toBe("released=false")
		expect(`counting={state.counting}`).toBe("counting=false")
	end)
end)

describe("value_reveal — landing", function()
	it("`landed` stops the count without re-holding", function()
		local reveal, state = harness()
		reveal:sync(cue({ open = true }))
		reveal:landed()
		expect(`counting={state.counting}`).toBe("counting=false")
		expect(`held={state.held}`).toBe("held=false")
	end)
end)
