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
	parent: any,
	shift: { down: boolean },
	stop: () -> (),
}

local function setup(build: (any, any, any, any) -> any): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
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
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
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

local function select(world: World, node: any)
	local previous = world.gui.SelectedObject
	if previous and previous ~= node then
		previous.SelectionLost.fire()
	end
	world.gui.SelectedObject = node
	if world.gui.SelectedObject == node then
		node.SelectionGained.fire()
	end
end

local function returnKey(world: World)
	local activate = action(world.parent, "Activate")
	assert(activate, "the selected control binds Activate")
	activate.Pressed.fire()
end

local function mountExample(name: string, folder: string?): (World, any)
	local built
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
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
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		inputTarget = parent,
		worldTarget = engine.new("Folder"),
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
	}
	local stop, screen = runtime.mount(function()
		require("../examples/gallery/client/screen").configure(ctx)
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				guiService = gui,
				reducedMotion = ctx.reducedMotion,
				inputParent = parent,
				services = { GuiService = gui, UserInputService = input },
			} :: any
		)
		built = (require :: any)("../examples/gallery/" .. (folder or "examples") .. "/" .. name).build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return runtime.constructors.ScreenGui({ built.screen() })
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

t.describe("native parity weaker selection", function()
	t.it("moves the selection out of a subtree whose ancestor stops being interactable and keeps it out", function()
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Screen")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				UI.Button("Before")({ label = "Before", LayoutOrder = 1 }),
				Host.Frame("Panel")({
					LayoutOrder = 2,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
					UI.Button("Inner")({ label = "Inner", LayoutOrder = 1 }),
					UI.Button("Deep")({ label = "Deep", LayoutOrder = 2 }),
				}),
				UI.Button("After")({ label = "After", LayoutOrder = 3 }),
			})
		end)
		local panel = find(world.screen, "Panel")
		world.gui.SelectedObject = find(world.screen, "Deep")
		panel.Interactable = false
		t.expect(selected(world)).toBe("After")
		panel.Interactable = true
		t.expect(selected(world)).toBe("After")
		world.gui.SelectedObject = find(world.screen, "Inner")
		panel.Visible = false
		t.expect(selected(world)).toBe("After")
		world.stop()
	end)

	t.it("keeps entry, Tab, activation and value keys out of a subtree whose ancestor is not interactable", function()
		local value, activated = Compose.cell(0.5), 0
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Screen")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				Host.Frame("Panel")({
					LayoutOrder = 1,
					Interactable = false,
					Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
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
		t.expect(selected(world)).toBe("Before")
		tab(world)
		t.expect(selected(world)).toBe("After")
		tab(world)
		t.expect(selected(world)).toBe("Before")
		tab(world, true)
		t.expect(selected(world)).toBe("After")
		select(world, find(world.screen, "Inner"))
		local activate = action(world.parent, "Activate")
		if activate then
			activate.Pressed.fire()
		end
		t.expect(activated).toBe(0)
		local panel, track = find(world.screen, "Panel"), find(find(world.screen, "Volume"), "Track")
		panel.Interactable = true
		select(world, track)
		press(world, "DPadRight")
		local raised = value:peek()
		t.expect(raised > 0.5).toBe(true)
		panel.Interactable = false
		t.expect(selected(world)).toBe("Before")
		track.SelectionLost.fire()
		find(world.screen, "Before").SelectionGained.fire()
		press(world, "DPadRight")
		press(world, "DPadLeft")
		t.expect(action(world.parent, "Increase")).toBe(nil)
		t.expect(action(world.parent, "Decrease")).toBe(nil)
		t.expect(value:peek()).toBe(raised)
		world.stop()
	end)

	t.it("reports each Tab move as one observable change of the native selection", function()
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Form")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
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
		t.expect(#seen).toBe(2)
		t.expect(seen[1]).toBe("Sfx")
		t.expect(seen[2]).toBe("Haptics")
		connection.Disconnect()
		world.stop()
	end)

	t.it("adds a control mounted by a condition to the walk, activates it and hands a removed one on", function()
		local shown, activated = Compose.cell(false), {}
		local world = setup(function(UI, Host, engine)
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
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				button("A", 1),
				Compose.show(shown, function()
					return button("B", 2)
				end),
				button("C", 3),
			})
		end)
		world.gui.SelectedObject = find(world.screen, "A")
		tab(world)
		t.expect(selected(world)).toBe("C")
		shown:set(true)
		tab(world, true)
		t.expect(selected(world)).toBe("B")
		select(world, find(world.screen, "B"))
		returnKey(world)
		t.expect(activated[#activated]).toBe("B")
		shown:set(false)
		t.expect(selected(world)).toBe("C")
		select(world, find(world.screen, "C"))
		returnKey(world)
		t.expect(activated[#activated]).toBe("C")
		t.expect(#activated).toBe(2)
		world.stop()
	end)

	t.it("walks and activates the selection through its input actions only", function()
		local activated = {}
		local world = setup(function(UI, Host, engine)
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
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
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
		t.expect(tabs).toBe(1)
		tab(world)
		tab(world)
		tab(world)
		t.expect(selected(world)).toBe("Save")
		tab(world, true)
		t.expect(selected(world)).toBe("Sfx")
		select(world, world.gui.SelectedObject)
		local activate = action(world.parent, "Activate")
		local keys = {}
		for _, binding in activate:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		t.expect(table.concat(keys, ",")).toBe("Return,Space")
		activate.Pressed.fire()
		t.expect(table.concat(activated, ",")).toBe("Sfx")
		world.stop()
	end)

	t.it("keeps the selection and an open modal through every input class flip", function()
		local presented = Compose.cell(false)
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Screen")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				UI.Button("A")({ label = "A", LayoutOrder = 1 }),
				UI.Button("B")({ label = "B", LayoutOrder = 2 }),
				UI.Alert({
					isPresented = presented,
					title = "Quit?",
					actions = {
						{ id = "Stay", label = "Stay", role = "cancel" },
						{ id = "Quit", label = "Quit", role = "destructive" },
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
		t.expect(selected(world)).toBe("B")
		flipEverything()
		t.expect(selected(world)).toBe("B")
		tab(world, true)
		t.expect(selected(world)).toBe("A")
		presented:set(true)
		local inside = selected(world)
		t.expect(inside == "Stay" or inside == "Quit").toBe(true)
		flipEverything()
		t.expect(presented:peek()).toBe(true)
		t.expect(selected(world)).toBe(inside)
		tab(world)
		t.expect(selected(world) == "Stay" or selected(world) == "Quit").toBe(true)
		action(world.parent, "ModalBack").Pressed.fire()
		t.expect(presented:peek()).toBe(false)
		t.expect(selected(world)).toBe("A")
		world.stop()
	end)

	t.it("selects a Picker option and toggles a DisclosureGroup with Return and with the engine activation", function()
		local choice, expanded = Compose.cell("a"), Compose.cell(false)
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Screen")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				UI.Picker("Mode")({
					LayoutOrder = 1,
					selected = choice,
					style = "segmented",
					options = {
						{ value = "a", label = "Alpha" },
						{ value = "b", label = "Beta" },
						{ value = "c", label = "Gamma" },
					},
				}),
				UI.DisclosureGroup({
					LayoutOrder = 2,
					expanded = expanded,
					label = "Details",
					content = function()
						return Host.Frame("Details")({})
					end,
				}),
			})
		end)
		select(world, find(world.screen, "b"))
		returnKey(world)
		t.expect(choice:peek()).toBe("b")
		select(world, find(world.screen, "c"))
		find(world.screen, "c").Activated.fire()
		t.expect(choice:peek()).toBe("c")
		local header = find(world.screen, "Header")
		select(world, header)
		returnKey(world)
		t.expect(expanded:peek()).toBe(true)
		header.Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		world.stop()
	end)

	t.it("keeps a card revealed while Tab walks its body and actions and ends it when Tab leaves", function()
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Row")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
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
		t.expect(revealed()).toBe(true)
		local walk = {}
		for _ = 1, 3 do
			tab(world)
			table.insert(walk, `{selected(world)}:{revealed()}`)
		end
		t.expect(walk[1]).toBe("Primary:true")
		t.expect(walk[2]).toBe("Trigger:true")
		t.expect(walk[3]).toBe("Next:false")
		tab(world, true)
		t.expect(selected(world)).toBe("Body")
		t.expect(revealed()).toBe(true)
		world.stop()
	end)

	t.it("reaches the playlist header from the first stop of the page with Tab", function()
		local world = mountExample("02_playlist_table")
		tab(world)
		local first = world.gui.SelectedObject
		t.expect(first ~= nil).toBe(true)
		local stops, reached = 1, nil
		local header = find(world.screen, "Header")
		t.expect(header ~= nil).toBe(true)
		for _ = 1, 80 do
			local current = world.gui.SelectedObject
			if current and current:IsDescendantOf(header) then
				reached = current
				break
			end
			tab(world)
			stops += 1
		end
		t.expect(first:IsDescendantOf(header)).toBe(false)
		t.expect(reached ~= nil).toBe(true)
		t.expect(stops > 1).toBe(true)
		t.expect(reached.Name == "Sort" or reached.Name == "Resize").toBe(true)
		world.stop()
	end)

	t.it(
		"steps the card rail sideways with the arrows and the D-pad, never along Up or Down, and picks with Return or A",
		function()
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
				t.expect(table.concat(keys, ",")).toBe(`DPad{direction},{direction}`)
				arrow.Pressed.fire()
				local node = world.gui.SelectedObject
				if node then
					node.SelectionGained.fire()
				end
			end
			select(world, find(rail, "Card_c1"))
			step("Right")
			t.expect(card()).toBe("Card_c2")
			step("Right")
			t.expect(card()).toBe("Card_c3")
			step("Left")
			t.expect(card()).toBe("Card_c2")
			step("Up")
			t.expect(card()).toBe("Card_c2")
			step("Down")
			t.expect(card()).toBe("Card_c2")
			returnKey(world)
			t.expect(built.report().selectedKey).toBe("c2")
			local shown = find(world.screen, "Selected")
			t.expect(string.find(shown.Text, "Livery 002", 1, true) ~= nil).toBe(true)
			step("Right")
			world.gui.SelectedObject.Activated.fire()
			t.expect(built.report().selectedKey).toBe("c3")
			world.stop()
		end
	)

	t.it("drives the settings sync example with Return, Tab, the engine activation and the steppers", function()
		local world, built = mountExample("03_settings_sync")
		press(world, "DPadDown")
		t.expect(selected(world)).toBe("Music")
		select(world, world.gui.SelectedObject)
		returnKey(world)
		t.expect(built.report().draft.music).toBe(true)
		t.expect(built.report().status).toBe("pending")
		local stops = 0
		repeat
			tab(world)
			stops += 1
		until selected(world) == "Deliver" or stops > 10
		t.expect(selected(world)).toBe("Deliver")
		select(world, world.gui.SelectedObject)
		returnKey(world)
		t.expect(built.report().status).toBe("confirmed")
		t.expect(built.report().server.music).toBe(true)
		local music = find(world.screen, "Music")
		select(world, music)
		music.Activated.fire()
		t.expect(built.report().draft.music).toBe(false)
		t.expect(built.report().status).toBe("pending")
		find(world.screen, "Deliver").Activated.fire()
		t.expect(built.report().status).toBe("confirmed")
		local decrease = find(find(world.screen, "Volume"), "Decrease")
		select(world, decrease)
		decrease.Activated.fire()
		t.expect(built.report().draft.volume).toBe(9)
		t.expect(built.report().status).toBe("pending")
		world.stop()
	end)

	t.it("keeps the selection on the only eligible control when Tab and Shift+Tab have nowhere else to go", function()
		local world = setup(function(UI, Host, engine)
			local E = engine.types.Enum
			return Host.Frame("Screen")({
				Host.UIListLayout({ SortOrder = E.SortOrder.LayoutOrder }),
				UI.Button("Off")({ label = "Off", LayoutOrder = 1, enabled = false }),
				UI.Button("Only")({ label = "Only", LayoutOrder = 2 }),
				UI.Button("Hidden")({ label = "Hidden", LayoutOrder = 3, Visible = false }),
			})
		end)
		tab(world)
		t.expect(selected(world)).toBe("Only")
		tab(world)
		t.expect(selected(world)).toBe("Only")
		tab(world, true)
		t.expect(selected(world)).toBe("Only")
		world.stop()
	end)
end)
