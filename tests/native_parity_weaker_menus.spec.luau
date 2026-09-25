--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	root: any,
	now: () -> number,
	step: (number) -> (),
	stop: () -> (),
}

local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local runtime = Facet.Roblox.createRuntime(engine)
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
		inputParent = root,
		reducedMotion = true,
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop = runtime.mount(function()
		return Host.Frame "Surface" {
			Size = engine.types.UDim2.fromScale(1, 1),
			build(UI, Host, engine),
		}
	end, root)
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		root = root,
		now = function()
			return now
		end,
		step = function(seconds: number)
			for _ = 1, math.ceil(seconds * 60) do
				now += 1 / 60
				engine.heartbeat.fire(1 / 60)
			end
		end,
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

local function all(root: any, name: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node.Name == name then
			table.insert(found, node)
		end
	end
	return found
end

local function action(root: any, name: string): any
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			return node:FindFirstChild(name)
		end
	end
	return nil
end

local function enabledContexts(root: any, name: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			table.insert(found, node)
		end
	end
	return found
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

local function mountError(build: (any, any) -> any): string?
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI =
		Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
	local Host = runtime.constructors
	local ok, message = pcall(function()
		local stop = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host) })
		end, engine.new("Folder"))
		stop()
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

local function refuses(message: string, build: (any, any) -> any): boolean
	local failure = mountError(build)
	return failure ~= nil and string.find(failure, message, 1, true) ~= nil
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

local function title(row: any): string
	local label = find(row, "Title")
	return if label then label.Text else row.Text
end

local function count(row: any): string?
	local badge = row:FindFirstChild("Count", true)
	if badge == nil then
		return nil
	end
	if badge:IsA("TextLabel") then
		return badge.Text
	end
	for _, node in badge:GetDescendants() do
		if node:IsA("TextLabel") and node.Text ~= "" then
			return node.Text
		end
	end
	return nil
end

local function selectables(root: any): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node:IsA("GuiObject") and node.Selectable and node.Visible and node.Interactable then
			table.insert(found, node)
		end
	end
	return found
end

local THREE = {
	{ value = "easy", label = "Easy" },
	{ value = "normal", label = "Normal" },
	{ value = "hard", label = "Hard" },
}

local NESTED = {
	{
		id = "adjust",
		label = "Adjust",
		children = {
			{ id = "head", label = "Head Adjustment", onSelect = function() end },
			{
				id = "layer",
				label = "Layering",
				children = {
					{ id = "clothing", label = "Clothing Layering", onSelect = function() end },
					{ id = "makeup", label = "Makeup Layering", onSelect = function() end },
				},
			},
		},
	},
	{ id = "skin", label = "Skin Color", onSelect = function() end },
}

local function place(world: World, trigger: any, x: number, y: number, width: number, height: number)
	trigger.AbsolutePosition = V2(world, x, y)
	trigger.AbsoluteSize = V2(world, width, height)
end

local function extent(world: World, width: number, height: number): any
	local modal = find(world.root, "Modal")
	modal.AbsolutePosition = V2(world, 0, 0)
	modal.AbsoluteSize = V2(world, width, height)
	return modal
end

