--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local worlds = require("./lib/content_world")
local overlay = require("./lib/overlay_world")
local engineLib = require("./lib/native_engine")
local Roblox = require("@lune/roblox")
local Compose = Facet.Compose
local themes = Facet.themes
local UDim2, Vector2, Enum = Roblox.UDim2, Roblox.Vector2, Roblox.Enum

local INK = { r = 0.97, g = 0.97, b = 0.98 }
local ON_INK = { r = 0.07, g = 0.07, b = 0.08 }
local VEIL = { r = 0.05, g = 0.05, b = 0.06 }

local function authored(extra: { [string]: any }, metrics: { [string]: any }?): any
	local neutral = themes.neutralPackage()
	local dark = neutral.style.themes[1]
	local merged = table.clone(dark.extra :: any)
	for key, value in extra do
		merged[key] = value
	end
	local package, report = themes.define({
		base = neutral,
		identity = { id = "roles", displayName = "Roles", schemaVersion = themes.SCHEMA, version = "1.0.0" },
		style = { defaultTheme = "Ink", themes = { { name = "Ink", colors = dark.colors, extra = merged } } },
		metrics = metrics,
	} :: any)
	assert(package ~= nil, "define failed: " .. tostring(report.errors[1] and report.errors[1].message))
	return package
end

local function withMetrics(metrics: { [string]: any }): (any, any)
	return themes.define({
		base = themes.neutralPackage(),
		identity = { id = "metrics", displayName = "Metrics", schemaVersion = themes.SCHEMA, version = "1.0.0" },
		metrics = metrics,
	} :: any)
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

local function resolve(sheet: any, node: any, property: string): any
	local best, value = -math.huge, nil
	for _, rule in sheet:GetChildren() do
		local selector = parse(rule.Selector)
		if selector.pseudo == nil and matchesAt(selector, #selector.parts, node) then
			local candidate = rule:GetProperties()[property]
			if candidate ~= nil and rule.Priority > best then
				best, value = rule.Priority, candidate
			end
		end
	end
	return value
end

local function sheetOf(package: any): (any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local stop, sheet = runtime.mount(function()
		return themes.createStyleSheet(
			runtime,
			package,
			{ types = engine.types, preferredTransparency = 1, reducedMotion = false } :: any
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

local function lastPriority(sheet: any, pattern: string): number
	local last = -math.huge
	for _, node in sheet:GetChildren() do
		if string.find(node.Selector, pattern, 1, true) then
			last = math.max(last, node.Priority)
		end
	end
	return last
end

local function same(color: any, rgb: any): boolean
	return color ~= nil
		and math.abs(color.R - rgb.r) < 1e-4
		and math.abs(color.G - rgb.g) < 1e-4
		and math.abs(color.B - rgb.b) < 1e-4
end

local function screen(package: any?, build: (any, any) -> any): any
	return worlds.new(function(UI, Host)
		return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), build(UI, Host) })
	end, { reducedMotion = true, theme = package })
end

t.describe("native optional palette roles", function()
	t.it("Neutral keeps its accent pair, its black scrim and no mark, plate or outline rule", function()
		local package = themes.neutralPackage()
		local colors = package.style.themes[1].colors
		local sheet, stop = sheetOf(package)
		for _, selector in { ".facet-toggle-on", ".facet-slider-fill", ".facet-selection-indicator" } do
			t.expect(`{selector} {same(ruleOf(sheet, selector):GetProperties().BackgroundColor3, colors.accent)}`)
				.toBe(`{selector} true`)
		end
		t.expect(
			same(
				ruleOf(sheet, ".facet-toggle-switch >> .facet-toggle-mark"):GetProperties().BackgroundColor3,
				colors.onAccent
			)
		).toBe(true)
		t.expect(same(ruleOf(sheet, ".facet-toggle-check"):GetProperties().ImageColor3, colors.onAccent)).toBe(true)
		t.expect(same(ruleOf(sheet, ".facet-scrim"):GetProperties().BackgroundColor3, { r = 0, g = 0, b = 0 }))
			.toBe(true)
		local extra = package.style.themes[1].extra :: any
		t.expect(
			same(
				ruleOf(sheet, ".facet-selection-mark.facet-selected"):GetProperties().BackgroundColor3,
				extra.controlSelected
			)
		).toBe(true)
		t.expect(ruleOf(sheet, ".facet-selection-mark.facet-selected:Hover")).toBeNil()
		t.expect(ruleOf(sheet, ".facet-appearance-link.facet-selected")).toBeNil()
		t.expect(ruleOf(sheet, ".facet-button.facet-disabled")).toBeNil()
		t.expect(ruleOf(sheet, ".facet-appearance-utility::UIStroke")).toBeNil()
		stop()
	end)

	t.it("authored selection, onSelection and scrim reach the switch, slider, underline, tick and backdrop", function()
		local sheet, stop = sheetOf(authored({ selection = INK, onSelection = ON_INK, scrim = VEIL }))
		for _, selector in { ".facet-toggle-on", ".facet-slider-fill", ".facet-selection-indicator" } do
			t.expect(`{selector} {same(ruleOf(sheet, selector):GetProperties().BackgroundColor3, INK)}`)
				.toBe(`{selector} true`)
		end
		for _, selector in
			{ ".facet-toggle-switch >> .facet-toggle-mark", ".facet-toggle-checkbox >> .facet-toggle-mark" }
		do
			t.expect(same(ruleOf(sheet, selector):GetProperties().BackgroundColor3, ON_INK)).toBe(true)
		end
		t.expect(same(ruleOf(sheet, ".facet-toggle-check"):GetProperties().ImageColor3, ON_INK)).toBe(true)
		t.expect(same(ruleOf(sheet, ".facet-scrim"):GetProperties().BackgroundColor3, VEIL)).toBe(true)
		stop()
	end)

	t.it("a mounted Slider fill, tab underline and switch track resolve the authored ink", function()
		local package = authored({ selection = INK, onSelection = ON_INK })
		local sheet, stopSheet = sheetOf(package)
		local world = screen(package, function(UI, Host)
			return UI.VStack({
				UI.Slider("Vol")({ value = Compose.cell(0.5), min = 0, max = 1 }),
				UI.Toggle("Sound")({ label = "Sound", value = Compose.cell(true) }),
				UI.TabView("Pages")({
					placement = "topBar",
					indicator = "underline",
					selection = Compose.cell("a"),
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								return Host.Frame({ Name = "PA" })
							end,
						},
						{
							id = "b",
							label = "B",
							content = function()
								return Host.Frame({ Name = "PB" })
							end,
						},
					},
				}),
			})
		end)
		local fill = nil
		for _, node in world.find("Vol"):GetDescendants() do
			if node:HasTag("facet-slider-fill") then
				fill = node
			end
		end
		t.expect(same(resolve(sheet, fill, "BackgroundColor3"), INK)).toBe(true)
		local underline = world.find("SelectionIndicator")
		t.expect(same(resolve(sheet, underline, "BackgroundColor3"), INK)).toBe(true)
		local track = world.find("Sound"):FindFirstChild("Indicator", true)
		t.expect(same(resolve(sheet, track, "BackgroundColor3"), INK)).toBe(true)
		t.expect(same(resolve(sheet, track:FindFirstChild("Mark"), "BackgroundColor3"), ON_INK)).toBe(true)
		world.stop()
		stopSheet()
	end)
