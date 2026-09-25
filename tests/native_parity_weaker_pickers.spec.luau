--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

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
	E: any,
	stop: () -> (),
}

local function setup(build: (any, any, any, any) -> any, options: { [string]: any }?): World
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
	local o: { [string]: any } = options or {}
	input.PreferredInput = engine.types.Enum.PreferredInput[o.preferred or "KeyboardAndMouse"]
	local root = engine.new("ScreenGui")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		inputParent = root,
		reducedMotion = true,
	}
	for key, value in o do
		if key ~= "preferred" then
			config[key] = value
		end
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, node = runtime.mount(function()
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
		E = engine.types.Enum,
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

local function under(root: any, path: string): any
	local at = root
	for name in string.gmatch(path, "[^/]+") do
		if at == nil then
			return nil
		end
		at = find(at, name)
	end
	return at
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

local function selectables(root: any): { any }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:IsA("GuiObject") and node.Selectable == true and node.Visible ~= false then
			table.insert(out, node)
		end
	end
	return out
end

local THREE = {
	{ value = "easy", label = "Easy" },
	{ value = "normal", label = "Normal" },
	{ value = "hard", label = "Hard" },
}

local INPUTS = { "pointer", "touch", "keyboard", "gamepad" }

local function press(world: World, node: any, input: string)
	local E = world.E
	if input == "pointer" then
		node.Activated.fire({ UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode.Unknown }, 1)
	elseif input == "touch" then
		node.Activated.fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown }, 1)
	elseif input == "keyboard" then
		world.gui.SelectedObject = node
		local activate = assert(action(world.root, "Activate"), "Activate action is bound on the selected control")
		t.expect(keys(activate).Return).toBe(true)
		t.expect(keys(activate).Space).toBe(true)
		activate.Pressed.fire()
	else
		world.gui.SelectedObject = node
		node.Activated.fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }, 1)
	end
end

local function refuse(world: World, node: any, input: string)
	if input == "keyboard" then
		world.gui.SelectedObject = node
		t.expect(action(world.root, "Activate")).toBeNil()
		node.Activated.fire({ UserInputType = world.E.UserInputType.Keyboard, KeyCode = world.E.KeyCode.Return }, 1)
	else
		press(world, node, input)
	end
end

type Compound = { class: string?, tags: { string }, state: string? }
type Selector = { parts: { Compound }, combinators: { string }, pseudo: string? }

local function compound(text: string): Compound
	local tags = {}
	for tag in string.gmatch(text, "%.([%w%-]+)") do
		table.insert(tags, tag)
	end
	return { class = string.match(text, "^(%a%w*)"), tags = tags, state = string.match(text, ":(%a+)$") }
end

