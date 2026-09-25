--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local themePackages = require("../tools/lune/theme_packages")
local Compose = Facet.Compose
local themes = Facet.themes

local SHIPPED: { string } = themePackages.shippable()

type World = {
	engine: any,
	runtime: any,
	gui: any,
	root: any,
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
	local root = engine.new("ScreenGui")
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
		inputParent = root,
		reducedMotion = true,
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop = runtime.mount(function()
		return Host.Frame "Surface" {
			Size = engine.types.UDim2.fromScale(1, 1),
			build(UI, Host, engine, runtime),
		}
	end, root)
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		root = root,
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

local function load(name: string): any
	local package, report = (require :: any)("../examples/themes/" .. name).build(themes)
	assert(package ~= nil and report.ok, name .. " failed its own package gate")
	return package
end

local function packages(): { { label: string, package: any } }
	local out = { { label = "facet_neutral", package = themes.neutralPackage() } }
	for _, name in SHIPPED do
		table.insert(out, { label = name, package = load(name) })
	end
	return out
end

local function sheetFor(package: any, options: { [string]: any }?): (any, any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local settings: { [string]: any } = { types = engine.types, preferredTransparency = 1, reducedMotion = true }
	for key, value in (options or {}) :: { [string]: any } do
		settings[key] = value
	end
	local _, sheet = runtime.mount(function()
		return themes.createStyleSheet(runtime, package, settings :: any)
	end, engine.new("Folder"))
	return sheet, engine, function()
		runtime:dispose()
	end
end

local function rules(sheet: any): { [string]: { [string]: any } }
	local out = {}
	for _, node in sheet:GetChildren() do
		out[node.Selector] = node:GetProperties()
	end
	return out
end

local function style(sheet: any, selector: string): { [string]: any }
	local found = rules(sheet)[selector]
	assert(found ~= nil, "No rule: " .. selector)
	return found
end

local function rgb(value: any): { r: number, g: number, b: number }
	if value.R ~= nil then
		return { r = value.R, g = value.G, b = value.B }
	end
	return { r = value.r, g = value.g, b = value.b }
end

local function same(a: any, b: any): boolean
	local x, y = rgb(a), rgb(b)
	return math.abs(x.r - y.r) < 1e-6 and math.abs(x.g - y.g) < 1e-6 and math.abs(x.b - y.b) < 1e-6
end

local function luminance(value: any): number
	local c = rgb(value)
	local function linear(channel: number): number
		return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
end

local function contrast(first: any, second: any): number
	local a, b = luminance(first), luminance(second)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

local function palettes(package: any): { any }
	return package.style.themes
end

type Compound = { class: string?, tags: { string }, state: string? }
type Selector = { parts: { Compound }, combinators: { string }, pseudo: string? }

local function compound(text: string): Compound
	local tags = {}
	for tag in string.gmatch(text, "%.([%w%-]+)") do
		table.insert(tags, tag)
	end
	return {
		class = string.match(text, "^(%a%w*)"),
		tags = tags,
		state = string.match(text, ":(%a+)$"),
	}
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
		if not string.find(rule.Selector, "#", 1, true) then
			local selector = parse(rule.Selector)
			if selector.pseudo == pseudo and matchesAt(selector, #selector.parts, node) then
				local candidate = rule:GetProperties()[property]
				if candidate ~= nil and rule.Priority > best then
					best, value = rule.Priority, candidate
				end
			end
		end
	end
	return value
end

local function guiState(engine: any, node: any, state: string)
	node.GuiState = (engine.types.Enum.GuiState :: any)[state]
end

local THREE = {
	{ value = "low", label = "Low" },
	{ value = "normal", label = "Normal" },
	{ value = "high", label = "High" },
}

local function segments(root: any): { any }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:HasTag("facet-segment") then
			table.insert(out, node)
		end
	end
	table.sort(out, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return out
end

t.describe("native parity weaker paint", function()
	t.it(
		"apps-200 the segmented track and its chosen segment follow radii.control concentrically in every package",
		function()
			local selected = Compose.cell("low")
			local world = setup(function(UI)
				return UI.Picker "View" { style = "segmented", selected = selected, options = THREE }
			end)
			local strip = find(world.root, "View")
			t.expect(strip:HasTag("facet-segmented")).toBe(true)
			local parts = segments(strip)
			t.expect(#parts).toBe(3)
			for _, part in parts do
				t.expect(part:FindFirstChildWhichIsA("UICorner")).toBeNil()
			end
			t.expect(parts[1]:HasTag("facet-segment-current")).toBe(true)
			selected:set("high")
			t.expect(parts[1]:HasTag("facet-segment-current")).toBe(false)
			t.expect(parts[3]:HasTag("facet-segment-current")).toBe(true)
			local measured = 0
			for _, entry in packages() do
				local sheet, _, stop = sheetFor(entry.package)
				local control = entry.package.metrics.radii.control
				local track = resolve(sheet, strip, "CornerRadius", "UICorner")
				local inset = resolve(sheet, strip, "PaddingLeft", "UIPadding")
				t.expect(`{entry.label} track scale {track.Scale}`).toBe(`{entry.label} track scale 0`)
				t.expect(`{entry.label} track {track.Offset >= control}`).toBe(`{entry.label} track true`)
				t.expect(`{entry.label} inset {inset.Offset}`).toBe(`{entry.label} inset 3`)
				for _, part in parts do
					local corner = resolve(sheet, part, "CornerRadius", "UICorner")
					t.expect(`{entry.label} {part.Name} {corner.Scale},{corner.Offset}`)
						.toBe(`{entry.label} {part.Name} 0,{math.max(0, track.Offset - inset.Offset)}`)
				end
				for _, side in { "PaddingRight", "PaddingTop", "PaddingBottom" } do
					t.expect(resolve(sheet, strip, side, "UIPadding").Offset).toBe(inset.Offset)
				end
				stop()
				measured += 1
			end
			t.expect(measured).toBe(#SHIPPED + 1)
			local narrow = assert(
				themes.define({ identity = { id = "narrow-control" }, metrics = { radii = { control = 2 } } } :: any)
			)
			local wide = assert(
				themes.define({ identity = { id = "wide-control" }, metrics = { radii = { control = 14 } } } :: any)
			)
			local narrowSheet, _, stopNarrow = sheetFor(narrow)
			local wideSheet, _, stopWide = sheetFor(wide)
			local narrowTrack = resolve(narrowSheet, strip, "CornerRadius", "UICorner").Offset
			local wideTrack = resolve(wideSheet, strip, "CornerRadius", "UICorner").Offset
			t.expect(wideTrack - narrowTrack).toBe(12)
			t.expect(
				resolve(wideSheet, parts[3], "CornerRadius", "UICorner").Offset
					- resolve(narrowSheet, parts[3], "CornerRadius", "UICorner").Offset
			).toBe(12)
			stopNarrow()
			stopWide()
			world.stop()
		end
	)

	t.it("apps-202 an authored square or pill strip corner outranks the theme radius in every package", function()
		for _, corners in { "square", "pill" } do
			local world = setup(function(UI)
				return UI.Picker "View" {
					style = "segmented",
					corners = corners,
					selected = Compose.cell("normal"),
					options = THREE,
				}
			end)
			local strip = find(world.root, "View")
			t.expect(strip:HasTag("facet-segmented-" .. corners)).toBe(true)
			local own = strip:FindFirstChildWhichIsA("UICorner")
			t.expect(own ~= nil).toBe(true)
			local want = if corners == "pill" then "1,0" else "0,0"
			t.expect(`{own.CornerRadius.Scale},{own.CornerRadius.Offset}`).toBe(want)
			for _, entry in packages() do
				local sheet, _, stop = sheetFor(entry.package)
				for _, part in segments(strip) do
					local corner = resolve(sheet, part, "CornerRadius", "UICorner")
					t.expect(`{entry.label} {corners} {part.Name} {corner.Scale},{corner.Offset}`)
						.toBe(`{entry.label} {corners} {part.Name} {want}`)
				end
				stop()
			end
			world.stop()
		end
	end)

	t.it("apps-205 a bar LevelPicker plates each level from the theme while a glyph picker plates nothing", function()
		local value = Compose.cell(2)
		local world = setup(function(UI, Host)
			return Host.Frame {
				UI.LevelPicker "Bars" { value = value, count = 4 },
				UI.LevelPicker "Stars" { value = value, count = 5, segment = "glyph" },
			}
		end)
		local bars, stars = find(world.root, "Bars"), find(world.root, "Stars")
		for _, entry in packages() do
			local sheet, _, stop = sheetFor(entry.package)
			for index = 1, 4 do
				local bar = find(bars, "Level" .. index)
				t.expect(bar.ClassName).toBe("Frame")
				t.expect(bar:HasTag("facet-level-segment")).toBe(true)
				t.expect(resolve(sheet, bar, "BackgroundTransparency")).toBe(0)
				t.expect(resolve(sheet, bar, "BackgroundColor3") ~= nil).toBe(true)
				t.expect(bar:FindFirstChildWhichIsA("UICorner") ~= nil).toBe(true)
			end
			for index = 1, 5 do
				local star = find(stars, "Level" .. index)
				t.expect(star.ClassName).toBe("TextLabel")
				t.expect(star:HasTag("facet-level-segment")).toBe(false)
				t.expect(star:HasTag("facet-level-on")).toBe(false)
				t.expect(star.BackgroundTransparency).toBe(1)
				t.expect(star:FindFirstChildWhichIsA("UICorner")).toBeNil()
			end
			stop()
		end
		t.expect(find(bars, "Track")).toBeNil()
		t.expect(find(stars, "Track")).toBeNil()
		world.stop()
	end)

	t.it("inputs-110 filled and empty bar levels resolve to different theme colours in every palette", function()
		local value = Compose.cell(3)
		local world = setup(function(UI)
			return UI.LevelPicker "Quality" { value = value, count = 10 }
		end)
		local picker = find(world.root, "Quality")
		local measured = 0
		for _, entry in packages() do
			for _, palette in palettes(entry.package) do
				local sheet, _, stop = sheetFor(entry.package, { theme = palette.name })
				local extra = palette.extra or {}
				local label = entry.label .. "/" .. palette.name
				value:set(3)
				local filled = resolve(sheet, find(picker, "Level3"), "BackgroundColor3")
				local empty = resolve(sheet, find(picker, "Level4"), "BackgroundColor3")
				t.expect(`{label} filled accent {same(filled, palette.colors.accent)}`)
					.toBe(`{label} filled accent true`)
				t.expect(`{label} empty control {same(empty, extra.control)}`).toBe(`{label} empty control true`)
				t.expect(`{label} distinct {not same(filled, empty)}`).toBe(`{label} distinct true`)
				value:set(7)
				t.expect(same(resolve(sheet, find(picker, "Level7"), "BackgroundColor3"), filled)).toBe(true)
				t.expect(same(resolve(sheet, find(picker, "Level8"), "BackgroundColor3"), empty)).toBe(true)
				stop()
				measured += 1
			end
		end
		t.expect(measured > #SHIPPED).toBe(true)
		world.stop()
	end)

	t.it("inputs-132 the hover fill is its own theme role and differs from the rest fill in every palette", function()
		local world = setup(function(UI)
			return UI.Button "Go" { label = "Go" }
		end)
		local button = find(world.root, "Go")
		local measured = 0
		for _, entry in packages() do
			for _, palette in palettes(entry.package) do
				local sheet, engine, stop = sheetFor(entry.package, { theme = palette.name })
				local extra = palette.extra or {}
				local label = entry.label .. "/" .. palette.name
				t.expect(`{label} roles differ {not same(extra.control, extra.controlHover)}`)
					.toBe(`{label} roles differ true`)
				guiState(engine, button, "Idle")
				local rest = resolve(sheet, button, "BackgroundColor3")
				guiState(engine, button, "Hover")
				local hover = resolve(sheet, button, "BackgroundColor3")
				t.expect(`{label} rest {same(rest, extra.control)}`).toBe(`{label} rest true`)
				t.expect(`{label} hover {same(hover, extra.controlHover)}`).toBe(`{label} hover true`)
				t.expect(`{label} distinct {not same(rest, hover)}`).toBe(`{label} distinct true`)
				stop()
				measured += 1
			end
		end
		t.expect(measured > #SHIPPED).toBe(true)
		world.stop()
	end)

	t.it("inputs-205 the checkbox keeps a theme-owned border outline in off, on, mixed and disabled states", function()
		local value, mixed, enabled = Compose.cell(false), Compose.cell(false), Compose.cell(true)
		local world = setup(function(UI)
			return UI.Toggle "Music" {
				label = "Music",
				value = value,
				mixed = mixed,
				enabled = enabled,
				presentation = "checkbox",
				row = { description = "Race music" },
			}
		end)
		local indicator = find(find(world.root, "Music"), "Indicator")
		t.expect(indicator.ClassName).toBe("Frame")
		local measured = 0
		for _, state in
			{ { false, false, true }, { true, false, true }, { false, true, true }, { false, false, false } }
		do
			value:set(state[1])
			mixed:set(state[2])
			enabled:set(state[3])
			t.expect(indicator:HasTag("facet-toggle-checkbox")).toBe(true)
			t.expect(indicator:FindFirstChildWhichIsA("UIStroke")).toBeNil()
			local check = find(indicator, "Check")
			t.expect(check.Visible).toBe(state[1] and not state[2])
			t.expect(find(indicator, "Mark").Visible).toBe(state[2])
			for _, entry in packages() do
				for _, palette in palettes(entry.package) do
					local sheet, engine, stop = sheetFor(entry.package, { theme = palette.name })
					local extra = palette.extra or {}
					local label = `{entry.label}/{palette.name} {state[1]},{state[2]},{state[3]}`
					local color = resolve(sheet, indicator, "Color", "UIStroke")
					local thickness = resolve(sheet, indicator, "Thickness", "UIStroke")
					local transparency = resolve(sheet, indicator, "Transparency", "UIStroke") or 0
					local mode = resolve(sheet, indicator, "ApplyStrokeMode", "UIStroke")
					t.expect(`{label} outline {color ~= nil and same(color, extra.contentSecondary)}`)
						.toBe(`{label} outline true`)
					t.expect(`{label} not the box fill {not same(color, extra.control)}`)
						.toBe(`{label} not the box fill true`)
					t.expect(`{label} visible {thickness > 0 and transparency < 1}`).toBe(`{label} visible true`)
					t.expect(`{label} border {mode == engine.types.Enum.ApplyStrokeMode.Border}`)
						.toBe(`{label} border true`)
					stop()
					measured += 1
				end
			end
		end
		t.expect(measured > 4 * #SHIPPED).toBe(true)
		world.stop()
	end)

	t.it("navigation-1-37 an alert centres its title and message and centres the mark over the title", function()
		for _, severity in { "none", "critical" } do
			local world = setup(function(UI)
				return UI.Alert {
					isPresented = Compose.cell(true),
					title = "Replace this save?",
					message = "Your selected driver is ready.",
					severity = if severity == "critical" then "critical" else nil,
					actions = { { id = "ok", label = "OK" } },
				}
			end)
			local content = find(world.root, "AlertContent")
			local title, message = find(content, "Title"), find(content, "Message")
			local center = world.engine.types.Enum.TextXAlignment.Center
			t.expect(`{severity} title {title.TextXAlignment == center}`).toBe(`{severity} title true`)
			t.expect(`{severity} message {message.TextXAlignment == center}`).toBe(`{severity} message true`)
			t.expect(title.Size.X.Scale).toBe(1)
			t.expect(title.Size.X.Offset).toBe(0)
			t.expect(message.Size.X.Scale).toBe(1)
			local layout = content:FindFirstChildWhichIsA("UIListLayout")
			t.expect(layout.HorizontalAlignment).toBe(world.engine.types.Enum.HorizontalAlignment.Center)
			local mark = find(content, "AlertIcon")
			if severity == "critical" then
				t.expect(mark ~= nil).toBe(true)
				t.expect(mark.LayoutOrder < title.LayoutOrder).toBe(true)
			else
				t.expect(mark).toBeNil()
			end
			world.stop()
		end
	end)

	t.it(
		"navigation-3-35 the tab bar keeps its paint order over the content through compact and distant resizes",
		function()
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
			input.PreferredInput = engine.types.Enum.PreferredInput.Touch
			local playerGui = engine.new("Folder")
			local app = Facet.app({
				runtime = runtime,
				theme = load("fantasy_ornate"),
				types = engine.types,
				parent = playerGui,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				reducedMotion = true,
			} :: any)
			local _, screen = app.mount(function()
				return app.UI.TabView {
					selection = Compose.cell("a"),
					style = "sidebarAdaptable",
					tabs = {
						{
							id = "a",
							label = "Garage",
							content = function()
								return app.UI.Button "Play" { label = "Play" }
							end,
						},
						{
							id = "b",
							label = "Store",
							content = function()
								return app.UI.Button "Buy" { label = "Buy" }
							end,
						},
					},
				}
			end)
			t.expect(screen.ZIndexBehavior).toBe(engine.types.Enum.ZIndexBehavior.Sibling)
			local root = find(screen, "TabView")
			local tabs = find(root, "Tabs")
			local function expectOrder(label: string)
				local content = find(root, "Content")
				t.expect(`{label} same bar {find(root, "Tabs") == tabs}`).toBe(`{label} same bar true`)
				t.expect(`{label} bar over content {tabs.ZIndex > content.ZIndex}`)
					.toBe(`{label} bar over content true`)
				t.expect(`{label} bar is a sibling of content {tabs.Parent == content.Parent}`)
					.toBe(`{label} bar is a sibling of content true`)
				local count = 0
				for _, node in tabs:GetDescendants() do
					if node:IsA("GuiObject") then
						count += 1
					end
				end
				t.expect(`{label} bar paints its tabs {count >= 2}`).toBe(`{label} bar paints its tabs true`)
			end
			root.AbsoluteSize = engine.types.Vector2.new(390, 844)
			expectOrder("compact")
			local compactPosition = tabs.Position
			for round = 1, 2 do
				root.AbsoluteSize = engine.types.Vector2.new(1920, 1080)
				input.PreferredInput = engine.types.Enum.PreferredInput.Gamepad
				expectOrder(`distant {round}`)
				t.expect(tabs.Position ~= compactPosition).toBe(true)
				root.AbsoluteSize = engine.types.Vector2.new(390, 844)
				input.PreferredInput = engine.types.Enum.PreferredInput.Touch
				expectOrder(`compact {round}`)
				t.expect(tabs.Position).toBe(compactPosition)
			end
			app.dispose()
			runtime:dispose()
		end
	)

	t.it("navigation-3-83 the chosen menu row clears 4.5:1 on its selection fill in every shipped palette", function()
		local world = setup(function(UI)
			return UI.Picker "Quality" {
				style = "menu",
				label = "Quality",
				selected = Compose.cell("normal"),
				isPresented = Compose.cell(false),
				options = THREE,
			}
		end)
		find(world.root, "Trigger").Activated.fire()
		local panel = find(world.root, "MenuPanel")
		local row = find(panel, "normal")
		local title = find(row, "Title")
		t.expect(row:HasTag("facet-menu-item")).toBe(true)
		t.expect(row:HasTag("facet-selected")).toBe(true)
		t.expect(find(panel, "low"):HasTag("facet-selected")).toBe(false)
		local measured = 0
		for _, entry in packages() do
			for _, palette in palettes(entry.package) do
				local sheet, engine, stop = sheetFor(entry.package, { theme = palette.name })
				for _, state in { "Idle", "Hover", "Press" } do
					guiState(engine, row, state)
					local label = `{entry.label}/{palette.name} {state}`
					local fill = resolve(sheet, row, "BackgroundColor3", nil)
					local ink = resolve(sheet, title, "TextColor3", nil)
					t.expect(`{label} fill {same(fill, palette.colors.accent)}`).toBe(`{label} fill true`)
					t.expect(`{label} ink {same(ink, palette.colors.onAccent)}`).toBe(`{label} ink true`)
					t.expect(`{label} opaque {resolve(sheet, row, "BackgroundTransparency", nil)}`)
						.toBe(`{label} opaque 0`)
					local ratio = contrast(ink, fill)
					t.expect(`{label} readable {ratio >= 4.5}`).toBe(`{label} readable true`)
				end
				guiState(engine, row, "Idle")
				stop()
				measured += 1
			end
		end
		t.expect(measured > #SHIPPED).toBe(true)
		world.stop()
	end)

	t.it("paint-72 an explicit per-view colour is written on the instance and survives theme changes", function()
		local red
		local theme = Compose.cell(themes.neutralPackage())
		local world = setup(function(UI, Host, engine)
			red = engine.types.Color3.new(1, 0, 0)
			return Host.Frame {
				UI.Button "Custom" { label = "Custom", BackgroundColor3 = red },
				UI.Button "Plain" { label = "Plain" },
			}
		end, { theme = theme })
		local custom, plain = find(world.root, "Custom"), find(world.root, "Plain")
		local blank = world.engine.new("TextButton").BackgroundColor3
		t.expect(custom.BackgroundColor3).toBe(red)
		t.expect(plain.BackgroundColor3).toBe(blank)
		t.expect(custom:HasTag("facet-button")).toBe(true)
		for _, entry in packages() do
			theme:set(entry.package)
			t.expect(`{entry.label} custom {custom.BackgroundColor3 == red}`).toBe(`{entry.label} custom true`)
			t.expect(`{entry.label} plain {plain.BackgroundColor3 == blank}`).toBe(`{entry.label} plain true`)
		end
		world.stop()
	end)

	t.it(
		"paint-76 a live palette swap repaints a mounted toggle through its rules and never touches its value",
		function()
			local value, changes = Compose.cell(true), 0
			local theme = Compose.cell(themes.neutralPackage())
			local sheet
			local world = setup(function(UI, Host, engine, runtime)
				sheet = themes.createStyleSheet(runtime, theme, { types = engine.types, reducedMotion = true } :: any)
				return Host.Frame {
					sheet,
					UI.Toggle "Music" {
						label = "Music",
						value = value,
						onChange = function(next)
							changes += 1
							value:set(next)
						end,
					},
				}
			end, { theme = theme })
			local indicator = find(find(world.root, "Music"), "Indicator")
			local mark = find(indicator, "Mark")
			local blank = world.engine.new("Frame").BackgroundColor3
			local position = mark.Position
			for _, entry in packages() do
				theme:set(entry.package)
				local palette = entry.package.style.themes[1]
				local extra = palette.extra or {}
				local on = resolve(sheet, indicator, "BackgroundColor3", nil)
				t.expect(`{entry.label} on {same(on, extra.selection or palette.colors.accent)}`)
					.toBe(`{entry.label} on true`)
				t.expect(value:peek()).toBe(true)
				t.expect(changes).toBe(0)
				t.expect(indicator:HasTag("facet-toggle-on")).toBe(true)
				t.expect(indicator.BackgroundColor3).toBe(blank)
				t.expect(mark.BackgroundColor3).toBe(blank)
				t.expect(mark.Position).toBe(position)
			end
			value:set(false)
			local off = resolve(sheet, indicator, "BackgroundColor3", nil)
			local last = packages()[#packages()]
			t.expect(same(off, last.package.style.themes[1].extra.control)).toBe(true)
			world.stop()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local _, bare = runtime.mount(function()
				return themes.createStyleSheet(runtime, nil, { types = engine.types } :: any)
			end, engine.new("Folder"))
			local neutral, _, stop = sheetFor(themes.neutralPackage())
			for _, selector in
				{ ".facet-toggle-indicator", ".facet-toggle-on", ".facet-toggle-switch >> .facet-toggle-mark" }
			do
				t.expect(same(style(bare, selector).BackgroundColor3, style(neutral, selector).BackgroundColor3))
					.toBe(true)
			end
			stop()
			runtime:dispose()
		end
	)

	t.it("paint-113 every stroke rule strokes the border so text hosts never stroke their glyphs", function()
		for _, entry in packages() do
			local package = table.clone(entry.package)
			package.rules = table.clone(package.rules or {})
			table.insert(package.rules, { selector = ".game-outline::UIStroke", properties = { Thickness = 2 } })
			local sheet, engine, stop = sheetFor(package)
			local border = engine.types.Enum.ApplyStrokeMode.Border
			local strokes = 0
			for selector, properties in rules(sheet) do
				if string.sub(selector, -10) == "::UIStroke" then
					strokes += 1
					t.expect(`{entry.label} {selector} {properties.ApplyStrokeMode == border}`)
						.toBe(`{entry.label} {selector} true`)
				end
			end
			t.expect(strokes >= 12).toBe(true)
			stop()
		end
		local authored = themes.neutralPackage()
		authored.rules = { { selector = ".game-glyphs::UIStroke", properties = { Thickness = 1 } } }
		local sheet, engine, stop = sheetFor(authored)
		local rule = sheet:GetChildren()[#sheet:GetChildren()]
		t.expect(rule.Selector).toBe(".game-glyphs::UIStroke")
		t.expect(rule:GetProperties().ApplyStrokeMode).toBe(engine.types.Enum.ApplyStrokeMode.Border)
		stop()
	end)

	t.it("mech1-106 a washed divider is quieter than secondary content on every ground in every palette", function()
		local function distance(a: any, b: any): number
			local x, y = rgb(a), rgb(b)
			return math.max(math.abs(x.r - y.r), math.abs(x.g - y.g), math.abs(x.b - y.b))
		end
		local washed, bold = 0, {}
		for _, entry in packages() do
			for _, palette in palettes(entry.package) do
				local sheet, _, stop = sheetFor(entry.package, { theme = palette.name })
				local label = entry.label .. "/" .. palette.name
				local extra = palette.extra or {}
				local rule = style(sheet, ".facet-divider")
				local transparency = rule.BackgroundTransparency
				t.expect(`{label} {transparency}`).toBe(`{label} {extra.hairlineOpacity or 0.92}`)
				t.expect(same(rule.BackgroundColor3, extra.hairline)).toBe(true)
				if transparency < 0.5 then
					table.insert(bold, label)
				else
					washed += 1
					local ink = rgb(rule.BackgroundColor3)
					local words = style(sheet, ".facet-secondary").TextColor3
					for _, role in { "control", "surface", "surfaceStrong" } do
						local ground = rgb(palette.colors[role] or extra[role])
						local alpha = 1 - transparency
						local seam = {
							r = ground.r + (ink.r - ground.r) * alpha,
							g = ground.g + (ink.g - ground.g) * alpha,
							b = ground.b + (ink.b - ground.b) * alpha,
						}
						t.expect(`{label} on {role} visible {distance(seam, ground) > 0}`)
							.toBe(`{label} on {role} visible true`)
						t.expect(`{label} on {role} quieter {distance(seam, ground) < distance(words, ground)}`)
							.toBe(`{label} on {role} quieter true`)
					end
				end
				stop()
			end
		end
		t.expect(washed > #SHIPPED).toBe(true)
		t.expect(table.concat(bold, ",")).toBe("pixel_quest/Quest")
		local neutral = themes.neutralPackage().style.themes[1].extra.hairline
		t.expect(`{neutral.r},{neutral.g},{neutral.b}`).toBe("1,1,1")
	end)
	t.it("keeps skinned tabs, badges and stepper labels legible on their art", function()
		for _, package in { themes.neutralPackage(), load("fantasy_ornate") } do
			local sheet, _, stop = sheetFor(package)
			local all = rules(sheet)
			t.expect(all[".facet-tab-filled.facet-skinned"].BackgroundTransparency).toBe(0)
			t.expect(all[".facet-tab-filled > #SkinBoundary"].Visible).toBe(false)
			t.expect(all[".facet-badge-captioned"].TextTransparency).toBe(1)
			t.expect(all[".facet-skinned >> .facet-stepper-inset"].PaddingLeft.Offset >= 12).toBe(true)
			stop()
		end
	end)
	t.it("pads every role by the larger of its floor and the package's chrome insets, zero insets included", function()
		local cases = packages()
		local bare = themes.neutralPackage()
		bare.chrome = bare.chrome or {}
		bare.chrome.control = { kind = "native", contentInsets = { left = 0, right = 0, top = 0, bottom = 0 } }
		table.insert(cases, { label = "zero-inset", package = bare })
		for _, entry in cases do
			local sheet, _, stop = sheetFor(entry.package)
			local all = rules(sheet)
			for role, floors in
				{
					button = { slot = "control", x = 12, y = 0 },
					field = { slot = "field", x = 0, y = 0 },
					badge = { slot = "badge", x = 8, y = 3 },
					panel = { slot = "panel", x = 0, y = 0 },
				} :: { [string]: any }
			do
				local recipe = (entry.package.chrome or {})[floors.slot]
				local inset = if recipe then recipe.contentInsets or {} else {}
				local padding = all[".facet-" .. role .. "::UIPadding"]
				t.expect(
					`{entry.label} {role} {padding.PaddingLeft.Offset},{padding.PaddingRight.Offset},{padding.PaddingTop.Offset},{padding.PaddingBottom.Offset}`
				).toBe(
					`{entry.label} {role} {math.max(floors.x, inset.left or 0)},{math.max(floors.x, inset.right or 0)},{math.max(
						floors.y,
						inset.top or 0
					)},{math.max(floors.y, inset.bottom or 0)}`
				)
			end
			stop()
		end
	end)
	t.it("paints state, selection and corner radii from each package's own tokens in every palette", function()
		local function luminance(color: any): number
			local function channel(value: number): number
				return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
		end
		local function contrast(a: any, b: any): number
			local x, y = luminance(a), luminance(b)
			return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
		end
		for _, entry in packages() do
			local radius = entry.package.metrics.radii.control
			for _, palette in entry.package.style.themes do
				local sheet, _, stop = sheetFor(entry.package, { theme = palette.name })
				local all = rules(sheet)
				local label = `{entry.label}/{palette.name}`
				t.expect(`{label} track {all[".facet-segmented::UICorner"].CornerRadius.Offset}`)
					.toBe(`{label} track {radius + 2}`)
				t.expect(`{label} segment {all[".facet-segment::UICorner"].CornerRadius.Offset}`)
					.toBe(
						`{label} segment {math.max(
							0,
							radius + 2 - all[".facet-segmented::UIPadding"].PaddingLeft.Offset
						)}`
					)
				t.expect(all[".facet-segmented-square >> .facet-segment::UICorner"].CornerRadius.Offset).toBe(0)
				t.expect(
					`{label} level halves differ {all[".facet-level-segment"].BackgroundColor3 ~= all[".facet-level-on"].BackgroundColor3}`
				).toBe(`{label} level halves differ true`)
				t.expect(
					`{label} hover differs {all[".facet-button:Hover"].BackgroundColor3 ~= all[".facet-button"].BackgroundColor3}`
				).toBe(`{label} hover differs true`)
				local outline = all[".facet-toggle-checkbox::UIStroke"]
				t.expect(`{label} checkbox outline {outline.Thickness > 0 and outline.Transparency < 1}`)
					.toBe(`{label} checkbox outline true`)
				local chosen = all[".facet-menu-item.facet-selected"]
				t.expect(`{label} chosen row readable {contrast(chosen.TextColor3, chosen.BackgroundColor3) >= 4.5}`)
					.toBe(`{label} chosen row readable true`)
				stop()
			end
		end
	end)
	t.it("resolves a palette role named in a package rule for each palette", function()
		local package = themes.neutralPackage()
		package.rules = { { selector = ".game-caption", properties = { TextColor3 = { role = "accent" } } } }
		for _, palette in package.style.themes do
			local sheet, _, stop = sheetFor(package, { theme = palette.name })
			local all = rules(sheet)
			t.expect(all[".game-caption"].TextColor3).toBe(all[".facet-accent"].BackgroundColor3)
			stop()
		end
	end)
end)

return nil
