--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local ComposeCore = require("../src/vendor/compose/core")
type Status = ComposeCore.OrderedCollectionStatus

local function setup(options: any?): (any, any, any, any, any)
	local settings: any = options or {}
	local engine: any = engineLib.new(settings.engine)
	if settings.hook then
		settings.hook(engine)
	end
	local runtime: any = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local root = engine.new("ScreenGui")
	local config: any = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui },
		inputParent = root,
		reducedMotion = true,
		theme = settings.theme,
	}
	local UI: any = Facet.controls(runtime, config)
	return engine, runtime, UI, root, gui
end

local function status(): any
	return Compose.cell({
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
	} :: Status)
end

local function records(count: number, prefix: string?): { any }
	local values = {}
	for index = 1, count do
		values[index] = { id = index, label = (prefix or "") .. tostring(index) }
	end
	return values
end

local function key(item: any): any
	return item.id
end

local function mountedKeys(node: any): { number }
	local keys = {}
	local items = node:FindFirstChild("Items")
	if items == nil then
		return keys
	end
	for _, row in items:GetChildren() do
		table.insert(keys, tonumber(row.Name) :: number)
	end
	table.sort(keys)
	return keys
end

local function range(first: number, last: number): { number }
	local values = {}
	for index = first, last do
		table.insert(values, index)
	end
	return values
end

local function rowHost(node: any, name: any): any
	local items = node:FindFirstChild("Items")
	return if items then items:FindFirstChild(tostring(name)) else nil
end

local function find(node: any, name: string): any
	if node.Name == name then
		return node
	end
	for _, child in node:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function window(node: any, engine: any, width: number, height: number)
	node.AbsoluteSize = engine.types.Vector2.new(width, height)
	node.AbsoluteWindowSize = engine.types.Vector2.new(width, height)
end

local function counter(engine: any): any
	local metrics = { writes = 0, creates = 0, destroys = 0 }
	local make = engine.new
	engine.new = function(className)
		local node = make(className)
		metrics.creates += 1
		local meta = getmetatable(node)
		local write = meta.__newindex
		meta.__newindex = function(self, name, value)
			metrics.writes += 1
			write(self, name, value)
		end
		return node
	end
	local destroy = engine.destroy
	engine.destroy = function(node)
		metrics.destroys += 1
		destroy(node)
	end
	return function(action: () -> ()): any
		metrics.writes, metrics.creates, metrics.destroys = 0, 0, 0
		action()
		return table.clone(metrics)
	end
end

local function shape(node: any): string
	local parts = { node.ClassName .. ":" .. node.Name }
	if node:IsA("TextButton") or node:IsA("TextLabel") then
		table.insert(parts, "text=" .. node.Text)
	end
	for _, tag in node:GetTags() do
		table.insert(parts, "tag=" .. tag)
	end
	for _, attribute in { "FacetCollectionRow", "FacetSelected", "Odd" } do
		if node:GetAttribute(attribute) ~= nil then
			table.insert(parts, attribute .. "=" .. tostring(node:GetAttribute(attribute)))
		end
	end
	if node:IsA("GuiObject") then
		table.insert(parts, tostring(node.Position) .. "/" .. tostring(node.Size) .. "/" .. tostring(node.Interactable))
	end
	local children = {}
	for _, child in node:GetChildren() do
		table.insert(children, shape(child))
	end
	table.sort(children)
	return "(" .. table.concat(parts, " ") .. " " .. table.concat(children, " ") .. ")"
end

local function label(UI: any, current: any): any
	return UI.Button "Action" {
		label = function(use)
			return use(current).label
		end,
	}
end

