--!strict
-- Smoke: the public entry point loads headless under lune via relative
-- require and exposes the Phase 1 surface end to end.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")

describe("Facet public surface", function()
	it("loads headless under lune with the phase-1 API", function()
		expect(Facet.VERSION).toBe("0.10.0") -- bump alongside the changelog entry
		expect(type(Facet.newCore)).toBe("function")
		expect(type(Facet.UI.Screen)).toBe("function")
		expect(type(Facet.mount)).toBe("function")
		expect(type(Facet.newPresenter)).toBe("function")
		expect(type(Facet.replication.snapshot)).toBe("function")
	end)

	it("the public API drives a full slice without touching internals", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local screen = Facet.UI.Screen({
			id = "S",
			children = { Facet.UI.Button({ id = "Go", label = "Go" }) },
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
		local pres = Facet.newPresenter(core, env, adapter, system)
		pres.present(screen)
		expect(created).toBe(2) -- Screen + Button
		expect(pres.focus.focused:get()).toBe("/S/Go")
	end)
end)