end)

t.describe("native selection marks", function()
	t.it("a chosen Chip, a checked box and a selected link row wear the authored ink, also under hover", function()
		local package = authored({ selection = INK, onSelection = ON_INK })
		local sheet, stopSheet = sheetOf(package)
		local checked = Compose.cell(false)
		local world = screen(package, function(UI)
			return UI.VStack({
				UI.Chip("Pick")({ label = "Pick", selected = Compose.cell(true) }),
				UI.Toggle("Check")({ label = "Check", presentation = "checkbox", value = checked }),
				UI.Button("Link")({ label = "Tracks", appearance = "link", selected = true }),
			})
		end)
		local chip = world.find("Pick")
		t.expect(chip:HasTag("facet-selection-mark")).toBe(true)
		t.expect(same(resolve(sheet, chip, "BackgroundColor3"), INK)).toBe(true)
		t.expect(same(resolve(sheet, chip, "TextColor3"), ON_INK)).toBe(true)
		local hover = ruleOf(sheet, ".facet-selection-mark.facet-selected:Hover")
		t.expect(same(hover:GetProperties().BackgroundColor3, INK)).toBe(true)
		t.expect(hover.Priority > lastPriority(sheet, ".facet-button:Hover")).toBe(true)
		t.expect(hover.Priority > ruleOf(sheet, ".facet-selected").Priority).toBe(true)
		local indicator = world.find("Check"):FindFirstChild("Indicator", true)
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(false)
		t.expect(indicator:FindFirstChild("Check").Visible).toBe(false)
		t.expect(same(resolve(sheet, indicator, "BackgroundColor3"), INK)).toBe(false)
		checked:set(true)
		t.expect(indicator:HasTag("facet-toggle-on")).toBe(true)
		t.expect(same(resolve(sheet, indicator, "BackgroundColor3"), INK)).toBe(true)
		local tick = indicator:FindFirstChild("Check")
		t.expect(tick.Visible).toBe(true)
		t.expect(same(resolve(sheet, tick, "ImageColor3"), ON_INK)).toBe(true)
		t.expect(same(resolve(sheet, world.find("Link"), "TextColor3"), INK)).toBe(true)
		world.stop()
		stopSheet()
	end)

	t.it("without an authored selection a chosen Chip keeps the selected-row wash", function()
		local package = themes.neutralPackage()
		local sheet, stopSheet = sheetOf(package)
		local world = screen(package, function(UI)
			return UI.Chip("Pick")({ label = "Pick", selected = Compose.cell(true) })
		end)
		local chip = world.find("Pick")
		t.expect(same(resolve(sheet, chip, "BackgroundColor3"), package.style.themes[1].extra.controlSelected))
			.toBe(true)
		world.stop()
		stopSheet()
	end)
end)