local function gallery(name: string): (any, any, () -> (), any)
	local engine: any = engineLib.new()
	local runtime: any = Facet.Roblox.createRuntime(engine)
	local target, guiService = engine.new("Folder"), engine.new("GuiService")
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		guiService = guiService,
		runService = { Heartbeat = engine.heartbeat },
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = viewport,
				guiService = guiService,
				services = { GuiService = guiService },
				inputParent = target,
				reducedMotion = true,
			} :: any
		),
	}
	local built: any
	local stop, node = runtime.mount(function()
		built = require("../examples/gallery/scenarios/" .. name).build(ctx)
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	return built, node, function()
		stop()
		runtime:dispose()
	end, engine
end

t.describe("native parity weaker virtual", function()
	t.it(
		"apps2-57 variable posts differ in height, never overlap, grow at each text offset and keep the scrolled post",
		function()
			for _, view in { { 320, 640 }, { 640, 320 }, { 1280, 720 } } do
				local built, node, stop, engine = gallery("variable_extents")
				local body = find(node, "Collection")
				window(body, engine, view[1], view[2])
				local report = built.report()
				t.expect(report.status.retained > 0).toBe(true)
				t.expect(report.status.retained < 20).toBe(true)
				local heights, distinct, previous = {}, 0, nil
				for _, index in mountedKeys(body) do
					local row = rowHost(body, index)
					local top, height = row.Position.Y.Offset, row.Size.Y.Offset
					t.expect(height).toBe(report.extents[tostring(index)])
					if heights[height] == nil then
						heights[height] = true
						distinct += 1
					end
					if previous then
						t.expect(top).toBe(previous.Position.Y.Offset + previous.Size.Y.Offset + 8)
					end
					previous = row
				end
				t.expect(distinct >= (if view[2] > 700 then 4 else 3)).toBe(true)
				stop()
			end
			local built, node, stop, engine = gallery("variable_extents")
			local body = find(node, "Collection")
			window(body, engine, 320, 640)
			local previousExtent = 0
			for _, offset in { 0, 4, 10, 14 } do
				find(node, "TextOffset" .. offset).Activated.fire()
				local report = built.report()
				t.expect(report.status.extent > previousExtent).toBe(true)
				t.expect(report.status.retained < 20).toBe(true)
				t.expect(report.extents["2"] > report.extents["1"]).toBe(true)
				previousExtent = report.status.extent
			end
			find(node, "TextOffset0").Activated.fire()
			find(node, "Mode").Activated.fire()
			t.expect(built.report().status.extent).toBe(400 * 84 + 399 * 8)
			for _, index in mountedKeys(body) do
				t.expect(rowHost(body, index).Size.Y.Offset).toBe(84)
			end
			find(node, "Mode").Activated.fire()
			find(node, "Jump").Activated.fire()
			local function topKey(): number?
				local at = body.CanvasPosition.Y
				for _, index in mountedKeys(body) do
					local row = rowHost(body, index)
					if row.Position.Y.Offset <= at and at < row.Position.Y.Offset + row.Size.Y.Offset + 8 then
						return index
					end
				end
				return nil
			end
			local first, anchor = built.report().status.first, topKey()
			local before = body.CanvasPosition.Y
			t.expect(before > 0).toBe(true)
			t.expect(anchor ~= nil).toBe(true)
			find(node, "TextOffset14").Activated.fire()
			t.expect(body.CanvasPosition.Y ~= before).toBe(true)
			t.expect(built.report().status.first).toBe(first)
			t.expect(topKey()).toBe(anchor)
			stop()
		end
	)

	t.it(
		"apps2-141 windows stay bounded at every size, through sweeps and churn, and scrolling adds no owners",
		function()
			local function world(count: number, mode: string?): any
				local engine, runtime, UI, root = setup()
				local source, state = Compose.cell(records(count)), status()
				local rendered, released = 0, 0
				local stop, node = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						mode = mode,
						itemSize = 56,
						status = state,
						render = function(current)
							rendered += 1
							Compose.cleanup(function()
								released += 1
							end)
							return label(UI, current)
						end,
					})
				end, root)
				window(node, engine, 480, 640)
				return {
					engine = engine,
					node = node,
					source = source,
					status = state,
					live = function()
						return rendered - released
					end,
					stop = function()
						stop()
						runtime:dispose()
					end,
				}
			end
			local bound = math.ceil(640 / 56) + 1 + 2 * 2
			local retained = {}
			for _, count in { 200, 2000, 20000 } do
				local w = world(count)
				t.expect(w.status:peek().total).toBe(count)
				t.expect(w.status:peek().retained <= bound).toBe(true)
				t.expect(w.live()).toBe(w.status:peek().retained)
				table.insert(retained, w.status:peek().retained)
				for step = 1, 30 do
					w.node.CanvasPosition = w.engine.types.Vector2.new(0, step * 61)
					t.expect(w.status:peek().retained <= bound).toBe(true)
				end
				w.stop()
			end
			t.expect(retained[2]).toBe(retained[1])
			t.expect(retained[3]).toBe(retained[1])
			local churn = world(800)
			churn.node.CanvasPosition = churn.engine.types.Vector2.new(0, 56 * 300)
			local rows = churn.source:peek()
			local inserted = table.clone(rows)
			for index = 1, 10 do
				table.insert(inserted, 1, { id = 1000 + index, label = "New" })
			end
			churn.source:set(inserted)
			t.expect(churn.status:peek().total).toBe(810)
			t.expect(churn.status:peek().retained <= bound).toBe(true)
			churn.source:set(rows)
			t.expect(churn.status:peek().total).toBe(800)
			t.expect(churn.status:peek().retained <= bound).toBe(true)
			local reordered = table.clone(rows)
			for index = 1, 5 do
				reordered[295 + index], reordered[306 - index] = reordered[306 - index], reordered[295 + index]
			end
			churn.source:set(reordered)
			t.expect(churn.status:peek().retained <= bound).toBe(true)
			t.expect(churn.live()).toBe(churn.status:peek().retained)
			churn.stop()
			local control = world(60, "all")
			t.expect(control.status:peek().retained).toBe(60)
			t.expect(control.status:peek().retained <= bound).toBe(false)
			control.stop()
			local owners = world(600)
			local function size(): number
				local census = owners.engine.census()
				return census.live + census.connections
			end
			local baseline = size()
			local function sweep(): number
				for step = 1, 240 do
					owners.node.CanvasPosition = owners.engine.types.Vector2.new(0, (step * 137) % (600 * 56 - 640))
				end
				owners.node.CanvasPosition = owners.engine.types.Vector2.zero
				return size()
			end
			local once = sweep()
			t.expect(once >= baseline).toBe(true)
			t.expect(sweep()).toBe(once)
			t.expect(sweep()).toBe(once)
			t.expect(owners.live()).toBe(owners.status:peek().retained)
			owners.stop()
		end
	)
	t.it("apps2-231 a virtual grid inside the collections showcase tabs windows on its pane and scrolls", function()
		local built, node, stop, engine = gallery("collections")
		local function button(name: string): any
			for _, candidate in node:GetDescendants() do
				if candidate.Name == name and candidate:IsA("TextButton") then
					return candidate
				end
			end
			return nil
		end
		button("grids").Activated.fire()
		button("vertical").Activated.fire()
		t.expect(built.report().active).toBe("vertical")
		local grid = find(find(node, "virtual_grid"), "Collection")
		t.expect(grid:IsA("ScrollingFrame")).toBe(true)
		t.expect(built.report().example.status.retained).toBe(0)
		window(grid, engine, 1000, 400)
		local tall = built.report().example.status
		t.expect(tall.total).toBe(5000)
		t.expect(tall.retained > 0).toBe(true)
		t.expect(tall.retained < 100).toBe(true)
		window(grid, engine, 1000, 200)
		local short = built.report().example.status
		t.expect(short.retained < tall.retained).toBe(true)
		local before = short.first
		grid.CanvasPosition = engine.types.Vector2.new(0, 1800)
		local after = built.report().example.status
		t.expect(after.first ~= before).toBe(true)
		t.expect(after.retained < 100).toBe(true)
		t.expect(built.report().example.mounted).toBe(after.retained)
		stop()
	end)

	t.it(
		"apps2-243 a single-selection list keeps its selection and never re-renders a mounted row through a live re-sort",
		function()
			local engine, runtime, UI, root = setup()
			local source, selection = Compose.cell(records(20)), Compose.cell({})
			local renders, selections = {}, {}
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 40,
					overscan = 0,
					selection = selection,
					onSelectionChange = function(nextSelection)
						table.insert(selections, nextSelection)
						selection:set(nextSelection)
					end,
					render = function(current, _, rowKey)
						renders[rowKey] = (renders[rowKey] or 0) + 1
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 400)
			local function hit(index: number): any
				return rowHost(node, index):FindFirstChild("RowHit", true)
			end
			hit(3).Activated.fire()
			t.expect(selection:peek()).toEqual({ [3] = true })
			hit(5).Activated.fire()
			t.expect(selection:peek()).toEqual({ [5] = true })
			hit(3).Activated.fire()
			t.expect(#selections).toBe(3)
			local survivors = {}
			for _, index in mountedKeys(node) do
				survivors[index] = true
			end
			for _ = 1, 3 do
				local rotated = table.clone(source:peek())
				table.insert(rotated, 1, table.remove(rotated) :: any)
				source:set(rotated)
				t.expect(source:peek()[1].id ~= 1).toBe(true)
				t.expect(selection:peek()).toEqual({ [3] = true })
				local stayed = {}
				for _, index in mountedKeys(node) do
					stayed[index] = survivors[index]
					t.expect(renders[index]).toBe(1)
					t.expect(hit(index):GetAttribute("FacetSelected")).toBe(index == 3)
				end
				survivors = stayed
			end
			t.expect(survivors[3]).toBe(true)
			local reversed = {}
			for index = #source:peek(), 1, -1 do
				table.insert(reversed, source:peek()[index])
			end
			source:set(reversed)
			t.expect(selection:peek()).toEqual({ [3] = true })
			t.expect(#selections).toBe(3)
			stop()
			runtime:dispose()
		end
	)

	t.it("apps-122 Compose.keyed rows keep their identity and hand handlers the latest item", function()
		local _, runtime, UI, root = setup()
		local items = Compose.cell({ { id = "a", name = "Axe" }, { id = "b", name = "Bow" } })
		local built, equipped = 0, nil
		local stop, node = runtime.mount(function()
			return runtime.constructors.Frame "List" {
				Compose.keyed({
					from = items,
					key = function(item)
						return item.id
					end,
					render = function(item)
						built += 1
						return UI.Button("Row-" .. item:peek().id)({
							label = function(use)
								return use(item).name
							end,
							onActivate = function()
								equipped = item:peek().name
							end,
						})
					end,
				}),
			}
		end, root)
		local row = node:FindFirstChild("Row-a")
		items:set({ { id = "b", name = "Bow" }, { id = "a", name = "Great Axe" }, { id = "c", name = "Club" } })
		t.expect(built).toBe(3)
		t.expect(node:FindFirstChild("Row-a")).toBe(row)
		t.expect(row.Text).toBe("Great Axe")
		row.Activated.fire()
		t.expect(equipped).toBe("Great Axe")
		items:set({ { id = "c", name = "Club" } })
		t.expect(node:FindFirstChild("Row-a")).toBeNil()
		t.expect(row.isDestroyed()).toBe(true)
		t.expect(built).toBe(3)
		stop()
		runtime:dispose()
	end)

	t.it(
		"collections-07 a gap bound to a theme package metric moves placements on a theme swap without a rebuild",
		function()
			local wide = Facet.themes.neutralPackage()
			local narrow = table.clone(wide)
			narrow.metrics = table.clone(wide.metrics)
			narrow.metrics.space = table.clone(wide.metrics.space)
			narrow.metrics.space.xs = wide.metrics.space.xs * 2
			local theme = Compose.cell(wide)
			local engine, runtime, UI, root = setup({ theme = theme })
			local controls, state, rendered = {}, status(), 0
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = records(8),
					key = key,
					itemSize = 40,
					gap = function(use)
						return use(theme).metrics.space.xs
					end,
					status = state,
					controls = controls,
					render = function(current)
						rendered += 1
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 600)
			local xs = wide.metrics.space.xs
			t.expect(controls.placementOf(3).offset).toBe(2 * (40 + xs))
			local before, second, count = state:peek().extent, rowHost(node, 2), rendered
			t.expect(before).toBe(8 * 40 + 7 * xs)
			theme:set(narrow)
			t.expect(state:peek().extent - before).toBe(7 * xs)
			t.expect(controls.placementOf(3).offset).toBe(2 * (40 + 2 * xs))
			t.expect(rowHost(node, 2)).toBe(second)
			t.expect(second.Position.Y.Offset).toBe(40 + 2 * xs)
			t.expect(node.CanvasSize.Y.Offset).toBe(8 * 40 + 14 * xs)
			t.expect(rendered).toBe(count)
			stop()
			runtime:dispose()
		end
	)

	t.it(
		"collections-09 a list without selection options declares no row hit and single selection survives a re-sort",
		function()
			local engine, runtime, UI, root = setup()
			local activated = 0
			local stopPlain, plain = runtime.mount(function()
				return UI.VirtualList({
					from = records(5),
					key = key,
					itemSize = 40,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(plain, engine, 200, 200)
			for _, index in mountedKeys(plain) do
				local content = rowHost(plain, index):FindFirstChild("Content")
				t.expect(content:FindFirstChild("RowHit")).toBeNil()
				t.expect(content:GetAttribute("FacetSelected")).toBeNil()
				rowHost(plain, index):FindFirstChild("Action", true).Activated.fire()
			end
			stopPlain()
			local stopActivate, activate = runtime.mount(function()
				return UI.VirtualList({
					from = records(5),
					key = key,
					itemSize = 40,
					onActivate = function()
						activated += 1
					end,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(activate, engine, 200, 200)
			local rowHit = rowHost(activate, 2):FindFirstChild("RowHit", true)
			rowHit.Activated.fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 }, 1)
			t.expect(activated).toBe(1)
			t.expect(rowHit:GetAttribute("FacetSelected")).toBe(false)
			stopActivate()
			local source, selection = Compose.cell(records(5)), Compose.cell({})
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 40,
					selection = selection,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 200)
			local function hit(index: number): any
				return rowHost(node, index):FindFirstChild("RowHit", true)
			end
			hit(2).Activated.fire()
			hit(4).Activated.fire()
			t.expect(selection:peek()).toEqual({ [4] = true })
			local reversed = table.clone(source:peek())
			for index = 1, 2 do
				reversed[index], reversed[6 - index] = reversed[6 - index], reversed[index]
			end
			source:set(reversed)
			t.expect(selection:peek()).toEqual({ [4] = true })
			for index = 1, 5 do
				t.expect(hit(index):GetAttribute("FacetSelected")).toBe(index == 4)
			end
			selection:set({})
			for index = 1, 5 do
				t.expect(hit(index):GetAttribute("FacetSelected")).toBe(false)
			end
			stop()
			runtime:dispose()
		end
	)

	t.it("collections-19 a readable itemSize and a resized viewport re-window in place", function()
		local engine, runtime, UI, root = setup()
		local itemSize, state, controls, rendered = Compose.cell(40), status(), {}, 0
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(60),
				key = key,
				itemSize = itemSize,
				measured = { [3] = 100 },
				overscan = 0,
				status = state,
				controls = controls,
				render = function(current)
					rendered += 1
					return label(UI, current)
				end,
			})
		end, root)
		window(node, engine, 200, 400)
		t.expect(mountedKeys(node)).toEqual(range(1, 9))
		t.expect(controls.placementOf(4).offset).toBe(180)
		t.expect(state:peek().extent).toBe(59 * 40 + 100)
		local first = rowHost(node, 1)
		itemSize:set(80)
		t.expect(mountedKeys(node)).toEqual(range(1, 5))
		t.expect(controls.placementOf(4).offset).toBe(260)
		t.expect(rowHost(node, 3).Size.Y.Offset).toBe(100)
		t.expect(rowHost(node, 2).Size.Y.Offset).toBe(80)
		t.expect(state:peek().extent).toBe(59 * 80 + 100)
		t.expect(node.CanvasSize.Y.Offset).toBe(59 * 80 + 100)
		t.expect(rowHost(node, 1)).toBe(first)
		local count = rendered
		window(node, engine, 200, 200)
		t.expect(mountedKeys(node)).toEqual(range(1, 3))
		t.expect(rowHost(node, 1)).toBe(first)
		window(node, engine, 200, 800)
		t.expect(mountedKeys(node)).toEqual(range(1, 10))
		t.expect(rowHost(node, 1)).toBe(first)
		t.expect(rendered).toBe(count + 7)
		stop()
		runtime:dispose()
	end)

	t.it(
		"collections-20 a list that does not follow never moves on growth and a follower rejoins inside its threshold",
		function()
			local engine, runtime, UI, root = setup()
			local plainRows = Compose.cell(records(40))
			local stopPlain, plain = runtime.mount(function()
				return UI.VirtualList({
					from = plainRows,
					key = key,
					itemSize = 40,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(plain, engine, 200, 400)
			t.expect(plain.CanvasPosition.Y).toBe(0)
			plainRows:set(records(43))
			t.expect(plain.CanvasPosition.Y).toBe(0)
			plain.CanvasPosition = engine.types.Vector2.new(0, 43 * 40 - 400)
			plainRows:set(records(46))
			t.expect(plain.CanvasPosition.Y).toBe(43 * 40 - 400)
			stopPlain()
			local source, state = Compose.cell(records(40)), status()
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 40,
					follow = "end",
					followThreshold = 8,
					status = state,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 400)
			t.expect(node.CanvasPosition.Y).toBe(40 * 40 - 400)
			source:set(records(43))
			t.expect(node.CanvasPosition.Y).toBe(43 * 40 - 400)
			node.CanvasPosition = engine.types.Vector2.new(0, 480)
			source:set(records(44))
			t.expect(node.CanvasPosition.Y).toBe(480)
			t.expect(state:peek().following).toBe(false)
			node.CanvasPosition = engine.types.Vector2.new(0, 44 * 40 - 400 - 6)
			source:set(records(45))
			t.expect(node.CanvasPosition.Y).toBe(45 * 40 - 400)
			t.expect(state:peek().following).toBe(true)
			stop()
			runtime:dispose()
		end
	)
	t.it(
		"collections-208 a virtual table mounts the viewport plus overscan below, spends the gap once and sizes its canvas",
		function()
			local function mountTable(count: number, gap: number?): any
				local delta: any
				local engine, runtime, UI, root = setup({
					hook = function(created)
						delta = counter(created)
					end,
				})
				local builds = 0
				local stop, node = runtime.mount(function()
					return UI.Table({
						from = records(count),
						key = key,
						itemSize = 40,
						gap = gap,
						overscan = 2,
						header = false,
						columns = {
							{
								id = "label",
								label = "Label",
								width = 100,
								render = function(current)
									builds += 1
									return label(UI, current)
								end,
							},
						},
					})
				end, root)
				local body = node:FindFirstChild("Body")
				window(body, engine, 200, 200)
				return {
					engine = engine,
					body = body,
					delta = delta,
					builds = function()
						return builds
					end,
					stop = function()
						stop()
						runtime:dispose()
					end,
				}
			end
			local w = mountTable(400)
			t.expect(mountedKeys(w.body)).toEqual(range(1, 7))
			t.expect(rowHost(w.body, 8)).toBeNil()
			t.expect(w.body.CanvasSize.Y.Offset).toBe(400 * 40)
			w.body.CanvasPosition = w.engine.types.Vector2.new(0, 10)
			t.expect(w.delta(function()
				w.body.CanvasPosition = w.engine.types.Vector2.new(0, 20)
			end)).toEqual({ writes = 1, creates = 0, destroys = 0 })
			w.body.CanvasPosition = w.engine.types.Vector2.new(0, 100 * 40)
			t.expect(rowHost(w.body, 1)).toBeNil()
			t.expect(mountedKeys(w.body)).toEqual(range(99, 107))
			w.stop()
			local gapped = mountTable(200, 6)
			t.expect(gapped.body.CanvasSize.Y.Offset).toBe(200 * 40 + 199 * 6)
			for _, index in mountedKeys(gapped.body) do
				t.expect(rowHost(gapped.body, index).Position.Y.Offset).toBe((index - 1) * 46)
				t.expect(rowHost(gapped.body, index).Size.Y.Offset).toBe(40)
			end
			gapped.stop()
			local large, small = mountTable(5000), mountTable(50)
			t.expect(large.builds()).toBe(7)
			t.expect(large.builds()).toBe(small.builds())
			large.stop()
			small.stop()
		end
	)

	t.it(
		"collections-222 a grid windows whole lines, a tall line alone, and a short last line keeps its lanes",
		function()
			local engine, runtime, UI, root = setup()
			local state = status()
			local stop, node = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(400),
					key = key,
					columns = 4,
					itemSize = 40,
					gap = 6,
					crossGap = 4,
					overscan = 0,
					status = state,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 320, 200)
			t.expect(state:peek().extent).toBe(100 * 40 + 99 * 6)
			t.expect(node.CanvasSize.Y.Offset).toBe(100 * 40 + 99 * 6 + 2 * 3)
			local padding = node:FindFirstChild("Items"):FindFirstChildWhichIsA("UIPadding")
			t.expect(padding.PaddingTop.Offset).toBe(3)
			t.expect(padding.PaddingLeft.Offset).toBe(2)
			t.expect(padding.PaddingRight.Offset).toBe(2)
			node.CanvasPosition = engine.types.Vector2.new(0, 460 + 3)
			t.expect(state:peek().firstRow).toBe(11)
			t.expect(state:peek().lastRow).toBe(15)
			t.expect(mountedKeys(node)).toEqual(range(41, 60))
			t.expect(rowHost(node, 41).Position.Y.Offset).toBe(460)
			stop()
			local tall = {}
			for index = 5, 8 do
				tall[index] = 249
			end
			local stopTall, ragged = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(80),
					key = key,
					columns = 4,
					itemSize = 40,
					measured = tall,
					overscan = 0,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(ragged, engine, 320, 120)
			ragged.CanvasPosition = engine.types.Vector2.new(0, 60)
			t.expect(mountedKeys(ragged)).toEqual(range(5, 8))
			t.expect(rowHost(ragged, 5).Size.Y.Offset).toBe(249)
			stopTall()
			local shortState = status()
			local stopShort, short = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(9),
					key = key,
					columns = 4,
					itemSize = 40,
					gap = 6,
					crossGap = 4,
					status = shortState,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(short, engine, 320, 400)
			t.expect(shortState:peek().rowCount).toBe(3)
			t.expect(shortState:peek().extent).toBe(3 * 40 + 2 * 6)
			t.expect(mountedKeys(short)).toEqual(range(1, 9))
			local ninth = rowHost(short, 9)
			t.expect(ninth.Size.X.Offset).toBe(76)
			t.expect(ninth.Position.X.Offset).toBe(0)
			t.expect(rowHost(short, 2).Position.X.Offset).toBe(80)
			t.expect(rowHost(short, 4).Position.X.Offset).toBe(240)
			stopShort()
			runtime:dispose()
		end
	)

	t.it(
		"collections-223 a grid builds exactly the windowed cells and the same count for 100 and 10000 items",
		function()
			local function buildsFor(count: number, jump: number?): (number, number)
				local engine, runtime, UI, root = setup()
				local built = 0
				local stop, node = runtime.mount(function()
					return UI.VirtualGrid({
						from = records(count),
						key = key,
						columns = 4,
						itemSize = 40,
						overscan = 2,
						render = function(current)
							built += 1
							return label(UI, current)
						end,
					})
				end, root)
				window(node, engine, 320, 200)
				local atTop = built
				if jump then
					node.CanvasPosition = engine.types.Vector2.new(0, jump)
					t.expect(#mountedKeys(node)).toBe(36)
				end
				stop()
				runtime:dispose()
				return atTop, built - atTop
			end
			local top, jumped = buildsFor(10000, 24000)
			t.expect(top).toBe(28)
			t.expect(jumped).toBe(36)
			t.expect((buildsFor(100))).toBe(28)
		end
	)

	t.it(
		"collections-240 a horizontal grid sizes its x canvas, stacks lines rightward and splits lanes by the cross extent",
		function()
			local engine, runtime, UI, root = setup()
			local state, built = status(), 0
			local stop, node = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(1000),
					key = key,
					direction = "horizontal",
					columns = 4,
					itemSize = 120,
					gap = 6,
					overscan = 0,
					status = state,
					render = function(current)
						built += 1
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 480, 318 + 2 * 3)
			t.expect(node.ScrollingDirection).toBe(engine.types.Enum.ScrollingDirection.X)
			t.expect(node.CanvasSize.X.Offset).toBe(250 * 120 + 249 * 6 + 2 * 3)
			t.expect(node.CanvasSize.Y.Offset).toBe(0)
			for _, probe in { { 1, 1, 1 }, { 7, 2, 3 }, { 12, 3, 4 } } do
				local cell = rowHost(node, probe[1])
				t.expect(cell.Position.X.Offset).toBe((probe[2] - 1) * 126)
				t.expect(cell.Position.Y.Offset).toBe((probe[3] - 1) * 81)
				t.expect(cell.Size.X.Offset).toBe(120)
				t.expect(cell.Size.Y.Offset).toBe(75)
			end
			t.expect(mountedKeys(node)).toEqual(range(1, 16))
			t.expect(built).toBe(16)
			node.CanvasPosition = engine.types.Vector2.new(126 * 100 + 3, 999)
			t.expect(state:peek().firstRow).toBe(101)
			t.expect(mountedKeys(node)).toEqual(range(401, 416))
			t.expect(built).toBe(32)
			stop()
			local stopShort, short = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(18),
					key = key,
					direction = "horizontal",
					columns = 4,
					itemSize = 120,
					gap = 6,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(short, engine, 1200, 318 + 2 * 3)
			t.expect(rowHost(short, 17).Size.Y.Offset).toBe(75)
			t.expect(rowHost(short, 18).Position.Y.Offset).toBe(81)
			t.expect(short.CanvasSize.X.Offset).toBe(5 * 120 + 4 * 6 + 2 * 3)
			stopShort()
			runtime:dispose()
		end
	)

	t.it(
		"collections-249 a horizontal list sizes its x canvas, windows on the pitch and keeps focus visible along x",
		function()
			local engine, runtime, UI, root = setup()
			local source, focus, state = Compose.cell(records(200)), {}, status()
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					direction = "horizontal",
					itemSize = 120,
					gap = 6,
					overscan = 0,
					focus = focus,
					status = state,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 252, 80)
			t.expect(node.CanvasSize.X.Offset).toBe(200 * 120 + 199 * 6)
			t.expect(node.CanvasSize.Y.Offset).toBe(0)
			t.expect(mountedKeys(node)).toEqual({ 1, 2 })
			local first, second = rowHost(node, 1), rowHost(node, 2)
			t.expect(first.Size.X.Offset).toBe(120)
			t.expect(first.Size.Y.Offset).toBe(80)
			t.expect(second.Position.X.Offset - (first.Position.X.Offset + first.Size.X.Offset)).toBe(6)
			t.expect(second.Position.Y.Offset).toBe(0)
			node.CanvasPosition = engine.types.Vector2.new(10 * 126, 999)
			t.expect(mountedKeys(node)).toEqual({ 11, 12 })
			focus.focus(20)
			t.expect(node.CanvasPosition.X).toBe(19 * 126 + 120 - 252)
			focus.focus(1)
			t.expect(node.CanvasPosition.X).toBe(0)
			source:set(records(1000))
			t.expect(node.CanvasSize.X.Offset).toBe(1000 * 120 + 999 * 6)
			node.CanvasPosition = engine.types.Vector2.new(126 * 500, 0)
			t.expect(state:peek().retained).toBe(2)
			t.expect(mountedKeys(node)).toEqual({ 501, 502 })
			stop()
			runtime:dispose()
		end
	)

	t.it("collections-258 a list that declares no direction is vertical end to end", function()
		local engine, runtime, UI, root, gui = setup()
		local focus = {}
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(100),
				key = key,
				itemSize = 40,
				focus = focus,
				render = function(current)
					return label(UI, current)
				end,
			})
		end, root)
		window(node, engine, 200, 400)
		t.expect(node.ScrollingDirection).toBe(engine.types.Enum.ScrollingDirection.Y)
		t.expect(node.CanvasSize.Y.Offset).toBe(100 * 40)
		t.expect(node.CanvasSize.X.Offset).toBe(0)
		t.expect(rowHost(node, 1).Position.Y.Offset).toBe(0)
		t.expect(rowHost(node, 3).Position.Y.Offset).toBe(80)
		t.expect(rowHost(node, 3).Position.X.Offset).toBe(0)
		t.expect(rowHost(node, 3).Size.X.Offset).toBe(200)
		focus.focus(1)
		t.expect(gui.SelectedObject.Text).toBe("1")
		local function press(name: string)
			root:FindFirstChild("FacetCollection" .. name):FindFirstChild("Collection" .. name).Pressed.fire()
		end
		press("Down")
		t.expect(focus.current:peek()).toBe(2)
		press("Right")
		t.expect(focus.current:peek()).toBe(2)
		for _ = 1, 12 do
			press("Down")
		end
		t.expect(focus.current:peek()).toBe(14)
		t.expect(node.CanvasPosition.Y).toBe(14 * 40 - 400)
		t.expect(node.CanvasPosition.X).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("collections-274 a horizontal measured list sizes each item from its native width and shrinks back", function()
		local engine, runtime, UI, root = setup()
		local state = status()
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(3),
				key = key,
				direction = "horizontal",
				itemSize = 40,
				measure = true,
				status = state,
				render = function()
					return runtime.constructors.Frame "Measured" {
						AutomaticSize = engine.types.Enum.AutomaticSize.X,
						Size = engine.types.UDim2.new(0, 0, 1, 0),
					}
				end,
			})
		end, root)
		window(node, engine, 600, 80)
		for index = 1, 3 do
			rowHost(node, index):FindFirstChild("Measured", true).AbsoluteSize = engine.types.Vector2.new(110, 80)
		end
		t.expect(state:peek().extent).toBe(3 * 110)
		t.expect(node.CanvasSize.X.Offset).toBe(3 * 110)
		t.expect(rowHost(node, 1).Size.X.Offset).toBe(110)
		t.expect(rowHost(node, 2).Position.X.Offset).toBe(110)
		t.expect(rowHost(node, 1):FindFirstChild("Measured", true).Size.X.Offset).toBe(0)
		rowHost(node, 1):FindFirstChild("Measured", true).AbsoluteSize = engine.types.Vector2.new(60, 80)
		t.expect(state:peek().extent).toBe(60 + 2 * 110)
		t.expect(rowHost(node, 2).Position.X.Offset).toBe(60)
		stop()
		runtime:dispose()
	end)

	t.it(
		"collections-296 a gap stays out of the row for keep-visible, drop hit tests and the bounded window",
		function()
			local engine, runtime, UI, root = setup()
			local focus, requests = {}, {}
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = records(100),
					key = key,
					itemSize = 56,
					gap = 6,
					focus = focus,
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(requests, { keys = keys, slot = slot })
					end,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 600)
			focus.focus(20)
			t.expect(node.CanvasPosition.Y).toBe(19 * 62 + 56 - 600)
			focus.focus(1)
			t.expect(node.CanvasPosition.Y).toBe(0)
			local detector = rowHost(node, 1):FindFirstChildWhichIsA("UIDragDetector", true)
			detector.DragStart.fire(engine.types.Vector2.new(10, 10))
			detector.DragContinue.fire(engine.types.Vector2.new(10, 3 * 62 + 56 + 3))
			t.expect(node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(4 * 62)
			detector.DragContinue.fire(engine.types.Vector2.new(10, 5 * 62 + 20))
			t.expect(node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(5 * 62)
			detector.DragContinue.fire(engine.types.Vector2.new(10, 5 * 62 + 40))
			t.expect(node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(6 * 62)
			detector.DragContinue.fire(engine.types.Vector2.new(10, 3 * 62 + 56 + 3))
			detector.DragEnd.fire()
			t.expect(requests).toEqual({ { keys = { 1 }, slot = 3 } })
			stop()
			local state = status()
			local stopBounded, bounded = runtime.mount(function()
				return UI.VirtualList({
					from = records(1000),
					key = key,
					itemSize = 56,
					gap = 6,
					status = state,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(bounded, engine, 200, 620)
			t.expect(state:peek().retained).toBe(12)
			bounded.CanvasPosition = engine.types.Vector2.new(0, 62 * 500)
			t.expect(state:peek().retained).toBe(14)
			t.expect(mountedKeys(bounded)).toEqual(range(499, 512))
			stopBounded()
			runtime:dispose()
		end
	)

	t.it(
		"collections-299 ragged rows get their own boxes at running offsets, a full canvas and own-extent keep-visible",
		function()
			local engine, runtime, UI, root = setup()
			local ragged = { 84, 249, 84, 120 }
			local extents = {}
			for index = 1, 8 do
				extents[index] = ragged[(index - 1) % 4 + 1]
			end
			local focus, state = {}, status()
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = records(8),
					key = key,
					itemSize = 40,
					measured = extents,
					gap = 6,
					focus = focus,
					status = state,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 2000)
			local total = 2 * (84 + 249 + 84 + 120) + 7 * 6
			t.expect(state:peek().extent).toBe(total)
			t.expect(node.CanvasSize.Y.Offset).toBe(total)
			local offset = 0
			for index = 1, 8 do
				local row = rowHost(node, index)
				t.expect(row.Position.Y.Offset).toBe(offset)
				t.expect(row.Size.Y.Offset).toBe(extents[index])
				offset += extents[index] + 6
			end
			stop()
			local stopPlain, plain = runtime.mount(function()
				return UI.VirtualList({
					from = records(8),
					key = key,
					itemSize = 40,
					measured = extents,
					focus = focus,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(plain, engine, 200, 300)
			focus.focus(6)
			t.expect(plain.CanvasPosition.Y).toBe(621 + 249 - 300)
			focus.focus(1)
			t.expect(plain.CanvasPosition.Y).toBe(0)
			stopPlain()
			runtime:dispose()
		end
	)

	t.it(
		"collections-300 a viewport inside one tall row windows that row alone and ragged windows stay bounded",
		function()
			local engine, runtime, UI, root = setup()
			local ragged = { 84, 249, 84, 120 }
			local function extents(count: number): { [number]: number }
				local values = {}
				for index = 1, count do
					values[index] = ragged[(index - 1) % 4 + 1]
				end
				return values
			end
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = records(40),
					key = key,
					itemSize = 40,
					measured = extents(40),
					overscan = 0,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 200, 120)
			node.CanvasPosition = engine.types.Vector2.new(0, 100)
			t.expect(mountedKeys(node)).toEqual({ 2 })
			stop()
			local built, state = 0, status()
			local stopLarge, large = runtime.mount(function()
				return UI.VirtualList({
					from = records(10000),
					key = key,
					itemSize = 40,
					measured = extents(10000),
					status = state,
					render = function(current)
						built += 1
						return label(UI, current)
					end,
				})
			end, root)
			window(large, engine, 200, 498)
			t.expect(built < 30).toBe(true)
			local atTop = built
			large.CanvasPosition = engine.types.Vector2.new(0, 300000)
			t.expect(built - atTop < 30).toBe(true)
			t.expect(state:peek().retained < 20).toBe(true)
			t.expect(state:peek().first > 1).toBe(true)
			stopLarge()
			runtime:dispose()
		end
	)
	t.it(
		"collections-305 same-window scrolls and off-window edits write nothing, re-entry is fresh and async loads cancel",
		function()
			local delta: any
			local engine, runtime, UI, root = setup({
				hook = function(created)
					delta = counter(created)
				end,
			})
			local source, state = Compose.cell(records(100)), status()
			local rendered, loads, cancels, resolvers = 0, 0, 0, {}
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 40,
					status = state,
					render = function(current, _, rowKey)
						rendered += 1
						local opened = Compose.cell(false)
						return runtime.constructors.Frame "Row" {
							Size = engine.types.UDim2.fromScale(1, 1),
							label(UI, current),
							UI.Toggle "Open" { value = opened, label = "Open" },
							UI.AsyncImage({
								image = "rbxassetid://" .. tostring(rowKey),
								loader = function(_, resolve)
									loads += 1
									resolvers[rowKey] = resolve
									return function()
										cancels += 1
									end
								end,
							}),
						}
					end,
				})
			end, root)
			window(node, engine, 200, 400)
			node.CanvasPosition = engine.types.Vector2.new(0, 10)
			local survivor = rowHost(node, 12)
			local sameWindow = delta(function()
				node.CanvasPosition = engine.types.Vector2.new(0, 20)
			end)
			t.expect(sameWindow).toEqual({ writes = 1, creates = 0, destroys = 0 })
			local edited = table.clone(source:peek())
			edited[50] = { id = 50, label = "Edited off window" }
			local offWindow = delta(function()
				source:set(edited)
			end)
			t.expect(offWindow).toEqual({ writes = 0, creates = 0, destroys = 0 })
			local before = rendered
			node.CanvasPosition = engine.types.Vector2.new(0, 100)
			t.expect(rowHost(node, 12)).toBe(survivor)
			t.expect(rendered - before).toBe(2)
			node.CanvasPosition = engine.types.Vector2.zero
			local content = rowHost(node, 1):FindFirstChild("Content")
			local opening = shape(content)
			content:FindFirstChild("Open", true).Activated.fire()
			t.expect(shape(content) ~= opening).toBe(true)
			t.expect(loads - cancels).toBe(state:peek().retained)
			node.CanvasPosition = engine.types.Vector2.new(0, 2000)
			t.expect(rowHost(node, 1)).toBeNil()
			t.expect(content.isDestroyed()).toBe(true)
			t.expect(cancels >= 10).toBe(true)
			local late = delta(function()
				resolvers[1]("rbxassetid://late")
			end)
			t.expect(late.writes).toBe(0)
			node.CanvasPosition = engine.types.Vector2.zero
			local fresh = rowHost(node, 1):FindFirstChild("Content")
			t.expect(fresh ~= content).toBe(true)
			t.expect(shape(fresh)).toBe(opening)
			stop()
			t.expect(cancels).toBe(loads)
			runtime:dispose()
			local storm = engineLib.new()
			local stormRuntime: any = Facet.Roblox.createRuntime(storm)
			local stormUI: any = Facet.controls(stormRuntime, { types = storm.types })
			local target = storm.new("Folder")
			local baseline = storm.census()
			local stopStorm, list = stormRuntime.mount(function()
				return stormUI.VirtualList({
					from = records(300),
					key = key,
					itemSize = 40,
					render = function(current)
						return label(stormUI, current)
					end,
				})
			end, target)
			window(list, storm, 200, 400)
			for step = 1, 60 do
				list.CanvasPosition = storm.types.Vector2.new(0, (step * 137) % (300 * 40 - 400))
			end
			stopStorm()
			stormRuntime.dispose()
			local after = storm.census()
			t.expect(after.live).toBe(baseline.live)
			t.expect(after.connections).toBe(baseline.connections)
		end
	)

	t.it(
		"mech1-72 measured feeds restore their anchor across widths and offsets, and grids keep cells and anchor on reflow",
		function()
			for _, width in { 320, 1280 } do
				for _, offset in { 220, 660, 1320 } do
					local engine, runtime, UI, root = setup()
					local height = if width < 400 then 140 else 100
					local function measureMounted(node: any)
						local changed = true
						while changed do
							changed = false
							for _, index in mountedKeys(node) do
								local row = rowHost(node, index)
								local content = if row then row:FindFirstChild("Message", true) else nil
								if content and content.AbsoluteSize.Y ~= height then
									content.AbsoluteSize = engine.types.Vector2.new(width, height)
									changed = true
								end
							end
						end
					end
					local function feed(position: any, known: any): (() -> (), any)
						local stop, node = runtime.mount(function()
							return UI.VirtualList({
								from = records(24, "Message "),
								key = key,
								itemSize = 100,
								gap = 16,
								measure = true,
								measured = known,
								CanvasPosition = position,
								render = function(current)
									return runtime.constructors.Frame "Message" {
										AutomaticSize = engine.types.Enum.AutomaticSize.Y,
										Size = engine.types.UDim2.fromScale(1, 0),
										label(UI, current),
									}
								end,
							})
						end, root)
						window(node, engine, width, 573)
						measureMounted(node)
						return stop, node
					end
					local function topKey(node: any): number?
						local at = node.CanvasPosition.Y
						for _, index in mountedKeys(node) do
							local row = rowHost(node, index)
							if row.Position.Y.Offset <= at and at < row.Position.Y.Offset + row.Size.Y.Offset + 16 then
								return index
							end
						end
						return nil
					end
					local stop, node = feed(nil, nil)
					for step = 100, offset, 100 do
						node.CanvasPosition = engine.types.Vector2.new(0, step)
						measureMounted(node)
					end
					node.CanvasPosition = engine.types.Vector2.new(0, offset)
					measureMounted(node)
					local saved, anchor = node.CanvasPosition.Y, topKey(node)
					t.expect(saved > 0).toBe(true)
					t.expect(anchor ~= nil).toBe(true)
					stop()
					local known = {}
					for index = 1, 24 do
						known[index] = height
					end
					local stopKnown, restored = feed(engine.types.Vector2.new(0, saved), known)
					t.expect(restored.CanvasPosition.Y).toBe(saved)
					t.expect(topKey(restored)).toBe(anchor)
					stopKnown()
					runtime:dispose()
				end
			end
			local engine, runtime, UI, root = setup()
			local source, measured, state = Compose.cell(records(40)), Compose.cell({}), status()
			local rendered, released = 0, 0
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 48,
					measured = measured,
					follow = "end",
					followThreshold = 8,
					status = state,
					render = function(current)
						rendered += 1
						Compose.cleanup(function()
							released += 1
						end)
						return label(UI, current)
					end,
				})
			end, root)
			window(node, engine, 400, 200)
			t.expect(node.CanvasPosition.Y).toBe(1720)
			source:set(records(43))
			t.expect(node.CanvasPosition.Y).toBe(1864)
			measured:set({ [43] = 96 })
			t.expect(node.CanvasPosition.Y).toBe(1912)
			node.CanvasPosition = engine.types.Vector2.new(0, 480)
			source:set(records(44))
			t.expect(node.CanvasPosition.Y).toBe(480)
			measured:set({ [1] = 96, [43] = 96 })
			t.expect(node.CanvasPosition.Y).toBe(528)
			t.expect(rendered - released < 12).toBe(true)
			stop()
			t.expect(released).toBe(rendered)
			local columns, gridState, controls = Compose.cell(3), status(), {}
			local stopGrid, grid = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(1000),
					key = key,
					columns = columns,
					itemSize = 40,
					overscan = 0,
					status = gridState,
					controls = controls,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			window(grid, engine, 600, 300)
			grid.CanvasPosition = engine.types.Vector2.new(0, 640)
			local anchorKey = (16 * 3) + 1
			local anchor = rowHost(grid, anchorKey)
			t.expect(anchor.Position.Y.Offset).toBe(640)
			columns:set(2)
			t.expect(rowHost(grid, anchorKey)).toBe(anchor)
			t.expect(grid.CanvasPosition.Y).toBe(controls.placementOf(anchorKey).offset)
			t.expect(anchor.Position.Y.Offset).toBe(24 * 40)
			t.expect(anchor.Size.X.Offset).toBe(300)
			stopGrid()
			runtime:dispose()
		end
	)

	t.it(
		"mech1-96 recipe columns follow measured width across a sweep and container bands follow each panel width",
		function()
			local engine, runtime, UI, root = setup()
			local frame
			local controls, rendered = {}, 0
			local stop = runtime.mount(function()
				frame = runtime.constructors.Frame({ Size = engine.types.UDim2.fromScale(1, 1) })
				local bounds = Compose.cell(frame.AbsoluteSize)
				local connection = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					bounds:set(frame.AbsoluteSize)
				end)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				local stopGrid = runtime.mount(function()
					return UI.VirtualGrid({
						Name = "Cards",
						from = records(40),
						key = key,
						columns = function(use)
							return math.max(1, math.floor(use(bounds).X / 240))
						end,
						itemSize = 180,
						controls = controls,
						render = function(current)
							rendered += 1
							return label(UI, current)
						end,
						Size = engine.types.UDim2.fromScale(1, 1),
					})
				end, frame)
				Compose.cleanup(stopGrid)
				return frame
			end, root)
			local grid = frame:FindFirstChild("Cards")
			local first
			for _, case in { { 0, 1 }, { 239, 1 }, { 240, 1 }, { 480, 2 }, { 1000, 4 }, { 1440, 6 }, { 480, 2 } } do
				local width = math.max(case[1], 1)
				frame.AbsoluteSize = engine.types.Vector2.new(case[1], 720)
				window(grid, engine, width, 720)
				t.expect(controls.placementOf(case[2] + 1).row).toBe(2)
				t.expect(controls.placementOf(case[2]).row).toBe(1)
				t.expect(controls.placementOf(2).crossSize).toBe(width / case[2])
				first = first or rowHost(grid, 1)
				t.expect(rowHost(grid, 1)).toBe(first)
			end
			stop()
			runtime:dispose()
			local built, node, close, galleryEngine = gallery("container_grid")
			local sidebar = find(node, "Sidebar")
			find(node, "GuidesToggle").Activated.fire()
			for _, case in
				{ { 320, 3, 1 }, { 599, 3, 1 }, { 600, 6, 2 }, { 959, 6, 2 }, { 960, 12, 3 }, { 1280, 12, 3 } }
			do
				sidebar.AbsoluteSize = galleryEngine.types.Vector2.new(case[1], 300)
				local facts = built.report().Sidebar
				t.expect(facts.columns).toBe(case[2])
				t.expect(facts.band).toBe(case[3])
				t.expect(facts.lane).toBe((case[1] - 32 - (case[2] - 1) * 8) / case[2])
				local visible = 0
				for index = 1, 12 do
					if find(sidebar, "Lane" .. index).Visible then
						visible += 1
					end
				end
				t.expect(visible).toBe(case[2])
				t.expect(find(sidebar, "Heading").Text)
					.toBe(string.format("Sidebar · %d px · %d columns", case[1], case[2]))
			end
			find(node, "GuidesToggle").Activated.fire()
			for index = 1, 12 do
				t.expect(find(sidebar, "Lane" .. index).Visible).toBe(false)
			end
			local media = find(sidebar, "Media")
			find(node, "Replays").Activated.fire()
			t.expect(media.Visible).toBe(false)
			t.expect(find(sidebar, "Standings").Visible).toBe(true)
			find(node, "Replays").Activated.fire()
			t.expect(find(sidebar, "Media")).toBe(media)
			t.expect(media.Visible).toBe(true)
			close()
		end
	)
	t.it(
		"mech2-30 pooled rows are indistinguishable from unpooled rows at every scroll step and the pool stays bounded",
		function()
			local function world(maxRetained: number): any
				local engine, runtime, UI, root = setup()
				local hosts, state = {}, status()
				local stop, node = runtime.mount(function()
					return UI.VirtualList({
						from = records(300),
						key = key,
						itemSize = 40,
						gap = 4,
						maxRetained = maxRetained,
						status = state,
						render = function(current, _, rowKey)
							if rowKey % 3 == 0 then
								return runtime.constructors.Frame "Wide" {
									Size = engine.types.UDim2.fromScale(1, 1),
									label(UI, current),
									runtime.constructors.UIStroke({ Thickness = 2 }),
								}
							end
							return label(UI, current)
						end,
					})
				end, root)
				window(node, engine, 200, 400)
				local function snapshot(): string
					local rows = {}
					for _, index in mountedKeys(node) do
						local row = rowHost(node, index)
						hosts[row] = true
						table.insert(rows, shape(row))
					end
					return table.concat(rows, "\n")
				end
				return {
					engine = engine,
					node = node,
					hosts = hosts,
					status = state,
					snapshot = snapshot,
					stop = function()
						stop()
						runtime:dispose()
					end,
				}
			end
			local pooled, fresh = world(32), world(0)
			local opening = pooled.snapshot()
			t.expect(fresh.snapshot()).toBe(opening)
			for step = 1, 40 do
				local at = pooled.engine.types.Vector2.new(0, step * 61)
				pooled.node.CanvasPosition = at
				fresh.node.CanvasPosition = at
				t.expect(pooled.snapshot()).toBe(fresh.snapshot())
			end
			pooled.node.CanvasPosition = pooled.engine.types.Vector2.zero
			fresh.node.CanvasPosition = fresh.engine.types.Vector2.zero
			t.expect(pooled.snapshot()).toBe(opening)
			t.expect(fresh.snapshot()).toBe(opening)
			local pooledHosts, freshHosts = 0, 0
			for host in pooled.hosts do
				pooledHosts += 1
				local _ = host
			end
			for host in fresh.hosts do
				freshHosts += 1
				t.expect(host.Parent == nil and not host.isDestroyed()).toBe(false)
			end
			t.expect(pooledHosts < freshHosts).toBe(true)
			for step = 1, 200 do
				pooled.node.CanvasPosition = pooled.engine.types.Vector2.new(0, (step * 61) % 11000)
				pooled.snapshot()
			end
			local parked = 0
			for host in pooled.hosts do
				if host.Parent == nil and not host.isDestroyed() then
					parked += 1
				end
			end
			t.expect(parked <= 32).toBe(true)
			local live = 0
			for host in pooled.hosts do
				if not host.isDestroyed() then
					live += 1
				end
			end
			t.expect(live <= pooled.status:peek().retained + 32).toBe(true)
			pooled.stop()
			fresh.stop()
		end
	)

	t.it(
		"mech3-03 a reused row container never carries the previous row's children, tags, attributes or props",
		function()
			local engine, runtime, UI, root = setup()
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = records(200),
					key = key,
					itemSize = 40,
					overscan = 0,
					render = function(current, _, rowKey)
						if rowKey % 2 == 1 then
							local odd = runtime.constructors.TextButton "Odd" {
								Text = function(use)
									return use(current).label
								end,
								Interactable = false,
								Size = engine.types.UDim2.fromScale(1, 1),
								Attributes = { Odd = true },
								runtime.constructors.UIStroke({ Thickness = 3 }),
								runtime.constructors.UIPadding({ PaddingLeft = engine.types.UDim.new(0, 12) }),
							}
							odd:AddTag("odd-row")
							return odd
						end
						return runtime.constructors.TextButton "Even" {
							Text = function(use)
								return use(current).label
							end,
							Size = engine.types.UDim2.fromScale(1, 1),
						}
					end,
				})
			end, root)
			window(node, engine, 200, 200)
			local hosted: { [any]: { [number]: boolean } } = {}
			local function check()
				for _, index in mountedKeys(node) do
					local host = rowHost(node, index)
					hosted[host] = hosted[host] or {}
					hosted[host][index % 2] = true
					t.expect(#host:GetChildren()).toBe(1)
					t.expect(#host:GetTags()).toBe(0)
					t.expect(host:GetAttribute("Odd")).toBeNil()
					t.expect(host.Size.Y.Offset).toBe(40)
					t.expect(host.Position.Y.Offset).toBe((index - 1) * 40)
					local content = host:FindFirstChild("Content")
					t.expect(#content:GetChildren()).toBe(1)
					local row = content:GetChildren()[1]
					t.expect(row.Text).toBe(tostring(index))
					if index % 2 == 1 then
						t.expect(row.Name).toBe("Odd")
						t.expect(row:HasTag("odd-row")).toBe(true)
						t.expect(row.Interactable).toBe(false)
					else
						t.expect(row.Name).toBe("Even")
						t.expect(row:HasTag("odd-row")).toBe(false)
						t.expect(row:GetAttribute("Odd")).toBeNil()
						t.expect(row.Interactable).toBe(true)
						t.expect(row:FindFirstChildWhichIsA("UIStroke")).toBeNil()
						t.expect(row:FindFirstChildWhichIsA("UIPadding")).toBeNil()
					end
				end
			end
			check()
			for step = 1, 30 do
				node.CanvasPosition = engine.types.Vector2.new(0, step * 57)
				check()
			end
			local crossed = false
			for _, parities in hosted do
				crossed = crossed or (parities[0] == true and parities[1] == true)
			end
			t.expect(crossed).toBe(true)
			stop()
			runtime:dispose()
		end
	)

	t.it(
		"mech3-97 degenerate collections answer without error and a past-the-end offset windows the last rows",
		function()
			local engine, runtime, UI, root = setup()
			local source, state, controls = Compose.cell({}), status(), {}
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 40,
					overscan = 0,
					status = state,
					controls = controls,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			t.expect(node:FindFirstChild("Items")).toBeNil()
			window(node, engine, 200, 400)
			t.expect(state:peek().total).toBe(0)
			t.expect(state:peek().extent).toBe(0)
			t.expect(state:peek().retained).toBe(0)
			t.expect(node.CanvasSize.Y.Offset).toBe(0)
			t.expect(mountedKeys(node)).toEqual({})
			source:set(records(1))
			t.expect(mountedKeys(node)).toEqual({ 1 })
			t.expect(state:peek().extent).toBe(40)
			t.expect(controls.placementOf(1).offset).toBe(0)
			source:set(records(10))
			t.expect(mountedKeys(node)).toEqual(range(1, 10))
			source:set(records(100))
			node.CanvasPosition = engine.types.Vector2.new(0, 100000)
			t.expect(mountedKeys(node)).toEqual(range(91, 100))
			t.expect(state:peek().last).toBe(100)
			window(node, engine, 200, 0)
			t.expect(node:FindFirstChild("Items")).toBeNil()
			stop()
			local uniformState, equalState = status(), status()
			local equal = {}
			for index = 1, 50 do
				equal[index] = 40
			end
			local stopUniform, uniform = runtime.mount(function()
				return UI.VirtualList({
					from = records(50),
					key = key,
					itemSize = 40,
					gap = 6,
					status = uniformState,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			local stopEqual, measured = runtime.mount(function()
				return UI.VirtualList({
					from = records(50),
					key = key,
					itemSize = 12,
					gap = 6,
					measured = equal,
					status = equalState,
					render = function(current)
						return label(UI, current)
					end,
				})
			end, root)
			for _, offset in { 0, 23, 460, 1000, 5000 } do
				for _, list in { uniform, measured } do
					window(list, engine, 200, 300)
					list.CanvasPosition = engine.types.Vector2.new(0, offset)
				end
				t.expect(equalState:peek().extent).toBe(uniformState:peek().extent)
				t.expect(mountedKeys(measured)).toEqual(mountedKeys(uniform))
				for _, index in mountedKeys(uniform) do
					t.expect(rowHost(measured, index).Position).toBe(rowHost(uniform, index).Position)
					t.expect(rowHost(measured, index).Size).toBe(rowHost(uniform, index).Size)
				end
			end
			stopUniform()
			stopEqual()
			runtime:dispose()
		end
	)

	t.it(
		"navigation-4-68 a list in a hidden tab keeps its keyed anchor across data changes and resets on empty data",
		function()
			local engine, runtime, UI, root = setup()
			local source, selected, state = Compose.cell(records(100)), Compose.cell("a"), status()
			local list, builds = nil, 0
			local stop, tabs = runtime.mount(function()
				return UI.TabView({
					selection = selected,
					tabs = {
						{
							id = "a",
							label = "List",
							content = function()
								list = UI.VirtualList({
									from = source,
									key = key,
									itemSize = 100,
									status = state,
									render = function(current)
										builds += 1
										return label(UI, current)
									end,
								})
								return list
							end,
						},
						{
							id = "b",
							label = "Other",
							content = function()
								return runtime.constructors.Frame({})
							end,
						},
					},
				})
			end, root)
			local mountedList = list
			window(list, engine, 400, 300)
			list.CanvasPosition = engine.types.Vector2.new(0, 2050)
			selected:set("b")
			local rotated = table.clone(source:peek())
			table.insert(rotated, 1, table.remove(rotated) :: any)
			source:set(rotated)
			selected:set("a")
			t.expect(list).toBe(mountedList)
			t.expect(list.CanvasPosition.Y).toBe(2150)
			t.expect(builds < 100).toBe(true)
			selected:set("b")
			source:set({})
			selected:set("a")
			t.expect(state:peek().extent).toBe(0)
			t.expect(list.CanvasSize.Y.Offset).toBe(0)
			t.expect(mountedKeys(list)).toEqual({})
			stop()
			local _ = tabs
			runtime:dispose()
		end
	)

	t.it(
		"themes-P1-35 avatar faces keep their resources on reorder and replace only a changed source or resource",
		function()
			local engine, runtime, UI, root = setup()
			local acquired, released = 0, 0
			local function resource()
				acquired += 1
				Compose.cleanup(function()
					released += 1
				end)
				return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://7") }
			end
			local a = { id = "a", name = "Ada", resource = resource, presence = "online" }
			local b = { id = "b", name = "Bo", image = "rbxassetid://1" }
			local roster = Compose.cell({ a, b })
			local stop, group = runtime.mount(function()
				return UI.AvatarGroup({ items = roster, layout = "spread" })
			end, root)
			t.expect(acquired).toBe(1)
			local faceA, faceB = group:FindFirstChild("a"), group:FindFirstChild("b")
			local imageB = faceB:FindFirstChild("Image", true)
			t.expect(faceA:FindFirstChild("Image", true).Image).toBe("rbxassetid://7")
			t.expect(imageB.Image).toBe("rbxassetid://1")
			roster:set({ b, { id = "a", name = "Alice Quill", resource = resource, presence = "away" } })
			t.expect(group:FindFirstChild("a")).toBe(faceA)
			t.expect(group:FindFirstChild("b")).toBe(faceB)
			t.expect(faceB.LayoutOrder < faceA.LayoutOrder).toBe(true)
			t.expect(acquired).toBe(1)
			t.expect(released).toBe(0)
			t.expect(faceA:FindFirstChild("Initials", true).Text).toBe("AQ")
			roster:set({ { id = "b", name = "Bo", image = "rbxassetid://2" }, roster:peek()[2] })
			t.expect(group:FindFirstChild("b")).toBe(faceB)
			t.expect(faceB:FindFirstChild("Image", true)).toBe(imageB)
			t.expect(imageB.Image).toBe("rbxassetid://2")
			t.expect(acquired).toBe(1)
			local replaced = 0
			local function replacement()
				replaced += 1
				return { state = Compose.cell("ready"), value = Compose.cell("rbxassetid://9") }
			end
			roster:set({ roster:peek()[1], { id = "a", name = "Alice Quill", resource = replacement } })
			t.expect(replaced).toBe(1)
			t.expect(released).toBe(1)
			t.expect(faceA.isDestroyed()).toBe(true)
			t.expect(group:FindFirstChild("b")).toBe(faceB)
			local faceNew = group:FindFirstChild("a")
			t.expect(faceNew ~= faceA).toBe(true)
			t.expect(faceNew:FindFirstChild("Image", true).Image).toBe("rbxassetid://9")
			roster:set({ roster:peek()[1] })
			t.expect(faceNew.isDestroyed()).toBe(true)
			stop()
			t.expect(released).toBe(acquired)
			runtime:dispose()
		end
	)
end)
