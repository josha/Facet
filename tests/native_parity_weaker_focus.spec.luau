--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type RowActions = typeof(require("@repo/tools/typecheck/aliases").RowActions)
	type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
	local FixtureRadialTypes = require("../src/ui/radial_types")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local NavigationFixtures = require("../src/ui/navigation_types")
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
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {}) :: { [string]: any } do
			if key == "prepare" then
				value(engine, input)
			else
				config[key] = value
			end
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host, engine, gui) })
		end, engine.new("Folder"))
		return {
			engine = engine,
			runtime = runtime,
			gui = gui,
			input = input,
			screen = screen,
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
		local winner
		for _, node in root:GetDescendants() do
			local inner = if node:IsA("InputContext") and node.Enabled then node:FindFirstChild(name) else nil
			if inner and inner:IsA("InputAction") and inner.Enabled ~= false then
				if winner == nil or node.Priority > winner.Parent.Priority then
					winner = inner
				end
			end
		end
		return winner
	end

	local function contexts(root: any, name: string): { any }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:IsA("InputContext") and node:FindFirstChild(name) then
				table.insert(found, node)
			end
		end
		return found
	end

	local function actionsNamed(root: any, name: string): { any }
		local found = {}
		for _, context in contexts(root, name) do
			table.insert(found, context:FindFirstChild(name))
		end
		return found
	end

	local function keys(inputAction: any): { string }
		local names = {}
		for _, binding in inputAction:GetChildren() do
			if binding:IsA("InputBinding") then
				table.insert(names, binding.KeyCode.Name)
			end
		end
		table.sort(names)
		return names
	end

	local function within(node: any, ancestor: any): boolean
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local function V2(world: World, x: number, y: number): any
		return world.engine.types.Vector2.new(x, y)
	end

	verifyHarness:suite("native parity weaker focus", function()
		verifyHarness:case("dismisses a sheet with Back and returns selection to the control that opened it", {
			id = "native_parity_weaker_focus::native parity weaker focus::dismisses a sheet with Back and returns selection to the control that opened it",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						UI.Sheet({
							isPresented = presented,
							detent = Compose.cell("medium"),
							title = "Options",
							content = function(): Instance
								return UI.Button("Inside")({ label = "Inside" })
							end,
						}),
					})
				end)
				local opener = find(world.screen, "Opener")
				world.gui.SelectedObject = opener
				presented:set(true)
				local panel = find(world.screen, "SheetPanel")
				Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
				local back = action(world.screen, "ModalBack")
				Verify.expect((keys(back))):toEqual({ "ButtonB", "Escape" })
				back.Pressed:Fire()
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect((find(world.screen, "SheetPanel"))):toBeNil()
				Verify.expect(world.gui.SelectedObject):toBe(opener)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the scrim out of selection so a rejected scrim selection leaves focus in the modal", {
			id = "native_parity_weaker_focus::native parity weaker focus::keeps the scrim out of selection so a rejected scrim selection leaves focus in the modal",
			run = function()
				for _, kind in { "Alert", "Sheet" } :: { "Alert" | "Sheet" } do
					local presented = Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button("Opener")({ label = "Open" }) :: unknown,
							if kind == "Alert"
								then UI.Alert({
									isPresented = presented,
									title = "Leave?",
									actions = {
										{ id = "Stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
									},
								})
								else UI.Sheet({
									isPresented = presented,
									detent = Compose.cell("medium"),
									content = function(): Instance
										return UI.Button("Inside")({ label = "Inside" })
									end,
								}) :: unknown,
						})
					end)
					world.gui.SelectedObject = find(world.screen, "Opener")
					presented:set(true)
					local scrim = find(world.screen, "DismissOutside")
					Verify.expect(scrim.Selectable):toBe(false)
					local selected = world.gui.SelectedObject
					Verify.expect((within(selected, scrim.Parent))):toBe(true)
					Verify.expect((within(selected, scrim))):toBe(false)
					world.gui.SelectedObject = scrim
					Verify.expect(world.gui.SelectedObject):toBe(selected)
					Verify.expect(table.find(world.engine.rejectedSelections(), scrim) ~= nil):toBe(true)
					world.stop()
				end
			end,
		})

		verifyHarness:case("dismisses every modal presentation on the default Back without an authored cancel action", {
			id = "native_parity_weaker_focus::native parity weaker focus::dismisses every modal presentation on the default Back without an authored cancel action",
			run = function()
				local alert, sheet, menu = Compose.cell(true), Compose.cell(false), Compose.cell(false)
				local accepted = 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Alert({
							isPresented = alert,
							title = "Saved",
							actions = {
								{
									id = "Accept",
									label = "Accept",
									onActivate = function()
										accepted += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
							},
						}) :: unknown,
						UI.Sheet({
							isPresented = sheet,
							detent = Compose.cell("medium"),
							content = function(): Instance
								return UI.Button({ label = "Inside" })
							end,
						}),
						UI.Menu({
							isPresented = menu,
							items = {
								{
									id = "Run",
									label = "Run",
									onSelect = function()
										accepted += 1
									end,
								} :: FixtureNavigationTypes.MenuItem<any>,
							},
						}),
					})
				end)
				for _, presented in { alert, sheet, menu } do
					presented:set(true)
					local back = action(world.screen, "ModalBack")
					Verify.expect(back ~= nil):toBe(true)
					back.Pressed:Fire()
					Verify.expect((presented:peek())):toBe(false)
					Verify.expect((action(world.screen, "ModalBack"))):toBeNil()
				end
				Verify.expect(accepted):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("keeps Tab and Escape native while an alert owns safe initial selection and Back", {
			id = "native_parity_weaker_focus::native parity weaker focus::keeps Tab and Escape native while an alert owns safe initial selection and Back",
			run = function()
				for _, reserved in { "Tab", "Escape" } do
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } } :: any)
					local ok, message = pcall(function()
						local stop = runtime.mount(function()
							return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
								UI.Button({ label = "Background", shortcut = { keyCode = reserved } }),
							})
						end, engine.new("Folder"))
						stop()
					end)
					runtime:dispose()
					Verify.expect(ok):toBe(false)
					Verify.expect(
						string.find(tostring(message), "Escape and Tab retain native navigation ownership", 1, true)
							~= nil
					):toBe(true)
				end
				local presented = Compose.cell(false)
				local shortcutCount, cancelled, deleted = 0, 0, 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Background")({
							label = "Background",
							shortcut = { keyCode = "K" },
							onActivate = function()
								shortcutCount += 1
							end,
						}) :: unknown,
						UI.Alert({
							isPresented = presented,
							title = "Delete?",
							actions = {
								{
									id = "Delete",
									label = "Delete",
									role = "destructive" :: "destructive",
									onActivate = function()
										deleted += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
								{
									id = "Keep",
									label = "Keep",
									role = "cancel" :: "cancel",
									onActivate = function()
										cancelled += 1
									end,
								} :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				local background = find(world.screen, "Background")
				world.gui.SelectedObject = background
				local shortcut = action(world.screen, "Shortcut")
				presented:set(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Keep")
				Verify.expect(shortcut.Parent.Enabled):toBe(false)
				local back = action(world.screen, "ModalBack")
				Verify.expect((keys(back))):toEqual({ "ButtonB", "Escape" })
				Verify.expect(back.Parent.Sink):toBe(true)
				back.Pressed:Fire()
				Verify.expect(cancelled):toBe(1)
				Verify.expect(deleted):toBe(0)
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect(world.gui.SelectedObject):toBe(background)
				Verify.expect(shortcut.Parent.Enabled):toBe(true)
				shortcut.Pressed:Fire()
				Verify.expect(shortcutCount):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("selects inside a modal only once its screen reaches a PlayerGui", {
			id = "native_parity_weaker_focus::native parity weaker focus::selects inside a modal only once its screen reaches a PlayerGui",
			run = function()
				local engine: any = engineLib.new({ selectionNeedsPlayerGui = true })
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local gui = engine.new("GuiService")
				local UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } } :: any)
				local playerGui = engine.new("PlayerGui")
				local other = engine.new("ScreenGui")
				other.Parent = playerGui
				local elsewhere = engine.new("TextButton")
				elsewhere.Selectable = true
				elsewhere.Parent = other
				gui.SelectedObject = elsewhere
				local holder = engine.new("Folder")
				local stop, screen: any = runtime.mount(function()
					return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
						UI.Alert({
							isPresented = Compose.cell(true),
							title = "Leave?",
							actions = { { id = "Stay", label = "Stay" } :: FixtureNavigationTypes.AlertAction<any> },
						}),
					})
				end, holder)
				Verify.expect(find(screen, "AlertPanel") ~= nil):toBe(true)
				Verify.expect(gui.SelectedObject):toBe(elsewhere)
				screen.Parent = playerGui
				Verify.expect(gui.SelectedObject ~= nil and gui.SelectedObject.Name == "Stay"):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("groups modal selection and enters at the first selectable control in document order", {
			id = "native_parity_weaker_focus::native parity weaker focus::groups modal selection and enters at the first selectable control in document order",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					return Host.Frame({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						UI.Sheet({
							isPresented = presented,
							detent = Compose.cell("large"),
							content = function(): Instance
								return Host.Frame("Body")({
									Host.UIListLayout({ SortOrder = engine.types.Enum.SortOrder.LayoutOrder }) :: unknown,
									UI.Button("First")({ label = "First", LayoutOrder = 1 }),
									UI.Button("Second")({ label = "Second", LayoutOrder = 2 }),
									UI.Button("Third")({ label = "Third", LayoutOrder = 3 }),
								})
							end,
						}),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				presented:set(true)
				local panel = find(world.screen, "SheetPanel")
				Verify.expect(panel.SelectionGroup):toBe(true)
				for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
					Verify.expect(panel["SelectionBehavior" .. direction])
						:toBe(world.engine.types.Enum.SelectionBehavior.Stop)
				end
				Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
				local walk = {}
				local function visit(node: any)
					if node:IsA("GuiObject") and (not node.Visible or not node.Interactable) then
						return
					end
					if node:IsA("GuiObject") and node.Selectable then
						table.insert(walk, node)
					end
					for _, child in node:GetChildren() do
						visit(child)
					end
				end
				visit(panel)
				Verify.expect(world.gui.SelectedObject):toBe(walk[1])
				local names = {}
				for _, node in walk do
					if node.Name == "First" or node.Name == "Second" or node.Name == "Third" then
						table.insert(names, node.Name)
					end
				end
				Verify.expect(names):toEqual({ "First", "Second", "Third" })
				for _, node in walk do
					Verify.expect((within(node, panel))):toBe(true)
				end
				presented:set(false)
				local alertPresented = Compose.cell(false)
				world.stop()
				local alertWorld = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						UI.Alert({
							isPresented = alertPresented,
							title = "Choose",
							actions = {
								{ id = "Off", label = "Off", enabled = false } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "One", label = "One" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Two", label = "Two" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						}),
					})
				end)
				alertWorld.gui.SelectedObject = find(alertWorld.screen, "Opener")
				alertPresented:set(true)
				Verify.expect(alertWorld.gui.SelectedObject.Name):toBe("One")
				Verify.expect(
					find(alertWorld.screen, "Off").Interactable == false
						or find(alertWorld.screen, "Off").Selectable == false
				):toBe(true)
				alertWorld.stop()
			end,
		})

		verifyHarness:case(
			"traps an open menu and returns selection to its trigger after outside tap, Back and model close",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::traps an open menu and returns selection to its trigger after outside tap, Back and model close",
				run = function()
					for _, route in { "outside", "back", "model" } do
						local opened = Compose.cell(false)
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.Button("Elsewhere")({ label = "Elsewhere" }) :: unknown,
								UI.Menu({
									label = "More",
									isPresented = opened,
									items = {
										{ id = "Rename", label = "Rename", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
										{ id = "Share", label = "Share", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
									},
								}),
							})
						end)
						local trigger = find(world.screen, "Trigger")
						world.gui.SelectedObject = trigger
						trigger.Activated:Fire()
						Verify.expect((opened:peek())):toBe(true)
						local panel = find(world.screen, "MenuPanel")
						Verify.expect(world.gui.SelectedObject.Name):toBe("Rename")
						Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
						local group = panel
						while group and group.SelectionGroup ~= true do
							group = group.Parent
						end
						Verify.expect(group ~= nil):toBe(true)
						for _, direction in { "Up", "Down", "Left", "Right" } :: { "Down" | "Left" | "Right" | "Up" } do
							Verify.expect(group["SelectionBehavior" .. direction])
								:toBe(world.engine.types.Enum.SelectionBehavior.Stop)
						end
						Verify.expect((action(world.screen, "Menu"))):toBeNil()
						if route == "outside" then
							find(world.screen, "DismissOutside").Activated:Fire({ Position = V2(world, 900, 900) })
						elseif route == "back" then
							action(world.screen, "ModalBack").Pressed:Fire()
						else
							opened:set(false)
						end
						Verify.expect((opened:peek())):toBe(false)
						Verify.expect((find(world.screen, "MenuPanel"))):toBeNil()
						Verify.expect(world.gui.SelectedObject):toBe(trigger)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("returns a submenu Back row to the item that opened it and traps a picker menu", {
			id = "native_parity_weaker_focus::native parity weaker focus::returns a submenu Back row to the item that opened it and traps a picker menu",
			run = function()
				local opened = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Menu({
							isPresented = opened,
							presentation = "sheet" :: "sheet",
							items = {
								{
									id = "Sort",
									label = "Sort",
									children = {
										{ id = "Name", label = "Name", onSelect = function() end },
										{ id = "Date", label = "Date", onSelect = function() end },
									},
								} :: FixtureNavigationTypes.MenuItem<any>,
								{ id = "Close", label = "Close", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							},
						}),
					})
				end)
				local trigger = find(world.screen, "Trigger")
				world.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				find(world.screen, "Sort").Activated:Fire()
				Verify.expect(world.gui.SelectedObject.Name):toBe("Name")
				find(world.screen, "Back").Activated:Fire()
				Verify.expect((opened:peek())):toBe(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Sort")
				world.gui.SelectedObject = find(world.screen, "Sort")
				action(world.screen, "MenuRight").Pressed:Fire()
				Verify.expect(world.gui.SelectedObject.Name):toBe("Name")
				action(world.screen, "MenuLeft").Pressed:Fire()
				Verify.expect(world.gui.SelectedObject.Name):toBe("Sort")
				Verify.expect((opened:peek())):toBe(true)
				action(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect(world.gui.SelectedObject):toBe(trigger)
				world.stop()
				for _, route in { "outside", "back", "model" } do
					local selected, presented = Compose.cell("a"), Compose.cell(false)
					local pickerWorld = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Picker("Speed")({
								selected = selected,
								style = "menu" :: "menu",
								isPresented = presented,
								options = {
									{ value = "a", label = "Slow" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Fast" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}),
						})
					end)
					local pickerTrigger = find(pickerWorld.screen, "Trigger")
					pickerWorld.gui.SelectedObject = pickerTrigger
					pickerTrigger.Activated:Fire()
					Verify.expect((presented:peek())):toBe(true)
					local panel = find(pickerWorld.screen, "MenuPanel")
					Verify.expect((within(pickerWorld.gui.SelectedObject, panel))):toBe(true)
					if route == "outside" then
						find(pickerWorld.screen, "DismissOutside").Activated:Fire({
							Position = V2(pickerWorld, 900, 900),
						})
					elseif route == "back" then
						action(pickerWorld.screen, "ModalBack").Pressed:Fire()
					else
						presented:set(false)
					end
					Verify.expect((presented:peek())):toBe(false)
					Verify.expect((selected:peek())):toBe("a")
					Verify.expect(pickerWorld.gui.SelectedObject):toBe(pickerTrigger)
					pickerWorld.stop()
				end
			end,
		})

		verifyHarness:case("lets a presented modal own Back over a navigation stack and leaves root Back unconsumed", {
			id = "native_parity_weaker_focus::native parity weaker focus::lets a presented modal own Back over a navigation stack and leaves root Back unconsumed",
			run = function()
				local path, presented =
					Compose.cell({ { id = "detail" } } :: { NavigationFixtures.NavigationEntry<any> }),
					Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.NavigationStack({
							path = path,
							root = {
								content = function(): Instance
									return UI.Button("RootAction")({ label = "Root" })
								end,
							} :: NavigationFixtures.NavigationDestination<any>,
							destinations = {
								detail = {
									content = function(): Instance
										return UI.Button("DetailAction")({ label = "Detail" })
									end,
								} :: NavigationFixtures.NavigationDestination<any>,
							},
						}) :: unknown,
						UI.Alert({ isPresented = presented, title = "Hold on" }),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "DetailAction")
				local navigationBack = actionsNamed(world.screen, "NavigationBack")[1]
				Verify.expect(navigationBack.Parent.Enabled):toBe(true)
				presented:set(true)
				Verify.expect(navigationBack.Parent.Enabled):toBe(false)
				navigationBack.Pressed:Fire()
				Verify.expect(#path:peek()):toBe(1)
				local modalBack = action(world.screen, "ModalBack")
				Verify.expect(modalBack.Parent.Priority > navigationBack.Parent.Priority):toBe(true)
				modalBack.Pressed:Fire()
				Verify.expect((presented:peek())):toBe(false)
				Verify.expect(#path:peek()):toBe(1)
				Verify.expect(navigationBack.Parent.Enabled):toBe(true)
				navigationBack.Pressed:Fire()
				Verify.expect(#path:peek()):toBe(0)
				Verify.expect(navigationBack.Parent.Enabled):toBe(false)
				navigationBack.Pressed:Fire()
				Verify.expect(#path:peek()):toBe(0)
				Verify.expect((action(world.screen, "NavigationBack"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("gives an open menu or picker popup the shoulders before tab content paging", {
			id = "native_parity_weaker_focus::native parity weaker focus::gives an open menu or picker popup the shoulders before tab content paging",
			run = function()
				for _, kind in { "Menu", "Picker" } :: { "Menu" | "Picker" } do
					local selection, opened = Compose.cell("a"), Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = selection,
							shoulderNavigation = "content" :: "content",
							tabs = {
								{
									id = "a",
									label = "A",
									content = function(): Instance
										if kind == "Menu" then
											return UI.Menu({
												isPresented = opened,
												items = {
													{ id = "Run", label = "Run", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
												},
											})
										end
										return UI.Picker({
											selected = Compose.cell(1),
											style = "menu" :: "menu",
											isPresented = opened,
											options = {
												{ value = 1, label = "One" } :: FixtureNavigationTypes.PickerOption<any>,
												{ value = 2, label = "Two" } :: FixtureNavigationTypes.PickerOption<any>,
											},
										})
									end,
								} :: FixtureNavigationTypes.Tab,
								{
									id = "b",
									label = "B",
									content = function(): Instance
										return Host.Frame("BBody")({})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local trigger = find(world.screen, "Trigger")
					world.gui.SelectedObject = trigger
					local next = action(world.screen, "NextTab")
					Verify.expect(next ~= nil):toBe(true)
					trigger.Activated:Fire()
					Verify.expect((opened:peek())):toBe(true)
					Verify.expect((within(world.gui.SelectedObject, find(world.screen, "MenuPanel")))):toBe(true)
					Verify.expect(next.Parent.Enabled):toBe(false)
					Verify.expect((action(world.screen, "NextTab"))):toBeNil()
					Verify.expect((action(world.screen, "PreviousTab"))):toBeNil()
					next.Pressed:Fire()
					Verify.expect((selection:peek())):toBe("a")
					Verify.expect((opened:peek())):toBe(true)
					world.gui.SelectedObject = trigger
					Verify.expect(next.Parent.Enabled):toBe(false)
					Verify.expect((action(world.screen, "NextTab"))):toBeNil()
					next.Pressed:Fire()
					Verify.expect((selection:peek())):toBe("a")
					action(world.screen, "ModalBack").Pressed:Fire()
					Verify.expect((opened:peek())):toBe(false)
					Verify.expect(world.gui.SelectedObject):toBe(trigger)
					Verify.expect(next.Parent.Enabled):toBe(true)
					next.Pressed:Fire()
					Verify.expect((selection:peek())):toBe("b")
					world.stop()
				end
			end,
		})

		verifyHarness:case(
			"returns disclosure focus to the header for a child collapse and leaves outside focus alone",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::returns disclosure focus to the header for a child collapse and leaves outside focus alone",
				run = function()
					local expanded = Compose.cell(true)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button("Outside")({ label = "Outside" }) :: unknown,
							UI.DisclosureGroup({
								expanded = expanded,
								label = "Details",
								content = function(): Instance
									return UI.Button("Collapse")({
										label = "Collapse",
										onActivate = function()
											expanded:set(false)
										end,
									})
								end,
							}),
						})
					end)
					local collapse = find(world.screen, "Collapse")
					world.gui.SelectedObject = collapse
					collapse.Activated:Fire()
					Verify.expect((expanded:peek())):toBe(false)
					Verify.expect(world.gui.SelectedObject):toBe(find(world.screen, "Header"))
					Verify.expect(find(world.screen, "Reveal").Interactable):toBe(false)
					world.engine.heartbeat:Fire(0.25)
					Verify.expect((collapse:isDestroyed())):toBe(true)
					Verify.expect(world.gui.SelectedObject):toBe(find(world.screen, "Header"))
					expanded:set(true)
					local outside = find(world.screen, "Outside")
					world.gui.SelectedObject = outside
					expanded:set(false)
					Verify.expect(world.gui.SelectedObject):toBe(outside)
					world.stop()
				end,
			}
		)

		verifyHarness:case("leaves background selection and shortcuts live while a callout is shown", {
			id = "native_parity_weaker_focus::native parity weaker focus::leaves background selection and shortcuts live while a callout is shown",
			run = function()
				local shown, count = Compose.cell(true), 0
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button("Anchor")({ label = "Anchor" })
					return Host.Frame({
						anchor :: unknown,
						UI.Button("Other")({
							label = "Other",
							shortcut = { keyCode = "K" },
							onActivate = function()
								count += 1
							end,
						}),
						UI.Callout({
							anchor = anchor :: GuiObject,
							isPresented = shown,
							onRetire = function() end,
							content = function(): Instance
								return UI.Button("Tip")({ label = "Tip" })
							end,
						}),
					})
				end)
				local anchor, other = find(world.screen, "Anchor"), find(world.screen, "Other")
				world.gui.SelectedObject = anchor
				local panel = find(world.screen, "CalloutPanel")
				Verify.expect(panel ~= nil):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(anchor)
				Verify.expect((action(world.screen, "ModalBack"))):toBeNil()
				Verify.expect((find(world.screen, "DismissOutside"))):toBeNil()
				local cursor = panel
				while cursor and cursor ~= world.screen do
					Verify.expect(
						cursor.SelectionGroup == true
							and cursor.SelectionBehaviorDown == world.engine.types.Enum.SelectionBehavior.Stop
					):toBe(false)
					cursor = cursor.Parent
				end
				world.gui.SelectedObject = other
				Verify.expect(world.gui.SelectedObject):toBe(other)
				local shortcut = action(world.screen, "Shortcut")
				Verify.expect(shortcut ~= nil):toBe(true)
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(1)
				world.gui.SelectedObject = anchor
				Verify.expect(world.gui.SelectedObject):toBe(anchor)
				Verify.expect(#world.engine.rejectedSelections()):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case("releases a column grip when selection moves to another grip or the table leaves", {
			id = "native_parity_weaker_focus::native parity weaker focus::releases a column grip when selection moves to another grip or the table leaves",
			run = function()
				local widths = Compose.cell({})
				local world = setup(function(UI: FacetControls)
					return UI.Table({
						from = { { id = 1 }, { id = 2 } },
						key = function(item)
							return item.id
						end,
						widths = widths,
						columns = {
							{ id = "first", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
							{ id = "second", width = 100 } :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end)
				local header = find(world.screen, "Header")
				local first, second = header:FindFirstChild("first"), header:FindFirstChild("second")
				first.AbsoluteSize = V2(world, 100, 40)
				second.AbsoluteSize = V2(world, 100, 40)
				local firstGrip, secondGrip = first:FindFirstChild("Resize"), second:FindFirstChild("Resize")
				local narrows = actionsNamed(world.screen, "NarrowColumn")
				Verify.expect(#narrows):toBe(2)
				local function narrowAll()
					for _, narrow in narrows do
						if narrow.Parent.Enabled then
							narrow.Pressed:Fire()
						end
					end
				end
				for _, narrow in narrows do
					Verify.expect(narrow.Parent.Enabled):toBe(false)
				end
				firstGrip.SelectionGained:Fire()
				narrowAll()
				Verify.expect((widths:peek())):toEqual({ first = 92 })
				firstGrip.SelectionLost:Fire()
				secondGrip.SelectionGained:Fire()
				local enabled = 0
				for _, narrow in narrows do
					if narrow.Parent.Enabled then
						enabled += 1
					end
				end
				Verify.expect(enabled):toBe(1)
				narrowAll()
				Verify.expect((widths:peek())):toEqual({ first = 92, second = 92 })
				for _, narrow in narrows do
					narrow.Pressed:Fire()
				end
				Verify.expect((widths:peek())):toEqual({ first = 92, second = 84 })
				world.stop()
				for _, narrow in narrows do
					Verify.expect((narrow:isDestroyed())):toBe(true)
					narrow.Pressed:Fire()
				end
				Verify.expect((widths:peek())):toEqual({ first = 92, second = 84 })
			end,
		})

		verifyHarness:case("keeps native selection on a diagonal wedge of an even ring across held aim frames", {
			id = "native_parity_weaker_focus::native parity weaker focus::keeps native selection on a diagonal wedge of an even ring across held aim frames",
			run = function()
				local engine: any = engineLib.new()
				local hold = engine.new("InputAction")
				local picked = {}
				local items = {}
				for index = 1, 8 do
					table.insert(items, {
						id = "Item" .. index,
						label = "Item " .. index,
						onSelect = function()
							table.insert(picked, "Item" .. index)
						end,
					})
				end
				local opened = Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					return UI.RadialMenu({ isPresented = opened, holdAction = hold, items = items })
				end, { motionLevel = "none" })
				hold.Pressed:Fire()
				Verify.expect((opened:peek())):toBe(true)
				local axis = action(world.screen, "RadialAim")
				local function aim(degrees: number, magnitude: number)
					local radians = math.rad(degrees)
					axis.StateChanged:Fire(V2(world, math.sin(radians) * magnitude, math.cos(radians) * magnitude))
				end
				aim(45, 0.9)
				local wedge = world.gui.SelectedObject
				Verify.expect(wedge ~= nil and wedge.Name):toBe("Item2")
				for _, degrees in { 40, 50, 60, 30, 45 } do
					aim(degrees, 0.9)
					world.engine.heartbeat:Fire(1 / 60)
					Verify.expect(world.gui.SelectedObject):toBe(wedge)
				end
				for _ = 1, 30 do
					world.engine.heartbeat:Fire(1 / 60)
				end
				Verify.expect(world.gui.SelectedObject):toBe(wedge)
				aim(135, 0.9)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Item4")
				aim(225, 0.9)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Item6")
				aim(315, 0.9)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Item8")
				aim(45, 0.9)
				Verify.expect(world.gui.SelectedObject):toBe(wedge)
				Verify.expect(#picked):toBe(0)
				hold.Released:Fire()
				Verify.expect(picked):toEqual({ "Item2" })
				world.stop()
			end,
		})

		verifyHarness:case("takes modal selection on entry only for selection navigation across sheets and menus", {
			id = "native_parity_weaker_focus::native parity weaker focus::takes modal selection on entry only for selection navigation across sheets and menus",
			run = function()
				for _, preferred in { "Touch", "KeyboardAndMouse", "Gamepad" } do
					local sheet, menu = Compose.cell(false), Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Sheet({
								isPresented = sheet,
								detent = Compose.cell("medium"),
								content = function(): Instance
									return UI.Button("Inside")({ label = "Inside" })
								end,
							}) :: unknown,
							UI.Menu({
								isPresented = menu,
								items = {
									{ id = "Run", label = "Run", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								},
							}),
						})
					end)
					world.input.PreferredInput = (world.engine.types.Enum.PreferredInput :: any)[preferred]
					for _, presented in { sheet, menu } do
						presented:set(true)
						if preferred == "Gamepad" then
							Verify.expect(world.gui.SelectedObject ~= nil):toBe(true)
							local panel = find(world.screen, if presented == sheet then "SheetPanel" else "MenuPanel")
							Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
						else
							Verify.expect(world.gui.SelectedObject):toBeNil()
						end
						presented:set(false)
						Verify.expect(world.gui.SelectedObject):toBeNil()
					end
					world.stop()
				end
			end,
		})

		verifyHarness:case(
			"restores a deep tab bookmark on shoulder entry and skips restoration when restoreFocus is off",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::restores a deep tab bookmark on shoulder entry and skips restoration when restoreFocus is off",
				run = function()
					for _, restore in { true, false } do
						local selection = Compose.cell("one")
						local rows = {}
						for index = 1, 12 do
							rows[index] = { id = index, label = tostring(index) }
						end
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView({
								selection = selection,
								shoulderNavigation = "content" :: "content",
								restoreFocus = restore,
								transition = false :: false,
								tabs = {
									{
										id = "one",
										label = "One",
										content = function(): Instance
											return Host.Frame("OneBody")({
												UI.Button("Top")({ label = "Top" }) :: unknown,
												Host.ScrollingFrame("Scroller")({
													Host.Frame("Group")({
														UI.Button("Shallow")({ label = "Shallow" }) :: unknown,
														UI.Button("Deep")({ label = "Deep" }),
													}),
												}),
											})
										end,
									} :: FixtureNavigationTypes.Tab,
									{
										id = "two",
										label = "Two",
										content = function(): Instance
											return UI.VirtualList("Rows")({
												from = rows,
												key = function(item)
													return item.id
												end,
												itemSize = 20,
												render = function(current): GuiObject
													return UI.Button("Row")({
														label = function(use: Use)
															return use(current).label
														end,
													})
												end,
											})
										end,
									} :: FixtureNavigationTypes.Tab,
								},
							})
						end)
						local deep = find(world.screen, "Deep")
						world.gui.SelectedObject = deep
						action(world.screen, "NextTab").Pressed:Fire()
						Verify.expect((selection:peek())):toBe("two")
						local list = find(world.screen, "Rows")
						list.AbsoluteWindowSize = V2(world, 200, 120)
						if restore then
							Verify.expect((within(world.gui.SelectedObject, list))):toBe(true)
						end
						local rowFive = find(list, "5")
						Verify.expect(rowFive ~= nil):toBe(true)
						local target = find(rowFive, "Row")
						world.gui.SelectedObject = target
						target.SelectionGained:Fire()
						action(world.screen, "PreviousTab").Pressed:Fire()
						Verify.expect((selection:peek())):toBe("one")
						if restore then
							Verify.expect(world.gui.SelectedObject):toBe(deep)
						else
							Verify.expect(world.gui.SelectedObject ~= deep):toBe(true)
						end
						world.gui.SelectedObject = deep
						action(world.screen, "NextTab").Pressed:Fire()
						Verify.expect((selection:peek())):toBe("two")
						if restore then
							Verify.expect(world.gui.SelectedObject):toBe(target)
						else
							Verify.expect(world.gui.SelectedObject ~= target):toBe(true)
						end
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case("extends reversed and focus-anchored ranges and toggles additive taps in edit mode", {
			id = "native_parity_weaker_focus::native parity weaker focus::extends reversed and focus-anchored ranges and toggles additive taps in edit mode",
			run = function()
				local shifted = false
				local selected = Compose.cell({})
				local world = setup(function(UI: FacetControls)
					return UI.Table({
						from = (function()
							local rows = {}
							for index = 1, 20 do
								rows[index] = { id = index, label = tostring(index) }
							end
							return rows
						end)(),
						key = function(item)
							return item.id
						end,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						editing = true,
						itemSize = 20,
						overscan = 0,
						columns = { { id = "label", label = "Label" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end)
				world.input.IsKeyDown = function(_, code)
					return shifted and (code.Name == "LeftShift" or code.Name == "RightShift")
				end
				local Enum = world.engine.types.Enum
				local body = find(world.screen, "Body")
				body.AbsoluteWindowSize = V2(world, 200, 400)
				local function hit(index: number): any
					return body:FindFirstChild(tostring(index), true):FindFirstChild("RowHit", true)
				end
				local function keysOf(): { number }
					local out = {}
					for index in selected:peek() do
						table.insert(out, index)
					end
					table.sort(out)
					return out
				end
				local touch = { UserInputType = Enum.UserInputType.Touch }
				local keyboard = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Return }
				local gamepad = { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA }
				hit(10).Activated:Fire(touch)
				shifted = true
				hit(3).Activated:Fire(touch)
				shifted = false
				Verify.expect((keysOf())):toEqual({ 3, 4, 5, 6, 7, 8, 9, 10 })
				selected:set({})
				hit(2).Activated:Fire(touch)
				hit(5).Activated:Fire(touch)
				Verify.expect((keysOf())):toEqual({ 2, 5 })
				hit(2).Activated:Fire(touch)
				Verify.expect((keysOf())):toEqual({ 5 })
				selected:set({})
				world.gui.SelectedObject = hit(4)
				hit(4).SelectionGained:Fire()
				hit(4).Activated:Fire(keyboard)
				Verify.expect((keysOf())):toEqual({ 4 })
				local down = action(world.screen, "CollectionDown")
				down.Pressed:Fire()
				down.Pressed:Fire()
				Verify.expect(world.gui.SelectedObject):toBe(hit(6))
				Verify.expect((keysOf())):toEqual({ 4 })
				shifted = true
				hit(6).Activated:Fire(keyboard)
				Verify.expect((keysOf())):toEqual({ 4, 5, 6 })
				hit(1).Activated:Fire(gamepad)
				shifted = false
				Verify.expect((keysOf())):toEqual({ 1, 2, 3, 4 })
				world.stop()
				local single = Compose.cell({})
				local singleWorld = setup(function(UI: FacetControls)
					return UI.Table({
						from = { { id = 1 }, { id = 2 }, { id = 3 } },
						key = function(item)
							return item.id
						end,
						selection = single,
						selectionMode = "single" :: "single",
						columns = { { id = "id", label = "Id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end)
				local singleBody = find(singleWorld.screen, "Body")
				singleBody.AbsoluteWindowSize = V2(singleWorld, 200, 400)
				singleBody:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated:Fire(touch)
				singleBody:FindFirstChild("3", true):FindFirstChild("RowHit", true).Activated:Fire(touch)
				Verify.expect((single:peek())):toEqual({ [3] = true })
				singleWorld.stop()
			end,
		})

		verifyHarness:case("toggles multi selection from the pad in edit mode without a focus landing undoing it", {
			id = "native_parity_weaker_focus::native parity weaker focus::toggles multi selection from the pad in edit mode without a focus landing undoing it",
			run = function()
				local selected, editing = Compose.cell({}), Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Table({
						from = { { id = 1 }, { id = 2 }, { id = 3 } },
						key = function(item)
							return item.id
						end,
						selection = selected,
						selectionMode = "multiple" :: "multiple",
						editing = editing,
						rowActions = function(): RowActions?
							return {
								trailing = {
									{ id = "Remove", label = "Remove", role = "destructive" :: "destructive" } :: FixtureCollectionTypes.RowAction,
								},
							}
						end,
						columns = { { id = "id", label = "Id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end)
				local Enum = world.engine.types.Enum
				local body = find(world.screen, "Body")
				body.AbsoluteWindowSize = V2(world, 200, 400)
				local gamepad = { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA }
				local two = body:FindFirstChild("2", true):FindFirstChild("RowHit", true)
				local three = body:FindFirstChild("3", true):FindFirstChild("RowHit", true)
				world.gui.SelectedObject = two
				two.SelectionGained:Fire()
				two.Activated:Fire(gamepad)
				Verify.expect((selected:peek())):toEqual({ [2] = true })
				two.SelectionLost:Fire()
				world.gui.SelectedObject = three
				three.SelectionGained:Fire()
				three.SelectionLost:Fire()
				world.gui.SelectedObject = two
				two.SelectionGained:Fire()
				Verify.expect((selected:peek())):toEqual({ [2] = true })
				three.Activated:Fire(gamepad)
				Verify.expect((selected:peek())):toEqual({ [2] = true, [3] = true })
				two.Activated:Fire(gamepad)
				Verify.expect((selected:peek())):toEqual({ [3] = true })
				Verify.expect((editing:peek())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("keeps collection focus on its key through a re-sort and a table sort change", {
			id = "native_parity_weaker_focus::native parity weaker focus::keeps collection focus on its key through a re-sort and a table sort change",
			run = function()
				local source = Compose.cell({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 } })
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local world = setup(function(UI: FacetControls)
					return UI.VirtualList({
						from = source,
						key = function(item)
							return item.id
						end,
						itemSize = 20,
						focus = focus,
						render = function(current): GuiObject
							return UI.Button("Row")({
								label = function(use: Use)
									return tostring(use(current).id)
								end,
							})
						end,
					})
				end)
				local list = world.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
				list.AbsoluteWindowSize = V2(world, 200, 200)
				assert(focus.focus)(3)
				local before = world.gui.SelectedObject
				Verify.expect(before.Text):toBe("3")
				source:set({ { id = 5 }, { id = 4 }, { id = 3 }, { id = 2 }, { id = 1 } })
				Verify.expect((assert(focus.current):peek())):toBe(3)
				Verify.expect(world.gui.SelectedObject.Text):toBe("3")
				source:set({ { id = 3 }, { id = 1 }, { id = 5 } })
				Verify.expect((assert(focus.current):peek())):toBe(3)
				Verify.expect(world.gui.SelectedObject.Text):toBe("3")
				action(world.screen, "CollectionDown").Pressed:Fire()
				Verify.expect((assert(focus.current):peek())):toBe(1)
				Verify.expect(world.gui.SelectedObject.Text):toBe("1")
				world.stop()
				local sort = Compose.cell(nil :: any)
				local tableWorld = setup(function(UI: FacetControls)
					return UI.Table({
						from = { { id = 1, name = "c" }, { id = 2, name = "a" }, { id = 3, name = "b" } },
						key = function(item)
							return item.id
						end,
						sort = sort,
						selection = Compose.cell({}),
						columns = {
							{
								id = "name",
								label = "Name",
								value = function(item)
									return item.name
								end,
							} :: FixtureCollectionTypes.TableColumn<any, any>,
						},
					})
				end)
				local body = find(tableWorld.screen, "Body")
				body.AbsoluteWindowSize = V2(tableWorld, 200, 400)
				local hit = body:FindFirstChild("3", true):FindFirstChild("RowHit", true)
				tableWorld.gui.SelectedObject = hit
				hit.SelectionGained:Fire()
				sort:set({ column = "name", direction = "descending" :: "descending" })
				Verify.expect(tableWorld.gui.SelectedObject):toBe(hit)
				Verify.expect((within(hit, body:FindFirstChild("3", true)))):toBe(true)
				action(tableWorld.screen, "CollectionDown").Pressed:Fire()
				Verify.expect((within(tableWorld.gui.SelectedObject, body:FindFirstChild("2", true)))):toBe(true)
				tableWorld.stop()
			end,
		})

		verifyHarness:case("never strands selection on a removed focused row and skips disabled table rows", {
			id = "native_parity_weaker_focus::native parity weaker focus::never strands selection on a removed focused row and skips disabled table rows",
			run = function()
				local source = Compose.cell({ { id = 1 }, { id = 2 }, { id = 3 } })
				local focus: FixtureCollectionTypes.FocusControls<any> = {}
				local world = setup(function(UI: FacetControls)
					return UI.VirtualList({
						from = source,
						key = function(item)
							return item.id
						end,
						itemSize = 20,
						focus = focus,
						render = function(current): GuiObject
							return UI.Button("Row")({
								label = function(use: Use)
									return tostring(use(current).id)
								end,
							})
						end,
					})
				end)
				local list = world.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
				list.AbsoluteWindowSize = V2(world, 200, 200)
				assert(focus.focus)(2)
				local removed = world.gui.SelectedObject
				Verify.expect(removed.Text):toBe("2")
				source:set({ { id = 1 }, { id = 3 } })
				Verify.expect(world.gui.SelectedObject == removed):toBe(false)
				Verify.expect(world.gui.SelectedObject == nil or not world.gui.SelectedObject:isDestroyed()):toBe(true)
				world.stop()
				local selected, activated = Compose.cell({}), 0
				local tableWorld = setup(function(UI: FacetControls)
					return UI.Table({
						from = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } },
						key = function(item)
							return item.id
						end,
						selection = selected,
						disabled = function(item)
							return item.id == 2 or item.id == 3
						end,
						onActivate = function()
							activated += 1
						end,
						columns = { { id = "id", label = "Id" } :: FixtureCollectionTypes.TableColumn<any, any> },
					})
				end)
				local body = find(tableWorld.screen, "Body")
				body.AbsoluteWindowSize = V2(tableWorld, 200, 400)
				local first = body:FindFirstChild("1", true):FindFirstChild("RowHit", true)
				local skipped = body:FindFirstChild("2", true):FindFirstChild("RowHit", true)
				Verify.expect(skipped.Interactable):toBe(false)
				tableWorld.gui.SelectedObject = first
				first.SelectionGained:Fire()
				action(tableWorld.screen, "CollectionDown").Pressed:Fire()
				Verify.expect((within(tableWorld.gui.SelectedObject, body:FindFirstChild("4", true)))):toBe(true)
				action(tableWorld.screen, "CollectionUp").Pressed:Fire()
				Verify.expect((within(tableWorld.gui.SelectedObject, body:FindFirstChild("1", true)))):toBe(true)
				skipped.Activated:Fire({ UserInputType = tableWorld.engine.types.Enum.UserInputType.Touch })
				Verify.expect((selected:peek())):toEqual({})
				Verify.expect(activated):toBe(0)
				tableWorld.stop()
			end,
		})

		verifyHarness:case(
			"releases the minimum-side arrow at the bound while bumpers stay bound, also inside a list row",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::releases the minimum-side arrow at the bound while bumpers stay bound, also inside a list row",
				run = function()
					local value = Compose.cell(1)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Rating("Stars")({ value = value }) :: unknown,
							UI.Slider("Volume")({ value = Compose.cell(0.5) }),
						})
					end)
					local stars = find(world.screen, "Stars")
					world.gui.SelectedObject = stars
					stars.SelectionGained:Fire()
					local decrease, increase =
						action(world.screen, "DecreaseArrow"), action(world.screen, "IncreaseArrow")
					local bumper = action(world.screen, "Decrease")
					Verify.expect(#contexts(world.screen, "DecreaseArrow")):toBe(1)
					decrease.Pressed:Fire()
					Verify.expect((value:peek())):toBe(0)
					decrease.Released:Fire()
					Verify.expect(decrease.Parent.Enabled):toBe(false)
					Verify.expect(stars.NextSelectionLeft ~= stars):toBe(true)
					Verify.expect(stars.NextSelectionRight):toBe(stars)
					Verify.expect(increase.Parent.Enabled):toBe(true)
					Verify.expect(bumper.Parent.Enabled):toBe(true)
					bumper.Pressed:Fire()
					Verify.expect((value:peek())):toBe(0)
					Verify.expect(bumper.Parent.Enabled):toBe(true)
					increase.Pressed:Fire()
					Verify.expect((value:peek())):toBe(1)
					Verify.expect(decrease.Parent.Enabled):toBe(true)
					world.stop()
					local rated = Compose.cell(3)
					local listWorld = setup(function(UI: FacetControls)
						return UI.VirtualList({
							from = { { id = 1 }, { id = 2 } },
							key = function(item)
								return item.id
							end,
							itemSize = 44,
							render = function(): GuiObject
								return UI.Rating("Stars")({ value = rated })
							end,
						})
					end)
					local list = listWorld.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
					list.AbsoluteWindowSize = V2(listWorld, 300, 200)
					local rowStars = find(find(list, "1"), "Stars")
					listWorld.gui.SelectedObject = rowStars
					rowStars.SelectionGained:Fire()
					local function winner(keyName: string): any
						local best
						for _, context in listWorld.screen:GetDescendants() do
							if context:IsA("InputContext") and context.Enabled then
								for _, inputAction in context:GetChildren() do
									if table.find(keys(inputAction), keyName) then
										if best == nil or context.Priority > best.Parent.Priority then
											best = inputAction
										end
									end
								end
							end
						end
						return best
					end
					Verify.expect(winner("Right").Name):toBe("IncreaseArrow")
					Verify.expect(winner("Left").Name):toBe("DecreaseArrow")
					local right = winner("Right")
					right.Pressed:Fire()
					right.Released:Fire()
					right.Pressed:Fire()
					Verify.expect((rated:peek())):toBe(5)
					right.Released:Fire()
					local past = winner("Right")
					Verify.expect(past == nil or past.Name ~= "IncreaseArrow"):toBe(true)
					Verify.expect(winner("Left").Name):toBe("DecreaseArrow")
					Verify.expect(winner("Down").Name):toBe("CollectionDown")
					listWorld.stop()
				end,
			}
		)

		verifyHarness:case(
			"captures selection in the avatar look sheet and reset alert and returns it to their openers",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::captures selection in the avatar look sheet and reset alert and returns it to their openers",
				run = function()
					local Roblox = Facet.Roblox
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
						local stop, avatar: any = runtime.mount(views.Avatar, target)
						local summary = find(find(avatar, "SummaryActions"), "Summary")
						for _, route in { "back", "done" } do
							gui.SelectedObject = summary
							summary.Activated:Fire()
							Verify.expect((model.avatarSummary:peek())):toBe(true)
							local panel = find(target, "SheetPanel")
							Verify.expect(panel ~= nil):toBe(true)
							Verify.expect((within(gui.SelectedObject, panel))):toBe(true)
							Verify.expect(panel.SelectionGroup):toBe(true)
							if route == "back" then
								action(target, "ModalBack").Pressed:Fire()
							else
								find(panel, "Done").Activated:Fire()
							end
							Verify.expect((model.avatarSummary:peek())):toBe(false)
							Verify.expect((find(target, "SheetPanel"))):toBeNil()
							Verify.expect(gui.SelectedObject):toBe(summary)
						end
						local reset = find(avatar, "Reset")
						gui.SelectedObject = reset
						reset.Activated:Fire()
						Verify.expect((model.resetAvatarPresented:peek())):toBe(true)
						Verify.expect(gui.SelectedObject.Name):toBe("cancel")
						action(target, "ModalBack").Pressed:Fire()
						Verify.expect((model.resetAvatarPresented:peek())):toBe(false)
						Verify.expect(gui.SelectedObject):toBe(reset)
						stop()
					end, runtime.reactor)
					lifetime.dispose()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"overlapping radials hold engine pad navigation off until the last closes, then restore the game's value",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::overlapping radials hold engine pad navigation off until the last closes, then restore the game's value",
				run = function()
					local a, b = Compose.cell(false), Compose.cell(false)
					local function wheel(UI: any, opened: any): any
						return UI.RadialMenu({
							isPresented = opened,
							launcher = false,
							items = {
								{ id = "North", label = "North", onSelect = function() end } :: FixtureRadialTypes.RadialItem<any>,
							},
						})
					end
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({ wheel(UI, a) :: unknown, wheel(UI, b) })
					end, { motionLevel = "none" })
					world.gui.GuiNavigationEnabled = true
					a:set(true)
					Verify.expect(world.gui.GuiNavigationEnabled):toBe(false)
					b:set(true)
					a:set(false)
					Verify.expect(world.gui.GuiNavigationEnabled):toBe(false)
					b:set(false)
					Verify.expect(world.gui.GuiNavigationEnabled):toBe(true)
					world.gui.GuiNavigationEnabled = false
					a:set(true)
					a:set(false)
					Verify.expect(world.gui.GuiNavigationEnabled):toBe(false)
					world.gui.GuiNavigationEnabled = true
					a:set(true)
					world.gui.GuiNavigationEnabled = true
					world.gui.GuiNavigationEnabled = false
					a:set(false)
					Verify.expect(world.gui.GuiNavigationEnabled):toBe(false)
					world.stop()
				end,
			}
		)

		verifyHarness:case("previews radial aim without committing and closes on semantic Back one level at a time", {
			id = "native_parity_weaker_focus::native parity weaker focus::previews radial aim without committing and closes on semantic Back one level at a time",
			run = function()
				local engine: any = engineLib.new()
				local hold = engine.new("InputAction")
				local picked, closes = {}, 0
				local opened = Compose.cell(false)
				local function item(id: string): any
					return {
						id = id,
						label = id,
						onSelect = function()
							table.insert(picked, id)
						end,
					}
				end
				local world = setup(function(UI: FacetControls)
					return UI.RadialMenu({
						isPresented = opened,
						holdAction = hold,
						onClose = function()
							closes += 1
						end,
						items = {
							item("North"),
							{ id = "Branch", label = "Branch", children = { item("Leaf"), item("Other") } } :: FixtureRadialTypes.RadialItem<any>,
							item("South"),
							item("West"),
						},
					})
				end, { motionLevel = "none" })
				world.gui.GuiNavigationEnabled = true
				hold.Pressed:Fire()

				Verify.expect(world.gui.GuiNavigationEnabled):toBe(false)
				local axis = action(world.screen, "RadialAim")
				axis.StateChanged:Fire(V2(world, 0, 0.9))
				Verify.expect(world.gui.SelectedObject.Name):toBe("North")
				axis.StateChanged:Fire(V2(world, 0.9, 0))
				Verify.expect(world.gui.SelectedObject.Name):toBe("Branch")
				Verify.expect(#picked):toBe(0)
				local back = action(world.screen, "ModalBack")
				Verify.expect((keys(back))):toEqual({ "ButtonB", "Escape" })
				back.Pressed:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect(world.gui.GuiNavigationEnabled):toBe(true)
				Verify.expect(closes):toBe(1)
				Verify.expect(#picked):toBe(0)
				hold.Released:Fire()
				Verify.expect(#picked):toBe(0)
				opened:set(true)
				local branch = find(world.screen, "Branch")
				world.gui.SelectedObject = branch
				branch.Activated:Fire()
				Verify.expect(find(world.screen, "Leaf") ~= nil):toBe(true)
				action(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(true)
				Verify.expect((find(world.screen, "Leaf"))):toBeNil()
				action(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect(closes):toBe(2)
				Verify.expect(#picked):toBe(0)
				world.stop()
			end,
		})

		verifyHarness:case(
			"activates a selected button once per Return or Space press and leaves a disabled one inert",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::activates a selected button once per Return or Space press and leaves a disabled one inert",
				run = function()
					local enabled, count = Compose.cell(true), 0
					local world = setup(function(UI: FacetControls)
						return UI.Button("Go")({
							label = "Go",
							enabled = enabled,
							onActivate = function()
								count += 1
							end,
						})
					end)
					local go = find(world.screen, "Go")
					world.gui.SelectedObject = go
					local activate = action(world.screen, "Activate")
					Verify.expect((keys(activate))):toEqual({ "Return", "Space" })
					Verify.expect(activate.Parent.Sink):toBe(true)
					Verify.expect(#contexts(world.screen, "Activate")):toBe(1)
					activate.Pressed:Fire()
					Verify.expect(count):toBe(1)
					activate.Released:Fire()
					Verify.expect(count):toBe(1)
					activate.Pressed:Fire()
					Verify.expect(count):toBe(2)
					enabled:set(false)
					Verify.expect(go.Selectable):toBe(false)
					Verify.expect(go.Interactable):toBe(false)
					Verify.expect(activate.Parent.Enabled):toBe(false)
					activate.Pressed:Fire()
					go.Activated:Fire()
					Verify.expect(count):toBe(2)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"deletes with Delete or Backspace through the first enabled destructive action, trailing first",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::deletes with Delete or Backspace through the first enabled destructive action, trailing first",
				run = function()
					for _, variant in { "trailing", "leading", "none" } do
						local invoked = {}
						local function recorder(id: string, role: string?, enabledValue: boolean?): any
							return {
								id = id,
								label = id,
								role = role,
								enabled = enabledValue,
								onActivate = function()
									table.insert(invoked, id)
								end,
							}
						end
						local world = setup(function(UI: FacetControls)
							return UI.RowActions({
								content = UI.Button("Action")({ label = "Row" }) :: GuiObject,
								leading = if variant == "none"
									then { recorder("Mark") }
									else { recorder("Archive", "destructive") },
								trailing = if variant == "trailing"
									then {
										recorder("Pin"),
										recorder("Locked", "destructive", false),
										recorder("Erase", "destructive"),
										recorder("Purge", "destructive"),
									}
									else { recorder("Pin") },
							})
						end, { motionLevel = "none" })
						world.gui.SelectedObject = find(world.screen, "Action")
						local deletes = contexts(world.screen, "RowActionsDelete")
						Verify.expect(#deletes):toBe(1)
						local delete = deletes[1]:FindFirstChild("RowActionsDelete")
						Verify.expect((keys(delete))):toEqual({ "Backspace", "Delete" })
						if variant == "none" then
							Verify.expect(delete.Parent.Enabled):toBe(false)
							delete.Pressed:Fire()
							Verify.expect(invoked):toEqual({})
						else
							Verify.expect(delete.Parent.Enabled):toBe(true)
							delete.Pressed:Fire()
							Verify.expect(invoked):toEqual({ if variant == "trailing" then "Erase" else "Archive" })
						end
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"repeats touch, keyboard and gamepad holds and suppresses the trailing activation in either order",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::repeats touch, keyboard and gamepad holds and suppresses the trailing activation in either order",
				run = function()
					local Enum: any
					for _, kind in
						{ "Touch", "Return", "Space", "ButtonA" } :: { "ButtonA" | "Return" | "Space" | "Touch" }
					do
						for _, order in { "endFirst", "activatedFirst" } do
							local count = 0
							local world = setup(function(UI: FacetControls)
								return UI.Button("Repeat")({
									label = "Repeat",
									repeatDelay = 0.4,
									repeatInterval = 0.1,
									onActivate = function()
										count += 1
									end,
								})
							end)
							Enum = world.engine.types.Enum
							local node = find(world.screen, "Repeat")
							local input = if kind == "Touch"
								then { UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode:FromValue(0) }
								elseif kind == "ButtonA" then {
									UserInputType = Enum.UserInputType.Gamepad1,
									KeyCode = Enum.KeyCode.ButtonA,
								}
								else {
									UserInputType = Enum.UserInputType.Keyboard,
									KeyCode = (Enum.KeyCode :: any)[kind],
								}
							node.InputBegan:Fire(input)
							world.engine.heartbeat:Fire(0.3)
							Verify.expect(count):toBe(0)
							world.engine.heartbeat:Fire(0.1)
							world.engine.heartbeat:Fire(0.1)
							world.engine.heartbeat:Fire(0.1)
							Verify.expect(count):toBe(3)
							if order == "endFirst" then
								node.InputEnded:Fire(input)
								node.Activated:Fire(input)
							else
								node.Activated:Fire(input)
								node.InputEnded:Fire(input)
							end
							Verify.expect(count):toBe(3)
							world.engine.heartbeat:Fire(1)
							Verify.expect(count):toBe(3)
							node.InputBegan:Fire(input)
							world.engine.heartbeat:Fire(0.1)
							node.InputEnded:Fire(input)
							node.Activated:Fire(input)
							Verify.expect(count):toBe(4)
							world.stop()
						end
					end
				end,
			}
		)

		verifyHarness:case("stops a held repeat when busy begins and keeps the next shortcut after a pointer leaves", {
			id = "native_parity_weaker_focus::native parity weaker focus::stops a held repeat when busy begins and keeps the next shortcut after a pointer leaves",
			run = function()
				local busy, count = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls)
					return UI.Button("Repeat")({
						label = "Repeat",
						busy = busy,
						repeatDelay = 0.4,
						repeatInterval = 0.1,
						shortcut = { keyCode = "F6" },
						onActivate = function()
							count += 1
						end,
					})
				end)
				local Enum = world.engine.types.Enum
				local node = find(world.screen, "Repeat")
				local mouse = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode:FromValue(0) }
				local shortcut = action(world.screen, "Shortcut")
				node.InputBegan:Fire(mouse)
				world.engine.heartbeat:Fire(0.4)
				Verify.expect(count):toBe(1)
				busy:set(true)
				world.engine.heartbeat:Fire(0.1)
				world.engine.heartbeat:Fire(0.4)
				Verify.expect(count):toBe(1)
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(1)
				busy:set(false)
				world.engine.heartbeat:Fire(0.4)
				Verify.expect(count):toBe(1)
				node.InputEnded:Fire(mouse)
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(2)
				node.InputBegan:Fire(mouse)
				world.engine.heartbeat:Fire(0.4)
				Verify.expect(count):toBe(3)
				node.MouseLeave:Fire()
				world.engine.heartbeat:Fire(0.4)
				Verify.expect(count):toBe(3)
				shortcut.Pressed:Fire()
				Verify.expect(count):toBe(4)
				world.stop()
			end,
		})

		verifyHarness:case("keeps readable key names and no glyph when the native key service fails", {
			id = "native_parity_weaker_focus::native parity weaker focus::keeps readable key names and no glyph when the native key service fails",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local gui = engine.new("GuiService")
				local failing = engine.new("UserInputService")
				failing.GetStringForKeyCode = function()
					error("native service unavailable")
				end
				failing.GetImageForKeyCode = function()
					error("native service unavailable")
				end
				failing.GetFocusedTextBox = function()
					return nil
				end
				local UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						guiService = gui,
						services = { GuiService = gui, UserInputService = failing },
					} :: any
				)
				local stop, screen: any = runtime.mount(function()
					local inputAction, binding = engine.new("InputAction"), engine.new("InputBinding")
					binding.KeyCode, binding.DisplayName = engine.types.Enum.KeyCode.Return, ""
					binding.PrimaryModifier = engine.types.Enum.KeyCode.LeftShift
					inputAction.PreferredBinding = binding
					local rightAction, rightBinding = engine.new("InputAction"), engine.new("InputBinding")
					rightBinding.KeyCode, rightBinding.DisplayName = engine.types.Enum.KeyCode.J, ""
					rightBinding.PrimaryModifier = engine.types.Enum.KeyCode.RightShift
					rightAction.PreferredBinding = rightBinding
					return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
						UI.ShortcutHint("Hint")({ action = inputAction }) :: unknown,
						UI.ShortcutHint("Right")({ action = rightAction }),
					})
				end, engine.new("Folder"))
				Verify.expect(find(find(screen, "Hint"), "Key").Text):toBe("Shift+Enter")
				Verify.expect(find(find(screen, "Right"), "Key").Text):toBe("Shift+J")
				Verify.expect((find(screen, "Glyph"))):toBeNil()
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("tracks separator and control rung on the same hint node without a rebuild", {
			id = "native_parity_weaker_focus::native parity weaker focus::tracks separator and control rung on the same hint node without a rebuild",
			run = function()
				local separator, rung =
					Compose.cell("or"), Compose.cell("compact" :: "compact" | "large" | "regular" | "xsmall")
				local world = setup(function(UI: FacetControls, Host: RobloxHost, engine)
					local inputAction, binding = engine.new("InputAction"), engine.new("InputBinding")
					binding.KeyCode = engine.types.Enum.KeyCode.ButtonX
					inputAction.PreferredBinding = binding
					return Host.Frame({
						UI.ShortcutHint("Explicit")({
							keys = { { "Ctrl", "K" }, { "F1" } },
							separator = separator,
							controlSize = rung,
						}) :: unknown,
						UI.ShortcutHint("Live")({ action = inputAction, controlSize = rung }),
					})
				end, {
					prepare = function(_, input)
						input.GetImageForKeyCode = function()
							return "rbxasset://textures/ui/Controls/xboxX.png"
						end
						input.GetStringForKeyCode = function()
							return ""
						end
					end,
				})
				local explicit = find(world.screen, "Explicit")
				local glyph = find(find(world.screen, "Live"), "Glyph")
				Verify.expect(explicit.Text):toBe("Ctrl+K or F1")
				local compactHeight, compactGlyph = explicit.Size.Y.Offset, glyph.Size.X.Offset
				separator:set("ou")
				rung:set("large")
				Verify.expect((find(world.screen, "Explicit"))):toBe(explicit)
				Verify.expect((find(find(world.screen, "Live"), "Glyph"))):toBe(glyph)
				Verify.expect(explicit.Text):toBe("Ctrl+K ou F1")
				Verify.expect(explicit.Size.Y.Offset > compactHeight):toBe(true)
				Verify.expect(glyph.Size.X.Offset > compactGlyph):toBe(true)
				rung:set("regular")
				Verify.expect(explicit.Size.Y.Offset > compactHeight):toBe(true)
				Verify.expect(explicit.Size.Y.Offset < 32 + 1):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("refuses every malformed shortcut hint declaration without native leftovers", {
			id = "native_parity_weaker_focus::native parity weaker focus::refuses every malformed shortcut hint declaration without native leftovers",
			run = function()
				local cases: { [string]: (any) -> { [string]: any } } = {
					missing = function()
						return {}
					end,
					both = function(engine)
						return { action = engine.new("InputAction"), keys = { { "K" } } }
					end,
					emptyAction = function()
						return { action = "" }
					end,
					boundAction = function()
						return { action = Compose.cell("Activate") }
					end,
					notAction = function(engine)
						return { action = engine.new("Frame") }
					end,
					emptyKeys = function()
						return { keys = {} }
					end,
					emptyChord = function()
						return { keys = { {} } }
					end,
					badKey = function()
						return { keys = { { 3 } } }
					end,
					emptyKey = function()
						return { keys = { { "" } } }
					end,
					separatorOnAction = function(engine)
						return { action = engine.new("InputAction"), separator = "or" }
					end,
					emptySeparator = function()
						return { keys = { { "K" } }, separator = Compose.cell("") }
					end,
					size = function()
						return { keys = { { "K" } }, controlSize = "huge" :: "huge" }
					end,
					over = function()
						return { keys = { { "K" } }, over = "photo" }
					end,
					unknown = function()
						return { keys = { { "K" } }, typo = true }
					end,
				}
				for name, build in cases do
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } } :: any)
					local spec = build(engine)
					local folder = engine.new("Folder")
					local ok = pcall(function()
						local stop = runtime.mount(function()
							return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
								UI.ShortcutHint(spec :: any),
							})
						end, folder)
						stop()
					end)
					runtime:dispose()
					Verify.expect(if ok then name else "refused"):toBe("refused")
					local leftovers = 0
					for _, node in engine.made do
						if
							not node:isDestroyed()
							and node ~= gui
							and node ~= folder
							and node.ClassName ~= "InputAction"
							and node.ClassName ~= "Frame"
						then
							leftovers += 1
						end
					end
					Verify.expect(leftovers):toBe(0)
					Verify.expect(#folder:GetChildren()):toBe(0)
				end
			end,
		})

		verifyHarness:case("selects an indicated picker option once by tap and by Return on the selected segment", {
			id = "native_parity_weaker_focus::native parity weaker focus::selects an indicated picker option once by tap and by Return on the selected segment",
			run = function()
				local selected, changes = Compose.cell("a"), 0
				local world = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = selected,
						style = "segmented" :: "segmented",
						indicator = "underline" :: "underline",
						onChange = function()
							changes += 1
						end,
						options = {
							{ value = "a", label = "Alpha" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "Beta" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "c", label = "Gamma", enabled = false } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end)
				local Enum = world.engine.types.Enum
				local b, c = find(world.screen, "b"), find(world.screen, "c")
				Verify.expect(b.Selectable):toBe(true)
				world.gui.SelectedObject = b
				local activate = action(world.screen, "Activate")
				Verify.expect((keys(activate))):toEqual({ "Return", "Space" })
				activate.Pressed:Fire()
				Verify.expect((selected:peek())):toBe("b")
				Verify.expect(find(b, "SelectionIndicator") ~= nil):toBe(true)
				Verify.expect((find(find(world.screen, "a"), "SelectionIndicator"))):toBeNil()
				activate.Pressed:Fire()
				Verify.expect(changes):toBe(1)
				find(world.screen, "a").Activated:Fire({ UserInputType = Enum.UserInputType.Touch })
				Verify.expect((selected:peek())):toBe("a")
				Verify.expect(changes):toBe(2)
				Verify.expect(c.Selectable):toBe(false)
				world.gui.SelectedObject = c
				Verify.expect(world.gui.SelectedObject):toBe(b)
				c.Activated:Fire()
				Verify.expect((selected:peek())):toBe("a")
				world.stop()
			end,
		})

		verifyHarness:case(
			"a tap or click on the grabber closes the sheet; Return and A grow it and close from the tallest",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::a tap or click on the grabber closes the sheet; Return and A grow it and close from the tallest",
				run = function()
					for _, kind in { "Touch", "MouseButton1" } :: { "MouseButton1" | "Touch" } do
						local presented = Compose.cell(true)
						local detent = Compose.cell("peek")
						local world = setup(function(UI: FacetControls)
							return UI.Sheet({
								isPresented = presented,
								detent = detent,
								detents = { "medium", "large", { id = "peek", height = 160 } } :: { SheetDetent },
								content = function(): Instance
									return UI.Button({ label = "Inside" })
								end,
							})
						end)
						local Enum = world.engine.types.Enum
						find(world.screen, "Grabber").Activated:Fire({ UserInputType = Enum.UserInputType[kind] })
						Verify.expect(`{kind}: {tostring(presented:peek())} {detent:peek()}`):toBe(`{kind}: false peek`)
						world.stop()
					end
					local held = Compose.cell("peek")
					local locked = setup(function(UI: FacetControls)
						return UI.Sheet({
							isPresented = Compose.cell(true),
							detent = held,
							detents = { "medium", { id = "peek", height = 160 } } :: { SheetDetent },
							interactiveDismissDisabled = true,
							content = function(): Instance
								return UI.Button({ label = "Inside" })
							end,
						})
					end)
					local Enum = locked.engine.types.Enum
					find(locked.screen, "Grabber").Activated:Fire({ UserInputType = Enum.UserInputType.Touch })
					Verify.expect((held:peek())):toBe("medium")
					locked.stop()
					local detent = Compose.cell("peek")
					local presented = Compose.cell(true)
					local world = setup(function(UI: FacetControls)
						return UI.Sheet({
							isPresented = presented,
							detent = detent,
							detents = { "medium", "large", { id = "peek", height = 160 } } :: { SheetDetent },
							content = function(): Instance
								return UI.Button({ label = "Inside" })
							end,
						})
					end)
					local grabber = find(world.screen, "Grabber")
					world.gui.SelectedObject = grabber
					grabber.Activated:Fire({
						UserInputType = Enum.UserInputType.Keyboard,
						KeyCode = Enum.KeyCode.Return,
					})
					Verify.expect((detent:peek())):toBe("medium")
					grabber.Activated:Fire({
						UserInputType = Enum.UserInputType.Gamepad1,
						KeyCode = Enum.KeyCode.ButtonA,
					})
					Verify.expect((detent:peek())):toBe("large")
					grabber.Activated:Fire({
						UserInputType = Enum.UserInputType.Gamepad1,
						KeyCode = Enum.KeyCode.ButtonA,
					})
					Verify.expect((presented:peek())):toBe(false)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"the grabber's own drag detector reads a still press as a tap that closes, and a drag as a resize",
			{
				id = "native_parity_weaker_focus::native parity weaker focus::the grabber's own drag detector reads a still press as a tap that closes, and a drag as a resize",
				run = function()
					for _, case: { direction: "right" | nil, x: number | typeof(-10), y: typeof(-10) | number } in
						{ { direction = nil, x = 0, y = -10 }, { direction = "right" :: "right", x = -10, y = 0 } } :: { { direction: "right" | nil, x: number | typeof(-10), y: typeof(-10) | number } }
					do
						for _, travel in { 1, 10 } do
							local presented = Compose.cell(true)
							local world = setup(function(UI: FacetControls)
								return UI.Sheet({
									isPresented = presented,
									detent = Compose.cell("medium"),
									edge = case.direction,
									placement = if case.direction then "side" :: "side" else nil,
									detents = { "medium", "large" } :: { SheetDetent },
									content = function(): Instance
										return UI.Button({ label = "Inside" })
									end,
								})
							end)
							local V2 = world.engine.types.Vector2
							local detector = find(world.screen, "Grabber"):FindFirstChildWhichIsA("UIDragDetector")
							local scale = travel / 10
							detector.DragStart:Fire(V2.new(200, 400))
							detector.DragContinue:Fire(V2.new(200 + case.x * scale, 400 + case.y * scale))
							detector.DragEnd:Fire()
							Verify.expect(`{tostring(case.direction)} {travel}: {tostring(presented:peek())}`)
								:toBe(`{tostring(case.direction)} {travel}: {tostring(travel > 4)}`)
							world.stop()
						end
					end
				end,
			}
		)

		verifyHarness:case("counts a still grip press once when the engine also activates the grabber", {
			id = "native_parity_weaker_focus::native parity weaker focus::counts a still grip press once when the engine also activates the grabber",
			run = function()
				local detent = Compose.cell("peek")
				local world = setup(function(UI: FacetControls)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = detent,
						interactiveDismissDisabled = true,
						detents = { "medium", "large", { id = "peek", height = 160 } } :: { SheetDetent },
						content = function(): Instance
							return UI.Button({ label = "Inside" })
						end,
					})
				end)
				local grabber = find(world.screen, "Grabber")
				local detector = grabber:FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(world.engine.types.Vector2.new(200, 400))
				detector.DragEnd:Fire()
				grabber.Activated:Fire({ UserInputType = world.engine.types.Enum.UserInputType.Touch })
				Verify.expect((detent:peek())):toBe("medium")
				world.stop()
			end,
		})

		verifyHarness:case("grows sheet detents from the selectable grabber and closes from the tallest", {
			id = "native_parity_weaker_focus::native parity weaker focus::grows sheet detents from the selectable grabber and closes from the tallest",
			run = function()
				local detent = Compose.cell("peek")
				local presented = Compose.cell(true)
				local world = setup(function(UI: FacetControls)
					return UI.Sheet({
						isPresented = presented,
						detent = detent,
						detents = { "medium", "large", { id = "peek", height = 160 } } :: { SheetDetent },
						content = function(): Instance
							return UI.Button({ label = "Inside" })
						end,
					})
				end)
				local Enum = world.engine.types.Enum
				local grabber = find(world.screen, "Grabber")
				Verify.expect((grabber:IsA("GuiButton"))):toBe(true)
				Verify.expect(grabber.Selectable):toBe(true)
				Verify.expect(grabber.Interactable):toBe(true)
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Resize: Peek")
				world.gui.SelectedObject = grabber
				Verify.expect(world.gui.SelectedObject):toBe(grabber)
				grabber.Activated:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Return })
				Verify.expect((detent:peek())):toBe("medium")
				grabber.Activated:Fire()
				Verify.expect((detent:peek())):toBe("large")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				grabber.Activated:Fire({ UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA })
				Verify.expect((presented:peek())):toBe(false)
				world.stop()
				local single = setup(function(UI: FacetControls)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = Compose.cell("large"),
						detents = { "large" } :: { SheetDetent },
						content = function(): Instance
							return UI.Button({ label = "Inside" })
						end,
					})
				end)
				Verify.expect(find(single.screen, "Grabber").Selectable):toBe(true)
				Verify.expect((find(single.screen, "Grabber"):GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				single.stop()
			end,
		})

		verifyHarness:case("a pad-selected grabber leaves A to the button: its drag detector stands down", {
			id = "native_parity_weaker_focus::native parity weaker focus::a pad-selected grabber leaves A to the button: its drag detector stands down",
			run = function()
				local input
				local world = setup(function(UI: FacetControls)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						content = function(): Instance
							return UI.Button({ label = "Inside" })
						end,
					})
				end, {
					prepare = function(_, service)
						input = service
					end,
				})
				local Enum = world.engine.types.Enum
				local grabber = find(world.screen, "Grabber")
				local detector = grabber:FindFirstChildWhichIsA("UIDragDetector")
				Verify.expect(detector.Enabled):toBe(true)
				input.PreferredInput = Enum.PreferredInput.Gamepad
				world.gui.SelectedObject = find(world.screen, "Inside")
				Verify.expect(detector.Enabled):toBe(true)
				world.gui.SelectedObject = grabber
				Verify.expect(detector.Enabled):toBe(false)
				world.gui.SelectedObject = nil
				Verify.expect(detector.Enabled):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("resizes a selected sheet grabber with Left and Right, as the pre-0.12 Adjust did", {
			id = "native_parity_weaker_focus::native parity weaker focus::resizes a selected sheet grabber with Left and Right, as the pre-0.12 Adjust did",
			run = function()
				local detent = Compose.cell("peek")
				local world = setup(function(UI: FacetControls)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = detent,
						detents = { "medium", "large", { id = "peek", height = 160 } } :: { SheetDetent },
						content = function(): Instance
							return UI.Button({ label = "Inside" })
						end,
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Grabber")
				action(world.screen, "IncreaseArrow").Pressed:Fire()
				Verify.expect((detent:peek())):toBe("medium")
				action(world.screen, "IncreaseArrow").Released:Fire()
				action(world.screen, "IncreaseArrow").Pressed:Fire()
				Verify.expect((detent:peek())):toBe("large")
				Verify.expect(action(world.screen, "IncreaseArrow")):toBe(nil)
				action(world.screen, "DecreaseArrow").Pressed:Fire()
				Verify.expect((detent:peek())):toBe("medium")
				world.stop()
			end,
		})

		verifyHarness:case("retakes the modal entry when the engine refuses it before the panel is laid out", {
			id = "native_parity_weaker_focus::native parity weaker focus::retakes the modal entry when the engine refuses it before the panel is laid out",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						UI.Button("Beside")({ label = "Beside" }),
						UI.Sheet({
							isPresented = presented,
							detent = Compose.cell("large"),
							content = function(): Instance
								return Host.Frame("Body")({
									UI.Button("First")({ label = "First" }),
								})
							end,
						}),
					})
				end, {
					prepare = function(engine, input)
						input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
					end,
				})
				local beside = find(world.screen, "Beside")
				local refusals = 0
				local refusing = world.gui:GetPropertyChangedSignal("SelectedObject"):Connect(function()
					local selected = world.gui.SelectedObject
					if
						selected
						and selected.AbsoluteSize.X == 0
						and find(world.screen, "SheetPanel")
						and within(selected, find(world.screen, "SheetPanel"))
					then
						refusals += 1
						world.gui.SelectedObject = beside
					end
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				presented:set(true)
				local panel = find(world.screen, "SheetPanel")
				Verify.expect(refusals >= 1):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(beside)
				local entry
				for _, node in panel:GetDescendants() do
					if entry == nil and node:IsA("GuiObject") and node.Selectable and node.Visible then
						entry = node
					end
				end
				entry.AbsoluteSize = world.engine.types.Vector2.new(88, 44)
				panel.AbsoluteSize = world.engine.types.Vector2.new(600, 400)
				Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
				Verify.expect(world.gui.SelectedObject):toBe(entry)
				world.gui.SelectedObject = beside
				panel.AbsoluteSize = world.engine.types.Vector2.new(600, 420)
				Verify.expect(world.gui.SelectedObject):toBe(beside)
				refusing:Disconnect()
				world.stop()
			end,
		})

		verifyHarness:case("returns the selection to the opener when the engine moves it aside as the modal leaves", {
			id = "native_parity_weaker_focus::native parity weaker focus::returns the selection to the opener when the engine moves it aside as the modal leaves",
			run = function()
				local presented = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						UI.Button("Beside")({ label = "Beside" }),
						UI.Sheet({
							isPresented = presented,
							detent = Compose.cell("large"),
							content = function(): Instance
								return Host.Frame("Body")({
									UI.Button("First")({ label = "First" }),
								})
							end,
						}),
					})
				end)
				local opener, beside = find(world.screen, "Opener"), find(world.screen, "Beside")
				world.gui.SelectedObject = opener
				presented:set(true)
				local panel = find(world.screen, "SheetPanel")
				Verify.expect((within(world.gui.SelectedObject, panel))):toBe(true)
				local root = panel.Parent
				local moved = 0
				local aside = root:GetPropertyChangedSignal("Parent"):Connect(function()
					if root.Parent == nil and within(world.gui.SelectedObject, root) then
						moved += 1
						world.gui.SelectedObject = beside
					end
				end)
				presented:set(false)
				Verify.expect(moved):toBe(1)
				Verify.expect(world.gui.SelectedObject):toBe(opener)
				aside:Disconnect()
				world.gui.SelectedObject = opener
				presented:set(true)
				world.gui.SelectedObject = beside
				presented:set(false)
				Verify.expect(world.gui.SelectedObject):toBe(beside)
				world.stop()
			end,
		})
	end)
end
