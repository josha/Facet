--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
t.describe("SplitButton", function()
	t.it("primary activation and menu opening are separate focusable actions", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local calls = 0
		local c = Facet.Controls.SplitButton(w.core, {
			id = "S",
			label = "Race",
			onActivate = function()
				calls += 1
			end,
			items = { { id = "practice", label = "Practice", onSelect = function() end } },
		})
		w.present(Facet.UI.Screen({ id = "Root", children = { c.blueprint } }))
		w.adapter.tap("/Root/S/Primary")
		t.expect(calls).toBe(1)
		w.adapter.tap("/Root/S/Menu")
		w.tick(0)
		t.expect(c.dump().menu.open).toBe(true)
		t.expect(calls).toBe(1)
		c.dispose()
	end)
end)
