--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local playlistExample = require("../examples/gallery/examples/02_playlist_table")
local themePackages = require("../tools/lune/theme_packages")
local Compose = Facet.Compose

type Stage = {
	engine: any,
	runtime: any,
	UI: any,
	Host: any,
	gui: any,
	input: any,
	screen: any,
	node: any,
	stop: () -> (),
}

local function services(engine: any): (any, any)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	return gui, input
end

local function stage(build: (any, any) -> any, config: { [string]: any }?): Stage
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui, input = services(engine)
	local options: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		userInputService = input,
		services = { GuiService = gui, UserInputService = input },
		reducedMotion = true,
	}
	for key, value in config or {} do
		options[key] = value
	end
	local UI = Facet.controls(runtime, options :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = Host,
		gui = gui,
		input = input,
		screen = screen,
		node = screen:FindFirstChildWhichIsA("Frame"),
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function records(count: number): { any }
	local values = {}
	for index = 1, count do
		values[index] = { id = index, label = tostring(index) }
	end
	return values
end

local function id(item: any): any
	return item.id
end

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function key(root: any, engine: any, code: string): string?
	local wanted = engine.types.Enum.KeyCode[code]
	local best, bestPriority = nil, -math.huge
	for _, context in root:GetDescendants() do
		if context.ClassName == "InputContext" and context.Enabled == true then
			for _, action in context:GetChildren() do
				if action.ClassName == "InputAction" then
					for _, binding in action:GetChildren() do
						if
							binding.ClassName == "InputBinding"
							and binding.KeyCode == wanted
							and context.Priority > bestPriority
						then
							best, bestPriority = action, context.Priority
						end
					end
				end
			end
		end
	end
	if best == nil then
		return nil
	end
	best.Pressed.fire()
	return best.Name
end

local function focus(gui: any, node: any)
	local previous = gui.SelectedObject
	gui.SelectedObject = node
	if previous and previous ~= node then
		previous.SelectionLost.fire()
	end
	if node and previous ~= node then
		node.SelectionGained.fire()
	end
end

local function span(rowNode: any, target: any, canvasX: number): (number, number)
	local path = {}
	local cursor = target
	while cursor and cursor ~= rowNode do
		table.insert(path, 1, cursor)
		cursor = cursor.Parent
	end
	assert(cursor == rowNode, "target is not inside the row")
	local x, width = rowNode.Position.X.Offset - canvasX, rowNode.Size.X.Offset
	for _, node in path do
		local nextWidth = node.Size.X.Scale * width + node.Size.X.Offset
		x += node.Position.X.Scale * width + node.Position.X.Offset - node.AnchorPoint.X * nextWidth
		width = nextWidth
	end
	return x, width
end

local function cellRow(rowNode: any): any
	return assert(rowNode:FindFirstChild("DisclosingRow", true)):FindFirstChild("Row")
end

local function expectSameColumns(header: any, row: any, columns: { string })
	for _, column in columns do
		local top, cell = header:FindFirstChild(column), row:FindFirstChild(column)
		t.expect(top.Size).toBe(cell.Size)
		t.expect(top.LayoutOrder).toBe(cell.LayoutOrder)
		t.expect(top.Visible).toBe(cell.Visible)
		t.expect(top:FindFirstChildWhichIsA("UIFlexItem").FlexMode)
			.toBe(cell:FindFirstChildWhichIsA("UIFlexItem").FlexMode)
		local topLimit, cellLimit =
			top:FindFirstChildWhichIsA("UISizeConstraint"), cell:FindFirstChildWhichIsA("UISizeConstraint")
		t.expect(topLimit.MinSize).toBe(cellLimit.MinSize)
		t.expect(topLimit.MaxSize).toBe(cellLimit.MaxSize)
	end
end

local function expectAligned(table_: any, key_: string, columns: { string })
	local header, body = table_:FindFirstChild("Header"), table_:FindFirstChild("Body")
	local rowNode = body:FindFirstChild("Items"):FindFirstChild(key_)
	local row = cellRow(rowNode)
	local x, width = span(rowNode, row, body.CanvasPosition.X)
	t.expect(x).toBe(header.Position.X.Offset)
	t.expect(width).toBe(header.Size.X.Offset)
	expectSameColumns(header, row, columns)
end

type Playlist = {
	built: any,
	node: any,
	engine: any,
	gui: any,
	input: any,
	target: any,
	tracks: any,
	stop: () -> (),
}

local function playlist(): Playlist
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui, input = services(engine)
	local target = engine.new("Folder")
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		inputTarget = target,
		guiService = gui,
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = viewport,
				guiService = gui,
				userInputService = input,
				services = { GuiService = gui, UserInputService = input },
				inputParent = target,
				reducedMotion = true,
			} :: any
		),
	}
	local built: any
	local stop, node = runtime.mount(function()
		built = playlistExample.build(ctx)
		return ctx.Host.ScreenGui("DemoScreen")({ built.screen() })
	end, target)
	local tracks = find(node, "Tracks")
	tracks:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(800, 288)
	return {
		built = built,
		node = node,
		engine = engine,
		gui = gui,
		input = input,
		target = target,
		tracks = tracks,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function ids(list: { any }): string
	local out = {}
	for _, track in list do
		table.insert(out, track.id)
	end
	return table.concat(out, ",")
end

local function renderedOrder(table_: any): string
	local items = table_:FindFirstChild("Body"):FindFirstChild("Items")
	local rows = {}
	for _, row in items:GetChildren() do
		table.insert(rows, row)
	end
	table.sort(rows, function(a, b)
		return a.Position.Y.Offset < b.Position.Y.Offset
	end)
	local out = {}
	for _, row in rows do
		table.insert(out, row.Name)
	end
	return table.concat(out, ",")
end

t.describe("native parity weaker tables", function()
	t.it("apps2-168 pointer keyboard and gamepad resize the same playlist column and the readout follows", function()
		local p = playlist()
		local V2 = p.engine.types.Vector2
		local header = p.tracks:FindFirstChild("Header")
		local name = header:FindFirstChild("name")
		name.AbsoluteSize = V2.new(220, 40)
		local readout = find(p.node, "Widths")
		t.expect(readout.Text).toBe("Name auto · Artist auto · Rating locked")
		local hint = find(p.node, "Hint")
		t.expect(hint.Text).toBe(p.built.hint())
		t.expect(hint.Text:find("drag a divider to resize", 1, true) ~= nil).toBe(true)
		local grip = name:FindFirstChild("Resize")
		local drag = grip:FindFirstChildWhichIsA("UIDragDetector")
		drag.DragStart.fire(V2.new(236, 10))
		drag.DragContinue.fire(V2.new(146, 10))
		drag.DragEnd.fire()
		t.expect(p.built.columnWidths:peek().name).toBe(130)
		t.expect(readout.Text).toBe("Name 130px · Artist auto · Rating locked")
		t.expect(p.built.widths()).toBe(readout.Text)
		focus(p.gui, grip)
		t.expect(key(p.target, p.engine, "Right")).toBe("WidenColumn")
		t.expect(p.built.columnWidths:peek().name).toBe(138)
		t.expect(key(p.target, p.engine, "Left")).toBe("NarrowColumn")
		t.expect(key(p.target, p.engine, "Left")).toBe("NarrowColumn")
		t.expect(p.built.columnWidths:peek().name).toBe(122)
		t.expect(readout.Text).toBe("Name 122px · Artist auto · Rating locked")
		t.expect(key(p.target, p.engine, "DPadRight")).toBe("WidenColumn")
		t.expect(p.built.columnWidths:peek().name).toBe(130)
		t.expect(key(p.target, p.engine, "DPadLeft")).toBe("NarrowColumn")
		t.expect(p.built.columnWidths:peek().name).toBe(122)
		t.expect(readout.Text).toBe("Name 122px · Artist auto · Rating locked")
		local rating = header:FindFirstChild("rating")
		t.expect(rating:FindFirstChild("Resize")).toBeNil()
		focus(p.gui, rating:FindFirstChild("Sort"))
		for _, code in { "Right", "Left", "DPadRight", "DPadLeft" } do
			local handled = key(p.target, p.engine, code)
			t.expect(handled ~= "WidenColumn" and handled ~= "NarrowColumn").toBe(true)
		end
		t.expect(p.built.columnWidths:peek().rating).toBeNil()
		t.expect(p.built.columnWidths:peek().name).toBe(122)
		t.expect(readout.Text).toBe("Name 122px · Artist auto · Rating locked")
		local artist = header:FindFirstChild("artist")
		artist.AbsoluteSize = V2.new(220, 40)
		focus(p.gui, artist:FindFirstChild("Resize"))
		t.expect(key(p.target, p.engine, "DPadRight")).toBe("WidenColumn")
		t.expect(readout.Text).toBe("Name 122px · Artist 228px · Rating locked")
		p.stop()
	end)

	t.it("apps2-171 the playlist ships unsorted and the Name heading cycles a sort the filter composes with", function()
		local p = playlist()
		local shipped = "neon,drift,turbo,pit,photo,apex"
		t.expect(p.built.sort:peek()).toBeNil()
		t.expect(p.built.sortedRows:peek()).toBe(p.built.baseRows:peek())
		t.expect(p.built.from:peek()).toBe(p.built.baseRows:peek())
		t.expect(ids(p.built.from:peek())).toBe(shipped)
		t.expect(renderedOrder(p.tracks)).toBe(shipped)
		local nameSort = p.tracks:FindFirstChild("Header"):FindFirstChild("name"):FindFirstChild("Sort")
		nameSort.Activated.fire()
		t.expect(p.built.sort:peek()).toEqual({ column = "name", direction = "ascending" })
		t.expect(ids(p.built.from:peek())).toBe("apex,drift,neon,photo,pit,turbo")
		t.expect(renderedOrder(p.tracks)).toBe("apex,drift,neon,photo,pit,turbo")
		t.expect(ids(p.built.baseRows:peek())).toBe(shipped)
		nameSort.Activated.fire()
		t.expect(p.built.sort:peek()).toEqual({ column = "name", direction = "descending" })
		t.expect(ids(p.built.from:peek())).toBe("turbo,pit,photo,neon,drift,apex")
		t.expect(renderedOrder(p.tracks)).toBe("turbo,pit,photo,neon,drift,apex")
		nameSort.Activated.fire()
		t.expect(p.built.sort:peek()).toEqual({ column = "name", direction = "ascending" })
		p.built.filterText:set("i")
		t.expect(ids(p.built.from:peek())).toBe("drift,neon,photo,pit")
		t.expect(renderedOrder(p.tracks)).toBe("drift,neon,photo,pit")
		nameSort.Activated.fire()
		t.expect(ids(p.built.from:peek())).toBe("pit,photo,neon,drift")
		t.expect(renderedOrder(p.tracks)).toBe("pit,photo,neon,drift")
		t.expect(ids(p.built.baseRows:peek())).toBe(shipped)
		p.stop()
	end)

	t.it(
		"apps2-173 a manual reorder bakes the sort, a refused or empty reorder keeps it, and Restore clears it",
		function()
			local p = playlist()
			local nameSort = p.tracks:FindFirstChild("Header"):FindFirstChild("name"):FindFirstChild("Sort")
			nameSort.Activated.fire()
			t.expect(ids(p.built.from:peek())).toBe("apex,drift,neon,photo,pit,turbo")
			p.built.reorder({ "apex" }, 2)
			t.expect(p.built.sort:peek()).toBeNil()
			t.expect(ids(p.built.baseRows:peek())).toBe("drift,neon,apex,photo,pit,turbo")
			t.expect(ids(p.built.from:peek())).toBe("drift,neon,apex,photo,pit,turbo")
			t.expect(renderedOrder(p.tracks)).toBe("drift,neon,apex,photo,pit,turbo")
			nameSort.Activated.fire()
			p.built.moveToTop("turbo")
			t.expect(p.built.sort:peek()).toBeNil()
			t.expect(ids(p.built.from:peek())).toBe("turbo,apex,drift,neon,photo,pit")
			nameSort.Activated.fire()
			local before = ids(p.built.baseRows:peek())
			p.built.moveToTop("not-in-the-playlist")
			p.built.reorder({}, 3)
			t.expect(p.built.sort:peek()).toEqual({ column = "name", direction = "ascending" })
			t.expect(ids(p.built.baseRows:peek())).toBe(before)
			p.built.removeTrack("neon")
			t.expect(p.built.sort:peek()).toEqual({ column = "name", direction = "ascending" })
			t.expect(ids(p.built.from:peek())).toBe("apex,drift,photo,pit,turbo")
			p.built.filterText:set("i")
			local filtered = ids(p.built.baseRows:peek())
			p.built.reorder({ "photo" }, 0)
			t.expect(ids(p.built.baseRows:peek())).toBe(filtered)
			t.expect(p.built.sort:peek()).toEqual({ column = "name", direction = "ascending" })
			p.built.ratingFor("neon"):set(1)
			p.built.nowPlaying:set("Photo Finish")
			find(p.node, "Restore").Activated.fire()
			t.expect(p.built.sort:peek()).toBeNil()
			t.expect(p.built.filterText:peek()).toBe("")
			t.expect(p.built.nowPlaying:peek()).toBeNil()
			t.expect(p.built.ratingFor("neon"):peek()).toBe(4)
			t.expect(ids(p.built.from:peek())).toBe("neon,drift,turbo,pit,photo,apex")
			t.expect(renderedOrder(p.tracks)).toBe("neon,drift,turbo,pit,photo,apex")
			t.expect(nameSort.Text).toBe("Name")
			p.stop()
		end
	)

	t.it("apps2-175 the resize grip keeps one trailing edge and sizes its target per input paradigm", function()
		local w = stage(function(UI)
			return UI.Table({
				from = records(2),
				key = id,
				columns = {
					{ id = "name", label = "Name", width = 200 },
					{ id = "laps", label = "Laps", width = 64, resizable = false },
				},
			})
		end)
		local E, V2, D2 = w.engine.types.Enum, w.engine.types.Vector2, w.engine.types.UDim2
		local header = w.node:FindFirstChild("Header")
		local grip = header:FindFirstChild("name"):FindFirstChild("Resize")
		t.expect(header:FindFirstChild("laps"):FindFirstChild("Resize")).toBeNil()
		local sort = header:FindFirstChild("name"):FindFirstChild("Sort")
		for _, case in
			{
				{ E.PreferredInput.KeyboardAndMouse, 12 },
				{ E.PreferredInput.Touch, 44 },
				{ E.PreferredInput.Gamepad, 12 },
				{ E.PreferredInput.KeyboardAndMouse, 12 },
			}
		do
			w.input.PreferredInput = case[1]
			t.expect(grip.Size).toBe(D2.new(0, case[2], 1, 0))
			t.expect(grip.AnchorPoint).toBe(V2.new(1, 0))
			t.expect(grip.Position).toBe(D2.fromScale(1, 0))
			t.expect(grip.Selectable).toBe(true)
			t.expect(grip.ZIndex > sort.ZIndex).toBe(true)
			t.expect(grip:GetAttribute("AccessibleLabel")).toBe("Resize Name")
		end
		w.stop()
	end)

	t.it("apps-242 touch and gamepad table rows clear the 44 floor with no wiring and a pinned height wins", function()
		local w = stage(function(UI)
			return UI.Table({
				from = records(3),
				key = id,
				controls = {},
				columns = { { id = "label", label = "Label" } },
			})
		end, { theme = { metrics = { controlSizes = { regular = { height = 32 } } } } })
		local pinnedControls: any = {}
		local pinned = stage(function(UI)
			return UI.Table({
				from = records(3),
				key = id,
				itemSize = 52,
				controls = pinnedControls,
				columns = { { id = "label", label = "Label" } },
			})
		end)
		local E, V2 = w.engine.types.Enum, w.engine.types.Vector2
		local body = w.node:FindFirstChild("Body")
		body.AbsoluteWindowSize = V2.new(300, 300)
		pinned.node:FindFirstChild("Body").AbsoluteWindowSize = V2.new(300, 300)
		local first = body:FindFirstChild("Items"):FindFirstChild("1")
		local pointer = first.Size.Y.Offset
		t.expect(pointer).toBe(40)
		for _, preferred in { E.PreferredInput.Touch, E.PreferredInput.Gamepad } do
			w.input.PreferredInput = preferred
			t.expect(first.Size.Y.Offset).toBe(44)
			t.expect(body:FindFirstChild("Items"):FindFirstChild("2").Position.Y.Offset).toBe(44)
			t.expect(first.Size.Y.Offset > pointer).toBe(true)
		end
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(first.Size.Y.Offset).toBe(40)
		for _, preferred in { E.PreferredInput.Touch, E.PreferredInput.KeyboardAndMouse, E.PreferredInput.Gamepad } do
			pinned.input.PreferredInput = preferred
			t.expect(pinnedControls.placementOf(2).offset).toBe(52)
			t.expect(pinnedControls.placementOf(1).size).toBe(52)
		end
		w.stop()
		pinned.stop()
	end)

	t.it(
		"collections-36 Table keeps cell state, windows large data, prunes selection and releases action rows",
		function()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui, input = services(engine)
			local UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					userInputService = input,
					services = { GuiService = gui, UserInputService = input },
					reducedMotion = true,
				} :: any
			)
			local V2 = engine.types.Vector2
			local host = engine.new("Folder")
			local baseline = engine.census()
			local rows = Compose.cell({ { id = "a", name = "First" }, { id = "b", name = "Second" } })
			local selected, sort, editing, widths =
				Compose.cell({}), Compose.cell(nil), Compose.cell(false), Compose.cell({})
			local factories, released = 0, 0
			local counts: { [string]: any } = {}
			local stop, node = runtime.mount(function()
				return runtime.constructors.ScreenGui({
					UI.Table("Records")({
						from = rows,
						key = id,
						selection = selected,
						selectionMode = "single",
						sort = sort,
						widths = widths,
						editing = editing,
						columns = {
							{
								id = "name",
								label = "Name",
								value = function(item)
									return item.name
								end,
							},
							{
								id = "counter",
								label = "Count",
								width = 100,
								render = function(current, _, rowKey)
									factories += 1
									local count = Compose.cell(0)
									counts[rowKey] = count
									Compose.cleanup(function()
										released += 1
									end)
									return UI.Button("Counter")({
										label = function(use)
											return `{use(current).name}: {use(count)}`
										end,
										onActivate = function()
											count:update(function(value)
												return value + 1
											end)
										end,
									})
								end,
							},
						},
						rowActions = function()
							return {
								trailing = {
									{
										id = "delete",
										label = "Delete",
										role = "destructive",
										onActivate = function() end,
									},
								},
							}
						end,
					}),
				})
			end, host)
			local table_ = node:FindFirstChild("Records")
			local body = table_:FindFirstChild("Body")
			body.AbsoluteWindowSize = V2.new(400, 200)
			local rowA = body:FindFirstChild("Items"):FindFirstChild("a")
			rowA:FindFirstChild("RowHit", true).Activated.fire()
			t.expect(selected:peek()).toEqual({ a = true })
			local counter = rowA:FindFirstChild("Counter", true)
			counter.Activated.fire()
			t.expect(counter.Text).toBe("First: 1")
			rows:set({ { id = "b", name = "Second" }, { id = "a", name = "Updated" } })
			t.expect(rowA:FindFirstChild("Counter", true)).toBe(counter)
			t.expect(counter.Text).toBe("Updated: 1")
			t.expect(rowA:FindFirstChild("Value", true).Text).toBe("Updated")
			t.expect(factories).toBe(2)
			table_:FindFirstChild("Header"):FindFirstChild("name"):FindFirstChild("Sort").Activated.fire()
			t.expect(sort:peek()).toEqual({ column = "name", direction = "ascending" })
			table_:FindFirstChild("Header"):FindFirstChild("name"):FindFirstChild("Sort").Activated.fire()
			t.expect(sort:peek()).toEqual({ column = "name", direction = "descending" })
			local nameColumn = table_:FindFirstChild("Header"):FindFirstChild("name")
			nameColumn.AbsoluteSize = V2.new(200, 40)
			local drag = nameColumn:FindFirstChild("Resize"):FindFirstChildWhichIsA("UIDragDetector")
			drag.DragStart.fire(V2.new(200, 10))
			drag.DragContinue.fire(V2.new(160, 10))
			t.expect(widths:peek().name).toBe(160)
			t.expect(rowA:FindFirstChild("Counter", true)).toBe(counter)
			t.expect(counts.a:peek()).toBe(1)
			t.expect(factories).toBe(2)
			editing:set(true)
			local actionRows = {}
			for _, candidate in body:GetDescendants() do
				if candidate:FindFirstChild("trailing") then
					table.insert(actionRows, candidate)
				end
			end
			t.expect(#actionRows).toBe(2)
			rows:set({ { id = "b", name = "Second" } })
			t.expect(selected:peek()).toEqual({})
			t.expect(released).toBe(1)
			rows:set({})
			t.expect(released).toBe(2)
			for _, actionRow in actionRows do
				t.expect(actionRow:isDestroyed()).toBe(true)
			end
			stop()
			runtime:dispose()
			t.expect(released).toBe(2)
			local after = engine.census()
			t.expect(after.live).toBe(baseline.live)
			t.expect(after.connections).toBe(baseline.connections)
			local many = {}
			for index = 1, 2000 do
				many[index] = { id = tostring(index), name = `Record {index}` }
			end
			local large = Compose.cell(many)
			local status: any = Compose.cell({
				mode = "windowed",
				direction = "vertical",
				total = 0,
				retained = 0,
				first = 0,
				last = 0,
				firstRow = 0,
				lastRow = 0,
				rowCount = 0,
				extent = 0,
				following = false,
				measured = 0,
			})
			local chosen = Compose.cell({ ["1"] = true })
			local w = stage(function(UIs)
				return UIs.Table({
					from = large,
					key = id,
					itemSize = 40,
					status = status,
					selection = chosen,
					selectionMode = "multi",
					columns = { { id = "name", label = "Name" } },
				})
			end)
			local largeBody = w.node:FindFirstChild("Body")
			largeBody.AbsoluteWindowSize = V2.new(400, 400)
			local function mounted(): number
				return #largeBody:FindFirstChild("Items"):GetChildren()
			end
			t.expect(status:peek().total).toBe(2000)
			t.expect(mounted() > 0 and mounted() < 30).toBe(true)
			largeBody.CanvasPosition = V2.new(0, 40000)
			t.expect(mounted() > 0 and mounted() < 30).toBe(true)
			t.expect(largeBody:FindFirstChild("Items"):FindFirstChild("1001") ~= nil).toBe(true)
			t.expect(largeBody:FindFirstChild("Items"):FindFirstChild("1")).toBeNil()
			local shorter = table.clone(many)
			table.remove(shorter, 1)
			large:set(shorter)
			t.expect(chosen:peek()["1"]).toBeNil()
			w.stop()
		end
	)

	t.it("collections-37 a focused grip widens narrows clamps and releases its keys", function()
		local widths = Compose.cell({})
		local w = stage(function(UI)
			return UI.Table({
				from = records(3),
				key = id,
				widths = widths,
				columns = {
					{ id = "name", label = "Name", width = 200, minWidth = 80, maxWidth = 224 },
					{ id = "laps", label = "Laps", width = 64, resizable = false },
				},
			})
		end)
		local V2 = w.engine.types.Vector2
		local header = w.node:FindFirstChild("Header")
		local name, laps = header:FindFirstChild("name"), header:FindFirstChild("laps")
		name.AbsoluteSize = V2.new(200, 40)
		local grip = name:FindFirstChild("Resize")
		t.expect(laps:FindFirstChild("Resize")).toBeNil()
		t.expect(key(w.screen, w.engine, "Left")).toBeNil()
		t.expect(key(w.screen, w.engine, "DPadRight")).toBeNil()
		t.expect(widths:peek()).toEqual({})
		focus(w.gui, grip)
		t.expect(key(w.screen, w.engine, "Right")).toBe("WidenColumn")
		t.expect(widths:peek().name).toBe(208)
		t.expect(key(w.screen, w.engine, "Left")).toBe("NarrowColumn")
		t.expect(widths:peek().name).toBe(200)
		t.expect(key(w.screen, w.engine, "DPadRight")).toBe("WidenColumn")
		t.expect(widths:peek().name).toBe(208)
		t.expect(key(w.screen, w.engine, "DPadLeft")).toBe("NarrowColumn")
		t.expect(widths:peek().name).toBe(200)
		for _ = 1, 5 do
			key(w.screen, w.engine, "Right")
		end
		t.expect(widths:peek().name).toBe(224)
		focus(w.gui, laps:FindFirstChild("Sort"))
		for _, code in { "Left", "Right", "DPadLeft", "DPadRight" } do
			t.expect(key(w.screen, w.engine, code)).toBeNil()
		end
		t.expect(widths:peek().name).toBe(224)
		focus(w.gui, grip)
		for _ = 1, 30 do
			t.expect(key(w.screen, w.engine, "Left")).toBe("NarrowColumn")
		end
		t.expect(widths:peek().name).toBe(80)
		focus(w.gui, nil)
		t.expect(key(w.screen, w.engine, "Right")).toBeNil()
		t.expect(widths:peek().name).toBe(80)
		w.stop()
	end)

	t.it(
		"collections-133 fill and fixed columns align in every row, rows take variable heights, dispose frees",
		function()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui, input = services(engine)
			local UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					userInputService = input,
					services = { GuiService = gui, UserInputService = input },
					reducedMotion = true,
				} :: any
			)
			local V2 = engine.types.Vector2
			local host = engine.new("Folder")
			local baseline = engine.census()
			local controls: any = {}
			local stop, screen = runtime.mount(function()
				return runtime.constructors.ScreenGui({
					UI.Table({
						from = {
							{ id = "razz", name = "Razz Raccoon", laps = 3 },
							{ id = "bolt", name = "Bolt", laps = 5 },
							{ id = "josh", name = "Josh", laps = 2 },
						},
						key = id,
						controls = controls,
						itemSize = 40,
						columns = {
							{ id = "name", label = "Name" },
							{ id = "laps", label = "Laps", width = 64 },
						},
					}),
				})
			end, host)
			local table_ = screen:FindFirstChildWhichIsA("Frame")
			local header, body = table_:FindFirstChild("Header"), table_:FindFirstChild("Body")
			body.AbsoluteWindowSize = V2.new(800, 400)
			for _, rowKey in { "razz", "bolt", "josh" } do
				expectAligned(table_, rowKey, { "name", "laps" })
			end
			t.expect(header:FindFirstChild("laps").Size.X.Offset).toBe(64)
			t.expect(header:FindFirstChild("name"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
				.toBe(engine.types.Enum.UIFlexMode.Fill)
			local items = body:FindFirstChild("Items")
			items:FindFirstChild("bolt"):FindFirstChild("Value", true).TextBounds = V2.new(100, 56)
			t.expect(controls.placementOf(1).size).toBe(40)
			t.expect(controls.placementOf(2).size).toBe(72)
			t.expect(items:FindFirstChild("bolt").Position.Y.Offset).toBe(40)
			t.expect(items:FindFirstChild("josh").Position.Y.Offset).toBe(112)
			t.expect(items:FindFirstChild("bolt").Size.Y.Offset).toBe(72)
			for _, rowKey in { "razz", "bolt", "josh" } do
				expectAligned(table_, rowKey, { "name", "laps" })
			end
			stop()
			runtime:dispose()
			local after = engine.census()
			t.expect(after.live).toBe(baseline.live)
			t.expect(after.connections).toBe(baseline.connections)
		end
	)

	t.it("collections-134 the header follows the reorder and edit gutters so columns stay aligned", function()
		local editing = Compose.cell(false)
		for _, reorderable in { true, false } do
			editing:set(false)
			local w = stage(function(UI)
				return UI.Table({
					from = records(3),
					key = id,
					itemSize = 40,
					editing = editing,
					reorderable = reorderable,
					onReorder = function() end,
					rowActions = function()
						return {
							trailing = {
								{ id = "remove", label = "Remove", role = "destructive", onActivate = function() end },
							},
						}
					end,
					columns = {
						{ id = "a", width = 100 },
						{ id = "b" },
					},
				})
			end)
			local V2 = w.engine.types.Vector2
			local body = w.node:FindFirstChild("Body")
			body.AbsoluteWindowSize = V2.new(400, 200)
			for _, row in body:FindFirstChild("Items"):GetChildren() do
				row.AbsoluteSize = V2.new(400, 40)
				for _, child in row:GetDescendants() do
					if child:FindFirstChild("trailing") then
						child.AbsoluteSize = V2.new(400, 40)
					end
				end
			end
			local header = w.node:FindFirstChild("Header")
			local gutter = if reorderable then 56 else 0
			t.expect(header.Position.X.Offset).toBe(gutter)
			for _, rowKey in { "1", "2", "3" } do
				expectAligned(w.node, rowKey, { "a", "b" })
			end
			editing:set(true)
			t.expect(header.Position.X.Offset > gutter).toBe(true)
			for _, rowKey in { "1", "2", "3" } do
				expectAligned(w.node, rowKey, { "a", "b" })
			end
			body.CanvasPosition = V2.new(30, 0)
			for _, rowKey in { "1", "2", "3" } do
				expectAligned(w.node, rowKey, { "a", "b" })
			end
			body.CanvasPosition = V2.new(0, 0)
			editing:set(false)
			t.expect(header.Position.X.Offset).toBe(gutter)
			for _, rowKey in { "1", "2", "3" } do
				expectAligned(w.node, rowKey, { "a", "b" })
			end
			w.stop()
		end
	end)

	t.it("collections-137 single replaces, multi toggles additively and keyboard focus walks and selects", function()
		local single = Compose.cell({})
		local w = stage(function(UI)
			return UI.Table({
				from = records(4),
				key = id,
				itemSize = 40,
				selection = single,
				selectionMode = "single",
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local E, V2 = w.engine.types.Enum, w.engine.types.Vector2
		local body = w.node:FindFirstChild("Body")
		body.AbsoluteWindowSize = V2.new(300, 300)
		local items = body:FindFirstChild("Items")
		local function hit(rowKey: string): any
			return items:FindFirstChild(rowKey):FindFirstChild("RowHit", true)
		end
		local touch = { UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown }
		local rowTwo, rowThree = items:FindFirstChild("2"), items:FindFirstChild("3")
		hit("2").Activated.fire(touch, 1)
		t.expect(single:peek()).toEqual({ [2] = true })
		t.expect(hit("2"):GetAttribute("FacetSelected")).toBe(true)
		hit("3").Activated.fire(touch, 1)
		t.expect(single:peek()).toEqual({ [3] = true })
		t.expect(hit("2"):GetAttribute("FacetSelected")).toBe(false)
		t.expect(hit("3"):GetAttribute("FacetSelected")).toBe(true)
		t.expect(items:FindFirstChild("2")).toBe(rowTwo)
		t.expect(items:FindFirstChild("3")).toBe(rowThree)
		focus(w.gui, hit("1"))
		t.expect(key(w.screen, w.engine, "Down")).toBe("CollectionDown")
		t.expect(w.gui.SelectedObject).toBe(hit("2"))
		t.expect(key(w.screen, w.engine, "DPadDown")).toBe("CollectionDown")
		t.expect(w.gui.SelectedObject).toBe(hit("3"))
		t.expect(key(w.screen, w.engine, "Up")).toBe("CollectionUp")
		t.expect(w.gui.SelectedObject).toBe(hit("2"))
		local enter = { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
		w.gui.SelectedObject.Activated.fire(enter, 1)
		t.expect(single:peek()).toEqual({ [2] = true })
		w.stop()
		local multi = Compose.cell({})
		local m = stage(function(UI)
			return UI.Table({
				from = records(4),
				key = id,
				itemSize = 40,
				selection = multi,
				selectionMode = "multi",
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local multiBody = m.node:FindFirstChild("Body")
		multiBody.AbsoluteWindowSize = V2.new(300, 300)
		local function multiHit(rowKey: string): any
			return multiBody:FindFirstChild("Items"):FindFirstChild(rowKey):FindFirstChild("RowHit", true)
		end
		multiHit("1").Activated.fire(touch, 1)
		multiHit("3").Activated.fire(touch, 1)
		t.expect(multi:peek()).toEqual({ [1] = true, [3] = true })
		multiHit("1").Activated.fire(touch, 1)
		t.expect(multi:peek()).toEqual({ [3] = true })
		t.expect(multiHit("1"):GetAttribute("FacetSelected")).toBe(false)
		t.expect(multiHit("3"):GetAttribute("FacetSelected")).toBe(true)
		m.stop()
	end)

	t.it("collections-142 columns own value and render cells, coerce numbers and cycle the header sort", function()
		local sort = Compose.cell(nil)
		local controls: any = {}
		local w = stage(function(UI)
			return UI.Table({
				from = {
					{ id = "razz", name = "Razz Raccoon", laps = 3 },
					{ id = "bolt", name = "Bolt", laps = 12 },
					{ id = "josh", name = "Josh", laps = 5 },
				},
				key = id,
				sort = sort,
				controls = controls,
				itemSize = 40,
				columns = {
					{
						id = "name",
						label = "Racer",
						sortable = false,
						render = function(current)
							return UI.Label("Custom")({
								text = function(use)
									return use(current).name
								end,
							})
						end,
					},
					{
						id = "laps",
						label = "Laps",
						width = 64,
						value = function(item)
							return item.laps
						end,
					},
				},
			})
		end)
		local V2 = w.engine.types.Vector2
		local body = w.node:FindFirstChild("Body")
		body.AbsoluteWindowSize = V2.new(400, 300)
		local items = body:FindFirstChild("Items")
		local razz = items:FindFirstChild("razz")
		t.expect(razz:FindFirstChild("name", true):FindFirstChild("Custom", true).Text).toBe("Razz Raccoon")
		t.expect(razz:FindFirstChild("name", true):FindFirstChild("Value", true)).toBeNil()
		local laps = razz:FindFirstChild("laps", true):FindFirstChild("Value", true)
		t.expect(laps.Text).toBe("3")
		t.expect(type(laps.Text)).toBe("string")
		local header = w.node:FindFirstChild("Header")
		local lapsSort = header:FindFirstChild("laps"):FindFirstChild("Sort")
		local nameSort = header:FindFirstChild("name"):FindFirstChild("Sort")
		t.expect(lapsSort.Text).toBe("Laps")
		t.expect(lapsSort.Selectable).toBe(true)
		lapsSort.Activated.fire()
		t.expect(sort:peek()).toEqual({ column = "laps", direction = "ascending" })
		t.expect(lapsSort.Text).toBe("Laps ↑")
		t.expect(controls.indexOfKey("razz")).toBe(1)
		t.expect(controls.indexOfKey("josh")).toBe(2)
		t.expect(controls.indexOfKey("bolt")).toBe(3)
		t.expect(renderedOrder(w.node)).toBe("razz,josh,bolt")
		lapsSort.Activated.fire()
		t.expect(sort:peek()).toEqual({ column = "laps", direction = "descending" })
		t.expect(lapsSort.Text).toBe("Laps ↓")
		t.expect(renderedOrder(w.node)).toBe("bolt,josh,razz")
		t.expect(items:FindFirstChild("razz")).toBe(razz)
		lapsSort.Activated.fire()
		t.expect(sort:peek()).toEqual({ column = "laps", direction = "ascending" })
		t.expect(nameSort.Selectable).toBe(false)
		t.expect(nameSort.Interactable).toBe(false)
		nameSort.Activated.fire()
		t.expect(sort:peek()).toEqual({ column = "laps", direction = "ascending" })
		t.expect(nameSort.Text).toBe("Racer")
		w.stop()
	end)

	t.it("collections-144 a Table row gap spaces the rows and the drop line follows the gap", function()
		local controls: any = {}
		local requests = {}
		local w = stage(function(UI)
			return UI.Table({
				from = records(3),
				key = id,
				itemSize = 40,
				gap = 4,
				header = false,
				controls = controls,
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local V2 = w.engine.types.Vector2
		local body = w.node:FindFirstChild("Body")
		body.AbsoluteWindowSize = V2.new(300, 300)
		local items = body:FindFirstChild("Items")
		t.expect(items:FindFirstChild("1").Position.Y.Offset).toBe(0)
		t.expect(items:FindFirstChild("2").Position.Y.Offset).toBe(44)
		t.expect(items:FindFirstChild("3").Position.Y.Offset).toBe(88)
		t.expect(items:FindFirstChild("2").Size.Y.Offset).toBe(40)
		local detector = items:FindFirstChild("1"):FindFirstChild("Move", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2.new(10, 20))
		detector.DragContinue.fire(V2.new(10, 70))
		t.expect(w.node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(88)
		detector.DragContinue.fire(V2.new(10, 60))
		t.expect(w.node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(44)
		detector.DragContinue.fire(V2.new(10, 70))
		detector.DragEnd.fire()
		t.expect(requests).toEqual({ { keys = { 1 }, slot = 1 } })
		t.expect(w.node:FindFirstChild("DropLine", true)).toBeNil()
		w.stop()
	end)

	t.it("collections-164 a numeric Table gap drives row pitch and the drop slot arithmetic", function()
		local function pitch(gap: number?): (number, number)
			local controls: any = {}
			local w = stage(function(UI)
				return UI.Table({
					from = records(4),
					key = id,
					itemSize = 40,
					gap = gap,
					header = false,
					controls = controls,
					columns = { { id = "label", label = "Label", width = 100 } },
				})
			end)
			w.node:FindFirstChild("Body").AbsoluteWindowSize = w.engine.types.Vector2.new(300, 400)
			local first, second = controls.placementOf(1), controls.placementOf(2)
			local between = second.offset - (first.offset + first.size)
			local extent = controls.placementOf(4).offset + controls.placementOf(4).size
			w.stop()
			return between, extent
		end
		t.expect(select(1, pitch(nil))).toBe(0)
		t.expect(select(1, pitch(6))).toBe(6)
		t.expect(select(2, pitch(6))).toBe(178)
		local requests = {}
		local w = stage(function(UI)
			return UI.Table({
				from = records(4),
				key = id,
				itemSize = 40,
				gap = 6,
				header = false,
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local V2 = w.engine.types.Vector2
		local items = w.node:FindFirstChild("Body")
		items.AbsoluteWindowSize = V2.new(300, 400)
		local detector = items
			:FindFirstChild("Items")
			:FindFirstChild("1")
			:FindFirstChild("Move", true)
			:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2.new(10, 20))
		detector.DragContinue.fire(V2.new(10, 112))
		t.expect(w.node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(138)
		detector.DragEnd.fire()
		t.expect(requests).toEqual({ { keys = { 1 }, slot = 2 } })
		w.stop()
	end)

	t.it("collections-151 only resizable columns grow a grip that resizes and clamps both bounds", function()
		local widths = Compose.cell({})
		local w = stage(function(UI)
			return UI.Table({
				from = records(2),
				key = id,
				widths = widths,
				columns = {
					{ id = "name", label = "Name", width = 200, minWidth = 80, maxWidth = 260 },
					{ id = "laps", label = "Laps", width = 64, resizable = false },
					{ id = "note", label = "Note" },
				},
			})
		end)
		local V2 = w.engine.types.Vector2
		local header = w.node:FindFirstChild("Header")
		local name = header:FindFirstChild("name")
		t.expect(name:FindFirstChild("Resize") ~= nil).toBe(true)
		t.expect(header:FindFirstChild("note"):FindFirstChild("Resize") ~= nil).toBe(true)
		t.expect(header:FindFirstChild("laps"):FindFirstChild("Resize")).toBeNil()
		t.expect(header:FindFirstChild("laps"):FindFirstChildWhichIsA("UIDragDetector", true)).toBeNil()
		name.AbsoluteSize = V2.new(200, 40)
		local drag = name:FindFirstChild("Resize"):FindFirstChildWhichIsA("UIDragDetector")
		drag.DragStart.fire(V2.new(200, 10))
		drag.DragContinue.fire(V2.new(10, 10))
		t.expect(widths:peek().name).toBe(80)
		drag.DragContinue.fire(V2.new(500, 10))
		t.expect(widths:peek().name).toBe(260)
		drag.DragContinue.fire(V2.new(150, 10))
		t.expect(widths:peek().name).toBe(150)
		drag.DragEnd.fire()
		t.expect(header:FindFirstChild("name").Size.X.Offset).toBe(150)
		w.node:FindFirstChild("Body").AbsoluteWindowSize = V2.new(600, 200)
		local row = cellRow(w.node:FindFirstChild("Body"):FindFirstChild("Items"):FindFirstChild("1"))
		t.expect(row:FindFirstChild("name").Size.X.Offset).toBe(150)
		name.AbsoluteSize = V2.new(150, 40)
		focus(w.gui, name:FindFirstChild("Resize"))
		t.expect(key(w.screen, w.engine, "Left")).toBe("NarrowColumn")
		t.expect(widths:peek().name).toBe(142)
		t.expect(row:FindFirstChild("name").Size.X.Offset).toBe(142)
		for _ = 1, 20 do
			key(w.screen, w.engine, "Left")
		end
		t.expect(widths:peek().name).toBe(80)
		w.stop()
	end)

	t.it("collections-203 every collapsed width carries a More disclosure on each row that opens", function()
		local widths = Compose.cell({ a = 150, b = 150, c = 150 })
		local w = stage(function(UI)
			return UI.Table({
				from = {
					{ id = 1, a = "Alpha", b = "Bravo", c = "Charlie one" },
					{ id = 2, a = "Delta", b = "Echo", c = "Charlie two" },
				},
				key = id,
				itemSize = 40,
				widths = widths,
				columns = {
					{ id = "a", label = "A" },
					{ id = "b", label = "B" },
					{ id = "c", label = "C" },
				},
			})
		end)
		local V2 = w.engine.types.Vector2
		local header, body = w.node:FindFirstChild("Header"), w.node:FindFirstChild("Body")
		body.AbsoluteWindowSize = V2.new(460, 200)
		local collapsedWidths, silent, disagreeing = 0, 0, 0
		local openWidth: number? = nil
		for width = 20, 460 do
			body.AbsoluteWindowSize = V2.new(width, 200)
			local hidden = {}
			for _, column in { "a", "b", "c" } do
				if header:FindFirstChild(column).Visible == false then
					table.insert(hidden, column)
				end
			end
			for _, rowKey in { "1", "2" } do
				local rowNode = body:FindFirstChild("Items"):FindFirstChild(rowKey)
				local details = rowNode:FindFirstChild("Details", true)
				if #hidden > 0 and details == nil then
					silent += 1
				end
				if #hidden == 0 and details ~= nil then
					disagreeing += 1
				end
				for _, column in { "a", "b", "c" } do
					if cellRow(rowNode):FindFirstChild(column).Visible ~= header:FindFirstChild(column).Visible then
						disagreeing += 1
					end
				end
			end
			if #hidden > 0 then
				collapsedWidths += 1
				openWidth = openWidth or width
			end
		end
		t.expect(collapsedWidths > 20).toBe(true)
		t.expect(silent).toBe(0)
		t.expect(disagreeing).toBe(0)
		t.expect(header:FindFirstChild("a").Visible).toBe(true)
		body.AbsoluteWindowSize = V2.new(200, 200)
		t.expect(header:FindFirstChild("a").Visible).toBe(true)
		t.expect(header:FindFirstChild("c").Visible).toBe(false)
		local rowNode = body:FindFirstChild("Items"):FindFirstChild("1")
		local details = rowNode:FindFirstChild("Details", true)
		t.expect(details.Size).toBe(w.engine.types.UDim2.new(0, 48, 1, 0))
		details.Activated.fire()
		local expanded = w.screen:FindFirstChild("Expanded", true)
		t.expect(expanded ~= nil).toBe(true)
		t.expect(expanded:FindFirstChild("c", true):FindFirstChild("FullValue", true).Text).toBe("Charlie one")
		w.stop()
	end)

	t.it("collections-207 header and body cells span the same columns in every shape and shipped package", function()
		local packages: { any } = { false }
		for _, name in themePackages.REFERENCE_ORDER do
			if themePackages.NOT_SHIPPABLE[name] == nil then
				local module = (require :: any)("../examples/themes/" .. name)
				local package = module.build(Facet.themes)
				assert(package, `{name} did not build`)
				table.insert(packages, package)
			end
		end
		t.expect(#packages >= 9).toBe(true)
		local shapes = { "viewport", "block", "reorder", "collapsed" }
		local checked = 0
		for _, package in packages do
			for _, shape in shapes do
				local w = stage(function(UI)
					return UI.Table({
						from = records(3),
						key = id,
						itemSize = 40,
						scrolls = if shape == "block" then false else nil,
						reorderable = shape == "reorder",
						onReorder = function() end,
						columns = {
							{ id = "fixed", width = 120, minWidth = 80, maxWidth = 200 },
							{ id = "fill" },
							{ id = "tail", width = 90, priority = 9 },
						},
					})
				end, if package then { theme = package } else nil)
				local body = w.node:FindFirstChild("Body")
				body.AbsoluteWindowSize = w.engine.types.Vector2.new(if shape == "collapsed" then 220 else 500, 200)
				for _, rowKey in { "1", "2", "3" } do
					expectAligned(w.node, rowKey, { "fixed", "fill", "tail" })
					checked += 1
				end
				t.expect(w.node:FindFirstChild("Header"):FindFirstChild("tail").Visible).toBe(shape ~= "collapsed")
				w.stop()
			end
		end
		t.expect(checked).toBe(#packages * #shapes * 3)
	end)

	t.it("inputs-06 a gamepad grab moves a row with the D-pad and drops it with A", function()
		local requests = {}
		local w = stage(function(UI)
			return UI.Table({
				from = records(4),
				key = id,
				itemSize = 40,
				selection = Compose.cell({}),
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local E, V2 = w.engine.types.Enum, w.engine.types.Vector2
		local body = w.node:FindFirstChild("Body")
		body.AbsoluteWindowSize = V2.new(300, 300)
		local handle = body:FindFirstChild("Items"):FindFirstChild("1"):FindFirstChild("Move", true)
		focus(w.gui, handle)
		t.expect(key(w.screen, w.engine, "DPadDown")).toBe("CollectionDown")
		t.expect(w.gui.SelectedObject)
			.toBe(body:FindFirstChild("Items"):FindFirstChild("2"):FindFirstChild("Move", true))
		focus(w.gui, handle)
		handle.Activated.fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }, 1)
		t.expect(handle:FindFirstChild("ReorderIcon").Image).toBe("rbxassetid://108245103349446")
		local selectedDuringGrab = w.gui.SelectedObject
		t.expect(key(w.screen, w.engine, "DPadDown")).toBe("ReorderDown")
		t.expect(w.gui.SelectedObject).toBe(selectedDuringGrab)
		t.expect(#requests).toBe(0)
		t.expect(w.node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(40 + 80)
		t.expect(key(w.screen, w.engine, "ButtonA")).toBe("ReorderDrop")
		t.expect(requests).toEqual({ { keys = { 1 }, slot = 1 } })
		t.expect(w.node:FindFirstChild("DropLine", true)).toBeNil()
		t.expect(key(w.screen, w.engine, "DPadDown") ~= "ReorderDown").toBe(true)
		w.stop()
	end)
end)
