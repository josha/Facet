--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local themes = Facet.themes

type Harness = {
	engine: any,
	runtime: any,
	UI: any,
	Host: any,
	gui: any,
	dispose: () -> (),
}

local function harness(options: { [string]: any }?): Harness
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local config: { [string]: any } = { types = engine.types, guiService = gui, services = { GuiService = gui } }
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	return {
		engine = engine,
		runtime = runtime,
		UI = UI,
		Host = runtime.constructors,
		gui = gui,
		dispose = function()
			runtime:dispose()
		end,
	}
end

local function mount(h: Harness, build: () -> any): (any, () -> ())
	local stop, root = h.runtime.mount(function()
		return h.Host.Frame({ build() })
	end, h.engine.new("ScreenGui"))
	return root, stop
end

local function sheetFor(h: Harness, package: any, options: { [string]: any }?): (any, () -> ())
	local settings: { [string]: any } = { types = h.engine.types, preferredTransparency = 1, reducedMotion = false }
	for key, value in (options or {}) :: { [string]: any } do
		settings[key] = value
	end
	local stop, sheet = h.runtime.mount(function()
		return themes.createStyleSheet(h.runtime, package, settings :: any)
	end, h.engine.new("Folder"))
	return sheet, stop
end

local function ruleNode(sheet: any, selector: string): any
	local found
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			found = node
		end
	end
	assert(found, "No rule: " .. selector)
	return found
end

local function style(sheet: any, selector: string): { [string]: any }
	return ruleNode(sheet, selector):GetProperties()
end

local function hasRule(sheet: any, selector: string): boolean
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			return true
		end
	end
	return false
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

local function tagged(root: any, tag: string): { any }
	local out = {}
	if root:HasTag(tag) then
		table.insert(out, root)
	end
	for _, node in root:GetDescendants() do
		if node:HasTag(tag) then
			table.insert(out, node)
		end
	end
	return out
end

local function color(engine: any, value: any): any
	return engine.types.Color3.new(value.r, value.g, value.b)
end

local function neutralColors(): ({ [string]: any }, { [string]: any })
	local palette = themes.neutralPackage().style.themes[1]
	return palette.colors, palette.extra
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

local function shipped(name: string): (any, any)
	local module: any = (require :: any)("../examples/themes/" .. name)
	local package, report = module.build(themes)
	assert(report.ok, name .. " did not build")
	return package, module
end

local function paletteOf(package: any, palette: any): ({ [string]: any }, { [string]: any })
	local colors, extra = neutralColors()
	local mergedColors, mergedExtra = table.clone(colors), table.clone(extra)
	for key, value in palette.colors or {} do
		mergedColors[key] = value
	end
	for key, value in palette.extra or {} do
		mergedExtra[key] = value
	end
	return mergedColors, mergedExtra
end

local SCANNED_CALLS: { [string]: number? } = { styled = nil, paintedPart = 3 }