t.describe("native whole-control disabled dim", function()
	t.it("dimDisabledPlates fades each plate toward the page, after every interaction rule", function()
		local package = authored({ dimDisabledPlates = true, disabledContentOpacity = 0.5 })
		local colors = package.style.themes[1].colors
		local sheet, stopSheet = sheetOf(package)
		local world = screen(package, function(UI)
			return UI.VStack({
				UI.Button("Go")({ label = "Go", appearance = "emphasis", enabled = false }),
				UI.Button("Stop")({ label = "Stop", role = "destructive", enabled = false }),
			})
		end)
		local function half(a: any, b: any): any
			return { r = (a.r + b.r) / 2, g = (a.g + b.g) / 2, b = (a.b + b.b) / 2 }
		end
		t.expect(same(resolve(sheet, world.find("Go"), "BackgroundColor3"), half(colors.accent, colors.surface)))
			.toBe(true)
		t.expect(same(resolve(sheet, world.find("Stop"), "BackgroundColor3"), half(colors.danger, colors.surface)))
			.toBe(true)
		local interaction = math.max(lastPriority(sheet, ":Hover"), lastPriority(sheet, ":Press"))
		for _, selector in
			{ ".facet-button.facet-disabled", ".facet-accent.facet-disabled", ".facet-disabled >> .facet-toggle-on" }
		do
			t.expect(`{selector} {ruleOf(sheet, selector).Priority > interaction}`).toBe(`{selector} true`)
		end
		world.stop()
		stopSheet()
		local neutralSheet, stopNeutral = sheetOf(themes.neutralPackage())
		t.expect(ruleOf(neutralSheet, ".facet-accent.facet-disabled")).toBeNil()
		stopNeutral()
	end)
end)

