--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI
t.describe("destination scroll bookmarks", function()
	t.it("restores a keyed descendant after reorder without retaining the page", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local selection = w.core:signal("a")
		local items = w.core:signal({ "a", "b", "c", "d", "e", "f" })
		local tabs = Facet.Controls.TabView(w.core, {
			id = "Tabs",
			selection = selection,
			placement = "topBar",
			tabs = {
				{
					id = "a",
					label = "Inventory",
					content = function()
						return UI.ScrollView({
							id = "Inventory",
							indicators = "none",
							height = UI.fill(),
							width = UI.fill(),
							children = {
								UI.ForEach({
									id = "Items",
									items = items,
									key = function(item)
										return item
									end,
									row = function(item)
										return UI.Button({
											id = "Item",
											label = item,
											width = UI.fill(),
											height = { type = "fixed", px = 200 },
										})
									end,
								}),
							},
						})
					end,
				},
				{
					id = "b",
					label = "Settings",
					content = function()
						return UI.Text({ id = "Other", text = "Settings" })
					end,
				},
			},
		})
		w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
		local path = "/S/Tabs/Content/Tab-a/then/Inventory"
		w.controller.scrollTo(path, { x = 0, y = 450 })
		selection:set("b")
		w.settle(2)
		items:set({ "f", "a", "b", "c", "d", "e" })
		selection:set("a")
		w.settle(2)
		t.expect(w.controller.scrollPosition(path).y).toBe(650)
		w.settle(90)
		local reads = 0
		local readRect = w.controller.screenRectOf
		w.controller.screenRectOf = function(...)
			reads += 1
			return readRect(...)
		end
		w.settle(5)
		t.expect(reads).toBe(0)
		w.pres.dismiss(w.handle)
		tabs.dispose()
	end)
	for _, kind in { "VirtualList", "VirtualGrid", "Table" } do
		for _, editing in (if kind == "VirtualGrid" then { false } else { false, true }) do
			t.it("restores " .. kind .. " keys with editing=" .. tostring(editing), function()
				local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, preferredInput = "Gamepad" })
				local data = {}
				for i = 1, 100 do
					data[i] = { id = tostring(i), label = "Item " .. i }
				end
				local rows = w.core:signal(data)
				local selected = w.core:signal("a")
				local edit = w.core:signal(editing)
				local builds = 0
				local control
				local tabs = Facet.Controls.TabView(w.core, {
					id = "Tabs",
					selection = selected,
					placement = "topBar",
					tabs = {
						{
							id = "a",
							content = function(scope)
								local spec = {
									id = "Collection",
									key = function(item)
										return item.id
									end,
								}
								local cell = function(item)
									builds += 1
									return UI.Text({ id = "Label", text = item.label, textSize = 14 })
								end
								if kind == "Table" then
									spec.rows = rows
									spec.columns = { { id = "label", title = "Item", width = UI.fill() } }
									spec.cellFor = function(_, item)
										return cell(item)
									end
									spec.virtualized = true
									spec.rowHeight = 100
									spec.rowGap = 0
									spec.header = false
									spec.editing = edit
									spec.reorderable = true
									spec.onReorder = function() end
								elseif kind == "VirtualGrid" then
									spec.items = rows
									spec.columns = 2
									spec.itemExtent = 100
									spec.viewportExtent = 300
									spec.gap = 0
									spec.rowGap = 0
									spec.cell = cell
								else
									spec.rows = rows
									spec.itemExtent = 100
									spec.viewportExtent = 300
									spec.cell = cell
									spec.reorderable = editing
									spec.onReorder = function() end
								end
								control = scope:own(Facet.Controls[kind](w.core, spec))
								return UI.focusSection(control.blueprint)
							end,
						},
						{
							id = "b",
							content = function()
								return UI.Text({ text = "Other" })
							end,
						},
					},
				})
				w.present(UI.Screen({ id = "S", children = { tabs.blueprint } }))
				local path = "/S/Tabs/Content/Tab-a/then/Collection" .. (if kind == "Table" then "/Main/Body" else "")
				w.adapter.driveScroll(path, { x = 0, y = 2050 })
				w.settle(2)
				selected:set("b")
				w.settle(2)
				local next = table.clone(data)
				table.insert(next, 1, table.remove(next))
				if kind == "VirtualGrid" then
					table.insert(next, 1, table.remove(next))
				end
				rows:set(next)
				selected:set("a")
				w.settle(2)
				t.expect(w.controller.scrollPosition(path).y).toBe(2150)
				t.expect(builds < 100).toBe(true)

				selected:set("b")
				w.settle(2)
				local shorter = {}
				for i = 1, 8 do
					shorter[i] = { id = "new-" .. i, label = "Replacement " .. i }
				end
				rows:set(shorter)
				selected:set("a")
				w.settle(3)
				local host = w.controller.scrollHostFor(path, true)
				t.expect(w.controller.scrollPosition(path).y).toBe(host.maxScroll)
				selected:set("b")
				w.settle(2)
				rows:set({})
				selected:set("a")
				w.settle(3)
				t.expect(w.controller.scrollPosition(path).y).toBe(0)
				edit:set(not editing)
				w.settle(2)
				w.pres.dismiss(w.handle)
				tabs.dispose()
			end)
		end
	end
end)
