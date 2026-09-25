--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	screen: any,
	parent: any,
	shift: { down: boolean },
	step: (number) -> (),
	stop: () -> (),
}

local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local now = 0
	engine.clock = function()
		return now
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	local shift = { down = false }
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function(_, key)
		return shift.down and key == engine.types.Enum.KeyCode.LeftShift
	end
	local parent = engine.new("Folder")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		inputParent = parent,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host, engine, gui) })
	end, parent)
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		screen = screen,
		parent = parent,
		shift = shift,
		step = function(seconds: number)
			now += seconds
			engine.heartbeat.fire(seconds)
		end,
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

local function childOf(node: any, className: string): { any }
	local out = {}
	for _, child in node:GetChildren() do
		if child.ClassName == className then
			table.insert(out, child)
		end
	end
	return out
end

local function placeholders(root: any): { any }
	local out = {}
	for index = 1, 8 do
		local node = find(root, "Placeholder" .. index)
		if node then
			table.insert(out, node)
		end
	end
	return out
end

local function tab(world: World, back: boolean?)
	world.shift.down = back == true
	local traverse = find(world.parent, "FacetTraversal")
	assert(traverse, "the traversal context exists")
	traverse:FindFirstChild("Traverse").Pressed.fire()
	world.shift.down = false
end

local function selected(world: World): string
	local node = world.gui.SelectedObject
	return if node then node.Name else "nil"
end