t.describe("native strong divider, pane and utility outline", function()
	t.it("a strong divider is three times the hairline unless the theme authors its opacity", function()
		local sheet, stop = sheetOf(themes.neutralPackage())
		local engine: any = engineLib.new()
		local rule = engine.new("Frame")
		rule:AddTag("facet-divider")
		rule:AddTag("facet-divider-strong")
		t.expect(math.abs(resolve(sheet, rule, "BackgroundTransparency") - 0.76) < 1e-9).toBe(true)
		stop()
		local authoredSheet, stopAuthored = sheetOf(authored({ strongHairlineOpacity = 0.6 }))
		t.expect(resolve(authoredSheet, rule, "BackgroundTransparency")).toBe(0.6)
		stopAuthored()
		local engine2: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine2)
		local stopDim, dimmed = runtime.mount(function()
			return themes.createStyleSheet(
				runtime,
				themes.neutralPackage(),
				{ types = engine2.types, preferredTransparency = 0.5, reducedMotion = true } :: any
			)
		end, engine2.new("Folder"))
		t.expect(math.abs(resolve(dimmed, rule, "BackgroundTransparency") - 0.76) < 1e-9).toBe(true)
		t.expect(ruleOf(dimmed, ".facet-scrim"):GetProperties().BackgroundTransparency).toBe(0.275)
		stopDim()
		runtime:dispose()
		local neutralSheet, stopNeutral = sheetOf(themes.neutralPackage())
		local strong = Compose.cell("strong")
		local world = screen(themes.neutralPackage(), function(UI)
			return UI.VStack({ UI.Divider("Edge")({ appearance = strong }) })
		end)
		local edge = world.find("Edge")
		t.expect(edge:HasTag("facet-divider")).toBe(true)
		t.expect(edge:HasTag("facet-divider-strong")).toBe(true)
		t.expect(math.abs(resolve(neutralSheet, edge, "BackgroundTransparency") - 0.76) < 1e-9).toBe(true)
		strong:set("standard")
		t.expect(edge:HasTag("facet-divider-strong")).toBe(false)
		t.expect(math.abs(resolve(neutralSheet, edge, "BackgroundTransparency") - 0.92) < 1e-9).toBe(true)
		world.stop()
		stopNeutral()
	end)

	t.it("the see-through backgrounds are a measured set, and the preference moves only the scrim", function()
		local function census(preference: number): { [string]: number }
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local found: { [string]: number } = {}
			local stop, sheet = runtime.mount(function()
				return themes.createStyleSheet(
					runtime,
					themes.neutralPackage(),
					{ types = engine.types, preferredTransparency = preference, reducedMotion = true } :: any
				)
			end, engine.new("Folder"))
			for _, node in sheet:GetDescendants() do
				if node.ClassName == "StyleRule" then
					local value = node:GetProperties().BackgroundTransparency
					if type(value) == "number" and value > 0 and value < 1 then
						found[node.Selector] = value
					end
				end
			end
			stop()
			runtime:dispose()
			return found
		end
		local full, half = census(1), census(0.5)
		local names: { string } = {}
		for selector in full do
			table.insert(names, selector)
		end
		table.sort(names)
		t.expect(table.concat(names, " ")).toBe(table.concat({
			".facet-appearance-soft",
			".facet-appearance-soft:Hover",
			".facet-appearance-soft:Press",
			".facet-choice-current",
			".facet-choice-current:Hover",
			".facet-choice-current:Press",
			".facet-divider",
			".facet-divider-strong",
			".facet-grabber",
			".facet-menu-hairline",
			".facet-scrim",
		}, " "))
		local moved: { string } = {}
		for _, selector in names do
			if math.abs(full[selector] - (half[selector] or -1)) > 1e-9 then
				table.insert(moved, selector)
			end
		end
		t.expect(table.concat(moved, " ")).toBe(".facet-scrim")
		t.expect(math.abs(half[".facet-scrim"] - full[".facet-scrim"] * 0.5) < 1e-9).toBe(true)
	end)

	t.it("a pane is the raised fill with no corner and no edge", function()
		local package = themes.neutralPackage()
		local sheet, stop = sheetOf(package)
		local engine: any = engineLib.new()
		local pane = engine.new("Frame")
		pane:AddTag("facet-pane")
		t.expect(same(resolve(sheet, pane, "BackgroundColor3"), package.style.themes[1].colors.surfaceStrong))
			.toBe(true)
		t.expect(resolve(sheet, pane, "BackgroundTransparency")).toBe(0)
		for _, node in sheet:GetChildren() do
			t.expect(string.find(node.Selector, "facet-pane::", 1, true)).toBeNil()
		end
		stop()
	end)

	t.it("strokes.utility draws the utility outline at its width, and 0 or unset draws none", function()
		local package = assert((withMetrics({ strokes = { hairline = 1, utility = 2 } })))
		local sheet, stop = sheetOf(package)
		local outline = ruleOf(sheet, ".facet-appearance-utility::UIStroke")
		t.expect(outline:GetProperties().Thickness).toBe(2)
		stop()
		local bare, stopBare = sheetOf(assert((withMetrics({ strokes = { hairline = 1, utility = 0 } }))))
		t.expect(ruleOf(bare, ".facet-appearance-utility::UIStroke")).toBeNil()
		stopBare()
	end)
end)

