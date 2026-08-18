--!strict
-- UI-PARADIGM-002 (matrix §C): the framework-level CARRY rows — focus and an
-- exclusive surface both survive ANY interaction-class flip. Regression pins:
-- nothing may ever observe a class flip and clear focus or un-engage a modal
-- (a device change never strands the player).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local function press(system: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
end

--[[ ONE SUBSTRATE, ONE ORDER (reuse audit REUSE-88, controller ruling R12).
	`tests/lib/world.luau` owns the construction and its two invariants; the tuple
	this file hands its cases is `core, env, adapter, system, pres` — the order
	`Facet.newPresenter` itself takes, and now the only one in the suite. It used
	to be `core, env, system, adapter, pres` here and the other spelling sixteen
	files away, with the same five names on both sides, so a line copied between
	two neighbouring specs bound an action system to a variable called `adapter`
	and said nothing. ]]
local function harness()
	local w = worldLib.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
	return w.core, w.env, w.adapter, w.system, w.pres
end

local function twoButtonScreen(id: string)
	return Facet.UI.Screen({
		id = id,
		children = {
			Facet.UI.Button({ id = "A", label = "A" }),
			Facet.UI.Button({ id = "B", label = "B" }),
		},
	})
end

local function flipEverything(env: any)
	-- a full hybrid churn: pad connects, preference flips to Gamepad, then a
	-- dock adds mouse/keyboard back and the preference returns — every flip
	-- the engine can express, in sequence
	env:set("capabilities", { keyboard = false, mouse = false, touch = true, gamepad = true })
	env:set("preferredInput", "Gamepad")
	env:set("capabilities", { keyboard = true, mouse = true, touch = true, gamepad = true })
	env:set("preferredInput", "KeyboardAndMouse")
end

describe("UI-PARADIGM-002: framework CARRY rows (matrix §C)", function()
	it("focus survives any class flip (ring stays put; every live class can keep driving it)", function()
		local _, env, _, system, pres = harness()
		pres.present(twoButtonScreen("S"))
		pres.refresh()
		press(system, "Down") -- move focus off the entry focusable
		local focusedBefore = pres.focus.focused:get()
		expect(focusedBefore).toBe("/S/B")
		flipEverything(env)
		pres.refresh()
		expect(pres.focus.focused:get()).toBe(focusedBefore)
		-- and the (still live) keyboard keeps driving the same ring
		press(system, "Up")
		expect(pres.focus.focused:get()).toBe("/S/A")
	end)

	it("an exclusive modal survives any class flip (never un-engages; dismissal paths intact)", function()
		local _, env, _, system, pres = harness()
		pres.present(twoButtonScreen("Base"))
		local modalHandle = pres.presentModal(Facet.UI.Screen({
			id = "M",
			children = { Facet.UI.Button({ id = "Close", label = "Close" }) },
		}))
		pres.refresh()
		expect(pres.exclusiveSurfaceActive:get()).toBe(true)
		flipEverything(env)
		pres.refresh()
		-- the modal is still up, still exclusive, focus still inside it
		expect(pres.exclusiveSurfaceActive:get()).toBe(true)
		expect(pres.focus.focused:get()).toBe("/M/Close")
		-- and gamepad Cancel still dismisses after the churn
		press(system, "ButtonB")
		pres.refresh()
		expect(pres.exclusiveSurfaceActive:get()).toBe(false)
		local _ = modalHandle
	end)
end)
