--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local perfRunner = require("../bench/perf_runner")
local perfProfiles = require("../bench/perf_profiles")
local Compose = Facet.Compose
local themes = Facet.themes

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

local function setup(build: (any, any, any, any) -> any, prepare: ((any, any) -> ())?): World
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
	if prepare then
		prepare(engine, input)
	end
	local root = engine.new("ScreenGui")
	local UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			guiService = gui,
			userInputService = input,
			services = { GuiService = gui, UserInputService = input },
			inputParent = root,
			reducedMotion = true,
		} :: any
	)
	local Host = runtime.constructors
	local stop, node = runtime.mount(function()
		return build(UI, Host, engine, runtime)
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
	for _, child in root:GetDescendants() do
		if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
			return child:FindFirstChild(name)
		end
	end
	return nil
end

local function deliver(root: any, key: any): { string }
	local contexts = {}
	for _, child in root:GetDescendants() do
		if child:IsA("InputContext") and child.Enabled then
			table.insert(contexts, child)
		end
	end
	table.sort(contexts, function(a, b)
		return a.Priority > b.Priority
	end)
	local received = {}
	for _, context in contexts do
		local matched = false
		for _, inputAction in context:GetChildren() do
			if inputAction:IsA("InputAction") then
				for _, binding in inputAction:GetChildren() do
					if binding:IsA("InputBinding") and binding.KeyCode == key then
						matched = true
						table.insert(received, context.Name)
						inputAction.Pressed.fire()
						break
					end
				end
			end
		end
		if matched and context.Sink then
			break
		end
	end
	return received
end

local function probe(Host: any, engine: any, onPressed: () -> ()): any
	return Host.InputContext "Probe" {
		Priority = 3000,
		Sink = false,
		Enabled = true,
		Host.InputAction "ProbeNavigate" {
			Pressed = onPressed,
			Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.DPadDown }),
			Host.InputBinding({ KeyCode = engine.types.Enum.KeyCode.Down }),
		},
	}
end

local function focusedBox(world: World, field: any)
	world.input.GetFocusedTextBox = function()
		return if field:IsFocused() then field else nil
	end
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