t.describe("native inverse and underlined Buttons", function()
	t.it("an inverse Button wears contentStrong lettered in surface, or the authored pair", function()
		local package = themes.neutralPackage()
		local colors = package.style.themes[1].colors
		local sheet, stopSheet = sheetOf(package)
		local world = screen(package, function(UI)
			return UI.Button("Inv")({ label = "Invert", appearance = "inverse" })
		end)
		local button = world.find("Inv")
		t.expect(button:HasTag("facet-appearance-inverse")).toBe(true)
		t.expect(same(resolve(sheet, button, "BackgroundColor3"), colors.contentStrong)).toBe(true)
		t.expect(same(resolve(sheet, button, "TextColor3"), colors.surface)).toBe(true)
		t.expect(same(ruleOf(sheet, ".facet-appearance-inverse:Hover"):GetProperties().TextColor3, colors.surface))
			.toBe(true)
		world.stop()
		stopSheet()
		local inkSheet, stopInk = sheetOf(authored({ inverseSurface = INK, onInverse = ON_INK }))
		t.expect(same(ruleOf(inkSheet, ".facet-appearance-inverse"):GetProperties().BackgroundColor3, INK)).toBe(true)
		stopInk()
	end)

	t.it("underline hover marks the escaped label while hovered or selected, and always marks it at rest", function()
		local world = screen(nil, function(UI)
			return UI.VStack({
				UI.Button("More")({ label = "Learn & more", appearance = "link", underline = "hover" }),
				UI.Button("Always")({ label = "Terms", appearance = "link", underline = "always" }),
			})
		end)
		local more = world.find("More")
		t.expect(more.RichText).toBe(true)
		t.expect(more.Text).toBe("Learn &amp; more")
		t.expect(world.find("Always").Text).toBe("<u>Terms</u>")
		more.GuiState = Enum.GuiState.Hover
		t.expect(more.Text).toBe("<u>Learn &amp; more</u>")
		more.GuiState = Enum.GuiState.Idle
		t.expect(more.Text).toBe("Learn &amp; more")
		world.gui.SelectedObject = more
		t.expect(more.Text).toBe("<u>Learn &amp; more</u>")
		world.gui.SelectedObject = nil
		t.expect(more.Text).toBe("Learn &amp; more")
		world.stop()
		t.expect(function()
			screen(nil, function(UI)
				return UI.Button({ label = "Go", icon = "close", underline = "always" })
			end)
		end).toThrow("underline belongs to a text button")
		t.expect(function()
			screen(nil, function(UI)
				return UI.Button({ label = "Go", underline = "sometimes" :: any })
			end)
		end).toThrow("underline must be always or hover")
	end)

	t.it("textSize reaches the label beside an icon and the plain label, as a role or a number", function()
		local package = themes.neutralPackage()
		local sheet, stopSheet = sheetOf(package)
		local world = screen(package, function(UI)
			return UI.VStack({
				UI.Button("Browse")({ label = "Browse", icon = "close", textSize = "label", controlSize = "compact" }),
				UI.Button("Plain")({ label = "Plain", textSize = "label" }),
				UI.Button("Sized")({ label = "Sized", icon = "close", textSize = 22 }),
			})
		end)
		local title = world.find("Browse"):FindFirstChild("Title", true)
		t.expect(title:HasTag("facet-type-label")).toBe(true)
		t.expect(resolve(sheet, title, "TextSize")).toBe(14)
		t.expect(resolve(sheet, world.find("Plain"), "TextSize")).toBe(14)
		t.expect(world.find("Sized"):FindFirstChild("Title", true).TextSize).toBe(22)
		world.stop()
		stopSheet()
		t.expect(function()
			screen(nil, function(UI)
				return UI.Button({ label = "Go", textSize = "huge" })
			end)
		end).toThrow("textSize must be a type role")
	end)
end)

t.describe("native xsmall rung", function()
	t.it(
		"xsmall is one ladder step below compact unless the theme authors it, and a partial rung is refused",
		function()
			local world = screen(nil, function(UI)
				return UI.VStack({
					UI.Button("Tiny")({ label = "Go", controlSize = "xsmall" }),
					UI.Chip("TinyChip")({ label = "Tag", selected = Compose.cell(false), controlSize = "xsmall" }),
				})
			end)
			for _, name in { "Tiny", "TinyChip" } do
				local node = world.find(name)
				t.expect(`{name} {node.Size.Y.Offset}`).toBe(`{name} 28`)
				t.expect(node:GetAttribute("controlSize")).toBe("xsmall")
			end
			world.stop()
			local package =
				assert((withMetrics({ controlSizes = { xsmall = { height = 24, paddingX = 8, iconSize = 12 } } })))
			local themed = screen(package, function(UI)
				return UI.Button("Tiny")({ label = "Go", controlSize = "xsmall" })
			end)
			t.expect(themed.find("Tiny").Size.Y.Offset).toBe(24)
			themed.stop()
			t.expect(function()
				screen(nil, function(UI)
					return UI.Button({ label = "Go", controlSize = "tiny" :: any })
				end)
			end).toThrow("xsmall, compact, regular or large")
			local bad, report = withMetrics({ controlSizes = { xsmall = { height = 24 } } })
			t.expect(bad).toBeNil()
			t.expect(string.find(report.errors[1].field, "xsmall", 1, true) ~= nil).toBe(true)
		end
	)
end)