local function parse(selector: string): Selector
	local pseudo = string.match(selector, "::(%a+)$")
	local rest = if pseudo then string.sub(selector, 1, -(#pseudo + 3)) else selector
	local parts, combinators = {}, {}
	while true do
		local first, last, combinator = string.find(rest, " (>>?) ")
		if not first then
			table.insert(parts, compound(rest))
			break
		end
		table.insert(parts, compound(string.sub(rest, 1, first - 1)))
		table.insert(combinators, combinator :: string)
		rest = string.sub(rest, (last :: number) + 1)
	end
	return { parts = parts, combinators = combinators, pseudo = pseudo }
end

local function matchesPart(part: Compound, node: any): boolean
	if part.class and not node:IsA(part.class) then
		return false
	end
	for _, tag in part.tags do
		if not node:HasTag(tag) then
			return false
		end
	end
	if part.state then
		local ok, state = pcall(function()
			return node.GuiState
		end)
		if not ok or state == nil or state.Name ~= part.state then
			return false
		end
	end
	return true
end

local function matchesAt(selector: Selector, index: number, node: any): boolean
	if not matchesPart(selector.parts[index], node) then
		return false
	end
	if index == 1 then
		return true
	end
	local parent = node.Parent
	if selector.combinators[index - 1] == ">" then
		return parent ~= nil and matchesAt(selector, index - 1, parent)
	end
	while parent do
		if matchesAt(selector, index - 1, parent) then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function resolve(sheet: any, node: any, property: string, pseudo: string?): any
	local best, value = -math.huge, nil
	for _, rule in sheet:GetChildren() do
		local selector = parse(rule.Selector)
		if selector.pseudo == pseudo and matchesAt(selector, #selector.parts, node) then
			local candidate = rule:GetProperties()[property]
			if candidate ~= nil and rule.Priority > best then
				best, value = rule.Priority, candidate
			end
		end
	end
	return value
end

local function sheetFor(world: World, package: any): any
	local _, sheet = world.runtime.mount(function()
		return themes.createStyleSheet(world.runtime, package, { types = world.types } :: any)
	end, world.engine.new("Folder"))
	return sheet
end

local SHIPPED = {
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local function shipped(name: string): any
	local module: any = (require :: any)("../examples/themes/" .. name)
	local package, report = module.build(themes)
	assert(report.ok, name .. " did not build")
	return package
end

t.describe("native parity weaker pickers", function()
	t.it("post-pickers-002 the label stands above the plate in a vertical list and a press on it focuses", function()
		for _, input in { "pointer", "touch" } do
			local world = setup(function(UI)
				return UI.TextInput("Name")({ value = Compose.cell(""), label = "Display name" })
			end)
			local root = world.node
			local label, plate = find(root, "Label"), find(root, "Input")
			t.expect(label.Parent == root and plate.Parent == root).toBe(true)
			local layout = root:FindFirstChildWhichIsA("UIListLayout")
			t.expect(layout.FillDirection).toBe(world.E.FillDirection.Vertical)
			t.expect(layout.SortOrder).toBe(world.E.SortOrder.LayoutOrder)
			t.expect(label.LayoutOrder < plate.LayoutOrder).toBe(true)
			for _, child in root:GetChildren() do
				if child:IsA("GuiObject") and child ~= label then
					t.expect(`{child.Name} {child.LayoutOrder > label.LayoutOrder}`).toBe(`{child.Name} true`)
				end
			end
			t.expect(label.Selectable).toBe(false)
			t.expect(label.Size.Y.Offset >= 44).toBe(true)
			local field = find(plate, "Field")
			t.expect(field:IsFocused()).toBe(false)
			press(world, label, input)
			t.expect(`{input}: {field:IsFocused()}`).toBe(`{input}: true`)
			world.stop()
		end
	end)
	local function accessories(world: any, pasted: { count: number }, value: any): any
		return function(UI: any, Host: any)
			return UI.TextInput("Name")({
				value = value,
				clearButtonMode = "always",
				leading = Host.TextLabel({ Name = "Mark", Text = "@" }),
				trailing = UI.Button("Paste")({
					label = "Paste",
					onActivate = function()
						pasted.count += 1
					end,
				}),
			})
		end
	end

	t.it(
		"post-pickers-010 the stops in the plate are the editor, the clear and the trailing action, in list order",
		function()
			local world = setup(accessories(nil, { count = 0 }, Compose.cell("Ada")))
			local plate = find(world.node, "Input")
			local layout = plate:FindFirstChildWhichIsA("UIListLayout")
			t.expect(layout.FillDirection).toBe(world.E.FillDirection.Horizontal)
			t.expect(layout.SortOrder).toBe(world.E.SortOrder.LayoutOrder)
			local leading = find(plate, "Leading")
			t.expect(leading.Selectable).toBe(false)
			t.expect(find(leading, "Mark").Selectable).toBe(false)
			t.expect(#selectables(leading)).toBe(0)
			local function place(node: any): number
				local at = node
				while at.Parent ~= plate do
					at = at.Parent
				end
				return at.LayoutOrder * 1000 + (if at == node then 0 else node.LayoutOrder)
			end
			local stops = selectables(plate)
			table.sort(stops, function(a, b)
				return place(a) < place(b)
			end)
			local names = {}
			for _, node in stops do
				table.insert(names, node.Name)
			end
			t.expect(table.concat(names, " ")).toBe("Field Clear Paste")
			t.expect(place(leading) < place(find(plate, "Field"))).toBe(true)
			world.stop()
		end
	)

	t.it("post-pickers-011 the trailing action fires once on pointer, touch, keyboard and gamepad", function()
		for _, input in INPUTS do
			local pasted = { count = 0 }
			local value = Compose.cell("Ada")
			local world = setup(accessories(nil, pasted, value))
			local paste = under(world.node, "Input/Trailing/Paste")
			press(world, paste, input)
			t.expect(`{input}: {pasted.count} {value:peek()}`).toBe(`{input}: 1 Ada`)
			world.stop()
		end
		local pasted = { count = 0 }
		local world = setup(accessories(nil, pasted, Compose.cell("Ada")))
		local paste = under(world.node, "Input/Trailing/Paste")
		for _, input in INPUTS do
			press(world, paste, input)
		end
		t.expect(pasted.count).toBe(4)
		world.stop()
	end)

	t.it("post-pickers-012 the clear is a stop after the editor and empties the field on every input", function()
		for _, labelled in { false, true } do
			for _, input in INPUTS do
				local value = Compose.cell("Ada")
				local world = setup(function(UI)
					return UI.TextInput("Name")({
						value = value,
						clearButtonMode = "always",
						label = if labelled then "Name" else nil,
					})
				end)
				local where = `{if labelled then "framed" else "bare"} {input}`
				local clear = find(world.node, "Clear")
				local order = {}
				if labelled then
					local plate = find(world.node, "Input")
					local stops = selectables(plate)
					table.sort(stops, function(a, b)
						return a.LayoutOrder < b.LayoutOrder
					end)
					for _, node in stops do
						table.insert(order, node.Name)
					end
				else
					t.expect(world.node.ClassName).toBe("TextBox")
					t.expect(clear.Parent == world.node).toBe(true)
					t.expect(clear.AnchorPoint.X).toBe(1)
					t.expect(clear.Position.X.Scale).toBe(1)
					table.insert(order, if world.node.Selectable then "Field" else "none")
					for _, node in selectables(world.node) do
						table.insert(order, node.Name)
					end
				end
				t.expect(`{where}: {table.concat(order, " ")}`).toBe(`{where}: Field Clear`)
				t.expect(clear.Size.X.Offset >= 44 and clear.Size.Y.Offset >= 44).toBe(true)
				press(world, clear, input)
				t.expect(`{where}: '{value:peek()}'`).toBe(`{where}: ''`)
				t.expect(clear.Visible).toBe(false)
				world.stop()
			end
		end
	end)

	t.it(
		"post-pickers-016 a compact plate sits centred in a whole target and focuses from the plate or the label",
		function()
			for _, labelled in { false, true } do
				local world = setup(function(UI)
					return UI.TextInput("Name")({
						value = Compose.cell(""),
						controlSize = "compact",
						label = if labelled then "Name" else nil,
					})
				end)
				local target = find(world.node, "Input+target")
				local plate = find(target, "Input")
				t.expect(plate.Parent == target).toBe(true)
				t.expect(plate.Size.Y.Offset).toBe(36)
				t.expect(plate.Size.Y.Scale).toBe(0)
				t.expect(target.Size.Y.Offset >= 44).toBe(true)
				t.expect(plate.AnchorPoint.Y).toBe(0.5)
				t.expect(plate.Position.Y.Scale).toBe(0.5)
				local field = find(plate, "Field")
				t.expect(field.ClassName).toBe("TextBox")
				t.expect(field.Selectable).toBe(true)
				if labelled then
					for _, input in { "pointer", "touch" } do
						field:ReleaseFocus(false)
						press(world, find(world.node, "Label"), input)
						t.expect(`{input}: {field:IsFocused()}`).toBe(`{input}: true`)
					end
				else
					field:CaptureFocus()
					t.expect(field:IsFocused()).toBe(true)
				end
				world.stop()
			end
			for _, rung in { "xsmall", "regular", "large" } do
				local world = setup(function(UI)
					return UI.TextInput("Name")({ value = Compose.cell(""), controlSize = rung })
				end)
				local target = find(world.node, "Input+target")
				local plate = find(target, "Input")
				t.expect(`{rung} {target.Size.Y.Offset >= 44} {target.Size.Y.Offset >= plate.Size.Y.Offset}`)
					.toBe(`{rung} true true`)
				world.stop()
			end
		end
	)

	local function numberWorld(spec: { [string]: any }): (World, any, any, { string })
		local draft = Compose.cell(spec.draft)
		local number = Compose.cell(spec.number)
		local commits: { string } = {}
		local merged: { [string]: any } = {
			value = draft,
			numericValue = number,
			stepButtons = true,
			onCommit = function(value: any, reason: string)
				table.insert(commits, `{value} {reason}`)
			end,
			onChange = function(text: string)
				draft:set(text)
			end,
		}
		for key, entry in spec do
			if key ~= "draft" and key ~= "number" then
				merged[key] = entry
			end
		end
		local world = setup(function(UI)
			return UI.NumberInput("Laps")(merged)
		end)
		return world, draft, number, commits
	end

	t.it(
		"post-pickers-028 a step button moves the value by one step on pointer, touch, keyboard and gamepad",
		function()
			for _, input in INPUTS do
				local world, draft, number, commits =
					numberWorld({ draft = "4", number = 4, step = 2, min = 0, max = 20 })
				press(world, under(world.node, "Input/Increment"), input)
				t.expect(`{input}: {number:peek()} {draft:peek()} {commits[#commits]}`).toBe(`{input}: 6 6 6 submit`)
				press(world, under(world.node, "Input/Decrement"), input)
				t.expect(`{input}: {number:peek()} {draft:peek()} {#commits}`).toBe(`{input}: 4 4 2`)
				world.stop()
			end
		end
	)

	t.it("post-pickers-033 a step button at its bound, read-only or disabled refuses every input", function()
		local cases = {
			{ name = "at max", spec = { draft = "20", number = 20 }, button = "Increment" },
			{ name = "at min", spec = { draft = "0", number = 0 }, button = "Decrement" },
			{ name = "read-only", spec = { draft = "8", number = 8, readOnly = true }, button = "Increment" },
			{ name = "disabled", spec = { draft = "8", number = 8, enabled = false }, button = "Increment" },
		}
		for _, case in cases do
			for _, input in INPUTS do
				local spec: { [string]: any } = { step = 5, min = 0, max = 20 }
				for key, entry in case.spec do
					spec[key] = entry
				end
				local world, _, number, commits = numberWorld(spec)
				local before = number:peek()
				local button = under(world.node, "Input/" .. case.button)
				t.expect(`{case.name}: {button.Interactable}`).toBe(`{case.name}: false`)
				refuse(world, button, input)
				t.expect(`{case.name}/{input}: {number:peek()} {#commits}`).toBe(`{case.name}/{input}: {before} 0`)
				world.stop()
			end
		end
		local world = numberWorld({ draft = "0", number = 0, step = 5, min = 0, max = 20 })
		t.expect(under(world.node, "Input/Increment").Interactable).toBe(true)
		world.stop()
	end)
	t.it(
		"post-pickers-045 the error paints the menu trigger's stroke in the danger colour and the hint returns",
		function()
			local failure = Compose.cell("")
			local world = setup(function(UI)
				return UI.Picker("P")({
					style = "menu",
					selected = Compose.cell("normal"),
					options = THREE,
					label = "Difficulty",
					requiredMark = "required",
					hint = "Change it any time",
					errorText = failure,
				})
			end)
			local package = themes.neutralPackage()
			local sheet = sheetFor(world, package)
			local colors = package.style.themes[1].colors
			local trigger = find(world.node, "Trigger")
			local line = find(world.node, "Validation")
			t.expect(find(world.node, "Label").Text).toBe("Difficulty *")
			t.expect(line.Text).toBe("Change it any time")
			local rest = resolve(sheet, trigger, "Color", "UIStroke")
			t.expect(rest).toBeNil()
			t.expect(trigger:HasTag("facet-invalid")).toBe(false)
			local size, position = trigger.Size, trigger.Position
			failure:set("Pick a difficulty to continue.")
			t.expect(line.Text).toBe("Pick a difficulty to continue.")
			t.expect(find(world.node, "MessageMark").Visible).toBe(true)
			local stroke = resolve(sheet, trigger, "Color", "UIStroke")
			t.expect(trigger:HasTag("facet-invalid")).toBe(true)
			t.expect(stroke ~= nil).toBe(true)
			t.expect(math.abs(stroke.R - colors.danger.r) < 1e-3).toBe(true)
			t.expect(math.abs(stroke.G - colors.danger.g) < 1e-3).toBe(true)
			t.expect(math.abs(stroke.B - colors.danger.b) < 1e-3).toBe(true)
			t.expect(stroke.R > stroke.G * 2).toBe(true)
			t.expect(resolve(sheet, trigger, "Thickness", "UIStroke")).toBe(1)
			t.expect(trigger.Size == size and trigger.Position == position).toBe(true)
			failure:set("")
			t.expect(line.Text).toBe("Change it any time")
			t.expect(resolve(sheet, trigger, "Color", "UIStroke")).toBeNil()
			world.stop()
		end
	)
	t.it("post-pickers-051 opening lands on the selected row inside the list window on every input", function()
		local long = {}
		for i = 1, 30 do
			table.insert(long, { value = `v{i}`, label = `Option {i}` })
		end
		for _, input in INPUTS do
			local preferred = if input == "pointer"
				then "KeyboardAndMouse"
				elseif input == "touch" then "Touch"
				elseif input == "keyboard" then "KeyboardAndMouse"
				else "Gamepad"
			local selected = Compose.cell("v25")
			local world = setup(function(UI)
				return UI.Picker("P")({ style = "menu", options = long, maxHeight = 200, selected = selected })
			end, { preferred = preferred })
			local trigger = find(world.node, "Trigger")
			if input == "keyboard" then
				world.gui.SelectedObject = trigger
				for _, c in world.root:GetChildren() do
					if c:IsA("InputContext") then
						print("CTX", c.Name, c.Enabled)
					end
				end
			end
			press(world, trigger, input)
			local panel = find(world.root, "MenuPanel")
			t.expect(`{input} open {panel ~= nil}`).toBe(`{input} open true`)
			local rows = find(panel, "MenuRows")
			local V2 = world.types.Vector2
			panel.AbsolutePosition = V2.new(0, 100)
			panel.AbsoluteSize = V2.new(280, 200)
			local ordered = {}
			for _, child in rows:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					table.insert(ordered, child)
				end
			end
			table.sort(ordered, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for index, row in ordered do
				row.AbsoluteSize = V2.new(280, 44)
				row.AbsolutePosition = V2.new(0, 100 + (index - 1) * 44)
			end
			rows.AbsolutePosition = V2.new(0, 100)
			rows.AbsoluteSize = V2.new(280, #ordered * 44)
			rows:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = V2.new(280, #ordered * 44)
			print("after content", panel.CanvasPosition.Y, #ordered)
			panel.AbsoluteSize = V2.new(280, 201)
			print("after panel", panel.CanvasPosition.Y)
			local row = find(rows, "v25")
			print("rowparent", row.Parent == rows, row.Parent.Name)
			local top = 0
			for _, other in ordered do
				if other.LayoutOrder < row.LayoutOrder then
					top += 44
				end
			end
			local scroll = panel.CanvasPosition.Y
			print(input, scroll, top, world.gui.SelectedObject and world.gui.SelectedObject.Name)
			world.stop()
		end
	end)
end)
