--!strict
local harness = require("./lib/harness")
--[[ A HELD DIRECTION COSTS THE RING ONE STEP, NOT A STEP EVERY TENTH OF A SECOND.

	The presenter's gamepad auto-repeat glue (`presenter.luau`,
	DPAD_REPEAT_DELAY_S = 0.4 then DPAD_REPEAT_INTERVAL_S = 0.1) re-delivers a held
	gamepad direction as a fresh `navigateHorizontal`/`navigateVertical` on its own
	clock, so that a held d-pad steps a menu row by row. That is correct for a
	LIST. A RadialMenu is not a list, and both of its input routes were paying for
	the mismatch:

	  * THE STICK. The angle names the wedge absolutely. Measured 2026-09-13: a
	    candidate aimed once with `deviceAxis` and then left alone solved SEVEN
	    times across 60 idle frames — one at the repeat delay, one every repeat
	    interval after it — while the repeats walked focus onto a wedge the stick
	    was not pointing at.

	  * THE D-PAD. `navigateIntercept`'s geometric nearest-wedge search used to
	    DECLINE when no wedge lay that way, and the presenter then walked its own
	    focus ring, which WRAPS. That wrap is the real root: a held `DPadRight` on
	    a compass ring went `:point` -(nothing to the right, wrap)-> `:call` -(the
	    search: `:point` IS right of `:call`)-> `:point`, for SEVEN focus changes
	    and eight solves across a 60-tick hold. Holding instead of falling through
	    makes the walk monotone (every accepted step needs `along > 1`, a strict
	    advance along the pressed direction) and therefore terminating — a ring
	    with more wedges that way still repeat-steps the whole way across.

	...and the same intercept moved focus with a bare `graph.focusOn`, never
	touching `candidate`. The presenter does NOT report a move an intercept claimed
	back through `focusMoved`, so a pad step left focus and the painted highlight
	disagreeing — and `candidate` is what a hold-action release COMMITS, so the pad
	user could fire a wedge that was never the one lit up.

	THE RULING PINNED HERE (2026-09-13): while focus is inside an OPEN ring, the
	ring owns the directional verbs — a held stick or d-pad never yanks focus out
	of it, and Cancel/B is how you leave. `from == nil` (a path this control never
	censused) still declines, so the ring claims nothing it does not own.

	ONE HONEST LIMIT ON CASE "the aim never yanks focus out of the ring": the
	`/S/Outside` half of that assertion does not currently bite on its own. With
	both guards removed the pre-fix escape was a WRAP INSIDE the ring (`:call` <->
	`:hide`), because the radial's own `focusGroups` group confines direction
	navigation — measured. It is kept as a pin on that group policy; the half that
	BITES is the one next to it, that focus never leaves the aimed wedge at all.

	WHICH GUARD EACH CASE HOLDS, measured one mutation at a time. The hold carries
	the two d-pad cases and, on a COMPASS ring, the aim cases as well — because a
	compass aim is always the extreme wedge along the axis it latched, so nothing
	lies that way for the geometric branch to step to. The aim guard has its own
	case, "a diagonal aim holds its wedge", on a six-wedge EVEN ring where a
	neighbour genuinely does lie along the latched axis: with the guard removed,
	that one alone goes red. ]]
local t = require("./lib/testkit")
local it, expect = t.it, t.expect
local world = require("./lib/harness_world")
local Facet = require("../src") :: any

local COMPASS = { { "wave", "N" }, { "point", "E" }, { "call", "S" }, { "hide", "W" } }