t.describe("native parity classb themes", function()
	t.it("rounds only the circle skeleton and pauses its sweep under reduced motion without a new plate", function()
		local reduced = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Skeleton("Circle")({ form = "circle" }),
				UI.Skeleton("Box")({ form = "box" }),
				UI.Skeleton("Lines")({ form = "line", lines = 2 }),
			})
		end, { reducedMotion = reduced })
		local circle = find(find(world.screen, "Circle"), "Placeholder1")
		local box = find(find(world.screen, "Box"), "Placeholder1")
		local lines = placeholders(find(world.screen, "Lines"))
		t.expect(#lines).toBe(2)
		local corners = childOf(circle, "UICorner")
		t.expect(#corners).toBe(1)
		t.expect(corners[1].CornerRadius.Scale).toBe(1)
		t.expect(corners[1].CornerRadius.Offset).toBe(0)
		t.expect(circle.Size.X.Offset).toBe(circle.Size.Y.Offset)
		t.expect(circle.Size.X.Scale).toBe(0)
		t.expect(#childOf(box, "UICorner")).toBe(0)
		for _, line in lines do
			t.expect(#childOf(line, "UICorner")).toBe(0)
		end
		local sweeps = {}
		for _, plate in { circle, box, lines[1], lines[2] } do
			local gradients = childOf(plate, "UIGradient")
			t.expect(#gradients).toBe(1)
			t.expect(gradients[1].Parent).toBe(plate)
			t.expect(gradients[1].Enabled).toBe(true)
			table.insert(sweeps, gradients[1])
		end
		reduced:set(true)
		for _, sweep in sweeps do
			t.expect(sweep.Enabled).toBe(false)
		end
		t.expect(find(find(world.screen, "Circle"), "Placeholder1")).toBe(circle)
		t.expect(childOf(circle, "UICorner")[1]).toBe(corners[1])
		t.expect(childOf(circle, "UIGradient")[1]).toBe(sweeps[1])
		reduced:set(false)
		for _, sweep in sweeps do
			t.expect(sweep.Enabled).toBe(true)
		end
		t.expect(find(find(world.screen, "Circle"), "Placeholder1")).toBe(circle)
		world.stop()
	end)

	t.it("keeps the moving band inside each placeholder at fractional widths through full cycles", function()
		local width = Compose.cell(390)
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				UI.Skeleton("A")({
					form = "box",
					Size = function(use)
						return engine.types.UDim2.fromOffset(use(width), 0)
					end,
				}),
			})
		end, { reducedMotion = false })
		local root = find(world.screen, "A")
		local plate = find(root, "Placeholder1")
		local sweep = find(plate, "Shimmer")
		for _, px in { 390, 101, 43.5, 0.5 } do
			width:set(px)
			t.expect(math.abs(root.Size.X.Offset - px) < 1).toBe(true)
			local low, high = math.huge, -math.huge
			for _ = 1, 80 do
				world.step(0.02)
				t.expect(sweep.Parent).toBe(plate)
				t.expect(plate.Size.X.Scale).toBe(1)
				t.expect(plate.Size.X.Offset).toBe(0)
				local offset = sweep.Offset
				t.expect(offset.Y).toBe(0)
				t.expect(offset.X >= -1 and offset.X <= 1).toBe(true)
				low, high = math.min(low, offset.X), math.max(high, offset.X)
			end
			t.expect(low < -0.9 and high > 0.9).toBe(true)
			for _, node in plate:GetDescendants() do
				t.expect(node:IsA("GuiObject")).toBe(false)
			end
		end
		world.stop()
	end)

	t.it("keeps a stage out of selection and Tab traversal as a non-interactive leaf", function()
		local world = setup(function(UI, Host, engine)
			return Host.Frame("Form")({
				Host.UIListLayout({ SortOrder = engine.types.Enum.SortOrder.LayoutOrder }),
				UI.Button("Before")({ label = "Before", LayoutOrder = 1 }),
				UI.Stage("Scene")({ LayoutOrder = 2 }),
				UI.Button("After")({ label = "After", LayoutOrder = 3 }),
			})
		end)
		local stage = find(world.screen, "Scene")
		t.expect(stage.ClassName).toBe("ViewportFrame")
		t.expect(stage.Selectable).toBe(false)
		t.expect(stage.Active).toBe(false)
		for _, node in stage:GetDescendants() do
			t.expect(node:IsA("InputContext")).toBe(false)
			if node:IsA("GuiObject") then
				t.expect(node.Selectable).toBe(false)
			end
		end
		world.gui.SelectedObject = find(world.screen, "Before")
		tab(world)
		t.expect(selected(world)).toBe("After")
		tab(world, true)
		t.expect(selected(world)).toBe("Before")
		tab(world, true)
		t.expect(selected(world)).toBe("After")
		world.stop()
	end)

	t.it("paints a stage through the panel style rule and follows a palette swap", function()
		local package = themes.define(themes.neutralPackage())
		local palette = Compose.cell(package.style.defaultTheme)
		local sheet
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types, theme = package } :: any)
		local Host = runtime.constructors
		local stop, root = runtime.mount(function()
			sheet = themes.createStyleSheet(
				runtime,
				package,
				{ types = engine.types, theme = palette, transition = false, preferredTransparency = 1 } :: any
			)
			return Host.ScreenGui({
				sheet,
				UI.Stage("Scene")({}),
			})
		end, engine.new("Folder"))
		local stage = find(root, "Scene")
		t.expect(stage:HasTag("facet-panel")).toBe(true)
		local default = engine.new("ViewportFrame")
		t.expect(stage.BackgroundColor3).toBe(default.BackgroundColor3)
		t.expect(stage.BackgroundTransparency).toBe(default.BackgroundTransparency)
		local function panel(): { [string]: any }
			for _, node in sheet:GetDescendants() do
				if
					node:IsA("StyleRule")
					and node.Selector == ".facet-panel"
					and node:GetProperties().BackgroundColor3
				then
					return node:GetProperties()
				end
			end
			error("no panel rule")
		end
		local names = {}
		for _, entry in package.style.themes do
			table.insert(names, entry.name)
		end
		t.expect(#names >= 2).toBe(true)
		local seen = {}
		for _, name in names do
			palette:set(name)
			local entry
			for _, candidate in package.style.themes do
				if candidate.name == name then
					entry = candidate
				end
			end
			local want = entry.colors.surfaceStrong
			local got = panel().BackgroundColor3
			t.expect(math.abs(got.R - want.r) < 1e-6).toBe(true)
			t.expect(math.abs(got.G - want.g) < 1e-6).toBe(true)
			t.expect(math.abs(got.B - want.b) < 1e-6).toBe(true)
			t.expect(panel().BackgroundTransparency).toBe(0)
			table.insert(seen, `{got.R},{got.G},{got.B}`)
		end
		t.expect(seen[1] ~= seen[2]).toBe(true)
		stop()
		runtime:dispose()
	end)
	t.it("spends an authored count height and widens the count pill to at least that height", function()
		local world = setup(function(UI, Host, engine)
			return Host.Frame({
				UI.StatusIndicator("Default")({ count = 7 }),
				UI.StatusIndicator("Authored")({
					count = 7,
					cutout = true,
					Size = engine.types.UDim2.new(0, 40, 0, 20),
				}),
			})
		end)
		local default = find(world.screen, "Default")
		local limits = childOf(default, "UISizeConstraint")
		t.expect(#limits).toBe(1)
		t.expect(limits[1].MinSize.X).toBe(24)
		t.expect(limits[1].MinSize.Y).toBe(24)
		t.expect(default.Size.Y.Offset).toBe(24)
		local authored = find(world.screen, "Authored")
		t.expect(authored.Size.Y.Offset).toBe(20)
		t.expect(authored.Size.X.Offset).toBe(40)
		local constraints = childOf(authored, "UISizeConstraint")
		t.expect(#constraints).toBe(1)
		t.expect(constraints[1].MinSize.Y).toBe(0)
		for _, height in { 20, 50, 12 } do
			authored.AbsoluteSize = world.engine.types.Vector2.new(40, height)
			authored:GetPropertyChangedSignal("AbsoluteSize").fire()
			t.expect(constraints[1].MinSize.X).toBe(height)
			t.expect(constraints[1].MinSize.Y).toBe(0)
		end
		local cutout = find(authored, "Cutout")
		t.expect(cutout.ClassName).toBe("UIStroke")
		t.expect(cutout.Thickness).toBe(1)
		t.expect(cutout.BorderStrokePosition).toBe(world.engine.types.Enum.BorderStrokePosition.Inner)
		t.expect(cutout:HasTag("facet-cutout")).toBe(true)
		world.stop()
	end)
end)
