--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
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
	input: any,
	dispose: () -> (),
}

local function harness(options: { [string]: any }?): Harness
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local config: { [string]: any } =
		{ types = engine.types, guiService = gui, services = { GuiService = gui, UserInputService = input } }
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
		input = input,
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

local function facetTags(node: any): { string }
	local out = {}
	for _, tag in node:GetTags() do
		if string.sub(tag, 1, 6) == "facet-" then
			table.insert(out, tag)
		end
	end
	table.sort(out)
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
	return package, report
end

local function paletteOf(palette: any): ({ [string]: any }, { [string]: any })
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

local parsed: { [string]: Selector } = {}

local function parse(selector: string): Selector
	local cached = parsed[selector]
	if cached then
		return cached
	end
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
	local result = { parts = parts, combinators = combinators, pseudo = pseudo }
	parsed[selector] = result
	return result
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

local function skinPackage(slots: { [string]: any }): any
	local package = themes.neutralPackage()
	package.assets = package.assets or {}
	for slot, asset in slots do
		package.assets[slot .. "Art"] = { content = asset }
		package.chrome[slot] = { kind = "nineSlice", asset = slot .. "Art" }
	end
	return package
end

local function ownArt(node: any, slot: string): any
	for _, child in node:GetChildren() do
		if string.sub(child.Name, -8) == "Boundary" then
			local art = find(child, slot .. "1")
			if art then
				return art
			end
		end
	end
	return nil
end

local function ownSlots(node: any): { string }
	local out = {}
	for _, child in node:GetChildren() do
		if string.sub(child.Name, -8) == "Boundary" or (child.ClassName == "Folder" and child.Name == "Chrome") then
			for _, image in child:GetDescendants() do
				if image.ClassName == "ImageLabel" and image.Visible then
					table.insert(out, (string.gsub(image.Name, "%d+$", "")))
				end
			end
		end
	end
	table.sort(out)
	return out
end

local function setState(h: Harness, node: any, state: string)
	node.GuiState = (h.engine.types.Enum.GuiState :: any)[state]
end

