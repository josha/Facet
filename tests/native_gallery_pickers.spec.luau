--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local expect = t.expect

local function scenario(name: string): any
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local guiService = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		inputTarget = engine.new("Folder"),
		worldTarget = engine.new("Folder"),
		guiService = guiService,
		runService = { Heartbeat = engine.heartbeat },
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				guiService = guiService,
				services = { GuiService = guiService, UserInputService = input },
			} :: any
		),
	}
	local built: any
	local target = engine.new("ScreenGui")
	local stop, node = runtime.mount(function()
		built = require("../examples/gallery/scenarios/" .. name).build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return built.screen()
	end, target)
	return { built = built, node = node, stop = stop, engine = engine, runtime = runtime, target = target }
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

t.describe("native gallery pickers and fields", function()
	t.it("the Writing tab shows the field chrome, units, arithmetic, scrub, read-only and line-count fields", function()
		local s = scenario("text_controls")
		local steps = s.built.steps
		local named = steps.nameError()
		expect(`{named.error} {named.errorMark} {named.trailing}`).toBe("That name is taken. true true")
		expect(find(find(s.node, "Handle"), "Title").Text).toBe("Display name *")
		find(find(s.node, "Handle"), "Paste").Activated.fire()
		expect(s.built.report().handle).toBe("Ada Lovelace")
		expect(s.built.report().pasted).toBe(1)
		local lines = steps.briefLines()
		expect(lines.before ~= nil and lines.before == lines.after).toBe(true)
		local fee = steps.stepFee()
		expect(`{fee.value} {fee.draft} {fee.committed} {fee.buttons}`).toBe("8 8.00 8 (submit) true")
		local join = find(find(s.node, "JoinCode"), "Field")
		expect(join.TextEditable).toBe(false)
		expect(join.Selectable).toBe(true)
		local speed = find(find(s.node, "Speed"), "Field")
		expect(speed:GetAttribute("selectOnFocus")).toBe("all")
		local laps = find(s.node, "Laps")
		find(laps, "Increment").Activated.fire()
		expect(s.built.report().laps).toBe(4)
		expect(find(laps, "Increment"):HasTag("facet-stepper-button")).toBe(true)
		steps.disable()
		expect(find(laps, "Increment").Interactable).toBe(false)
		expect(find(find(s.node, "Handle"), "Label").Interactable).toBe(false)
		s.stop()
		expect(#s.target:GetChildren()).toBe(0)
	end)

	t.it(
		"the Basics tab shows the slider shapes: a band, a turned band, a vertical track, auto, none and a knob",
		function()
			local s = scenario("adaptive_controls")
			local steps = s.built.steps
			local band = find(s.node, "LapWindow")
			expect(find(band, "HandleLower") ~= nil and find(band, "HandleUpper") ~= nil).toBe(true)
			expect(steps.sliderBand().band).toBe("2-18")
			expect(find(band, "Value").Text).toBe("2 – 18")
			local tilt = find(find(s.node, "Tilt"), "Track")
			expect(tilt.Rotation).toBe(0)
			expect(steps.sliderTilt().degrees).toBe(45)
			expect(tilt.Rotation).toBe(45)
			local rear = find(s.node, "Balance")
			expect(find(rear, "Track").Size.Y.Scale).toBe(1)
			local before = find(rear, "Thumb").Position.Y.Scale
			expect(steps.sliderAxis().rear).toBe(90)
			expect(find(rear, "Thumb").Position.Y.Scale < before).toBe(true)
			expect(find(find(s.node, "Boost"), "Thumb").Visible).toBe(false)
			expect(find(find(s.node, "Camera"), "Thumb").Visible).toBe(false)
			expect(find(find(s.node, "Steer"), "Knob") ~= nil).toBe(true)
			s.built.reset()
			expect(s.built.report().tilt).toBe(0)
			s.stop()
			expect(#s.target:GetChildren()).toBe(0)
		end
	)

	t.it("the Buttons tab's race tags select at rest and are removed in edit mode", function()
		local s = scenario("action_controls")
		local tokens = find(s.node, "Tokens")
		local first = find(tokens, "Token")
		first.Activated.fire()
		expect(s.built.report().tokenCount).toBe(3)
		expect(first:HasTag("facet-selected")).toBe(true)
		expect(find(first, "Remove").Visible).toBe(false)
		find(s.node, "EditTags").Activated.fire()
		expect(s.built.report().editingTags).toBe(true)
		expect(find(first, "Remove").Visible).toBe(true)
		first.Activated.fire()
		expect(s.built.report().tokenCount).toBe(2)
		s.stop()
	end)

	t.it("the Choices tab shows the driver field, the race cards and the stroked lap strip", function()
		local s = scenario("selection_controls")
		local driver = find(s.node, "Driver")
		expect(find(driver, "Label").Text).toBe("Driver *")
		expect(find(driver, "Validation").Text).toBe("Who takes the wheel for this race.")
		expect(s.built.steps.driverError().error).toBe("Pick a driver to continue.")
		expect(find(driver, "Validation").Text).toBe("Pick a driver to continue.")
		expect(find(driver, "MessageMark").Visible).toBe(true)
		expect(find(driver, "Trigger").Text).toBe("Cy")
		local mode = find(s.node, "Mode")
		find(mode, "Card-sprint").Activated.fire()
		expect(s.built.report().mode).toBeNil()
		find(mode, "Card-endurance").Activated.fire()
		expect(s.built.report().mode).toBe("endurance")
		local laps = find(s.node, "Laps")
		expect(laps:HasTag("facet-segmented-stroke")).toBe(true)
		expect(find(laps, "Corners").CornerRadius.Scale).toBe(1)
		find(laps, "10").Activated.fire()
		expect(s.built.report().laps).toBe("10")
		find(driver, "Trigger").Activated.fire()
		local headings = {}
		for _, node in s.target:GetDescendants() do
			if node.Name == "SectionTitle" then
				table.insert(headings, node.Text)
			end
		end
		table.sort(headings)
		expect(table.concat(headings, " ")).toBe("Crew Rivals")
		s.stop()
	end)
	t.it("the Pickers tab commits colours and dates, and a refused proposal never paints", function()
		local s = scenario("pickers")
		local function hex(c: any): string
			return string.format(
				"#%02X%02X%02X",
				math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5),
				math.floor(c.B * 255 + 0.5)
			)
		end
		local function cells(): { any }
			local out = {}
			for _, child in find(s.target, "Swatches"):GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(out, child)
				end
			end
			table.sort(out, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			return out
		end
		for _, name in { "Accent", "Body", "Trim", "Livery", "Fog", "RaceDay", "Starts", "Window" } do
			expect(`{name} {find(s.node, name) ~= nil}`).toBe(`{name} true`)
		end
		expect(find(find(s.node, "Accent"), "Well")).toBeNil()
		expect(find(find(s.node, "Fog"), "Well")).toBeNil()
		expect(find(find(s.node, "Body"), "Title").Text).toBe("Kart body")
		expect(find(s.node, "Committed").Text).toBe("Committed: nothing yet")
		local trim = find(s.node, "Trim")
		local well = find(trim, "Well")
		expect(well:GetAttribute("label")).toBe("#FFC400")
		well.Activated.fire()
		local team = cells()
		expect(#team >= 4).toBe(true)
		team[4].Activated.fire()
		expect(s.built.report().trim).toBe("#00AA8C")
		expect(find(s.node, "Committed").Text).toBe("Committed: #00AA8C")
		expect(hex(find(find(well, "Swatch"), "Plate").BackgroundColor3)).toBe("#00AA8C")
		expect(s.built.steps.refuse().refuse).toBe(true)
		cells()[2].Activated.fire()
		expect(s.built.report().trim).toBe("#00AA8C")
		expect(hex(find(find(well, "Swatch"), "Plate").BackgroundColor3)).toBe("#00AA8C")
		expect(s.built.report().raceDay).toBe("10/04/2026")
		expect(find(find(s.node, "RaceDay"), "Field") ~= nil).toBe(true)
		s.stop()
		expect(#s.target:GetChildren()).toBe(0)
	end)
end)