t.describe("native parity weaker editing", function()
	t.it("apps-169 keeps the arrows with an editing field and commits it through Tab before advancing", function()
		local commits, value = {}, Compose.cell("hi")
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.TextInput "Name" {
					value = value,
					onCommit = function(text, reason)
						table.insert(commits, { text, reason })
					end,
				},
				UI.Button "Next" { label = "Next" },
			})
		end)
		local E = world.engine.types.Enum
		local field = find(world.node, "Name")
		focusedBox(world, field)
		world.gui.SelectedObject = field
		field:CaptureFocus()
		t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(true)
		for _, key in { E.KeyCode.Down, E.KeyCode.Up, E.KeyCode.Left, E.KeyCode.Right } do
			t.expect(deliver(world.root, key)[1]).toBe("FacetTextEditing")
			t.expect(world.gui.SelectedObject).toBe(field)
			t.expect(field:IsFocused()).toBe(true)
		end
		field.Text = "hi there"
		t.expect(#commits).toBe(0)
		local received = deliver(world.root, E.KeyCode.Tab)
		t.expect(received).toEqual({ "FacetTraversal" })
		t.expect(field:IsFocused()).toBe(false)
		t.expect(#commits).toBe(1)
		t.expect(commits[1][1]).toBe("hi there")
		t.expect(commits[1][2]).toBe("focusLost")
		t.expect(value:peek()).toBe("hi there")
		t.expect(world.gui.SelectedObject).toBe(find(world.node, "Next"))
		t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(false)
		deliver(world.root, E.KeyCode.Tab)
		t.expect(world.gui.SelectedObject).toBe(field)
		t.expect(#commits).toBe(1)
		world.stop()
	end)

	t.it("inputs-181 enters editing on native focus once and keeps the edit and its snapshot on a repeat", function()
		local value, changes, commits, cancels = Compose.cell("seed"), {}, {}, 0
		local probed = 0
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				probe(Host, engine, function()
					probed += 1
				end),
				UI.TextInput "Name" {
					value = value,
					onChange = function(text)
						value:set(text)
						table.insert(changes, text)
					end,
					onCommit = function(text, reason)
						table.insert(commits, { text, reason })
					end,
					onCancel = function()
						cancels += 1
					end,
				},
			})
		end)
		local E = world.engine.types.Enum
		local field = find(world.node, "Name")
		world.gui.SelectedObject = field
		t.expect(action(world.root, "TextEditing")).toBe(nil)
		field:CaptureFocus()
		t.expect(action(world.root, "TextEditing") ~= nil).toBe(true)
		field.Text = "seedX"
		t.expect(value:peek()).toBe("seedX")
		field.Focused.fire()
		t.expect(field:IsFocused()).toBe(true)
		t.expect(action(world.root, "TextEditing") ~= nil).toBe(true)
		t.expect(#commits).toBe(0)
		t.expect(changes).toEqual({ "seedX" })
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(0)
		action(world.root, "Cancel").Pressed.fire()
		t.expect(value:peek()).toBe("seed")
		t.expect(field.Text).toBe("seed")
		t.expect(cancels).toBe(1)
		t.expect(#commits).toBe(0)
		t.expect(field:IsFocused()).toBe(false)
		t.expect(world.gui.SelectedObject).toBe(field)
		deliver(world.root, E.KeyCode.DPadDown)
		t.expect(probed).toBe(1)
		field:CaptureFocus()
		t.expect(action(world.root, "TextEditing") ~= nil).toBe(true)
		field:ReleaseFocus(true)
		t.expect(#commits).toBe(1)
		t.expect(commits[1][1]).toBe("seed")
		t.expect(commits[1][2]).toBe("submit")
		t.expect(action(world.root, "TextEditing")).toBe(nil)
		world.stop()
	end)

	t.it(
		"inputs-137 carries an edit across device arrivals and commits it once when the editing surface leaves",
		function()
			local value, commits, probed = Compose.cell(""), {}, 0
			local world = setup(function(UI, Host, engine)
				return Host.Frame({
					probe(Host, engine, function()
						probed += 1
					end),
					UI.TextInput "Name" {
						value = value,
						onCommit = function(text, reason)
							table.insert(commits, { text, reason })
						end,
					},
				})
			end, function(_, input)
				input.TouchEnabled = true
				input.KeyboardEnabled = false
				input.GamepadEnabled = false
			end)
			local E = world.engine.types.Enum
			local field = find(world.node, "Name")
			field:CaptureFocus()
			field.Text = "hi"
			deliver(world.root, E.KeyCode.DPadDown)
			t.expect(probed).toBe(0)
			world.input.GamepadEnabled = true
			t.expect(field:IsFocused()).toBe(true)
			t.expect(value:peek()).toBe("hi")
			t.expect(#commits).toBe(0)
			world.input.KeyboardEnabled = true
			world.input.TouchEnabled = false
			t.expect(field:IsFocused()).toBe(true)
			t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(true)
			t.expect(#commits).toBe(0)
			world.input.TouchEnabled = true
			world.input.KeyboardEnabled = false
			t.expect(field:IsFocused()).toBe(true)
			world.input.TouchEnabled = false
			t.expect(field:IsFocused()).toBe(false)
			t.expect(#commits).toBe(1)
			t.expect(commits[1][1]).toBe("hi")
			t.expect(commits[1][2]).toBe("focusLost")
			t.expect(value:peek()).toBe("hi")
			t.expect(find(world.root, "FacetTextEditing").Enabled).toBe(false)
			deliver(world.root, E.KeyCode.DPadDown)
			t.expect(probed).toBe(1)
			world.stop()
		end
	)

	t.it("inputs-141 follows the engine preferred input and ignores raw pointer and stick noise", function()
		local env: any, published = nil, 0
		local world = setup(function(UI, Host, engine)
			env = UI.environment(engine.new("ScreenGui"))
			Compose.watch(function(use)
				use(env.effectiveInput)
				published += 1
			end)
			return Host.Frame({})
		end, function(engine, input)
			input.MouseEnabled = true
			input.KeyboardEnabled = true
			input.GamepadEnabled = true
			input.TouchEnabled = false
			input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
		end)
		local E = world.engine.types.Enum
		local classes = env.interactionClasses:peek()
		t.expect(classes.primary).toBe("gamepad")
		t.expect(classes.pointer).toBe(true)
		t.expect(classes.gamepad).toBe(true)
		t.expect(env.effectiveInput:peek()).toBe("Gamepad")
		local before = published
		for _ = 1, 20 do
			world.input.InputChanged.fire({
				UserInputType = E.UserInputType.Gamepad1,
				KeyCode = E.KeyCode.Thumbstick1,
				Position = world.engine.types.Vector3.new(0.1, 0, 0),
			})
			world.input.InputChanged.fire({
				UserInputType = E.UserInputType.MouseMovement,
				KeyCode = E.KeyCode.Unknown,
				Position = world.engine.types.Vector3.new(10, 10, 0),
			})
		end
		world.input.InputBegan.fire({ UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode.Unknown })
		t.expect(published).toBe(before)
		t.expect(env.effectiveInput:peek()).toBe("Gamepad")
		world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(published).toBe(before + 1)
		classes = env.interactionClasses:peek()
		t.expect(classes.primary).toBe("pointer")
		t.expect(classes.gamepad).toBe(true)
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		for _ = 1, 10 do
			world.input.InputChanged.fire({
				UserInputType = E.UserInputType.MouseMovement,
				KeyCode = E.KeyCode.Unknown,
				Position = world.engine.types.Vector3.new(20, 20, 0),
			})
		end
		t.expect(published).toBe(before + 1)
		world.input.PreferredInput = E.PreferredInput.Gamepad
		t.expect(env.interactionClasses:peek().primary).toBe("gamepad")
		t.expect(published).toBe(before + 2)
		world.input.TouchEnabled = true
		world.input.PreferredInput = E.PreferredInput.Touch
		t.expect(env.interactionClasses:peek().primary).toBe("touch")
		t.expect(env.effectiveInput:peek()).toBe("Touch")
		world.input.TouchEnabled = false
		world.input.MouseEnabled = false
		world.input.KeyboardEnabled = false
		world.input.PreferredInput = E.PreferredInput.Gamepad
		world.input.InputBegan.fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown })
		classes = env.interactionClasses:peek()
		t.expect(classes.primary).toBe("gamepad")
		t.expect(classes.pointer).toBe(false)
		world.stop()
		world = setup(function(UI, Host, engine)
			env = UI.environment(engine.new("ScreenGui"))
			return Host.Frame({})
		end, function(engine, input)
			input.MouseEnabled = true
			input.KeyboardEnabled = true
			input.GamepadEnabled = false
			input.TouchEnabled = false
			input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		end)
		classes = env.interactionClasses:peek()
		t.expect(classes.primary).toBe("pointer")
		t.expect(classes.gamepad).toBe(false)
		t.expect(env.effectiveInput:peek()).toBe("KeyboardAndMouse")
		world.stop()
	end)

	t.it("inputs-122 keeps the field frame outside a native viewport and keeps newlines until focus loss", function()
		local value, commits = Compose.cell("Notes"), {}
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.TextInput "Editor" {
					value = value,
					multiline = true,
					visibleLines = 4,
					onCommit = function(text, reason)
						table.insert(commits, { text, reason })
					end,
				},
			})
		end)
		local root = find(world.node, "Editor")
		t.expect(root.ClassName).toBe("Frame")
		local viewport = find(root, "Viewport")
		t.expect(viewport.ClassName).toBe("ScrollingFrame")
		local field = find(viewport, "Field")
		t.expect(field.ClassName).toBe("TextBox")
		t.expect(field.MultiLine).toBe(true)
		t.expect(field:IsDescendantOf(viewport)).toBe(true)
		local plate = find(root, "Input")
		t.expect(plate:HasTag("facet-field")).toBe(true)
		t.expect(plate:FindFirstChildWhichIsA("UIPadding") ~= nil).toBe(true)
		t.expect(viewport:IsDescendantOf(plate)).toBe(true)
		local viewportSize = viewport.Size
		field:CaptureFocus()
		field.Text = "first\nsecond"
		t.expect(value:peek()).toBe("first\nsecond")
		t.expect(field:IsFocused()).toBe(true)
		t.expect(#commits).toBe(0)
		local long = string.rep("A line of notes.\n", 14)
		field.Text = long
		local flow = find(viewport, "Flow")
		flow.AbsoluteSize = V2(world, 300, 14 * 21)
		t.expect(viewport.CanvasSize.Y.Offset).toBe(14 * 21)
		t.expect(viewport.Size).toBe(viewportSize)
		t.expect(find(world.node, "Editor")).toBe(root)
		t.expect(find(viewport, "Field")).toBe(field)
		field:ReleaseFocus(false)
		t.expect(#commits).toBe(1)
		t.expect(commits[1][1]).toBe(long)
		t.expect(commits[1][2]).toBe("focusLost")
		t.expect(value:peek()).toBe(long)
		world.stop()
		local grown = Compose.cell("Lap")
		world = setup(function(UI)
			return UI.TextInput "Plain" { value = grown, multiline = true }
		end)
		local plain = world.node
		t.expect(plain.ClassName).toBe("TextBox")
		local measure = plain:FindFirstChild("Measure")
		t.expect(measure.ClassName).toBe("TextLabel")
		t.expect(plain.Size.Y.Offset).toBe(96)
		plain:CaptureFocus()
		plain.Text = "Lap" .. string.rep("\nLap", 15) .. "\n"
		t.expect(measure.Text).toBe(plain.Text .. " ")
		measure.TextBounds = V2(world, 200, 17 * 16)
		t.expect(plain.Size.Y.Offset).toBe(17 * 16 + 16)
		t.expect(plain:IsFocused()).toBe(true)
		world.stop()
		local ornate = (require :: any)("../examples/themes/fantasy_ornate").build(themes)
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local stop, sheet = runtime.mount(function()
			return themes.createStyleSheet(runtime, ornate, { types = engine.types } :: any)
		end, engine.new("Folder"))
		local inset = ((ornate.chrome or {}).field or {}).contentInsets or {}
		local rule
		for _, node in sheet:GetChildren() do
			if node.Selector == ".facet-field::UIPadding" then
				rule = node
			end
		end
		t.expect(rule ~= nil).toBe(true)
		local padding = rule:GetProperties()
		t.expect(padding.PaddingLeft.Offset).toBe(math.max(0, inset.left or 0))
		t.expect(padding.PaddingRight.Offset).toBe(math.max(0, inset.right or 0))
		t.expect(padding.PaddingTop.Offset).toBe(math.max(0, inset.top or 0))
		t.expect(padding.PaddingBottom.Offset).toBe(math.max(0, inset.bottom or 0))
		t.expect((inset.left or 0) > 0).toBe(true)
		stop()
		runtime:dispose()
	end)

	t.it("collections-53 re-derives an open tray button width when the preferred text size changes", function()
		local open = Compose.cell("trailing" :: string?)
		local world = setup(function(UI)
			return UI.RowActions({
				open = open,
				content = UI.Button("Action")({ label = "Row" }),
				trailing = { { id = "Delete", label = "Delete", role = "destructive" } },
			})
		end)
		local row = world.node
		row.AbsoluteSize = V2(world, 400, 44)
		local tray = find(row, "trailing")
		local button = find(tray, "Delete")
		local content = find(row, "Content")
		t.expect(tray.Visible).toBe(true)
		button.TextBounds = V2(world, 44, 20)
		t.expect(tray.Size.X.Offset).toBe(88)
		t.expect(content.Position.X.Offset).toBe(-88)
		world.gui.PreferredTextSize = world.engine.types.Enum.PreferredTextSize.Largest
		button.TextBounds = V2(world, 96, 30)
		t.expect(open:peek()).toBe("trailing")
		t.expect(find(tray, "Delete")).toBe(button)
		t.expect(tray.Size.X.Offset).toBe(128)
		t.expect(content.Position.X.Offset).toBe(-128)
		world.gui.PreferredTextSize = world.engine.types.Enum.PreferredTextSize.Medium
		button.TextBounds = V2(world, 44, 20)
		t.expect(tray.Size.X.Offset).toBe(88)
		t.expect(content.Position.X.Offset).toBe(-88)
		open:set(nil)
		button.TextBounds = V2(world, 110, 30)
		open:set("trailing")
		t.expect(tray.Size.X.Offset).toBe(142)
		world.stop()
	end)

	t.it("apps-260 retires a presence region until its exit completes and reuses it on re-entry", function()
		local shown, done = Compose.cell(true), Compose.cell(false)
		local built, cleaned, phase = 0, 0, nil :: any
		local world = setup(function(UI, Host)
			return Host.Frame "Holder" {
				UI.Button "Toggle" {
					label = "Toggle",
					onActivate = function()
						shown:set(not shown:peek())
					end,
				},
				Host.Frame "Region" {
					Compose.presence(shown, function(current)
						built += 1
						phase = current
						Compose.cleanup(function()
							cleaned += 1
						end)
						return Host.Frame "Panel" {}
					end, {
						exit = function()
							done:set(false)
							return { completed = done }
						end,
					}),
				},
			}
		end)
		local toggle = find(world.node, "Toggle")
		local region = find(world.node, "Region")
		local first = find(region, "Panel")
		t.expect(first ~= nil).toBe(true)
		t.expect(built).toBe(1)
		toggle.Activated.fire()
		t.expect(find(region, "Panel")).toBe(first)
		t.expect(cleaned).toBe(0)
		t.expect(phase.exiting:peek()).toBe(true)
		toggle.Activated.fire()
		t.expect(find(region, "Panel")).toBe(first)
		t.expect(built).toBe(1)
		t.expect(phase.exiting:peek()).toBe(false)
		toggle.Activated.fire()
		done:set(true)
		t.expect(cleaned).toBe(1)
		t.expect(find(region, "Panel")).toBeNil()
		done:set(false)
		done:set(true)
		t.expect(cleaned).toBe(1)
		local baseline = #region:GetDescendants()
		for _ = 1, 20 do
			toggle.Activated.fire()
			toggle.Activated.fire()
			done:set(true)
		end
		t.expect(built).toBe(21)
		t.expect(cleaned).toBe(21)
		t.expect(#region:GetDescendants()).toBe(baseline)
		t.expect(find(region, "Panel")).toBeNil()
		world.stop()
	end)

	t.it("apps2-161 counts the registrations that the application owner of a scene holds", function()
		local function scene(watchers: number)
			return {
				name = `registrations-{watchers}`,
				requirement = "UI-PERF-001",
				dataset = `{watchers} watchers`,
				setup = function()
					local core = Compose.createRootOwner(function() end)
					local source = Compose.cell(0)
					for _ = 1, watchers do
						core.owner.watch(function(use)
							use(source)
						end)
					end
					return { core = core, source = source, n = 0 }
				end,
				run = function(state: any)
					state.n += 1
					state.source:set(state.n)
					return nil
				end,
				teardown = function(state: any)
					state.core.dispose()
				end,
			}
		end
		local profile = perfProfiles.get(perfProfiles.REFERENCE)
		local one = perfRunner.runScene(scene(1), profile, { warmup = 1, samples = 3 })
		local five = perfRunner.runScene(scene(5), profile, { warmup = 1, samples = 3 })
		t.expect(type(one.liveRegistry.registrations)).toBe("number")
		t.expect(one.liveRegistry.registrations >= 1).toBe(true)
		t.expect(five.liveRegistry.registrations - one.liveRegistry.registrations).toBe(4)
		t.expect(five.metrics.connections.reactiveRegistrations).toBe(five.liveRegistry.registrations)
		local blind = perfRunner.runScene({
			name = "no-owner",
			requirement = "UI-PERF-001",
			dataset = "none",
			setup = function()
				return {}
			end,
			run = function()
				return nil
			end,
		}, profile, { warmup = 1, samples = 2 })
		t.expect(blind.liveRegistry.registrations.measured).toBe(false)
	end)

	t.it("mech1-115 rethrows a failure outside every boundary to the writer and contains one inside", function()
		local outside, inside = Compose.cell(false), Compose.cell(false)
		local reported = {}
		local world = setup(function(UI, Host)
			return Host.Frame({
				Compose.show(outside, function()
					error("outside failure", 0)
				end),
				UI.ErrorBoundary "Guard" {
					view = function()
						return Host.Frame({
							Compose.show(inside, function()
								error("inside failure", 0)
							end),
						})
					end,
					fallback = function()
						return Host.TextLabel "Fallback" { Text = "broken" }
					end,
					onError = function(failure)
						table.insert(reported, tostring(failure))
					end,
				},
				Host.TextLabel "Sibling" { Text = "ok" },
			})
		end)
		local ok = pcall(function()
			inside:set(true)
		end)
		t.expect(ok).toBe(true)
		t.expect(#reported).toBe(1)
		t.expect(string.find(reported[1], "inside failure", 1, true) ~= nil).toBe(true)
		t.expect(find(world.node, "Fallback") ~= nil).toBe(true)
		t.expect(find(world.node, "Sibling") ~= nil).toBe(true)
		local failed, message = pcall(function()
			outside:set(true)
		end)
		t.expect(failed).toBe(false)
		t.expect(string.find(tostring(message), "outside failure", 1, true) ~= nil).toBe(true)
		t.expect(#reported).toBe(1)
		world.stop()
	end)
end)
