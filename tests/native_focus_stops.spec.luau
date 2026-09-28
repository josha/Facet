--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local function setup(build: (any, any) -> any, options: { [string]: any }?): any
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
	local parent = engine.new("Folder")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		inputParent = parent,
		motionLevel = "none",
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in options or {} do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors) })
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
		input.InputBegan.fire({
			KeyCode = (engine.types.Enum.KeyCode :: any)[key],
			UserInputType = engine.types.Enum.UserInputType.Gamepad1,
		}, true)
		input.InputEnded.fire({
			KeyCode = (engine.types.Enum.KeyCode :: any)[key],
			UserInputType = engine.types.Enum.UserInputType.Gamepad1,
		}, true)
	end
	function world.stick(x: number, y: number, key: string?)
		input.InputChanged.fire({
			KeyCode = (engine.types.Enum.KeyCode :: any)[key or "Thumbstick1"],
			UserInputType = engine.types.Enum.UserInputType.Gamepad1,
			Position = engine.types.Vector3.new(x, y, 0),
		}, true)
	end
	function world.stickEnded()
		input.InputEnded.fire({
			KeyCode = engine.types.Enum.KeyCode.Thumbstick1,
			UserInputType = engine.types.Enum.UserInputType.Gamepad1,
			Position = engine.types.Vector3.new(0, 0, 0),
		}, true)
	end
	function world.action(name: string)
		for _, node in parent:GetDescendants() do
			if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
				node:FindFirstChild(name).Pressed.fire()
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

