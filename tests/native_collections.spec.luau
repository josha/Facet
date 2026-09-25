--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local context = require("../src/ui/context")
local registerInputs = require("../src/ui/inputs")
local registerCollections = require("../src/ui/collections")
local registerRowActions = require("../src/ui/collection_row_actions")
local registerTable = require("../src/ui/collection_table")
local engineLib = require("./lib/native_engine")

local function setup(options)
	local engine = engineLib.new(options and options.engine)
	if options and options.clock then
		engine.clock = options.clock
	end
	local runtime = Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local root = engine.new("ScreenGui")
	local config = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui },
		inputParent = root,
		reducedMotion = true,
	}
	for field, value in options or {} do
		if field ~= "engine" then
			config[field] = value
		end
	end
	if config.userInputService and config.userInputService.GetPropertyChangedSignal == nil then
		local service = engine.new("UserInputService")
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
	local ctx = context(Compose, runtime, config)
	local UI = {}
	registerInputs(ctx, UI)
	local surfaces = require("../src/ui/nav_modal")(ctx)
	require("../src/ui/nav_menu")(ctx, UI, surfaces)
	require("../src/ui/nav_surfaces")(ctx, UI, surfaces)
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

local function key(item)
	return item.id
end

local function button(UI, current)
	return UI.Button "Action" {
		label = function(use)
			return use(current).label
		end,
	}
end

