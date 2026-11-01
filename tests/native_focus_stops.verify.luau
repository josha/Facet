--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local InputProps = require("../src/ui/input_props")
local InputTypes = require("../src/ui/input_types")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type Attributes = typeof(require("@repo/tools/typecheck/aliases").Attributes)
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local requireDynamic = require :: (any) -> any

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose = require("../src/vendor/compose/core")

	local function setup(build: (FacetControls, RobloxHost) -> Compose.Node, options: { [string]: any }?): any
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
		local Host = Facet.host(runtime)
		local stop, screen: any = runtime.mount(function()
			return Host.ScreenGui {
				build(UI, Host),
			}
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

	describe("an adjustable claims its axis on its own stop only", function()
		it("a selected child of a Stepper does not pin its own links", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a selected child of a Stepper does not pin its own links",
			run = function()
				local value = Compose.cell(6)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 10 } }
				end)
				local stepper = w.find("Volume")
				expect((stepper:HasTag("facet-adjustable"))):toBe(true)
				local plus = w.find("Increase", stepper)
				w.gui.SelectedObject = plus
				expect(plus.NextSelectionLeft):toBe(nil)
				expect(plus.NextSelectionRight):toBe(nil)
				w.press("DPadLeft")
				expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		it("at a limit the stop frees that direction for the engine; a held press stops at the limit", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::at a limit the stop frees that direction for the engine; a held press stops at the limit",
			run = function()
				local left, right = Compose.cell(8), Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Stepper "A" { value = left, max = 10 },
						UI.Stepper "B" { value = right, max = 10 },
					}
				end)
				local V = w.engine.types.Vector2
				local a, b = w.find("A"), w.find("B")
				w.engine.environment.poke(FixtureRoblox.assertInstance(a), "AbsolutePosition", V.new(0, 0))
				w.engine.environment.poke(FixtureRoblox.assertInstance(a), "AbsoluteSize", V.new(200, 44))
				w.engine.environment.poke(FixtureRoblox.assertInstance(b), "AbsolutePosition", V.new(220, 0))
				w.engine.environment.poke(FixtureRoblox.assertInstance(b), "AbsoluteSize", V.new(200, 44))
				w.gui.SelectedObject = a
				w.stick(1, 0)
				expect((left:peek())):toBe(9)
				for _ = 1, 6 do
					w.engine.heartbeat:Fire(0.41)
				end
				expect((left:peek())):toBe(10)
				expect(w.gui.SelectedObject):toBe(a)
				w.stickEnded()
				expect(a.NextSelectionRight):toBe(nil)
				expect(a.NextSelectionLeft):toBe(a)
				w.press("DPadRight")
				expect((left:peek())):toBe(10)
				w.gui.SelectedObject = b
				expect(b.NextSelectionLeft):toBe(b)
				expect(b.NextSelectionRight):toBe(b)
				w.press("DPadLeft")
				w.press("DPadLeft")
				w.press("DPadLeft")
				expect((right:peek())):toBe(0)
				expect(w.gui.SelectedObject):toBe(b)
				expect(b.NextSelectionLeft):toBe(nil)
				expect(b.NextSelectionRight):toBe(b)
				w.stop()
			end,
		})

		local function pair(w: any, extra: any?): (any, any)
			local V = w.engine.types.Vector2
			local a, b = w.find("A"), w.find("B")
			w.engine.environment.poke(FixtureRoblox.assertInstance(a), "AbsolutePosition", V.new(0, 0))
			w.engine.environment.poke(FixtureRoblox.assertInstance(a), "AbsoluteSize", V.new(200, 44))
			w.engine.environment.poke(FixtureRoblox.assertInstance(b), "AbsolutePosition", V.new(220, 0))
			w.engine.environment.poke(FixtureRoblox.assertInstance(b), "AbsoluteSize", V.new(200, 44))
			return a, b
		end

		it("R1 and Period at the maximum keep the selection and the value; only a direction passes on", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::R1 and Period at the maximum keep the selection and the value; only a direction passes on",
			run = function()
				local left, right = Compose.cell(10), Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Stepper "A" { value = left, max = 10 },
						UI.Stepper "B" { value = right, max = 10 },
					}
				end)
				local a = pair(w)
				w.gui.SelectedObject = a
				expect((w.action("Increase"))):toBe(true)
				expect(w.gui.SelectedObject):toBe(a)
				expect((left:peek())):toBe(10)
				expect((right:peek())):toBe(3)
				w.stop()
			end,
		})

		it("at a limit the stop keeps the game's own NextSelection link, so the engine moves the selection", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::at a limit the stop keeps the game's own NextSelection link, so the engine moves the selection",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Stepper "A" { value = Compose.cell(10), max = 10 },
						UI.Stepper "B" { value = Compose.cell(3), max = 10 },
						UI.Button "C" { label = "C" },
					}
				end)
				local a = pair(w)
				local c = w.find("C")
				w.engine.environment.poke(
					FixtureRoblox.assertInstance(c),
					"AbsolutePosition",
					w.engine.types.Vector2.new(0, 300)
				)
				w.engine.environment.poke(
					FixtureRoblox.assertInstance(c),
					"AbsoluteSize",
					w.engine.types.Vector2.new(200, 44)
				)
				a.NextSelectionRight = c
				w.gui.SelectedObject = a
				expect(a.NextSelectionRight):toBe(c)
				expect(a.NextSelectionLeft):toBe(a)
				w.press("DPadRight")
				expect(a.NextSelectionRight):toBe(c)
				w.stop()
			end,
		})

		it("the D-pad moves through a collection row instead of adjusting a control in it", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::the D-pad moves through a collection row instead of adjusting a control in it",
			run = function()
				local inside, outside = Compose.cell(3), Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Holder" {
						Host.Frame "Row" {
							Attributes = { FacetCollectionRow = true } :: Attributes,
							UI.Rating "Stars" {
								value = inside,
								onChange = function(value: number)
									inside:set(value)
								end,
							},
						},
						UI.Stepper "Loose" { value = outside, max = 10 },
					}
				end)
				w.gui.SelectedObject = w.find("Stars")
				w.press("DPadRight")
				expect((inside:peek())):toBe(3)
				w.gui.SelectedObject = w.find("Loose")
				w.press("DPadRight")
				expect((outside:peek())):toBe(4)
				w.stop()
			end,
		})

		it("the stick, like the D-pad, leaves a stop under a non-interactable ancestor alone", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::the stick, like the D-pad, leaves a stop under a non-interactable ancestor alone",
			run = function()
				local value = Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Holder" { UI.Stepper "A" { value = value, max = 10 } }
				end)
				w.gui.SelectedObject = w.find("A")
				w.find("Holder").Interactable = false
				w.press("DPadRight")
				w.stick(1, 0)
				expect((value:peek())):toBe(3)
				w.stop()
			end,
		})

		it("a press whose release was lost does not block the D-pad after the action switches off and on", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a press whose release was lost does not block the D-pad after the action switches off and on",
			run = function()
				local value = Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Holder" { UI.Stepper "A" { value = value, max = 10 } }
				end)
				w.gui.SelectedObject = w.find("A")
				expect((w.action("IncreaseArrow"))):toBe(true)
				expect((value:peek())):toBe(4)
				w.find("Holder").Interactable = false
				w.find("Holder").Interactable = true
				w.press("DPadRight")
				expect((value:peek())):toBe(5)
				w.stop()
			end,
		})

		it("only a navigation gamepad's stick adjusts the selection", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::only a navigation gamepad's stick adjusts the selection",
			run = function()
				local value = Compose.cell(3)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "A" { value = value, max = 10 } }
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
				expect((value:peek())):toBe(3)
				w.stick(1, 0)
				expect((value:peek())):toBe(4)
				w.stickEnded()
				w.input.GetNavigationGamepads = function()
					return { E.UserInputType.Gamepad2 }
				end
				w.stick(1, 0)
				expect((value:peek())):toBe(4)
				push(E.UserInputType.Gamepad2, 0)
				push(E.UserInputType.Gamepad2, 1)
				expect((value:peek())):toBe(5)
				push(E.UserInputType.Gamepad2, 0)
				w.input.GetNavigationGamepads = function()
					return {}
				end
				w.input.GetLastInputType = function()
					return E.UserInputType.Gamepad2
				end
				push(E.UserInputType.Gamepad2, 1)
				expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		it("at the minimum Left changes nothing and is free for the engine; Right stays on the axis", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::at the minimum Left changes nothing and is free for the engine; Right stays on the axis",
			run = function()
				local value = Compose.cell(0)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 10 } }
				end)
				local stepper = w.find("Volume")
				w.gui.SelectedObject = stepper
				expect(stepper.NextSelectionLeft):toBe(nil)
				expect(stepper.NextSelectionRight):toBe(stepper)
				expect(stepper.NextSelectionUp):toBe(nil)
				w.press("DPadLeft")
				expect((value:peek())):toBe(0)
				w.press("DPadRight")
				expect((value:peek())):toBe(1)
				expect(stepper.NextSelectionLeft):toBe(stepper)
				w.gui.SelectedObject = nil
				expect(stepper.NextSelectionLeft):toBe(nil)
				w.stop()
			end,
		})
		it("the stick adjusts on the control's axis and repeats only while held", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::the stick adjusts on the control's axis and repeats only while held",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 10 } }
				end)
				w.gui.SelectedObject = w.find("Volume")
				w.stick(-0.9, 0.1)
				expect((value:peek())):toBe(4)
				w.stick(-0.95, 0)
				expect((value:peek())):toBe(4)
				w.stick(0, 0)
				w.stick(0.2, 0.9)
				expect((value:peek())):toBe(4)
				w.stick(0.8, 0)
				expect((value:peek())):toBe(5)
				expect(engineLib.connections(w.engine.heartbeat) > 0):toBe(true)
				w.stick(0, 0)
				expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
				w.stop()
			end,
		})

		it("a vertical adjustable takes the stick's Y axis", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a vertical adjustable takes the stick's Y axis",
			run = function()
				local value = Compose.cell(50)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Slider "Rear" { value = value, min = 0, max = 100, step = 10, axis = "y" :: "y" },
					}
				end)
				w.gui.SelectedObject = w.find("Rear")
				w.stick(0, 0.9)
				expect((value:peek())):toBe(60)
				w.stop()
			end,
		})

		it("a held push that wobbles around half-way steps once, then repeats on the repeat timer", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a held push that wobbles around half-way steps once, then repeats on the repeat timer",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 20 } }
				end)
				w.gui.SelectedObject = w.find("Volume")
				for _, x in { 0.51, 0.49, 0.51, 0.45, 0.52, 0.4, 0.51 } do
					w.stick(x, 0.01)
				end
				expect((value:peek())):toBe(6)
				w.engine.heartbeat:Fire(0.41)
				expect((value:peek())):toBe(7)
				w.stick(0.3, 0)
				expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
				for _, push in { { 0.6, 0.59 }, { 0.59, 0.6 }, { 0.6, 0.59 }, { 0.62, 0.6 } } do
					w.stick(push[1], push[2])
				end
				expect((value:peek())):toBe(7)
				w.stick(0, 0)
				w.stick(-0.9, 0)
				expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		it("a stick already pushed when the selection lands waits for a release first", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a stick already pushed when the selection lands waits for a release first",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 20 } }
				end)
				local E = w.engine.types.Enum
				w.input.GetGamepadState = function()
					return { { KeyCode = E.KeyCode.Thumbstick1, Position = { Magnitude = 0.9 } } }
				end
				w.gui.SelectedObject = w.find("Volume")
				w.stick(0.9, 0)
				w.stick(0.8, 0)
				expect((value:peek())):toBe(5)
				w.stick(0, 0)
				w.stick(0.9, 0)
				expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		it("a stick that arrived mostly across the axis adjusts once it rolls onto the axis, without centring", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a stick that arrived mostly across the axis adjusts once it rolls onto the axis, without centring",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 20 } }
				end)
				local E = w.engine.types.Enum
				w.input.GetGamepadState = function()
					return { { KeyCode = E.KeyCode.Thumbstick1, Position = { Magnitude = 0.98 } } }
				end
				w.gui.SelectedObject = w.find("Volume")
				for _, push in { { 0.4, 0.9 }, { 0.7, 0.6 }, { 0.95, 0.1 } } do
					w.stick(push[1], push[2])
				end
				expect((value:peek())):toBe(6)
				w.stop()
			end,
		})

		it("a busy UI.adjustable keeps its stop and ignores presses until it is idle", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a busy UI.adjustable keeps its stop and ignores presses until it is idle",
			run = function()
				local steps, busy = {}, Compose.cell(false)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local dial = Host.Frame { Name = "Dial" }
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
				expect(`{dial.Selectable} {dial:GetAttribute("disabled")}`):toBe("true false")
				w.press("DPadRight")
				expect(#steps):toBe(0)
				busy:set(false)
				w.press("DPadRight")
				expect(steps):toEqual({ 1 })
				w.stop()
			end,
		})

		it("the stick is read from UserInputService: no input context, other sticks and unselected stops ignored", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::the stick is read from UserInputService: no input context, other sticks and unselected stops ignored",
			run = function()
				local value = Compose.cell(5)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 10 } }
				end)
				w.stick(-1, 0)
				w.stickEnded()
				expect((value:peek())):toBe(5)
				w.gui.SelectedObject = w.find("Volume")
				expect((w.find("FacetStickAdjust", w.parent))):toBe(nil)
				w.stick(-1, 0, "Thumbstick2")
				expect((value:peek())):toBe(5)
				w.stick(-1, 0)
				expect((value:peek())):toBe(4)
				w.stickEnded()
				expect((engineLib.connections(w.engine.heartbeat))):toBe(0)
				w.stick(-1, 0)
				expect((value:peek())):toBe(3)
				w.stop()
			end,
		})

		it("a row swipe ends without opening its tray when the detector switches off mid-drag", {
			id = "native_focus_stops::an adjustable claims its axis on its own stop only::a row swipe ends without opening its tray when the detector switches off mid-drag",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.RowActions {
						content = Host.TextLabel { Text = "Row" } :: GuiObject,
						trailing = {
							{ id = "Save", label = "Save", onActivate = function() end } :: FixtureCollectionTypes.RowAction,
						},
					}
				end)
				local E, V = w.engine.types.Enum, w.engine.types.Vector2
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.KeyboardAndMouse)
				w.engine.environment.poke(w.screen:GetChildren()[1], "AbsoluteSize", V.new(400, 44))
				local detector = w.screen:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart:Fire(V.new(300, 10))
				detector.DragContinue:Fire(V.new(100, 10))
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.Gamepad)
				detector.DragEnd:Fire()
				expect(w.find("DismissTray").Visible):toBe(false)
				w.stop()
			end,
		})
	end)

	describe("focus ring part", function()
		local function ringWorld(scaled: boolean)
			local w = setup(function(_, Host: RobloxHost)
				local row = Host.Frame {
					Name = "Row",
					Selectable = true,
					Host.Frame { Name = "Track", Host.Frame { Name = "Knob" } },
				}
				return if scaled then Host.Frame { Host.UIScale { Scale = 0.5 }, row } else row
			end)
			local playerGui = w.engine.new("PlayerGui")
			local stopRing = Facet.Roblox.createRuntime(w.engine).mount(function()
				return w.UI.focusRing(playerGui)
			end, playerGui)
			return w, playerGui, stopRing
		end

		it("draws on FacetFocusPart and follows it", {
			id = "native_focus_stops::focus ring part::draws on FacetFocusPart and follows it",
			run = function()
				local w, playerGui, stopRing = ringWorld(false)
				local V2 = w.engine.types.Vector2
				local row, knob = w.find("Row"), w.find("Knob")
				w.engine.environment.poke(row, "AbsolutePosition", V2.new(100, 100))
				w.engine.environment.poke(row, "AbsoluteSize", V2.new(600, 60))
				w.engine.environment.poke(knob, "AbsolutePosition", V2.new(300, 110))
				w.engine.environment.poke(knob, "AbsoluteSize", V2.new(44, 44))
				row:SetAttribute("FacetFocusPart", "Track/Knob")
				w.gui.SelectedObject = row
				local image = playerGui.SelectionImageObject
				expect(image.Position.X.Scale * 600):toBeCloseTo(200, 1e-4)
				expect(image.Position.X.Offset):toBe(-2)
				expect(image.Size.X.Scale * 600):toBeCloseTo(44, 1e-4)
				expect(image.Size.X.Offset):toBe(4)
				w.engine.environment.poke(knob, "AbsolutePosition", V2.new(320, 110))
				expect(image.Position.X.Scale * 600):toBeCloseTo(220, 1e-4)
				stopRing()
				w.stop()
			end,
		})

		it("draws on an ancestor named with .. and covers it", {
			id = "native_focus_stops::focus ring part::draws on an ancestor named with .. and covers it",
			run = function()
				local w, playerGui, stopRing = ringWorld(false)
				local V2 = w.engine.types.Vector2
				local row, knob = w.find("Row"), w.find("Knob")
				w.engine.environment.poke(row, "AbsolutePosition", V2.new(100, 100))
				w.engine.environment.poke(row, "AbsoluteSize", V2.new(600, 60))
				w.engine.environment.poke(knob, "AbsolutePosition", V2.new(300, 110))
				w.engine.environment.poke(knob, "AbsoluteSize", V2.new(44, 44))
				knob.Selectable = true
				knob:SetAttribute("FacetFocusPart", "../..")
				w.gui.SelectedObject = knob
				local image = playerGui.SelectionImageObject
				expect(image.Position.X.Scale * 44):toBeCloseTo(-200, 1e-4)
				expect(image.Size.X.Scale * 44):toBeCloseTo(600, 1e-4)
				expect(image.Size.Y.Scale * 44):toBeCloseTo(60, 1e-4)
				stopRing()
				w.stop()
			end,
		})

		it("a framed field's text box rings its whole plate, icon and all", {
			id = "native_focus_stops::focus ring part::a framed field's text box rings its whole plate, icon and all",
			run = function()
				local w = setup(function(UI: FacetControls)
					local fieldProps: InputProps.TextInputCellProps = {
						value = Compose.cell(""),
						presentation = "search" :: "search",
						controlSize = "compact" :: "compact",
						clearButton = true,
					}
					return UI.TextInput(fieldProps)
				end)
				local input = w.find("Input")
				local box = input:FindFirstChildWhichIsA("TextBox", true)
				local path = box:GetAttribute("FacetFocusPart")
				expect((type(path))):toBe("string")
				local at = box
				for name in string.gmatch(path, "[^/]+") do
					at = if name == ".." then at.Parent else at:FindFirstChild(name)
				end
				expect(at):toBe(input)
				expect(input:FindFirstChild("SearchIcon", true) ~= nil):toBe(true)
				w.stop()
			end,
		})

		it("stays on the part under a parent UIScale because it is placed in the stop's own proportions", {
			id = "native_focus_stops::focus ring part::stays on the part under a parent UIScale because it is placed in the stop's own proportions",
			run = function()
				local w, playerGui, stopRing = ringWorld(true)
				local V2 = w.engine.types.Vector2
				local row, knob = w.find("Row"), w.find("Knob")
				w.engine.environment.poke(row, "AbsolutePosition", V2.new(50, 50))
				w.engine.environment.poke(row, "AbsoluteSize", V2.new(300, 30))
				w.engine.environment.poke(knob, "AbsolutePosition", V2.new(150, 55))
				w.engine.environment.poke(knob, "AbsoluteSize", V2.new(22, 22))
				row:SetAttribute("FacetFocusPart", "Track/Knob")
				w.gui.SelectedObject = row
				local image = playerGui.SelectionImageObject
				expect(image.Size.X.Scale * row.AbsoluteSize.X):toBeCloseTo(knob.AbsoluteSize.X, 1e-4)
				expect(image.Size.Y.Scale * row.AbsoluteSize.Y):toBeCloseTo(knob.AbsoluteSize.Y, 1e-4)
				expect(image.Position.X.Scale * row.AbsoluteSize.X):toBeCloseTo(100, 1e-4)
				expect(image.Position.Y.Scale * row.AbsoluteSize.Y):toBeCloseTo(5, 1e-4)
				stopRing()
				w.stop()
			end,
		})
	end)

	describe("the Slider is one stop", function()
		for _, variant: { label: string?, thumb: ("always" | "auto" | "none")?, row: InputTypes.Row?, axis: "y"? } in
			{
				{ label = "Boost" },
				{ label = "Boost", thumb = "auto" },
				{ row = { title = "Boost" } },
				{ axis = "y" :: "y", label = "Rear" },
			} :: { { label: string?, thumb: ("always" | "auto" | "none")?, row: InputTypes.Row?, axis: "y"? } }
		do
			it(
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
						local spec: InputProps.SliderCellProps = {
							value = value,
							min = 0,
							max = 100,
							step = 5,
							label = variant.label,
							thumb = variant.thumb,
							row = variant.row,
							axis = variant.axis,
						}
						local w = setup(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame { UI.Slider "S"(spec) }
						end)
						local slider = w.find("S")
						expect(slider.Selectable):toBe(true)
						expect((selectableInside(slider))):toEqual({})
						expect((slider:HasTag("facet-adjustable"))):toBe(true)
						expect((slider:GetAttribute("axis"))):toBe(
							if variant.axis == "y" then "vertical" else "horizontal"
						)
						local part = slider:GetAttribute("FacetFocusPart")
						expect((type(part))):toBe("string")
						w.gui.SelectedObject = slider
						w.press(if variant.axis == "y" then "DPadUp" else "DPadRight")
						expect((value:peek())):toBe(35)
						w.stop()
					end,
				}
			)
		end
	end)

	describe("M1: the Stepper", function()
		it("M1 is one stop: Left and the stick change it, the buttons are not stops, Up and Down leave", {
			id = "native_focus_stops::M1: the Stepper::M1 is one stop: Left and the stick change it, the buttons are not stops, Up and Down leave",
			run = function()
				local value = Compose.cell(6)
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Stepper "Volume" { value = value, max = 10 } }
				end)
				local stepper = w.find("Volume")
				expect((selectableInside(stepper))):toEqual({})
				expect(stepper.Selectable):toBe(true)
				w.gui.SelectedObject = stepper
				w.press("DPadLeft")
				expect((value:peek())):toBe(5)
				w.stick(-1, 0)
				w.stick(0, 0)
				expect((value:peek())):toBe(4)
				expect(stepper.NextSelectionUp):toBe(nil)
				expect(stepper.NextSelectionDown):toBe(nil)
				w.find("Increase", stepper).Activated:Fire()
				expect((value:peek())):toBe(5)
				w.stop()
			end,
		})
	end)

	describe("the range Slider is one stop", function()
		it("Return does not switch the handle while a TextBox has the keyboard", {
			id = "native_focus_stops::the range Slider is one stop::Return does not switch the handle while a TextBox has the keyboard",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local rangeProps: InputProps.SliderRangeProps = {
						value = Compose.cell({ lower = 20, upper = 60 }),
						range = true :: true,
						min = 0,
						max = 100,
					}
					return Host.Frame {
						UI.Slider "Tilt"(rangeProps),
					}
				end)
				local slider = w.find("Tilt")
				w.gui.SelectedObject = slider
				local box = w.engine.new("TextBox")
				w.input.GetFocusedTextBox = function()
					return box
				end
				w.action("SwitchThumb")
				expect((slider:GetAttribute("adjusting"))):toBe("lower")
				w.input.GetFocusedTextBox = function()
					return nil
				end
				w.action("SwitchThumb")
				expect((slider:GetAttribute("adjusting"))):toBe("upper")
				w.stop()
			end,
		})

		it("Return switches the handle even beside a dialog's default button", {
			id = "native_focus_stops::the range Slider is one stop::Return switches the handle even beside a dialog's default button",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local rangeProps: InputProps.SliderRangeProps = {
						value = Compose.cell({ lower = 20, upper = 60 }),
						range = true :: true,
						min = 0,
						max = 100,
					}
					return Host.Frame {
						UI.Slider "Tilt"(rangeProps),
						UI.Button "Save" {
							label = "Save",
							dialogAction = "default" :: "default",
							onActivate = function() end,
						},
					}
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
				expect(best):toBe("SwitchThumb")
				w.stop()
			end,
		})

		it("lands on the lower handle, A switches, arrows and stick move the adjusted handle", {
			id = "native_focus_stops::the range Slider is one stop::lands on the lower handle, A switches, arrows and stick move the adjusted handle",
			run = function()
				local value = Compose.cell({ lower = 20, upper = 60 })
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local rangeProps: InputProps.SliderRangeProps =
						{ value = value, range = true :: true, min = 0, max = 100, step = 5 }
					return Host.Frame {
						UI.Slider "Tilt"(rangeProps),
					}
				end)
				local slider = w.find("Tilt")
				expect(slider.Selectable):toBe(true)
				expect((selectableInside(slider))):toEqual({})
				w.gui.SelectedObject = slider
				expect((slider:GetAttribute("adjusting"))):toBe("lower")
				expect(string.find(slider:GetAttribute("FacetFocusPart"), "HandleLower", 1, true) ~= nil):toBe(true)
				w.press("DPadRight")
				expect(value:peek().lower):toBe(25)
				local names = {}
				for _, binding in w.find("FacetSwitchThumb", w.parent):FindFirstChild("SwitchThumb"):GetChildren() do
					table.insert(names, binding.KeyCode.Name)
				end
				table.sort(names)
				expect(names):toEqual({ "ButtonA", "Return" })
				expect((w.action("SwitchThumb"))):toBe(true)
				expect((slider:GetAttribute("adjusting"))):toBe("upper")
				expect(string.find(slider:GetAttribute("FacetFocusPart"), "HandleUpper", 1, true) ~= nil):toBe(true)
				w.stick(1, 0)
				w.stick(0, 0)
				expect(value:peek().upper):toBe(65)
				expect((w.action("SwitchThumb"))):toBe(true)
				expect((slider:GetAttribute("adjusting"))):toBe("lower")
				expect((w.action("SwitchThumb"))):toBe(true)
				w.gui.SelectedObject = nil
				w.gui.SelectedObject = slider
				expect((slider:GetAttribute("adjusting"))):toBe("lower")
				w.stop()
			end,
		})
	end)

	describe("other adjustables are one stop", function()
		it("Rating and LevelPicker hold no selectable part", {
			id = "native_focus_stops::other adjustables are one stop::Rating and LevelPicker hold no selectable part",
			run = function()
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Rating "Stars" { value = Compose.cell(2), count = 5 },
						UI.LevelPicker "Level" { value = Compose.cell(1), count = 4 },
					}
				end)
				for _, name in { "Stars", "Level" } do
					local root = w.find(name)
					expect(root.Selectable):toBe(true)
					expect((selectableInside(root))):toEqual({})
				end
				w.stop()
			end,
		})

		it("UI.adjustable makes its node the stop", {
			id = "native_focus_stops::other adjustables are one stop::UI.adjustable makes its node the stop",
			run = function()
				local steps = {}
				local w = setup(function(UI: FacetControls, Host: RobloxHost)
					local node = Host.Frame { Name = "Dial" }
					UI.adjustable(node, {
						onAdjust = function(direction)
							table.insert(steps, direction)
						end,
					})
					return node
				end)
				local dial = w.find("Dial")
				expect(dial.Selectable):toBe(true)
				w.gui.SelectedObject = dial
				w.press("DPadLeft")
				w.stick(1, 0)
				w.stick(0, 0)
				expect(steps):toEqual({ -1, 1 })
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

	describe("every Showcase value control is one stop", function()
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