t.describe("an adjustable claims its axis on its own stop only", function()
	t.it("a selected child of a Stepper does not pin its own links", function()
		local value = Compose.cell(6)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
		end)
		local stepper = w.find("Volume")
		t.expect(stepper:HasTag("facet-adjustable")).toBe(true)
		local plus = w.find("Increase", stepper)
		w.gui.SelectedObject = plus
		t.expect(plus.NextSelectionLeft).toBe(nil)
		t.expect(plus.NextSelectionRight).toBe(nil)
		w.press("DPadLeft")
		t.expect(value:peek()).toBe(6)
		w.stop()
	end)

	t.it("a fresh press at a limit passes to the next control that way; a held press stops at the limit", function()
		local left, right = Compose.cell(8), Compose.cell(3)
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Stepper("A")({ value = left, max = 10 }),
				UI.Stepper("B")({ value = right, max = 10 }),
			})
		end)
		local V = w.engine.types.Vector2
		local a, b = w.find("A"), w.find("B")
		a.AbsolutePosition, a.AbsoluteSize = V.new(0, 0), V.new(200, 44)
		b.AbsolutePosition, b.AbsoluteSize = V.new(220, 0), V.new(200, 44)
		w.gui.SelectedObject = a
		w.stick(1, 0)
		t.expect(left:peek()).toBe(9)
		for _ = 1, 6 do
			w.engine.heartbeat.fire(0.41)
		end
		t.expect(left:peek()).toBe(10)
		t.expect(w.gui.SelectedObject).toBe(a)
		w.stickEnded()
		w.stick(1, 0)
		t.expect(w.gui.SelectedObject).toBe(b)
		w.stickEnded()
		w.gui.SelectedObject = a
		w.press("DPadRight")
		t.expect(w.gui.SelectedObject).toBe(b)
		t.expect(right:peek()).toBe(3)
		w.press("DPadLeft")
		w.press("DPadLeft")
		w.press("DPadLeft")
		t.expect(right:peek()).toBe(0)
		t.expect(w.gui.SelectedObject).toBe(b)
		w.press("DPadLeft")
		t.expect(w.gui.SelectedObject).toBe(a)
		w.stop()
	end)

	local function pair(w: any, extra: any?): (any, any)
		local V = w.engine.types.Vector2
		local a, b = w.find("A"), w.find("B")
		a.AbsolutePosition, a.AbsoluteSize = V.new(0, 0), V.new(200, 44)
		b.AbsolutePosition, b.AbsoluteSize = V.new(220, 0), V.new(200, 44)
		return a, b
	end

	t.it("R1 and Period at the maximum keep the selection and the value; only a direction passes on", function()
		local left, right = Compose.cell(10), Compose.cell(3)
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Stepper("A")({ value = left, max = 10 }),
				UI.Stepper("B")({ value = right, max = 10 }),
			})
		end)
		local a = pair(w)
		w.gui.SelectedObject = a
		t.expect(w.action("Increase")).toBe(true)
		t.expect(w.gui.SelectedObject).toBe(a)
		t.expect(left:peek()).toBe(10)
		t.expect(right:peek()).toBe(3)
		w.stop()
	end)

	t.it("at a limit the hand-off follows the game's own NextSelection link, as focusQuery reports", function()
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Stepper("A")({ value = Compose.cell(10), max = 10 }),
				UI.Stepper("B")({ value = Compose.cell(3), max = 10 }),
				UI.Button("C")({ label = "C" }),
			})
		end)
		local a = pair(w)
		local c = w.find("C")
		c.AbsolutePosition, c.AbsoluteSize = w.engine.types.Vector2.new(0, 300), w.engine.types.Vector2.new(200, 44)
		a.NextSelectionRight = c
		w.gui.SelectedObject = a
		t.expect(w.UI.focusQuery(a).Right.target).toBe(c)
		w.press("DPadRight")
		t.expect(w.gui.SelectedObject).toBe(c)
		t.expect(a.NextSelectionRight).toBe(c)
		w.stop()
	end)

	t.it("the stick, like the D-pad, leaves a stop under a non-interactable ancestor alone", function()
		local value = Compose.cell(3)
		local w = setup(function(UI, Host)
			return Host.Frame "Holder" { UI.Stepper("A")({ value = value, max = 10 }) }
		end)
		w.gui.SelectedObject = w.find("A")
		w.find("Holder").Interactable = false
		w.press("DPadRight")
		w.stick(1, 0)
		t.expect(value:peek()).toBe(3)
		w.stop()
	end)

	t.it("only the first gamepad's stick adjusts the selection", function()
		local value = Compose.cell(3)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("A")({ value = value, max = 10 }) })
		end)
		w.gui.SelectedObject = w.find("A")
		w.input.InputChanged.fire({
			KeyCode = w.engine.types.Enum.KeyCode.Thumbstick1,
			UserInputType = w.engine.types.Enum.UserInputType.Gamepad2,
			Position = w.engine.types.Vector3.new(1, 0, 0),
		}, true)
		t.expect(value:peek()).toBe(3)
		w.stick(1, 0)
		t.expect(value:peek()).toBe(4)
		w.stop()
	end)

	t.it("keeps the axis at a bound: Left at the minimum stays and changes nothing", function()
		local value = Compose.cell(0)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
		end)
		local stepper = w.find("Volume")
		w.gui.SelectedObject = stepper
		t.expect(stepper.NextSelectionLeft).toBe(stepper)
		t.expect(stepper.NextSelectionRight).toBe(stepper)
		t.expect(stepper.NextSelectionUp).toBe(nil)
		w.press("DPadLeft")
		t.expect(value:peek()).toBe(0)
		w.press("DPadRight")
		t.expect(value:peek()).toBe(1)
		w.gui.SelectedObject = nil
		t.expect(stepper.NextSelectionLeft).toBe(nil)
		w.stop()
	end)
	t.it("the stick adjusts on the control's axis and repeats only while held", function()
		local value = Compose.cell(5)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
		end)
		w.gui.SelectedObject = w.find("Volume")
		w.stick(-0.9, 0.1)
		t.expect(value:peek()).toBe(4)
		w.stick(-0.95, 0)
		t.expect(value:peek()).toBe(4)
		w.stick(0, 0)
		w.stick(0.2, 0.9)
		t.expect(value:peek()).toBe(4)
		w.stick(0.8, 0)
		t.expect(value:peek()).toBe(5)
		t.expect(w.engine.heartbeat.count() > 0).toBe(true)
		w.stick(0, 0)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.stop()
	end)

	t.it("a vertical adjustable takes the stick's Y axis", function()
		local value = Compose.cell(50)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Slider("Rear")({ value = value, min = 0, max = 100, step = 10, axis = "y" }) })
		end)
		w.gui.SelectedObject = w.find("Rear")
		w.stick(0, 0.9)
		t.expect(value:peek()).toBe(60)
		w.stop()
	end)

	t.it("a held push that wobbles around half-way steps once, then repeats on the repeat timer", function()
		local value = Compose.cell(5)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 20 }) })
		end)
		w.gui.SelectedObject = w.find("Volume")
		for _, x in { 0.51, 0.49, 0.51, 0.45, 0.52, 0.4, 0.51 } do
			w.stick(x, 0.01)
		end
		t.expect(value:peek()).toBe(6)
		w.engine.heartbeat.fire(0.41)
		t.expect(value:peek()).toBe(7)
		w.stick(0.3, 0)
		t.expect(w.engine.heartbeat.count()).toBe(0)
		for _, push in { { 0.6, 0.59 }, { 0.59, 0.6 }, { 0.6, 0.59 }, { 0.62, 0.6 } } do
			w.stick(push[1], push[2])
		end
		t.expect(value:peek()).toBe(7)
		w.stick(0, 0)
		w.stick(-0.9, 0)
		t.expect(value:peek()).toBe(6)
		w.stop()
	end)

	t.it("a stick already pushed when the selection lands waits for a release first", function()
		local value = Compose.cell(5)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 20 }) })
		end)
		local E = w.engine.types.Enum
		w.input.GetGamepadState = function()
			return { { KeyCode = E.KeyCode.Thumbstick1, Position = { Magnitude = 0.9 } } }
		end
		w.gui.SelectedObject = w.find("Volume")
		w.stick(0.9, 0)
		w.stick(0.8, 0)
		t.expect(value:peek()).toBe(5)
		w.stick(0, 0)
		w.stick(0.9, 0)
		t.expect(value:peek()).toBe(6)
		w.stop()
	end)

	t.it("a stick that arrived mostly across the axis adjusts once it rolls onto the axis, without centring", function()
		local value = Compose.cell(5)
		local w = setup(function(UI, Host)
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
		t.expect(value:peek()).toBe(6)
		w.stop()
	end)

	t.it("a busy UI.adjustable keeps its stop and ignores presses until it is idle", function()
		local steps, busy = {}, Compose.cell(false)
		local w = setup(function(UI, Host)
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
		t.expect(`{dial.Selectable} {dial:GetAttribute("disabled")}`).toBe("true false")
		w.press("DPadRight")
		t.expect(#steps).toBe(0)
		busy:set(false)
		w.press("DPadRight")
		t.expect(steps).toEqual({ 1 })
		w.stop()
	end)

	t.it(
		"the stick is read from UserInputService: no input context, other sticks and unselected stops ignored",
		function()
			local value = Compose.cell(5)
			local w = setup(function(UI, Host)
				return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
			end)
			w.stick(-1, 0)
			w.stickEnded()
			t.expect(value:peek()).toBe(5)
			w.gui.SelectedObject = w.find("Volume")
			t.expect(w.find("FacetStickAdjust", w.parent)).toBe(nil)
			w.stick(-1, 0, "Thumbstick2")
			t.expect(value:peek()).toBe(5)
			w.stick(-1, 0)
			t.expect(value:peek()).toBe(4)
			w.stickEnded()
			t.expect(w.engine.heartbeat.count()).toBe(0)
			w.stick(-1, 0)
			t.expect(value:peek()).toBe(3)
			w.stop()
		end
	)

	t.it(
		"every value control's stop listens for SelectionGained, so the engine's D-pad ranks it with buttons",
		function()
			local w = setup(function(UI, Host)
				local dial = Host.Frame({ Name = "Dial" })
				UI.adjustable(dial, { onAdjust = function() end })
				return Host.Frame({
					UI.Slider("One")({ value = Compose.cell(3), min = 0, max = 10 }),
					UI.Slider("Two")({
						value = Compose.cell({ lower = 2, upper = 8 }),
						range = true,
						min = 0,
						max = 10,
					}),
					UI.Stepper("Three")({ value = Compose.cell(1), max = 5 }),
					dial,
				})
			end)
			local unwired = {}
			for _, node in w.screen:GetDescendants() do
				if node:HasTag("facet-adjustable") and node.SelectionGained.count() == 0 then
					table.insert(unwired, node.Name)
				end
			end
			t.expect(unwired).toEqual({})
			w.stop()
		end
	)

	t.it("a row's swipe detector switches off while the gamepad is the preferred input", function()
		local w = setup(function(UI, Host)
			return UI.RowActions({
				content = Host.TextLabel({ Text = "Row" }),
				trailing = { { id = "Save", label = "Save", onActivate = function() end } },
			})
		end)
		local detector = w.screen:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		local E = w.engine.types.Enum
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(detector.Enabled).toBe(true)
		w.input.PreferredInput = E.PreferredInput.Gamepad
		t.expect(detector.Enabled).toBe(false)
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		t.expect(detector.Enabled).toBe(true)
		w.stop()
	end)

	t.it("a slider drag ends and commits when its detector switches off mid-drag", function()
		local commits = {}
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Slider("One")({
					value = Compose.cell(3),
					min = 0,
					max = 10,
					onCommit = function(value)
						table.insert(commits, value)
					end,
				}),
			})
		end)
		local E = w.engine.types.Enum
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		local detector = w.screen:FindFirstChildWhichIsA("UIDragDetector", true)
		detector.DragStart.fire(w.engine.types.Vector2.new(10, 10))
		t.expect(#commits).toBe(0)
		w.input.PreferredInput = E.PreferredInput.Gamepad
		t.expect(#commits).toBe(1)
		detector.DragEnd.fire()
		t.expect(#commits).toBe(1)
		w.stop()
	end)

	t.it("a row swipe ends without opening its tray when the detector switches off mid-drag", function()
		local w = setup(function(UI, Host)
			return UI.RowActions({
				content = Host.TextLabel({ Text = "Row" }),
				trailing = { { id = "Save", label = "Save", onActivate = function() end } },
			})
		end)
		local E, V = w.engine.types.Enum, w.engine.types.Vector2
		w.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
		w.screen:GetChildren()[1].AbsoluteSize = V.new(400, 44)
		local detector = w.screen:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(V.new(300, 10))
		detector.DragContinue.fire(V.new(100, 10))
		w.input.PreferredInput = E.PreferredInput.Gamepad
		detector.DragEnd.fire()
		t.expect(w.find("DismissTray").Visible).toBe(false)
		w.stop()
	end)

	t.it("slider drag detectors switch off while the gamepad is the preferred input", function()
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Slider("One")({ value = Compose.cell(3), min = 0, max = 10 }),
				UI.Slider("Two")({ value = Compose.cell({ lower = 2, upper = 8 }), range = true, min = 0, max = 10 }),
			})
		end)
		local function detectors(): { boolean }
			local states = {}
			for _, node in w.screen:GetDescendants() do
				if node:IsA("UIDragDetector") then
					table.insert(states, node.Enabled)
				end
			end
			return states
		end
		t.expect(detectors()).toEqual({ true, true, true, true })
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Gamepad
		t.expect(detectors()).toEqual({ false, false, false, false })
		w.input.PreferredInput = w.engine.types.Enum.PreferredInput.Touch
		t.expect(detectors()).toEqual({ true, true, true, true })
		w.stop()
	end)
