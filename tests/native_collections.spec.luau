--!strict
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
local t = require("./lib/testkit")
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
	registerCollections(ctx, UI)
	registerRowActions(ctx, UI)
	registerTable(ctx, UI)
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

t.describe("Compose native collections", function()
	t.it("paints list and grid selection on the cell owner and clears recycled state", function()
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
			t.expect(painted:HasTag("facet-tablerow")).toBe(true)
			t.expect(painted.BackgroundTransparency).toBe(0)
			t.expect(hit.BackgroundTransparency).toBe(1)
			hit.Activated.fire()
			t.expect(painted:HasTag("facet-selected")).toBe(true)
			selected:set({ [2] = true })
			t.expect(painted:HasTag("facet-selected")).toBe(false)
			t.expect(node:FindFirstChild("2", true):FindFirstChild("RowHit", true).Parent:HasTag("facet-selected"))
				.toBe(true)
			node.CanvasPosition = engine.types.Vector2.new(0, 400)
			for _, child in node:GetDescendants() do
				t.expect(child:HasTag("facet-selected")).toBe(false)
			end
			stop()
			runtime:dispose()
		end
	end)

	t.it("selects on click zero and activates on click one for lists and grids", function()
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
			hit.Activated.fire(mouse, 0)
			t.expect(selected:peek()[1]).toBe(true)
			t.expect(activated).toBe(0)
			hit.Activated.fire(mouse, 1)
			t.expect(activated).toBe(1)
			stop()
		end
	end)

	t.it("uses native whole-row dragging in plugin windows without global mouse events", function()
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
		row.MouseButton1Down.fire(97, 20)
		row.InputBegan.fire(press)
		press.Position = V3.new(35, 2, 0)
		row.InputEnded.fire(press)
		t.expect(#reorders).toBe(0)
		press.Position = V3.new(35, 0, 0)
		row.MouseButton1Down.fire(97, 20)
		row.InputBegan.fire(press)
		press.Position = V3.new(35, 90, 0)
		row.InputEnded.fire(press)
		t.expect(reorders).toEqual({ { keys = { 1 }, slot = 2 } })
		press.Position = V3.new(35, 0, 0)
		press.UserInputState = E.UserInputState.Begin
		row.MouseButton1Down.fire(97, 20)
		row.InputBegan.fire(press)
		list.MouseMoved.fire(97, 110)
		widget.WindowFocusReleased.fire()
		press.UserInputState = E.UserInputState.End
		row.InputEnded.fire(press)
		t.expect(#reorders).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("reuses row containers, replaces reactive items and anchors native scrolling", function()
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
		t.expect(status:peek().retained).toBe(5)
		local initialContainers = {}
		for _, row in node:FindFirstChild("Items"):GetChildren() do
			initialContainers[row] = true
		end
		local original = node:FindFirstChild("1", true):FindFirstChild("Action", true)
		local changed = table.clone(rows)
		changed[1] = { id = 1, label = "Updated" }
		source:set(changed)
		t.expect(node:FindFirstChild("1", true):FindFirstChild("Action", true)).toBe(original)
		t.expect(original.Text).toBe("Updated")
		node.CanvasPosition = engine.types.Vector2.new(0, 400)
		t.expect(status:peek().first).toBe(21)
		local before = node:FindFirstChild("21", true)
		local nextRows = table.clone(changed)
		table.remove(nextRows, 1)
		source:set(nextRows)
		t.expect(node.CanvasPosition.Y).toBe(380)
		t.expect(status:peek().first).toBe(20)
		t.expect(node:FindFirstChild("21", true)).toBe(before)
		node.CanvasPosition = engine.types.Vector2.new(0, 800)
		local reused = false
		for _, row in node:FindFirstChild("Items"):GetChildren() do
			reused = reused or initialContainers[row] == true
		end
		t.expect(reused).toBe(true)
		for index = 1, 10 do
			node.CanvasPosition = engine.types.Vector2.new(0, index * 100)
		end
		stop()
		t.expect(disposed).toBe(rendered)
		for _, made in engine.made do
			if made.Name == "Content" or made.Name == "Action" then
				t.expect(made.isDestroyed()).toBe(true)
			end
		end
		runtime:dispose()
	end)

	t.it("accepts a field name as the collection key", function()
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
		t.expect(list:FindFirstChild("7", true) ~= nil).toBe(true)
		t.expect(keys[1]).toBe("7")
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
		t.expect(tableNode:FindFirstChild("Body"):FindFirstChild("9", true) ~= nil).toBe(true)
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
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "key must be a function or a field name", 1, true) ~= nil).toBe(true)
		runtime:dispose()
	end)

	t.it("defers initial offscreen focus until native geometry and suppresses navigation while editing", function()
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
		t.expect(gui.SelectedObject).toBeNil()
		node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		t.expect(gui.SelectedObject.Text).toBe("50")
		local down = target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown")
		gui.SelectedObject:CaptureFocus()
		down.Pressed.fire()
		t.expect(assert(focus.current):peek()).toBe(50)
		gui.SelectedObject:ReleaseFocus()
		down.Pressed.fire()
		t.expect(assert(focus.current):peek()).toBe(52)
		t.expect(gui.SelectedObject.Text).toBe("52")
		stop()
		runtime:dispose()
	end)

	t.it("wraps arrow and D-pad focus at both ends when wrapFocus is set", function()
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
			t.expect(gui.SelectedObject.Text).toBe("5")
			target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed.fire()
			t.expect(assert(focus.current):peek()).toBe(if wrap then 1 else 5)
			assert(focus.focus)(1)
			target:FindFirstChild("FacetCollectionUp"):FindFirstChild("CollectionUp").Pressed.fire()
			t.expect(assert(focus.current):peek()).toBe(if wrap then 5 else 1)
			target:FindFirstChild("FacetCollectionRight"):FindFirstChild("CollectionRight").Pressed.fire()
			t.expect(assert(focus.current):peek()).toBe(if wrap then 5 else 1)
			stop()
			runtime:dispose()
		end
	end)

	t.it("uses measured extents and column placements for both scroll directions", function()
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
			t.expect(assert(controls.placementOf)(3).offset).toBe(65)
			t.expect(status:peek().extent).toBe(160)
			measured:set({ [1] = 40 })
			t.expect(assert(controls.placementOf)(3).offset).toBe(45)
			columns:set(1)
			t.expect(assert(controls.placementOf)(2).offset).toBe(45)
			local second = node:FindFirstChild("2", true)
			t.expect(if direction == "horizontal" then second.Position.X.Offset else second.Position.Y.Offset).toBe(45)
			gap:set(9)
			t.expect(assert(controls.placementOf)(2).offset).toBe(49)
			t.expect(node:FindFirstChild("2", true)).toBe(second)
			stop()
			runtime:dispose()
		end
	end)

	t.it("observes automatic row sizes without overwriting content geometry", function()
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
						(((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown) :: FrameConstructor
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
		t.expect(status:peek().extent).toBe(140)
		t.expect(content.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(content.Size.Y.Offset).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("measures original content through action and selection wrappers", function()
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
		t.expect(status:peek().extent).toBe(140)
		t.expect(content.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(content.Size.Y.Offset).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("measures a row at its unscaled size while a lift scale grows it", function()
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
						(((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown) :: FrameConstructor
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
		local content = node:FindFirstChild("1", true):FindFirstChild("Measured", true)
		content.AbsoluteSize = engine.types.Vector2.new(200, 60)
		t.expect(status:peek().extent).toBe(140)
		lift:set(1.5)
		content.AbsoluteSize = engine.types.Vector2.new(300, 90)
		t.expect(status:peek().extent).toBe(140)
		stop()
		runtime:dispose()
	end)

	t.it("measures a slot-filling row in layout units under a scaled ancestor", function()
		local engine, runtime, UI, target = setup()
		local stop, node: any = runtime.mount(function()
			return UI.VirtualList({
				from = records(3),
				key = key,
				itemSize = 20,
				measure = true,
				render = function(): GuiObject
					return (
						(((runtime.constructors.Frame :: unknown) :: FrameConstructor) :: unknown) :: FrameConstructor
					) "Fill" {
						Size = engine.types.UDim2.fromScale(1, 1),
					}
				end,
			})
		end, target)
		node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
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
		t.expect(slot.Size.Y.Offset).toBe(20)
		t.expect(writes).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("follows a readable follow policy while the viewport stays at the end", function()
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
		t.expect(node.CanvasPosition.Y).toBe(0)
		node.CanvasPosition = engine.types.Vector2.new(0, 100)
		source:set(records(11))
		t.expect(node.CanvasPosition.Y).toBe(100)
		node.CanvasPosition = engine.types.Vector2.new(0, 120)
		follow:set("end")
		t.expect(node.CanvasPosition.Y).toBe(120)
		source:set(records(12))
		t.expect(node.CanvasPosition.Y).toBe(140)
		follow:set("none")
		source:set(records(13))
		t.expect(node.CanvasPosition.Y).toBe(140)
		stop()
		t.expect(function()
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
		end).toThrow()
		runtime:dispose()
	end)

	t.it("follows appended rows only while native viewport stays at the end", function()
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
		t.expect(node.CanvasPosition.Y).toBe(100)
		source:set(records(11))
		t.expect(node.CanvasPosition.Y).toBe(120)
		node.CanvasPosition = engine.types.Vector2.new(0, 0)
		source:set(records(12))
		t.expect(node.CanvasPosition.Y).toBe(0)
		t.expect(status:peek().following).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("restores the keyed native focus target when virtualization remounts it", function()
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
		t.expect(gui.SelectedObject.Text).toBe("50")
		t.expect(node.CanvasPosition.Y).toBe(900)
		local action
		for _, native in engine.made do
			if native.Name == "Activate" and not native.isDestroyed() and native.Parent.Enabled then
				action = native
			end
		end
		t.expect(action ~= nil).toBe(true)
		node.CanvasPosition = engine.types.Vector2.new(0, 0)
		t.expect(gui.SelectedObject).toBeNil()
		t.expect(action.isDestroyed()).toBe(true)
		node.CanvasPosition = engine.types.Vector2.new(0, 900)
		t.expect(gui.SelectedObject.Text).toBe("50")
		stop()
		t.expect(gui.SelectedObject).toBeNil()
		runtime:dispose()
	end)

	t.it("waits for a PlayerGui before it restores the keyed focus target", function()
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
		t.expect(pcall(assert(focus.focus), 50)).toBe(true)
		t.expect(gui.SelectedObject).toBeNil()
		target.Parent = engine.new("PlayerGui")
		assert(focus.focus)(51)
		t.expect(gui.SelectedObject.Text).toBe("51")
		stop()
		runtime:dispose()
	end)

	t.it("keeps table cells alive across sort and native column resize and prunes selection", function()
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
		column:FindFirstChild("Sort").Activated.fire()
		t.expect(sort:peek()).toEqual({ column = "label", direction = "ascending" :: "ascending" })
		t.expect(body:FindFirstChild("1", true):FindFirstChild("Action", true)).toBe(original)
		column.AbsoluteSize = engine.types.Vector2.new(100, 40)
		local grip = column:FindFirstChild("Resize")
		t.expect(grip.AnchorPoint).toBe(engine.types.Vector2.new(1, 0))
		t.expect(grip.Position).toBe(engine.types.UDim2.fromScale(1, 0))
		t.expect(grip.Size.X.Offset).toBe(12)
		t.expect(header.Size.Y.Offset).toBe(40)
		assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
		t.expect(grip.Size.X.Offset).toBe(44)
		t.expect(header.Size.Y.Offset).toBe(44)
		assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(grip.Size.X.Offset).toBe(12)
		t.expect(header.Size.Y.Offset).toBe(40)
		local detector = column:FindFirstChildWhichIsA("UIDragDetector", true)
		detector.DragStart.fire(engine.types.Vector2.new(100, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(180, 10))
		t.expect(widths:peek().label).toBe(160)
		column:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.new(200, 2)
		column.AbsoluteSize = engine.types.Vector2.new(200, 80)
		detector.DragStart.fire(engine.types.Vector2.new(100, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(180, 10))
		t.expect(widths:peek().label).toBe(140)
		widths:set({ label = 160 })
		column:FindFirstChild("Resize").SelectionGained.fire()
		target:FindFirstChild("FacetNarrowColumn"):FindFirstChild("NarrowColumn").Pressed.fire()
		t.expect(widths:peek().label).toBe(152)
		t.expect(builds).toBe(2)
		source:set({ { id = 2, label = "A" } })
		t.expect(selection:peek()[1]).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("glides the rows that follow a deleted row into place and snaps under reduced motion", function()
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
			t.expect(second.Position.Y.Offset).toBe(20)
			local remaining = records(5)
			table.remove(remaining, 1)
			source:set(remaining)
			t.expect(second.Position.Y.Offset).toBe(if reduced then 0 else 20)
			for _ = 1, 30 do
				engine.heartbeat.fire(1 / 60)
			end
			t.expect(second.Position.Y.Offset).toBe(0)
			stop()
			runtime:dispose()
		end
	end)

	t.it("lays rows out in layout units under a scaled ancestor, as in a ten-foot preview", function()
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
		t.expect(node:FindFirstChild("1", true).Size.X.Offset).toBe(200)
		t.expect(node:FindFirstChild("5", true) ~= nil).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("resolves a card rail to one card with a peek on compact touch and to whole cards elsewhere", function()
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
		t.expect(node:FindFirstChild("1", true).Size.X.Offset).toBe(244)
		assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
		node.AbsoluteWindowSize = V2.new(400, 200)
		t.expect(node:FindFirstChild("1", true).Size.X.Offset).toBe(352)
		t.expect(node:FindFirstChild("2", true).Position.X.Offset).toBe(360)
		stop()
		runtime:dispose()
		t.expect(pcall(function()
			runtime.mount(function()
				return UI.VirtualList({ from = {}, render = button, cards = { perView = 2 } } :: any)
			end, target)
		end)).toBe(false)
	end)

	t.it("withholds a table row's destructive actions from every route when rowDeletable refuses it", function()
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
		t.expect(first:FindFirstChild("trailing", true):FindFirstChild("delete")).toBeNil()
		t.expect(first:FindFirstChild("trailing", true):FindFirstChild("flag") ~= nil).toBe(true)
		t.expect(second:FindFirstChild("trailing", true):FindFirstChild("delete") ~= nil).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("offers a table's own Edit toolbar on touch, gamepad and a mouseless keyboard, never with a mouse", function()
		local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
		local E = engine.types.Enum
		local input: any = assert(ctx.config.userInputService)
		input.PreferredInput, input.MouseEnabled, input.KeyboardEnabled = E.PreferredInput.KeyboardAndMouse, true, true
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
		t.expect(shown()).toBe(false)
		input.MouseEnabled = false
		t.expect(shown()).toBe(true)
		input.MouseEnabled = true
		input.PreferredInput = E.PreferredInput.Gamepad
		t.expect(shown()).toBe(true)
		input.PreferredInput = E.PreferredInput.Touch
		t.expect(shown()).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("a bare modifier press does not flip a touch table to its pointer layout; a real key does", function()
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
		t.expect(shown()).toBe(true)
		for _, modifier in { E.KeyCode.LeftSuper, E.KeyCode.LeftControl, E.KeyCode.LeftShift } do
			pressed = { { KeyCode = modifier } }
			input.InputBegan.fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = modifier })
			input.PreferredInput = E.PreferredInput.KeyboardAndMouse
			t.expect(shown()).toBe(true)
			pressed = {}
			input.PreferredInput = E.PreferredInput.Touch
		end
		pressed = { { KeyCode = E.KeyCode.LeftSuper } }
		input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(shown()).toBe(true)
		pressed = { { KeyCode = E.KeyCode.LeftSuper }, { KeyCode = E.KeyCode.C } }
		input.InputBegan.fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.C })
		t.expect(shown()).toBe(false)
		pressed = {}
		input.PreferredInput = E.PreferredInput.Touch
		t.expect(shown()).toBe(true)
		pressed = { { KeyCode = E.KeyCode.A } }
		input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(shown()).toBe(false)
		pressed = {}
		input.PreferredInput = E.PreferredInput.Touch
		pressed = { { KeyCode = E.KeyCode.LeftShift } }
		input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(shown()).toBe(true)
		pressed = {}
		input.InputChanged.fire({ UserInputType = E.UserInputType.MouseMovement })
		t.expect(shown()).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("keeps a gap under its Edit toolbar and paints the header band across the persistent scrollbar", function()
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
				columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
			})
		end, target)
		node:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(347, 240)
		local toolbar, header, band =
			node:FindFirstChild("Toolbar"), node:FindFirstChild("Header"), node:FindFirstChild("HeaderBand")
		t.expect(header.Position.Y.Offset - toolbar.Size.Y.Offset).toBe(8)
		t.expect(band.Position.Y.Offset).toBe(header.Position.Y.Offset)
		t.expect(band.Size.X.Scale).toBe(1)
		t.expect(band.Size.X.Offset).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("holds a custom cell's content in the themed inset a text value uses", function()
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
		t.expect(mark.Parent.Name).toBe("Inset")
		t.expect(mark.Parent:HasTag("facet-tablecellinset")).toBe(true)
		t.expect(mark.Parent.Parent:HasTag("facet-tablecell")).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("sizes table rows by viewing distance: dense pointer, two-line touch, one large line at ten feet", function()
		local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
		local E = engine.types.Enum
		local input: any = assert(ctx.config.userInputService)
		input.PreferredInput, input.MouseEnabled, input.TouchEnabled = E.PreferredInput.Gamepad, false, false
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
		t.expect(height()).toBe(56)
		t.expect(wraps()).toBe(false)
		gui.ViewportDisplaySize = E.DisplaySize.Medium
		t.expect(height()).toBe(44)
		input.PreferredInput, input.TouchEnabled = E.PreferredInput.Touch, true
		t.expect(height()).toBe(56)
		t.expect(wraps()).toBe(true)
		input.PreferredInput, input.MouseEnabled, input.TouchEnabled = E.PreferredInput.KeyboardAndMouse, true, false
		t.expect(height()).toBe(44)
		t.expect(wraps()).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("marks each row's selection in the leading gutter while a selectable table is editing", function()
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
			return node:FindFirstChild("Body"):FindFirstChild(tostring(row), true):FindFirstChild("SelectMark", true)
		end
		t.expect(mark(1) == nil or mark(1).Visible == false).toBe(true)
		editing:set(true)
		t.expect(mark(1).Visible).toBe(true)
		t.expect(mark(1):HasTag("facet-radio-mark")).toBe(true)
		t.expect(mark(1).Selectable).toBe(false)
		t.expect(mark(1):FindFirstChild("Check").Visible).toBe(false)
		t.expect(mark(2):FindFirstChild("Check").Visible).toBe(true)
		t.expect(node:FindFirstChild("Header").Position.X.Offset).toBe(44)
		selection:set({ [1] = true })
		t.expect(mark(1):FindFirstChild("Check").Visible).toBe(true)
		t.expect(mark(2):FindFirstChild("Check").Visible).toBe(false)
		editing:set(false)
		t.expect(mark(1).Visible).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("resizes and sorts a column from the keyboard or pad and releases the grip to its heading", function()
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
					context:FindFirstChild(name).Pressed.fire()
					return true
				end
			end
			return false
		end
		heading.SelectionGained.fire()
		t.expect(press("NarrowColumnKey")).toBe(true)
		t.expect(widths:peek().label).toBe(92)
		heading.SelectionLost.fire()
		grip.SelectionGained.fire()
		t.expect(press("WidenColumnKey")).toBe(true)
		t.expect(widths:peek().label).toBe(100)
		t.expect(press("SortColumn")).toBe(true)
		t.expect(sort:peek()).toEqual({ column = "label", direction = "ascending" :: "ascending" })
		gui.SelectedObject = grip
		t.expect(press("ReleaseColumn")).toBe(true)
		t.expect(gui.SelectedObject).toBe(heading)
		stop()
		runtime:dispose()
	end)

	t.it("leaves the cross-axis D-pad to the engine so focus can leave a rail for the next shelf", function()
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
			t.expect(
				`{direction} {enabled["FacetCollection" .. along] == true} {enabled["FacetCollection" .. across] == true}`
			)
				.toBe(`{direction} true false`)
			stop()
			runtime:dispose()
		end
	end)

	t.it("keeps focus on the item by default and on the slot with focusPolicy index", function()
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
			t.expect(assert(focus.current):peek()).toBe(if policyName == "index" then 5 else 2)
			source:set(records(6))
			t.expect(assert(focus.current):peek()).toBe(2)
			stop()
			runtime:dispose()
		end
		local _, runtime, UI, target = setup()
		t.expect(pcall(function()
			runtime.mount(function()
				return UI.VirtualList({ from = {}, render = button, focusPolicy = "slot" } :: any)
			end, target)
		end)).toBe(false)
	end)

	t.it("picks a row up from a held finger anywhere on it and leaves a moving finger to the scroll", function()
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
		action.InputBegan.fire(swipe)
		swipe.Position = V3.new(50, 40, 0)
		input.InputChanged.fire(swipe)
		for _ = 1, 30 do
			engine.heartbeat.fire(1 / 60)
		end
		t.expect(node:FindFirstChild("DragImage", true)).toBeNil()
		local hold = { UserInputType = E.UserInputType.Touch, Position = V3.new(50, 10, 0) }
		action.InputBegan.fire(hold)
		engine.heartbeat.fire(0.2)
		t.expect(node:FindFirstChild("DragImage", true)).toBeNil()
		node:FindFirstChild("1", true)
			:FindFirstChild("Reorderable", true).TouchLongPress
			.fire({ engine.types.Vector2.new(50, 10) }, E.UserInputState.Begin)
		t.expect(node:FindFirstChild("DragImage", true) ~= nil).toBe(true)
		t.expect(node.ScrollingEnabled).toBe(false)
		hold.Position = V3.new(50, 70, 0)
		input.InputChanged.fire(hold)
		hold.UserInputState = E.UserInputState.End
		input.InputEnded.fire(hold)
		t.expect(reorders).toBe(1)
		t.expect(node.ScrollingEnabled).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("scrolls a dragged row at the list's edge unless autoscroll is off", function()
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
				engine.heartbeat.fire(1 / 60)
			end
			t.expect(node.CanvasPosition.Y > 0).toBe(autoscroll)
			stop()
			runtime:dispose()
		end
	end)

	t.it("hands edge autoscroll to the enclosing scroller once the list can travel no further", function()
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
		engine.heartbeat.fire(1 / 60)
		t.expect(node.CanvasPosition.Y > 0).toBe(true)
		t.expect(page.CanvasPosition.Y).toBe(0)
		node.CanvasPosition = V2.new(0, 300)
		engine.heartbeat.fire(1 / 60)
		t.expect(node.CanvasPosition.Y).toBe(300)
		t.expect(page.CanvasPosition.Y > 0).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("scrolls a horizontal rail by a mouse drag and keeps the press from activating a card", function()
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
		input.InputBegan.fire(mouse(E.UserInputType.MouseButton1, 250))
		input.InputChanged.fire(mouse(E.UserInputType.MouseMovement, 247))
		t.expect(node.CanvasPosition.X).toBe(0)
		input.InputChanged.fire(mouse(E.UserInputType.MouseMovement, 150))
		t.expect(node.CanvasPosition.X).toBe(100)
		t.expect(node:FindFirstChild("Items").Interactable).toBe(false)
		input.InputChanged.fire(mouse(E.UserInputType.MouseMovement, 400))
		t.expect(node.CanvasPosition.X).toBe(0)
		input.InputEnded.fire(mouse(E.UserInputType.MouseButton1, 400))
		engine.heartbeat.fire(1 / 60)
		t.expect(node:FindFirstChild("Items").Interactable).toBe(true)
		input.InputBegan.fire(mouse(E.UserInputType.MouseButton1, 900))
		input.InputChanged.fire(mouse(E.UserInputType.MouseMovement, 700))
		t.expect(node.CanvasPosition.X).toBe(0)
		stop()
		runtime:dispose()
	end)

	t.it("carries a released mouse drag on a horizontal rail with decaying momentum", function()
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
		input.InputBegan.fire(mouse(E.UserInputType.MouseButton1, 280))
		for x = 260, 180, -20 do
			now += 1 / 60
			input.InputChanged.fire(mouse(E.UserInputType.MouseMovement, x))
		end
		now += 1 / 120
		input.InputChanged.fire(mouse(E.UserInputType.MouseMovement, 180))
		local released = node.CanvasPosition.X
		t.expect(released).toBe(100)
		input.InputEnded.fire(mouse(E.UserInputType.MouseButton1, 180))
		local previous, step = released, 0
		for _ = 1, 20 do
			now += 1 / 60
			engine.heartbeat.fire(1 / 60)
			local at = node.CanvasPosition.X
			t.expect(at >= previous).toBe(true)
			step, previous = at - previous, at
		end
		t.expect(previous > released + 100).toBe(true)
		for _ = 1, 600 do
			now += 1 / 60
			engine.heartbeat.fire(1 / 60)
		end
		local rest = node.CanvasPosition.X
		now += 1 / 60
		engine.heartbeat.fire(1 / 60)
		t.expect(node.CanvasPosition.X).toBe(rest)
		t.expect(step > 0).toBe(true)
		input.InputBegan.fire(mouse(E.UserInputType.MouseButton1, 200))
		input.InputEnded.fire(mouse(E.UserInputType.MouseButton1, 200))
		now += 1 / 60
		engine.heartbeat.fire(1 / 60)
		t.expect(node.CanvasPosition.X).toBe(rest)
		stop()
		runtime:dispose()
	end)

	t.it(
		"places a dragged row and its image in layout units under a scaled ancestor, as in a ten-foot preview",
		function()
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

			nativeDrag.move(input, { UserInputType = E.UserInputType.MouseMovement, Position = V3.new(50, 130, 0) })
			t.expect(node:FindFirstChild("DragImage", true).Position.Y.Offset).toBe(65 - 10)
			nativeDrag.finish(input, { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(50, 130, 0) })
			t.expect(moved).toBe("1@2")
			stop()
			runtime:dispose()
		end
	)

	t.it("keeps grid drag cards at cell size and picks insertion slots across both axes", function()
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
			t.expect(image.Size)
				.toBe(if horizontal then engine.types.UDim2.fromOffset(86, 106) else engine.types.UDim2.fromOffset(106, 86))
			local labels = {}
			for _, layer in image:GetChildren() do
				if layer.Name == "Reorderable" then
					table.insert(labels, layer:FindFirstChild("Action", true):GetAttribute("label"))
					t.expect(layer.Size).toBe(
						if horizontal
							then engine.types.UDim2.fromOffset(80, 100)
							else engine.types.UDim2.fromOffset(100, 80)
					)
				end
			end
			table.sort(labels)
			t.expect(labels).toEqual({ "1", "4" })
			local marker = node:FindFirstChild("DropLine", true)
			t.expect(marker.Size)
				.toBe(if horizontal then engine.types.UDim2.fromOffset(80, 2) else engine.types.UDim2.fromOffset(2, 80))
			nativeDrag.finish(ctx.config.userInputService, press)
			t.expect(requests).toEqual({ { keys = { 1, 4 }, slot = 2 } })
			stop()
			runtime:dispose()
		end
	end)

	t.it("drags an image of the row, stacked two or three deep for a selection, from a press anywhere on it", function()
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
			t.expect(image ~= nil).toBe(true)
			t.expect(image.Interactable).toBe(false)
			local layers = {}
			for _, child in image:GetChildren() do
				if child.Name == "Reorderable" then
					table.insert(layers, child.Position.X.Offset)
				end
			end
			table.sort(layers)
			t.expect(table.concat(layers, ",")).toBe(if count == 1 then "0" elseif count == 2 then "0,6" else "0,6,12")
			t.expect(reorderable.Interactable).toBe(true)
			t.expect(image:FindFirstChild("DragLabel").Visible).toBe(count > 1)
			local ghost = target:FindFirstChild("DragGhost")
			local stack = math.min(count - 1, 2) * 6
			t.expect(math.abs(ghost.AnchorPoint.X * ghost.Size.X.Offset - (200 - stack) / 4) < 0.001).toBe(true)
			t.expect(math.abs(ghost.AnchorPoint.Y * ghost.Size.Y.Offset - 10) < 0.001).toBe(true)
			t.expect(ghost.Position).toBe(engine.types.UDim2.fromOffset(50, 40))
			stop()
			runtime:dispose()
		end
	end)

	t.it("draws icon actions at a fixed width and arms the first action past a 0.6 full swipe", function()
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
		t.expect(delete:GetAttribute("label")).toBe("Delete")
		t.expect(delete:FindFirstChild("LeadingIcon", true) ~= nil).toBe(true)
		local caption = delete:FindFirstChild("Title", true)
		t.expect(caption == nil or caption.Visible == false or caption.Text == "").toBe(true)
		local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(250, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(200, 20))
		t.expect(tray.Size.X.Offset).toBe(50)
		t.expect(`{delete.Size.X.Scale} {delete.Size.X.Offset}`).toBe("0 64")
		detector.DragContinue.fire(engine.types.Vector2.new(170, 20))
		t.expect(`{delete.Size.X.Scale} {delete.Size.X.Offset}`).toBe("0 64")
		detector.DragContinue.fire(engine.types.Vector2.new(65, 20))
		t.expect(delete.Size).toEqual(engine.types.UDim2.fromScale(1, 1))
		t.expect(flag.Visible).toBe(false)
		t.expect(tray.Size.X.Offset).toBe(185)
		detector.DragEnd.fire()
		t.expect(deleted).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("uses native drag to reveal and invoke row actions with cancellation and coordination", function()
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
		detector.DragStart.fire(engine.types.Vector2.new(200, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(120, 20))
		detector.DragEnd.fire()
		t.expect(open:peek()).toBe("trailing")
		coordinator:set({})
		t.expect(open:peek()).toBeNil()
		detector.DragStart.fire(engine.types.Vector2.new(250, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 20))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(1)
		t.expect(open:peek()).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("swipes a Button row from a grip over the content and forwards a tap to the Button", function()
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
		t.expect(grip:IsA("GuiButton")).toBe(true)
		t.expect(grip.Selectable).toBe(false)
		t.expect(grip.Visible).toBe(true)
		t.expect(grip.BackgroundTransparency).toBe(1)
		t.expect(grip.Size).toEqual(engine.types.UDim2.fromScale(1, 1))
		t.expect(grip.ZIndex > mail.ZIndex).toBe(true)
		t.expect(mail.Selectable).toBe(true)
		local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
		t.expect(node:FindFirstChildWhichIsA("UIDragDetector")).toBeNil()
		detector.DragStart.fire(engine.types.Vector2.new(150, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(153, 22))
		detector.DragEnd.fire()
		t.expect(activated).toBe(1)
		t.expect(open:peek()).toBeNil()
		detector.DragStart.fire(engine.types.Vector2.new(200, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(120, 20))
		detector.DragEnd.fire()
		t.expect(open:peek()).toBe("trailing")
		t.expect(activated).toBe(1)
		open:set(nil)
		detector.DragStart.fire(engine.types.Vector2.new(150, 20))
		detector.DragContinue.fire(engine.types.Vector2.new(150, 60))
		detector.DragEnd.fire()
		t.expect(activated).toBe(1)
		t.expect(open:peek()).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("hands touch swipes to the native pan gesture so a vertical pan stays with the scroller", function()
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
		t.expect(detector.Enabled).toBe(true)
		assert(ctx.config.userInputService).PreferredInput = E.PreferredInput.Touch
		t.expect(detector.Enabled).toBe(false)
		local function pan(to: any, state: any)
			grip.TouchPan.fire({ to }, to - V2.new(200, 20), V2.zero, state)
		end
		pan(V2.new(190, 20), E.UserInputState.Begin)
		pan(V2.new(120, 20), E.UserInputState.Change)
		pan(V2.new(120, 20), E.UserInputState.End)
		grip.Activated.fire()
		t.expect(open:peek()).toBe("trailing")
		t.expect(activated).toBe(0)
		open:set(nil)
		pan(V2.new(200, 10), E.UserInputState.Begin)
		pan(V2.new(200, -60), E.UserInputState.Change)
		pan(V2.new(200, -60), E.UserInputState.End)
		grip.Activated.fire()
		t.expect(open:peek()).toBeNil()
		t.expect(activated).toBe(0)
		engine.heartbeat.fire(1 / 60)
		grip.Activated.fire()
		t.expect(activated).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("commits a touch row action from the final pan distance or native release velocity", function()
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
			grip.TouchPan.fire({ V2.new(280, 20) }, V2.new(-20, 0), V2.zero, E.UserInputState.Begin)
			grip.TouchPan.fire({ V2.new(220, 20) }, V2.new(-80, 0), V2.zero, E.UserInputState.Change)
			grip.TouchPan.fire(
				{},
				V2.new(sample.distance, 0),
				V2.new(sample.speed, 0),
				if sample.cancel then E.UserInputState.Cancel else E.UserInputState.End
			)
			t.expect(invoked).toBe(sample.expected)
			t.expect(open:peek()).toBe(if sample.expected == 1 or sample.cancel then nil else "trailing")
			grip.TouchPan.fire({}, V2.new(sample.distance, 0), V2.new(sample.speed, 0), E.UserInputState.End)
			t.expect(invoked).toBe(sample.expected)
			stop()
			runtime:dispose()
		end
	end)

	t.it(
		"a horizontal touch pan holds Facet's enclosing scrollers until release; a vertical one leaves them",
		function()
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
				grip.TouchPan.fire({ to }, to - from, V2.zero, state)
			end
			local function held(): string
				return `{page.ScrollingEnabled} {body.ScrollingEnabled}`
			end
			pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.Begin)
			t.expect(held()).toBe("true false")
			pan(V2.new(120, 24), V2.new(200, 20), E.UserInputState.Change)
			pan(V2.new(120, 24), V2.new(200, 20), E.UserInputState.End)
			t.expect(held()).toBe("true true")
			t.expect(open:peek()).toBe("trailing")
			local sheet = engine.new("Frame")
			sheet.Parent = target
			pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.Begin)
			scrollLock.acquire(target, sheet)
			pan(V2.new(186, 22), V2.new(200, 20), E.UserInputState.End)
			t.expect(held()).toBe("false false")
			scrollLock.release(target, sheet)
			t.expect(held()).toBe("true true")
			open:set(nil)
			engine.heartbeat.fire(1 / 60)
			pan(V2.new(202, 6), V2.new(200, 20), E.UserInputState.Begin)
			pan(V2.new(204, -60), V2.new(200, 20), E.UserInputState.Change)
			t.expect(held()).toBe("true true")
			pan(V2.new(204, -60), V2.new(200, 20), E.UserInputState.End)
			t.expect(open:peek()).toBeNil()
			pan(V2.new(186, 20), V2.new(200, 20), E.UserInputState.Begin)
			pan(V2.new(186, 20), V2.new(200, 20), E.UserInputState.Cancel)
			t.expect(held()).toBe("true true")
			stop()
			runtime:dispose()
		end
	)

	t.it("selects ranges across unmounted rows while honoring row capability policies", function()
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
		body:FindFirstChild("2", true):FindFirstChild("RowHit", true).Activated.fire()
		shifted = true
		body.CanvasPosition = engine.types.Vector2.new(0, 180)
		body:FindFirstChild("10", true):FindFirstChild("RowHit", true).Activated.fire()
		for index = 2, 10 do
			t.expect(selected:peek()[index] == true).toBe(index ~= 4 and index ~= 5)
		end
		t.expect(selected:peek()[1]).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("reorders selected blocks with native drag and cancels stale or keyboard moves", function()
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
		detector.DragStart.fire(engine.types.Vector2.new(10, 40))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 35))
		t.expect(node:FindFirstChild("DropLine", true).Position.Y.Offset).toBe(100)
		t.expect(node:FindFirstChild("DragLabel", true).Text).toBe("2 selected")
		detector.DragEnd.fire()
		t.expect(requests).toEqual({ { keys = { 1, 3 }, slot = 1 } })
		t.expect(body:FindFirstChild("4", true):FindFirstChild("Move", true).Interactable).toBe(false)
		detector.DragStart.fire(engine.types.Vector2.new(10, 40))
		source:set(records(5))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 100))
		detector.DragEnd.fire()
		t.expect(#requests).toBe(1)
		handle.SelectionGained.fire()
		handle.Activated.fire()
		t.expect(handle:FindFirstChild("ReorderIcon").Image).toBe("rbxassetid://108245103349446")
		local cancel
		for _, contextNode in target:GetChildren() do
			if contextNode.Name == "FacetReorderCancel" and contextNode.Enabled then
				cancel = contextNode:FindFirstChild("ReorderCancel")
			end
		end
		assert(cancel)
		cancel.Pressed.fire()
		t.expect(handle.Text).toBe("")
		t.expect(handle:FindFirstChild("ReorderIcon").Image).toBe("rbxassetid://119066409501208")
		t.expect(handle:FindFirstChild("ReorderIcon").Position).toBe(engine.types.UDim2.fromScale(0.5, 0.5))
		t.expect(#requests).toBe(1)
		handle.Activated.fire()
		for _, contextNode in target:GetChildren() do
			if contextNode.Name == "FacetReorderDown" and contextNode.Enabled then
				contextNode:FindFirstChild("ReorderDown").Pressed.fire()
			end
		end
		handle.Activated.fire()
		t.expect(requests[2]).toEqual({ keys = { 1, 3 }, slot = 1 })
		t.expect(node:FindFirstChild("DropLine", true)).toBeNil()
		local stationary = body:FindFirstChild("2", true):FindFirstChild("Move", true)
		stationary.Activated.fire()
		stationary.Activated.fire()
		t.expect(#requests).toBe(2)
		stop()
		runtime:dispose()
	end)

	t.it("arms a move on a detector tap and commits it on the next tap", function()
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
		detector.DragStart.fire(engine.types.Vector2.new(10, 30))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 31))
		detector.DragEnd.fire()
		handle.Activated.fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 })
		t.expect(reorderable:GetAttribute("FacetDragging")).toBe(true)
		t.expect(#requests).toBe(0)
		for _, contextNode in target:GetChildren() do
			if contextNode.Name == "FacetReorderDown" and contextNode.Enabled then
				contextNode:FindFirstChild("ReorderDown").Pressed.fire()
			end
		end
		detector.DragStart.fire(engine.types.Vector2.new(10, 30))
		detector.DragEnd.fire()
		handle.Activated.fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton1 })
		t.expect(reorderable:GetAttribute("FacetDragging")).toBe(false)
		t.expect(requests).toEqual({ { keys = { 2 }, slot = 2 } })
		stop()
		runtime:dispose()
	end)

	t.it("commits a destructive action once after Compose departure and cancels on disposal", function()
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
		engine.heartbeat.fire(0.3)
		local action = node:FindFirstChild("Delete", true)
		action.Activated.fire()
		action.Activated.fire()
		t.expect(invoked).toBe(0)
		engine.heartbeat.fire(0.3)
		t.expect(invoked).toBe(1)
		t.expect(node.Size.Y.Offset).toBe(0)
		action.Activated.fire()
		t.expect(invoked).toBe(1)
		stop()
		local cancel, pending: any = mount()
		pending.AbsoluteSize = engine.types.Vector2.new(300, 40)
		engine.heartbeat.fire(0.3)
		pending:FindFirstChild("Delete", true).Activated.fire()
		cancel()
		engine.heartbeat.fire(1)
		t.expect(invoked).toBe(1)
		runtime:dispose()
	end)

	t.it("never commits or opens a full swipe on an unmeasured row", function()
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
		detector.DragStart.fire(engine.types.Vector2.new(100, 0))
		detector.DragContinue.fire(engine.types.Vector2.new(85, 0))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		t.expect(open:peek()).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("restores a kept row after a destructive action so it can commit again", function()
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
		node:FindFirstChild("Delete", true).Activated.fire()
		t.expect(invoked).toBe(1)
		t.expect(node.Size.Y.Offset).toBe(0)
		t.expect(detector.Enabled).toBe(false)
		open:set("trailing")
		t.expect(node.Size.Y.Offset).toBe(44)
		t.expect(detector.Enabled).toBe(true)
		t.expect(node:FindFirstChild("trailing").Visible).toBe(true)
		node:FindFirstChild("Delete", true).Activated.fire()
		t.expect(invoked).toBe(2)
		stop()
		runtime:dispose()
	end)

	t.it("respects edge full-swipe policy, edit affordances and focused destructive input", function()
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
		detector.DragStart.fire(engine.types.Vector2.new(280, 0))
		detector.DragContinue.fire(engine.types.Vector2.new(0, 0))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		t.expect(open:peek()).toBe("trailing")
		open:set(nil)
		t.expect(node:FindFirstChild("Delete")).toBeNil()
		editing:set(true)
		t.expect(node:FindFirstChild("Delete") ~= nil).toBe(true)
		gui.SelectedObject = node:FindFirstChild("Action", true)
		local contextNode = target:FindFirstChild("FacetRowActionsDelete")
		t.expect(contextNode.Enabled).toBe(true)
		contextNode:FindFirstChild("RowActionsDelete").Pressed.fire()
		t.expect(invoked).toBe(1)
		node:FindFirstChild("Delete").Activated.fire()
		t.expect(invoked).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("uses the shared native menu for all actions and restores focus after cancellation", function()
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
		node.InputBegan.fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton2 })
		local panel = target:FindFirstChild("MenuPanel", true)
		t.expect(panel ~= nil).toBe(true)
		t.expect(panel.SelectionBehaviorDown).toBe(engine.types.Enum.SelectionBehavior.Stop)
		t.expect(target:FindFirstChild("leading:Read", true) ~= nil).toBe(true)
		t.expect(target:FindFirstChild("trailing:Save", true) ~= nil).toBe(true)
		target:FindFirstChild("FacetModalBack"):FindFirstChild("ModalBack").Pressed.fire()
		t.expect(target:FindFirstChild("MenuPanel", true)).toBeNil()
		t.expect(gui.SelectedObject).toBe(original)
		t.expect(invoked).toBe(0)
		node:FindFirstChild("SwipeGrip", true).InputBegan.fire({
			UserInputType = engine.types.Enum.UserInputType.MouseButton2,
		})
		target:FindFirstChild("leading:Read", true).Activated.fire()
		t.expect(invoked).toBe(1)
		t.expect(target:FindFirstChild("MenuPanel", true)).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("lets domain callbacks reject table selection, sorting and resize requests", function()
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
		body:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated.fire()
		node:FindFirstChild("Sort", true).Activated.fire()
		local resize = node:FindFirstChild("Resize", true):FindFirstChildWhichIsA("UIDragDetector")
		resize.DragStart.fire(engine.types.Vector2.new(10, 10))
		resize.DragContinue.fire(engine.types.Vector2.new(50, 10))
		t.expect(requests).toBe(3)
		t.expect(selection:peek()).toEqual({})
		t.expect(sort:peek()).toBeNil()
		t.expect(widths:peek()).toEqual({})
		stop()
		runtime:dispose()
	end)

	t.it("keeps block tables fully mounted and discloses collapsed columns without losing cell state", function()
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
		t.expect(body.ScrollingEnabled).toBe(false)
		t.expect(node.Size.Y.Offset).toBe(80)
		local row = body:FindFirstChild("1", true)
		local cell = row:FindFirstChild("third", true)
		body.AbsoluteWindowSize = engine.types.Vector2.new(250, 40)
		body.Parent.AbsoluteSize = body.AbsoluteWindowSize
		t.expect(cell.Visible).toBe(false)
		local menu = row:FindFirstChild("Details", true)
		menu.Activated.fire()
		local fullValue = target:FindFirstChild("Popup", true):FindFirstChild("third", true)
		t.expect(fullValue ~= nil).toBe(true)
		body.AbsoluteWindowSize = engine.types.Vector2.new(400, 40)
		body.Parent.AbsoluteSize = body.AbsoluteWindowSize
		t.expect(row:FindFirstChild("third", true)).toBe(cell)
		t.expect(cell.Visible).toBe(true)
		t.expect(builds).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("uses new grid neighbors when responsive columns change without changing total extent", function()
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
		t.expect(assert(focus.current):peek()).toBe(7)
		stop()
		runtime:dispose()
	end)

	t.it("drops removed measurements and refreshes current-item row actions under stable keys", function()
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
		t.expect(status:peek().extent).toBe(80)
		local action = row:FindFirstChild("Save", true)
		source:set({ { id = 1, label = "Latest" }, { id = 2, label = "Second" } })
		t.expect(row:FindFirstChild("Save", true)).toBe(action)
		t.expect(action.Text).toBe("Latest")
		action.Activated.fire()
		t.expect(invoked).toBe("Latest")
		source:set({ { id = 2, label = "Second" } })
		source:set(records(2))
		t.expect(status:peek().extent).toBe(40)
		stop()
		runtime:dispose()
	end)

	t.it("locks vertical gestures, opens short velocity flicks and cancels disabled drags", function()
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
		detector.DragStart.fire(engine.types.Vector2.new(200, 0))
		now = 0.1
		detector.DragContinue.fire(engine.types.Vector2.new(195, 60))
		detector.DragEnd.fire()
		t.expect(open:peek()).toBeNil()
		detector.DragStart.fire(engine.types.Vector2.new(200, 0))
		now = 0.11
		detector.DragContinue.fire(engine.types.Vector2.new(188, 0))
		t.expect(node:FindFirstChild("trailing").Size.X.Offset).toBe(12)
		t.expect(node:FindFirstChild("LeadingIcon", true).Image).toBe("rbxassetid://1")
		detector.DragEnd.fire()
		t.expect(open:peek()).toBe("trailing")
		open:set(nil)
		detector.DragStart.fire(engine.types.Vector2.new(200, 0))
		now = 0.3
		detector.DragContinue.fire(engine.types.Vector2.new(-100, 0))
		enabled:set(false)
		detector.DragEnd.fire()
		t.expect(open:peek()).toBeNil()
		t.expect(invoked).toBe(0)
		t.expect(detector.Enabled).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("adapts table row and header height from native text bounds and preferred input", function()
		local engine, runtime, UI, target, _, ctx =
			setup({ userInputService = {}, theme = { metrics = { controlSizes = { regular = { height = 32 } } } } })
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
		t.expect(assert(controls.placementOf)(2).offset).toBe(40)
		row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 60)
		t.expect(assert(controls.placementOf)(2).offset).toBe(76)
		node:FindFirstChild("Sort", true).TextBounds = engine.types.Vector2.new(100, 70)
		t.expect(body.Position.Y.Offset).toBe(86)

		node:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.new(2, 2)
		t.expect(body.Position.Y.Offset).toBe(51)
		t.expect(assert(controls.placementOf)(2).offset).toBe(46)
		local header = node:FindFirstChild("Header")
		header:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = engine.types.Vector2.new(800, 102)
		t.expect(body.CanvasSize.X.Offset).toBe(400)
		body.CanvasPosition = engine.types.Vector2.new(80, 0)
		t.expect(header.Position.X.Offset).toBe(-40)
		body.CanvasPosition = engine.types.Vector2.zero
		node:FindFirstChild("LayoutUnit").AbsoluteSize = engine.types.Vector2.one

		assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.Touch
		row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 8)
		t.expect(assert(controls.placementOf)(2).offset).toBe(56)
		row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 60)
		t.expect(assert(controls.placementOf)(2).offset).toBe(76)
		t.expect(body:FindFirstChild("1", true)).toBe(row)
		node:FindFirstChild("Sort", true).TextBounds = engine.types.Vector2.new(100, 20)
		t.expect(body.Position.Y.Offset).toBe(44)
		stop()
		runtime:dispose()
	end)
	t.it("measures localized row action labels and reveals truncated visible table values", function()
		local engine, runtime, UI, target = setup()
		local open: FixtureComposeTypes.Cell<("leading" | "trailing")?>, editing =
			Compose.cell("trailing" :: ("leading" | "trailing")?), Compose.cell(true)
		local stopActions, actions: any = runtime.mount(function()
			return UI.RowActions({
				content = UI.Button "Action" { label = "Row" } :: GuiObject,
				open = open,
				editing = editing,
				trailing = {
					{ id = "Remove", label = "Localized destructive action", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
				},
			})
		end, target)
		actions.AbsoluteSize = engine.types.Vector2.new(500, 40)
		actions:FindFirstChild("Remove", true).TextBounds = engine.types.Vector2.new(210, 20)
		t.expect(actions:FindFirstChild("trailing").Size.X.Offset).toBe(242)
		actions:FindFirstChild("Delete", true).TextBounds = engine.types.Vector2.new(190, 20)
		t.expect(actions:FindFirstChild("Content").Position.X.Offset).toBe(-20)
		actions:FindFirstChild("Remove", true).TextBounds = engine.types.Vector2.new(30, 20)
		t.expect(actions:FindFirstChild("trailing").Size.X.Offset).toBe(88)
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
		t.expect(row:FindFirstChild("Details", true)).toBeNil()
		row:FindFirstChild("Undisclosed", true).TextFits = false
		row:FindFirstChild("Details", true).Activated.fire()
		local expanded = target:FindFirstChild("Popup", true)
		t.expect(expanded:FindFirstChild("FullValue", true).Text).toBe("Long value that should be disclosed")
		source:set({ { id = 1, label = "Updated entire value" } })
		t.expect(expanded:FindFirstChild("FullValue", true).Text).toBe("Updated entire value")
		row:FindFirstChild("Undisclosed", true).TextFits = true
		t.expect(target:FindFirstChild("Popup", true)).toBeNil()
		t.expect(body:FindFirstChild("1", true)).toBe(row)
		stop()
		runtime:dispose()
	end)

	t.it("keeps native reorder capture and keyboard drop alive across offscreen autoscroll", function()
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
		handle.InputBegan.fire(input)
		detector.DragStart.fire(engine.types.Vector2.new(10, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 99))
		for _ = 1, 40 do
			engine.heartbeat.fire(1 / 60)
		end
		t.expect(body.CanvasPosition.Y > 200).toBe(true)
		t.expect(body:FindFirstChild("1", true)).toBeNil()
		local injectedInputChanged = assert(ctx.config.userInputService).InputChanged :: any
		injectedInputChanged.fire({
			UserInputType = engine.types.Enum.UserInputType.MouseMovement,
			Position = engine.types.Vector3.new(10, 80, 0),
		})
		local injectedInputEnded = assert(ctx.config.userInputService).InputEnded :: any
		injectedInputEnded.fire(input)
		t.expect(#requests).toBe(1)
		t.expect(requests[1].keys).toEqual({ 1 })
		t.expect(requests[1].slot > 10).toBe(true)
		body.CanvasPosition = engine.types.Vector2.zero
		handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
		handle.Activated.fire()
		t.expect(gui.SelectedObject.Name).toBe("Drop")
		for _, part in node:FindFirstChild("DragImage", true):GetDescendants() do
			if part:IsA("GuiObject") or part:IsA("Path2D") then
				t.expect(gui.SelectedObject.ZIndex > part.ZIndex).toBe(true)
			end
		end
		local action = target:FindFirstChild("FacetReorderDown"):FindFirstChild("ReorderDown")
		for _ = 1, 25 do
			action.Pressed.fire()
		end
		t.expect(body:FindFirstChild("1", true)).toBeNil()
		t.expect(gui.SelectedObject.Name).toBe("Drop")
		target:FindFirstChild("FacetReorderDrop"):FindFirstChild("ReorderDrop").Pressed.fire()
		t.expect(requests[2]).toEqual({ keys = { 1 }, slot = 25 })
		body.CanvasPosition = engine.types.Vector2.zero
		handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
		detector = handle:FindFirstChildWhichIsA("UIDragDetector")
		handle.InputBegan.fire(input)
		detector.DragStart.fire(engine.types.Vector2.new(10, 10))
		ctx.config.userInputService.MouseEnabled = false
		t.expect(node:FindFirstChild("DropLine", true)).toBeNil()
		local injectedInputEnded = assert(ctx.config.userInputService).InputEnded :: any
		injectedInputEnded.fire(input)
		t.expect(#requests).toBe(2)
		stop()
		runtime:dispose()
	end)
	t.it("shares list selection and reorder policies and fails closed for protected rows", function()
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
		node:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated.fire()
		node:FindFirstChild("2", true):FindFirstChild("RowHit", true).Activated.fire()
		t.expect(selected:peek()).toEqual({ [1] = true })
		t.expect(node:FindFirstChild("1", true):FindFirstChild("RowHit", true):GetAttribute("FacetSelected")).toBe(true)
		t.expect(node:FindFirstChild("2", true):FindFirstChild("Move", true).Interactable).toBe(false)
		local detector = node:FindFirstChild("1", true):FindFirstChildWhichIsA("UIDragDetector", true)
		detector.DragStart.fire(engine.types.Vector2.new(10, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 90))
		detector.DragEnd.fire()
		t.expect(#requests).toBe(0)
		local remaining = records(4)
		table.remove(remaining, 1)
		source:set(remaining)
		t.expect(selected:peek()).toEqual({})
		stop()
		runtime:dispose()
	end)

	t.it("snaps native scrolling to Compose measured boundaries and yields animation to input", function()
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
				engine.heartbeat.fire(1 / 60)
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
		t.expect(node.CanvasPosition.Y >= 26 and node.CanvasPosition.Y < 40).toBe(true)
		local input = { UserInputType = engine.types.Enum.UserInputType.MouseButton1 }
		node.InputBegan.fire(input)
		local interrupted = node.CanvasPosition.Y
		advance(0.5)
		t.expect(node.CanvasPosition.Y).toBe(interrupted)
		node.InputEnded.fire(input)
		advance(0.4)
		t.expect(node.CanvasPosition.Y).toBe(40)
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
		t.expect(measured.CanvasPosition.Y).toBe(35)
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
		grid.InputBegan.fire(input)
		now += 0.01
		grid.CanvasPosition = engine.types.Vector2.new(5, 0)
		grid.InputEnded.fire(input)
		advance(0.15)
		t.expect(grid.CanvasPosition.X).toBe(40)
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
		t.expect(large.CanvasPosition.Y).toBe(23)
		stopLarge()
		runtime:dispose()
	end)
	t.it("a list that opts into motion still lands its snap when the device asks for reduced motion", function()
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
			engine.heartbeat.fire(1 / 60)
		end
		t.expect(node.CanvasPosition.Y).toBe(40)
		stop()
		runtime:dispose()
	end)
	t.it("a snap starts gently from rest and lands flush", function()
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
			engine.heartbeat.fire(1 / 60)
			table.insert(offsets, node.CanvasPosition.Y)
		end
		local moves = {}
		for index = 2, #offsets do
			if offsets[index] ~= offsets[index - 1] then
				table.insert(moves, offsets[index] - offsets[index - 1])
			end
		end
		t.expect(#moves >= 4).toBe(true)
		t.expect(moves[1] < moves[4]).toBe(true)
		t.expect(offsets[#offsets]).toBe(40)
		stop()
		runtime:dispose()
	end)
	t.it("cancels native row gestures and keeps destructive opt-outs behind every action route", function()
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
		node.InputBegan.fire(pointer)
		detector.DragStart.fire(engine.types.Vector2.new(280, 0))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 0))
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		open:set("trailing")
		node:FindFirstChild("Remove", true).Activated.fire()
		t.expect(invoked).toBe(0)
		t.expect(node:FindFirstChild("Delete", true)).toBeNil()
		gui.SelectedObject = node:FindFirstChild("Action", true)
		open:set(nil)
		t.expect(target:FindFirstChild("FacetRowActionsDelete").Enabled).toBe(false)
		node.InputBegan.fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton2 })
		local menuButton = target:FindFirstChild("trailing:Remove", true)
		t.expect(menuButton.Interactable).toBe(false)
		menuButton.Activated.fire()
		t.expect(invoked).toBe(0)
		target:FindFirstChild("FacetModalBack"):FindFirstChild("ModalBack").Pressed.fire()
		enabled:set(true)
		node.InputBegan.fire(pointer)
		detector.DragStart.fire(engine.types.Vector2.new(280, 0))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 0))
		pointer.UserInputState = engine.types.Enum.UserInputState.Cancel
		local injectedInputChanged = assert(ctx.config.userInputService).InputChanged :: any
		injectedInputChanged.fire(pointer)
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		t.expect(open:peek()).toBeNil()
		stop()
		runtime:dispose()
	end)
	t.it("enters native focus after unfocused collection churn and reaches offscreen keys", function()
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
		first.SelectionGained.fire()
		target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed.fire()
		t.expect(gui.SelectedObject.Text).toBe("3")
		target:FindFirstChild("FacetCollectionLast"):FindFirstChild("CollectionLast").Pressed.fire()
		t.expect(gui.SelectedObject.Text).toBe("100")
		t.expect(node.CanvasPosition.Y).toBe(1900)
		stop()
		runtime:dispose()
	end)
end)

t.describe("Table compact width", function()
	t.it("keeps every column in a narrow table and paints the header band across its columns", function()
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
			t.expect(row:FindFirstChild(id, true).Visible).toBe(true)
			t.expect(node:FindFirstChild("Header"):FindFirstChild(id).Visible).toBe(true)
		end
		local band = node:FindFirstChild("HeaderBand")
		local gutter = node:FindFirstChild("Header").Position.X.Offset
		t.expect(band.Position.X.Offset).toBe(gutter)
		t.expect(band.Size).toBe(engine.types.UDim2.new(1, 0, 0, node:FindFirstChild("Header").Size.Y.Offset))
		t.expect(band:HasTag("facet-tablehead")).toBe(true)
		t.expect(node:FindFirstChild("Header").BackgroundTransparency).toBe(1)
		row:FindFirstChild("Undisclosed", true).TextFits = false
		local more = row:FindFirstChild("Details", true)
		t.expect(more:FindFirstChild("Title", true) == nil or not more:FindFirstChild("Title", true).Visible).toBe(true)
		t.expect(more:FindFirstChild("LeadingIcon", true) ~= nil).toBe(true)
		t.expect(more:GetAttribute("label")).toBe("More actions")
		t.expect(more:HasTag("facet-appearance-utility")).toBe(true)
		stop()
		runtime:dispose()
	end)
end)

t.describe("Table under a scaled ancestor", function()
	t.it("sizes its header in layout units when a UIScale shrinks the rendered window", function()
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
		t.expect(unit ~= nil).toBe(true)
		unit.AbsoluteSize = engine.types.Vector2.new(0.8, 0.8)
		body.AbsoluteWindowSize = engine.types.Vector2.new(800, 200)
		body.Parent.AbsoluteSize = body.AbsoluteWindowSize
		t.expect(node:FindFirstChild("Header").Size.X.Offset).toBe(1000)
		stop()
		runtime:dispose()
	end)
end)

t.describe("Table row tap", function()
	t.it("a tap on a swipeable reorderable row selects it with a band and never starts a move", function()
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
				grip.InputBegan.fire(input)
			end
			local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(engine.types.Vector2.new(150, 20))
			detector.DragEnd.fire()
			return rowNode
		end
		local mouse = { UserInputType = E.UserInputType.MouseButton1, UserInputState = E.UserInputState.Begin }
		local first = tap("1", mouse)
		t.expect(selection:peek()).toEqual({ [1] = true })
		t.expect(rating).toBe(0)
		t.expect(node:FindFirstChild("DropFeedback", true)).toBeNil()
		t.expect(first:FindFirstChild("Reorderable", true):HasTag("facet-selected")).toBe(true)
		local second = tap("2", mouse)
		t.expect(selection:peek()).toEqual({ [2] = true })
		t.expect(first:FindFirstChild("Reorderable", true):HasTag("facet-selected")).toBe(false)
		t.expect(second:FindFirstChild("Reorderable", true):HasTag("facet-selected")).toBe(true)
		stop()
		runtime:dispose()
	end)
end)

t.describe("Row actions under a reorder drag", function()
	t.it("the drag image carries the row content without its open action tray", function()
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
		engine.heartbeat.fire(1)
		opened:set("trailing")
		engine.heartbeat.fire(1)
		t.expect(content.Parent:FindFirstChild("trailing").Visible).toBe(true)
		t.expect(content.Position.X.Offset < 0).toBe(true)
		local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(100, 20, 0) }
		local dismiss = content:FindFirstChild("DismissTray")
		t.expect(dismiss.Visible).toBe(true)
		nativeDrag.press(dismiss, press)
		t.expect(opened:peek()).toBeNil()
		local input: any = assert(ctx.config.userInputService)
		nativeDrag.move(input, { UserInputType = E.UserInputType.MouseMovement, Position = V3.new(100, 60, 0) })
		local image = node:FindFirstChild("DragImage", true)
		t.expect(image ~= nil).toBe(true)
		local ghost = image:FindFirstChild("SwipeGrip", true).Parent
		t.expect(ghost.Parent:FindFirstChild("trailing")).toBeNil()
		t.expect(ghost.Position.X.Offset).toBe(0)
		stop()
		runtime:dispose()
	end)
end)

t.describe("Table selection after a pointer reorder", function()
	t.it("a plain click on another row after a drop selects only that row", function()
		local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
		local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
		local rows = Compose.cell({ { id = 1, name = "Neon" }, { id = 2, name = "Drift" }, { id = 3, name = "Apex" } })
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
			g.InputBegan.fire(press)
			local detector = g:FindFirstChildWhichIsA("UIDragDetector")
			detector.DragStart.fire(V2.new(100, y))
			detector.DragEnd.fire()
			press.UserInputState = E.UserInputState.End
			input.InputEnded.fire(press)
		end
		click("3", 100)
		t.expect(selection:peek()).toEqual({ [3] = true })
		local press = {
			UserInputType = E.UserInputType.MouseButton1,
			UserInputState = E.UserInputState.Begin,
			Position = V3.new(100, 100, 0),
		}
		local g = grip("3")
		g.InputBegan.fire(press)
		local detector = g:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2.new(100, 100))
		for y = 90, 10, -20 do
			input.InputChanged.fire({ UserInputType = E.UserInputType.MouseMovement, Position = V3.new(100, y, 0) })
			detector.DragContinue.fire(V2.new(100, y))
		end
		press.UserInputState = E.UserInputState.End
		press.Position = V3.new(100, 10, 0)
		input.InputEnded.fire(press)
		detector.DragEnd.fire()
		engine.heartbeat.fire(1)
		t.expect(rows:peek()[1].id).toBe(3)
		click("2", 100)
		t.expect(selection:peek()).toEqual({ [2] = true })
		stop()
		runtime:dispose()
	end)
end)

t.describe("Table keyed reorder motion", function()
	t.it("a Table glides its rows to a reversed order like VirtualList", function()
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
		engine.heartbeat.fire(1 / 60)
		local first = body:FindFirstChild("Items"):FindFirstChild("1")
		local before = first.Position.Y.Offset
		rows:set({ rows:peek()[3], rows:peek()[2], rows:peek()[1] })
		engine.heartbeat.fire(0.05)
		local during = first.Position.Y.Offset
		for _ = 1, 30 do
			engine.heartbeat.fire(1 / 60)
		end
		local after = first.Position.Y.Offset
		t.expect(after > before).toBe(true)
		t.expect(during > before and during < after).toBe(true)
		stop()
		runtime:dispose()
	end)
end)

t.describe("Row action tray width", function()
	t.it("an icon action's tray fits its painted icon and keeps the label as its name", function()
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
		t.expect(remove:GetAttribute("label")).toBe("Remove")
		t.expect(remove:HasTag("facet-row-action")).toBe(true)
		t.expect(actions:FindFirstChild("trailing").Size.X.Offset).toBe(math.max(64, 32 + 20 + 8))
		stop()
		runtime:dispose()
	end)
end)

t.describe("editable collections: reorderable and deletable on every input", function()
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
			target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed.fire()
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

	t.it("a pointer drags a row (or the selected rows) to reorder with no handle on show", function()
		for _, list in { false, true } do
			local w = editableWorld("KeyboardAndMouse", { reorderable = true }, list)
			local V2 = w.engine.types.Vector2
			t.expect(w.row(2):FindFirstChild("Move", true).Visible).toBe(false)
			t.expect(w.row(2):FindFirstChild("Cells", true).Position.X.Offset).toBe(0)
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
			t.expect(w.node:FindFirstChild("DropLine", true)).toBeNil()
			nativeDrag.move(w.service, {
				UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
				UserInputState = w.engine.types.Enum.UserInputState.Change,
				Position = V2.new(10, 150),
			})
			t.expect(w.node:FindFirstChild("DropLine", true) ~= nil).toBe(true)
			local image = w.node:FindFirstChild("DragImage", true)
			local copy = image:FindFirstChild("Reorderable")
			t.expect(copy ~= nil).toBe(true)
			local original = w.row(2):FindFirstChild("Reorderable", true)
			for _, part in copy:GetDescendants() do
				if part:IsA("GuiObject") then
					t.expect(part.ZIndex > original.ZIndex).toBe(true)
					t.expect(part.Interactable or part.Active or part.Selectable).toBe(false)
				end
			end
			t.expect(w.node:FindFirstChild("ReorderFeedback", true).ZIndex > w.row(2).ZIndex).toBe(true)
			if list then
				t.expect(copy:FindFirstChild("Action", true).Text).toBe("2")
				t.expect(copy:FindFirstChild("Action", true):HasTag("facet-button")).toBe(true)
			end
			nativeDrag.finish(w.service, {
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = w.engine.types.Enum.UserInputState.End,
			})
			t.expect(#w.reorders).toBe(1)
			t.expect(w.reorders[1].keys).toEqual({ 2 })
			w.stop()
		end
	end)

	t.it("a row dragged away and back to its own slot keeps the selection and activates nothing", function()
		local w =
			editableWorld("KeyboardAndMouse", { reorderable = true, selected = { [1] = true, [2] = true } }, false)
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
		hit.Activated.fire(press, 0)
		t.expect(w.selection:peek()).toEqual({ [1] = true, [2] = true })
		nativeDrag.press(w.service, press)
		hit.Activated.fire(press, 0)
		t.expect(w.selection:peek()).toEqual({ [2] = true })
		w.stop()
	end)

	t.it("Delete, Backspace and the X button remove the selected deletable rows through onDelete", function()
		for _, list in { false, true } do
			local w =
				editableWorld("KeyboardAndMouse", { deletable = true, selected = { [3] = true, [1] = true } }, list)
			w.pressed("DeleteRows")
			t.expect(w.deletes).toEqual({ { 1, 3 } })
			w.stop()
			local fixed = editableWorld("KeyboardAndMouse", { selected = { [2] = true } }, list)
			local engine = fixed.engine
			t.expect(fixed.node.Parent:FindFirstChild("FacetDeleteRows")).toBeNil()
			fixed.stop()
			local _ = engine
		end
	end)

	t.it("in edit mode X deletes the row that holds the pad selection when nothing is selected", function()
		for _, list in { false, true } do
			local w = editableWorld("Gamepad", { deletable = true, editing = Compose.cell(true) }, list)
			local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
			local target = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
			w.gui.SelectedObject = target
			t.expect(w.gui.SelectedObject ~= nil).toBe(true)
			w.pressed("DeleteRows")
			t.expect(w.deletes).toEqual({ { 2 } })
			w.stop()
		end
	end)

	t.it("touch and gamepad multi-select in Edit: marks, a tap or A toggles a row, Delete removes them", function()
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
			t.expect(edit ~= nil and edit.Text == "Edit").toBe(true)
			t.expect(edit:HasTag("facet-appearance-utility")).toBe(false)
			t.expect(w.row(1):FindFirstChild("Move", true).Visible).toBe(false)
			t.expect(w.row(1):FindFirstChild("Minus", true)).toBeNil()
			t.expect(w.row(1):FindFirstChild("SelectMark", true).Visible).toBe(false)
			edit.Activated.fire()
			t.expect(edit.Text).toBe("Done")
			local move, mark = w.row(1):FindFirstChild("Move", true), w.row(1):FindFirstChild("SelectMark", true)
			t.expect(move.Visible and move.AnchorPoint.X == 1 and move.Position.X.Scale == 1).toBe(true)
			t.expect(mark.Visible and mark.Position.X.Scale == 0).toBe(true)
			local cells = w.row(1):FindFirstChild("Cells", true)
			t.expect(cells.Position.X.Offset).toBe(44)
			t.expect(cells.Size.X.Offset).toBe(-88)
			t.expect(cells.Parent:HasTag("facet-tablerow")).toBe(true)
			local delete = w.node:FindFirstChild("DeleteSelected", true)
			t.expect(delete.Visible).toBe(input == "Touch")
			t.expect(w.node:FindFirstChild("PadHints", true).Visible).toBe(input == "Gamepad")
			t.expect(delete.Interactable).toBe(false)
			w.row(1):FindFirstChild("RowHit", true).Activated.fire(press, 1)
			w.row(3):FindFirstChild("RowHit", true).Activated.fire(press, 1)
			t.expect(w.selection:peek()).toEqual({ [1] = true, [3] = true })
			t.expect(mark:FindFirstChild("Check").Visible).toBe(true)
			w.row(3):FindFirstChild("RowHit", true).Activated.fire(press, 1)
			w.row(4):FindFirstChild("RowHit", true).Activated.fire(press, 1)
			t.expect(w.selection:peek()).toEqual({ [1] = true, [4] = true })
			t.expect(activated).toEqual({})
			if input == "Touch" then
				t.expect(delete.Interactable).toBe(true)
				delete.Activated.fire(press)
			else
				w.pressed("DeleteRows")
			end
			t.expect(w.deletes).toEqual({ { 1, 4 } })
			edit.Activated.fire()
			t.expect(mark.Visible).toBe(false)
			w.row(2):FindFirstChild("RowHit", true).Activated.fire(press, 1)
			t.expect(activated).toEqual({ 2 })
			w.stop()
		end
		local pointer = editableWorld("KeyboardAndMouse", { reorderable = true, deletable = true }, false)
		t.expect(pointer.node:FindFirstChild("Edit", true)).toBeNil()
		pointer.stop()
	end)

	t.it("a List in edit mode marks its rows and a tap toggles one without activating it", function()
		local activated, editing = {}, Compose.cell(true)
		local w = editableWorld("Touch", {
			deletable = true,
			editing = editing,
			onActivate = function(_, rowKey)
				table.insert(activated, rowKey)
			end,
		}, true)
		local touch = { UserInputType = w.engine.types.Enum.UserInputType.Touch }
		t.expect(w.row(2):FindFirstChild("SelectMark", true).Visible).toBe(true)
		t.expect(w.row(2):FindFirstChild("Minus", true)).toBeNil()
		w.row(2):FindFirstChild("RowHit", true).Activated.fire(touch, 1)
		w.row(3):FindFirstChild("RowHit", true).Activated.fire(touch, 1)
		t.expect(w.selection:peek()).toEqual({ [2] = true, [3] = true })
		t.expect(activated).toEqual({})
		w.pressed("DeleteRows")
		t.expect(w.deletes).toEqual({ { 2, 3 } })
		editing:set(false)
		w.row(1):FindFirstChild("RowHit", true).Activated.fire(touch, 1)
		t.expect(activated).toEqual({ 1 })
		w.stop()
	end)

	t.it("the focused-row fallback for Delete looks only inside its own collection", function()
		local w = editableWorld("KeyboardAndMouse", { deletable = true, editing = Compose.cell(true) }, false)
		local crowd = w.engine.new("Frame")
		local outside = w.engine.new("TextButton")
		outside.Parent = crowd
		crowd.Parent = w.node.Parent
		w.gui.SelectedObject = outside
		w.pressed("DeleteRows")
		t.expect(w.deletes).toEqual({})
		w.gui.SelectedObject = w.row(2):FindFirstChildWhichIsA("GuiButton", true) or w.row(2)
		w.pressed("DeleteRows")
		t.expect(w.deletes).toEqual({ { 2 } })
		w.stop()
	end)

	t.it("the toolbar Delete acts on the selection only; the focused-row fallback belongs to the key", function()
		local w = editableWorld("Touch", { reorderable = true, deletable = true }, false)
		w.node:FindFirstChild("Edit", true).Activated.fire()
		local delete = w.node:FindFirstChild("DeleteSelected", true)
		local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
		w.gui.SelectedObject = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
		t.expect(w.gui.SelectedObject ~= nil).toBe(true)
		t.expect(delete.Interactable).toBe(false)
		delete.Activated.fire({ UserInputType = w.engine.types.Enum.UserInputType.Touch })
		t.expect(w.deletes).toEqual({})
		w.pressed("DeleteRows")
		t.expect(w.deletes).toEqual({ { 2 } })
		w.stop()
	end)

	t.it("a single-selection List in edit mode toggles its one row: a tap on the chosen row clears it", function()
		local activated = {}
		local w = editableWorld("Touch", {
			selectionMode = "single" :: "single",
			editing = Compose.cell(true),
			onActivate = function(_, rowKey)
				table.insert(activated, rowKey)
			end,
		}, true)
		local touch = { UserInputType = w.engine.types.Enum.UserInputType.Touch }
		w.row(2):FindFirstChild("RowHit", true).Activated.fire(touch, 1)
		t.expect(w.selection:peek()).toEqual({ [2] = true })
		w.row(3):FindFirstChild("RowHit", true).Activated.fire(touch, 1)
		t.expect(w.selection:peek()).toEqual({ [3] = true })
		w.row(3):FindFirstChild("RowHit", true).Activated.fire(touch, 1)
		t.expect(w.selection:peek()).toEqual({})
		t.expect(activated).toEqual({})
		w.stop()
	end)

	t.it("a handle drag always drops on DragEnd, even when the detector starts before the handle's press", function()
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
				handle.InputBegan.fire(touch)
			end
			detector.DragStart.fire(V2.new(280, from))
			if not pressFirst then
				handle.InputBegan.fire(touch)
			end
			detector.DragContinue.fire(V2.new(280, to))
			detector.DragEnd.fire()
			touch.UserInputState = E.UserInputState.End
			w.service.InputEnded.fire(touch)
		end
		drag(1, 20, 100, true)
		t.expect(#w.reorders).toBe(1)
		drag(4, 140, 20, false)
		t.expect(#w.reorders).toBe(2)
		t.expect(w.node:FindFirstChild("DragImage", true)).toBeNil()
		t.expect(w.row(4):FindFirstChild("Reorderable", true):GetAttribute("FacetDragging")).toBe(false)
		w.stop()
	end)

	t.it("the drag image stays over the rows, never over the Edit toolbar or the header", function()
		local w = editableWorld("Touch", { reorderable = true }, false)
		local V2 = w.engine.types.Vector2
		w.node:FindFirstChild("Edit", true).Activated.fire()
		local detector = w.row(3):FindFirstChild("Move", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V2.new(280, 100))
		detector.DragContinue.fire(V2.new(280, -200))
		local image = w.node:FindFirstChild("DragImage", true)
		local top = w.body.Position.Y.Offset
		t.expect(top > 0).toBe(true)
		t.expect(image.Position.Y.Offset).toBe(top)
		detector.DragContinue.fire(V2.new(280, 900))
		t.expect(image.Position.Y.Offset).toBe(top + 200 - 40)
		detector.DragEnd.fire()
		w.stop()
	end)

	t.it("a held finger on a Table row that has an Edit mode scrolls instead of picking the row up", function()
		local w = editableWorld("Touch", { reorderable = true }, false)
		local E, V3 = w.engine.types.Enum, w.engine.types.Vector3
		local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
		hit.InputBegan.fire({ UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) })
		for _ = 1, 30 do
			w.engine.heartbeat.fire(1 / 60)
		end
		t.expect(w.node:FindFirstChild("DragImage", true)).toBeNil()
		t.expect(w.body.ScrollingEnabled).toBe(true)
		w.stop()
	end)

	t.it("a list handed editing = false keeps touch hold-to-reorder", function()
		local w = editableWorld("Touch", { reorderable = true, editing = false }, true)
		local E, V3 = w.engine.types.Enum, w.engine.types.Vector3
		local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
		hit.InputBegan.fire({ UserInputType = E.UserInputType.Touch, Position = V3.new(50, 60, 0) })
		for _ = 1, 30 do
			w.engine.heartbeat.fire(1 / 60)
		end
		w.row(2)
			:FindFirstChild("Reorderable", true).TouchLongPress
			.fire({ w.engine.types.Vector2.new(50, 60) }, E.UserInputState.Begin)
		t.expect(w.node:FindFirstChild("DragImage", true) ~= nil).toBe(true)
		w.stop()
	end)

	t.it("columns that cannot fit beside the edit controls scroll inside a pinned lane, never clip", function()
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
		t.expect(header.Size.X.Offset).toBe(359)
		node:FindFirstChild("Edit", true).Activated.fire()
		t.expect(header.Size.X.Offset).toBe(271)
		t.expect(header:FindFirstChild("name"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(44)
		assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(header.Size.X.Offset).toBe(306)
		header:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = V2.new(306, 44)
		t.expect(body.CanvasSize.X.Offset).toBe(306 + 88)
		local lane = body:FindFirstChild("1", true):FindFirstChild("Row", true)
		local painted = lane:FindFirstAncestorWhichIsA("Frame")
		while not painted:HasTag("facet-tablerow") do
			painted = painted.Parent
		end
		t.expect(lane.Size.X.Offset).toBe(306)
		body.CanvasPosition = V2.new(35, 0)
		t.expect(lane.Position.X.Offset).toBe(-35)
		t.expect(painted.Position.X.Offset).toBe(35)
		t.expect(lane.Parent.ClipsDescendants).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("a touch cell wraps only at word boundaries and truncates when one word cannot fit", function()
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
		t.expect(word.Text).toBe("Neon\nStraightaway\nMMMM\nilllllll")
		t.expect(word.TextWrapped).toBe(false)
		t.expect(word.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(value.TextTruncate).toBe(engine.types.Enum.TextTruncate.AtEnd)
		word.TextFits = true
		t.expect(value.TextWrapped).toBe(true)
		word.TextFits = false
		t.expect(value.TextWrapped).toBe(false)
		assert(ctx.config.userInputService).PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		word.TextFits = true
		t.expect(value.TextWrapped).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("touch flexible columns keep the touch floor and scroll sideways instead of shrinking to nothing", function()
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
		t.expect(header.Size.X.Offset).toBe(6 * 44)
		for index = 1, 6 do
			t.expect(header:FindFirstChild(`c{index}`):FindFirstChildWhichIsA("UISizeConstraint").MinSize.X).toBe(44)
		end
		stop()
		runtime:dispose()
	end)

	t.it("the shoulder buttons move the selected rows by one slot", function()
		local w = editableWorld("Gamepad", { reorderable = true, selected = { [2] = true } }, false)
		w.pressed("MoveRowsLater")
		t.expect(w.reorders).toEqual({ { keys = { 2 }, slot = 2 } })
		w.pressed("MoveRowsEarlier")
		t.expect(w.reorders[2]).toEqual({ keys = { 2 }, slot = 0 })
		w.stop()
	end)

	t.it("a shoulder move in edit mode keeps the pad selection on the moved row", function()
		for _, list in { false, true } do
			local w = editableWorld("Gamepad", { reorderable = true, editing = Compose.cell(true) }, list)
			local hit = w.row(2):FindFirstChild("RowHit", true) or w.row(2)
			local target = if hit.Selectable then hit else hit:FindFirstChildWhichIsA("GuiButton", true)
			w.gui.SelectedObject = target
			w.pressed("MoveRowsLater")
			t.expect(#w.reorders).toBe(1)
			t.expect(w.gui.SelectedObject).toBe(target)
			w.stop()
		end
	end)

	t.it("selectionMode takes none, single or multiple and refuses anything else", function()
		local engine, runtime, UI, target = setup()
		t.expect(function()
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
		end).toThrow()
		runtime:dispose()
		local _ = engine
	end)
end)

t.describe("shared container editing", function()
	t.it("replaces plain selection and toggles only in explicit edit mode across all containers", function()
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
					body:FindFirstChild(tostring(id), true):FindFirstChild("RowHit", true).Activated.fire(input, 0)
				end
				selection:set({})
				tap(1)
				tap(2)
				t.expect(selection:peek()).toEqual({ [2] = true })
				tap(2)
				t.expect(selection:peek()).toEqual({ [2] = true })
				editing:set(true)
				tap(1)
				t.expect(selection:peek()).toEqual({ [1] = true, [2] = true })
				tap(2)
				t.expect(selection:peek()).toEqual({ [1] = true })
				editing:set(false)
				t.expect(selection:peek()).toEqual({ [1] = true })
				tap(3)
				t.expect(selection:peek()).toEqual({ [3] = true })
			end
			stop()
			runtime:dispose()
		end
	end)

	t.it("preserves hidden selection across views and prunes only deleted records", function()
		local engine, runtime, UI, target = setup()
		local all, visible, selection = Compose.cell(records(3)), Compose.cell(records(3)), Compose.cell({ [2] = true })
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
		t.expect(selection:peek()[2]).toBe(true)
		all:set({ all:peek()[1], all:peek()[3] })
		t.expect(selection:peek()[2]).toBe(nil)
		for _, stop in stops do
			stop()
		end
	end)

	t.it("keeps rejected drafts through remount and cancels to the latest model value", function()
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
			return stop, node:FindFirstChildWhichIsA("TextBox", true)
		end
		local stop, field = mount()
		field.Focused.fire()
		field.Text = "Beta"
		field.FocusLost.fire(true)
		t.expect(commits).toBe(1)
		t.expect(value:peek()).toBe("Alpha")
		t.expect(assert(draft:peek()).text).toBe("Beta")
		t.expect(assert(draft:peek()).error ~= nil).toBe(true)
		stop()
		stop, field = mount()
		t.expect(field.Text).toBe("Beta")
		value:set("Remote")
		t.expect(field.Text).toBe("Beta")
		field.Focused.fire()
		field.FocusLost.fire(false, { KeyCode = engine.types.Enum.KeyCode.Escape })
		t.expect(draft:peek()).toBe(nil)
		t.expect(field.Text).toBe("Remote")
		accept = true
		field.Focused.fire()
		field.Text = "Saved"
		field.FocusLost.fire(true)
		t.expect(value:peek()).toBe("Saved")
		t.expect(draft:peek()).toBe(nil)
		stop()
	end)

	t.it("does not save an unfinished draft when its cell is removed", function()
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
		local field = node:FindFirstChildWhichIsA("TextBox", true)
		field.Focused.fire()
		field.Text = "Unfinished"
		stop()
		t.expect(commits).toBe(0)
		t.expect(assert(draft:peek()).text).toBe("Unfinished")
	end)

	t.it("commits clamped numbers and keeps pending text until the model confirms it", function()
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
		local field = node:FindFirstChildWhichIsA("TextBox", true)
		field.Focused.fire()
		field.Text = "25"
		field.FocusLost.fire(true)
		t.expect(proposed).toBe(10)
		t.expect(value:peek()).toBe(5)
		t.expect(assert(draft:peek()).text).toBe("10")
		value:set(10)
		busy:set(false)
		t.expect(draft:peek()).toBe(nil)
		stop()
	end)

	t.it("disables swipe overlays while editing embedded controls", function()
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
					return { trailing = { { id = "delete", label = "Delete", role = "destructive" :: "destructive" } } }
				end,
			}
			return UI.VirtualList(props)
		end, target)
		local grip = list:FindFirstChild("SwipeGrip", true)
		t.expect(grip.Visible).toBe(true)
		editing:set(true)
		t.expect(grip.Visible).toBe(false)
		stop()
	end)
end)

t.describe("container presentation and shared cells", function()
	t.it("reflows minimum-width tiles as the viewport and bound size change", function()
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
		t.expect(controls.placementOf(3).offset).toBe(0)
		t.expect(controls.placementOf(4).offset > 0).toBe(true)
		grid.AbsoluteSize = engine.types.Vector2.new(320, 300)
		grid.AbsoluteWindowSize = engine.types.Vector2.new(320, 300)
		t.expect(controls.placementOf(3).offset > 0).toBe(true)
		t.expect(controls.placementOf(2).offset).toBe(0)
		minimum:set(240)
		t.expect(controls.placementOf(2).offset > 0).toBe(true)
		minimum:set(150)
		t.expect(controls.placementOf(2).offset).toBe(0)
		stop()
	end)

	t.it("keeps grid edit controls above full-width content and measures their height", function()
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
		t.expect(cells.Position).toBe(D2.fromOffset(0, 44))
		t.expect(cells.Size).toBe(D2.new(1, 0, 1, -44))
		t.expect(controls.placementOf(1).size).toBe(124)
		local handle = row:FindFirstChild("Move", true)
		t.expect(handle.Size).toBe(D2.fromOffset(44, 44))
		t.expect(handle:FindFirstChildWhichIsA("UIDragDetector").DragStyle)
			.toBe(E.UIDragDetectorDragStyle.TranslatePlane)
		t.expect(row:FindFirstChild("SelectMark", true).Position).toBe(D2.fromOffset(22, 22))
		editing:set(false)
		t.expect(cells.Position).toBe(D2.fromOffset(0, 44))
		t.expect(cells.Size).toBe(D2.new(1, 0, 1, -44))
		t.expect(controls.placementOf(1).size).toBe(124)
		t.expect(handle.Visible).toBe(false)
		stop()
		runtime:dispose()
	end)

	t.it("shares one draft between two native fields without duplicate proposals", function()
		local _, runtime, UI, target = setup()
		local value, draft, commits = Compose.cell("Alpha"), Compose.cell(nil :: FixtureCollectionTypes.CellDraft?), 0
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
			table.insert(fields, node:FindFirstChildWhichIsA("TextBox", true))
		end
		fields[1].Focused.fire()
		fields[1].Text = "Shared"
		t.expect(fields[2].Text).toBe("Shared")
		t.expect(value:peek()).toBe("Alpha")
		fields[1].FocusLost.fire(true)
		t.expect(commits).toBe(1)
		t.expect(value:peek()).toBe("Shared")
		t.expect(draft:peek()).toBe(nil)
		for _, stop in stops do
			stop()
		end
	end)

	t.it("keeps toggle and menu cells on their native controls", function()
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
		t.expect(toggle:IsA("TextButton")).toBe(true)
		toggle.Activated.fire()
		t.expect(value:peek()).toBe(true)
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
		t.expect(node:FindFirstChild("Trigger", true) ~= nil).toBe(true)
		t.expect(node:FindFirstChildWhichIsA("TextBox", true)).toBe(nil)
		stop()
	end)
end)

t.describe("input-aware collection commands", function()
	t.it("routes a shared selection delete including hidden records only through the focused collection", function()
		local engine, runtime, UI, target, gui = setup()
		local rows, selection, proposals = Compose.cell(records(3)), Compose.cell({ [2] = true, [3] = true }), {}
		local nodes, stops = {}, {}
		for index = 1, 2 do
			local stop, node: any = runtime.mount(function()
				return UI.VirtualList({
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
				} :: FixtureCollectionTypes.KeyedCollectionSpec<
					{ id: number, label: string },
					number
				>)
			end, target)
			table.insert(nodes, node)
			table.insert(stops, stop)
		end
		gui.SelectedObject = nodes[1]:FindFirstChild("2", true):FindFirstChild("RowHit", true)
		for _, child in target:GetChildren() do
			if child.Name == "FacetDeleteRows" then
				child:FindFirstChild("DeleteRows").Pressed.fire()
			end
		end
		t.expect(#proposals).toBe(1)
		t.expect(proposals[1].view).toBe(1)
		t.expect(proposals[1].keys).toEqual({ 2, 3 })
		for _, stop in stops do
			stop()
		end
	end)

	t.it("shows edit checkmarks for touch and gamepad but uses highlights on desktop", function()
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
		t.expect(mark.Visible).toBe(false)
		input.PreferredInput = engine.types.Enum.PreferredInput.Touch
		t.expect(mark.Visible).toBe(true)
		t.expect(mark:FindFirstChild("Check") ~= nil).toBe(true)
		input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
		t.expect(mark.Visible).toBe(true)
		stop()
	end)
end)

t.describe("spatial grid reordering", function()
	t.it("moves across cells and between rows for both grid directions, including a short last row", function()
		for _, horizontal in { false, true } do
			local engine, runtime, UI, target, _, ctx = setup()
			local requests = {}
			local stop, node: any = runtime.mount(function()
				local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
					from = records(8),
					key = key,
					mode = "all" :: "all",
					columns = 3,
					itemSize = 40,
					direction = if horizontal then "horizontal" :: "horizontal" else "vertical" :: "vertical",
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
				t.expect(action.Enabled).toBe(true)
				action:FindFirstChild(name).Pressed.fire()
			end
			local handle = node:FindFirstChild("1", true):FindFirstChild("Move", true)
			handle.Parent.AbsoluteSize = engine.types.Vector2.new(100, 40)
			handle.Activated.fire()
			t.expect(require("../src/ui/drag_session")(ctx).state:peek().pickupSize).toBe(handle.Parent.AbsoluteSize)
			press("ChooseDropDestination")
			t.expect(target:FindFirstChild("FacetReorderCrossLater").Enabled).toBe(false)
			press("ChooseDropDestination")
			t.expect(target:FindFirstChild("FacetReorderCrossLater").Enabled).toBe(true)
			press("ReorderCrossLater")
			press("ReorderDown")
			press("ReorderDown")
			press("ReorderDown")
			press("ReorderUp")
			press("ReorderDrop")
			t.expect(requests).toEqual({ { keys = { 1 }, slot = 4 } })
			handle.Activated.fire()
			press("ReorderCrossEarlier")
			press("ReorderUp")
			press("ReorderCancel")
			t.expect(#requests).toBe(1)
			stop()
			runtime:dispose()
		end
	end)
	t.it("uses the current column count for selected blocks and permits cancelling an all-selected grid", function()
		local engine, runtime, UI, target = setup()
		local columns = Compose.cell(3)
		local selection = Compose.cell({ [1] = true, [2] = true })
		local requests = {}
		local stop, node: any = runtime.mount(function()
			local props: FixtureCollectionTypes.KeyedCollectionSpec<{ id: number, label: string }, number> = {
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
			target:FindFirstChild("Facet" .. name):FindFirstChild(name).Pressed.fire()
		end
		node:FindFirstChild("1", true):FindFirstChild("Move", true).Activated.fire()
		columns:set(2)
		press("ReorderDown")
		press("ReorderDrop")
		t.expect(requests).toEqual({ { keys = { 1, 2 }, slot = 2 } })
		selection:set({ [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true })
		node:FindFirstChild("1", true):FindFirstChild("Move", true).Activated.fire()
		press("ReorderDown")
		press("ReorderCrossLater")
		press("ReorderCancel")
		t.expect(#requests).toBe(1)
		stop()
		runtime:dispose()
	end)
end)

t.describe("collection transfer sessions", function()
	t.it("keyboard pickup carries selected hidden items and calls the source lifecycle once", function()
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
							t.expect(mode).toBe("armed")
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
		hit.Activated.fire({
			UserInputType = engine.types.Enum.UserInputType.Keyboard,
			KeyCode = engine.types.Enum.KeyCode.Return,
		})
		t.expect(carried).toEqual({ 1, 2 })
		t.expect(node:FindFirstChild("FacetDropOutline")).toBe(nil)
		t.expect(node:FindFirstChild("DropLine", true).Visible).toBe(false)
		t.expect(starts).toBe(1)
		require("../src/ui/drag_session")(ctx).finish(false)
		t.expect(ends).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("rebases pending insertion against surviving neighbors and rejects removed neighbors", function()
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
		t.expect(pending.insertion.beforeKey).toBe(2)
		local changed = records(3)
		table.insert(changed, 1, { id = 4, label = "New" })
		rows:set(changed)
		t.expect(pending.complete(true)).toBe(true)
		t.expect(pending.insertion.slot).toBe(2)
		t.expect(pending.complete(true)).toBe(false)
		rows:set(records(3))
		drop()
		rows:set({ { id = 3, label = "Only survivor" } })
		t.expect(pending.complete(true)).toBe(false)
		stop()
		runtime:dispose()
	end)
end)

t.describe("native collection detector taps", function()
	t.it("selects a frame-backed card before and after a drag without selecting on the drop", function()
		for _, kind in { "VirtualGrid", "VirtualList" } do
			local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
			local E, V2, V3 = engine.types.Enum, engine.types.Vector2, engine.types.Vector3
			local selection = Compose.cell({})
			local stop, list: any = runtime.mount(function()
				return UI[kind] {
					from = records(3),
					key = key,
					mode = "all" :: "all",
					selection = selection,
					reorderable = true,
					onReorder = function() end,
					render = function(): GuiObject
						return ((runtime.constructors.Frame :: unknown) :: FrameConstructor) { Name = "Card" }
					end,
				}
			end, target)
			local input: any = assert(ctx.config.userInputService)
			local press = { UserInputType = E.UserInputType.MouseButton1, Position = V3.new(20, 20, 0) }
			local function tap(id: number, cancelled: boolean?)
				press.UserInputState = E.UserInputState.Begin
				input.InputBegan.fire(press)
				local card = list:FindFirstChild(tostring(id), true):FindFirstChild("Card", true)
				card.InputBegan.fire(press)
				local detector = card:FindFirstChild("FacetCollectionDrag")
				detector.DragStart.fire(V2.new(20, 20))
				press.UserInputState = if cancelled then E.UserInputState.Cancel else E.UserInputState.End
				input.InputEnded.fire(press)
				detector.DragEnd.fire()
			end
			tap(1)
			t.expect(selection:peek()).toEqual({ [1] = true })
			local card = list:FindFirstChild("1", true):FindFirstChild("Card", true)
			press.UserInputState = E.UserInputState.Begin
			input.InputBegan.fire(press)
			card.InputBegan.fire(press)
			local detector = card:FindFirstChild("FacetCollectionDrag")
			detector.DragStart.fire(V2.new(20, 20))
			detector.DragContinue.fire(V2.new(20, 140))
			press.UserInputState = E.UserInputState.End
			input.InputEnded.fire(press)
			detector.DragEnd.fire()
			t.expect(selection:peek()).toEqual({ [1] = true })
			tap(2)
			t.expect(selection:peek()).toEqual({ [2] = true })
			tap(3, true)
			t.expect(selection:peek()).toEqual({ [2] = true })
			stop()
			runtime:dispose()
		end
	end)
end)
