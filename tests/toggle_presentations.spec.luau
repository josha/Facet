--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local fakeTarget = require("./lib/fake_target")
t.describe("Toggle presentations", function()
	for _, presentation in { "switch", "checkbox", "button" } do
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			t.it(presentation .. " toggles once through " .. input, function()
				local core = Facet.newCore()
				local env = Facet.newEnvironment(core)
				env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
				local value = core:signal(false)
				local mixed = if presentation == "checkbox" then core:signal(true) else nil
				local enabled = core:signal(true)
				local changes = 0
				local control = Facet.Controls.Toggle(core, {
					id = "T",
					label = "Receive race updates with detailed results",
					value = value,
					mixed = mixed,
					presentation = presentation,
					enabled = enabled,
					onChange = function()
						changes += 1
					end,
				})
				local adapter = fakeTarget.new()
				local system = Facet.newActionSystem(core)
				local pres = Facet.newPresenter(core, env, adapter, system)
				pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
				pres.refresh()
				if input == "pointer" or input == "touch" then
					adapter.tap("/S/T", { pointer = input })
				else
					system.deviceKey(if input == "keyboard" then "Return" else "ButtonA", true)
					system.deviceKey(if input == "keyboard" then "Return" else "ButtonA", false)
				end
				t.expect(value:get()).toBe(true)
				t.expect(changes).toBe(1)
				if mixed then
					t.expect(mixed:get()).toBe(false)
				end
				enabled:set(false)
				pres.refresh()
				adapter.tap("/S/T")
				t.expect(changes).toBe(1)
				t.expect(adapter.node("/S/T").rect.h >= 44).toBe(true)
			end)
		end
	end
end)