t.describe("native paint strength: button content", function()
	t.it("paints rich button titles and icons with the plate text color for every role and appearance", function()
		local h = harness()
		local packages = { themes.neutralPackage() }
		for _, name in SHIPPED do
			table.insert(packages, (shipped(name)))
		end
		local role, appearance, selected = Compose.cell("default"), Compose.cell("standard"), Compose.cell(false)
		local enabled = Compose.cell(true)
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Button({
					Name = "Plain",
					label = "Go",
					role = role,
					appearance = appearance,
					selected = selected,
					enabled = enabled,
				}),
				h.UI.Button({
					Name = "Rich",
					label = "Go",
					icon = "checkmark",
					role = role,
					appearance = appearance,
					selected = selected,
					enabled = enabled,
				}),
			})
		end)
		local plain, rich = find(root, "Plain"), find(root, "Rich")
		local title, icon = find(rich, "Title"), find(rich, "LeadingIcon")
		t.expect(title:HasTag("facet-text")).toBe(true)
		t.expect(icon:HasTag("facet-icon")).toBe(true)
		local checked = 0
		for _, package in packages do
			for _, palette in package.style.themes do
				local colors, extra = paletteOf(palette)
				local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
				for _, nextAppearance in { "standard", "emphasis", "soft", "utility", "link" } do
					for _, nextRole in { "default", "destructive" } do
						for _, isSelected in { false, true } do
							appearance:set(nextAppearance)
							role:set(nextRole)
							selected:set(isSelected)
							for _, state in { "Idle", "Hover", "Press" } do
								setState(h, plain, state)
								setState(h, rich, state)
								local expected = resolve(sheet, plain, "TextColor3")
								t.expect(expected ~= nil).toBe(true)
								t.expect(resolve(sheet, rich, "TextColor3")).toBe(expected)
								t.expect(resolve(sheet, title, "TextColor3")).toBe(expected)
								t.expect(resolve(sheet, icon, "ImageColor3")).toBe(expected)
								local dim = resolve(sheet, plain, "TextTransparency") or 0
								t.expect(resolve(sheet, title, "TextTransparency") or 0).toBe(dim)
								t.expect(resolve(sheet, icon, "ImageTransparency") or 0).toBe(dim)
								checked += 1
							end
						end
					end
				end
				appearance:set("standard")
				selected:set(false)
				setState(h, plain, "Idle")
				setState(h, rich, "Idle")
				role:set("destructive")
				t.expect(resolve(sheet, title, "TextColor3")).toBe(color(h.engine, colors.onDanger))
				t.expect(resolve(sheet, icon, "ImageColor3")).toBe(color(h.engine, colors.onDanger))
				appearance:set("emphasis")
				t.expect(resolve(sheet, icon, "ImageColor3")).toBe(color(h.engine, colors.onAccent))
				appearance:set("link")
				t.expect(resolve(sheet, title, "TextColor3")).toBe(color(h.engine, colors.danger))
				t.expect(resolve(sheet, icon, "ImageColor3")).toBe(color(h.engine, colors.danger))
				setState(h, rich, "Press")
				t.expect(resolve(sheet, title, "TextTransparency")).toBe(0.3)
				t.expect(resolve(sheet, icon, "ImageTransparency")).toBe(0.3)
				setState(h, rich, "Idle")
				appearance:set("standard")
				role:set("default")
				enabled:set(false)
				t.expect(resolve(sheet, plain, "TextTransparency")).toBe(extra.disabledContentOpacity)
				t.expect(resolve(sheet, title, "TextTransparency")).toBe(extra.disabledContentOpacity)
				t.expect(resolve(sheet, icon, "ImageTransparency")).toBe(extra.disabledContentOpacity)
				t.expect(style(sheet, ".facet-disabled >> .facet-button-caption").TextTransparency)
					.toBe(extra.disabledContentOpacity)
				enabled:set(true)
				t.expect(resolve(sheet, title, "TextTransparency")).toBe(nil)
				stopSheet()
			end
		end
		t.expect(checked >= 9 * 30).toBe(true)
		stop()
		h.dispose()
	end)

	t.it("keeps a hidden plaque caption hidden while its button is disabled", function()
		local h = harness()
		local _, extra = neutralColors()
		local sheet, stop = sheetFor(h, themes.neutralPackage())
		local root, stopMount = mount(h, function()
			return h.UI.Button({ Name = "Plaque", label = "Go", enabled = false })
		end)
		local button = find(root, "Plaque")
		button:AddTag("facet-skin-caption")
		local caption = h.engine.new("TextLabel")
		caption:AddTag("facet-text")
		caption:AddTag("facet-button-caption")
		caption.Parent = button
		t.expect(resolve(sheet, caption, "TextTransparency")).toBe(1)
		button:RemoveTag("facet-skin-caption")
		t.expect(resolve(sheet, caption, "TextTransparency")).toBe(extra.disabledContentOpacity)
		caption:Destroy()
		stopMount()
		stop()
		h.dispose()
	end)

	t.it("mints one tag per authored appearance word and rung, none for standard or no rung", function()
		local h = harness()
		local expected: { [string]: { string } } = {
			standard = {},
			emphasis = { "facet-accent" },
			soft = { "facet-appearance-soft" },
			utility = { "facet-appearance-utility" },
			link = { "facet-appearance-link" },
		}
		local bound = Compose.cell("standard")
		local nodes: { [string]: any } = {}
		local root, stop = mount(h, function()
			local children = {}
			for word in expected do
				for _, size in { "compact", "regular", "large" } do
					table.insert(
						children,
						h.UI.Button({ Name = word .. "-" .. size, label = word, appearance = word, controlSize = size })
					)
				end
			end
			table.insert(children, h.UI.Button({ Name = "Bare", label = "Bare" }))
			table.insert(children, h.UI.Button({ Name = "Bound", label = "Bound", appearance = bound }))
			return h.Host.Frame(children)
		end)
		for word, extra in expected do
			for _, size in { "compact", "regular", "large" } do
				local node = find(root, word .. "-" .. size)
				nodes[word] = node
				local want = { "facet-button", "facet-role-default", "facet-size-" .. size }
				for _, tag in extra do
					table.insert(want, tag)
				end
				table.sort(want)
				t.expect(facetTags(node)).toEqual(want)
				t.expect(node:GetAttribute("appearance")).toBe(word)
				t.expect(node:GetAttribute("controlSize")).toBe(size)
			end
		end
		t.expect(facetTags(find(root, "Bare"))).toEqual({ "facet-button", "facet-role-default" })
		t.expect(find(root, "Bare"):GetAttribute("controlSize")).toBe("regular")
		local node = find(root, "Bound")
		for _, word in { "emphasis", "soft", "utility", "link", "standard" } do
			bound:set(word)
			local want = { "facet-button", "facet-role-default" }
			for _, tag in expected[word] do
				table.insert(want, tag)
			end
			table.sort(want)
			t.expect(facetTags(node)).toEqual(want)
		end
		for _, candidate in root:GetDescendants() do
			for _, tag in candidate:GetTags() do
				local sized = string.sub(tag, 1, 11) == "facet-size-"
				t.expect(sized and (candidate.Name == "Bare" or candidate.Name == "Bound")).toBe(false)
				t.expect(sized and tag ~= "facet-size-" .. tostring(candidate:GetAttribute("controlSize"))).toBe(false)
				t.expect(tag == "facet-appearance-standard" or tag == "facet-appearance-emphasis").toBe(false)
			end
		end
		stop()
		h.dispose()
	end)

	t.it("leaves game-owned tags in place while control state tags come and go", function()
		local h = harness()
		local role, appearance, selected = Compose.cell("destructive"), Compose.cell("utility"), Compose.cell(true)
		local busy, enabled, value = Compose.cell(true), Compose.cell(false), Compose.cell(true)
		local level, pick, tab = Compose.cell(3), Compose.cell("a"), Compose.cell("one")
		local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Button({
					Name = "Action",
					label = "Go",
					role = role,
					appearance = appearance,
					selected = selected,
					busy = busy,
					enabled = enabled,
				}),
				h.UI.Toggle({ Name = "Switch", value = value, label = "On" }),
				h.UI.LevelPicker({ Name = "Level", value = level, count = 5 }),
				h.Host.Frame({
					Name = "Segmented",
					h.UI.Picker({ selected = pick, style = "segmented", options = options }),
				}),
				h.UI.TabView({
					selection = tab,
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
				}),
			})
		end)
		local action = find(root, "Action")
		local indicator = find(find(root, "Switch"), "Indicator")
		local bar = find(find(root, "Level"), "Level1")
		local option = find(find(root, "Segmented"), "a")
		local tabButton = find(root, "one")
		local owned = { action, indicator, bar, option, tabButton }
		for _, node in owned do
			node:AddTag("game-owned")
			node:AddTag("facet-game-mark")
		end
		t.expect(action:HasTag("facet-role-destructive")).toBe(true)
		t.expect(action:HasTag("facet-quiet-destructive")).toBe(true)
		t.expect(action:HasTag("facet-selected")).toBe(true)
		t.expect(action:HasTag("facet-busy")).toBe(true)
		t.expect(action:HasTag("facet-disabled")).toBe(true)
		role:set("cancel")
		appearance:set("emphasis")
		selected:set(false)
		busy:set(false)
		enabled:set(true)
		value:set(false)
		level:set(0)
		pick:set("b")
		tab:set("two")
		t.expect(action:HasTag("facet-role-destructive")).toBe(false)
		t.expect(action:HasTag("facet-role-cancel")).toBe(true)
		t.expect(action:HasTag("facet-quiet-destructive")).toBe(false)
		t.expect(action:HasTag("facet-appearance-utility")).toBe(false)
		t.expect(action:HasTag("facet-accent")).toBe(true)
		t.expect(action:HasTag("facet-selected")).toBe(false)
		t.expect(action:HasTag("facet-busy")).toBe(false)
		t.expect(action:HasTag("facet-disabled")).toBe(false)
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(false)
		t.expect(bar:HasTag("facet-level-on")).toBe(false)
		t.expect(option:HasTag("facet-segment-current")).toBe(false)
		t.expect(tabButton:HasTag("facet-tab-current")).toBe(false)
		for _, node in owned do
			t.expect(node:HasTag("game-owned")).toBe(true)
			t.expect(node:HasTag("facet-game-mark")).toBe(true)
		end
		role:set("destructive")
		value:set(true)
		level:set(5)
		pick:set("a")
		tab:set("one")
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(true)
		t.expect(bar:HasTag("facet-level-on")).toBe(true)
		t.expect(option:HasTag("facet-segment-current")).toBe(true)
		t.expect(tabButton:HasTag("facet-tab-current")).toBe(true)
		for _, node in owned do
			t.expect(node:HasTag("game-owned")).toBe(true)
			t.expect(node:HasTag("facet-game-mark")).toBe(true)
		end
		stop()
		h.dispose()
	end)

	t.it("replaces the selected plate with the chosen indicator instead of painting both", function()
		local h = harness()
		local colors, extra = neutralColors()
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
		local segmented, indicator = Compose.cell("b"), Compose.cell("underline")
		local selection, tabIndicator = Compose.cell("two"), Compose.cell("automatic")
		local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.Host.Frame({
					Name = "Segmented",
					h.UI.Picker({ selected = segmented, style = "segmented", indicator = indicator, options = options }),
				}),
				h.UI.TabView({
					selection = selection,
					indicator = tabIndicator,
					placement = "topBar",
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
				}),
			})
		end)
		local picker = find(root, "Segmented")
		local a, b = find(picker, "a"), find(picker, "b")
		local function bars(scope: any): number
			return #tagged(scope, "facet-selection-indicator")
		end
		t.expect(bars(picker)).toBe(1)
		t.expect(find(b, "SelectionIndicator") ~= nil).toBe(true)
		t.expect(b:HasTag("facet-selected")).toBe(false)
		t.expect(resolve(sheet, b, "BackgroundTransparency")).toBe(1)
		t.expect(resolve(sheet, b, "BackgroundTransparency")).toBe(resolve(sheet, a, "BackgroundTransparency"))
		t.expect(resolve(sheet, b, "BackgroundColor3")).toBe(resolve(sheet, a, "BackgroundColor3"))
		t.expect(resolve(sheet, find(b, "SelectionIndicator"), "BackgroundColor3")).toBe(color(h.engine, colors.accent))
		indicator:set("pill")
		t.expect(bars(picker)).toBe(0)
		t.expect(resolve(sheet, b, "BackgroundTransparency")).toBe(0)
		t.expect(resolve(sheet, b, "BackgroundColor3")).toBe(color(h.engine, colors.accent))
		t.expect(resolve(sheet, a, "BackgroundTransparency")).toBe(1)
		local one, two = find(root, "one"), find(root, "two")
		local tabs = one.Parent
		t.expect(bars(tabs)).toBe(1)
		t.expect(find(two, "SelectionIndicator") ~= nil).toBe(true)
		t.expect(two:HasTag("facet-selected")).toBe(false)
		t.expect(resolve(sheet, two, "BackgroundTransparency")).toBe(1)
		t.expect(resolve(sheet, two, "BackgroundColor3")).toBe(resolve(sheet, one, "BackgroundColor3"))
		tabIndicator:set("underline")
		t.expect(bars(tabs)).toBe(1)
		t.expect(two:HasTag("facet-selected")).toBe(false)
		t.expect(resolve(sheet, two, "BackgroundTransparency")).toBe(1)
		tabIndicator:set("pill")
		t.expect(bars(tabs)).toBe(0)
		t.expect(two:HasTag("facet-selected")).toBe(true)
		t.expect(resolve(sheet, two, "BackgroundTransparency")).toBe(0)
		t.expect(resolve(sheet, two, "BackgroundColor3")).toBe(color(h.engine, extra.controlSelected))
		setState(h, two, "Hover")
		t.expect(resolve(sheet, two, "BackgroundTransparency")).toBe(0)
		setState(h, two, "Idle")
		t.expect(resolve(sheet, one, "BackgroundTransparency")).toBe(1)
		tabIndicator:set("none")
		t.expect(bars(tabs)).toBe(0)
		t.expect(two:HasTag("facet-selected")).toBe(false)
		t.expect(resolve(sheet, two, "BackgroundTransparency")).toBe(1)
		stop()
		stopSheet()
		h.dispose()
	end)

	t.it("keeps the radial button plate by default and omits it for every item when the surface is none", function()
		local colors, extra = neutralColors()
		for _, surface in { "native", "none" } do
			local h = harness({ reducedMotion = true })
			local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
			local items = {}
			for _, id in { "N", "E", "S", "W" } do
				table.insert(items, {
					id = id,
					slot = id,
					label = id,
					icon = if id == "N" then "checkmark" else nil,
					completion = "stay",
					onSelect = function() end,
				})
			end
			local root, stop = mount(h, function()
				return h.UI.RadialMenu({
					isPresented = Compose.cell(true),
					appearance = "buttons",
					buttonSurface = if surface == "none" then "none" else nil,
					distribution = "compass",
					items = items,
				})
			end)
			local screen = root.Parent
			for _, id in { "N", "E", "S", "W" } do
				local button = find(screen, id)
				t.expect(button:HasTag("facet-button")).toBe(true)
				if surface == "none" then
					t.expect(button.BackgroundTransparency).toBe(1)
				else
					t.expect(button.BackgroundTransparency).toBe(0)
					t.expect(resolve(sheet, button, "BackgroundTransparency")).toBe(0)
					t.expect(resolve(sheet, button, "BackgroundColor3"))
						.toBe(
							color(
								h.engine,
								if button:HasTag("facet-selected") then extra.controlSelected else extra.control
							)
						)
				end
				t.expect(resolve(sheet, button, "TextColor3")).toBe(color(h.engine, colors.content))
			end
			local icon = find(find(screen, "N"), "LeadingIcon")
			t.expect(resolve(sheet, icon, "ImageColor3")).toBe(color(h.engine, colors.content))
			stop()
			stopSheet()
			h.dispose()
		end
		local h = harness({ reducedMotion = true })
		local root, stop = mount(h, function()
			return h.UI.RadialMenu({
				isPresented = Compose.cell(true),
				distribution = "compass",
				items = { { id = "N", slot = "N", label = "N", completion = "stay", onSelect = function() end } },
			})
		end)
		t.expect(find(root.Parent, "N").BackgroundTransparency).toBe(1)
		stop()
		h.dispose()
		t.expect(function()
			local bad = harness({ reducedMotion = true })
			mount(bad, function()
				return bad.UI.RadialMenu({
					isPresented = Compose.cell(true),
					buttonSurface = "plate",
					items = { { id = "N", label = "N", onSelect = function() end } },
				})
			end)
		end).toThrow()
	end)
end)