t.describe("native dense pointer rows", function()
	t.it("targetSizes.pointer is refused below 24 and above the minimum", function()
		for _, value in { 20, 48 } do
			local package, report = withMetrics({ targetSizes = { minimum = 44, pointer = value } })
			t.expect(package).toBeNil()
			t.expect(report.errors[1].field).toBe("metrics.targetSizes.pointer")
		end
		t.expect((withMetrics({ targetSizes = { minimum = 44, pointer = 28 } }))).never().toBeNil()
	end)

	local function menu(package: any): (any, () -> { string })
		local world = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				Size = UDim2.fromOffset(800, 600),
				UI.Menu("M")({
					label = "Options",
					items = {
						{ id = "a", label = "Alpha", onSelect = function() end },
						{ id = "b", label = "Beta", onSelect = function() end },
						{ id = "c", label = "Gamma", onSelect = function() end },
					},
				}),
			})
		end, { reducedMotion = true, theme = package })
		world.input.MouseEnabled, world.input.TouchEnabled, world.input.GamepadEnabled = true, false, false
		world.find("Trigger").Activated.fire()
		local function pitch(): { string }
			local panel = world.find("MenuPanel", world.screen.Parent)
			local out = {}
			for _, id in { "a", "b", "c" } do
				local row = world.find(id, panel)
				table.insert(out, `{row.Size.Y.Offset}{if row:HasTag("facet-menu-dense") then "d" else ""}`)
			end
			return out
		end
		return world, pitch
	end

	t.it("floating menu rows take the pointer floor while the input is pointer-only, live both ways", function()
		local package = assert((withMetrics({ targetSizes = { minimum = 44, pointer = 28 } })))
		local world, pitch = menu(package)
		t.expect(table.concat(pitch(), ",")).toBe("28d,28d,28d")
		world.input.GamepadEnabled = true
		t.expect(table.concat(pitch(), ",")).toBe("44,44,44")
		world.input.GamepadEnabled = false
		t.expect(table.concat(pitch(), ",")).toBe("28d,28d,28d")
		world.input.TouchEnabled = true
		t.expect(table.concat(pitch(), ",")).toBe("44,44,44")
		world.stop()
		local neutral, neutralPitch = menu(themes.neutralPackage())
		t.expect(table.concat(neutralPitch(), ",")).toBe("44,44,44")
		neutral.stop()
		local sheet, stop = sheetOf(package)
		local padding = ruleOf(sheet, ".facet-menu-dense::UIPadding"):GetProperties()
		t.expect(padding.PaddingTop.Offset + padding.PaddingBottom.Offset).toBe(0)
		stop()
	end)

	t.it("a Picker menu's rows take the pointer floor, and touch grows them back", function()
		local package = assert((withMetrics({ targetSizes = { minimum = 44, pointer = 28 } })))
		local world = worlds.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				Size = UDim2.fromOffset(800, 600),
				UI.Picker("P")({
					style = "menu",
					selected = Compose.cell("normal"),
					options = {
						{ value = "slow", label = "Slow" },
						{ value = "normal", label = "Normal" },
						{ value = "fast", label = "Fast" },
					},
				}),
			})
		end, { reducedMotion = true, theme = package })
		world.input.MouseEnabled = true
		world.find("Trigger").Activated.fire()
		local panel = world.find("MenuPanel", world.screen.Parent)
		for _, id in { "slow", "normal", "fast" } do
			t.expect(world.find(id, panel).Size.Y.Offset).toBe(28)
		end
		world.input.TouchEnabled = true
		for _, id in { "slow", "normal", "fast" } do
			t.expect(world.find(id, panel).Size.Y.Offset).toBe(44)
		end
		world.stop()
	end)
end)

t.describe("native plain Toggle", function()
	t.it("a plain compact checkbox paints no wash, labels at its role and still toggles", function()
		local package = themes.neutralPackage()
		local sheet, stopSheet = sheetOf(package)
		local value = Compose.cell(false)
		local world = screen(package, function(UI)
			return UI.Toggle("Box")({
				label = "Reduced motion",
				presentation = "checkbox",
				appearance = "plain",
				controlSize = "compact",
				textSize = "label",
				value = value,
			})
		end)
		local row = world.find("Box")
		t.expect(row:HasTag("facet-toggle-plain")).toBe(true)
		t.expect(row.Size.Y.Offset).toBe(36)
		t.expect(resolve(sheet, row, "TextSize")).toBe(14)
		row.Activated.fire()
		t.expect(value:peek()).toBe(true)
		t.expect(row:HasTag("facet-selected")).toBe(false)
		t.expect(row:FindFirstChild("Indicator", true):HasTag("facet-toggle-on")).toBe(true)
		world.stop()
		stopSheet()
		t.expect(function()
			screen(nil, function(UI)
				return UI.Toggle({
					label = "B",
					presentation = "button",
					appearance = "plain",
					value = Compose.cell(false),
				})
			end)
		end).toThrow("cannot be plain")
	end)
end)