end)

t.describe("focus ring part", function()
	local function ringWorld(scaled: boolean)
		local w = setup(function(_, Host)
			local row = Host.Frame({
				Name = "Row",
				Selectable = true,
				Host.Frame({ Name = "Track", Host.Frame({ Name = "Knob" }) }),
			})
			return if scaled then Host.Frame({ Host.UIScale({ Scale = 0.5 }), row }) else row
		end)
		local playerGui = w.engine.new("PlayerGui")
		local stopRing = Facet.Roblox.createRuntime(w.engine).mount(function()
			return w.UI.focusRing(playerGui)
		end, playerGui)
		return w, playerGui, stopRing
	end

	t.it("draws on FacetFocusPart and follows it", function()
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
		t.expect(image.Position.X.Scale * 600).toBeCloseTo(200)
		t.expect(image.Position.X.Offset).toBe(-2)
		t.expect(image.Size.X.Scale * 600).toBeCloseTo(44)
		t.expect(image.Size.X.Offset).toBe(4)
		knob.AbsolutePosition = V2.new(320, 110)
		t.expect(image.Position.X.Scale * 600).toBeCloseTo(220)
		stopRing()
		w.stop()
	end)

	t.it("stays on the part under a parent UIScale because it is placed in the stop's own proportions", function()
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
		t.expect(image.Size.X.Scale * row.AbsoluteSize.X).toBeCloseTo(knob.AbsoluteSize.X)
		t.expect(image.Size.Y.Scale * row.AbsoluteSize.Y).toBeCloseTo(knob.AbsoluteSize.Y)
		t.expect(image.Position.X.Scale * row.AbsoluteSize.X).toBeCloseTo(100)
		t.expect(image.Position.Y.Scale * row.AbsoluteSize.Y).toBeCloseTo(5)
		stopRing()
		w.stop()
	end)
end)

