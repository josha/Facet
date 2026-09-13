--!strict
--[[ A HELD, UNCHANGED THUMBSTICK COSTS NOTHING.

	The presenter's d-pad/analog auto-repeat glue (`presenter.luau`,
	DPAD_REPEAT_DELAY_S = 0.4 then DPAD_REPEAT_INTERVAL_S = 0.1) re-delivers a
	held gamepad direction as a fresh navigation on its own clock, so that a held
	d-pad steps a menu row by row. That is correct for a LIST. A RadialMenu has
	no repeat semantics at all: the stick's angle names one wedge, and while the
	angle does not change, the named wedge does not change either.

	Measured before the fix (tests/motion_paint_only.spec.luau's implementer,
	2026-09-13): a radial candidate aimed ONCE with `deviceAxis` and then left
	alone solved again at frame 24 and every sixth frame after it — the repeat
	delay followed by the repeat interval — each re-emitting the same six props.
	A player holding the stick at a wedge paid a full layout solve every 0.1 s
	for a picture that never changed.

	So: aim once, then hold for a full second (60 frames, one repeat delay plus
	six repeat intervals) and assert the solve delta is ZERO and the candidate is
	still the wedge the stick is pointing at. The second half of the pair is what
	keeps the first honest — a fix that simply stopped naming a candidate would
	pass a solve counter on its own. ]]
local t = require("./lib/testkit")
local it, expect = t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any

local function setup()
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 650 },
		capabilities = { pointer = true, keyboard = true, gamepad = true, touch = true },
		preferredInput = "Gamepad",
	})
	local fired = {}
	local c = Facet.Controls.RadialMenu(w.core, {
		id = "Ctl",
		distribution = "compass",
		items = {
			{
				id = "wave",
				label = "Wave",
				icon = "flag",
				slot = "N",
				onSelect = function()
					table.insert(fired, "wave")
				end,
			},
			{
				id = "point",
				label = "Point",
				slot = "E",
				onSelect = function()
					table.insert(fired, "point")
				end,
			},
			{
				id = "call",
				label = "Call",
				slot = "S",
				onSelect = function()
					table.insert(fired, "call")
				end,
			},
			{
				id = "hide",
				label = "Hide",
				slot = "W",
				onSelect = function()
					table.insert(fired, "hide")
				end,
			},
		},
	})
	w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
	w.settle(2)
	return w, c, fired
end

local function launcher(w: any): string
	for _, p in w.adapter.paths() do
		if p:match("/Launcher$") then
			return p
		end
	end
	error("missing launcher")
end

t.describe("RadialMenu held-stick idle cost", function()
	it("a held, unchanged thumbstick re-solves the ring zero times across 60 frames", function()
		local w, c, fired = setup()
		w.adapter.tap(launcher(w))
		w.settle(3)
		expect(c.dump().open).toBe(true)

		-- aim once, east. The candidate's own arrival IS a real state change and
		-- is spent before the window opens.
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
end)