t.describe("native paint strength: skins", function()
	t.it("drives the control skin art from the button's own interaction state", function()
		local package = themes.neutralPackage()
		for name, id in { rest = 11, hot = 12, press = 13, chosen = 14, off = 15, bare = 16, pushed = 17 } do
			package.assets[name] = { content = "rbxassetid://" .. id }
		end
		package.chrome.control = {
			kind = "nineSlice",
			asset = { default = "rest", hover = "hot", pressed = "press", selected = "chosen", disabled = "off" },
		}
		local h = harness({ theme = package })
		local sheet, stopSheet = sheetFor(h, package)
		local selected, enabled = Compose.cell(false), Compose.cell(true)
		local root, stop = mount(h, function()
			return h.UI.Button({ Name = "Go", label = "Go", selected = selected, enabled = enabled })
		end)
		local button = find(root, "Go")
		local art = ownArt(button, "control")
		t.expect(button:HasTag("facet-skinned")).toBe(true)
		local function expectArt(state: string, id: number)
			setState(h, button, state)
			t.expect(ownArt(button, "control")).toBe(art)
			t.expect(art.Image).toBe("rbxassetid://" .. id)
			t.expect(resolve(sheet, button, "BackgroundTransparency")).toBe(1)
		end
		expectArt("Idle", 11)
		expectArt("Hover", 12)
		expectArt("Press", 13)
		expectArt("Idle", 11)
		selected:set(true)
		expectArt("Idle", 14)
		expectArt("Hover", 12)
		expectArt("Press", 13)
		enabled:set(false)
		expectArt("Press", 15)
		expectArt("NonInteractable", 15)
		expectArt("Idle", 15)
		enabled:set(true)
		selected:set(false)
		expectArt("Idle", 11)
		stop()
		stopSheet()
		h.dispose()
		local partial = themes.neutralPackage()
		partial.assets.bare = { content = "rbxassetid://16" }
		partial.assets.pushed = { content = "rbxassetid://17" }
		partial.chrome.control = { kind = "nineSlice", asset = { default = "bare", pressed = "pushed" } }
		local other = harness({ theme = partial })
		local otherRoot, stopOther = mount(other, function()
			return other.UI.Button({ Name = "Go", label = "Go", selected = true })
		end)
		local plate = find(otherRoot, "Go")
		local image = ownArt(plate, "control")
		for state, id in { Idle = 16, Hover = 16, Press = 17 } do
			setState(other, plate, state)
			t.expect(image.Image).toBe("rbxassetid://" .. id)
		end
		stopOther()
		other.dispose()
	end)

	t.it("maps hover and press on each skinned part to that part's state art", function()
		local package = themes.neutralPackage()
		local ids = { default = 1, hover = 2, pressed = 3, selected = 4 }
		for _, slot in { "field", "stepperPlate", "toggleTrack", "toggleKnob", "sliderThumb" } do
			local variants = {}
			for state, id in ids do
				local name = slot .. "-" .. state
				package.assets[name] = { content = "rbxassetid://" .. slot .. id }
				variants[state] = name
			end
			package.chrome[slot] = { kind = "nineSlice", asset = variants }
		end
		local h = harness({ theme = package })
		local value = Compose.cell(false)
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.TextInput({ Name = "Field", value = Compose.cell("Ada") }),
				h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
				h.UI.Toggle({ Name = "Switch", value = value, label = "On" }),
				h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
			})
		end)
		local switch = find(root, "Switch")
		local parts = {
			{ find(root, "Field"), "field" },
			{ find(root, "Stepper"), "stepperPlate" },
			{ find(switch, "Indicator"), "toggleTrack" },
			{ find(switch, "Mark"), "toggleKnob" },
			{ find(find(root, "Slider"), "Thumb"), "sliderThumb" },
		}
		for _, entry in parts do
			local node, slot = entry[1], entry[2]
			local art = ownArt(node, slot)
			t.expect(art ~= nil).toBe(true)
			t.expect(node:HasTag("facet-skinned")).toBe(true)
			for _, step in { { "Idle", 1 }, { "Hover", 2 }, { "Press", 3 }, { "Idle", 1 } } do
				setState(h, node, step[1])
				t.expect(art.Image).toBe("rbxassetid://" .. slot .. step[2])
			end
		end
		value:set(true)
		local indicator, mark = find(switch, "Indicator"), find(switch, "Mark")
		t.expect(ownArt(indicator, "toggleTrack").Image).toBe("rbxassetid://toggleTrack4")
		t.expect(ownArt(mark, "toggleKnob").Image).toBe("rbxassetid://toggleKnob4")
		setState(h, indicator, "Hover")
		t.expect(ownArt(indicator, "toggleTrack").Image).toBe("rbxassetid://toggleTrack2")
		setState(h, indicator, "Idle")
		value:set(false)
		t.expect(ownArt(indicator, "toggleTrack").Image).toBe("rbxassetid://toggleTrack1")
		stop()
		h.dispose()
	end)

	t.it("gives each control part the art of its own chrome slot and no other", function()
		local slots = {
			"control",
			"field",
			"toggleTrack",
			"toggleKnob",
			"stepperPlate",
			"sliderTrack",
			"sliderThumb",
			"barFill",
			"barTrack",
			"badge",
			"panel",
		}
		local assets = {}
		for index, slot in slots do
			assets[slot] = "rbxassetid://" .. (500 + index)
		end
		local package = skinPackage(assets)
		local h = harness({ theme = package })
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Button({ Name = "Action", label = "Go" }),
				h.UI.TextInput({ Name = "Field", value = Compose.cell("Ada") }),
				h.UI.Toggle({ Name = "Switch", value = Compose.cell(true), label = "On" }),
				h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
				h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
				h.UI.ProgressView({ Name = "Progress", value = 0.5 }),
				h.UI.Badge({ Name = "Seal", label = "3" }),
				h.UI.Alert({
					isPresented = Compose.cell(true),
					title = "Leave?",
					actions = { { id = "stay", label = "Stay", role = "cancel" } },
				}),
			})
		end)
		local slider, progress = find(root, "Slider"), find(root, "Progress")
		local panel = find(root.Parent, "AlertPanel")
		local expected = {
			{ find(root, "Action"), "control" },
			{ find(root, "Field"), "field" },
			{ find(find(root, "Switch"), "Indicator"), "toggleTrack" },
			{ find(find(root, "Switch"), "Mark"), "toggleKnob" },
			{ find(root, "Stepper"), "stepperPlate" },
			{ find(slider, "Rail"), "sliderTrack" },
			{ find(slider, "Thumb"), "sliderThumb" },
			{ find(slider, "Fill"), "barFill" },
			{ find(progress, "Track"), "barTrack" },
			{ tagged(progress, "facet-fill")[1], "barFill" },
			{ find(root, "Seal"), "badge" },
			{ panel, "panel" },
		}
		local seen: { [string]: boolean } = {}
		for _, entry in expected do
			local node, slot = entry[1], entry[2]
			t.expect(node ~= nil).toBe(true)
			t.expect(ownSlots(node)).toEqual({ slot })
			t.expect(ownArt(node, slot) ~= nil or find(node, slot .. "1") ~= nil).toBe(true)
			t.expect((ownArt(node, slot) or find(node, slot .. "1")).Image).toBe(assets[slot])
			t.expect(node:HasTag("facet-skinned")).toBe(true)
			seen[slot] = true
		end
		for _, slot in slots do
			t.expect(seen[slot]).toBe(true)
		end
		stop()
		h.dispose()
	end)

	t.it("suppresses a skinned plate and its outline in every state and restores both when the art goes", function()
		local _, extra = neutralColors()
		local art = skinPackage({
			control = "rbxassetid://601",
			toggleTrack = "rbxassetid://602",
			toggleKnob = "rbxassetid://603",
			sliderThumb = "rbxassetid://604",
			sliderTrack = "rbxassetid://605",
			barFill = "rbxassetid://606",
		})
		local selected = Compose.cell(art)
		local h = harness({ theme = selected })
		local sheet, stopSheet = sheetFor(h, selected)
		local options = { { value = "a", label = "A" }, { value = "b", label = "B" } }
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Button({ Name = "Soft", label = "Soft", appearance = "soft" }),
				h.UI.Button({ Name = "Utility", label = "Utility", appearance = "utility" }),
				h.UI.Button({ Name = "Primary", label = "Primary", appearance = "emphasis", selected = true }),
				h.UI.Button({ Name = "Danger", label = "Danger", role = "destructive" }),
				h.Host.Frame({
					Name = "Segmented",
					h.UI.Picker({ selected = Compose.cell("a"), style = "segmented", options = options }),
				}),
				h.UI.Toggle({ Name = "Box", value = Compose.cell(true), label = "Box", presentation = "checkbox" }),
				h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
			})
		end)
		local box = find(find(root, "Box"), "Indicator")
		local slider = find(root, "Slider")
		local nodes = {
			find(root, "Soft"),
			find(root, "Utility"),
			find(root, "Primary"),
			find(root, "Danger"),
			find(find(root, "Segmented"), "a"),
			box,
			find(slider, "Thumb"),
			find(slider, "Rail"),
			find(slider, "Fill"),
		}
		t.expect(find(find(root, "Segmented"), "a"):HasTag("facet-segment-current")).toBe(true)
		local function sweep(expectSkinned: boolean)
			for _, node in nodes do
				t.expect(node:HasTag("facet-skinned")).toBe(expectSkinned)
				for _, state in { "Idle", "Hover", "Press" } do
					setState(h, node, state)
					local transparency = resolve(sheet, node, "BackgroundTransparency")
					if expectSkinned and node:HasTag("facet-segment-current") then
						t.expect(transparency).toBe(0)
					elseif expectSkinned then
						t.expect(transparency).toBe(1)
					else
						t.expect(transparency ~= 1 or node == find(root, "Utility")).toBe(true)
					end
				end
				setState(h, node, "Idle")
			end
		end
		sweep(true)
		t.expect(resolve(sheet, box, "Transparency", "UIStroke")).toBe(1)
		local menu = h.engine.new("Frame")
		menu:AddTag("facet-menu")
		menu:AddTag("facet-skinned")
		t.expect(resolve(sheet, menu, "Transparency", "UIStroke")).toBe(1)
		menu:RemoveTag("facet-skinned")
		t.expect(resolve(sheet, menu, "Transparency", "UIStroke")).toBe(0.3)
		t.expect(
			ruleNode(sheet, ".facet-skinned").Priority > ruleNode(sheet, ".facet-appearance-utility:Hover").Priority
		)
			.toBe(true)
		t.expect(ruleNode(sheet, ".facet-skinned").Priority > ruleNode(sheet, ".facet-segment-current").Priority)
			.toBe(true)
		selected:set(themes.neutralPackage())
		t.expect(#tagged(root, "facet-skinned")).toBe(0)
		sweep(false)
		t.expect(resolve(sheet, find(root, "Soft"), "BackgroundTransparency")).toBe(0.8)
		t.expect(resolve(sheet, find(root, "Danger"), "BackgroundTransparency")).toBe(0)
		t.expect(resolve(sheet, find(root, "Primary"), "BackgroundColor3"))
			.toBe(color(h.engine, neutralColors().accent))
		t.expect(resolve(sheet, find(slider, "Thumb"), "BackgroundColor3"))
			.toBe(color(h.engine, neutralColors().accent))
		t.expect(resolve(sheet, find(slider, "Rail"), "BackgroundColor3")).toBe(color(h.engine, extra.control))
		t.expect(resolve(sheet, box, "Transparency", "UIStroke")).toBe(0.2)
		selected:set(art)
		sweep(true)
		stop()
		stopSheet()
		h.dispose()
	end)

	t.it("drops the skinned tag from a field and a button when the package stops drawing their art", function()
		local art = skinPackage({ field = "rbxassetid://701", control = "rbxassetid://702" })
		local missing = themes.neutralPackage()
		missing.chrome.field = { kind = "layered", layers = { { kind = "fill", asset = "absent" } } }
		missing.chrome.control = { kind = "native" }
		local none = themes.neutralPackage()
		none.chrome.field = { kind = "none" }
		none.chrome.control = { kind = "none" }
		local selected = Compose.cell(art)
		local h = harness({ theme = selected })
		local sheet, stopSheet = sheetFor(h, selected)
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.TextInput({ Name = "Field", value = Compose.cell("Ada") }),
				h.UI.Button({ Name = "Action", label = "Go" }),
			})
		end)
		local field, action = find(root, "Field"), find(root, "Action")
		t.expect(field.ClassName).toBe("TextBox")
		local plain = {}
		for _, package in { art, missing, none, art } do
			selected:set(package)
			local drawn = package == art
			for _, node in { field, action } do
				t.expect(node:HasTag("facet-skinned")).toBe(drawn)
				local transparency = resolve(sheet, node, "BackgroundTransparency")
				if drawn then
					t.expect(transparency).toBe(1)
				else
					t.expect(transparency).toBe(0)
					plain[node] = resolve(sheet, node, "BackgroundColor3")
				end
			end
			local image = ownArt(field, "field")
			t.expect(image == nil or image.Visible == drawn).toBe(true)
		end
		t.expect(plain[field] ~= nil and plain[action] ~= nil).toBe(true)
		t.expect(field.Text).toBe("Ada")
		stop()
		stopSheet()
		h.dispose()
	end)

	t.it("marks only the value parts a package actually skins", function()
		local _, extra = neutralColors()
		local colors = neutralColors()
		local package = skinPackage({
			sliderThumb = "rbxassetid://801",
			toggleKnob = "rbxassetid://802",
			barFill = "rbxassetid://803",
		})
		local h = harness({ theme = package })
		local sheet, stopSheet = sheetFor(h, package)
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Slider({ Name = "Slider", value = Compose.cell(0.5) }),
				h.UI.Toggle({ Name = "Switch", value = Compose.cell(true), label = "On" }),
				h.UI.ProgressView({ Name = "Progress", value = 0.5 }),
				h.UI.Stepper({ Name = "Stepper", value = Compose.cell(2), min = 0, max = 5 }),
			})
		end)
		local slider, switch, progress = find(root, "Slider"), find(root, "Switch"), find(root, "Progress")
		local skinned = {
			find(slider, "Thumb"),
			find(slider, "Fill"),
			find(switch, "Mark"),
			tagged(progress, "facet-fill")[1],
		}
		local bare = {
			{ find(slider, "Rail"), extra.control },
			{ find(switch, "Indicator"), colors.accent },
			{ find(progress, "Track"), extra.control },
			{ find(find(root, "Stepper"), "Controls"), extra.control },
		}
		for _, node in skinned do
			t.expect(node:HasTag("facet-skinned")).toBe(true)
			t.expect(resolve(sheet, node, "BackgroundTransparency")).toBe(1)
		end
		for _, entry in bare do
			local node = entry[1]
			t.expect(node:HasTag("facet-skinned")).toBe(false)
			t.expect(resolve(sheet, node, "BackgroundTransparency")).toBe(0)
			t.expect(resolve(sheet, node, "BackgroundColor3")).toBe(color(h.engine, entry[2]))
		end
		t.expect(#tagged(root, "facet-skinned")).toBe(#skinned)
		t.expect(find(root, "Stepper"):HasTag("facet-skinned")).toBe(false)
		stop()
		stopSheet()
		h.dispose()
	end)

	t.it("keeps full-bleed art on the plate's own box when the padding changes after mount", function()
		local package = skinPackage({ control = "rbxassetid://123" })
		local h = harness({ theme = package })
		local root, stop = mount(h, function()
			return h.UI.Button({ Name = "Plate", label = "Mark read" })
		end)
		local plate = find(root, "Plate")
		local skin, label = find(plate, "SkinBounds"), find(plate, "LabelBounds")
		local UDim = h.engine.types.UDim
		local hostX, hostWidth = 10, 83
		plate.AbsoluteSize = h.engine.types.Vector2.new(hostWidth, 28)
		for _, bounds in { skin, label } do
			bounds.Parent.AbsoluteSize = h.engine.types.Vector2.new(1, 1)
		end
		local padding = plate:FindFirstChildWhichIsA("UIPadding")
		local function painted(bounds: any): (number, number)
			local right = padding.PaddingRight.Offset
			local boundaryLeft = hostX + hostWidth - right - 1
			local rightEdge = boundaryLeft + bounds.Position.X.Offset
			return rightEdge - bounds.Size.X.Offset, rightEdge
		end
		for _, inset in { 12, 8, 0, 8 } do
			padding.PaddingLeft = UDim.new(0, inset)
			padding.PaddingRight = UDim.new(0, inset)
			local left, right = painted(skin)
			t.expect(`{left}..{right}`).toBe("10..93")
			local textLeft, textRight = painted(label)
			t.expect(`{textLeft}..{textRight}`).toBe(`{10 + inset}..{93 - inset}`)
		end
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 8)
		local left, right = painted(skin)
		t.expect(`{left}..{right}`).toBe("10..93")
		local textLeft, textRight = painted(label)
		t.expect(`{textLeft}..{textRight}`).toBe("22..85")
		stop()
		h.dispose()
	end)

	t.it("renders the declared shadow of every shipped package slot and none for flat packages", function()
		local presets = {
			raised = { blur = 14, transparency = 0.35, y = 3 },
		}
		local expectations: { [string]: { [string]: any } } = {
			fantasy_parchment = { panel = "raised", control = "raised" },
			fantasy_ornate = { panel = "raised", control = "raised" },
			glossy_mobile = { panel = "raised", control = "raised" },
			glossy_touch = { panel = "raised" },
			scifi_hud = { panel = { blur = 24, transparency = 0.3 }, control = { blur = 16, transparency = 0.28 } },
			classic_desktop = {},
			compact_pointer = {},
			pixel_quest = {},
		}
		local candidates = {}
		for name, slots in expectations do
			table.insert(candidates, { name = name, package = (shipped(name)), slots = slots })
		end
		table.insert(candidates, { name = "neutral", package = themes.neutralPackage(), slots = {} })
		for _, entry in candidates do
			local h = harness({ theme = entry.package })
			for _, slot in { "panel", "control" } do
				local target
				local stop = h.runtime.mount(function()
					target = h.Host.Frame({ Name = "Host" })
					h.runtime.mount(function()
						return themes.skin(h.runtime, entry.package, slot, { types = h.engine.types, target = target })
					end, target)
					return target
				end, h.engine.new("ScreenGui"))
				local shadow = target:FindFirstChild("ChromeShadow")
				local want = entry.slots[slot]
				if want == nil then
					t.expect(shadow == nil or shadow.Enabled == false).toBe(true)
				else
					local numbers = if type(want) == "string" then presets[want] else want
					t.expect(shadow.ClassName).toBe("UIShadow")
					t.expect(shadow.Enabled).toBe(true)
					t.expect(shadow.BlurRadius).toBe(h.engine.types.UDim.new(0, numbers.blur))
					t.expect(shadow.Transparency).toBe(numbers.transparency)
					t.expect(shadow.ZIndex < 0).toBe(true)
					if numbers.y then
						t.expect(shadow.Offset).toBe(h.engine.types.UDim2.new(0, 0, 0, numbers.y))
					end
					if entry.name == "scifi_hud" then
						t.expect(shadow.Color).toBe(h.engine.types.Color3.new(0.05, 0.42, 0.5))
						t.expect(shadow.Color.B > shadow.Color.R).toBe(true)
					end
					if entry.name == "glossy_mobile" then
						t.expect(entry.package.chrome[slot].kind).toBe("native")
						local images = 0
						for _, node in target:GetDescendants() do
							if node.ClassName == "ImageLabel" then
								images += 1
							end
						end
						t.expect(images).toBe(0)
					end
				end
				stop()
			end
			local root, stopButton = mount(h, function()
				return h.UI.Button({ Name = "Action", label = "Go" })
			end)
			local shadow = find(root, "Action"):FindFirstChild("ChromeShadow")
			t.expect(shadow ~= nil and shadow.Enabled).toBe(entry.slots.control ~= nil)
			stopButton()
			h.dispose()
		end
	end)

	t.it("resolves the overlay preset and package-named shadows on the native shadow", function()
		local definition = themes.neutralPackage()
		definition.style.shadows = {
			lifted = {
				blurRadius = { offset = 9 },
				transparency = 0.2,
				offset = { x = { offset = 2 }, y = { offset = 5 } },
			},
			raised = { blurRadius = { offset = 30 }, transparency = 0.6, color = { r = 0.2, g = 0, b = 0 } },
		}
		definition.chrome.control = { kind = "native", shadow = "overlay" }
		definition.chrome.panel = { kind = "native", shadow = "lifted" }
		definition.chrome.field = { kind = "native", shadow = "raised" }
		local package, report = themes.define(definition)
		t.expect(report.ok).toBe(true)
		local h = harness({ theme = package })
		local UDim, UDim2 = h.engine.types.UDim, h.engine.types.UDim2
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Button({ Name = "Action", label = "Go" }),
				h.UI.TextInput({ Name = "Field", value = Compose.cell("") }),
			})
		end)
		local overlay = find(root, "Action"):FindFirstChild("ChromeShadow")
		t.expect(overlay.BlurRadius).toBe(UDim.new(0, 24))
		t.expect(overlay.Transparency).toBe(0.45)
		t.expect(overlay.Offset).toBe(UDim2.new(0, 0, 0, 8))
		t.expect(overlay.ZIndex).toBe(-1)
		t.expect(overlay.Color).toBe(h.engine.types.Color3.new(0, 0, 0))
		local owned = find(root, "Field"):FindFirstChild("ChromeShadow")
		t.expect(owned.BlurRadius).toBe(UDim.new(0, 30))
		t.expect(owned.Transparency).toBe(0.6)
		t.expect(owned.Color).toBe(h.engine.types.Color3.new(0.2, 0, 0))
		stop()
		local target
		local stopPanel = h.runtime.mount(function()
			target = h.Host.Frame({ Name = "Panel" })
			h.runtime.mount(function()
				return themes.skin(h.runtime, package, "panel", { types = h.engine.types, target = target })
			end, target)
			return target
		end, h.engine.new("ScreenGui"))
		local lifted = target:FindFirstChild("ChromeShadow")
		t.expect(lifted.BlurRadius).toBe(UDim.new(0, 9))
		t.expect(lifted.Transparency).toBe(0.2)
		t.expect(lifted.Offset).toBe(UDim2.new(0, 2, 0, 5))
		stopPanel()
		h.dispose()
		local live = themes.neutralPackage()
		live.chrome.control = { kind = "native", shadow = "overlay" }
		local selected = Compose.cell(live)
		local reactive = harness({ theme = selected })
		local reactiveRoot, stopReactive = mount(reactive, function()
			return reactive.UI.Button({ Name = "Action", label = "Go" })
		end)
		local shadow = find(reactiveRoot, "Action"):FindFirstChild("ChromeShadow")
		t.expect(shadow.BlurRadius).toBe(UDim.new(0, 24))
		local named = themes.neutralPackage()
		named.style.shadows = { lifted = { blurRadius = { offset = 9 }, transparency = 0.2 } }
		named.chrome.control = { kind = "native", shadow = "lifted" }
		selected:set(named)
		t.expect(find(reactiveRoot, "Action"):FindFirstChild("ChromeShadow")).toBe(shadow)
		t.expect(shadow.BlurRadius).toBe(UDim.new(0, 9))
		t.expect(shadow.Transparency).toBe(0.2)
		stopReactive()
		reactive.dispose()
		local unknown = themes.neutralPackage()
		unknown.chrome.control = { kind = "native", shadow = "floaty" }
		local rejected, failure = themes.define(unknown)
		t.expect(rejected).toBe(nil)
		t.expect(failure.errors[1].field).toBe("chrome.control.shadow")
	end)