-- a four-wedge compass ring, open-able, with ONE control outside it so "the ring
-- never hands focus away" is a question this screen can actually be asked
local function setup()
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 650 },
		capabilities = { pointer = true, keyboard = true, gamepad = true, touch = true },
		preferredInput = "Gamepad",
	})
	local fired = {}
	local items = {}
	for _, def in COMPASS do
		table.insert(items, {
			id = def[1],
			label = def[1],
			slot = def[2],
			onSelect = function()
				table.insert(fired, def[1])
			end,
		})
	end
	local c = harness.Controls.RadialMenu(w.core, { id = "Ctl", distribution = "compass", items = items })
	w.present(harness.UI.Screen({
		id = "S",
		children = { c.blueprint, harness.UI.Button({ id = "Outside", label = "Outside" }) },
	}))
	w.settle(2)
	return w, c, fired
end

-- ...and an EVEN ring of `n` wedges. A compass ring cannot ask the question case
-- "a diagonal aim is not a step" asks: on a compass the AIMED wedge is always the
-- extreme one along whichever axis the stick latched, so nothing ever lies that
-- way and the hold below would answer for the aim. Six even wedges sit at 0/60/
-- 120/180/240/300, so a stick aimed at the top wedge can latch `right` with
-- another wedge genuinely to the right of it.
local function evenSetup(n: number)
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 650 },
		capabilities = { pointer = true, keyboard = true, gamepad = true, touch = true },
		preferredInput = "Gamepad",
	})
	local items = {}
	for i = 1, n do
		table.insert(items, { id = `i{i}`, label = `Item {i}`, onSelect = function() end })
	end
	local c = harness.Controls.RadialMenu(w.core, { id = "Ctl", distribution = "even", items = items })
	w.present(harness.UI.Screen({ id = "S", children = { c.blueprint } }))
	w.settle(2)
	return w, c
end

local function launcher(w: any): string
	for _, p in w.adapter.paths() do
		if p:match("/Launcher$") then
			return p
		end
	end
	error("missing launcher")
end

local function open(w: any, c: any)
	w.adapter.tap(launcher(w))
	w.settle(3)
	expect(c.dump().open).toBe(true)
end

-- the wedge key a focus path names (`:point`), or the raw path when focus is on
-- something that is not a wedge — so a failure reads `:call`, not 140 characters
local function wedgeOf(path: string?): string
	if path == nil then
		return "nil"
	end
	return path:match("%[([^%]]+)%]") or path
end

