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
	function world.stick(x: number, y: number)
		local context = world.find("FacetStickAdjust", parent)
		assert(context and context.Enabled, "the stick adjust context is live")
		context:FindFirstChild("StickAdjust").StateChanged.fire(engine.types.Vector2.new(x, y))
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

	t.it("the stick context does not sink, so the engine still moves on the other axis", function()
		local w = setup(function(UI, Host)
			return Host.Frame({ UI.Stepper("Volume")({ value = Compose.cell(5), max = 10 }) })
		end)
		w.gui.SelectedObject = w.find("Volume")
		t.expect(w.find("FacetStickAdjust", w.parent).Sink).toBe(false)
		w.stop()
	end)
end)

t.describe("focus ring part", function()
	t.it("draws on FacetFocusPart and follows it", function()
		local w = setup(function(_, Host)
			return Host.Frame({
				Name = "Row",
				Selectable = true,
				Host.Frame({ Name = "Track", Host.Frame({ Name = "Knob" }) }),
			})
		end)
		local playerGui = w.engine.new("PlayerGui")
		local ring
		local stopRing = Facet.Roblox.createRuntime(w.engine).mount(function()
			ring = w.UI.focusRing(playerGui)
			return ring
		end, playerGui)
		local row, knob = w.find("Row"), w.find("Knob")
		row.AbsolutePosition = w.engine.types.Vector2.new(100, 100)
		knob.AbsolutePosition = w.engine.types.Vector2.new(300, 110)
		knob.AbsoluteSize = w.engine.types.Vector2.new(44, 44)
		row:SetAttribute("FacetFocusPart", "Track/Knob")
		w.gui.SelectedObject = row
		local image = playerGui.SelectionImageObject
		t.expect(image.Position.X.Offset).toBe(198)
		t.expect(image.Size.X.Offset).toBe(48)
		knob.AbsolutePosition = w.engine.types.Vector2.new(320, 110)
		t.expect(image.Position.X.Offset).toBe(218)
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

return nil
