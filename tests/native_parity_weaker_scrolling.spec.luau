--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	screen: any,
	node: any,
	advance: (number) -> (),
	stop: () -> (),
}

local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		reducedMotion = true,
	}
	for key, value in (options or {}) :: { [string]: any } do
		if key == "preferredInput" then
			input.PreferredInput = engine.types.Enum.PreferredInput[value]
		else
			config[key] = value
		end
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local node
	local stop, screen = runtime.mount(function()
		node = build(UI, Host, engine)
		return Host.ScreenGui({ node })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		screen = screen,
		node = node,
		advance = function(seconds: number)
			for _ = 1, math.max(1, math.round(seconds * 60)) do
				now += 1 / 60
				engine.heartbeat.fire(1 / 60)
			end
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
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

local function action(root: any, name: string): any
	return assert(find(root, "Facet" .. name), name):FindFirstChild(name)
end

local function records(count: number): { { id: number, label: string } }
	local values = {}
	for index = 1, count do
		values[index] = { id = index, label = tostring(index) }
	end
	return values
end

local function key(item: { id: number }): number
	return item.id
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

local function row(root: any, name: string): any
	local items = root:FindFirstChild("Items")
	return if items then items:FindFirstChild(name) else nil
end

local function list(count: number, extra: { [string]: any }?): (any, any, any) -> any
	return function(UI)
		local spec: { [string]: any } = {
			from = records(count),
			key = key,
			itemSize = 20,
			overscan = 0,
			render = function(current)
				return UI.Button("Action")({
					label = function(use)
						return use(current).label
					end,
				})
			end,
		}
		for field, value in extra or {} do
			spec[field] = value
		end
		return UI.VirtualList(spec)
	end
end

local function pointer(world: World): any
	return {
		UserInputType = world.engine.types.Enum.UserInputType.MouseButton1,
		UserInputState = world.engine.types.Enum.UserInputState.Begin,
		Position = world.engine.types.Vector3.new(10, 10, 0),
	}
end

local function lift(world: World, body: any, name: string, at: number): (any, any)
	local handle = row(body, name):FindFirstChild("Move", true)
	local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
	local input = pointer(world)
	handle.InputBegan.fire(input)
	detector.DragStart.fire(V2(world, 10, 10))
	detector.DragContinue.fire(V2(world, 10, at))
	return detector, input
end

t.describe("native parity weaker scrolling", function()
	t.it("collections-03 autoscroll clamps at both canvas ends, stays armed and stops with the drag", function()
		local requests = {}
		local world = setup(list(30, {
			reorderable = true,
			onReorder = function(keys, slot)
				table.insert(requests, { keys = keys, slot = slot })
			end,
		}))
		local body = world.node
		body.AbsoluteWindowSize = V2(world, 200, 100)
		t.expect(world.engine.heartbeat.count()).toBe(0)
		lift(world, body, "1", 99)
		world.advance(2)
		t.expect(body.CanvasPosition.Y).toBe(500)
		world.advance(1)
		t.expect(body.CanvasPosition.Y).toBe(500)
		t.expect(find(body, "DropLine") ~= nil).toBe(true)
		t.expect(world.engine.heartbeat.count() > 0).toBe(true)
		local function move(y: number)
			world.input.InputChanged.fire({
				UserInputType = world.engine.types.Enum.UserInputType.MouseMovement,
				UserInputState = world.engine.types.Enum.UserInputState.Change,
				Position = world.engine.types.Vector3.new(10, y, 0),
			})
		end
		move(1)
		world.advance(2)
		t.expect(body.CanvasPosition.Y).toBe(0)
		world.advance(1)
		t.expect(body.CanvasPosition.Y).toBe(0)
		t.expect(find(body, "DropLine") ~= nil).toBe(true)
		move(50)
		body.CanvasPosition = V2(world, 0, 200)
		world.advance(1)
		t.expect(body.CanvasPosition.Y).toBe(200)
		world.input.InputEnded.fire(pointer(world))
		t.expect(#requests).toBe(1)
		t.expect(find(body, "DropLine")).toBeNil()
		t.expect(world.engine.heartbeat.count()).toBe(0)
		world.advance(1)
		t.expect(body.CanvasPosition.Y).toBe(200)
		world.stop()
	end)

	t.it("collections-15 edge autoscroll arms only for a captured pointer drag with room to scroll", function()
		local requests = {}
		local function reorderable(count: number)
			return list(count, {
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
			})
		end
		local world = setup(reorderable(30))
		local body = world.node
		body.AbsoluteWindowSize = V2(world, 200, 100)
		lift(world, body, "1", 95)
		world.advance(1 / 60)
		t.expect(body.CanvasPosition.Y > 0).toBe(true)
		world.advance(0.5)
		local scrolled = body.CanvasPosition.Y
		t.expect(scrolled > 100).toBe(true)
		world.input.InputEnded.fire(pointer(world))
		t.expect(#requests).toBe(1)
		t.expect(requests[1].keys).toEqual({ 1 })
		t.expect(requests[1].slot).toBe(math.floor((scrolled + 95 + 10) / 20) - 1)
		world.stop()

		local short = setup(reorderable(3))
		short.node.AbsoluteWindowSize = V2(short, 200, 100)
		lift(short, short.node, "1", 99)
		short.advance(1)
		t.expect(short.node.CanvasPosition.Y).toBe(0)
		short.input.InputEnded.fire(pointer(short))
		short.stop()

		local armed = setup(reorderable(30))
		armed.node.AbsoluteWindowSize = V2(armed, 200, 100)
		row(armed.node, "1"):FindFirstChild("Move", true).Activated.fire()
		t.expect(armed.gui.SelectedObject.Name).toBe("Drop")
		t.expect(armed.engine.heartbeat.count()).toBe(0)
		armed.advance(1)
		t.expect(armed.node.CanvasPosition.Y).toBe(0)
		armed.stop()

		local plain = setup(list(30))
		plain.node.AbsoluteWindowSize = V2(plain, 200, 100)
		t.expect(find(plain.node, "Move")).toBeNil()
		t.expect(find(plain.node, "ReorderFeedback")).toBeNil()
		plain.input.InputBegan.fire(pointer(plain))
		plain.advance(1)
		t.expect(plain.engine.heartbeat.count()).toBe(0)
		t.expect(plain.node.CanvasPosition.Y).toBe(0)
		plain.stop()
	end)

	t.it("collections-183 table autoscroll needs a drag and releases with the drop", function()
		local requests = {}
		local world = setup(function(UI)
			return UI.Table({
				from = records(100),
				key = key,
				overscan = 0,
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 200, 200)
		local resting = pointer(world)
		resting.Position = world.engine.types.Vector3.new(10, 195, 0)
		body.InputBegan.fire(resting)
		world.input.InputChanged.fire(resting)
		world.advance(1)
		t.expect(body.CanvasPosition.Y).toBe(0)
		t.expect(world.engine.heartbeat.count()).toBe(0)
		world.input.InputEnded.fire(resting)
		lift(world, body, "1", 195)
		world.advance(0.5)
		t.expect(body.CanvasPosition.Y > 0).toBe(true)
		world.input.InputEnded.fire(pointer(world))
		t.expect(#requests).toBe(1)
		local atDrop = body.CanvasPosition.Y
		t.expect(world.engine.heartbeat.count()).toBe(0)
		world.advance(1)
		t.expect(body.CanvasPosition.Y).toBe(atDrop)
		world.stop()
	end)

	t.it("collections-176 table body focus scrolls rows into view minimally in both directions", function()
		local focus: { [string]: any } = {}
		local world = setup(function(UI)
			return UI.Table({
				from = records(40),
				key = key,
				overscan = 0,
				focus = focus,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 200, 200)
		focus.focus(1)
		local first = row(body, "1")
		t.expect(first ~= nil).toBe(true)
		local height = first.Size.Y.Offset
		t.expect(height >= 40).toBe(true)
		t.expect(body.CanvasPosition.Y).toBe(0)
		local down, up = action(world.screen, "CollectionDown"), action(world.screen, "CollectionUp")
		local band = math.floor(200 / height)
		for _ = 1, band - 1 do
			down.Pressed.fire()
		end
		t.expect(focus.current:peek()).toBe(band)
		t.expect(body.CanvasPosition.Y).toBe(0)
		for _ = 1, 3 do
			down.Pressed.fire()
		end
		t.expect(focus.current:peek()).toBe(band + 3)
		t.expect(body.CanvasPosition.Y).toBe((band + 3) * height - 200)
		t.expect(world.gui.SelectedObject:IsDescendantOf(row(body, tostring(band + 3)))).toBe(true)
		for _ = 1, band + 2 do
			up.Pressed.fire()
		end
		t.expect(focus.current:peek()).toBe(1)
		t.expect(body.CanvasPosition.Y).toBe(0)
		world.stop()
	end)

	t.it("apps-225 engine scrolling reaches the collection observer until teardown", function()
		local status = Compose.cell({
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
		} :: Compose.OrderedCollectionStatus)
		local world = setup(list(100, { status = status }))
		local node = world.node
		node.AbsoluteWindowSize = V2(world, 200, 100)
		t.expect(status:peek().first).toBe(1)
		node.CanvasPosition = V2(world, 0, 77)
		t.expect(status:peek().first).toBe(4)
		t.expect(row(node, "4") ~= nil).toBe(true)
		node.CanvasPosition = V2(world, 0, 99)
		t.expect(status:peek().first).toBe(5)
		world.stop()
		node.CanvasPosition = V2(world, 0, 400)
		t.expect(status:peek().first).toBe(5)
		t.expect(node:GetPropertyChangedSignal("CanvasPosition").count()).toBe(0)
	end)

	local function grid(direction: string)
		return function(UI)
			return UI.VirtualGrid({
				from = records(400),
				key = key,
				columns = 4,
				direction = direction,
				itemSize = 40,
				overscan = 0,
				render = function(current)
					return UI.Button("Action")({
						label = function(use)
							return use(current).label
						end,
					})
				end,
			})
		end
	end

	t.it("collections-32 list, both grid axes and table slide their windows from engine scrolling alone", function()
		local vertical = setup(list(100, { itemSize = 40 }))
		vertical.node.AbsoluteWindowSize = V2(vertical, 200, 400)
		t.expect(row(vertical.node, "1") ~= nil).toBe(true)
		vertical.node.CanvasPosition = V2(vertical, 0, 2000)
		t.expect(row(vertical.node, "1")).toBeNil()
		t.expect(row(vertical.node, "51") ~= nil).toBe(true)
		vertical.stop()
		for _, direction in { "vertical", "horizontal" } do
			local world = setup(grid(direction))
			world.node.AbsoluteWindowSize = if direction == "vertical" then V2(world, 320, 400) else V2(world, 400, 320)
			t.expect(row(world.node, "1") ~= nil).toBe(true)
			t.expect(row(world.node, "41")).toBeNil()
			world.node.CanvasPosition = if direction == "vertical" then V2(world, 0, 400) else V2(world, 400, 0)
			t.expect(row(world.node, "1")).toBeNil()
			t.expect(row(world.node, "41") ~= nil).toBe(true)
			world.stop()
		end
		local tableWorld = setup(function(UI)
			return UI.Table({
				from = records(400),
				key = key,
				overscan = 0,
				header = false,
				columns = { { id = "label", label = "Label" } },
			})
		end)
		local body = find(tableWorld.node, "Body")
		body.AbsoluteWindowSize = V2(tableWorld, 200, 400)
		local height = row(body, "1").Size.Y.Offset
		t.expect(row(body, "1") ~= nil).toBe(true)
		body.CanvasPosition = V2(tableWorld, 0, 50 * height)
		t.expect(row(body, "1")).toBeNil()
		t.expect(row(body, "51") ~= nil).toBe(true)
		tableWorld.stop()
	end)

	t.it("collections-231 engine scroll slides a vertical grid window to whole lines at canvas offsets", function()
		local world = setup(grid("vertical"))
		world.node.AbsoluteWindowSize = V2(world, 320, 400)
		t.expect(world.node.CanvasSize.Y.Offset).toBe(100 * 40)
		world.node.CanvasPosition = V2(world, 0, 400)
		for index = 1, 40 do
			t.expect(row(world.node, tostring(index))).toBeNil()
		end
		for index = 41, 80 do
			local cell = row(world.node, tostring(index))
			t.expect(cell ~= nil).toBe(true)
			t.expect(cell.Position.Y.Offset).toBe(math.floor((index - 1) / 4) * 40)
			t.expect(cell.Position.X.Offset).toBe(((index - 1) % 4) * 80)
		end
		t.expect(row(world.node, "81")).toBeNil()
		world.stop()
	end)

	t.it("collections-242 native X scroll slides a horizontal grid window along X", function()
		local world = setup(grid("horizontal"))
		world.node.AbsoluteWindowSize = V2(world, 400, 320)
		t.expect(world.node.CanvasSize.X.Offset).toBe(100 * 40)
		t.expect(world.node.CanvasSize.Y.Offset).toBe(0)
		world.node.CanvasPosition = V2(world, 400, 0)
		for index = 1, 40 do
			t.expect(row(world.node, tostring(index))).toBeNil()
		end
		for index = 41, 80 do
			local cell = row(world.node, tostring(index))
			t.expect(cell ~= nil).toBe(true)
			t.expect(cell.Position.X.Offset).toBe(math.floor((index - 1) / 4) * 40)
			t.expect(cell.Position.Y.Offset).toBe(((index - 1) % 4) * 80)
		end
		t.expect(row(world.node, "81")).toBeNil()
		world.node.CanvasPosition = V2(world, 400, 900)
		t.expect(row(world.node, "41") ~= nil).toBe(true)
		t.expect(row(world.node, "1")).toBeNil()
		world.stop()
	end)

	t.it("collections-262 list keys bind arrows and D-pad to one action that steps and reveals rows", function()
		local focus: { [string]: any } = {}
		local world = setup(list(100, { itemSize = 40, focus = focus }))
		local node = world.node
		node.AbsoluteWindowSize = V2(world, 200, 200)
		node.CanvasPosition = V2(world, 0, 480)
		t.expect(row(node, "1")).toBeNil()
		t.expect(row(node, "13").Position.Y.Offset).toBe(12 * 40)
		node.CanvasPosition = V2(world, 0, 0)
		local KeyCode = world.engine.types.Enum.KeyCode
		local expected = {
			CollectionDown = { KeyCode.Down, KeyCode.DPadDown },
			CollectionUp = { KeyCode.Up, KeyCode.DPadUp },
			CollectionLeft = { KeyCode.Left, KeyCode.DPadLeft },
			CollectionRight = { KeyCode.Right, KeyCode.DPadRight },
		}
		for name, keys in expected do
			local inputAction = action(world.screen, name)
			t.expect(inputAction.ClassName).toBe("InputAction")
			local bound = {}
			for _, binding in inputAction:GetChildren() do
				if binding:IsA("InputBinding") then
					table.insert(bound, binding.KeyCode)
				end
			end
			t.expect(bound).toEqual(keys)
		end
		focus.focus(1)
		t.expect(world.gui.SelectedObject.Text).toBe("1")
		local down, up = action(world.screen, "CollectionDown"), action(world.screen, "CollectionUp")
		down.Pressed.fire()
		down.Pressed.fire()
		t.expect(world.gui.SelectedObject.Text).toBe("3")
		up.Pressed.fire()
		t.expect(world.gui.SelectedObject.Text).toBe("2")
		t.expect(node.CanvasPosition.Y).toBe(0)
		for _ = 1, 5 do
			down.Pressed.fire()
		end
		t.expect(world.gui.SelectedObject.Text).toBe("7")
		t.expect(node.CanvasPosition.Y).toBe(7 * 40 - 200)
		world.stop()
	end)

	local function snapList(
		count: number,
		viewport: number,
		extra: { [string]: any }?,
		options: { [string]: any }?
	): World
		local spec: { [string]: any } = { itemSize = 100, snap = "item" }
		for field, value in extra or {} do
			spec[field] = value
		end
		local world = setup(list(count, spec), options)
		world.node.AbsoluteWindowSize = V2(world, 200, viewport)
		return world
	end

	local function scroll(world: World, offset: number)
		world.node.CanvasPosition = V2(world, 0, offset)
	end

	local function flick(world: World, from: number, to: number, steps: number)
		for index = 1, steps do
			scroll(world, from + (to - from) * (index / steps))
			world.advance(1 / 60)
		end
	end

	local function writes(world: World): () -> number
		local count = 0
		world.node:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			count += 1
		end)
		return function()
			return count
		end
	end

	t.it("collections-125 snap resolves nearest, flick, fling, end and fitting content boundaries", function()
		local world = snapList(20, 300)
		world.advance(1)
		scroll(world, 77)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(100)
		world.advance(1)
		flick(world, 100, 130, 3)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(200)
		scroll(world, 133)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(100)
		scroll(world, 400)
		world.advance(0.5)
		local count = writes(world)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(400)
		t.expect(count()).toBe(0)
		world.advance(1)
		flick(world, 400, 440, 4)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(500)
		world.advance(1)
		flick(world, 500, 460, 4)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(400)
		world.advance(1)
		flick(world, 400, 1230, 4)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(1200)
		world.advance(1)
		scroll(world, 1700)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(1700)
		world.advance(1)
		scroll(world, 1696)
		world.advance(0.5)
		t.expect(world.node.CanvasPosition.Y).toBe(1700)
		world.stop()

		local page = snapList(20, 250)
		page.advance(1)
		scroll(page, 1745)
		page.advance(0.5)
		t.expect(page.node.CanvasPosition.Y).toBe(1750)
		page.advance(1)
		scroll(page, 1710)
		page.advance(0.5)
		t.expect(page.node.CanvasPosition.Y).toBe(1700)
		page.advance(1)
		scroll(page, 1750)
		page.advance(0.5)
		t.expect(page.node.CanvasPosition.Y).toBe(1750)
		page.advance(1)
		flick(page, 1750, 1690, 4)
		page.advance(0.5)
		t.expect(page.node.CanvasPosition.Y).toBe(1700)
		page.stop()

		local fits = snapList(2, 300)
		local fitted = writes(fits)
		fits.advance(1)
		scroll(fits, 0)
		fits.node.InputBegan.fire(pointer(fits))
		fits.input.InputEnded.fire(pointer(fits))
		fits.advance(1)
		t.expect(fits.node.CanvasPosition.Y).toBe(0)
		t.expect(fitted()).toBe(0)
		scroll(fits, 40)
		fits.advance(0.5)
		t.expect(fits.node.CanvasPosition.Y).toBe(0)
		fits.stop()
	end)

	local function recorded(world: World): { number }
		local values = {}
		world.node:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			table.insert(values, world.node.CanvasPosition.Y)
		end)
		return values
	end

	t.it(
		"collections-127 engine-driven snap settles, travels, holds, yields and treats framework writes as rests",
		function()
			local plain = snapList(20, 300, { snap = "none" })
			plain.advance(1)
			scroll(plain, 77)
			local untouched = writes(plain)
			plain.advance(1)
			t.expect(plain.node.CanvasPosition.Y).toBe(77)
			t.expect(untouched()).toBe(0)
			plain.stop()

			local reduced = snapList(20, 300)
			reduced.advance(1)
			scroll(reduced, 77)
			local values = recorded(reduced)
			reduced.advance(0.12)
			t.expect(values).toEqual({})
			reduced.advance(1 / 60)
			t.expect(values).toEqual({ 100 })
			reduced.advance(1)
			t.expect(values).toEqual({ 100 })
			t.expect(reduced.engine.heartbeat.count()).toBe(0)
			reduced.advance(1)
			scroll(reduced, 1700)
			local atEnd = writes(reduced)
			reduced.advance(1)
			t.expect(reduced.node.CanvasPosition.Y).toBe(1700)
			t.expect(atEnd()).toBe(0)
			reduced.advance(1)
			scroll(reduced, 40)
			reduced.advance(0.5)
			t.expect(reduced.node.CanvasPosition.Y).toBe(0)
			reduced.advance(1)
			flick(reduced, 0, 30, 5)
			reduced.advance(0.5)
			t.expect(reduced.node.CanvasPosition.Y).toBe(100)
			reduced.stop()

			local moving = snapList(20, 300, nil, { reducedMotion = false })
			moving.advance(1)
			scroll(moving, 77)
			moving.advance(10 / 60)
			local mid = moving.node.CanvasPosition.Y
			t.expect(mid > 77 and mid < 100).toBe(true)
			moving.advance(1)
			t.expect(moving.node.CanvasPosition.Y).toBe(100)
			t.expect(moving.engine.heartbeat.count()).toBe(0)
			moving.advance(1)
			scroll(moving, 177)
			moving.advance(10 / 60)
			t.expect(moving.node.CanvasPosition.Y > 177).toBe(true)
			scroll(moving, 640)
			moving.advance(3 / 60)
			t.expect(moving.node.CanvasPosition.Y).toBe(640)
			moving.advance(1)
			t.expect(moving.node.CanvasPosition.Y).toBe(600)
			moving.stop()

			local tall = snapList(10, 300, { itemSize = 400 })
			tall.advance(1)
			scroll(tall, 77)
			tall.advance(1)
			t.expect(tall.node.CanvasPosition.Y).toBe(77)
			tall.stop()

			local varied = snapList(8, 300, { measured = { [1] = 100, [2] = 250, [3] = 60, [4] = 400, [5] = 120 } })
			varied.advance(1)
			scroll(varied, 180)
			varied.advance(0.5)
			t.expect(varied.node.CanvasPosition.Y).toBe(100)
			varied.advance(1)
			scroll(varied, 300)
			varied.advance(0.5)
			t.expect(varied.node.CanvasPosition.Y).toBe(350)
			varied.advance(1)
			scroll(varied, 500)
			varied.advance(0.5)
			t.expect(varied.node.CanvasPosition.Y).toBe(500)
			varied.stop()

			local sizes = Compose.cell({} :: { [number]: number })
			local anchored = snapList(8, 300, { measured = sizes })
			anchored.advance(1)
			scroll(anchored, 300)
			anchored.advance(1)
			t.expect(anchored.node.CanvasPosition.Y).toBe(300)
			local grown = {}
			for index = 1, 8 do
				grown[index] = 150
			end
			sizes:set(grown)
			t.expect(anchored.node.CanvasPosition.Y).toBe(450)
			anchored.advance(1)
			t.expect(anchored.node.CanvasPosition.Y).toBe(450)
			anchored.stop()

			local focus: { [string]: any } = {}
			local focused = snapList(20, 250, { focus = focus })
			focused.advance(1)
			flick(focused, 0, 40, 4)
			focus.focus(9)
			t.expect(focused.node.CanvasPosition.Y).toBe(650)
			focused.advance(1)
			t.expect(focused.node.CanvasPosition.Y).toBe(650)
			focused.stop()

			t.expect(function()
				setup(list(4, { snap = "paging" }))
			end).toThrow()

			for _, snap in { "item", "none" } do
				local world = setup(function(UI)
					return UI.VirtualGrid({
						from = records(40),
						key = key,
						columns = 2,
						itemSize = 100,
						overscan = 0,
						snap = snap,
						render = function(current)
							return UI.Button("Action")({
								label = function(use)
									return use(current).label
								end,
							})
						end,
					})
				end)
				world.node.AbsoluteWindowSize = V2(world, 320, 300)
				world.advance(1)
				scroll(world, 77)
				world.advance(1)
				t.expect(world.node.CanvasPosition.Y).toBe(if snap == "item" then 100 else 77)
				world.stop()
			end
		end
	)

	t.it("apps-231 snap travel yields to native scrolling and never resumes toward its old target", function()
		local world = snapList(20, 300, nil, { reducedMotion = false })
		world.advance(1)
		scroll(world, 77)
		world.advance(10 / 60)
		t.expect(world.node.CanvasPosition.Y > 77).toBe(true)
		local values = recorded(world)
		scroll(world, 180)
		world.advance(6 / 60)
		t.expect(values).toEqual({ 180 })
		world.advance(1)
		t.expect(world.node.CanvasPosition.Y).toBe(200)
		for _, value in values do
			t.expect(value >= 180).toBe(true)
		end
		world.stop()
	end)

	t.it("apps2-267 Discover and Chat scroll positions survive presentation switches at 640/1280/1920", function()
		local modelModule = require("../examples/virtual_monitors/model")
		local screens = require("../examples/virtual_monitors/screens")
		local extents: { [string]: { number } } = { Discover = {}, Chat = {} }
		for _, application in { "Discover", "Chat" } do
			for _, screenWidth in { 640, 1280, 1920 } do
				local engine: any = engineLib.new()
				local runtime = Facet.Roblox.createRuntime(engine)
				local target = engine.new("ScreenGui")
				local gui, input = engine.new("GuiService"), engine.new("UserInputService")
				input.GetFocusedTextBox = function()
					return nil
				end
				input.IsKeyDown = function()
					return false
				end
				local types = engine.types
				local lifetime = Compose.createRootOwner(function()
					local model = modelModule.new(Compose)
					Compose.cleanup(model.dispose)
					local history = {}
					for index = 1, 24 do
						table.insert(history, {
							id = index,
							role = if index % 2 == 0 then "assistant" else "user",
							content = `Message {index}: retained conversation history.`,
						})
					end
					model.chat.messages:set(history)
					local scrollerName = if application == "Discover" then "Games" else "Messages"
					local bodyName = if application == "Discover" then "DiscoverBody" else "ChatBody"
					local position = if application == "Discover" then model.discoveryScroll else model.chatScroll
					local function present(spatial: boolean, width: number): (() -> (), any)
						local views = screens.create(Facet, runtime, {
							model = model,
							types = types,
							services = { GuiService = gui, UserInputService = input },
							spatial = spatial,
							reducedMotion = true,
						})
						local stop, root = runtime.mount(views[application], target)
						root.AbsoluteSize = types.Vector2.new(width, 640)
						find(root, bodyName).AbsoluteSize = types.Vector2.new(width, 640)
						local scroller = find(root, scrollerName)
						scroller.AbsoluteWindowSize = types.Vector2.new(width - 40, 260)
						return stop, scroller
					end
					local stopSpatial, spatial = present(true, 920)
					spatial.CanvasPosition = types.Vector2.new(0, 420)
					t.expect(position:peek()).toBe(420)
					stopSpatial()
					model.mode:set("Screen")
					local stopFlat, flat = present(false, screenWidth)
					t.expect(`{application} {screenWidth} {flat.CanvasPosition.Y}`)
						.toBe(`{application} {screenWidth} 420`)
					table.insert(extents[application], flat.CanvasSize.Y.Offset)
					flat.CanvasPosition = types.Vector2.new(0, 660)
					t.expect(position:peek()).toBe(660)
					stopFlat()
					local stopReturn, returned = present(false, screenWidth)
					t.expect(`{application} {screenWidth} {returned.CanvasPosition.Y}`)
						.toBe(`{application} {screenWidth} 660`)
					stopReturn()
					model.mode:set("Spatial")
					local stopBack, back = present(true, 920)
					t.expect(`{application} {screenWidth} {back.CanvasPosition.Y}`)
						.toBe(`{application} {screenWidth} 660`)
					stopBack()
				end, runtime.reactor)
				lifetime.dispose()
				t.expect(#target:GetChildren()).toBe(0)
				runtime:dispose()
			end
		end
		t.expect(extents.Discover[1] > extents.Discover[2] and extents.Discover[2] > extents.Discover[3]).toBe(true)
		t.expect(extents.Chat[1] >= extents.Chat[3]).toBe(true)
	end)

	t.it(
		"navigation-1-18 a long alert message scrolls inside a bounded region while the actions stay reachable",
		function()
			local cases = {
				{
					modal = { 640, 320 },
					content = 1000,
					message = string.rep("Check your selected equipment before continuing. ", 40),
					actions = {
						{ id = "Cancel", label = "Cancel", role = "cancel" },
						{ id = "Go", label = "Continue" },
					},
				},
				{
					modal = { 749, 235 },
					content = 60,
					message = "Your current progress will replace the previous checkpoint.",
					actions = {
						{ id = "Cancel", label = "Keep previous", role = "cancel" },
						{ id = "Delete", label = "Replace save", role = "destructive" },
					},
				},
			}
			for _, case in cases do
				local world = setup(function(UI)
					return UI.Alert({
						isPresented = Compose.cell(true),
						title = "Review changes",
						severity = if case.actions[2].role == "destructive" then "critical" else nil,
						message = case.message,
						actions = case.actions,
					})
				end, { preferredInput = "Gamepad" })
				local types = world.engine.types
				find(world.screen, "AlertModal").AbsoluteSize = types.Vector2.new(case.modal[1], case.modal[2])
				find(world.screen, "Actions").AbsoluteSize = types.Vector2.new(case.modal[1] - 40, 44)
				find(world.screen, "AlertContent").AbsoluteSize = types.Vector2.new(case.modal[1] - 40, case.content)
				local scroll = find(world.screen, "AlertMessage")
				t.expect(scroll.ClassName).toBe("ScrollingFrame")
				t.expect(scroll.ScrollingDirection).toBe(types.Enum.ScrollingDirection.Y)
				t.expect(scroll.AutomaticCanvasSize).toBe(types.Enum.AutomaticSize.None)
				local bound = math.max(44, case.modal[2] - 44 - 40 - 40)
				t.expect(scroll.Size.Y.Offset).toBe(math.min(case.content, bound))
				t.expect(scroll.Size.Y.Offset < case.content).toBe(case.content > bound)
				t.expect(find(world.screen, "AlertContent"):IsDescendantOf(scroll)).toBe(true)
				local actions = find(world.screen, "Actions")
				t.expect(actions:IsDescendantOf(scroll)).toBe(false)
				t.expect(actions.Parent == scroll.Parent).toBe(true)
				for _, entry in case.actions do
					local button = find(actions, entry.id)
					t.expect(button.Selectable).toBe(true)
					t.expect(button.Interactable).toBe(true)
					t.expect(button.Visible).toBe(true)
				end
				local selected = world.gui.SelectedObject
				t.expect(selected ~= nil and selected:IsDescendantOf(actions)).toBe(true)
				t.expect(selected.Name).toBe("Cancel")
				world.stop()
			end
		end
	)

	t.it("navigation-5-05 selecting an off-screen tab reveals it on either side of a top bar or sidebar", function()
		for _, placement in { "topBar", "sidebar" } do
			local selected = Compose.cell("a")
			local world = setup(function(UI)
				local tabs = {}
				for _, id in { "a", "b", "c" } do
					table.insert(tabs, {
						id = id,
						label = string.upper(id),
						content = function()
							return UI.Button(id .. "Content")({ label = id })
						end,
					})
				end
				return UI.TabView({ selection = selected, placement = placement, transition = false, tabs = tabs })
			end)
			local types = world.engine.types
			local vertical = placement == "sidebar"
			local function along(main: number, cross: number): any
				return if vertical then types.Vector2.new(cross, main) else types.Vector2.new(main, cross)
			end
			local bar = find(world.screen, "Tabs")
			t.expect(bar.ClassName).toBe("ScrollingFrame")
			local function offset(): number
				return if vertical then bar.CanvasPosition.Y else bar.CanvasPosition.X
			end
			local function place(scrolled: number)
				for index, id in { "a", "b", "c" } do
					local button = find(bar, id)
					button.AbsolutePosition = along((index - 1) * 80 - scrolled, 0)
					button.AbsoluteSize = along(80, 44)
				end
			end
			bar.AbsoluteSize = along(100, 200)
			place(0)
			local changes = 0
			bar:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				changes += 1
			end)
			selected:set("c")
			t.expect(offset()).toBe(140)
			t.expect(changes).toBe(1)
			place(140)
			t.expect(changes).toBe(1)
			selected:set("a")
			t.expect(offset()).toBe(0)
			t.expect(changes).toBe(2)
			place(0)
			bar.AbsoluteSize = along(250, 200)
			selected:set("b")
			selected:set("c")
			t.expect(offset()).toBe(0)
			t.expect(changes).toBe(2)
			world.stop()
		end
	end)
end)
