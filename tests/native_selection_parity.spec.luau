--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	type World = {
		engine: any,
		runtime: any,
		gui: any,
		input: any,
		screen: any,
		parent: any,
		shift: { down: boolean },
		stop: () -> (),
	}

	local function setup(build: (any, any, any, any) -> any): World
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local input = engine.new("UserInputService")
		local shift = { down = false }
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function(_, key)
			return shift.down and key == engine.types.Enum.KeyCode.LeftShift
		end
		local parent = engine.new("Folder")
		local UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = gui,
				inputParent = parent,
				services = { GuiService = gui, UserInputService = input },
			} :: any
		)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine, gui) })
		end, parent)
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			screen = screen,
			parent = parent,
			shift = shift,
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
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				return node:FindFirstChild(name)
			end
		end
		return nil
	end

	local function press(world: World, key: string)
		world.input.InputBegan.fire({
			KeyCode = (world.engine.types.Enum.KeyCode :: any)[key],
			UserInputType = world.engine.types.Enum.UserInputType.Gamepad1,
		}, true)
	end

	local function tab(world: World, back: boolean?)
		world.shift.down = back == true
		local traverse = find(world.parent, "FacetTraversal")
		assert(traverse, "the traversal context exists")
		traverse:FindFirstChild("Traverse").Pressed.fire()
		world.shift.down = false
	end

	local function selected(world: World): string
		local node = world.gui.SelectedObject
		return if node then node.Name else "nil"
	end

	local function form(UI: any, Host: any, E: any, shown: any?, order: any?)
		return Host.Frame("Form")({
			Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
			UI.Button("Music")({ label = "Music", LayoutOrder = 1 }),
			Compose.show(shown or function()
				return true
			end, function()
				return UI.Button("Sfx")({ label = "Sfx", LayoutOrder = 2 })
			end),
			UI.Button("Haptics")({
				label = "Haptics",
				LayoutOrder = if order
					then function(use: Use)
						return use(order)
					end
					else 3,
			}),
			UI.Button("Save")({ label = "Save", LayoutOrder = 4 }),
		})
	end

	verifyHarness:suite("native selection parity with the main focus graph", function()
		verifyHarness:case(
			"enters the screen at its first control on the first D-pad press and never moves a live selection",
			{
				id = "native_selection_parity::native selection parity with the main focus graph::enters the screen at its first control on the first D-pad press and never moves a live selection",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						return form(UI, Host, engine.types.Enum)
					end)
					Verify.expect(world.gui.SelectedObject):toBe(nil)
					press(world, "DPadDown")
					Verify.expect((selected(world))):toBe("Music")
					world.gui.SelectedObject = find(world.screen, "Save")
					press(world, "DPadUp")
					Verify.expect((selected(world))):toBe("Save")
					world.gui.SelectedObject = nil
					press(world, "ButtonA")
					Verify.expect(world.gui.SelectedObject):toBe(nil)
					world.stop()
				end,
			}
		)

		verifyHarness:case("enters at the first eligible control and inside an open modal", {
			id = "native_selection_parity::native selection parity with the main focus graph::enters at the first eligible control and inside an open modal",
			run = function()
				local presented, enabled = Compose.cell(false), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame("Screen")({
						UI.Button("Off")({ label = "Off", enabled = enabled }) :: unknown,
						UI.Button("On")({ label = "On" }),
						UI.Alert({
							isPresented = presented,
							title = "Leave race?",
							actions = {
								{ id = "stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				press(world, "DPadRight")
				Verify.expect((selected(world))):toBe("On")
				world.gui.SelectedObject = nil
				presented:set(true)
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				press(world, "DPadDown")
				Verify.expect((selected(world))):toBe("stay")
				world.stop()
			end,
		})

		verifyHarness:case("walks Tab forward and Shift+Tab back in layout order and wraps at both ends", {
			id = "native_selection_parity::native selection parity with the main focus graph::walks Tab forward and Shift+Tab back in layout order and wraps at both ends",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return form(UI, Host, engine.types.Enum)
				end)
				tab(world)
				Verify.expect((selected(world))):toBe("Music")
				tab(world)
				Verify.expect((selected(world))):toBe("Sfx")
				tab(world)
				tab(world)
				Verify.expect((selected(world))):toBe("Save")
				tab(world)
				Verify.expect((selected(world))):toBe("Music")
				tab(world, true)
				Verify.expect((selected(world))):toBe("Save")
				tab(world, true)
				Verify.expect((selected(world))):toBe("Haptics")
				world.gui.SelectedObject = nil
				tab(world, true)
				Verify.expect((selected(world))):toBe("Save")
				world.stop()
			end,
		})

		verifyHarness:case("skips hidden, disabled and removed controls and rereads the order on the next press", {
			id = "native_selection_parity::native selection parity with the main focus graph::skips hidden, disabled and removed controls and rereads the order on the next press",
			run = function()
				local shown, order = Compose.cell(true), Compose.cell(3)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return form(UI, Host, engine.types.Enum, shown, order)
				end)
				find(world.screen, "Haptics").Visible = false
				world.gui.SelectedObject = find(world.screen, "Music")
				tab(world)
				Verify.expect((selected(world))):toBe("Sfx")
				tab(world)
				Verify.expect((selected(world))):toBe("Save")
				find(world.screen, "Haptics").Visible = true
				shown:set(false)
				world.gui.SelectedObject = find(world.screen, "Music")
				tab(world)
				Verify.expect((selected(world))):toBe("Haptics")
				order:set(0)
				world.gui.SelectedObject = find(world.screen, "Music")
				tab(world, true)
				Verify.expect((selected(world))):toBe("Haptics")
				world.stop()
			end,
		})

		verifyHarness:case("traps Tab inside a modal and restores the launching control when it closes", {
			id = "native_selection_parity::native selection parity with the main focus graph::traps Tab inside a modal and restores the launching control when it closes",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame("Screen")({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						UI.Alert({
							isPresented = presented,
							title = "Replace this save?",
							actions = {
								{ id = "keep", label = "Keep", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "replace", label = "Replace", role = "destructive" :: "destructive" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				presented:set(true)
				local seen = { selected(world) }
				for _ = 1, 4 do
					tab(world)
					table.insert(seen, selected(world))
				end
				Verify.expect((table.find(seen, "Opener"))):toBe(nil)
				Verify.expect(table.find(seen, "keep") ~= nil and table.find(seen, "replace") ~= nil):toBe(true)
				presented:set(false)
				Verify.expect((selected(world))):toBe("Opener")
				world.stop()
			end,
		})

		verifyHarness:case("falls to the nearest surviving neighbour when the selected control is removed", {
			id = "native_selection_parity::native selection parity with the main focus graph::falls to the nearest surviving neighbour when the selected control is removed",
			run = function()
				local shown = Compose.cell(true)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return form(UI, Host, engine.types.Enum, shown)
				end)
				world.gui.SelectedObject = find(world.screen, "Sfx")
				shown:set(false)
				Verify.expect((selected(world))):toBe("Haptics")
				find(world.screen, "Save").Visible = false
				Verify.expect((selected(world))):toBe("Haptics")
				world.gui.SelectedObject = find(world.screen, "Music")
				world.gui.SelectedObject = nil
				Verify.expect(world.gui.SelectedObject):toBe(nil)
				world.stop()
				local last = Compose.cell(true)
				local tail = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return Host.Frame("Row")({
						Host.UIListLayout({ SortOrder = engine.types.Enum.SortOrder.LayoutOrder }) :: unknown,
						UI.Button("First")({ label = "First", LayoutOrder = 1 }),
						Compose.show(last, function()
							return UI.Button("Last")({ label = "Last", LayoutOrder = 2 })
						end),
					})
				end)
				tail.gui.SelectedObject = find(tail.screen, "Last")
				last:set(false)
				Verify.expect((selected(tail))):toBe("First")
				tail.stop()
			end,
		})

		verifyHarness:case("moves a removed collection row's selection to the following key, then the preceding one", {
			id = "native_selection_parity::native selection parity with the main focus graph::moves a removed collection row's selection to the following key, then the preceding one",
			run = function()
				local rows = Compose.cell({ { id = "r1" }, { id = "r2" }, { id = "r3" }, { id = "r4" } })
				local world = setup(function(UI: FacetControls)
					return UI.VirtualList("Rows")({
						from = rows,
						key = function(item)
							return item.id
						end,
						itemSize = 20,
						render = function(current): GuiObject
							return UI.Button("Row")({
								label = function(use: Use)
									return use(current).id
								end,
							})
						end,
					})
				end)
				local list = find(world.screen, "Rows")
				list.AbsoluteWindowSize = world.engine.types.Vector2.new(200, 200)
				local function row(key: string): any
					return find(find(list, key), "Row")
				end
				local target = row("r2")
				world.gui.SelectedObject = target
				target.SelectionGained.fire()
				rows:set({ { id = "r1" }, { id = "r3" }, { id = "r4" } })
				Verify.expect(world.gui.SelectedObject):toBe(row("r3"))
				target = row("r4")
				world.gui.SelectedObject = target
				target.SelectionGained.fire()
				rows:set({ { id = "r1" }, { id = "r3" } })
				Verify.expect(world.gui.SelectedObject):toBe(row("r3"))
				world.stop()
			end,
		})

		verifyHarness:case("takes the selection back from an engine fallback when the selected row's key is removed", {
			id = "native_selection_parity::native selection parity with the main focus graph::takes the selection back from an engine fallback when the selected row's key is removed",
			run = function()
				local rows = Compose.cell({ { id = "r1" }, { id = "r2" }, { id = "r3" } })
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Toolbar")({ label = "Jump" }) :: unknown,
						UI.VirtualList("Rows")({
							from = rows,
							key = function(item)
								return item.id
							end,
							itemSize = 20,
							render = function(current): GuiObject
								return UI.Button("Row")({
									label = function(use: Use)
										return use(current).id
									end,
								})
							end,
						}),
					})
				end)
				local list = find(world.screen, "Rows")
				list.AbsoluteWindowSize = world.engine.types.Vector2.new(200, 200)
				local target = find(find(list, "r2"), "Row")
				world.gui.SelectedObject = target
				target.SelectionGained.fire()
				local toolbar = find(world.screen, "Toolbar")
				target.Destroying:Connect(function()
					world.gui.SelectedObject = toolbar
				end)
				rows:set({ { id = "r1" }, { id = "r3" } })
				Verify.expect(world.gui.SelectedObject):toBe(find(find(list, "r3"), "Row"))
				world.stop()
			end,
		})

		verifyHarness:case("adjusts a selected slider with the D-pad while the other axis still navigates", {
			id = "native_selection_parity::native selection parity with the main focus graph::adjusts a selected slider with the D-pad while the other axis still navigates",
			run = function()
				local value = Compose.cell(0.5)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Slider("Volume")({ value = value, step = 0.1 }) :: unknown,
						UI.Button("Next")({ label = "Next" }),
					})
				end)
				local track = find(world.screen, "Volume")
				world.gui.SelectedObject = track
				Verify.expect(track.NextSelectionRight):toBe(track)
				Verify.expect(track.NextSelectionLeft):toBe(track)
				Verify.expect(track.NextSelectionDown):toBe(nil)
				press(world, "DPadRight")
				Verify.expect(value:peek() > 0.5):toBe(true)
				local raised = value:peek()
				press(world, "DPadDown")
				Verify.expect((value:peek())):toBe(raised)
				press(world, "DPadLeft")
				Verify.expect(value:peek() < raised):toBe(true)
				world.gui.SelectedObject = find(world.screen, "Next")
				Verify.expect(track.NextSelectionRight):toBe(nil)
				local settled = value:peek()
				press(world, "DPadRight")
				Verify.expect((value:peek())):toBe(settled)
				world.stop()
			end,
		})

		verifyHarness:case("enters a submenu with Right and returns to its row with Left while selection is native", {
			id = "native_selection_parity::native selection parity with the main focus graph::enters a submenu with Right and returns to its row with Left while selection is native",
			run = function()
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = Compose.cell(true),
						presentation = "menu" :: "menu",
						items = {
							{ id = "first", label = "First", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "layering",
								label = "Layering",
								children = {
									{ id = "clothing", label = "Clothing", onSelect = function() end },
									{ id = "makeup", label = "Makeup", onSelect = function() end },
								},
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
				world.gui.SelectedObject = find(world.screen, "layering")
				press(world, "DPadRight")
				Verify.expect(find(world.screen, "clothing") ~= nil):toBe(true)
				Verify.expect(table.find({ "Back", "clothing" }, selected(world)) ~= nil):toBe(true)
				press(world, "DPadLeft")
				Verify.expect((selected(world))):toBe("layering")
				world.stop()
			end,
		})

		verifyHarness:case("enters a tab strip on its selected tab", {
			id = "native_selection_parity::native selection parity with the main focus graph::enters a tab strip on its selected tab",
			run = function()
				local selection = Compose.cell("two")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Above")({ label = "Above" }) :: unknown,
						UI.TabView("Tabs")({
							selection = selection,
							transition = false :: false,
							tabs = {
								{
									id = "one",
									label = "One",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "two",
									label = "Two",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "three",
									label = "Three",
									content = function(): Instance
										return Host.Frame({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}),
					})
				end)
				local tabs = find(world.screen, "Tabs")
				local strip = tabs:FindFirstChildWhichIsA("ScrollingFrame", true)
				world.gui.SelectedObject = find(world.screen, "Above")
				world.gui.SelectedObject = strip
				Verify.expect((selected(world))):toBe("two")
				selection:set("three")
				world.gui.SelectedObject = find(world.screen, "Above")
				world.gui.SelectedObject = strip
				Verify.expect((selected(world))):toBe("three")
				world.stop()
			end,
		})

		verifyHarness:case(
			"passes through a scroll container with no controls to the next control in the direction of travel",
			{
				id = "native_selection_parity::native selection parity with the main focus graph::passes through a scroll container with no controls to the next control in the direction of travel",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button("Above")({ label = "Above" }) :: unknown,
							Host.ScrollingFrame("Empty")({
								Host.TextLabel({ Text = "Beginner tasks" }),
							}),
							UI.Button("Below")({ label = "Below" }),
						})
					end)
					local V2 = world.engine.types.Vector2
					local function place(name: string, y: number, height: number)
						local node = find(world.screen, name)
						node.AbsolutePosition = V2.new(0, y)
						node.AbsoluteSize = V2.new(200, height)
					end
					place("Above", 0, 40)
					place("Empty", 50, 300)
					place("Below", 360, 40)
					world.gui.SelectedObject = find(world.screen, "Above")
					world.gui.SelectedObject = find(world.screen, "Empty")
					Verify.expect((selected(world))):toBe("Below")
					world.gui.SelectedObject = find(world.screen, "Empty")
					Verify.expect((selected(world))):toBe("Above")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"passes through an empty scroll container to the in-beam control with the nearest leading edge",
			{
				id = "native_selection_parity::native selection parity with the main focus graph::passes through an empty scroll container to the in-beam control with the nearest leading edge",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button("Above")({ label = "Above" }) :: unknown,
							Host.ScrollingFrame("Empty")({
								Host.TextLabel({ Text = "Beginner tasks" }),
							}),
							UI.Button("Near")({ label = "Near" }),
							UI.Button("Centred")({ label = "Centred" }),
						})
					end)
					local V2 = world.engine.types.Vector2
					local function place(name: string, x: number, y: number, height: number)
						local node = find(world.screen, name)
						node.AbsolutePosition = V2.new(x, y)
						node.AbsoluteSize = V2.new(200, height)
					end
					place("Above", 0, 0, 40)
					place("Empty", 0, 50, 300)
					place("Near", 150, 360, 40)
					place("Centred", 0, 420, 40)
					world.gui.SelectedObject = find(world.screen, "Above")
					world.gui.SelectedObject = find(world.screen, "Empty")
					Verify.expect((selected(world))):toBe("Near")
					world.stop()
				end,
			}
		)

		verifyHarness:case("never stops on a scroll container and forwards to its nearest child", {
			id = "native_selection_parity::native selection parity with the main focus graph::never stops on a scroll container and forwards to its nearest child",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Above")({ label = "Above" }) :: unknown,
						Host.ScrollingFrame("Page")({
							UI.Button("Inside")({ label = "Inside" }),
						}),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Above")
				world.gui.SelectedObject = find(world.screen, "Page")
				Verify.expect((selected(world))):toBe("Inside")
				world.stop()
			end,
		})

		verifyHarness:case("a move that lands on the scroll container around the selection keeps the selection", {
			id = "native_selection_parity::native selection parity with the main focus graph::a move that lands on the scroll container around the selection keeps the selection",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.ScrollingFrame("Page")({
						UI.Button("First")({ label = "First" }) :: unknown,
						UI.Button("Edge")({ label = "Edge" }),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Edge")
				world.gui.SelectedObject = find(world.screen, "Page")
				Verify.expect((selected(world))):toBe("Edge")
				world.stop()
			end,
		})
	end)
end
