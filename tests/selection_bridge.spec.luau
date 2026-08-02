--!strict
-- Engine-selection bridge (native-substrate NS-A12/NS-A11): opt-in,
-- modal-only, mirrors logical focus, clears on teardown; passive/default
-- surfaces NEVER touch engine selection. The engine half (Selectable
-- handling, autoscroll, reassignment warning) is spike m9 + scenario
-- 'selection_bridge'; the physical-pad row is NS-P1.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local LuauUIRoot = require("../src")
local fake_target = require("../tests/lib/fake_target")

local function present(kind: string, opts: any)
	local core = customFactory.new()
	local env = LuauUIRoot.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	local adapter = fake_target.new()
	local system = LuauUIRoot.newActionSystem(core)
	local pres = LuauUIRoot.newPresenter(core, env, adapter, system)
	local UI = LuauUIRoot.UI
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.Button({ id = "A", label = "A" }),
			UI.Button({ id = "B", label = "B" }),
		},
	})
	local handle
	if kind == "modal" then
		handle = pres.presentModal(bp, opts)
	else
		handle = pres.present(bp, opts)
	end
	return core, adapter, pres, handle
end

describe("engine-selection bridge (NS-A12)", function()
	it("default surfaces never touch engine selection (NS-A11)", function()
		local _, adapter, pres, handle = present("screen", {})
		expect(adapter.engineSelection).toBe(nil)
		for _, op in adapter.takeOps() do
			expect(string.find(op, "engineselection") == nil).toBe(true)
		end
		pres.dismiss(handle)
		expect(adapter.engineSelection).toBe(nil)
	end)

	it("present() IGNORES the opt (bridge is modal-only)", function()
		local _, adapter, pres, handle = present("screen", { engineSelectionBridge = true })
		expect(adapter.engineSelection).toBe(nil)
		pres.dismiss(handle)
	end)

	it("an opted-in modal mirrors logical focus and clears on dismiss", function()
		local _, adapter, pres, handle = present("modal", { engineSelectionBridge = true })
		-- the presenter focuses the first focusable on present
		expect(adapter.engineSelection ~= nil).toBe(true)
		expect(string.find(adapter.engineSelection, "/S/") ~= nil).toBe(true)
		pres.dismiss(handle)
		expect(adapter.engineSelection).toBe(nil)
	end)

	it("a modal WITHOUT the opt stays engine-silent", function()
		local _, adapter, pres, handle = present("modal", {})
		expect(adapter.engineSelection).toBe(nil)
		pres.dismiss(handle)
		expect(adapter.engineSelection).toBe(nil)
	end)
end)
