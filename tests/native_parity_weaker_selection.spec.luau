--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
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
		world.input.InputBegan:Fire({
			KeyCode = (world.engine.types.Enum.KeyCode :: any)[key],
			UserInputType = world.engine.types.Enum.UserInputType.Gamepad1,
		}, true)
	end

	local function tab(world: World, back: boolean?)
		world.shift.down = back == true
		local traverse = find(world.parent, "FacetTraversal")
		assert(traverse, "the traversal context exists")
		traverse:FindFirstChild("Traverse").Pressed:Fire()
		world.shift.down = false
	end

	local function selected(world: World): string
		local node = world.gui.SelectedObject
		return if node then node.Name else "nil"
	end

	local function select(world: World, node: any)
		local previous = world.gui.SelectedObject
		if previous and previous ~= node then
			previous.SelectionLost:Fire()
		end
		world.gui.SelectedObject = node
		if world.gui.SelectedObject == node then
			node.SelectionGained:Fire()
		end
	end

	local function returnKey(world: World)
		local activate = action(world.parent, "Activate")
		assert(activate, "the selected control binds Activate")
		activate.Pressed:Fire()
	end

	local function mountExample(name: string, folder: string?): (World, any)
		local built
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
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = parent,
			worldTarget = engine.new("Folder"),
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
		}
		local stop, screen: any = runtime.mount(function()
			require("../examples/gallery/client/screen").configure(ctx)
			ctx.UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					viewport = ctx.viewport,
					guiService = gui,
					motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
						return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
					end) :: unknown) :: MotionLevel,
					inputParent = parent,
					services = { GuiService = gui, UserInputService = input },
				} :: any
			)
			built = (require :: any)("../examples/gallery/" .. (folder or "examples") .. "/" .. name).build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({ built.screen() })
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
		},
			built
	end

	verifyHarness:suite("native parity weaker selection", function()
		verifyHarness:case(
			"moves the selection out of a subtree whose ancestor stops being interactable and keeps it out",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::moves the selection out of a subtree whose ancestor stops being interactable and keeps it out",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						local E = engine.types.Enum
						return Host.Frame("Screen")({
							Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
							UI.Button("Before")({ label = "Before", LayoutOrder = 1 }),
							Host.Frame("Panel")({
								LayoutOrder = 2,
								Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
								UI.Button("Inner")({ label = "Inner", LayoutOrder = 1 }),
								UI.Button("Deep")({ label = "Deep", LayoutOrder = 2 }),
							}),
							UI.Button("After")({ label = "After", LayoutOrder = 3 }),
						})
					end)
					local panel = find(world.screen, "Panel")
					world.gui.SelectedObject = find(world.screen, "Deep")
					panel.Interactable = false
					Verify.expect((selected(world))):toBe("After")
					panel.Interactable = true
					Verify.expect((selected(world))):toBe("After")
					world.gui.SelectedObject = find(world.screen, "Inner")
					panel.Visible = false
					Verify.expect((selected(world))):toBe("After")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps entry, Tab, activation and value keys out of a subtree whose ancestor is not interactable",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::keeps entry, Tab, activation and value keys out of a subtree whose ancestor is not interactable",
				run = function()
					local value, activated = Compose.cell(0.5), 0
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						local E = engine.types.Enum
						return Host.Frame("Screen")({
							Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
							Host.Frame("Panel")({
								LayoutOrder = 1,
								Interactable = false,
								Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
								UI.Button("Inner")({
									label = "Inner",
									LayoutOrder = 1,
									onActivate = function()
										activated += 1
									end,
								}),
								UI.Slider("Volume")({ value = value, step = 0.1, LayoutOrder = 2 }),
							}),
							UI.Button("Before")({ label = "Before", LayoutOrder = 2 }),
							UI.Button("After")({ label = "After", LayoutOrder = 3 }),
						})
					end)
					press(world, "DPadDown")
					Verify.expect((selected(world))):toBe("Before")
					tab(world)
					Verify.expect((selected(world))):toBe("After")
					tab(world)
					Verify.expect((selected(world))):toBe("Before")
					tab(world, true)
					Verify.expect((selected(world))):toBe("After")
					select(world, find(world.screen, "Inner"))
					local activate = action(world.parent, "Activate")
					if activate then
						activate.Pressed:Fire()
					end
					Verify.expect(activated):toBe(0)
					local panel, track = find(world.screen, "Panel"), find(world.screen, "Volume")
					panel.Interactable = true
					select(world, track)
					press(world, "DPadRight")
					local raised = value:peek()
					Verify.expect(raised > 0.5):toBe(true)
					panel.Interactable = false
					Verify.expect((selected(world))):toBe("Before")
					track.SelectionLost:Fire()
					find(world.screen, "Before").SelectionGained:Fire()
					press(world, "DPadRight")
					press(world, "DPadLeft")
					Verify.expect((action(world.parent, "Increase"))):toBe(nil)
					Verify.expect((action(world.parent, "Decrease"))):toBe(nil)
					Verify.expect((value:peek())):toBe(raised)
					world.stop()
				end,
			}
		)

		verifyHarness:case("reports each Tab move as one observable change of the native selection", {
			id = "native_parity_weaker_selection::native parity weaker selection::reports each Tab move as one observable change of the native selection",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local E = engine.types.Enum
					return Host.Frame("Form")({
						Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
						UI.Button("Music")({ label = "Music", LayoutOrder = 1 }),
						UI.Button("Sfx")({ label = "Sfx", LayoutOrder = 2 }),
						UI.Button("Haptics")({ label = "Haptics", LayoutOrder = 3 }),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Music")
				local seen = {}
				local connection = world.gui:GetPropertyChangedSignal("SelectedObject"):Connect(function()
					table.insert(seen, selected(world))
				end)
				tab(world)
				tab(world)
				Verify.expect(#seen):toBe(2)
				Verify.expect(seen[1]):toBe("Sfx")
				Verify.expect(seen[2]):toBe("Haptics")
				connection.Disconnect()
				world.stop()
			end,
		})

		verifyHarness:case(
			"adds a control mounted by a condition to the walk, activates it and hands a removed one on",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::adds a control mounted by a condition to the walk, activates it and hands a removed one on",
				run = function()
					local shown, activated = Compose.cell(false), {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						local E = engine.types.Enum
						local function button(name: string, order: number)
							return UI.Button(name)({
								label = name,
								LayoutOrder = order,
								onActivate = function()
									table.insert(activated, name)
								end,
							})
						end
						return Host.Frame("Screen")({
							Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
							button("A", 1),
							Compose.show(shown, function()
								return button("B", 2)
							end),
							button("C", 3),
						})
					end)
					world.gui.SelectedObject = find(world.screen, "A")
					tab(world)
					Verify.expect((selected(world))):toBe("C")
					shown:set(true)
					tab(world, true)
					Verify.expect((selected(world))):toBe("B")
					select(world, find(world.screen, "B"))
					returnKey(world)
					Verify.expect(activated[#activated]):toBe("B")
					shown:set(false)
					Verify.expect((selected(world))):toBe("C")
					select(world, find(world.screen, "C"))
					returnKey(world)
					Verify.expect(activated[#activated]):toBe("C")
					Verify.expect(#activated):toBe(2)
					world.stop()
				end,
			}
		)

		verifyHarness:case("walks and activates the selection through its input actions only", {
			id = "native_parity_weaker_selection::native parity weaker selection::walks and activates the selection through its input actions only",
			run = function()
				local activated = {}
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local E = engine.types.Enum
					local function button(name: string, order: number)
						return UI.Button(name)({
							label = name,
							LayoutOrder = order,
							onActivate = function()
								table.insert(activated, name)
							end,
						})
					end
					return Host.Frame("Settings")({
						Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
						button("Music", 1),
						button("Sfx", 2),
						button("Save", 3),
					})
				end)
				local traverse = find(find(world.parent, "FacetTraversal"), "Traverse")
				local tabs = 0
				for _, binding in traverse:GetChildren() do
					if binding:IsA("InputBinding") and binding.KeyCode == world.engine.types.Enum.KeyCode.Tab then
						tabs += 1
					end
				end
				Verify.expect(tabs):toBe(1)
				tab(world)
				tab(world)
				tab(world)
				Verify.expect((selected(world))):toBe("Save")
				tab(world, true)
				Verify.expect((selected(world))):toBe("Sfx")
				select(world, world.gui.SelectedObject)
				local activate = action(world.parent, "Activate")
				local keys = {}
				for _, binding in activate:GetChildren() do
					table.insert(keys, binding.KeyCode.Name)
				end
				table.sort(keys)
				Verify.expect((table.concat(keys, ","))):toBe("Return,Space")
				activate.Pressed:Fire()
				Verify.expect((table.concat(activated, ","))):toBe("Sfx")
				world.stop()
			end,
		})

		verifyHarness:case("keeps the selection and an open modal through every input class flip", {
			id = "native_parity_weaker_selection::native parity weaker selection::keeps the selection and an open modal through every input class flip",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local E = engine.types.Enum
					return Host.Frame("Screen")({
						Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
						UI.Button("A")({ label = "A", LayoutOrder = 1 }),
						UI.Button("B")({ label = "B", LayoutOrder = 2 }),
						UI.Alert({
							isPresented = presented,
							title = "Quit?",
							actions = {
								{ id = "Stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Quit", label = "Quit", role = "destructive" :: "destructive" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local Preferred = world.engine.types.Enum.PreferredInput
				local function flipEverything()
					world.input.TouchEnabled = true
					world.input.GamepadEnabled = true
					world.input.PreferredInput = Preferred.Gamepad
					world.input.KeyboardEnabled = true
					world.input.MouseEnabled = true
					world.input.PreferredInput = Preferred.KeyboardAndMouse
					world.input.PreferredInput = Preferred.Touch
					world.input.PreferredInput = Preferred.KeyboardAndMouse
				end
				press(world, "DPadDown")
				tab(world)
				Verify.expect((selected(world))):toBe("B")
				flipEverything()
				Verify.expect((selected(world))):toBe("B")
				tab(world, true)
				Verify.expect((selected(world))):toBe("A")
				presented:set(true)
				local inside = selected(world)
				Verify.expect(inside == "Stay" or inside == "Quit"):toBe(true)
				flipEverything()
				Verify.expect((presented:peek())):toBe(true)
				Verify.expect((selected(world))):toBe(inside)
				tab(world)
				Verify.expect(selected(world) == "Stay" or selected(world) == "Quit"):toBe(true)
				action(world.parent, "ModalBack").Pressed:Fire()
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect((selected(world))):toBe("A")
				world.stop()
			end,
		})

		verifyHarness:case(
			"selects a Picker option and toggles a DisclosureGroup with Return and with the engine activation",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::selects a Picker option and toggles a DisclosureGroup with Return and with the engine activation",
				run = function()
					local choice, expanded = Compose.cell("a"), Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						local E = engine.types.Enum
						return Host.Frame("Screen")({
							Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
							UI.Picker("Mode")({
								LayoutOrder = 1,
								selected = choice,
								style = "segmented" :: "segmented",
								options = {
									{ value = "a", label = "Alpha" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Beta" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "c", label = "Gamma" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}),
							UI.DisclosureGroup({
								LayoutOrder = 2,
								expanded = expanded,
								label = "Details",
								content = function(): Instance
									return Host.Frame("Details")({})
								end,
							}),
						})
					end)
					select(world, find(world.screen, "b"))
					returnKey(world)
					Verify.expect((choice:peek())):toBe("b")
					select(world, find(world.screen, "c"))
					find(world.screen, "c").Activated:Fire()
					Verify.expect((choice:peek())):toBe("c")
					local header = find(world.screen, "Header")
					select(world, header)
					returnKey(world)
					Verify.expect((expanded:peek())):toBe(true)
					header.Activated:Fire()
					Verify.expect((expanded:peek())):toBe(false)
					world.stop()
				end,
			}
		)

		verifyHarness:case("keeps a card revealed while Tab walks its body and actions and ends it when Tab leaves", {
			id = "native_parity_weaker_selection::native parity weaker selection::keeps a card revealed while Tab walks its body and actions and ends it when Tab leaves",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local E = engine.types.Enum
					return Host.Frame("Row")({
						Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
						UI.Card("C")({
							LayoutOrder = 1,
							image = "rbxassetid://1",
							title = "Nebula Racers",
							caption = "Friends playing",
							onActivate = function() end,
							primaryAction = { label = "Play", onActivate = function() end },
							menu = { items = { { id = "hide", label = "Not interested", onSelect = function() end } } },
						}),
						UI.Button("Next")({ label = "Next", LayoutOrder = 2 }),
					})
				end)
				local root = find(world.screen, "C")
				local function revealed(): boolean
					return root:GetAttribute("FacetRevealed") == true
				end
				root:_fireSignal("MouseEnter")
				world.gui.SelectedObject = find(root, "Body")
				root:_fireSignal("MouseLeave")
				Verify.expect((revealed())):toBe(true)
				local walk = {}
				for _ = 1, 3 do
					tab(world)
					table.insert(walk, `{selected(world)}:{revealed()}`)
				end
				Verify.expect(walk[1]):toBe("Primary:true")
				Verify.expect(walk[2]):toBe("More:true")
				Verify.expect(walk[3]):toBe("Next:false")
				tab(world, true)
				Verify.expect((selected(world))):toBe("Body")
				Verify.expect((revealed())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("reaches the playlist header from the first stop of the page with Tab", {
			id = "native_parity_weaker_selection::native parity weaker selection::reaches the playlist header from the first stop of the page with Tab",
			run = function()
				local world = mountExample("02_playlist_table")
				tab(world)
				local first = world.gui.SelectedObject
				Verify.expect(first ~= nil):toBe(true)
				local stops, reached = 1, nil
				local header = find(world.screen, "Header")
				Verify.expect(header ~= nil):toBe(true)
				for _ = 1, 80 do
					local current = world.gui.SelectedObject
					if current and current:IsDescendantOf(header) then
						reached = current
						break
					end
					tab(world)
					stops += 1
				end
				Verify.expect((first:IsDescendantOf(header))):toBe(false)
				Verify.expect(reached ~= nil):toBe(true)
				Verify.expect(stops > 1):toBe(true)
				Verify.expect(reached.Name == "Sort" or reached.Name == "Resize"):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"steps the card rail sideways with the arrows and the D-pad, never along Up or Down, and picks with Return or A",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::steps the card rail sideways with the arrows and the D-pad, never along Up or Down, and picks with Return or A",
				run = function()
					local world, built = mountExample("card_rail", "scenarios")
					local rail = find(world.screen, "Rail")
					rail.AbsoluteSize = world.engine.types.Vector2.new(1000, 300)
					rail.AbsoluteWindowSize = world.engine.types.Vector2.new(1000, 300)
					local function card(): string
						local node = world.gui.SelectedObject
						return if node then node.Name else "nil"
					end
					local function step(direction: string)
						local arrow = action(world.parent, "Collection" .. direction)
						assert(arrow, `the rail binds {direction}`)
						local keys = {}
						for _, binding in arrow:GetChildren() do
							table.insert(keys, binding.KeyCode.Name)
						end
						table.sort(keys)
						Verify.expect((table.concat(keys, ","))):toBe(`DPad{direction},{direction}`)
						arrow.Pressed:Fire()
						local node = world.gui.SelectedObject
						if node then
							node.SelectionGained:Fire()
						end
					end
					select(world, find(rail, "Card_c1"))
					step("Right")
					Verify.expect((card())):toBe("Card_c2")
					step("Right")
					Verify.expect((card())):toBe("Card_c3")
					step("Left")
					Verify.expect((card())):toBe("Card_c2")

					Verify.expect((action(world.parent, "CollectionUp"))):toBeNil()
					Verify.expect((action(world.parent, "CollectionDown"))):toBeNil()
					Verify.expect((card())):toBe("Card_c2")
					returnKey(world)
					Verify.expect(built.report().selectedKey):toBe("c2")
					local shown = find(world.screen, "Selected")
					Verify.expect(string.find(shown.Text, "Livery 002", 1, true) ~= nil):toBe(true)
					step("Right")
					world.gui.SelectedObject.Activated:Fire()
					Verify.expect(built.report().selectedKey):toBe("c3")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"drives the settings sync example with Return, Tab, the engine activation and the steppers",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::drives the settings sync example with Return, Tab, the engine activation and the steppers",
				run = function()
					local world, built = mountExample("03_settings_sync")
					press(world, "DPadDown")
					Verify.expect((selected(world))):toBe("Music")
					select(world, world.gui.SelectedObject)
					returnKey(world)
					Verify.expect(built.report().draft.music):toBe(true)
					Verify.expect(built.report().status):toBe("pending")
					local stops = 0
					repeat
						tab(world)
						stops += 1
					until selected(world) == "Deliver" or stops > 10
					Verify.expect((selected(world))):toBe("Deliver")
					select(world, world.gui.SelectedObject)
					returnKey(world)
					Verify.expect(built.report().status):toBe("confirmed")
					Verify.expect(built.report().server.music):toBe(true)
					local music = find(world.screen, "Music")
					select(world, music)
					music.Activated:Fire()
					Verify.expect(built.report().draft.music):toBe(false)
					Verify.expect(built.report().status):toBe("pending")
					find(world.screen, "Deliver").Activated:Fire()
					Verify.expect(built.report().status):toBe("confirmed")
					local decrease = find(find(world.screen, "Volume"), "Decrease")
					select(world, decrease)
					decrease.Activated:Fire()
					Verify.expect(built.report().draft.volume):toBe(9)
					Verify.expect(built.report().status):toBe("pending")
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"keeps the selection on the only eligible control when Tab and Shift+Tab have nowhere else to go",
			{
				id = "native_parity_weaker_selection::native parity weaker selection::keeps the selection on the only eligible control when Tab and Shift+Tab have nowhere else to go",
				run = function()
					local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
						local E = engine.types.Enum
						return Host.Frame("Screen")({
							Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }) :: unknown,
							UI.Button("Off")({ label = "Off", LayoutOrder = 1, enabled = false }),
							UI.Button("Only")({ label = "Only", LayoutOrder = 2 }),
							UI.Button("Hidden")({ label = "Hidden", LayoutOrder = 3, Visible = false }),
						})
					end)
					tab(world)
					Verify.expect((selected(world))):toBe("Only")
					tab(world)
					Verify.expect((selected(world))):toBe("Only")
					tab(world, true)
					Verify.expect((selected(world))):toBe("Only")
					world.stop()
				end,
			}
		)
	end)
end