t.describe("the Slider is one stop", function()
	for _, variant in
		{
			{ label = "Boost" },
			{ label = "Boost", thumb = "auto" },
			{ row = { title = "Boost" } },
			{ axis = "y", label = "Rear" },
		}
	do
		t.it(
			`one stop for {variant.axis or "horizontal"} {if variant.row then "row" else variant.thumb or "always"}`,
			function()
				local value = Compose.cell(30)
				local spec: { [string]: any } = { value = value, min = 0, max = 100, step = 5 }
				for key, field in variant do
					spec[key] = field
				end
				local w = setup(function(UI, Host)
					return Host.Frame({ UI.Slider("S")(spec) })
				end)
				local slider = w.find("S")
				t.expect(slider.Selectable).toBe(true)
				t.expect(selectableInside(slider)).toEqual({})
				t.expect(slider:HasTag("facet-adjustable")).toBe(true)
				t.expect(slider:GetAttribute("axis")).toBe(if variant.axis == "y" then "vertical" else "horizontal")
				local part = slider:GetAttribute("FacetFocusPart")
				t.expect(type(part)).toBe("string")
				w.gui.SelectedObject = slider
				w.press(if variant.axis == "y" then "DPadUp" else "DPadRight")
				t.expect(value:peek()).toBe(35)
				w.stop()
			end
		)
	end
end)

