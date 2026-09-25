--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

local PACKAGES = {
	"neutral",
	"classic_desktop",
	"compact_pointer",
	"fantasy_ornate",
	"fantasy_parchment",
	"glossy_mobile",
	"glossy_touch",
	"pixel_quest",
	"scifi_hud",
}

local INK = { r = 0.97, g = 0.97, b = 0.98 }
local ON_INK = { r = 0.07, g = 0.07, b = 0.08 }

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

local function findAll(root: any, name: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node.Name == name then
			table.insert(found, node)
		end
	end
	return found
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

local INPUTS = { "pointer", "touch", "keyboard", "gamepad" }

local function press(world: World, node: any, input: string)
	local E = world.types.Enum
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
		activate.Released.fire()
	else
		world.gui.SelectedObject = node
		node.Activated.fire({ UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }, 1)
	end
end

local function package(name: string): any
	if name == "neutral" then
		return themes.neutralPackage()
	end
	local module: any = (require :: any)("../examples/themes/" .. name)
	return module.build(themes)
end

local function authored(extra: { [string]: any }): any
	local neutral = themes.neutralPackage()
	local dark = neutral.style.themes[1]
	local merged = table.clone(dark.extra :: any)
	for key, value in extra do
		merged[key] = value
	end
	local built, report = themes.define({
		base = neutral,
		identity = { id = "roles", displayName = "Roles", schemaVersion = themes.SCHEMA, version = "1.0.0" },
		style = { defaultTheme = "Ink", themes = { { name = "Ink", colors = dark.colors, extra = merged } } },
	} :: any)
	assert(built ~= nil, "define failed: " .. tostring(report.errors[1] and report.errors[1].message))
	return built
end

local function withMetrics(metrics: { [string]: any }): any
	local built, report = themes.define({
		base = themes.neutralPackage(),
		identity = { id = "metrics", displayName = "Metrics", schemaVersion = themes.SCHEMA, version = "1.0.0" },
		metrics = metrics,
	} :: any)
	assert(built ~= nil, "define failed: " .. tostring(report.errors[1] and report.errors[1].message))
	return built
end

local function sheetOf(theme: any, preference: number?): (any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local stop, sheet = runtime.mount(function()
		return themes.createStyleSheet(
			runtime,
			theme,
			{ types = engine.types, preferredTransparency = preference or 1, reducedMotion = true } :: any
		)
	end, engine.new("Folder"))
	return sheet, function()
		stop()
		runtime:dispose()
	end
end

local function ruleOf(sheet: any, selector: string): any
	local found
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			found = node
		end
	end
	return found
end

local function lastPriority(sheet: any, selector: string): number
	local last = -math.huge
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			last = math.max(last, node.Priority)
		end
	end
	return last
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

local function same(color: any, rgb: any): boolean
	return color ~= nil
		and math.abs(color.R - rgb.r) < 1e-4
		and math.abs(color.G - rgb.g) < 1e-4
		and math.abs(color.B - rgb.b) < 1e-4
end

t.describe("native parity weaker foundation", function()
	t.it(
		"post-port26-006: an xsmall Button and Chip paint the 28 px plate, the 4 px sides and the 12 px icon, and take every input",
		function()
			local neutral = themes.neutralPackage()
			local sheet, stopSheet = sheetOf(neutral)
			local clicks, chosen = 0, Compose.cell(false)
			local world = setup(function(UI, Host)
				return Host.Frame({
					Name = "Rows",
					UI.Button("Tiny")({
						label = "Go",
						icon = "close",
						trailingIcon = "close",
						controlSize = "xsmall",
						onActivate = function()
							clicks += 1
						end,
					}),
					UI.Chip("TinyChip")({
						label = "Tag",
						selected = chosen,
						controlSize = "xsmall",
						onToggle = function(next: boolean)
							chosen:set(next)
						end,
					}),
				})
			end)
			for _, name in { "Tiny", "TinyChip" } do
				local node = find(world.node, name)
				t.expect(`{name} {node.Size.Y.Offset}`).toBe(`{name} 28`)
				t.expect(node:HasTag("facet-size-xsmall")).toBe(true)
				t.expect(node:GetAttribute("controlSize")).toBe("xsmall")
				t.expect(`{name} {resolve(sheet, node, "PaddingLeft", "UIPadding").Offset}`).toBe(`{name} 4`)
				t.expect(`{name} {resolve(sheet, node, "PaddingRight", "UIPadding").Offset}`).toBe(`{name} 4`)
			end
			local tiny = find(world.node, "Tiny")
			for _, name in { "LeadingIcon", "TrailingIcon" } do
				local icon = find(tiny, name)
				t.expect(`{name} {icon.Size.X.Offset}x{icon.Size.Y.Offset}`).toBe(`{name} 12x12`)
			end
			for index, input in INPUTS do
				press(world, tiny, input)
				t.expect(`{input} {clicks}`).toBe(`{input} {index}`)
				press(world, find(world.node, "TinyChip"), input)
				t.expect(`{input} {chosen:peek()}`).toBe(`{input} {index % 2 == 1}`)
			end
			world.stop()
			stopSheet()

			local ladder = setup(function(UI, Host)
				return Host.Frame({
					Name = "Ladder",
					UI.Button("xsmall")({ label = "A", icon = "close", controlSize = "xsmall" }),
					UI.Button("compact")({ label = "A", icon = "close", controlSize = "compact" }),
					UI.Button("regular")({ label = "A", icon = "close", controlSize = "regular" }),
					UI.Button("large")({ label = "A", icon = "close", controlSize = "large" }),
					UI.Button("plain")({ label = "A", icon = "close" }),
				})
			end)
			for _, rung in { "compact", "regular", "large" } do
				local want = neutral.metrics.controlSizes[rung].iconSize
				t.expect(`{rung} {find(find(ladder.node, rung), "LeadingIcon").Size.X.Offset}`).toBe(`{rung} {want}`)
			end
			local regular = neutral.metrics.controlSizes.regular.iconSize
			t.expect(find(find(ladder.node, "plain"), "LeadingIcon").Size.X.Offset).toBe(regular)
			t.expect(find(find(ladder.node, "xsmall"), "LeadingIcon").Size.X.Offset < regular).toBe(true)
			ladder.stop()

			local rung = Compose.cell("xsmall")
			local live = setup(function(UI, Host)
				return Host.Frame({ UI.Button("Live")({ label = "A", icon = "close", controlSize = rung }) })
			end)
			local icon = find(find(live.node, "Live"), "LeadingIcon")
			t.expect(icon.Size.X.Offset).toBe(12)
			rung:set("large")
			t.expect(icon.Size.X.Offset).toBe(neutral.metrics.controlSizes.large.iconSize)
			live.stop()

			local themed = withMetrics({ controlSizes = { xsmall = { height = 24, paddingX = 8, iconSize = 10 } } })
			local themedSheet, stopThemed = sheetOf(themed)
			local custom = setup(function(UI, Host)
				return Host.Frame({ UI.Button("Tiny")({ label = "Go", icon = "close", controlSize = "xsmall" }) })
			end, { theme = themed })
			local button = find(custom.node, "Tiny")
			t.expect(button.Size.Y.Offset).toBe(24)
			t.expect(resolve(themedSheet, button, "PaddingLeft", "UIPadding").Offset).toBe(8)
			t.expect(find(button, "LeadingIcon").Size.X.Offset).toBe(10)
			custom.stop()
			stopThemed()
		end
	)

	t.it(
		"post-port26-021 post-port26-022 post-port26-023: every shipped package keeps the measured see-through set, and the preference moves only the scrim",
		function()
			local measured = {
				[".facet-appearance-soft"] = true,
				[".facet-appearance-soft:Hover"] = true,
				[".facet-appearance-soft:Press"] = true,
				[".facet-choice-current"] = true,
				[".facet-choice-current:Hover"] = true,
				[".facet-choice-current:Press"] = true,
				[".facet-divider"] = true,
				[".facet-divider-strong"] = true,
				[".facet-grabber"] = true,
				[".facet-menu-hairline"] = true,
				[".facet-scrim"] = true,
			}
			local function census(theme: any, preference: number): ({ [string]: number }, any, () -> ())
				local sheet, stop = sheetOf(theme, preference)
				local found: { [string]: number } = {}
				for _, node in sheet:GetDescendants() do
					if node.ClassName == "StyleRule" then
						local value = node:GetProperties().BackgroundTransparency
						if type(value) == "number" and value > 0 and value < 1 then
							found[node.Selector] = value
						end
					end
				end
				return found, sheet, stop
			end
			for _, name in PACKAGES do
				local theme = package(name)
				local full, sheet, stopFull = census(theme, 1)
				local half, _, stopHalf = census(theme, 0.5)
				for selector in full do
					t.expect(`{name} {selector} {measured[selector] == true}`).toBe(`{name} {selector} true`)
				end
				for _, selector in { ".facet-divider", ".facet-scrim" } do
					t.expect(`{name} {selector} {full[selector] ~= nil}`).toBe(`{name} {selector} true`)
				end
				local strong = ruleOf(sheet, ".facet-divider-strong"):GetProperties().BackgroundTransparency
				t.expect(`{name} {strong < full[".facet-divider"]}`).toBe(`{name} true`)
				t.expect(`{name} {half[".facet-divider-strong"] == full[".facet-divider-strong"]}`).toBe(`{name} true`)
				local moved: { string } = {}
				for selector, value in full do
					if math.abs(value - (half[selector] or -1)) > 1e-9 then
						table.insert(moved, selector)
					end
				end
				t.expect(`{name} {table.concat(moved, " ")}`).toBe(`{name} .facet-scrim`)
				t.expect(math.abs(half[".facet-scrim"] - full[".facet-scrim"] * 0.5) < 1e-9).toBe(true)
				t.expect(ruleOf(sheet, ".facet-divider-strong").Priority > lastPriority(sheet, ".facet-divider"))
					.toBe(true)
				stopFull()
				stopHalf()
			end
		end
	)

	t.it(
		"post-port26-029: only an authoring theme gets hover, press and link mark rules, each after the rule it overrides",
		function()
			for _, name in PACKAGES do
				local theme = package(name)
				local authoring = false
				for _, palette in theme.style.themes do
					if type(palette.extra) == "table" and palette.extra.selection ~= nil then
						authoring = true
					end
				end
				if not authoring then
					local sheet, stop = sheetOf(theme)
					for _, selector in
						{
							".facet-selection-mark.facet-selected:Hover",
							".facet-selection-mark.facet-selected:Press",
							".facet-appearance-link.facet-selected",
						}
					do
						t.expect(`{name} {selector} {ruleOf(sheet, selector) == nil}`).toBe(`{name} {selector} true`)
					end
					local chosen = ruleOf(sheet, ".facet-selection-mark.facet-selected"):GetProperties()
					local wash = theme.style.themes[1].extra.controlSelected
					t.expect(`{name} {same(chosen.BackgroundColor3, wash)}`).toBe(`{name} true`)
					stop()
				end
			end
			local sheet, stop = sheetOf(authored({ selection = INK, onSelection = ON_INK }))
			local chosen = ruleOf(sheet, ".facet-selection-mark.facet-selected")
			t.expect(same(chosen:GetProperties().BackgroundColor3, INK)).toBe(true)
			t.expect(same(chosen:GetProperties().TextColor3, ON_INK)).toBe(true)
			t.expect(chosen.Priority > lastPriority(sheet, ".facet-selected")).toBe(true)
			for _, state in { ":Hover", ":Press" } do
				local rule = ruleOf(sheet, ".facet-selection-mark.facet-selected" .. state)
				t.expect(same(rule:GetProperties().BackgroundColor3, INK)).toBe(true)
				t.expect(rule.Priority > lastPriority(sheet, ".facet-selected" .. state)).toBe(true)
				t.expect(rule.Priority > lastPriority(sheet, ".facet-button" .. state)).toBe(true)
				t.expect(rule.Priority > lastPriority(sheet, ".facet-appearance-utility" .. state)).toBe(true)
			end
			local link = ruleOf(sheet, ".facet-appearance-link.facet-selected")
			t.expect(same(link:GetProperties().TextColor3, INK)).toBe(true)
			t.expect(link.Priority > lastPriority(sheet, ".facet-selected")).toBe(true)
			t.expect(link.Priority > lastPriority(sheet, ".facet-appearance-link")).toBe(true)
			local engine: any = engineLib.new()
			local mark = engine.new("TextButton")
			for _, tag in { "facet-button", "facet-chip", "facet-selection-mark", "facet-selected" } do
				mark:AddTag(tag)
			end
			local icon = engine.new("ImageLabel")
			icon:AddTag("facet-icon")
			icon.Parent = mark
			local caption = engine.new("TextLabel")
			caption:AddTag("facet-text")
			caption.Parent = mark
			t.expect(same(resolve(sheet, icon, "ImageColor3"), ON_INK)).toBe(true)
			t.expect(same(resolve(sheet, caption, "TextColor3"), ON_INK)).toBe(true)
			local linked = engine.new("TextButton")
			for _, tag in { "facet-button", "facet-appearance-link", "facet-selected" } do
				linked:AddTag(tag)
			end
			t.expect(same(resolve(sheet, linked, "TextColor3"), INK)).toBe(true)
			stop()
		end
	)

	t.it("post-port26-034: strokes.utility retunes the utility outline alone and leaves every other stroke", function()
		local function strokes(theme: any): ({ [string]: number }, number?)
			local sheet, stop = sheetOf(theme)
			local found: { [string]: number } = {}
			local utility: number? = nil
			for _, node in sheet:GetChildren() do
				local thickness = node:GetProperties().Thickness
				if type(thickness) == "number" then
					if node.Selector == ".facet-appearance-utility::UIStroke" then
						utility = thickness
					else
						found[node.Selector] = thickness
					end
				end
			end
			stop()
			return found, utility
		end
		local base, baseUtility = strokes(withMetrics({ strokes = { hairline = 1 } }))
		local tuned, tunedUtility = strokes(withMetrics({ strokes = { hairline = 1, utility = 2 } }))
		local bare, bareUtility = strokes(withMetrics({ strokes = { hairline = 1, utility = 0 } }))
		t.expect(baseUtility).toBeNil()
		t.expect(tunedUtility).toBe(2)
		t.expect(bareUtility).toBeNil()
		local count = 0
		for selector, thickness in base do
			count += 1
			t.expect(`{selector} {tuned[selector]}`).toBe(`{selector} {thickness}`)
			t.expect(`{selector} {bare[selector]}`).toBe(`{selector} {thickness}`)
		end
		t.expect(count > 0).toBe(true)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Util")({ label = "Utility", appearance = "utility" }),
				UI.Button("Plain")({ label = "Standard" }),
			})
		end, { theme = withMetrics({ strokes = { hairline = 1, utility = 2 } }) })
		t.expect(find(world.node, "Util"):HasTag("facet-appearance-utility")).toBe(true)
		t.expect(find(world.node, "Plain"):HasTag("facet-appearance-utility")).toBe(false)
		world.stop()
	end)

	t.it(
		"post-port27-006 post-port27-007: on both axes the Track owns a 44 px floor and the thumb runs inside it",
		function()
			for _, axis in { "x", "y" } do
				for _, rung in { "none", "compact", "large" } do
					local value = Compose.cell(50)
					local world = setup(function(UI, Host, engine)
						return Host.Frame({
							Name = "Cell",
							AutomaticSize = engine.types.Enum.AutomaticSize.XY,
							UI.Slider("Vol")({
								label = "Vol",
								value = value,
								min = 0,
								max = 100,
								axis = axis,
								controlSize = if rung == "none" then nil else rung,
								onChange = function(next: number)
									value:set(next)
								end,
							}),
						})
					end)
					local track = find(world.node, "Track")
					local floors = {}
					for _, child in track:GetChildren() do
						if child.ClassName == "UISizeConstraint" then
							table.insert(floors, child)
						end
					end
					t.expect(`{axis} {rung} {#floors}`).toBe(`{axis} {rung} 1`)
					local floor = floors[1]
					t.expect(`{floor.MinSize.X} {floor.MinSize.Y}`).toBe("44 44")
					t.expect(floor.MaxSize.X >= 44 and floor.MaxSize.Y >= 44).toBe(true)
					local along = if axis == "y" then track.Size.Y else track.Size.X
					local flex = track:FindFirstChildWhichIsA("UIFlexItem")
					local fills = along.Scale == 1
						or (flex ~= nil and flex.FlexMode == world.types.Enum.UIFlexMode.Fill)
					t.expect(`{axis} {rung} {fills}`).toBe(`{axis} {rung} true`)
					local thumb = find(track, "Thumb")
					t.expect(thumb ~= nil and thumb:IsDescendantOf(track)).toBe(true)
					world.stop()
				end
			end
		end
	)

	t.it("post-port27-010: a ring shows its value exactly once at every rung, in the gauge for large", function()
		for _, rung in { "xsmall", "compact", "regular", "large" } do
			local world = setup(function(UI, Host)
				return Host.Frame({
					UI.ProgressView("P")({
						value = 0.65,
						presentation = "circular",
						showValue = true,
						controlSize = rung,
						format = function(value: number): string
							return tostring(value)
						end,
					}),
				})
			end)
			local shown = findAll(world.node, "Value")
			t.expect(`{rung} {#shown}`).toBe(`{rung} 1`)
			t.expect(`{rung} {shown[1].Text}`).toBe(`{rung} 0.65`)
			if rung == "large" then
				t.expect(shown[1]:IsDescendantOf(find(world.node, "Gauge"))).toBe(true)
			end
			world.stop()
		end
	end)

	t.it("post-port27-015: the status mark is a sized dot in its status colour, apart from the plate", function()
		for _, name in { "neutral", "pixel_quest", "fantasy_ornate" } do
			local theme = package(name)
			local sheet, stop = sheetOf(theme)
			for _, status in { "warning", "error", "accent", "neutral" } do
				local world = setup(function(UI, Host)
					return Host.Frame({ UI.Badge("B")({ label = "Ready", appearance = "status", status = status }) })
				end, { theme = theme })
				local plate = find(world.node, "B")
				local mark = find(plate, "Status")
				t.expect(`{name} {status} {mark ~= nil and mark.Visible}`).toBe(`{name} {status} true`)
				t.expect(`{name} {status} {mark.Size.X.Offset > 0 and mark.Size.Y.Offset > 0}`)
					.toBe(`{name} {status} true`)
				t.expect(mark:HasTag("facet-status-" .. status)).toBe(true)
				t.expect(find(plate, "Cutout")).toBeNil()
				local ink = resolve(sheet, mark, "BackgroundColor3")
				local paper = resolve(sheet, plate, "BackgroundColor3")
				t.expect(ink ~= nil and paper ~= nil).toBe(true)
				t.expect(`{name} {status} {ink == paper}`).toBe(`{name} {status} false`)
				world.stop()
			end
			stop()
		end
	end)

	t.it(
		"post-port27-016: an unplated utility badge draws no status mark for any status and keeps its words",
		function()
			for _, status in { "neutral", "info", "success", "warning", "error", "accent" } do
				local world = setup(function(UI, Host)
					return Host.Frame({ UI.Badge("B")({ label = "Ready", appearance = "utility", status = status }) })
				end)
				local plate = find(world.node, "B")
				t.expect(`{status} {find(plate, "Status") == nil}`).toBe(`{status} true`)
				local words = false
				for _, node in plate:GetDescendants() do
					if node:IsA("TextLabel") and node.Text == "Ready" then
						words = true
					end
				end
				if plate:IsA("TextLabel") and plate.Text == "Ready" then
					words = true
				end
				t.expect(`{status} {words}`).toBe(`{status} true`)
				world.stop()
			end
		end
	)

	t.it("post-port27-020: an art theme's carve pads the standard plate at every rung, around every part", function()
		for _, name in { "pixel_quest", "fantasy_ornate", "glossy_mobile" } do
			local theme = package(name)
			local carve = ((theme.chrome or {}).panel or {}).contentInsets or {}
			for _, rung in { "xsmall", "compact", "regular", "large" } do
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Notice("Conn")({
							title = "Update available",
							message = "A new track pack is ready.",
							controlSize = rung,
							actions = { { id = "Install", label = "Install", onActivate = function() end } },
							onDismiss = function() end,
						}),
					})
				end, { theme = theme })
				local root = find(world.node, "Conn")
				local padding = root:FindFirstChildWhichIsA("UIPadding")
				local got =
					`{padding.PaddingLeft.Offset} {padding.PaddingRight.Offset} {padding.PaddingTop.Offset} {padding.PaddingBottom.Offset}`
				local want = `{math.max(8, carve.left or 0)} {math.max(8, carve.right or 0)} {math.max(
					8,
					carve.top or 0
				)} {math.max(8, carve.bottom or 0)}`
				t.expect(`{name} {rung} {got}`).toBe(`{name} {rung} {want}`)
				for _, part in { "Title", "Install" } do
					local node = find(root, part)
					t.expect(`{name} {rung} {part} {node ~= nil and node:IsDescendantOf(root)}`)
						.toBe(`{name} {rung} {part} true`)
				end
				world.stop()
			end
		end
	end)

	t.it(
		"post-card-12: a pointer or touch press held on an action keeps the reveal after the pointer leaves",
		function()
			for _, kind in { "MouseButton1", "Touch" } do
				local world = setup(function(UI, Host)
					return Host.Frame({
						UI.Card("C")({
							image = "rbxassetid://1",
							title = "Nebula Racers",
							onActivate = function() end,
							primaryAction = { label = "Play", onActivate = function() end },
							menu = { items = { { id = "hide", label = "Hide", onSelect = function() end } } },
						}),
					})
				end)
				local E = world.types.Enum
				local root = find(world.node, "C")
				local primary = find(root, "Primary")
				root:_fireSignal("MouseEnter")
				t.expect(root:GetAttribute("FacetRevealed")).toBe(true)
				primary.InputBegan.fire({ UserInputType = E.UserInputType[kind] })
				root:_fireSignal("MouseLeave")
				t.expect(`{kind} {root:GetAttribute("FacetPressing")}`).toBe(`{kind} true`)
				t.expect(`{kind} {root:GetAttribute("FacetRevealed")}`).toBe(`{kind} true`)
				primary.InputEnded.fire({ UserInputType = E.UserInputType[kind] })
				t.expect(`{kind} {root:GetAttribute("FacetRevealed")}`).toBe(`{kind} false`)
				primary.InputBegan.fire({ UserInputType = E.UserInputType.Keyboard })
				t.expect(`{kind} {root:GetAttribute("FacetRevealed")}`).toBe(`{kind} false`)
				world.stop()
			end
		end
	)

	t.it(
		"post-card-22: only the card whose browse stop is selected reveals, and a session with no selection reveals none",
		function()
			local stops: { [string]: any } = {}
			local world = setup(function(UI, Host)
				local children: { any } = {}
				for _, key in { "i1", "i2" } do
					table.insert(
						children,
						Host.Frame({
							Name = "Cell" .. key,
							UI.Button("Stop" .. key)({ label = key, onActivate = function() end }),
							UI.Card("Card" .. key)({
								image = "rbxassetid://1",
								title = key,
								browseTarget = function()
									return stops[key]
								end,
								primaryAction = { label = "Play", onActivate = function() end },
							}),
						})
					)
				end
				return Host.Frame(children)
			end)
			for _, key in { "i1", "i2" } do
				stops[key] = find(world.node, "Stop" .. key)
			end
			local function revealed(key: string): boolean
				return find(world.node, "Card" .. key):GetAttribute("FacetRevealed")
			end
			t.expect(revealed("i1") or revealed("i2")).toBe(false)
			world.gui.SelectedObject = stops.i1
			t.expect(find(world.node, "Cardi1"):GetAttribute("FacetBrowsing")).toBe(true)
			t.expect(`{revealed("i1")} {revealed("i2")}`).toBe("true false")
			local card = find(world.node, "Cardi1")
			t.expect(find(card, "Reveal"):IsDescendantOf(card)).toBe(true)
			world.gui.SelectedObject = nil
			t.expect(`{revealed("i1")} {revealed("i2")}`).toBe("false false")
			world.gui.SelectedObject = stops.i1
			world.gui.SelectedObject = stops.i2
			t.expect(`{revealed("i1")} {revealed("i2")}`).toBe("false true")
			world.stop()
		end
	)

	t.it(
		"post-pickers-080: a held removal does not repeat across an input change, inherited disabled refuses every input, and re-enabling restores it",
		function()
			local calls = 0
			local world = setup(function(UI, Host)
				return Host.Frame({
					Name = "Owner",
					UI.Chip("Token")({
						label = "Rain",
						onRemove = function()
							calls += 1
						end,
					}),
				})
			end)
			local E = world.types.Enum
			local token = find(world.node, "Token")
			world.gui.SelectedObject = token
			local activate = assert(action(world.root, "Activate"))
			activate.Pressed.fire()
			t.expect(calls).toBe(1)
			world.input.GamepadEnabled = true
			world.input.PreferredInput = E.PreferredInput.Gamepad
			for _ = 1, 30 do
				world.engine.heartbeat.fire(1 / 60)
			end
			activate.Released.fire()
			t.expect(calls).toBe(1)
			local remove = assert(action(world.root, "RemoveChip"))
			t.expect(keys(remove).Delete and keys(remove).ButtonX).toBe(true)
			remove.Pressed.fire()
			t.expect(calls).toBe(2)
			world.input.PreferredInput = E.PreferredInput.KeyboardAndMouse
			for _ = 1, 30 do
				world.engine.heartbeat.fire(1 / 60)
			end
			remove.Released.fire()
			t.expect(calls).toBe(2)
			local owner = find(world.node, "Owner")
			owner.Interactable = false
			for _, input in INPUTS do
				if input == "keyboard" then
					world.gui.SelectedObject = token
					local bound = action(world.root, "Activate")
					if bound then
						bound.Pressed.fire()
						bound.Released.fire()
					end
				else
					press(world, token, input)
				end
				t.expect(`{input} {calls}`).toBe(`{input} 2`)
			end
			world.gui.SelectedObject = token
			t.expect(action(world.root, "RemoveChip")).toBeNil()
			owner.Interactable = true
			for index, input in INPUTS do
				press(world, token, input)
				t.expect(`{input} {calls}`).toBe(`{input} {2 + index}`)
			end
			world.stop()
		end
	)
end)
