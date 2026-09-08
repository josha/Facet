--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
t.describe("Stateful menu", function()
	t.it("checked items and radio items persist while ordinary actions dismiss", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local checked = core:signal(false)
		local selected = core:signal("a")
		local calls = 0
		local menu = Facet.Controls.Menu(core, {
			id = "M",
			trigger = Facet.UI.Button({ id = "T", label = "Filters" }),
			presentation = "menu",
			items = {
				{ id = "check", label = "Favorites", checked = checked },
				{ id = "a", label = "All", selected = selected, value = "a" },
				{ id = "b", label = "Friends", selected = selected, value = "b" },
				{
					id = "done",
					label = "Done",
					onSelect = function()
						calls += 1
					end,
				},
			},
		})
		local adapter = w.adapter
		local pres = w.pres
		pres.present(Facet.UI.Screen({ id = "S", children = { menu.blueprint } }))
		pres.refresh()
		adapter.tap("/S/T")
		pres.refresh()
		local function expectSingleStateIcon(item: string, on: boolean)
			local path = "/Menu-M/Layer/Surface/Panel/Item:" .. item .. "/HStack#1/Indicator/"
			t.expect(adapter.visibleOf(path .. "Outline") == true).toBe(not on)
			t.expect(adapter.visibleOf(path .. "Mark") == true).toBe(on)
		end
		expectSingleStateIcon("check", false)
		expectSingleStateIcon("a", true)
		expectSingleStateIcon("b", false)
		adapter.tap("/Menu-M/Layer/Surface/Panel/Item:check")
		pres.refresh()
		expectSingleStateIcon("check", true)
		t.expect(checked:get()).toBe(true)
		t.expect(menu.dump().open).toBe(true)
		adapter.tap("/Menu-M/Layer/Surface/Panel/Item:b")
		pres.refresh()
		t.expect(selected:get()).toBe("b")
		expectSingleStateIcon("a", false)
		expectSingleStateIcon("b", true)
		t.expect(menu.dump().open).toBe(true)
		adapter.tap("/Menu-M/Layer/Surface/Panel/Item:done")
		pres.refresh()
		t.expect(calls).toBe(1)
		t.expect(menu.dump().open).toBe(false)
	end)
end)