t.describe("M1: the Stepper", function()
	t.it("M1 is one stop: Left and the stick change it, the buttons are not stops, Up and Down leave", function()
		local value = Compose.cell(6)
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = value, max = 10 }) })
		end)
		local stepper = w.find("Volume")
		t.expect(selectableInside(stepper)).toEqual({})
		t.expect(stepper.Selectable).toBe(true)
		w.gui.SelectedObject = stepper
		w.press("DPadLeft")
		t.expect(value:peek()).toBe(5)
		w.stick(-1, 0)
		w.stick(0, 0)
		t.expect(value:peek()).toBe(4)
		t.expect(stepper.NextSelectionUp).toBe(nil)
		t.expect(stepper.NextSelectionDown).toBe(nil)
		w.find("Increase", stepper).Activated.fire()
		t.expect(value:peek()).toBe(5)
		w.stop()
	end)
end)

t.describe("the range Slider is one stop", function()
	t.it("Return does not switch the handle while a TextBox has the keyboard", function()
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Slider("Tilt")({
					value = Compose.cell({ lower = 20, upper = 60 }),
					range = true,
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
		t.expect(slider:GetAttribute("adjusting")).toBe("lower")
		w.input.GetFocusedTextBox = function()
			return nil
		end
		w.action("SwitchThumb")
		t.expect(slider:GetAttribute("adjusting")).toBe("upper")
		w.stop()
	end)

	t.it("Return switches the handle even beside a dialog's default button", function()
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Slider("Tilt")({
					value = Compose.cell({ lower = 20, upper = 60 }),
					range = true,
					min = 0,
					max = 100,
				}),
				UI.Button("Save")({ label = "Save", dialogAction = "default", onActivate = function() end }),
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
		t.expect(best).toBe("SwitchThumb")
		w.stop()
	end)

	t.it("lands on the lower handle, A switches, arrows and stick move the adjusted handle", function()
		local value = Compose.cell({ lower = 20, upper = 60 })
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Slider("Tilt")({ value = value, range = true, min = 0, max = 100, step = 5 }) })
		end)
		local slider = w.find("Tilt")
		t.expect(slider.Selectable).toBe(true)
		t.expect(selectableInside(slider)).toEqual({})
		w.gui.SelectedObject = slider
		t.expect(slider:GetAttribute("adjusting")).toBe("lower")
		t.expect(string.find(slider:GetAttribute("FacetFocusPart"), "HandleLower", 1, true) ~= nil).toBe(true)
		w.press("DPadRight")
		t.expect(value:peek().lower).toBe(25)
		local names = {}
		for _, binding in w.find("FacetSwitchThumb", w.parent):FindFirstChild("SwitchThumb"):GetChildren() do
			table.insert(names, binding.KeyCode.Name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "ButtonA", "Return" })
		t.expect(w.action("SwitchThumb")).toBe(true)
		t.expect(slider:GetAttribute("adjusting")).toBe("upper")
		t.expect(string.find(slider:GetAttribute("FacetFocusPart"), "HandleUpper", 1, true) ~= nil).toBe(true)
		w.stick(1, 0)
		w.stick(0, 0)
		t.expect(value:peek().upper).toBe(65)
		t.expect(w.action("SwitchThumb")).toBe(true)
		t.expect(slider:GetAttribute("adjusting")).toBe("lower")
		t.expect(w.action("SwitchThumb")).toBe(true)
		w.gui.SelectedObject = nil
		w.gui.SelectedObject = slider
		t.expect(slider:GetAttribute("adjusting")).toBe("lower")
		w.stop()
	end)
