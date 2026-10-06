--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local nativeDrag = require("./lib/native_drag")

	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type TextBoxConstructor = typeof(require("@repo/tools/typecheck/aliases").TextBoxConstructor)
	type UIScaleConstructor = typeof(require("@repo/tools/typecheck/aliases").UIScaleConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureEnvironmentTypes = require("../src/ui/environment_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T
	local SharedTypes = require("../src/ui/control_types")

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local registerInputs = require("../src/ui/inputs")
	local registerCollections = require("../src/ui/collections")
	local registerRowActions = require("../src/ui/collection_row_actions")
	local registerTable = require("../src/ui/collection_table")
	local engineLib = require("./lib/native_engine")

	local function setup(options: { [string]: any }?)
		local engine = engineLib.new(options and options.engine)
		if options and options.clock then
			engine.clock = options.clock
		end
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui },
			inputParent = root,
			motionLevel = "none",
		}
		for field, value in (options or {}) :: { [string]: any } do
			if field ~= "engine" then
				config[field] = value
			end
		end
		if config.userInputService and config.userInputService.GetPropertyChangedSignal == nil then
			local service: any = engine.new("UserInputService")
			service.IsKeyDown = function()
				return false
			end
			service.GetFocusedTextBox = function()
				return nil
			end
			for key, value in config.userInputService do
				service[key] = value
			end
			config.userInputService = service
			config.services.UserInputService = service
		end
		local ctx = context(Compose, runtime, config :: SharedTypes.Config)
		local UI = ({} :: unknown) :: SharedTypes.Controls
		registerInputs(ctx, UI)
		local surfaces = require("../src/ui/nav_modal")(ctx)
		require("../src/ui/nav_menu")(ctx, UI, surfaces)
		require("../src/ui/nav_surfaces")(ctx, UI, surfaces)
		require("../src/ui/nav_popover")(ctx, UI, surfaces)
		require("../src/ui/nav_pages")(ctx, UI, surfaces)
		require("../src/ui/nav_radial")(ctx, UI, surfaces)
		local buildList = registerCollections(ctx, UI)
		registerRowActions(ctx, UI)
		registerTable(ctx, UI, buildList)
		return engine, runtime, UI, root, gui, ctx
	end

	local function records(count)
		local values = {}
		for index = 1, count do
			values[index] = { id = index, label = tostring(index) }
		end
		return values
	end

	type KeyedRecord =
		{ id: number, label: string }
		| { id: number, name: string }
		| { id: number, name: string, artist: string, rating: number }
		| { id: number, first: string, second: string, third: string }
	local function key(item: KeyedRecord): number
		return item.id
	end

	local function button(UI: SharedTypes.Controls, current: Compose.Readable<{ id: number, label: string }>): GuiObject
		return UI.Button "Action" {
			label = function(use: Use)
				return use(current).label
			end,
		}
	end

	verifyHarness:suite("Compose native collections", function()
		verifyHarness:case("paints list and grid selection on the cell owner and clears recycled state", {
			id = "native_collections::Compose native collections::paints list and grid selection on the cell owner and clears recycled state",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid" } do
					local engine, runtime, UI, target = setup()
					local selected = Compose.cell({})
					local stop, node: any = runtime.mount(function()
						return UI[kind]({
							from = Compose.cell(records(20)),
							key = key,
							selection = selected,
							selectionMode = "multiple" :: "multiple",
							itemSize = 40,
							overscan = 0,
							render = function(): GuiObject
								return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({
									BackgroundTransparency = 1,
								})
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 80)
					local hit = node:FindFirstChild("1", true):FindFirstChild("RowHit", true)
					local painted = hit.Parent
					Verify.expect((painted:HasTag("facet-tablerow"))):toBe(true)
					Verify.expect(painted.BackgroundTransparency):toBe(0)
					Verify.expect(hit.BackgroundTransparency):toBe(1)
					hit.Activated:Fire()
					Verify.expect((painted:HasTag("facet-selected"))):toBe(true)
					selected:set({ [2] = true })
					Verify.expect((painted:HasTag("facet-selected"))):toBe(false)
					Verify.expect(
						(node:FindFirstChild("2", true):FindFirstChild("RowHit", true).Parent:HasTag("facet-selected"))
					)
						:toBe(true)
					node.CanvasPosition = engine.types.Vector2.new(0, 400)
					for _, child in node:GetDescendants() do
						Verify.expect((child:HasTag("facet-selected"))):toBe(false)
					end
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("selects on click zero and activates on click one for lists and grids", {
			id = "native_collections::Compose native collections::selects on click zero and activates on click one for lists and grids",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid" } :: { "VirtualGrid" | "VirtualList" } do
					local engine, runtime, UI, target = setup()
					local selected = Compose.cell({})
					local activated = 0
					local stop, list: any = runtime.mount(function()
						return UI[kind] {
							from = records(2),
							key = key,
							mode = "all" :: "all",
							selection = selected,
							onActivate = function()
								activated += 1
							end,
							render = function(): GuiObject
								return (
									(
										((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown
									) :: FrameConstructor
								) {
									Size = engine.types.UDim2.fromScale(1, 1),
								}
							end,
						}
					end, target)
					local hit = list:FindFirstChild("1", true):FindFirstChild("RowHit", true)
					local mouse = { UserInputType = engine.types.Enum.UserInputType.MouseButton1 }
					hit.Activated:Fire(mouse, 0)
					Verify.expect(selected:peek()[1]):toBe(true)
					Verify.expect(activated):toBe(0)
					hit.Activated:Fire(mouse, 1)
					Verify.expect(activated):toBe(1)
					stop()
				end
			end,
		})

		verifyHarness:case("uses native whole-row dragging in plugin windows without global mouse events", {
			id = "native_collections::Compose native collections::uses native whole-row dragging in plugin windows without global mouse events",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2 = engine.types.Enum, engine.types.Vector2
				assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.KeyboardAndMouse
				local widget = engine.new("DockWidgetPluginGui")
				ctx.config.inputParent = widget
				local reorders = {}
				local stop, list: any = runtime.mount(function()
					return UI.VirtualList {
						from = records(3),
						key = key,
						mode = "all" :: "all",
						itemSize = 40,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(reorders, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
				end, target)
				list.AbsoluteWindowSize = V2.new(200, 120)
				local row = list:FindFirstChild("1", true):FindFirstChild("Action", true)
				local V3 = engine.types.Vector3
				local press = {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.End,
					Position = V3.new(35, 0, 0),
				}
				row.MouseButton1Down:Fire(97, 20)
				row.InputBegan:Fire(press)
				press.Position = V3.new(35, 2, 0)
				row.InputEnded:Fire(press)
				Verify.expect(#reorders):toBe(0)
				press.Position = V3.new(35, 0, 0)
				row.MouseButton1Down:Fire(97, 20)
				row.InputBegan:Fire(press)
				press.Position = V3.new(35, 90, 0)
				row.InputEnded:Fire(press)
				Verify.expect(reorders):toEqual({ { keys = { 1 }, slot = 2 } })
				press.Position = V3.new(35, 0, 0)
				press.UserInputState = E.UserInputState.Begin
				row.MouseButton1Down:Fire(97, 20)
				row.InputBegan:Fire(press)
				list.MouseMoved:Fire(97, 110)
				widget.WindowFocusReleased:Fire()
				press.UserInputState = E.UserInputState.End
				row.InputEnded:Fire(press)
				Verify.expect(#reorders):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("reuses row containers, replaces reactive items and anchors native scrolling", {
			id = "native_collections::Compose native collections::reuses row containers, replaces reactive items and anchors native scrolling",
			run = function()
				local engine, runtime, UI, target = setup()
				local rows = records(100)
				local source, status =
					Compose.cell(rows), Compose.cell({
						mode = "windowed" :: "windowed",
						direction = "vertical" :: "vertical",
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
				local rendered, disposed = 0, 0
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						status = status,
						render = function(current): GuiObject
							rendered += 1
							Compose.cleanup(function()
								disposed += 1
							end)
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				Verify.expect(status:peek().retained):toBe(5)
				local initialContainers = {}
				for _, row in node:FindFirstChild("Items"):GetChildren() do
					initialContainers[row] = true
				end
				local original = node:FindFirstChild("1", true):FindFirstChild("Action", true)
				local changed = table.clone(rows)
				changed[1] = { id = 1, label = "Updated" }
				source:set(changed)
				Verify.expect((node:FindFirstChild("1", true):FindFirstChild("Action", true))):toBe(original)
				Verify.expect(original.Text):toBe("Updated")
				node.CanvasPosition = engine.types.Vector2.new(0, 400)
				Verify.expect(status:peek().first):toBe(21)
				local before = node:FindFirstChild("21", true)
				local nextRows = table.clone(changed)
				table.remove(nextRows, 1)
				source:set(nextRows)
				Verify.expect(node.CanvasPosition.Y):toBe(380)
				Verify.expect(status:peek().first):toBe(20)
				Verify.expect((node:FindFirstChild("21", true))):toBe(before)
				node.CanvasPosition = engine.types.Vector2.new(0, 800)
				local reused = false
				for _, row in node:FindFirstChild("Items"):GetChildren() do
					reused = reused or initialContainers[row] == true
				end
				Verify.expect(reused):toBe(true)
				for index = 1, 10 do
					node.CanvasPosition = engine.types.Vector2.new(0, index * 100)
				end
				stop()
				Verify.expect(disposed):toBe(rendered)
				for _, made in engine.made do
					if made.Name == "Content" or made.Name == "Action" then
						Verify.expect((made:isDestroyed())):toBe(true)
					end
				end
				runtime:dispose()
			end,
		})

		verifyHarness:case("accepts a field name as the collection key", {
			id = "native_collections::Compose native collections::accepts a field name as the collection key",
			run = function()
				local engine, runtime, UI, target = setup()
				local source = Compose.cell({ { id = 7, label = "Seven" }, { id = 9, label = "Nine" } })
				local keys = {}
				local stopList, list: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = "id",
						itemSize = 20,
						render = function(current, _placement, rowKey): GuiObject
							table.insert(keys, rowKey)
							return button(UI, current)
						end,
					})
				end, target)
				list.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				Verify.expect(list:FindFirstChild("7", true) ~= nil):toBe(true)
				Verify.expect(keys[1]):toBe("7")
				stopList()
				local stopTable, tableNode: any = runtime.mount(function()
					return UI.Table({
						from = source,
						key = "id",
						columns = {
							{
								id = "label",
								label = "Name",
								render = function(current): GuiObject
									return button(UI, current)
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				tableNode:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				Verify.expect(tableNode:FindFirstChild("Body"):FindFirstChild("9", true) ~= nil):toBe(true)
				stopTable()
				local ok, message = pcall(function()
					local stopBad = runtime.mount(function()
						return UI.VirtualList({
							from = source,
							key = 3,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						} :: any)
					end, target)
					stopBad()
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(message), "key must be a function or a field name", 1, true) ~= nil)
					:toBe(true)
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"defers initial offscreen focus until native geometry and suppresses navigation while editing",
			{
				id = "native_collections::Compose native collections::defers initial offscreen focus until native geometry and suppresses navigation while editing",
				run = function()
					local engine, runtime, UI, target, gui = setup()
					local focus: FixtureCollectionTypes.FocusControls<any> = {}
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(100),
							key = key,
							itemSize = 20,
							overscan = 0,
							focus = focus,
							initialFocus = 50,
							disabled = function(item)
								return item.id == 51
							end,
							render = function(current): GuiObject
								return ((runtime.constructors.TextBox :: unknown) :: TextBoxConstructor) "Editor" {
									Text = function(use: Use)
										return use(current).label
									end,
									Selectable = true,
								}
							end,
						})
					end, target)
					Verify.expect(gui.SelectedObject):toBeNil()
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
					Verify.expect(gui.SelectedObject.Text):toBe("50")
					local down = target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown")
					gui.SelectedObject:CaptureFocus()
					down.Pressed:Fire()
					Verify.expect((assert(focus.current):peek())):toBe(50)
					gui.SelectedObject:ReleaseFocus()
					down.Pressed:Fire()
					Verify.expect((assert(focus.current):peek())):toBe(52)
					Verify.expect(gui.SelectedObject.Text):toBe("52")
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("wraps arrow and D-pad focus at both ends when wrapFocus is set", {
			id = "native_collections::Compose native collections::wraps arrow and D-pad focus at both ends when wrapFocus is set",
			run = function()
				for _, wrap in { true, false } do
					local engine, runtime, UI, target, gui = setup()
					local focus: FixtureCollectionTypes.FocusControls<any> = {}
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(5),
							key = key,
							itemSize = 20,
							focus = focus,
							wrapFocus = wrap,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
					assert(focus.focus)(5)
					Verify.expect(gui.SelectedObject.Text):toBe("5")
					target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed:Fire()
					Verify.expect((assert(focus.current):peek())):toBe(if wrap then 1 else 5)
					assert(focus.focus)(1)
					target:FindFirstChild("FacetCollectionUp"):FindFirstChild("CollectionUp").Pressed:Fire()
					Verify.expect((assert(focus.current):peek())):toBe(if wrap then 5 else 1)
					target:FindFirstChild("FacetCollectionRight"):FindFirstChild("CollectionRight").Pressed:Fire()
					Verify.expect((assert(focus.current):peek())):toBe(if wrap then 5 else 1)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("uses measured extents and column placements for both scroll directions", {
			id = "native_collections::Compose native collections::uses measured extents and column placements for both scroll directions",
			run = function()
				for _, direction in { "vertical", "horizontal" } :: { "horizontal" | "vertical" } do
					local engine, runtime, UI, target = setup()
					local measured, columns, gap = Compose.cell({ [1] = 60 }), Compose.cell(2), Compose.cell(5)
					local controls: FixtureComposeTypes.OrderedCollectionControls<any>, status =
						{}, Compose.cell({
							mode = "windowed" :: "windowed",
							direction = "vertical" :: "vertical",
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
					local stop, node: any = runtime.mount(function()
						return UI.VirtualGrid({
							from = records(10),
							key = key,
							columns = columns,
							direction = direction :: "horizontal" | "vertical",
							measured = measured,
							itemSize = 20,
							gap = gap,
							crossGap = 10,
							overscan = 0,
							status = status,
							controls = controls,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
					Verify.expect(assert(controls.placementOf)(3).offset):toBe(65)
					Verify.expect(status:peek().extent):toBe(160)
					measured:set({ [1] = 40 })
					Verify.expect(assert(controls.placementOf)(3).offset):toBe(45)
					columns:set(1)
					Verify.expect(assert(controls.placementOf)(2).offset):toBe(45)
					local second = node:FindFirstChild("2", true)
					Verify.expect(
						if direction == "horizontal" then second.Position.X.Offset else second.Position.Y.Offset
					)
						:toBe(45)
					gap:set(9)
					Verify.expect(assert(controls.placementOf)(2).offset):toBe(49)
					Verify.expect((node:FindFirstChild("2", true))):toBe(second)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("observes automatic row sizes without overwriting content geometry", {
			id = "native_collections::Compose native collections::observes automatic row sizes without overwriting content geometry",
			run = function()
				local engine, runtime, UI, target = setup()
				local status = Compose.cell({
					mode = "windowed" :: "windowed",
					direction = "vertical" :: "vertical",
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
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(5),
						key = key,
						itemSize = 20,
						measure = true,
						status = status,
						render = function(): GuiObject
							return (
								(
									((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown
								) :: FrameConstructor
							) "Measured" {
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
							}
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local content = node:FindFirstChild("1", true):FindFirstChild("Measured", true)
				content.AbsoluteSize = engine.types.Vector2.new(200, 60)
				Verify.expect(status:peek().extent):toBe(140)
				Verify.expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				Verify.expect(content.Size.Y.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("measures original content through action and selection wrappers", {
			id = "native_collections::Compose native collections::measures original content through action and selection wrappers",
			run = function()
				local engine, runtime, UI, target = setup()
				local status = Compose.cell({
					mode = "windowed" :: "windowed",
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
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(5),
						key = key,
						itemSize = 20,
						measure = true,
						selectionMode = "multiple" :: "multiple",
						editing = true,
						rowActions = function(): FixtureCollectionTypes.RowActionsOptions
							return { trailing = { { id = "open", label = "Open", onActivate = function() end } } }
						end,
						status = status,
						render = function(): GuiObject
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor) "Measured" {
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
							}
						end,
					}
					return UI.VirtualList(props)
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local content = node:FindFirstChild("1", true):FindFirstChild("Measured", true)
				content.AbsoluteSize = engine.types.Vector2.new(200, 60)
				Verify.expect(status:peek().extent):toBe(140)
				Verify.expect(content.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				Verify.expect(content.Size.Y.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("measures a row at its unscaled size while a lift scale grows it", {
			id = "native_collections::Compose native collections::measures a row at its unscaled size while a lift scale grows it",
			run = function()
				local engine, runtime, UI, target = setup()
				local status = Compose.cell({
					mode = "windowed" :: "windowed",
					direction = "vertical" :: "vertical",
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
				local lift = Compose.cell(1)
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(5),
						key = key,
						itemSize = 20,
						measure = true,
						status = status,
						render = function(): GuiObject
							return (
								(
									((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown
								) :: FrameConstructor
							) "Measured" {
								AutomaticSize = engine.types.Enum.AutomaticSize.Y,
								Size = engine.types.UDim2.new(1, 0, 0, 0),
								((runtime.constructors.UIScale :: unknown) :: UIScaleConstructor)({
									Name = "Lift",
									Scale = lift,
								}),
							}
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local slot = node:FindFirstChild("1", true)
				local content = slot:FindFirstChild("Measured", true)
				content.AbsoluteSize = engine.types.Vector2.new(200, 60)
				slot.AbsoluteSize = engine.types.Vector2.new(200, 60)
				Verify.expect(status:peek().extent):toBe(140)
				lift:set(1.5)
				content.AbsoluteSize = engine.types.Vector2.new(300, 90)
				Verify.expect(status:peek().extent):toBe(140)
				Verify.expect(slot.Size.Y.Offset):toBe(60)
				content.AbsoluteSize = engine.types.Vector2.new(300, 90.6)
				Verify.expect(slot.Size.Y.Offset):toBe(60)
				content.AbsoluteSize = engine.types.Vector2.new(300, 135)
				Verify.expect(slot.Size.Y.Offset):toBe(90)
				Verify.expect(status:peek().extent):toBe(170)
				content.AbsoluteSize = engine.types.Vector2.new(300, 90)
				Verify.expect(slot.Size.Y.Offset):toBe(60)
				slot.AbsoluteSize = engine.types.Vector2.new(200, 60)
				Verify.expect(status:peek().extent):toBe(140)
				lift:set(1)
				content.AbsoluteSize = engine.types.Vector2.new(200, 60)
				Verify.expect(slot.Size.Y.Offset):toBe(60)
				Verify.expect(status:peek().extent):toBe(140)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("measures a slot-filling row in layout units under a scaled ancestor", {
			id = "native_collections::Compose native collections::measures a slot-filling row in layout units under a scaled ancestor",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(3),
						key = key,
						itemSize = 20,
						measure = true,
						render = function(): GuiObject
							return (
								(
									((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown
								) :: FrameConstructor
							) "Fill" {
								Size = engine.types.UDim2.fromScale(1, 1),
							}
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				node:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.new(1.25, 1.25)
				local slot = node:FindFirstChild("1", true)
				local fill = slot:FindFirstChild("Fill", true)
				local writes = 0
				local function relayout()
					writes += 1
					if writes > 40 then
						return
					end
					local size = engine.types.Vector2.new(200 * 1.25, slot.Size.Y.Offset * 1.25)
					slot.AbsoluteSize = size
					fill.AbsoluteSize = size
				end
				slot:GetPropertyChangedSignal("Size"):Connect(relayout)
				relayout()
				Verify.expect(slot.Size.Y.Offset):toBe(20)
				Verify.expect(writes):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("follows a readable follow policy while the viewport stays at the end", {
			id = "native_collections::Compose native collections::follows a readable follow policy while the viewport stays at the end",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, follow = Compose.cell(records(10)), Compose.cell("none" :: "end" | "none")
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						follow = follow,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				Verify.expect(node.CanvasPosition.Y):toBe(0)
				node.CanvasPosition = engine.types.Vector2.new(0, 100)
				source:set(records(11))
				Verify.expect(node.CanvasPosition.Y):toBe(100)
				node.CanvasPosition = engine.types.Vector2.new(0, 120)
				follow:set("end")
				Verify.expect(node.CanvasPosition.Y):toBe(120)
				source:set(records(12))
				Verify.expect(node.CanvasPosition.Y):toBe(140)
				follow:set("none")
				source:set(records(13))
				Verify.expect(node.CanvasPosition.Y):toBe(140)
				stop()
				Verify.expect(function()
					runtime.mount(function()
						return UI.VirtualList({
							from = source,
							key = key,
							follow = "bottom",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						} :: any)
					end, target)
				end):toThrow()
				runtime:dispose()
			end,
		})

		verifyHarness:case("follows appended rows only while native viewport stays at the end", {
			id = "native_collections::Compose native collections::follows appended rows only while native viewport stays at the end",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, status =
					Compose.cell(records(10)), Compose.cell({
						mode = "windowed" :: "windowed",
						direction = "vertical" :: "vertical",
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
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						follow = "end" :: "end",
						status = status,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				Verify.expect(node.CanvasPosition.Y):toBe(100)
				source:set(records(11))
				Verify.expect(node.CanvasPosition.Y):toBe(120)
				node.CanvasPosition = engine.types.Vector2.new(0, 0)
				source:set(records(12))
				Verify.expect(node.CanvasPosition.Y):toBe(0)
				Verify.expect(status:peek().following):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("restores the keyed native focus target when virtualization remounts it", {
			id = "native_collections::Compose native collections::restores the keyed native focus target when virtualization remounts it",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				assert(focus.focus)(50)
				Verify.expect(gui.SelectedObject.Text):toBe("50")
				Verify.expect(node.CanvasPosition.Y):toBe(900)
				local action
				for _, native in engine.made do
					if native.Name == "Activate" and not native:isDestroyed() and native.Parent.Enabled then
						action = native
					end
				end
				Verify.expect(action ~= nil):toBe(true)
				node.CanvasPosition = engine.types.Vector2.new(0, 0)
				Verify.expect(gui.SelectedObject):toBeNil()
				Verify.expect((action:isDestroyed())):toBe(true)
				node.CanvasPosition = engine.types.Vector2.new(0, 900)
				Verify.expect(gui.SelectedObject.Text):toBe("50")
				stop()
				Verify.expect(gui.SelectedObject):toBeNil()
				runtime:dispose()
			end,
		})

		verifyHarness:case("waits for a PlayerGui before it restores the keyed focus target", {
			id = "native_collections::Compose native collections::waits for a PlayerGui before it restores the keyed focus target",
			run = function()
				local engine, runtime, UI, target, gui = setup({ engine = { selectionNeedsPlayerGui = true } })
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				Verify.expect((pcall(assert(focus.focus), 50))):toBe(true)
				Verify.expect(gui.SelectedObject):toBeNil()
				target.Parent = engine.new("PlayerGui")
				assert(focus.focus)(51)
				Verify.expect(gui.SelectedObject.Text):toBe("51")
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps table cells alive across sort and native column resize and prunes selection", {
			id = "native_collections::Compose native collections::keeps table cells alive across sort and native column resize and prunes selection",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local source = Compose.cell({ { id = 1, label = "Z" }, { id = 2, label = "A" } })
				local sort, widths, selection =
					Compose.cell(nil :: { column: string, direction: "ascending" | "descending" }?),
					Compose.cell({} :: { [string]: number }),
					Compose.cell({ [1] = true })
				local builds = 0
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = source,
						key = key,
						sort = sort,
						widths = widths,
						selection = selection,
						columns = {
							{
								id = "label",
								label = "Name",
								width = 100,
								minWidth = 60,
								maxWidth = 160,
								render = function(current): GuiObject
									builds += 1
									return button(UI, current)
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body, header = node:FindFirstChild("Body"), node:FindFirstChild("Header")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local original = body:FindFirstChild("1", true):FindFirstChild("Action", true)
				local column = header:FindFirstChild("label")
				column:FindFirstChild("Sort").Activated:Fire()
				Verify.expect((sort:peek())):toEqual({ column = "label", direction = "ascending" :: "ascending" })
				Verify.expect((body:FindFirstChild("1", true):FindFirstChild("Action", true))):toBe(original)
				column.AbsoluteSize = engine.types.Vector2.new(100, 40)
				local grip = column:FindFirstChild("Resize")
				Verify.expect(grip.AnchorPoint):toBe(engine.types.Vector2.new(0.5, 0))
				Verify.expect(grip.Position):toBe(engine.types.UDim2.fromScale(1, 0))
				Verify.expect(grip.Size.X.Offset):toBe(12)
				Verify.expect(header.Size.Y.Offset):toBe(40)
				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
				Verify.expect(grip.Size.X.Offset):toBe(44)
				Verify.expect(header.Size.Y.Offset):toBe(44)
				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(grip.Size.X.Offset):toBe(12)
				Verify.expect(header.Size.Y.Offset):toBe(40)
				local detector = column:FindFirstChildWhichIsA("UIDragDetector", true)
				detector.DragStart:Fire(engine.types.Vector2.new(100, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(180, 10))
				Verify.expect(widths:peek().label):toBe(160)
				column:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.new(200, 2)
				column.AbsoluteSize = engine.types.Vector2.new(200, 80)
				detector.DragStart:Fire(engine.types.Vector2.new(100, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(180, 10))
				Verify.expect(widths:peek().label):toBe(140)
				widths:set({ label = 160 })
				column:FindFirstChild("Resize").SelectionGained:Fire()
				target:FindFirstChild("FacetNarrowColumn"):FindFirstChild("NarrowColumn").Pressed:Fire()
				Verify.expect(widths:peek().label):toBe(152)
				Verify.expect(builds):toBe(2)
				source:set({ { id = 2, label = "A" } })
				Verify.expect(selection:peek()[1]):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("glides the rows that follow a deleted row into place and snaps under reduced motion", {
			id = "native_collections::Compose native collections::glides the rows that follow a deleted row into place and snaps under reduced motion",
			run = function()
				for _, reduced in { false, true } do
					local engine, runtime, UI, target = setup({ motionLevel = if reduced then "none" else "normal" })
					local source = Compose.cell(records(5))
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = source,
							key = key,
							itemSize = 20,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
					local second = node:FindFirstChild("2", true)
					Verify.expect(second.Position.Y.Offset):toBe(20)
					local remaining = records(5)
					table.remove(remaining, 1)
					source:set(remaining)
					Verify.expect(second.Position.Y.Offset):toBe(if reduced then 0 else 20)
					for _ = 1, 30 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect(second.Position.Y.Offset):toBe(0)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("lays rows out in layout units under a scaled ancestor, as in a ten-foot preview", {
			id = "native_collections::Compose native collections::lays rows out in layout units under a scaled ancestor, as in a ten-foot preview",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(20),
						key = key,
						itemSize = 20,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.new(0.8, 0.8)
				node.AbsoluteWindowSize = engine.types.Vector2.new(160, 80)
				Verify.expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(200)
				Verify.expect(node:FindFirstChild("5", true) ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"resolves a card rail to one card with a peek on compact touch and to whole cards elsewhere",
			{
				id = "native_collections::Compose native collections::resolves a card rail to one card with a peek on compact touch and to whole cards elsewhere",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2 = engine.types.Enum, engine.types.Vector2
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.KeyboardAndMouse
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(20),
							key = key,
							direction = "horizontal" :: "horizontal",
							itemSize = "cards" :: "cards",
							gap = 8,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = V2.new(1000, 200)
					Verify.expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(244)
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
					node.AbsoluteWindowSize = V2.new(400, 200)
					Verify.expect(node:FindFirstChild("1", true).Size.X.Offset):toBe(352)
					Verify.expect(node:FindFirstChild("2", true).Position.X.Offset):toBe(360)
					stop()
					runtime:dispose()
					Verify.expect((pcall(function()
						runtime.mount(function()
							return UI.VirtualList({ from = {}, render = button, cards = { perView = 2 } } :: any)
						end, target)
					end))):toBe(false)
				end,
			}
		)

		verifyHarness:case(
			"withholds a table row's destructive actions from every route when rowDeletable refuses it",
			{
				id = "native_collections::Compose native collections::withholds a table row's destructive actions from every route when rowDeletable refuses it",
				run = function()
					local engine, runtime, UI, target = setup()
					local stop, node: any = runtime.mount(function()
						return UI.Table({
							from = records(3),
							key = key,
							itemSize = 20,
							deletable = true,
							rowDeletable = function(item)
								return item.id ~= 1
							end,
							onDelete = function() end,
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
							rowActions = function(): FixtureCollectionTypes.RowActionsOptions?
								return {
									trailing = {
										{ id = "delete", label = "Delete", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
										{ id = "flag", label = "Flag" } :: FixtureCollectionTypes.RowAction,
									},
								}
							end,
						})
					end, target)
					local body = node:FindFirstChild("Body")
					body.AbsoluteWindowSize = engine.types.Vector2.new(300, 100)
					body.Parent.AbsoluteSize = body.AbsoluteWindowSize
					local first, second = body:FindFirstChild("1", true), body:FindFirstChild("2", true)
					Verify.expect((first:FindFirstChild("trailing", true):FindFirstChild("delete"))):toBeNil()
					Verify.expect(first:FindFirstChild("trailing", true):FindFirstChild("flag") ~= nil):toBe(true)
					Verify.expect(second:FindFirstChild("trailing", true):FindFirstChild("delete") ~= nil):toBe(true)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"offers a table's own Edit toolbar on touch, gamepad and a mouseless keyboard, never with a mouse",
			{
				id = "native_collections::Compose native collections::offers a table's own Edit toolbar on touch, gamepad and a mouseless keyboard, never with a mouse",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E = engine.types.Enum
					local input: any = assert(ctx.config.userInputService)
					input.PreferredInput, input.MouseEnabled, input.KeyboardEnabled =
						E.PreferredInput.KeyboardAndMouse, true, true
					local stop, node: any = runtime.mount(function()
						return UI.Table({
							from = records(3),
							key = key,
							reorderable = true,
							onReorder = function() end,
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end, target)
					local function shown()
						return node:FindFirstChild("Toolbar") ~= nil
					end
					Verify.expect((shown())):toBe(false)
					input.MouseEnabled = false
					Verify.expect((shown())):toBe(true)
					input.MouseEnabled = true
					input.PreferredInput = E.PreferredInput.Gamepad
					Verify.expect((shown())):toBe(true)
					input.PreferredInput = E.PreferredInput.Touch
					Verify.expect((shown())):toBe(true)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("a bare modifier press does not flip a touch table to its pointer layout; a real key does", {
			id = "native_collections::Compose native collections::a bare modifier press does not flip a touch table to its pointer layout; a real key does",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E = engine.types.Enum
				local input: any = assert(ctx.config.userInputService)
				local pressed = {}
				input.GetKeysPressed = function()
					return pressed
				end
				input.GetMouseButtonsPressed = function()
					return {}
				end
				input.PreferredInput, input.TouchEnabled, input.MouseEnabled = E.PreferredInput.Touch, true, true
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(3),
						key = key,
						deletable = true,
						onDelete = function() end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local function shown()
					return node:FindFirstChild("Toolbar") ~= nil
				end
				Verify.expect((shown())):toBe(true)
				for _, modifier in { E.KeyCode.LeftSuper, E.KeyCode.LeftControl, E.KeyCode.LeftShift } do
					pressed = { { KeyCode = modifier } }
					input.InputBegan:Fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = modifier })
					input.PreferredInput = E.PreferredInput.KeyboardAndMouse
					Verify.expect((shown())):toBe(true)
					pressed = {}
					input.PreferredInput = E.PreferredInput.Touch
				end
				pressed = { { KeyCode = E.KeyCode.LeftSuper } }
				input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				Verify.expect((shown())):toBe(true)
				pressed = { { KeyCode = E.KeyCode.LeftSuper }, { KeyCode = E.KeyCode.C } }
				input.InputBegan:Fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.C })
				Verify.expect((shown())):toBe(false)
				pressed = {}
				input.PreferredInput = E.PreferredInput.Touch
				Verify.expect((shown())):toBe(true)
				pressed = { { KeyCode = E.KeyCode.A } }
				input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				Verify.expect((shown())):toBe(false)
				pressed = {}
				input.PreferredInput = E.PreferredInput.Touch
				pressed = { { KeyCode = E.KeyCode.LeftShift } }
				input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				Verify.expect((shown())):toBe(true)
				pressed = {}
				input.InputChanged:Fire({ UserInputType = E.UserInputType.MouseMovement })
				Verify.expect((shown())):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"keeps a gap under its Edit toolbar and paints the header band across the persistent scrollbar",
			{
				id = "native_collections::Compose native collections::keeps a gap under its Edit toolbar and paints the header band across the persistent scrollbar",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E = engine.types.Enum
					local input: any = assert(ctx.config.userInputService)
					input.PreferredInput, input.MouseEnabled = E.PreferredInput.Touch, false
					local stop, node: any = runtime.mount(function()
						return UI.Table({
							from = records(3),
							key = key,
							reorderable = true,
							onReorder = function() end,
							columns = {
								{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end, target)
					node:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(347, 240)
					local toolbar, header, band =
						node:FindFirstChild("Toolbar"), node:FindFirstChild("Header"), node:FindFirstChild("HeaderBand")
					Verify.expect(header.Position.Y.Offset - toolbar.Size.Y.Offset):toBe(8)
					Verify.expect(band.Position.Y.Offset):toBe(header.Position.Y.Offset)
					Verify.expect(band.Size.X.Scale):toBe(1)
					Verify.expect(band.Size.X.Offset):toBe(0)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("holds a custom cell's content in the themed inset a text value uses", {
			id = "native_collections::Compose native collections::holds a custom cell's content in the themed inset a text value uses",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(1),
						key = key,
						columns = {
							{ id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{
								id = "mark",
								label = "Mark",
								width = 120,
								render = function(): GuiObject
									return (
										(
											((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown
										) :: FrameConstructor
									)({ Name = "Mark" })
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				node:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(300, 200)
				local mark = node:FindFirstChild("Mark", true)
				Verify.expect(mark.Parent.Name):toBe("Inset")
				Verify.expect((mark.Parent:HasTag("facet-tablecellinset"))):toBe(true)
				Verify.expect((mark.Parent.Parent:HasTag("facet-tablecell"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"sizes table rows by viewing distance: dense pointer, two-line touch, one large line at ten feet",
			{
				id = "native_collections::Compose native collections::sizes table rows by viewing distance: dense pointer, two-line touch, one large line at ten feet",
				run = function()
					local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
					local E = engine.types.Enum
					local input: any = assert(ctx.config.userInputService)
					input.PreferredInput, input.MouseEnabled, input.TouchEnabled =
						E.PreferredInput.Gamepad, false, false
					gui.ViewportDisplaySize = E.DisplaySize.Large
					local stop, node: any = runtime.mount(function()
						return UI.Table({
							from = records(3),
							key = key,
							columns = {
								{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end, target)
					node:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(300, 400)
					local function height()
						return node:FindFirstChild("1", true).Size.Y.Offset
					end
					local function wraps()
						return node:FindFirstChild("1", true):FindFirstChild("Value", true).TextWrapped
					end
					Verify.expect((height())):toBe(56)
					Verify.expect((wraps())):toBe(false)
					gui.ViewportDisplaySize = E.DisplaySize.Medium
					Verify.expect((height())):toBe(44)
					input.PreferredInput, input.TouchEnabled = E.PreferredInput.Touch, true
					Verify.expect((height())):toBe(56)
					Verify.expect((wraps())):toBe(true)
					input.PreferredInput, input.MouseEnabled, input.TouchEnabled =
						E.PreferredInput.KeyboardAndMouse, true, false
					Verify.expect((height())):toBe(44)
					Verify.expect((wraps())):toBe(false)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("marks each row's selection in the leading gutter while a selectable table is editing", {
			id = "native_collections::Compose native collections::marks each row's selection in the leading gutter while a selectable table is editing",
			run = function()
				local engine, runtime, UI, target = setup()
				local editing, selection = Compose.cell(false), Compose.cell({ [2] = true })
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(3),
						key = key,
						editing = editing,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				node:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(300, 400)
				local function mark(row)
					return node:FindFirstChild("Body")
						:FindFirstChild(tostring(row), true)
						:FindFirstChild("SelectMark", true)
				end
				Verify.expect(mark(1) == nil or mark(1).Visible == false):toBe(true)
				editing:set(true)
				Verify.expect(mark(1).Visible):toBe(true)
				Verify.expect((mark(1):HasTag("facet-radio-mark"))):toBe(true)
				Verify.expect(mark(1).Selectable):toBe(false)
				Verify.expect(mark(1):FindFirstChild("Check").Visible):toBe(false)
				Verify.expect(mark(2):FindFirstChild("Check").Visible):toBe(true)
				Verify.expect(node:FindFirstChild("Header").Position.X.Offset):toBe(44)
				selection:set({ [1] = true })
				Verify.expect(mark(1):FindFirstChild("Check").Visible):toBe(true)
				Verify.expect(mark(2):FindFirstChild("Check").Visible):toBe(false)
				editing:set(false)
				Verify.expect(mark(1).Visible):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("resizes and sorts a column from the keyboard or pad and releases the grip to its heading", {
			id = "native_collections::Compose native collections::resizes and sorts a column from the keyboard or pad and releases the grip to its heading",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local sort, widths = Compose.cell(nil :: {}?), Compose.cell({})
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(3),
						key = key,
						sort = sort,
						widths = widths,
						columns = {
							{ id = "label", label = "Name", width = 100, minWidth = 60 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local column = node:FindFirstChild("Header"):FindFirstChild("label")
				column.AbsoluteSize = engine.types.Vector2.new(100, 40)
				local heading, grip = column:FindFirstChild("Sort"), column:FindFirstChild("Resize")
				local function press(name: string)
					for _, context in target:GetChildren() do
						if context.Name == "Facet" .. name and context.Enabled then
							context:FindFirstChild(name).Pressed:Fire()
							return true
						end
					end
					return false
				end
				heading.SelectionGained:Fire()
				Verify.expect((press("NarrowColumnKey"))):toBe(true)
				Verify.expect(widths:peek().label):toBe(92)
				heading.SelectionLost:Fire()
				grip.SelectionGained:Fire()
				Verify.expect((press("WidenColumnKey"))):toBe(true)
				Verify.expect(widths:peek().label):toBe(100)
				Verify.expect((press("SortColumn"))):toBe(true)
				Verify.expect((sort:peek())):toEqual({ column = "label", direction = "ascending" :: "ascending" })
				gui.SelectedObject = grip
				Verify.expect((press("ReleaseColumn"))):toBe(true)
				Verify.expect(gui.SelectedObject):toBe(heading)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("resizes a compact touch column without jumping to its desktop minimum", {
			id = "native_collections::Compose native collections::resizes a compact touch column without jumping to its desktop minimum",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2 = engine.types.Enum, engine.types.Vector2
				assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
				local widths = Compose.cell({} :: { [string]: number })
				local stop, node: any = runtime.mount(function()
					return UI.Table {
						from = records(1),
						key = key,
						widths = widths,
						columns = {
							{ id = "label", minWidth = 180 },
							{ id = "kind", width = 100 },
						} :: { FixtureCollectionTypes.TableColumn<any, any> },
					}
				end, target)
				local header = node:FindFirstChild("Header")
				local column = header:FindFirstChild("label")
				column.AbsoluteSize = V2.new(120, 44)
				local detector = column:FindFirstChild("Resize"):FindFirstChildWhichIsA("UIDragDetector")
				Verify.expect(column.ZIndex > header:FindFirstChild("kind").ZIndex):toBe(true)
				detector.DragStart:Fire(V2.new(120, 0))
				detector.DragContinue:Fire(V2.new(130, 0))
				Verify.expect(widths:peek().label):toBe(130)
				detector.DragEnd:Fire()
				stop()
			end,
		})

		verifyHarness:case("leaves the cross-axis D-pad to the engine so focus can leave a rail for the next shelf", {
			id = "native_collections::Compose native collections::leaves the cross-axis D-pad to the engine so focus can leave a rail for the next shelf",
			run = function()
				for _, direction in { "horizontal", "vertical" } :: { "horizontal" | "vertical" } do
					local engine, runtime, UI, target, gui = setup()
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(6),
							key = key,
							itemSize = 40,
							direction = direction :: "horizontal" | "vertical",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 200)
					gui.SelectedObject = node:FindFirstChild("1", true):FindFirstChild("Action", true)
					local enabled = {}
					for _, context in target:GetChildren() do
						if context:IsA("InputContext") and context.Enabled then
							enabled[context.Name] = true
						end
					end
					local along = if direction == "horizontal" then "Right" else "Down"
					local across = if direction == "horizontal" then "Down" else "Right"
					Verify.expect(
						`{direction} {enabled["FacetCollection" .. along] == true} {enabled["FacetCollection" .. across] == true}`
					):toBe(`{direction} true false`)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("keeps focus on the item by default and on the slot with focusPolicy index", {
			id = "native_collections::Compose native collections::keeps focus on the item by default and on the slot with focusPolicy index",
			run = function()
				for _, policyName in { "key", "index" } do
					local engine, runtime, UI, target = setup()
					local source, focus: FixtureCollectionTypes.FocusControls<any> = Compose.cell(records(6)), {}
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = source,
							key = key,
							itemSize = 20,
							focus = focus,
							focusPolicy = policyName :: "index" | "key",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 120)
					assert(focus.focus)(2)
					local reversed = records(6)
					for index = 1, 3 do
						reversed[index], reversed[7 - index] = reversed[7 - index], reversed[index]
					end
					source:set(reversed)
					Verify.expect((assert(focus.current):peek())):toBe(if policyName == "index" then 5 else 2)
					source:set(records(6))
					Verify.expect((assert(focus.current):peek())):toBe(2)
					stop()
					runtime:dispose()
				end
				local _, runtime, UI, target = setup()
				Verify.expect((pcall(function()
					runtime.mount(function()
						return UI.VirtualList({ from = {}, render = button, focusPolicy = "slot" } :: any)
					end, target)
				end))):toBe(false)
			end,
		})

		verifyHarness:case(
			"picks a row up from a held finger anywhere on it and leaves a moving finger to the scroll",
			{
				id = "native_collections::Compose native collections::picks a row up from a held finger anywhere on it and leaves a moving finger to the scroll",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V3 = engine.types.Enum, engine.types.Vector3
					local reorders = 0
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(6),
							key = key,
							itemSize = 20,
							reorderable = true,
							onReorder = function()
								reorders += 1
							end,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 120)
					local input: any = assert(ctx.config.userInputService)
					local action = node:FindFirstChild("1", true):FindFirstChild("Action", true)
					local swipe = { UserInputType = E.UserInputType.Touch, Position = V3.new(50, 10, 0) }
					action.InputBegan:Fire(swipe)
					swipe.Position = V3.new(50, 40, 0)
					input.InputChanged:Fire(swipe)
					for _ = 1, 30 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect((node:FindFirstChild("DragImage", true))):toBeNil()
					local hold = { UserInputType = E.UserInputType.Touch, Position = V3.new(50, 10, 0) }
					action.InputBegan:Fire(hold)
					engine.heartbeat:Fire(0.2)
					Verify.expect((node:FindFirstChild("DragImage", true))):toBeNil()
					node:FindFirstChild("1", true)
						:FindFirstChild("Reorderable", true).TouchLongPress
						:Fire({ engine.types.Vector2.new(50, 10) }, E.UserInputState.Begin)
					Verify.expect(node:FindFirstChild("DragImage", true) ~= nil):toBe(true)
					Verify.expect(node.ScrollingEnabled):toBe(false)
					hold.Position = V3.new(50, 70, 0)
					input.InputChanged:Fire(hold)
					hold.UserInputState = E.UserInputState.End
					input.InputEnded:Fire(hold)
					Verify.expect(reorders):toBe(1)
					Verify.expect(node.ScrollingEnabled):toBe(true)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("scrolls a dragged row at the list's edge unless autoscroll is off", {
			id = "native_collections::Compose native collections::scrolls a dragged row at the list's edge unless autoscroll is off",
			run = function()
				for _, autoscroll in { true, false } do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V3 = engine.types.Enum, engine.types.Vector3
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(20),
							key = key,
							itemSize = 20,
							reorderable = true,
							autoscroll = autoscroll,
							onReorder = function() end,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
					nativeDrag.press(node:FindFirstChild("1", true):FindFirstChild("Action", true), {
						UserInputType = E.UserInputType.MouseButton1,
						Position = V3.new(50, 10, 0),
					})
					nativeDrag.move(ctx.config.userInputService, {
						UserInputType = E.UserInputType.MouseMovement,
						Position = V3.new(50, 98, 0),
					})
					for _ = 1, 10 do
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect(node.CanvasPosition.Y > 0):toBe(autoscroll)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("hands edge autoscroll to the enclosing scroller once the list can travel no further", {
			id = "native_collections::Compose native collections::hands edge autoscroll to the enclosing scroller once the list can travel no further",
			run = function()
				local engine, runtime, UI, _, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local page = engine.new("ScrollingFrame")
				page.AbsoluteWindowSize, page.AbsoluteCanvasSize = V2.new(200, 110), V2.new(200, 600)
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(20),
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function() end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, page)
				node.AbsoluteWindowSize = V2.new(200, 100)
				nativeDrag.press(node:FindFirstChild("1", true):FindFirstChild("Action", true), {
					UserInputType = E.UserInputType.MouseButton1,
					Position = V3.new(50, 10, 0),
				})
				nativeDrag.move(ctx.config.userInputService, {
					UserInputType = E.UserInputType.MouseMovement,
					Position = V3.new(50, 98, 0),
				})
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(node.CanvasPosition.Y > 0):toBe(true)
				Verify.expect(page.CanvasPosition.Y):toBe(0)
				node.CanvasPosition = V2.new(0, 300)
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(node.CanvasPosition.Y):toBe(300)
				Verify.expect(page.CanvasPosition.Y > 0):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("scrolls a horizontal rail by a mouse drag and keeps the press from activating a card", {
			id = "native_collections::Compose native collections::scrolls a horizontal rail by a mouse drag and keeps the press from activating a card",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(20),
						key = key,
						direction = "horizontal" :: "horizontal",
						itemSize = 100,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = V2.new(300, 100)
				node.AbsoluteSize = V2.new(300, 100)
				local input: any = assert(ctx.config.userInputService)
				local function mouse(kind, x)
					return { UserInputType = kind, Position = V3.new(x, 50, 0) }
				end
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 250))
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 247))
				Verify.expect(node.CanvasPosition.X):toBe(0)
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 150))
				Verify.expect(node.CanvasPosition.X):toBe(100)
				Verify.expect(node:FindFirstChild("Items").Interactable):toBe(false)
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 400))
				Verify.expect(node.CanvasPosition.X):toBe(0)
				input.InputEnded:Fire(mouse(E.UserInputType.MouseButton1, 400))
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(node:FindFirstChild("Items").Interactable):toBe(true)
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 900))
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 700))
				Verify.expect(node.CanvasPosition.X):toBe(0)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("carries a released mouse drag on a horizontal rail with decaying momentum", {
			id = "native_collections::Compose native collections::carries a released mouse drag on a horizontal rail with decaying momentum",
			run = function()
				local now = 0
				local engine, runtime, UI, target, _, ctx = setup({
					userInputService = {},
					clock = function()
						return now
					end,
				})
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(40),
						key = key,
						direction = "horizontal" :: "horizontal",
						itemSize = 100,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = V2.new(300, 100)
				node.AbsoluteSize = V2.new(300, 100)
				local input: any = assert(ctx.config.userInputService)
				local function mouse(kind, x)
					return { UserInputType = kind, Position = V3.new(x, 50, 0) }
				end
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 280))
				for x = 260, 180, -20 do
					now += 1 / 60
					input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, x))
				end
				now += 1 / 120
				input.InputChanged:Fire(mouse(E.UserInputType.MouseMovement, 180))
				local released = node.CanvasPosition.X
				Verify.expect(released):toBe(100)
				input.InputEnded:Fire(mouse(E.UserInputType.MouseButton1, 180))
				local previous, step = released, 0
				for _ = 1, 20 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
					local at = node.CanvasPosition.X
					Verify.expect(at >= previous):toBe(true)
					step, previous = at - previous, at
				end
				Verify.expect(previous > released + 100):toBe(true)
				for _ = 1, 600 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
				end
				local rest = node.CanvasPosition.X
				now += 1 / 60
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(node.CanvasPosition.X):toBe(rest)
				Verify.expect(step > 0):toBe(true)
				input.InputBegan:Fire(mouse(E.UserInputType.MouseButton1, 200))
				input.InputEnded:Fire(mouse(E.UserInputType.MouseButton1, 200))
				now += 1 / 60
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(node.CanvasPosition.X):toBe(rest)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"places a dragged row and its image in layout units under a scaled ancestor, as in a ten-foot preview",
			{
				id = "native_collections::Compose native collections::places a dragged row and its image in layout units under a scaled ancestor, as in a ten-foot preview",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
					local moved
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(20),
							key = key,
							itemSize = 20,
							reorderable = true,
							onReorder = function(keys: { number }, slot: number)
								moved = `{table.concat(keys, ",")}@{slot}`
							end,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node:FindFirstChild("LayoutUnit").AbsoluteSize = V2.new(2, 2)
					node.AbsoluteWindowSize = V2.new(400, 400)
					local input: any = assert(ctx.config.userInputService)
					nativeDrag.press(node:FindFirstChild("1", true):FindFirstChild("Action", true), {
						UserInputType = E.UserInputType.MouseButton1,
						Position = V3.new(50, 20, 0),
					})

					nativeDrag.move(
						input,
						{ UserInputType = E.UserInputType.MouseMovement, Position = V3.new(50, 130, 0) }
					)
					Verify.expect(node:FindFirstChild("DragImage", true).Position.Y.Offset):toBe(65 - 10)
					nativeDrag.finish(
						input,
						{ UserInputType = E.UserInputType.MouseButton1, Position = V3.new(50, 130, 0) }
					)
					Verify.expect(moved):toBe("1@2")
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("keeps grid drag cards at cell size and picks insertion slots across both axes", {
			id = "native_collections::Compose native collections::keeps grid drag cards at cell size and picks insertion slots across both axes",
			run = function()
				for _, horizontal in { false, true } do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
					local requests = {}
					local stop, node: any = runtime.mount(function()
						return UI.VirtualGrid({
							from = records(6),
							key = key,
							columns = 3,
							itemSize = 80,
							gap = 10,
							direction = if horizontal then "horizontal" :: "horizontal" else "vertical" :: "vertical",
							selection = Compose.cell({ [1] = true, [4] = true }),
							selectionMode = "multiple" :: "multiple",
							reorderable = true,
							onReorder = function(keys: { number }, slot: number)
								table.insert(requests, { keys = keys, slot = slot })
							end,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						} :: FixtureCollectionTypes.KeyedCollectionSpec<
							{ id: number, label: string },
							number
						>)
					end, target)
					node.AbsoluteSize = if horizontal then V2.new(300, 330) else V2.new(330, 300)
					node.AbsoluteWindowSize = node.AbsoluteSize
					local row = node:FindFirstChild("1", true)
					row:FindFirstChild("Reorderable", true).AbsoluteSize = if horizontal
						then V2.new(80, 100)
						else V2.new(100, 80)
					local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(20, 20, 0) }
					nativeDrag.press(row:FindFirstChild("RowHit", true), press)
					nativeDrag.move(ctx.config.userInputService, {
						UserInputType = E.UserInputType.MouseMovement,
						Position = if horizontal then V3.new(20, 300, 0) else V3.new(300, 20, 0),
					})
					local image = node:FindFirstChild("DragImage", true)
					Verify.expect(image.Size):toBe(
						if horizontal
							then engine.types.UDim2.fromOffset(86, 106)
							else engine.types.UDim2.fromOffset(106, 86)
					)
					local labels = {}
					for _, layer in image:GetChildren() do
						if layer.Name == "Reorderable" then
							table.insert(labels, layer:FindFirstChild("Action", true):GetAttribute("label"))
							Verify.expect(layer.Size):toBe(
								if horizontal
									then engine.types.UDim2.fromOffset(80, 100)
									else engine.types.UDim2.fromOffset(100, 80)
							)
						end
					end
					table.sort(labels)
					Verify.expect(labels):toEqual({ "1", "4" })
					local marker = node:FindFirstChild("DropLine", true)
					Verify.expect(marker.Size):toBe(
						if horizontal
							then engine.types.UDim2.fromOffset(80, 2)
							else engine.types.UDim2.fromOffset(2, 80)
					)
					nativeDrag.finish(ctx.config.userInputService, press)
					Verify.expect(requests):toEqual({ { keys = { 1, 4 }, slot = 2 } })
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case(
			"drags an image of the row, stacked two or three deep for a selection, from a press anywhere on it",
			{
				id = "native_collections::Compose native collections::drags an image of the row, stacked two or three deep for a selection, from a press anywhere on it",
				run = function()
					for _, count in { 1, 2, 4 } do
						local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
						local E, V3 = engine.types.Enum, engine.types.Vector3
						local chosen = {}
						for index = 1, count do
							chosen[index] = true
						end
						local stop, node: any = runtime.mount(function()
							return UI.VirtualList({
								from = records(6),
								key = key,
								itemSize = 20,
								selection = Compose.cell(chosen),
								selectionMode = "multiple" :: "multiple",
								reorderable = true,
								onReorder = function() end,
								render = function(current): GuiObject
									return button(UI, current)
								end,
							})
						end, target)
						node.AbsoluteWindowSize = engine.types.Vector2.new(200, 120)
						local row = node:FindFirstChild("1", true)
						local reorderable = row:FindFirstChild("Reorderable", true)
						reorderable.AbsoluteSize = engine.types.Vector2.new(200, 20)
						local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(50, 10, 0) }
						nativeDrag.press(row:FindFirstChild("Action", true), press)
						nativeDrag.move(ctx.config.userInputService, {
							UserInputType = E.UserInputType.MouseMovement,
							Position = V3.new(50, 40, 0),
						})
						local image = node:FindFirstChild("DragImage", true)
						Verify.expect(image ~= nil):toBe(true)
						Verify.expect(image.Interactable):toBe(false)
						local layers = {}
						for _, child in image:GetChildren() do
							if child.Name == "Reorderable" then
								table.insert(layers, child.Position.X.Offset)
							end
						end
						table.sort(layers)
						Verify.expect((table.concat(layers, ",")))
							:toBe(if count == 1 then "0" elseif count == 2 then "0,6" else "0,6,12")
						Verify.expect(reorderable.Interactable):toBe(true)
						Verify.expect(image:FindFirstChild("DragLabel").Visible):toBe(count > 1)
						local ghost = target:FindFirstChild("DragGhost")
						local stack = math.min(count - 1, 2) * 6
						Verify.expect(math.abs(ghost.AnchorPoint.X * ghost.Size.X.Offset - (200 - stack) / 4) < 0.001)
							:toBe(true)
						Verify.expect(math.abs(ghost.AnchorPoint.Y * ghost.Size.Y.Offset - 10) < 0.001):toBe(true)
						Verify.expect(ghost.Position):toBe(engine.types.UDim2.fromOffset(50, 40))
						stop()
						runtime:dispose()
					end
				end,
			}
		)

		verifyHarness:case("draws icon actions at a fixed width and arms the first action past a 0.6 full swipe", {
			id = "native_collections::Compose native collections::draws icon actions at a fixed width and arms the first action past a 0.6 full swipe",
			run = function()
				local engine, runtime, UI, target = setup()
				local deleted = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						fullSwipe = true,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "delete",
								label = "Delete",
								icon = "trash",
								role = "destructive" :: "destructive",
								onActivate = function()
									deleted += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
							{ id = "flag", label = "Flag", icon = "flag" } :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local tray = node:FindFirstChild("trailing")
				local delete, flag = tray:FindFirstChild("delete"), tray:FindFirstChild("flag")
				Verify.expect((delete:GetAttribute("label"))):toBe("Delete")
				Verify.expect(delete:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				local caption = delete:FindFirstChild("Title", true)
				Verify.expect(caption == nil or caption.Visible == false or caption.Text == ""):toBe(true)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(250, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(200, 20))
				Verify.expect(tray.Size.X.Offset):toBe(50)
				Verify.expect(`{delete.Size.X.Scale} {delete.Size.X.Offset}`):toBe("0 64")
				detector.DragContinue:Fire(engine.types.Vector2.new(170, 20))
				Verify.expect(`{delete.Size.X.Scale} {delete.Size.X.Offset}`):toBe("0 64")
				detector.DragContinue:Fire(engine.types.Vector2.new(65, 20))
				Verify.expect(delete.Size):toEqual(engine.types.UDim2.fromScale(1, 1))
				Verify.expect(flag.Visible):toBe(false)
				Verify.expect(tray.Size.X.Offset):toBe(185)
				detector.DragEnd:Fire()
				Verify.expect(deleted):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("uses native drag to reveal and invoke row actions with cancellation and coordination", {
			id = "native_collections::Compose native collections::uses native drag to reveal and invoke row actions with cancellation and coordination",
			run = function()
				local engine, runtime, UI, target = setup()
				local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, coordinator =
					Compose.cell(nil :: ("leading" | "trailing")?), Compose.cell(nil :: {}?)
				local invoked = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						open = open,
						coordinator = coordinator,
						fullSwipe = true,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "Delete",
								label = "Delete",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(200, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(120, 20))
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBe("trailing")
				coordinator:set({})
				Verify.expect((open:peek())):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(250, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 20))
				detector.DragEnd:Fire()
				Verify.expect(invoked):toBe(1)
				Verify.expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("swipes a Button row from a grip over the content and forwards a tap to the Button", {
			id = "native_collections::Compose native collections::swipes a Button row from a grip over the content and forwards a tap to the Button",
			run = function()
				local engine, runtime, UI, target = setup()
				local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, activated =
					Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						open = open,
						content = UI.Button "Mail" {
							label = "Mail",
							onActivate = function()
								activated += 1
							end,
						} :: GuiObject,
						trailing = {
							{ id = "Delete", label = "Delete", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local content = node:FindFirstChild("Content")
				local grip = content:FindFirstChild("SwipeGrip")
				local mail = content:FindFirstChild("Mail", true)
				Verify.expect((grip:IsA("GuiButton"))):toBe(true)
				Verify.expect(grip.Selectable):toBe(false)
				Verify.expect(grip.Visible):toBe(true)
				Verify.expect(grip.BackgroundTransparency):toBe(1)
				Verify.expect(grip.Size):toEqual(engine.types.UDim2.fromScale(1, 1))
				Verify.expect(grip.ZIndex > mail.ZIndex):toBe(true)
				Verify.expect(mail.Selectable):toBe(true)
				local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
				Verify.expect((node:FindFirstChildWhichIsA("UIDragDetector"))):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(150, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(153, 22))
				detector.DragEnd:Fire()
				Verify.expect(activated):toBe(1)
				Verify.expect((open:peek())):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(200, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(120, 20))
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBe("trailing")
				Verify.expect(activated):toBe(1)
				open:set(nil)
				detector.DragStart:Fire(engine.types.Vector2.new(150, 20))
				detector.DragContinue:Fire(engine.types.Vector2.new(150, 60))
				detector.DragEnd:Fire()
				Verify.expect(activated):toBe(1)
				Verify.expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("hands touch swipes to the native pan gesture so a vertical pan stays with the scroller", {
			id = "native_collections::Compose native collections::hands touch swipes to the native pan gesture so a vertical pan stays with the scroller",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E = engine.types.Enum
				local V2 = engine.types.Vector2
				local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, activated =
					Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						open = open,
						content = UI.Button "Mail" {
							label = "Mail",
							onActivate = function()
								activated += 1
							end,
						} :: GuiObject,
						trailing = {
							{ id = "Delete", label = "Delete", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = V2.new(300, 40)
				local grip = node:FindFirstChild("SwipeGrip", true)
				local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
				Verify.expect(detector.Enabled):toBe(true)
				assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
				Verify.expect(detector.Enabled):toBe(false)
				local function pan(to: any, state: any)
					grip.TouchPan:Fire({ to }, to - V2.new(200, 20), V2.zero, state)
				end
				pan(V2.new(190, 20), E.UserInputState.Begin)
				pan(V2.new(120, 20), E.UserInputState.Change)
				pan(V2.new(120, 20), E.UserInputState.End)
				grip.Activated:Fire()
				Verify.expect((open:peek())):toBe("trailing")
				Verify.expect(activated):toBe(0)
				open:set(nil)
				pan(V2.new(200, 10), E.UserInputState.Begin)
				pan(V2.new(200, -60), E.UserInputState.Change)
				pan(V2.new(200, -60), E.UserInputState.End)
				grip.Activated:Fire()
				Verify.expect((open:peek())):toBeNil()
				Verify.expect(activated):toBe(0)
				engine.heartbeat:Fire(1 / 60)
				grip.Activated:Fire()
				Verify.expect(activated):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("commits a touch row action from the final pan distance or native release velocity", {
			id = "native_collections::Compose native collections::commits a touch row action from the final pan distance or native release velocity",
			run = function()
				for _, sample in
					{
						{ distance = -220, speed = 0, expected = 1 },
						{ distance = -80, speed = -1400, expected = 1 },
						{ distance = -80, speed = 0, expected = 0 },
						{ distance = -80, speed = -1400, expected = 0, fullSwipe = false },
						{ distance = -220, speed = 0, expected = 0, cancel = true },
					}
				do
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E, V2 = engine.types.Enum, engine.types.Vector2
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, invoked =
						Compose.cell(nil :: ("leading" | "trailing")?), 0
					local stop, node: any = runtime.mount(function()
						return UI.RowActions({
							open = open,
							fullSwipe = sample.fullSwipe,
							content = UI.Button { label = "Track" } :: GuiObject,
							trailing = {
								{
									id = "remove",
									label = "Remove",
									role = "destructive" :: "destructive",
									onActivate = function()
										invoked += 1
									end,
								} :: FixtureCollectionTypes.RowAction,
							},
						})
					end, target)
					node.AbsoluteSize = V2.new(300, 44)
					local grip = node:FindFirstChild("SwipeGrip", true)
					grip.TouchPan:Fire({ V2.new(280, 20) }, V2.new(-20, 0), V2.zero, E.UserInputState.Begin)
					grip.TouchPan:Fire({ V2.new(220, 20) }, V2.new(-80, 0), V2.zero, E.UserInputState.Change)
					grip.TouchPan:Fire(
						{},
						V2.new(sample.distance, 0),
						V2.new(sample.speed, 0),
						if sample.cancel then E.UserInputState.Cancel else E.UserInputState.End
					)
					Verify.expect(invoked):toBe(sample.expected)
					Verify.expect((open:peek())):toBe(if sample.expected == 1 or sample.cancel then nil else "trailing")
					grip.TouchPan:Fire({}, V2.new(sample.distance, 0), V2.new(sample.speed, 0), E.UserInputState.End)
					Verify.expect(invoked):toBe(sample.expected)
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case(
			"a horizontal touch pan holds Facet's enclosing scrollers until release; a vertical one leaves them",
			{
				id = "native_collections::Compose native collections::a horizontal touch pan holds Facet's enclosing scrollers until release; a vertical one leaves them",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local E = engine.types.Enum
					local V2 = engine.types.Vector2
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
					local open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
						Compose.cell(nil :: ("leading" | "trailing")?)
					local stop, page: any = runtime.mount(function()
						return ctx.Host.ScrollingFrame "Page" {
							ctx.Host.ScrollingFrame "Body" {
								UI.RowActions({
									Name = "Row",
									open = open,
									content = UI.Button "Mail" { label = "Mail" } :: GuiObject,
									trailing = {
										{ id = "Delete", label = "Delete", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
									},
								}),
							},
						}
					end, target)
					local scrollLock = require("../src/ui/scroll_lock")
					local body = page:FindFirstChild("Body")
					scrollLock.own(body)
					local row = body:FindFirstChild("Row")
					row.AbsoluteSize = V2.new(300, 40)
					local grip = row:FindFirstChild("SwipeGrip", true)
					local function pan(to: any, from: any, state: any)
						grip.TouchPan:Fire({ to }, to - from, V2.zero, state)
					end
					local function held(): string
						return `{page.ScrollingEnabled} {body.ScrollingEnabled}`
					end
					pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.Begin)
					Verify.expect((held())):toBe("true false")
					pan(V2.new(120, 24), V2.new(200, 20), E.UserInputState.Change)
					pan(V2.new(120, 24), V2.new(200, 20), E.UserInputState.End)
					Verify.expect((held())):toBe("true true")
					Verify.expect((open:peek())):toBe("trailing")
					local sheet = engine.new("Frame")
					sheet.Parent = target
					pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.Begin)
					scrollLock.acquire(target, sheet)
					pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.End)
					Verify.expect((held())):toBe("false false")
					scrollLock.release(target, sheet)
					Verify.expect((held())):toBe("true true")
					open:set(nil)
					engine.heartbeat:Fire(1 / 60)
					pan(V2.new(202, 6), V2.new(200, 20), E.UserInputState.Begin)
					pan(V2.new(204, -60), V2.new(200, 20), E.UserInputState.Change)
					Verify.expect((held())):toBe("true true")
					pan(V2.new(204, -60), V2.new(200, 20), E.UserInputState.End)
					Verify.expect((open:peek())):toBeNil()
					pan(V2.new(186, 20), V2.new(200, 20), E.UserInputState.Begin)
					pan(V2.new(186, 20), V2.new(200, 20), E.UserInputState.Cancel)
					Verify.expect((held())):toBe("true true")
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("selects ranges across unmounted rows while honoring row capability policies", {
			id = "native_collections::Compose native collections::selects ranges across unmounted rows while honoring row capability policies",
			run = function()
				local shifted = false
				local engine, runtime, UI, target = setup({
					userInputService = {
						IsKeyDown = function()
							return shifted
						end,
						GetFocusedTextBox = function()
							return nil
						end,
					},
				})
				local selected = Compose.cell({})
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(100),
						key = key,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						itemSize = 20,
						overscan = 0,
						selectable = function(item)
							return item.id ~= 4
						end,
						disabled = function(item)
							return item.id == 5
						end,
						columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 60)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				body:FindFirstChild("2", true):FindFirstChild("RowHit", true).Activated:Fire()
				shifted = true
				body.CanvasPosition = engine.types.Vector2.new(0, 180)
				body:FindFirstChild("10", true):FindFirstChild("RowHit", true).Activated:Fire()
				for index = 2, 10 do
					Verify.expect(selected:peek()[index] == true):toBe(index ~= 4 and index ~= 5)
				end
				Verify.expect(selected:peek()[1]):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("reorders selected blocks with native drag and cancels stale or keyboard moves", {
			id = "native_collections::Compose native collections::reorders selected blocks with native drag and cancels stale or keyboard moves",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, selected = Compose.cell(records(5)), Compose.cell({ [1] = true, [3] = true })
				local requests = {}
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = source,
						key = key,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						itemSize = 20,
						reorderable = true,
						movable = function(item)
							return item.id ~= 4
						end,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local handle = body:FindFirstChild("3", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(10, 40))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 35))
				Verify.expect(node:FindFirstChild("DropLine", true).Position.Y.Offset):toBe(100)
				Verify.expect(node:FindFirstChild("DragLabel", true).Text):toBe("2 selected")
				detector.DragEnd:Fire()
				Verify.expect(requests):toEqual({ { keys = { 1, 3 }, slot = 1 } })
				Verify.expect(body:FindFirstChild("4", true):FindFirstChild("Move", true).Interactable):toBe(false)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 40))
				source:set(records(5))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 100))
				detector.DragEnd:Fire()
				Verify.expect(#requests):toBe(1)
				handle.SelectionGained:Fire()
				handle.Activated:Fire()
				Verify.expect(handle:FindFirstChild("ReorderIcon").Image):toBe("rbxassetid://108245103349446")
				local cancel
				for _, contextNode in target:GetChildren() do
					if contextNode.Name == "FacetReorderCancel" and contextNode.Enabled then
						cancel = contextNode:FindFirstChild("ReorderCancel")
					end
				end
				assert(cancel)
				cancel.Pressed:Fire()
				Verify.expect(handle.Text):toBe("")
				Verify.expect(handle:FindFirstChild("ReorderIcon").Image):toBe("rbxassetid://119066409501208")
				Verify.expect(handle:FindFirstChild("ReorderIcon").Position)
					:toBe(engine.types.UDim2.fromScale(0.5, 0.5))
				Verify.expect(#requests):toBe(1)
				handle.Activated:Fire()
				for _, contextNode in target:GetChildren() do
					if contextNode.Name == "FacetReorderDown" and contextNode.Enabled then
						contextNode:FindFirstChild("ReorderDown").Pressed:Fire()
					end
				end
				handle.Activated:Fire()
				Verify.expect(requests[2]):toEqual({ keys = { 1, 3 }, slot = 1 })
				Verify.expect((node:FindFirstChild("DropLine", true))):toBeNil()
				local stationary = body:FindFirstChild("2", true):FindFirstChild("Move", true)
				stationary.Activated:Fire()
				stationary.Activated:Fire()
				Verify.expect(#requests):toBe(2)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps touch handle drags active with a focused handle and moves a non-adjacent selection", {
			id = "native_collections::Compose native collections::keeps touch handle drags active with a focused handle and moves a non-adjacent selection",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
				local selected, requests = Compose.cell({ [1] = true, [3] = true }), {}
				local stop, node: any = runtime.mount(function()
					return UI.Table {
						from = records(5),
						key = key,
						itemSize = 20,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						editing = true,
						reorderable = true,
						onReorder = function(keys, slot)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = { { id = "label", width = 100 } },
					}
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = V2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				body.ScrollingEnabled = true
				local handle = body:FindFirstChild("3", true):FindFirstChild("Move", true)
				gui.SelectedObject = handle
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				Verify.expect(detector.Enabled):toBe(true)
				local input = {
					UserInputType = E.UserInputType.Touch,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(10, 40, 0),
				}
				detector.DragStart:Fire(V2.new(10, 40))
				handle.InputBegan:Fire(input)
				Verify.expect(body.ScrollingEnabled):toBe(false)
				detector.DragContinue:Fire(V2.new(10, 35))
				detector.DragEnd:Fire()
				Verify.expect(requests):toEqual({ { keys = { 1, 3 }, slot = 1 } })
				Verify.expect(body.ScrollingEnabled):toBe(true)
				Verify.expect((selected:peek())):toEqual({ [1] = true, [3] = true })
				stop()
			end,
		})

		verifyHarness:case("arms a move on a detector tap and commits it on the next tap", {
			id = "native_collections::Compose native collections::arms a move on a detector tap and commits it on the next tap",
			run = function()
				local engine, runtime, UI, target = setup()
				local source = Compose.cell(records(5))
				local requests = {}
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = source,
						key = key,
						itemSize = 20,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local handle = body:FindFirstChild("2", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				local reorderable = handle.Parent
				detector.DragStart:Fire(engine.types.Vector2.new(10, 30))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 31))
				detector.DragEnd:Fire()
				handle.Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 })
				Verify.expect((reorderable:GetAttribute("FacetDragging"))):toBe(true)
				Verify.expect(#requests):toBe(0)
				for _, contextNode in target:GetChildren() do
					if contextNode.Name == "FacetReorderDown" and contextNode.Enabled then
						contextNode:FindFirstChild("ReorderDown").Pressed:Fire()
					end
				end
				detector.DragStart:Fire(engine.types.Vector2.new(10, 30))
				detector.DragEnd:Fire()
				handle.Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 })
				Verify.expect((reorderable:GetAttribute("FacetDragging"))):toBe(false)
				Verify.expect(requests):toEqual({ { keys = { 2 }, slot = 2 } })
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("commits a destructive action once after Compose departure and cancels on disposal", {
			id = "native_collections::Compose native collections::commits a destructive action once after Compose departure and cancels on disposal",
			run = function()
				local engine, runtime, UI, target = setup({ motionLevel = "normal" })
				local invoked = 0
				local function mount()
					return runtime.mount(function()
						return UI.RowActions({
							open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Cell<FixtureCollectionTypes.RowEdge?>,
							content = UI.Button "Action" { label = "Row" } :: GuiObject,
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
					end, target)
				end
				local stop, node: any = mount()
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				engine.heartbeat:Fire(0.3)
				local action = node:FindFirstChild("Delete", true)
				action.Activated:Fire()
				action.Activated:Fire()
				Verify.expect(invoked):toBe(0)
				engine.heartbeat:Fire(0.3)
				Verify.expect(invoked):toBe(1)
				Verify.expect(node.Size.Y.Offset):toBe(0)
				action.Activated:Fire()
				Verify.expect(invoked):toBe(1)
				stop()
				local cancel, pending: any = mount()
				pending.AbsoluteSize = engine.types.Vector2.new(300, 40)
				engine.heartbeat:Fire(0.3)
				pending:FindFirstChild("Delete", true).Activated:Fire()
				cancel()
				engine.heartbeat:Fire(1)
				Verify.expect(invoked):toBe(1)
				runtime:dispose()
			end,
		})

		verifyHarness:case("never commits or opens a full swipe on an unmeasured row", {
			id = "native_collections::Compose native collections::never commits or opens a full swipe on an unmeasured row",
			run = function()
				local engine, runtime, UI, target = setup()
				local invoked, open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
					0, Compose.cell(nil :: ("leading" | "trailing")?)
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						open = open,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						trailing = {
							{
								id = "Archive",
								label = "Archive",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(100, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(85, 0))
				detector.DragEnd:Fire()
				Verify.expect(invoked):toBe(0)
				Verify.expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("restores a kept row after a destructive action so it can commit again", {
			id = "native_collections::Compose native collections::restores a kept row after a destructive action so it can commit again",
			run = function()
				local engine, runtime, UI, target = setup()
				local invoked, open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
					0, Compose.cell("trailing" :: ("leading" | "trailing")?)
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						open = open,
						reducedMotion = true,
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
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
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				node:FindFirstChild("Delete", true).Activated:Fire()
				Verify.expect(invoked):toBe(1)
				Verify.expect(node.Size.Y.Offset):toBe(0)
				Verify.expect(detector.Enabled):toBe(false)
				open:set("trailing")
				Verify.expect(node.Size.Y.Offset):toBe(44)
				Verify.expect(detector.Enabled):toBe(true)
				Verify.expect(node:FindFirstChild("trailing").Visible):toBe(true)
				node:FindFirstChild("Delete", true).Activated:Fire()
				Verify.expect(invoked):toBe(2)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("respects edge full-swipe policy, edit affordances and focused destructive input", {
			id = "native_collections::Compose native collections::respects edge full-swipe policy, edit affordances and focused destructive input",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local editing, open: FixtureComposeTypes.Cell<("leading" | "trailing")?> =
					Compose.cell(false), Compose.cell(nil :: ("leading" | "trailing")?)
				local invoked = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						editing = editing,
						open = open,
						fullSwipe = { trailing = false },
						trailing = {
							{
								id = "Erase",
								label = "Delete",
								role = "destructive" :: "destructive",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(280, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(0, 0))
				detector.DragEnd:Fire()
				Verify.expect(invoked):toBe(0)
				Verify.expect((open:peek())):toBe("trailing")
				open:set(nil)
				Verify.expect((node:FindFirstChild("Delete"))):toBeNil()
				editing:set(true)
				Verify.expect(node:FindFirstChild("Delete") ~= nil):toBe(true)
				gui.SelectedObject = node:FindFirstChild("Action", true)
				local contextNode = target:FindFirstChild("FacetRowActionsDelete")
				Verify.expect(contextNode.Enabled):toBe(true)
				contextNode:FindFirstChild("RowActionsDelete").Pressed:Fire()
				Verify.expect(invoked):toBe(1)
				node:FindFirstChild("Delete").Activated:Fire()
				Verify.expect(invoked):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("uses the shared native menu for all actions and restores focus after cancellation", {
			id = "native_collections::Compose native collections::uses the shared native menu for all actions and restores focus after cancellation",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local invoked = 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						leading = {
							{
								id = "Read",
								label = "Read",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
						trailing = {
							{
								id = "Save",
								label = "Save",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				local original = node:FindFirstChild("Action", true)
				gui.SelectedObject = original
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton2,
					Position = engine.types.Vector3.new(50, 50, 0),
				})
				local panel = target:FindFirstChild("MenuPanel", true)
				Verify.expect(panel ~= nil):toBe(true)
				Verify.expect(panel.SelectionBehaviorDown):toBe(engine.types.Enum.SelectionBehavior.Stop)
				Verify.expect(target:FindFirstChild("leading:Read", true) ~= nil):toBe(true)
				Verify.expect(target:FindFirstChild("trailing:Save", true) ~= nil):toBe(true)
				target:FindFirstChild("FacetModalBack"):FindFirstChild("ModalBack").Pressed:Fire()
				Verify.expect((target:FindFirstChild("MenuPanel", true))):toBeNil()
				Verify.expect(gui.SelectedObject):toBe(original)
				Verify.expect(invoked):toBe(0)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton2,
					Position = engine.types.Vector3.new(70, 80, 0),
				})
				target:FindFirstChild("leading:Read", true).Activated:Fire()
				Verify.expect(invoked):toBe(1)
				Verify.expect((target:FindFirstChild("MenuPanel", true))):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("lets domain callbacks reject table selection, sorting and resize requests", {
			id = "native_collections::Compose native collections::lets domain callbacks reject table selection, sorting and resize requests",
			run = function()
				local engine, runtime, UI, target = setup()
				local selection, sort, widths = Compose.cell({}), Compose.cell(nil :: {}?), Compose.cell({})
				local requests = 0
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(5),
						key = key,
						selection = selection,
						sort = sort,
						widths = widths,
						onSelectionChange = function()
							requests += 1
						end,
						onSortChange = function()
							requests += 1
						end,
						onWidthsChange = function()
							requests += 1
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				body:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated:Fire()
				node:FindFirstChild("Sort", true).Activated:Fire()
				local resize = node:FindFirstChild("Resize", true):FindFirstChildWhichIsA("UIDragDetector")
				resize.DragStart:Fire(engine.types.Vector2.new(10, 10))
				resize.DragContinue:Fire(engine.types.Vector2.new(50, 10))
				Verify.expect(requests):toBe(3)
				Verify.expect((selection:peek())):toEqual({})
				Verify.expect((sort:peek())):toBeNil()
				Verify.expect((widths:peek())):toEqual({})
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"keeps block tables fully mounted and discloses collapsed columns without losing cell state",
			{
				id = "native_collections::Compose native collections::keeps block tables fully mounted and discloses collapsed columns without losing cell state",
				run = function()
					local engine, runtime, UI, target = setup()
					local builds = 0
					local stop, node: any = runtime.mount(function()
						return UI.Table({
							from = { { id = 1, first = "One", second = "Two", third = "Full hidden value" } },
							key = key,
							scrolls = false,
							itemSize = 40,
							columns = {
								{ id = "first", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								{ id = "second", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
								{
									id = "third",
									label = "Third",
									width = 100,
									priority = 3,
									render = function(): GuiObject
										builds += 1
										return ((runtime.constructors.TextBox :: unknown) :: TextBoxConstructor)({
											Text = "Local edit",
										})
									end,
								} :: FixtureCollectionTypes.TableColumn<any, any>,
							},
						})
					end, target)
					local body = node:FindFirstChild("Body")
					Verify.expect(body.ScrollingEnabled):toBe(false)
					Verify.expect(node.Size.Y.Offset):toBe(80)
					local row = body:FindFirstChild("1", true)
					local cell = row:FindFirstChild("third", true)
					body.AbsoluteWindowSize = engine.types.Vector2.new(250, 40)
					body.Parent.AbsoluteSize = body.AbsoluteWindowSize
					Verify.expect(cell.Visible):toBe(false)
					local menu = row:FindFirstChild("Details", true)
					menu.Activated:Fire()
					local fullValue = target:FindFirstChild("Popup", true):FindFirstChild("third", true)
					Verify.expect(fullValue ~= nil):toBe(true)
					body.AbsoluteWindowSize = engine.types.Vector2.new(400, 40)
					body.Parent.AbsoluteSize = body.AbsoluteWindowSize
					Verify.expect((row:FindFirstChild("third", true))):toBe(cell)
					Verify.expect(cell.Visible):toBe(true)
					Verify.expect(builds):toBe(1)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("uses new grid neighbors when responsive columns change without changing total extent", {
			id = "native_collections::Compose native collections::uses new grid neighbors when responsive columns change without changing total extent",
			run = function()
				local engine, runtime, UI, target = setup()
				local columns, focus: FixtureCollectionTypes.FocusControls<any> = Compose.cell(4), {}
				local stop, node: any = runtime.mount(function()
					return UI.VirtualGrid({
						from = records(12),
						key = key,
						itemSize = 20,
						columns = columns,
						focus = focus,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				assert(focus.focus)(2)
				columns:set(5)
				assert(focus.move)("down")
				Verify.expect((assert(focus.current):peek())):toBe(7)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("drops removed measurements and refreshes current-item row actions under stable keys", {
			id = "native_collections::Compose native collections::drops removed measurements and refreshes current-item row actions under stable keys",
			run = function()
				local engine, runtime, UI, target = setup()
				local source, status =
					Compose.cell(records(2)), Compose.cell({
						mode = "windowed" :: "windowed",
						direction = "vertical" :: "vertical",
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
				local invoked = ""
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						itemSize = 20,
						status = status,
						measure = true,
						render = function(current): GuiObject
							return UI.RowActions({
								open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Cell<FixtureCollectionTypes.RowEdge?>,
								content = button(UI, current),
								trailing = function(use: Use): { FixtureCollectionTypes.RowAction }
									local item = use(current)
									return {
										{
											id = "Save",
											label = item.label,
											onActivate = function()
												invoked = item.label
											end,
										},
									}
								end,
							})
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local row = node:FindFirstChild("1", true):FindFirstChild("Content"):GetChildren()[1]
				row.AbsoluteSize = engine.types.Vector2.new(200, 60)
				Verify.expect(status:peek().extent):toBe(80)
				local action = row:FindFirstChild("Save", true)
				source:set({ { id = 1, label = "Latest" }, { id = 2, label = "Second" } })
				Verify.expect((row:FindFirstChild("Save", true))):toBe(action)
				Verify.expect(action.Text):toBe("Latest")
				action.Activated:Fire()
				Verify.expect(invoked):toBe("Latest")
				source:set({ { id = 2, label = "Second" } })
				source:set(records(2))
				Verify.expect(status:peek().extent):toBe(40)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("locks vertical gestures, opens short velocity flicks and cancels disabled drags", {
			id = "native_collections::Compose native collections::locks vertical gestures, opens short velocity flicks and cancels disabled drags",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
				})
				local enabled, open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, invoked =
					Compose.cell(true), Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						open = open,
						enabled = enabled,
						trailing = {
							{
								id = "Save",
								icon = "rbxassetid://1",
								label = "Save",
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(engine.types.Vector2.new(200, 0))
				now = 0.1
				detector.DragContinue:Fire(engine.types.Vector2.new(195, 60))
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBeNil()
				detector.DragStart:Fire(engine.types.Vector2.new(200, 0))
				now = 0.11
				detector.DragContinue:Fire(engine.types.Vector2.new(188, 0))
				Verify.expect(node:FindFirstChild("trailing").Size.X.Offset):toBe(12)
				Verify.expect(node:FindFirstChild("LeadingIcon", true).Image):toBe("rbxassetid://1")
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBe("trailing")
				open:set(nil)
				detector.DragStart:Fire(engine.types.Vector2.new(200, 0))
				now = 0.3
				detector.DragContinue:Fire(engine.types.Vector2.new(-100, 0))
				enabled:set(false)
				detector.DragEnd:Fire()
				Verify.expect((open:peek())):toBeNil()
				Verify.expect(invoked):toBe(0)
				Verify.expect(detector.Enabled):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("adapts table row and header height from native text bounds and preferred input", {
			id = "native_collections::Compose native collections::adapts table row and header height from native text bounds and preferred input",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({
					userInputService = {},
					theme = { metrics = { controlSizes = { regular = { height = 32 } } } },
				})
				local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(2),
						key = key,
						controls = controls,
						columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local row = body:FindFirstChild("1", true)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(40)
				row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 60)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(76)
				node:FindFirstChild("Sort", true).TextBounds = engine.types.Vector2.new(100, 70)
				Verify.expect(body.Position.Y.Offset):toBe(86)

				node:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.new(2, 2)
				Verify.expect(body.Position.Y.Offset):toBe(51)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(46)
				local header = node:FindFirstChild("Header")
				header:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = engine.types.Vector2.new(800, 102)
				Verify.expect(body.CanvasSize.X.Offset):toBe(400)
				body.CanvasPosition = engine.types.Vector2.new(80, 0)
				Verify.expect(header.Position.X.Offset):toBe(-40)
				body.CanvasPosition = engine.types.Vector2.zero
				node:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.one

				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
				row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 8)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(56)
				row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 60)
				Verify.expect(assert(controls.placementOf)(2).offset):toBe(76)
				Verify.expect((body:FindFirstChild("1", true))):toBe(row)
				node:FindFirstChild("Sort", true).TextBounds = engine.types.Vector2.new(100, 20)
				Verify.expect(body.Position.Y.Offset):toBe(44)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("measures localized row action labels and reveals truncated visible table values", {
			id = "native_collections::Compose native collections::measures localized row action labels and reveals truncated visible table values",
			run = function()
				local engine, runtime, UI, target = setup()
				local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, editing =
					Compose.cell("trailing" :: ("leading" | "trailing")?), Compose.cell(true)
				local stopActions, actions: any = runtime.mount(function()
					return UI.RowActions({
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						open = open,
						editing = editing,
						trailing = {
							{
								id = "Remove",
								label = "Localized destructive action",
								role = "destructive" :: "destructive",
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				actions.AbsoluteSize = engine.types.Vector2.new(500, 40)
				actions:FindFirstChild("Remove", true).TextBounds = engine.types.Vector2.new(210, 20)
				Verify.expect(actions:FindFirstChild("trailing").Size.X.Offset):toBe(242)
				actions:FindFirstChild("Delete", true).TextBounds = engine.types.Vector2.new(190, 20)
				Verify.expect(actions:FindFirstChild("Content").Position.X.Offset):toBe(-20)
				actions:FindFirstChild("Remove", true).TextBounds = engine.types.Vector2.new(30, 20)
				Verify.expect(actions:FindFirstChild("trailing").Size.X.Offset):toBe(88)
				stopActions()
				local source = Compose.cell({ { id = 1, label = "Long value that should be disclosed" } })
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = source,
						key = key,
						columns = {
							{ id = "label", label = "Label", width = 180 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(250, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local row = body:FindFirstChild("1", true)
				Verify.expect((row:FindFirstChild("Details", true))):toBeNil()
				row:FindFirstChild("Undisclosed", true).TextFits = false
				row:FindFirstChild("Details", true).Activated:Fire()
				local expanded = target:FindFirstChild("Popup", true)
				Verify.expect(expanded:FindFirstChild("FullValue", true).Text)
					:toBe("Long value that should be disclosed")
				source:set({ { id = 1, label = "Updated entire value" } })
				Verify.expect(expanded:FindFirstChild("FullValue", true).Text):toBe("Updated entire value")
				row:FindFirstChild("Undisclosed", true).TextFits = true
				Verify.expect((target:FindFirstChild("Popup", true))):toBeNil()
				Verify.expect((body:FindFirstChild("1", true))):toBe(row)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("keeps native reorder capture and keyboard drop alive across offscreen autoscroll", {
			id = "native_collections::Compose native collections::keeps native reorder capture and keyboard drop alive across offscreen autoscroll",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local requests = {}
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(100),
						key = key,
						itemSize = 20,
						overscan = 0,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						columns = {
							{ id = "label", label = "Label", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				local input = {
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					Position = engine.types.Vector3.new(10, 10, 0),
				}
				handle.InputBegan:Fire(input)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 99))
				for _ = 1, 40 do
					engine.heartbeat:Fire(1 / 60)
				end
				Verify.expect(body.CanvasPosition.Y > 200):toBe(true)
				Verify.expect((body:FindFirstChild("1", true))):toBeNil()
				local injectedInputChanged = assert(ctx.config.userInputService).InputChanged :: any
				injectedInputChanged:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseMovement,
					Position = engine.types.Vector3.new(10, 80, 0),
				})
				local injectedInputEnded = assert(ctx.config.userInputService).InputEnded :: any
				injectedInputEnded:Fire(input)
				Verify.expect(#requests):toBe(1)
				Verify.expect(requests[1].keys):toEqual({ 1 })
				Verify.expect(requests[1].slot > 10):toBe(true)
				body.CanvasPosition = engine.types.Vector2.zero
				handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				handle.Activated:Fire()
				Verify.expect(gui.SelectedObject.Name):toBe("Drop")
				for _, part in node:FindFirstChild("DragImage", true):GetDescendants() do
					if part:IsA("GuiObject") or part:IsA("Path2D") then
						Verify.expect(gui.SelectedObject.ZIndex > part.ZIndex):toBe(true)
					end
				end
				local action = target:FindFirstChild("FacetReorderDown"):FindFirstChild("ReorderDown")
				for _ = 1, 25 do
					action.Pressed:Fire()
				end
				Verify.expect((body:FindFirstChild("1", true))):toBeNil()
				Verify.expect(gui.SelectedObject.Name):toBe("Drop")
				target:FindFirstChild("FacetReorderDrop"):FindFirstChild("ReorderDrop").Pressed:Fire()
				Verify.expect(requests[2]):toEqual({ keys = { 1 }, slot = 25 })
				Verify.expect(body.CanvasPosition.Y):toBe(0)
				handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				Verify.expect(gui.SelectedObject):toBe(handle)
				handle.Activated:Fire()
				for _ = 1, 25 do
					action.Pressed:Fire()
				end
				target:FindFirstChild("FacetReorderCancel"):FindFirstChild("ReorderCancel").Pressed:Fire()
				Verify.expect(body.CanvasPosition.Y):toBe(0)
				handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
				Verify.expect(gui.SelectedObject):toBe(handle)
				detector = handle:FindFirstChildWhichIsA("UIDragDetector")
				handle.InputBegan:Fire(input)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				ctx.config.userInputService.MouseEnabled = false
				Verify.expect((node:FindFirstChild("DropLine", true))):toBeNil()
				local injectedInputEnded = assert(ctx.config.userInputService).InputEnded :: any
				injectedInputEnded:Fire(input)
				Verify.expect(#requests):toBe(2)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("shares list selection and reorder policies and fails closed for protected rows", {
			id = "native_collections::Compose native collections::shares list selection and reorder policies and fails closed for protected rows",
			run = function()
				local engine, runtime, UI, target = setup()
				local selected, requests = Compose.cell({}), {}
				local source = Compose.cell(records(4))
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						selectable = function(item)
							if item.id == 2 then
								error("rejected")
							end
							return true
						end,
						movable = function(item)
							if item.id == 2 then
								error("rejected")
							end
							return true
						end,
						reorderable = true,
						onReorder = function(keys: { number }, slot: number)
							table.insert(requests, { keys = keys, slot = slot })
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				node:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated:Fire()
				node:FindFirstChild("2", true):FindFirstChild("RowHit", true).Activated:Fire()
				Verify.expect((selected:peek())):toEqual({ [1] = true })
				Verify.expect(
					(node:FindFirstChild("1", true):FindFirstChild("RowHit", true):GetAttribute("FacetSelected"))
				)
					:toBe(true)
				Verify.expect(node:FindFirstChild("2", true):FindFirstChild("Move", true).Interactable):toBe(false)
				local detector = node:FindFirstChild("1", true):FindFirstChildWhichIsA("UIDragDetector", true)
				detector.DragStart:Fire(engine.types.Vector2.new(10, 10))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 90))
				detector.DragEnd:Fire()
				Verify.expect(#requests):toBe(0)
				local remaining = records(4)
				table.remove(remaining, 1)
				source:set(remaining)
				Verify.expect((selected:peek())):toEqual({})
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("snaps native scrolling to Compose measured boundaries and yields animation to input", {
			id = "native_collections::Compose native collections::snaps native scrolling to Compose measured boundaries and yields animation to input",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
					motionLevel = "normal",
				})
				local function advance(seconds: number)
					for _ = 1, math.ceil(seconds * 60) do
						now += 1 / 60
						engine.heartbeat:Fire(1 / 60)
					end
				end
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(20),
						key = key,
						itemSize = 40,
						snap = "item" :: "item",
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				now = 1
				node.CanvasPosition = engine.types.Vector2.new(0, 26)
				advance(0.14)
				Verify.expect(node.CanvasPosition.Y >= 26 and node.CanvasPosition.Y < 40):toBe(true)
				local input = { UserInputType = engine.types.Enum.UserInputType.MouseButton1 }
				node.InputBegan:Fire(input)
				local interrupted = node.CanvasPosition.Y
				advance(0.5)
				Verify.expect(node.CanvasPosition.Y):toBe(interrupted)
				node.InputEnded:Fire(input)
				advance(0.4)
				Verify.expect(node.CanvasPosition.Y):toBe(40)
				stop()
				local stopMeasured, measured: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(20),
						key = key,
						itemSize = 20,
						measured = { [1] = 35 },
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				measured.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				now += 1
				measured.CanvasPosition = engine.types.Vector2.new(0, 23)
				advance(0.2)
				Verify.expect(measured.CanvasPosition.Y):toBe(35)
				stopMeasured()
				local stopGrid, grid: any = runtime.mount(function()
					return UI.VirtualGrid({
						from = records(20),
						key = key,
						itemSize = 40,
						columns = 2,
						direction = "horizontal" :: "horizontal",
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				grid.AbsoluteWindowSize = engine.types.Vector2.new(100, 200)
				grid.InputBegan:Fire(input)
				now += 0.01
				grid.CanvasPosition = engine.types.Vector2.new(5, 0)
				grid.InputEnded:Fire(input)
				advance(0.15)
				Verify.expect(grid.CanvasPosition.X):toBe(40)
				stopGrid()
				local stopLarge, large: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(5),
						key = key,
						itemSize = 120,
						snap = "item" :: "item",
						reducedMotion = true,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				large.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				now += 1
				large.CanvasPosition = engine.types.Vector2.new(0, 23)
				advance(0.2)
				Verify.expect(large.CanvasPosition.Y):toBe(23)
				stopLarge()
				runtime:dispose()
			end,
		})
		verifyHarness:case(
			"a list that opts into motion still lands its snap when the device asks for reduced motion",
			{
				id = "native_collections::Compose native collections::a list that opts into motion still lands its snap when the device asks for reduced motion",
				run = function()
					local now = 0
					local engine, runtime, UI, target = setup({
						clock = function()
							return now
						end,
						motionLevel = "none",
					})
					local stop, node: any = runtime.mount(function()
						return UI.VirtualList({
							from = records(20),
							key = key,
							itemSize = 40,
							snap = "item" :: "item",
							reducedMotion = false,
							render = function(current): GuiObject
								return button(UI, current)
							end,
						})
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
					now = 1
					node.CanvasPosition = engine.types.Vector2.new(0, 26)
					for _ = 1, 60 do
						now += 1 / 60
						engine.heartbeat:Fire(1 / 60)
					end
					Verify.expect(node.CanvasPosition.Y):toBe(40)
					stop()
					runtime:dispose()
				end,
			}
		)
		verifyHarness:case("a snap starts gently from rest and lands flush", {
			id = "native_collections::Compose native collections::a snap starts gently from rest and lands flush",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					clock = function()
						return now
					end,
					motionLevel = "normal",
				})
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = records(20),
						key = key,
						itemSize = 40,
						snap = "item" :: "item",
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				now = 1
				node.CanvasPosition = engine.types.Vector2.new(0, 26)
				local offsets = {}
				for _ = 1, 40 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
					table.insert(offsets, node.CanvasPosition.Y)
				end
				local moves = {}
				for index = 2, #offsets do
					if offsets[index] ~= offsets[index - 1] then
						table.insert(moves, offsets[index] - offsets[index - 1])
					end
				end
				Verify.expect(#moves >= 4):toBe(true)
				Verify.expect(moves[1] < moves[4]):toBe(true)
				Verify.expect(offsets[#offsets]):toBe(40)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("cancels native row gestures and keeps destructive opt-outs behind every action route", {
			id = "native_collections::Compose native collections::cancels native row gestures and keeps destructive opt-outs behind every action route",
			run = function()
				local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
				local enabled, open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, invoked =
					Compose.cell(false), Compose.cell(nil :: ("leading" | "trailing")?), 0
				local stop, node: any = runtime.mount(function()
					return UI.RowActions({
						content = UI.Button "Action" { label = "Protected" } :: GuiObject,
						open = open,
						editing = Compose.cell(true),
						trailing = {
							{
								id = "Remove",
								label = "Remove",
								role = "destructive" :: "destructive",
								enabled = enabled,
								onActivate = function()
									invoked += 1
								end,
							} :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				node.AbsoluteSize = engine.types.Vector2.new(300, 40)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				local pointer = {
					UserInputType = engine.types.Enum.UserInputType.Touch,
					UserInputState = engine.types.Enum.UserInputState.Begin,
				}
				node.InputBegan:Fire(pointer)
				detector.DragStart:Fire(engine.types.Vector2.new(280, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 0))
				detector.DragEnd:Fire()
				Verify.expect(invoked):toBe(0)
				open:set("trailing")
				node:FindFirstChild("Remove", true).Activated:Fire()
				Verify.expect(invoked):toBe(0)
				Verify.expect((node:FindFirstChild("Delete", true))):toBeNil()
				gui.SelectedObject = node:FindFirstChild("Action", true)
				open:set(nil)
				Verify.expect(target:FindFirstChild("FacetRowActionsDelete").Enabled):toBe(false)
				node.InputBegan:Fire({
					UserInputType = engine.types.Enum.UserInputType.MouseButton2,
					Position = engine.types.Vector3.new(50, 50, 0),
				})
				local menuButton = target:FindFirstChild("trailing:Remove", true)
				Verify.expect(menuButton.Interactable):toBe(false)
				menuButton.Activated:Fire()
				Verify.expect(invoked):toBe(0)
				target:FindFirstChild("FacetModalBack"):FindFirstChild("ModalBack").Pressed:Fire()
				enabled:set(true)
				node.InputBegan:Fire(pointer)
				detector.DragStart:Fire(engine.types.Vector2.new(280, 0))
				detector.DragContinue:Fire(engine.types.Vector2.new(10, 0))
				pointer.UserInputState = engine.types.Enum.UserInputState.Cancel
				local injectedInputChanged = assert(ctx.config.userInputService).InputChanged :: any
				injectedInputChanged:Fire(pointer)
				detector.DragEnd:Fire()
				Verify.expect(invoked):toBe(0)
				Verify.expect((open:peek())):toBeNil()
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("enters native focus after unfocused collection churn and reaches offscreen keys", {
			id = "native_collections::Compose native collections::enters native focus after unfocused collection churn and reaches offscreen keys",
			run = function()
				local engine, runtime, UI, target, gui = setup()
				local source = Compose.cell(records(100))
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = source,
						key = key,
						itemSize = 20,
						overscan = 0,
						disabled = function(item)
							return item.id == 2
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local replaced = records(100)
				replaced[1] = { id = 101, label = "101" }
				source:set(replaced)
				local first = node:FindFirstChild("101", true):FindFirstChild("Action", true)
				gui.SelectedObject = first
				first.SelectionGained:Fire()
				target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed:Fire()
				Verify.expect(gui.SelectedObject.Text):toBe("3")
				target:FindFirstChild("FacetCollectionLast"):FindFirstChild("CollectionLast").Pressed:Fire()
				Verify.expect(gui.SelectedObject.Text):toBe("100")
				Verify.expect(node.CanvasPosition.Y):toBe(1900)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Table compact width", function()
		verifyHarness:case("keeps every column in a narrow table and paints the header band across its columns", {
			id = "native_collections::Table compact width::keeps every column in a narrow table and paints the header band across its columns",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = { { id = 1, name = "Neon Straightaway", artist = "Chrome Coyote", rating = 4 } },
						key = key,
						reorderable = true,
						onReorder = function() end,
						columns = {
							{ id = "name", label = "Name", minWidth = 90 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "artist", label = "Artist", minWidth = 72 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "rating", label = "Rating", width = 144, resizable = false } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(300, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local row = body:FindFirstChild("1", true)
				for _, id in { "name", "artist", "rating" } do
					Verify.expect(row:FindFirstChild(id, true).Visible):toBe(true)
					Verify.expect(node:FindFirstChild("Header"):FindFirstChild(id).Visible):toBe(true)
				end
				local band = node:FindFirstChild("HeaderBand")
				local gutter = node:FindFirstChild("Header").Position.X.Offset
				Verify.expect(band.Position.X.Offset):toBe(gutter)
				Verify.expect(band.Size)
					:toBe(engine.types.UDim2.new(1, 0, 0, node:FindFirstChild("Header").Size.Y.Offset))
				Verify.expect((band:HasTag("facet-tablehead"))):toBe(true)
				Verify.expect(node:FindFirstChild("Header").BackgroundTransparency):toBe(1)
				row:FindFirstChild("Undisclosed", true).TextFits = false
				local more = row:FindFirstChild("Details", true)
				Verify.expect(
					more:FindFirstChild("Title", true) == nil or not more:FindFirstChild("Title", true).Visible
				)
					:toBe(true)
				Verify.expect(more:FindFirstChild("LeadingIcon", true) ~= nil):toBe(true)
				Verify.expect((more:GetAttribute("label"))):toBe("More actions")
				Verify.expect((more:HasTag("facet-appearance-utility"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Table under a scaled ancestor", function()
		verifyHarness:case("sizes its header in layout units when a UIScale shrinks the rendered window", {
			id = "native_collections::Table under a scaled ancestor::sizes its header in layout units when a UIScale shrinks the rendered window",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = { { id = 1, name = "Neon" } },
						key = key,
						columns = {
							{ id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "rating", label = "Rating", width = 144 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				local unit = node:FindFirstChild("LayoutUnit")
				Verify.expect(unit ~= nil):toBe(true)
				unit.AbsoluteSize = engine.types.Vector2.new(0.8, 0.8)
				body.AbsoluteWindowSize = engine.types.Vector2.new(800, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				Verify.expect(node:FindFirstChild("Header").Size.X.Offset):toBe(1000)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Table row tap", function()
		verifyHarness:case("a tap on a swipeable reorderable row selects it with a band and never starts a move", {
			id = "native_collections::Table row tap::a tap on a swipeable reorderable row selects it with a band and never starts a move",
			run = function()
				local engine, runtime, UI, target = setup()
				local E = engine.types.Enum
				local selection = Compose.cell({})
				local rating = 0
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = { { id = 1, name = "Neon" }, { id = 2, name = "Drift" } },
						key = key,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function() end,
						columns = {
							{ id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any>,
							{
								id = "rating",
								label = "Rating",
								width = 100,
								render = function(): GuiObject
									return UI.Button "Star" {
										label = "*",
										onActivate = function()
											rating += 1
										end,
									}
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
						rowActions = function(): FixtureCollectionTypes.RowActionsOptions?
							return {
								trailing = {
									{ id = "remove", label = "Remove", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(400, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local function tap(rowKey: string, input: any?)
					local rowNode = body:FindFirstChild("Items"):FindFirstChild(rowKey)
					local grip = rowNode:FindFirstChild("SwipeGrip", true)
					if input then
						grip.InputBegan:Fire(input)
					end
					local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart:Fire(engine.types.Vector2.new(150, 20))
					detector.DragEnd:Fire()
					return rowNode
				end
				local mouse = { UserInputType = E.UserInputType.MouseButton1, UserInputState = E.UserInputState.Begin }
				local first = tap("1", mouse)
				Verify.expect((selection:peek())):toEqual({ [1] = true })
				Verify.expect(rating):toBe(0)
				Verify.expect((node:FindFirstChild("DropFeedback", true))):toBeNil()
				Verify.expect((first:FindFirstChild("Reorderable", true):HasTag("facet-selected"))):toBe(true)
				local second = tap("2", mouse)
				Verify.expect((selection:peek())):toEqual({ [2] = true })
				Verify.expect((first:FindFirstChild("Reorderable", true):HasTag("facet-selected"))):toBe(false)
				Verify.expect((second:FindFirstChild("Reorderable", true):HasTag("facet-selected"))):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Row actions under a reorder drag", function()
		verifyHarness:case("the drag image carries the row content without its open action tray", {
			id = "native_collections::Row actions under a reorder drag::the drag image carries the row content without its open action tray",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V3 = engine.types.Enum, engine.types.Vector3
				local opened = Compose.cell(nil :: ("leading" | "trailing")?)
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = { { id = 1, name = "Neon" }, { id = 2, name = "Drift" }, { id = 3, name = "Apex" } },
						key = key,
						itemSize = 40,
						reorderable = true,
						onReorder = function() end,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
						rowActions = function(_, rowKey): FixtureCollectionTypes.RowActionsOptions?
							return {
								open = if rowKey == 1 then opened else nil,
								trailing = {
									{ id = "remove", label = "Remove", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(400, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local rowNode = body:FindFirstChild("Items"):FindFirstChild("1")
				local grip = rowNode:FindFirstChild("SwipeGrip", true)
				local content = grip.Parent
				content.Parent.AbsoluteSize = engine.types.Vector2.new(400, 40)
				engine.heartbeat:Fire(1)
				opened:set("trailing")
				engine.heartbeat:Fire(1)
				Verify.expect(content.Parent:FindFirstChild("trailing").Visible):toBe(true)
				Verify.expect(content.Position.X.Offset < 0):toBe(true)
				local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(100, 20, 0) }
				local dismiss = content:FindFirstChild("DismissTray")
				Verify.expect(dismiss.Visible):toBe(true)
				nativeDrag.press(dismiss, press)
				Verify.expect((opened:peek())):toBeNil()
				local input: any = assert(ctx.config.userInputService)
				nativeDrag.move(input, { UserInputType = E.UserInputType.MouseMovement, Position = V3.new(100, 60, 0) })
				local image = node:FindFirstChild("DragImage", true)
				Verify.expect(image ~= nil):toBe(true)
				local ghost = image:FindFirstChild("SwipeGrip", true).Parent
				Verify.expect((ghost.Parent:FindFirstChild("trailing"))):toBeNil()
				Verify.expect(ghost.Position.X.Offset):toBe(0)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Table selection after a pointer reorder", function()
		verifyHarness:case("a plain click on another row after a drop selects only that row", {
			id = "native_collections::Table selection after a pointer reorder::a plain click on another row after a drop selects only that row",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
				local rows =
					Compose.cell({ { id = 1, name = "Neon" }, { id = 2, name = "Drift" }, { id = 3, name = "Apex" } })
				local selection = Compose.cell({})
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = rows,
						key = key,
						itemSize = 40,
						selection = selection,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function(keys, slot: number)
							local list = {}
							for _, item in rows:peek() do
								if item.id ~= keys[1] then
									table.insert(list, item)
								end
							end
							table.insert(list, slot + 1, { id = keys[1], name = "moved" })
							rows:set(list)
						end,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
						rowActions = function(): FixtureCollectionTypes.RowActionsOptions?
							return {
								trailing = {
									{ id = "remove", label = "Remove", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = V2.new(400, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local input: any = assert(ctx.config.userInputService)
				local function grip(rowKey)
					return body:FindFirstChild("Items"):FindFirstChild(rowKey):FindFirstChild("SwipeGrip", true)
				end
				local function click(rowKey, y)
					local press = {
						UserInputType = E.UserInputType.MouseButton1,
						UserInputState = E.UserInputState.Begin,
						Position = V3.new(100, y, 0),
					}
					local g = grip(rowKey)
					g.InputBegan:Fire(press)
					local detector = g:FindFirstChildWhichIsA("UIDragDetector")
					detector.DragStart:Fire(V2.new(100, y))
					detector.DragEnd:Fire()
					press.UserInputState = E.UserInputState.End
					input.InputEnded:Fire(press)
				end
				click("3", 100)
				Verify.expect((selection:peek())):toEqual({ [3] = true })
				local press = {
					UserInputType = E.UserInputType.MouseButton1,
					UserInputState = E.UserInputState.Begin,
					Position = V3.new(100, 100, 0),
				}
				local g = grip("3")
				g.InputBegan:Fire(press)
				local detector = g:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V2.new(100, 100))
				for y = 90, 10, -20 do
					input.InputChanged:Fire({
						UserInputType = E.UserInputType.MouseMovement,
						Position = V3.new(100, y, 0),
					})
					detector.DragContinue:Fire(V2.new(100, y))
				end
				press.UserInputState = E.UserInputState.End
				press.Position = V3.new(100, 10, 0)
				input.InputEnded:Fire(press)
				detector.DragEnd:Fire()
				engine.heartbeat:Fire(1)
				Verify.expect(rows:peek()[1].id):toBe(3)
				click("2", 100)
				Verify.expect((selection:peek())):toEqual({ [2] = true })
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Table keyed reorder motion", function()
		verifyHarness:case("a Table glides its rows to a reversed order like VirtualList", {
			id = "native_collections::Table keyed reorder motion::a Table glides its rows to a reversed order like VirtualList",
			run = function()
				local engine, runtime, UI, target = setup({ motionLevel = "normal" })
				local rows = Compose.cell({ { id = 1, name = "A" }, { id = 2, name = "B" }, { id = 3, name = "C" } })
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = rows,
						key = key,
						itemSize = 40,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(400, 300)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				engine.heartbeat:Fire(1 / 60)
				local first = body:FindFirstChild("Items"):FindFirstChild("1")
				local before = first.Position.Y.Offset
				rows:set({ rows:peek()[3], rows:peek()[2], rows:peek()[1] })
				engine.heartbeat:Fire(0.05)
				local during = first.Position.Y.Offset
				for _ = 1, 30 do
					engine.heartbeat:Fire(1 / 60)
				end
				local after = first.Position.Y.Offset
				Verify.expect(after > before):toBe(true)
				Verify.expect(during > before and during < after):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Row action tray width", function()
		verifyHarness:case("an icon action's tray fits its painted icon and keeps the label as its name", {
			id = "native_collections::Row action tray width::an icon action's tray fits its painted icon and keeps the label as its name",
			run = function()
				local engine, runtime, UI, target = setup()
				local stop, actions: any = runtime.mount(function()
					return UI.RowActions({
						content = UI.Button "Action" { label = "Row" } :: GuiObject,
						open = Compose.cell("trailing" :: "leading" | "trailing" | nil) :: FixtureComposeTypes.Cell<FixtureCollectionTypes.RowEdge?>,
						trailing = {
							{ id = "remove", label = "Remove", icon = "trash", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
						},
					})
				end, target)
				actions.AbsoluteSize = engine.types.Vector2.new(500, 40)
				local remove = actions:FindFirstChild("remove", true)
				Verify.expect((remove:GetAttribute("label"))):toBe("Remove")
				Verify.expect((remove:HasTag("facet-row-action"))):toBe(true)
				Verify.expect(actions:FindFirstChild("trailing").Size.X.Offset):toBe(math.max(64, 32 + 20 + 8))
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("editable collections: reorderable and deletable on every input", function()
		local function editableWorld(input: string, spec: { [string]: any }, list: boolean?)
			local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
			local service: any = assert(ctx.config.userInputService)
			service.PreferredInput = engine.types.Enum.PreferredInput:FromName(input)
			local reorders, deletes = {}, {}
			local selection = Compose.cell(spec.selected or {})
			local base: { [any]: any } = {
				from = records(4),
				key = key,
				itemSize = 40,
				selection = selection,
				selectionMode = "multiple" :: "multiple",
				onReorder = function(keys: { number }, slot: number)
					table.insert(reorders, { keys = keys, slot = slot })
				end,
				onDelete = function(keys: { number })
					table.insert(deletes, keys)
				end,
			}
			for field, value in spec do
				if field ~= "selected" then
					base[field] = value
				end
			end
			if list then
				base.render = function(current): GuiObject
					return button(UI, current)
				end
			else
				base.columns = { { id = "label", label = "Label", width = 100 } }
			end
			local stop, node: any = runtime.mount(function()
				return if list then UI.VirtualList(base) else UI.Table(base)
			end, target)
			local body = if list then node else node:FindFirstChild("Body")
			body.AbsoluteWindowSize = engine.types.Vector2.new(300, 200)
			body.Parent.AbsoluteSize = body.AbsoluteWindowSize
			local function pressed(name: string)
				target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
			end
			local function row(rowKey)
				return body:FindFirstChild(tostring(rowKey), true)
			end
			return {
				engine = engine,
				gui = gui,
				service = service,
				node = node,
				body = body,
				row = row,
				pressed = pressed,
				reorders = reorders,
				deletes = deletes,
				selection = selection,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		verifyHarness:case("a pointer drags a row (or the selected rows) to reorder with no handle on show", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a pointer drags a row (or the selected rows) to reorder with no handle on show",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld("KeyboardAndMouse", { reorderable = true }, list)
					local V2 = w.engine.types.Vector2
					Verify.expect((w.row(2):FindFirstChild("Move", true))):toBeNil()
					Verify.expect(w.row(2):FindFirstChild("Cells", true).Position.X.Offset):toBe(0)
					local hit = w.row(2):FindFirstChild("RowHit", true)
					nativeDrag.press(hit, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
						Position = V2.new(10, 50),
					})
					nativeDrag.move(w.service, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
						UserInputState = w.engine.types.Enum.UserInputState.Change,
						Position = V2.new(10, 52),
					})
					Verify.expect((w.node:FindFirstChild("DropLine", true))):toBeNil()
					nativeDrag.move(w.service, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
						UserInputState = w.engine.types.Enum.UserInputState.Change,
						Position = V2.new(10, 150),
					})
					Verify.expect(w.node:FindFirstChild("DropLine", true) ~= nil):toBe(true)
					local image = w.node:FindFirstChild("DragImage", true)
					local copy = image:FindFirstChild("Reorderable")
					Verify.expect(copy ~= nil):toBe(true)
					local original = w.row(2):FindFirstChild("Reorderable", true)
					for _, part in copy:GetDescendants() do
						if part:IsA("GuiObject") then
							Verify.expect(part.ZIndex > original.ZIndex):toBe(true)
							Verify.expect(part.Interactable or part.Active or part.Selectable):toBe(false)
						end
					end
					Verify.expect(w.node:FindFirstChild("ReorderFeedback", true).ZIndex > w.row(2).ZIndex):toBe(true)
					if list then
						Verify.expect(copy:FindFirstChild("Action", true).Text):toBe("2")
						Verify.expect((copy:FindFirstChild("Action", true):HasTag("facet-button"))):toBe(true)
					end
					nativeDrag.finish(w.service, {
						UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
						UserInputState = w.engine.types.Enum.UserInputState.End,
					})
					Verify.expect(#w.reorders):toBe(1)
					Verify.expect(w.reorders[1].keys):toEqual({ 2 })
					w.stop()
				end
			end,
		})

		verifyHarness:case("completes a fast native row drag without an intermediate drag event", {
			id = "native_collections::editable collections: reorderable and deletable on every input::completes a fast native row drag without an intermediate drag event",
			run = function()
				local w = editableWorld("KeyboardAndMouse", { reorderable = true }, true)
				local V2 = w.engine.types.Vector2
				local detector = w.row(2):FindFirstChild("FacetCollectionDrag", true)
				detector.DragStart:Fire(V2.new(10, 50))
				detector.DragEnd:Fire(V2.new(10, 150))
				Verify.expect(#w.reorders):toBe(1)
				Verify.expect(w.reorders[1].keys):toEqual({ 2 })
				w.stop()
			end,
		})

		verifyHarness:case("a row dragged away and back to its own slot keeps the selection and activates nothing", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a row dragged away and back to its own slot keeps the selection and activates nothing",
			run = function()
				local w = editableWorld(
					"KeyboardAndMouse",
					{ reorderable = true, selected = { [1] = true, [2] = true } },
					false
				)
				local V2, E = w.engine.types.Vector2, w.engine.types.Enum
				local hit = w.row(2):FindFirstChild("RowHit", true)
				local press = { UserInputType = E.UserInputType.MouseButton1, Position = V2.new(10, 50) }
				nativeDrag.press(hit, press)
				for _, y in { 150, 50 } do
					nativeDrag.move(w.service, {
						UserInputType = E.UserInputType.MouseMovement,
						UserInputState = E.UserInputState.Change,
						Position = V2.new(10, y),
					})
				end
				nativeDrag.finish(w.service, press)
				hit.Activated:Fire(press, 0)
				Verify.expect((w.selection:peek())):toEqual({ [1] = true, [2] = true })
				nativeDrag.press(w.service, press)
				hit.Activated:Fire(press, 0)
				Verify.expect((w.selection:peek())):toEqual({ [2] = true })
				w.stop()
			end,
		})

		verifyHarness:case("Delete, Backspace and the X button remove the selected deletable rows through onDelete", {
			id = "native_collections::editable collections: reorderable and deletable on every input::Delete, Backspace and the X button remove the selected deletable rows through onDelete",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld(
						"KeyboardAndMouse",
						{ deletable = true, selected = { [3] = true, [1] = true } },
						list
					)
					w.pressed("DeleteRows")
					Verify.expect(w.deletes):toEqual({ { 1, 3 } })
					w.stop()
					local fixed = editableWorld("KeyboardAndMouse", { selected = { [2] = true } }, list)
					local engine = fixed.engine
					Verify.expect((fixed.node.Parent:FindFirstChild("FacetDeleteRows"))):toBeNil()
					fixed.stop()
					local _ = engine
				end
			end,
		})

		verifyHarness:case("in edit mode X deletes the row that holds the pad selection when nothing is selected", {
			id = "native_collections::editable collections: reorderable and deletable on every input::in edit mode X deletes the row that holds the pad selection when nothing is selected",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld("Gamepad", { deletable = true, editing = Compose.cell(true) }, list)
					local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
					local target = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
					w.gui.SelectedObject = target
					Verify.expect(w.gui.SelectedObject ~= nil):toBe(true)
					w.pressed("DeleteRows")
					Verify.expect(w.deletes):toEqual({ { 2 } })
					w.stop()
				end
			end,
		})

		verifyHarness:case(
			"touch and gamepad multi-select in Edit: marks, a tap or A toggles a row, Delete removes them",
			{
				id = "native_collections::editable collections: reorderable and deletable on every input::touch and gamepad multi-select in Edit: marks, a tap or A toggles a row, Delete removes them",
				run = function()
					for _, input in { "Touch", "Gamepad" } do
						local activated = {}
						local w = editableWorld(input, {
							reorderable = true,
							deletable = true,
							onActivate = function(_, rowKey)
								table.insert(activated, rowKey)
							end,
						}, false)
						local E = w.engine.types.Enum
						local press = if input == "Touch"
							then { UserInputType = E.UserInputType.Touch }
							else { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
						local edit = w.node:FindFirstChild("Edit", true)
						Verify.expect(edit ~= nil and edit.Text == "Edit"):toBe(true)
						Verify.expect((edit:HasTag("facet-appearance-utility"))):toBe(false)
						Verify.expect((w.row(1):FindFirstChild("Move", true))):toBeNil()
						Verify.expect((w.row(1):FindFirstChild("Minus", true))):toBeNil()
						Verify.expect(w.row(1):FindFirstChild("SelectMark", true).Visible):toBe(false)
						edit.Activated:Fire()
						Verify.expect(edit.Text):toBe("Done")
						local move, mark =
							w.row(1):FindFirstChild("Move", true), w.row(1):FindFirstChild("SelectMark", true)
						Verify.expect(move.Visible and move.AnchorPoint.X == 1 and move.Position.X.Scale == 1)
							:toBe(true)
						Verify.expect(mark.Visible and mark.Position.X.Scale == 0):toBe(true)
						local cells = w.row(1):FindFirstChild("Cells", true)
						Verify.expect(cells.Position.X.Offset):toBe(44)
						Verify.expect(cells.Size.X.Offset):toBe(-88)
						Verify.expect((cells.Parent:HasTag("facet-tablerow"))):toBe(true)
						local delete = w.node:FindFirstChild("DeleteSelected", true)
						Verify.expect(delete.Visible):toBe(input == "Touch")
						Verify.expect(w.node:FindFirstChild("PadHints", true).Visible):toBe(input == "Gamepad")
						Verify.expect(delete.Interactable):toBe(false)
						w.row(1):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
						w.row(3):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
						Verify.expect((w.selection:peek())):toEqual({ [1] = true, [3] = true })
						Verify.expect(mark:FindFirstChild("Check").Visible):toBe(true)
						w.row(3):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
						w.row(4):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
						Verify.expect((w.selection:peek())):toEqual({ [1] = true, [4] = true })
						Verify.expect(activated):toEqual({})
						if input == "Touch" then
							Verify.expect(delete.Interactable):toBe(true)
							delete.Activated:Fire(press)
						else
							w.pressed("DeleteRows")
						end
						Verify.expect(w.deletes):toEqual({ { 1, 4 } })
						edit.Activated:Fire()
						Verify.expect(mark.Visible):toBe(false)
						w.row(2):FindFirstChild("RowHit", true).Activated:Fire(press, 1)
						Verify.expect(activated):toEqual({ 2 })
						w.stop()
					end
					local pointer = editableWorld("KeyboardAndMouse", { reorderable = true, deletable = true }, false)
					Verify.expect((pointer.node:FindFirstChild("Edit", true))):toBeNil()
					pointer.stop()
				end,
			}
		)

		verifyHarness:case("a List in edit mode marks its rows and a tap toggles one without activating it", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a List in edit mode marks its rows and a tap toggles one without activating it",
			run = function()
				local activated, editing = {}, Compose.cell(true)
				local w = editableWorld("Touch", {
					deletable = true,
					editing = editing,
					onActivate = function(_, rowKey)
						table.insert(activated, rowKey)
					end,
				}, true)
				local touch = { UserInputType = w.engine.types.Enum.UserInputType.Touch }
				Verify.expect(w.row(2):FindFirstChild("SelectMark", true).Visible):toBe(true)
				Verify.expect((w.row(2):FindFirstChild("Minus", true))):toBeNil()
				w.row(2):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				w.row(3):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				Verify.expect((w.selection:peek())):toEqual({ [2] = true, [3] = true })
				Verify.expect(activated):toEqual({})
				w.pressed("DeleteRows")
				Verify.expect(w.deletes):toEqual({ { 2, 3 } })
				editing:set(false)
				w.row(1):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
				Verify.expect(activated):toEqual({ 1 })
				w.stop()
			end,
		})

		verifyHarness:case("the focused-row fallback for Delete looks only inside its own collection", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the focused-row fallback for Delete looks only inside its own collection",
			run = function()
				local w = editableWorld("KeyboardAndMouse", { deletable = true, editing = Compose.cell(true) }, false)
				local crowd = w.engine.new("Frame")
				local outside = w.engine.new("TextButton")
				outside.Parent = crowd
				crowd.Parent = w.node.Parent
				w.gui.SelectedObject = outside
				w.pressed("DeleteRows")
				Verify.expect(w.deletes):toEqual({})
				w.gui.SelectedObject = w.row(2):FindFirstChildWhichIsA("GuiButton", true) or w.row(2)
				w.pressed("DeleteRows")
				Verify.expect(w.deletes):toEqual({ { 2 } })
				w.stop()
			end,
		})

		verifyHarness:case(
			"the toolbar Delete acts on the selection only; the focused-row fallback belongs to the key",
			{
				id = "native_collections::editable collections: reorderable and deletable on every input::the toolbar Delete acts on the selection only; the focused-row fallback belongs to the key",
				run = function()
					local w = editableWorld("Touch", { reorderable = true, deletable = true }, false)
					w.node:FindFirstChild("Edit", true).Activated:Fire()
					local delete = w.node:FindFirstChild("DeleteSelected", true)
					local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
					w.gui.SelectedObject = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
					Verify.expect(w.gui.SelectedObject ~= nil):toBe(true)
					Verify.expect(delete.Interactable):toBe(false)
					delete.Activated:Fire({ UserInputType = w.engine.types.Enum.UserInputType.Touch })
					Verify.expect(w.deletes):toEqual({})
					w.pressed("DeleteRows")
					Verify.expect(w.deletes):toEqual({ { 2 } })
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"a single-selection List in edit mode toggles its one row: a tap on the chosen row clears it",
			{
				id = "native_collections::editable collections: reorderable and deletable on every input::a single-selection List in edit mode toggles its one row: a tap on the chosen row clears it",
				run = function()
					local activated = {}
					local w = editableWorld("Touch", {
						selectionMode = "single" :: "single",
						editing = Compose.cell(true),
						onActivate = function(_, rowKey)
							table.insert(activated, rowKey)
						end,
					}, true)
					local touch = { UserInputType = w.engine.types.Enum.UserInputType.Touch }
					w.row(2):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
					Verify.expect((w.selection:peek())):toEqual({ [2] = true })
					w.row(3):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
					Verify.expect((w.selection:peek())):toEqual({ [3] = true })
					w.row(3):FindFirstChild("RowHit", true).Activated:Fire(touch, 1)
					Verify.expect((w.selection:peek())):toEqual({})
					Verify.expect(activated):toEqual({})
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"a handle drag always drops on DragEnd, even when the detector starts before the handle's press",
			{
				id = "native_collections::editable collections: reorderable and deletable on every input::a handle drag always drops on DragEnd, even when the detector starts before the handle's press",
				run = function()
					local w = editableWorld("Touch", { reorderable = true, editing = Compose.cell(true) }, false)
					local E, V2, V3 = w.engine.types.Enum, w.engine.types.Vector2, w.engine.types.Vector3
					local function drag(rowKey, from, to, pressFirst)
						local handle = w.row(rowKey):FindFirstChild("Move", true)
						local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
						local touch = {
							UserInputType = E.UserInputType.Touch,
							UserInputState = E.UserInputState.Begin,
							Position = V3.new(280, from, 0),
						}
						if pressFirst then
							handle.InputBegan:Fire(touch)
						end
						detector.DragStart:Fire(V2.new(280, from))
						if not pressFirst then
							handle.InputBegan:Fire(touch)
						end
						detector.DragContinue:Fire(V2.new(280, to))
						detector.DragEnd:Fire()
						touch.UserInputState = E.UserInputState.End
						w.service.InputEnded:Fire(touch)
					end
					drag(1, 20, 100, true)
					Verify.expect(#w.reorders):toBe(1)
					drag(4, 140, 20, false)
					Verify.expect(#w.reorders):toBe(2)
					Verify.expect((w.node:FindFirstChild("DragImage", true))):toBeNil()
					Verify.expect((w.row(4):FindFirstChild("Reorderable", true):GetAttribute("FacetDragging")))
						:toBe(false)
					w.stop()
				end,
			}
		)

		verifyHarness:case("the drag image stays over the rows, never over the Edit toolbar or the header", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the drag image stays over the rows, never over the Edit toolbar or the header",
			run = function()
				local w = editableWorld("Touch", { reorderable = true }, false)
				local V2 = w.engine.types.Vector2
				w.node:FindFirstChild("Edit", true).Activated:Fire()
				local detector = w.row(3):FindFirstChild("Move", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V2.new(280, 100))
				detector.DragContinue:Fire(V2.new(280, -200))
				local image = w.node:FindFirstChild("DragImage", true)
				local top = w.body.Position.Y.Offset
				Verify.expect(top > 0):toBe(true)
				Verify.expect(image.Position.Y.Offset):toBe(top)
				detector.DragContinue:Fire(V2.new(280, 900))
				Verify.expect(image.Position.Y.Offset):toBe(top + 200 - 40)
				detector.DragEnd:Fire()
				w.stop()
			end,
		})

		verifyHarness:case("a held finger on a Table row that has an Edit mode scrolls instead of picking the row up", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a held finger on a Table row that has an Edit mode scrolls instead of picking the row up",
			run = function()
				local w = editableWorld("Touch", { reorderable = true }, false)
				local E, V3 = w.engine.types.Enum, w.engine.types.Vector3
				local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
				hit.InputBegan:Fire({ UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) })
				for _ = 1, 30 do
					w.engine.heartbeat:Fire(1 / 60)
				end
				Verify.expect((w.node:FindFirstChild("DragImage", true))):toBeNil()
				Verify.expect(w.body.ScrollingEnabled):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a list handed editing = false keeps touch hold-to-reorder", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a list handed editing = false keeps touch hold-to-reorder",
			run = function()
				local w = editableWorld("Touch", { reorderable = true, editing = false }, true)
				local E, V3 = w.engine.types.Enum, w.engine.types.Vector3
				local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
				hit.InputBegan:Fire({ UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) })
				for _ = 1, 30 do
					w.engine.heartbeat:Fire(1 / 60)
				end
				w.row(2)
					:FindFirstChild("Reorderable", true).TouchLongPress
					:Fire({ w.engine.types.Vector2.new(50, 60) }, E.UserInputState.Begin)
				Verify.expect(w.node:FindFirstChild("DragImage", true) ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("columns that cannot fit beside the edit controls scroll inside a pinned lane, never clip", {
			id = "native_collections::editable collections: reorderable and deletable on every input::columns that cannot fit beside the edit controls scroll inside a pinned lane, never clip",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local V2 = engine.types.Vector2
				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = records(3),
						key = key,
						itemSize = 44,
						reorderable = true,
						deletable = true,
						onReorder = function() end,
						onDelete = function() end,
						columns = {
							{ id = "name", label = "Name", minWidth = 90 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "artist", label = "Artist", minWidth = 72 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "rating", label = "Rating", width = 144 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = V2.new(359, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local header = node:FindFirstChild("Header")
				Verify.expect(header.Size.X.Offset):toBe(359)
				node:FindFirstChild("Edit", true).Activated:Fire()
				Verify.expect(header.Size.X.Offset):toBe(271)
				Verify.expect(header:FindFirstChild("name"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.X)
					:toBe(44)
				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(header.Size.X.Offset):toBe(306)
				header:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = V2.new(306, 44)
				Verify.expect(body.CanvasSize.X.Offset):toBe(306 + 88)
				local lane = body:FindFirstChild("1", true):FindFirstChild("Row", true)
				local painted = lane:FindFirstAncestorWhichIsA("Frame")
				while not painted:HasTag("facet-tablerow") do
					painted = painted.Parent
				end
				Verify.expect(lane.Size.X.Offset):toBe(306)
				body.CanvasPosition = V2.new(35, 0)
				Verify.expect(lane.Position.X.Offset):toBe(-35)
				Verify.expect(painted.Position.X.Offset):toBe(35)
				Verify.expect(lane.Parent.ClipsDescendants):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("a touch cell wraps only at word boundaries and truncates when one word cannot fit", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a touch cell wraps only at word boundaries and truncates when one word cannot fit",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
				local stop, node: any = runtime.mount(function()
					return UI.Table({
						from = { { id = 1, name = "Neon Straightaway MMMM illlllll" } },
						key = key,
						columns = { { id = "name", label = "Name" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end, target)
				local body = node:FindFirstChild("Body")
				body.AbsoluteWindowSize = engine.types.Vector2.new(300, 200)
				body.Parent.AbsoluteSize = body.AbsoluteWindowSize
				local cell = body:FindFirstChild("1", true):FindFirstChild("name", true)
				local value, word = cell:FindFirstChild("Value"), cell:FindFirstChild("LongestWord")
				Verify.expect(word.Text):toBe("Neon\nStraightaway\nMMMM\nilllllll")
				Verify.expect(word.TextWrapped):toBe(false)
				Verify.expect(word.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				Verify.expect(value.TextTruncate):toBe(engine.types.Enum.TextTruncate.AtEnd)
				word.TextFits = true
				Verify.expect(value.TextWrapped):toBe(true)
				word.TextFits = false
				Verify.expect(value.TextWrapped):toBe(false)
				assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
				word.TextFits = true
				Verify.expect(value.TextWrapped):toBe(false)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"touch flexible columns keep the touch floor and scroll sideways instead of shrinking to nothing",
			{
				id = "native_collections::editable collections: reorderable and deletable on every input::touch flexible columns keep the touch floor and scroll sideways instead of shrinking to nothing",
				run = function()
					local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
					local V2 = engine.types.Vector2
					assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
					local columns = {}
					for index = 1, 6 do
						table.insert(columns, { id = `c{index}`, label = `Column {index}` })
					end
					local stop, node: any = runtime.mount(function()
						return UI.Table({ from = records(3), key = key, itemSize = 44, columns = columns })
					end, target)
					node:FindFirstChild("Body").AbsoluteWindowSize = V2.new(200, 200)
					local header = node:FindFirstChild("Header")
					Verify.expect(header.Size.X.Offset):toBe(6 * 44)
					for index = 1, 6 do
						Verify.expect(
							header:FindFirstChild(`c{index}`):FindFirstChildWhichIsA("UISizeConstraint").MinSize.X
						)
							:toBe(44)
					end
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("the shoulder buttons move the selected rows by one slot", {
			id = "native_collections::editable collections: reorderable and deletable on every input::the shoulder buttons move the selected rows by one slot",
			run = function()
				local w = editableWorld("Gamepad", { reorderable = true, selected = { [2] = true } }, false)
				w.pressed("MoveRowsLater")
				Verify.expect(w.reorders):toEqual({ { keys = { 2 }, slot = 2 } })
				w.pressed("MoveRowsEarlier")
				Verify.expect(w.reorders[2]):toEqual({ keys = { 2 }, slot = 0 })
				w.stop()
			end,
		})

		verifyHarness:case("a shoulder move in edit mode keeps the pad selection on the moved row", {
			id = "native_collections::editable collections: reorderable and deletable on every input::a shoulder move in edit mode keeps the pad selection on the moved row",
			run = function()
				for _, list in { false, true } do
					local w = editableWorld("Gamepad", { reorderable = true, editing = Compose.cell(true) }, list)
					local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
					local target = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
					w.gui.SelectedObject = target
					w.pressed("MoveRowsLater")
					Verify.expect(#w.reorders):toBe(1)
					Verify.expect(w.gui.SelectedObject):toBe(target)
					w.stop()
				end
			end,
		})

		verifyHarness:case("selectionMode takes none, single or multiple and refuses anything else", {
			id = "native_collections::editable collections: reorderable and deletable on every input::selectionMode takes none, single or multiple and refuses anything else",
			run = function()
				local engine, runtime, UI, target = setup()
				Verify.expect(function()
					runtime.mount(function()
						return UI.VirtualList({
							from = records(2),
							key = key,
							selectionMode = "multi",
							render = function(current): GuiObject
								return button(UI, current)
							end,
						} :: any)
					end, target)
				end):toThrow()
				runtime:dispose()
				local _ = engine
			end,
		})
	end)

	verifyHarness:suite("shared container editing", function()
		verifyHarness:case("replaces plain selection and toggles only in explicit edit mode across all containers", {
			id = "native_collections::shared container editing::replaces plain selection and toggles only in explicit edit mode across all containers",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid", "Table" } do
					local engine, runtime, UI, target = setup()
					local selection, editing = Compose.cell({}), Compose.cell(false)
					local stop, node: any = runtime.mount(function()
						local spec: any = {
							from = records(3),
							key = key,
							selection = selection,
							selectionMode = "multiple",
							editing = editing,
							mode = "all",
							render = function(): GuiObject
								return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
							end,
						}
						if kind == "Table" then
							spec.columns = { { id = "label", label = "Label", width = 100 } }
							spec.mode, spec.render = nil, nil
						end
						return UI[kind](spec)
					end, target)
					local body = if kind == "Table" then node:FindFirstChild("Body") else node
					body.AbsoluteWindowSize = engine.types.Vector2.new(300, 200)
					local inputs: { Enum.UserInputType | boolean } = {
						engine.types.Enum.UserInputType.Touch,
						engine.types.Enum.UserInputType.Gamepad1,
						engine.types.Enum.UserInputType.Keyboard,
						engine.types.Enum.UserInputType.MouseButton1,
						false,
					}
					for _, inputType in inputs do
						local input = if inputType then { UserInputType = inputType } else nil
						local function tap(id: number)
							body:FindFirstChild(tostring(id), true)
								:FindFirstChild("RowHit", true).Activated
								:Fire(input, 0)
						end
						selection:set({})
						tap(1)
						tap(2)
						Verify.expect((selection:peek())):toEqual({ [2] = true })
						tap(2)
						Verify.expect((selection:peek())):toEqual({ [2] = true })
						editing:set(true)
						tap(1)
						Verify.expect((selection:peek())):toEqual({ [1] = true, [2] = true })
						tap(2)
						Verify.expect((selection:peek())):toEqual({ [1] = true })
						editing:set(false)
						Verify.expect((selection:peek())):toEqual({ [1] = true })
						tap(3)
						Verify.expect((selection:peek())):toEqual({ [3] = true })
					end
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("preserves hidden selection across views and prunes only deleted records", {
			id = "native_collections::shared container editing::preserves hidden selection across views and prunes only deleted records",
			run = function()
				local engine, runtime, UI, target = setup()
				local all, visible, selection =
					Compose.cell(records(3)), Compose.cell(records(3)), Compose.cell({ [2] = true })
				local stops = {}
				for _, kind in { "VirtualList", "VirtualGrid", "Table" } do
					local stop = runtime.mount(function()
						local spec: any = {
							from = visible,
							selectionFrom = all,
							key = key,
							selection = selection,
							selectionMode = "multiple" :: "multiple",
							mode = "all" :: "all",
							render = function(): GuiObject
								return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
							end,
						}
						if kind == "Table" then
							local column = {
								id = "label",
								value = function(item)
									return item.label
								end,
							}
							spec.columns = { column }
							spec.mode, spec.render = nil, nil
						end
						return UI[kind](spec)
					end, target)
					table.insert(stops, stop)
				end
				visible:set({ all:peek()[1] })
				Verify.expect(selection:peek()[2]):toBe(true)
				all:set({ all:peek()[1], all:peek()[3] })
				Verify.expect(selection:peek()[2]):toBe(nil)
				for _, stop in stops do
					stop()
				end
			end,
		})

		verifyHarness:case("keeps rejected drafts through remount and cancels to the latest model value", {
			id = "native_collections::shared container editing::keeps rejected drafts through remount and cancels to the latest model value",
			run = function()
				local engine, runtime, UI, target = setup()
				local value, draft = Compose.cell("Alpha"), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?)
				local accept, commits = false, 0
				local function mount()
					local stop, node: any = runtime.mount(function()
						return UI.CellEditor {
							editor = "text" :: "text",
							value = value,
							draft = draft,
							validate = function(v)
								return if v == "" then "Required" else nil
							end,
							onChange = function(v: any)
								commits += 1
								if accept then
									value:set(v)
								end
							end,
						}
					end, target)
					require("../src/ui/activation").edits(node)[1].onActivate()
					return stop, node:FindFirstChildWhichIsA("TextBox", true)
				end
				local stop, field = mount()
				field.Focused:Fire()
				field.Text = "Beta"
				field.FocusLost:Fire(true)
				Verify.expect(commits):toBe(1)
				Verify.expect((value:peek())):toBe("Alpha")
				Verify.expect(assert(draft:peek()).text):toBe("Beta")
				Verify.expect(assert(draft:peek()).error ~= nil):toBe(true)
				stop()
				stop, field = mount()
				Verify.expect(field.Text):toBe("Beta")
				value:set("Remote")
				Verify.expect(field.Text):toBe("Beta")
				field.Focused:Fire()
				field.FocusLost:Fire(false, { KeyCode = engine.types.Enum.KeyCode.Escape })
				Verify.expect((draft:peek())):toBe(nil)
				Verify.expect(field.Text):toBe("Remote")
				accept = true
				field.Focused:Fire()
				field.Text = "Saved"
				field.FocusLost:Fire(true)
				Verify.expect((value:peek())):toBe("Saved")
				Verify.expect((draft:peek())):toBe(nil)
				stop()
			end,
		})

		verifyHarness:case("keeps inline editors compact on pointer input and enlarges their input target for touch", {
			id = "native_collections::shared container editing::keeps inline editors compact on pointer input and enlarges their input target for touch",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = { MouseEnabled = true } })
				local enabled = Compose.cell(true)
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "text" :: "text",
						value = "Alpha",
						enabled = enabled,
						onChange = function() end,
					}
				end, target)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local hit = node:FindFirstChild("Input+target", true)
				local compactHeight = hit.Size.Y.Offset
				local input = assert(ctx.config.userInputService)
				Verify.expect(compactHeight < 44):toBe(true)
				input.PreferredInput = engine.types.Enum.PreferredInput.Touch
				Verify.expect(hit.Size.Y.Offset >= 44):toBe(true)
				input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
				Verify.expect(hit.Size.Y.Offset >= 44):toBe(true)
				input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(hit.Size.Y.Offset):toBe(compactHeight)
				enabled:set(false)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local field = node:FindFirstChildWhichIsA("TextBox", true)
				Verify.expect(field.TextEditable):toBe(false)
				Verify.expect(field.Selectable):toBe(false)
				Verify.expect(field.Interactable):toBe(false)
				Verify.expect((field:GetAttribute("readOnly"))):toBe(true)
				Verify.expect(hit.Size.Y.Offset):toBe(compactHeight)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("reserves the same inline field box before, during and after editing", {
			id = "native_collections::shared container editing::reserves the same inline field box before, during and after editing",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = { MouseEnabled = true } })
				local editing = Compose.cell(false)
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "text" :: "text",
						label = "Name",
						value = "Alpha",
						editing = editing,
						onChange = function() end,
					}
				end, target)
				Verify.expect((node:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
				local display = node:FindFirstChild("Value")
				local floor = node:FindFirstChild("FieldSize")
				Verify.expect((node:FindFirstChild("Label", true))):toBe(nil)
				Verify.expect(floor ~= nil):toBe(true)
				for _, input in
					{
						engine.types.Enum.PreferredInput.KeyboardAndMouse,
						engine.types.Enum.PreferredInput.Touch,
						engine.types.Enum.PreferredInput.Gamepad,
					}
				do
					assert(ctx.config.userInputService).PreferredInput = input
					local height = floor.MinSize.Y
					for _, active in { false, true, false } do
						editing:set(active)
						Verify.expect(floor.MinSize.Y):toBe(height)
						Verify.expect(display.Size.Y.Offset):toBe(height)
						if active then
							Verify.expect(node:FindFirstChild("Input+target", true).Size.Y.Offset):toBe(height)
						end
					end
				end
				stop()
			end,
		})

		verifyHarness:case("does not save an unfinished draft when its cell is removed", {
			id = "native_collections::shared container editing::does not save an unfinished draft when its cell is removed",
			run = function()
				local _, runtime, UI, target = setup()
				local draft, commits = Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), 0
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "text" :: "text",
						value = "Alpha",
						draft = draft,
						onChange = function()
							commits += 1
						end,
					}
				end, target)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local field = node:FindFirstChildWhichIsA("TextBox", true)
				field.Focused:Fire()
				field.Text = "Unfinished"
				stop()
				Verify.expect(commits):toBe(0)
				Verify.expect(assert(draft:peek()).text):toBe("Unfinished")
			end,
		})

		verifyHarness:case("commits clamped numbers and keeps pending text until the model confirms it", {
			id = "native_collections::shared container editing::commits clamped numbers and keeps pending text until the model confirms it",
			run = function()
				local _, runtime, UI, target = setup()
				local value, draft, busy =
					Compose.cell(5), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), Compose.cell(false)
				local proposed
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "number" :: "number",
						value = value,
						draft = draft,
						busy = busy,
						min = 0,
						max = 10,
						onChange = function(v: any)
							proposed = v
							busy:set(true)
						end,
					}
				end, target)
				require("../src/ui/activation").edits(node)[1].onActivate()
				local field = node:FindFirstChildWhichIsA("TextBox", true)
				field.Focused:Fire()
				field.Text = "25"
				field.FocusLost:Fire(true)
				Verify.expect(proposed):toBe(10)
				Verify.expect((value:peek())):toBe(5)
				Verify.expect(assert(draft:peek()).text):toBe("10")
				value:set(10)
				busy:set(false)
				Verify.expect((draft:peek())):toBe(nil)
				stop()
			end,
		})

		verifyHarness:case("keeps swipe overlays off independently editable embedded controls", {
			id = "native_collections::shared container editing::keeps swipe overlays off independently editable embedded controls",
			run = function()
				local _, runtime, UI, target = setup()
				local editing = Compose.cell(false)
				local stop, list: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(1),
						key = key,
						mode = "all" :: "all",
						editing = editing,
						render = function(): GuiObject
							return UI.CellEditor { editor = "text" :: "text", value = "Name", onChange = function() end }
						end,
						rowActions = function(): FixtureCollectionTypes.RowActionsOptions
							return {
								trailing = {
									{ id = "delete", label = "Delete", role = "destructive" :: "destructive" },
								},
							}
						end,
					}
					return UI.VirtualList(props)
				end, target)
				local grip = list:FindFirstChild("SwipeGrip", true)
				Verify.expect(grip.Visible):toBe(false)
				editing:set(true)
				Verify.expect(grip.Visible):toBe(false)
				stop()
			end,
		})
	end)

	verifyHarness:suite("container presentation and shared cells", function()
		verifyHarness:case("reflows minimum-width tiles as the viewport and bound size change", {
			id = "native_collections::container presentation and shared cells::reflows minimum-width tiles as the viewport and bound size change",
			run = function()
				local engine, runtime, UI, target = setup()
				local controls: any = {}
				local minimum = Compose.cell(150)
				local stop, grid: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(10),
						key = key,
						minColumnWidth = minimum,
						gap = 10,
						itemSize = 80,
						controls = controls,
						render = function(): GuiObject
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				grid.AbsoluteSize = engine.types.Vector2.new(500, 300)
				grid.AbsoluteWindowSize = engine.types.Vector2.new(500, 300)
				Verify.expect(controls.placementOf(3).offset):toBe(0)
				Verify.expect(controls.placementOf(4).offset > 0):toBe(true)
				grid.AbsoluteSize = engine.types.Vector2.new(320, 300)
				grid.AbsoluteWindowSize = engine.types.Vector2.new(320, 300)
				Verify.expect(controls.placementOf(3).offset > 0):toBe(true)
				Verify.expect(controls.placementOf(2).offset):toBe(0)
				minimum:set(240)
				Verify.expect(controls.placementOf(2).offset > 0):toBe(true)
				minimum:set(150)
				Verify.expect(controls.placementOf(2).offset):toBe(0)
				stop()
			end,
		})

		verifyHarness:case("keeps grid edit controls above full-width content and measures their height", {
			id = "native_collections::container presentation and shared cells::keeps grid edit controls above full-width content and measures their height",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local E, V2, D2 = engine.types.Enum, engine.types.Vector2, engine.types.UDim2
				assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
				local editing, controls: any = Compose.cell(true), {}
				local stop, grid: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(4),
						key = key,
						mode = "all" :: "all",
						columns = 2,
						itemSize = 80,
						measure = true,
						controls = controls,
						editing = editing,
						selectionMode = "multiple" :: "multiple",
						reorderable = true,
						onReorder = function() end,
						render = function(): GuiObject
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor) { Name = "Tile" }
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				grid.AbsoluteSize = V2.new(320, 300)
				grid.AbsoluteWindowSize = V2.new(320, 300)
				local row = grid:FindFirstChild("1", true)
				local tile = row:FindFirstChild("Tile", true)
				tile.AbsoluteSize = V2.new(160, 80)
				local cells = row:FindFirstChild("Cells", true)
				Verify.expect(cells.Position):toBe(D2.fromOffset(0, 44))
				Verify.expect(cells.Size):toBe(D2.new(1, 0, 1, -44))
				Verify.expect(controls.placementOf(1).size):toBe(124)
				local handle = row:FindFirstChild("Move", true)
				Verify.expect(handle.Size):toBe(D2.fromOffset(44, 44))
				Verify.expect(handle:FindFirstChildWhichIsA("UIDragDetector").DragStyle)
					:toBe(E.UIDragDetectorDragStyle.TranslatePlane)
				Verify.expect(row:FindFirstChild("SelectMark", true).Position):toBe(D2.fromOffset(22, 22))
				editing:set(false)
				Verify.expect(cells.Position):toBe(D2.fromOffset(0, 44))
				Verify.expect(cells.Size):toBe(D2.new(1, 0, 1, -44))
				Verify.expect(controls.placementOf(1).size):toBe(124)
				Verify.expect((row:FindFirstChild("Move", true))):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("shares one draft between two native fields without duplicate proposals", {
			id = "native_collections::container presentation and shared cells::shares one draft between two native fields without duplicate proposals",
			run = function()
				local _, runtime, UI, target = setup()
				local value, draft, commits =
					Compose.cell("Alpha"), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), 0
				local fields, stops = {}, {}
				for _ = 1, 2 do
					local stop, node: any = runtime.mount(function()
						return UI.CellEditor {
							editor = "text" :: "text",
							value = value,
							draft = draft,
							onChange = function(v: any)
								commits += 1
								value:set(v)
							end,
						}
					end, target)
					table.insert(stops, stop)
					require("../src/ui/activation").edits(node)[1].onActivate()
					table.insert(fields, node:FindFirstChildWhichIsA("TextBox", true))
				end
				fields[1].Focused:Fire()
				fields[1].Text = "Shared"
				Verify.expect(fields[2].Text):toBe("Shared")
				Verify.expect((value:peek())):toBe("Alpha")
				fields[1].FocusLost:Fire(true)
				Verify.expect(commits):toBe(1)
				Verify.expect((value:peek())):toBe("Shared")
				Verify.expect((draft:peek())):toBe(nil)
				for _, stop in stops do
					stop()
				end
			end,
		})

		verifyHarness:case("keeps toggle and menu cells on their native controls", {
			id = "native_collections::container presentation and shared cells::keeps toggle and menu cells on their native controls",
			run = function()
				local _, runtime, UI, target = setup()
				local value = Compose.cell(false)
				local stop, node: any = runtime.mount(function()
					return UI.CellEditor {
						editor = "toggle" :: "toggle",
						value = value,
						onChange = function(v: any)
							value:set(v)
						end,
					}
				end, target)
				local toggle = node:FindFirstChild("Editor")
				Verify.expect((toggle:IsA("TextButton"))):toBe(true)
				toggle.Activated:Fire()
				Verify.expect((value:peek())):toBe(true)
				stop()
				local selected = Compose.cell("Blue")
				stop, node = runtime.mount(function()
					return UI.CellEditor {
						editor = "menu" :: "menu",
						value = selected,
						options = { { value = "Blue", label = "Blue" }, { value = "Red", label = "Red" } },
						onChange = function(v: any)
							selected:set(v)
						end,
					}
				end, target)
				Verify.expect(node:FindFirstChild("Trigger", true) ~= nil):toBe(true)
				Verify.expect((node:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
				stop()
			end,
		})
	end)

	verifyHarness:suite("input-aware collection commands", function()
		verifyHarness:case(
			"routes a shared selection delete including hidden records only through the focused collection",
			{
				id = "native_collections::input-aware collection commands::routes a shared selection delete including hidden records only through the focused collection",
				run = function()
					local engine, runtime, UI, target, gui = setup()
					local rows, selection, proposals =
						Compose.cell(records(3)), Compose.cell({ [2] = true, [3] = true }), {}
					local nodes, stops = {}, {}
					for index = 1, 2 do
						local stop, node: any = runtime.mount(function()
							return UI.VirtualList(
								{
									from = { rows:peek()[1], rows:peek()[2] },
									selectionFrom = rows,
									key = key,
									mode = "all" :: "all",
									selection = selection,
									selectionMode = "multiple" :: "multiple",
									editing = true,
									deletable = true,
									onDelete = function(keys: { number })
										table.insert(proposals, { view = index, keys = keys })
									end,
									render = function(): GuiObject
										return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
									end,
								} :: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number>
							)
						end, target)
						table.insert(nodes, node)
						table.insert(stops, stop)
					end
					gui.SelectedObject = nodes[1]:FindFirstChild("2", true):FindFirstChild("RowHit", true)
					for _, child in target:GetChildren() do
						if child.Name == "FacetDeleteRows" then
							child:FindFirstChild("DeleteRows").Pressed:Fire()
						end
					end
					Verify.expect(#proposals):toBe(1)
					Verify.expect(proposals[1].view):toBe(1)
					Verify.expect(proposals[1].keys):toEqual({ 2, 3 })
					for _, stop in stops do
						stop()
					end
				end,
			}
		)

		verifyHarness:case("shows edit checkmarks for touch and gamepad but uses highlights on desktop", {
			id = "native_collections::input-aware collection commands::shows edit checkmarks for touch and gamepad but uses highlights on desktop",
			run = function()
				local engine = engineLib.new()
				local input = engine.new("UserInputService")
				input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
				local _, runtime, UI, target = setup({ userInputService = input })
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = records(2),
						key = key,
						mode = "all" :: "all",
						selectionMode = "multiple" :: "multiple",
						editing = true,
						render = function(): GuiObject
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor)({})
						end,
					}
					return UI.VirtualList(props)
				end, target)
				local mark = node:FindFirstChild("SelectMark", true)
				Verify.expect(mark.Visible):toBe(false)
				input.PreferredInput = engine.types.Enum.PreferredInput.Touch
				Verify.expect(mark.Visible):toBe(true)
				Verify.expect(mark:FindFirstChild("Check") ~= nil):toBe(true)
				input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
				Verify.expect(mark.Visible):toBe(true)
				stop()
			end,
		})
	end)

	verifyHarness:suite("spatial grid reordering", function()
		verifyHarness:case("moves across cells and between rows for both grid directions, including a short last row", {
			id = "native_collections::spatial grid reordering::moves across cells and between rows for both grid directions, including a short last row",
			run = function()
				for _, horizontal in { false, true } do
					local engine, runtime, UI, target, _, ctx = setup()
					local requests = {}
					local stop, node: any = runtime.mount(function()
						local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(8),
								key = key,
								mode = "all" :: "all",
								columns = 3,
								itemSize = 40,
								direction = if horizontal
									then "horizontal" :: "horizontal"
									else "vertical" :: "vertical",
								reorderable = true,
								collectionId = "spatial-test",
								drag = function(
									_: { { id: number, label: string } },
									keys: { number }
								): FixtureEnvironmentTypes.DraggableSpec
									return {
										payload = { collection = "spatial-test", keys = keys },
										operations = { "move" } :: { "copy" | "move" | "apply" },
									}
								end,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								render = function(current): GuiObject
									return button(UI, current)
								end,
							}
						return UI.VirtualGrid(props)
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(300, 300)
					node.AbsoluteSize = node.AbsoluteWindowSize
					local function press(name)
						local action = target:FindFirstChild("Facet" .. name)
						Verify.expect(action.Enabled):toBe(true)
						action:FindFirstChild(name).Pressed:Fire()
					end
					local handle = node:FindFirstChild("1", true):FindFirstChild("Move", true)
					handle.Parent.AbsoluteSize = engine.types.Vector2.new(100, 40)
					handle.Activated:Fire()
					Verify.expect(require("../src/ui/drag_session")(ctx).state:peek().pickupSize)
						:toBe(handle.Parent.AbsoluteSize)
					press("ChooseDropDestination")
					Verify.expect(target:FindFirstChild("Drop", true).Visible):toBe(false)
					Verify.expect(target:FindFirstChild("FacetReorderCrossLater").Enabled):toBe(false)
					press("ChooseDropDestination")
					Verify.expect(target:FindFirstChild("FacetReorderCrossLater").Enabled):toBe(true)
					press("ReorderCrossLater")
					press("ReorderDown")
					press("ReorderDown")
					press("ReorderDown")
					press("ReorderUp")
					press("ReorderDrop")
					Verify.expect(requests):toEqual({ { keys = { 1 }, slot = 4 } })
					handle.Activated:Fire()
					press("ReorderCrossEarlier")
					press("ReorderUp")
					press("ReorderCancel")
					Verify.expect(#requests):toBe(1)
					stop()
					runtime:dispose()
				end
			end,
		})
		verifyHarness:case(
			"uses the current column count for selected blocks and permits cancelling an all-selected grid",
			{
				id = "native_collections::spatial grid reordering::uses the current column count for selected blocks and permits cancelling an all-selected grid",
				run = function()
					local engine, runtime, UI, target = setup()
					local columns = Compose.cell(3)
					local selection = Compose.cell({ [1] = true, [2] = true })
					local requests = {}
					local stop, node: any = runtime.mount(function()
						local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> =
							{
								from = records(8),
								key = key,
								mode = "all" :: "all",
								columns = columns,
								itemSize = 40,
								selection = selection,
								selectionMode = "multiple" :: "multiple",
								reorderable = true,
								onReorder = function(keys: { number }, slot: number)
									table.insert(requests, { keys = keys, slot = slot })
								end,
								render = function(current): GuiObject
									return button(UI, current)
								end,
							}
						return UI.VirtualGrid(props)
					end, target)
					node.AbsoluteWindowSize = engine.types.Vector2.new(300, 300)
					node.AbsoluteSize = node.AbsoluteWindowSize
					local function press(name)
						target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed:Fire()
					end
					node:FindFirstChild("1", true):FindFirstChild("Move", true).Activated:Fire()
					columns:set(2)
					press("ReorderDown")
					press("ReorderDrop")
					Verify.expect(requests):toEqual({ { keys = { 1, 2 }, slot = 2 } })
					selection:set({
						[1] = true,
						[2] = true,
						[3] = true,
						[4] = true,
						[5] = true,
						[6] = true,
						[7] = true,
						[8] = true,
					})
					node:FindFirstChild("1", true):FindFirstChild("Move", true).Activated:Fire()
					press("ReorderDown")
					press("ReorderCrossLater")
					press("ReorderCancel")
					Verify.expect(#requests):toBe(1)
					stop()
					runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("collection transfer sessions", function()
		verifyHarness:case("keyboard pickup carries selected hidden items and calls the source lifecycle once", {
			id = "native_collections::collection transfer sessions::keyboard pickup carries selected hidden items and calls the source lifecycle once",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local all = records(3)
				local carried, starts, ends = nil, 0, 0
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = { all[1], all[3] },
						selectionFrom = all,
						key = key,
						selection = Compose.cell({ [1] = true, [2] = true }),
						selectionMode = "multiple" :: "multiple",
						itemSize = 40,
						columns = 2,
						drag = function(
							items: { { id: number, label: string } },
							keys: { number }
						): FixtureEnvironmentTypes.DraggableSpec
							carried = keys
							return {
								payload = items,
								onStart = function(_: any, mode: "armed" | "pointer")
									starts += 1
									Verify.expect(mode):toBe("armed")
								end,
								onEnd = function()
									ends += 1
								end,
							}
						end,
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualGrid(props)
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
				local hit = node:FindFirstChild("1", true):FindFirstChild("RowHit", true)
				hit.Activated:Fire({
					UserInputType = engine.types.Enum.UserInputType.Keyboard,
					KeyCode = engine.types.Enum.KeyCode.Return,
				})
				Verify.expect(carried):toEqual({ 1, 2 })
				Verify.expect((node:FindFirstChild("FacetDropOutline"))):toBe(nil)
				Verify.expect(node:FindFirstChild("DropLine", true).Visible):toBe(false)
				Verify.expect(starts):toBe(1)
				require("../src/ui/drag_session")(ctx).finish(false)
				Verify.expect(ends):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("bounds placement queries while dragging through ten thousand rows", {
			id = "native_collections::collection transfer sessions::bounds placement queries while dragging through ten thousand rows",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local rows = Compose.cell(records(10000))
				local controls: FixtureComposeTypes.OrderedCollectionControls<any> = {}
				local insertion
				local stop, node: any = runtime.mount(function()
					return UI.VirtualList({
						from = rows,
						key = key,
						controls = controls,
						itemSize = 40,
						drop = {
							operation = "copy" :: "copy",
							onDrop = function(_: any, info: any)
								insertion = info.insertion
								return true
							end,
						},
						render = function(current): GuiObject
							return button(UI, current)
						end,
					})
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 200)
				nativeDrag.measure(node)
				local queries = 0
				local placement = assert(controls.placementOf)
				controls.placementOf = function(index)
					queries += 1
					return placement(index)
				end
				local session = require("../src/ui/drag_session")(ctx)
				local source = engine.new("TextButton")
				source.Parent = target
				session.begin(source, { payload = "new", operations = { "copy" } }, "pointer", nil, false)
				for _, y in { 45, 85, 125 } do
					queries = 0
					session.update(engine.types.Vector2.new(100, y))
					Verify.expect(queries > 0 and queries < 100):toBe(true)
				end
				local changed = records(10000)
				table.insert(changed, 1, { id = 10001, label = "New" })
				rows:set(changed)
				node.CanvasPosition = engine.types.Vector2.zero
				session.update(engine.types.Vector2.new(100, 45))
				session.commit(node)
				Verify.expect(insertion.beforeKey):toBe(1)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("rebases pending insertion against surviving neighbors and rejects removed neighbors", {
			id = "native_collections::collection transfer sessions::rebases pending insertion against surviving neighbors and rejects removed neighbors",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup()
				local rows = Compose.cell(records(3))
				local pending
				local stop, node: any = runtime.mount(function()
					local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
						from = rows,
						key = key,
						itemSize = 40,
						drop = {
							operation = "copy" :: "copy",
							onDrop = function(_: any, info: any)
								pending = info
								return "pending" :: "pending"
							end,
						},
						render = function(current): GuiObject
							return button(UI, current)
						end,
					}
					return UI.VirtualList(props)
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(200, 200)
				nativeDrag.measure(node)
				local session = require("../src/ui/drag_session")(ctx)
				local source = engine.new("TextButton")
				source.Parent = target
				local function drop()
					session.begin(source, { payload = "new", operations = { "copy" } }, "pointer", nil, false)
					session.update(engine.types.Vector2.new(100, 45))
					session.commit(node)
				end
				drop()
				Verify.expect(pending.insertion.beforeKey):toBe(2)
				local changed = records(3)
				table.insert(changed, 1, { id = 4, label = "New" })
				rows:set(changed)
				Verify.expect((pending.complete(true))):toBe(true)
				Verify.expect(pending.insertion.slot):toBe(2)
				Verify.expect((pending.complete(true))):toBe(false)
				rows:set(records(3))
				drop()
				rows:set({ { id = 3, label = "Only survivor" } })
				Verify.expect((pending.complete(true))):toBe(false)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("native collection detector taps", function()
		verifyHarness:case("selects a frame-backed card before and after a drag without selecting on the drop", {
			id = "native_collections::native collection detector taps::selects a frame-backed card before and after a drag without selecting on the drop",
			run = function()
				for _, kind in { "VirtualGrid", "VirtualList" } do
					local now = 0
					local engine, runtime, UI, target, _, ctx = setup({
						userInputService = {},
						clock = function()
							return now
						end,
					})
					local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
					local selection = Compose.cell({})
					local opened = {}
					local stop, list: any = runtime.mount(function()
						return UI[kind] {
							from = records(3),
							key = key,
							mode = "all" :: "all",
							selection = selection,
							reorderable = true,
							onReorder = function() end,
							onActivate = function(_, id)
								table.insert(opened, id)
							end,
							render = function(): GuiObject
								return ((runtime.constructors.Frame :: unknown) :: FrameConstructor) { Name = "Card" }
							end,
						}
					end, target)
					local input: any = assert(ctx.config.userInputService)
					local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(20, 20, 0) }
					local function tap(id: number, cancelled: boolean?)
						press.UserInputState = E.UserInputState.Begin
						input.InputBegan:Fire(press)
						local card = list:FindFirstChild(tostring(id), true):FindFirstChild("Card", true)
						card.InputBegan:Fire(press)
						local detector = card:FindFirstChild("FacetCollectionDrag")
						detector.DragStart:Fire(V2.new(20, 20))
						press.UserInputState = if cancelled then E.UserInputState.Cancel else E.UserInputState.End
						input.InputEnded:Fire(press)
						detector.DragEnd:Fire()
					end
					tap(1)
					Verify.expect((selection:peek())):toEqual({ [1] = true })
					Verify.expect(#opened):toBe(0)
					tap(1)
					Verify.expect(opened):toEqual({ 1 })
					local card = list:FindFirstChild("1", true):FindFirstChild("Card", true)
					press.UserInputState = E.UserInputState.Begin
					input.InputBegan:Fire(press)
					card.InputBegan:Fire(press)
					local detector = card:FindFirstChild("FacetCollectionDrag")
					input.PreferredInput = E.PreferredInput.Gamepad
					Verify.expect(detector.Enabled):toBe(false)
					input.PreferredInput = E.PreferredInput.Touch
					Verify.expect(detector.Enabled):toBe(false)
					input.PreferredInput = E.PreferredInput.KeyboardAndMouse
					Verify.expect(detector.Enabled):toBe(true)
					detector.DragStart:Fire(V2.new(20, 20))
					detector.DragContinue:Fire(V2.new(20, 140))
					press.UserInputState = E.UserInputState.End
					input.InputEnded:Fire(press)
					detector.DragEnd:Fire()
					Verify.expect((selection:peek())):toEqual({ [1] = true })
					tap(2)
					Verify.expect((selection:peek())):toEqual({ [2] = true })
					Verify.expect(opened):toEqual({ 1 })
					now += 0.6
					engine.heartbeat:Fire(0.6)
					tap(2)
					Verify.expect(opened):toEqual({ 1 })
					tap(3, true)
					Verify.expect((selection:peek())):toEqual({ [2] = true })
					stop()
					runtime:dispose()
				end
			end,
		})
	end)

	verifyHarness:suite("independent cell editing", function()
		verifyHarness:case(
			"keeps table field permissions separate from collection editing and rechecks changed records",
			{
				id = "native_collections::independent cell editing::keeps table field permissions separate from collection editing and rechecks changed records",
				run = function()
					local engine, runtime, UI, target = setup({ userInputService = {} })
					local rows = Compose.cell({ { id = 1, name = "Alpha", checked = false, locked = false } })
					local editing, changes = Compose.cell(false), {}
					local stop, node: any = runtime.mount(function()
						local props: FixtureCollectionTypes.KeyedTableSpec<
							{ id: number, name: string, checked: boolean, locked: boolean },
							number
						> =
							{
								from = rows,
								key = "id",
								editing = editing,
								columns = {
									{
										id = "name",
										editor = "text",
										editLabel = "Edit title",
										editable = function()
											return false
										end,
									} :: FixtureCollectionTypes.TableColumn<any, any>,
									{
										id = "checked",
										editor = "toggle",
										editable = function(item)
											return not item.locked
										end,
									} :: FixtureCollectionTypes.TableColumn<any, any>,
								},
								onCellChange = function(_: number, column: string, value: unknown)
									table.insert(changes, { column = column, value = value })
								end,
							}
						return UI.Table(props)
					end, target)
					local body = node:FindFirstChild("Body")
					body.AbsoluteWindowSize = engine.types.Vector2.new(400, 200)
					local row = node:FindFirstChild("1", true)
					local name = row:FindFirstChild("name", true)
					local toggle = row:FindFirstChild("checked", true):FindFirstChild("Editor", true)
					local edits = require("../src/ui/activation").edits(row)
					Verify.expect(edits[1].label):toBe("Edit title")
					Verify.expect((edits[1].enabled())):toBe(false)
					edits[1].onActivate()
					Verify.expect((name:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
					toggle.Activated:Fire()
					Verify.expect(#changes):toBe(1)
					editing:set(true)
					Verify.expect((edits[1].enabled())):toBe(false)
					edits[1].onActivate()
					Verify.expect((name:FindFirstChildWhichIsA("TextBox", true))):toBe(nil)
					rows:set({ { id = 1, name = "Alpha", checked = false, locked = true } })
					toggle.Activated:Fire()
					Verify.expect(#changes):toBe(1)
					editing:set(false)
					toggle.Activated:Fire()
					Verify.expect(#changes):toBe(1)
					stop()
				end,
			}
		)

		verifyHarness:case("selects before mouse rename and exposes the same field action on nested outline rows", {
			id = "native_collections::independent cell editing::selects before mouse rename and exposes the same field action on nested outline rows",
			run = function()
				for _, kind in { "VirtualList", "VirtualGrid", "Outline", "Table" } do
					local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
					local E = engine.types.Enum
					local selected, editing, allowed = Compose.cell({}), Compose.cell(false), Compose.cell(true)
					local values = Compose.cell("Child")
					local stop, node: any = runtime.mount(function()
						local render = function(_current, _placement, key)
							local fieldEditing: FixtureComposeTypes.Cell<boolean> = if key == "parent"
								then Compose.cell(false)
								else editing
							return UI.CellEditor {
								editor = "text" :: "text",
								value = values,
								editing = fieldEditing,
								enabled = allowed,
								editLabel = "Edit title",
								onChange = function(v: any)
									values:set(v)
								end,
							}
						end
						local spec: any = {
							from = { { id = "child" } },
							key = "id",
							selection = selected,
							selectionMode = "multiple",
							render = render,
							mode = "all",
						}
						if kind == "Outline" then
							spec.from = { { id = "parent", children = { { id = "child" } } } }
							spec.children, spec.expanded = "children", Compose.cell({ parent = true })
						elseif kind == "Table" then
							spec.render = nil
							spec.columns = { { id = "name", render = render } }
						end
						return UI[kind](spec)
					end, target)
					local body = if kind == "Table" then node:FindFirstChild("Body") else node
					body.AbsoluteSize = engine.types.Vector2.new(400, 300)
					body.AbsoluteWindowSize = engine.types.Vector2.new(400, 300)
					local row = node:FindFirstChild("child", true)
					local actionButtons = 0
					for _, child in row:GetDescendants() do
						if child.Name == "CellActions" then
							actionButtons += 1
						end
					end
					Verify.expect(actionButtons):toBe(1)
					local hit = row:FindFirstChild("EditLabel", true)
					local function click(inputType)
						hit.Activated:Fire({ UserInputType = inputType })
					end
					click(E.UserInputType.MouseButton1)
					Verify.expect((selected:peek())):toEqual({ child = true })
					Verify.expect((editing:peek())):toBe(false)
					click(E.UserInputType.Touch)
					Verify.expect((editing:peek())):toBe(false)
					click(E.UserInputType.MouseButton1)
					Verify.expect((editing:peek())):toBe(true)
					editing:set(false)
					assert(ctx.config.userInputService).IsKeyDown = function(_, code)
						return code == E.KeyCode.LeftControl
					end
					click(E.UserInputType.MouseButton1)
					Verify.expect((editing:peek())):toBe(false)
					assert(ctx.config.userInputService).IsKeyDown = function()
						return false
					end
					selected:set({ child = true })
					gui.SelectedObject = row:FindFirstChild("RowHit", true)
					local rename = target:FindFirstChild("RenameCell", true)
					Verify.expect(rename.Parent.Enabled):toBe(true)
					rename.Pressed:Fire()
					Verify.expect((editing:peek())):toBe(true)
					editing:set(false)
					local edits = require("../src/ui/activation").edits(row)
					Verify.expect(edits[1].label):toBe("Edit title")
					edits[1].onActivate()
					Verify.expect((editing:peek())):toBe(true)
					editing:set(false)
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Gamepad
					gui.SelectedObject = row:FindFirstChild("RowHit", true)
					edits[1].onActivate()
					local field = row:FindFirstChildWhichIsA("TextBox", true)
					Verify.expect(gui.SelectedObject):toBe(field)
					field.FocusLost:Fire(false, { KeyCode = E.KeyCode.ButtonB })
					Verify.expect((editing:peek())):toBe(false)
					Verify.expect(gui.SelectedObject):toBe(row:FindFirstChild("RowHit", true))
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
					edits[1].onActivate()
					Verify.expect(gui.SelectedObject):toBe(field)
					field.FocusLost:Fire(false, { KeyCode = E.KeyCode.ButtonB })
					Verify.expect(gui.SelectedObject):toBe(row:FindFirstChild("RowHit", true))
					allowed:set(false)
					edits[1].onActivate()
					Verify.expect((editing:peek())):toBe(false)
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
					Verify.expect(row:FindFirstChild("CellActions", true).Visible):toBe(true)
					local actions = row:FindFirstChild("CellActions", true)
					actions.AbsoluteSize = engine.types.Vector2.new(70, 46)
					Verify.expect(actions.Parent:FindFirstChild("Content").Size.X.Offset)
						:toBe(if kind == "VirtualGrid" then 0 else -70)
					Verify.expect(actions.Parent:FindFirstChild("Content").Size.Y.Offset)
						:toBe(if kind == "VirtualGrid" then -46 else 0)
					Verify.expect(actions.AnchorPoint.Y):toBe(if kind == "VirtualGrid" then 1 else 0.5)

					Verify.expect(row:FindFirstChild("SwipeGrip", true).Visible):toBe(false)
					assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.KeyboardAndMouse
					Verify.expect(row:FindFirstChild("CellActions", true).Visible):toBe(false)
					stop()
				end
			end,
		})
	end)

	type OutlineRecord = { id: string, label: string?, children: { OutlineRecord }? }

	verifyHarness:suite("outline collections", function()
		verifyHarness:case("shares hierarchy, selection and controlled expansion across lists and tables", {
			id = "native_collections::outline collections::shares hierarchy, selection and controlled expansion across lists and tables",
			run = function()
				for _, kind in { "Outline", "VirtualList", "Table" } do
					local engine, runtime, UI, target = setup()
					local rows: Compose.Cell<{ OutlineRecord }> = Compose.cell({
						{ id = "folder", label = "Folder", children = { { id = "child", label = "Child" } } },
						{ id = "empty", label = "Empty", children = {} },
						{ id = "leaf", label = "Leaf" },
					} :: { OutlineRecord })
					local expanded, selection = Compose.cell({}), Compose.cell({ child = true })
					local requests = 0
					local focus: any = {}
					local stop, node: any = runtime.mount(function()
						local spec: any = {
							from = rows,
							key = "id",
							children = "children",
							expanded = expanded,
							selection = selection,
							selectionMode = "multiple",
							focus = focus,
							mode = "all" :: "all",
							itemSize = 60,
							onExpansionChange = function(value)
								requests += 1
								expanded:set(value)
							end,
							render = function(current)
								return runtime.constructors.TextLabel {
									Text = function(use)
										return use(current).label
									end,
									Size = engine.types.UDim2.new(1, 0, 0, 40),
								}
							end,
						}
						if kind == "Table" then
							spec.columns = { { id = "label", label = "Name", width = 240 } }
							spec.render = nil
						end
						return (UI :: any)[kind](spec)
					end, target)
					local function row(key)
						return node:FindFirstChild(key, true)
					end
					Verify.expect((row("child"))):toBe(nil)
					Verify.expect(selection:peek().child):toBe(true)
					Verify.expect(row("empty"):FindFirstChild("Disclosure", true).Visible):toBe(true)
					local leafDisclosure = row("leaf"):FindFirstChild("Disclosure", true)
					Verify.expect(leafDisclosure == nil or not leafDisclosure.Visible):toBe(true)
					row("folder"):FindFirstChild("Disclosure", true).Activated:Fire()
					Verify.expect(requests):toBe(1)
					Verify.expect(row("child") ~= nil):toBe(true)
					Verify.expect((row("child"):FindFirstChild("OutlineRow", true):GetAttribute("FacetOutlineDepth")))
						:toBe(1)
					focus.focus("child")
					Verify.expect((focus.current:peek())):toBe("child")
					row("folder"):FindFirstChild("Disclosure", true).Activated:Fire()
					Verify.expect((row("child"))):toBe(nil)
					Verify.expect(selection:peek().child):toBe(true)
					Verify.expect((focus.current:peek())):toBe("folder")
					stop()
					runtime:dispose()
				end
			end,
		})
		verifyHarness:case("keeps large animated branches windowed and preserves extent when expansion reverses", {
			id = "native_collections::outline collections::keeps large animated branches windowed and preserves extent when expansion reverses",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					motionLevel = "normal",
					clock = function()
						return now
					end,
				})
				local children: { OutlineRecord } = {}
				for index = 1, 1000 do
					table.insert(children, { id = tostring(index) })
				end
				local expanded = Compose.cell({})
				local status: any = Compose.cell(nil)
				local stop, node: any = runtime.mount(function()
					return UI.Outline {
						from = { { id = "folder", children = children }, { id = "last" } } :: { OutlineRecord },
						key = "id",
						children = "children",
						expanded = expanded,
						itemSize = 40,
						status = status,
						render = function(): GuiObject
							return ((runtime.constructors.Frame :: unknown) :: FrameConstructor) {
								Size = engine.types.UDim2.new(1, 0, 0, 40),
							}
						end,
					}
				end, target)
				node.AbsoluteWindowSize = engine.types.Vector2.new(400, 240)
				expanded:set({ folder = true })
				for _ = 1, 4 do
					now += 0.01
					engine.heartbeat:Fire(0.01)
					Verify.expect(status:peek().retained <= 12):toBe(true)
				end
				local before = status:peek().extent
				expanded:set({})
				Verify.expect(math.abs(status:peek().extent - before) < 0.001):toBe(true)
				for _ = 1, 20 do
					now += 0.02
					engine.heartbeat:Fire(0.02)
					Verify.expect(status:peek().retained <= 12):toBe(true)
				end
				Verify.expect(status:peek().total):toBe(2)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("animates row extent on expansion and collapse and honors reduced motion", {
			id = "native_collections::outline collections::animates row extent on expansion and collapse and honors reduced motion",
			run = function()
				for _, reduced in { false, true } do
					local now = 0
					local engine, runtime, UI, target = setup({
						motionLevel = if reduced then "none" else "normal",
						clock = function()
							return now
						end,
					})
					local expanded = Compose.cell({})
					local controls: any = {}
					local stop, node: any = runtime.mount(function()
						return UI.Outline {
							from = { { id = "folder", children = { { id = "child" } } }, { id = "last" } } :: { OutlineRecord },
							key = "id",
							children = "children",
							expanded = expanded,
							mode = "all" :: "all",
							itemSize = 80,
							controls = controls,
							render = function(): GuiObject
								return ((runtime.constructors.Frame :: unknown) :: FrameConstructor) {
									Size = engine.types.UDim2.new(1, 0, 0, 40),
								}
							end,
						}
					end, target)
					expanded:set({ folder = true })
					if not reduced then
						now += 0.025
						engine.heartbeat:Fire(0.025)
						local size = controls.placementOf(2).size
						Verify.expect(size > 0 and size < 80):toBe(true)
					end
					now += 1
					engine.heartbeat:Fire(1)
					Verify.expect(controls.placementOf(2).size):toBe(80)
					expanded:set({})
					if not reduced then
						now += 0.025
						engine.heartbeat:Fire(0.025)
						local size = controls.placementOf(2).size
						Verify.expect(size > 0 and size < 80):toBe(true)
						Verify.expect(node:FindFirstChild("child", true).Interactable):toBe(false)
					end
					now += 1
					engine.heartbeat:Fire(1)
					Verify.expect((node:FindFirstChild("child", true))):toBe(nil)
					stop()
					runtime:dispose()
				end
			end,
		})
	end)

	verifyHarness:suite("outline movement boundaries", function()
		verifyHarness:case("reports sibling insertion slots and prevents implicit reparenting", {
			id = "native_collections::outline movement boundaries::reports sibling insertion slots and prevents implicit reparenting",
			run = function()
				local _, runtime, UI, target, _, ctx = setup()
				local tree: any
				local stop = runtime.mount(function()
					tree = require("../src/ui/collection_tree")(ctx, UI, {
						from = { { id = "folder", children = { { id = "a" }, { id = "b" } } }, { id = "next" } } :: { OutlineRecord },
						children = "children",
						expanded = Compose.cell({ folder = true } :: { [string]: boolean }),
					}, function(item: OutlineRecord)
						return item.id
					end)
					return runtime.constructors.Frame {}
				end, target)
				local accepted, slot, parent = tree.location({ "a" }, 2)
				Verify.expect(accepted):toBe(true)
				Verify.expect(slot):toBe(1)
				Verify.expect(parent):toBe("folder")
				Verify.expect((tree.location({ "a" }, 0))):toBe(false)
				Verify.expect((tree.location({ "a", "next" }, 0))):toBe(false)
				Verify.expect((tree.location({ "next" }, 1))):toBe(false)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("collection row destinations", function()
		verifyHarness:case(
			"routes row centers to item drops, edges to insertion, and armed focus to collapsed folders",
			{
				id = "native_collections::collection row destinations::routes row centers to item drops, edges to insertion, and armed focus to collapsed folders",
				run = function()
					for _, kind in { "VirtualList", "VirtualGrid", "Outline", "Table" } do
						local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
						local drops, reorders = {}, {}
						local stop, node = runtime.mount(function()
							local spec: any = {
								from = {
									{ id = 1, label = "File" },
									{ id = 2, label = "Folder", children = { { id = 4, label = "Child" } } },
									{ id = 3, label = "File" },
								},
								key = function(item)
									return item.id
								end,
								itemSize = 60,
								editing = true,
								reorderable = true,
								collectionId = "library",
								drag = function(items, keys)
									return {
										payload = { collection = "library", items = items, keys = keys },
										operations = {
											"move",
										},
									}
								end,
								onReorder = function(keys, slot)
									table.insert(reorders, { keys, slot })
								end,
								rowDrop = function(current, key): FixtureEnvironmentTypes.DropTargetSpec?
									if key ~= 2 then
										return nil
									end
									return {
										accepts = function(payload)
											return payload.kind ~= "blocked", "Cannot put this in a folder"
										end,
										onDrop = function(payload)
											table.insert(drops, { key, payload })
											return true
										end,
									}
								end,
								render = function(current)
									return button(UI, current)
								end,
							}
							if kind == "Table" then
								spec.render = nil
								spec.columns = { { id = "label", label = "Name" } }
							end
							if kind == "Outline" then
								spec.children = "children"
							end
							return (UI :: any)[kind](spec)
						end, target)
						local root = node :: any
						local body = if kind == "Table" then root:FindFirstChild("Body") else root
						local V2 = engine.types.Vector2
						body.AbsolutePosition = V2.new(0, 0)
						body.AbsoluteWindowSize = V2.new(300, 240)
						nativeDrag.measure(body)
						local outer = body:FindFirstChild("2", true)
						outer.AbsolutePosition = V2.new(0, 60)
						outer.AbsoluteSize = V2.new(300, 60)
						local row = outer:FindFirstChild("Content")
						row.AbsolutePosition = V2.new(0, 60)
						row.AbsoluteSize = V2.new(300, 60)
						local session = require("../src/ui/drag_session")(ctx)
						local source = engine.new("TextButton")
						source.Parent = target
						session.begin(
							source,
							{ payload = { collection = "library", keys = { 1 } } },
							"pointer",
							nil,
							false
						)
						session.update(V2.new(150, 90))
						Verify.expect(session.state:peek().target):toBe(row)
						Verify.expect((row:GetAttribute("FacetDropState"))):toBe("accepted")
						session.update(if kind == "VirtualGrid" then V2.new(5, 90) else V2.new(150, 61))
						Verify.expect(session.state:peek().target):toBe(body)
						Verify.expect((row:GetAttribute("FacetDropState"))):toBeNil()
						session.update(V2.new(150, 90))
						session.commit(nil)
						Verify.expect(#drops):toBe(1)
						Verify.expect(#reorders):toBe(0)
						session.begin(source, { payload = { kind = "blocked" } }, "pointer", nil, false)
						session.update(V2.new(150, 90))
						Verify.expect((row:GetAttribute("FacetDropState"))):toBe("rejected")
						Verify.expect((row:GetAttribute("FacetDropReason"))):toBe("Cannot put this in a folder")
						session.commit(nil)
						Verify.expect(#drops):toBe(1)
						session.begin(source, { payload = { kind = "file" } }, "armed", nil, false)
						local hit = row:FindFirstChild("RowHit")
						Verify.expect((session.targetOf(hit))):toBe(row)
						hit.Activated:Fire({ UserInputType = engine.types.Enum.UserInputType.Touch }, 1)
						Verify.expect(#drops):toBe(2)
						Verify.expect((session.state:peek())):toBeNil()
						stop()
						runtime:dispose()
					end
				end,
			}
		)
	end)
end
