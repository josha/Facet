--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local nativeDrag = require("./lib/native_drag")

	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type FolderConstructor = typeof(require("@repo/tools/typecheck/aliases").FolderConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local transitionOf = require("./lib/transition")
	local fs = require("@lune/fs")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

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
			if child:IsA("InputContext") and child.Enabled then
				local found = child:FindFirstChild(name)
				if found and found.Enabled ~= false then
					return found
				end
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			input.TouchEnabled = settings.preferredInput == "Touch"
			input.GamepadEnabled = settings.preferredInput == "Gamepad"
		end
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = root,
			overlayParent = root,
			motionLevel = "none",
		}
		for key, value in settings.config or {} do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, node: any = runtime.mount(function()
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
		nativeDrag.move(world.input, input)
	end

	local function release(world: World, input: any)
		input.UserInputState = world.engine.types.Enum.UserInputState.End
		nativeDrag.finish(world.input, input)
	end

	local function compass(picked: { string }): { any }
		local entries = {}
		for _, id in { "N", "E", "S", "W" } do
			table.insert(entries, {
				id = id,
				slot = id,
				label = id,
				completion = "stay" :: "stay",
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

	verifyHarness:suite("pointer, touch and drag strength", function()
		verifyHarness:case("swaps a dragged Match3 tile only with the orthogonal neighbour in the drag direction", {
			id = "native_parity_weaker_pointer::pointer, touch and drag strength::swaps a dragged Match3 tile only with the orthogonal neighbour in the drag direction",
			run = function()
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
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local target = engine.new("Folder")
					local viewport = Compose.cell({ width = 800, height = 600 })
					local ctx: any = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
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
					local stop, node: any = runtime.mount(function()
						gallery.configure(ctx)
						ctx.UI = Facet.controls(
							runtime,
							{
								types = engine.types,
								viewport = viewport,
								motionLevel = (
										Compose.formula(function(use: Use): "normal" | "limited" | "none"
											return if ctx.reducedMotion and use(ctx.reducedMotion)
												then "none"
												else "normal"
										end) :: unknown
									) :: MotionLevel,
							} :: any
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
					drag.DragStart:Fire(origin)
					drag.DragContinue:Fire(destination)
					drag.DragEnd:Fire(destination)
					if swapRow == 0 then
						Verify.expect((game.isResolving())):toBe(false)
						for row = 1, 6 do
							for col = 1, 6 do
								Verify.expect((game.tileIdAt(row, col))):toBe(ids[row][col])
							end
						end
					else
						Verify.expect((game.isResolving())):toBe(true)
						Verify.expect((game.tileIdAt(swapRow, swapCol))):toBe(ids[fromRow][fromCol])
						Verify.expect((game.tileIdAt(fromRow, fromCol))):toBe(ids[swapRow][swapCol])
						for row = 1, 6 do
							for col = 1, 6 do
								local moved = (row == fromRow and col == fromCol) or (row == swapRow and col == swapCol)
								if not moved then
									Verify.expect((game.tileIdAt(row, col))):toBe(ids[row][col])
								end
							end
						end
						Verify.expect(math.abs(swapRow - fromRow) + math.abs(swapCol - fromCol)):toBe(1)
					end
					for _ = 1, 2400 do
						if game.phase() == "idle" then
							break
						end
						engine.heartbeat:Fire(0.01)
					end
					Verify.expect((game.phase())):toBe("idle")
					local matched = swapRow == 2 and swapCol == 3
					Verify.expect((game.moves())):toBe(if matched then 1 else 0)
					Verify.expect(game.score() > 0):toBe(matched)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case(
			"latches a launcher tap open without a commit and keeps every ring target at the touch floor",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::latches a launcher tap open without a commit and keeps every ring target at the touch floor",
				run = function()
					local picked = {}
					local opened = Compose.cell(false)
					local world =
						radial({ isPresented = opened, distribution = "compass" :: "compass", items = compass(picked) })
					local launcher = find(world.root, "Launcher")
					for _, point in { { 0, 0 }, { 320, 240 } } do
						local press = touch(world, point[1], point[2])
						nativeDrag.press(launcher, press)
						Verify.expect((opened:peek())):toBe(true)
						release(world, press)
						launcher.Activated:Fire(press)
						Verify.expect((opened:peek())):toBe(true)
						Verify.expect(#picked):toBe(0)
						Verify.expect((presentation(world))):toBe("radial")
						opened:set(false)
						launcher.Activated:Fire({
							UserInputType = world.engine.types.Enum.UserInputType.Gamepad1,
							KeyCode = world.engine.types.Enum.KeyCode.ButtonA,
						})
						Verify.expect((opened:peek())):toBe(true)
						Verify.expect(#picked):toBe(0)
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
							nativeDrag.press(panel, press)
							release(world, press)
							Verify.expect(#picked):toBe(before + 1)
							Verify.expect(picked[#picked]):toBe(id)
						end
					end
					Verify.expect((opened:peek())):toBe(true)
					world.stop()
					local crowded = {}
					for index = 1, 24 do
						table.insert(
							crowded,
							{ id = "Item" .. index, label = "Item " .. index, onSelect = function() end }
						)
					end
					local dense = radial({ items = crowded })
					Verify.expect((presentation(dense))):toBe("list")
					for index = 1, 24 do
						Verify.expect(find(dense.root, "Item" .. index).Size.Y.Offset):toBe(44)
					end
					dense.stop()
				end,
			}
		)

		verifyHarness:case(
			"previews a dragged or hovered choice without running it and cancels when the drag returns to the center",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::previews a dragged or hovered choice without running it and cancels when the drag returns to the center",
				run = function()
					local picked = {}
					local opened = Compose.cell(false)
					local items = compass(picked)
					for _, item in items do
						item.icon, item.labelStyle = "flag" :: "flag", "icon"
					end
					local world = radial({ isPresented = opened, distribution = "compass" :: "compass", items = items })
					local launcher = find(world.root, "Launcher")
					world.input.GetLastInputType = function()
						return world.engine.types.Enum.UserInputType.MouseMovement
					end
					for _, kind in { "Touch", "MouseButton1" } :: { "MouseButton1" | "Touch" } do
						local press = touch(world, 320, 240)
						press.UserInputType = world.engine.types.Enum.UserInputType[kind]
						nativeDrag.press(launcher, press)
						Verify.expect((opened:peek())):toBe(true)
						local south = find(world.root, "S")
						Verify.expect((south:HasTag("facet-selected"))):toBe(false)
						if kind == "Touch" then
							moveTo(world, press, 320, 370)
						else
							nativeDrag.move(world.input, {
								UserInputType = world.engine.types.Enum.UserInputType.MouseMovement,
								UserInputState = world.engine.types.Enum.UserInputState.Change,
								Position = world.engine.types.Vector3.new(320, 370, 0),
							})
						end
						Verify.expect((preview(world))):toBe("S")
						Verify.expect((south:HasTag("facet-selected"))):toBe(true)
						Verify.expect(#picked):toBe(0)
						if kind == "Touch" then
							moveTo(world, press, 321, 239)
						else
							nativeDrag.move(world.input, {
								UserInputType = world.engine.types.Enum.UserInputType.MouseMovement,
								UserInputState = world.engine.types.Enum.UserInputState.Change,
								Position = world.engine.types.Vector3.new(321, 239, 0),
							})
						end
						Verify.expect(preview(world) ~= "S"):toBe(true)
						Verify.expect((south:HasTag("facet-selected"))):toBe(false)
						press.Position = world.engine.types.Vector3.new(321, 239, 0)
						release(world, press)
						launcher.Activated:Fire(press)
						Verify.expect(#picked):toBe(0)
						Verify.expect((south:HasTag("facet-selected"))):toBe(false)
						local east = find(world.root, "E")
						east.MouseEnter:Fire()
						Verify.expect((preview(world))):toBe("E")
						Verify.expect((east:HasTag("facet-selected"))):toBe(true)
						Verify.expect(#picked):toBe(0)
						east.MouseLeave:Fire()
						Verify.expect(preview(world) ~= "E"):toBe(true)
						Verify.expect((east:HasTag("facet-selected"))):toBe(false)
						opened:set(false)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"commits once when native Activated arrives before the release and when a list launcher echoes a touch",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::commits once when native Activated arrives before the release and when a list launcher echoes a touch",
				run = function()
					local picked = {}
					local world = radial({
						distribution = "compass" :: "compass",
						completion = "stay" :: "stay",
						items = compass(picked),
					})
					local north = find(world.root, "N")
					local press = touch(world, 320, 110)
					nativeDrag.press(north, press)
					north.Activated:Fire(press)
					Verify.expect(#picked):toBe(1)
					release(world, press)
					Verify.expect(#picked):toBe(1)
					local after = touch(world, 320, 110)
					nativeDrag.press(north, after)
					release(world, after)
					north.Activated:Fire(after)
					Verify.expect(#picked):toBe(2)
					world.stop()
					local listPicked = {}
					local opened = Compose.cell(false)
					local listWorld = radial({
						isPresented = opened,
						distribution = "compass" :: "compass",
						items = compass(listPicked),
					})
					local launcher = find(listWorld.root, "Launcher")
					local tap = touch(listWorld, 0, 0)
					nativeDrag.press(launcher, tap)
					Verify.expect((opened:peek())):toBe(true)
					find(listWorld.root, "Modal").AbsoluteSize = V2(listWorld, 420, 200)
					Verify.expect((presentation(listWorld))):toBe("list")
					release(listWorld, tap)
					launcher.Activated:Fire(tap)
					Verify.expect((opened:peek())):toBe(true)
					Verify.expect(#listPicked):toBe(0)
					find(listWorld.root, "E").Activated:Fire(touch(listWorld, 40, 40))
					Verify.expect(#listPicked):toBe(1)
					Verify.expect(listPicked[1]):toBe("E")
					nativeDrag.finish(listWorld.input, touch(listWorld, 40, 40))
					Verify.expect(#listPicked):toBe(1)
					listWorld.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps the radial ring in a short viewport when gestures select by direction and commits beyond it",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::keeps the radial ring in a short viewport when gestures select by direction and commits beyond it",
				run = function()
					for _, mode in { "direction", "bounded" } :: { "bounded" | "direction" } do
						local picked = {}
						local world = radial({
							distribution = "compass" :: "compass",
							gestureSelection = mode :: "bounded" | "direction",
							items = compass(picked),
						})
						find(world.root, "Modal").AbsoluteSize = V2(world, 420, 200)
						Verify.expect((presentation(world))):toBe(if mode == "direction" then "radial" else "list")
						if mode == "direction" then
							local press = touch(world, 210, 100)
							nativeDrag.press(find(world.root, "RadialPanel"), press)
							moveTo(world, press, 710, 100)
							Verify.expect((presentation(world))):toBe("radial")
							Verify.expect((find(world.root, "E"):HasTag("facet-selected"))):toBe(true)
							Verify.expect(#picked):toBe(0)
							release(world, press)
							Verify.expect((table.concat(picked, ","))):toBe("E")
						end
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"cuts the pass-through aperture around a moved anchor and restores capture in the list fallback",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::cuts the pass-through aperture around a moved anchor and restores capture in the list fallback",
				run = function()
					local picked = {}
					local world = radial({
						center = "empty" :: "empty",
						centerPassThrough = true,
						anchor = { x = 200, y = 150 },
						distribution = "compass" :: "compass",
						items = compass(picked),
					})
					local panel = find(world.root, "RadialPanel")
					Verify.expect(panel.Active):toBe(false)
					Verify.expect(find(world.root, "DismissOutside").Visible):toBe(false)
					local covered = 0
					for _, edge in { "Top", "Bottom", "Left", "Right" } :: { "Bottom" | "Left" | "Right" | "Top" } do
						local catcher = find(world.root, "Dismiss" .. edge)
						Verify.expect(catcher.Visible):toBe(true)
						local x, y = catcher.Position.X.Offset, catcher.Position.Y.Offset
						local w, h = catcher.Size.X.Offset, catcher.Size.Y.Offset
						Verify.expect(200 >= x and 200 < x + w and 150 >= y and 150 < y + h):toBe(false)
						covered += w * h
					end
					Verify.expect(covered):toBe(640 * 480 - 80 * 80)
					local through = touch(world, 200, 150)
					nativeDrag.press(panel, through)
					moveTo(world, through, 200, 20)
					release(world, through)
					Verify.expect(#picked):toBe(0)
					local ring = touch(world, 200, 60)
					nativeDrag.press(panel, ring)
					release(world, ring)
					Verify.expect((table.concat(picked, ","))):toBe("N")
					find(world.root, "Modal").AbsoluteSize = V2(world, 180, 180)
					Verify.expect((presentation(world))):toBe("list")
					Verify.expect(panel.Active):toBe(true)
					Verify.expect(find(world.root, "DismissOutside").Visible):toBe(true)
					for _, edge in { "Top", "Bottom", "Left", "Right" } :: { "Bottom" | "Left" | "Right" | "Top" } do
						Verify.expect(find(world.root, "Dismiss" .. edge).Visible):toBe(false)
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"settles row action trays at half the tray width and snaps every repeated short swipe closed",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::settles row action trays at half the tray width and snaps every repeated short swipe closed",
				run = function()
					for _, edge in { "trailing", "leading" } :: { "leading" | "trailing" } do
						local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
							Compose.cell(nil :: ("leading" | "trailing")?)
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
						local detector =
							world.node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
						local sign = if edge == "trailing" then -1 else 1
						local function swipe(distance: number)
							detector.DragStart:Fire(V2(world, 150, 20))
							detector.DragContinue:Fire(V2(world, 150 + sign * distance, 20))
							detector.DragEnd:Fire()
						end
						for _ = 1, 3 do
							swipe(43)
							Verify.expect((open:peek())):toBeNil()
							Verify.expect(world.node:FindFirstChild(edge).Visible):toBe(false)
							Verify.expect(world.node:FindFirstChild("Content").Position.X.Offset):toBe(0)
						end
						swipe(44)
						Verify.expect((open:peek())):toBe(edge)
						Verify.expect(world.node:FindFirstChild("Content").Position.X.Offset):toBe(sign * 88)
						swipe(-45)
						Verify.expect((open:peek())):toBeNil()
						Verify.expect(world.node:FindFirstChild("Content").Position.X.Offset):toBe(0)
						swipe(88)
						Verify.expect((open:peek())):toBe(edge)
						swipe(-44)
						Verify.expect((open:peek())):toBe(edge)
						for _ = 1, 3 do
							open:set(nil)
							swipe(20)
							Verify.expect((open:peek())):toBeNil()
							Verify.expect(world.node:FindFirstChild(edge).Visible):toBe(false)
						end
						Verify.expect(invoked):toBe(0)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"sends ties to the vertical axis, tracks linearly, resists past a tray with no full swipe and commits one at sixty percent",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::sends ties to the vertical axis, tracks linearly, resists past a tray with no full swipe and commits one at sixty percent",
				run = function()
					local policies: { any } = { true, { trailing = false } }
					for _, policy in policies do
						local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
							Compose.cell(nil :: ("leading" | "trailing")?)
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
						local detector =
							world.node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
						local content = world.node:FindFirstChild("Content")
						local tray = world.node:FindFirstChild("trailing")
						local function swipe(from: number, to: number)
							detector.DragStart:Fire(V2(world, from, 20))
							detector.DragContinue:Fire(V2(world, to, 20))
							detector.DragEnd:Fire()
						end
						detector.DragStart:Fire(V2(world, 200, 20))
						detector.DragContinue:Fire(V2(world, 190, 30))
						Verify.expect(content.Position.X.Offset):toBe(0)
						detector.DragContinue:Fire(V2(world, 120, 30))
						Verify.expect(content.Position.X.Offset):toBe(0)
						detector.DragEnd:Fire()
						Verify.expect((open:peek())):toBeNil()
						detector.DragStart:Fire(V2(world, 200, 20))
						for _, distance in { 10, 20, 50, 80, 88 } do
							detector.DragContinue:Fire(V2(world, 200 - distance, 20))
							Verify.expect(content.Position.X.Offset):toBe(-distance)
							Verify.expect(tray.Size.X.Offset):toBe(distance)
							Verify.expect(tray.Visible):toBe(true)
						end
						detector.DragContinue:Fire(V2(world, 200 - 150, 20))
						Verify.expect(content.Position.X.Offset):toBe(if policy == true then -150 else -122)
						Verify.expect(tray.Size.X.Offset):toBe(if policy == true then 150 else 122)
						detector.DragContinue:Fire(V2(world, 200 - 179, 20))
						detector.DragEnd:Fire()
						Verify.expect(invoked.trailing):toBe(0)
						Verify.expect((open:peek())):toBe("trailing")
						open:set(nil)
						swipe(250, 250 - 210)
						Verify.expect(invoked.trailing):toBe(if policy == true then 1 else 0)
						Verify.expect((open:peek())):toBe(if policy == true then nil else "trailing")
						open:set(nil)
						swipe(290, 0)
						Verify.expect(invoked.trailing):toBe(if policy == true then 2 else 0)
						open:set(nil)
						swipe(20, 20 + 179)
						Verify.expect(invoked.leading):toBe(0)
						Verify.expect((open:peek())):toBe("leading")
						open:set(nil)
						swipe(20, 20 + 180)
						Verify.expect(invoked.leading):toBe(1)
						Verify.expect((open:peek())):toBeNil()
						trailingOnly:set(true)
						detector.DragStart:Fire(V2(world, 20, 20))
						detector.DragContinue:Fire(V2(world, 250, 20))
						Verify.expect(content.Position.X.Offset):toBe(0)
						detector.DragEnd:Fire()
						Verify.expect((open:peek())):toBeNil()
						Verify.expect(invoked.leading):toBe(1)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("widens a touch grip and clamps a touch resize to the column minimum and maximum", {
			id = "native_parity_weaker_pointer::pointer, touch and drag strength::widens a touch grip and clamps a touch resize to the column minimum and maximum",
			run = function()
				local widths: any = Compose.cell({})
				local world = setup(function(UI)
					return UI.Table({
						from = { { id = 1, label = "A" } },
						key = function(item: any)
							return item.id
						end,
						widths = widths,
						columns = {
							{ id = "label", label = "Name", width = 100, minWidth = 60, maxWidth = 160 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, { preferredInput = "Touch" })
				local column = world.node:FindFirstChild("Header"):FindFirstChild("label")
				column.AbsoluteSize = V2(world, 100, 44)
				local grip = column:FindFirstChild("Resize")
				Verify.expect(grip.Size.X.Offset):toBe(44)
				Verify.expect(grip.Size.Y.Scale):toBe(1)
				local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V2(world, 100, 10))
				detector.DragContinue:Fire(V2(world, 70, 12))
				Verify.expect(widths:peek().label):toBe(70)
				detector.DragContinue:Fire(V2(world, 20, 12))
				Verify.expect(widths:peek().label):toBe(60)
				detector.DragContinue:Fire(V2(world, -400, 12))
				Verify.expect(widths:peek().label):toBe(60)
				detector.DragEnd:Fire(V2(world, -400, 12))
				column.AbsoluteSize = V2(world, 60, 44)
				detector.DragStart:Fire(V2(world, 60, 10))
				detector.DragContinue:Fire(V2(world, 400, 12))
				Verify.expect(widths:peek().label):toBe(160)
				detector.DragEnd:Fire(V2(world, 400, 12))
				Verify.expect(grip.Size.X.Offset):toBe(44)
				world.stop()
			end,
		})

		verifyHarness:case(
			"cancels a Rating and a LevelPicker scrub back to its value when the player switches to a gamepad",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::cancels a Rating and a LevelPicker scrub back to its value when the player switches to a gamepad",
				run = function()
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
						scrub.DragStart:Fire(V2(world, 95, 20))
						Verify.expect((value:peek())):toBe(case[2])
						scrub.DragContinue:Fire(V2(world, 55, 20))
						Verify.expect((value:peek())):toBe(math.floor(0.55 * case[2]) + 1)
						world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
						Verify.expect((value:peek())):toBe(case[3])
						scrub.DragContinue:Fire(V2(world, 95, 20))
						Verify.expect((value:peek())):toBe(case[3])
						scrub.DragEnd:Fire(V2(world, 95, 20))
						control.Activated:Fire({
							UserInputType = world.engine.types.Enum.UserInputType.Touch,
							Position = world.engine.types.Vector3.new(95, 20, 0),
						})
						Verify.expect((value:peek())):toBe(case[3])
						world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
						scrub.DragStart:Fire(V2(world, 95, 20))
						scrub.DragEnd:Fire(V2(world, 95, 20))
						Verify.expect((value:peek())):toBe(case[2])
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"autoscrolls a reorder only from the edge bands, stops on retraction and release, and clamps both ends",
			{
				id = "native_parity_weaker_pointer::pointer, touch and drag strength::autoscrolls a reorder only from the edge bands, stops on retraction and release, and clamps both ends",
				run = function()
					local requests = {}
					local world = setup(function(UI: FacetControls)
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
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end)
					local engine = world.engine
					local body = world.node:FindFirstChild("Body")
					body.AbsoluteWindowSize = V2(world, 200, 100)
					nativeDrag.measure(body)
					local function frames(count: number)
						for _ = 1, count do
							engine.heartbeat:Fire(1 / 60)
						end
					end
					frames(10)
					Verify.expect(body.CanvasPosition.Y):toBe(0)
					local handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
					local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
					local press = {
						UserInputType = engine.types.Enum.UserInputType.MouseButton1,
						UserInputState = engine.types.Enum.UserInputState.Begin,
						Position = engine.types.Vector3.new(10, 50, 0),
					}
					nativeDrag.press(handle, press)
					detector.DragStart:Fire(V2(world, 10, 50))
					frames(20)
					Verify.expect(body.CanvasPosition.Y):toBe(0)
					detector.DragContinue:Fire(V2(world, 10, 99))
					frames(20)
					local advanced = body.CanvasPosition.Y
					Verify.expect(advanced > 0):toBe(true)
					local function pointerAt(y: number)
						detector.DragContinue:Fire(V2(world, 10, y))
						nativeDrag.move(world.input, {
							UserInputType = engine.types.Enum.UserInputType.MouseMovement,
							UserInputState = engine.types.Enum.UserInputState.Change,
							Position = engine.types.Vector3.new(10, y, 0),
						})
					end
					pointerAt(50)
					frames(20)
					Verify.expect(body.CanvasPosition.Y):toBe(advanced)
					pointerAt(1)
					frames(200)
					Verify.expect(body.CanvasPosition.Y):toBe(0)
					pointerAt(99)
					frames(2000)
					Verify.expect(body.CanvasPosition.Y):toBe(100 * 20 - 100)
					nativeDrag.finish(world.input, press)
					Verify.expect(#requests):toBe(1)
					Verify.expect(requests[1].slot):toBe(99)
					body.CanvasPosition = V2(world, 0, 500)
					frames(60)
					Verify.expect(body.CanvasPosition.Y):toBe(500)
					world.stop()
				end,
			}
		)

		verifyHarness:case("gives a disabled row no drag session and restores the session when it is enabled again", {
			id = "native_parity_weaker_pointer::pointer, touch and drag strength::gives a disabled row no drag session and restores the session when it is enabled again",
			run = function()
				local enabled, open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
					Compose.cell(false), Compose.cell(nil :: ("leading" | "trailing")?)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.RowActions({
						open = open,
						enabled = enabled,
						content = Host.TextLabel({ Text = "Row" }) :: GuiObject,
						trailing = {
							{ id = "Save", label = "Save", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					})
				end, {
					clock = function()
						return 0
					end,
				})
				world.node.AbsoluteSize = V2(world, 300, 44)
				local detector = world.node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				local content = world.node:FindFirstChild("Content")
				Verify.expect(detector.Enabled):toBe(false)
				detector.DragStart:Fire(V2(world, 200, 20))
				detector.DragContinue:Fire(V2(world, 100, 20))
				Verify.expect(content.Position.X.Offset):toBe(0)
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBeNil()
				enabled:set(true)
				Verify.expect(detector.Enabled):toBe(true)
				detector.DragStart:Fire(V2(world, 200, 20))
				detector.DragContinue:Fire(V2(world, 100, 20))
				Verify.expect(content.Position.X.Offset):toBe(-100)
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBe("trailing")
				world.stop()
				local value = Compose.cell(2)
				local levelEnabled = Compose.cell(false)
				local level = setup(function(UI: FacetControls)
					return UI.LevelPicker({ value = value, count = 10, enabled = levelEnabled })
				end)
				level.node.AbsoluteSize = V2(level, 100, 44)
				local scrub = level.node:FindFirstChild("Scrub")
				Verify.expect(scrub.Enabled):toBe(false)
				scrub.DragStart:Fire(V2(level, 95, 20))
				Verify.expect((value:peek())):toBe(2)
				levelEnabled:set(true)
				Verify.expect(scrub.Enabled):toBe(true)
				scrub.DragStart:Fire(V2(level, 95, 20))
				scrub.DragEnd:Fire(V2(level, 95, 20))
				Verify.expect((value:peek())):toBe(10)
				level.stop()
			end,
		})

		verifyHarness:case("opens a plain menu when a touch long press begins and only then", {
			id = "native_parity_weaker_pointer::pointer, touch and drag strength::opens a plain menu when a touch long press begins and only then",
			run = function()
				for _, triggers in { false, true } do
					local opened = Compose.cell(false)
					local world = setup(function(UI: FacetControls)
						return UI.Menu({
							label = "Options",
							isPresented = opened,
							triggers = if triggers
								then {
									"activate",
									"secondary",
									"keyboard",
									"gamepad",
								} :: { "activate" | "secondary" | "keyboard" | "gamepad" }
								else nil,
							items = {
								{ id = "Rename", label = "Rename", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							},
						})
					end, { preferredInput = "Touch" })
					local trigger = find(world.node, "Trigger")
					local states = world.engine.types.Enum.UserInputState
					trigger.TouchLongPress:Fire({}, states.Change)
					trigger.TouchLongPress:Fire({}, states.End)
					Verify.expect((opened:peek())):toBe(false)
					trigger.TouchLongPress:Fire({}, states.Begin)
					Verify.expect((opened:peek())):toBe(not triggers)
					if not triggers then
						Verify.expect(find(world.root, "MenuPanel") ~= nil):toBe(true)
						trigger.TouchLongPress:Fire({}, states.End)
						Verify.expect((opened:peek())):toBe(true)
					end
					world.stop()
				end
			end,
		})

		verifyHarness:case("resizes a sheet live while its handle is dragged up and snaps to the nearest detent", {
			id = "native_parity_weaker_pointer::pointer, touch and drag strength::resizes a sheet live while its handle is dragged up and snaps to the nearest detent",
			run = function()
				local detent = Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = detent,
						title = "Sheet",
						content = function(): Instance
							return Host.Frame("Body")({})
						end,
					})
				end)
				local panel = find(world.root, "SheetPanel")
				local drag = find(find(world.root, "DragHandle"), "UIDragDetector")
				Verify.expect(panel.Size.Y.Offset):toBe(360)
				drag.DragStart:Fire(V2(world, 0, 400))
				drag.DragContinue:Fire(V2(world, 0, 200))
				Verify.expect(panel.Size.Y.Offset):toBe(560)
				Verify.expect((detent:peek())):toBe("medium")
				drag.DragContinue:Fire(V2(world, 0, 100))
				Verify.expect(panel.Size.Y.Offset):toBe(660)
				drag.DragEnd:Fire()
				Verify.expect((detent:peek())):toBe("large")
				Verify.expect(panel.Size.Y.Offset):toBe(684)
				drag.DragStart:Fire(V2(world, 0, 100))
				drag.DragContinue:Fire(V2(world, 0, 250))
				drag.DragEnd:Fire()
				Verify.expect((detent:peek())):toBe("large")
				drag.DragStart:Fire(V2(world, 0, 100))
				drag.DragContinue:Fire(V2(world, 0, 300))
				drag.DragEnd:Fire()
				Verify.expect((detent:peek())):toBe("medium")
				drag.DragStart:Fire(V2(world, 0, 400))
				drag.DragContinue:Fire(V2(world, 0, 230))
				drag.DragEnd:Fire()
				Verify.expect((detent:peek())):toBe("large")
				drag.DragStart:Fire(V2(world, 0, 400))
				drag.DragContinue:Fire(V2(world, 0, 600))
				drag.DragEnd:Fire()
				Verify.expect((detent:peek())):toBe("medium")
				Verify.expect(panel.Size.Y.Offset):toBe(360)
				world.stop()
			end,
		})
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

	verifyHarness:suite("adaptive environment strength", function()
		verifyHarness:case(
			"applies the ten-foot console profile facts to native input and engages the gamepad policies",
			{
				id = "native_parity_weaker_pointer::adaptive environment strength::applies the ten-foot console profile facts to native input and engages the gamepad policies",
				run = function()
					local perfProfiles = require("../bench/perf_profiles")
					for _, name in { "consoleTenFoot", "desktop" } do
						local profile = perfProfiles.get(name)
						local tenFoot = name == "consoleTenFoot"
						Verify.expect(profile.displaySize):toBe(if tenFoot then "Large" else profile.displaySize)
						Verify.expect(profile.overscanInsets.left > 0):toBe(tenFoot)
						local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.Table({
									from = { { id = 1, label = "A" }, { id = 2, label = "B" } },
									key = function(item: any)
										return item.id
									end,
									controls = controls,
									columns = {
										{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
									},
								}) :: unknown,
								UI.Picker("Choice")({
									selected = Compose.cell("1"),
									options = {
										{ value = "1", label = "One" } :: FixtureNavigationTypes.PickerOption<any>,
										{ value = "2", label = "Two" } :: FixtureNavigationTypes.PickerOption<any>,
										{ value = "3", label = "Three" } :: FixtureNavigationTypes.PickerOption<any>,
										{ value = "4", label = "Four" } :: FixtureNavigationTypes.PickerOption<any>,
										{ value = "5", label = "Five" } :: FixtureNavigationTypes.PickerOption<any>,
									},
								}),
							})
						end, {
							preferredInput = profile.preferredInput,
							config = { theme = compactTheme() },
						})
						Verify.expect(world.input.PreferredInput):toBe(
							if tenFoot
								then world.engine.types.Enum.PreferredInput.Gamepad
								else world.engine.types.Enum.PreferredInput.KeyboardAndMouse
						)
						find(world.node, "Body").AbsoluteWindowSize = V2(world, 200, 100)
						Verify.expect(assert(controls.placementOf)(2).offset):toBe(if tenFoot then 44 else 40)
						local picker = find(world.node, "Choice")
						picker.AbsoluteSize = V2(world, profile.viewport.w / 2, 44)
						Verify.expect(find(picker, "Trigger") == nil):toBe(tenFoot)
						Verify.expect(find(picker, "5") ~= nil):toBe(tenFoot)
						world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
						Verify.expect(assert(controls.placementOf)(2).offset):toBe(40)
						Verify.expect(find(picker, "Trigger") ~= nil):toBe(true)
						world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
						Verify.expect(assert(controls.placementOf)(2).offset):toBe(44)
						Verify.expect((find(picker, "Trigger"))):toBeNil()
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"falls back to a spaced touch list in small space, keeps activation and returns to a ring with its clearance",
			{
				id = "native_parity_weaker_pointer::adaptive environment strength::falls back to a spaced touch list in small space, keeps activation and returns to a ring with its clearance",
				run = function()
					local picked = {}
					local items = {}
					for _, id in { "a", "b", "c" } do
						table.insert(items, {
							id = id,
							label = "Item " .. id,
							completion = "stay" :: "stay",
							onSelect = function()
								table.insert(picked, id)
							end,
						})
					end
					local world = radial({ clearance = 100, items = items })
					local modal = find(world.root, "Modal")
					modal.AbsoluteSize = V2(world, 320, 300)
					Verify.expect((presentation(world))):toBe("list")
					local panel = find(world.root, "RadialPanel")
					Verify.expect(panel.ScrollingEnabled):toBe(true)
					Verify.expect(panel:FindFirstChildWhichIsA("UIListLayout").Padding.Offset):toBe(4)
					for _, id in { "a", "b", "c" } do
						local row = find(world.root, id)
						Verify.expect(row.Size.Y.Offset):toBe(44)
						Verify.expect(row.Size.X.Scale):toBe(1)
						Verify.expect(row.Size.X.Offset):toBe(-8)
						Verify.expect(row.Parent.Size.Y.Offset):toBe(44)
					end
					find(world.root, "b").Activated:Fire(touch(world, 40, 100))
					Verify.expect((table.concat(picked, ","))):toBe("b")
					world.gui.SelectedObject = find(world.root, "a")
					find(world.root, "a").SelectionGained:Fire()
					action(world.root, "Radial-down").Pressed:Fire()
					Verify.expect(world.gui.SelectedObject):toBe(find(world.root, "b"))
					action(world.root, "Radial-down").Pressed:Fire()
					Verify.expect(world.gui.SelectedObject):toBe(find(world.root, "c"))
					modal.AbsoluteSize = V2(world, 920, 640)
					Verify.expect((presentation(world))):toBe("radial")
					for _, id in { "a", "b", "c" } do
						local x, y = positionOf(find(world.root, id))
						local distance = math.sqrt((x - 460) ^ 2 + (y - 320) ^ 2)
						Verify.expect(distance >= 100):toBe(true)
					end
					find(world.root, "c").Activated:Fire(touch(world, 460, 100))
					Verify.expect((table.concat(picked, ","))):toBe("b,c")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"shows the monitor header actions when they fit and runs them from the menu when they do not",
			{
				id = "native_parity_weaker_pointer::adaptive environment strength::shows the monitor header actions when they fit and runs them from the menu when they do not",
				run = function()
					local Roblox = require("../src/vendor/compose/roblox")
					local modelModule = require("../examples/virtual_monitors/model")
					local screens = require("../examples/virtual_monitors/screens")
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Roblox.createRuntime(engine)
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
							motionLevel = "none",
						})
						local stop, discover: any = runtime.mount(views.Discover, target)
						discover.AbsoluteSize = engine.types.Vector2.new(920, 690)
						local chrome, menu = find(discover, "Chrome"), find(discover, "ActionsMenu")
						Verify.expect(chrome.Visible):toBe(true)
						Verify.expect(menu.Visible):toBe(false)
						local mode = model.mode:peek()
						find(chrome, "Presentation").Activated:Fire()
						Verify.expect(model.mode:peek() ~= mode):toBe(true)
						find(chrome, "About").Activated:Fire()
						Verify.expect(find(target, "DialogModal") ~= nil):toBe(true)
						find(target, "done").Activated:Fire()
						Verify.expect((find(target, "DialogModal"))):toBeNil()
						discover.AbsoluteSize = engine.types.Vector2.new(393, 690)
						Verify.expect(chrome.Visible):toBe(false)
						Verify.expect(menu.Visible):toBe(true)
						local function choose(id: string)
							menu.Activated:Fire()
							local panel = find(target, "MenuPanel")
							local labels = {}
							for _, node in panel:GetDescendants() do
								if node:IsA("GuiButton") and node.Visible then
									labels[node.Name] = true
								end
							end
							for _, name in { "Presentation", "Appearance", "About" } do
								Verify.expect(labels[name]):toBe(true)
							end
							find(panel, id).Activated:Fire()
						end
						choose("Presentation")
						Verify.expect((model.mode:peek())):toBe(mode)
						local dark = model.dark:peek()
						choose("Appearance")
						Verify.expect((model.dark:peek())):toBe(not dark)
						choose("About")
						Verify.expect(find(target, "DialogModal") ~= nil):toBe(true)
						find(target, "done").Activated:Fire()
						discover.AbsoluteSize = engine.types.Vector2.new(920, 690)
						Verify.expect(chrome.Visible):toBe(true)
						Verify.expect(menu.Visible):toBe(false)
						stop()
					end, runtime.reactor)
					lifetime.dispose()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"keeps every interactive control target at 44 pixels under touch and gamepad at every text size",
			{
				id = "native_parity_weaker_pointer::adaptive environment strength::keeps every interactive control target at 44 pixels under touch and gamepad at every text size",
				run = function()
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
							return {
								value = Compose.cell("Query"),
								presentation = "search" :: "search",
								clearButtonMode = "always",
							}
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
							return {
								label = "Options",
								isPresented = Compose.cell(true),
								items = { item("Alpha"), item("Beta") },
							}
						end,
						Picker = function()
							return {
								selected = Compose.cell("a"),
								style = "segmented" :: "segmented",
								options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
							}
						end,
						SplitButton = function()
							return { label = "Action", onActivate = function() end, items = { item("Alpha") } }
						end,
						DisclosureGroup = function(Host: RobloxHost)
							return {
								label = "Details",
								expanded = Compose.cell(true),
								content = function(): Instance
									return Host.TextLabel({ Text = "Body" })
								end,
							}
						end,
						TabView = function(Host: RobloxHost)
							local function tab(id: string): any
								return {
									id = id,
									label = id,
									content = function(): Instance
										return Host.TextLabel({ Text = id })
									end,
								}
							end
							return { selection = Compose.cell("a"), tabs = { tab("a"), tab("b") } }
						end,
						PageView = function(Host: RobloxHost)
							local function page(id: string): any
								return {
									id = id,
									title = id,
									content = function(): Instance
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
								actions = {
									{ id = "ok", label = "OK" },
									{ id = "cancel", label = "Cancel", role = "cancel" :: "cancel" },
								},
							}
						end,
						Sheet = function(Host: RobloxHost)
							return {
								title = "Sheet",
								detent = Compose.cell("medium"),
								isPresented = Compose.cell(true),
								content = function(): Instance
									return Host.TextLabel({ Text = "Body" })
								end,
							}
						end,
						RowActions = function(Host: RobloxHost)
							return {
								content = function(): Instance
									return Host.TextLabel({ Text = "Row" })
								end,
								trailing = {
									{
										id = "delete",
										label = "Delete",
										role = "destructive" :: "destructive",
										onActivate = function() end,
									} :: FixtureCollectionTypes.RowAction,
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
						for _, kind in { "Touch", "Gamepad" } :: { "Gamepad" | "Touch" } do
							local world = setup(function(UI: FacetControls, Host: RobloxHost)
								return Host.Frame({ UI[name](fixtures[name](Host)) })
							end, { preferredInput = kind :: "Gamepad" | "Touch" })
							for _, child in world.node:GetChildren() do
								if child:IsA("GuiObject") then
									child.AbsoluteSize = V2(world, 300, 44)
								end
							end
							local found = targets(world.root)
							Verify.expect(`{name}:{#found > 0}`):toBe(`{name}:true`)
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
					Verify.expect((table.concat(failures, "; "))):toBe("")
				end,
			}
		)

		verifyHarness:case(
			"keeps controls legal and mounted through seeded preferred-input, transparency, motion and garbage bound storms",
			{
				id = "native_parity_weaker_pointer::adaptive environment strength::keeps controls legal and mounted through seeded preferred-input, transparency, motion and garbage bound storms",
				run = function()
					local inputs = engineLib.new().types.Enum.PreferredInput:GetEnumItems()
					for seed = 1, 20 do
						local state = 917359 + seed
						local function nextInteger(low: number, high: number): number
							state = (state * 16807) % 2147483647
							return low + state % (high - low + 1)
						end
						local value = Compose.cell(0.5)
						local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
						local sheet: any
						local current: any
						local services = {
							GetService = function(_: any, name: string)
								return if name == "GuiService" then current else nil
							end,
						}
						local world: World
						withGame(services, function()
							world = setup(function(UI: FacetControls, Host: RobloxHost, engine, gui, runtime)
								current = gui
								sheet = Facet.themes.createStyleSheet(
									runtime,
									Facet.themes.neutralPackage(),
									{ types = engine.types }
								)
								return Host.Frame({
									sheet :: unknown,
									UI.Table({
										from = {
											{ id = 1, label = "A" },
											{ id = 2, label = "B" },
											{ id = 3, label = "C" },
										},
										key = function(item: any)
											return item.id
										end,
										controls = controls,
										columns = {
											{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
										},
									}),
									UI.Slider("Volume")({ value = value }),
									UI.Alert({
										title = "Confirm",
										message = "Continue?",
										isPresented = Compose.cell(true),
										actions = {
											{ id = "ok", label = "OK" } :: FixtureNavigationTypes.AlertAction<any>,
										},
									}),
								})
							end, { config = { theme = compactTheme() } })
						end)
						local scrim = scrimOf(sheet)
						local body = find(world.node, "Body")
						body.AbsoluteWindowSize = V2(world, 200, 200)
						nativeDrag.measure(body)
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
								drag.DragStart:Fire(V2(world, nextInteger(0, 200), 20))
							end
							world.input.PreferredInput = kind
							world.gui.PreferredTransparency = garbage[nextInteger(1, #garbage)]
							world.gui.ReducedMotionEnabled = nextInteger(0, 1) == 1
							body.AbsoluteWindowSize = V2(world, extents[nextInteger(1, #extents)], 200)
							nativeDrag.measure(body)
							if drag then
								drag.DragEnd:Fire(V2(world, 100, 20))
							end
							local expected = if kind == world.engine.types.Enum.PreferredInput.Touch
								then 56
								elseif kind == world.engine.types.Enum.PreferredInput.Gamepad then 44
								else 40
							Verify.expect(assert(controls.placementOf)(2).offset):toBe(expected)
							for index = 1, 3 do
								Verify.expect((body:FindFirstChild(tostring(index), true))):toBe(rows[index])
							end
							Verify.expect((find(world.node, "Volume"))):toBe(slider)
							local current = value:peek()
							Verify.expect(current == current and current >= 0 and current <= 1):toBe(true)
							local transparency = scrim:GetProperties().BackgroundTransparency
							Verify.expect(transparency == transparency and transparency >= 0 and transparency <= 1)
								:toBe(true)
							Verify.expect((find(world.root, "DismissOutside"))):toBe(catcher)
							Verify.expect((catcher:HasTag("facet-scrim"))):toBe(true)
						end
						world.stop()
						local picked = {}
						local ring = radial({ distribution = "compass" :: "compass", items = compass(picked) })
						local modal = find(ring.root, "Modal")
						local north = find(ring.root, "N")
						for _ = 1, 10 do
							modal.AbsoluteSize = V2(
								ring,
								extents[nextInteger(1, #extents)] * 100,
								extents[nextInteger(1, #extents)] * 100
							)
							local shown = presentation(ring)
							Verify.expect(shown == "radial" or shown == "list"):toBe(true)
							Verify.expect((find(ring.root, "N"))):toBe(north)
						end
						north.Activated:Fire()
						Verify.expect((table.concat(picked, ","))):toBe("N")
						ring.stop()
					end
				end,
			}
		)

		verifyHarness:case("keeps device names and platform branches out of the framework and example sources", {
			id = "native_parity_weaker_pointer::adaptive environment strength::keeps device names and platform branches out of the framework and example sources",
			run = function()
				local files = {}
				sourceFiles("src", files)
				sourceFiles("examples", files)
				Verify.expect(#files > 50):toBe(true)
				local found = {}
				for _, file in files do
					local source = string.lower(fs.readFile(file))
					for _, device in
						{
							"iphone",
							"ipad",
							"android",
							"xbox",
							"playstation",
							"nintendo",
							"macos",
							"windows",
							"ios",
							"tvos",
						}
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
				Verify.expect((table.concat(found, ", "))):toBe("")
			end,
		})

		verifyHarness:case("resolves an automatic picker from width, option shape and every preferred input", {
			id = "native_parity_weaker_pointer::adaptive environment strength::resolves an automatic picker from width, option shape and every preferred input",
			run = function()
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
					{ 2, false, 240, "KeyboardAndMouse", "segmented" },
					{ 2, false, 240, "Touch", "segmented" },
					{ 2, false, 240, "Gamepad", "segmented" },
					{ 2, false, 80, "KeyboardAndMouse", "menu" },
					{ 2, false, 80, "Touch", "menu" },
					{ 2, false, 80, "Gamepad", "inline" },
					{ 5, false, 400, "KeyboardAndMouse", "menu" },
					{ 5, false, 400, "Touch", "menu" },
					{ 5, false, 400, "Gamepad", "inline" },
					{ 7, false, 400, "Gamepad", "menu" },
					{ 3, true, 400, "KeyboardAndMouse", "menu" },
					{ 3, true, 400, "Gamepad", "inline" },
				}
				for _, case in cases do
					local selected = Compose.cell("1")
					local world = setup(function(UI: FacetControls)
						return UI.Picker({ selected = selected, options = options(case[1], case[2]) })
					end, { preferredInput = case[4] })
					find(world.node, "LabelMeasure").TextBounds = V2(world, case[1] * 60, 18)
					world.node.AbsoluteSize = V2(world, case[3], 44)
					local presented = find(world.node, "Presentation")
					local trigger = find(world.node, "Trigger")
					local style = if trigger
						then "menu"
						elseif presented and presented:HasTag("facet-segmented") then "segmented"
						else "inline"
					Verify.expect(`{case[1]}/{case[3]}/{case[4]}={style}`)
						:toBe(`{case[1]}/{case[3]}/{case[4]}={case[5]}`)
					if style ~= "menu" then
						find(world.node, "2").Activated:Fire()
						Verify.expect((selected:peek())):toBe("2")
					end
					world.stop()
				end
				local query = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = Compose.cell("1"),
						query = Compose.cell(""),
						options = options(2, false),
					})
				end, { preferredInput = "Gamepad" })
				query.node.AbsoluteSize = V2(query, 400, 44)
				Verify.expect((find(query.node, "5"))):toBeNil()
				Verify.expect((find(query.node, "Presentation"):HasTag("facet-segmented"))):toBe(false)
				query.stop()
			end,
		})

		verifyHarness:case(
			"follows GuiService transparency from attach and live without wiring, and keeps paint fades under Reduce Motion",
			{
				id = "native_parity_weaker_pointer::adaptive environment strength::follows GuiService transparency from attach and live without wiring, and keeps paint fades under Reduce Motion",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
							sheet = Facet.themes.createStyleSheet(
								runtime,
								Facet.themes.neutralPackage(),
								{ types = engine.types }
							)
							return ((runtime.constructors.Folder :: unknown) :: FolderConstructor)({ sheet :: unknown })
						end, engine.new("Folder"))
					end)
					local scrim = scrimOf(sheet)
					local authored = 0.55
					Verify.expect(math.abs(scrim:GetProperties().BackgroundTransparency - authored * 0.5) < 1e-6)
						:toBe(true)
					Verify.expect(transitionOf(scrim, "BackgroundTransparency").Time > 0):toBe(true)
					gui.PreferredTransparency = 0
					Verify.expect(scrim:GetProperties().BackgroundTransparency):toBe(0)
					gui.PreferredTransparency = 1
					Verify.expect(math.abs(scrim:GetProperties().BackgroundTransparency - authored) < 1e-6):toBe(true)
					gui.ReducedMotionEnabled = false
					Verify.expect(transitionOf(scrim, "BackgroundTransparency").Time > 0):toBe(true)
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("PreferredTransparency"))))
						:toBe(1)
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("ReducedMotionEnabled")))):toBe(0)
					stop()
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("PreferredTransparency"))))
						:toBe(0)
					Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("ReducedMotionEnabled")))):toBe(0)
					local explicit: any
					withGame(services, function()
						local stopExplicit = runtime.mount(function()
							explicit = Facet.themes.createStyleSheet(
								runtime,
								Facet.themes.neutralPackage(),
								{ types = engine.types, preferredTransparency = 1, motionLevel = "normal" }
							)
							return ((runtime.constructors.Folder :: unknown) :: FolderConstructor)({
								explicit :: unknown,
							})
						end, engine.new("Folder"))
						Verify.expect((engineLib.connections(gui:GetPropertyChangedSignal("PreferredTransparency"))))
							:toBe(0)
						gui.PreferredTransparency = 0
						Verify.expect(
							math.abs(scrimOf(explicit):GetProperties().BackgroundTransparency - authored) < 1e-6
						)
							:toBe(true)
						stopExplicit()
					end)
					runtime:dispose()
				end,
			}
		)
	end)

	return nil
end