end)

t.describe("other adjustables are one stop", function()
	t.it("Rating and LevelPicker hold no selectable part", function()
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Rating("Stars")({ value = Compose.cell(2), count = 5 }),
				UI.LevelPicker("Level")({ value = Compose.cell(1), count = 4 }),
			})
		end)
		for _, name in { "Stars", "Level" } do
			local root = w.find(name)
			t.expect(root.Selectable).toBe(true)
			t.expect(selectableInside(root)).toEqual({})
		end
		w.stop()
	end)

	t.it("UI.adjustable makes its node the stop", function()
		local steps = {}
		local w = setup(function(UI, Host)
			local node = Host.Frame({ Name = "Dial" })
			UI.adjustable(node, {
				onAdjust = function(direction)
					table.insert(steps, direction)
				end,
			})
			return node
		end)
		local dial = w.find("Dial")
		t.expect(dial.Selectable).toBe(true)
		w.gui.SelectedObject = dial
		w.press("DPadLeft")
		w.stick(1, 0)
		w.stick(0, 0)
		t.expect(steps).toEqual({ -1, 1 })
		w.stop()
	end)
end)

t.describe("a disabled value control is not a stop, and the stop carries the name", function()
	t.it("a disabled Stepper or UI.adjustable is not selectable and becomes a stop when enabled", function()
		local on = Compose.cell(false)
		local w = setup(function(UI, Host)
			local dial = Host.Frame({ Name = "Dial" })
			UI.adjustable(dial, { enabled = on, onAdjust = function() end })
			return Host.Frame({ UI.Stepper("Volume")({ value = Compose.cell(3), max = 9, enabled = on }), dial })
		end)
		t.expect(`{w.find("Volume").Selectable} {w.find("Dial").Selectable}`).toBe("false false")
		on:set(true)
		t.expect(`{w.find("Volume").Selectable} {w.find("Dial").Selectable}`).toBe("true true")
		w.stop()
	end)

	t.it("the Slider and Stepper stops carry their accessible label", function()
		local w = setup(function(UI, Host)
			return Host.Frame({
				UI.Slider("Boost")({ value = Compose.cell(3), min = 0, max = 9, label = "Boost" }),
				UI.Slider("Row")({ value = Compose.cell(3), min = 0, max = 9, row = { title = "Music" } }),
				UI.Stepper("Volume")({ value = Compose.cell(3), max = 9, label = "Volume" }),
			})
		end)
		t.expect(w.find("Boost"):GetAttribute("AccessibleLabel")).toBe("Boost")
		t.expect(w.find("Row"):GetAttribute("AccessibleLabel")).toBe("Music")
		t.expect(w.find("Volume"):GetAttribute("AccessibleLabel")).toBe("Volume")
		w.stop()
	end)
end)