end)

local function countWrites(sheet: any): { [any]: number }
	local writes: { [any]: number } = {}
	for _, rule in sheet:GetChildren() do
		local meta = getmetatable(rule)
		local index = meta.__index
		local original = rule.SetProperties
		local counted = function(self: any, properties: any)
			writes[self] = (writes[self] or 0) + 1
			return original(self, properties)
		end
		meta.__index = function(self: any, key: any)
			return if key == "SetProperties" then counted else index(self, key)
		end
	end
	return writes
end

t.describe("native paint strength: theme sheets", function()
	t.it("falls back to GuiService for reduced motion and to a 0.2 second paint transition", function()
		local h = harness()
		local environment = (getfenv :: any)(0)
		local gui = h.engine.new("GuiService")
		gui.ReducedMotionEnabled = false
		gui.PreferredTransparency = 0.5
		local requested = {}
		environment.game = {
			GetService = function(_, name: string)
				table.insert(requested, name)
				return gui
			end,
		}
		local package = themes.neutralPackage()
		package.metrics.motion = nil
		local stop, sheet = h.runtime.mount(function()
			return themes.createStyleSheet(h.runtime, package, { types = h.engine.types })
		end, h.engine.new("Folder"))
		environment.game = nil
		t.expect(requested).toEqual({ "GuiService", "GuiService", "UserInputService" })
		local text = ruleNode(sheet, ".facet-text")
		local timing = text:GetPropertyTransitions().TextColor3
		t.expect(timing.Time).toBe(0.2)
		t.expect(timing.EasingStyle).toBe(h.engine.types.Enum.EasingStyle.Quad)
		t.expect(timing.EasingDirection).toBe(h.engine.types.Enum.EasingDirection.Out)
		t.expect(ruleNode(sheet, ".facet-surface"):GetPropertyTransitions().BackgroundTransparency).toBe(timing)
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBeCloseTo(0.55 * 0.5)
		gui.ReducedMotionEnabled = true
		t.expect(text:GetPropertyTransitions().TextColor3.Time).toBe(0)
		gui.ReducedMotionEnabled = false
		t.expect(text:GetPropertyTransitions().TextColor3.Time).toBe(0.2)
		gui.PreferredTransparency = 1
		t.expect(style(sheet, ".facet-scrim").BackgroundTransparency).toBeCloseTo(0.55)
		t.expect(gui:GetPropertyChangedSignal("ReducedMotionEnabled").count()).toBe(1)
		t.expect(gui:GetPropertyChangedSignal("PreferredTransparency").count()).toBe(1)
		stop()
		t.expect(gui:GetPropertyChangedSignal("ReducedMotionEnabled").count()).toBe(0)
		t.expect(gui:GetPropertyChangedSignal("PreferredTransparency").count()).toBe(0)
		local halfDeclared = themes.neutralPackage()
		halfDeclared.metrics.motion = { fast = 0.1 }
		local second, stopSecond = sheetFor(h, halfDeclared)
		t.expect(ruleNode(second, ".facet-text"):GetPropertyTransitions().TextColor3.Time).toBe(0.2)
		stopSecond()
		local headless, stopHeadless = sheetFor(h, themes.neutralPackage(), { reducedMotion = nil })
		t.expect(ruleNode(headless, ".facet-text"):GetPropertyTransitions().TextColor3.Time).toBe(0.2)
		stopHeadless()
		h.dispose()
	end)

	t.it("writes per-side button insets to the padding rules and costs no writes when nothing changes", function()
		local h = harness()
		local UDim = h.engine.types.UDim
		local package = Compose.cell(themes.neutralPackage())
		local sheet, stop = sheetFor(h, package)
		local function padding(selector: string): { number }
			local properties = style(sheet, selector)
			return {
				properties.PaddingLeft and properties.PaddingLeft.Offset,
				properties.PaddingRight and properties.PaddingRight.Offset,
				properties.PaddingTop and properties.PaddingTop.Offset,
				properties.PaddingBottom and properties.PaddingBottom.Offset,
			} :: any
		end
		t.expect(padding(".facet-button::UIPadding")).toEqual({ 12, 12, 0, 0 })
		t.expect(padding(".facet-button > UIPadding")).toEqual({ 12, 12, 0, 0 })
		t.expect(padding(".facet-shape-circle::UIPadding")).toEqual({ 0, 0, 0, 0 })
		t.expect(padding(".facet-badge::UIPadding")).toEqual({ 8, 8, 3, 3 })
		local writes = countWrites(sheet)
		package:set(themes.neutralPackage())
		t.expect(next(writes)).toBe(nil)
		local inset = themes.neutralPackage()
		inset.assets.plate = { content = "rbxassetid://9" }
		inset.chrome.control = {
			kind = "nineSlice",
			asset = "plate",
			contentInsets = { left = 20, right = 14, top = 6, bottom = 9 },
		}
		package:set(inset)
		t.expect(padding(".facet-button::UIPadding")).toEqual({ 20, 14, 6, 9 })
		t.expect(padding(".facet-button > UIPadding")).toEqual({ 20, 14, 6, 9 })
		t.expect(style(sheet, ".facet-button-described::UIPadding").PaddingTop).toBe(UDim.new(0, 10))
		t.expect(style(sheet, ".facet-button-described::UIPadding").PaddingBottom).toBe(UDim.new(0, 10))
		t.expect(style(sheet, ".facet-busy::UIPadding").PaddingRight).toBe(UDim.new(0, 34))
		t.expect(style(sheet, ".facet-disclosure::UIPadding").PaddingRight).toBe(UDim.new(0, 34))
		t.expect(writes[ruleNode(sheet, ".facet-button::UIPadding")]).toBe(1)
		t.expect(writes[ruleNode(sheet, ".facet-button > UIPadding")]).toBe(1)
		t.expect(writes[ruleNode(sheet, ".facet-field::UIPadding")]).toBe(nil)
		t.expect(writes[ruleNode(sheet, ".facet-button")]).toBe(nil)
		t.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]).toBe(nil)
		table.clear(writes)
		local same = themes.neutralPackage()
		same.assets.plate = { content = "rbxassetid://9" }
		same.chrome.control = {
			kind = "nineSlice",
			asset = "plate",
			contentInsets = { left = 20, right = 14, top = 6, bottom = 9 },
		}
		package:set(same)
		t.expect(next(writes)).toBe(nil)
		local narrow = table.clone(same)
		narrow.chrome = table.clone(same.chrome)
		narrow.chrome.control = { kind = "nineSlice", asset = "plate", contentInsets = { left = 4, top = 2 } }
		package:set(narrow)
		t.expect(padding(".facet-button::UIPadding")).toEqual({ 12, 12, 2, 0 })
		table.clear(writes)
		local metric = table.clone(narrow)
		metric.metrics = table.clone(narrow.metrics)
		metric.metrics.radii = { control = 5, panel = 12, pill = 999 }
		package:set(metric)
		t.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]).toBe(1)
		t.expect(style(sheet, ".facet-button::UICorner").CornerRadius).toBe(UDim.new(0, 5))
		t.expect(writes[ruleNode(sheet, ".facet-button::UIPadding")]).toBe(nil)
		stop()
		h.dispose()
	end)

	t.it("orders every state rule after its base and disabled after selection in every shipped sheet", function()
		local h = harness()
		local packages = { themes.neutralPackage() }
		for _, name in SHIPPED do
			table.insert(packages, (shipped(name)))
		end
		local checkedStates = 0
		for _, package in packages do
			for _, palette in package.style.themes do
				local sheet, stop = sheetFor(h, package, { theme = palette.name })
				local first: { [string]: number } = {}
				for _, rule in sheet:GetChildren() do
					if first[rule.Selector] == nil then
						first[rule.Selector] = rule.Priority
					end
				end
				for selector, priority in first do
					local base, state = string.match(selector, "^(.-):(%a+)$")
					if base and string.sub(base, -1) ~= ":" and (state == "Hover" or state == "Press") then
						t.expect(first[base] ~= nil).toBe(true)
						t.expect(priority > first[base]).toBe(true)
						checkedStates += 1
						if state == "Press" and first[base .. ":Hover"] then
							t.expect(priority > first[base .. ":Hover"]).toBe(true)
						end
					end
				end
				t.expect(first[".facet-text"] < first[".facet-surface"]).toBe(true)
				t.expect(first[".facet-control"] < first[".facet-button:Hover"]).toBe(true)
				t.expect(first[".facet-button:Hover"] < first[".facet-button:Press"]).toBe(true)
				t.expect(first[".facet-button:Press"] < first[".facet-selected"]).toBe(true)
				t.expect(first[".facet-selected"] < first[".facet-disabled"]).toBe(true)
				for _, role in { ".facet-role-destructive", ".facet-accent", ".facet-appearance-soft" } do
					t.expect(first[role] > first[".facet-button"]).toBe(true)
				end
				t.expect(first[".facet-skinned"] > first[".facet-segment-current:Hover"]).toBe(true)
				stop()
			end
		end
		t.expect(checkedStates > 12 * 15).toBe(true)
		h.dispose()
	end)

	t.it("paints the authored selected label or the content color and rejects an unreadable one", function()
		local h = harness()
		local colors, extra = neutralColors()
		local sheet, stop = sheetFor(h, themes.neutralPackage())
		for _, selector in { ".facet-selected", ".facet-selected >> .facet-text" } do
			t.expect(style(sheet, selector).TextColor3).toBe(color(h.engine, colors.content))
		end
		t.expect(style(sheet, ".facet-selected >> .facet-icon").ImageColor3).toBe(color(h.engine, colors.content))
		stop()
		local authored = themes.neutralPackage()
		authored.style.themes[1].extra.controlSelected = { r = 0.1, g = 0.3, b = 0.8 }
		authored.style.themes[1].extra.onSelected = { r = 1, g = 1, b = 1 }
		local package, report = themes.define(authored)
		t.expect(report.ok).toBe(true)
		local pairs = {}
		for _, entry in report.contrast do
			if entry.pair == "onSelected/controlSelected" then
				table.insert(pairs, entry)
			end
		end
		t.expect(#pairs).toBe(#authored.style.themes)
		t.expect(pairs[1].ok).toBe(true)
		t.expect(pairs[1].ratio).toBeCloseTo(contrast({ r = 1, g = 1, b = 1 }, { r = 0.1, g = 0.3, b = 0.8 }))
		for index = 2, #pairs do
			local palette = authored.style.themes[index]
			t.expect(pairs[index].ok).toBe(true)
			t.expect(pairs[index].ratio)
				.toBeCloseTo(contrast(palette.extra.onSelected or palette.colors.content, palette.extra.controlSelected))
		end
		local authoredSheet, stopAuthored = sheetFor(h, package)
		local white = h.engine.types.Color3.new(1, 1, 1)
		local root, stopMount = mount(h, function()
			return h.UI.Button({ Name = "Chosen", label = "Chosen", icon = "checkmark", selected = true })
		end)
		local chosen = find(root, "Chosen")
		t.expect(resolve(authoredSheet, chosen, "BackgroundColor3")).toBe(h.engine.types.Color3.new(0.1, 0.3, 0.8))
		t.expect(resolve(authoredSheet, find(chosen, "Title"), "TextColor3")).toBe(white)
		t.expect(resolve(authoredSheet, find(chosen, "LeadingIcon"), "ImageColor3")).toBe(white)
		stopMount()
		stopAuthored()
		local unreadable = themes.neutralPackage()
		unreadable.style.themes[1].extra.onSelected = unreadable.style.themes[1].extra.controlSelected
		local rejected, failure = themes.define(unreadable)
		t.expect(rejected).toBe(nil)
		t.expect(failure.errors[1].field).toBe("style.Dark")
		t.expect(failure.errors[1].message).toBe("onSelected contrast is below 4.5:1")
		local dark = themes.neutralPackage()
		dark.style.themes[1].extra.controlSelected = { r = 0.85, g = 0.88, b = 0.92 }
		local noPartner = themes.define(dark)
		t.expect(noPartner).toBe(nil)
		t.expect(extra.onSelected).toBe(nil)
		h.dispose()
	end)

	t.it("rewrites only changed rules and keeps a designer edit on an untouched rule", function()
		local h = harness()
		local base = themes.neutralPackage()
		local package = Compose.cell(base)
		local sheet, stop = sheetFor(h, package)
		local writes = countWrites(sheet)
		local tooltip = ruleNode(sheet, ".facet-tooltip::UIStroke")
		local edited = tooltip:GetProperties()
		edited.Thickness = 3
		tooltip:SetProperties(edited)
		table.clear(writes)
		local recolored = themes.neutralPackage()
		recolored.style.themes[1].colors.accent = { r = 0.9, g = 0.2, b = 0.4 }
		package:set(recolored)
		local accent = h.engine.types.Color3.new(0.9, 0.2, 0.4)
		t.expect(style(sheet, ".facet-accent").BackgroundColor3).toBe(accent)
		t.expect(writes[ruleNode(sheet, ".facet-accent")]).toBe(1)
		t.expect(writes[tooltip]).toBe(nil)
		t.expect(tooltip:GetProperties().Thickness).toBe(3)
		t.expect(writes[ruleNode(sheet, ".facet-text")]).toBe(nil)
		t.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]).toBe(nil)
		for rule in writes do
			local properties = rule:GetProperties()
			local touched = false
			for _, value in properties do
				if value == accent then
					touched = true
				end
			end
			t.expect(touched).toBe(true)
		end
		table.clear(writes)
		local metric = themes.neutralPackage()
		metric.style.themes[1].colors.accent = { r = 0.9, g = 0.2, b = 0.4 }
		metric.metrics.radii.control = 3
		metric.metrics.typography.control.size = 22
		package:set(metric)
		t.expect(writes[ruleNode(sheet, ".facet-button::UICorner")]).toBe(1)
		t.expect(style(sheet, ".facet-button::UICorner").CornerRadius).toBe(h.engine.types.UDim.new(0, 3))
		t.expect(writes[ruleNode(sheet, ".facet-button")]).toBe(1)
		t.expect(style(sheet, ".facet-button").TextSize).toBe(22)
		t.expect(writes[ruleNode(sheet, ".facet-accent")]).toBe(nil)
		t.expect(writes[tooltip]).toBe(nil)
		t.expect(tooltip:GetProperties().Thickness).toBe(3)
		stop()
		h.dispose()
	end)

	t.it("keeps each selection art declaration close to its sampled plate and pins the readable label", function()
		local samples = serde.decode("json", fs.readFile("assets/themes/plate-samples.json")).samples
		local function distance(a: any, b: any): number
			return math.sqrt((a.r - b.r) ^ 2 + (a.g - b.g) ^ 2 + (a.b - b.b) ^ 2)
		end
		local pinned = {}
		local hashed = 0
		for key, entry in samples do
			for _, sample in entry do
				t.expect(serde.hash("sha256", fs.readFile(sample.file))).toBe(sample.sha256)
				t.expect(sample.alpha >= 0.9).toBe(true)
				hashed += 1
			end
			local plate = entry.selected
			if plate then
				local package = shipped((string.gsub(key, "-", "_")))
				local art = { r = plate.r / 255, g = plate.g / 255, b = plate.b / 255 }
				for _, palette in package.style.themes do
					local colors, extra = paletteOf(palette)
					local accent = colors.accent
					local tint = {
						r = 1 + (accent.r - 1) * 0.35,
						g = 1 + (accent.g - 1) * 0.35,
						b = 1 + (accent.b - 1) * 0.35,
					}
					local tinted = { r = art.r * tint.r, g = art.g * tint.g, b = art.b * tint.b }
					t.expect(distance(extra.controlSelected, tinted) <= 0.12).toBe(true)
					local label = extra.onSelected or colors.content
					t.expect(contrast(label, art) >= 4.5).toBe(true)
					t.expect(contrast(label, extra.controlSelected) >= 4.5).toBe(true)
					table.insert(pinned, `{key}/{palette.name}={if extra.onSelected then "onSelected" else "content"}`)
				end
			end
		end
		table.sort(pinned)
		t.expect(hashed).toBe(9)
		t.expect(table.concat(pinned, " ")).toBe(
			"compact-pointer/Aqua=content fantasy-ornate/Crypt=content fantasy-ornate/Grand Hall=content "
				.. "glossy-touch/Sky=onSelected pixel-quest/Quest=onSelected"
		)
	end)

	t.it("reports contrast with the written-out WCAG formula for every shipped pair", function()
		local function wcag(value: any): number
			local function linear(channel: number): number
				return if channel <= 0.03928 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * linear(value.r) + 0.7152 * linear(value.g) + 0.0722 * linear(value.b)
		end
		local function ratio(first: any, second: any): number
			local a, b = wcag(first), wcag(second)
			return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
		end
		local measured = 0
		for _, name in SHIPPED do
			local package, report = shipped(name)
			local index = 0
			for _, palette in package.style.themes do
				local colors, extra = paletteOf(palette)
				for _, pair in
					{
						{ "content", "surface" },
						{ "contentStrong", "surfaceStrong" },
						{ "onAccent", "accent" },
						{ "onDanger", "danger" },
						{ "onSuccess", "success" },
						{ "onWarning", "warning" },
						{ "onSelected", "controlSelected" },
					}
				do
					index += 1
					local entry = report.contrast[index]
					t.expect(entry.pair).toBe(pair[1] .. "/" .. pair[2])
					local first = colors[pair[1]] or extra[pair[1]] or colors.content
					local second = colors[pair[2]] or extra[pair[2]]
					t.expect(math.abs(entry.ratio - ratio(first, second)) < 1e-4).toBe(true)
					t.expect(math.abs(entry.ratio - contrast(first, second)) < 1e-9).toBe(true)
					t.expect(entry.ok).toBe(entry.ratio >= 4.5)
					measured += 1
				end
			end
			t.expect(#report.contrast).toBe(index)
		end
		t.expect(measured).toBe(11 * 7)
		local extreme = themes.neutralPackage()
		extreme.style.themes[1].colors.content = { r = 1, g = 1, b = 1 }
		extreme.style.themes[1].colors.surface = { r = 0, g = 0, b = 0 }
		local _, report = themes.define(extreme)
		t.expect(report.contrast[1].pair).toBe("content/surface")
		t.expect(report.contrast[1].ratio).toBe(21)
		local same = themes.neutralPackage()
		same.style.themes[1].colors.content = same.style.themes[1].colors.surface
		local _, flat = themes.define(same)
		t.expect(flat.contrast[1].ratio).toBe(1)
		t.expect(flat.contrast[1].ok).toBe(false)
	end)

	t.it("keeps every token pair readable and the accent indicator visible on its surface", function()
		local h = harness()
		local entries = { { id = "neutral", package = themes.neutralPackage() } }
		for _, name in SHIPPED do
			table.insert(entries, { id = name, package = (shipped(name)) })
		end
		for _, entry in entries do
			for _, palette in entry.package.style.themes do
				local colors, extra = paletteOf(palette)
				t.expect(contrast(colors.content, colors.surface) >= 4.5).toBe(true)
				t.expect(contrast(colors.contentStrong, colors.surfaceStrong) >= 4.5).toBe(true)
				t.expect(contrast(colors.onAccent, colors.accent) >= 4.5).toBe(true)
				t.expect(contrast(colors.accent, colors.surface) >= 3).toBe(true)
				local sheet, stop = sheetFor(h, entry.package, { theme = palette.name })
				t.expect(style(sheet, ".facet-selection-indicator").BackgroundColor3)
					.toBe(color(h.engine, colors.accent))
				t.expect(style(sheet, ".facet-surface").BackgroundColor3).toBe(color(h.engine, colors.surface))
				t.expect(style(sheet, ".facet-text").TextColor3).toBe(color(h.engine, colors.content))
				t.expect(style(sheet, ".facet-accent").TextColor3).toBe(color(h.engine, colors.onAccent))
				t.expect(style(sheet, ".facet-selected").BackgroundColor3).toBe(color(h.engine, extra.controlSelected))
				stop()
			end
		end
		local weak = themes.neutralPackage()
		weak.style.themes[1].colors.accent = { r = 0.1, g = 0.1, b = 0.13 }
		t.expect(contrast(weak.style.themes[1].colors.accent, weak.style.themes[1].colors.surface) < 3).toBe(true)
		h.dispose()
	end)

	t.it("composes the sheet scrim and the full-screen backdrop from the same clamped preference", function()
		local h = harness({ reducedMotion = true })
		local preference = Compose.cell(1 :: any)
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage(), { preferredTransparency = preference })
		local base = 1 - 0.45
		local source
		local root, stop = mount(h, function()
			source = h.Host.Frame({ Name = "Source" })
			return h.Host.Frame({
				source,
				h.UI.Alert({
					isPresented = Compose.cell(true),
					title = "Map",
					surface = "fullScreen",
					transition = { source = source },
					actions = { { id = "close", label = "Close", role = "cancel" } },
				}),
			})
		end)
		local backdrop = find(root.Parent, "DismissOutside")
		t.expect(backdrop:HasTag("facet-scrim")).toBe(true)
		local backdropBase = backdrop.BackgroundTransparency
		t.expect(backdropBase).toBeCloseTo(0.35)
		local expected = { [1] = 1, [0.5] = 0.5, [0.25] = 0.25, [0] = 0, [-1] = 0, [2] = 1 }
		local inputs: { any } = { 1, 0.5, 0.25, 0, -1, 2, 0 / 0, "opaque" }
		for _, value in inputs do
			preference:set(value)
			h.gui.PreferredTransparency = value
			local clamped = if type(value) == "number" and value == value then expected[value] else 1
			local fromSheet = style(sheet, ".facet-scrim").BackgroundTransparency
			local fromBackdrop = backdrop.BackgroundTransparency
			t.expect(fromSheet).toBeCloseTo(if clamped >= 1 then base else base * clamped)
			t.expect(fromBackdrop).toBeCloseTo(backdropBase * clamped)
			t.expect(fromSheet / base).toBeCloseTo(fromBackdrop / backdropBase)
		end
		stop()
		stopSheet()
		h.dispose()
	end)
