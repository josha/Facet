--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

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
	for _, child in root:GetChildren() do
		if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
			return child:FindFirstChild(name)
		end
	end
	return nil
end

type World = {
	engine: any,
	runtime: any,
	UI: any,
	Host: any,
	gui: any,
	input: any,
	root: any,
	node: any,
	stop: () -> (),
}

local function setup(build: (any, any, any, any, any) -> any, options: { [string]: any }?): World
	local settings: { [string]: any } = options or {}
	local engine: any = engineLib.new()
	if settings.clock then
		engine.clock = settings.clock
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
	if settings.preferredInput then
		input.PreferredInput = engine.types.Enum.PreferredInput[settings.preferredInput]
	end
	local root = engine.new("ScreenGui")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		inputParent = root,
		overlayParent = root,
		reducedMotion = true,
	}
	for key, value in settings.config or {} do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, node = runtime.mount(function()
		return build(UI, Host, engine, gui, runtime)
	end, root)
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = Host,
		gui = gui,
		input = input,
		root = root,
		node = node,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

local function touch(world: World, x: number, y: number): any
	return {
		UserInputType = world.engine.types.Enum.UserInputType.Touch,
		UserInputState = world.engine.types.Enum.UserInputState.Begin,
		Position = world.engine.types.Vector3.new(x, y, 0),
	}
end

local function moveTo(world: World, input: any, x: number, y: number)
	input.Position = world.engine.types.Vector3.new(x, y, 0)
	input.UserInputState = world.engine.types.Enum.UserInputState.Change
	world.input.InputChanged.fire(input)
end

local function release(world: World, input: any)
	input.UserInputState = world.engine.types.Enum.UserInputState.End
	world.input.InputEnded.fire(input)
end

local function compass(picked: { string }): { any }
	local entries = {}
	for _, id in { "N", "E", "S", "W" } do
		table.insert(entries, {
			id = id,
			slot = id,
			label = id,
			completion = "stay",
			onSelect = function()
				table.insert(picked, id)
			end,
		})
	end
	return entries
end

local function radial(spec: { [string]: any }): World
	spec.isPresented = spec.isPresented or Compose.cell(true)
	local world = setup(function(UI, Host)
		return Host.Frame({ UI.RadialMenu(spec) })
	end)
	return world
end

local function preview(world: World): string
	local node = find(world.root, "SelectionPreview")
	return if node then node.Text else ""
end

local function presentation(world: World): string?
	local panel = find(world.root, "RadialPanel")
	return if panel then panel:GetAttribute("Presentation") else nil
end

local function positionOf(node: any): (number, number)
	return node.Position.X.Offset, node.Position.Y.Offset
end

