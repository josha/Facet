--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	local nativeDrag = require("./lib/native_drag")

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RowActions = typeof(require("@repo/tools/typecheck/aliases").RowActions)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			motionLevel = "none",
		}
		for field, value in (options or {}) :: { [string]: any } do
			config[field] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, node: any = runtime.mount(function()
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			Host = (runtime.constructors :: unknown) :: RobloxHost,
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
					motionLevel = "none",
				} :: any
			),
		}
		local built
		local stop, node: any = runtime.mount(function()
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

	verifyHarness:suite("native parity weaker rows", function()
		verifyHarness:case(
			"collections-53 passes through without actions, reveals only filled edges and tracks the tray",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-53 passes through without actions, reveals only filled edges and tracks the tray",
				run = function()
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, trailing =
						Compose.cell(nil :: ("leading" | "trailing")?), Compose.cell({} :: { any })
					local world = setup(function(UI: FacetControls)
						return UI.RowActions({
							open = open,
							content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
							trailing = trailing,
						})
					end)
					local row = world.node
					row.AbsoluteSize = V2(world, 300, 40)
					local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					local content = find(row, "Content")
					Verify.expect(detector.Enabled):toBe(false)
					drag(world, detector, 200, 20)
					Verify.expect((open:peek())):toBeNil()
					Verify.expect(content.Position.X.Offset):toBe(0)
					Verify.expect(find(row, "leading").Visible):toBe(false)
					Verify.expect(find(row, "trailing").Visible):toBe(false)
					world.input.IsKeyDown = function()
						return false
					end
					row.InputBegan.fire({
						UserInputType = world.engine.types.Enum.UserInputType.MouseButton2,
						Position = world.engine.types.Vector3.new(50, 50, 0),
					})
					Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
					local invoked = {}
					trailing:set({
						{ id = "Save", label = "Save" },
						{ id = "Pin", label = "Pin", icon = "rbxassetid://7" },
						trailingAction(invoked, "Erase", "destructive"),
					})
					Verify.expect(detector.Enabled):toBe(true)
					Verify.expect(find(row, "trailing").Visible):toBe(false)
					open:set("leading")
					Verify.expect((open:peek())):toBeNil()
					Verify.expect(content.Position.X.Offset):toBe(0)
					Verify.expect(find(row, "leading").Visible):toBe(false)
					open:set("trailing")
					Verify.expect(find(row, "trailing").Visible):toBe(true)
					Verify.expect(content.Position.X.Offset):toBe(-264)
					Verify.expect(find(row, "trailing").Size.X.Offset):toBe(264)
					local save = find(find(row, "trailing"), "Save")
					Verify.expect(`{save.Size.X.Scale} {save.Size.X.Offset}`):toBe("0 88")
					Verify.expect((textOf(save))):toBe("Save")
					Verify.expect((find(save, "LeadingIcon"))):toBeNil()
					local pin = find(find(row, "trailing"), "Pin")
					Verify.expect(find(pin, "LeadingIcon").Image):toBe("rbxassetid://7")
					Verify.expect((textOf(pin))):toBe("")
					Verify.expect((pin:GetAttribute("label"))):toBe("Pin")
					open:set(nil)
					Verify.expect(content.Position.X.Offset):toBe(0)
					Verify.expect(find(row, "trailing").Visible):toBe(false)
					detector.DragStart.fire(V2(world, 250, 20))
					detector.DragContinue.fire(V2(world, 230, 20))
					Verify.expect(find(row, "trailing").Size.X.Offset):toBe(20)
					Verify.expect(content.Position.X.Offset):toBe(-20)
					detector.DragContinue.fire(V2(world, 150, 20))
					Verify.expect(find(row, "trailing").Size.X.Offset):toBe(100)
					Verify.expect(content.Position.X.Offset):toBe(-100)
					detector.DragContinue.fire(V2(world, 0, 20))
					Verify.expect(find(row, "trailing").Size.X.Offset):toBe(250)
					Verify.expect(find(row, "leading").Visible):toBe(false)
					detector.DragContinue.fire(V2(world, 500, 20))
					Verify.expect(content.Position.X.Offset):toBe(0)
					detector.DragEnd.fire()
					Verify.expect((open:peek())):toBeNil()
					Verify.expect(#invoked):toBe(0)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-53 animates a reveal over frames, snaps under reduced motion and leaks nothing",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-53 animates a reveal over frames, snaps under reduced motion and leaks nothing",
				run = function()
					for _, reduced in { false, true } do
						local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
							Compose.cell(nil :: ("leading" | "trailing")?)
						local world = setup(function(UI: FacetControls)
							return UI.RowActions({
								open = open,
								reducedMotion = reduced,
								content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
								trailing = { { id = "Save", label = "Save" } :: FixtureCollectionTypes.RowAction },
							})
						end, { motionLevel = "normal" })
						local row = world.node
						row.AbsoluteSize = V2(world, 300, 40)
						world.engine.heartbeat.fire(1)
						local content = find(row, "Content")
						open:set("trailing")
						if reduced then
							Verify.expect(content.Position.X.Offset):toBe(-88)
						else
							Verify.expect(content.Position.X.Offset):toBe(0)
							local previous = 0
							local frames = 0
							for _ = 1, 120 do
								world.engine.heartbeat.fire(1 / 60)
								local now = content.Position.X.Offset
								Verify.expect(now <= previous):toBe(true)
								if now ~= -88 then
									frames += 1
								end
								previous = now
							end
							Verify.expect(frames > 2):toBe(true)
							Verify.expect(content.Position.X.Offset):toBeCloseTo(-88, 0.5)
							open:set(nil)
							world.engine.heartbeat.fire(1 / 60)
							Verify.expect(content.Position.X.Offset < 0):toBe(true)
						end
						local made = {}
						for _, node in world.engine.made do
							made[node] = true
						end
						world.stop()
						world.engine.heartbeat.fire(1 / 60)
						for node in made do
							if node:IsA("GuiObject") then
								Verify.expect((node:isDestroyed())):toBe(true)
							end
						end
					end
				end,
			}
		)

		verifyHarness:case(
			"collections-57 runs a tray action once from touch, keyboard and gamepad and closes the tray",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-57 runs a tray action once from touch, keyboard and gamepad and closes the tray",
				run = function()
					local E = nil :: any
					for _, route in { "touch", "keyboard", "gamepad", "mouse" } do
						local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, invoked =
							Compose.cell("trailing" :: ("leading" | "trailing")?), {}
						local world = setup(function(UI: FacetControls)
							return UI.RowActions({
								open = open,
								content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
								trailing = { trailingAction(invoked, "Save"), trailingAction(invoked, "Flag") },
							})
						end)
						E = world.engine.types.Enum
						local row = world.node
						row.AbsoluteSize = V2(world, 300, 40)
						local save = find(find(row, "trailing"), "Save")
						Verify.expect(find(row, "trailing").Visible):toBe(true)
						if route == "keyboard" then
							world.gui.SelectedObject = save
							local activate = action(world.root, "Activate")
							Verify.expect(activate ~= nil):toBe(true)
							activate.Pressed.fire()
						else
							local inputType = if route == "touch"
								then E.UserInputType.Touch
								elseif route == "gamepad" then E.UserInputType.Gamepad1
								else E.UserInputType.MouseButton1
							save.Activated.fire({ UserInputType = inputType, UserInputState = E.UserInputState.End }, 1)
						end
						Verify.expect(invoked):toEqual({ "Save" })
						Verify.expect((open:peek())):toBeNil()
						Verify.expect(find(row, "trailing").Visible):toBe(false)
						Verify.expect(find(row, "Content").Position.X.Offset):toBe(0)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"collections-61 shows the minus only while editing a destructive row and deletes once from it",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-61 shows the minus only while editing a destructive row and deletes once from it",
				run = function()
					local invoked = {}
					local editing = Compose.cell(false)
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
						Compose.cell(nil :: ("leading" | "trailing")?)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.RowActions("Unwired")({
								content = UI.Button({ label = "Unwired" }) :: GuiObject,
								trailing = { trailingAction(invoked, "Unwired", "destructive") },
							}) :: unknown,
							UI.RowActions("Plain")({
								editing = editing,
								content = UI.Button({ label = "Plain" }) :: GuiObject,
								trailing = { trailingAction(invoked, "Archive") },
							}),
							UI.RowActions("Edited")({
								editing = editing,
								open = open,
								fullSwipe = false,
								content = UI.Button("Action")({ label = "Edited" }) :: GuiObject,
								trailing = {
									trailingAction(invoked, "Archive"),
									{
										id = "Erase",
										label = "Erase this row",
										role = "destructive" :: "destructive",
										onActivate = function()
											table.insert(invoked, "Erase")
										end,
									} :: FixtureCollectionTypes.RowAction,
								},
							}),
							UI.RowActions("LeadingOnly")({
								editing = editing,
								content = UI.Button({ label = "Leading" }) :: GuiObject,
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
						Verify.expect((row:FindFirstChild("Delete"))):toBeNil()
					end
					editing:set(true)
					Verify.expect((unwired:FindFirstChild("Delete"))):toBeNil()
					Verify.expect((plain:FindFirstChild("Delete"))):toBeNil()
					Verify.expect(find(plain, "Content").Position.X.Offset):toBe(72)
					local minus = edited:FindFirstChild("Delete")
					Verify.expect(minus ~= nil):toBe(true)
					Verify.expect(minus.Text):toBe("Erase this row")
					Verify.expect(find(edited, "Content").Position.X.Offset):toBe(72)
					Verify.expect(find(edited, "Content").Size.X.Offset):toBe(-72)
					local detector = edited:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					drag(world, detector, 290, 5)
					Verify.expect((open:peek())):toBe("trailing")
					Verify.expect(#invoked):toBe(0)
					editing:set(false)
					Verify.expect((open:peek())):toBe("trailing")
					Verify.expect((edited:FindFirstChild("Delete"))):toBeNil()
					Verify.expect(find(edited, "Content").Position.X.Offset):toBe(-176)
					open:set(nil)
					editing:set(true)
					minus = edited:FindFirstChild("Delete")
					minus.Activated.fire()
					minus.Activated.fire()
					Verify.expect(invoked):toEqual({ "Erase" })
					world.engine.heartbeat.fire(1 / 60)
					world.gui.SelectedObject = edited:FindFirstChild("Delete")
					local activate = action(world.root, "Activate")
					Verify.expect(activate ~= nil):toBe(true)
					activate.Pressed.fire()
					Verify.expect(invoked):toEqual({ "Erase", "Erase" })
					world.engine.heartbeat.fire(1 / 60)
					leadingOnly:FindFirstChild("Delete").Activated.fire()
					Verify.expect(invoked):toEqual({ "Erase", "Erase", "Drop" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-88 keeps an irrevocable commit running through close attempts and new gestures",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-88 keeps an irrevocable commit running through close attempts and new gestures",
				run = function()
					local invoked, open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, coordinator =
						0, Compose.cell("trailing" :: ("leading" | "trailing")?), Compose.cell(nil :: any)
					local world = setup(function(UI: FacetControls)
						return UI.RowActions({
							open = open,
							coordinator = coordinator,
							content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
							trailing = {
								{
									id = "Delete",
									label = "Delete",
									role = "destructive" :: "destructive",
									onActivate = function()
										invoked += 1
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						})
					end, { motionLevel = "normal" })
					local row = world.node
					row.AbsoluteSize = V2(world, 300, 40)
					world.engine.heartbeat.fire(1)
					local content = find(row, "Content")
					local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					find(row, "Delete").Activated.fire()
					Verify.expect(invoked):toBe(0)
					Verify.expect(detector.Enabled):toBe(false)
					open:set(nil)
					coordinator:set({})
					world.gui.SelectedObject = find(row, "Action")
					Verify.expect((action(world.root, "RowActionsClose"))):toBeNil()
					Verify.expect((action(world.root, "RowActionsDelete"))):toBeNil()
					detector.DragStart.fire(V2(world, 20, 20))
					detector.DragContinue.fire(V2(world, 280, 20))
					detector.DragEnd.fire()
					world.engine.heartbeat.fire(0.1)
					Verify.expect(content.Position.X.Offset < -88):toBe(true)
					Verify.expect(invoked):toBe(0)
					local lowest = row.Size.Y.Offset
					for _ = 1, 30 do
						world.engine.heartbeat.fire(1 / 60)
						lowest = math.min(lowest, row.Size.Y.Offset)
					end
					Verify.expect(invoked):toBe(1)
					Verify.expect(lowest):toBe(0)
					for _ = 1, 30 do
						world.engine.heartbeat.fire(1 / 60)
					end
					Verify.expect(invoked):toBe(1)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-76 lets one of two real list rows stay open and releases the claim on removal",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-76 lets one of two real list rows stay open and releases the claim on removal",
				run = function()
					local coordinator = Compose.cell(nil :: any)
					local source = Compose.cell(records(3))
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = source,
							key = key,
							itemSize = 44,
							render = function(current): GuiObject
								return UI.RowActions({
									coordinator = coordinator,
									content = UI.Button("Action")({
										label = function(use: Use)
											return use(current).label
										end,
									}) :: GuiObject,
									trailing = { { id = "Save", label = "Save" } :: FixtureCollectionTypes.RowAction },
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
					Verify.expect((opened(1))):toBe(true)
					swipe(2)
					Verify.expect((opened(1))):toBe(false)
					Verify.expect((opened(2))):toBe(true)
					Verify.expect((opened(3))):toBe(false)
					Verify.expect(coordinator:peek() ~= nil):toBe(true)
					source:set({ records(3)[1], records(3)[3] })
					Verify.expect((world.node:FindFirstChild("2", true))):toBeNil()
					Verify.expect((coordinator:peek())):toBeNil()
					swipe(3)
					Verify.expect((opened(3))):toBe(true)
					Verify.expect((opened(1))):toBe(false)
					world.stop()
				end,
			}
		)

		verifyHarness:case("collections-65 slides, opens, commits, closes and coordinates swipes on real table rows", {
			id = "native_parity_weaker_rows::native parity weaker rows::collections-65 slides, opens, commits, closes and coordinates swipes on real table rows",
			run = function()
				local invoked = {}
				local world = setup(function(UI: FacetControls)
					return UI.Table({
						from = records(4),
						key = key,
						itemSize = 44,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
						rowActions = function(_, rowKey: number): RowActions?
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
				nativeDrag.measure(body)
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
					Verify.expect(content.Position.X.Offset < previous):toBe(true)
					previous = content.Position.X.Offset
				end
				Verify.expect(find(first, "trailing").Visible):toBe(true)
				detector.DragEnd.fire()
				Verify.expect(content.Position.X.Offset):toBe(-176)
				detector.DragStart.fire(V2(world, 100, 20))
				detector.DragContinue.fire(V2(world, 220, 20))
				detector.DragEnd.fire()
				Verify.expect(content.Position.X.Offset):toBe(0)
				Verify.expect(find(first, "trailing").Visible):toBe(false)
				detector.DragStart.fire(V2(world, 150, 20))
				detector.DragContinue.fire(V2(world, 145, 80))
				detector.DragContinue.fire(V2(world, 100, 120))
				Verify.expect(content.Position.X.Offset):toBe(0)
				detector.DragEnd.fire()
				Verify.expect(content.Position.X.Offset):toBe(0)
				drag(world, detector, 50, 110)
				Verify.expect(find(first, "leading").Visible):toBe(true)
				Verify.expect(content.Position.X.Offset):toBe(88)
				world.gui.SelectedObject = find(first.Parent, "RowHit")
				local close = action(world.root, "RowActionsClose")
				Verify.expect(close ~= nil):toBe(true)
				close.Pressed.fire()
				Verify.expect(content.Position.X.Offset):toBe(0)
				local second = row(2)
				drag(world, detector, 250, 150)
				Verify.expect(find(first, "trailing").Visible):toBe(true)
				drag(world, second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 250, 150)
				Verify.expect(find(first, "trailing").Visible):toBe(false)
				Verify.expect(find(second, "trailing").Visible):toBe(true)
				Verify.expect(#invoked):toBe(0)
				drag(world, row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"), 290, 10)
				Verify.expect(invoked):toEqual({ "Archive3" })
				Verify.expect(find(row(3), "trailing").Visible):toBe(false)
				world.engine.heartbeat.fire(1 / 60)
				Verify.expect(invoked):toEqual({ "Archive3" })
				world.stop()
			end,
		})

		verifyHarness:case(
			"collections-67 table edit mode leaves action chrome independent and releases swipe capture",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-67 table edit mode leaves action chrome independent and releases swipe capture",
				run = function()
					local deleted, editing = {}, Compose.cell(false)
					local world = setup(function(UI: FacetControls)
						return UI.Table({
							from = records(3),
							key = key,
							itemSize = 44,
							editing = editing,
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
							rowActions = function(_, rowKey: number): RowActions?
								if rowKey == 3 then
									return {
										trailing = {
											{ id = "Flag", label = "Flag" } :: FixtureCollectionTypes.RowAction,
										},
									}
								end
								return {
									trailing = {
										{
											id = "Remove",
											label = "Remove row " .. rowKey,
											role = "destructive" :: "destructive",
											onActivate = function()
												table.insert(deleted, rowKey)
											end,
										} :: FixtureCollectionTypes.RowAction,
									},
								}
							end,
						})
					end)
					local body = find(world.node, "Body")
					body.AbsoluteWindowSize = V2(world, 300, 200)
					nativeDrag.measure(body)
					local function row(rowKey: number): any
						local node = rowActionsIn(body:FindFirstChild(tostring(rowKey), true))
						node.AbsoluteSize = V2(world, 300, 44)
						return node
					end
					for rowKey = 1, 3 do
						Verify.expect((row(rowKey):FindFirstChild("Delete"))):toBeNil()
					end
					editing:set(true)
					for rowKey = 1, 3 do
						Verify.expect((row(rowKey):FindFirstChild("Delete"))):toBeNil()
						Verify.expect(row(rowKey):FindFirstChild("SwipeGrip", true).Visible):toBe(false)
					end
					Verify.expect(deleted):toEqual({})
					world.stop()
				end,
			}
		)

		verifyHarness:case("collections-168 wraps only table rows whose callback returns actions", {
			id = "native_parity_weaker_rows::native parity weaker rows::collections-168 wraps only table rows whose callback returns actions",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Table({
						from = records(4),
						key = key,
						itemSize = 44,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
						rowActions = function(_, rowKey: number): RowActions?
							if rowKey % 2 == 0 then
								return nil
							end
							return { trailing = { { id = "Save", label = "Save" } :: FixtureCollectionTypes.RowAction } }
						end,
					})
				end)
				local body = find(world.node, "Body")
				body.AbsoluteWindowSize = V2(world, 300, 200)
				nativeDrag.measure(body)
				for rowKey = 1, 4 do
					local node = body:FindFirstChild(tostring(rowKey), true)
					local wrapped = rowActionsIn(node)
					if rowKey % 2 == 0 then
						Verify.expect(wrapped):toBeNil()
						Verify.expect((node:FindFirstChildWhichIsA("UIDragDetector", true))):toBeNil()
						Verify.expect(find(node, "RowHit") ~= nil):toBe(true)
						Verify.expect(find(node, "Value").Text):toBe(tostring(rowKey))
					else
						Verify.expect(wrapped ~= nil):toBe(true)
						Verify.expect(
							wrapped:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector") ~= nil
						)
							:toBe(true)
						Verify.expect(find(find(wrapped, "Content"), "Value").Text):toBe(tostring(rowKey))
					end
				end
				world.stop()
			end,
		})

		verifyHarness:case(
			"collections-11 reorders list rows by pointer both ways and leaves plain rows to native panning",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-11 reorders list rows by pointer both ways and leaves plain rows to native panning",
				run = function()
					local requests = {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.VirtualList("Ordered")({
								from = records(6),
								key = key,
								itemSize = 20,
								reorderable = true,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								render = function(current): GuiObject
									return UI.Button("Action")({
										label = function(use: Use)
											return use(current).label
										end,
									})
								end,
							}) :: unknown,
							UI.VirtualList("Plain")({
								from = records(6),
								key = key,
								itemSize = 20,
								render = function(current): GuiObject
									return UI.Button("Action")({
										label = function(use: Use)
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
					Verify.expect((plain:FindFirstChildWhichIsA("UIDragDetector", true))):toBeNil()
					Verify.expect((find(plain, "Move"))):toBeNil()
					for rowKey = 1, 6 do
						local cells = find(ordered:FindFirstChild(tostring(rowKey), true), "Cells")
						Verify.expect(cells:FindFirstChild("FacetCollectionDrag", true) ~= nil):toBe(true)
					end
					local function handle(rowKey: number): any
						return find(ordered:FindFirstChild(tostring(rowKey), true), "Move"):FindFirstChildWhichIsA(
							"UIDragDetector"
						)
					end
					local detector = handle(1)
					detector.DragStart.fire(V2(world, 10, 10))
					detector.DragContinue.fire(V2(world, 10, 75))
					Verify.expect(find(ordered, "DropLine").Position.Y.Offset):toBe(80)
					Verify.expect(ordered:FindFirstChild("1", true).Position.Y.Offset):toBe(0)
					detector.DragContinue.fire(V2(world, 10, 45))
					Verify.expect(find(ordered, "DropLine").Position.Y.Offset):toBe(40)
					detector.DragContinue.fire(V2(world, 10, 75))
					detector.DragEnd.fire()
					Verify.expect(requests):toEqual({ { keys = { 1 }, slot = 3 } })
					Verify.expect((find(ordered, "DropLine"))):toBeNil()
					detector = handle(5)
					detector.DragStart.fire(V2(world, 10, 90))
					detector.DragContinue.fire(V2(world, 10, 25))
					Verify.expect(find(ordered, "DropLine").Position.Y.Offset):toBe(20)
					detector.DragEnd.fire()
					Verify.expect(requests[2]):toEqual({ keys = { 5 }, slot = 1 })
					detector = handle(3)
					detector.DragStart.fire(V2(world, 10, 50))
					detector.DragContinue.fire(V2(world, 10, 45))
					detector.DragEnd.fire()
					Verify.expect(#requests):toBe(2)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-145 keeps the dragged row in place, drags single or block rows and ignores no-op drops",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-145 keeps the dragged row in place, drags single or block rows and ignores no-op drops",
				run = function()
					local requests = {}
					local selected = Compose.cell({ [4] = true, [5] = true })
					local world = setup(function(UI: FacetControls)
						return UI.Table({
							from = records(5),
							key = key,
							itemSize = 20,
							selection = selected,
							selectionMode = "multiple" :: "multiple",
							reorderable = true,
							onReorder = function(keys: { number }, slot: number)
								table.insert(requests, { keys = keys, slot = slot })
							end,
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end)
					local body = find(world.node, "Body")
					body.AbsoluteWindowSize = V2(world, 200, 100)
					nativeDrag.measure(body)
					local function handle(rowKey: number): any
						return body:FindFirstChild(tostring(rowKey), true)
							:FindFirstChild("Move", true)
							:FindFirstChildWhichIsA("UIDragDetector")
					end
					local origin = body:FindFirstChild("1", true)
					local detector = handle(1)
					detector.DragStart.fire(V2(world, 10, 10))
					detector.DragContinue.fire(V2(world, 10, 65))
					Verify.expect((body:FindFirstChild("1", true))):toBe(origin)
					Verify.expect(origin.Position.Y.Offset):toBe(0)
					Verify.expect((find(origin, "Reorderable"):GetAttribute("FacetDragging"))):toBe(true)
					Verify.expect(find(world.node, "DropLine").Position.Y.Offset):toBe(body.Position.Y.Offset + 60)
					Verify.expect(find(world.node, "DragLabel").Text):toBe("1")
					detector.DragEnd.fire()
					Verify.expect(requests):toEqual({ { keys = { 1 }, slot = 2 } })
					Verify.expect((selected:peek())):toEqual({ [4] = true, [5] = true })
					Verify.expect((find(world.node, "DropLine"))):toBeNil()
					detector = handle(4)
					detector.DragStart.fire(V2(world, 10, 70))
					detector.DragContinue.fire(V2(world, 10, 5))
					Verify.expect(find(world.node, "DragLabel").Text):toBe("2 selected")
					detector.DragEnd.fire()
					Verify.expect(requests[2]):toEqual({ keys = { 4, 5 }, slot = 0 })
					selected:set({ [1] = true, [2] = true })
					detector = handle(1)
					detector.DragStart.fire(V2(world, 10, 10))
					detector.DragContinue.fire(V2(world, 10, 3))
					detector.DragEnd.fire()
					detector = handle(3)
					detector.DragStart.fire(V2(world, 10, 50))
					detector.DragContinue.fire(V2(world, 10, 45))
					detector.DragEnd.fire()
					Verify.expect(#requests):toBe(2)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-145 cancels a table drag on focus loss or dismissal and gives non-reorderable tables no drag",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-145 cancels a table drag on focus loss or dismissal and gives non-reorderable tables no drag",
				run = function()
					local requests = {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Table("Ordered")({
								from = records(5),
								key = key,
								itemSize = 20,
								reorderable = true,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								columns = {
									{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								},
							}) :: unknown,
							UI.Table("Fixed")({
								from = records(5),
								key = key,
								itemSize = 20,
								selection = Compose.cell({}),
								columns = {
									{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								},
							}),
						})
					end)
					local body = find(find(world.node, "Ordered"), "Body")
					body.AbsoluteWindowSize = V2(world, 200, 100)
					nativeDrag.measure(body)
					local fixed = find(world.node, "Fixed")
					find(fixed, "Body").AbsoluteWindowSize = V2(world, 200, 100)
					Verify.expect((find(fixed, "Move"))):toBeNil()
					Verify.expect((find(fixed, "ReorderFeedback"))):toBeNil()
					for _, node in find(fixed, "Body"):GetDescendants() do
						Verify.expect((node:IsA("UIDragDetector"))):toBe(false)
					end
					local E = world.engine.types.Enum
					local function begin(rowKey: number): (any, any)
						local move = body:FindFirstChild(tostring(rowKey), true):FindFirstChild("Move", true)
						local detector = move:FindFirstChildWhichIsA("UIDragDetector")
						local pointer = {
							UserInputType = E.UserInputType.MouseButton1,
							UserInputState = E.UserInputState.Begin,
							Position = world.engine.types.Vector3.new(10, 10, 0),
						}
						nativeDrag.press(move, pointer)
						detector.DragStart.fire(V2(world, 10, (rowKey - 1) * 20 + 10))
						detector.DragContinue.fire(V2(world, 10, 90))
						Verify.expect(find(world.node, "DropLine") ~= nil):toBe(true)
						return detector, pointer
					end
					local detector, pointer = begin(1)
					world.input.WindowFocusReleased.fire()
					Verify.expect((find(world.node, "DropLine"))):toBeNil()
					nativeDrag.finish(world.input, pointer)
					detector.DragEnd.fire()
					Verify.expect(#requests):toBe(0)
					detector, pointer = begin(2)
					pointer.UserInputState = E.UserInputState.End
					nativeDrag.finish(world.input, pointer)
					Verify.expect(requests):toEqual({ { keys = { 2 }, slot = 4 } })
					detector, pointer = begin(3)
					world.stop()
					pointer.UserInputState = E.UserInputState.End
					nativeDrag.finish(world.input, pointer)
					detector.DragEnd.fire()
					world.engine.heartbeat.fire(1 / 60)
					Verify.expect(#requests):toBe(1)
				end,
			}
		)

		verifyHarness:case(
			"collections-120 refuses unselectable rows in single mode, refuses pinned grabs and keeps absent predicates open",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-120 refuses unselectable rows in single mode, refuses pinned grabs and keeps absent predicates open",
				run = function()
					local single, requests = Compose.cell({}), {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Table("Guarded")({
								from = records(4),
								key = key,
								itemSize = 20,
								selection = single,
								selectionMode = "single" :: "single",
								selectable = function(item)
									return item.id ~= 2
								end,
								reorderable = true,
								movable = function(item)
									return item.id ~= 3
								end,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								columns = {
									{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								},
							}) :: unknown,
							UI.Table("Open")({
								from = records(4),
								key = key,
								itemSize = 20,
								selection = Compose.cell({}),
								selectionMode = "multiple" :: "multiple",
								editing = true,
								reorderable = true,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot, open = true })
								end,
								columns = {
									{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								},
							}),
						})
					end)
					local guarded, openTable =
						find(find(world.node, "Guarded"), "Body"), find(find(world.node, "Open"), "Body")
					guarded.AbsoluteWindowSize = V2(world, 200, 100)
					openTable.AbsoluteWindowSize = V2(world, 200, 100)
					local function hit(body: any, rowKey: number): any
						return find(body:FindFirstChild(tostring(rowKey), true), "RowHit")
					end
					hit(guarded, 1).Activated.fire()
					Verify.expect((single:peek())):toEqual({ [1] = true })
					hit(guarded, 2).Activated.fire()
					Verify.expect((single:peek())):toEqual({ [1] = true })
					hit(guarded, 3).Activated.fire()
					Verify.expect((single:peek())):toEqual({ [3] = true })
					local pinned = guarded:FindFirstChild("3", true):FindFirstChild("Move", true)
					Verify.expect(pinned.Interactable):toBe(false)
					pinned.Activated.fire()
					Verify.expect((find(world.node, "DropLine"))):toBeNil()
					Verify.expect((action(world.root, "ReorderDrop"))):toBeNil()
					local detector = pinned:FindFirstChildWhichIsA("UIDragDetector")
					Verify.expect(detector.Enabled):toBe(false)
					detector.DragStart.fire(V2(world, 10, 50))
					detector.DragContinue.fire(V2(world, 10, 5))
					detector.DragEnd.fire()
					Verify.expect(#requests):toBe(0)
					for rowKey = 1, 4 do
						local move = openTable:FindFirstChild(tostring(rowKey), true):FindFirstChild("Move", true)
						Verify.expect(move.Interactable):toBe(true)
						Verify.expect(move:FindFirstChildWhichIsA("UIDragDetector").Enabled):toBe(true)
						hit(openTable, rowKey).Activated.fire()
					end
					for rowKey = 1, 4 do
						Verify.expect(
							(
								find(openTable:FindFirstChild(tostring(rowKey), true), "Row"):GetAttribute(
									"FacetSelected"
								)
							)
						)
							:toBe(true)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"collections-122 protects deletion on every route through table and list hosts but keeps other actions",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-122 protects deletion on every route through table and list hosts but keeps other actions",
				run = function()
					for _, host in { "table", "list" } do
						local deleted, flagged, editing = {}, {}, Compose.cell(false)
						local function actionsFor(current: any, rowKey: number): any
							return {
								trailing = {
									{
										id = "Delete",
										label = "Delete",
										role = "destructive" :: "destructive",
										enabled = function(use: Use)
											return use(current).id ~= 2
										end,
										onActivate = function()
											table.insert(deleted, rowKey)
										end,
									} :: FixtureCollectionTypes.RowAction,
									{
										id = "Flag",
										label = "Flag",
										onActivate = function()
											table.insert(flagged, rowKey)
										end,
									} :: FixtureCollectionTypes.RowAction,
								},
							}
						end
						local world = setup(function(UI: FacetControls)
							if host == "table" then
								return UI.Table({
									from = records(4),
									key = key,
									itemSize = 44,
									editing = editing,
									columns = {
										{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
									},
									rowActions = actionsFor,
								})
							end
							return UI.VirtualList({
								from = records(4),
								key = key,
								itemSize = 44,
								selection = Compose.cell({}),
								render = function(current, _, rowKey): GuiObject
									local spec = actionsFor(current, rowKey)
									spec.editing = editing
									spec.content = UI.Button("Action")({ label = tostring(rowKey) })
									return UI.RowActions(spec)
								end,
							})
						end)
						local body = if host == "table" then find(world.node, "Body") else world.node
						body.AbsoluteWindowSize = V2(world, 300, 200)
						nativeDrag.measure(body)
						local function row(rowKey: number): any
							local node = rowActionsIn(body:FindFirstChild(tostring(rowKey), true))
							node.AbsoluteSize = V2(world, 300, 44)
							return node
						end
						local protected = row(2)
						local detector =
							protected:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
						drag(world, detector, 290, 5)
						Verify.expect(deleted):toEqual({})
						drag(world, detector, 250, 150)
						local trayDelete = find(find(protected, "trailing"), "Delete")
						Verify.expect(find(protected, "trailing").Visible):toBe(true)
						Verify.expect(trayDelete.Interactable):toBe(false)
						trayDelete.Activated.fire()
						Verify.expect(deleted):toEqual({})
						find(find(protected, "trailing"), "Flag").Activated.fire()
						Verify.expect(flagged):toEqual({ 2 })
						editing:set(true)
						Verify.expect((protected:FindFirstChild("Delete"))):toBeNil()
						Verify.expect(`{host}:{row(1):FindFirstChild("Delete") ~= nil}`):toBe(`{host}:{host == "list"}`)
						editing:set(false)
						world.gui.SelectedObject = find(body:FindFirstChild("2", true), "RowHit")
						Verify.expect(world.gui.SelectedObject ~= nil):toBe(true)
						Verify.expect((action(world.root, "RowActionsDelete"))):toBeNil()
						protected.InputBegan.fire({
							UserInputType = world.engine.types.Enum.UserInputType.MouseButton2,
							Position = world.engine.types.Vector3.new(50, 50, 0),
						})
						local menuDelete = find(world.root, "trailing:Delete")
						Verify.expect(menuDelete.Interactable):toBe(false)
						menuDelete.Activated.fire()
						Verify.expect(deleted):toEqual({})
						find(world.root, "trailing:Flag").Activated.fire()
						Verify.expect(flagged):toEqual({ 2, 2 })
						Verify.expect((find(world.root, "MenuPanel"))):toBeNil()
						world.gui.SelectedObject = find(body:FindFirstChild("3", true), "RowHit")
						local delete = action(world.root, "RowActionsDelete")
						Verify.expect(delete ~= nil):toBe(true)
						delete.Pressed.fire()
						Verify.expect(deleted):toEqual({ 3 })
						world.engine.heartbeat.fire(1 / 60)
						drag(
							world,
							row(4):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
							290,
							5
						)
						Verify.expect(deleted):toEqual({ 3, 4 })
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"collections-116 refuses locked selection, pinned movement and protected deletion in the run sheet",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-116 refuses locked selection, pinned movement and protected deletion in the run sheet",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local target = engine.new("Folder")
					local guiService = engine.new("GuiService")
					local ctx = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
						types = engine.types,
						guiService = guiService,
						UI = Facet.controls(
							runtime,
							{
								types = engine.types,
								guiService = guiService,
								services = { GuiService = guiService },
								inputParent = target,
								motionLevel = "none",
							} :: any
						),
					}
					local built
					local stop, node: any = runtime.mount(function()
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
					nativeDrag.measure(body)
					local function row(id: string): any
						return body:FindFirstChild(id, true)
					end
					find(row("warmup"), "RowHit").Activated.fire()
					find(row("notes"), "RowHit").Activated.fire()
					Verify.expect(built.report().selection):toEqual({ warmup = true })
					local height = row("warmup").Position.Y.Offset - row("grid").Position.Y.Offset
					Verify.expect(height > 0):toBe(true)
					local function dragRow(id: string, toY: number)
						local detector = find(row(id), "Move"):FindFirstChildWhichIsA("UIDragDetector")
						detector.DragStart.fire(engine.types.Vector2.new(10, row(id).Position.Y.Offset + height / 2))
						detector.DragContinue.fire(engine.types.Vector2.new(10, toY))
						detector.DragEnd.fire()
					end
					dragRow("grid", height * 4.5)
					Verify.expect((ids())):toBe("grid,warmup,main,notes,cool")
					find(row("grid"), "Move").Activated.fire()
					Verify.expect((find(node, "DropLine"))):toBeNil()
					dragRow("warmup", 2)
					Verify.expect((ids())):toBe("grid,warmup,main,notes,cool")
					dragRow("cool", height * 1.5 + 2)
					Verify.expect((ids())):toBe("grid,warmup,cool,main,notes")
					local protected = rowActionsIn(row("main"))
					protected.AbsoluteSize = engine.types.Vector2.new(500, 44)
					local detector =
						protected:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart.fire(engine.types.Vector2.new(480, 20))
					detector.DragContinue.fire(engine.types.Vector2.new(10, 20))
					detector.DragEnd.fire()
					Verify.expect(#built.report().rows):toBe(5)
					guiService.SelectedObject = find(row("main"), "RowHit")
					Verify.expect((action(target, "RowActionsDelete"))):toBeNil()
					Verify.expect(#built.report().rows):toBe(5)
					Verify.expect(built.report().message)
						:toBe(require("../examples/gallery/scenarios/row_capabilities").copy.refusalIdle)
					local open = rowActionsIn(row("cool"))
					open.AbsoluteSize = engine.types.Vector2.new(500, 44)
					guiService.SelectedObject = find(row("cool"), "RowHit")
					action(target, "RowActionsDelete").Pressed.fire()
					Verify.expect((ids())):toBe("grid,warmup,main,notes")
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"collections-281 locks, coordinates, releases, fires once and follows reactive actions inside list rows",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-281 locks, coordinates, releases, fires once and follows reactive actions inside list rows",
				run = function()
					local coordinator = Compose.cell(nil :: any)
					local source = Compose.cell({
						{ id = 1, label = "1", armed = true },
						{ id = 2, label = "2", armed = true },
						{ id = 3, label = "3", armed = false },
						{ id = 4, label = "4", armed = true },
					})
					local invoked = {}
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = source,
							key = key,
							itemSize = 44,
							render = function(current, _, rowKey): GuiObject
								return UI.RowActions({
									coordinator = coordinator,
									content = UI.Button("Action")({ label = tostring(rowKey) }) :: GuiObject,
									trailing = function(use: Use)
										if not use(current).armed then
											return {}
										end
										return {
											{
												id = "Delete",
												label = "Delete",
												role = "destructive" :: "destructive",
												onActivate = function()
													table.insert(invoked, rowKey)
												end,
											},
										}
									end,
								})
							end,
						})
					end, { motionLevel = "normal" })
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
					Verify.expect(find(first, "Content").Position.X.Offset):toBe(0)
					detector.DragEnd.fire()
					settle()
					Verify.expect(find(first, "trailing").Visible):toBe(false)
					drag(world, detector, 250, 150)
					settle()
					Verify.expect(find(first, "trailing").Visible):toBe(true)
					drag(
						world,
						row(2):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						250,
						150
					)
					settle()
					Verify.expect(find(first, "trailing").Visible):toBe(false)
					Verify.expect(find(row(2), "trailing").Visible):toBe(true)
					Verify.expect(
						row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled
					)
						:toBe(false)
					local armed = table.clone(source:peek())
					armed[3] = { id = 3, label = "3", armed = true }
					source:set(armed)
					Verify.expect(
						row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled
					)
						:toBe(true)
					drag(
						world,
						row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						250,
						150
					)
					settle()
					Verify.expect(find(row(3), "trailing").Visible):toBe(true)
					local disarmed = table.clone(source:peek())
					disarmed[3] = { id = 3, label = "3", armed = false }
					source:set(disarmed)
					settle()
					Verify.expect(
						row(3):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled
					)
						:toBe(false)
					Verify.expect(find(row(3), "trailing").Visible):toBe(false)
					Verify.expect(find(row(3), "Content").Position.X.Offset):toBe(0)
					source:set(armed)
					settle()
					Verify.expect(find(row(3), "trailing").Visible):toBe(false)
					Verify.expect(find(row(3), "Content").Position.X.Offset):toBe(0)
					local second = row(2):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					drag(world, second, 250, 150)
					settle()
					Verify.expect(find(row(2), "trailing").Visible):toBe(true)
					second.DragStart.fire(V2(world, 250, 20))
					second.DragContinue.fire(V2(world, 200, 20))
					source:set({ source:peek()[1], source:peek()[3], source:peek()[4] })
					second.DragEnd.fire()
					Verify.expect((world.node:FindFirstChild("2", true))):toBeNil()
					Verify.expect((coordinator:peek())):toBeNil()
					local fourth = row(4):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
					drag(world, fourth, 290, 5)
					Verify.expect(#invoked):toBe(0)
					drag(world, fourth, 290, 5)
					drag(
						world,
						row(1):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						250,
						150
					)
					settle()
					Verify.expect(invoked):toEqual({ 4 })
					Verify.expect(row(4).Size.Y.Offset):toBe(44)
					world.stop()
					Verify.expect((coordinator:peek())):toBeNil()
				end,
			}
		)

		verifyHarness:case("collections-281 keeps a model-owned open row slid when virtualization remounts it", {
			id = "native_parity_weaker_rows::native parity weaker rows::collections-281 keeps a model-owned open row slid when virtualization remounts it",
			run = function()
				local opens: { [number]: any } = {}
				local world = setup(function(UI: FacetControls)
					return UI.VirtualList({
						from = records(30),
						key = key,
						itemSize = 44,
						overscan = 0,
						render = function(_, _, rowKey): GuiObject
							opens[rowKey] = opens[rowKey] or Compose.cell(nil :: string?)
							return UI.RowActions({
								open = opens[rowKey],
								content = UI.Button("Action")({ label = tostring(rowKey) }) :: GuiObject,
								trailing = { { id = "Save", label = "Save" } :: FixtureCollectionTypes.RowAction },
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
				drag(
					world,
					original:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
					250,
					150
				)
				Verify.expect((opens[1]:peek())):toBe("trailing")
				world.node.CanvasPosition = V2(world, 0, 900)
				Verify.expect((world.node:FindFirstChild("1", true))):toBeNil()
				world.node.CanvasPosition = V2(world, 0, 0)
				local returned = row(1)
				Verify.expect(returned ~= nil):toBe(true)
				Verify.expect(find(returned, "trailing").Visible):toBe(true)
				Verify.expect(find(returned, "Content").Position.X.Offset):toBe(-88)
				world.stop()
			end,
		})

		verifyHarness:case(
			"collections-284 measures, taps once, hands off with motion and collapses only the committed list row",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::collections-284 measures, taps once, hands off with motion and collapses only the committed list row",
				run = function()
					local coordinator = Compose.cell(nil :: any)
					local source = Compose.cell(records(3))
					local invoked, keep = {}, true
					local world = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = source,
							key = key,
							itemSize = 44,
							render = function(_, _, rowKey): GuiObject
								return UI.RowActions({
									coordinator = coordinator,
									content = UI.Button("Action")({ label = tostring(rowKey) }) :: GuiObject,
									trailing = {
										{
											id = "Remove",
											label = "Remove",
											role = "destructive" :: "destructive",
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
										} :: FixtureCollectionTypes.RowAction,
									},
								})
							end,
						})
					end, { motionLevel = "normal" })
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
					drag(
						world,
						first:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						280,
						180
					)
					settle()
					Verify.expect(find(first, "trailing").Size.X.Offset):toBe(182)
					Verify.expect(find(first, "Content").Position.X.Offset):toBeCloseTo(-182, 0.5)
					drag(
						world,
						second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						250,
						150
					)
					local previous = find(first, "Content").Position.X.Offset
					local steps = 0
					for _ = 1, 60 do
						world.engine.heartbeat.fire(1 / 60)
						local now = find(first, "Content").Position.X.Offset
						Verify.expect(now >= previous):toBe(true)
						if now < -0.5 then
							steps += 1
						end
						previous = now
					end
					Verify.expect(steps > 2):toBe(true)
					Verify.expect(previous):toBeCloseTo(0, 0.5)
					Verify.expect(find(second, "Content").Position.X.Offset):toBeCloseTo(-88, 0.5)
					find(second, "Remove").Activated.fire({
						UserInputType = world.engine.types.Enum.UserInputType.Touch,
					})
					find(second, "Remove").Activated.fire({
						UserInputType = world.engine.types.Enum.UserInputType.Touch,
					})
					Verify.expect(#invoked):toBe(0)
					local frames = 0
					while #invoked == 0 and frames < 60 do
						world.engine.heartbeat.fire(1 / 60)
						frames += 1
						Verify.expect(first.Size.Y.Offset):toBe(44)
						Verify.expect(row(3).Size.Y.Offset):toBe(44)
					end
					Verify.expect(invoked):toEqual({ 2 })
					Verify.expect(second.Size.Y.Offset):toBe(0)
					settle(90)
					Verify.expect(invoked):toEqual({ 2 })
					Verify.expect(second.Size.Y.Offset):toBe(44)
					Verify.expect(find(second, "trailing").Visible):toBe(false)
					Verify.expect(find(second, "Content").Position.X.Offset):toBeCloseTo(0, 0.5)
					Verify.expect(
						second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector").Enabled
					)
						:toBe(true)
					keep = false
					drag(
						world,
						second:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						290,
						5
					)
					Verify.expect(#invoked):toBe(1)
					settle(20)
					Verify.expect(invoked):toEqual({ 2, 2 })
					Verify.expect((world.node:FindFirstChild("2", true))):toBeNil()
					local standing = 0
					for _, node in world.node:GetDescendants() do
						if node.Name == "Remove" then
							standing += 1
						end
					end
					Verify.expect(standing):toBe(2)
					Verify.expect(row(1).Size.Y.Offset):toBe(44)
					world.stop()
				end,
			}
		)

		verifyHarness:case("inputs-58 removes a remove-only token once through every input, and never while disabled", {
			id = "native_parity_weaker_rows::native parity weaker rows::inputs-58 removes a remove-only token once through every input, and never while disabled",
			run = function()
				local calls, enabled = 0, Compose.cell(true)
				local world = setup(function(UI: FacetControls)
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
				Verify.expect(token.Selectable):toBe(true)
				Verify.expect((token:GetAttribute("AccessibleLabel"))):toBe("Remove Rain")
				Verify.expect(find(token, "Remove").Visible):toBe(true)
				local expected = 0
				for _, inputType in { E.UserInputType.MouseButton1, E.UserInputType.Touch, E.UserInputType.Gamepad1 } do
					token.Activated.fire({ UserInputType = inputType, UserInputState = E.UserInputState.End }, 1)
					expected += 1
					Verify.expect(calls):toBe(expected)
				end
				world.gui.SelectedObject = token
				local activate = action(world.root, "Activate")
				Verify.expect(activate ~= nil):toBe(true)
				activate.Pressed.fire()
				Verify.expect(calls):toBe(expected + 1)
				local delete = action(world.root, "RemoveChip")
				Verify.expect(delete ~= nil):toBe(true)
				delete.Pressed.fire()
				delete.Released.fire()
				Verify.expect(calls):toBe(expected + 2)
				enabled:set(false)
				token.Activated.fire({ UserInputType = E.UserInputType.Touch }, 1)
				Verify.expect((action(world.root, "Activate"))):toBeNil()
				Verify.expect((action(world.root, "RemoveChip"))):toBeNil()
				Verify.expect(calls):toBe(expected + 2)
				world.stop()
			end,
		})

		verifyHarness:case("apps2-40 reorders, swipes Top and Remove, plays on a plain tap and restores the playlist", {
			id = "native_parity_weaker_rows::native parity weaker rows::apps2-40 reorders, swipes Top and Remove, plays on a plain tap and restores the playlist",
			run = function()
				local built, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
				local E = world.engine.types.Enum
				local body = find(node, "Body")
				body.AbsoluteWindowSize = V2(world, 900, 600)
				nativeDrag.measure(body)
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
				Verify.expect((ids(built.baseRows:peek()))):toBe("neon,drift,turbo,pit,photo,apex")
				local height = row("drift").Position.Y.Offset - row("neon").Position.Y.Offset
				local move = find(row("neon"), "Move"):FindFirstChildWhichIsA("UIDragDetector")
				move.DragStart.fire(V2(world, 20, height / 2))
				move.DragContinue.fire(V2(world, 20, row("turbo").Position.Y.Offset + height * 0.75))
				move.DragEnd.fire()
				Verify.expect((ids(built.baseRows:peek()))):toBe("drift,turbo,neon,pit,photo,apex")
				local tap = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.End }
				find(row("pit"), "RowHit").Activated.fire(tap, 1)
				Verify.expect((built.nowPlaying:peek())):toBe("Pit Lane Shuffle")
				Verify.expect(find(actions("pit"), "leading").Visible):toBe(false)
				Verify.expect(find(actions("pit"), "trailing").Visible):toBe(false)
				Verify.expect(find(actions("pit"), "Content").Position.X.Offset):toBe(0)
				drag(
					world,
					actions("pit"):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
					300,
					420
				)
				Verify.expect(find(actions("pit"), "leading").Visible):toBe(true)
				Verify.expect((ids(built.baseRows:peek()))):toBe("drift,turbo,neon,pit,photo,apex")
				find(find(actions("pit"), "leading"), "top").Activated.fire(tap, 1)
				Verify.expect((ids(built.baseRows:peek()))):toBe("pit,drift,turbo,neon,photo,apex")
				drag(
					world,
					actions("apex"):FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
					600,
					480
				)
				Verify.expect(find(actions("apex"), "trailing").Visible):toBe(true)
				Verify.expect(#built.baseRows:peek()):toBe(6)
				find(find(actions("apex"), "trailing"), "remove").Activated.fire(tap, 1)
				Verify.expect((ids(built.baseRows:peek()))):toBe("pit,drift,turbo,neon,photo")
				Verify.expect((row("apex"))):toBeNil()
				built.ratingFor("neon"):set(1)
				find(node, "Restore").Activated.fire(tap, 1)
				Verify.expect((ids(built.baseRows:peek()))):toBe("neon,drift,turbo,pit,photo,apex")
				Verify.expect((built.ratingFor("neon"):peek())):toBe(4)
				Verify.expect((built.nowPlaying:peek())):toBeNil()
				Verify.expect(row("apex") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"apps2-39 grabs, steps and drops a playlist row by gamepad and reaches a swiped tray's Remove",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::apps2-39 grabs, steps and drops a playlist row by gamepad and reaches a swiped tray's Remove",
				run = function()
					local built, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
					local E = world.engine.types.Enum
					local body = find(node, "Body")
					body.AbsoluteWindowSize = V2(world, 900, 600)
					nativeDrag.measure(body)
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
					Verify.expect(world.gui.SelectedObject.Name):toBe("Drop")
					local function keys(name: string): { string }
						local out = {}
						for _, binding in action(world.root, name):GetChildren() do
							table.insert(out, binding.KeyCode.Name)
						end
						table.sort(out)
						return out
					end
					Verify.expect(table.find(keys("ReorderDown"), "DPadDown") ~= nil):toBe(true)
					Verify.expect(table.find(keys("ReorderDrop"), "ButtonA") ~= nil):toBe(true)
					action(world.root, "ReorderDown").Pressed.fire()
					action(world.root, "ReorderDown").Pressed.fire()
					action(world.root, "ReorderDrop").Pressed.fire()
					Verify.expect((ids())):toBe("drift,turbo,neon,pit,photo,apex")
					Verify.expect((action(world.root, "ReorderDrop"))):toBeNil()
					local turbo = rowActionsIn(body:FindFirstChild("turbo", true))
					turbo.AbsoluteSize = V2(world, 844, 44)
					local hit = find(body:FindFirstChild("turbo", true), "RowHit")
					world.gui.SelectedObject = hit
					drag(
						world,
						turbo:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						600,
						480
					)
					local remove = find(find(turbo, "trailing"), "remove")
					Verify.expect(remove.Selectable):toBe(true)
					Verify.expect(remove.Interactable):toBe(true)
					Verify.expect(world.gui.SelectedObject):toBe(remove)
					local close = action(world.root, "RowActionsClose")
					Verify.expect(close ~= nil):toBe(true)
					close.Pressed.fire()
					Verify.expect(world.gui.SelectedObject):toBe(hit)
					drag(
						world,
						turbo:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector"),
						600,
						480
					)
					Verify.expect(world.gui.SelectedObject):toBe(remove)
					remove.Activated.fire(pad, 1)
					Verify.expect((ids())):toBe("drift,neon,pit,photo,apex")
					world.stop()
				end,
			}
		)

		verifyHarness:case("apps2-39 keeps a selected Move handle out of the engine drag so ButtonA grabs the row", {
			id = "native_parity_weaker_rows::native parity weaker rows::apps2-39 keeps a selected Move handle out of the engine drag so ButtonA grabs the row",
			run = function()
				local _, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
				find(node, "Edit").Activated.fire()
				local body = find(node, "Body")
				body.AbsoluteWindowSize = V2(world, 900, 600)
				nativeDrag.measure(body)
				local handle = find(body:FindFirstChild("neon", true), "Move")
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				Verify.expect(detector.Enabled):toBe(true)
				world.gui.SelectedObject = handle
				Verify.expect(detector.Enabled):toBe(false)
				world.gui.SelectedObject = find(body:FindFirstChild("drift", true), "Move")
				Verify.expect(detector.Enabled):toBe(true)
				world.gui.SelectedObject = nil
				Verify.expect(detector.Enabled):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"apps2-38 selects playlist rows additively in Edit by touch and reorders by a touch handle drag",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::apps2-38 selects playlist rows additively in Edit by touch and reorders by a touch handle drag",
				run = function()
					local built, node, world = mountGallery("../examples/gallery/examples/02_playlist_table")
					local E = world.engine.types.Enum
					world.input.PreferredInput = E.PreferredInput.Touch
					find(node, "Edit").Activated.fire()
					local body = find(node, "Body")
					body.AbsoluteWindowSize = V2(world, 900, 600)
					nativeDrag.measure(body)
					local function selected(id: string): boolean
						return find(body:FindFirstChild(id, true), "Row"):GetAttribute("FacetSelected") == true
					end
					local tap = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.End }
					find(body:FindFirstChild("turbo", true), "RowHit").Activated.fire(tap, 1)
					find(body:FindFirstChild("pit", true), "RowHit").Activated.fire(tap, 1)
					Verify.expect((selected("turbo"))):toBe(true)
					Verify.expect((selected("pit"))):toBe(true)
					Verify.expect((selected("neon"))):toBe(false)
					find(body:FindFirstChild("pit", true), "RowHit").Activated.fire(tap, 1)
					Verify.expect((selected("pit"))):toBe(false)
					Verify.expect((selected("turbo"))):toBe(true)
					find(body:FindFirstChild("turbo", true), "RowHit").Activated.fire(tap, 1)
					local height = body:FindFirstChild("drift", true).Position.Y.Offset
						- body:FindFirstChild("neon", true).Position.Y.Offset
					local handle = find(body:FindFirstChild("neon", true), "Move")
					local finger = {
						UserInputType = E.UserInputType.Touch,
						UserInputState = E.UserInputState.Begin,
						Position = world.engine.types.Vector3.new(20, height / 2, 0),
					}
					nativeDrag.press(handle, finger)
					local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart.fire(V2(world, 20, height / 2))
					finger.UserInputState = E.UserInputState.Change
					finger.Position = world.engine.types.Vector3.new(20, height * 1.5 + height * 0.25, 0)
					nativeDrag.move(world.input, finger)
					Verify.expect(find(node, "DropLine") ~= nil):toBe(true)
					detector.DragEnd.fire()
					Verify.expect(built.baseRows:peek()[1].id):toBe("drift")
					finger.UserInputState = E.UserInputState.End
					nativeDrag.finish(world.input, finger)
					Verify.expect(built.baseRows:peek()[1].id):toBe("drift")
					Verify.expect(built.baseRows:peek()[2].id):toBe("neon")
					Verify.expect((find(node, "DropLine"))):toBeNil()
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"apps2-265 grows the streamed reply, swipes a message away and clears from the conversation menu",
			{
				id = "native_parity_weaker_rows::native parity weaker rows::apps2-265 grows the streamed reply, swipes a message away and clears from the conversation menu",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
							motionLevel = "none",
						})
						local _, chat: any = runtime.mount(views.Chat, target)
						local send = find(chat, "Send")
						model.chat.draft:set("What game should I play with friends?")
						send.Activated.fire()
						Verify.expect((model.chat.streaming:peek())):toBe(true)
						find(chat, "Messages").AbsoluteWindowSize = engine.types.Vector2.new(850, 300)
						local reply = find(find(chat, "Message_2"), "Message")
						Verify.expect(find(find(chat, "Message_2"), "Thinking") ~= nil):toBe(true)
						local previous = 0
						local grew = 0
						for _ = 1, 6 do
							model.step(0.1, true)
							local shown = utf8.len(reply.Text) or #reply.Text
							Verify.expect(#reply.Text):toBe(model.chat.streamedChars:peek())
							Verify.expect(shown >= previous):toBe(true)
							if shown > previous then
								grew += 1
							end
							previous = shown
						end
						Verify.expect(grew > 1):toBe(true)
						Verify.expect(model.chat.streamedChars:peek() < model.chat.totalChars:peek()):toBe(true)
						Verify.expect((find(find(chat, "Message_2"), "Thinking"))):toBe(nil)
						send.Activated.fire()
						Verify.expect((model.chat.streaming:peek())):toBe(false)
						find(chat, "Messages").AbsoluteWindowSize = engine.types.Vector2.new(850, 300)
						Verify.expect(#model.chat.messages:peek()):toBe(2)
						local row = find(chat, "MessageActions_2")
						row.AbsoluteSize = engine.types.Vector2.new(800, 60)
						local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
						detector.DragStart.fire(engine.types.Vector2.new(780, 20))
						detector.DragContinue.fire(engine.types.Vector2.new(20, 20))
						detector.DragEnd.fire()
						Verify.expect(#model.chat.messages:peek()):toBe(1)
						Verify.expect(model.chat.messages:peek()[1].role):toBe("user")
						find(chat, "ConversationMenu").Activated.fire()
						local panel = find(target, "MenuPanel")
						Verify.expect(find(panel, "Suggest") ~= nil):toBe(true)
						local clear = find(panel, "Clear")
						Verify.expect((clear:GetAttribute("role"))):toBe("destructive")
						clear.Activated.fire()
						Verify.expect(#model.chat.messages:peek()):toBe(0)
					end, runtime.reactor)
					lifetime.dispose()
					runtime:dispose()
				end,
			}
		)
	end)
end
