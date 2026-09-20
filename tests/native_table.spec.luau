--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native Table", function()
	t.it("retains rows and cell state across replacement, reorder and resize without Facet scopes", function()
		local app, adapter, advance, core = world()
		local UI = app.controls
		local rows = Compose.cell({ { id = "a", name = "First" }, { id = "b", name = "Second" } })
		local selected = Compose.cell({})
		local factories = 0
		local baseline = core.owner.size()
		local close = app.mount(function()
			local before = core.owner.size()
			local node = UI.Table("Records")({
				rows = rows,
				key = function(item)
					return item.id
				end,
				rowHeight = 48,
				selection = "single",
				selectedKeys = selected,
				columns = {
					{
						id = "name",
						title = "Name",
						resizable = true,
						width = { type = "fill", weight = 1 },
						value = function(item)
							return item.name
						end,
					},
					{
						id = "counter",
						title = "Count",
						width = { type = "fixed", px = 100 },
						cell = function(item)
							factories += 1
							local count = Compose.cell(0)
							return UI.Button({
								label = function(use)
									return `{use(item).name}: {use(count)}`
								end,
								onActivate = function()
									count:update(function(n)
										return n + 1
									end)
								end,
							})
						end,
					},
				},
			})
			t.expect(core.owner.size()).toBe(before)
			return node
		end)
		advance(0.1)
		adapter.driveActivate("/Records/Main/Body/Rows/[a]/Row/Hit")
		t.expect(selected:peek().a).toBe(true)
		local function find(prop, value)
			for _, path in adapter.paths() do
				local node = adapter.node(path)
				if node.props[prop] == value then
					return node, path
				end
			end
			error(`missing {prop}={value}`)
		end
		local original, path = find("label", "First: 0")
		adapter.driveActivate(path)
		advance(0.1)
		t.expect(adapter.node(path).props.label).toBe("First: 1")
		rows:set({ { id = "b", name = "Second" }, { id = "a", name = "Updated" } })
		advance(0.1)
		t.expect(find("label", "Updated: 1")).toBe(original)
		find("text", "Updated")
		t.expect(factories).toBe(2)
		local grip
		for _, candidate in adapter.paths() do
			if candidate:sub(-5) == "/Grip" then
				grip = candidate
				break
			end
		end
		assert(grip, "column resize grip missing")
		local rect = adapter.node(grip).rect
		adapter.pointerDown(grip, rect.x + rect.w / 2, rect.y + rect.h / 2)
		adapter.pointerMove(rect.x + rect.w / 2 - 40, rect.y + rect.h / 2)
		advance(0.1)
		adapter.pointerUp(rect.x + rect.w / 2 - 40, rect.y + rect.h / 2)
		advance(0.1)
		t.expect(find("label", "Updated: 1")).toBe(original)
		t.expect(factories).toBe(2)
		rows:set({ { id = "a", name = "Updated" } })
		advance(0.1)
		close()
		advance(0.1)
		t.expect(core.owner.size()).toBe(baseline)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
	t.it("windows a large table and removes selection when an item leaves the model", function()
		local app, adapter, advance, core = world()
		local items = {}
		for i = 1, 2000 do
			items[i] = { id = tostring(i), name = `Record {i}` }
		end
		local rows, selected = Compose.cell(items), Compose.cell({ ["1"] = true })
		local before = core.owner.size()
		local close = app.mount(function()
			return app.controls.Table("Large")({
				rows = rows,
				key = function(item)
					return item.id
				end,
				selection = "multi",
				selectedKeys = selected,
				virtualized = true,
				rowHeight = 40,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(item)
							return item.name
						end,
					},
				},
			})
		end)
		advance(0.1)
		local function mountedRows()
			local count = 0
			for _, path in adapter.paths() do
				if path:sub(-8) == "/Row/Hit" then
					count += 1
				end
			end
			return count
		end
		t.expect(mountedRows() > 0 and mountedRows() < 30).toBe(true)
		adapter.driveScroll("/Large/Main/Body", { x = 0, y = 4000 })
		advance(0.1)
		t.expect(mountedRows() > 0 and mountedRows() < 30).toBe(true)
		local next = table.clone(items)
		table.remove(next, 1)
		rows:set(next)
		advance(0.1)
		t.expect(selected:peek()["1"]).toBeNil()
		close()
		advance(0.1)
		t.expect(core.owner.size()).toBe(before)
		app.dispose()
	end)
	t.it("updates native sort and edit cells and releases action rows", function()
		local app, adapter, advance, core = world()
		local rows = Compose.cell({ { id = "a", name = "First" } })
		local sortOrder, editing = Compose.cell(nil), Compose.cell(false)
		local before = core.owner.size()
		local close = app.mount(function()
			return app.controls.Table("Actions")({
				rows = rows,
				key = function(item)
					return item.id
				end,
				selection = "multi",
				sortOrder = sortOrder,
				editing = editing,
				columns = {
					{
						id = "name",
						title = "Name",
						width = { type = "fill", weight = 1 },
						value = function(item)
							return item.name
						end,
					},
				},
				rowActions = function()
					return {
						trailing = {
							{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
						},
					}
				end,
			})
		end)
		advance(0.1)
		adapter.driveActivate("/Actions/Main/Header/Head-name/Column")
		advance(0.1)
		t.expect(sortOrder:peek().column).toBe("name")
		t.expect(sortOrder:peek().ascending).toBe(true)
		adapter.driveActivate("/Actions/Main/Header/Head-name/Column")
		advance(0.1)
		t.expect(sortOrder:peek().ascending).toBe(false)
		editing:set(true)
		advance(0.1)
		rows:set({})
		advance(0.1)
		close()
		advance(0.1)
		t.expect(core.owner.size()).toBe(before)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
