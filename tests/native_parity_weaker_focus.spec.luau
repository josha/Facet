--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

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
	local runtime = Facet.Roblox.createRuntime(engine)
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
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
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
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			if winner == nil or node.Priority > winner.Parent.Priority then
				winner = node:FindFirstChild(name)
			end
		end
	end
	return winner
end

local function contexts(root: any, name: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name then
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

t.describe("native parity weaker focus", function()
	t.it("dismisses a sheet with Back and returns selection to the control that opened it", function()
		local presented = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Opener")({ label = "Open" }),
				UI.Sheet({
					isPresented = presented,
					detent = Compose.cell("medium"),
					title = "Options",
					content = function()
						return UI.Button("Inside")({ label = "Inside" })
					end,
				}),
			})
		end)
		local opener = find(world.screen, "Opener")
		world.gui.SelectedObject = opener
		presented:set(true)
		local panel = find(world.screen, "SheetPanel")
		t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
		local back = action(world.screen, "ModalBack")
		t.expect(keys(back)).toEqual({ "ButtonB", "Escape" })
		back.Pressed.fire()
		t.expect(presented:peek()).toBe(false)
		t.expect(find(world.screen, "SheetPanel")).toBeNil()
		t.expect(world.gui.SelectedObject).toBe(opener)
		world.stop()
	end)

	t.it("keeps the scrim out of selection so a rejected scrim selection leaves focus in the modal", function()
		for _, kind in { "Alert", "Sheet" } do
			local presented = Compose.cell(false)
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Button("Opener")({ label = "Open" }),
					if kind == "Alert"
						then UI.Alert({
							isPresented = presented,
							title = "Leave?",
							actions = { { id = "Stay", label = "Stay", role = "cancel" } },
						})
						else UI.Sheet({
							isPresented = presented,
							detent = Compose.cell("medium"),
							content = function()
								return UI.Button("Inside")({ label = "Inside" })
							end,
						}),
				})
			end)
			world.gui.SelectedObject = find(world.screen, "Opener")
			presented:set(true)
			local scrim = find(world.screen, "DismissOutside")
			t.expect(scrim.Selectable).toBe(false)
			local selected = world.gui.SelectedObject
			t.expect(within(selected, scrim.Parent)).toBe(true)
			t.expect(within(selected, scrim)).toBe(false)
			world.gui.SelectedObject = scrim
			t.expect(world.gui.SelectedObject).toBe(selected)
			t.expect(table.find(world.engine.rejectedSelections, scrim) ~= nil).toBe(true)
			world.stop()
		end
	end)

	t.it("dismisses every modal presentation on the default Back without an authored cancel action", function()
		local alert, sheet, menu = Compose.cell(true), Compose.cell(false), Compose.cell(false)
		local accepted = 0
		local world = setup(function(UI, Host)
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
						},
					},
				}),
				UI.Sheet({
					isPresented = sheet,
					detent = Compose.cell("medium"),
					content = function()
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
						},
					},
				}),
			})
		end)
		for _, presented in { alert, sheet, menu } do
			presented:set(true)
			local back = action(world.screen, "ModalBack")
			t.expect(back ~= nil).toBe(true)
			back.Pressed.fire()
			t.expect(presented:peek()).toBe(false)
			t.expect(action(world.screen, "ModalBack")).toBeNil()
		end
		t.expect(accepted).toBe(0)
		world.stop()
	end)

	t.it("keeps Tab and Escape native while an alert owns safe initial selection and Back", function()
		for _, reserved in { "Tab", "Escape" } do
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } } :: any)
			local ok, message = pcall(function()
				local stop = runtime.mount(function()
					return runtime.constructors.ScreenGui({
						UI.Button({ label = "Background", shortcut = { keyCode = reserved } }),
					})
				end, engine.new("Folder"))
				stop()
			end)
			runtime:dispose()
			t.expect(ok).toBe(false)
			t.expect(
				string.find(tostring(message), "Escape and Tab retain native navigation ownership", 1, true) ~= nil
			)
				.toBe(true)
		end
		local presented = Compose.cell(false)
		local shortcutCount, cancelled, deleted = 0, 0, 0
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Background")({
					label = "Background",
					shortcut = { keyCode = "K" },
					onActivate = function()
						shortcutCount += 1
					end,
				}),
				UI.Alert({
					isPresented = presented,
					title = "Delete?",
					actions = {
						{
							id = "Delete",
							label = "Delete",
							role = "destructive",
							onActivate = function()
								deleted += 1
							end,
						},
						{
							id = "Keep",
							label = "Keep",
							role = "cancel",
							onActivate = function()
								cancelled += 1
							end,
						},
					},
				}),
			})
		end)
		local background = find(world.screen, "Background")
		world.gui.SelectedObject = background
		local shortcut = action(world.screen, "Shortcut")
		presented:set(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Keep")
		t.expect(shortcut.Parent.Enabled).toBe(false)
		local back = action(world.screen, "ModalBack")
		t.expect(keys(back)).toEqual({ "ButtonB", "Escape" })
		t.expect(back.Parent.Sink).toBe(true)
		back.Pressed.fire()
		t.expect(cancelled).toBe(1)
		t.expect(deleted).toBe(0)
		t.expect(presented:peek()).toBe(false)
		t.expect(world.gui.SelectedObject).toBe(background)
		t.expect(shortcut.Parent.Enabled).toBe(true)
		shortcut.Pressed.fire()
		t.expect(shortcutCount).toBe(1)
		world.stop()
	end)

	t.it("selects inside a modal only once its screen reaches a PlayerGui", function()
		local engine: any = engineLib.new({ selectionNeedsPlayerGui = true })
		local runtime = Facet.Roblox.createRuntime(engine)
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
		local stop, screen = runtime.mount(function()
			return runtime.constructors.ScreenGui({
				UI.Alert({
					isPresented = Compose.cell(true),
					title = "Leave?",
					actions = { { id = "Stay", label = "Stay" } },
				}),
			})
		end, holder)
		t.expect(find(screen, "AlertPanel") ~= nil).toBe(true)
		t.expect(gui.SelectedObject).toBe(elsewhere)
		screen.Parent = playerGui
		t.expect(gui.SelectedObject ~= nil and gui.SelectedObject.Name == "Stay").toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("groups modal selection and enters at the first selectable control in document order", function()
		local presented = Compose.cell(false)
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				UI.Button("Opener")({ label = "Open" }),
				UI.Sheet({
					isPresented = presented,
					detent = Compose.cell("large"),
					content = function()
						return Host.Frame("Body")({
							Host.UIListLayout({ SortOrder = engine.types.Enum.SortOrder.LayoutOrder }),
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
		t.expect(panel.SelectionGroup).toBe(true)
		for _, direction in { "Up", "Down", "Left", "Right" } do
			t.expect(panel["SelectionBehavior" .. direction]).toBe(world.engine.types.Enum.SelectionBehavior.Stop)
		end
		t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
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
		t.expect(world.gui.SelectedObject).toBe(walk[1])
		local names = {}
		for _, node in walk do
			if node.Name == "First" or node.Name == "Second" or node.Name == "Third" then
				table.insert(names, node.Name)
			end
		end
		t.expect(names).toEqual({ "First", "Second", "Third" })
		for _, node in walk do
			t.expect(within(node, panel)).toBe(true)
		end
		presented:set(false)
		local alertPresented = Compose.cell(false)
		world.stop()
		local alertWorld = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Opener")({ label = "Open" }),
				UI.Alert({
					isPresented = alertPresented,
					title = "Choose",
					actions = {
						{ id = "Off", label = "Off", enabled = false },
						{ id = "One", label = "One" },
						{ id = "Two", label = "Two" },
					},
				}),
			})
		end)
		alertWorld.gui.SelectedObject = find(alertWorld.screen, "Opener")
		alertPresented:set(true)
		t.expect(alertWorld.gui.SelectedObject.Name).toBe("One")
		t.expect(
			find(alertWorld.screen, "Off").Interactable == false or find(alertWorld.screen, "Off").Selectable == false
		)
			.toBe(true)
		alertWorld.stop()
	end)

	t.it("traps an open menu and returns selection to its trigger after outside tap, Back and model close", function()
		for _, route in { "outside", "back", "model" } do
			local opened = Compose.cell(false)
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Button("Elsewhere")({ label = "Elsewhere" }),
					UI.Menu({
						label = "More",
						isPresented = opened,
						items = {
							{ id = "Rename", label = "Rename", onSelect = function() end },
							{ id = "Share", label = "Share", onSelect = function() end },
						},
					}),
				})
			end)
			local trigger = find(world.screen, "Trigger")
			world.gui.SelectedObject = trigger
			trigger.Activated.fire()
			t.expect(opened:peek()).toBe(true)
			local panel = find(world.screen, "MenuPanel")
			t.expect(world.gui.SelectedObject.Name).toBe("Rename")
			t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
			local group = panel
			while group and group.SelectionGroup ~= true do
				group = group.Parent
			end
			t.expect(group ~= nil).toBe(true)
			for _, direction in { "Up", "Down", "Left", "Right" } do
				t.expect(group["SelectionBehavior" .. direction]).toBe(world.engine.types.Enum.SelectionBehavior.Stop)
			end
			t.expect(action(world.screen, "Menu")).toBeNil()
			if route == "outside" then
				find(world.screen, "DismissOutside").Activated.fire({ Position = V2(world, 900, 900) })
			elseif route == "back" then
				action(world.screen, "ModalBack").Pressed.fire()
			else
				opened:set(false)
			end
			t.expect(opened:peek()).toBe(false)
			t.expect(find(world.screen, "MenuPanel")).toBeNil()
			t.expect(world.gui.SelectedObject).toBe(trigger)
			world.stop()
		end
	end)

	t.it("returns a submenu Back row to the item that opened it and traps a picker menu", function()
		local opened = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Menu({
					isPresented = opened,
					presentation = "sheet",
					items = {
						{
							id = "Sort",
							label = "Sort",
							children = {
								{ id = "Name", label = "Name", onSelect = function() end },
								{ id = "Date", label = "Date", onSelect = function() end },
							},
						},
						{ id = "Close", label = "Close", onSelect = function() end },
					},
				}),
			})
		end)
		local trigger = find(world.screen, "Trigger")
		world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		find(world.screen, "Sort").Activated.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("Name")
		find(world.screen, "Back").Activated.fire()
		t.expect(opened:peek()).toBe(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Sort")
		world.gui.SelectedObject = find(world.screen, "Sort")
		action(world.screen, "MenuRight").Pressed.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("Name")
		action(world.screen, "MenuLeft").Pressed.fire()
		t.expect(world.gui.SelectedObject.Name).toBe("Sort")
		t.expect(opened:peek()).toBe(true)
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(world.gui.SelectedObject).toBe(trigger)
		world.stop()
		for _, route in { "outside", "back", "model" } do
			local selected, presented = Compose.cell("a"), Compose.cell(false)
			local pickerWorld = setup(function(UI, Host)
				return Host.Frame({
					UI.Picker("Speed")({
						selected = selected,
						style = "menu",
						isPresented = presented,
						options = {
							{ value = "a", label = "Slow" },
							{ value = "b", label = "Fast" },
						},
					}),
				})
			end)
			local pickerTrigger = find(pickerWorld.screen, "Trigger")
			pickerWorld.gui.SelectedObject = pickerTrigger
			pickerTrigger.Activated.fire()
			t.expect(presented:peek()).toBe(true)
			local panel = find(pickerWorld.screen, "MenuPanel")
			t.expect(within(pickerWorld.gui.SelectedObject, panel)).toBe(true)
			if route == "outside" then
				find(pickerWorld.screen, "DismissOutside").Activated.fire({ Position = V2(pickerWorld, 900, 900) })
			elseif route == "back" then
				action(pickerWorld.screen, "ModalBack").Pressed.fire()
			else
				presented:set(false)
			end
			t.expect(presented:peek()).toBe(false)
			t.expect(selected:peek()).toBe("a")
			t.expect(pickerWorld.gui.SelectedObject).toBe(pickerTrigger)
			pickerWorld.stop()
		end
	end)

	t.it("lets a presented modal own Back over a navigation stack and leaves root Back unconsumed", function()
		local path, presented = Compose.cell({ { id = "detail" } }), Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.NavigationStack({
					path = path,
					root = {
						content = function()
							return UI.Button("RootAction")({ label = "Root" })
						end,
					},
					destinations = {
						detail = {
							content = function()
								return UI.Button("DetailAction")({ label = "Detail" })
							end,
						},
					},
				}),
				UI.Alert({ isPresented = presented, title = "Hold on" }),
			})
		end)
		world.gui.SelectedObject = find(world.screen, "DetailAction")
		local navigationBack = actionsNamed(world.screen, "NavigationBack")[1]
		t.expect(navigationBack.Parent.Enabled).toBe(true)
		presented:set(true)
		t.expect(navigationBack.Parent.Enabled).toBe(false)
		navigationBack.Pressed.fire()
		t.expect(#path:peek()).toBe(1)
		local modalBack = action(world.screen, "ModalBack")
		t.expect(modalBack.Parent.Priority > navigationBack.Parent.Priority).toBe(true)
		modalBack.Pressed.fire()
		t.expect(presented:peek()).toBe(false)
		t.expect(#path:peek()).toBe(1)
		t.expect(navigationBack.Parent.Enabled).toBe(true)
		navigationBack.Pressed.fire()
		t.expect(#path:peek()).toBe(0)
		t.expect(navigationBack.Parent.Enabled).toBe(false)
		navigationBack.Pressed.fire()
		t.expect(#path:peek()).toBe(0)
		t.expect(action(world.screen, "NavigationBack")).toBeNil()
		world.stop()
	end)

	t.it("gives an open menu or picker popup the shoulders before tab content paging", function()
		for _, kind in { "Menu", "Picker" } do
			local selection, opened = Compose.cell("a"), Compose.cell(false)
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					shoulderNavigation = "content",
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								if kind == "Menu" then
									return UI.Menu({
										isPresented = opened,
										items = { { id = "Run", label = "Run", onSelect = function() end } },
									})
								end
								return UI.Picker({
									selected = Compose.cell(1),
									style = "menu",
									isPresented = opened,
									options = { { value = 1, label = "One" }, { value = 2, label = "Two" } },
								})
							end,
						},
						{
							id = "b",
							label = "B",
							content = function()
								return Host.Frame("BBody")({})
							end,
						},
					},
				})
			end)
			local trigger = find(world.screen, "Trigger")
			world.gui.SelectedObject = trigger
			local next = action(world.screen, "NextTab")
			t.expect(next ~= nil).toBe(true)
			trigger.Activated.fire()
			t.expect(opened:peek()).toBe(true)
			t.expect(within(world.gui.SelectedObject, find(world.screen, "MenuPanel"))).toBe(true)
			t.expect(next.Parent.Enabled).toBe(false)
			t.expect(action(world.screen, "NextTab")).toBeNil()
			t.expect(action(world.screen, "PreviousTab")).toBeNil()
			next.Pressed.fire()
			t.expect(selection:peek()).toBe("a")
			t.expect(opened:peek()).toBe(true)
			world.gui.SelectedObject = trigger
			t.expect(next.Parent.Enabled).toBe(false)
			t.expect(action(world.screen, "NextTab")).toBeNil()
			next.Pressed.fire()
			t.expect(selection:peek()).toBe("a")
			action(world.screen, "ModalBack").Pressed.fire()
			t.expect(opened:peek()).toBe(false)
			t.expect(world.gui.SelectedObject).toBe(trigger)
			t.expect(next.Parent.Enabled).toBe(true)
			next.Pressed.fire()
			t.expect(selection:peek()).toBe("b")
			world.stop()
		end
	end)

	t.it("returns disclosure focus to the header for a child collapse and leaves outside focus alone", function()
		local expanded = Compose.cell(true)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Outside")({ label = "Outside" }),
				UI.DisclosureGroup({
					expanded = expanded,
					label = "Details",
					content = function()
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
		collapse.Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		t.expect(world.gui.SelectedObject).toBe(find(world.screen, "Header"))
		t.expect(find(world.screen, "Reveal").Interactable).toBe(false)
		world.engine.heartbeat.fire(0.25)
		t.expect(collapse.isDestroyed()).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(find(world.screen, "Header"))
		expanded:set(true)
		local outside = find(world.screen, "Outside")
		world.gui.SelectedObject = outside
		expanded:set(false)
		t.expect(world.gui.SelectedObject).toBe(outside)
		world.stop()
	end)

	t.it("leaves background selection and shortcuts live while a callout is shown", function()
		local shown, count = Compose.cell(true), 0
		local world = setup(function(UI, Host)
			local anchor = UI.Button("Anchor")({ label = "Anchor" })
			return Host.Frame({
				anchor,
				UI.Button("Other")({
					label = "Other",
					shortcut = { keyCode = "K" },
					onActivate = function()
						count += 1
					end,
				}),
				UI.Callout({
					anchor = anchor,
					isPresented = shown,
					onRetire = function() end,
					content = function()
						return UI.Button("Tip")({ label = "Tip" })
					end,
				}),
			})
		end)
		local anchor, other = find(world.screen, "Anchor"), find(world.screen, "Other")
		world.gui.SelectedObject = anchor
		local panel = find(world.screen, "CalloutPanel")
		t.expect(panel ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(anchor)
		t.expect(action(world.screen, "ModalBack")).toBeNil()
		t.expect(find(world.screen, "DismissOutside")).toBeNil()
		local cursor = panel
		while cursor and cursor ~= world.screen do
			t.expect(
				cursor.SelectionGroup == true
					and cursor.SelectionBehaviorDown == world.engine.types.Enum.SelectionBehavior.Stop
			).toBe(false)
			cursor = cursor.Parent
		end
		world.gui.SelectedObject = other
		t.expect(world.gui.SelectedObject).toBe(other)
		local shortcut = action(world.screen, "Shortcut")
		t.expect(shortcut ~= nil).toBe(true)
		shortcut.Pressed.fire()
		t.expect(count).toBe(1)
		world.gui.SelectedObject = anchor
		t.expect(world.gui.SelectedObject).toBe(anchor)
		t.expect(#world.engine.rejectedSelections).toBe(0)
		world.stop()
	end)

	t.it("releases a column grip when selection moves to another grip or the table leaves", function()
		local widths = Compose.cell({})
		local world = setup(function(UI)
			return UI.Table({
				from = { { id = 1 }, { id = 2 } },
				key = function(item)
					return item.id
				end,
				widths = widths,
				columns = { { id = "first", width = 100 }, { id = "second", width = 100 } },
			})
		end)
		local header = find(world.screen, "Header")
		local first, second = header:FindFirstChild("first"), header:FindFirstChild("second")
		first.AbsoluteSize = V2(world, 100, 40)
		second.AbsoluteSize = V2(world, 100, 40)
		local firstGrip, secondGrip = first:FindFirstChild("Resize"), second:FindFirstChild("Resize")
		local narrows = actionsNamed(world.screen, "NarrowColumn")
		t.expect(#narrows).toBe(2)
		local function narrowAll()
			for _, narrow in narrows do
				if narrow.Parent.Enabled then
					narrow.Pressed.fire()
				end
			end
		end
		for _, narrow in narrows do
			t.expect(narrow.Parent.Enabled).toBe(false)
		end
		firstGrip.SelectionGained.fire()
		narrowAll()
		t.expect(widths:peek()).toEqual({ first = 92 })
		firstGrip.SelectionLost.fire()
		secondGrip.SelectionGained.fire()
		local enabled = 0
		for _, narrow in narrows do
			if narrow.Parent.Enabled then
				enabled += 1
			end
		end
		t.expect(enabled).toBe(1)
		narrowAll()
		t.expect(widths:peek()).toEqual({ first = 92, second = 92 })
		for _, narrow in narrows do
			narrow.Pressed.fire()
		end
		t.expect(widths:peek()).toEqual({ first = 92, second = 84 })
		world.stop()
		for _, narrow in narrows do
			t.expect(narrow.isDestroyed()).toBe(true)
			narrow.Pressed.fire()
		end
		t.expect(widths:peek()).toEqual({ first = 92, second = 84 })
	end)

	t.it("keeps native selection on a diagonal wedge of an even ring across held aim frames", function()
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
		local world = setup(function(UI)
			return UI.RadialMenu({ isPresented = opened, holdAction = hold, items = items })
		end, { reducedMotion = true })
		hold.Pressed.fire()
		t.expect(opened:peek()).toBe(true)
		local axis = action(world.screen, "RadialAim")
		local function aim(degrees: number, magnitude: number)
			local radians = math.rad(degrees)
			axis.StateChanged.fire(V2(world, math.sin(radians) * magnitude, math.cos(radians) * magnitude))
		end
		aim(45, 0.9)
		local wedge = world.gui.SelectedObject
		t.expect(wedge ~= nil and wedge.Name).toBe("Item2")
		for _, degrees in { 40, 50, 60, 30, 45 } do
			aim(degrees, 0.9)
			world.engine.heartbeat.fire(1 / 60)
			t.expect(world.gui.SelectedObject).toBe(wedge)
		end
		for _ = 1, 30 do
			world.engine.heartbeat.fire(1 / 60)
		end
		t.expect(world.gui.SelectedObject).toBe(wedge)
		aim(135, 0.9)
		t.expect(world.gui.SelectedObject.Name).toBe("Item4")
		aim(225, 0.9)
		t.expect(world.gui.SelectedObject.Name).toBe("Item6")
		aim(315, 0.9)
		t.expect(world.gui.SelectedObject.Name).toBe("Item8")
		aim(45, 0.9)
		t.expect(world.gui.SelectedObject).toBe(wedge)
		t.expect(#picked).toBe(0)
		hold.Released.fire()
		t.expect(picked).toEqual({ "Item2" })
		world.stop()
	end)

	t.it("takes modal selection on entry only for selection navigation across sheets and menus", function()
		for _, preferred in { "Touch", "KeyboardAndMouse", "Gamepad" } do
			local sheet, menu = Compose.cell(false), Compose.cell(false)
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.Sheet({
						isPresented = sheet,
						detent = Compose.cell("medium"),
						content = function()
							return UI.Button("Inside")({ label = "Inside" })
						end,
					}),
					UI.Menu({
						isPresented = menu,
						items = { { id = "Run", label = "Run", onSelect = function() end } },
					}),
				})
			end)
			world.input.PreferredInput = (world.engine.types.Enum.PreferredInput :: any)[preferred]
			for _, presented in { sheet, menu } do
				presented:set(true)
				if preferred == "Gamepad" then
					t.expect(world.gui.SelectedObject ~= nil).toBe(true)
					local panel = find(world.screen, if presented == sheet then "SheetPanel" else "MenuPanel")
					t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
				else
					t.expect(world.gui.SelectedObject).toBeNil()
				end
				presented:set(false)
				t.expect(world.gui.SelectedObject).toBeNil()
			end
			world.stop()
		end
	end)

	t.it("restores a deep tab bookmark on shoulder entry and skips restoration when restoreFocus is off", function()
		for _, restore in { true, false } do
			local selection = Compose.cell("one")
			local rows = {}
			for index = 1, 12 do
				rows[index] = { id = index, label = tostring(index) }
			end
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					shoulderNavigation = "content",
					restoreFocus = restore,
					transition = false,
					tabs = {
						{
							id = "one",
							label = "One",
							content = function()
								return Host.Frame("OneBody")({
									UI.Button("Top")({ label = "Top" }),
									Host.ScrollingFrame("Scroller")({
										Host.Frame("Group")({
											UI.Button("Shallow")({ label = "Shallow" }),
											UI.Button("Deep")({ label = "Deep" }),
										}),
									}),
								})
							end,
						},
						{
							id = "two",
							label = "Two",
							content = function()
								return UI.VirtualList("Rows")({
									from = rows,
									key = function(item)
										return item.id
									end,
									itemSize = 20,
									render = function(current)
										return UI.Button("Row")({
											label = function(use)
												return use(current).label
											end,
										})
									end,
								})
							end,
						},
					},
				})
			end)
			local deep = find(world.screen, "Deep")
			world.gui.SelectedObject = deep
			action(world.screen, "NextTab").Pressed.fire()
			t.expect(selection:peek()).toBe("two")
			local list = find(world.screen, "Rows")
			list.AbsoluteWindowSize = V2(world, 200, 120)
			if restore then
				t.expect(within(world.gui.SelectedObject, list)).toBe(true)
			end
			local rowFive = find(list, "5")
			t.expect(rowFive ~= nil).toBe(true)
			local target = find(rowFive, "Row")
			world.gui.SelectedObject = target
			target.SelectionGained.fire()
			action(world.screen, "PreviousTab").Pressed.fire()
			t.expect(selection:peek()).toBe("one")
			if restore then
				t.expect(world.gui.SelectedObject).toBe(deep)
			else
				t.expect(world.gui.SelectedObject ~= deep).toBe(true)
			end
			world.gui.SelectedObject = deep
			action(world.screen, "NextTab").Pressed.fire()
			t.expect(selection:peek()).toBe("two")
			if restore then
				t.expect(world.gui.SelectedObject).toBe(target)
			else
				t.expect(world.gui.SelectedObject ~= target).toBe(true)
			end
			world.stop()
		end
	end)

	t.it("extends reversed and focus-anchored ranges and toggles additive taps in multi selection", function()
		local shifted = false
		local selected = Compose.cell({})
		local world = setup(function(UI)
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
				selectionMode = "multi",
				itemSize = 20,
				overscan = 0,
				columns = { { id = "label", label = "Label" } },
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
		hit(10).Activated.fire(touch)
		shifted = true
		hit(3).Activated.fire(touch)
		shifted = false
		t.expect(keysOf()).toEqual({ 3, 4, 5, 6, 7, 8, 9, 10 })
		selected:set({})
		hit(2).Activated.fire(touch)
		hit(5).Activated.fire(touch)
		t.expect(keysOf()).toEqual({ 2, 5 })
		hit(2).Activated.fire(touch)
		t.expect(keysOf()).toEqual({ 5 })
		selected:set({})
		world.gui.SelectedObject = hit(4)
		hit(4).SelectionGained.fire()
		hit(4).Activated.fire(keyboard)
		t.expect(keysOf()).toEqual({ 4 })
		local down = action(world.screen, "CollectionDown")
		down.Pressed.fire()
		down.Pressed.fire()
		t.expect(world.gui.SelectedObject).toBe(hit(6))
		t.expect(keysOf()).toEqual({ 4 })
		shifted = true
		hit(6).Activated.fire(keyboard)
		t.expect(keysOf()).toEqual({ 4, 5, 6 })
		hit(1).Activated.fire(gamepad)
		shifted = false
		t.expect(keysOf()).toEqual({ 1, 2, 3, 4 })
		world.stop()
		local single = Compose.cell({})
		local singleWorld = setup(function(UI)
			return UI.Table({
				from = { { id = 1 }, { id = 2 }, { id = 3 } },
				key = function(item)
					return item.id
				end,
				selection = single,
				selectionMode = "single",
				columns = { { id = "id", label = "Id" } },
			})
		end)
		local singleBody = find(singleWorld.screen, "Body")
		singleBody.AbsoluteWindowSize = V2(singleWorld, 200, 400)
		singleBody:FindFirstChild("1", true):FindFirstChild("RowHit", true).Activated.fire(touch)
		singleBody:FindFirstChild("3", true):FindFirstChild("RowHit", true).Activated.fire(touch)
		t.expect(single:peek()).toEqual({ [3] = true })
		singleWorld.stop()
	end)

	t.it("toggles multi selection from the pad in edit mode without a focus landing undoing it", function()
		local selected, editing = Compose.cell({}), Compose.cell(true)
		local world = setup(function(UI)
			return UI.Table({
				from = { { id = 1 }, { id = 2 }, { id = 3 } },
				key = function(item)
					return item.id
				end,
				selection = selected,
				selectionMode = "multi",
				editing = editing,
				rowActions = function()
					return { trailing = { { id = "Remove", label = "Remove", role = "destructive" } } }
				end,
				columns = { { id = "id", label = "Id" } },
			})
		end)
		local Enum = world.engine.types.Enum
		local body = find(world.screen, "Body")
		body.AbsoluteWindowSize = V2(world, 200, 400)
		local gamepad = { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA }
		local two = body:FindFirstChild("2", true):FindFirstChild("RowHit", true)
		local three = body:FindFirstChild("3", true):FindFirstChild("RowHit", true)
		world.gui.SelectedObject = two
		two.SelectionGained.fire()
		two.Activated.fire(gamepad)
		t.expect(selected:peek()).toEqual({ [2] = true })
		two.SelectionLost.fire()
		world.gui.SelectedObject = three
		three.SelectionGained.fire()
		three.SelectionLost.fire()
		world.gui.SelectedObject = two
		two.SelectionGained.fire()
		t.expect(selected:peek()).toEqual({ [2] = true })
		three.Activated.fire(gamepad)
		t.expect(selected:peek()).toEqual({ [2] = true, [3] = true })
		two.Activated.fire(gamepad)
		t.expect(selected:peek()).toEqual({ [3] = true })
		t.expect(editing:peek()).toBe(true)
		world.stop()
	end)

	t.it("keeps collection focus on its key through a re-sort and a table sort change", function()
		local source = Compose.cell({ { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 } })
		local focus: any = {}
		local world = setup(function(UI)
			return UI.VirtualList({
				from = source,
				key = function(item)
					return item.id
				end,
				itemSize = 20,
				focus = focus,
				render = function(current)
					return UI.Button("Row")({
						label = function(use)
							return tostring(use(current).id)
						end,
					})
				end,
			})
		end)
		local list = world.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
		list.AbsoluteWindowSize = V2(world, 200, 200)
		focus.focus(3)
		local before = world.gui.SelectedObject
		t.expect(before.Text).toBe("3")
		source:set({ { id = 5 }, { id = 4 }, { id = 3 }, { id = 2 }, { id = 1 } })
		t.expect(focus.current:peek()).toBe(3)
		t.expect(world.gui.SelectedObject.Text).toBe("3")
		source:set({ { id = 3 }, { id = 1 }, { id = 5 } })
		t.expect(focus.current:peek()).toBe(3)
		t.expect(world.gui.SelectedObject.Text).toBe("3")
		action(world.screen, "CollectionDown").Pressed.fire()
		t.expect(focus.current:peek()).toBe(1)
		t.expect(world.gui.SelectedObject.Text).toBe("1")
		world.stop()
		local sort = Compose.cell(nil :: any)
		local tableWorld = setup(function(UI)
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
					},
				},
			})
		end)
		local body = find(tableWorld.screen, "Body")
		body.AbsoluteWindowSize = V2(tableWorld, 200, 400)
		local hit = body:FindFirstChild("3", true):FindFirstChild("RowHit", true)
		tableWorld.gui.SelectedObject = hit
		hit.SelectionGained.fire()
		sort:set({ column = "name", direction = "descending" })
		t.expect(tableWorld.gui.SelectedObject).toBe(hit)
		t.expect(within(hit, body:FindFirstChild("3", true))).toBe(true)
		action(tableWorld.screen, "CollectionDown").Pressed.fire()
		t.expect(within(tableWorld.gui.SelectedObject, body:FindFirstChild("2", true))).toBe(true)
		tableWorld.stop()
	end)

	t.it("never strands selection on a removed focused row and skips disabled table rows", function()
		local source = Compose.cell({ { id = 1 }, { id = 2 }, { id = 3 } })
		local focus: any = {}
		local world = setup(function(UI)
			return UI.VirtualList({
				from = source,
				key = function(item)
					return item.id
				end,
				itemSize = 20,
				focus = focus,
				render = function(current)
					return UI.Button("Row")({
						label = function(use)
							return tostring(use(current).id)
						end,
					})
				end,
			})
		end)
		local list = world.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
		list.AbsoluteWindowSize = V2(world, 200, 200)
		focus.focus(2)
		local removed = world.gui.SelectedObject
		t.expect(removed.Text).toBe("2")
		source:set({ { id = 1 }, { id = 3 } })
		t.expect(world.gui.SelectedObject == removed).toBe(false)
		t.expect(world.gui.SelectedObject == nil or not world.gui.SelectedObject.isDestroyed()).toBe(true)
		world.stop()
		local selected, activated = Compose.cell({}), 0
		local tableWorld = setup(function(UI)
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
				columns = { { id = "id", label = "Id" } },
			})
		end)
		local body = find(tableWorld.screen, "Body")
		body.AbsoluteWindowSize = V2(tableWorld, 200, 400)
		local first = body:FindFirstChild("1", true):FindFirstChild("RowHit", true)
		local skipped = body:FindFirstChild("2", true):FindFirstChild("RowHit", true)
		t.expect(skipped.Interactable).toBe(false)
		tableWorld.gui.SelectedObject = first
		first.SelectionGained.fire()
		action(tableWorld.screen, "CollectionDown").Pressed.fire()
		t.expect(within(tableWorld.gui.SelectedObject, body:FindFirstChild("4", true))).toBe(true)
		action(tableWorld.screen, "CollectionUp").Pressed.fire()
		t.expect(within(tableWorld.gui.SelectedObject, body:FindFirstChild("1", true))).toBe(true)
		skipped.Activated.fire({ UserInputType = tableWorld.engine.types.Enum.UserInputType.Touch })
		t.expect(selected:peek()).toEqual({})
		t.expect(activated).toBe(0)
		tableWorld.stop()
	end)

	t.it("yields the minimum-side arrow at the bound while bumpers stay bound, also inside a list row", function()
		local value = Compose.cell(1)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Rating("Stars")({ value = value }),
				UI.Slider("Volume")({ value = Compose.cell(0.5) }),
			})
		end)
		local stars = find(world.screen, "Stars")
		world.gui.SelectedObject = stars
		stars.SelectionGained.fire()
		local decrease, increase = action(world.screen, "DecreaseArrow"), action(world.screen, "IncreaseArrow")
		local bumper = action(world.screen, "Decrease")
		t.expect(#contexts(world.screen, "DecreaseArrow")).toBe(1)
		decrease.Pressed.fire()
		t.expect(value:peek()).toBe(0)
		t.expect(decrease.Parent.Enabled).toBe(false)
		t.expect(increase.Parent.Enabled).toBe(true)
		t.expect(bumper.Parent.Enabled).toBe(true)
		decrease.Pressed.fire()
		bumper.Pressed.fire()
		t.expect(value:peek()).toBe(0)
		t.expect(bumper.Parent.Enabled).toBe(true)
		increase.Pressed.fire()
		t.expect(value:peek()).toBe(1)
		t.expect(decrease.Parent.Enabled).toBe(true)
		world.stop()
		local rated = Compose.cell(3)
		local listWorld = setup(function(UI)
			return UI.VirtualList({
				from = { { id = 1 }, { id = 2 } },
				key = function(item)
					return item.id
				end,
				itemSize = 44,
				render = function()
					return UI.Rating("Stars")({ value = rated })
				end,
			})
		end)
		local list = listWorld.screen:FindFirstChildWhichIsA("ScrollingFrame", true)
		list.AbsoluteWindowSize = V2(listWorld, 300, 200)
		local rowStars = find(find(list, "1"), "Stars")
		listWorld.gui.SelectedObject = rowStars
		rowStars.SelectionGained.fire()
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
		t.expect(winner("Right").Name).toBe("IncreaseArrow")
		t.expect(winner("Left").Name).toBe("DecreaseArrow")
		winner("Right").Pressed.fire()
		winner("Right").Pressed.fire()
		t.expect(rated:peek()).toBe(5)
		t.expect(winner("Right").Name ~= "IncreaseArrow").toBe(true)
		t.expect(winner("Down").Name).toBe("CollectionDown")
		listWorld.stop()
	end)

	t.it("captures selection in the avatar look sheet and reset alert and returns it to their openers", function()
		local Roblox = Facet.Roblox
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
			local stop, avatar = runtime.mount(views.Avatar, target)
			local summary = find(find(avatar, "SummaryActions"), "Summary")
			for _, route in { "back", "done" } do
				gui.SelectedObject = summary
				summary.Activated.fire()
				t.expect(model.avatarSummary:peek()).toBe(true)
				local panel = find(target, "SheetPanel")
				t.expect(panel ~= nil).toBe(true)
				t.expect(within(gui.SelectedObject, panel)).toBe(true)
				t.expect(panel.SelectionGroup).toBe(true)
				if route == "back" then
					action(target, "ModalBack").Pressed.fire()
				else
					find(panel, "Close").Activated.fire()
				end
				t.expect(model.avatarSummary:peek()).toBe(false)
				t.expect(find(target, "SheetPanel")).toBeNil()
				t.expect(gui.SelectedObject).toBe(summary)
			end
			local reset = find(avatar, "Reset")
			gui.SelectedObject = reset
			reset.Activated.fire()
			t.expect(model.resetAvatarPresented:peek()).toBe(true)
			t.expect(gui.SelectedObject.Name).toBe("cancel")
			action(target, "ModalBack").Pressed.fire()
			t.expect(model.resetAvatarPresented:peek()).toBe(false)
			t.expect(gui.SelectedObject).toBe(reset)
			stop()
		end, runtime.reactor)
		lifetime.dispose()
		runtime:dispose()
	end)

	t.it("previews radial aim without committing and closes on semantic Back one level at a time", function()
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
		local world = setup(function(UI)
			return UI.RadialMenu({
				isPresented = opened,
				holdAction = hold,
				onClose = function()
					closes += 1
				end,
				items = {
					item("North"),
					{ id = "Branch", label = "Branch", children = { item("Leaf"), item("Other") } },
					item("South"),
					item("West"),
				},
			})
		end, { reducedMotion = true })
		hold.Pressed.fire()
		local axis = action(world.screen, "RadialAim")
		axis.StateChanged.fire(V2(world, 0, 0.9))
		t.expect(world.gui.SelectedObject.Name).toBe("North")
		axis.StateChanged.fire(V2(world, 0.9, 0))
		t.expect(world.gui.SelectedObject.Name).toBe("Branch")
		t.expect(#picked).toBe(0)
		local back = action(world.screen, "ModalBack")
		t.expect(keys(back)).toEqual({ "ButtonB", "Escape" })
		back.Pressed.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(closes).toBe(1)
		t.expect(#picked).toBe(0)
		hold.Released.fire()
		t.expect(#picked).toBe(0)
		opened:set(true)
		local branch = find(world.screen, "Branch")
		world.gui.SelectedObject = branch
		branch.Activated.fire()
		t.expect(find(world.screen, "Leaf") ~= nil).toBe(true)
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(true)
		t.expect(find(world.screen, "Leaf")).toBeNil()
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(closes).toBe(2)
		t.expect(#picked).toBe(0)
		world.stop()
	end)

	t.it("activates a selected button once per Return or Space press and leaves a disabled one inert", function()
		local enabled, count = Compose.cell(true), 0
		local world = setup(function(UI)
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
		t.expect(keys(activate)).toEqual({ "Return", "Space" })
		t.expect(activate.Parent.Sink).toBe(true)
		t.expect(#contexts(world.screen, "Activate")).toBe(1)
		activate.Pressed.fire()
		t.expect(count).toBe(1)
		activate.Released.fire()
		t.expect(count).toBe(1)
		activate.Pressed.fire()
		t.expect(count).toBe(2)
		enabled:set(false)
		t.expect(go.Selectable).toBe(false)
		t.expect(go.Interactable).toBe(false)
		t.expect(activate.Parent.Enabled).toBe(false)
		activate.Pressed.fire()
		go.Activated.fire()
		t.expect(count).toBe(2)
		world.stop()
	end)

	t.it("deletes with Delete or Backspace through the first enabled destructive action, trailing first", function()
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
			local world = setup(function(UI)
				return UI.RowActions({
					content = UI.Button("Action")({ label = "Row" }),
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
			end, { reducedMotion = true })
			world.gui.SelectedObject = find(world.screen, "Action")
			local deletes = contexts(world.screen, "RowActionsDelete")
			t.expect(#deletes).toBe(1)
			local delete = deletes[1]:FindFirstChild("RowActionsDelete")
			t.expect(keys(delete)).toEqual({ "Backspace", "Delete" })
			if variant == "none" then
				t.expect(delete.Parent.Enabled).toBe(false)
				delete.Pressed.fire()
				t.expect(invoked).toEqual({})
			else
				t.expect(delete.Parent.Enabled).toBe(true)
				delete.Pressed.fire()
				t.expect(invoked).toEqual({ if variant == "trailing" then "Erase" else "Archive" })
			end
			world.stop()
		end
	end)

	t.it("repeats touch, keyboard and gamepad holds and suppresses the trailing activation in either order", function()
		local Enum: any
		for _, kind in { "Touch", "Return", "Space", "ButtonA" } do
			for _, order in { "endFirst", "activatedFirst" } do
				local count = 0
				local world = setup(function(UI)
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
					then { UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown }
					elseif kind == "ButtonA" then {
						UserInputType = Enum.UserInputType.Gamepad1,
						KeyCode = Enum.KeyCode.ButtonA,
					}
					else { UserInputType = Enum.UserInputType.Keyboard, KeyCode = (Enum.KeyCode :: any)[kind] }
				node.InputBegan.fire(input)
				world.engine.heartbeat.fire(0.3)
				t.expect(count).toBe(0)
				world.engine.heartbeat.fire(0.1)
				world.engine.heartbeat.fire(0.1)
				world.engine.heartbeat.fire(0.1)
				t.expect(count).toBe(3)
				if order == "endFirst" then
					node.InputEnded.fire(input)
					node.Activated.fire(input)
				else
					node.Activated.fire(input)
					node.InputEnded.fire(input)
				end
				t.expect(count).toBe(3)
				world.engine.heartbeat.fire(1)
				t.expect(count).toBe(3)
				node.InputBegan.fire(input)
				world.engine.heartbeat.fire(0.1)
				node.InputEnded.fire(input)
				node.Activated.fire(input)
				t.expect(count).toBe(4)
				world.stop()
			end
		end
	end)

	t.it("stops a held repeat when busy begins and keeps the next shortcut after a pointer leaves", function()
		local busy, count = Compose.cell(false), 0
		local world = setup(function(UI)
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
		local mouse = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown }
		local shortcut = action(world.screen, "Shortcut")
		node.InputBegan.fire(mouse)
		world.engine.heartbeat.fire(0.4)
		t.expect(count).toBe(1)
		busy:set(true)
		world.engine.heartbeat.fire(0.1)
		world.engine.heartbeat.fire(0.4)
		t.expect(count).toBe(1)
		shortcut.Pressed.fire()
		t.expect(count).toBe(1)
		busy:set(false)
		world.engine.heartbeat.fire(0.4)
		t.expect(count).toBe(1)
		node.InputEnded.fire(mouse)
		shortcut.Pressed.fire()
		t.expect(count).toBe(2)
		node.InputBegan.fire(mouse)
		world.engine.heartbeat.fire(0.4)
		t.expect(count).toBe(3)
		node.MouseLeave.fire()
		world.engine.heartbeat.fire(0.4)
		t.expect(count).toBe(3)
		shortcut.Pressed.fire()
		t.expect(count).toBe(4)
		world.stop()
	end)

	t.it("keeps readable key names and no glyph when the native key service fails", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
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
		local stop, screen = runtime.mount(function()
			local inputAction, binding = engine.new("InputAction"), engine.new("InputBinding")
			binding.KeyCode, binding.DisplayName = engine.types.Enum.KeyCode.Return, ""
			binding.PrimaryModifier = engine.types.Enum.KeyCode.LeftShift
			inputAction.PreferredBinding = binding
			return runtime.constructors.ScreenGui({ UI.ShortcutHint("Hint")({ action = inputAction }) })
		end, engine.new("Folder"))
		t.expect(find(screen, "Key").Text).toBe("Shift+Enter")
		t.expect(find(screen, "Glyph")).toBeNil()
		stop()
		runtime:dispose()
	end)

	t.it("tracks separator and control rung on the same hint node without a rebuild", function()
		local separator, rung = Compose.cell("or"), Compose.cell("compact")
		local world = setup(function(UI, Host, engine)
			local inputAction, binding = engine.new("InputAction"), engine.new("InputBinding")
			binding.KeyCode = engine.types.Enum.KeyCode.ButtonX
			inputAction.PreferredBinding = binding
			return Host.Frame({
				UI.ShortcutHint("Explicit")({
					keys = { { "Ctrl", "K" }, { "F1" } },
					separator = separator,
					controlSize = rung,
				}),
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
		t.expect(explicit.Text).toBe("Ctrl+K or F1")
		local compactHeight, compactGlyph = explicit.Size.Y.Offset, glyph.Size.X.Offset
		separator:set("ou")
		rung:set("large")
		t.expect(find(world.screen, "Explicit")).toBe(explicit)
		t.expect(find(find(world.screen, "Live"), "Glyph")).toBe(glyph)
		t.expect(explicit.Text).toBe("Ctrl+K ou F1")
		t.expect(explicit.Size.Y.Offset > compactHeight).toBe(true)
		t.expect(glyph.Size.X.Offset > compactGlyph).toBe(true)
		rung:set("regular")
		t.expect(explicit.Size.Y.Offset > compactHeight).toBe(true)
		t.expect(explicit.Size.Y.Offset < 32 + 1).toBe(true)
		world.stop()
	end)

	t.it("refuses every malformed shortcut hint declaration without native leftovers", function()
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
				return { keys = { { "K" } }, controlSize = "huge" }
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
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local UI = Facet.controls(runtime, { types = engine.types, services = { GuiService = gui } } :: any)
			local spec = build(engine)
			local folder = engine.new("Folder")
			local ok = pcall(function()
				local stop = runtime.mount(function()
					return runtime.constructors.ScreenGui({ UI.ShortcutHint(spec) })
				end, folder)
				stop()
			end)
			runtime:dispose()
			t.expect(if ok then name else "refused").toBe("refused")
			local leftovers = 0
			for _, node in engine.made do
				if
					not node.isDestroyed()
					and node ~= gui
					and node ~= folder
					and node.ClassName ~= "InputAction"
					and node.ClassName ~= "Frame"
				then
					leftovers += 1
				end
			end
			t.expect(leftovers).toBe(0)
			t.expect(#folder:GetChildren()).toBe(0)
		end
	end)

	t.it("selects an indicated picker option once by tap and by Return on the selected segment", function()
		local selected, changes = Compose.cell("a"), 0
		local world = setup(function(UI)
			return UI.Picker({
				selected = selected,
				style = "segmented",
				indicator = "underline",
				onChange = function()
					changes += 1
				end,
				options = {
					{ value = "a", label = "Alpha" },
					{ value = "b", label = "Beta" },
					{ value = "c", label = "Gamma", enabled = false },
				},
			})
		end)
		local Enum = world.engine.types.Enum
		local b, c = find(world.screen, "b"), find(world.screen, "c")
		t.expect(b.Selectable).toBe(true)
		world.gui.SelectedObject = b
		local activate = action(world.screen, "Activate")
		t.expect(keys(activate)).toEqual({ "Return", "Space" })
		activate.Pressed.fire()
		t.expect(selected:peek()).toBe("b")
		t.expect(find(b, "SelectionIndicator") ~= nil).toBe(true)
		t.expect(find(find(world.screen, "a"), "SelectionIndicator")).toBeNil()
		activate.Pressed.fire()
		t.expect(changes).toBe(1)
		find(world.screen, "a").Activated.fire({ UserInputType = Enum.UserInputType.Touch })
		t.expect(selected:peek()).toBe("a")
		t.expect(changes).toBe(2)
		t.expect(c.Selectable).toBe(false)
		world.gui.SelectedObject = c
		t.expect(world.gui.SelectedObject).toBe(b)
		c.Activated.fire()
		t.expect(selected:peek()).toBe("a")
		world.stop()
	end)

	t.it("cycles sheet detents from the selectable grabber for tap, mouse and gamepad activation", function()
		local detent = Compose.cell("medium")
		local world = setup(function(UI)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = detent,
				detents = { "medium", "large", { id = "peek", height = 160 } },
				content = function()
					return UI.Button({ label = "Inside" })
				end,
			})
		end)
		local Enum = world.engine.types.Enum
		local grabber = find(world.screen, "Grabber")
		t.expect(grabber:IsA("GuiButton")).toBe(true)
		t.expect(grabber.Selectable).toBe(true)
		t.expect(grabber.Interactable).toBe(true)
		t.expect(grabber:GetAttribute("AccessibleLabel")).toBe("Size: Medium")
		world.gui.SelectedObject = grabber
		t.expect(world.gui.SelectedObject).toBe(grabber)
		grabber.Activated.fire({ UserInputType = Enum.UserInputType.Touch })
		t.expect(detent:peek()).toBe("large")
		grabber.Activated.fire({ UserInputType = Enum.UserInputType.MouseButton1 })
		t.expect(detent:peek()).toBe("peek")
		grabber.Activated.fire({ UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonA })
		t.expect(detent:peek()).toBe("medium")
		world.stop()
		local single = setup(function(UI)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = Compose.cell("large"),
				detents = { "large" },
				content = function()
					return UI.Button({ label = "Inside" })
				end,
			})
		end)
		t.expect(find(single.screen, "Grabber").Selectable).toBe(false)
		single.stop()
	end)

	t.it("retakes the modal entry when the engine refuses it before the panel is laid out", function()
		local presented = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Opener")({ label = "Open" }),
				UI.Button("Beside")({ label = "Beside" }),
				UI.Sheet({
					isPresented = presented,
					detent = Compose.cell("large"),
					content = function()
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
		t.expect(refusals >= 1).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(beside)
		local entry
		for _, node in panel:GetDescendants() do
			if entry == nil and node:IsA("GuiObject") and node.Selectable and node.Visible then
				entry = node
			end
		end
		entry.AbsoluteSize = world.engine.types.Vector2.new(88, 44)
		panel.AbsoluteSize = world.engine.types.Vector2.new(600, 400)
		t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(entry)
		world.gui.SelectedObject = beside
		panel.AbsoluteSize = world.engine.types.Vector2.new(600, 420)
		t.expect(world.gui.SelectedObject).toBe(beside)
		refusing:Disconnect()
		world.stop()
	end)

	t.it("returns the selection to the opener when the engine moves it aside as the modal leaves", function()
		local presented = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Opener")({ label = "Open" }),
				UI.Button("Beside")({ label = "Beside" }),
				UI.Sheet({
					isPresented = presented,
					detent = Compose.cell("large"),
					content = function()
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
		t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
		local root = panel.Parent
		local moved = 0
		local aside = root:GetPropertyChangedSignal("Parent"):Connect(function()
			if root.Parent == nil and within(world.gui.SelectedObject, root) then
				moved += 1
				world.gui.SelectedObject = beside
			end
		end)
		presented:set(false)
		t.expect(moved).toBe(1)
		t.expect(world.gui.SelectedObject).toBe(opener)
		aside:Disconnect()
		world.gui.SelectedObject = opener
		presented:set(true)
		world.gui.SelectedObject = beside
		presented:set(false)
		t.expect(world.gui.SelectedObject).toBe(beside)
		world.stop()
	end)
end)