local function scanTags(source: string, literals: { [string]: boolean }, prefixes: { [string]: boolean }): { string }
	local dynamic = {}
	for literal in string.gmatch(source, '"(facet%-[%w%-]*)"') do
		if string.sub(literal, -1) == "-" then
			prefixes[literal] = true
		else
			literals[literal] = true
		end
	end
	for name in { styled = true, paintedPart = true } do
		local position = 1
		while true do
			local start, finish = string.find(source, "[%.%s%(]" .. name .. "%(", position)
			if not start then
				break
			end
			local depth, index, args, current = 1, finish + 1, {}, ""
			while depth > 0 do
				local char = string.sub(source, index, index)
				if char == '"' then
					local close = assert(string.find(source, '"', index + 1, true))
					current ..= string.sub(source, index, close)
					index = close + 1
					continue
				end
				if char == "(" or char == "{" or char == "[" then
					depth += 1
				elseif char == ")" or char == "}" or char == "]" then
					depth -= 1
				end
				if depth == 1 and char == "," then
					table.insert(args, current)
					current = ""
				elseif depth > 0 then
					current ..= char
				end
				index += 1
			end
			table.insert(args, current)
			local argument = args[SCANNED_CALLS[name] or #args]
			position = finish + 1
			if argument == nil or string.sub(source, math.max(1, start - 8), start) == "function " then
				continue
			end
			local strings = {}
			for value in string.gmatch(argument, '"([^"]*)"') do
				table.insert(strings, value)
			end
			if #strings == 0 then
				table.insert(dynamic, (string.gsub(string.gsub(argument, "%s+", " "), "^ ", "")))
			elseif string.find(argument, "..", 1, true) then
				prefixes["facet-" .. string.lower(strings[1])] = true
			else
				for _, value in strings do
					literals["facet-" .. string.lower(value)] = true
				end
			end
		end
	end
	return dynamic
end

local function luminance(value: any): number
	local function linear(channel: number): number
		return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
end

local function contrast(first: any, second: any): number
	local a, b = luminance(first), luminance(second)
	return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

t.describe("native parity paint", function()
	t.it("compiles the button role and appearance vocabulary to palette rules above their base states", function()
		local h = harness()
		local colors, extra = neutralColors()
		local package = Compose.cell(themes.neutralPackage())
		local sheet, stop = sheetFor(h, package)
		local function expectColor(selector: string, property: string, value: any)
			t.expect(style(sheet, selector)[property]).toBe(color(h.engine, value))
		end
		expectColor(".facet-role-destructive", "BackgroundColor3", colors.danger)
		expectColor(".facet-role-destructive", "TextColor3", colors.onDanger)
		expectColor(".facet-role-destructive:Hover", "BackgroundColor3", colors.danger)
		expectColor(".facet-role-destructive:Press", "BackgroundColor3", colors.danger)
		expectColor(".facet-role-destructive >> .facet-button-caption", "TextColor3", colors.onDanger)
		expectColor(".facet-role-cancel >> .facet-button-caption", "TextColor3", extra.contentSecondary)
		expectColor(".facet-role-onIndicator >> .facet-button-caption", "TextColor3", colors.onAccent)
		expectColor(".facet-accent", "BackgroundColor3", colors.accent)
		expectColor(".facet-accent", "TextColor3", colors.onAccent)
		expectColor(".facet-accent >> .facet-button-caption", "TextColor3", colors.onAccent)
		expectColor(".facet-appearance-soft", "BackgroundColor3", colors.accent)
		t.expect(style(sheet, ".facet-appearance-soft").BackgroundTransparency).toBe(0.8)
		t.expect(style(sheet, ".facet-appearance-soft:Hover").BackgroundTransparency).toBe(0.7)
		t.expect(style(sheet, ".facet-appearance-soft:Press").BackgroundTransparency).toBe(0.6)
		expectColor(".facet-appearance-soft >> .facet-button-caption", "TextColor3", colors.accent)
		expectColor(".facet-appearance-soft >> .facet-icon", "ImageColor3", colors.accent)
		t.expect(style(sheet, ".facet-appearance-utility").BackgroundTransparency).toBe(1)
		expectColor(".facet-appearance-utility:Hover", "BackgroundColor3", extra.controlHover)
		t.expect(style(sheet, ".facet-appearance-utility:Hover").BackgroundTransparency).toBe(0)
		expectColor(".facet-appearance-utility:Press", "BackgroundColor3", extra.controlPressed)
		t.expect(style(sheet, ".facet-appearance-link").BackgroundTransparency).toBe(1)
		expectColor(".facet-appearance-link", "TextColor3", colors.accent)
		expectColor(".facet-appearance-link >> .facet-button-caption", "TextColor3", colors.accent)
		expectColor(".facet-appearance-link >> .facet-icon", "ImageColor3", colors.accent)
		t.expect(style(sheet, ".facet-appearance-link::UIPadding").PaddingLeft).toBe(h.engine.types.UDim.new(0, 0))
		expectColor(".facet-quiet-destructive", "TextColor3", colors.danger)
		expectColor(".facet-quiet-destructive >> .facet-button-caption", "TextColor3", colors.danger)
		expectColor(".facet-selected", "BackgroundColor3", extra.controlSelected)
		expectColor(".facet-selected", "TextColor3", colors.content)
		t.expect(style(sheet, ".facet-disabled").TextTransparency).toBe(extra.disabledContentOpacity)
		t.expect(style(sheet, ".facet-disabled >> .facet-button-caption").TextTransparency)
			.toBe(extra.disabledContentOpacity)
		expectColor(".facet-button:Hover", "BackgroundColor3", extra.controlHover)
		expectColor(".facet-button:Press", "BackgroundColor3", extra.controlPressed)
		local function priority(selector: string): number
			return ruleNode(sheet, selector).Priority
		end
		for _, base in
			{
				".facet-role-destructive",
				".facet-appearance-soft",
				".facet-appearance-utility",
				".facet-appearance-link",
			}
		do
			for _, state in { ":Hover", ":Press" } do
				t.expect(priority(base .. state) > priority(base)).toBe(true)
				t.expect(priority(base .. state) > priority(".facet-button" .. state)).toBe(true)
			end
		end
		t.expect(priority(".facet-button:Hover") > priority(".facet-button")).toBe(true)
		t.expect(priority(".facet-quiet-destructive") > priority(".facet-appearance-utility")).toBe(true)
		t.expect(
			priority(".facet-quiet-destructive >> .facet-button-caption")
				> priority(".facet-appearance-link >> .facet-button-caption")
		).toBe(true)
		local destructive = ruleNode(sheet, ".facet-role-destructive")
		local retuned = themes.neutralPackage()
		retuned.style.themes[1].colors.danger = { r = 0.5, g = 0, b = 0.1 }
		package:set(retuned)
		t.expect(ruleNode(sheet, ".facet-role-destructive")).toBe(destructive)
		t.expect(destructive:GetProperties().BackgroundColor3).toBe(h.engine.types.Color3.new(0.5, 0, 0.1))
		stop()
		h.dispose()
	end)

	t.it("tags each button role, appearance and corner choice for the matching rule", function()
		local h = harness()
		local role, appearance = Compose.cell("destructive"), Compose.cell("standard")
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Button({ Name = "Reactive", label = "Delete", role = role, appearance = appearance }),
				h.UI.Button({ Name = "Pill", label = "Pill", corners = "pill" }),
				h.UI.Button({ Name = "Square", label = "Square", corners = "square" }),
			})
		end)
		local button = find(root, "Reactive")
		t.expect(button:HasTag("facet-button")).toBe(true)
		t.expect(button:HasTag("facet-role-destructive")).toBe(true)
		t.expect(button:HasTag("facet-role-default")).toBe(false)
		local expected = {
			standard = {},
			emphasis = { "facet-accent" },
			soft = { "facet-appearance-soft" },
			utility = { "facet-appearance-utility", "facet-quiet-destructive" },
			link = { "facet-appearance-link", "facet-quiet-destructive" },
		}
		local all = {
			"facet-accent",
			"facet-appearance-soft",
			"facet-appearance-utility",
			"facet-appearance-link",
			"facet-quiet-destructive",
		}
		for _, name in { "emphasis", "soft", "utility", "link", "standard" } do
			appearance:set(name)
			for _, tag in all do
				t.expect(button:HasTag(tag)).toBe(table.find(expected[name], tag) ~= nil)
			end
		end
		appearance:set("utility")
		role:set("cancel")
		t.expect(button:HasTag("facet-role-cancel")).toBe(true)
		t.expect(button:HasTag("facet-role-destructive")).toBe(false)
		t.expect(button:HasTag("facet-quiet-destructive")).toBe(false)
		role:set("onIndicator")
		t.expect(button:HasTag("facet-role-onIndicator")).toBe(true)
		t.expect(button:HasTag("facet-role-cancel")).toBe(false)
		t.expect(find(root, "Pill"):FindFirstChildWhichIsA("UICorner").CornerRadius).toBe(h.engine.types.UDim.new(1, 0))
		t.expect(find(root, "Square"):FindFirstChildWhichIsA("UICorner").CornerRadius)
			.toBe(h.engine.types.UDim.new(0, 0))
		stop()
		h.dispose()
	end)

	t.it("moves the picker current-option tags with the selection and the indicator choice", function()
		local h = harness()
		local colors = neutralColors()
		local segmented, inline = Compose.cell("a"), Compose.cell("a")
		local indicator = Compose.cell("automatic")
		local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.Host.Frame({
					Name = "Segmented",
					h.UI.Picker({ selected = segmented, style = "segmented", indicator = indicator, options = options }),
				}),
				h.Host.Frame({
					Name = "Inline",
					h.UI.Picker({ selected = inline, style = "inline", options = options }),
				}),
			})
		end)
		local a, b = find(find(root, "Segmented"), "a"), find(find(root, "Segmented"), "b")
		t.expect(a:HasTag("facet-segment")).toBe(true)
		t.expect(a:HasTag("facet-segment-current")).toBe(true)
		t.expect(a:HasTag("facet-selected")).toBe(true)
		t.expect(b:HasTag("facet-segment-current")).toBe(false)
		t.expect(b:HasTag("facet-selected")).toBe(false)
		segmented:set("b")
		t.expect(find(find(root, "Segmented"), "a")).toBe(a)
		t.expect(a:HasTag("facet-segment-current")).toBe(false)
		t.expect(a:HasTag("facet-selected")).toBe(false)
		t.expect(b:HasTag("facet-segment-current")).toBe(true)
		t.expect(b:HasTag("facet-selected")).toBe(true)
		indicator:set("none")
		t.expect(b:HasTag("facet-segment-current")).toBe(true)
		t.expect(b:HasTag("facet-selected")).toBe(true)
		t.expect(find(root, "SelectionIndicator")).toBe(nil)
		indicator:set("underline")
		t.expect(b:HasTag("facet-segment-current")).toBe(false)
		t.expect(b:HasTag("facet-selected")).toBe(false)
		t.expect(find(b, "SelectionIndicator"):HasTag("facet-selection-indicator")).toBe(true)
		indicator:set("pill")
		t.expect(b:HasTag("facet-segment-current")).toBe(true)
		t.expect(find(root, "SelectionIndicator")).toBe(nil)
		local inlineA, inlineB = find(find(root, "Inline"), "a"), find(find(root, "Inline"), "b")
		t.expect(inlineA:HasTag("facet-choice")).toBe(true)
		t.expect(inlineA:HasTag("facet-choice-current")).toBe(true)
		t.expect(inlineA:HasTag("facet-segment-current")).toBe(false)
		t.expect(inlineB:HasTag("facet-choice-current")).toBe(false)
		inline:set("b")
		t.expect(inlineA:HasTag("facet-choice-current")).toBe(false)
		t.expect(inlineB:HasTag("facet-choice-current")).toBe(true)
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
		t.expect(style(sheet, ".facet-segment-current").BackgroundColor3).toBe(color(h.engine, colors.accent))
		t.expect(style(sheet, ".facet-segment-current").BackgroundTransparency).toBe(0)
		t.expect(style(sheet, ".facet-segment-current >> .facet-button-caption").TextColor3)
			.toBe(color(h.engine, colors.onAccent))
		t.expect(style(sheet, ".facet-choice-current").BackgroundColor3).toBe(color(h.engine, colors.accent))
		t.expect(style(sheet, ".facet-choice-current >> .facet-button-caption").TextColor3)
			.toBe(color(h.engine, colors.accent))
		t.expect(style(sheet, ".facet-selection-indicator").BackgroundColor3).toBe(color(h.engine, colors.accent))
		t.expect(ruleNode(sheet, ".facet-segment-current").Priority > ruleNode(sheet, ".facet-segment:Hover").Priority)
			.toBe(true)
		stopSheet()
		stop()
		h.dispose()
	end)

	t.it("keeps the picker menu catcher invisible at every background preference", function()
		local h = harness()
		local presented = Compose.cell(false)
		local _, stop = mount(h, function()
			return h.UI.Picker({
				selected = Compose.cell("a"),
				style = "menu",
				isPresented = presented,
				options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
			})
		end)
		presented:set(true)
		local catchers = {}
		for _, node in h.engine.made do
			if node.Name == "DismissOutside" and not node:isDestroyed() then
				table.insert(catchers, node)
			end
		end
		t.expect(#catchers).toBe(1)
		local catcher = catchers[1]
		t.expect(catcher:HasTag("facet-scrim")).toBe(false)
		for _, preference in { 1, 0, 0.5, 0 / 0 } do
			h.gui.PreferredTransparency = preference
			t.expect(catcher.BackgroundTransparency).toBe(1)
		end
		stop()
		h.dispose()
	end)

	t.it("marks the selected tab by placement and indicator choice", function()
		local h = harness()
		local selection, indicator, placement = Compose.cell("one"), Compose.cell("automatic"), Compose.cell("topBar")
		local root, stop = mount(h, function()
			return h.UI.TabView({
				selection = selection,
				indicator = indicator,
				placement = placement,
				tabs = {
					{
						id = "one",
						label = "One",
						content = function()
							return h.Host.Frame({})
						end,
					},
					{
						id = "two",
						label = "Two",
						content = function()
							return h.Host.Frame({})
						end,
					},
				},
			})
		end)
		local function tab(id: string): any
			for _, node in root:GetDescendants() do
				if
					node:HasTag("facet-tab-item")
					and node:GetAttribute("FacetLabel") == (if id == "one" then "One" else "Two")
				then
					return node
				end
			end
			error("no tab " .. id)
		end
		local one, two = tab("one"), tab("two")
		t.expect(one:HasTag("facet-tab-current")).toBe(true)
		t.expect(two:HasTag("facet-tab-current")).toBe(false)
		t.expect(find(one, "SelectionIndicator"):HasTag("facet-selection-indicator")).toBe(true)
		t.expect(find(two, "SelectionIndicator")).toBe(nil)
		t.expect(one:HasTag("facet-tab-filled")).toBe(false)
		selection:set("two")
		t.expect(find(one, "SelectionIndicator")).toBe(nil)
		t.expect(find(two, "SelectionIndicator") ~= nil).toBe(true)
		t.expect(two:HasTag("facet-tab-current")).toBe(true)
		indicator:set("pill")
		t.expect(find(root, "SelectionIndicator")).toBe(nil)
		t.expect(two:HasTag("facet-selected")).toBe(true)
		indicator:set("none")
		t.expect(find(root, "SelectionIndicator")).toBe(nil)
		t.expect(two:HasTag("facet-selected")).toBe(false)
		indicator:set("automatic")
		placement:set("bottomBar")
		t.expect(find(root, "SelectionIndicator")).toBe(nil)
		t.expect(two:HasTag("facet-tab-filled")).toBe(true)
		t.expect(one:HasTag("facet-tab-filled")).toBe(false)
		placement:set("sidebar")
		t.expect(two:HasTag("facet-tab-filled")).toBe(true)
		indicator:set("none")
		t.expect(two:HasTag("facet-tab-filled")).toBe(false)
		t.expect(two:HasTag("facet-tab-current")).toBe(true)
		local colors = neutralColors()
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
		t.expect(style(sheet, ".facet-tab-filled").BackgroundColor3).toBe(color(h.engine, colors.accent))
		t.expect(style(sheet, ".facet-tab-filled >> .facet-button-caption").TextColor3)
			.toBe(color(h.engine, colors.onAccent))
		t.expect(style(sheet, ".facet-tab-current >> .facet-button-caption").TextColor3)
			.toBe(color(h.engine, colors.content))
		stopSheet()
		stop()
		h.dispose()
	end)

	t.it("paints every value-control own slot solid in every shipped package and palette", function()
		local h = harness()
		local accentSlots = { "slider-thumb", "slider-fill", "toggle-mark", "selection-indicator", "fill" }
		local controlSlots =
			{ "slider-rail", "slider-track", "toggle", "toggle-indicator", "stepper-track", "track", "badge" }
		for _, name in SHIPPED do
			local package = shipped(name)
			for _, palette in package.style.themes do
				local colors, extra = paletteOf(package, palette)
				local sheet, stop = sheetFor(h, package, { theme = palette.name })
				for _, slot in accentSlots do
					local properties = style(sheet, ".facet-" .. slot)
					t.expect(properties.BackgroundTransparency).toBe(0)
					t.expect(properties.BackgroundColor3).toBe(color(h.engine, colors.accent))
				end
				for _, slot in controlSlots do
					local properties = style(sheet, ".facet-" .. slot)
					t.expect(properties.BackgroundTransparency).toBe(0)
					t.expect(properties.BackgroundColor3).toBe(color(h.engine, extra.control))
				end
				t.expect(style(sheet, ".facet-toggle-on").BackgroundColor3).toBe(color(h.engine, colors.accent))
				t.expect(style(sheet, ".facet-toggle-switch >> .facet-toggle-mark").BackgroundColor3)
					.toBe(color(h.engine, colors.onAccent))
				t.expect(style(sheet, ".facet-toggle-check").ImageColor3).toBe(color(h.engine, colors.onAccent))
				t.expect(style(sheet, ".facet-level-on").BackgroundColor3).toBe(color(h.engine, colors.accent))
				t.expect(style(sheet, ".facet-stepper-track::UICorner").CornerRadius)
					.toBe(h.engine.types.UDim.new(0, package.metrics.radii.control))
				t.expect(
					ruleNode(sheet, ".facet-toggle-on").Priority > ruleNode(sheet, ".facet-toggle-indicator").Priority
				)
					.toBe(true)
				stop()
			end
		end
		h.dispose()
	end)

	t.it("tags unskinned value-control slots for their own paint and keeps the tags when skinned", function()
		local function build(h: Harness)
			return mount(h, function()
				return h.Host.Frame({
					h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
					h.UI.Toggle({ Name = "Switch", value = Compose.cell(true), label = "On" }),
					h.UI.Toggle({ Name = "Box", value = Compose.cell(true), label = "Box", presentation = "checkbox" }),
					h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
					h.UI.ProgressView({ Name = "Progress", value = 0.5 }),
				})
			end)
		end
		local plain = harness()
		local root, stop = build(plain)
		local slider = find(root, "Slider")
		t.expect(slider:HasTag("facet-slider")).toBe(true)
		t.expect(find(slider, "Track"):HasTag("facet-slider-track")).toBe(true)
		t.expect(find(slider, "Rail"):HasTag("facet-slider-rail")).toBe(true)
		t.expect(find(slider, "Fill"):HasTag("facet-slider-fill")).toBe(true)
		t.expect(find(slider, "Thumb"):HasTag("facet-slider-thumb")).toBe(true)
		local switch = find(root, "Switch")
		local indicator = find(switch, "Indicator")
		t.expect(switch:HasTag("facet-toggle")).toBe(true)
		t.expect(indicator:HasTag("facet-toggle-indicator")).toBe(true)
		t.expect(indicator:HasTag("facet-toggle-switch")).toBe(true)
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(true)
		t.expect(find(indicator, "Mark"):HasTag("facet-toggle-mark")).toBe(true)
		t.expect(find(find(root, "Box"), "Indicator"):HasTag("facet-toggle-checkbox")).toBe(true)
		t.expect(find(find(root, "Stepper"), "Controls"):HasTag("facet-stepper-track")).toBe(true)
		t.expect(find(root, "Stepper"):HasTag("facet-stepper")).toBe(true)
		t.expect(find(find(root, "Progress"), "Track"):HasTag("facet-track")).toBe(true)
		t.expect(#tagged(find(root, "Progress"), "facet-fill")).toBe(1)
		t.expect(#tagged(root, "facet-skinned")).toBe(0)
		stop()
		plain.dispose()

		local package = themes.neutralPackage()
		package.assets = { art = { content = "rbxassetid://41" } }
		for _, slot in
			{ "sliderTrack", "sliderThumb", "barFill", "barTrack", "toggleTrack", "toggleKnob", "stepperPlate" }
		do
			package.chrome[slot] = { kind = "fill", asset = "art" }
		end
		local skinned = harness({ theme = package })
		local skinnedRoot, stopSkinned = build(skinned)
		local sheet, stopSheet = sheetFor(skinned, package)
		local expectations = {
			{ find(find(skinnedRoot, "Slider"), "Rail"), "facet-slider-rail" },
			{ find(find(skinnedRoot, "Slider"), "Thumb"), "facet-slider-thumb" },
			{ find(find(skinnedRoot, "Slider"), "Fill"), "facet-slider-fill" },
			{ find(find(skinnedRoot, "Switch"), "Indicator"), "facet-toggle-indicator" },
			{ find(find(skinnedRoot, "Switch"), "Mark"), "facet-toggle-mark" },
			{ find(find(skinnedRoot, "Progress"), "Track"), "facet-track" },
			{ find(skinnedRoot, "Stepper"), "facet-stepper" },
		}
		for _, entry in expectations do
			t.expect(entry[1]:HasTag(entry[2])).toBe(true)
			t.expect(entry[1]:HasTag("facet-skinned")).toBe(true)
		end
		local skinnedPriority = ruleNode(sheet, ".facet-skinned").Priority
		t.expect(style(sheet, ".facet-skinned").BackgroundTransparency).toBe(1)
		local checked = 0
		for _, node in tagged(skinnedRoot, "facet-skinned") do
			for _, tag in node:GetTags() do
				for _, rule in sheet:GetChildren() do
					if
						rule.Selector == "." .. tag
						and rule:GetProperties().BackgroundTransparency ~= nil
						and tag ~= "facet-skinned"
					then
						checked += 1
						t.expect(skinnedPriority > rule.Priority).toBe(true)
					end
				end
			end
		end
		t.expect(checked >= #expectations).toBe(true)
		stopSheet()
		stopSkinned()
		skinned.dispose()
	end)

	t.it("repaints corner radii and type roles in place when package metrics change", function()
		local h = harness()
		local UDim = h.engine.types.UDim
		local package = Compose.cell(themes.neutralPackage())
		local sheet, stop = sheetFor(h, package)
		local control, panel, sheetCorner =
			ruleNode(sheet, ".facet-button::UICorner"),
			ruleNode(sheet, ".facet-panel::UICorner"),
			ruleNode(sheet, ".facet-sheet::UICorner")
		local body, button = ruleNode(sheet, ".facet-type-body"), ruleNode(sheet, ".facet-button")
		local count = #sheet:GetChildren()
		t.expect(control:GetProperties().CornerRadius).toBe(UDim.new(0, 8))
		t.expect(panel:GetProperties().CornerRadius).toBe(UDim.new(0, 12))
		for _, role in
			{ "surface", "control", "field", "button", "badge", "track", "skeleton", "avatar", "menu", "tab" }
		do
			t.expect(style(sheet, ".facet-" .. role .. "::UICorner").CornerRadius).toBe(UDim.new(0, 8))
		end
		t.expect(style(sheet, ".facet-sheet::UICorner").CornerRadius).toBe(UDim.new(0, 12))
		t.expect(style(sheet, ".facet-segmented::UICorner").CornerRadius).toBe(UDim.new(0, 10))
		local retuned = themes.neutralPackage()
		retuned.metrics.radii.control = 14
		retuned.metrics.typography.body.size = 19
		retuned.metrics.typography.control.size = 21
		package:set(retuned)
		t.expect(ruleNode(sheet, ".facet-button::UICorner")).toBe(control)
		t.expect(control:GetProperties().CornerRadius).toBe(UDim.new(0, 14))
		t.expect(style(sheet, ".facet-stepper-track::UICorner").CornerRadius).toBe(UDim.new(0, 14))
		t.expect(style(sheet, ".facet-segmented::UICorner").CornerRadius).toBe(UDim.new(0, 16))
		t.expect(panel:GetProperties().CornerRadius).toBe(UDim.new(0, 12))
		t.expect(ruleNode(sheet, ".facet-type-body")).toBe(body)
		t.expect(body:GetProperties().TextSize).toBe(19)
		t.expect(style(sheet, ".facet-text").TextSize).toBe(19)
		t.expect(button:GetProperties().TextSize).toBe(21)
		t.expect(style(sheet, ".facet-button-caption").TextSize).toBe(21)
		local panels = themes.neutralPackage()
		panels.metrics.radii.panel = 20
		package:set(panels)
		t.expect(panel:GetProperties().CornerRadius).toBe(UDim.new(0, 20))
		t.expect(sheetCorner:GetProperties().CornerRadius).toBe(UDim.new(0, 20))
		t.expect(control:GetProperties().CornerRadius).toBe(UDim.new(0, 8))
		panels = themes.neutralPackage()
		panels.metrics.radii.panel = 0
		package:set(panels)
		t.expect(panel:GetProperties().CornerRadius).toBe(UDim.new(0, 0))
		t.expect(#sheet:GetChildren()).toBe(count)
		stop()
		h.dispose()
	end)

	t.it("compiles every type role to native font rules and tags labels with their role", function()
		local h = harness()
		local _, extra = neutralColors()
		local package = Compose.cell(themes.neutralPackage())
		local sheet, stop = sheetFor(h, package)
		local sizes =
			{ caption = 12, label = 14, body = 16, heading = 20, title = 24, control = 18, strong = 16, numeral = 18 }
		local weights = { strong = "SemiBold", numeral = "Bold", heading = "Bold", title = "Bold" }
		for _, role in themes.TYPE_ROLES do
			local properties = style(sheet, ".facet-type-" .. role)
			t.expect(properties.TextSize).toBe(sizes[role])
			t.expect(properties.LineHeight).toBe(1.2)
			t.expect(properties.FontFace).toBe(
				h.engine.types.Font.new(
					"rbxasset://fonts/families/BuilderSans.json",
					(h.engine.types.Enum.FontWeight :: any)[weights[role] or "Regular"],
					h.engine.types.Enum.FontStyle.Normal
				)
			)
			t.expect(properties.TextColor3)
				.toBe(if role == "caption" then color(h.engine, extra.contentSecondary) else nil)
		end
		t.expect(style(sheet, ".facet-button").TextSize).toBe(18)
		t.expect(style(sheet, ".facet-button-caption").FontFace).toBe(style(sheet, ".facet-type-control").FontFace)
		t.expect(style(sheet, ".facet-validation").TextSize).toBe(12)
		t.expect(style(sheet, ".facet-shortcut-hint").TextSize).toBe(12)
		local edited = themes.neutralPackage()
		edited.metrics.typography.title =
			{ size = 31, lineHeight = 1.4, font = { family = "rbxassetid://777", weight = "Heavy", style = "Italic" } }
		edited.metrics.typography.caption.size = 11
		package:set(edited)
		local title = style(sheet, ".facet-type-title")
		t.expect(title.TextSize).toBe(31)
		t.expect(title.LineHeight).toBe(1.4)
		t.expect(title.FontFace).toBe(
			h.engine.types.Font.new(
				"rbxassetid://777",
				h.engine.types.Enum.FontWeight.Heavy,
				h.engine.types.Enum.FontStyle.Italic
			)
		)
		t.expect(style(sheet, ".facet-validation").TextSize).toBe(11)
		local role = Compose.cell("title")
		local root, stopLabels = mount(h, function()
			return h.Host.Frame({
				h.UI.Label({ Name = "Plain", text = "a" }),
				h.UI.Label({ Name = "Bound", text = "b", textRole = role }),
				h.UI.Label({ Name = "Fixed", text = "c", textRole = "numeral" }),
			})
		end)
		t.expect(find(root, "Plain"):HasTag("facet-type-body")).toBe(true)
		t.expect(find(root, "Plain"):HasTag("facet-text")).toBe(true)
		t.expect(find(root, "Fixed"):HasTag("facet-type-numeral")).toBe(true)
		local bound = find(root, "Bound")
		for _, next in themes.TYPE_ROLES do
			role:set(next)
			for _, other in themes.TYPE_ROLES do
				t.expect(bound:HasTag("facet-type-" .. other)).toBe(other == next)
			end
			t.expect(hasRule(sheet, ".facet-type-" .. next)).toBe(true)
		end
		t.expect(ruleNode(sheet, ".facet-type-title").Priority > ruleNode(sheet, ".facet-text").Priority).toBe(true)
		stopLabels()
		stop()
		h.dispose()
	end)

	t.it("compiles palette chrome gradients to UIGradient rules and removes them with the palette", function()
		local h = harness()
		local package = themes.neutralPackage()
		local dark = package.style.themes[1]
		local light = table.clone(dark)
		light.name = "Light"
		dark.extra = table.clone(dark.extra)
		dark.extra.chromeGradient = {
			panel = {
				rotation = 45,
				stops = { { t = 0, r = 1, g = 0, b = 0 }, { t = 1, r = 0, g = 0, b = 1 } },
				alpha = { { t = 0, v = 0 }, { t = 1, v = 0.5 } },
			},
			control = { stops = { { t = 0, r = 1, g = 1, b = 1 }, { t = 1, r = 0, g = 0, b = 0 } } },
			badge = { stops = { { t = 0, r = 1, g = 1, b = 1 } } },
		}
		table.insert(package.style.themes, light)
		local defined = assert(themes.define(package))
		local palette = Compose.cell("Dark")
		local sheet, stop = sheetFor(h, defined, { theme = palette })
		local panel = style(sheet, ".facet-panel::UIGradient")
		t.expect(typeof(panel.Color)).toBe("ColorSequence")
		t.expect(#panel.Color.Keypoints).toBe(2)
		t.expect(panel.Color.Keypoints[1].Value).toBe(h.engine.types.Color3.new(1, 0, 0))
		t.expect(panel.Color.Keypoints[2].Value).toBe(h.engine.types.Color3.new(0, 0, 1))
		t.expect(panel.Rotation).toBe(45)
		t.expect(typeof(panel.Transparency)).toBe("NumberSequence")
		t.expect(panel.Transparency.Keypoints[2].Value).toBe(0.5)
		local control = style(sheet, ".facet-control::UIGradient")
		t.expect(control.Rotation).toBe(90)
		t.expect(control.Transparency).toBe(nil)
		t.expect(hasRule(sheet, ".facet-badge::UIGradient")).toBe(false)
		local node = ruleNode(sheet, ".facet-panel::UIGradient")
		palette:set("Light")
		t.expect(node.isDestroyed()).toBe(true)
		t.expect(hasRule(sheet, ".facet-panel::UIGradient")).toBe(false)
		t.expect(hasRule(sheet, ".facet-control::UIGradient")).toBe(false)
		palette:set("Dark")
		t.expect(style(sheet, ".facet-panel::UIGradient").Rotation).toBe(45)
		stop()
		for _, name in { "scifi_hud", "glossy_mobile" } do
			local shipped, _ = shipped(name)
			for _, entry in shipped.style.themes do
				local gradients = (entry.extra or {}).chromeGradient
				t.expect(gradients ~= nil).toBe(true)
				local shippedSheet, stopShipped = sheetFor(h, shipped, { theme = entry.name })
				local compiled = 0
				for _, rule in shippedSheet:GetChildren() do
					if string.sub(rule.Selector, -12) == "::UIGradient" then
						compiled += 1
						t.expect(typeof(rule:GetProperties().Color)).toBe("ColorSequence")
					end
				end
				local declared = 0
				for _, gradient in gradients do
					declared += 1
					for _, stop in gradient.alpha or {} do
						t.expect(stop.v >= 0 and stop.v <= 0.35).toBe(true)
					end
				end
				t.expect(compiled).toBe(declared)
				t.expect(compiled >= if name == "scifi_hud" then 3 else 1).toBe(true)
				stopShipped()
			end
		end
		h.dispose()
	end)

	t.it("orders rule priority by declaration with states after rests and package rules last", function()
		local h = harness()
		local package = themes.neutralPackage()
		package.rules = {
			{ selector = ".game-x", properties = { BackgroundTransparency = 0.3 } },
			{ selector = ".facet-button", properties = { BackgroundColor3 = h.engine.types.Color3.new(1, 0, 1) } },
		}
		local sheet, stop = sheetFor(h, package)
		local previous = -1
		local builtIn = 0
		for _, rule in sheet:GetChildren() do
			t.expect(rule.Priority > previous).toBe(true)
			previous = rule.Priority
			if
				rule.Selector ~= ".game-x"
				and not (
					rule.Selector == ".facet-button"
					and rule:GetProperties().BackgroundColor3 == h.engine.types.Color3.new(1, 0, 1)
				)
			then
				builtIn = math.max(builtIn, rule.Priority)
			end
		end
		local children = sheet:GetChildren()
		t.expect(children[#children - 1].Selector).toBe(".game-x")
		t.expect(children[#children].Selector).toBe(".facet-button")
		t.expect(children[#children - 1].Priority > builtIn).toBe(true)
		t.expect(ruleNode(sheet, ".facet-button").Priority).toBe(children[#children].Priority)
		local function first(selector: string): any
			for _, rule in children do
				if rule.Selector == selector then
					return rule
				end
			end
			return nil
		end
		t.expect(first(".facet-button:Hover").Priority > first(".facet-button").Priority).toBe(true)
		t.expect(first(".facet-skinned").Priority > first(".facet-button").Priority).toBe(true)
		t.expect(first(".facet-skinned").Priority > first(".facet-surface").Priority).toBe(true)
		t.expect(first(".facet-type-body").Priority > first(".facet-text").Priority).toBe(true)
		t.expect(first(".facet-selected").Priority > first(".facet-button:Press").Priority).toBe(true)
		stop()
		h.dispose()
	end)

	t.it("keeps an icon badge icon through reactive status paint and switches badge appearances", function()
		local h = harness()
		local colors, extra = neutralColors()
		local status, appearance = Compose.cell("neutral"), Compose.cell("status")
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Badge({ Name = "Iconic", label = "Ready", icon = "checkmark", status = status }),
				h.UI.Badge({ Name = "Live", label = "Live", status = "error", appearance = appearance }),
			})
		end)
		local pill = find(root, "Iconic")
		local icon = pill:FindFirstChildWhichIsA("ImageLabel")
		t.expect(icon:HasTag("facet-icon")).toBe(true)
		t.expect(pill:HasTag("facet-badge")).toBe(true)
		local statuses = { "neutral", "info", "success", "warning", "error", "accent" }
		for _, next in statuses do
			status:set(next)
			for _, other in statuses do
				t.expect(pill:HasTag("facet-status-" .. other)).toBe(other == next)
			end
			t.expect(pill:FindFirstChildWhichIsA("ImageLabel")).toBe(icon)
			t.expect(icon.Image ~= "").toBe(true)
		end
		local live = find(root, "Live")
		t.expect(live:HasTag("facet-badge-status")).toBe(true)
		t.expect(find(live, "Status"):HasTag("facet-status-error")).toBe(true)
		appearance:set("utility")
		t.expect(live:HasTag("facet-badge-utility")).toBe(true)
		t.expect(live:HasTag("facet-badge-status")).toBe(false)
		t.expect(find(live, "Status")).toBe(nil)
		appearance:set("standard")
		t.expect(live:HasTag("facet-badge-standard")).toBe(true)
		t.expect(live:HasTag("facet-badge-utility")).toBe(false)
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
		local partners = {
			neutral = { extra.contentSecondary, colors.surface },
			info = { colors.accent, colors.onAccent },
			success = { colors.success, colors.onSuccess },
			warning = { colors.warning, colors.onWarning },
			error = { colors.danger, colors.onDanger },
			accent = { colors.accent, colors.onAccent },
		}
		for name, pair in partners do
			t.expect(style(sheet, ".facet-status-" .. name).BackgroundColor3).toBe(color(h.engine, pair[1]))
			t.expect(style(sheet, ".facet-status-" .. name .. " > .facet-icon").ImageColor3)
				.toBe(color(h.engine, pair[2]))
			t.expect(style(sheet, ".facet-status-" .. name .. " > .facet-text").TextColor3)
				.toBe(color(h.engine, pair[2]))
			t.expect(ruleNode(sheet, ".facet-status-" .. name).Priority > ruleNode(sheet, ".facet-badge").Priority)
				.toBe(true)
		end
		t.expect(style(sheet, ".facet-badge-utility").BackgroundTransparency).toBe(1)
		t.expect(style(sheet, ".facet-badge-utility > .facet-text").TextColor3)
			.toBe(color(h.engine, extra.contentSecondary))
		t.expect(style(sheet, ".facet-badge-status").BackgroundColor3).toBe(color(h.engine, extra.control))
		t.expect(ruleNode(sheet, ".facet-badge-utility").Priority > ruleNode(sheet, ".facet-status-error").Priority)
			.toBe(true)
		t.expect(style(sheet, ".facet-badge").BackgroundTransparency).toBe(0)
		stopSheet()
		stop()
		h.dispose()
	end)

	t.it("skins the badge seal from the package badge slot and removes it with the package", function()
		local package = themes.neutralPackage()
		package.assets = { seal = { content = "rbxassetid://77" } }
		package.chrome.badge = {
			kind = "nineSlice",
			asset = "seal",
			contentInsets = { top = 5, right = 5, bottom = 5, left = 5 },
		}
		local selected = Compose.cell(package)
		local h = harness({ theme = selected })
		local root, stop = mount(h, function()
			return h.UI.Badge({ Name = "Seal", label = "3" })
		end)
		local badge = find(root, "Seal")
		t.expect(find(badge, "badge1").Image).toBe("rbxassetid://77")
		t.expect(find(badge, "badge1").Visible).toBe(true)
		t.expect(badge:HasTag("facet-skinned")).toBe(true)
		local sheet, stopSheet = sheetFor(h, package)
		t.expect(style(sheet, ".facet-badge::UIPadding").PaddingTop).toBe(h.engine.types.UDim.new(0, 5))
		t.expect(style(sheet, ".facet-badge::UIPadding").PaddingLeft).toBe(h.engine.types.UDim.new(0, 8))
		stopSheet()
		selected:set(themes.neutralPackage())
		t.expect(badge:HasTag("facet-skinned")).toBe(false)
		local art = find(badge, "badge1")
		t.expect(art == nil or art.Visible == false).toBe(true)
		stop()
		h.dispose()
	end)

	t.it("blends a bound dimmed async image and restores it", function()
		local h = harness()
		local dimmed = Compose.cell(false)
		local root, stop = mount(h, function()
			return h.UI.AsyncImage({ Name = "Art", image = "rbxassetid://1", dimmed = dimmed })
		end)
		local image = find(find(root, "Art"), "Image")
		t.expect(image.ImageTransparency).toBe(0)
		dimmed:set(true)
		t.expect(image.ImageTransparency).toBe(0.35)
		dimmed:set(false)
		t.expect(image.ImageTransparency).toBe(0)
		stop()
		h.dispose()
	end)

	t.it("lets per-view slider images replace the theme skin on that node only", function()
		local package = themes.neutralPackage()
		package.assets = { thumb = { content = "rbxassetid://5" }, rail = { content = "rbxassetid://6" } }
		package.chrome.sliderThumb = { kind = "nineSlice", asset = "thumb" }
		package.chrome.sliderTrack = { kind = "nineSlice", asset = "rail" }
		for _, theme in { package, themes.neutralPackage() } do
			local h = harness({ theme = theme })
			local root, stop = mount(h, function()
				return h.Host.Frame({
					h.UI.Slider({
						Name = "Both",
						value = Compose.cell(0.5),
						thumbImage = "rbxassetid://9",
						trackImage = "rbxassetid://8",
					}),
					h.UI.Slider({ Name = "ThumbOnly", value = Compose.cell(0.5), thumbImage = "rbxassetid://9" }),
				})
			end)
			local both = find(root, "Both")
			t.expect(find(find(both, "Thumb"), "Artwork").Image).toBe("rbxassetid://9")
			t.expect(find(find(both, "Rail"), "Artwork").Image).toBe("rbxassetid://8")
			t.expect(find(both, "sliderThumb1")).toBe(nil)
			t.expect(find(both, "sliderTrack1")).toBe(nil)
			t.expect(find(both, "Thumb"):HasTag("facet-slider-thumb")).toBe(true)
			local thumbOnly = find(root, "ThumbOnly")
			t.expect(find(find(thumbOnly, "Thumb"), "Artwork").Image).toBe("rbxassetid://9")
			t.expect(find(thumbOnly, "sliderThumb1")).toBe(nil)
			t.expect(find(find(thumbOnly, "Rail"), "Artwork")).toBe(nil)
			if theme == package then
				t.expect(find(find(thumbOnly, "Rail"), "sliderTrack1").Image).toBe("rbxassetid://6")
				t.expect(find(thumbOnly, "Rail"):HasTag("facet-skinned")).toBe(true)
			else
				t.expect(find(thumbOnly, "sliderTrack1")).toBe(nil)
			end
			stop()
			h.dispose()
		end
	end)

	t.it("leaves icon tint and transparency to the style sheet", function()
		local writes: { string } = {}
		local package = themes.neutralPackage()
		local h = harness({ theme = package })
		local original = h.engine.new
		h.engine.new = function(className: string)
			local node = original(className)
			if className == "ImageLabel" then
				local meta = getmetatable(node)
				local assign = meta.__newindex
				meta.__newindex = function(self, key, value)
					table.insert(writes, key)
					assign(self, key, value)
				end
			end
			return node
		end
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Label({ text = "Close", icon = "close" }),
				h.UI.Button({ label = "Go", icon = "checkmark", role = "destructive" }),
				h.UI.Badge({ label = "New", icon = "checkmark", status = "success" }),
			})
		end)
		local icons = tagged(root, "facet-icon")
		t.expect(#icons >= 3).toBe(true)
		t.expect(#writes > 0).toBe(true)
		t.expect(table.find(writes, "ImageColor3")).toBe(nil)
		t.expect(table.find(writes, "ImageTransparency")).toBe(nil)
		local colors = neutralColors()
		local sheet, stopSheet = sheetFor(h, package)
		t.expect(style(sheet, ".facet-icon").ImageColor3).toBe(color(h.engine, colors.content))
		t.expect(style(sheet, ".facet-icon").BackgroundTransparency).toBe(1)
		stopSheet()
		stop()
		h.dispose()
	end)

	t.it("tints framework icons with the content role of each palette and never leaves them white", function()
		local h = harness()
		local package = themes.neutralPackage()
		local dark = package.style.themes[1]
		local light = table.clone(dark)
		light.name = "Light"
		light.colors = table.clone(dark.colors)
		light.colors.content = { r = 0.1, g = 0.15, b = 0.2 }
		package.style.themes = { dark, light }
		local white = h.engine.types.Color3.new(1, 1, 1)
		for _, palette in package.style.themes do
			local colors = paletteOf(package, palette)
			local sheet, stop = sheetFor(h, package, { theme = palette.name })
			local tint = style(sheet, ".facet-icon").ImageColor3
			t.expect(tint).toBe(color(h.engine, colors.content))
			t.expect(tint == white).toBe(false)
			stop()
		end
		for _, name in SHIPPED do
			local shippedPackage = shipped(name)
			for _, palette in shippedPackage.style.themes do
				local colors = paletteOf(shippedPackage, palette)
				local sheet, stop = sheetFor(h, shippedPackage, { theme = palette.name })
				t.expect(style(sheet, ".facet-icon").ImageColor3).toBe(color(h.engine, colors.content))
				stop()
			end
		end
		h.dispose()
	end)

	t.it("re-letters the icon on a status plate with the plate partner color as a direct child", function()
		local partners = {
			neutral = "surface",
			info = "onAccent",
			success = "onSuccess",
			warning = "onWarning",
			error = "onDanger",
			accent = "onAccent",
		}
		local h = harness({ theme = themes.neutralPackage() })
		local package = themes.neutralPackage()
		for _, palette in package.style.themes do
			local colors, extra = paletteOf(package, palette)
			local sheet, stop = sheetFor(h, package, { theme = palette.name })
			local base = ruleNode(sheet, ".facet-icon").Priority
			for status, partner in partners do
				local selector = ".facet-status-" .. status .. " > .facet-icon"
				local expected = colors[partner] or extra[partner]
				t.expect(expected ~= nil).toBe(true)
				t.expect(style(sheet, selector).ImageColor3).toBe(color(h.engine, expected))
				t.expect(ruleNode(sheet, selector).Priority > base).toBe(true)
				t.expect(ruleNode(sheet, selector).Priority > ruleNode(sheet, ".facet-icon-" .. status).Priority)
					.toBe(true)
			end
			stop()
		end
		local status = Compose.cell("warning")
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Badge({ Name = "Warn", label = "!", icon = "status.warning", status = status }),
				h.UI.Badge({ Name = "Fail", label = "!", icon = "status.error", status = "error" }),
			})
		end)
		for name, tag in { Warn = "facet-status-warning", Fail = "facet-status-error" } do
			local plate = find(root, name)
			t.expect(plate:HasTag(tag)).toBe(true)
			local icons = tagged(plate, "facet-icon")
			t.expect(#icons).toBe(1)
			t.expect(icons[1].Parent).toBe(plate)
			t.expect(icons[1].ClassName).toBe("ImageLabel")
		end
		local warn = find(root, "Warn")
		local icon = tagged(warn, "facet-icon")[1]
		status:set("error")
		t.expect(warn:HasTag("facet-status-error")).toBe(true)
		t.expect(warn:HasTag("facet-status-warning")).toBe(false)
		t.expect(tagged(warn, "facet-icon")[1]).toBe(icon)
		t.expect(icon.Parent).toBe(warn)
		stop()
		h.dispose()
	end)

	t.it(
		"keeps the selected label readable on the selection fill and its sampled art in every shipped theme",
		function()
			local h = harness()
			for _, name in SHIPPED do
				local package = shipped(name)
				for _, palette in package.style.themes do
					local colors, extra = paletteOf(package, palette)
					local label = extra.onSelected or colors.content
					t.expect(contrast(label, extra.controlSelected) >= 4.5).toBe(true)
					local sheet, stop = sheetFor(h, package, { theme = palette.name })
					t.expect(style(sheet, ".facet-selected").TextColor3).toBe(color(h.engine, label))
					t.expect(style(sheet, ".facet-selected >> .facet-text").TextColor3).toBe(color(h.engine, label))
					t.expect(style(sheet, ".facet-selected >> .facet-icon").ImageColor3).toBe(color(h.engine, label))
					t.expect(style(sheet, ".facet-selected").BackgroundColor3)
						.toBe(color(h.engine, extra.controlSelected))
					stop()
				end
			end
			local serde = require("@lune/serde")
			local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
			local checked = 0
			for key, entry in samples do
				for _, sample in entry do
					t.expect(serde.hash("sha256", fs.readFile(sample.file))).toBe(sample.sha256)
				end
				local plate = entry.selected
				if plate then
					local package = shipped((string.gsub(key, "-", "_")))
					local art = { r = plate.r / 255, g = plate.g / 255, b = plate.b / 255 }
					for _, palette in package.style.themes do
						local colors, extra = paletteOf(package, palette)
						t.expect(contrast(extra.onSelected or colors.content, art) >= 4.5).toBe(true)
						checked += 1
					end
				end
			end
			t.expect(checked >= 4).toBe(true)
			h.dispose()
		end
	)

	t.it("keeps a selected toggle row label on the content color over its clear row", function()
		local h = harness()
		for _, name in SHIPPED do
			local package = shipped(name)
			for _, palette in package.style.themes do
				local colors = paletteOf(package, palette)
				local sheet, stop = sheetFor(h, package, { theme = palette.name })
				local row = style(sheet, ".facet-toggle-row")
				t.expect(row.BackgroundTransparency).toBe(1)
				t.expect(style(sheet, ".facet-toggle-row.facet-selected").TextColor3)
					.toBe(color(h.engine, colors.content))
				t.expect(style(sheet, ".facet-toggle-row.facet-selected >> .facet-text").TextColor3)
					.toBe(color(h.engine, colors.content))
				stop()
			end
		end
		h.dispose()
	end)

	t.it(
		"drops hover paint while touch is the preferred input, so a tapped control does not keep a hover tint",
		function()
			local h = harness()
			local hover = Compose.cell(true)
			local sheet, stop = sheetFor(h, themes.neutralPackage(), { hover = hover })
			t.expect(hasRule(sheet, ".facet-button:Hover")).toBe(true)
			t.expect(hasRule(sheet, ".facet-button:Press")).toBe(true)
			hover:set(false)
			for _, node in sheet:GetChildren() do
				t.expect(string.find(node.Selector, ":Hover", 1, true)).toBe(nil)
			end
			t.expect(hasRule(sheet, ".facet-button:Press")).toBe(true)
			t.expect(hasRule(sheet, ".facet-button")).toBe(true)
			hover:set(true)
			t.expect(hasRule(sheet, ".facet-button:Hover")).toBe(true)
			stop()
			h.dispose()
		end
	)

	t.it("treats a garbage transparency preference as the identity", function()
		local h = harness()
		local preference = Compose.cell(1 :: any)
		local sheet, stop = sheetFor(h, themes.neutralPackage(), { preferredTransparency = preference })
		local authored = style(sheet, ".facet-scrim").BackgroundTransparency
		for _, value in { 0 / 0, "x", false, math.huge / math.huge } do
			preference:set(value)
			t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(authored)
		end
		preference:set(-3)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(0)
		preference:set(7)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBe(authored)
		stop()
		local presented = Compose.cell(true)
		local root, stopAlert = mount(h, function()
			return h.UI.Alert({
				isPresented = presented,
				title = "Title",
				message = "Message",
				actions = { { id = "ok", label = "OK", role = "default" } },
			})
		end)
		local catcher
		for _, node in h.engine.made do
			if node.Name == "DismissOutside" and not node:isDestroyed() then
				catcher = node
			end
		end
		t.expect(catcher ~= nil).toBe(true)
		h.gui.PreferredTransparency = 0 / 0
		local value = catcher.BackgroundTransparency
		t.expect(value == value).toBe(true)
		t.expect(root ~= nil).toBe(true)
		stopAlert()
		h.dispose()
	end)

	t.it("scales only the scrim backdrop by the transparency preference", function()
		local h = harness()
		local package = themes.neutralPackage()
		package.rules = { { selector = ".game-glass", properties = { BackgroundTransparency = 0.5 } } }
		local preference = Compose.cell(1)
		local sheet, stop = sheetFor(h, package, { preferredTransparency = preference })
		local before: { [any]: any } = {}
		for _, rule in sheet:GetChildren() do
			before[rule] = rule:GetProperties()
		end
		for _, value in { 0.5, 0 } do
			preference:set(value)
			local changed = {}
			for _, rule in sheet:GetChildren() do
				local properties = rule:GetProperties()
				for key, previous in before[rule] do
					if properties[key] ~= previous then
						table.insert(changed, rule.Selector .. "." .. key)
					end
				end
			end
			t.expect(#changed).toBe(1)
			t.expect(changed[1]).toBe(".facet-scrim.BackgroundTransparency")
			t.expect(style(sheet, ".facet-scrim").BackgroundTransparency)
				.toBe(before[ruleNode(sheet, ".facet-scrim")].BackgroundTransparency * value)
		end
		t.expect(style(sheet, ".facet-divider").BackgroundTransparency).toBe(0.92)
		t.expect(style(sheet, ".facet-appearance-soft").BackgroundTransparency).toBe(0.8)
		t.expect(style(sheet, ".facet-choice-current").BackgroundTransparency).toBe(0.82)
		t.expect(style(sheet, ".game-glass").BackgroundTransparency).toBe(0.5)
		t.expect(style(sheet, ".facet-disabled").TextTransparency).toBe(0.4)
		stop()
		h.dispose()
	end)

	t.it("insets and paints the recipe dividers from the installed theme", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local theme = Compose.cell(themes.neutralPackage())
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = engine.new("Folder"),
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			theme = theme,
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					services = { GuiService = gui },
					theme = theme,
					reducedMotion = true,
				} :: any
			),
		}
		local recipes: any = (require :: any)("../examples/gallery/scenarios/recipes_common")
		local built
		local stop, root = runtime.mount(function()
			built = recipes.build(ctx)
			return ctx.Host.ScreenGui("DemoScreen")({ built.screen() })
		end, engine.new("Folder"))
		local UDim = engine.types.UDim
		local function check(package: any)
			local m, hairline = package.metrics.space.m, package.metrics.strokes.hairline
			local expected = {
				DividerFull = { 0, 0 },
				DividerLeading = { m, 0 },
				DividerTrailing = { 0, m },
				DividerBoth = { m, m },
				DividerHeavy = { 0, 0 },
			}
			for name, sides in expected do
				local divider = find(root, name)
				local padding = find(divider, "Pad"):FindFirstChildWhichIsA("UIPadding")
				t.expect(padding.PaddingLeft).toBe(UDim.new(0, sides[1]))
				t.expect(padding.PaddingRight).toBe(UDim.new(0, sides[2]))
				t.expect(padding.PaddingTop).toBe(UDim.new(0, 0))
				local line = find(divider, "Line")
				t.expect(line:HasTag("facet-divider")).toBe(true)
				t.expect(line.Size.Y.Offset).toBe(if name == "DividerHeavy" then 3 * hairline else hairline)
			end
		end
		check(theme:peek())
		local pointer = shipped("compact_pointer")
		theme:set(pointer)
		t.expect(pointer.metrics.space.m ~= 16).toBe(true)
		check(pointer)
		local thick = themes.neutralPackage()
		thick.metrics.strokes.hairline = 2
		thick.metrics.space.m = 22
		theme:set(thick)
		check(thick)
		local sheet, stopSheet = sheetFor(harness(), thick)
		t.expect(style(sheet, ".facet-divider").BackgroundTransparency).toBe(0.92)
		stopSheet()
		stop()
		runtime:dispose()
	end)

	t.it("marks the active word row and pending crossword tiles without relying on color", function()
		local function world(): any
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local target = engine.new("Folder")
			local viewport = Compose.cell({ width = 800, height = 600 })
			return {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				types = engine.types,
				inputTarget = target,
				worldTarget = engine.new("Folder"),
				guiService = engine.new("GuiService"),
				viewport = viewport,
				runService = { Heartbeat = engine.heartbeat },
				target = target,
				engine = engine,
				UI = Facet.controls(runtime, { types = engine.types, viewport = viewport } :: any),
			}
		end
		local function start(ctx: any, definition: any): (any, any, () -> ())
			local game
			local stop, node = ctx.runtime.mount(function()
				game = definition.build(ctx)
				return ctx.Host.ScreenGui("GameScreen")({ game.screen() })
			end, ctx.target)
			return game, node, function()
				stop()
				ctx.runtime:dispose()
			end
		end
		local word: any = (require :: any)("../examples/gallery/examples/05_word_game")
		local seed
		for candidate = 1, 100000 do
			if word.rules.solutionForSeed(candidate) == "REACT" then
				seed = candidate
				break
			end
		end
		local ctx = world()
		local game, node, stop = start(ctx, word)
		game.restart(seed)
		local function outlined(row: number): boolean
			local enabled = nil
			for column = 1, word.rules.COLS do
				local outline = find(find(node, `tile{row}_{column}`), "ActiveRow")
				t.expect(outline.ClassName).toBe("UIStroke")
				t.expect(outline:HasTag("facet-status-ring")).toBe(true)
				if enabled == nil then
					enabled = outline.Enabled
				end
				t.expect(outline.Enabled).toBe(enabled)
			end
			return enabled == true
		end
		t.expect(outlined(1)).toBe(true)
		t.expect(outlined(2)).toBe(false)
		t.expect(game.mark(1, 1)).toBe("_")
		game.press("R")
		t.expect(outlined(1)).toBe(true)
		for _, letter in { "U", "L", "E", "S" } do
			game.press(letter)
		end
		local function key(letter: string): any
			return find(node, "key_" .. letter)
		end
		t.expect(key("R"):HasTag("facet-status-success")).toBe(false)
		game.press("Return")
		t.expect(game.keyState("R")).toBe("correct")
		t.expect(game.keyState("U")).toBe("absent")
		t.expect(game.keyState("E")).toBe("present")
		t.expect(key("R"):HasTag("facet-status-success")).toBe(true)
		t.expect(key("U"):HasTag("facet-status-neutral")).toBe(true)
		t.expect(key("E"):HasTag("facet-status-warning")).toBe(true)
		t.expect(find(find(node, "tile1_1"), "fill"):HasTag("facet-status-success")).toBe(true)
		t.expect(game.activeRow()).toBe(2)
		t.expect(outlined(1)).toBe(false)
		t.expect(outlined(2)).toBe(true)
		for _, letter in { "R", "E", "A", "C", "T" } do
			game.press(letter)
		end
		game.press("Return")
		t.expect(game.phase()).toBe("won")
		for row = 1, word.rules.ROWS do
			t.expect(outlined(row)).toBe(false)
		end
		stop()

		local tile: any = (require :: any)("../examples/gallery/examples/06_tile_game")
		local tileCtx = world()
		local board, boardNode, stopBoard = start(tileCtx, tile)
		for _, move in { { 1, 4, 1 }, { 3, 4, 2 }, { 5, 4, 3 }, { 6, 4, 4 }, { 2, 4, 5 } } do
			board.select(move[1])
			board.place(move[2], move[3])
		end
		board.submit()
		t.expect(board.turn()).toBe(2)
		board.select(4)
		board.place(2, 5)
		t.expect(board.cellState(4, 1)).toBe("committed")
		t.expect(board.cellState(2, 5)).toBe("pending")
		local committed = find(find(boardNode, "cell4_1"), "tap")
		local pending = find(find(boardNode, "cell2_5"), "tap")
		t.expect(board.cellSurface(4, 1)).toBe("raised")
		t.expect(board.cellSurface(2, 5)).toBe("chip")
		t.expect(string.find(committed.Text, "~", 1, true)).toBe(nil)
		t.expect(string.sub(pending.Text, -1)).toBe("~")
		t.expect(find(committed, "Outline").Enabled).toBe(false)
		t.expect(find(pending, "Outline").Enabled).toBe(true)
		board.undo()
		t.expect(find(pending, "Outline").Enabled).toBe(false)
		stopBoard()
	end)

	t.it("selects every tag the framework emits with a rule in every shipped sheet", function()
		local literals, prefixes, dynamic = {}, {}, {}
		for _, entry in fs.readDir("src/ui") do
			if entry ~= "themes.luau" and string.sub(entry, -5) == ".luau" then
				for _, site in scanTags(fs.readFile("src/ui/" .. entry), literals, prefixes) do
					table.insert(dynamic, entry .. ":" .. site)
				end
			end
		end
		t.expect(dynamic).toEqual({ "inputs.luau:role" })
		t.expect(string.find(fs.readFile("src/ui/nav_menu.luau"), 'family .. "-current"', 1, true) ~= nil).toBe(true)
		literals["facet-segment-current"] = true
		literals["facet-choice-current"] = true
		local expanded: { [string]: { string } } = {
			["facet-"] = {},
			["facet-role-"] = { "default", "cancel", "destructive", "onIndicator" },
			["facet-status-"] = { "neutral", "info", "success", "warning", "error", "accent" },
			["facet-type-"] = table.clone(themes.TYPE_ROLES) :: any,
			["facet-badge-"] = { "standard", "status", "utility" },
			["facet-disclosure-"] = { "plain", "contained", "divided" },
			["facet-size-"] = { "xsmall", "compact", "regular", "large" },
		}
		local found = {}
		for prefix in prefixes do
			table.insert(found, prefix)
		end
		table.sort(found)
		local declared = {}
		for prefix in expanded do
			table.insert(declared, prefix)
		end
		table.sort(declared)
		t.expect(found).toEqual(declared)
		for prefix, values in expanded do
			for _, value in values do
				literals[prefix .. value] = true
			end
		end
		local hooks = {
			["facet-alert"] = true,
			["facet-callout"] = true,
			["facet-collection"] = true,
			["facet-dialog"] = true,
			["facet-level-picker"] = true,
			["facet-notice"] = true,
			["facet-popover"] = true,
			["facet-radial-sector"] = true,
			["facet-rating"] = true,
			["facet-rowactions"] = true,
			["facet-slider"] = true,
			["facet-snackbar"] = true,
			["facet-stepper"] = true,
			["facet-table"] = true,
			["facet-tablecell"] = true,
			["facet-tableheader"] = true,
			["facet-role-default"] = true,
			["facet-badge-standard"] = true,
			["facet-disclosure-plain"] = true,
			["facet-disclosure-contained"] = true,
			["facet-disclosure-divided"] = true,
		}
		for hook in hooks do
			t.expect(literals[hook]).toBe(true)
		end
		local h = harness()
		local probes, stopProbes = mount(h, function()
			return h.Host.Frame({
				h.UI.Slider({ value = Compose.cell(0.5) }),
				h.UI.Toggle({ value = Compose.cell(true), label = "T" }),
				h.UI.Toggle({ value = Compose.cell(false), label = "C", presentation = "checkbox" }),
				h.UI.Stepper({ value = Compose.cell(2), min = 0, max = 5 }),
				h.UI.ProgressView({ value = 0.5 }),
				h.UI.ProgressView({ value = 0.5, presentation = "circular" }),
				h.UI.Badge({ label = "B", icon = "checkmark", status = "warning", appearance = "status" }),
				h.UI.Button({ label = "Go", appearance = "soft", role = "destructive", subtitle = "More" }),
				h.UI.Label({ text = "L", textRole = "heading", role = "secondary" }),
				h.UI.Picker({
					selected = Compose.cell("a"),
					style = "segmented",
					options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
				}),
				h.UI.Picker({
					selected = Compose.cell("a"),
					style = "inline",
					options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
				}),
				h.UI.TextInput({ value = Compose.cell("") }),
				h.UI.Chip({ label = "Chip", selected = Compose.cell(true) }),
				h.UI.Rating({ value = Compose.cell(2) }),
				h.UI.LevelPicker({ value = Compose.cell(2) }),
				h.UI.Avatar({ name = "Ada Lovelace" }),
				h.UI.AvatarGroup({ items = { { id = "a", name = "Ada" }, { id = "b", name = "Bo" } } }),
				h.UI.StatusIndicator({ status = "info", form = "ring" }),
				h.UI.Skeleton({}),
				h.UI.ShortcutHint({ keys = { { "Ctrl", "K" } } }),
				h.UI.DisclosureGroup({
					expanded = Compose.cell(true),
					appearance = "contained",
					label = "More",
					content = function()
						return h.Host.Frame({})
					end,
				}),
			})
		end)
		local mounted = 0
		for _, node in probes:GetDescendants() do
			for _, tag in node:GetTags() do
				if string.sub(tag, 1, 6) == "facet-" then
					mounted += 1
					if not literals[tag] then
						error("scan missed emitted tag " .. tag)
					end
				end
			end
		end
		t.expect(mounted > 60).toBe(true)
		stopProbes()
		local packages = { themes.neutralPackage() }
		for _, name in SHIPPED do
			table.insert(packages, (shipped(name)))
		end
		for _, package in packages do
			for _, palette in package.style.themes do
				local sheet, stop = sheetFor(h, package, { theme = palette.name })
				local selected = {}
				for _, rule in sheet:GetChildren() do
					for class in string.gmatch(rule.Selector, "%.([%w%-]+)") do
						selected[class] = true
					end
				end
				for tag in literals do
					if hooks[tag] then
						t.expect(selected[tag] == true).toBe(false)
					elseif not selected[tag] then
						error(`{package.identity.id}/{palette.name} has no rule for emitted tag {tag}`)
					end
				end
				stop()
			end
		end
		h.dispose()
	end)
end)
