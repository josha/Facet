--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

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

local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local root = engine.new("ScreenGui")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		userInputService = input,
		inputParent = root,
		reducedMotion = true,
	}
	for field, value in (options or {}) :: { [string]: any } do
		config[field] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, node = runtime.mount(function()
		return build(UI, Host, engine, runtime)
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

local function find(root: any, name: string): any
	if root == nil then
		return nil
	end
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

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

local function records(count: number): { { id: number, label: string } }
	local values = {}
	for index = 1, count do
		values[index] = { id = index, label = tostring(index) }
	end
	return values
end

local function key(item: any): number
	return item.id
end

local function drag(world: World, detector: any, fromX: number, toX: number, y: number?)
	detector.DragStart.fire(V2(world, fromX, y or 20))
	detector.DragContinue.fire(V2(world, toX, y or 20))
	detector.DragEnd.fire()
end

local function rowActionsIn(node: any): any
	if node == nil then
		return nil
	end
	if node:HasTag("facet-rowactions") then
		return node
	end
	for _, child in node:GetDescendants() do
		if child:HasTag("facet-rowactions") then
			return child
		end
	end
	return nil
end

local function textOf(node: any): string
	if node:IsA("TextButton") or node:IsA("TextLabel") then
		if node.Text ~= "" then
			return node.Text
		end
	end
	for _, child in node:GetDescendants() do
		if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.Text ~= "" then
			return child.Text
		end
	end
	return ""
end

local function trailingAction(invoked: { string }, id: string, role: string?, enabled: any?): any
	return {
		id = id,
		label = id,
		role = role,
		enabled = enabled,
		onActivate = function()
			table.insert(invoked, id)
		end,
	}
end

local function mountGallery(path: string): (any, any, World)
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("ScreenGui")
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		guiService = gui,
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = viewport,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				userInputService = input,
				inputParent = target,
				reducedMotion = true,
			} :: any
		),
	}
	local built
	local stop, node = runtime.mount(function()
		built = (require :: any)(path).build(ctx)
		return built.screen()
	end, target)
	local world: World = {
		engine = engine,
		runtime = runtime,
		UI = ctx.UI,
		Host = ctx.Host,
		gui = gui,
		input = input,
		root = target,
		node = node,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
	return built, node, world
end

t.describe("native parity weaker rows", function()
	t.it("collections-53 passes through without actions, reveals only filled edges and tracks the tray", function()
		local open, trailing = Compose.cell(nil :: string?), Compose.cell({} :: { any })
		local world = setup(function(UI)
			return UI.RowActions({
				open = open,
				content = UI.Button("Action")({ label = "Row" }),
				trailing = trailing,
			})
		end)
		local row = world.node
		row.AbsoluteSize = V2(world, 300, 40)
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		local content = find(row, "Content")
		t.expect(detector.Enabled).toBe(false)
		drag(world, detector, 200, 20)
		t.expect(open:peek()).toBeNil()
		t.expect(content.Position.X.Offset).toBe(0)
		t.expect(find(row, "leading").Visible).toBe(false)
		t.expect(find(row, "trailing").Visible).toBe(false)
		world.input.IsKeyDown = function()
			return false
		end
		row.InputBegan.fire({ UserInputType = world.engine.types.Enum.UserInputType.MouseButton2 })
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		local invoked = {}
		trailing:set({
			{ id = "Save", label = "Save" },
			{ id = "Pin", label = "Pin", icon = "rbxassetid://7" },
			trailingAction(invoked, "Erase", "destructive"),
		})
		t.expect(detector.Enabled).toBe(true)
		t.expect(find(row, "trailing").Visible).toBe(false)
		open:set("leading")
		t.expect(open:peek()).toBeNil()
		t.expect(content.Position.X.Offset).toBe(0)
		t.expect(find(row, "leading").Visible).toBe(false)
		open:set("trailing")
		t.expect(find(row, "trailing").Visible).toBe(true)
		t.expect(content.Position.X.Offset).toBe(-264)
		t.expect(find(row, "trailing").Size.X.Offset).toBe(264)
		local save = find(find(row, "trailing"), "Save")
		t.expect(save.Size.X.Scale).toBeCloseTo(1 / 3, 0.001)
		t.expect(textOf(save)).toBe("Save")
		t.expect(find(save, "LeadingIcon")).toBeNil()
		local pin = find(find(row, "trailing"), "Pin")
		t.expect(find(pin, "LeadingIcon").Image).toBe("rbxassetid://7")
		t.expect(textOf(pin)).toBe("Pin")
		open:set(nil)
		t.expect(content.Position.X.Offset).toBe(0)
		t.expect(find(row, "trailing").Visible).toBe(false)
		detector.DragStart.fire(V2(world, 250, 20))
		detector.DragContinue.fire(V2(world, 230, 20))
		t.expect(find(row, "trailing").Size.X.Offset).toBe(20)
		t.expect(content.Position.X.Offset).toBe(-20)
		detector.DragContinue.fire(V2(world, 150, 20))
		t.expect(find(row, "trailing").Size.X.Offset).toBe(100)
		t.expect(content.Position.X.Offset).toBe(-100)
		detector.DragContinue.fire(V2(world, 0, 20))
		t.expect(find(row, "trailing").Size.X.Offset).toBe(250)
		t.expect(find(row, "leading").Visible).toBe(false)
		detector.DragContinue.fire(V2(world, 500, 20))
		t.expect(content.Position.X.Offset).toBe(0)
		detector.DragEnd.fire()
		t.expect(open:peek()).toBeNil()
		t.expect(#invoked).toBe(0)
		world.stop()
	end)

	t.it("collections-53 animates a reveal over frames, snaps under reduced motion and leaks nothing", function()
		for _, reduced in { false, true } do
			local open = Compose.cell(nil :: string?)
			local world = setup(function(UI)
				return UI.RowActions({
					open = open,
					reducedMotion = reduced,
					content = UI.Button("Action")({ label = "Row" }),
					trailing = { { id = "Save", label = "Save" } },
				})
			end, { reducedMotion = false })
			local row = world.node
			row.AbsoluteSize = V2(world, 300, 40)
			world.engine.heartbeat.fire(1)
			local content = find(row, "Content")
			open:set("trailing")
			if reduced then
				t.expect(content.Position.X.Offset).toBe(-88)
			else
				t.expect(content.Position.X.Offset).toBe(0)
				local previous = 0
				local frames = 0
				for _ = 1, 120 do
					world.engine.heartbeat.fire(1 / 60)
					local now = content.Position.X.Offset
					t.expect(now <= previous).toBe(true)
					if now ~= -88 then
						frames += 1
					end
					previous = now
				end
				t.expect(frames > 2).toBe(true)
				t.expect(content.Position.X.Offset).toBeCloseTo(-88, 0.5)
				open:set(nil)
				world.engine.heartbeat.fire(1 / 60)
				t.expect(content.Position.X.Offset < 0).toBe(true)
			end
			local made = {}
			for _, node in world.engine.made do
				made[node] = true
			end
			world.stop()
			world.engine.heartbeat.fire(1 / 60)
			for node in made do
				if node:IsA("GuiObject") then
					t.expect(node:isDestroyed()).toBe(true)
				end
			end
		end
	end)

	t.it("collections-57 runs a tray action once from touch, keyboard and gamepad and closes the tray", function()
		local E = nil :: any
		for _, route in { "touch", "keyboard", "gamepad", "mouse" } do
			local open, invoked = Compose.cell("trailing" :: string?), {}
			local world = setup(function(UI)
				return UI.RowActions({
					open = open,
					content = UI.Button("Action")({ label = "Row" }),
					trailing = { trailingAction(invoked, "Save"), trailingAction(invoked, "Flag") },
				})
			end)
			E = world.engine.types.Enum
			local row = world.node
			row.AbsoluteSize = V2(world, 300, 40)
			local save = find(find(row, "trailing"), "Save")
			t.expect(find(row, "trailing").Visible).toBe(true)
			if route == "keyboard" then
				world.gui.SelectedObject = save
				local activate = action(world.root, "Activate")
				t.expect(activate ~= nil).toBe(true)
				activate.Pressed.fire()
			else
				local inputType = if route == "touch"
					then E.UserInputType.Touch
					elseif route == "gamepad" then E.UserInputType.Gamepad1
					else E.UserInputType.MouseButton1
				save.Activated.fire({ UserInputType = inputType, UserInputState = E.UserInputState.End }, 1)
			end
			t.expect(invoked).toEqual({ "Save" })
			t.expect(open:peek()).toBeNil()
			t.expect(find(row, "trailing").Visible).toBe(false)
			t.expect(find(row, "Content").Position.X.Offset).toBe(0)
			world.stop()
		end
	end)

	t.it("collections-61 shows the minus only while editing a destructive row and deletes once from it", function()
		local invoked = {}
		local editing = Compose.cell(false)
		local open = Compose.cell(nil :: string?)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.RowActions("Unwired")({
					content = UI.Button({ label = "Unwired" }),
					trailing = { trailingAction(invoked, "Unwired", "destructive") },
				}),
				UI.RowActions("Plain")({
					editing = editing,
					content = UI.Button({ label = "Plain" }),
					trailing = { trailingAction(invoked, "Archive") },
				}),
				UI.RowActions("Edited")({
					editing = editing,
					open = open,
					fullSwipe = false,
					content = UI.Button("Action")({ label = "Edited" }),
					trailing = {
						trailingAction(invoked, "Archive"),
						{
							id = "Erase",
							label = "Erase this row",
							role = "destructive",
							onActivate = function()
								table.insert(invoked, "Erase")
							end,
						},
					},
				}),
				UI.RowActions("LeadingOnly")({
					editing = editing,
					content = UI.Button({ label = "Leading" }),
					leading = { trailingAction(invoked, "Drop", "destructive") },
				}),
			})
		end)
		local unwired, plain, edited, leadingOnly =
			find(world.node, "Unwired"),
			find(world.node, "Plain"),
			find(world.node, "Edited"),
			find(world.node, "LeadingOnly")
		for _, row in { unwired, plain, edited, leadingOnly } do
			row.AbsoluteSize = V2(world, 300, 40)
		end
		for _, row in { unwired, plain, edited, leadingOnly } do
			t.expect(row:FindFirstChild("Delete")).toBeNil()
		end
		editing:set(true)
		t.expect(unwired:FindFirstChild("Delete")).toBeNil()
		t.expect(plain:FindFirstChild("Delete")).toBeNil()
		t.expect(find(plain, "Content").Position.X.Offset).toBe(72)
		local minus = edited:FindFirstChild("Delete")
		t.expect(minus ~= nil).toBe(true)
		t.expect(minus.Text).toBe("Erase this row")
		t.expect(find(edited, "Content").Position.X.Offset).toBe(72)
		t.expect(find(edited, "Content").Size.X.Offset).toBe(-72)
		local detector = edited:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		drag(world, detector, 290, 5)
		t.expect(open:peek()).toBe("trailing")
		t.expect(#invoked).toBe(0)
		editing:set(false)
		t.expect(open:peek()).toBe("trailing")
		t.expect(edited:FindFirstChild("Delete")).toBeNil()
		t.expect(find(edited, "Content").Position.X.Offset).toBe(-176)
		open:set(nil)
		editing:set(true)
		minus = edited:FindFirstChild("Delete")
		minus.Activated.fire()
		minus.Activated.fire()
		t.expect(invoked).toEqual({ "Erase" })
		world.engine.heartbeat.fire(1 / 60)
		world.gui.SelectedObject = edited:FindFirstChild("Delete")
		local activate = action(world.root, "Activate")
		t.expect(activate ~= nil).toBe(true)
		activate.Pressed.fire()
		t.expect(invoked).toEqual({ "Erase", "Erase" })
		world.engine.heartbeat.fire(1 / 60)
		leadingOnly:FindFirstChild("Delete").Activated.fire()
		t.expect(invoked).toEqual({ "Erase", "Erase", "Drop" })
		world.stop()
	end)

	t.it("collections-88 keeps an irrevocable commit running through close attempts and new gestures", function()
		local invoked, open, coordinator = 0, Compose.cell("trailing" :: string?), Compose.cell(nil :: any)
		local world = setup(function(UI)
			return UI.RowActions({
				open = open,
				coordinator = coordinator,
				content = UI.Button("Action")({ label = "Row" }),
				trailing = {
					{
						id = "Delete",
						label = "Delete",
						role = "destructive",
						onActivate = function()
							invoked += 1
						end,
					},
				},
			})
		end, { reducedMotion = false })
		local row = world.node
		row.AbsoluteSize = V2(world, 300, 40)
		world.engine.heartbeat.fire(1)
		local content = find(row, "Content")
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		find(row, "Delete").Activated.fire()
		t.expect(invoked).toBe(0)
		t.expect(detector.Enabled).toBe(false)
		open:set(nil)
		coordinator:set({})
		world.gui.SelectedObject = find(row, "Action")
		t.expect(action(world.root, "RowActionsClose")).toBeNil()
		t.expect(action(world.root, "RowActionsDelete")).toBeNil()
		detector.DragStart.fire(V2(world, 20, 20))
		detector.DragContinue.fire(V2(world, 280, 20))
		detector.DragEnd.fire()
		world.engine.heartbeat.fire(0.1)
		t.expect(content.Position.X.Offset < -88).toBe(true)
		t.expect(invoked).toBe(0)
		local lowest = row.Size.Y.Offset
		for _ = 1, 30 do
			world.engine.heartbeat.fire(1 / 60)
			lowest = math.min(lowest, row.Size.Y.Offset)
		end
		t.expect(invoked).toBe(1)
		t.expect(lowest).toBe(0)
		for _ = 1, 30 do
			world.engine.heartbeat.fire(1 / 60)
		end
		t.expect(invoked).toBe(1)
		world.stop()
	end)

	t.it("collections-76 lets one of two real list rows stay open and releases the claim on removal", function()
		local coordinator = Compose.cell(nil :: any)
		local source = Compose.cell(records(3))
		local world = setup(function(UI)
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 44,
				render = function(current)
					return UI.RowActions({
						coordinator = coordinator,
						content = UI.Button("Action")({
							label = function(use)
								return use(current).label
							end,
						}),
						trailing = { { id = "Save", label = "Save" } },
					})
				end,
			})
		end)
		world.node.AbsoluteWindowSize = V2(world, 300, 200)
		local function row(rowKey: number): any
			local node = rowActionsIn(world.node:FindFirstChild(tostring(rowKey), true))
			if node then
				node.AbsoluteSize = V2(world, 300, 44)
			end
			return node
		end
		local function swipe(rowKey: number)
			drag(
				world,
				row(rowKey):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
				250,
				150
			)
		end
		local function opened(rowKey: number): boolean
			return find(row(rowKey), "trailing").Visible
		end
		swipe(1)
		t.expect(opened(1)).toBe(true)
		swipe(2)
		t.expect(opened(1)).toBe(false)
		t.expect(opened(2)).toBe(true)
		t.expect(opened(3)).toBe(false)
		t.expect(coordinator:peek() ~= nil).toBe(true)
		source:set({ records(3)[1], records(3)[3] })
		t.expect(world.node:FindFirstChild("2", true)).toBeNil()
		t.expect(coordinator:peek()).toBeNil()
		swipe(3)
		t.expect(opened(3)).toBe(true)
		t.expect(opened(1)).toBe(false)
		world.stop()
	end)

	t.it("collections-65 slides, opens, commits, closes and coordinates swipes on real table rows", function()
		local invoked = {}
		local world = setup(function(UI)
			return UI.Table({
				from = records(4),
				key = key,
				itemSize = 44,
				columns = { { id = "label", label = "Label", width = 100 } },
				rowActions = function(_, rowKey)
					return {
						leading = { trailingAction(invoked, "Pin" .. rowKey) },
						trailing = {
							trailingAction(invoked, "Archive" .. rowKey),
							trailingAction(invoked, "Flag" .. rowKey),
						},
					}
				end,
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 300, 200)
		local function row(rowKey: number): any
			local node = rowActionsIn(body:FindFirstChild(tostring(rowKey), true))
			node.AbsoluteSize = V2(world, 300, 44)
			return node
		end
		local first = row(1)
		local content = find(first, "Content")
		local detector = first:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 250, 20))
		local previous = 0
		for _, x in { 240, 225, 205, 180, 160 } do
			detector.DragContinue.fire(V2(world, x, 20))
			t.expect(content.Position.X.Offset < previous).toBe(true)
			previous = content.Position.X.Offset
		end
		t.expect(find(first, "trailing").Visible).toBe(true)
		detector.DragEnd.fire()
		t.expect(content.Position.X.Offset).toBe(-176)
		detector.DragStart.fire(V2(world, 100, 20))
		detector.DragContinue.fire(V2(world, 220, 20))
		detector.DragEnd.fire()
		t.expect(content.Position.X.Offset).toBe(0)
		t.expect(find(first, "trailing").Visible).toBe(false)
		detector.DragStart.fire(V2(world, 150, 20))
		detector.DragContinue.fire(V2(world, 145, 80))
		detector.DragContinue.fire(V2(world, 100, 120))
		t.expect(content.Position.X.Offset).toBe(0)
		detector.DragEnd.fire()
		t.expect(content.Position.X.Offset).toBe(0)
		drag(world, detector, 50, 110)
		t.expect(find(first, "leading").Visible).toBe(true)
		t.expect(content.Position.X.Offset).toBe(88)
		world.gui.SelectedObject = find(first.Parent, "RowHit")
		local close = action(world.root, "RowActionsClose")
		t.expect(close ~= nil).toBe(true)
		close.Pressed.fire()
		t.expect(content.Position.X.Offset).toBe(0)
		local second = row(2)
		drag(world, detector, 250, 150)
		t.expect(find(first, "trailing").Visible).toBe(true)
		drag(world, second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
		t.expect(find(first, "trailing").Visible).toBe(false)
		t.expect(find(second, "trailing").Visible).toBe(true)
		t.expect(#invoked).toBe(0)
		drag(world, row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 290, 10)
		t.expect(invoked).toEqual({ "Archive3" })
		t.expect(find(row(3), "trailing").Visible).toBe(false)
		world.engine.heartbeat.fire(1 / 60)
		t.expect(invoked).toEqual({ "Archive3" })
		world.stop()
	end)

	t.it("collections-67 forwards table editing into hosted rows and deletes the row its minus belongs to", function()
		local deleted, editing = {}, Compose.cell(false)
		local world = setup(function(UI)
			return UI.Table({
				from = records(3),
				key = key,
				itemSize = 44,
				editing = editing,
				columns = { { id = "label", label = "Label", width = 100 } },
				rowActions = function(_, rowKey)
					if rowKey == 3 then
						return { trailing = { { id = "Flag", label = "Flag" } } }
					end
					return {
						trailing = {
							{
								id = "Remove",
								label = "Remove row " .. rowKey,
								role = "destructive",
								onActivate = function()
									table.insert(deleted, rowKey)
								end,
							},
						},
					}
				end,
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 300, 200)
		local function row(rowKey: number): any
			local node = rowActionsIn(body:FindFirstChild(tostring(rowKey), true))
			node.AbsoluteSize = V2(world, 300, 44)
			return node
		end
		for rowKey = 1, 3 do
			t.expect(row(rowKey):FindFirstChild("Delete")).toBeNil()
		end
		editing:set(true)
		t.expect(row(3):FindFirstChild("Delete")).toBeNil()
		local minus = row(2):FindFirstChild("Delete")
		t.expect(minus.Text).toBe("Remove row 2")
		t.expect(row(1):FindFirstChild("Delete").Text).toBe("Remove row 1")
		minus.Activated.fire()
		minus.Activated.fire()
		t.expect(deleted).toEqual({ 2 })
		editing:set(false)
		t.expect(row(1):FindFirstChild("Delete")).toBeNil()
		t.expect(deleted).toEqual({ 2 })
		world.stop()
	end)

	t.it("collections-168 wraps only table rows whose callback returns actions", function()
		local world = setup(function(UI)
			return UI.Table({
				from = records(4),
				key = key,
				itemSize = 44,
				columns = { { id = "label", label = "Label", width = 100 } },
				rowActions = function(_, rowKey)
					if rowKey % 2 == 0 then
						return nil
					end
					return { trailing = { { id = "Save", label = "Save" } } }
				end,
			})
		end)
		local body = find(world.node, "Body")
		body.AbsoluteWindowSize = V2(world, 300, 200)
		for rowKey = 1, 4 do
			local node = body:FindFirstChild(tostring(rowKey), true)
			local wrapped = rowActionsIn(node)
			if rowKey % 2 == 0 then
				t.expect(wrapped).toBeNil()
				t.expect(node:FindFirstChildWhichIsA("UIDragDetector", true)).toBeNil()
				t.expect(find(node, "RowHit") ~= nil).toBe(true)
				t.expect(find(node, "Value").Text).toBe(tostring(rowKey))
			else
				t.expect(wrapped ~= nil).toBe(true)
				t.expect(wrapped:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector") ~= nil)
					.toBe(true)
				t.expect(find(find(wrapped, "Content"), "Value").Text).toBe(tostring(rowKey))
			end
		end
		world.stop()
	end)

	t.it("collections-11 reorders list rows by pointer both ways and leaves plain rows to native panning", function()
		local requests = {}
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.VirtualList("Ordered")({
					from = records(6),
					key = key,
					itemSize = 20,
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(requests, { keys = keys, slot = slot })
					end,
					render = function(current)
						return UI.Button("Action")({
							label = function(use)
								return use(current).label
							end,
						})
					end,
				}),
				UI.VirtualList("Plain")({
					from = records(6),
					key = key,
					itemSize = 20,
					render = function(current)
						return UI.Button("Action")({
							label = function(use)
								return use(current).label
							end,
						})
					end,
				}),
			})
		end)
		local ordered, plain = find(world.node, "Ordered"), find(world.node, "Plain")
		ordered.AbsoluteWindowSize = V2(world, 200, 120)
		plain.AbsoluteWindowSize = V2(world, 200, 120)
		t.expect(plain:FindFirstChildWhichIsA("UIDragDetector", true)).toBeNil()
		t.expect(find(plain, "Move")).toBeNil()
		for rowKey = 1, 6 do
			local cells = find(ordered:FindFirstChild(tostring(rowKey), true), "Cells")
			t.expect(cells:FindFirstChildWhichIsA("UIDragDetector", true)).toBeNil()
		end
		local function handle(rowKey: number): any
			return find(ordered:FindFirstChild(tostring(rowKey), true), "Move"):FindFirstChildWhichIsA("UIDragDetector")
		end
		local detector = handle(1)
		detector.DragStart.fire(V2(world, 10, 10))
		detector.DragContinue.fire(V2(world, 10, 75))
		t.expect(find(ordered, "DropLine").Position.Y.Offset).toBe(80)
		t.expect(ordered:FindFirstChild("1", true).Position.Y.Offset).toBe(0)
		detector.DragContinue.fire(V2(world, 10, 45))
		t.expect(find(ordered, "DropLine").Position.Y.Offset).toBe(40)
		detector.DragContinue.fire(V2(world, 10, 75))
		detector.DragEnd.fire()
		t.expect(requests).toEqual({ { keys = { 1 }, slot = 3 } })
		t.expect(find(ordered, "DropLine")).toBeNil()
		detector = handle(5)
		detector.DragStart.fire(V2(world, 10, 90))
		detector.DragContinue.fire(V2(world, 10, 25))
		t.expect(find(ordered, "DropLine").Position.Y.Offset).toBe(20)
		detector.DragEnd.fire()
		t.expect(requests[2]).toEqual({ keys = { 5 }, slot = 1 })
		detector = handle(3)
		detector.DragStart.fire(V2(world, 10, 50))
		detector.DragContinue.fire(V2(world, 10, 45))
		detector.DragEnd.fire()
		t.expect(#requests).toBe(2)
		world.stop()
	end)

	t.it(
		"collections-145 keeps the dragged row in place, drags single or block rows and ignores no-op drops",
		function()
			local requests = {}
			local selected = Compose.cell({ [4] = true, [5] = true })
			local world = setup(function(UI)
				return UI.Table({
					from = records(5),
					key = key,
					itemSize = 20,
					selection = selected,
					selectionMode = "multi",
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(requests, { keys = keys, slot = slot })
					end,
					columns = { { id = "label", label = "Label", width = 100 } },
				})
			end)
			local body = find(world.node, "Body")
			body.AbsoluteWindowSize = V2(world, 200, 100)
			local function handle(rowKey: number): any
				return body:FindFirstChild(tostring(rowKey), true)
					:FindFirstChild("Move", true)
					:FindFirstChildWhichIsA("UIDragDetector")
			end
			local origin = body:FindFirstChild("1", true)
			local detector = handle(1)
			detector.DragStart.fire(V2(world, 10, 10))
			detector.DragContinue.fire(V2(world, 10, 65))
			t.expect(body:FindFirstChild("1", true)).toBe(origin)
			t.expect(origin.Position.Y.Offset).toBe(0)
			t.expect(find(origin, "Reorderable"):GetAttribute("FacetDragging")).toBe(true)
			t.expect(find(world.node, "DropLine").Position.Y.Offset).toBe(body.Position.Y.Offset + 60)
			t.expect(find(world.node, "DragLabel").Text).toBe("1")
			detector.DragEnd.fire()
			t.expect(requests).toEqual({ { keys = { 1 }, slot = 2 } })
			t.expect(selected:peek()).toEqual({ [4] = true, [5] = true })
			t.expect(find(world.node, "DropLine")).toBeNil()
			detector = handle(4)
			detector.DragStart.fire(V2(world, 10, 70))
			detector.DragContinue.fire(V2(world, 10, 5))
			t.expect(find(world.node, "DragLabel").Text).toBe("2 selected")
			detector.DragEnd.fire()
			t.expect(requests[2]).toEqual({ keys = { 4, 5 }, slot = 0 })
			selected:set({ [1] = true, [2] = true })
			detector = handle(1)
			detector.DragStart.fire(V2(world, 10, 10))
			detector.DragContinue.fire(V2(world, 10, 3))
			detector.DragEnd.fire()
			detector = handle(3)
			detector.DragStart.fire(V2(world, 10, 50))
			detector.DragContinue.fire(V2(world, 10, 45))
			detector.DragEnd.fire()
			t.expect(#requests).toBe(2)
			world.stop()
		end
	)

	t.it(
		"collections-145 cancels a table drag on focus loss or dismissal and gives non-reorderable tables no drag",
		function()
			local requests = {}
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Table("Ordered")({
						from = records(5),
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function(keys, slot)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = { { id = "label", label = "Label", width = 100 } },
					}),
					UI.Table("Fixed")({
						from = records(5),
						key = key,
						itemSize = 20,
						selection = Compose.cell({}),
						columns = { { id = "label", label = "Label", width = 100 } },
					}),
				})
			end)
			local body = find(find(world.node, "Ordered"), "Body")
			body.AbsoluteWindowSize = V2(world, 200, 100)
			local fixed = find(world.node, "Fixed")
			find(fixed, "Body").AbsoluteWindowSize = V2(world, 200, 100)
			t.expect(find(fixed, "Move")).toBeNil()
			t.expect(find(fixed, "ReorderFeedback")).toBeNil()
			for _, node in find(fixed, "Body"):GetDescendants() do
				t.expect(node:IsA("UIDragDetector")).toBe(false)
			end
			local E = world.engine.types.Enum
			local function begin(rowKey: number): any
				local move = body:FindFirstChild(tostring(rowKey), true):FindFirstChild("Move", true)
				local detector = move:FindFirstChildWhichIsA("UIDragDetector")
				local pointer = {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.Begin,
					Position = world.engine.types.Vector3.new(10, 10, 0),
				}
				move.InputBegan.fire(pointer)
				detector.DragStart.fire(V2(world, 10, (rowKey - 1) * 20 + 10))
				detector.DragContinue.fire(V2(world, 10, 90))
				t.expect(find(world.node, "DropLine") ~= nil).toBe(true)
				return detector, pointer
			end
			local detector, pointer = begin(1)
			world.input.WindowFocusReleased.fire()
			t.expect(find(world.node, "DropLine")).toBeNil()
			world.input.InputEnded.fire(pointer)
			detector.DragEnd.fire()
			t.expect(#requests).toBe(0)
			detector, pointer = begin(2)
			pointer.UserInputState = E.UserInputState.End
			world.input.InputEnded.fire(pointer)
			t.expect(requests).toEqual({ { keys = { 2 }, slot = 4 } })
			detector, pointer = begin(3)
			world.stop()
			pointer.UserInputState = E.UserInputState.End
			world.input.InputEnded.fire(pointer)
			detector.DragEnd.fire()
			world.engine.heartbeat.fire(1 / 60)
			t.expect(#requests).toBe(1)
		end
	)

	t.it(
		"collections-120 refuses unselectable rows in single mode, refuses pinned grabs and keeps absent predicates open",
		function()
			local single, requests = Compose.cell({}), {}
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Table("Guarded")({
						from = records(4),
						key = key,
						itemSize = 20,
						selection = single,
						selectionMode = "single",
						selectable = function(item)
							return item.id ~= 2
						end,
						reorderable = true,
						movable = function(item)
							return item.id ~= 3
						end,
						onReorder = function(keys, slot)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = { { id = "label", label = "Label", width = 100 } },
					}),
					UI.Table("Open")({
						from = records(4),
						key = key,
						itemSize = 20,
						selection = Compose.cell({}),
						selectionMode = "multi",
						reorderable = true,
						onReorder = function(keys, slot)
							table.insert(requests, { keys = keys, slot = slot, open = true })
						end,
						columns = { { id = "label", label = "Label", width = 100 } },
					}),
				})
			end)
			local guarded, openTable = find(find(world.node, "Guarded"), "Body"), find(find(world.node, "Open"), "Body")
			guarded.AbsoluteWindowSize = V2(world, 200, 100)
			openTable.AbsoluteWindowSize = V2(world, 200, 100)
			local function hit(body: any, rowKey: number): any
				return find(body:FindFirstChild(tostring(rowKey), true), "RowHit")
			end
			hit(guarded, 1).Activated.fire()
			t.expect(single:peek()).toEqual({ [1] = true })
			hit(guarded, 2).Activated.fire()
			t.expect(single:peek()).toEqual({ [1] = true })
			hit(guarded, 3).Activated.fire()
			t.expect(single:peek()).toEqual({ [3] = true })
			local pinned = guarded:FindFirstChild("3", true):FindFirstChild("Move", true)
			t.expect(pinned.Interactable).toBe(false)
			pinned.Activated.fire()
			t.expect(find(world.node, "DropLine")).toBeNil()
			t.expect(action(world.root, "ReorderDrop")).toBeNil()
			local detector = pinned:FindFirstChildWhichIsA("UIDragDetector")
			t.expect(detector.Enabled).toBe(false)
			detector.DragStart.fire(V2(world, 10, 50))
			detector.DragContinue.fire(V2(world, 10, 5))
			detector.DragEnd.fire()
			t.expect(#requests).toBe(0)
			for rowKey = 1, 4 do
				local move = openTable:FindFirstChild(tostring(rowKey), true):FindFirstChild("Move", true)
				t.expect(move.Interactable).toBe(true)
				t.expect(move:FindFirstChildWhichIsA("UIDragDetector").Enabled).toBe(true)
				hit(openTable, rowKey).Activated.fire()
			end
			for rowKey = 1, 4 do
				t.expect(find(openTable:FindFirstChild(tostring(rowKey), true), "Row"):GetAttribute("FacetSelected"))
					.toBe(true)
			end
			world.stop()
		end
	)

	t.it(
		"collections-122 protects deletion on every route through table and list hosts but keeps other actions",
		function()
			for _, host in { "table", "list" } do
				local deleted, flagged, editing = {}, {}, Compose.cell(false)
				local function actionsFor(current: any, rowKey: number): any
					return {
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								role = "destructive",
								enabled = function(use)
									return use(current).id ~= 2
								end,
								onActivate = function()
									table.insert(deleted, rowKey)
								end,
							},
							{
								id = "Flag",
								label = "Flag",
								onActivate = function()
									table.insert(flagged, rowKey)
								end,
							},
						},
					}
				end
				local world = setup(function(UI)
					if host == "table" then
						return UI.Table({
							from = records(4),
							key = key,
							itemSize = 44,
							editing = editing,
							columns = { { id = "label", label = "Label", width = 100 } },
							rowActions = actionsFor,
						})
					end
					return UI.VirtualList({
						from = records(4),
						key = key,
						itemSize = 44,
						selection = Compose.cell({}),
						render = function(current, _, rowKey)
							local spec = actionsFor(current, rowKey)
							spec.editing = editing
							spec.content = UI.Button("Action")({ label = tostring(rowKey) })
							return UI.RowActions(spec)
						end,
					})
				end)
				local body = if host == "table" then find(world.node, "Body") else world.node
				body.AbsoluteWindowSize = V2(world, 300, 200)
				local function row(rowKey: number): any
					local node = rowActionsIn(body:FindFirstChild(tostring(rowKey), true))
					node.AbsoluteSize = V2(world, 300, 44)
					return node
				end
				local protected = row(2)
				local detector = protected:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				drag(world, detector, 290, 5)
				t.expect(deleted).toEqual({})
				drag(world, detector, 250, 150)
				local trayDelete = find(find(protected, "trailing"), "Delete")
				t.expect(find(protected, "trailing").Visible).toBe(true)
				t.expect(trayDelete.Interactable).toBe(false)
				trayDelete.Activated.fire()
				t.expect(deleted).toEqual({})
				find(find(protected, "trailing"), "Flag").Activated.fire()
				t.expect(flagged).toEqual({ 2 })
				editing:set(true)
				t.expect(protected:FindFirstChild("Delete")).toBeNil()
				t.expect(row(1):FindFirstChild("Delete") ~= nil).toBe(true)
				editing:set(false)
				world.gui.SelectedObject = find(body:FindFirstChild("2", true), "RowHit")
				t.expect(world.gui.SelectedObject ~= nil).toBe(true)
				t.expect(action(world.root, "RowActionsDelete")).toBeNil()
				protected.InputBegan.fire({ UserInputType = world.engine.types.Enum.UserInputType.MouseButton2 })
				local menuDelete = find(world.root, "trailing:Delete")
				t.expect(menuDelete.Interactable).toBe(false)
				menuDelete.Activated.fire()
				t.expect(deleted).toEqual({})
				find(world.root, "trailing:Flag").Activated.fire()
				t.expect(flagged).toEqual({ 2, 2 })
				t.expect(find(world.root, "MenuPanel")).toBeNil()
				world.gui.SelectedObject = find(body:FindFirstChild("3", true), "RowHit")
				local delete = action(world.root, "RowActionsDelete")
				t.expect(delete ~= nil).toBe(true)
				delete.Pressed.fire()
				t.expect(deleted).toEqual({ 3 })
				world.engine.heartbeat.fire(1 / 60)
				drag(world, row(4):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 290, 5)
				t.expect(deleted).toEqual({ 3, 4 })
				world.stop()
			end
		end
	)

	t.it("collections-116 refuses locked selection, pinned movement and protected deletion in the run sheet", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			guiService = guiService,
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = guiService,
					services = { GuiService = guiService },
					inputParent = target,
					reducedMotion = true,
				} :: any
			),
		}
		local built
		local stop, node = runtime.mount(function()
			built = require("../examples/gallery/scenarios/row_capabilities").build(ctx)
			return built.screen()
		end, target)
		local function ids(): string
			local out = {}
			for _, item in built.report().rows do
				table.insert(out, item.id)
			end
			return table.concat(out, ",")
		end
		local body = find(find(node, "RunSheet"), "Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(500, 400)
		local function row(id: string): any
			return body:FindFirstChild(id, true)
		end
		find(row("warmup"), "RowHit").Activated.fire()
		find(row("notes"), "RowHit").Activated.fire()
		t.expect(built.report().selection).toEqual({ warmup = true })
		local height = row("warmup").Position.Y.Offset - row("grid").Position.Y.Offset
		t.expect(height > 0).toBe(true)
		local function dragRow(id: string, toY: number)
			local detector = find(row(id), "Move"):FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(engine.types.Vector2.new(10, row(id).Position.Y.Offset + height / 2))
			detector.DragContinue.fire(engine.types.Vector2.new(10, toY))
			detector.DragEnd.fire()
		end
		dragRow("grid", height * 4.5)
		t.expect(ids()).toBe("grid,warmup,main,notes,cool")
		find(row("grid"), "Move").Activated.fire()
		t.expect(find(node, "DropLine")).toBeNil()
		dragRow("warmup", 2)
		t.expect(ids()).toBe("grid,warmup,main,notes,cool")
		dragRow("cool", height * 1.5 + 2)
		t.expect(ids()).toBe("grid,warmup,cool,main,notes")
		local protected = rowActionsIn(row("main"))
		protected.AbsoluteSize = engine.types.Vector2.new(500, 44)
		local detector = protected:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(480, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 20))
		detector.DragEnd.fire()
		t.expect(#built.report().rows).toBe(5)
		guiService.SelectedObject = find(row("main"), "RowHit")
		t.expect(action(target, "RowActionsDelete")).toBeNil()
		t.expect(#built.report().rows).toBe(5)
		t.expect(built.report().message)
			.toBe(require("../examples/gallery/scenarios/row_capabilities").copy.refusalIdle)
		local open = rowActionsIn(row("cool"))
		open.AbsoluteSize = engine.types.Vector2.new(500, 44)
		guiService.SelectedObject = find(row("cool"), "RowHit")
		action(target, "RowActionsDelete").Pressed.fire()
		t.expect(ids()).toBe("grid,warmup,main,notes")
		stop()
		runtime:dispose()
	end)

	t.it(
		"collections-281 locks, coordinates, releases, fires once and follows reactive actions inside list rows",
		function()
			local coordinator = Compose.cell(nil :: any)
			local source = Compose.cell({
				{ id = 1, label = "1", armed = true },
				{ id = 2, label = "2", armed = true },
				{ id = 3, label = "3", armed = false },
				{ id = 4, label = "4", armed = true },
			})
			local invoked = {}
			local world = setup(function(UI)
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 44,
					render = function(current, _, rowKey)
						return UI.RowActions({
							coordinator = coordinator,
							content = UI.Button("Action")({ label = tostring(rowKey) }),
							trailing = function(use)
								if not use(current).armed then
									return {}
								end
								return {
									{
										id = "Delete",
										label = "Delete",
										role = "destructive",
										onActivate = function()
											table.insert(invoked, rowKey)
										end,
									},
								}
							end,
						})
					end,
				})
			end, { reducedMotion = false })
			world.node.AbsoluteWindowSize = V2(world, 300, 200)
			local function row(rowKey: number): any
				local node = rowActionsIn(world.node:FindFirstChild(tostring(rowKey), true))
				if node then
					node.AbsoluteSize = V2(world, 300, 44)
				end
				return node
			end
			local function settle()
				for _ = 1, 60 do
					world.engine.heartbeat.fire(1 / 60)
				end
			end
			local first = row(1)
			local detector = first:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(V2(world, 200, 20))
			detector.DragContinue.fire(V2(world, 196, 80))
			detector.DragContinue.fire(V2(world, 100, 140))
			t.expect(find(first, "Content").Position.X.Offset).toBe(0)
			detector.DragEnd.fire()
			settle()
			t.expect(find(first, "trailing").Visible).toBe(false)
			drag(world, detector, 250, 150)
			settle()
			t.expect(find(first, "trailing").Visible).toBe(true)
			drag(world, row(2):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
			settle()
			t.expect(find(first, "trailing").Visible).toBe(false)
			t.expect(find(row(2), "trailing").Visible).toBe(true)
			t.expect(row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled)
				.toBe(false)
			local armed = table.clone(source:peek())
			armed[3] = { id = 3, label = "3", armed = true }
			source:set(armed)
			t.expect(row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled)
				.toBe(true)
			drag(world, row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
			settle()
			t.expect(find(row(3), "trailing").Visible).toBe(true)
			local disarmed = table.clone(source:peek())
			disarmed[3] = { id = 3, label = "3", armed = false }
			source:set(disarmed)
			settle()
			t.expect(row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled)
				.toBe(false)
			t.expect(find(row(3), "trailing").Visible).toBe(false)
			t.expect(find(row(3), "Content").Position.X.Offset).toBe(0)
			source:set(armed)
			settle()
			t.expect(find(row(3), "trailing").Visible).toBe(false)
			t.expect(find(row(3), "Content").Position.X.Offset).toBe(0)
			local second = row(2):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
			drag(world, second, 250, 150)
			settle()
			t.expect(find(row(2), "trailing").Visible).toBe(true)
			second.DragStart.fire(V2(world, 250, 20))
			second.DragContinue.fire(V2(world, 200, 20))
			source:set({ source:peek()[1], source:peek()[3], source:peek()[4] })
			second.DragEnd.fire()
			t.expect(world.node:FindFirstChild("2", true)).toBeNil()
			t.expect(coordinator:peek()).toBeNil()
			local fourth = row(4):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
			drag(world, fourth, 290, 5)
			t.expect(#invoked).toBe(0)
			drag(world, fourth, 290, 5)
			drag(world, row(1):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
			settle()
			t.expect(invoked).toEqual({ 4 })
			t.expect(row(4).Size.Y.Offset).toBe(44)
			world.stop()
			t.expect(coordinator:peek()).toBeNil()
		end
	)

	t.it("collections-281 keeps a model-owned open row slid when virtualization remounts it", function()
		local opens: { [number]: any } = {}
		local world = setup(function(UI)
			return UI.VirtualList({
				from = records(30),
				key = key,
				itemSize = 44,
				overscan = 0,
				render = function(_, _, rowKey)
					opens[rowKey] = opens[rowKey] or Compose.cell(nil :: string?)
					return UI.RowActions({
						open = opens[rowKey],
						content = UI.Button("Action")({ label = tostring(rowKey) }),
						trailing = { { id = "Save", label = "Save" } },
					})
				end,
			})
		end)
		world.node.AbsoluteWindowSize = V2(world, 300, 200)
		local function row(rowKey: number): any
			local node = rowActionsIn(world.node:FindFirstChild(tostring(rowKey), true))
			if node then
				node.AbsoluteSize = V2(world, 300, 44)
			end
			return node
		end
		local original = row(1)
		drag(world, original:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
		t.expect(opens[1]:peek()).toBe("trailing")
		world.node.CanvasPosition = V2(world, 0, 900)
		t.expect(world.node:FindFirstChild("1", true)).toBeNil()
		world.node.CanvasPosition = V2(world, 0, 0)
		local returned = row(1)
		t.expect(returned ~= nil).toBe(true)
		t.expect(find(returned, "trailing").Visible).toBe(true)
		t.expect(find(returned, "Content").Position.X.Offset).toBe(-88)
		world.stop()
	end)

	t.it(
		"collections-284 measures, taps once, hands off with motion and collapses only the committed list row",
		function()
			local coordinator = Compose.cell(nil :: any)
			local source = Compose.cell(records(3))
			local invoked, keep = {}, true
			local world = setup(function(UI)
				return UI.VirtualList({
					from = source,
					key = key,
					itemSize = 44,
					render = function(_, _, rowKey)
						return UI.RowActions({
							coordinator = coordinator,
							content = UI.Button("Action")({ label = tostring(rowKey) }),
							trailing = {
								{
									id = "Remove",
									label = "Remove",
									role = "destructive",
									onActivate = function()
										table.insert(invoked, rowKey)
										if not keep then
											local rest = {}
											for _, item in source:peek() do
												if item.id ~= rowKey then
													table.insert(rest, item)
												end
											end
											source:set(rest)
										end
									end,
								},
							},
						})
					end,
				})
			end, { reducedMotion = false })
			world.node.AbsoluteWindowSize = V2(world, 300, 200)
			local function row(rowKey: number): any
				local node = rowActionsIn(world.node:FindFirstChild(tostring(rowKey), true))
				if node then
					node.AbsoluteSize = V2(world, 300, 44)
				end
				return node
			end
			local function settle(frames: number?)
				for _ = 1, frames or 60 do
					world.engine.heartbeat.fire(1 / 60)
				end
			end
			local first, second = row(1), row(2)
			find(first, "Remove").TextBounds = V2(world, 150, 20)
			drag(world, first:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 280, 180)
			settle()
			t.expect(find(first, "trailing").Size.X.Offset).toBe(182)
			t.expect(find(first, "Content").Position.X.Offset).toBeCloseTo(-182, 0.5)
			drag(world, second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
			local previous = find(first, "Content").Position.X.Offset
			local steps = 0
			for _ = 1, 60 do
				world.engine.heartbeat.fire(1 / 60)
				local now = find(first, "Content").Position.X.Offset
				t.expect(now >= previous).toBe(true)
				if now < -0.5 then
					steps += 1
				end
				previous = now
			end
			t.expect(steps > 2).toBe(true)
			t.expect(previous).toBeCloseTo(0, 0.5)
			t.expect(find(second, "Content").Position.X.Offset).toBeCloseTo(-88, 0.5)
			find(second, "Remove").Activated.fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
			find(second, "Remove").Activated.fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
			t.expect(#invoked).toBe(0)
			local frames = 0
			while #invoked == 0 and frames < 60 do
				world.engine.heartbeat.fire(1 / 60)
				frames += 1
				t.expect(first.Size.Y.Offset).toBe(44)
				t.expect(row(3).Size.Y.Offset).toBe(44)
			end
			t.expect(invoked).toEqual({ 2 })
			t.expect(second.Size.Y.Offset).toBe(0)
			settle(90)
			t.expect(invoked).toEqual({ 2 })
			t.expect(second.Size.Y.Offset).toBe(44)
			t.expect(find(second, "trailing").Visible).toBe(false)
			t.expect(find(second, "Content").Position.X.Offset).toBeCloseTo(0, 0.5)
			t.expect(second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled)
				.toBe(true)
			keep = false
			drag(world, second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 290, 5)
			t.expect(#invoked).toBe(1)
			settle(20)
			t.expect(invoked).toEqual({ 2, 2 })
			t.expect(world.node:FindFirstChild("2", true)).toBeNil()
			local standing = 0
			for _, node in world.node:GetDescendants() do
				if node.Name == "Remove" then
					standing += 1
				end
			end
			t.expect(standing).toBe(2)
			t.expect(row(1).Size.Y.Offset).toBe(44)
			world.stop()
		end
	)

	t.it("inputs-58 removes a remove-only token once through every input, and never while disabled", function()
		local calls, enabled = 0, Compose.cell(true)
		local world = setup(function(UI)
			return UI.Chip("Token")({
				label = "Rain",
				removeLabel = "Remove Rain",
				enabled = enabled,
				onRemove = function()
					calls += 1
				end,
			})
		end)
		local E = world.engine.types.Enum
		local token = find(world.node, "Token")
		t.expect(token.Selectable).toBe(true)
		t.expect(token:GetAttribute("AccessibleLabel")).toBe("Remove Rain")
		t.expect(find(token, "Remove").Visible).toBe(true)
		local expected = 0
		for _, inputType in { E.UserInputType.MouseButton1, E.UserInputType.Touch, E.UserInputType.Gamepad1 } do
			token.Activated.fire({ UserInputType = inputType, UserInputState = E.UserInputState.End }, 1)
			expected += 1
			t.expect(calls).toBe(expected)
		end
		world.gui.SelectedObject = token
		local activate = action(world.root, "Activate")
		t.expect(activate ~= nil).toBe(true)
		activate.Pressed.fire()
		t.expect(calls).toBe(expected + 1)
		local delete = action(world.root, "RemoveChip")
		t.expect(delete ~= nil).toBe(true)
		delete.Pressed.fire()
		delete.Released.fire()
		t.expect(calls).toBe(expected + 2)
		enabled:set(false)
		token.Activated.fire({ UserInputType = E.UserInputType.Touch }, 1)
		t.expect(action(world.root, "Activate")).toBeNil()
		t.expect(action(world.root, "RemoveChip")).toBeNil()
		t.expect(calls).toBe(expected + 2)
		world.stop()
	end)

	t.it("apps2-40 reorders, swipes Top and Remove, plays on a plain tap and restores the playlist", function()
		local built, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
		local E = world.engine.types.Enum
		local body = find(node, "Body")
		body.AbsoluteWindowSize = V2(world, 900, 600)
		local function ids(rows: { any }): string
			local out = {}
			for _, track in rows do
				table.insert(out, track.id)
			end
			return table.concat(out, ",")
		end
		local function row(id: string): any
			return body:FindFirstChild(id, true)
		end
		local function actions(id: string): any
			local node = rowActionsIn(row(id))
			node.AbsoluteSize = V2(world, 844, 44)
			return node
		end
		t.expect(ids(built.baseRows:peek())).toBe("neon,drift,turbo,pit,photo,apex")
		local height = row("drift").Position.Y.Offset - row("neon").Position.Y.Offset
		local move = find(row("neon"), "Move"):FindFirstChildWhichIsA("UIDragDetector")
		move.DragStart.fire(V2(world, 20, height / 2))
		move.DragContinue.fire(V2(world, 20, row("turbo").Position.Y.Offset + height * 0.75))
		move.DragEnd.fire()
		t.expect(ids(built.baseRows:peek())).toBe("drift,turbo,neon,pit,photo,apex")
		local tap = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.End }
		find(row("pit"), "RowHit").Activated.fire(tap, 1)
		t.expect(built.nowPlaying:peek()).toBe("Pit Lane Shuffle")
		t.expect(find(actions("pit"), "leading").Visible).toBe(false)
		t.expect(find(actions("pit"), "trailing").Visible).toBe(false)
		t.expect(find(actions("pit"), "Content").Position.X.Offset).toBe(0)
		drag(world, actions("pit"):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 300, 420)
		t.expect(find(actions("pit"), "leading").Visible).toBe(true)
		t.expect(ids(built.baseRows:peek())).toBe("drift,turbo,neon,pit,photo,apex")
		find(find(actions("pit"), "leading"), "top").Activated.fire(tap, 1)
		t.expect(ids(built.baseRows:peek())).toBe("pit,drift,turbo,neon,photo,apex")
		drag(
			world,
			actions("apex"):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
			600,
			480
		)
		t.expect(find(actions("apex"), "trailing").Visible).toBe(true)
		t.expect(#built.baseRows:peek()).toBe(6)
		find(find(actions("apex"), "trailing"), "remove").Activated.fire(tap, 1)
		t.expect(ids(built.baseRows:peek())).toBe("pit,drift,turbo,neon,photo")
		t.expect(row("apex")).toBeNil()
		built.ratingFor("neon"):set(1)
		find(node, "Restore").Activated.fire(tap, 1)
		t.expect(ids(built.baseRows:peek())).toBe("neon,drift,turbo,pit,photo,apex")
		t.expect(built.ratingFor("neon"):peek()).toBe(4)
		t.expect(built.nowPlaying:peek()).toBeNil()
		t.expect(row("apex") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("apps2-39 grabs, steps and drops a playlist row by gamepad and reaches a swiped tray's Remove", function()
		local built, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
		local E = world.engine.types.Enum
		local body = find(node, "Body")
		body.AbsoluteWindowSize = V2(world, 900, 600)
		local function ids(): string
			local out = {}
			for _, track in built.baseRows:peek() do
				table.insert(out, track.id)
			end
			return table.concat(out, ",")
		end
		local pad = { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
		local handle = find(body:FindFirstChild("neon", true), "Move")
		world.gui.SelectedObject = handle
		handle.Activated.fire(pad, 1)
		t.expect(world.gui.SelectedObject.Name).toBe("Drop")
		local function keys(name: string): { string }
			local out = {}
			for _, binding in action(world.root, name):GetChildren() do
				table.insert(out, binding.KeyCode.Name)
			end
			table.sort(out)
			return out
		end
		t.expect(table.find(keys("ReorderDown"), "DPadDown") ~= nil).toBe(true)
		t.expect(table.find(keys("ReorderDrop"), "ButtonA") ~= nil).toBe(true)
		action(world.root, "ReorderDown").Pressed.fire()
		action(world.root, "ReorderDown").Pressed.fire()
		action(world.root, "ReorderDrop").Pressed.fire()
		t.expect(ids()).toBe("drift,turbo,neon,pit,photo,apex")
		t.expect(action(world.root, "ReorderDrop")).toBeNil()
		local turbo = rowActionsIn(body:FindFirstChild("turbo", true))
		turbo.AbsoluteSize = V2(world, 844, 44)
		local hit = find(body:FindFirstChild("turbo", true), "RowHit")
		world.gui.SelectedObject = hit
		drag(world, turbo:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 600, 480)
		local remove = find(find(turbo, "trailing"), "remove")
		t.expect(remove.Selectable).toBe(true)
		t.expect(remove.Interactable).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(remove)
		local close = action(world.root, "RowActionsClose")
		t.expect(close ~= nil).toBe(true)
		close.Pressed.fire()
		t.expect(world.gui.SelectedObject).toBe(hit)
		drag(world, turbo:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 600, 480)
		t.expect(world.gui.SelectedObject).toBe(remove)
		remove.Activated.fire(pad, 1)
		t.expect(ids()).toBe("drift,neon,pit,photo,apex")
		world.stop()
	end)

	t.it("apps2-39 keeps a selected Move handle out of the engine drag so ButtonA grabs the row", function()
		local _, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
		local body = find(node, "Body")
		body.AbsoluteWindowSize = V2(world, 900, 600)
		local handle = find(body:FindFirstChild("neon", true), "Move")
		local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
		t.expect(detector.Enabled).toBe(true)
		world.gui.SelectedObject = handle
		t.expect(detector.Enabled).toBe(false)
		world.gui.SelectedObject = find(body:FindFirstChild("drift", true), "Move")
		t.expect(detector.Enabled).toBe(true)
		world.gui.SelectedObject = nil
		t.expect(detector.Enabled).toBe(true)
		world.stop()
	end)

	t.it("apps2-38 selects playlist rows additively by touch and reorders by a touch handle drag", function()
		local built, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
		local E = world.engine.types.Enum
		local body = find(node, "Body")
		body.AbsoluteWindowSize = V2(world, 900, 600)
		local function selected(id: string): boolean
			return find(body:FindFirstChild(id, true), "Row"):GetAttribute("FacetSelected") == true
		end
		local tap = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.End }
		find(body:FindFirstChild("turbo", true), "RowHit").Activated.fire(tap, 1)
		find(body:FindFirstChild("pit", true), "RowHit").Activated.fire(tap, 1)
		t.expect(selected("turbo")).toBe(true)
		t.expect(selected("pit")).toBe(true)
		t.expect(selected("neon")).toBe(false)
		find(body:FindFirstChild("pit", true), "RowHit").Activated.fire(tap, 1)
		t.expect(selected("pit")).toBe(false)
		t.expect(selected("turbo")).toBe(true)
		find(body:FindFirstChild("turbo", true), "RowHit").Activated.fire(tap, 1)
		local height = body:FindFirstChild("drift", true).Position.Y.Offset
			- body:FindFirstChild("neon", true).Position.Y.Offset
		local handle = find(body:FindFirstChild("neon", true), "Move")
		local finger = {
			UserInputType = E.UserInputType.Touch,
			UserInputState = E.UserInputState.Begin,
			Position = world.engine.types.Vector3.new(20, height / 2, 0),
		}
		handle.InputBegan.fire(finger)
		local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2(world, 20, height / 2))
		finger.UserInputState = E.UserInputState.Change
		finger.Position = world.engine.types.Vector3.new(20, height * 1.5 + height * 0.25, 0)
		world.input.InputChanged.fire(finger)
		t.expect(find(node, "DropLine") ~= nil).toBe(true)
		detector.DragEnd.fire()
		t.expect(built.baseRows:peek()[1].id).toBe("neon")
		finger.UserInputState = E.UserInputState.End
		world.input.InputEnded.fire(finger)
		t.expect(built.baseRows:peek()[1].id).toBe("drift")
		t.expect(built.baseRows:peek()[2].id).toBe("neon")
		t.expect(find(node, "DropLine")).toBeNil()
		world.stop()
	end)

	t.it("apps2-265 grows the streamed reply, swipes a message away and clears from the conversation menu", function()
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
		local lifetime = Compose.createRootOwner(function()
			local model = require("../examples/virtual_monitors/model").new(Compose)
			Compose.cleanup(model.dispose)
			local views = require("../examples/virtual_monitors/screens").create(Facet, runtime, {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				reducedMotion = true,
			})
			local _, chat = runtime.mount(views.Chat, target)
			local send = find(chat, "Send")
			model.chat.draft:set("What game should I play with friends?")
			send.Activated.fire()
			t.expect(model.chat.streaming:peek()).toBe(true)
			find(chat, "Messages").AbsoluteWindowSize = engine.types.Vector2.new(850, 300)
			local reply = find(find(chat, "Message_2"), "Message")
			t.expect(find(find(chat, "Message_2"), "Thinking") ~= nil).toBe(true)
			local previous = 0
			local grew = 0
			for _ = 1, 6 do
				model.step(0.1, true)
				local shown = utf8.len(reply.Text) or #reply.Text
				t.expect(#reply.Text).toBe(model.chat.streamedChars:peek())
				t.expect(shown >= previous).toBe(true)
				if shown > previous then
					grew += 1
				end
				previous = shown
			end
			t.expect(grew > 1).toBe(true)
			t.expect(model.chat.streamedChars:peek() < model.chat.totalChars:peek()).toBe(true)
			t.expect(find(find(chat, "Message_2"), "Thinking")).toBe(nil)
			send.Activated.fire()
			t.expect(model.chat.streaming:peek()).toBe(false)
			find(chat, "Messages").AbsoluteWindowSize = engine.types.Vector2.new(850, 300)
			t.expect(#model.chat.messages:peek()).toBe(2)
			local row = find(chat, "MessageActions_2")
			row.AbsoluteSize = engine.types.Vector2.new(800, 60)
			local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(engine.types.Vector2.new(780, 20))
			detector.DragContinue.fire(engine.types.Vector2.new(20, 20))
			detector.DragEnd.fire()
			t.expect(#model.chat.messages:peek()).toBe(1)
			t.expect(model.chat.messages:peek()[1].role).toBe("user")
			find(chat, "ConversationMenu").Activated.fire()
			local panel = find(target, "MenuPanel")
			t.expect(find(panel, "Suggest") ~= nil).toBe(true)
			local clear = find(panel, "Clear")
			t.expect(clear:GetAttribute("role")).toBe("destructive")
			clear.Activated.fire()
			t.expect(#model.chat.messages:peek()).toBe(0)
		end, runtime.reactor)
		lifetime.dispose()
		runtime:dispose()
	end)
end)