end)

t.describe("native paint strength: value and status paint", function()
	t.it("sizes ring strokes, bar tracks and spinner dots from theme metrics unless authored", function()
		local colors, extra = neutralColors()
		local package = Compose.cell(themes.neutralPackage())
		local h = harness({ theme = package })
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
		local diameter = Compose.cell(32)
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.ProgressView({ Name = "Ring", presentation = "circular", value = 0.5, diameter = diameter }),
				h.UI.ProgressView({ Name = "Authored", presentation = "circular", value = 0.5, thickness = 5 }),
				h.UI.ProgressView({ Name = "Bar", value = 0.5 }),
				h.UI.ProgressView({ Name = "Thin", value = 0.5, thickness = 4 }),
				h.UI.ProgressView({ Name = "Spinner", presentation = "spinner" }),
			})
		end)
		local ring = find(root, "Ring")
		local fill, track = find(ring, "RingFill"), find(ring, "RingTrack")
		for _, case in { { 32, 3 }, { 20, 3 }, { 100, 8 }, { 64, 5 } } do
			diameter:set(case[1])
			t.expect(fill.Thickness).toBe(case[2])
			t.expect(track.Thickness).toBe(case[2])
		end
		local authored = find(find(root, "Authored"), "RingFill")
		t.expect(authored.Thickness).toBe(5)
		t.expect(find(find(root, "Bar"), "Track").Size).toBe(h.engine.types.UDim2.new(1, 0, 0, 6))
		t.expect(find(find(root, "Thin"), "Track").Size).toBe(h.engine.types.UDim2.new(1, 0, 0, 4))
		t.expect(find(find(root, "Spinner"), "Segment1").Size).toBe(h.engine.types.UDim2.fromOffset(4, 4))
		local retuned = themes.neutralPackage()
		retuned.metrics.controls.progress =
			{ trackHeight = 10, circularSize = 32, circularThickness = 7, spinnerDotSize = 6 }
		package:set(retuned)
		t.expect(fill.Thickness).toBe(7)
		t.expect(track.Thickness).toBe(7)
		diameter:set(100)
		t.expect(fill.Thickness).toBe(8)
		t.expect(authored.Thickness).toBe(5)
		t.expect(find(find(root, "Bar"), "Track").Size).toBe(h.engine.types.UDim2.new(1, 0, 0, 10))
		t.expect(find(find(root, "Thin"), "Track").Size).toBe(h.engine.types.UDim2.new(1, 0, 0, 4))
		t.expect(find(find(root, "Spinner"), "Segment1").Size).toBe(h.engine.types.UDim2.fromOffset(6, 6))
		t.expect(resolve(sheet, fill, "Color3")).toBe(color(h.engine, colors.accent))
		t.expect(resolve(sheet, track, "Color3")).toBe(color(h.engine, extra.control))
		stop()
		stopSheet()
		h.dispose()
	end)

	t.it("paints each level half with its own tint and returns an omitted half to the theme", function()
		local h = harness()
		local colors, extra = neutralColors()
		local sheet, stopSheet = sheetFor(h, themes.neutralPackage())
		local Color3 = h.engine.types.Color3
		local red, green, blue = Color3.new(1, 0, 0), Color3.new(0, 1, 0), Color3.new(0, 0, 1)
		local bars, glyphs, images, plain = Compose.cell(3), Compose.cell(2), Compose.cell(1), Compose.cell(2)
		local filledTint = Compose.cell(red)
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.LevelPicker({
					Name = "Bars",
					value = bars,
					count = 10,
					tint = { filled = filledTint, empty = green },
				}),
				h.UI.LevelPicker({
					Name = "Glyphs",
					value = glyphs,
					count = 3,
					segment = "glyph",
					tint = { filled = red },
				}),
				h.UI.LevelPicker({
					Name = "Images",
					value = images,
					count = 3,
					segment = "image",
					images = { filled = "rbxassetid://1", empty = "rbxassetid://2" },
					tint = { empty = green },
				}),
				h.UI.LevelPicker({ Name = "Plain", value = plain, count = 4 }),
			})
		end)
		local function mark(name: string, index: number): any
			return find(find(root, name), "Level" .. index)
		end
		for index = 1, 10 do
			t.expect(mark("Bars", index).BackgroundColor3).toBe(if index <= 3 then red else green)
		end
		bars:set(7)
		t.expect(mark("Bars", 7).BackgroundColor3).toBe(red)
		t.expect(mark("Bars", 8).BackgroundColor3).toBe(green)
		filledTint:set(blue)
		t.expect(mark("Bars", 1).BackgroundColor3).toBe(blue)
		t.expect(mark("Bars", 8).BackgroundColor3).toBe(green)
		local untouched = h.engine.new("TextLabel").TextColor3
		t.expect(mark("Glyphs", 1).TextColor3).toBe(red)
		t.expect(mark("Glyphs", 3).TextColor3).toBe(untouched)
		t.expect(resolve(sheet, mark("Glyphs", 3), "TextColor3")).toBe(color(h.engine, colors.content))
		glyphs:set(1)
		t.expect(mark("Glyphs", 2).TextColor3).toBe(untouched)
		t.expect(mark("Glyphs", 1).TextColor3).toBe(red)
		glyphs:set(3)
		t.expect(mark("Glyphs", 3).TextColor3).toBe(red)
		local defaultImage = h.engine.new("ImageLabel").ImageColor3
		t.expect(mark("Images", 1).ImageColor3).toBe(defaultImage)
		t.expect(mark("Images", 2).ImageColor3).toBe(green)
		images:set(3)
		t.expect(mark("Images", 2).ImageColor3).toBe(defaultImage)
		t.expect(mark("Images", 2).Image).toBe("rbxassetid://1")
		local filled, empty = mark("Plain", 1), mark("Plain", 4)
		t.expect(resolve(sheet, filled, "BackgroundColor3")).toBe(color(h.engine, colors.accent))
		t.expect(resolve(sheet, empty, "BackgroundColor3")).toBe(color(h.engine, extra.control))
		t.expect(resolve(sheet, filled, "BackgroundColor3") ~= resolve(sheet, empty, "BackgroundColor3")).toBe(true)
		plain:set(4)
		t.expect(resolve(sheet, empty, "BackgroundColor3")).toBe(color(h.engine, colors.accent))
		stop()
		stopSheet()
		h.dispose()
	end)

	t.it("paints an unstatused badge as a control plate with content text and no focus stop", function()
		local h = harness()
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.Badge({ Name = "Plain", label = "New" }),
				h.UI.Badge({ Name = "Iconic", label = "New", icon = "checkmark" }),
				h.UI.Badge({ Name = "Neutral", label = "New", status = Compose.cell("neutral") }),
			})
		end)
		local packages = { themes.neutralPackage() }
		for _, name in SHIPPED do
			table.insert(packages, (shipped(name)))
		end
		for _, package in packages do
			for _, palette in package.style.themes do
				local colors, extra = paletteOf(palette)
				local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
				for _, name in { "Plain", "Iconic" } do
					local pill = find(root, name)
					for _, tag in pill:GetTags() do
						t.expect(string.sub(tag, 1, 13) == "facet-status-").toBe(false)
					end
					t.expect(resolve(sheet, pill, "BackgroundColor3")).toBe(color(h.engine, extra.control))
					t.expect(resolve(sheet, pill, "BackgroundTransparency")).toBe(0)
					t.expect(resolve(sheet, pill, "CornerRadius", "UICorner"))
						.toBe(h.engine.types.UDim.new(0, package.metrics.radii.control))
					t.expect(resolve(sheet, pill, "PaddingLeft", "UIPadding").Offset >= 8).toBe(true)
					t.expect(resolve(sheet, pill, "PaddingTop", "UIPadding").Offset >= 3).toBe(true)
					local text = if pill:IsA("TextLabel") then pill else find(pill, "Label")
					t.expect(resolve(sheet, text, "TextColor3")).toBe(color(h.engine, colors.content))
				end
				local icon = find(root, "Iconic"):FindFirstChildWhichIsA("ImageLabel")
				t.expect(resolve(sheet, icon, "ImageColor3")).toBe(color(h.engine, colors.content))
				local neutral = find(root, "Neutral")
				t.expect(resolve(sheet, neutral, "BackgroundColor3")).toBe(color(h.engine, extra.contentSecondary))
				t.expect(resolve(sheet, neutral, "TextColor3")).toBe(color(h.engine, colors.surface))
				stopSheet()
			end
		end
		for _, name in { "Plain", "Iconic", "Neutral" } do
			local pill = find(root, name)
			for _, node in { pill, table.unpack(pill:GetDescendants()) } do
				if node:IsA("GuiObject") then
					t.expect(node.Selectable).toBe(false)
				end
			end
		end
		stop()
		h.dispose()
	end)

	t.it("paints every status with its shared palette pair and caps the count at the authored max", function()
		local h = harness()
		local pairs = {
			neutral = { "contentSecondary", "surface" },
			info = { "accent", "onAccent" },
			success = { "success", "onSuccess" },
			warning = { "warning", "onWarning" },
			error = { "danger", "onDanger" },
			accent = { "accent", "onAccent" },
		}
		local count, capped = Compose.cell(0), Compose.cell(0)
		local status = Compose.cell("neutral")
		local root, stop = mount(h, function()
			return h.Host.Frame({
				h.UI.StatusIndicator({ Name = "Count", status = status, count = count }),
				h.UI.StatusIndicator({ Name = "Capped", status = status, count = capped, max = 9 }),
				h.UI.StatusIndicator({ Name = "Ring", status = status, form = "ring", diameter = 16 }),
			})
		end)
		local node, cappedNode = find(root, "Count"), find(root, "Capped")
		local ring = find(root, "Ring"):FindFirstChildWhichIsA("UIStroke")
		t.expect(node:FindFirstChildWhichIsA("UISizeConstraint").MinSize).toBe(h.engine.types.Vector2.new(24, 24))
		for _, entry in { { 0, "0" }, { 9, "9" }, { 99, "99" }, { 100, "99+" }, { 1000, "99+" } } do
			count:set(entry[1])
			t.expect(node.Text).toBe(entry[2])
		end
		for _, entry in { { 0, "0" }, { 9, "9" }, { 10, "9+" }, { 1000, "9+" } } do
			capped:set(entry[1])
			t.expect(cappedNode.Text).toBe(entry[2])
		end
		local packages = { themes.neutralPackage() }
		for _, name in SHIPPED do
			table.insert(packages, (shipped(name)))
		end
		for _, package in packages do
			for _, palette in package.style.themes do
				local colors, extra = paletteOf(palette)
				local sheet, stopSheet = sheetFor(h, package, { theme = palette.name })
				for name, pair in pairs do
					status:set(name)
					local fill = colors[pair[1]] or extra[pair[1]]
					local partner = colors[pair[2]] or extra[pair[2]]
					for _, indicator in { node, cappedNode } do
						t.expect(resolve(sheet, indicator, "BackgroundColor3")).toBe(color(h.engine, fill))
						t.expect(resolve(sheet, indicator, "TextColor3")).toBe(color(h.engine, partner))
						t.expect(resolve(sheet, indicator, "BackgroundTransparency")).toBe(0)
					end
					t.expect(resolve(sheet, ring, "Color")).toBe(color(h.engine, fill))
					t.expect(resolve(sheet, find(root, "Ring"), "BackgroundTransparency")).toBe(1)
				end
				stopSheet()
			end
		end
		t.expect(function()
			mount(h, function()
				return h.UI.StatusIndicator({ count = 3, max = 1.5 })
			end)
		end).toThrow()
		stop()
		h.dispose()
	end)
end)