t.describe("native parity weaker menus", function()
	t.it(
		"opens a radial menu from its launcher, runs only the chosen command and releases every native object",
		function()
			local engine: any = engineLib.new()
			local now = 0
			engine.clock = function()
				return now
			end
			local function step(seconds: number)
				for _ = 1, math.ceil(seconds * 60) do
					now += 1 / 60
					engine.heartbeat.fire(1 / 60)
				end
			end
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local target = engine.new("Folder")
			local baseline = engine.census()
			local fired = 0
			local UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					services = { GuiService = gui, UserInputService = input },
					reducedMotion = false,
				} :: any
			)
			local stop, screen = runtime.mount(function()
				return runtime.constructors.ScreenGui({
					UI.RadialMenu "Actions" {
						items = {
							{
								id = "wave",
								label = "Wave",
								onSelect = function()
									fired += 1
								end,
							},
							{
								id = "point",
								label = "Point",
								onSelect = function()
									fired += 10
								end,
							},
						},
					},
				})
			end, target)
			step(0.3)
			t.expect(find(screen, "RadialPanel")).toBeNil()
			find(screen, "Launcher").Activated.fire()
			step(0.7)
			local panel = find(screen, "RadialPanel")
			t.expect(panel ~= nil).toBe(true)
			t.expect(find(panel, "point") ~= nil).toBe(true)
			find(panel, "wave").Activated.fire()
			step(0.7)
			t.expect(fired).toBe(1)
			t.expect(find(screen, "RadialPanel")).toBeNil()
			t.expect(panel.isDestroyed()).toBe(true)
			stop()
			step(0.5)
			runtime:dispose()
			t.expect(screen.isDestroyed()).toBe(true)
			t.expect(engine.heartbeat.count()).toBe(0)
			local after = engine.census()
			t.expect(after.live).toBe(baseline.live)
			t.expect(after.connections).toBe(baseline.connections)
		end
	)

	t.it("overlays the quick palette on a 393 pixel phone inside its own box and sets the shared palette", function()
		local Roblox = require("../src/vendor/compose/roblox")
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
			avatar.AbsoluteSize = engine.types.Vector2.new(393, 852)
			local quick = find(avatar, "QuickPalette")
			local launcher = find(quick, "Launcher")
			t.expect(launcher.Visible).toBe(true)
			t.expect(model.palette:peek()).toBe("sage")
			launcher.Activated.fire()
			local modal = find(target, "Modal")
			t.expect(within(modal, quick)).toBe(false)
			t.expect(modal.Size.X.Scale).toBe(1)
			t.expect(modal.Size.Y.Scale).toBe(1)
			modal.AbsolutePosition = engine.types.Vector2.new(0, 0)
			modal.AbsoluteSize = engine.types.Vector2.new(393, 852)
			local panel = find(target, "RadialPanel")
			t.expect(panel.Parent).toBe(modal)
			local x = panel.Position.X.Scale * 393 + panel.Position.X.Offset
			local y = panel.Position.Y.Scale * 852 + panel.Position.Y.Offset
			local width = panel.Size.X.Scale * 393 + panel.Size.X.Offset
			local height = panel.Size.Y.Scale * 852 + panel.Size.Y.Offset
			t.expect(x >= 0 and y >= 0).toBe(true)
			t.expect(x + width <= 393).toBe(true)
			t.expect(y + height <= 852).toBe(true)
			t.expect(height >= 400).toBe(true)
			find(panel, "clay").Activated.fire()
			t.expect(model.palette:peek()).toBe("clay")
			stop()
		end, runtime.reactor)
		lifetime.dispose()
		t.expect(#target:GetChildren()).toBe(0)
		runtime:dispose()
	end)

	t.it("closes an open menu picker on a tap away without changing the selection and restores the trigger", function()
		local selected, opened, changes = Compose.cell("normal"), Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Picker "Difficulty" {
				style = "menu",
				selected = selected,
				isPresented = opened,
				options = THREE,
				onChange = function()
					changes += 1
				end,
			}
		end)
		local trigger = find(world.root, "Trigger")
		place(world, trigger, 100, 40, 160, 44)
		world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		t.expect(opened:peek()).toBe(true)
		local panel = find(world.root, "MenuPanel")
		t.expect(within(world.gui.SelectedObject, panel)).toBe(true)
		extent(world, 800, 600)
		panel.AbsolutePosition = V2(world, 100, 88)
		panel.AbsoluteSize = V2(world, 220, 150)
		local catcher = find(world.root, "DismissOutside")
		t.expect(catcher.Size.X.Scale).toBe(1)
		t.expect(catcher.Size.Y.Scale).toBe(1)
		catcher.Activated.fire({ Position = V2(world, 700, 550) })
		t.expect(opened:peek()).toBe(false)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(selected:peek()).toBe("normal")
		t.expect(changes).toBe(0)
		t.expect(world.gui.SelectedObject).toBe(trigger)
		trigger.Activated.fire()
		find(world.root, "Modal").AbsoluteSize = V2(world, 800, 600)
		panel = find(world.root, "MenuPanel")
		panel.AbsolutePosition = V2(world, 100, 88)
		panel.AbsoluteSize = V2(world, 220, 150)
		find(world.root, "DismissOutside").Activated.fire({ Position = V2(world, 180, 50) })
		t.expect(opened:peek()).toBe(false)
		t.expect(selected:peek()).toBe("normal")
		t.expect(changes).toBe(0)
		t.expect(world.gui.SelectedObject).toBe(trigger)
		world.stop()
	end)

	t.it("closes an open menu picker on Back and leaves Back unclaimed while it is closed", function()
		local selected, opened, changes = Compose.cell("normal"), Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Picker "Difficulty" {
				style = "menu",
				selected = selected,
				isPresented = opened,
				options = THREE,
				onChange = function()
					changes += 1
				end,
			}
		end)
		local Enum = world.engine.types.Enum
		local function backClaims(): number
			local count = 0
			for _, node in world.root:GetDescendants() do
				if node:IsA("InputContext") and node.Enabled then
					for _, binding in node:GetDescendants() do
						if
							binding:IsA("InputBinding")
							and (binding.KeyCode == Enum.KeyCode.ButtonB or binding.KeyCode == Enum.KeyCode.Escape)
						then
							count += 1
						end
					end
				end
			end
			return count
		end
		local trigger = find(world.root, "Trigger")
		world.gui.SelectedObject = trigger
		t.expect(backClaims()).toBe(0)
		trigger.Activated.fire()
		t.expect(backClaims() > 0).toBe(true)
		world.gui.SelectedObject = find(find(world.root, "MenuPanel"), "hard")
		action(world.root, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(selected:peek()).toBe("normal")
		t.expect(changes).toBe(0)
		t.expect(world.gui.SelectedObject).toBe(trigger)
		t.expect(backClaims()).toBe(0)
		t.expect(action(world.root, "ModalBack")).toBeNil()
		world.stop()
	end)

	t.it("renders the icon-only glyph without a label and refuses an option without an icon", function()
		local options = Compose.cell({ { value = "a", label = "Route", icon = "checkmark" } })
		local world = setup(function(UI)
			return UI.Picker "Icons" {
				style = "segmented",
				iconOnly = true,
				selected = Compose.cell("a"),
				options = options,
			}
		end)
		local row = find(find(world.root, "Icons"), "a")
		t.expect(find(row, "LeadingIcon").Image).toBe(themes.resolveIcon({}, "checkmark"))
		t.expect(title(row)).toBe("")
		t.expect(row:GetAttribute("FacetLabel")).toBe("Route")
		local ok = pcall(function()
			options:set({ { value = "a", label = "Route" } })
		end)
		t.expect(ok).toBe(false)
		world.stop()
		for _, style in { "segmented", "inline", "radioGroup", "menu" } do
			for _, live in { false, true } do
				local list = { { value = "a", label = "Route" } }
				t.expect(refuses("Picker.iconOnly requires an icon on each option", function(UI)
					return UI.Picker({
						style = style,
						iconOnly = true,
						selected = Compose.cell("a"),
						options = if live then Compose.cell(list) else list,
					})
				end)).toBe(true)
			end
		end
	end)

	t.it("keeps choice rows, their selection focus and missing selected values through live replacements", function()
		local selected = Compose.cell("a")
		local options = Compose.cell({
			{ id = "one", value = "a", label = "Alpine", badge = 3 },
			{ id = "two", value = "b", label = "Beach" },
		})
		local world = setup(function(UI)
			return UI.Picker "Routes" { style = "radioGroup", selected = selected, options = options }
		end)
		local picker = find(world.root, "Routes")
		local row = find(picker, "one")
		world.gui.SelectedObject = row
		t.expect(title(row)).toBe("Alpine")
		t.expect(count(row)).toBe("3")
		t.expect(find(row, "Description").Visible).toBe(false)
		options:set({
			{ id = "one", value = "a", label = "Alpine pass", description = "A mountain route", badge = 7 },
			{ id = "two", value = "c", label = "Coast" },
		})
		t.expect(find(picker, "one")).toBe(row)
		t.expect(world.gui.SelectedObject).toBe(row)
		t.expect(title(row)).toBe("Alpine pass")
		t.expect(count(row)).toBe("7")
		t.expect(find(row, "Description").Text).toBe("A mountain route")
		t.expect(find(row, "Description").Visible).toBe(true)
		t.expect(selected:peek()).toBe("a")
		options:set({ { id = "one", value = "a", label = "Alpine pass" }, { id = "two", value = "c", label = "Coast" } })
		t.expect(find(picker, "one")).toBe(row)
		t.expect(world.gui.SelectedObject).toBe(row)
		t.expect(title(row)).toBe("Alpine pass")
		t.expect(count(row)).toBeNil()
		t.expect(find(row, "Description").Visible).toBe(false)
		local survivor = find(picker, "two")
		options:set({ { id = "two", value = "c", label = "Coast" } })
		t.expect(find(picker, "one")).toBeNil()
		t.expect(find(picker, "two")).toBe(survivor)
		t.expect(selected:peek()).toBe("a")
		survivor.Activated.fire()
		t.expect(selected:peek()).toBe("c")
		world.stop()
	end)

	t.it("keeps a radio group exclusive and skips a disabled option without rewriting the owner state", function()
		local selected, enabled, changes = Compose.cell("a"), Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Picker "Access" {
				style = "radioGroup",
				selected = selected,
				onChange = function()
					changes += 1
				end,
				options = {
					{ value = "a", label = "Open" },
					{ value = "b", label = "Club", description = "Requires club membership", enabled = enabled },
				},
			}
		end)
		local picker = find(world.root, "Access")
		local a, b = find(picker, "a"), find(picker, "b")
		local function current(): { string }
			local names = {}
			for _, node in picker:GetDescendants() do
				if node:HasTag("facet-choice-current") then
					table.insert(names, node.Name)
				end
			end
			return names
		end
		t.expect(b.Interactable).toBe(false)
		b.Activated.fire()
		t.expect(selected:peek()).toBe("a")
		t.expect(changes).toBe(0)
		t.expect(current()).toEqual({ "a" })
		enabled:set(true)
		b.Activated.fire()
		t.expect(selected:peek()).toBe("b")
		t.expect(changes).toBe(1)
		t.expect(current()).toEqual({ "b" })
		enabled:set(false)
		t.expect(selected:peek()).toBe("b")
		t.expect(changes).toBe(1)
		t.expect(current()).toEqual({ "b" })
		a.Activated.fire()
		t.expect(selected:peek()).toBe("a")
		t.expect(current()).toEqual({ "a" })
		world.stop()
	end)

	t.it("refuses malformed picker options and callback contracts by name for static and live sources", function()
		local optionCases: { { any } } = {
			{ "Picker options require a dense array", { named = { value = "a", label = "Alpha" } } },
			{
				"Picker options require a dense array",
				{ [1] = { value = "a", label = "Alpha" }, [3] = { value = "b", label = "Beta" } },
			},
			{
				"Picker options require unique values or ids",
				{ { value = "a", label = "Alpha" }, { value = "a", label = "Again" } },
			},
			{ "Picker options require unique values or ids", { { label = "Nameless" } } },
			{ "Picker options require nonempty labels", { { value = "a", label = "" } } },
			{ "Picker description must be text", { { value = "a", label = "Alpha", description = false } } },
			{ "Picker option enabled must be a boolean", { { value = "a", label = "Alpha", enabled = "false" } } },
			{ "Picker option badge must be text or a number", { { value = "a", label = "Alpha", badge = {} } } },
			{ "Picker option icon must be an icon name", { { value = "a", label = "Alpha", icon = false } } },
			{ "Unknown Picker option field misspelled", { { value = "a", label = "Alpha", misspelled = true } } },
		}
		for _, style in { "radioGroup", "menu", "segmented" } do
			for _, live in { false, true } do
				for _, case in optionCases do
					t.expect(refuses(case[1], function(UI)
						return UI.Picker({
							style = style,
							selected = Compose.cell("a"),
							options = if live then Compose.cell(case[2]) else case[2],
						})
					end)).toBe(true)
				end
			end
		end
		local specCases: { { any } } = {
			{ "Picker.onChange must be a function", { onChange = true } },
			{ "Picker.onChanging must be a function", { onChanging = true } },
			{ "Picker.required must be a boolean", { required = "false" } },
			{ "Picker.enabled must be a boolean", { enabled = "false" } },
			{ "Picker.enabled must be a boolean", { enabled = Compose.cell("false") } },
			{ "unknown option 'misspelled'", { misspelled = true } },
		}
		for _, style in { "radioGroup", "menu", "navigationLink", "automatic" } do
			for _, live in { false, true } do
				for _, case in specCases do
					t.expect(refuses(case[1], function(UI)
						local list = { { value = "a", label = "Alpha" } }
						local spec: { [string]: any } = {
							style = style,
							selected = Compose.cell("a"),
							options = if live then Compose.cell(list) else list,
						}
						for key, value in case[2] do
							spec[key] = value
						end
						return UI.Picker(spec)
					end)).toBe(true)
				end
			end
		end
		t.expect(mountError(function(UI)
			return UI.Picker({
				style = "radioGroup",
				selected = Compose.cell("a"),
				enabled = Compose.cell(true),
				required = true,
				onChange = function() end,
				onChanging = function()
					return true
				end,
				options = { { id = "x", value = "a", label = "Alpha", icon = "edit", badge = 2, enabled = true } },
			})
		end)).toBeNil()
	end)

	t.it("collapses four long labels off the segmented strip below 360 pixels with no environment wiring", function()
		local long = {
			{ value = "a", label = "Screen-anchored heads-up display" },
			{ value = "b", label = "Billboard following a world object" },
			{ value = "c", label = "World-fixed surface on a part" },
			{ value = "d", label = "Nothing presented at all today" },
		}
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Picker "Narrow" { selected = Compose.cell("a"), options = long },
				UI.Picker "Wide" { selected = Compose.cell("a"), options = long },
			})
		end)
		local Enum = world.engine.types.Enum
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		local narrow, wide = find(world.root, "Narrow"), find(world.root, "Wide")
		narrow.AbsoluteSize = V2(world, 300, 44)
		wide.AbsoluteSize = V2(world, 1400, 44)
		local function presentation(node: any): any
			return node:FindFirstChild("Presentation")
		end
		t.expect(presentation(wide):HasTag("facet-segmented")).toBe(true)
		t.expect(presentation(narrow):HasTag("facet-segmented")).toBe(false)
		t.expect(find(presentation(narrow), "d"):HasTag("facet-choice")).toBe(true)
		t.expect(find(presentation(narrow), "Trigger")).toBeNil()
		world.input.PreferredInput = Enum.PreferredInput.Touch
		t.expect(find(presentation(narrow), "Trigger") ~= nil).toBe(true)
		t.expect(presentation(wide):HasTag("facet-segmented")).toBe(true)
		narrow.AbsoluteSize = V2(world, 360, 44)
		t.expect(presentation(narrow):HasTag("facet-segmented")).toBe(true)
		world.stop()
	end)

	t.it("wraps an explicit segmented strip inside the width of its labelled row", function()
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Picker "Handling" {
					label = "Handling",
					style = "segmented",
					selected = Compose.cell("a"),
					options = {
						{ value = "a", label = "Arcade handling" },
						{ value = "b", label = "Simulation handling" },
						{ value = "c", label = "Drift assist" },
						{ value = "d", label = "Rally gravel" },
					},
				},
			})
		end)
		local row = find(world.root, "Handling")
		local options = find(row, "Options")
		t.expect(options:FindFirstChildWhichIsA("UIListLayout").Wraps).toBe(true)
		t.expect(options:FindFirstChild("TargetFloor").MinSize.Y).toBe(50)
		row.AbsoluteSize = V2(world, 390, 100)
		local limit
		for _, child in options:GetChildren() do
			if child.ClassName == "UISizeConstraint" and child.Name ~= "TargetFloor" then
				limit = child
			end
		end
		t.expect(limit ~= nil).toBe(true)
		t.expect(limit.MaxSize.X).toBe(390)
		row.AbsoluteSize = V2(world, 1280, 100)
		t.expect(limit.MaxSize.X).toBe(1280)
		world.stop()
	end)

	t.it("leaves the segmented strip when the measured labels do not fit the width", function()
		local long = {
			{ value = "a", label = "Automatic transmission mode" },
			{ value = "b", label = "Manual transmission override" },
			{ value = "c", label = "Sequential paddle shift gear" },
			{ value = "d", label = "Assisted launch control mode" },
		}
		local world = setup(function(UI, Host)
			return Host.Frame({ UI.Picker "Gears" { selected = Compose.cell("a"), options = long } })
		end)
		local Enum = world.engine.types.Enum
		world.input.PreferredInput = Enum.PreferredInput.Touch
		local picker = find(world.root, "Gears")
		picker.AbsoluteSize = V2(world, 400, 44)
		local measure = find(picker, "LabelMeasure")
		t.expect(measure ~= nil).toBe(true)
		t.expect(measure.Visible).toBe(false)
		t.expect(measure.Text).toBe(
			"Automatic transmission modeManual transmission overrideSequential paddle shift gearAssisted launch control mode"
		)
		local function presentation(): any
			return picker:FindFirstChild("Presentation")
		end
		measure.TextBounds = V2(world, 200, 18)
		t.expect(presentation():HasTag("facet-segmented")).toBe(true)
		measure.TextBounds = V2(world, 791, 18)
		t.expect(presentation():HasTag("facet-segmented")).toBe(false)
		t.expect(find(presentation(), "Trigger") ~= nil).toBe(true)
		picker.AbsoluteSize = V2(world, 920, 44)
		t.expect(presentation():HasTag("facet-segmented")).toBe(true)
		world.stop()
	end)

	t.it(
		"opens the row menu from ButtonX and Menu, lists leading then trailing actions and scopes it to the selected row",
		function()
			local fired: { string } = {}
			local function row(UI: any, name: string): any
				return UI.RowActions(name)({
					content = UI.Button(name .. "Body")({ label = name }),
					leading = {
						{
							id = "archive",
							label = "Archive",
							onActivate = function()
								table.insert(fired, name .. ":archive")
							end,
						},
					},
					trailing = {
						{
							id = "flag",
							label = "Flag",
							onActivate = function()
								table.insert(fired, name .. ":flag")
							end,
						},
						{
							id = "delete",
							label = "Delete",
							role = "destructive",
							onActivate = function()
								table.insert(fired, name .. ":delete")
							end,
						},
					},
				})
			end
			local world = setup(function(UI, Host)
				return Host.Frame({ row(UI, "A"), row(UI, "B") })
			end)
			local bodyA = find(world.root, "ABody")
			world.gui.SelectedObject = bodyA
			t.expect(#enabledContexts(world.root, "RowActionsReveal")).toBe(1)
			local reveal = action(world.root, "RowActionsReveal")
			t.expect(within(reveal, find(world.root, "A")) or within(bodyA, find(world.root, "A"))).toBe(true)
			local keys = {}
			for _, binding in reveal:GetChildren() do
				table.insert(keys, binding.KeyCode.Name)
			end
			table.sort(keys)
			t.expect(keys).toEqual({ "ButtonX", "Menu" })
			reveal.Pressed.fire()
			local panel = find(world.root, "MenuPanel")
			t.expect(panel ~= nil).toBe(true)
			t.expect(#all(world.root, "MenuPanel")).toBe(1)
			t.expect(world.gui.SelectedObject.Name).toBe("leading:archive")
			local order = {}
			for _, node in panel:GetDescendants() do
				if node:HasTag("facet-menu-item") then
					table.insert(order, node)
				end
			end
			table.sort(order, function(left, right)
				return left.LayoutOrder < right.LayoutOrder
			end)
			local names = {}
			for _, node in order do
				table.insert(names, node.Name)
			end
			t.expect(names).toEqual({ "leading:archive", "trailing:flag", "trailing:delete" })
			for _, direction in { "Up", "Down", "Left", "Right" } do
				t.expect(panel["SelectionBehavior" .. direction]).toBe(world.engine.types.Enum.SelectionBehavior.Stop)
			end
			t.expect(action(world.root, "RowActionsDelete")).toBeNil()
			action(world.root, "ModalBack").Pressed.fire()
			t.expect(find(world.root, "MenuPanel")).toBeNil()
			t.expect(world.gui.SelectedObject).toBe(bodyA)
			t.expect(#fired).toBe(0)
			action(world.root, "RowActionsReveal").Pressed.fire()
			find(find(world.root, "MenuPanel"), "trailing:flag").Activated.fire()
			t.expect(fired).toEqual({ "A:flag" })
			t.expect(find(world.root, "MenuPanel")).toBeNil()
			world.gui.SelectedObject = find(world.root, "BBody")
			t.expect(#enabledContexts(world.root, "RowActionsReveal")).toBe(1)
			action(world.root, "RowActionsReveal").Pressed.fire()
			find(find(world.root, "MenuPanel"), "leading:archive").Activated.fire()
			t.expect(fired).toEqual({ "A:flag", "B:archive" })
			world.stop()
		end
	)

	t.it("runs a destructive row action from its menu through the full departure and closes the menu first", function()
		local invoked = 0
		local world = setup(function(UI)
			return UI.RowActions "Row" {
				content = UI.Button "Body" { label = "Row" },
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onActivate = function()
							invoked += 1
						end,
					},
				},
			}
		end, { reducedMotion = false })
		local row = find(world.root, "Row")
		row.AbsoluteSize = V2(world, 300, 44)
		world.gui.SelectedObject = find(row, "Body")
		action(world.root, "RowActionsReveal").Pressed.fire()
		local panel = find(world.root, "MenuPanel")
		find(panel, "trailing:delete").Activated.fire()
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(find(world.root, "DismissOutside")).toBeNil()
		t.expect(invoked).toBe(0)
		world.step(0.1)
		t.expect(invoked).toBe(0)
		t.expect(find(row, "Content").Position.X.Offset < 0).toBe(true)
		local frames = 0
		while invoked == 0 and frames < 60 do
			world.step(1 / 60)
			frames += 1
		end
		t.expect(invoked).toBe(1)
		t.expect(world.now() >= 0.2).toBe(true)
		t.expect(row.Size.Y.Offset).toBe(0)
		world.step(0.5)
		t.expect(invoked).toBe(1)
		world.stop()
	end)

	t.it("presents a wide menu as a cascade for pointer and gamepad and as a sheet for touch", function()
		local presented = Compose.cell(true)
		local world = setup(function(UI)
			return UI.Menu "Gear" { isPresented = presented, items = NESTED }
		end)
		local Enum = world.engine.types.Enum
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		extent(world, 1280, 720)
		find(world.root, "adjust").Activated.fire()
		t.expect(find(world.root, "AncestorMenu") ~= nil).toBe(true)
		t.expect(find(world.root, "MenuPanel").Size.X.Scale).toBe(0)
		world.input.PreferredInput = Enum.PreferredInput.Touch
		t.expect(find(world.root, "AncestorMenu")).toBeNil()
		t.expect(find(world.root, "MenuPanel").Size.X.Scale).toBe(1)
		t.expect(find(world.root, "Back") ~= nil).toBe(true)
		t.expect(find(world.root, "head") ~= nil).toBe(true)
		world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
		t.expect(find(world.root, "AncestorMenu") ~= nil).toBe(true)
		t.expect(find(world.root, "MenuPanel").Size.X.Scale).toBe(0)
		t.expect(presented:peek()).toBe(true)
		world.stop()
		for _, case in { { "sheet", "KeyboardAndMouse", 1 }, { "menu", "Touch", 0 } } do
			local forced = setup(function(UI)
				return UI.Menu { isPresented = Compose.cell(true), presentation = case[1], items = NESTED }
			end)
			forced.input.PreferredInput = (Enum.PreferredInput :: any)[case[2]]
			extent(forced, 1280, 720)
			find(forced.root, "adjust").Activated.fire()
			t.expect(find(forced.root, "MenuPanel").Size.X.Scale).toBe(case[3])
			t.expect(find(forced.root, "AncestorMenu") == nil).toBe(case[1] == "sheet")
			forced.stop()
		end
	end)

	t.it("opens a menu against its trigger rectangle, flips above it near the bottom and runs an item once", function()
		local runs = 0
		local world = setup(function(UI)
			return UI.Menu "More" {
				label = "More",
				items = {
					{
						id = "go",
						label = "Go",
						onSelect = function()
							runs += 1
						end,
					},
				},
			}
		end)
		local trigger = find(world.root, "Trigger")
		place(world, trigger, 100, 50, 120, 44)
		trigger.Activated.fire()
		extent(world, 1000, 720)
		local panel = find(world.root, "MenuPanel")
		panel.AbsoluteSize = V2(world, 220, 200)
		t.expect(panel.Position.Y.Offset >= 50 + 44).toBe(true)
		t.expect(panel.Position.X.Offset).toBe(100)
		place(world, trigger, 950, 600, 120, 44)
		t.expect(panel.Position.Y.Offset + 200 <= 600).toBe(true)
		t.expect(panel.Position.X.Offset + 220 <= 1000 - 8).toBe(true)
		find(panel, "go").Activated.fire()
		t.expect(runs).toBe(1)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(find(world.root, "Modal")).toBeNil()
		world.stop()
	end)

	t.it("replaces a compact sheet level on entry and walks back one level from the row, Left and Back", function()
		local presented = Compose.cell(false)
		local world = setup(function(UI)
			return UI.Menu "Avatar" { isPresented = presented, items = NESTED }
		end)
		local trigger = find(world.root, "Trigger")
		world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		extent(world, 360, 640)
		t.expect(find(world.root, "MenuPanel").Size.X.Scale).toBe(1)
		t.expect(find(world.root, "Back")).toBeNil()
		t.expect(world.gui.SelectedObject.Name).toBe("adjust")
		local function enter(id: string)
			world.gui.SelectedObject = find(find(world.root, "MenuPanel"), id)
			find(find(world.root, "MenuPanel"), id).Activated.fire()
		end
		enter("adjust")
		t.expect(find(world.root, "AncestorMenu")).toBeNil()
		t.expect(find(world.root, "adjust")).toBeNil()
		t.expect(find(world.root, "head") ~= nil).toBe(true)
		t.expect(find(world.root, "Back") ~= nil).toBe(true)
		t.expect(#all(world.root, "MenuPanel")).toBe(1)
		find(world.root, "Back").Activated.fire()
		t.expect(presented:peek()).toBe(true)
		t.expect(find(world.root, "adjust") ~= nil).toBe(true)
		t.expect(find(world.root, "Back")).toBeNil()
		t.expect(world.gui.SelectedObject.Name).toBe("adjust")
		enter("adjust")
		enter("layer")
		t.expect(find(world.root, "clothing") ~= nil).toBe(true)
		t.expect(find(world.root, "head")).toBeNil()
		action(world.root, "MenuLeft").Pressed.fire()
		t.expect(find(world.root, "head") ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject.Name).toBe("layer")
		action(world.root, "ModalBack").Pressed.fire()
		t.expect(presented:peek()).toBe(true)
		t.expect(find(world.root, "adjust") ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject.Name).toBe("adjust")
		action(world.root, "ModalBack").Pressed.fire()
		t.expect(presented:peek()).toBe(false)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(world.gui.SelectedObject).toBe(trigger)
		world.stop()
	end)

	t.it("stacks each cascade level beside its parent at the trigger without overlapping it", function()
		local world = setup(function(UI)
			return UI.Menu "Avatar" { items = NESTED }
		end)
		local trigger = find(world.root, "Trigger")
		place(world, trigger, 100, 50, 120, 44)
		trigger.Activated.fire()
		extent(world, 1600, 900)
		find(world.root, "adjust").Activated.fire()
		local function levels(): { any }
			local found = all(world.root, "AncestorMenu")
			table.sort(found, function(left, right)
				return left.Position.X.Offset < right.Position.X.Offset
			end)
			return found
		end
		local first = levels()
		t.expect(#first).toBe(1)
		t.expect(find(first[1], "adjust") ~= nil).toBe(true)
		t.expect(first[1].Position.X.Offset).toBe(100)
		local panel = find(world.root, "MenuPanel")
		t.expect(panel.Position.X.Offset >= first[1].Position.X.Offset + first[1].Size.X.Offset).toBe(true)
		t.expect(panel.Position.Y.Offset).toBe(first[1].Position.Y.Offset)
		find(panel, "layer").Activated.fire()
		local second = levels()
		t.expect(#second).toBe(2)
		t.expect(find(second[2], "layer") ~= nil).toBe(true)
		t.expect(second[2].Position.X.Offset >= second[1].Position.X.Offset + second[1].Size.X.Offset).toBe(true)
		t.expect(panel.Position.X.Offset >= second[2].Position.X.Offset + second[2].Size.X.Offset).toBe(true)
		t.expect(find(panel, "clothing") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("labels the sheet Back row with the literal Back unless backLabel replaces it", function()
		for _, case in { { nil, "Back" }, { "Zurück", "Zurück" } } do
			local world = setup(function(UI)
				return UI.Menu {
					isPresented = Compose.cell(true),
					presentation = "sheet",
					backLabel = case[1],
					items = NESTED,
				}
			end)
			find(world.root, "adjust").Activated.fire()
			local back = find(world.root, "Back")
			t.expect(back.Text).toBe(case[2])
			t.expect(back.ClassName).toBe("TextButton")
			t.expect(back.LayoutOrder < find(world.root, "head").LayoutOrder).toBe(true)
			world.stop()
		end
	end)

	t.it("switches the menu scenario idiom at depth and rebuilds the open chain in place", function()
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
		local target = engine.new("Folder")
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1200, height = 900 }),
			inputTarget = target,
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					services = { GuiService = gui, UserInputService = input },
					reducedMotion = true,
				} :: any
			),
		}
		local scenario = require("../examples/gallery/scenarios/menu")
		local built
		local stop, screen = runtime.mount(function()
			built = scenario.build(ctx)
			return ctx.Host.ScreenGui({ built.screen() })
		end, target)
		local function modal(): any
			local node = find(screen, "Modal")
			node.AbsolutePosition = engine.types.Vector2.new(0, 0)
			node.AbsoluteSize = engine.types.Vector2.new(1200, 900)
			return node
		end
		local function enter(id: string)
			find(find(screen, "MenuPanel"), id).Activated.fire()
		end
		built.steps.idiom(built, "panel")
		find(find(screen, "CardTap"), "Trigger").Activated.fire()
		modal()
		enter("layering")
		t.expect(#all(screen, "AncestorMenu")).toBe(1)
		t.expect(find(find(screen, "MenuPanel"), "clothing") ~= nil).toBe(true)
		enter("makeup")
		t.expect(#all(screen, "AncestorMenu")).toBe(2)
		t.expect(find(find(screen, "MenuPanel"), "lips") ~= nil).toBe(true)
		built.steps.idiom(built, "sheet")
		t.expect(#all(screen, "AncestorMenu")).toBe(0)
		t.expect(#all(screen, "MenuPanel")).toBe(1)
		t.expect(find(find(screen, "MenuPanel"), "lips") ~= nil).toBe(true)
		t.expect(find(find(screen, "MenuPanel"), "Back") ~= nil).toBe(true)
		t.expect(string.find(built.report().state, scenario.copy.open, 1, true) ~= nil).toBe(true)
		built.steps.idiom(built, "panel")
		t.expect(#all(screen, "AncestorMenu")).toBe(2)
		t.expect(find(find(screen, "MenuPanel"), "lips") ~= nil).toBe(true)
		find(find(screen, "MenuPanel"), "lips").Activated.fire()
		t.expect(built.report().ran).toBe(scenario.copy.lips)
		t.expect(find(screen, "MenuPanel")).toBeNil()
		built.steps.idiom(built, "sheet")
		find(find(screen, "CardTap"), "Trigger").Activated.fire()
		modal()
		t.expect(find(find(screen, "MenuPanel"), "Back")).toBeNil()
		enter("layering")
		t.expect(#all(screen, "MenuPanel")).toBe(1)
		t.expect(find(find(screen, "MenuPanel"), "accessory")).toBeNil()
		t.expect(find(find(screen, "MenuPanel"), "clothing") ~= nil).toBe(true)
		t.expect(find(find(screen, "MenuPanel"), "Back") ~= nil).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("shows the selected value, the disclosure chevron and the label row on a menu picker trigger", function()
		local selected, changes = Compose.cell("normal"), {}
		local world = setup(function(UI)
			return UI.Picker "Difficulty" {
				style = "menu",
				label = "Difficulty",
				selected = selected,
				options = THREE,
				onChange = function(value)
					table.insert(changes, value)
				end,
			}
		end)
		local picker = find(world.root, "Difficulty")
		t.expect(find(picker, "Label").Text).toBe("Difficulty")
		local value = find(picker, "Value")
		t.expect(find(picker, "Label").LayoutOrder < value.LayoutOrder).toBe(true)
		t.expect(value.AnchorPoint.X).toBe(0)
		t.expect(value.Position.X.Scale).toBe(0)
		local trigger = find(value, "Trigger")
		t.expect(trigger.Text).toBe("Normal")
		t.expect(trigger:HasTag("facet-disclosure")).toBe(true)
		local chevron = find(trigger, "Disclosure")
		t.expect(chevron:IsA("ImageLabel")).toBe(true)
		t.expect(chevron.Image).toBe(themes.resolveIcon({}, "chevron.up.chevron.down"))
		local focusable = selectables(picker)
		t.expect(#focusable).toBe(1)
		t.expect(focusable[1]).toBe(trigger)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		for _, option in THREE do
			t.expect(find(picker, option.value)).toBeNil()
		end
		trigger.Activated.fire()
		local panel = find(world.root, "MenuPanel")
		for _, option in THREE do
			t.expect(title(find(panel, option.value))).toBe(option.label)
		end
		find(panel, "hard").Activated.fire()
		t.expect(selected:peek()).toBe("hard")
		t.expect(changes).toEqual({ "hard" })
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(trigger.Text).toBe("Hard")
		trigger.Activated.fire()
		find(find(world.root, "MenuPanel"), "hard").Activated.fire()
		t.expect(changes).toEqual({ "hard" })
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		t.expect(trigger.Text).toBe("Hard")
		world.stop()
	end)

	t.it("lists every option with its label and check after pointer and touch activation of the trigger", function()
		for _, kind in { "MouseButton1", "Touch" } do
			local world = setup(function(UI)
				return UI.Picker "Difficulty" { style = "menu", selected = Compose.cell("normal"), options = THREE }
			end)
			local Enum = world.engine.types.Enum
			find(world.root, "Trigger").Activated.fire({
				UserInputType = (Enum.UserInputType :: any)[kind],
				Position = V2(world, 10, 10),
			})
			local panel = find(world.root, "MenuPanel")
			t.expect(panel ~= nil).toBe(true)
			local rows = {}
			for _, node in panel:GetDescendants() do
				if node:HasTag("facet-menu-item") then
					table.insert(rows, node)
				end
			end
			table.sort(rows, function(left, right)
				return left.LayoutOrder < right.LayoutOrder
			end)
			t.expect(#rows).toBe(#THREE)
			for index, option in THREE do
				t.expect(rows[index].Name).toBe(option.value)
				t.expect(title(rows[index])).toBe(option.label)
				t.expect(find(rows[index], "TrailingIcon").Visible).toBe(option.value == "normal")
			end
			world.stop()
		end
	end)

	t.it("becomes a sheet for a touch or narrow menu picker and anchors to its trigger for a wide pointer", function()
		local seven = {}
		for index = 1, 7 do
			table.insert(seven, { value = "v" .. index, label = "Value " .. index })
		end
		for _, case in
			{
				{ "Touch", 1280, THREE, 1 },
				{ "Touch", 1280, seven, 1 },
				{ "KeyboardAndMouse", 360, THREE, 1 },
				{ "KeyboardAndMouse", 1280, THREE, 0 },
				{ "Gamepad", 1280, seven, 0 },
			}
		do
			local selected = Compose.cell(case[3][1].value)
			local world = setup(function(UI)
				return UI.Picker "Choice" { style = "menu", selected = selected, options = case[3] }
			end)
			world.input.PreferredInput = (world.engine.types.Enum.PreferredInput :: any)[case[1]]
			local trigger = find(world.root, "Trigger")
			place(world, trigger, 40, 40, 160, 44)
			trigger.Activated.fire()
			extent(world, case[2], 720)
			local panel = find(world.root, "MenuPanel")
			t.expect(panel.Size.X.Scale).toBe(case[4])
			if case[4] == 1 then
				t.expect(panel.Size.X.Offset).toBe(-24)
			else
				t.expect(panel.Position.X.Offset).toBe(40)
				t.expect(panel.Position.Y.Offset >= 84).toBe(true)
			end
			find(panel, case[3][2].value).Activated.fire()
			t.expect(selected:peek()).toBe(case[3][2].value)
			t.expect(find(world.root, "MenuPanel")).toBeNil()
			world.stop()
		end
	end)

	t.it("forwards authored native properties to a navigation link and fills its search rows", function()
		local selection, query, opened = Compose.cell("a"), Compose.cell(""), Compose.cell(false)
		local world = setup(function(UI, _, engine)
			return UI.Picker "Track" {
				style = "navigationLink",
				label = "Track",
				selected = selection,
				query = query,
				isPresented = opened,
				Size = engine.types.UDim2.new(1, 0, 0, 44),
				LayoutOrder = 4,
				options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			}
		end)
		local trigger = find(world.root, "Track")
		t.expect(trigger.ClassName).toBe("TextButton")
		t.expect(title(trigger)).toBe("Track")
		t.expect(trigger.Size.X.Scale).toBe(1)
		t.expect(trigger.LayoutOrder).toBe(4)
		world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		local sheet = find(world.root, "PickerSearch")
		t.expect(find(sheet, "Search") ~= nil).toBe(true)
		local choices = find(sheet, "Choices")
		t.expect(choices.Size.X.Scale).toBe(1)
		for _, id in { "a", "b" } do
			local row = find(choices, id)
			t.expect(row.Size.X.Scale).toBe(1)
			t.expect(row.Size.X.Offset).toBe(0)
		end
		query:set("Bet")
		t.expect(find(choices, "a")).toBeNil()
		find(choices, "b").Activated.fire()
		t.expect(selection:peek()).toBe("b")
		t.expect(opened:peek()).toBe(false)
		t.expect(find(world.root, "PickerSearch")).toBeNil()
		t.expect(world.gui.SelectedObject).toBe(trigger)
		world.stop()
	end)

	t.it("opens, picks and dismisses every picker style for each theme and input with focus restored", function()
		local packages: { any } = { false }
		for _, name in { "glossy_touch", "pixel_quest", "fantasy_ornate" } do
			local package, report = (require :: any)("../examples/themes/" .. name).build(themes)
			t.expect(report.ok).toBe(true)
			table.insert(packages, package)
		end
		local inputs = { { "Touch", 390 }, { "KeyboardAndMouse", 1280 }, { "Gamepad", 1920 } }
		local styles = { "automatic", "menu", "segmented", "inline", "radioGroup", "navigationLink" }
		for _, package in packages do
			for _, device in inputs do
				for _, style in styles do
					local selected, changes = Compose.cell("easy"), 0
					local world = setup(function(UI)
						return UI.Picker "Choice" {
							style = style,
							label = "Difficulty",
							selected = selected,
							options = THREE,
							onChange = function()
								changes += 1
							end,
						}
					end, if package then { theme = package } else nil)
					world.input.PreferredInput = (world.engine.types.Enum.PreferredInput :: any)[device[1]]
					local picker = find(world.root, "Choice")
					picker.AbsoluteSize = V2(world, device[2], 44)
					local trigger = find(picker, "Trigger") or (if style == "navigationLink" then picker else nil)
					if trigger then
						world.gui.SelectedObject = trigger
						trigger.Activated.fire()
						local surface = find(world.root, "MenuPanel") or find(world.root, "PickerSearch")
						t.expect(surface ~= nil).toBe(true)
						t.expect(within(world.gui.SelectedObject, surface)).toBe(true)
						action(world.root, "ModalBack").Pressed.fire()
						t.expect(find(world.root, "Modal")).toBeNil()
						t.expect(world.gui.SelectedObject).toBe(trigger)
						t.expect(selected:peek()).toBe("easy")
						trigger.Activated.fire()
						surface = find(world.root, "MenuPanel") or find(world.root, "PickerSearch")
						find(surface, "normal").Activated.fire()
						t.expect(find(world.root, "Modal")).toBeNil()
						t.expect(world.gui.SelectedObject).toBe(trigger)
					else
						find(picker, "normal").Activated.fire()
					end
					t.expect(selected:peek()).toBe("normal")
					t.expect(changes).toBe(1)
					world.stop()
				end
			end
		end
	end)

	t.it("keeps a focused menu row while its live description appears, changes and disappears", function()
		local options = Compose.cell({ { value = "a", label = "Alpine" }, { value = "b", label = "Beach" } })
		local world = setup(function(UI)
			return UI.Picker "Route" {
				style = "menu",
				selected = Compose.cell("a"),
				isPresented = Compose.cell(false),
				options = options,
			}
		end)
		local trigger = find(world.root, "Trigger")
		world.gui.SelectedObject = trigger
		trigger.Activated.fire()
		local panel = find(world.root, "MenuPanel")
		local row = find(panel, "a")
		t.expect(world.gui.SelectedObject).toBe(row)
		t.expect(find(row, "Description").Visible).toBe(false)
		for _, description in { "Added", "", "Returned" } do
			options:set({
				{ value = "a", label = "Alpine", description = description },
				{ value = "b", label = "Beach" },
			})
			t.expect(find(panel, "a")).toBe(row)
			t.expect(world.gui.SelectedObject).toBe(row)
			t.expect(find(row, "Description").Visible).toBe(description ~= "")
			if description ~= "" then
				t.expect(find(row, "Description").Text).toBe(description)
			end
		end
		options:set({ { value = "a", label = "Alpine" }, { value = "b", label = "Beach" } })
		t.expect(find(panel, "a")).toBe(row)
		t.expect(world.gui.SelectedObject).toBe(row)
		t.expect(find(row, "Description").Visible).toBe(false)
		world.stop()
	end)

	t.it("refuses to choose filtered or disabled menu rows and keeps multiple selection after disposal", function()
		local selected, query, changes = Compose.cell({ a = true }), Compose.cell(""), 0
		local options =
			Compose.cell({ { value = "a", label = "Alpine" }, { value = "b", label = "Beach", enabled = false } })
		local world = setup(function(UI)
			return UI.Picker "Route" {
				style = "menu",
				multiple = true,
				selected = selected,
				query = query,
				options = options,
				isPresented = Compose.cell(true),
				onChange = function()
					changes += 1
				end,
			}
		end)
		local panel = find(world.root, "MenuPanel")
		local disabled = find(panel, "b")
		t.expect(disabled.Interactable).toBe(false)
		disabled.Activated.fire()
		t.expect(selected:peek().b).toBeNil()
		t.expect(changes).toBe(0)
		options:set({ { value = "a", label = "Alpine" }, { value = "b", label = "Beach" } })
		local stale = find(panel, "b")
		query:set("alp")
		t.expect(find(panel, "b")).toBeNil()
		stale.Activated.fire()
		t.expect(selected:peek().b).toBeNil()
		t.expect(changes).toBe(0)
		query:set("")
		local row = find(panel, "b")
		row.Activated.fire()
		t.expect(selected:peek().a).toBe(true)
		t.expect(selected:peek().b).toBe(true)
		t.expect(changes).toBe(1)
		world.stop()
		row.Activated.fire()
		t.expect(selected:peek().a).toBe(true)
		t.expect(selected:peek().b).toBe(true)
		t.expect(changes).toBe(1)
	end)

	t.it("keeps checked and radio menu items open by default with their marks while actions dismiss", function()
		local presented, checked, selected, calls = Compose.cell(true), Compose.cell(false), Compose.cell("a"), 0
		local world = setup(function(UI)
			return UI.Menu "Filters" {
				isPresented = presented,
				items = {
					{ id = "check", label = "Favorites", checked = checked },
					{ id = "a", label = "All", selected = selected, value = "a" },
					{ id = "b", label = "Friends", selected = selected, value = "b" },
					{
						id = "done",
						label = "Done",
						onSelect = function()
							calls += 1
						end,
					},
				},
			}
		end)
		local function mark(id: string): boolean
			return find(find(world.root, id), "TrailingIcon").Visible
		end
		t.expect(mark("check")).toBe(false)
		t.expect(mark("a")).toBe(true)
		t.expect(mark("b")).toBe(false)
		t.expect(find(find(world.root, "done"), "TrailingIcon")).toBeNil()
		find(world.root, "check").Activated.fire()
		t.expect(checked:peek()).toBe(true)
		t.expect(presented:peek()).toBe(true)
		t.expect(mark("check")).toBe(true)
		find(world.root, "b").Activated.fire()
		t.expect(selected:peek()).toBe("b")
		t.expect(presented:peek()).toBe(true)
		t.expect(mark("a")).toBe(false)
		t.expect(mark("b")).toBe(true)
		find(world.root, "check").Activated.fire()
		t.expect(checked:peek()).toBe(false)
		t.expect(mark("check")).toBe(false)
		find(world.root, "done").Activated.fire()
		t.expect(calls).toBe(1)
		t.expect(presented:peek()).toBe(false)
		t.expect(find(world.root, "MenuPanel")).toBeNil()
		world.stop()
	end)
end)
