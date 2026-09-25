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
	held: { [string]: boolean },
	stop: () -> (),
}

local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	local held: { [string]: boolean } = {}
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function(_, key)
		return held[key.Name] == true
	end
	input.IsGamepadButtonDown = function(_, _, key)
		return held[key.Name] == true
	end
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		userInputService = input,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		if key == "prepare" then
			value(engine, input)
		elseif key == "config" then
			value(config, engine)
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
		held = held,
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

local function within(node: any, ancestor: any): boolean
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end

local function enabledChain(node: any): boolean
	local cursor = node
	while cursor do
		if cursor.ClassName == "InputContext" and cursor.Enabled == false then
			return false
		end
		cursor = cursor.Parent
	end
	return true
end

local function bindsKey(inputAction: any, key: string): boolean
	for _, binding in inputAction:GetChildren() do
		if binding:IsA("InputBinding") and binding.KeyCode.Name == key then
			return true
		end
	end
	return false
end

local function winner(root: any, key: string): (any, any)
	local best, bestContext
	for _, node in root:GetDescendants() do
		if node.ClassName == "InputContext" and enabledChain(node) then
			for _, child in node:GetChildren() do
				if child.ClassName == "InputAction" and child.Enabled ~= false and bindsKey(child, key) then
					if bestContext == nil or node.Priority > bestContext.Priority then
						best, bestContext = child, node
					end
				end
			end
		end
	end
	return best, bestContext
end

