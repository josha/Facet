--!strict
-- ADR-0004 Phase 1 proof (UI-INPUT-002): a PreferredInput change updates hint
-- bindings on MOUNTED controls without any factory rerun, remount, or
-- structural change — and other bindings keep working throughout.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src")
local fake_target = require("../tests/lib/fake_target")

describe("hint changes without remount (ADR-0004)", function()
	it("preferredInput flip updates the hint text prop only; zero factory reruns", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local hint = core:memo(function(use)
			local preferred = use(env:get("preferredInput"))
			return if preferred == "Touch" then "Tap Save" else "Press Enter"
		end)
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Text({ id = "Hint", text = hint, textSize = 14 }),
				LuauUI.UI.Button({ id = "Save", label = "Save" }),
			},
		})
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local handle = pres.present(screen)
		local runsBefore = handle.root.counters().factoryRuns
		local mountedBefore = handle.root.counters().mounted
		adapter.takeOps()

		env:set("preferredInput", "Touch")
		pres.refresh()

		expect(adapter.node("/S/Hint").props.text).toBe("Tap Save")
		expect(handle.root.counters().factoryRuns).toBe(runsBefore) -- no rerun
		expect(handle.root.counters().mounted).toBe(mountedBefore) -- no remount
		-- keyboard binding still works after the flip (inputs never removed)
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/S/Save")
	end)
end)
