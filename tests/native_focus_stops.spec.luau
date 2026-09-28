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

return nil