t.describe("RadialMenu held-direction cost", function()
	it("a held, unchanged thumbstick re-solves the ring zero times across 60 frames", function()
		local w, c, fired = setup()
		open(w, c)

		-- aim once, due east. The candidate's own arrival IS a real state change
		-- and is spent before the window opens.
		w.system.deviceAxis("Thumbstick1", 1, 0)
		w.settle(3)
		expect(c.dump().candidate).toBe(":point")

		-- ...and now the stick does not move for a full second: one 0.4 s repeat
		-- delay plus six 0.1 s repeat intervals.
		local before = w.controller.stats().solves
		w.settle(60)
		local delta = w.controller.stats().solves - before

		expect(`held-stick solves={delta}`).toBe("held-stick solves=0")
		-- the counter is only honest while the aim still holds
		expect(c.dump().candidate).toBe(":point")
		expect(c.dump().open).toBe(true)
		expect(#fired).toBe(0)
		c.dispose()
	end)

	it("a held D-PAD steps the ring once and then rests", function()
		local w, c, fired = setup()
		open(w, c)
		expect(wedgeOf(w.pres.focus.focused:peek())).toBe(":wave")

		-- DOWN, never up: the key stays held for the whole window, exactly the way
		-- tests/dpad_repeat.spec.luau drives a hold.
		w.system.deviceKey("DPadRight", true)
		w.settle(3) -- the one legitimate step, and its solve, spent before the window
		local landed = w.pres.focus.focused:peek()
		expect(wedgeOf(landed)).toBe(":point")

		local before = w.controller.stats().solves
		local changes = 0
		local previous = landed
		for _ = 1, 60 do
			w.tick()
			w.pres.refresh()
			local now = w.pres.focus.focused:peek()
			if now ~= previous then
				changes += 1
				previous = now
			end
		end
		local delta = w.controller.stats().solves - before

		expect(`held-dpad focusChanges={changes} solves={delta}`).toBe("held-dpad focusChanges=0 solves=0")
		expect(wedgeOf(w.pres.focus.focused:peek())).toBe(":point")
		expect(#fired).toBe(0)
		w.system.deviceKey("DPadRight", false)
		c.dispose()
	end)

	it("a d-pad step moves focus and the painted candidate together", function()
		local w, c = setup()
		open(w, c)
		expect(c.dump().candidate).toBe(nil)

		w.press("DPadRight")
		w.settle(2)
		expect(wedgeOf(w.pres.focus.focused:peek())).toBe(":point")
		expect(c.dump().candidate).toBe(":point")

		-- and again, on a step the GEOMETRIC branch takes rather than the wrap:
		-- `:wave` is the wedge above `:call`, and `:call` is below `:point`
		w.press("DPadDown")
		w.settle(2)
		expect(c.dump().candidate).toBe(wedgeOf(w.pres.focus.focused:peek()))
		expect(c.dump().candidate).toBe(":call")
		c.dispose()
	end)

	it("a held aim never yanks focus out of the open ring", function()
		local w, c = setup()
		open(w, c)
		w.system.deviceAxis("Thumbstick1", 0, 1) -- due south: `:call`, and nothing below it
		w.settle(3)
		expect(c.dump().candidate).toBe(":call")

		local escaped, wandered = false, false
		for _ = 1, 60 do
			w.tick()
			w.pres.refresh()
			local focused = w.pres.focus.focused:peek()
			if focused == "/S/Outside" then
				escaped = true
			end
			if wedgeOf(focused) ~= ":call" then
				wandered = true
			end
		end

		expect(`aim escaped={escaped} wandered={wandered}`).toBe("aim escaped=false wandered=false")
		expect(c.dump().open).toBe(true)
		c.dispose()
	end)

	it("a diagonal aim holds its wedge even when another lies along the latched axis", function()
		local w, c = evenSetup(6)
		open(w, c)

		-- north-by-east, hard enough that BOTH components cross the 0.5 latch:
		-- the ring reads the angle and aims `:i1` (the top wedge), while the
		-- presenter's NavigateH latches `right` — and `:i2` really is to the right
		-- of `:i1`, so the geometric branch below would step onto it. Measured
		-- with the aim guard removed: focus leaves `:i1` for `:i2` mid-hold, and
		-- the highlight goes with it, lighting a wedge the stick is not on.
		w.system.deviceAxis("Thumbstick1", 0.6, -1.04)
		w.settle(3)
		expect(c.dump().candidate).toBe(":i1")
		expect(wedgeOf(w.pres.focus.focused:peek())).toBe(":i1")

		local wandered = false
		for _ = 1, 60 do
			w.tick()
			w.pres.refresh()
			if wedgeOf(w.pres.focus.focused:peek()) ~= ":i1" or c.dump().candidate ~= ":i1" then
				wandered = true
			end
		end
		expect(`diagonal aim wandered={wandered}`).toBe("diagonal aim wandered=false")
		c.dispose()
	end)

	it("releasing the stick hands the ring back to the d-pad", function()
		local w, c = setup()
		open(w, c)
		w.system.deviceAxis("Thumbstick1", 0, 1)
		w.settle(2)
		expect(c.dump().analog).toBe(true)

		w.system.deviceAxis("Thumbstick1", 0, 0) -- re-centre: below the 0.25 release
		w.settle(2)
		expect(c.dump().analog).toBe(false)

		-- ...so the geometric branch is live again and a discrete press navigates
		local before = w.pres.focus.focused:peek()
		w.press("DPadUp")
		w.settle(2)
		expect(w.pres.focus.focused:peek() ~= before).toBe(true)
		c.dispose()
	end)
end)