local function controlsFor(ctx)
	return Facet.controls(ctx.runtime, {
		types = ctx.types,
		viewport = ctx.viewport,
		guiService = ctx.guiService,
		motionLevel = Compose.formula(function(use)
			return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
		end),
	})
end

local function nativeContext()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local target = engine.new("Folder")
	local guiService = engine.new("GuiService")
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		guiService = guiService,
		runService = { Heartbeat = engine.heartbeat },
	}
	ctx.UI = controlsFor(ctx)
	return ctx, engine, target
end

local function load(kind, name)
	return require("../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name)
end

local catalogue = require("../examples/gallery/client/demo_picker")
local gallery = require("../examples/gallery/client/screen")

local VALUE_CONTROL_TAGS = { "facet-slider", "facet-stepper", "facet-rating", "facet-level-picker" }

local census = 0

local function offenders(root: any): { string }
	local bad = {}
	for _, node in root:GetDescendants() do
		for _, tag in VALUE_CONTROL_TAGS do
			if node:HasTag(tag) then
				census += 1
				if not node:HasTag("facet-adjustable") then
					table.insert(bad, `{node:GetFullName()} is a {tag} without facet-adjustable`)
				end
			end
		end
		if node:HasTag("facet-adjustable") and node.Interactable ~= false and node:GetAttribute("disabled") ~= true then
			if not node.Selectable then
				table.insert(bad, `{node:GetFullName()} is not a stop`)
			end
			for _, inner in node:GetDescendants() do
				if inner:IsA("GuiObject") and inner.Selectable then
					table.insert(bad, `{inner:GetFullName()} is a stop inside {node.Name}`)
				end
			end
		end
	end
	return bad
end

t.describe("the stop lint and disabled value controls", function()
	t.it("a disabled Slider, Stepper or UI.adjustable is correctly not a stop", function()
		local w = setup(function(UI, Host)
			local dial = Host.Frame({ Name = "Dial" })
			UI.adjustable(dial, { enabled = false, onAdjust = function() end })
			return Host.Frame({
				UI.Slider("S")({ value = Compose.cell(3), min = 0, max = 9, enabled = false }),
				UI.Stepper("Volume")({ value = Compose.cell(3), max = 9, enabled = false }),
				dial,
			})
		end)
		for _, name in { "S", "Volume", "Dial" } do
			t.expect(`{name} {w.find(name).Selectable} {w.find(name):GetAttribute("disabled")}`)
				.toBe(`{name} false true`)
		end
		t.expect(offenders(w.screen)).toEqual({})
		w.stop()
	end)
end)

t.describe("every Showcase value control is one stop", function()
	local function check(label: string, build: (any) -> any)
		t.it(label, function()
			local ctx, _, target = nativeContext()
			local stop, node = ctx.runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = controlsFor(ctx)
				local built = build(ctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return built.screen()
			end, target)
			local before = census
			t.expect(offenders(node)).toEqual({})
			if string.find(label, "inputs/basics", 1, true) then
				t.expect(census - before >= 4).toBe(true)
			end
			stop()
			ctx.runtime:dispose()
		end)
	end
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