t.describe("pointer, touch and drag strength", function()
	t.it("swaps a dragged Match3 tile only with the orthogonal neighbour in the drag direction", function()
		local match3 = require("../examples/gallery/examples/07_match3")
		local gallery = require("../examples/gallery/client/screen")
		local board = {
			{ "a", "a", "b", "c", "d", "e" },
			{ "c", "d", "a", "e", "b", "c" },
			{ "e", "b", "c", "d", "a", "b" },
			{ "b", "c", "d", "e", "c", "a" },
			{ "d", "e", "b", "a", "e", "d" },
			{ "a", "c", "e", "b", "d", "c" },
		}
		local cases: { { number } } = {
			{ 1, 3, 2, 3, 2, 3 },
			{ 1, 3, 2, 4, 2, 3 },
			{ 1, 3, 4, 3, 2, 3 },
			{ 2, 4, 2, 6, 2, 5 },
			{ 1, 3, 0, 3, 0, 0 },
			{ 1, 1, 1, 0, 0, 0 },
		}
		for _, case in cases do
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local target = engine.new("Folder")
			local viewport = Compose.cell({ width = 800, height = 600 })
			local ctx: any = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				types = engine.types,
				inputTarget = target,
				worldTarget = engine.new("Folder"),
				guiService = engine.new("GuiService"),
				viewport = viewport,
				runService = { Heartbeat = engine.heartbeat },
				target = target,
				engine = engine,
			}
			ctx.guiService.ReducedMotionEnabled = true
			local game: any
			local stop, node = runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = Facet.controls(
					runtime,
					{ types = engine.types, viewport = viewport, reducedMotion = ctx.reducedMotion } :: any
				)
				game = match3.build(ctx)
				return ctx.Host.ScreenGui("GameScreen")({ game.screen() })
			end, target)
			game.debugSetBoard(board)
			local fromRow, fromCol, toRow, toCol, swapRow, swapCol = table.unpack(case)
			local ids = {}
			for row = 1, 6 do
				ids[row] = {}
				for col = 1, 6 do
					ids[row][col] = game.tileIdAt(row, col)
				end
			end
			local hit = find(find(node, "tile" .. ids[fromRow][fromCol]), "hit")
			local drag = find(hit, "SwapDrag")
			local origin = engine.types.Vector2.new((fromCol - 0.5) * 48, (fromRow - 0.5) * 48)
			local destination = engine.types.Vector2.new((toCol - 0.5) * 48, (toRow - 0.5) * 48)
			drag.DragStart.fire(origin)
			drag.DragContinue.fire(destination)
			drag.DragEnd.fire(destination)
			if swapRow == 0 then
				t.expect(game.isResolving()).toBe(false)
				for row = 1, 6 do
					for col = 1, 6 do
						t.expect(game.tileIdAt(row, col)).toBe(ids[row][col])
					end
				end
			else
				t.expect(game.isResolving()).toBe(true)
				t.expect(game.tileIdAt(swapRow, swapCol)).toBe(ids[fromRow][fromCol])
				t.expect(game.tileIdAt(fromRow, fromCol)).toBe(ids[swapRow][swapCol])
				for row = 1, 6 do
					for col = 1, 6 do
						local moved = (row == fromRow and col == fromCol) or (row == swapRow and col == swapCol)
						if not moved then
							t.expect(game.tileIdAt(row, col)).toBe(ids[row][col])
						end
					end
				end
				t.expect(math.abs(swapRow - fromRow) + math.abs(swapCol - fromCol)).toBe(1)
			end
			for _ = 1, 2400 do
				if game.phase() == "idle" then
					break
				end
				engine.heartbeat.fire(0.01)
			end
			t.expect(game.phase()).toBe("idle")
			local matched = swapRow == 2 and swapCol == 3
			t.expect(game.moves()).toBe(if matched then 1 else 0)
			t.expect(game.score() > 0).toBe(matched)
			stop()
			runtime:dispose()
		end
	end)

	t.it("latches a launcher tap open without a commit and keeps every ring target at the touch floor", function()
		local picked = {}
		local opened = Compose.cell(false)
		local world = radial({ isPresented = opened, distribution = "compass", items = compass(picked) })
		local launcher = find(world.root, "Launcher")
		for _, point in { { 0, 0 }, { 320, 240 } } do
			local press = touch(world, point[1], point[2])
			launcher.InputBegan.fire(press)
			t.expect(opened:peek()).toBe(true)
			release(world, press)
			launcher.Activated.fire(press)
			t.expect(opened:peek()).toBe(true)
			t.expect(#picked).toBe(0)
			t.expect(presentation(world)).toBe("radial")
			opened:set(false)
			launcher.Activated.fire({
				UserInputType = world.engine.types.Enum.UserInputType.Gamepad1,
				KeyCode = world.engine.types.Enum.KeyCode.ButtonA,
			})
			t.expect(opened:peek()).toBe(true)
			t.expect(#picked).toBe(0)
			opened:set(false)
		end
		opened:set(true)
		local panel = find(world.root, "RadialPanel")
		for _, id in { "N", "E", "S", "W" } do
			local button = find(world.root, id)
			local x, y = positionOf(button)
			local dx, dy = x - 320, y - 240
			local length = math.sqrt(dx * dx + dy * dy)
			local ux, uy = dx / length, dy / length
			local reach = 22
			for _, offset in { { reach, 0 }, { -reach, 0 }, { 0, reach }, { 0, -reach } } do
				local px = x + ux * offset[1] - uy * offset[2]
				local py = y + uy * offset[1] + ux * offset[2]
				local before = #picked
				local press = touch(world, px, py)
				panel.InputBegan.fire(press)
				release(world, press)
				t.expect(#picked).toBe(before + 1)
				t.expect(picked[#picked]).toBe(id)
			end
		end
		t.expect(opened:peek()).toBe(true)
		world.stop()
		local crowded = {}
		for index = 1, 24 do
			table.insert(crowded, { id = "Item" .. index, label = "Item " .. index, onSelect = function() end })
		end
		local dense = radial({ items = crowded })
		t.expect(presentation(dense)).toBe("list")
		for index = 1, 24 do
			t.expect(find(dense.root, "Item" .. index).Size.Y.Offset).toBe(44)
		end
		dense.stop()
	end)

	t.it(
		"previews a dragged or hovered choice without running it and cancels when the drag returns to the center",
		function()
			local picked = {}
			local opened = Compose.cell(false)
			local world = radial({ isPresented = opened, distribution = "compass", items = compass(picked) })
			local launcher = find(world.root, "Launcher")
			for _, kind in { "Touch", "MouseButton1" } do
				local press = touch(world, 320, 240)
				press.UserInputType = world.engine.types.Enum.UserInputType[kind]
				launcher.InputBegan.fire(press)
				t.expect(opened:peek()).toBe(true)
				local south = find(world.root, "S")
				t.expect(south:HasTag("facet-selected")).toBe(false)
				if kind == "Touch" then
					moveTo(world, press, 320, 370)
				else
					world.input.InputChanged.fire({
						UserInputType = world.engine.types.Enum.UserInputType.MouseMovement,
						UserInputState = world.engine.types.Enum.UserInputState.Change,
						Position = world.engine.types.Vector3.new(320, 370, 0),
					})
				end
				t.expect(preview(world)).toBe("S")
				t.expect(south:HasTag("facet-selected")).toBe(true)
				t.expect(#picked).toBe(0)
				if kind == "Touch" then
					moveTo(world, press, 321, 239)
				else
					world.input.InputChanged.fire({
						UserInputType = world.engine.types.Enum.UserInputType.MouseMovement,
						UserInputState = world.engine.types.Enum.UserInputState.Change,
						Position = world.engine.types.Vector3.new(321, 239, 0),
					})
				end
				t.expect(preview(world) ~= "S").toBe(true)
				t.expect(south:HasTag("facet-selected")).toBe(false)
				press.Position = world.engine.types.Vector3.new(321, 239, 0)
				release(world, press)
				launcher.Activated.fire(press)
				t.expect(#picked).toBe(0)
				t.expect(south:HasTag("facet-selected")).toBe(false)
				local east = find(world.root, "E")
				east.MouseEnter.fire()
				t.expect(preview(world)).toBe("E")
				t.expect(east:HasTag("facet-selected")).toBe(true)
				t.expect(#picked).toBe(0)
				east.MouseLeave.fire()
				t.expect(preview(world) ~= "E").toBe(true)
				t.expect(east:HasTag("facet-selected")).toBe(false)
				opened:set(false)
			end
			world.stop()
		end
	)

	t.it(
		"commits once when native Activated arrives before the release and when a list launcher echoes a touch",
		function()
			local picked = {}
			local world = radial({ distribution = "compass", completion = "stay", items = compass(picked) })
			local north = find(world.root, "N")
			local press = touch(world, 320, 110)
			north.InputBegan.fire(press)
			north.Activated.fire(press)
			t.expect(#picked).toBe(1)
			release(world, press)
			t.expect(#picked).toBe(1)
			local after = touch(world, 320, 110)
			north.InputBegan.fire(after)
			release(world, after)
			north.Activated.fire(after)
			t.expect(#picked).toBe(2)
			world.stop()
			local listPicked = {}
			local opened = Compose.cell(false)
			local listWorld = radial({ isPresented = opened, distribution = "compass", items = compass(listPicked) })
			local launcher = find(listWorld.root, "Launcher")
			local tap = touch(listWorld, 0, 0)
			launcher.InputBegan.fire(tap)
			t.expect(opened:peek()).toBe(true)
			find(listWorld.root, "Modal").AbsoluteSize = V2(listWorld, 420, 200)
			t.expect(presentation(listWorld)).toBe("list")
			release(listWorld, tap)
			launcher.Activated.fire(tap)
			t.expect(opened:peek()).toBe(true)
			t.expect(#listPicked).toBe(0)
			find(listWorld.root, "E").Activated.fire(touch(listWorld, 40, 40))
			t.expect(#listPicked).toBe(1)
			t.expect(listPicked[1]).toBe("E")
			listWorld.input.InputEnded.fire(touch(listWorld, 40, 40))
			t.expect(#listPicked).toBe(1)
			listWorld.stop()
		end
	)

	t.it("keeps the radial ring in a short viewport when gestures select by direction and commits beyond it", function()
		for _, mode in { "direction", "bounded" } do
			local picked = {}
			local world = radial({ distribution = "compass", gestureSelection = mode, items = compass(picked) })
			find(world.root, "Modal").AbsoluteSize = V2(world, 420, 200)
			t.expect(presentation(world)).toBe(if mode == "direction" then "radial" else "list")
			if mode == "direction" then
				local press = touch(world, 210, 100)
				find(world.root, "RadialPanel").InputBegan.fire(press)
				moveTo(world, press, 710, 100)
				t.expect(presentation(world)).toBe("radial")
				t.expect(preview(world)).toBe("E")
				t.expect(#picked).toBe(0)
				release(world, press)
				t.expect(table.concat(picked, ",")).toBe("E")
			end
			world.stop()
		end
	end)

	t.it("cuts the pass-through aperture around a moved anchor and restores capture in the list fallback", function()
		local picked = {}
		local world = radial({
			center = "empty",
			centerPassThrough = true,
			anchor = { x = 200, y = 150 },
			distribution = "compass",
			items = compass(picked),
		})
		local panel = find(world.root, "RadialPanel")
		t.expect(panel.Active).toBe(false)
		t.expect(find(world.root, "DismissOutside").Visible).toBe(false)
		local covered = 0
		for _, edge in { "Top", "Bottom", "Left", "Right" } do
			local catcher = find(world.root, "Dismiss" .. edge)
			t.expect(catcher.Visible).toBe(true)
			local x, y = catcher.Position.X.Offset, catcher.Position.Y.Offset
			local w, h = catcher.Size.X.Offset, catcher.Size.Y.Offset
			t.expect(200 >= x and 200 < x + w and 150 >= y and 150 < y + h).toBe(false)
			covered += w * h
		end
		t.expect(covered).toBe(640 * 480 - 80 * 80)
		local through = touch(world, 200, 150)
		panel.InputBegan.fire(through)
		moveTo(world, through, 200, 20)
		release(world, through)
		t.expect(#picked).toBe(0)
		local ring = touch(world, 200, 60)
		panel.InputBegan.fire(ring)
		release(world, ring)
		t.expect(table.concat(picked, ",")).toBe("N")
		find(world.root, "Modal").AbsoluteSize = V2(world, 180, 180)
		t.expect(presentation(world)).toBe("list")
		t.expect(panel.Active).toBe(true)
		t.expect(find(world.root, "DismissOutside").Visible).toBe(true)
		for _, edge in { "Top", "Bottom", "Left", "Right" } do
			t.expect(find(world.root, "Dismiss" .. edge).Visible).toBe(false)
		end
		world.stop()
	end)

	t.it("settles row action trays at half the tray width and snaps every repeated short swipe closed", function()
		for _, edge in { "trailing", "leading" } do
			local open = Compose.cell(nil :: string?)
			local invoked = 0
			local actions = {
				{
					id = "Pin",
					label = "Pin",
					onActivate = function()
						invoked += 1
					end,
				},
			}
			local world = setup(function(UI, Host)
				return UI.RowActions({
					open = open,
					content = Host.TextLabel({ Text = "Row" }),
					trailing = if edge == "trailing" then actions else nil,
					leading = if edge == "leading" then actions else nil,
				})
			end, {
				clock = function()
					return 0
				end,
			})
			world.node.AbsoluteSize = V2(world, 300, 44)
			local detector = world.node:FindFirstChildWhichIsA("UIDragDetector")
			local sign = if edge == "trailing" then -1 else 1
			local function swipe(distance: number)
				detector.DragStart.fire(V2(world, 150, 20))
				detector.DragContinue.fire(V2(world, 150 + sign * distance, 20))
				detector.DragEnd.fire()
			end
			for _ = 1, 3 do
				swipe(43)
				t.expect(open:peek()).toBeNil()
				t.expect(world.node:FindFirstChild(edge).Visible).toBe(false)
				t.expect(world.node:FindFirstChild("Content").Position.X.Offset).toBe(0)
			end
			swipe(44)
			t.expect(open:peek()).toBe(edge)
			t.expect(world.node:FindFirstChild("Content").Position.X.Offset).toBe(sign * 88)
			swipe(-45)
			t.expect(open:peek()).toBeNil()
			t.expect(world.node:FindFirstChild("Content").Position.X.Offset).toBe(0)
			swipe(88)
			t.expect(open:peek()).toBe(edge)
			swipe(-44)
			t.expect(open:peek()).toBe(edge)
			for _ = 1, 3 do
				open:set(nil)
				swipe(20)
				t.expect(open:peek()).toBeNil()
				t.expect(world.node:FindFirstChild(edge).Visible).toBe(false)
			end
			t.expect(invoked).toBe(0)
			world.stop()
		end
	end)

	t.it("sends ties to the vertical axis, tracks linearly and commits a full swipe at seventy percent", function()
		local policies: { any } = { true, { trailing = false } }
		for _, policy in policies do
			local open = Compose.cell(nil :: string?)
			local invoked = { trailing = 0, leading = 0 }
			local function actionFor(edge: string): any
				return {
					{
						id = edge,
						label = edge,
						onActivate = function()
							invoked[edge] += 1
						end,
					},
				}
			end
			local trailingOnly = Compose.cell(false)
			local world = setup(function(UI, Host)
				return UI.RowActions({
					open = open,
					fullSwipe = policy,
					content = Host.TextLabel({ Text = "Row" }),
					trailing = actionFor("trailing"),
					leading = function(use: any)
						return if use(trailingOnly) then {} else actionFor("leading")
					end,
				})
			end, {
				clock = function()
					return 0
				end,
			})
			world.node.AbsoluteSize = V2(world, 300, 44)
			local detector = world.node:FindFirstChildWhichIsA("UIDragDetector")
			local content = world.node:FindFirstChild("Content")
			local tray = world.node:FindFirstChild("trailing")
			local function swipe(from: number, to: number)
				detector.DragStart.fire(V2(world, from, 20))
				detector.DragContinue.fire(V2(world, to, 20))
				detector.DragEnd.fire()
			end
			detector.DragStart.fire(V2(world, 200, 20))
			detector.DragContinue.fire(V2(world, 190, 30))
			t.expect(content.Position.X.Offset).toBe(0)
			detector.DragContinue.fire(V2(world, 120, 30))
			t.expect(content.Position.X.Offset).toBe(0)
			detector.DragEnd.fire()
			t.expect(open:peek()).toBeNil()
			detector.DragStart.fire(V2(world, 200, 20))
			for _, distance in { 10, 20, 50, 80, 88 } do
				detector.DragContinue.fire(V2(world, 200 - distance, 20))
				t.expect(content.Position.X.Offset).toBe(-distance)
				t.expect(tray.Size.X.Offset).toBe(distance)
				t.expect(tray.Visible).toBe(true)
			end
			detector.DragContinue.fire(V2(world, 200 - 150, 20))
			t.expect(content.Position.X.Offset).toBe(-150)
			t.expect(tray.Size.X.Offset).toBe(88)
			detector.DragContinue.fire(V2(world, 200 - 209, 20))
			detector.DragEnd.fire()
			t.expect(invoked.trailing).toBe(0)
			t.expect(open:peek()).toBe("trailing")
			open:set(nil)
			swipe(250, 250 - 210)
			t.expect(invoked.trailing).toBe(if policy == true then 1 else 0)
			t.expect(open:peek()).toBe(if policy == true then nil else "trailing")
			open:set(nil)
			swipe(290, 0)
			t.expect(invoked.trailing).toBe(if policy == true then 2 else 0)
			open:set(nil)
			swipe(20, 20 + 209)
			t.expect(invoked.leading).toBe(0)
			t.expect(open:peek()).toBe("leading")
			open:set(nil)
			swipe(20, 20 + 210)
			t.expect(invoked.leading).toBe(1)
			t.expect(open:peek()).toBeNil()
			trailingOnly:set(true)
			detector.DragStart.fire(V2(world, 20, 20))
			detector.DragContinue.fire(V2(world, 250, 20))
			t.expect(content.Position.X.Offset).toBe(0)
			detector.DragEnd.fire()
			t.expect(open:peek()).toBeNil()
			t.expect(invoked.leading).toBe(1)
			world.stop()
		end
	end)

	t.it("widens a touch grip and clamps a touch resize to the column minimum and maximum", function()
		local widths: any = Compose.cell({})
		local world = setup(function(UI)
			return UI.Table({
				from = { { id = 1, label = "A" } },
				key = function(item: any)
					return item.id
				end,
				widths = widths,
				columns = { { id = "label", label = "Name", width = 100, minWidth = 60, maxWidth = 160 } },
			})
		end, { preferredInput = "Touch" })
		local column = world.node:FindFirstChild("Header"):FindFirstChild("label")
		column.AbsoluteSize = V2(world, 100, 44)
		local grip = column:FindFirstChild("Resize")
		t.expect(grip.Size.X.Offset).toBe(44)
		t.expect(grip.Size.Y.Scale).toBe(1)
		local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 100, 10))
		detector.DragContinue.fire(V2(world, 70, 12))
		t.expect(widths:peek().label).toBe(70)
		detector.DragContinue.fire(V2(world, 20, 12))
		t.expect(widths:peek().label).toBe(60)
		detector.DragContinue.fire(V2(world, -400, 12))
		t.expect(widths:peek().label).toBe(60)
		detector.DragEnd.fire(V2(world, -400, 12))
		column.AbsoluteSize = V2(world, 60, 44)
		detector.DragStart.fire(V2(world, 60, 10))
		detector.DragContinue.fire(V2(world, 400, 12))
		t.expect(widths:peek().label).toBe(160)
		detector.DragEnd.fire(V2(world, 400, 12))
		t.expect(grip.Size.X.Offset).toBe(44)
		world.stop()
	end)

	t.it("cancels a Rating and a LevelPicker scrub back to its value when the player switches to a gamepad", function()
		local levelCases: { { any } } = { { "Rating" :: any, 5, 3 }, { "LevelPicker" :: any, 10, 2 } }
		for _, case in levelCases do
			local value = Compose.cell(case[3])
			local world = setup(function(UI)
				return UI[case[1]]({ value = value, count = case[2] })
			end, { preferredInput = "Touch" })
			local control = world.node
			control.AbsolutePosition = V2(world, 0, 0)
			control.AbsoluteSize = V2(world, 100, 44)
			local scrub = control:FindFirstChild("Scrub")
			scrub.DragStart.fire(V2(world, 95, 20))
			t.expect(value:peek()).toBe(case[2])
			scrub.DragContinue.fire(V2(world, 55, 20))
			t.expect(value:peek()).toBe(math.floor(0.55 * case[2]) + 1)
			world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
			t.expect(value:peek()).toBe(case[3])
			scrub.DragContinue.fire(V2(world, 95, 20))
			t.expect(value:peek()).toBe(case[3])
			scrub.DragEnd.fire(V2(world, 95, 20))
			control.Activated.fire({
				UserInputType = world.engine.types.Enum.UserInputType.Touch,
				Position = world.engine.types.Vector3.new(95, 20, 0),
			})
			t.expect(value:peek()).toBe(case[3])
			world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
			scrub.DragStart.fire(V2(world, 95, 20))
			scrub.DragEnd.fire(V2(world, 95, 20))
			t.expect(value:peek()).toBe(case[2])
			world.stop()
		end
	end)

	t.it(
		"autoscrolls a reorder only from the edge bands, stops on retraction and release, and clamps both ends",
		function()
			local requests = {}
			local world = setup(function(UI)
				local rows = {}
				for index = 1, 100 do
					rows[index] = { id = index, label = tostring(index) }
				end
				return UI.Table({
					from = rows,
					key = function(item: any)
						return item.id
					end,
					itemSize = 20,
					overscan = 0,
					reorderable = true,
					onReorder = function(keys: any, slot: number)
						table.insert(requests, { keys = keys, slot = slot })
					end,
					columns = { { id = "label", label = "Label", width = 100 } },
				})
			end)
			local engine = world.engine
			local body = world.node:FindFirstChild("Body")
			body.AbsoluteWindowSize = V2(world, 200, 100)
			local function frames(count: number)
				for _ = 1, count do
					engine.heartbeat.fire(1 / 60)
				end
			end
			frames(10)
			t.expect(body.CanvasPosition.Y).toBe(0)
			local handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
			local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
			local press = {
				UserInputType = engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = engine.types.Enum.UserInputState.Begin,
				Position = engine.types.Vector3.new(10, 50, 0),
			}
			handle.InputBegan.fire(press)
			detector.DragStart.fire(V2(world, 10, 50))
			frames(20)
			t.expect(body.CanvasPosition.Y).toBe(0)
			detector.DragContinue.fire(V2(world, 10, 99))
			frames(20)
			local advanced = body.CanvasPosition.Y
			t.expect(advanced > 0).toBe(true)
			local function pointerAt(y: number)
				world.input.InputChanged.fire({
					UserInputType = engine.types.Enum.UserInputType.MouseMovement,
					UserInputState = engine.types.Enum.UserInputState.Change,
					Position = engine.types.Vector3.new(10, y, 0),
				})
			end
			pointerAt(50)
			frames(20)
			t.expect(body.CanvasPosition.Y).toBe(advanced)
			pointerAt(1)
			frames(200)
			t.expect(body.CanvasPosition.Y).toBe(0)
			pointerAt(99)
			frames(2000)
			t.expect(body.CanvasPosition.Y).toBe(100 * 20 - 100)
			world.input.InputEnded.fire(press)
			t.expect(#requests).toBe(1)
			t.expect(requests[1].slot).toBe(99)
			body.CanvasPosition = V2(world, 0, 500)
			frames(60)
			t.expect(body.CanvasPosition.Y).toBe(500)
			world.stop()
		end
	)

	t.it("gives a disabled row no drag session and restores the session when it is enabled again", function()
		local enabled, open = Compose.cell(false), Compose.cell(nil :: string?)
		local world = setup(function(UI, Host)
			return UI.RowActions({
				open = open,
				enabled = enabled,
				content = Host.TextLabel({ Text = "Row" }),
				trailing = { { id = "Save", label = "Save", onActivate = function() end } },
			})
		end, {
			clock = function()
				return 0
			end,
		})
		world.node.AbsoluteSize = V2(world, 300, 44)
		local detector = world.node:FindFirstChildWhichIsA("UIDragDetector")
		local content = world.node:FindFirstChild("Content")
		t.expect(detector.Enabled).toBe(false)
		detector.DragStart.fire(V2(world, 200, 20))
		detector.DragContinue.fire(V2(world, 100, 20))
		t.expect(content.Position.X.Offset).toBe(0)
		detector.DragEnd.fire()
		t.expect(open:peek()).toBeNil()
		enabled:set(true)
		t.expect(detector.Enabled).toBe(true)
		detector.DragStart.fire(V2(world, 200, 20))
		detector.DragContinue.fire(V2(world, 100, 20))
		t.expect(content.Position.X.Offset).toBe(-100)
		detector.DragEnd.fire()
		t.expect(open:peek()).toBe("trailing")
		world.stop()
		local value = Compose.cell(2)
		local levelEnabled = Compose.cell(false)
		local level = setup(function(UI)
			return UI.LevelPicker({ value = value, count = 10, enabled = levelEnabled })
		end)
		level.node.AbsoluteSize = V2(level, 100, 44)
		local scrub = level.node:FindFirstChild("Scrub")
		t.expect(scrub.Enabled).toBe(false)
		scrub.DragStart.fire(V2(level, 95, 20))
		t.expect(value:peek()).toBe(2)
		levelEnabled:set(true)
		t.expect(scrub.Enabled).toBe(true)
		scrub.DragStart.fire(V2(level, 95, 20))
		scrub.DragEnd.fire(V2(level, 95, 20))
		t.expect(value:peek()).toBe(10)
		level.stop()
	end)

	t.it("opens a plain menu when a touch long press begins and only then", function()
		for _, triggers in { false, true } do
			local opened = Compose.cell(false)
			local world = setup(function(UI)
				return UI.Menu({
					label = "Options",
					isPresented = opened,
					triggers = if triggers then { "activate", "secondary", "keyboard", "gamepad" } else nil,
					items = { { id = "Rename", label = "Rename", onSelect = function() end } },
				})
			end, { preferredInput = "Touch" })
			local trigger = find(world.node, "Trigger")
			local states = world.engine.types.Enum.UserInputState
			trigger.TouchLongPress.fire({}, states.Change)
			trigger.TouchLongPress.fire({}, states.End)
			t.expect(opened:peek()).toBe(false)
			trigger.TouchLongPress.fire({}, states.Begin)
			t.expect(opened:peek()).toBe(not triggers)
			if not triggers then
				t.expect(find(world.root, "MenuPanel") ~= nil).toBe(true)
				trigger.TouchLongPress.fire({}, states.End)
				t.expect(opened:peek()).toBe(true)
			end
			world.stop()
		end
	end)

	t.it("resizes a sheet live while its handle is dragged up and snaps to the nearest detent", function()
		local detent = Compose.cell("medium")
		local world = setup(function(UI, Host)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = detent,
				title = "Sheet",
				content = function()
					return Host.Frame("Body")({})
				end,
			})
		end)
		local panel = find(world.root, "SheetPanel")
		local drag = find(find(world.root, "DragHandle"), "UIDragDetector")
		t.expect(panel.Size.Y.Offset).toBe(360)
		drag.DragStart.fire(V2(world, 0, 400))
		drag.DragContinue.fire(V2(world, 0, 200))
		t.expect(panel.Size.Y.Offset).toBe(560)
		t.expect(detent:peek()).toBe("medium")
		drag.DragContinue.fire(V2(world, 0, 100))
		t.expect(panel.Size.Y.Offset).toBe(660)
		drag.DragEnd.fire()
		t.expect(detent:peek()).toBe("large")
		t.expect(panel.Size.Y.Offset).toBe(684)
		drag.DragStart.fire(V2(world, 0, 100))
		drag.DragContinue.fire(V2(world, 0, 250))
		drag.DragEnd.fire()
		t.expect(detent:peek()).toBe("large")
		drag.DragStart.fire(V2(world, 0, 100))
		drag.DragContinue.fire(V2(world, 0, 300))
		drag.DragEnd.fire()
		t.expect(detent:peek()).toBe("medium")
		drag.DragStart.fire(V2(world, 0, 400))
		drag.DragContinue.fire(V2(world, 0, 230))
		drag.DragEnd.fire()
		t.expect(detent:peek()).toBe("large")
		drag.DragStart.fire(V2(world, 0, 400))
		drag.DragContinue.fire(V2(world, 0, 600))
		drag.DragEnd.fire()
		t.expect(detent:peek()).toBe("medium")
		t.expect(panel.Size.Y.Offset).toBe(360)
		world.stop()
	end)
end)

local function resolvedHeight(node: any): number?
	if not node:IsA("GuiObject") then
		return nil
	end
	local size = node.Size
	local height: number
	if size.Y.Scale == 0 then
		height = size.Y.Offset
	else
		local parent = node.Parent
		local above = if parent then resolvedHeight(parent) else nil
		if above == nil then
			return nil
		end
		height = above * size.Y.Scale + size.Y.Offset
	end
	local automatic = node.AutomaticSize
	local grows = automatic ~= nil and (automatic.Name == "Y" or automatic.Name == "XY")
	for _, child in node:GetChildren() do
		if child:IsA("UISizeConstraint") then
			height = math.max(height, child.MinSize.Y)
		elseif grows and child:IsA("GuiObject") and child.Size.Y.Scale == 0 then
			height = math.max(height, resolvedHeight(child) or 0)
		end
	end
	return height
end

local function targets(root: any): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if
			node:IsA("GuiObject")
			and not node:IsA("ScrollingFrame")
			and node.Visible
			and (node.Selectable or ((node:IsA("GuiButton") or node:IsA("TextBox")) and node.Interactable))
		then
			local shown = true
			local cursor = node.Parent
			while cursor and cursor:IsA("GuiObject") do
				if not cursor.Visible then
					shown = false
				end
				cursor = cursor.Parent
			end
			if shown then
				table.insert(found, node)
			end
		end
	end
	return found
end

local function withGame(value: any, body: () -> ())
	local environment: any = getfenv(0)
	local previous = environment.game
	environment.game = value
	local ok, failure = pcall(body :: any)
	environment.game = previous
	if not ok then
		error(failure, 0)
	end
end

local function scrimOf(sheet: any): any
	for _, rule in sheet:GetDescendants() do
		if rule:IsA("StyleRule") and rule.Selector == ".facet-scrim" then
			return rule
		end
	end
	return nil
end

local function sourceFiles(directory: string, into: { string })
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if path ~= "src/vendor" then
				sourceFiles(path, into)
			end
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(into, path)
		end
	end
end

local function compactTheme(): any
	local package: any = Facet.themes.neutralPackage()
	package.metrics.controlSizes.regular.height = 32
	return package
end

t.describe("adaptive environment strength", function()
	t.it("applies the ten-foot console profile facts to native input and engages the gamepad policies", function()
		local perfProfiles = require("../bench/perf_profiles")
		for _, name in { "consoleTenFoot", "desktop" } do
			local profile = perfProfiles.get(name)
			local tenFoot = name == "consoleTenFoot"
			t.expect(profile.displaySize).toBe(if tenFoot then "Large" else profile.displaySize)
			t.expect(profile.overscanInsets.left > 0).toBe(tenFoot)
			local controls: any = {}
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Table({
						from = { { id = 1, label = "A" }, { id = 2, label = "B" } },
						key = function(item: any)
							return item.id
						end,
						controls = controls,
						columns = { { id = "label", label = "Label" } },
					}),
					UI.Picker("Choice")({
						selected = Compose.cell("1"),
						options = {
							{ value = "1", label = "One" },
							{ value = "2", label = "Two" },
							{ value = "3", label = "Three" },
							{ value = "4", label = "Four" },
							{ value = "5", label = "Five" },
						},
					}),
				})
			end, {
				preferredInput = profile.preferredInput,
				config = { theme = compactTheme() },
			})
			t.expect(world.input.PreferredInput).toBe(
				if tenFoot
					then world.engine.types.Enum.PreferredInput.Gamepad
					else world.engine.types.Enum.PreferredInput.KeyboardAndMouse
			)
			find(world.node, "Body").AbsoluteWindowSize = V2(world, 200, 100)
			t.expect(controls.placementOf(2).offset).toBe(if tenFoot then 44 else 40)
			local picker = find(world.node, "Choice")
			picker.AbsoluteSize = V2(world, profile.viewport.w / 2, 44)
			t.expect(find(picker, "Trigger") == nil).toBe(tenFoot)
			t.expect(find(picker, "5") ~= nil).toBe(tenFoot)
			world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
			t.expect(controls.placementOf(2).offset).toBe(40)
			t.expect(find(picker, "Trigger") ~= nil).toBe(true)
			world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
			t.expect(controls.placementOf(2).offset).toBe(44)
			t.expect(find(picker, "Trigger")).toBeNil()
			world.stop()
		end
	end)

	t.it(
		"falls back to a spaced touch list in small space, keeps activation and returns to a ring with its clearance",
		function()
			local picked = {}
			local items = {}
			for _, id in { "a", "b", "c" } do
				table.insert(items, {
					id = id,
					label = "Item " .. id,
					completion = "stay",
					onSelect = function()
						table.insert(picked, id)
					end,
				})
			end
			local world = radial({ clearance = 100, items = items })
			local modal = find(world.root, "Modal")
			modal.AbsoluteSize = V2(world, 320, 300)
			t.expect(presentation(world)).toBe("list")
			local panel = find(world.root, "RadialPanel")
			t.expect(panel.ScrollingEnabled).toBe(true)
			t.expect(panel:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(4)
			for _, id in { "a", "b", "c" } do
				local row = find(world.root, id)
				t.expect(row.Size.Y.Offset).toBe(44)
				t.expect(row.Size.X.Scale).toBe(1)
				t.expect(row.Size.X.Offset).toBe(-8)
				t.expect(row.Parent.Size.Y.Offset).toBe(44)
			end
			find(world.root, "b").Activated.fire(touch(world, 40, 100))
			t.expect(table.concat(picked, ",")).toBe("b")
			world.gui.SelectedObject = find(world.root, "a")
			find(world.root, "a").SelectionGained.fire()
			action(world.root, "Radial-down").Pressed.fire()
			t.expect(world.gui.SelectedObject).toBe(find(world.root, "b"))
			action(world.root, "Radial-down").Pressed.fire()
			t.expect(world.gui.SelectedObject).toBe(find(world.root, "c"))
			modal.AbsoluteSize = V2(world, 920, 640)
			t.expect(presentation(world)).toBe("radial")
			for _, id in { "a", "b", "c" } do
				local x, y = positionOf(find(world.root, id))
				local distance = math.sqrt((x - 460) ^ 2 + (y - 320) ^ 2)
				t.expect(distance >= 100).toBe(true)
			end
			find(world.root, "c").Activated.fire(touch(world, 460, 100))
			t.expect(table.concat(picked, ",")).toBe("b,c")
			world.stop()
		end
	)

	t.it("shows the monitor header actions when they fit and runs them from the menu when they do not", function()
		local Roblox = require("../src/vendor/compose/roblox")
		local modelModule = require("../examples/virtual_monitors/model")
		local screens = require("../examples/virtual_monitors/screens")
		local engine: any = engineLib.new()
		local runtime = Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local lifetime = Compose.createRootOwner(function()
			local model = modelModule.new(Compose)
			Compose.cleanup(model.dispose)
			local views = screens.create(Facet, runtime, {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				reducedMotion = true,
			})
			local stop, discover: any = runtime.mount(views.Discover, target)
			discover.AbsoluteSize = engine.types.Vector2.new(920, 690)
			local chrome, menu = find(discover, "Chrome"), find(discover, "ActionsMenu")
			t.expect(chrome.Visible).toBe(true)
			t.expect(menu.Visible).toBe(false)
			local mode = model.mode:peek()
			find(chrome, "Presentation").Activated.fire()
			t.expect(model.mode:peek() ~= mode).toBe(true)
			find(chrome, "About").Activated.fire()
			t.expect(find(target, "DialogModal") ~= nil).toBe(true)
			find(target, "done").Activated.fire()
			t.expect(find(target, "DialogModal")).toBeNil()
			discover.AbsoluteSize = engine.types.Vector2.new(393, 690)
			t.expect(chrome.Visible).toBe(false)
			t.expect(menu.Visible).toBe(true)
			local function choose(id: string)
				find(menu, "MenuButton").Activated.fire()
				local panel = find(target, "MenuPanel")
				local labels = {}
				for _, node in panel:GetDescendants() do
					if node:IsA("GuiButton") and node.Visible then
						labels[node.Name] = true
					end
				end
				for _, name in { "Presentation", "Appearance", "About" } do
					t.expect(labels[name]).toBe(true)
				end
				find(panel, id).Activated.fire()
			end
			choose("Presentation")
			t.expect(model.mode:peek()).toBe(mode)
			local dark = model.dark:peek()
			choose("Appearance")
			t.expect(model.dark:peek()).toBe(not dark)
			choose("About")
			t.expect(find(target, "DialogModal") ~= nil).toBe(true)
			find(target, "done").Activated.fire()
			discover.AbsoluteSize = engine.types.Vector2.new(920, 690)
			t.expect(chrome.Visible).toBe(true)
			t.expect(menu.Visible).toBe(false)
			stop()
		end, runtime.reactor)
		lifetime.dispose()
		runtime:dispose()
	end)

	t.it("keeps every interactive control target at 44 pixels under touch and gamepad at every text size", function()
		local function item(id: string): any
			return { id = id, label = id, onSelect = function() end }
		end
		local fixtures: { [string]: (any) -> any } = {
			Button = function()
				return { label = "Press", onActivate = function() end }
			end,
			Toggle = function()
				return { value = Compose.cell(false), label = "Music" }
			end,
			TextInput = function()
				return { value = Compose.cell("Query"), presentation = "search", clearButtonMode = "always" }
			end,
			Stepper = function()
				return { value = Compose.cell(1), min = 0, max = 10, label = "Count" }
			end,
			Slider = function()
				return { value = Compose.cell(0.5), label = "Volume" }
			end,
			Rating = function()
				return { value = Compose.cell(2) }
			end,
			LevelPicker = function()
				return { value = Compose.cell(2) }
			end,
			Chip = function()
				return { label = "Chip", onRemove = function() end }
			end,
			Avatar = function()
				return { name = "Ada", onActivate = function() end }
			end,
			Menu = function()
				return { label = "Options", isPresented = Compose.cell(true), items = { item("Alpha"), item("Beta") } }
			end,
			Picker = function()
				return {
					selected = Compose.cell("a"),
					style = "segmented",
					options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
				}
			end,
			SplitButton = function()
				return { label = "Action", onActivate = function() end, items = { item("Alpha") } }
			end,
			DisclosureGroup = function(Host)
				return {
					label = "Details",
					expanded = Compose.cell(true),
					content = function()
						return Host.TextLabel({ Text = "Body" })
					end,
				}
			end,
			TabView = function(Host)
				local function tab(id: string): any
					return {
						id = id,
						label = id,
						content = function()
							return Host.TextLabel({ Text = id })
						end,
					}
				end
				return { selection = Compose.cell("a"), tabs = { tab("a"), tab("b") } }
			end,
			PageView = function(Host)
				local function page(id: string): any
					return {
						id = id,
						title = id,
						content = function()
							return Host.TextLabel({ Text = id })
						end,
					}
				end
				return { selection = Compose.cell("a"), pages = { page("a"), page("b") } }
			end,
			Alert = function()
				return {
					title = "Confirm",
					message = "Continue?",
					isPresented = Compose.cell(true),
					actions = { { id = "ok", label = "OK" }, { id = "cancel", label = "Cancel", role = "cancel" } },
				}
			end,
			Sheet = function(Host)
				return {
					title = "Sheet",
					detent = Compose.cell("medium"),
					isPresented = Compose.cell(true),
					content = function()
						return Host.TextLabel({ Text = "Body" })
					end,
				}
			end,
			RowActions = function(Host)
				return {
					content = function()
						return Host.TextLabel({ Text = "Row" })
					end,
					trailing = {
						{ id = "delete", label = "Delete", role = "destructive", onActivate = function() end },
					},
					open = Compose.cell("trailing"),
				}
			end,
		}
		local names = {}
		for name in fixtures do
			table.insert(names, name)
		end
		table.sort(names)
		local failures = {}
		for _, name in names do
			for _, kind in { "Touch", "Gamepad" } do
				local world = setup(function(UI, Host)
					return Host.Frame({ UI[name](fixtures[name](Host)) })
				end, { preferredInput = kind })
				for _, child in world.node:GetChildren() do
					if child:IsA("GuiObject") then
						child.AbsoluteSize = V2(world, 300, 44)
					end
				end
				local found = targets(world.root)
				t.expect(`{name}:{#found > 0}`).toBe(`{name}:true`)
				for _, bounds in { V2(world, 0, 0), V2(world, 400, 90), V2(world, 12, 6) } do
					for _, node in world.root:GetDescendants() do
						if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
							node.TextBounds = bounds
						end
					end
					for _, node in found do
						local height = resolvedHeight(node)
						if height ~= nil and height < 44 then
							table.insert(failures, `{name}/{kind}/{node.Name}: {height}`)
						end
					end
				end
				world.stop()
			end
		end
		t.expect(table.concat(failures, "; ")).toBe("")
	end)

	t.it(
		"keeps controls legal and mounted through seeded preferred-input, transparency, motion and garbage bound storms",
		function()
			local inputs = engineLib.new().types.Enum.PreferredInput:GetEnumItems()
			for seed = 1, 20 do
				local state = 917359 + seed
				local function nextInteger(low: number, high: number): number
					state = (state * 16807) % 2147483647
					return low + state % (high - low + 1)
				end
				local value = Compose.cell(0.5)
				local controls: any = {}
				local sheet: any
				local current: any
				local services = {
					GetService = function(_: any, name: string)
						return if name == "GuiService" then current else nil
					end,
				}
				local world: World
				withGame(services, function()
					world = setup(function(UI, Host, engine, gui, runtime)
						current = gui
						sheet = Facet.themes.createStyleSheet(
							runtime,
							Facet.themes.neutralPackage(),
							{ types = engine.types }
						)
						return Host.Frame({
							sheet,
							UI.Table({
								from = { { id = 1, label = "A" }, { id = 2, label = "B" }, { id = 3, label = "C" } },
								key = function(item: any)
									return item.id
								end,
								controls = controls,
								columns = { { id = "label", label = "Label" } },
							}),
							UI.Slider("Volume")({ value = value }),
							UI.Alert({
								title = "Confirm",
								message = "Continue?",
								isPresented = Compose.cell(true),
								actions = { { id = "ok", label = "OK" } },
							}),
						})
					end, { config = { theme = compactTheme() } })
				end)
				local scrim = scrimOf(sheet)
				local body = find(world.node, "Body")
				body.AbsoluteWindowSize = V2(world, 200, 200)
				local rows = {}
				for index = 1, 3 do
					rows[index] = body:FindFirstChild(tostring(index), true)
				end
				local slider = find(world.node, "Volume")
				local track = find(slider, "Track")
				local catcher = find(world.root, "DismissOutside")
				local garbage: { any } = { -5, 0, 0.4, 7, 0 / 0, math.huge, -math.huge }
				local extents: { number } = { -5, 0, 0.4, 7, 0 / 0, 200 }
				for _ = 1, 30 do
					local kind = inputs[nextInteger(1, #inputs)]
					local drag = track and track:FindFirstChildWhichIsA("UIDragDetector")
					if drag and nextInteger(0, 1) == 1 then
						track.AbsolutePosition = V2(world, 0, 0)
						track.AbsoluteSize = V2(world, 200, 44)
						drag.DragStart.fire(V2(world, nextInteger(0, 200), 20))
					end
					world.input.PreferredInput = kind
					world.gui.PreferredTransparency = garbage[nextInteger(1, #garbage)]
					world.gui.ReducedMotionEnabled = nextInteger(0, 1) == 1
					body.AbsoluteWindowSize = V2(world, extents[nextInteger(1, #extents)], 200)
					if drag then
						drag.DragEnd.fire(V2(world, 100, 20))
					end
					local expected = if kind == world.engine.types.Enum.PreferredInput.Touch
							or kind == world.engine.types.Enum.PreferredInput.Gamepad
						then 44
						else 40
					t.expect(controls.placementOf(2).offset).toBe(expected)
					for index = 1, 3 do
						t.expect(body:FindFirstChild(tostring(index), true)).toBe(rows[index])
					end
					t.expect(find(world.node, "Volume")).toBe(slider)
					local current = value:peek()
					t.expect(current == current and current >= 0 and current <= 1).toBe(true)
					local transparency = scrim:GetProperties().BackgroundTransparency
					t.expect(transparency == transparency and transparency >= 0 and transparency <= 1).toBe(true)
					t.expect(find(world.root, "DismissOutside")).toBe(catcher)
					t.expect(catcher:HasTag("facet-scrim")).toBe(true)
				end
				world.stop()
				local picked = {}
				local ring = radial({ distribution = "compass", items = compass(picked) })
				local modal = find(ring.root, "Modal")
				local north = find(ring.root, "N")
				for _ = 1, 10 do
					modal.AbsoluteSize =
						V2(ring, extents[nextInteger(1, #extents)] * 100, extents[nextInteger(1, #extents)] * 100)
					local shown = presentation(ring)
					t.expect(shown == "radial" or shown == "list").toBe(true)
					t.expect(find(ring.root, "N")).toBe(north)
				end
				north.Activated.fire()
				t.expect(table.concat(picked, ",")).toBe("N")
				ring.stop()
			end
		end
	)

	t.it("keeps device names and platform branches out of the framework and example sources", function()
		local files = {}
		sourceFiles("src", files)
		sourceFiles("examples", files)
		t.expect(#files > 50).toBe(true)
		local found = {}
		for _, file in files do
			local source = string.lower(fs.readFile(file))
			for _, device in
				{ "iphone", "ipad", "android", "xbox", "playstation", "nintendo", "macos", "windows", "ios", "tvos" }
			do
				if string.find(source, "%f[%w]" .. device .. "%f[%W]") ~= nil then
					table.insert(found, file .. ":" .. device)
				end
			end
			for _, api in { "getplatform", "enum.platform", "getdevice" } do
				if string.find(source, api, 1, true) ~= nil then
					table.insert(found, file .. ":" .. api)
				end
			end
		end
		t.expect(table.concat(found, ", ")).toBe("")
	end)

	t.it("resolves an automatic picker from width, option shape and every preferred input", function()
		local function options(count: number, described: boolean): { any }
			local list = {}
			for index = 1, count do
				list[index] = {
					value = tostring(index),
					label = "Option " .. index,
					description = if described then "Detail" else nil,
				}
			end
			return list
		end
		local cases: { { any } } = {
			{ 2, false, 400, "KeyboardAndMouse", "segmented" },
			{ 2, false, 400, "Touch", "segmented" },
			{ 2, false, 400, "Gamepad", "segmented" },
			{ 2, false, 240, "KeyboardAndMouse", "menu" },
			{ 2, false, 240, "Touch", "menu" },
			{ 2, false, 240, "Gamepad", "inline" },
			{ 5, false, 400, "KeyboardAndMouse", "menu" },
			{ 5, false, 400, "Touch", "menu" },
			{ 5, false, 400, "Gamepad", "inline" },
			{ 7, false, 400, "Gamepad", "menu" },
			{ 3, true, 400, "KeyboardAndMouse", "menu" },
			{ 3, true, 400, "Gamepad", "inline" },
		}
		for _, case in cases do
			local selected = Compose.cell("1")
			local world = setup(function(UI)
				return UI.Picker({ selected = selected, options = options(case[1], case[2]) })
			end, { preferredInput = case[4] })
			world.node.AbsoluteSize = V2(world, case[3], 44)
			local presented = find(world.node, "Presentation")
			local trigger = find(world.node, "Trigger")
			local style = if trigger
				then "menu"
				elseif presented and presented:HasTag("facet-segmented") then "segmented"
				else "inline"
			t.expect(`{case[1]}/{case[3]}/{case[4]}={style}`).toBe(`{case[1]}/{case[3]}/{case[4]}={case[5]}`)
			if style ~= "menu" then
				find(world.node, "2").Activated.fire()
				t.expect(selected:peek()).toBe("2")
			end
			world.stop()
		end
		local query = setup(function(UI)
			return UI.Picker({ selected = Compose.cell("1"), query = Compose.cell(""), options = options(2, false) })
		end, { preferredInput = "Gamepad" })
		query.node.AbsoluteSize = V2(query, 400, 44)
		t.expect(find(query.node, "5")).toBeNil()
		t.expect(find(query.node, "Presentation"):HasTag("facet-segmented")).toBe(false)
		query.stop()
	end)

	t.it("follows GuiService transparency and motion preferences from attach and live without wiring", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		gui.PreferredTransparency = 0.5
		gui.ReducedMotionEnabled = true
		local services = {
			GetService = function(_: any, name: string)
				return if name == "GuiService" then gui else nil
			end,
		}
		local sheet: any
		local stop: any
		withGame(services, function()
			stop = runtime.mount(function()
				sheet = Facet.themes.createStyleSheet(runtime, Facet.themes.neutralPackage(), { types = engine.types })
				return runtime.constructors.Folder({ sheet })
			end, engine.new("Folder"))
		end)
		local scrim = scrimOf(sheet)
		local authored = 0.55
		t.expect(math.abs(scrim:GetProperties().BackgroundTransparency - authored * 0.5) < 1e-6).toBe(true)
		t.expect(scrim:GetPropertyTransitions().BackgroundTransparency.Time).toBe(0)
		gui.PreferredTransparency = 0
		t.expect(scrim:GetProperties().BackgroundTransparency).toBe(0)
		gui.PreferredTransparency = 1
		t.expect(math.abs(scrim:GetProperties().BackgroundTransparency - authored) < 1e-6).toBe(true)
		gui.ReducedMotionEnabled = false
		t.expect(scrim:GetPropertyTransitions().BackgroundTransparency.Time > 0).toBe(true)
		t.expect(gui:GetPropertyChangedSignal("PreferredTransparency").count()).toBe(1)
		t.expect(gui:GetPropertyChangedSignal("ReducedMotionEnabled").count()).toBe(1)
		stop()
		t.expect(gui:GetPropertyChangedSignal("PreferredTransparency").count()).toBe(0)
		t.expect(gui:GetPropertyChangedSignal("ReducedMotionEnabled").count()).toBe(0)
		local explicit: any
		withGame(services, function()
			local stopExplicit = runtime.mount(function()
				explicit = Facet.themes.createStyleSheet(
					runtime,
					Facet.themes.neutralPackage(),
					{ types = engine.types, preferredTransparency = 1, reducedMotion = false }
				)
				return runtime.constructors.Folder({ explicit })
			end, engine.new("Folder"))
			t.expect(gui:GetPropertyChangedSignal("PreferredTransparency").count()).toBe(0)
			gui.PreferredTransparency = 0
			t.expect(math.abs(scrimOf(explicit):GetProperties().BackgroundTransparency - authored) < 1e-6).toBe(true)
			stopExplicit()
		end)
		runtime:dispose()
	end)
end)

return t
