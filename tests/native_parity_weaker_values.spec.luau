--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	type World = {
		engine: any,
		runtime: any,
		UI: any,
		Host: any,
		gui: any,
		input: any,
		root: any,
		node: any,
		types: any,
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
		local root = engine.new("ScreenGui")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = root,
			motionLevel = "none",
		}
		for key, value in (options or {}) :: { [string]: any } do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, node: any = runtime.mount(function()
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
			types = engine.types,
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
		for _, child in root:GetChildren() do
			if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
				return child:FindFirstChild(name)
			end
		end
		return nil
	end

	local function keys(bound: any): { [string]: boolean }
		local found = {}
		for _, binding in bound:GetChildren() do
			if binding:IsA("InputBinding") then
				found[binding.KeyCode.Name] = true
			end
		end
		return found
	end

	local function mountError(build: (any, any) -> any): string?
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local UI =
			Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local ok, message = pcall(function()
			local stop = runtime.mount(function()
				return Host.Frame({ build(UI, Host) })
			end, engine.new("ScreenGui"))
			stop()
		end)
		runtime:dispose()
		return if ok then nil else tostring(message)
	end

	local function refuses(message: string, build: (any, any) -> any): boolean
		local failure = mountError(build)
		return failure ~= nil and string.find(failure, message, 1, true) ~= nil
	end

	local function selectableCount(node: any): number
		local count = if node:IsA("GuiObject") and node.Selectable then 1 else 0
		for _, child in node:GetDescendants() do
			if child:IsA("GuiObject") and child.Selectable then
				count += 1
			end
		end
		return count
	end

	local INPUTS = { "pointer", "touch", "keyboard", "gamepad" }

	local function press(world: World, node: any, input: string)
		local E = world.types.Enum
		if input == "pointer" then
			node.Activated.fire({ UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode:FromValue(0) }, 1)
		elseif input == "touch" then
			node.Activated.fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode:FromValue(0) }, 1)
		elseif input == "keyboard" then
			world.gui.SelectedObject = node
			local activate = assert(action(world.root, "Activate"), "Activate action is bound on the selected control")
			Verify.expect(keys(activate).Return):toBe(true)
			Verify.expect(keys(activate).Space):toBe(true)
			activate.Pressed.fire()
		else
			world.gui.SelectedObject = node
			node.Activated.fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }, 1)
		end
	end

	verifyHarness:suite("native parity weaker values", function()
		verifyHarness:case("level picker read-only is not selectable and refuses pointer scrub and adjust input", {
			id = "native_parity_weaker_values::native parity weaker values::level picker read-only is not selectable and refuses pointer scrub and adjust input",
			run = function()
				for _, name in { "LevelPicker", "Rating" } do
					local value = Compose.cell(2)
					local world = setup(function(UI, Host)
						return Host.Frame({ UI[name]("Level")({ value = value, count = 10, readOnly = true }) })
					end)
					local node = find(world.node, "Level")
					Verify.expect(node.Selectable):toBe(false)
					Verify.expect(node.Interactable):toBe(false)
					Verify.expect((selectableCount(node))):toBe(0)
					Verify.expect(find(node, "Level1") ~= nil):toBe(true)
					node.AbsoluteSize = world.types.Vector2.new(200, 44)
					node.Activated.fire({ Position = world.types.Vector2.new(190, 0) })
					Verify.expect((value:peek())):toBe(2)
					Verify.expect(find(node, "Scrub").Enabled):toBe(false)
					find(node, "Scrub").DragStart.fire(world.types.Vector2.new(190, 0))
					Verify.expect((value:peek())):toBe(2)
					world.gui.SelectedObject = node
					Verify.expect((action(world.root, "Increase"))):toBeNil()
					Verify.expect((action(world.root, "IncreaseArrow"))):toBeNil()
					world.stop()
				end
			end,
		})

		verifyHarness:case("level picker pointer tap and touch scrub reach the level arithmetic", {
			id = "native_parity_weaker_values::native parity weaker values::level picker pointer tap and touch scrub reach the level arithmetic",
			run = function()
				local value = Compose.cell(2)
				local world = setup(function(UI, Host)
					return Host.Frame({ UI.LevelPicker("Quality")({ value = value, count = 10 }) })
				end)
				local node = find(world.node, "Quality")
				local V2 = world.types.Vector2
				node.AbsolutePosition = V2.new(100, 0)
				node.AbsoluteSize = V2.new(200, 44)
				node.Activated.fire({ Position = V2.new(100 + 200 * 0.95, 10) })
				Verify.expect((value:peek())):toBe(10)
				node.Activated.fire({ Position = V2.new(100 + 200 * 0.35, 10) })
				Verify.expect((value:peek())):toBe(4)
				local scrub = find(node, "Scrub")
				Verify.expect(scrub.ClassName):toBe("UIDragDetector")
				scrub.DragStart.fire(V2.new(100 + 200 * 0.05, 10))
				Verify.expect((value:peek())):toBe(1)
				scrub.DragContinue.fire(V2.new(100 + 200 * 0.65, 10))
				Verify.expect((value:peek())):toBe(7)
				scrub.DragEnd.fire()
				node.Activated.fire({ Position = V2.new(100 + 200 * 0.65, 10) })
				Verify.expect((value:peek())):toBe(7)
				Verify.expect(node.Size.Y.Offset >= 44):toBe(true)
				local drags = 0
				for _, child in node:GetDescendants() do
					if child:IsA("UIDragDetector") then
						drags += 1
					end
				end
				Verify.expect(drags):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case(
			"level picker keyboard and gamepad adjust only while selected and hold the axis at the limit",
			{
				id = "native_parity_weaker_values::native parity weaker values::level picker keyboard and gamepad adjust only while selected and hold the axis at the limit",
				run = function()
					local value = Compose.cell(2)
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Button("Elsewhere")({ label = "Elsewhere", onActivate = function() end }) :: unknown,
							UI.LevelPicker("Quality")({ value = value, count = 10 }),
						})
					end)
					local node = find(world.node, "Quality")
					world.gui.SelectedObject = find(world.node, "Elsewhere")
					Verify.expect((action(world.root, "Increase"))):toBeNil()
					Verify.expect((action(world.root, "Decrease"))):toBeNil()
					world.gui.SelectedObject = node
					local increase, decrease = action(world.root, "Increase"), action(world.root, "Decrease")
					Verify.expect(keys(increase).Period):toBe(true)
					Verify.expect(keys(increase).ButtonR1):toBe(true)
					Verify.expect(keys(decrease).Comma):toBe(true)
					Verify.expect(keys(decrease).ButtonL1):toBe(true)
					increase.Pressed.fire()
					increase.Released.fire()
					Verify.expect((value:peek())):toBe(3)
					decrease.Pressed.fire()
					decrease.Released.fire()
					Verify.expect((value:peek())):toBe(2)
					value:set(9)
					local right = action(world.root, "IncreaseArrow")
					Verify.expect(keys(right).Right):toBe(true)
					Verify.expect(keys(right).DPadRight):toBe(true)
					right.Pressed.fire()
					right.Released.fire()
					Verify.expect((value:peek())):toBe(10)
					local held = action(world.root, "IncreaseArrow")
					Verify.expect(held ~= nil):toBe(true)
					held.Pressed.fire()
					held.Released.fire()
					Verify.expect((value:peek())):toBe(10)
					Verify.expect(action(world.root, "Increase") ~= nil):toBe(true)
					Verify.expect(action(world.root, "DecreaseArrow") ~= nil):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("level picker cancels a pointer scrub back to its snapshot when the gamepad takes over", {
			id = "native_parity_weaker_values::native parity weaker values::level picker cancels a pointer scrub back to its snapshot when the gamepad takes over",
			run = function()
				local value = Compose.cell(2)
				local world = setup(function(UI, Host)
					return Host.Frame({ UI.LevelPicker("Quality")({ value = value, count = 10 }) })
				end)
				local node = find(world.node, "Quality")
				local V2 = world.types.Vector2
				node.AbsoluteSize = V2.new(200, 44)
				find(node, "Scrub").DragStart.fire(V2.new(190, 0))
				Verify.expect((value:peek())):toBe(10)
				world.input.PreferredInput = world.types.Enum.PreferredInput.Gamepad
				Verify.expect((value:peek())):toBe(2)
				find(node, "Scrub").DragContinue.fire(V2.new(150, 0))
				Verify.expect((value:peek())):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("level picker disabled refuses pointer scrub and adjust input", {
			id = "native_parity_weaker_values::native parity weaker values::level picker disabled refuses pointer scrub and adjust input",
			run = function()
				local value, enabled = Compose.cell(2), Compose.cell(false)
				local world = setup(function(UI, Host)
					return Host.Frame({ UI.LevelPicker("Quality")({ value = value, count = 10, enabled = enabled }) })
				end)
				local node = find(world.node, "Quality")
				node.AbsoluteSize = world.types.Vector2.new(200, 44)
				Verify.expect(node.Selectable):toBe(false)
				node.Activated.fire({ Position = world.types.Vector2.new(190, 0) })
				find(node, "Scrub").DragStart.fire(world.types.Vector2.new(190, 0))
				world.gui.SelectedObject = node
				Verify.expect((action(world.root, "Increase"))):toBeNil()
				Verify.expect((value:peek())):toBe(2)
				enabled:set(true)
				world.gui.SelectedObject = node
				action(world.root, "Increase").Pressed.fire()
				Verify.expect((value:peek())):toBe(3)
				world.stop()
			end,
		})

		verifyHarness:case("rating is five glyph stars with the default star pair and no tint", {
			id = "native_parity_weaker_values::native parity weaker values::rating is five glyph stars with the default star pair and no tint",
			run = function()
				local value = Compose.cell(3)
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Rating("Stars")({ value = value }) :: unknown,
						UI.LevelPicker("Plain")({ value = Compose.cell(1), segment = "glyph" }),
					})
				end)
				local stars = find(world.node, "Stars")
				local painted = ""
				for index = 1, 5 do
					local star = find(stars, "Level" .. index)
					Verify.expect(star.ClassName):toBe("TextLabel")
					Verify.expect(star.Selectable):toBe(false)
					painted ..= star.Text
				end
				Verify.expect(painted):toBe("★★★☆☆")
				Verify.expect((find(stars, "Level6"))):toBeNil()
				Verify.expect((stars:GetAttribute("maximum"))):toBe(5)
				Verify.expect(find(stars, "Level1").TextSize):toBe(20)
				Verify.expect(find(find(world.node, "Plain"), "Level1").Text):toBe("★")
				Verify.expect(find(find(world.node, "Plain"), "Level2").Text):toBe("☆")
				local sibling = setup(function(UI, Host)
					return Host.Frame({ UI.Rating("Stars")({ value = Compose.cell(3) }) })
				end)
				Verify.expect(find(find(sibling.node, "Stars"), "Level1").TextColor3)
					:toBe(find(find(sibling.node, "Stars"), "Level5").TextColor3)
				sibling.stop()
				Verify.expect((refuses("images require image segments", function(UI)
					return UI.Rating({ value = Compose.cell(1), images = { filled = "a", empty = "b" } })
				end))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("rating is one focus stop that pointer touch keyboard and gamepad all adjust", {
			id = "native_parity_weaker_values::native parity weaker values::rating is one focus stop that pointer touch keyboard and gamepad all adjust",
			run = function()
				local value = Compose.cell(2)
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Button("Elsewhere")({ label = "Elsewhere", onActivate = function() end }) :: unknown,
						UI.Rating("Stars")({ value = value }),
					})
				end)
				local node = find(world.node, "Stars")
				local V2 = world.types.Vector2
				Verify.expect((selectableCount(node))):toBe(1)
				Verify.expect(node.Selectable):toBe(true)
				node.AbsoluteSize = V2.new(100, 44)
				node.Activated.fire({ Position = V2.new(70, 10) })
				Verify.expect((value:peek())):toBe(4)
				local scrub = find(node, "Scrub")
				scrub.DragStart.fire(V2.new(95, 10))
				Verify.expect((value:peek())):toBe(5)
				scrub.DragContinue.fire(V2.new(25, 10))
				Verify.expect((value:peek())):toBe(2)
				scrub.DragEnd.fire()
				Verify.expect((value:peek())):toBe(2)
				world.gui.SelectedObject = find(world.node, "Elsewhere")
				Verify.expect((action(world.root, "Increase"))):toBeNil()
				world.gui.SelectedObject = node
				local increase = action(world.root, "Increase")
				Verify.expect(keys(increase).Period and keys(increase).ButtonR1):toBe(true)
				increase.Pressed.fire()
				increase.Released.fire()
				Verify.expect((value:peek())):toBe(3)
				action(world.root, "Decrease").Pressed.fire()
				Verify.expect((value:peek())):toBe(2)
				scrub.DragStart.fire(V2.new(95, 10))
				Verify.expect((value:peek())):toBe(5)
				action(world.root, "Cancel").Pressed.fire()
				Verify.expect((value:peek())):toBe(2)
				world.stop()
			end,
		})

		verifyHarness:case("rating read-only and disabled refuse every input class", {
			id = "native_parity_weaker_values::native parity weaker values::rating read-only and disabled refuse every input class",
			run = function()
				for _, variant in { "readOnly", "disabled" } do
					local value = Compose.cell(2)
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Rating("Stars")({
								value = value,
								readOnly = variant == "readOnly",
								enabled = variant ~= "disabled",
							}),
						})
					end)
					local node = find(world.node, "Stars")
					local V2 = world.types.Vector2
					Verify.expect(node.Selectable):toBe(false)
					Verify.expect((selectableCount(node))):toBe(0)
					node.AbsoluteSize = V2.new(100, 44)
					node.Activated.fire({ Position = V2.new(95, 10) })
					node.Activated.fire(nil)
					find(node, "Scrub").DragStart.fire(V2.new(95, 10))
					world.gui.SelectedObject = node
					Verify.expect((action(world.root, "Increase"))):toBeNil()
					Verify.expect((action(world.root, "IncreaseArrow"))):toBeNil()
					Verify.expect((value:peek())):toBe(2)
					Verify.expect(find(node, "Level2").Text):toBe("★")
					Verify.expect(find(node, "Level3").Text):toBe("☆")
					world.stop()
				end
			end,
		})

		local function toggleOn(node: any, presentation: string): boolean
			local selected = node:GetAttribute("selected") == true
			if presentation == "switch" then
				local scale = find(node, "Mark").Position.X.Scale
				Verify.expect(math.abs(scale - (if selected then 0.7 else 0.3)) < 1e-6):toBe(true)
				Verify.expect((find(node, "Indicator"):HasTag("facet-toggle-on"))):toBe(selected)
			elseif presentation == "checkbox" then
				Verify.expect((find(node, "Indicator"):GetAttribute("selected"))):toBe(selected)
			end
			Verify.expect((node:HasTag("facet-selected"))):toBe(selected)
			return selected
		end

		for _, presentation in { "switch", "checkbox", "button" } :: { "button" | "checkbox" | "switch" } do
			verifyHarness:case(
				presentation .. " toggle flips once through every input and refuses input when disabled",
				{
					id = "native_parity_weaker_values::"
						.. "native parity weaker values"
						.. "::"
						.. presentation
						.. " toggle flips once through every input and refuses input when disabled",
					run = function()
						for _, input in INPUTS do
							local value, enabled = Compose.cell(false), Compose.cell(true)
							local mixed = if presentation == "checkbox" then Compose.cell(true) else nil
							local changes = 0
							local world = setup(function(UI, Host)
								return Host.Frame({
									UI.Toggle("T")({
										label = "Receive race updates with detailed results",
										value = value,
										mixed = mixed,
										presentation = presentation :: "button" | "checkbox" | "switch",
										enabled = enabled,
										onChange = function(nextValue)
											changes += 1
											value:set(nextValue)
											if mixed then
												mixed:set(false)
											end
										end,
									}),
								})
							end)
							local node = find(world.node, "T")
							Verify.expect(node.ClassName):toBe("TextButton")
							Verify.expect(node.Size.Y.Offset >= 44):toBe(true)
							Verify.expect((selectableCount(node))):toBe(1)
							press(world, node, input)
							Verify.expect((value:peek())):toBe(true)
							Verify.expect(changes):toBe(1)
							Verify.expect((toggleOn(node, presentation))):toBe(true)
							if mixed then
								Verify.expect((mixed:peek())):toBe(false)
							end
							enabled:set(false)
							press(world, node, "pointer")
							world.gui.SelectedObject = node
							Verify.expect((action(world.root, "Activate"))):toBeNil()
							Verify.expect(changes):toBe(1)
							world.stop()
						end
					end,
				}
			)
		end

		for _, presentation in { "switch", "checkbox", "button", "row" } :: { "button" | "checkbox" | "row" | "switch" } do
			verifyHarness:case(presentation .. " toggle waits for model approval through every input", {
				id = "native_parity_weaker_values::"
					.. "native parity weaker values"
					.. "::"
					.. presentation
					.. " toggle waits for model approval through every input",
				run = function()
					for _, input in INPUTS do
						local value, mixed, enabled = Compose.cell(false), Compose.cell(false), Compose.cell(true)
						local requests, observedValue, observedMixed, wanted = 0, nil, nil, nil
						local accept = false
						local shape = if presentation == "row" then "switch" else presentation
						local world = setup(function(UI, Host)
							return Host.Frame({
								UI.Toggle("T")({
									label = "Music",
									value = value,
									enabled = enabled,
									mixed = if presentation == "checkbox" then mixed else nil,
									presentation = shape,
									row = if presentation == "row" then { description = "Background music" } else nil,
									onChange = function(nextValue)
										requests += 1
										observedValue, observedMixed, wanted = value:peek(), mixed:peek(), nextValue
										if accept then
											value:set(nextValue)
											mixed:set(false)
										end
									end,
								}),
							})
						end)
						local node = find(world.node, "T")
						for _, initial in { false, true } do
							value:set(initial)
							local before = requests
							accept = false
							press(world, node, input)
							Verify.expect(requests):toBe(before + 1)
							Verify.expect(wanted):toBe(not initial)
							Verify.expect(observedValue):toBe(initial)
							Verify.expect((value:peek())):toBe(initial)
							Verify.expect((toggleOn(node, shape))):toBe(initial)
							accept = true
							press(world, node, input)
							Verify.expect(requests):toBe(before + 2)
							Verify.expect(observedValue):toBe(initial)
							Verify.expect((value:peek())):toBe(not initial)
							Verify.expect((toggleOn(node, shape))):toBe(not initial)
						end
						if presentation == "checkbox" then
							value:set(false)
							mixed:set(true)
							accept = false
							press(world, node, input)
							Verify.expect(wanted):toBe(true)
							Verify.expect(observedValue):toBe(false)
							Verify.expect(observedMixed):toBe(true)
							Verify.expect((value:peek())):toBe(false)
							Verify.expect((mixed:peek())):toBe(true)
							Verify.expect((toggleOn(node, shape))):toBe(true)
							Verify.expect(find(node, "Mark").Visible):toBe(true)
							Verify.expect(find(node, "Check").Visible):toBe(false)
							accept = true
							press(world, node, input)
							Verify.expect((value:peek())):toBe(true)
							Verify.expect((mixed:peek())):toBe(false)
							Verify.expect(find(node, "Check").Visible):toBe(true)
						end
						local before = requests
						enabled:set(false)
						press(world, node, if input == "keyboard" then "pointer" else input)
						world.gui.SelectedObject = node
						Verify.expect((action(world.root, "Activate"))):toBeNil()
						Verify.expect(requests):toBe(before)
						Verify.expect((node:GetAttribute("selected"))):toBe(value:peek())
						world.stop()
					end
				end,
			})
		end

		for _, source in { "cell", "formula", "function" } do
			verifyHarness:case("toggle reads an accepted " .. source .. " source without a writable proxy", {
				id = "native_parity_weaker_values::"
					.. "native parity weaker values"
					.. "::"
					.. "toggle reads an accepted "
					.. source
					.. " source without a writable proxy",
				run = function()
					local value, mixed = Compose.cell(false), Compose.cell(true)
					local accept = false
					local function binding(cell: any): any
						if source == "formula" then
							return Compose.formula(function(use: Use)
								return use(cell)
							end)
						elseif source == "function" then
							return function(use: Use)
								return use(cell)
							end
						end
						return cell
					end
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Toggle("T")({
								label = "Select all",
								value = binding(value),
								mixed = binding(mixed),
								presentation = "checkbox" :: "checkbox",
								onChange = function(nextValue)
									if accept then
										value:set(nextValue)
										mixed:set(false)
									end
								end,
							}),
						})
					end)
					local node = find(world.node, "T")
					Verify.expect((node:GetAttribute("selected"))):toBe(true)
					press(world, node, "pointer")
					Verify.expect((value:peek())):toBe(false)
					Verify.expect((mixed:peek())):toBe(true)
					accept = true
					press(world, node, "pointer")
					Verify.expect((value:peek())):toBe(true)
					Verify.expect((mixed:peek())):toBe(false)
					Verify.expect((node:GetAttribute("selected"))):toBe(true)
					Verify.expect(find(node, "Check").Visible):toBe(true)
					value:set(false)
					Verify.expect((node:GetAttribute("selected"))):toBe(false)
					Verify.expect(find(node, "Check").Visible):toBe(false)
					world.stop()
				end,
			})
		end

		verifyHarness:case(
			"toggle edits writable cells without a callback in every presentation and refuses read-only sources",
			{
				id = "native_parity_weaker_values::native parity weaker values::toggle edits writable cells without a callback in every presentation and refuses read-only sources",
				run = function()
					for _, presentation in { "switch", "checkbox", "button" } :: { "button" | "checkbox" | "switch" } do
						local value, mixed = Compose.cell(false), Compose.cell(true)
						local world = setup(function(UI, Host)
							return Host.Frame({
								UI.Toggle("T")({
									label = "Music",
									value = value,
									mixed = if presentation == "checkbox" then mixed else nil,
									presentation = presentation :: "button" | "checkbox" | "switch",
								}),
							})
						end)
						local node = find(world.node, "T")
						press(world, node, "pointer")
						Verify.expect((value:peek())):toBe(true)
						if presentation == "checkbox" then
							Verify.expect((mixed:peek())):toBe(false)
						end
						press(world, node, "keyboard")
						Verify.expect((value:peek())):toBe(false)
						world.stop()
					end
					for _, field in { "value", "mixed" } do
						Verify.expect((refuses("requires onChange", function(UI)
							local spec: any = {
								value = Compose.cell(false),
								mixed = Compose.cell(false),
								presentation = "checkbox" :: "checkbox",
							}
							spec[field] = Compose.formula(function()
								return false
							end)
							return UI.Toggle(spec)
						end))):toBe(true)
					end
				end,
			}
		)

		verifyHarness:case("switch paints its initial value on the first frame and each change at once", {
			id = "native_parity_weaker_values::native parity weaker values::switch paints its initial value on the first frame and each change at once",
			run = function()
				for _, initial in { false, true } do
					local value = Compose.cell(initial)
					local world = setup(function(UI, Host)
						return Host.Frame({ UI.Toggle("T")({ label = "Music", value = value }) })
					end)
					local node = find(world.node, "T")
					local mark = find(node, "Mark")
					Verify.expect(mark.Position.X.Scale):toBeCloseTo(if initial then 0.7 else 0.3, 1e-4)
					Verify.expect((find(node, "Indicator"):GetAttribute("selected"))):toBe(initial)
					Verify.expect((find(node, "Indicator"):HasTag("facet-toggle-on"))):toBe(initial)
					local frames = world.engine.heartbeat.count()
					value:set(not initial)
					Verify.expect((find(node, "Mark"))):toBe(mark)
					Verify.expect(mark.Position.X.Scale):toBeCloseTo(if initial then 0.3 else 0.7, 1e-4)
					Verify.expect((world.engine.heartbeat.count())):toBe(frames)
					world.stop()
				end
				local fixed = setup(function(UI, Host)
					return Host.Frame({
						UI.Toggle("T")({ label = "Music", value = Compose.cell(true), onChange = function() end }),
					})
				end)
				Verify.expect(find(find(fixed.node, "T"), "Mark").Position.X.Scale):toBeCloseTo(0.7, 1e-4)
				fixed.stop()
			end,
		})

		for _, side in { "leading", "trailing" } do
			verifyHarness:case("row indicator on the " .. side .. " side requests model approval through every input", {
				id = "native_parity_weaker_values::"
					.. "native parity weaker values"
					.. "::"
					.. "row indicator on the "
					.. side
					.. " side requests model approval through every input",
				run = function()
					for _, presentation in { "switch", "checkbox" } :: { "checkbox" | "switch" } do
						for _, input in INPUTS do
							local value, enabled, requests, accept = Compose.cell(false), Compose.cell(true), 0, false
							local world = setup(function(UI, Host)
								return Host.Frame({
									UI.Button("Other")({ label = "Other", onActivate = function() end }) :: unknown,
									UI.Toggle("T")({
										label = "Music",
										value = value,
										enabled = enabled,
										presentation = presentation :: "checkbox" | "switch",
										indicatorPosition = side :: "leading" | "trailing",
										row = { description = "Play race music" },
										onChange = function(wanted)
											requests += 1
											if accept then
												value:set(wanted)
											end
										end,
									}),
								})
							end)
							local node = find(world.node, "T")
							local indicator = find(node, "Indicator")
							Verify.expect((indicator:IsA("GuiButton"))):toBe(false)
							Verify.expect(indicator.Selectable):toBe(false)
							Verify.expect((selectableCount(node))):toBe(1)
							local row = indicator.Parent
							Verify.expect(row:FindFirstChildWhichIsA("UIListLayout").SortOrder)
								:toBe(world.types.Enum.SortOrder.LayoutOrder)
							for _, child in row:GetChildren() do
								if child:IsA("GuiObject") and child ~= indicator then
									Verify.expect(indicator.LayoutOrder < child.LayoutOrder):toBe(side == "leading")
								end
							end
							world.gui.SelectedObject = find(world.node, "Other")
							press(world, node, input)
							Verify.expect(requests):toBe(1)
							Verify.expect((value:peek())):toBe(false)
							Verify.expect((indicator:GetAttribute("selected"))):toBe(false)
							if input == "keyboard" or input == "gamepad" then
								Verify.expect(world.gui.SelectedObject):toBe(node)
							end
							accept = true
							press(world, node, input)
							Verify.expect(requests):toBe(2)
							Verify.expect((value:peek())):toBe(true)
							Verify.expect((indicator:GetAttribute("selected"))):toBe(true)
							if presentation == "checkbox" then
								Verify.expect(find(indicator, "Check").Visible):toBe(true)
							else
								Verify.expect(find(indicator, "Mark").Position.X.Scale):toBeCloseTo(0.7, 1e-4)
							end
							enabled:set(false)
							press(world, node, "pointer")
							Verify.expect(requests):toBe(2)
							world.stop()
						end
					end
				end,
			})
		end

		local PREFERRED = {
			{ "Gamepad", "Gamepad", "gamepad" },
			{ "Keyboard", "KeyboardAndMouse", "keyboard" },
			{ "Touch", "Touch", "touch" },
			{ "MouseKeyboard", "KeyboardAndMouse", "pointer" },
		}
		for _, entry in PREFERRED do
			verifyHarness:case("keeps one semantic target and readable row content for " .. entry[1] .. " input", {
				id = "native_parity_weaker_values::"
					.. "native parity weaker values"
					.. "::"
					.. "keeps one semantic target and readable row content for "
					.. entry[1]
					.. " input",
				run = function()
					local value, volume, hits = Compose.cell(false), Compose.cell(50), 0
					local world = setup(function(UI, Host)
						return Host.Frame({
							UI.Button("Action")({
								label = "Manage equipment",
								row = {
									description = "Choose equipment for the next expedition",
									icon = "settings",
									value = "12 items",
								},
								onActivate = function()
									hits += 1
								end,
							}) :: unknown,
							UI.Toggle("Toggle")({
								label = "Camera assistance",
								row = { description = "Keep the route in view", icon = "settings" },
								value = value,
							}),
							UI.Slider("Volume")({
								label = "Music volume",
								row = { description = "Adjust music while playing", icon = "settings" },
								value = volume,
								min = 0,
								max = 100,
								step = 10,
							}),
						})
					end)
					world.input.PreferredInput = (world.types.Enum.PreferredInput :: any)[entry[2]]
					local toggle, button, volumeNode =
						find(world.node, "Toggle"), find(world.node, "Action"), find(world.node, "Volume")
					Verify.expect(toggle.ClassName):toBe("TextButton")
					Verify.expect(button.ClassName):toBe("TextButton")
					Verify.expect((selectableCount(world.node))):toBe(3)
					Verify.expect(find(button, "Title").Text):toBe("Manage equipment")
					Verify.expect(find(button, "Description").Text):toBe("Choose equipment for the next expedition")
					Verify.expect(find(button, "Value").Text):toBe("12 items")
					local texts = {}
					for _, child in toggle:GetDescendants() do
						if child:IsA("TextLabel") then
							texts[child.Text] = true
						end
					end
					Verify.expect(texts["Camera assistance"]):toBe(true)
					Verify.expect(texts["Keep the route in view"]):toBe(true)
					Verify.expect(find(volumeNode, "Title").Text):toBe("Music volume")
					Verify.expect(find(volumeNode, "Description").Text):toBe("Adjust music while playing")
					press(world, toggle, entry[3])
					Verify.expect((value:peek())):toBe(true)
					press(world, button, entry[3])
					Verify.expect(hits):toBe(1)
					local track = find(volumeNode, "Track")
					Verify.expect(volumeNode.Selectable):toBe(true)
					if entry[3] == "touch" or entry[3] == "pointer" then
						track.AbsolutePosition = world.types.Vector2.new(10, 0)
						track.AbsoluteSize = world.types.Vector2.new(300, 44)
						find(track, "Drag").DragStart.fire(world.types.Vector2.new(310, 20))
						find(track, "Drag").DragEnd.fire()
						Verify.expect((volume:peek())):toBe(100)
					else
						world.gui.SelectedObject = volumeNode
						local increase = action(world.root, "Increase")
						Verify.expect(keys(increase).ButtonR1):toBe(true)
						increase.Pressed.fire()
						increase.Released.fire()
						Verify.expect((volume:peek())):toBe(60)
					end
					world.stop()
				end,
			})
		end

		verifyHarness:case(
			"chip requests onToggle without writing the cell and toggles a writable cell from every input",
			{
				id = "native_parity_weaker_values::native parity weaker values::chip requests onToggle without writing the cell and toggles a writable cell from every input",
				run = function()
					for _, input in INPUTS do
						local selected, requests = Compose.cell(false), {}
						local free = Compose.cell(false)
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.Chip("Controlled")({
									label = "Rain",
									selected = selected,
									onToggle = function(nextValue)
										table.insert(requests, nextValue)
									end,
								}) :: unknown,
								UI.Chip("Free")({ label = "Snow", selected = free }),
							})
						end)
						local controlled, chip = find(world.node, "Controlled"), find(world.node, "Free")
						Verify.expect(controlled.Size.Y.Offset >= 44):toBe(true)
						Verify.expect(chip.Selectable):toBe(true)
						press(world, controlled, input)
						Verify.expect(#requests):toBe(1)
						Verify.expect(requests[1]):toBe(true)
						Verify.expect((selected:peek())):toBe(false)
						Verify.expect((controlled:HasTag("facet-selected"))):toBe(false)
						Verify.expect((free:peek())):toBe(false)
						press(world, chip, input)
						Verify.expect((free:peek())):toBe(true)
						Verify.expect((find(world.node, "Free"))):toBe(chip)
						Verify.expect((chip:HasTag("facet-selected"))):toBe(true)
						Verify.expect(#requests):toBe(1)
						press(world, chip, input)
						Verify.expect((free:peek())):toBe(false)
						Verify.expect((chip:HasTag("facet-selected"))):toBe(false)
						selected:set(true)
						press(world, controlled, input)
						Verify.expect(requests[2]):toBe(false)
						Verify.expect((selected:peek())):toBe(true)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"stepper step buttons are not stops; a click on them and the Adjust keys on the stepper step the value",
			{
				id = "native_parity_weaker_values::native parity weaker values::stepper step buttons are not stops; a click on them and the Adjust keys on the stepper step the value",
				run = function()
					local value = Compose.cell(3)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Button("Elsewhere")({ label = "Elsewhere", onActivate = function() end }) :: unknown,
							UI.Stepper("Qty")({ value = value, min = 0, max = 10, step = 1 }),
						})
					end)
					local stepper = find(world.node, "Qty")
					local decrease, increase = find(stepper, "Decrease"), find(stepper, "Increase")
					Verify.expect(decrease.Selectable):toBe(false)
					Verify.expect(increase.Selectable):toBe(false)
					Verify.expect(stepper.Selectable):toBe(true)
					world.gui.SelectedObject = find(world.node, "Elsewhere")
					Verify.expect((action(world.root, "Increase"))):toBeNil()
					decrease.Activated.fire()
					Verify.expect((value:peek())):toBe(2)
					increase.Activated.fire()
					Verify.expect((value:peek())):toBe(3)
					world.gui.SelectedObject = stepper
					local adjust = action(world.root, "Increase")
					Verify.expect(keys(adjust).Period and keys(adjust).ButtonR1):toBe(true)
					adjust.Pressed.fire()
					adjust.Released.fire()
					Verify.expect((value:peek())):toBe(4)
					local lower = action(world.root, "Decrease")
					Verify.expect(keys(lower).Comma and keys(lower).ButtonL1):toBe(true)
					lower.Pressed.fire()
					lower.Released.fire()
					Verify.expect((value:peek())):toBe(3)
					world.gui.SelectedObject = stepper
					action(world.root, "Increase").Pressed.fire()
					Verify.expect((value:peek())):toBe(4)
					world.stop()
				end,
			}
		)

		verifyHarness:case("stepper value label follows the value and a custom format in place", {
			id = "native_parity_weaker_values::native parity weaker values::stepper value label follows the value and a custom format in place",
			run = function()
				local value = Compose.cell(5)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Stepper("Plain")({ value = value, label = "Volume", min = 0, max = 10, step = 1 }) :: unknown,
						UI.Stepper("Loud")({
							value = value,
							min = 0,
							max = 10,
							step = 1,
							format = function(level: number)
								return string.format("%d dB", level)
							end,
						}),
					})
				end)
				local plain, loud = find(world.node, "Plain"), find(world.node, "Loud")
				local readout = find(plain, "Value")
				Verify.expect(readout.Text):toBe("5")
				Verify.expect(find(loud, "Value").Text):toBe("5 dB")
				find(plain, "Increase").Activated.fire()
				Verify.expect((value:peek())):toBe(6)
				Verify.expect((find(plain, "Value"))):toBe(readout)
				Verify.expect(readout.Text):toBe("6")
				Verify.expect((plain:GetAttribute("semanticValue"))):toBe("6 of 0 to 10")
				Verify.expect(find(loud, "Value").Text):toBe("6 dB")
				Verify.expect((loud:GetAttribute("semanticValue"))):toBe("6 dB of 0 to 10")
				value:set(99)
				Verify.expect(readout.Text):toBe("10")
				Verify.expect(find(loud, "Value").Text):toBe("10 dB")
				world.stop()
			end,
		})

		verifyHarness:case("slider refuses a literal non-positive step and a live step that turns non-positive", {
			id = "native_parity_weaker_values::native parity weaker values::slider refuses a literal non-positive step and a live step that turns non-positive",
			run = function()
				for _, bad in { 0, -1, 0 / 0, math.huge } do
					Verify.expect((refuses("step must be positive", function(UI: FacetControls)
						return UI.Slider({ value = Compose.cell(0), min = 0, max = 10, step = bad })
					end))):toBe(true)
					Verify.expect((refuses("step must be positive", function(UI: FacetControls)
						return UI.Stepper({ value = Compose.cell(0), min = 0, max = 10, step = bad })
					end))):toBe(true)
				end
				Verify.expect((mountError(function(UI: FacetControls)
					return UI.Slider({ value = Compose.cell(0), min = 0, max = 10, step = 2 })
				end))):toBeNil()
				local angle, step = Compose.cell(0), Compose.cell(15)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Slider("Angle")({ value = angle, min = -180, max = 180, step = step }) })
				end)
				local slider = find(world.node, "Angle")
				local track = find(slider, "Track")
				track.AbsoluteSize = world.types.Vector2.new(360, 44)
				world.gui.SelectedObject = slider
				local increase = action(world.root, "Increase")
				increase.Pressed.fire()
				increase.Released.fire()
				Verify.expect((angle:peek())):toBe(15)
				step:set(90)
				Verify.expect((find(world.node, "Angle"))):toBe(slider)
				increase.Pressed.fire()
				increase.Released.fire()
				Verify.expect((angle:peek())):toBe(90)
				find(track, "Drag").DragStart.fire(world.types.Vector2.new(180 + 22, 0))
				Verify.expect((angle:peek())):toBe(0)
				step:set(45)
				find(track, "Drag").DragContinue.fire(world.types.Vector2.new(180 + 40, 0))
				Verify.expect((angle:peek())):toBe(45)
				find(track, "Drag").DragEnd.fire()
				step:set(0)
				Verify.expect((pcall(function()
					increase.Pressed.fire()
				end))):toBe(false)
				Verify.expect((angle:peek())):toBe(45)
				step:set(nil :: any)
				increase.Released.fire()
				world.gui.SelectedObject = nil
				world.gui.SelectedObject = slider
				action(world.root, "Increase").Pressed.fire()
				Verify.expect((angle:peek())):toBeCloseTo(48.6, 1e-4)
				world.stop()
			end,
		})

		verifyHarness:case("value controls format without negative zero and land non-integer grids on the bounds", {
			id = "native_parity_weaker_values::native parity weaker values::value controls format without negative zero and land non-integer grids on the bounds",
			run = function()
				local make = require("../src/ui/input_value")
				local function read<T>(
					source: T | FixtureComposeTypes.Readable<T> | FixtureComposeTypes.Formula<T> | FixtureComposeTypes.Body<T>,
					use: Use?
				): T
					return (if Compose.isReadable(source) then (source :: any):peek() else source) :: T
				end
				local signed = make({ min = -5, max = 5 }, read)
				Verify.expect((signed.format(3))):toBe("3")
				Verify.expect((signed.format(2.5))):toBe("2.5")
				Verify.expect((signed.format(0))):toBe("0")
				Verify.expect((signed.format(-0.0))):toBe("0")
				Verify.expect((signed.format(-0.001))):toBe("0")
				Verify.expect((signed.format(-0.004))):toBe("0")
				Verify.expect((signed.format(-0.25))):toBe("-0.25")
				local quarter = make({ min = 0, max = 1, step = 0.25 }, read)
				Verify.expect((quarter.quantize(0.3))):toBe(0.25)
				Verify.expect((quarter.quantize(0.99))):toBe(1)
				Verify.expect((quarter.stepped(0.75, 1))):toBe(1)
				local tenth = make({ min = 0, max = 0.3, step = 0.1 }, read)
				local at = 0
				for _ = 1, 3 do
					at = tenth.stepped(at, 1)
				end
				Verify.expect(at):toBe(0.3)
				Verify.expect((tenth.stepped(at, 1))):toBe(0.3)
				Verify.expect((tenth.fromFraction(1))):toBe(0.3)
				local offset = make({ min = 5, max = 25, step = 5 }, read)
				Verify.expect((offset.quantize(7))):toBe(5)
				Verify.expect((offset.quantize(8))):toBe(10)
				Verify.expect((offset.quantize(1000))):toBe(25)
				local bounded = make({ min = 2, max = 8 }, read)
				Verify.expect((bounded.quantize(0 / 0))):toBe(2)
				Verify.expect((bounded.quantize(math.huge))):toBe(2)
				Verify.expect((bounded.fraction(0 / 0))):toBe(0)
				local mid = make({ min = 0, max = 10, step = 2 }, read)
				Verify.expect(mid.stepped(5, 1) > 5):toBe(true)
				Verify.expect(mid.stepped(5, -1) < 5):toBe(true)
				local value = Compose.cell(-0.001)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Slider("Balance")({ value = value, min = -1, max = 1 }) :: unknown,
						UI.Slider("Quarter")({ value = Compose.cell(0), min = 0, max = 1, step = 0.25 }),
					})
				end)
				Verify.expect(find(find(world.node, "Balance"), "Value").Text):toBe("0")
				Verify.expect((find(world.node, "Balance"):GetAttribute("semanticValue"))):toBe("0 of -1 to 1")
				local quarterNode = find(world.node, "Quarter")
				local track = find(quarterNode, "Track")
				track.AbsoluteSize = world.types.Vector2.new(100, 44)
				find(track, "Drag").DragStart.fire(world.types.Vector2.new(99, 0))
				Verify.expect((quarterNode:GetAttribute("value"))):toBe(1)
				Verify.expect(find(quarterNode, "Fill").Size.X.Scale):toBe(1)
				Verify.expect(find(quarterNode, "ThumbStop").Position.X.Scale):toBe(1)
				world.stop()
				for _, bounds in { { 10, 10 }, { 0 / 0, 1 }, { 0, math.huge } } do
					Verify.expect((refuses("finite min must be below max", function(UI: FacetControls)
						return UI.Stepper({ value = Compose.cell(0), min = bounds[1], max = bounds[2] })
					end))):toBe(true)
				end
			end,
		})

		verifyHarness:case("playlist rating inside a table cell sets that track by tap and scrub without remount", {
			id = "native_parity_weaker_values::native parity weaker values::playlist rating inside a table cell sets that track by tap and scrub without remount",
			run = function()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local viewport = Compose.cell({ width = 1280, height = 720 })
				local target = engine.new("Folder")
				local guiService = engine.new("GuiService")
				local ctx = {
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = (runtime.constructors :: unknown) :: RobloxHost,
					types = engine.types,
					viewport = viewport,
					inputTarget = target,
					worldTarget = engine.new("Folder"),
					guiService = guiService,
					runService = { Heartbeat = engine.heartbeat },
					UI = Facet.controls(
						runtime,
						{ types = engine.types, viewport = viewport, guiService = guiService } :: any
					),
				}
				local built: any
				local stop, node: any = runtime.mount(function()
					built = (require("../examples/gallery/examples/02_playlist_table") :: any).build(ctx)
					return built.screen()
				end, target)
				find(node, "Body").AbsoluteWindowSize = engine.types.Vector2.new(600, 400)
				local row = find(find(node, "Items"), "drift")
				local rating = find(row, "Rating")
				Verify.expect(rating.ClassName):toBe("TextButton")
				Verify.expect((built.ratingFor("drift"):peek())):toBe(3)
				Verify.expect((rating:GetAttribute("value"))):toBe(3)
				local neighbour = built.ratingFor("neon"):peek()
				local V2 = engine.types.Vector2
				rating.AbsolutePosition = V2.new(400, 60)
				rating.AbsoluteSize = V2.new(110, 44)
				local function at(fraction: number): any
					return V2.new(400 + 110 * fraction, 65)
				end
				rating.Activated.fire({ Position = at(0.7) }, 1)
				Verify.expect((built.ratingFor("drift"):peek())):toBe(4)
				Verify.expect(find(rating, "Level4").Text):toBe("★")
				Verify.expect(find(rating, "Level5").Text):toBe("☆")
				Verify.expect((find(find(node, "Items"), "drift"))):toBe(row)
				Verify.expect((find(row, "Rating"))):toBe(rating)
				rating.Activated.fire({ Position = at(0.3) }, 1)
				Verify.expect((built.ratingFor("drift"):peek())):toBe(2)
				local scrub = find(rating, "Scrub")
				scrub.DragStart.fire(at(0.9))
				Verify.expect((built.ratingFor("drift"):peek())):toBe(5)
				scrub.DragContinue.fire(at(0.3))
				Verify.expect((built.ratingFor("drift"):peek())):toBe(2)
				scrub.DragContinue.fire(V2.new(396, 65))
				Verify.expect((built.ratingFor("drift"):peek())):toBe(1)
				scrub.DragContinue.fire(at(0.5))
				Verify.expect((built.ratingFor("drift"):peek())):toBe(3)
				scrub.DragEnd.fire()
				rating.Activated.fire({ Position = at(0.5) }, 1)
				Verify.expect((built.ratingFor("drift"):peek())):toBe(3)
				Verify.expect(find(rating, "Level3").Text):toBe("★")
				Verify.expect(find(rating, "Level4").Text):toBe("☆")
				Verify.expect((find(row, "Rating"))):toBe(rating)
				Verify.expect((built.ratingFor("neon"):peek())):toBe(neighbour)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case(
			"avatar auto-spin advances faster at each higher level and holds still when off or reduced",
			{
				id = "native_parity_weaker_values::native parity weaker values::avatar auto-spin advances faster at each higher level and holds still when off or reduced",
				run = function()
					local modelModule: any = require("../examples/virtual_monitors/model")
					local screens: any = require("../examples/virtual_monitors/screens")
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
						local stopAvatar, avatar: any = runtime.mount(views.Avatar, target)
						find(find(avatar, "SettingsDisclosure"), "Header").Activated.fire()
						find(avatar, "MotionRow").Activated.fire()
						local levels = find(avatar, "AutoSpin")
						Verify.expect(levels.ClassName):toBe("TextButton")
						local function advance(): number
							model.angle:set(0)
							for _ = 1, 5 do
								model.step(0.1, false)
							end
							return model.angle:peek()
						end
						model.autoSpin:set(0)
						Verify.expect((advance())):toBe(0)
						gui.SelectedObject = levels
						local deltas = {}
						for level = 1, 3 do
							local increase = assert(find(target, "FacetIncrease")):FindFirstChild("Increase")
							increase.Pressed.fire()
							increase.Released.fire()
							Verify.expect((model.autoSpin:peek())):toBe(level)
							deltas[level] = advance()
							Verify.expect(deltas[level] > 0):toBe(true)
						end
						Verify.expect(deltas[2] > deltas[1]):toBe(true)
						Verify.expect(deltas[3] > deltas[2]):toBe(true)
						local held = model.angle:peek()
						for _ = 1, 5 do
							model.step(0.1, true)
						end
						Verify.expect((model.angle:peek())):toBe(held)
						model.step(2, false)
						Verify.expect((model.angle:peek())):toBe(held + 15)
						stopAvatar()
					end, runtime.reactor)
					lifetime.dispose()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case("picker badge on an unselected option stays live and an empty badge hides", {
			id = "native_parity_weaker_values::native parity weaker values::picker badge on an unselected option stays live and an empty badge hides",
			run = function()
				local selected, count = Compose.cell("grid"), Compose.cell(3 :: any)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker("View")({
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "grid", label = "Grid" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "list", label = "Listing", badge = count } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end)
				local picker = find(world.node, "View")
				local grid, list = find(picker, "grid"), find(picker, "list")
				local function shown(node: any): string
					local title, pill = find(node, "Title"), find(node, "Count")
					return `{if title then title.Text else node.Text}{if pill then " [" .. pill.Text .. "]" else ""}`
				end
				Verify.expect((list:HasTag("facet-selected"))):toBe(false)
				Verify.expect((shown(list))):toBe("Listing [3]")
				Verify.expect((list:GetAttribute("label"))):toBe("Listing (3)")
				Verify.expect((shown(grid))):toBe("Grid")
				count:set("12")
				Verify.expect((find(picker, "list"))):toBe(list)
				Verify.expect((shown(list))):toBe("Listing [12]")
				count:set("")
				Verify.expect((shown(list))):toBe("Listing")
				count:set(nil)
				Verify.expect((shown(list))):toBe("Listing")
				count:set(2)
				Verify.expect((shown(list))):toBe("Listing [2]")
				Verify.expect((list:GetAttribute("FacetLabel"))):toBe("Listing")
				Verify.expect((selectableCount(picker))):toBe(2)
				list.Activated.fire()
				Verify.expect((selected:peek())):toBe("list")
				Verify.expect((shown(list))):toBe("Listing [2]")
				Verify.expect((find(picker, "list"))):toBe(list)
				world.stop()
				Verify.expect((refuses("badge must be text or a number", function(UI: FacetControls)
					return UI.Picker({
						style = "segmented" :: "segmented",
						selected = Compose.cell("a"),
						options = { { value = "a", label = "A", badge = true } },
					} :: any)
				end))):toBe(true)
			end,
		})

		verifyHarness:case("picker readable option label updates the text and announced label in place", {
			id = "native_parity_weaker_values::native parity weaker values::picker readable option label updates the text and announced label in place",
			run = function()
				local selected, name = Compose.cell("list"), Compose.cell("Listing")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker("View")({
							style = "segmented" :: "segmented",
							selected = selected,
							options = {
								{ value = "grid", label = "Grid" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "list", label = name } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}) :: unknown,
						UI.Picker("Icons")({
							style = "segmented" :: "segmented",
							iconOnly = true,
							selected = selected,
							options = {
								{ value = "grid", label = "Grid", icon = "menu" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "list", label = name, icon = "settings" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end)
				local list = find(find(world.node, "View"), "list")
				local icon = find(find(world.node, "Icons"), "list")
				Verify.expect(list.Text):toBe("Listing")
				Verify.expect((list:GetAttribute("FacetLabel"))):toBe("Listing")
				Verify.expect((list:GetAttribute("label"))):toBe("Listing")
				Verify.expect((icon:GetAttribute("FacetLabel"))):toBe("Listing")
				name:set("Rows")
				Verify.expect((find(find(world.node, "View"), "list"))):toBe(list)
				Verify.expect(list.Text):toBe("Rows")
				Verify.expect((list:GetAttribute("FacetLabel"))):toBe("Rows")
				Verify.expect((list:GetAttribute("label"))):toBe("Rows")
				Verify.expect((find(find(world.node, "Icons"), "list"))):toBe(icon)
				Verify.expect((icon:GetAttribute("FacetLabel"))):toBe("Rows")
				world.stop()
				Verify.expect((refuses("nonempty labels", function(UI: FacetControls)
					return UI.Picker({
						style = "segmented" :: "segmented",
						selected = Compose.cell("a"),
						options = {
							{ value = "a", label = Compose.cell("") } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end))):toBe(true)
			end,
		})

		verifyHarness:case("picker indicator paints the initial selection at first paint and follows every change", {
			id = "native_parity_weaker_values::native parity weaker values::picker indicator paints the initial selection at first paint and follows every change",
			run = function()
				for _, skin in { "underline", "pill", "automatic" } do
					local selected = Compose.cell("b")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Picker("View")({
								style = "segmented" :: "segmented",
								indicator = skin :: "underline" | "pill" | "automatic",
								selected = selected,
								options = {
									{ value = "a", label = "Alpha" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "b", label = "Beta" } :: FixtureNavigationTypes.PickerOption<any>,
									{ value = "c", label = "Gamma" } :: FixtureNavigationTypes.PickerOption<any>,
								},
							}),
						})
					end)
					local picker = find(world.node, "View")
					local a, b = find(picker, "a"), find(picker, "b")
					if skin == "underline" then
						local bar = find(b, "SelectionIndicator")
						Verify.expect(bar ~= nil):toBe(true)
						Verify.expect(bar.Visible):toBe(true)
						Verify.expect(bar.Selectable):toBe(false)
						Verify.expect(bar.Size.X.Scale):toBe(1)
						Verify.expect(bar.Size.Y.Offset):toBe(2)
						Verify.expect(bar.Position.Y.Scale):toBe(1)
						Verify.expect((bar:HasTag("facet-selection-indicator"))):toBe(true)
						Verify.expect((b:HasTag("facet-selected"))):toBe(false)
						Verify.expect((b:HasTag("facet-segment-current"))):toBe(false)
						Verify.expect((find(a, "SelectionIndicator"))):toBeNil()
						selected:set("a")
						Verify.expect((find(b, "SelectionIndicator"))):toBeNil()
						Verify.expect(find(a, "SelectionIndicator").Visible):toBe(true)
						local count = 0
						for _, child in picker:GetDescendants() do
							if child.Name == "SelectionIndicator" then
								count += 1
							end
						end
						Verify.expect(count):toBe(1)
					else
						Verify.expect((find(picker, "SelectionIndicator"))):toBeNil()
						Verify.expect((b:HasTag("facet-selected"))):toBe(true)
						Verify.expect((b:HasTag("facet-segment-current"))):toBe(true)
						Verify.expect((b:GetAttribute("selected"))):toBe(true)
						Verify.expect((a:HasTag("facet-selected"))):toBe(false)
						selected:set("a")
						Verify.expect((a:HasTag("facet-selected"))):toBe(true)
						Verify.expect((a:HasTag("facet-segment-current"))):toBe(true)
						Verify.expect((b:HasTag("facet-selected"))):toBe(false)
						Verify.expect((b:HasTag("facet-segment-current"))):toBe(false)
					end
					Verify.expect((find(picker, "a"))):toBe(a)
					Verify.expect((selectableCount(picker))):toBe(3)
					world.stop()
				end
			end,
		})

		verifyHarness:case("picker indicator none keeps the ordinary selection paint without a bar", {
			id = "native_parity_weaker_values::native parity weaker values::picker indicator none keeps the ordinary selection paint without a bar",
			run = function()
				local selected, indicator = Compose.cell("grid"), require("./lib/cells").indicator("none")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Picker("View")({
							style = "segmented" :: "segmented",
							indicator = indicator,
							selected = selected,
							options = {
								{ value = "grid", label = "Grid" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "list", label = "Listing" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						}),
					})
				end)
				local picker = find(world.node, "View")
				local grid, list = find(picker, "grid"), find(picker, "list")
				Verify.expect((find(picker, "SelectionIndicator"))):toBeNil()
				Verify.expect((grid:HasTag("facet-selected"))):toBe(true)
				Verify.expect((grid:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((list:HasTag("facet-selected"))):toBe(false)
				list.Activated.fire()
				Verify.expect((selected:peek())):toBe("list")
				Verify.expect((list:HasTag("facet-selected"))):toBe(true)
				Verify.expect((list:HasTag("facet-segment-current"))):toBe(true)
				Verify.expect((grid:HasTag("facet-selected"))):toBe(false)
				Verify.expect((find(picker, "SelectionIndicator"))):toBeNil()
				indicator:set("underline")
				Verify.expect(find(list, "SelectionIndicator") ~= nil):toBe(true)
				Verify.expect((list:HasTag("facet-selected"))):toBe(false)
				indicator:set("none")
				Verify.expect((find(picker, "SelectionIndicator"))):toBeNil()
				Verify.expect((list:HasTag("facet-selected"))):toBe(true)
				world.stop()
				Verify.expect((refuses("Invalid Picker.indicator", function(UI: FacetControls)
					return UI.Picker({
						style = "segmented",
						indicator = "glow",
						selected = Compose.cell("a"),
						options = { { value = "a", label = "A" } },
					} :: any)
				end))):toBe(true)
			end,
		})

		verifyHarness:case("progress bar maps clamps and repaints the same fill with track and fill paint tags", {
			id = "native_parity_weaker_values::native parity weaker values::progress bar maps clamps and repaints the same fill with track and fill paint tags",
			run = function()
				local value = Compose.cell(0.25)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.ProgressView("Load")({ value = value }) :: unknown,
						UI.ProgressView("Range")({ value = 15, min = 10, max = 30 }),
					})
				end)
				local load = find(world.node, "Load")
				local track, fill = find(load, "Track"), find(load, "Fill1")
				Verify.expect((track:HasTag("facet-track"))):toBe(true)
				Verify.expect((fill:HasTag("facet-fill"))):toBe(true)
				Verify.expect((track:HasTag("facet-fill"))):toBe(false)
				Verify.expect((fill:HasTag("facet-track"))):toBe(false)
				Verify.expect(fill.Size.X.Scale):toBe(0.25)
				Verify.expect(fill.Size.Y.Scale):toBe(1)
				value:set(0)
				Verify.expect((find(load, "Fill1"))):toBe(fill)
				Verify.expect(fill.Size.X.Scale):toBe(0)
				value:set(1)
				Verify.expect((find(load, "Fill1"))):toBe(fill)
				Verify.expect(fill.Size.X.Scale):toBe(1)
				value:set(5)
				Verify.expect(fill.Size.X.Scale):toBe(1)
				value:set(-3)
				Verify.expect(fill.Size.X.Scale):toBe(0)
				Verify.expect((find(load, "Fill1"))):toBe(fill)
				Verify.expect(find(find(world.node, "Range"), "Fill1").Size.X.Scale):toBe(0.25)
				world.stop()
				Verify.expect((fill.isDestroyed())):toBe(true)
				Verify.expect((track.isDestroyed())):toBe(true)
				Verify.expect((world.engine.heartbeat.count())):toBe(0)
				Verify.expect((refuses("max must exceed min", function(UI: FacetControls)
					return UI.ProgressView({ value = 1, min = 2, max = 2 })
				end))):toBe(true)
			end,
		})

		verifyHarness:case(
			"circular progress thickness follows eight percent of a live diameter and retracts to theme metrics",
			{
				id = "native_parity_weaker_values::native parity weaker values::circular progress thickness follows eight percent of a live diameter and retracts to theme metrics",
				run = function()
					local diameter = Compose.cell(200 :: any)
					local themes: any = Facet.themes
					local package = Compose.cell(themes.neutralPackage())
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.ProgressView("Ring")({
								presentation = "circular" :: "circular",
								value = 0.5,
								diameter = diameter,
							}) :: unknown,
							UI.ProgressView("Spin")({ presentation = "spinner" :: "spinner" }),
							UI.ProgressView("Compact")({
								presentation = "circular" :: "circular",
								value = 0.5,
								controlSize = "compact" :: "compact",
							}),
							UI.ProgressView("Large")({
								presentation = "circular" :: "circular",
								value = 0.5,
								controlSize = "large" :: "large",
							}),
						})
					end, { theme = package })
					local ring = find(find(world.node, "Ring"), "Indicator")
					local fill, track = find(ring, "RingFill"), find(ring, "RingTrack")
					Verify.expect(ring.Size.X.Offset):toBe(200)
					Verify.expect(fill.Thickness):toBe(16)
					Verify.expect(track.Thickness):toBe(16)
					diameter:set(500)
					Verify.expect(fill.Thickness):toBe(40)
					diameter:set(30)
					Verify.expect(ring.Size.X.Offset):toBe(30)
					Verify.expect(fill.Thickness):toBe(3)
					diameter:set(nil)
					Verify.expect(ring.Size.X.Offset):toBe(32)
					Verify.expect(ring.Size.Y.Offset):toBe(32)
					Verify.expect(fill.Thickness):toBe(3)
					local spinner = find(find(world.node, "Spin"), "Indicator")
					Verify.expect(spinner.Size.X.Offset):toBe(32)
					Verify.expect(find(spinner, "Segment1").Size.X.Offset):toBe(4)
					Verify.expect(find(find(world.node, "Compact"), "Indicator").Size.X.Offset):toBe(36)
					Verify.expect(find(find(world.node, "Large"), "Indicator").Size.X.Offset):toBe(56)
					local nextPackage = themes.neutralPackage()
					nextPackage.metrics.controls.progress.circularSize = 100
					nextPackage.metrics.controls.progress.spinnerDotSize = 11
					package:set(nextPackage)
					Verify.expect(ring.Size.X.Offset):toBe(100)
					Verify.expect(fill.Thickness):toBe(8)
					Verify.expect(spinner.Size.X.Offset):toBe(100)
					Verify.expect(find(spinner, "Segment1").Size.X.Offset):toBe(11)
					diameter:set(64)
					Verify.expect(ring.Size.X.Offset):toBe(64)
					Verify.expect(fill.Thickness):toBe(5)
					diameter:set(nil)
					Verify.expect(ring.Size.X.Offset):toBe(100)
					world.stop()
				end,
			}
		)

		verifyHarness:case("circular progress at a quarter ends at three o'clock", {
			id = "native_parity_weaker_values::native parity weaker values::circular progress at a quarter ends at three o'clock",
			run = function()
				local value = Compose.cell(0.25)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.ProgressView("Ring")({ presentation = "circular" :: "circular", value = value }),
					})
				end)
				local fill = find(find(world.node, "Ring"), "RingFill")
				local radius = 1 - 3 / 32
				local points = fill:GetControlPoints()
				Verify.expect(points[1].Position.X.Scale):toBeCloseTo(0.5, 1e-4)
				Verify.expect(points[1].Position.Y.Scale):toBeCloseTo(0.5 - radius / 2, 1e-4)
				Verify.expect(points[#points].Position.X.Scale):toBeCloseTo(0.5 + radius / 2, 1e-4)
				Verify.expect(points[#points].Position.Y.Scale):toBeCloseTo(0.5, 1e-4)
				value:set(0.75)
				points = fill:GetControlPoints()
				Verify.expect(points[#points].Position.X.Scale):toBeCloseTo(0.5 - radius / 2, 1e-4)
				Verify.expect(points[#points].Position.Y.Scale):toBeCloseTo(0.5, 1e-4)
				world.stop()
			end,
		})

		verifyHarness:case("badge caption and control size rung stay live through invalid captions", {
			id = "native_parity_weaker_values::native parity weaker values::badge caption and control size rung stay live through invalid captions",
			run = function()
				local label, size = Compose.cell("New" :: any), Compose.cell("compact" :: any)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Badge("Plain")({ label = label, controlSize = size }) :: unknown,
						UI.Badge("Iconic")({ label = label, icon = "checkmark", controlSize = size }),
					})
				end)
				local plain, iconic = find(world.node, "Plain"), find(world.node, "Iconic")
				local glyph = iconic:FindFirstChildWhichIsA("ImageLabel")
				Verify.expect(plain.Size.Y.Offset):toBe(20)
				Verify.expect(iconic.Size.Y.Offset):toBe(20)
				Verify.expect(glyph.Size.X.Offset):toBe(11)
				Verify.expect((pcall(function()
					label:set(42)
				end))):toBe(false)
				Verify.expect(plain.Text):toBe("New")
				label:set("Ready")
				size:set("large")
				Verify.expect(plain.Text):toBe("Ready")
				Verify.expect(find(iconic, "Label").Text):toBe("Ready")
				Verify.expect(plain.Size.Y.Offset):toBe(28)
				Verify.expect(iconic.Size.Y.Offset):toBe(28)
				Verify.expect(glyph.Size.X.Offset):toBe(17)
				Verify.expect((pcall(function()
					size:set("huge")
				end))):toBe(false)
				Verify.expect(plain.Size.Y.Offset):toBe(28)
				Verify.expect(glyph.Size.X.Offset):toBe(17)
				size:set(nil)
				Verify.expect(plain.Size.Y.Offset):toBe(24)
				Verify.expect(glyph.Size.X.Offset):toBe(14)
				Verify.expect((find(world.node, "Iconic"))):toBe(iconic)
				world.stop()
			end,
		})

		verifyHarness:case("badge refuses meaningless content and invalid options at construction", {
			id = "native_parity_weaker_values::native parity weaker values::badge refuses meaningless content and invalid options at construction",
			run = function()
				local cases: { { any } } = {
					{ "meaningful text or a named icon", {} },
					{ "meaningful text or a named icon", { label = "" } },
					{ "meaningful text or a named icon", { icon = "checkmark" } },
					{ "label must be a string", { label = 2 } },
					{ "invalid iconPosition", { label = "New", icon = "checkmark", iconPosition = "above" } },
					{ "invalid appearance", { label = "New", appearance = "emphasis" } },
					{ "invalid status", { label = "New", status = "bad" } },
					{ "invalid status", { label = "New", status = false } },
				}
				for _, case in cases do
					Verify.expect((refuses(case[1], function(UI: FacetControls)
						return UI.Badge(case[2])
					end))):toBe(true)
				end
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Badge("Named")({ icon = "checkmark", name = "Verified" }) :: unknown,
						UI.Badge("Trailing")({
							label = "New",
							icon = "checkmark",
							iconPosition = "trailing" :: "trailing",
						}),
					})
				end)
				local named = find(world.node, "Named")
				Verify.expect((named:FindFirstChildWhichIsA("TextLabel"):GetAttribute("AccessibleLabel")))
					:toBe("Verified")
				Verify.expect(named:FindFirstChildWhichIsA("TextLabel").Text):toBe("")
				local trailing = find(world.node, "Trailing")
				Verify.expect(trailing:FindFirstChildWhichIsA("ImageLabel").LayoutOrder):toBe(2)
				Verify.expect(find(trailing, "Label").LayoutOrder):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case("badge quarantines an empty unnamed caption and a false status then recovers", {
			id = "native_parity_weaker_values::native parity weaker values::badge quarantines an empty unnamed caption and a false status then recovers",
			run = function()
				local label, status = Compose.cell("Ready" :: any), Compose.cell("error" :: any)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Badge("Tag")({ label = label, status = status }) })
				end)
				local badge = find(world.node, "Tag")
				for _, empty in { "", nil :: any } do
					Verify.expect((pcall(function()
						label:set(empty)
					end))):toBe(false)
					Verify.expect(badge.Text):toBe("Ready")
				end
				label:set("New")
				Verify.expect(badge.Text):toBe("New")
				Verify.expect((pcall(function()
					status:set(false)
				end))):toBe(false)
				Verify.expect((badge:HasTag("facet-status-error"))):toBe(true)
				Verify.expect((badge:HasTag("facet-status-neutral"))):toBe(false)
				status:set("neutral")
				Verify.expect((badge:HasTag("facet-status-neutral"))):toBe(true)
				Verify.expect((badge:HasTag("facet-status-error"))):toBe(false)
				Verify.expect(badge.Text):toBe("New")
				world.stop()
			end,
		})

		verifyHarness:case("status indicator is a compact twelve pixel dot with a readable name and no focus stop", {
			id = "native_parity_weaker_values::native parity weaker values::status indicator is a compact twelve pixel dot with a readable name and no focus stop",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.StatusIndicator("Mark")({ name = "Connected" }) :: unknown,
						UI.StatusIndicator("Plain")({ status = "error" :: "error" }),
					})
				end)
				local mark = find(world.node, "Mark")
				Verify.expect(mark.Size.X.Offset):toBe(12)
				Verify.expect(mark.Size.Y.Offset):toBe(12)
				Verify.expect(mark:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale):toBe(1)
				Verify.expect(mark:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(1)
				Verify.expect(mark.Text):toBe("")
				Verify.expect((mark:HasTag("facet-status-neutral"))):toBe(true)
				Verify.expect((mark:HasTag("facet-badge"))):toBe(true)
				Verify.expect((mark:GetAttribute("AccessibleLabel"))):toBe("Connected")
				Verify.expect(mark.Selectable):toBe(false)
				Verify.expect((mark:IsA("GuiButton"))):toBe(false)
				Verify.expect((selectableCount(world.node))):toBe(0)
				Verify.expect((find(world.node, "Plain"):HasTag("facet-status-error"))):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("status indicator forms stay distinguishable at ten thirteen and sixteen pixels", {
			id = "native_parity_weaker_values::native parity weaker values::status indicator forms stay distinguishable at ten thirteen and sixteen pixels",
			run = function()
				for _, size in { 10, 13, 16 } do
					local signatures = {}
					for _, form in { "dot", "ring", "square", "dash" } :: { "dash" | "dot" | "ring" | "square" } do
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({
								UI.StatusIndicator("Mark")({
									form = form :: "dash" | "dot" | "ring" | "square",
									diameter = size,
								}),
							})
						end)
						local mark = find(world.node, "Mark")
						local corner = mark:FindFirstChildWhichIsA("UICorner").CornerRadius
						local aspect = mark:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio
						local ring = mark:FindFirstChild("Ring")
						Verify.expect(mark.Size.X.Offset):toBe(size)
						Verify.expect(corner.Offset):toBe(0)
						Verify.expect(corner.Scale):toBe(if form == "square" then 0 else 1)
						Verify.expect(aspect):toBe(if form == "dash" then 3 else 1)
						Verify.expect(mark.Size.Y.Offset)
							:toBe(if form == "dash" then math.floor(math.max(3, size / 3)) else size)
						Verify.expect(ring ~= nil):toBe(form == "ring")
						Verify.expect((mark:HasTag("facet-status-hollow"))):toBe(form == "ring")
						if ring then
							Verify.expect(ring.Thickness):toBe(math.max(2, math.floor(size / 6 + 0.5)))
							Verify.expect(ring.Thickness * 2 < size):toBe(true)
						end
						signatures[`{corner.Scale}:{aspect}:{ring ~= nil}`] = true
						world.stop()
					end
					local distinct = 0
					for _ in signatures do
						distinct += 1
					end
					Verify.expect(distinct):toBe(4)
				end
			end,
		})

		verifyHarness:case("status indicator refuses invalid construction", {
			id = "native_parity_weaker_values::native parity weaker values::status indicator refuses invalid construction",
			run = function()
				local cases: { { any } } = {
					{ "invalid form", { form = "blob" } },
					{ "invalid status", { status = "bad" } },
					{ "invalid status", { status = false } },
					{ "count must be a nonnegative integer", { count = -1 } },
					{ "count must be a nonnegative integer", { count = 1.5 } },
					{ "count must be a nonnegative integer", { count = math.huge } },
					{ "count must be a nonnegative integer", { count = 0 / 0 } },
					{ "count requires dot or square", { count = 1, form = "ring" } },
					{ "count requires dot or square", { count = 1, form = "dash" } },
					{ "max must be a nonnegative integer", { count = 1, max = -1 } },
					{ "max must be a nonnegative integer", { count = 1, max = 2.5 } },
				}
				for _, case in cases do
					Verify.expect((refuses(case[1], function(UI: FacetControls)
						return UI.StatusIndicator(case[2])
					end))):toBe(true)
				end
				Verify.expect((mountError(function(UI: FacetControls)
					return UI.StatusIndicator({ count = 3, form = "square", max = 9 } :: any)
				end))):toBeNil()
			end,
		})

		verifyHarness:case("skeleton forms are inert placeholders with a sixty percent final paragraph line", {
			id = "native_parity_weaker_values::native parity weaker values::skeleton forms are inert placeholders with a sixty percent final paragraph line",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Skeleton("Box")({}) :: unknown,
						UI.Skeleton("Circle")({ form = "circle" :: "circle" }),
						UI.Skeleton("Paragraph")({ form = "line" :: "line", lines = 3 }),
						UI.Skeleton("Line")({ form = "line" :: "line" }),
					})
				end)
				local box = find(find(world.node, "Box"), "Placeholder1")
				Verify.expect(box.Size.X.Scale):toBe(1)
				Verify.expect(box.Size.Y.Offset):toBe(44)
				Verify.expect((box:FindFirstChildWhichIsA("UICorner"))):toBeNil()
				local circle = find(find(world.node, "Circle"), "Placeholder1")
				Verify.expect(circle.Size.X.Offset):toBe(44)
				Verify.expect(circle.Size.Y.Offset):toBe(44)
				Verify.expect(circle.Size.X.Scale):toBe(0)
				Verify.expect(circle:FindFirstChildWhichIsA("UICorner").CornerRadius.Scale):toBe(1)
				local paragraph = find(world.node, "Paragraph")
				for index = 1, 3 do
					local line = find(paragraph, "Placeholder" .. index)
					Verify.expect(line.Size.Y.Offset):toBe(20)
					Verify.expect(line.Size.X.Scale):toBeCloseTo(if index == 3 then 0.6 else 1, 1e-4)
				end
				Verify.expect(find(find(world.node, "Line"), "Placeholder1").Size.X.Scale):toBe(1)
				Verify.expect((selectableCount(world.node))):toBe(0)
				for _, child in world.node:GetDescendants() do
					Verify.expect((child:IsA("GuiButton"))):toBe(false)
					if child:IsA("GuiObject") and string.match(child.Name, "^Placeholder") then
						Verify.expect((child:HasTag("facet-skeleton"))):toBe(true)
					end
				end
				world.stop()
				for _, spec in
					{ { form = "blob" }, { form = "box", lines = 2 }, { form = "circle", corners = "pill" :: "pill" } }
				do
					Verify.expect(mountError(function(UI: FacetControls)
						return UI.Skeleton(spec :: any)
					end) ~= nil):toBe(true)
				end
			end,
		})

		local function reference(name: string): any
			local themes: any = Facet.themes
			if name == "neutral" then
				return themes.neutralPackage()
			end
			local module: any = (require :: any)("../examples/themes/" .. name)
			local package, report = module.build(themes)
			assert(report.ok, name)
			return package
		end

		local function artwork(root: any, name: string): any
			return root:FindFirstChild(name, true)
		end

		verifyHarness:case("value display and toggle slots stretch their plates and keep fixed ornaments whole", {
			id = "native_parity_weaker_values::native parity weaker values::value display and toggle slots stretch their plates and keep fixed ornaments whole",
			run = function()
				local themes: any = Facet.themes
				local package = themes.neutralPackage()
				package.assets = {
					plate = { content = "rbxassetid://40", sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 } },
					cap = { content = "rbxassetid://41" },
					center = { content = "rbxassetid://42" },
				}
				for _, slot in { "barTrack", "barFill", "stepperPlate", "toggleTrack", "toggleKnob" } do
					package.chrome[slot] = { kind = "nineSlice" :: "nineSlice", asset = "plate" }
				end
				package.chrome.barCap = { kind = "nineSlice" :: "nineSlice", asset = "cap", size = { w = 20, h = 24 } }
				package.chrome.barCenter =
					{ kind = "nineSlice" :: "nineSlice", asset = "center", size = { w = 30, h = 18 } }
				local value = Compose.cell(0.4)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.ProgressView("Bar")({ value = value, thickness = 24 }) :: unknown,
						UI.Toggle("Switch")({ value = Compose.cell(true), label = "Music" }),
						UI.Stepper("Count")({ value = Compose.cell(2), min = 0, max = 10 }),
					})
				end, { theme = package })
				local bar, switch, stepper =
					find(world.node, "Bar"), find(world.node, "Switch"), find(world.node, "Count")
				local track = find(bar, "Track")
				local trackArt = artwork(track, "barTrack1")
				Verify.expect(trackArt.Image):toBe("rbxassetid://40")
				Verify.expect(trackArt.ScaleType):toBe(world.types.Enum.ScaleType.Slice)
				Verify.expect(trackArt.Size.X.Scale):toBe(1)
				Verify.expect(trackArt.Size.Y.Scale):toBe(1)
				local fillArt = artwork(find(bar, "Fill1"), "barFill1")
				Verify.expect(fillArt.ScaleType):toBe(world.types.Enum.ScaleType.Slice)
				for _, name in { "barCap-start", "barCap-end" } do
					local cap = artwork(bar, name)
					Verify.expect(cap.Image):toBe("rbxassetid://41")
					Verify.expect(cap.ScaleType):toBe(world.types.Enum.ScaleType.Stretch)
					Verify.expect(cap.Size):toBe(world.types.UDim2.fromOffset(20, 24))
					Verify.expect(cap.AnchorPoint):toBe(world.types.Vector2.new(cap.Position.X.Scale, 0.5))
				end
				local center = artwork(bar, "barCenter")
				Verify.expect(center.Size):toBe(world.types.UDim2.fromOffset(30, 18))
				Verify.expect(center.Position):toBe(world.types.UDim2.fromScale(0.5, 0.5))
				value:set(0.9)
				Verify.expect(artwork(bar, "barCap-end").Size):toBe(world.types.UDim2.fromOffset(20, 24))
				Verify.expect((artwork(bar, "barCenter"))):toBe(center)
				Verify.expect(center.Size):toBe(world.types.UDim2.fromOffset(30, 18))
				local trackSkin = artwork(switch, "toggleTrack1")
				Verify.expect((trackSkin:IsDescendantOf(find(switch, "Indicator")))):toBe(true)
				Verify.expect(trackSkin.Size.X.Scale):toBe(1)
				local knob = artwork(switch, "toggleKnob1")
				Verify.expect((knob:IsDescendantOf(find(switch, "Mark")))):toBe(true)
				Verify.expect(knob.Size.X.Scale):toBe(1)
				local plate = artwork(stepper, "stepperPlate1")
				Verify.expect(plate.Image):toBe("rbxassetid://40")
				Verify.expect(plate.Size.X.Scale):toBe(1)
				Verify.expect(plate.Size.Y.Scale):toBe(1)
				Verify.expect((plate:IsDescendantOf(find(stepper, "Controls")))):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("toggle on art keys on the value tag while the row keeps its ordinary paint", {
			id = "native_parity_weaker_values::native parity weaker values::toggle on art keys on the value tag while the row keeps its ordinary paint",
			run = function()
				local themes: any = Facet.themes
				local package = themes.neutralPackage()
				package.assets = { off = { content = "rbxassetid://50" }, on = { content = "rbxassetid://51" } }
				for _, slot in { "toggleTrack", "toggleKnob" } do
					package.chrome[slot] =
						{ kind = "nineSlice" :: "nineSlice", asset = { default = "off", selected = "on" } }
				end
				for _, presentation in { "switch" } :: { "switch" } do
					local value = Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Toggle("T")({ value = value, label = "Music", presentation = presentation :: "switch" }) :: unknown,
							UI.Toggle("B")({ value = value, label = "Music", presentation = "button" :: "button" }),
						})
					end, { theme = package })
					local node, indicator = find(world.node, "T"), find(find(world.node, "T"), "Indicator")
					local button = find(world.node, "B")
					Verify.expect((node:HasTag("facet-toggle-row"))):toBe(true)
					Verify.expect((indicator:HasTag("facet-toggle-on"))):toBe(false)
					Verify.expect(artwork(indicator, "toggleTrack1").Image):toBe("rbxassetid://50")
					Verify.expect(artwork(find(indicator, "Mark"), "toggleKnob1").Image):toBe("rbxassetid://50")
					value:set(true)
					Verify.expect((indicator:HasTag("facet-toggle-on"))):toBe(true)
					Verify.expect(artwork(indicator, "toggleTrack1").Image):toBe("rbxassetid://51")
					Verify.expect(artwork(find(indicator, "Mark"), "toggleKnob1").Image):toBe("rbxassetid://51")
					Verify.expect((button:HasTag("facet-toggle-row"))):toBe(false)
					Verify.expect((find(button, "Indicator"))):toBeNil()
					Verify.expect((button:HasTag("facet-selected"))):toBe(true)
					value:set(false)
					Verify.expect((indicator:HasTag("facet-toggle-on"))):toBe(false)
					Verify.expect(artwork(indicator, "toggleTrack1").Image):toBe("rbxassetid://50")
					world.stop()
				end
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local stop, sheet: any = runtime.mount(function()
					return themes.createStyleSheet(runtime, themes.neutralPackage(), { types = engine.types })
				end, engine.new("Folder"))
				local priorities, properties = {}, {}
				for _, rule in sheet:GetChildren() do
					priorities[rule.Selector] = rule.Priority
					properties[rule.Selector] = rule:GetProperties()
				end
				Verify.expect(properties[".facet-toggle-on"].BackgroundColor3 ~= nil):toBe(true)
				Verify.expect(properties[".facet-toggle-row"].BackgroundTransparency):toBe(1)
				Verify.expect(priorities[".facet-toggle-row"] > priorities[".facet-selected"]):toBe(true)
				Verify.expect(priorities[".facet-toggle-row.facet-selected"] > priorities[".facet-selected"]):toBe(true)
				Verify.expect(properties[".facet-toggle-row.facet-selected"].TextColor3 ~= nil):toBe(true)
				Verify.expect(properties[".facet-toggle-row.facet-selected"].BackgroundColor3):toBeNil()
				Verify.expect(
					priorities[".facet-toggle-row.facet-selected >> .facet-text"]
						> priorities[".facet-selected >> .facet-text"]
				):toBe(true)
				stop()
				runtime:dispose()
			end,
		})

		verifyHarness:case("value controls declare their slots and fill geometry stays the percent", {
			id = "native_parity_weaker_values::native parity weaker values::value controls declare their slots and fill geometry stays the percent",
			run = function()
				local themes: any = Facet.themes
				local withPlate = themes.neutralPackage()
				withPlate.assets = { art = { content = "rbxassetid://60" }, button = { content = "rbxassetid://61" } }
				for _, slot in { "stepperPlate", "sliderTrack", "sliderThumb", "barFill", "barTrack" } do
					withPlate.chrome[slot] = { kind = "nineSlice" :: "nineSlice", asset = "art" }
				end
				withPlate.chrome.control = { kind = "nineSlice" :: "nineSlice", asset = "button" }
				local controlOnly = themes.neutralPackage()
				controlOnly.assets = { button = { content = "rbxassetid://61" } }
				controlOnly.chrome.control = { kind = "nineSlice" :: "nineSlice", asset = "button" }
				for _, package in { withPlate, controlOnly } do
					local value = Compose.cell(0.25)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Stepper("Count")({ value = Compose.cell(2), min = 0, max = 10 }) :: unknown,
							UI.Slider("Volume")({ value = value, min = 0, max = 1 }),
							UI.ProgressView("Load")({ value = value }),
						})
					end, { theme = package })
					local stepper = find(world.node, "Count")
					for _, name in { "Decrease", "Increase" } do
						local art = artwork(find(stepper, name), "control1")
						Verify.expect(art ~= nil):toBe(true)
						Verify.expect(art.Image):toBe("rbxassetid://61")
					end
					local slider = find(world.node, "Volume")
					local fill = find(slider, "Fill")
					Verify.expect(fill.Size.X.Scale):toBe(0.25)
					Verify.expect(find(slider, "ThumbStop").Position.X.Scale):toBe(0.25)
					local load = find(world.node, "Load")
					Verify.expect(find(load, "Fill1").Size.X.Scale):toBe(0.25)
					if package == withPlate then
						Verify.expect(artwork(stepper, "stepperPlate1").Image):toBe("rbxassetid://60")
						Verify.expect(artwork(find(slider, "Rail"), "sliderTrack1").Image):toBe("rbxassetid://60")
						Verify.expect(artwork(find(slider, "Thumb"), "sliderThumb1").Image):toBe("rbxassetid://60")
						Verify.expect(artwork(fill, "barFill1").Image):toBe("rbxassetid://60")
						Verify.expect(artwork(find(load, "Track"), "barTrack1") ~= nil):toBe(true)
						Verify.expect(artwork(find(load, "Fill1"), "barFill1") ~= nil):toBe(true)
					else
						Verify.expect((artwork(stepper, "stepperPlate1"))):toBeNil()
						Verify.expect((artwork(find(load, "Track"), "control1"))):toBeNil()
						Verify.expect((artwork(slider, "control1"))):toBeNil()
					end
					value:set(0.75)
					Verify.expect(fill.Size.X.Scale):toBe(0.75)
					Verify.expect(find(slider, "ThumbStop").Position.X.Scale):toBe(0.75)
					Verify.expect(find(load, "Fill1").Size.X.Scale):toBe(0.75)
					Verify.expect((find(slider, "Fill"))):toBe(fill)
					world.stop()
				end
			end,
		})

		verifyHarness:case(
			"toggle label column reserves the track beside a growing native label across reference packages",
			{
				id = "native_parity_weaker_values::native parity weaker values::toggle label column reserves the track beside a growing native label across reference packages",
				run = function()
					for _, name in { "neutral", "pixel_quest", "fantasy_ornate", "compact_pointer" } do
						local package = reference(name)
						local skin = package.chrome and package.chrome.control
						local insets = if skin then skin.contentInsets or {} else {}
						for _, presentation in { "switch", "checkbox" } :: { "checkbox" | "switch" } do
							for _, side in { "leading", "trailing" } do
								local label = Compose.cell("Rain")
								local world = setup(function(UI: FacetControls, Host: RobloxHost)
									return Host.Frame({
										UI.Toggle("T")({
											label = label,
											value = Compose.cell(true),
											presentation = presentation :: "checkbox" | "switch",
											indicatorPosition = side :: "leading" | "trailing",
										}),
									})
								end, { theme = package })
								local node = find(world.node, "T")
								local indicator = find(node, "Indicator")
								local padding = node:FindFirstChildWhichIsA("UIPadding")
								local width = if presentation == "switch" then 38 else 24
								local reserve = width + 8
								Verify.expect(node.AutomaticSize):toBe(world.types.Enum.AutomaticSize.XY)
								Verify.expect(node.TextWrapped):toBe(false)
								Verify.expect(indicator.Size.X.Offset):toBe(width)
								local reserved = if side == "leading" then padding.PaddingLeft else padding.PaddingRight
								local other = if side == "leading" then padding.PaddingRight else padding.PaddingLeft
								Verify.expect(reserved.Offset)
									:toBe((insets[if side == "leading" then "left" else "right"] or 0) + reserve)
								Verify.expect(other.Offset)
									:toBe(insets[if side == "leading" then "right" else "left"] or 0)
								if side == "leading" then
									Verify.expect(indicator.Position.X.Scale):toBe(0)
									Verify.expect(indicator.Position.X.Offset):toBe(-reserve)
									Verify.expect(indicator.Position.X.Offset + width <= 0):toBe(true)
								else
									Verify.expect(indicator.Position.X.Scale):toBe(1)
									Verify.expect(indicator.Position.X.Offset >= 0):toBe(true)
									Verify.expect(indicator.Position.X.Offset + width):toBe(reserve)
								end
								Verify.expect(node.Text):toBe("Rain")
								label:set("Night vision assistance")
								Verify.expect(node.Text):toBe("Night vision assistance")
								Verify.expect((find(world.node, "T"))):toBe(node)
								Verify.expect(padding.Parent):toBe(node)
								world.stop()
							end
						end
					end
				end,
			}
		)
	end)
end
