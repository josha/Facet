--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ScreenGuiConstructor = typeof(require("@repo/tools/typecheck/aliases").ScreenGuiConstructor)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local requireDynamic = require :: (any) -> any

	local Facet = require("../src") :: any
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

	local function setup(build: (any, any) -> any, options: { [string]: any }?): any
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
		local parent = engine.new("Folder")
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			inputParent = parent,
			motionLevel = "none",
			services = { GuiService = gui, UserInputService = input },
		}
		for key, value in (options or {} :: { [string]: any }) do
			config[key] = value
		end
		local UI = Facet.controls(runtime, config)
		local stop, screen: any = runtime.mount(function()
			return ((runtime.constructors.ScreenGui :: unknown) :: ScreenGuiConstructor)({
				build(UI, runtime.constructors),
			})
		end, parent)
		local world = { engine = engine, gui = gui, input = input, screen = screen, parent = parent, UI = UI }
		function world.find(name: string, root: any?): any
			local at = root or screen
			if at.Name == name then
				return at
			end
			for _, child in at:GetChildren() do
				local found = world.find(name, child)
				if found then
					return found
				end
			end
			return nil
		end
		function world.press(key: string)
			input.InputBegan:Fire({
				KeyCode = (engine.types.Enum.KeyCode :: any)[key],
				UserInputType = engine.types.Enum.UserInputType.Gamepad1,
			}, true)
			input.InputEnded:Fire({
				KeyCode = (engine.types.Enum.KeyCode :: any)[key],
				UserInputType = engine.types.Enum.UserInputType.Gamepad1,
			}, true)
		end
		function world.stick(x: number, y: number, key: string?)
			input.InputChanged:Fire({
				KeyCode = (engine.types.Enum.KeyCode :: any)[key or "Thumbstick1"],
				UserInputType = engine.types.Enum.UserInputType.Gamepad1,
				Position = engine.types.Vector3.new(x, y, 0),
			}, true)
		end
		function world.stickEnded()
			input.InputEnded:Fire({
				KeyCode = engine.types.Enum.KeyCode.Thumbstick1,
				UserInputType = engine.types.Enum.UserInputType.Gamepad1,
				Position = engine.types.Vector3.new(0, 0, 0),
			}, true)
		end
		function world.action(name: string)
			for _, node in parent:GetDescendants() do
				if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
					node:FindFirstChild(name).Pressed:Fire()
					return true
				end
			end
			return false
		end
		function world.stop()
			stop()
			runtime:dispose()
		end
		return world
	end

	local function selectableInside(root: any): { string }
		local found = {}
		for _, node in root:GetDescendants() do
			if node:IsA("GuiObject") and node.Selectable then
				table.insert(found, node.Name)
			end
		end
		return found
	end

	verifyHarness:suite("an adjustable claims its axis on its own stop only", function()
		verifyHarness:case("a selected child of a Stepper does not pin its own links", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a selected child of a Stepper does not pin its own links",
			run = function()
				local value = Compose.cell(6)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
				end)
				local stepper = w.find("Volume")
				Verify.expect((stepper:HasTag("facet-adjustable"))):toBe(true)
				local plus = w.find("Increase", stepper)
				w.gui.SelectedObject = plus
				Verify.expect(plus.NextSelectionLeft):toBe(nil)
				Verify.expect(plus.NextSelectionRight):toBe(nil)
				w.press("DPadLeft")
				Verify.expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		verifyHarness:case("at a limit the stop frees that direction for the engine; a held press stops at the limit", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::at a limit the stop frees that direction for the engine; a held press stops at the limit",
			run = function()
				local left, right = Compose.cell(8), Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Stepper("A")({ value = left, max = 10 }) :: unknown,
						UI.Stepper("B")({ value = right, max = 10 }),
					})
				end)
				local V = w.engine.types.Vector2
				local a, b = w.find("A"), w.find("B")
				a.AbsolutePosition, a.AbsoluteSize = V.new(0, 0), V.new(200, 44)
				b.AbsolutePosition, b.AbsoluteSize = V.new(220, 0), V.new(200, 44)
				w.gui.SelectedObject = a
				w.stick(1, 0)
				Verify.expect((left:peek())):toBe(9)
				for _ = 1, 6 do
					w.engine.heartbeat:Fire(0.41)
				end
				Verify.expect((left:peek())):toBe(10)
				Verify.expect(w.gui.SelectedObject):toBe(a)
				w.stickEnded()
				Verify.expect(a.NextSelectionRight):toBe(nil)
				Verify.expect(a.NextSelectionLeft):toBe(a)
				w.press("DPadRight")
				Verify.expect((left:peek())):toBe(10)
				w.gui.SelectedObject = b
				Verify.expect(b.NextSelectionLeft):toBe(b)
				Verify.expect(b.NextSelectionRight):toBe(b)
				w.press("DPadLeft")
				w.press("DPadLeft")
				w.press("DPadLeft")
				Verify.expect((right:peek())):toBe(0)
				Verify.expect(w.gui.SelectedObject):toBe(b)
				Verify.expect(b.NextSelectionLeft):toBe(nil)
				Verify.expect(b.NextSelectionRight):toBe(b)
				w.stop()
			end,
		})

		local function pair(w: any, extra: any?): (any, any)
			local V = w.engine.types.Vector2
			local a, b = w.find("A"), w.find("B")
			a.AbsolutePosition, a.AbsoluteSize = V.new(0, 0), V.new(200, 44)
			b.AbsolutePosition, b.AbsoluteSize = V.new(220, 0), V.new(200, 44)
			return a, b
		end

		verifyHarness:case(
			"R1 and Period at the maximum keep the selection and the value; only a direction passes on",
			{
				id = "native_focus_stops::an adjustable claims its axis on its own stop only::R1 and Period at the maximum keep the selection and the value; only a direction passes on",
				run = function()
					local left, right = Compose.cell(10), Compose.cell(3)
					local w = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Stepper("A")({ value = left, max = 10 }) :: unknown,
							UI.Stepper("B")({ value = right, max = 10 }),
						})
					end)
					local a = pair(w)
					w.gui.SelectedObject = a
					Verify.expect((w.action("Increase"))):toBe(true)
					Verify.expect(w.gui.SelectedObject):toBe(a)
					Verify.expect((left:peek())):toBe(10)
					Verify.expect((right:peek())):toBe(3)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"at a limit the stop keeps the game's own NextSelection link, so the engine moves the selection",
			{
				id = "native_focus_stops::an adjustable claims its axis on its own stop only::at a limit the stop keeps the game's own NextSelection link, so the engine moves the selection",
				run = function()
					local w = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Stepper("A")({ value = Compose.cell(10), max = 10 }) :: unknown,
							UI.Stepper("B")({ value = Compose.cell(3), max = 10 }),
							UI.Button("C")({ label = "C" }),
						})
					end)
					local a = pair(w)
					local c = w.find("C")
					c.AbsolutePosition, c.AbsoluteSize =
						w.engine.types.Vector2.new(0, 300), w.engine.types.Vector2.new(200, 44)
					a.NextSelectionRight = c
					w.gui.SelectedObject = a
					Verify.expect(a.NextSelectionRight):toBe(c)
					Verify.expect(a.NextSelectionLeft):toBe(a)
					w.press("DPadRight")
					Verify.expect(a.NextSelectionRight):toBe(c)
					w.stop()
				end,
			}
		)

		verifyHarness:case("the stick, like the D-pad, leaves a stop under a non-interactable ancestor alone", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::the stick, like the D-pad, leaves a stop under a non-interactable ancestor alone",
			run = function()
				local value = Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Holder" { UI.Stepper("A")({ value = value, max = 10 }) }
				end)
				w.gui.SelectedObject = w.find("A")
				w.find("Holder").Interactable = false
				w.press("DPadRight")
				w.stick(1, 0)
				Verify.expect((value:peek())):toBe(3)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a press whose release was lost does not block the D-pad after the action switches off and on",
			{
				id = "native_focus_stops::an adjustable claims its axis on its own stop only::a press whose release was lost does not block the D-pad after the action switches off and on",
				run = function()
					local value = Compose.cell(3)
					local w = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame "Holder" { UI.Stepper("A")({ value = value, max = 10 }) }
					end)
					w.gui.SelectedObject = w.find("A")
					Verify.expect((w.action("IncreaseArrow"))):toBe(true)
					Verify.expect((value:peek())):toBe(4)
					w.find("Holder").Interactable = false
					w.find("Holder").Interactable = true
					w.press("DPadRight")
					Verify.expect((value:peek())):toBe(5)
					w.stop()
				end,
			}
		)

		verifyHarness:case("only a navigation gamepad's stick adjusts the selection", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::only a navigation gamepad's stick adjusts the selection",
			run = function()
				local value = Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Stepper("A")({ value = value, max = 10 }) })
				end)
				local E = w.engine.types.Enum
				local function push(pad: any, x: number)
					w.input.InputChanged:Fire({
						KeyCode = E.KeyCode.Thumbstick1,
						UserInputType = pad,
						Position = w.engine.types.Vector3.new(x, 0, 0),
					}, true)
				end
				w.gui.SelectedObject = w.find("A")
				push(E.UserInputType.Gamepad2, 1)
				Verify.expect((value:peek())):toBe(3)
				w.stick(1, 0)
				Verify.expect((value:peek())):toBe(4)
				w.stickEnded()
				w.input.GetNavigationGamepads = function()
					return { E.UserInputType.Gamepad2 }
				end
				w.stick(1, 0)
				Verify.expect((value:peek())):toBe(4)
				push(E.UserInputType.Gamepad2, 0)
				push(E.UserInputType.Gamepad2, 1)
				Verify.expect((value:peek())):toBe(5)
				push(E.UserInputType.Gamepad2, 0)
				w.input.GetNavigationGamepads = function()
					return {}
				end
				w.input.GetLastInputType = function()
					return E.UserInputType.Gamepad2
				end
				push(E.UserInputType.Gamepad2, 1)
				Verify.expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		verifyHarness:case("at the minimum Left changes nothing and is free for the engine; Right stays on the axis", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::at the minimum Left changes nothing and is free for the engine; Right stays on the axis",
			run = function()
				local value = Compose.cell(0)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
				end)
				local stepper = w.find("Volume")
				w.gui.SelectedObject = stepper
				Verify.expect(stepper.NextSelectionLeft):toBe(nil)
				Verify.expect(stepper.NextSelectionRight):toBe(stepper)
				Verify.expect(stepper.NextSelectionUp):toBe(nil)
				w.press("DPadLeft")
				Verify.expect((value:peek())):toBe(0)
				w.press("DPadRight")
				Verify.expect((value:peek())):toBe(1)
				Verify.expect(stepper.NextSelectionLeft):toBe(stepper)
				w.gui.SelectedObject = nil
				Verify.expect(stepper.NextSelectionLeft):toBe(nil)
				w.stop()
			end,
		})
		verifyHarness:case("the stick adjusts on the control's axis and repeats only while held", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::the stick adjusts on the control's axis and repeats only while held",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
				end)
				w.gui.SelectedObject = w.find("Volume")
				w.stick(-0.9, 0.1)
				Verify.expect((value:peek())):toBe(4)
				w.stick(-0.95, 0)
				Verify.expect((value:peek())):toBe(4)
				w.stick(0, 0)
				w.stick(0.2, 0.9)
				Verify.expect((value:peek())):toBe(4)
				w.stick(0.8, 0)
				Verify.expect((value:peek())):toBe(5)
				Verify.expect(engineLib.connections(w.engine.heartbeat) > 0):toBe(true)
				w.stick(0, 0)
				Verify.expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a vertical adjustable takes the stick's Y axis", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a vertical adjustable takes the stick's Y axis",
			run = function()
				local value = Compose.cell(50)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Slider("Rear")({ value = value, min = 0, max = 100, step = 10, axis = "y" :: "y" }),
					})
				end)
				w.gui.SelectedObject = w.find("Rear")
				w.stick(0, 0.9)
				Verify.expect((value:peek())):toBe(60)
				w.stop()
			end,
		})

		verifyHarness:case("a held push that wobbles around half-way steps once, then repeats on the repeat timer", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a held push that wobbles around half-way steps once, then repeats on the repeat timer",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 20 }) })
				end)
				w.gui.SelectedObject = w.find("Volume")
				for _, x in { 0.51, 0.49, 0.51, 0.45, 0.52, 0.4, 0.51 } do
					w.stick(x, 0.01)
				end
				Verify.expect((value:peek())):toBe(6)
				w.engine.heartbeat:Fire(0.41)
				Verify.expect((value:peek())):toBe(7)
				w.stick(0.3, 0)
				Verify.expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
				for _, push in { { 0.6, 0.59 }, { 0.59, 0.6 }, { 0.6, 0.59 }, { 0.62, 0.6 } } do
					w.stick(push[1], push[2])
				end
				Verify.expect((value:peek())):toBe(7)
				w.stick(0, 0)
				w.stick(-0.9, 0)
				Verify.expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		verifyHarness:case("a stick already pushed when the selection lands waits for a release first", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a stick already pushed when the selection lands waits for a release first",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 20 }) })
				end)
				local E = w.engine.types.Enum
				w.input.GetGamepadState = function()
					return { { KeyCode = E.KeyCode.Thumbstick1, Position = { Magnitude = 0.9 } } }
				end
				w.gui.SelectedObject = w.find("Volume")
				w.stick(0.9, 0)
				w.stick(0.8, 0)
				Verify.expect((value:peek())):toBe(5)
				w.stick(0, 0)
				w.stick(0.9, 0)
				Verify.expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a stick that arrived mostly across the axis adjusts once it rolls onto the axis, without centring",
			{
				id = "native_focus_stops::an adjustable claims its axis on its own stop only::a stick that arrived mostly across the axis adjusts once it rolls onto the axis, without centring",
				run = function()
					local value = Compose.cell(5)
					local w = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 20 }) })
					end)
					local E = w.engine.types.Enum
					w.input.GetGamepadState = function()
						return { { KeyCode = E.KeyCode.Thumbstick1, Position = { Magnitude = 0.98 } } }
					end
					w.gui.SelectedObject = w.find("Volume")
					for _, push in { { 0.4, 0.9 }, { 0.7, 0.6 }, { 0.95, 0.1 } } do
						w.stick(push[1], push[2])
					end
					Verify.expect((value:peek())):toBe(6)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a busy UI.adjustable keeps its stop and ignores presses until it is idle", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a busy UI.adjustable keeps its stop and ignores presses until it is idle",
			run = function()
				local steps, busy = {}, Compose.cell(false)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local dial = Host.Frame({ Name = "Dial" })
					UI.adjustable(dial, {
						busy = busy,
						onAdjust = function(direction)
							table.insert(steps, direction)
						end,
					})
					return dial
				end)
				local dial = w.find("Dial")
				w.gui.SelectedObject = dial
				busy:set(true)
				Verify.expect(`{dial.Selectable} {dial:GetAttribute("disabled")}`):toBe("true false")
				w.press("DPadRight")
				Verify.expect(#steps):toBe(0)
				busy:set(false)
				w.press("DPadRight")
				Verify.expect(steps):toEqual({ 1 })
				w.stop()
			end,
		})

		verifyHarness:case(
			"the stick is read from UserInputService: no input context, other sticks and unselected stops ignored",
			{
				id = "native_focus_stops::an adjustable claims its axis on its own stop only::the stick is read from UserInputService: no input context, other sticks and unselected stops ignored",
				run = function()
					local value = Compose.cell(5)
					local w = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
					end)
					w.stick(-1, 0)
					w.stickEnded()
					Verify.expect((value:peek())):toBe(5)
					w.gui.SelectedObject = w.find("Volume")
					Verify.expect((w.find("FacetStickAdjust", w.parent))):toBe(nil)
					w.stick(-1, 0, "Thumbstick2")
					Verify.expect((value:peek())):toBe(5)
					w.stick(-1, 0)
					Verify.expect((value:peek())):toBe(4)
					w.stickEnded()
					Verify.expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
					w.stick(-1, 0)
					Verify.expect((value:peek())):toBe(3)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a row swipe ends without opening its tray when the detector switches off mid-drag", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a row swipe ends without opening its tray when the detector switches off mid-drag",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.RowActions({
						content = Host.TextLabel({ Text = "Row" }) :: GuiObject,
						trailing = {
							{ id = "Save", label = "Save", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					})
				end)
				local E, V = w.engine.types.Enum, w.engine.types.Vector2
				w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				w.screen:GetChildren()[1].AbsoluteSize = V.new(400, 44)
				local detector = w.screen:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V.new(300, 10))
				detector.DragContinue:Fire(V.new(100, 10))
				w.input.PreferredInput = E.PreferredInput.Gamepad
				detector.DragEnd:Fire()
				Verify.expect(w.find("DismissTray").Visible):toBe(false)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("focus ring part", function()
		local function ringWorld(scaled: boolean)
			local w = setup(function(_, Host: RobloxHost)
				local row = Host.Frame({
					Name = "Row",
					Selectable = true,
					Host.Frame({ Name = "Track", Host.Frame({ Name = "Knob" }) }),
				})
				return if scaled then Host.Frame({ Host.UIScale({ Scale = 0.5 }) :: unknown, row }) else row
			end)
			local playerGui = w.engine.new("PlayerGui")
			local stopRing = Facet.Roblox.createRuntime(w.engine).mount(function()
				return w.UI.focusRing(playerGui)
			end, playerGui)
			return w, playerGui, stopRing
		end

		verifyHarness:case("draws on FacetFocusPart and follows it", {
			id = "native_focus_stops::focus ring part::draws on FacetFocusPart and follows it",
			run = function()
				local w, playerGui, stopRing = ringWorld(false)
				local V2 = w.engine.types.Vector2
				local row, knob = w.find("Row"), w.find("Knob")
				row.AbsolutePosition = V2.new(100, 100)
				row.AbsoluteSize = V2.new(600, 60)
				knob.AbsolutePosition = V2.new(300, 110)
				knob.AbsoluteSize = V2.new(44, 44)
				row:SetAttribute("FacetFocusPart", "Track/Knob")
				w.gui.SelectedObject = row
				local image = playerGui.SelectionImageObject
				Verify.expect(image.Position.X.Scale * 600):toBeCloseTo(200, 1e-4)
				Verify.expect(image.Position.X.Offset):toBe(-2)
				Verify.expect(image.Size.X.Scale * 600):toBeCloseTo(44, 1e-4)
				Verify.expect(image.Size.X.Offset):toBe(4)
				knob.AbsolutePosition = V2.new(320, 110)
				Verify.expect(image.Position.X.Scale * 600):toBeCloseTo(220, 1e-4)
				stopRing()
				w.stop()
			end,
		})

		verifyHarness:case("draws on an ancestor named with .. and covers it", {
			id = "native_focus_stops::focus ring part::draws on an ancestor named with .. and covers it",
			run = function()
				local w, playerGui, stopRing = ringWorld(false)
				local V2 = w.engine.types.Vector2
				local row, knob = w.find("Row"), w.find("Knob")
				row.AbsolutePosition = V2.new(100, 100)
				row.AbsoluteSize = V2.new(600, 60)
				knob.AbsolutePosition = V2.new(300, 110)
				knob.AbsoluteSize = V2.new(44, 44)
				knob.Selectable = true
				knob:SetAttribute("FacetFocusPart", "../..")
				w.gui.SelectedObject = knob
				local image = playerGui.SelectionImageObject
				Verify.expect(image.Position.X.Scale * 44):toBeCloseTo(-200, 1e-4)
				Verify.expect(image.Size.X.Scale * 44):toBeCloseTo(600, 1e-4)
				Verify.expect(image.Size.Y.Scale * 44):toBeCloseTo(60, 1e-4)
				stopRing()
				w.stop()
			end,
		})

		verifyHarness:case("a framed field's text box rings its whole plate, icon and all", {
			id = "native_focus_stops::focus ring part::a framed field's text box rings its whole plate, icon and all",
			run = function()
				local w = setup(function(UI: FacetControls)
					return UI.TextInput({
						value = Compose.cell(""),
						presentation = "search" :: "search",
						controlSize = "compact" :: "compact",
						clearButton = true,
					})
				end)
				local input = w.find("Input")
				local box = input:FindFirstChildWhichIsA("TextBox", true)
				local path = box:GetAttribute("FacetFocusPart")
				Verify.expect((type(path))):toBe("string")
				local at = box
				for name in string.gmatch(path, "[^/]+") do
					at = if name == ".." then at.Parent else at:FindFirstChild(name)
				end
				Verify.expect(at):toBe(input)
				Verify.expect(input:FindFirstChild("SearchIcon", true) ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case(
			"stays on the part under a parent UIScale because it is placed in the stop's own proportions",
			{
				id = "native_focus_stops::focus ring part::stays on the part under a parent UIScale because it is placed in the stop's own proportions",
				run = function()
					local w, playerGui, stopRing = ringWorld(true)
					local V2 = w.engine.types.Vector2
					local row, knob = w.find("Row"), w.find("Knob")
					row.AbsolutePosition = V2.new(50, 50)
					row.AbsoluteSize = V2.new(300, 30)
					knob.AbsolutePosition = V2.new(150, 55)
					knob.AbsoluteSize = V2.new(22, 22)
					row:SetAttribute("FacetFocusPart", "Track/Knob")
					w.gui.SelectedObject = row
					local image = playerGui.SelectionImageObject
					Verify.expect(image.Size.X.Scale * row.AbsoluteSize.X):toBeCloseTo(knob.AbsoluteSize.X, 1e-4)
					Verify.expect(image.Size.Y.Scale * row.AbsoluteSize.Y):toBeCloseTo(knob.AbsoluteSize.Y, 1e-4)
					Verify.expect(image.Position.X.Scale * row.AbsoluteSize.X):toBeCloseTo(100, 1e-4)
					Verify.expect(image.Position.Y.Scale * row.AbsoluteSize.Y):toBeCloseTo(5, 1e-4)
					stopRing()
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("the Slider is one stop", function()
		for _, variant: { label: string?, thumb: string?, row: { title: string }?, axis: "y"? } in
			{
				{ label = "Boost" },
				{ label = "Boost", thumb = "auto" },
				{ row = { title = "Boost" } },
				{ axis = "y" :: "y", label = "Rear" },
			} :: { { label: string?, thumb: string?, row: { title: string }?, axis: "y"? } }
		do
			verifyHarness:case(
				`one stop for {variant.axis or "horizontal"} {if variant.row then "row" else variant.thumb or "always"}`,
				{
					id = "native_focus_stops::"
						.. "the Slider is one stop"
						.. "::"
						.. `one stop for {variant.axis or "horizontal"} {if variant.row
							then "row"
							else variant.thumb or "always"}`,
					run = function()
						local value = Compose.cell(30)
						local spec: { [any]: any } = { value = value, min = 0, max = 100, step = 5 }
						for key, field in variant do
							spec[key] = field
						end
						local w = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({ UI.Slider("S")(spec) })
						end)
						local slider = w.find("S")
						Verify.expect(slider.Selectable):toBe(true)
						Verify.expect((selectableInside(slider))):toEqual({})
						Verify.expect((slider:HasTag("facet-adjustable"))):toBe(true)
						Verify.expect((slider:GetAttribute("axis")))
							:toBe(if variant.axis == "y" then "vertical" else "horizontal")
						local part = slider:GetAttribute("FacetFocusPart")
						Verify.expect((type(part))):toBe("string")
						w.gui.SelectedObject = slider
						w.press(if variant.axis == "y" then "DPadUp" else "DPadRight")
						Verify.expect((value:peek())):toBe(35)
						w.stop()
					end,
				}
			)
		end
	end)

	verifyHarness:suite("M1: the Stepper", function()
		verifyHarness:case(
			"M1 is one stop: Left and the stick change it, the buttons are not stops, Up and Down leave",
			{
				id = "native_focus_stops::M1: the Stepper::M1 is one stop: Left and the stick change it, the buttons are not stops, Up and Down leave",
				run = function()
					local value = Compose.cell(6)
					local w = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
					end)
					local stepper = w.find("Volume")
					Verify.expect((selectableInside(stepper))):toEqual({})
					Verify.expect(stepper.Selectable):toBe(true)
					w.gui.SelectedObject = stepper
					w.press("DPadLeft")
					Verify.expect((value:peek())):toBe(5)
					w.stick(-1, 0)
					w.stick(0, 0)
					Verify.expect((value:peek())):toBe(4)
					Verify.expect(stepper.NextSelectionUp):toBe(nil)
					Verify.expect(stepper.NextSelectionDown):toBe(nil)
					w.find("Increase", stepper).Activated:Fire()
					Verify.expect((value:peek())):toBe(5)
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("the range Slider is one stop", function()
		verifyHarness:case("Return does not switch the handle while a TextBox has the keyboard", {
			id = "native_focus_stops::the range Slider is one stop::Return does not switch the handle while a TextBox has the keyboard",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Slider("Tilt")({
							value = Compose.cell({ lower = 20, upper = 60 }),
							range = true :: true,
							min = 0,
							max = 100,
						}),
					})
				end)
				local slider = w.find("Tilt")
				w.gui.SelectedObject = slider
				local box = w.engine.new("TextBox")
				w.input.GetFocusedTextBox = function()
					return box
				end
				w.action("SwitchThumb")
				Verify.expect((slider:GetAttribute("adjusting"))):toBe("lower")
				w.input.GetFocusedTextBox = function()
					return nil
				end
				w.action("SwitchThumb")
				Verify.expect((slider:GetAttribute("adjusting"))):toBe("upper")
				w.stop()
			end,
		})

		verifyHarness:case("Return switches the handle even beside a dialog's default button", {
			id = "native_focus_stops::the range Slider is one stop::Return switches the handle even beside a dialog's default button",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Slider("Tilt")({
							value = Compose.cell({ lower = 20, upper = 60 }),
							range = true :: true,
							min = 0,
							max = 100,
						}) :: unknown,
						UI.Button("Save")({
							label = "Save",
							dialogAction = "default" :: "default",
							onActivate = function() end,
						}),
					})
				end)
				w.gui.SelectedObject = w.find("Tilt")
				local best, bestPriority = nil, -math.huge
				for _, context in w.parent:GetDescendants() do
					if context:IsA("InputContext") and context.Enabled then
						for _, action in context:GetChildren() do
							for _, binding in action:GetChildren() do
								if
									binding.KeyCode == w.engine.types.Enum.KeyCode.Return
									and context.Priority > bestPriority
								then
									best, bestPriority = action.Name, context.Priority
								end
							end
						end
					end
				end
				Verify.expect(best):toBe("SwitchThumb")
				w.stop()
			end,
		})

		verifyHarness:case("lands on the lower handle, A switches, arrows and stick move the adjusted handle", {
			id = "native_focus_stops::the range Slider is one stop::lands on the lower handle, A switches, arrows and stick move the adjusted handle",
			run = function()
				local value = Compose.cell({ lower = 20, upper = 60 })
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Slider("Tilt")({ value = value, range = true :: true, min = 0, max = 100, step = 5 }),
					})
				end)
				local slider = w.find("Tilt")
				Verify.expect(slider.Selectable):toBe(true)
				Verify.expect((selectableInside(slider))):toEqual({})
				w.gui.SelectedObject = slider
				Verify.expect((slider:GetAttribute("adjusting"))):toBe("lower")
				Verify.expect(string.find(slider:GetAttribute("FacetFocusPart"), "HandleLower", 1, true) ~= nil)
					:toBe(true)
				w.press("DPadRight")
				Verify.expect(value:peek().lower):toBe(25)
				local names = {}
				for _, binding in w.find("FacetSwitchThumb", w.parent):FindFirstChild("SwitchThumb"):GetChildren() do
					table.insert(names, binding.KeyCode.Name)
				end
				table.sort(names)
				Verify.expect(names):toEqual({ "ButtonA", "Return" })
				Verify.expect((w.action("SwitchThumb"))):toBe(true)
				Verify.expect((slider:GetAttribute("adjusting"))):toBe("upper")
				Verify.expect(string.find(slider:GetAttribute("FacetFocusPart"), "HandleUpper", 1, true) ~= nil)
					:toBe(true)
				w.stick(1, 0)
				w.stick(0, 0)
				Verify.expect(value:peek().upper):toBe(65)
				Verify.expect((w.action("SwitchThumb"))):toBe(true)
				Verify.expect((slider:GetAttribute("adjusting"))):toBe("lower")
				Verify.expect((w.action("SwitchThumb"))):toBe(true)
				w.gui.SelectedObject = nil
				w.gui.SelectedObject = slider
				Verify.expect((slider:GetAttribute("adjusting"))):toBe("lower")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("other adjustables are one stop", function()
		verifyHarness:case("Rating and LevelPicker hold no selectable part", {
			id = "native_focus_stops::other adjustables are one stop::Rating and LevelPicker hold no selectable part",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Rating("Stars")({ value = Compose.cell(2), count = 5 }) :: unknown,
						UI.LevelPicker("Level")({ value = Compose.cell(1), count = 4 }),
					})
				end)
				for _, name in { "Stars", "Level" } do
					local root = w.find(name)
					Verify.expect(root.Selectable):toBe(true)
					Verify.expect((selectableInside(root))):toEqual({})
				end
				w.stop()
			end,
		})

		verifyHarness:case("UI.adjustable makes its node the stop", {
			id = "native_focus_stops::other adjustables are one stop::UI.adjustable makes its node the stop",
			run = function()
				local steps = {}
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local node = Host.Frame({ Name = "Dial" })
					UI.adjustable(node, {
						onAdjust = function(direction)
							table.insert(steps, direction)
						end,
					})
					return node
				end)
				local dial = w.find("Dial")
				Verify.expect(dial.Selectable):toBe(true)
				w.gui.SelectedObject = dial
				w.press("DPadLeft")
				w.stick(1, 0)
				w.stick(0, 0)
				Verify.expect(steps):toEqual({ -1, 1 })
				w.stop()
			end,
		})
	end)

	local function load(kind, name: string)
		return requireDynamic(
			"../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name
		)
	end

	local catalogue = require("../examples/gallery/client/demo_picker")
	local gallery = require("../examples/gallery/client/screen")

	verifyHarness:suite("every Showcase value control is one stop", function()
		local function check(label: string, build: (any) -> any) end
		for _, demo in catalogue.list() do
			check("lint " .. demo.id, function(ctx)
				return load(demo.kind, demo.module).build(ctx)
			end)
		end
		for _, groupName in { "all_controls", "collections", "motion_layout" } do
			for _, section in load("fixture", groupName).groups do
				for _, tab in section.tabs do
					check(`lint {groupName}/{section.id}/{tab.id}`, function(ctx)
						return tab.scenario.build(ctx)
					end)
				end
			end
		end
	end)

	return nil
end
