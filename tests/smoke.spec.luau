--!strict
-- Smoke: the public entry point loads headless under lune via relative
-- require and exposes the Phase 1 surface end to end.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src")

describe("LuauUI public surface", function()
	it("loads headless under lune with the phase-1 API", function()
		expect(LuauUI.VERSION).toBe("0.8.0") -- ADR-0011; bump alongside the ADR
		expect(type(LuauUI.newCore)).toBe("function")
		expect(type(LuauUI.UI.Screen)).toBe("function")
		expect(type(LuauUI.mount)).toBe("function")
		expect(type(LuauUI.newPresenter)).toBe("function")
		expect(type(LuauUI.replication.snapshot)).toBe("function")
	end)

	it("the public API drives a full slice without touching internals", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		local system = LuauUI.newActionSystem(core)
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = { LuauUI.UI.Button({ id = "Go", label = "Go" }) },
		})
		local created = 0
		local adapter = {
			createRoot = function()
				return {}
			end,
			create = function()
				created += 1
				return {}
			end,
			setRect = function() end,
			setProp = function() end,
			remove = function() end,
			destroyRoot = function() end,
		}
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		pres.present(screen)
		expect(created).toBe(2) -- Screen + Button
		expect(pres.focus.focused:get()).toBe("/S/Go")
	end)
end)