t.describe("native outline DisclosureGroup", function()
	t.it("leads its header with the title, and a trailing chevron sits at the far edge", function()
		local world = screen(nil, function(UI, Host)
			return Host.Frame({
				UI.DisclosureGroup("Lead")({
					label = "Inputs",
					expanded = Compose.cell(false),
					content = function()
						return Host.TextLabel({ Text = "Button" })
					end,
				}),
				UI.DisclosureGroup("Trail")({
					label = "Inputs",
					chevronPosition = "trailing",
					expanded = Compose.cell(false),
					content = function()
						return Host.TextLabel({ Text = "Button" })
					end,
				}),
			})
		end)
		local E = Enum
		for _, name in { "Lead", "Trail" } do
			local content = world.find(name):FindFirstChild("Content", true)
			t.expect(content:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
				.toBe(E.HorizontalAlignment.Left)
		end
		local title = world.find("Trail"):FindFirstChild("Title", true)
		t.expect(title:FindFirstChildWhichIsA("UIFlexItem") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("keeps the gap above the body inside the clipped reveal, so a collapse ends without a step", function()
		local world = screen(nil, function(UI, Host)
			return UI.DisclosureGroup("G")({
				label = "Inputs",
				expanded = Compose.cell(true),
				content = function()
					return Host.TextLabel({ Name = "Row", Text = "Button" })
				end,
			})
		end)
		local group = world.find("G")
		t.expect(group:FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(0)
		local reveal = world.find("Reveal")
		t.expect(reveal.ClipsDescendants).toBe(true)
		t.expect(world.find("RevealFade"):FindFirstChildWhichIsA("UIPadding").PaddingTop.Offset).toBe(8)
		t.expect(world.find("RevealFade"):FindFirstChildWhichIsA("UIPadding").PaddingBottom.Offset).toBe(8)
		world.stop()
	end)

	t.it("an outline group has no expanded wash, a chosen role and an indented body", function()
		local package = themes.neutralPackage()
		local sheet, stopSheet = sheetOf(package)
		local world = screen(package, function(UI, Host)
			return UI.DisclosureGroup("G")({
				label = "Inputs",
				appearance = "outline",
				textSize = "label",
				indent = "m",
				expanded = Compose.cell(true),
				content = function()
					return Host.TextLabel({ Name = "Row", Text = "Button" })
				end,
			})
		end)
		local header = world.find("Header")
		t.expect(header:HasTag("facet-selected")).toBe(false)
		t.expect(resolve(sheet, header, "BackgroundTransparency")).toBe(1)
		t.expect(world.find("G"):HasTag("facet-disclosure-outline")).toBe(true)
		t.expect(resolve(sheet, header:FindFirstChild("Title", true), "TextSize")).toBe(14)
		local inset = world.find("RevealFade"):FindFirstChildWhichIsA("UIPadding")
		t.expect(inset.PaddingLeft.Offset).toBe(16)
		t.expect(inset.PaddingTop.Offset).toBe(8)
		t.expect(world.find("G"):FindFirstChildWhichIsA("UIListLayout").Padding.Offset).toBe(0)
		world.stop()
		stopSheet()
		t.expect(function()
			screen(nil, function(UI)
				return UI.DisclosureGroup({
					label = "X",
					indent = "huge" :: any,
					expanded = Compose.cell(false),
					content = function()
						return nil :: any
					end,
				})
			end)
		end).toThrow("indent must be a spacing step")
	end)
end)

t.describe("native TabView controlSize", function()
	t.it("each tab paints at the rung height while the strip keeps the touch floor", function()
		local world = screen(nil, function(UI, Host)
			return UI.TabView("Pages")({
				placement = "topBar",
				controlSize = "compact",
				selection = Compose.cell("a"),
				tabs = {
					{
						id = "a",
						label = "Alpha",
						content = function()
							return Host.Frame({ Name = "PA" })
						end,
					},
					{
						id = "b",
						label = "Beta",
						content = function()
							return Host.Frame({ Name = "PB" })
						end,
					},
				},
			})
		end)
		for _, id in { "a", "b" } do
			local tab = world.find(id)
			t.expect(`{id} {tab.Size.Y.Offset}`).toBe(`{id} 36`)
			t.expect(tab:GetAttribute("controlSize")).toBe("compact")
		end
		t.expect(world.find("Tabs").Size.Y.Offset).toBe(44)
		world.stop()
	end)
end)

t.describe("native Sheet adaptive placement", function()
	local function mount(placement: string, width: number, touch: boolean): any
		local w = overlay.new(function(UI, Host)
			return UI.Sheet("Sheet")({
				isPresented = Compose.cell(true),
				detent = Compose.cell("medium"),
				placement = placement :: any,
				title = "Inspector",
				content = function()
					return Host.Frame({ Name = "Copy" })
				end,
			})
		end, { reducedMotion = true })
		w.input.MouseEnabled, w.input.TouchEnabled = true, touch
		w.find("Modal").AbsoluteSize = Vector2.new(width, 800)
		w.advance(1 / 300, 2)
		return w
	end

	t.it("a roomy pointer screen docks the sheet at the side edge; touch and compact keep the bottom", function()
		local desktop = mount("adaptive", 1200, false)
		local panel = desktop.find("SheetPanel")
		t.expect(panel:GetAttribute("FacetPlacement")).toBe("side")
		t.expect(panel.AnchorPoint).toBe(desktop.Vector2.new(1, 1))
		t.expect(panel.Position.X.Scale).toBe(1)
		desktop.input.TouchEnabled = true
		t.expect(panel:GetAttribute("FacetPlacement")).toBe("bottom")
		t.expect(panel.AnchorPoint).toBe(desktop.Vector2.new(0.5, 1))
		desktop.stop()
		local phone = mount("adaptive", 390, false)
		t.expect(phone.find("SheetPanel"):GetAttribute("FacetPlacement")).toBe("bottom")
		phone.stop()
		local automatic = mount("automatic", 1200, false)
		t.expect(automatic.find("SheetPanel"):GetAttribute("FacetPlacement")).toBe("bottom")
		automatic.stop()
	end)
end)

t.describe("native start-aligned Picker menu", function()
	local OPTIONS = {
		{ value = "slow", label = "Slow" },
		{ value = "normal", label = "Normal" },
		{ value = "fast", label = "Fast" },
	}

	t.it("a start-aligned title sits on one line beside its value, and hug sizing hugs the pair", function()
		local world = screen(nil, function(UI)
			return UI.Picker("P")({
				label = "Motion",
				style = "menu",
				valueAlignment = "start",
				sizing = "hug",
				controlSize = "compact",
				options = OPTIONS,
				selected = Compose.cell("normal"),
			})
		end)
		local row = world.find("P")
		local layout = row:FindFirstChildWhichIsA("UIListLayout")
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Horizontal)
		t.expect(layout.Wraps).toBe(true)
		t.expect(layout.VerticalAlignment).toBe(Enum.VerticalAlignment.Center)
		t.expect(row.AutomaticSize).toBe(Enum.AutomaticSize.XY)
		t.expect(row.Size.X.Scale).toBe(0)
		local label = world.find("Label")
		t.expect(label.AutomaticSize).toBe(Enum.AutomaticSize.XY)
		t.expect(label.LayoutOrder < world.find("Value").LayoutOrder).toBe(true)
		world.stop()
	end)

	t.it("under touch the one-line trigger hugs its value, and end keeps the title above the trigger", function()
		local world = screen(nil, function(UI)
			return UI.VStack({
				UI.Picker("Start")({
					label = "Motion",
					style = "menu",
					valueAlignment = "start",
					options = OPTIONS,
					selected = Compose.cell("normal"),
				}),
				UI.Picker("End")({
					label = "Motion",
					style = "menu",
					options = OPTIONS,
					selected = Compose.cell("fast"),
				}),
			})
		end)
		world.input.TouchEnabled, world.input.PreferredInput = true, Enum.PreferredInput.Touch
		local start = world.find("Start")
		local trigger = world.find("Trigger", start)
		t.expect(trigger.AutomaticSize == Enum.AutomaticSize.XY or trigger.AutomaticSize == Enum.AutomaticSize.X)
			.toBe(true)
		t.expect(start.Size.X.Scale).toBe(1)
		local stacked = world.find("End"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(stacked.FillDirection).toBe(Enum.FillDirection.Vertical)
		world.stop()
		t.expect(function()
			screen(nil, function(UI)
				return UI.Picker({
					label = "M",
					style = "menu",
					valueAlignment = "middle" :: any,
					options = OPTIONS,
					selected = Compose.cell("slow"),
				})
			end)
		end).toThrow("valueAlignment must be start or end")
	end)
end)

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
	local target = engine.new("ScreenGui")
	local stop, node = runtime.mount(function()
		local built = require("../examples/gallery/scenarios/" .. name).build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return built.screen()
	end, target)
	return {
		node = node,
		stop = stop,
		find = function(name: string, root: any?): any
			return overlay.find(root or node, name)
		end,
	}
end

t.describe("native gallery foundation options", function()
	t.it(
		"the gallery shows the xsmall rung, the inverse and underlined links, the plain checkbox and the outline",
		function()
			local actions = scenario("action_controls")
			t.expect(actions.find("RungXsmall").Size.Y.Offset).toBe(28)
			t.expect(actions.find("LookInverse"):HasTag("facet-appearance-inverse")).toBe(true)
			local link = actions.find("LookLink")
			t.expect(link.RichText).toBe(true)
			link.GuiState = Enum.GuiState.Hover
			t.expect(link.Text).toBe("<u>link</u>")
			actions.stop()
			local choices = scenario("selection_controls")
			local plain = choices.find("PlainCheckbox")
			t.expect(plain:HasTag("facet-toggle-plain")).toBe(true)
			t.expect(plain.Size.Y.Offset).toBe(36)
			choices.stop()
			local basics = scenario("adaptive_controls")
			local edge = basics.find("PaneEdge")
			t.expect(edge:HasTag("facet-divider") and edge:HasTag("facet-divider-strong")).toBe(true)
			local outline = basics.find("Outline")
			t.expect(outline:HasTag("facet-disclosure-outline")).toBe(true)
			t.expect(basics.find("Header", outline):HasTag("facet-selected")).toBe(false)
			t.expect(basics.find("OutlineButton", outline) ~= nil).toBe(true)
			basics.stop()
		end
	)
end)