local function contextsFor(root: any, key: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node.ClassName == "InputContext" and enabledChain(node) then
			for _, child in node:GetChildren() do
				if child.ClassName == "InputAction" and bindsKey(child, key) then
					table.insert(found, node)
				end
			end
		end
	end
	return found
end

local function press(root: any, key: string): any
	local action = winner(root, key)
	assert(action, `no enabled action binds {key}`)
	action.Pressed.fire()
	action.Released.fire()
	return action
end

t.describe("native parity classb input", function()
	t.it("leaves every disabled haptic control not interactable and plays no detent for it", function()
		local enabled = Compose.cell(false)
		local toggled, stepped, rated, sliding = Compose.cell(false), Compose.cell(1), Compose.cell(2), Compose.cell(5)
		local effect
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Boost")({ label = "Boost", haptic = true, enabled = enabled }),
				UI.Toggle("Music")({ label = "Music", value = toggled, enabled = enabled }),
				UI.Stepper("Qty")({ value = stepped, min = 0, max = 5, step = 1, enabled = enabled }),
				UI.Rating("Stars")({ value = rated, enabled = enabled }),
				UI.Slider("Volume")({ value = sliding, min = 0, max = 10, step = 1, enabled = enabled }),
			})
		end, {
			config = function(config, engine)
				effect = engine.new("HapticEffect")
				config.pressHaptic = effect
			end,
		})
		local function carriers(): { any }
			local found = {}
			for _, node in world.screen:GetDescendants() do
				if node:IsA("GuiButton") and node.PressHapticEffect == effect then
					table.insert(found, node)
				end
			end
			return found
		end
		local felt = carriers()
		t.expect(#felt >= 3).toBe(true)
		for _, node in felt do
			t.expect(`{node.Name} interactable {node.Interactable}`).toBe(`{node.Name} interactable false`)
		end
		local track = find(find(world.screen, "Volume"), "Track")
		world.gui.SelectedObject = track
		t.expect(world.gui.SelectedObject).toBeNil()
		t.expect(winner(world.screen, "Period")).toBeNil()
		enabled:set(true)
		world.gui.SelectedObject = track
		for _, node in carriers() do
			t.expect(`{node.Name} interactable {node.Interactable}`).toBe(`{node.Name} interactable true`)
		end
		press(world.screen, "Period")
		t.expect(sliding:peek()).toBe(6)
		t.expect(effect.PlayCount).toBe(1)
		enabled:set(false)
		for _, node in carriers() do
			t.expect(`{node.Name} interactable {node.Interactable}`).toBe(`{node.Name} interactable false`)
		end
		t.expect(winner(world.screen, "Period")).toBeNil()
		sliding:set(3)
		t.expect(effect.PlayCount).toBe(1)
		world.stop()
	end)

	t.it("ignores the held arrow that landed selection and steps on the next press of it", function()
		for _, key in { "DPadRight", "Right" } do
			local value = Compose.cell(5)
			local world = setup(function(UI)
				return UI.Slider("Volume")({ value = value, min = 0, max = 10, step = 1 })
			end)
			local track = find(world.screen, "Track")
			world.held[key] = true
			world.gui.SelectedObject = track
			local arrow = winner(world.screen, key)
			t.expect(arrow.Name).toBe("IncreaseArrow")
			arrow.Pressed.fire()
			t.expect(`{key} landed {value:peek()}`).toBe(`{key} landed 5`)
			world.held[key] = nil
			arrow.Released.fire()
			arrow.Pressed.fire()
			arrow.Released.fire()
			t.expect(`{key} next {value:peek()}`).toBe(`{key} next 6`)
			world.stop()
		end
	end)

	t.it("holds an analog stick direction until it recenters and arms again after that", function()
		local color
		local commits = 0
		local world = setup(function(UI, Host, engine)
			color = Compose.cell(engine.types.Color3.fromHSV(0.5, 0.5, 0.5))
			return Host.Frame({
				UI.ColorPicker("Paint")({
					value = color,
					style = "inline",
					modes = { "spectrum" },
					onCommit = function()
						commits += 1
					end,
				}),
				UI.Button("Other")({ label = "Other" }),
			})
		end)
		local Enum = world.engine.types.Enum
		local V2 = world.engine.types.Vector2.new
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		world.gui.SelectedObject = find(world.screen, "Surface")
		local steer = winner(world.screen, "Thumbstick2")
		t.expect(steer.Name).toBe("ColorPlaneSteer")
		t.expect(steer.Parent.Sink).toBe(true)
		local listeners = world.engine.heartbeat.count()
		steer.StateChanged.fire(V2(1, 0))
		world.engine.heartbeat.fire(0.2)
		local moved = color:peek()
		t.expect(moved ~= world.engine.types.Color3.fromHSV(0.5, 0.5, 0.5)).toBe(true)
		t.expect(world.engine.heartbeat.count()).toBe(listeners + 1)
		steer.StateChanged.fire(V2(0.05, 0))
		t.expect(commits).toBe(1)
		t.expect(world.engine.heartbeat.count()).toBe(listeners)
		world.engine.heartbeat.fire(0.5)
		t.expect(color:peek()).toBe(moved)
		steer.StateChanged.fire(V2(0, -1))
		world.engine.heartbeat.fire(0.2)
		t.expect(color:peek() ~= moved).toBe(true)
		steer.StateChanged.fire(V2(0, 0))
		t.expect(commits).toBe(2)
		world.stop()
	end)
	t.it("presents an automatic menu as a sheet only while touch is the preferred input", function()
		local opened = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				Name = "Screen",
				UI.Menu("Actions")({
					isPresented = opened,
					items = {
						{ id = "Run", label = "Run", onSelect = function() end },
						{ id = "Walk", label = "Walk", onSelect = function() end },
					},
				}),
			})
		end)
		local Enum = world.engine.types.Enum
		world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
		opened:set(true)
		local modal = find(world.screen, "Modal")
		modal.AbsoluteSize = world.engine.types.Vector2.new(1280, 720)
		local panel = find(world.screen, "MenuPanel")
		local function form(): string
			return if panel.Size.X.Scale == 1 then "sheet" else "menu"
		end
		t.expect(form()).toBe("menu")
		for _, step in
			{
				{ "Touch", "sheet" },
				{ "KeyboardAndMouse", "menu" },
				{ "Gamepad", "menu" },
				{ "Touch", "sheet" },
				{ "Gamepad", "menu" },
			}
		do
			world.input.PreferredInput = Enum.PreferredInput[step[1]]
			t.expect(`{step[1]} {form()}`).toBe(`{step[1]} {step[2]}`)
			t.expect(opened:peek()).toBe(true)
			t.expect(find(world.screen, "MenuPanel")).toBe(panel)
		end
		modal.AbsoluteSize = world.engine.types.Vector2.new(390, 720)
		world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
		t.expect(form()).toBe("sheet")
		world.stop()
	end)

	t.it("lets a saturated value control consume the shoulders without paging its tab view", function()
		for _, kind in { "Slider", "Stepper", "Rating" } do
			local selected = Compose.cell("a")
			local value = Compose.cell(5)
			local world = setup(function(UI, Host)
				local spec: { [string]: any } = { value = value }
				if kind ~= "Rating" then
					spec.min = 0
					spec.max = 5
					spec.step = 1
				end
				return UI.TabView("Tabs")({
					selection = selected,
					shoulderNavigation = "content",
					tabs = {
						{ id = "a", label = "A", content = UI[kind]("Value")(spec) },
						{ id = "b", label = "B", content = UI.Button("Next")({ label = "Next" }) },
					},
				})
			end)
			local Enum = world.engine.types.Enum
			world.input.PreferredInput = Enum.PreferredInput.Gamepad
			local control = find(world.screen, "Value")
			local target
			for _, node in control:GetDescendants() do
				if node:IsA("GuiObject") and node.Selectable and node.Interactable ~= false then
					target = target or node
				end
			end
			if control:IsA("GuiObject") and control.Selectable then
				target = control
			end
			world.gui.SelectedObject = target
			t.expect(world.gui.SelectedObject ~= nil).toBe(true)
			for _, key in { "ButtonR1", "ButtonL1" } do
				local action, context = winner(world.screen, key)
				t.expect(`{kind} {key} {action.Name}`)
					.toBe(`{kind} {key} {if key == "ButtonR1" then "Increase" else "Decrease"}`)
				t.expect(context.Sink).toBe(true)
				local pages = 0
				for _, other in contextsFor(world.screen, key) do
					if other ~= context then
						t.expect(other.Priority < context.Priority).toBe(true)
						pages += 1
					end
				end
				t.expect(`{kind} {key} tab pagers {pages}`).toBe(`{kind} {key} tab pagers 1`)
			end
			press(world.screen, "ButtonR1")
			t.expect(`{kind} {value:peek()} {selected:peek()}`).toBe(`{kind} 5 a`)
			press(world.screen, "ButtonL1")
			t.expect(`{kind} {value:peek()} {selected:peek()}`).toBe(`{kind} 4 a`)
			world.stop()
		end
	end)
	t.it("latches a radial stick aim past its deadzone, holds it in the band and rearms after recenter", function()
		local opened = Compose.cell(false)
		local items = {}
		for _, def in { { "wave", "N" }, { "point", "E" }, { "call", "S" }, { "hide", "W" } } do
			table.insert(items, { id = def[1], label = def[1], slot = def[2], onSelect = function() end })
		end
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.RadialMenu("Ring")({ isPresented = opened, distribution = "compass", items = items }),
				UI.Button("Outside")({ label = "Outside" }),
			})
		end, { reducedMotion = true })
		local Enum = world.engine.types.Enum
		local V2 = world.engine.types.Vector2.new
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		t.expect(#contextsFor(world.screen, "Thumbstick1")).toBe(0)
		local game = world.engine.new("InputContext")
		game.Name = "Gameplay"
		game.Priority = 1000
		game.Sink = false
		game.Parent = world.screen
		local move = world.engine.new("InputAction")
		move.Name = "Move"
		move.Parent = game
		local binding = world.engine.new("InputBinding")
		binding.KeyCode = Enum.KeyCode.Thumbstick1
		binding.Parent = move
		t.expect(winner(world.screen, "Thumbstick1")).toBe(move)
		opened:set(true)
		for _ = 1, 5 do
			world.engine.heartbeat.fire(1 / 60)
		end
		local axis, context = winner(world.screen, "Thumbstick1")
		t.expect(axis.Name).toBe("RadialAim")
		t.expect(context.Sink).toBe(true)
		t.expect(context.Priority > game.Priority).toBe(true)
		local start = world.gui.SelectedObject
		local function name(): string
			local selected = world.gui.SelectedObject
			return if selected then selected.Name else "nil"
		end
		local function aim(x: number, y: number): string
			axis.StateChanged.fire(V2(x, y))
			world.engine.heartbeat.fire(1 / 60)
			return name()
		end
		t.expect(aim(0.3, 0)).toBe(if start then start.Name else "nil")
		t.expect(aim(0, 0.34)).toBe(if start then start.Name else "nil")
		t.expect(aim(0.6, 0)).toBe("point")
		t.expect(aim(0.9, 0.1)).toBe("point")
		t.expect(aim(0.3, 0)).toBe("point")
		t.expect(aim(0.27, 0.05)).toBe("point")
		t.expect(aim(0.1, 0)).toBe("point")
		t.expect(aim(0, 0.3)).toBe("point")
		t.expect(aim(-0.7, 0)).toBe("hide")
		t.expect(aim(0, -0.8)).toBe("call")
		opened:set(false)
		for _ = 1, 30 do
			world.engine.heartbeat.fire(1 / 60)
		end
		t.expect(winner(world.screen, "Thumbstick1")).toBe(move)
		world.stop()
	end)
end)
