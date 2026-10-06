--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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

	verifyHarness:suite("native parity classb input", function()
		verifyHarness:case("leaves every disabled haptic control not interactable and plays no detent for it", {
			id = "native_parity_classb_input::native parity classb input::leaves every disabled haptic control not interactable and plays no detent for it",
			run = function()
				local enabled = Compose.cell(false)
				local toggled, stepped, rated, sliding =
					Compose.cell(false), Compose.cell(1), Compose.cell(2), Compose.cell(5)
				local effect
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Button("Boost")({ label = "Boost", haptic = true, enabled = enabled }) :: unknown,
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
				Verify.expect(#felt >= 3):toBe(true)
				for _, node in felt do
					Verify.expect(`{node.Name} interactable {node.Interactable}`):toBe(`{node.Name} interactable false`)
				end
				world.gui.SelectedObject = find(world.screen, "Volume")
				Verify.expect(world.gui.SelectedObject):toBeNil()
				Verify.expect((winner(world.screen, "Period"))):toBeNil()
				enabled:set(true)
				world.gui.SelectedObject = find(world.screen, "Volume")
				for _, node in carriers() do
					Verify.expect(`{node.Name} interactable {node.Interactable}`):toBe(`{node.Name} interactable true`)
				end
				press(world.screen, "Period")
				Verify.expect((sliding:peek())):toBe(6)
				Verify.expect(effect.PlayCount):toBe(1)
				enabled:set(false)
				for _, node in carriers() do
					Verify.expect(`{node.Name} interactable {node.Interactable}`):toBe(`{node.Name} interactable false`)
				end
				Verify.expect((winner(world.screen, "Period"))):toBeNil()
				sliding:set(3)
				Verify.expect(effect.PlayCount):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("ignores the held arrow that landed selection and steps on the next press of it", {
			id = "native_parity_classb_input::native parity classb input::ignores the held arrow that landed selection and steps on the next press of it",
			run = function()
				for _, key in { "DPadRight", "Right" } do
					local value = Compose.cell(5)
					local world = setup(function(UI)
						return UI.Slider("Volume")({ value = value, min = 0, max = 10, step = 1 })
					end)
					world.held[key] = true
					world.gui.SelectedObject = find(world.screen, "Volume")
					local arrow = winner(world.screen, key)
					Verify.expect(arrow.Name):toBe("IncreaseArrow")
					arrow.Pressed.fire()
					Verify.expect(`{key} landed {value:peek()}`):toBe(`{key} landed 5`)
					world.held[key] = nil
					arrow.Released.fire()
					arrow.Pressed.fire()
					arrow.Released.fire()
					Verify.expect(`{key} next {value:peek()}`):toBe(`{key} next 6`)
					world.stop()
				end
			end,
		})

		verifyHarness:case("holds an analog stick direction until it recenters and arms again after that", {
			id = "native_parity_classb_input::native parity classb input::holds an analog stick direction until it recenters and arms again after that",
			run = function()
				local color
				local commits = 0
				local world = setup(function(UI, Host, engine)
					color = Compose.cell(engine.types.Color3.fromHSV(0.5, 0.5, 0.5))
					return Host.Frame({
						UI.ColorPicker("Paint")({
							value = color,
							style = "inline" :: "inline",
							modes = { "spectrum" },
							onCommit = function()
								commits += 1
							end,
						}) :: unknown,
						UI.Button("Other")({ label = "Other" }),
					})
				end)
				local Enum = world.engine.types.Enum
				local V2 = world.engine.types.Vector2.new
				world.input.PreferredInput = Enum.PreferredInput.Gamepad
				world.gui.SelectedObject = find(world.screen, "Surface")
				local steer = winner(world.screen, "Thumbstick2")
				Verify.expect(steer.Name):toBe("ColorPlaneSteer")
				Verify.expect(steer.Parent.Sink):toBe(true)
				local listeners = world.engine.heartbeat.count()
				steer.StateChanged.fire(V2(1, 0))
				world.engine.heartbeat.fire(0.2)
				local moved = color:peek()
				Verify.expect(moved ~= world.engine.types.Color3.fromHSV(0.5, 0.5, 0.5)):toBe(true)
				Verify.expect((world.engine.heartbeat.count())):toBe(listeners + 1)
				steer.StateChanged.fire(V2(0.05, 0))
				Verify.expect(commits):toBe(1)
				Verify.expect((world.engine.heartbeat.count())):toBe(listeners)
				world.engine.heartbeat.fire(0.5)
				Verify.expect((color:peek())):toBe(moved)
				steer.StateChanged.fire(V2(0, -1))
				world.engine.heartbeat.fire(0.2)
				Verify.expect(color:peek() ~= moved):toBe(true)
				steer.StateChanged.fire(V2(0, 0))
				Verify.expect(commits):toBe(2)
				world.stop()
			end,
		})
		verifyHarness:case(
			"presents an automatic menu as a sheet only while touch or a gamepad is the preferred input",
			{
				id = "native_parity_classb_input::native parity classb input::presents an automatic menu as a sheet only while touch or a gamepad is the preferred input",
				run = function()
					local opened = Compose.cell(false)
					local world = setup(function(UI, Host)
						return Host.Frame({
							Name = "Screen",
							UI.Menu("Actions")({
								isPresented = opened,
								items = {
									{ id = "Run", label = "Run", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
									{ id = "Walk", label = "Walk", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
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
					Verify.expect((form())):toBe("menu")
					for _, step in
						{
							{ "Touch", "sheet" },
							{ "KeyboardAndMouse", "menu" },
							{ "Gamepad", "sheet" },
							{ "Touch", "sheet" },
							{ "Gamepad", "sheet" },
						}
					do
						world.input.PreferredInput = Enum.PreferredInput[step[1]]
						Verify.expect(`{step[1]} {form()}`):toBe(`{step[1]} {step[2]}`)
						Verify.expect((opened:peek())):toBe(true)
						Verify.expect((find(world.screen, "MenuPanel"))):toBe(panel)
					end
					modal.AbsoluteSize = world.engine.types.Vector2.new(390, 720)
					world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
					Verify.expect((form())):toBe("sheet")
					world.stop()
				end,
			}
		)

		verifyHarness:case("lets a saturated value control consume the shoulders without paging its tab view", {
			id = "native_parity_classb_input::native parity classb input::lets a saturated value control consume the shoulders without paging its tab view",
			run = function()
				for _, kind in { "Slider", "Stepper", "Rating" } :: { "Rating" | "Slider" | "Stepper" } do
					local selected = Compose.cell("a")
					local value = Compose.cell(5)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local spec: { [string]: any } = { value = value }
						if kind ~= "Rating" then
							spec.min = 0
							spec.max = 5
							spec.step = 1
						end
						return UI.TabView("Tabs")({
							selection = selected,
							shoulderNavigation = "content" :: "content",
							tabs = {
								{ id = "a", label = "A", content = UI[kind]("Value")(spec) } :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = UI.Button("Next")({ label = "Next" }) } :: FixtureNavigationTypes.Tab,
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
					Verify.expect(world.gui.SelectedObject ~= nil):toBe(true)
					for _, key in { "ButtonR1", "ButtonL1" } do
						local action, context = winner(world.screen, key)
						Verify.expect(`{kind} {key} {action.Name}`)
							:toBe(`{kind} {key} {if key == "ButtonR1" then "Increase" else "Decrease"}`)
						Verify.expect(context.Sink):toBe(true)
						local pages = 0
						for _, other in contextsFor(world.screen, key) do
							if other ~= context then
								Verify.expect(other.Priority < context.Priority):toBe(true)
								pages += 1
							end
						end
						Verify.expect(`{kind} {key} tab pagers {pages}`):toBe(`{kind} {key} tab pagers 1`)
					end
					press(world.screen, "ButtonR1")
					Verify.expect(`{kind} {value:peek()} {selected:peek()}`):toBe(`{kind} 5 a`)
					press(world.screen, "ButtonL1")
					Verify.expect(`{kind} {value:peek()} {selected:peek()}`):toBe(`{kind} 4 a`)
					world.stop()
				end
			end,
		})
		verifyHarness:case(
			"latches a radial stick aim past its deadzone, holds it in the band and rearms after recenter",
			{
				id = "native_parity_classb_input::native parity classb input::latches a radial stick aim past its deadzone, holds it in the band and rearms after recenter",
				run = function()
					local opened = Compose.cell(false)
					local items = {}
					for _, def in { { "wave", "N" }, { "point", "E" }, { "call", "S" }, { "hide", "W" } } do
						table.insert(items, {
							id = def[1],
							label = def[1],
							slot = def[2] :: "N" | "E" | "S" | "W",
							onSelect = function() end,
						})
					end
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.RadialMenu("Ring")({
								isPresented = opened,
								distribution = "compass" :: "compass",
								items = items,
							}) :: unknown,
							UI.Button("Outside")({ label = "Outside" }),
						})
					end, { motionLevel = "none" })
					local Enum = world.engine.types.Enum
					local V2 = world.engine.types.Vector2.new
					world.input.PreferredInput = Enum.PreferredInput.Gamepad
					Verify.expect(#contextsFor(world.screen, "Thumbstick1")):toBe(0)
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
					Verify.expect((winner(world.screen, "Thumbstick1"))):toBe(move)
					opened:set(true)
					for _ = 1, 5 do
						world.engine.heartbeat.fire(1 / 60)
					end
					local axis, context = winner(world.screen, "Thumbstick1")
					Verify.expect(axis.Name):toBe("RadialAim")
					Verify.expect(context.Sink):toBe(true)
					Verify.expect(context.Priority > game.Priority):toBe(true)
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
					Verify.expect((aim(0.3, 0))):toBe(if start then start.Name else "nil")
					Verify.expect((aim(0, 0.34))):toBe(if start then start.Name else "nil")
					Verify.expect((aim(0.6, 0))):toBe("point")
					Verify.expect((aim(0.9, 0.1))):toBe("point")
					Verify.expect((aim(0.3, 0))):toBe("point")
					Verify.expect((aim(0.27, 0.05))):toBe("point")
					Verify.expect((aim(0.1, 0))):toBe("point")
					Verify.expect((aim(0, 0.3))):toBe("point")
					Verify.expect((aim(-0.7, 0))):toBe("hide")
					Verify.expect((aim(0, -0.8))):toBe("call")
					opened:set(false)
					for _ = 1, 30 do
						world.engine.heartbeat.fire(1 / 60)
					end
					Verify.expect((winner(world.screen, "Thumbstick1"))):toBe(move)
					world.stop()
				end,
			}
		)
	end)
end