t.describe("Compose native collections", function()
	t.it("reuses row containers, replaces reactive items and anchors native scrolling", function()
		local engine, runtime, UI, target = setup()
		local rows = records(100)
		local source, status =
			Compose.cell(rows), Compose.cell({
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
		local rendered, disposed = 0, 0
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 20,
				overscan = 0,
				status = status,
				render = function(current)
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
		local stopList, list = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = "id",
				itemSize = 20,
				render = function(current, _placement, rowKey)
					table.insert(keys, rowKey)
					return button(UI, current)
				end,
			})
		end, target)
		list.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		t.expect(list:FindFirstChild("7", true) ~= nil).toBe(true)
		t.expect(keys[1]).toBe("7")
		stopList()
		local stopTable, tableNode = runtime.mount(function()
			return UI.Table({
				from = source,
				key = "id",
				columns = {
					{
						id = "label",
						label = "Name",
						render = function(current)
							return button(UI, current)
						end,
					},
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
					render = function(current)
						return button(UI, current)
					end,
				})
			end, target)
			stopBad()
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "key must be a function or a field name", 1, true) ~= nil).toBe(true)
		runtime:dispose()
	end)

	t.it("defers initial offscreen focus until native geometry and suppresses navigation while editing", function()
		local engine, runtime, UI, target, gui = setup()
		local focus = {}
		local stop, node = runtime.mount(function()
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
				render = function(current)
					return runtime.constructors.TextBox "Editor" {
						Text = function(use)
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
		t.expect(focus.current:peek()).toBe(50)
		gui.SelectedObject:ReleaseFocus()
		down.Pressed.fire()
		t.expect(focus.current:peek()).toBe(52)
		t.expect(gui.SelectedObject.Text).toBe("52")
		stop()
		runtime:dispose()
	end)

	t.it("wraps arrow and D-pad focus at both ends when wrapFocus is set", function()
		for _, wrap in { true, false } do
			local engine, runtime, UI, target, gui = setup()
			local focus = {}
			local stop, node = runtime.mount(function()
				return UI.VirtualList({
					from = records(5),
					key = key,
					itemSize = 20,
					focus = focus,
					wrapFocus = wrap,
					render = function(current)
						return button(UI, current)
					end,
				})
			end, target)
			node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
			focus.focus(5)
			t.expect(gui.SelectedObject.Text).toBe("5")
			target:FindFirstChild("FacetCollectionDown"):FindFirstChild("CollectionDown").Pressed.fire()
			t.expect(focus.current:peek()).toBe(if wrap then 1 else 5)
			focus.focus(1)
			target:FindFirstChild("FacetCollectionUp"):FindFirstChild("CollectionUp").Pressed.fire()
			t.expect(focus.current:peek()).toBe(if wrap then 5 else 1)
			target:FindFirstChild("FacetCollectionRight"):FindFirstChild("CollectionRight").Pressed.fire()
			t.expect(focus.current:peek()).toBe(if wrap then 5 else 1)
			stop()
			runtime:dispose()
		end
	end)

	t.it("uses measured extents and column placements for both scroll directions", function()
		for _, direction in { "vertical", "horizontal" } do
			local engine, runtime, UI, target = setup()
			local measured, columns, gap = Compose.cell({ [1] = 60 }), Compose.cell(2), Compose.cell(5)
			local controls, status =
				{}, Compose.cell({
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
			local stop, node = runtime.mount(function()
				return UI.VirtualGrid({
					from = records(10),
					key = key,
					columns = columns,
					direction = direction,
					measured = measured,
					itemSize = 20,
					gap = gap,
					crossGap = 10,
					overscan = 0,
					status = status,
					controls = controls,
					render = function(current)
						return button(UI, current)
					end,
				})
			end, target)
			node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
			t.expect(controls.placementOf(3).offset).toBe(65)
			t.expect(status:peek().extent).toBe(160)
			measured:set({ [1] = 40 })
			t.expect(controls.placementOf(3).offset).toBe(45)
			columns:set(1)
			t.expect(controls.placementOf(2).offset).toBe(45)
			local second = node:FindFirstChild("2", true)
			t.expect(if direction == "horizontal" then second.Position.X.Offset else second.Position.Y.Offset).toBe(45)
			gap:set(9)
			t.expect(controls.placementOf(2).offset).toBe(49)
			t.expect(node:FindFirstChild("2", true)).toBe(second)
			stop()
			runtime:dispose()
		end
	end)

	t.it("observes automatic row sizes without overwriting content geometry", function()
		local engine, runtime, UI, target = setup()
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
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(5),
				key = key,
				itemSize = 20,
				measure = true,
				status = status,
				render = function()
					return runtime.constructors.Frame "Measured" {
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

	t.it("measures a row at its unscaled size while a lift scale grows it", function()
		local engine, runtime, UI, target = setup()
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
		local lift = Compose.cell(1)
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(5),
				key = key,
				itemSize = 20,
				measure = true,
				status = status,
				render = function()
					return runtime.constructors.Frame "Measured" {
						AutomaticSize = engine.types.Enum.AutomaticSize.Y,
						Size = engine.types.UDim2.new(1, 0, 0, 0),
						runtime.constructors.UIScale({ Name = "Lift", Scale = lift }),
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

	t.it("follows a readable follow policy while the viewport stays at the end", function()
		local engine, runtime, UI, target = setup()
		local source, follow = Compose.cell(records(10)), Compose.cell("none")
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 20,
				overscan = 0,
				follow = follow,
				render = function(current)
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
					render = function(current)
						return button(UI, current)
					end,
				})
			end, target)
		end).toThrow()
		runtime:dispose()
	end)

	t.it("follows appended rows only while native viewport stays at the end", function()
		local engine, runtime, UI, target = setup()
		local source, status =
			Compose.cell(records(10)), Compose.cell({
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
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 20,
				overscan = 0,
				follow = "end",
				status = status,
				render = function(current)
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
		local focus = {}
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(100),
				key = key,
				itemSize = 20,
				overscan = 0,
				focus = focus,
				render = function(current)
					return button(UI, current)
				end,
			})
		end, target)
		node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		focus.focus(50)
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
		local focus = {}
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(100),
				key = key,
				itemSize = 20,
				overscan = 0,
				focus = focus,
				render = function(current)
					return button(UI, current)
				end,
			})
		end, target)
		node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		t.expect(pcall(focus.focus, 50)).toBe(true)
		t.expect(gui.SelectedObject).toBeNil()
		target.Parent = engine.new("PlayerGui")
		focus.focus(51)
		t.expect(gui.SelectedObject.Text).toBe("51")
		stop()
		runtime:dispose()
	end)

	t.it("keeps table cells alive across sort and native column resize and prunes selection", function()
		local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
		local source = Compose.cell({ { id = 1, label = "Z" }, { id = 2, label = "A" } })
		local sort, widths, selection = Compose.cell(nil), Compose.cell({}), Compose.cell({ [1] = true })
		local builds = 0
		local stop, node = runtime.mount(function()
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
						render = function(current)
							builds += 1
							return button(UI, current)
						end,
					},
				},
			})
		end, target)
		local body, header = node:FindFirstChild("Body"), node:FindFirstChild("Header")
		body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		local original = body:FindFirstChild("1", true):FindFirstChild("Action", true)
		local column = header:FindFirstChild("label")
		column:FindFirstChild("Sort").Activated.fire()
		t.expect(sort:peek()).toEqual({ column = "label", direction = "ascending" })
		t.expect(body:FindFirstChild("1", true):FindFirstChild("Action", true)).toBe(original)
		column.AbsoluteSize = engine.types.Vector2.new(100, 40)
		local grip = column:FindFirstChild("Resize")
		t.expect(grip.AnchorPoint).toBe(engine.types.Vector2.new(1, 0))
		t.expect(grip.Position).toBe(engine.types.UDim2.fromScale(1, 0))
		t.expect(grip.Size.X.Offset).toBe(12)
		t.expect(header.Size.Y.Offset).toBe(40)
		ctx.config.userInputService.PreferredInput = engine.types.Enum.PreferredInput.Touch
		t.expect(grip.Size.X.Offset).toBe(44)
		t.expect(header.Size.Y.Offset).toBe(44)
		ctx.config.userInputService.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(grip.Size.X.Offset).toBe(12)
		t.expect(header.Size.Y.Offset).toBe(40)
		local detector = column:FindFirstChildWhichIsA("UIDragDetector", true)
		detector.DragStart.fire(engine.types.Vector2.new(100, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(180, 10))
		t.expect(widths:peek().label).toBe(160)
		column:FindFirstChild("Resize").SelectionGained.fire()
		target:FindFirstChild("FacetNarrowColumn"):FindFirstChild("NarrowColumn").Pressed.fire()
		t.expect(widths:peek().label).toBe(152)
		t.expect(builds).toBe(2)
		source:set({ { id = 2, label = "A" } })
		t.expect(selection:peek()[1]).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("uses native drag to reveal and invoke row actions with cancellation and coordination", function()
		local engine, runtime, UI, target = setup()
		local open, coordinator = Compose.cell(nil), Compose.cell(nil)
		local invoked = 0
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				open = open,
				coordinator = coordinator,
				fullSwipe = true,
				content = button(UI, Compose.cell({ label = "Row" })),
				trailing = {
					{
						id = "Delete",
						label = "Delete",
						onActivate = function()
							invoked += 1
						end,
					},
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
		local open, activated = Compose.cell(nil), 0
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				open = open,
				content = UI.Button "Mail" {
					label = "Mail",
					onActivate = function()
						activated += 1
					end,
				},
				trailing = { { id = "Delete", label = "Delete", onActivate = function() end } },
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
		local open, activated = Compose.cell(nil), 0
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				open = open,
				content = UI.Button "Mail" {
					label = "Mail",
					onActivate = function()
						activated += 1
					end,
				},
				trailing = { { id = "Delete", label = "Delete", onActivate = function() end } },
			})
		end, target)
		node.AbsoluteSize = V2.new(300, 40)
		local grip = node:FindFirstChild("SwipeGrip", true)
		local detector = grip:FindFirstChildWhichIsA("UIDragDetector")
		t.expect(detector.Enabled).toBe(true)
		ctx.config.userInputService.PreferredInput = E.PreferredInput.Touch
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
		local stop, node = runtime.mount(function()
			return UI.Table({
				from = records(100),
				key = key,
				selection = selected,
				selectionMode = "multi",
				itemSize = 20,
				overscan = 0,
				selectable = function(item)
					return item.id ~= 4
				end,
				disabled = function(item)
					return item.id == 5
				end,
				columns = { { id = "label", label = "Label" } },
			})
		end, target)
		local body = node:FindFirstChild("Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(200, 60)
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
		local stop, node = runtime.mount(function()
			return UI.Table({
				from = source,
				key = key,
				selection = selected,
				selectionMode = "multi",
				itemSize = 20,
				reorderable = true,
				movable = function(item)
					return item.id ~= 4
				end,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end, target)
		local body = node:FindFirstChild("Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
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

	t.it("commits a destructive action once after Compose departure and cancels on disposal", function()
		local engine, runtime, UI, target = setup({ reducedMotion = false })
		local invoked = 0
		local function mount()
			return runtime.mount(function()
				return UI.RowActions({
					open = Compose.cell("trailing"),
					content = button(UI, Compose.cell({ label = "Row" })),
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
			end, target)
		end
		local stop, node = mount()
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
		local cancel, pending = mount()
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
		local invoked, open = 0, Compose.cell(nil)
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				open = open,
				content = button(UI, Compose.cell({ label = "Row" })),
				trailing = {
					{
						id = "Archive",
						label = "Archive",
						onActivate = function()
							invoked += 1
						end,
					},
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
		local invoked, open = 0, Compose.cell("trailing")
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				open = open,
				reducedMotion = true,
				content = button(UI, Compose.cell({ label = "Row" })),
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
		local editing, open = Compose.cell(false), Compose.cell(nil)
		local invoked = 0
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				content = button(UI, Compose.cell({ label = "Row" })),
				editing = editing,
				open = open,
				fullSwipe = { trailing = false },
				trailing = {
					{
						id = "Erase",
						label = "Delete",
						role = "destructive",
						onActivate = function()
							invoked += 1
						end,
					},
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
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				content = button(UI, Compose.cell({ label = "Row" })),
				leading = {
					{
						id = "Read",
						label = "Read",
						onActivate = function()
							invoked += 1
						end,
					},
				},
				trailing = {
					{
						id = "Save",
						label = "Save",
						onActivate = function()
							invoked += 1
						end,
					},
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
		node.InputBegan.fire({ UserInputType = engine.types.Enum.UserInputType.MouseButton2 })
		target:FindFirstChild("leading:Read", true).Activated.fire()
		t.expect(invoked).toBe(1)
		t.expect(target:FindFirstChild("MenuPanel", true)).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("lets domain callbacks reject table selection, sorting and resize requests", function()
		local engine, runtime, UI, target = setup()
		local selection, sort, widths = Compose.cell({}), Compose.cell(nil), Compose.cell({})
		local requests = 0
		local stop, node = runtime.mount(function()
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
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end, target)
		local body = node:FindFirstChild("Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
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
		local stop, node = runtime.mount(function()
			return UI.Table({
				from = { { id = 1, first = "One", second = "Two", third = "Full hidden value" } },
				key = key,
				scrolls = false,
				itemSize = 40,
				columns = {
					{ id = "first", width = 100 },
					{ id = "second", width = 100 },
					{
						id = "third",
						label = "Third",
						width = 100,
						priority = 3,
						render = function()
							builds += 1
							return runtime.constructors.TextBox({ Text = "Local edit" })
						end,
					},
				},
			})
		end, target)
		local body = node:FindFirstChild("Body")
		t.expect(body.ScrollingEnabled).toBe(false)
		t.expect(node.Size.Y.Offset).toBe(80)
		local row = body:FindFirstChild("1", true)
		local cell = row:FindFirstChild("third", true)
		body.AbsoluteWindowSize = engine.types.Vector2.new(250, 40)
		t.expect(cell.Visible).toBe(false)
		local menu = row:FindFirstChild("Details", true)
		menu.Activated.fire()
		local fullValue = target:FindFirstChild("Expanded", true):FindFirstChild("third", true)
		t.expect(fullValue ~= nil).toBe(true)
		body.AbsoluteWindowSize = engine.types.Vector2.new(400, 40)
		t.expect(row:FindFirstChild("third", true)).toBe(cell)
		t.expect(cell.Visible).toBe(true)
		t.expect(builds).toBe(1)
		stop()
		runtime:dispose()
	end)

	t.it("uses new grid neighbors when responsive columns change without changing total extent", function()
		local engine, runtime, UI, target = setup()
		local columns, focus = Compose.cell(4), {}
		local stop, node = runtime.mount(function()
			return UI.VirtualGrid({
				from = records(12),
				key = key,
				itemSize = 20,
				columns = columns,
				focus = focus,
				render = function(current)
					return button(UI, current)
				end,
			})
		end, target)
		node.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		focus.focus(2)
		columns:set(5)
		focus.move("down")
		t.expect(focus.current:peek()).toBe(7)
		stop()
		runtime:dispose()
	end)

	t.it("drops removed measurements and refreshes current-item row actions under stable keys", function()
		local engine, runtime, UI, target = setup()
		local source, status =
			Compose.cell(records(2)), Compose.cell({
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
		local invoked = ""
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 20,
				status = status,
				measure = true,
				render = function(current)
					return UI.RowActions({
						open = Compose.cell("trailing"),
						content = button(UI, current),
						trailing = function(use)
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
		local enabled, open, invoked = Compose.cell(true), Compose.cell(nil), 0
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				content = button(UI, Compose.cell({ label = "Row" })),
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
					},
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
		local controls = {}
		local stop, node = runtime.mount(function()
			return UI.Table({
				from = records(2),
				key = key,
				controls = controls,
				columns = { { id = "label", label = "Label" } },
			})
		end, target)
		local body = node:FindFirstChild("Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
		local row = body:FindFirstChild("1", true)
		t.expect(controls.placementOf(2).offset).toBe(40)
		row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 60)
		t.expect(controls.placementOf(2).offset).toBe(76)
		node:FindFirstChild("Sort", true).TextBounds = engine.types.Vector2.new(100, 70)
		t.expect(body.Position.Y.Offset).toBe(86)
		ctx.config.userInputService.PreferredInput = engine.types.Enum.PreferredInput.Touch
		row:FindFirstChild("Value", true).TextBounds = engine.types.Vector2.new(100, 8)
		t.expect(controls.placementOf(2).offset).toBe(44)
		t.expect(body:FindFirstChild("1", true)).toBe(row)
		node:FindFirstChild("Sort", true).TextBounds = engine.types.Vector2.new(100, 20)
		t.expect(body.Position.Y.Offset).toBe(44)
		stop()
		runtime:dispose()
	end)
	t.it("measures localized row action labels and reveals truncated visible table values", function()
		local engine, runtime, UI, target = setup()
		local open, editing = Compose.cell("trailing"), Compose.cell(true)
		local stopActions, actions = runtime.mount(function()
			return UI.RowActions({
				content = button(UI, Compose.cell({ label = "Row" })),
				open = open,
				editing = editing,
				trailing = { { id = "Remove", label = "Localized destructive action", role = "destructive" } },
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
		local stop, node = runtime.mount(function()
			return UI.Table({ from = source, key = key, columns = { { id = "label", label = "Label", width = 180 } } })
		end, target)
		local body = node:FindFirstChild("Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(250, 100)
		local row = body:FindFirstChild("1", true)
		local value = row:FindFirstChild("Value", true)
		t.expect(row:FindFirstChild("Details", true)).toBeNil()
		value.TextFits = false
		row:FindFirstChild("Details", true).Activated.fire()
		local expanded = target:FindFirstChild("Expanded", true)
		t.expect(expanded:FindFirstChild("FullValue", true).Text).toBe("Long value that should be disclosed")
		source:set({ { id = 1, label = "Updated entire value" } })
		t.expect(expanded:FindFirstChild("FullValue", true).Text).toBe("Updated entire value")
		value.TextFits = true
		t.expect(target:FindFirstChild("Expanded", true)).toBeNil()
		t.expect(body:FindFirstChild("1", true)).toBe(row)
		stop()
		runtime:dispose()
	end)

	t.it("keeps native reorder capture and keyboard drop alive across offscreen autoscroll", function()
		local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
		local requests = {}
		local stop, node = runtime.mount(function()
			return UI.Table({
				from = records(100),
				key = key,
				itemSize = 20,
				overscan = 0,
				reorderable = true,
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				columns = { { id = "label", label = "Label", width = 100 } },
			})
		end, target)
		local body = node:FindFirstChild("Body")
		body.AbsoluteWindowSize = engine.types.Vector2.new(200, 100)
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
		ctx.config.userInputService.InputChanged.fire({
			UserInputType = engine.types.Enum.UserInputType.MouseMovement,
			Position = engine.types.Vector3.new(10, 80, 0),
		})
		ctx.config.userInputService.InputEnded.fire(input)
		t.expect(#requests).toBe(1)
		t.expect(requests[1].keys).toEqual({ 1 })
		t.expect(requests[1].slot > 10).toBe(true)
		body.CanvasPosition = engine.types.Vector2.zero
		handle = body:FindFirstChild("1", true):FindFirstChild("Move", true)
		handle.Activated.fire()
		t.expect(gui.SelectedObject.Name).toBe("Drop")
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
		ctx.config.userInputService.InputEnded.fire(input)
		t.expect(#requests).toBe(2)
		stop()
		runtime:dispose()
	end)
	t.it("shares list selection and reorder policies and fails closed for protected rows", function()
		local engine, runtime, UI, target = setup()
		local selected, requests = Compose.cell({}), {}
		local source = Compose.cell(records(4))
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 20,
				overscan = 0,
				selection = selected,
				selectionMode = "multi",
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
				onReorder = function(keys, slot)
					table.insert(requests, { keys = keys, slot = slot })
				end,
				render = function(current)
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
			reducedMotion = false,
		})
		local function advance(seconds)
			for _ = 1, math.ceil(seconds * 60) do
				now += 1 / 60
				engine.heartbeat.fire(1 / 60)
			end
		end
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = records(20),
				key = key,
				itemSize = 40,
				snap = "item",
				render = function(current)
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
		local stopMeasured, measured = runtime.mount(function()
			return UI.VirtualList({
				from = records(20),
				key = key,
				itemSize = 20,
				measured = { [1] = 35 },
				snap = "item",
				reducedMotion = true,
				render = function(current)
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
		local stopGrid, grid = runtime.mount(function()
			return UI.VirtualGrid({
				from = records(20),
				key = key,
				itemSize = 40,
				columns = 2,
				direction = "horizontal",
				snap = "item",
				reducedMotion = true,
				render = function(current)
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
		local stopLarge, large = runtime.mount(function()
			return UI.VirtualList({
				from = records(5),
				key = key,
				itemSize = 120,
				snap = "item",
				reducedMotion = true,
				render = function(current)
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
	t.it("cancels native row gestures and keeps destructive opt-outs behind every action route", function()
		local engine, runtime, UI, target, gui, ctx = setup({ userInputService = {} })
		local enabled, open, invoked = Compose.cell(false), Compose.cell(nil), 0
		local stop, node = runtime.mount(function()
			return UI.RowActions({
				content = button(UI, Compose.cell({ label = "Protected" })),
				open = open,
				editing = Compose.cell(true),
				trailing = {
					{
						id = "Remove",
						label = "Remove",
						role = "destructive",
						enabled = enabled,
						onActivate = function()
							invoked += 1
						end,
					},
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
		ctx.config.userInputService.InputChanged.fire(pointer)
		detector.DragEnd.fire()
		t.expect(invoked).toBe(0)
		t.expect(open:peek()).toBeNil()
		stop()
		runtime:dispose()
	end)
	t.it("enters native focus after unfocused collection churn and reaches offscreen keys", function()
		local engine, runtime, UI, target, gui = setup()
		local source = Compose.cell(records(100))
		local stop, node = runtime.mount(function()
			return UI.VirtualList({
				from = source,
				key = key,
				itemSize = 20,
				overscan = 0,
				disabled = function(item)
					return item.id == 2
				end,
				render = function(current)
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
