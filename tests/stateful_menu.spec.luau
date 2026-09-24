--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")
t.describe("Stateful menu", function()
	t.it("checked items and radio items persist while ordinary actions dismiss", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local checked = Compose.cell(false)
		local selected = Compose.cell("a")
		local calls = 0
		local menu = harness.Controls.Menu(core, {
			id = "M",
			trigger = harness.UI.Button({ id = "T", label = "Filters" }),
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
		pres.present(harness.UI.Screen({ id = "S", children = { menu.blueprint } }))
		pres.refresh()
		adapter.tap("/S/T")
		pres.refresh()
		local function expectSingleStateIcon(item: string, on: boolean)
			-- the item's content row is unnamed, so its path segment is found
			local prefix = "/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:" .. item .. "/"
			local path: string? = nil
			for _, candidate in adapter.paths() do
				if string.sub(candidate, 1, #prefix) == prefix and string.match(candidate, "/Indicator$") then
					path = candidate .. "/"
				end
			end
			assert(path, "the item mounts a state indicator")
			t.expect(adapter.visibleOf(path .. "Outline") == true).toBe(not on)
			t.expect(adapter.visibleOf(path .. "Mark") == true).toBe(on)
		end
		expectSingleStateIcon("check", false)
		expectSingleStateIcon("a", true)
		expectSingleStateIcon("b", false)
		adapter.tap("/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:check")
		pres.refresh()
		expectSingleStateIcon("check", true)
		t.expect(checked:peek()).toBe(true)
		t.expect(menu.dump().open).toBe(true)
		adapter.tap("/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:b")
		pres.refresh()
		t.expect(selected:peek()).toBe("b")
		expectSingleStateIcon("a", false)
		expectSingleStateIcon("b", true)
		t.expect(menu.dump().open).toBe(true)
		adapter.tap("/Menu-M/Layer/Surface/Popup/Panel/List/Rows/Item:done")
		pres.refresh()
		t.expect(calls).toBe(1)
		t.expect(menu.dump().open).toBe(false)
	end)
end)
