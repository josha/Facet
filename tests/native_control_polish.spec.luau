--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engines = require("./lib/native_engine")
local Vector2 = require("@lune/roblox").Vector2
local Compose = Facet.Compose
local themes = Facet.themes
local expect = t.expect

local THREE = {
	{ value = "easy", label = "Easy" },
	{ value = "normal", label = "Normal" },
	{ value = "hard", label = "Hard" },
}

local SHIPPED: { any } = {
	require("../examples/themes/classic_desktop"),
	require("../examples/themes/compact_pointer"),
	require("../examples/themes/fantasy_ornate"),
	require("../examples/themes/fantasy_parchment"),
	require("../examples/themes/glossy_mobile"),
	require("../examples/themes/glossy_touch"),
	require("../examples/themes/pixel_quest"),
	require("../examples/themes/scifi_hud"),
}

local function find(root: any, name: string): any
	if root == nil then
		return nil
	end
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

local function world(build: (any, any, any) -> any, options: { [string]: any }?): any
	local o: { [string]: any } = options or {}
	local engine: any = engines.new({
		measureText = function(node: any): any
			local text = node.Text or ""
			return Vector2.new(#text * 11, if #text > 0 then 20 else 0)
		end,
	})
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local config: { [string]: any } = {
		types = engine.types,
		services = { GuiService = gui, UserInputService = input },
		theme = o.theme,
		controlSize = o.controlSize,
	}
	local UI: any = Facet.controls(runtime, config :: any)
	local stop, screen = runtime.mount(function()
		return runtime.constructors.ScreenGui({ build(UI, runtime.constructors, engine) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		gui = gui,
		runtime = runtime,
		screen = screen,
		UI = UI,
		V2 = engine.types.Vector2,
		E = engine.types.Enum,
		step = function(count: number?)
			for _ = 1, count or 1 do
				engine.heartbeat.fire(1 / 60)
			end
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function width(node: any): number
	if node:IsA("TextLabel") or node:IsA("TextButton") then
		return math.max(node.Size.X.Offset, #node.Text * 11)
	end
	local widest = node.Size.X.Offset
	for _, child in node:GetChildren() do
		if child:IsA("GuiObject") and child.Visible ~= false then
			widest = math.max(widest, width(child))
		end
	end
	return widest
end

local function placed(row: any): { [any]: { x: number, w: number } }
	local layout = row:FindFirstChildWhichIsA("UIListLayout")
	assert(layout, `{row.Name} places its parts with a list layout`)
	assert(layout.FillDirection.Name == "Horizontal", `{row.Name} is a horizontal row`)
	local parts = {}
	for index, child in row:GetChildren() do
		if child:IsA("GuiObject") and child.Visible ~= false then
			table.insert(parts, { node = child, order = child.LayoutOrder, index = index })
		end
	end
	table.sort(parts, function(a, b)
		return if a.order == b.order then a.index < b.index else a.order < b.order
	end)
	local result, x = {}, 0
	for _, part in parts do
		local w = width(part.node)
		result[part.node] = { x = x, w = w }
		x += w + layout.Padding.Offset
	end
	return result
end

local function clear(case: string, button: any, markName: string, edge: string)
	expect(`{case}: row {tostring(button ~= nil)}`).toBe(`{case}: row true`)
	local row = button:FindFirstChild("Content")
	expect(`{case}: content {tostring(row ~= nil)}`).toBe(`{case}: content true`)
	local mark = row:FindFirstChild(markName)
	local label = row:FindFirstChild("Captions") or row:FindFirstChild("Title")
	expect(`{case}: mark in row {tostring(mark ~= nil)}`).toBe(`{case}: mark in row true`)
	expect(`{case}: label in row {tostring(label ~= nil)}`).toBe(`{case}: label in row true`)
	local at = placed(row)
	local m, l = at[mark], at[label]
	expect(m.w).toBeGreaterThan(0)
	if edge == "leading" then
		expect(`{case}: {tostring(l.x >= m.x + m.w)}`).toBe(`{case}: true`)
	else
		expect(`{case}: {tostring(m.x >= l.x + l.w)}`).toBe(`{case}: true`)
	end
end

local function sheetFor(w: any, package: any, options: { [string]: any }?): any
	local settings: { [string]: any } = { types = w.engine.types, preferredTransparency = 1, reducedMotion = false }
	for key, value in (options or {}) :: { [string]: any } do
		settings[key] = value
	end
	local _, sheet = w.runtime.mount(function()
		return themes.createStyleSheet(w.runtime, package, settings :: any)
	end, w.engine.new("Folder"))
	return sheet
end

local function rule(sheet: any, selector: string): any
	local found
	for _, node in sheet:GetChildren() do
		if node.Selector == selector then
			found = node
		end
	end
	return found
end

t.describe("native option rows keep the mark in its own slot", function()
	t.it("the label starts after the leading radio mark and ends before a trailing one", function()
		for _, edge in { "leading", "trailing" } do
			local w = world(function(UI)
				return UI.Picker "P" {
					style = "radioGroup",
					indicatorPosition = edge,
					selected = Compose.cell("normal"),
					options = THREE,
				}
			end)
			for _, key in { "easy", "normal", "hard" } do
				clear(`radio {edge} {key}`, find(w.screen, key), "Indicator", edge)
			end
			local dot = find(find(find(w.screen, "normal"), "Indicator"), "Dot")
			expect(dot.Visible).toBe(true)
			expect(find(find(find(w.screen, "easy"), "Indicator"), "Dot").Visible).toBe(false)
			w.stop()
		end
	end)

	t.it("a radio row without a description keeps one line centered at the row height", function()
		local options = table.clone(THREE)
		options[2] = { value = "normal", label = "Normal", description = "Most players" }
		local w = world(function(UI)
			return UI.Picker "P" {
				style = "radioGroup",
				selected = Compose.cell("normal"),
				options = options,
			}
		end)
		local plain, described = find(w.screen, "easy"), find(w.screen, "normal")
		expect(plain:HasTag("facet-button-described")).toBe(false)
		expect(find(plain, "Content").AnchorPoint).toBe(w.V2.new(0, 0.5))
		expect(find(plain, "Content").Position.Y.Scale).toBe(0.5)
		expect(described:HasTag("facet-button-described")).toBe(true)
		expect(find(described, "Content").AnchorPoint).toBe(w.V2.new(0, 0))
		w.stop()
	end)

	t.it("the radio group in a presented popover keeps the same slot", function()
		local w = world(function(UI)
			return UI.Popover "Status" {
				isPresented = Compose.cell(true),
				onPresentedChange = function() end,
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return UI.Picker "Presence" {
						style = "radioGroup",
						selected = Compose.cell("away"),
						options = {
							{ value = "online", label = "Online" },
							{ value = "away", label = "Away" },
							{ value = "busy", label = "Busy" },
						},
					}
				end,
			}
		end)
		for _, key in { "online", "away", "busy" } do
			clear(`popover {key}`, find(w.screen, key), "Indicator", "leading")
		end
		w.stop()
	end)

	t.it("an inline list and a menu keep the check after the label", function()
		local inline = world(function(UI)
			return UI.Picker "P" {
				style = "inline",
				indicator = "none",
				selected = Compose.cell("normal"),
				options = THREE,
			}
		end)
		clear("inline", find(inline.screen, "normal"), "TrailingIcon", "trailing")
		inline.stop()
		local menu = world(function(UI)
			return UI.Picker "P" { style = "menu", selected = Compose.cell("normal"), options = THREE }
		end)
		find(menu.screen, "Trigger").Activated.fire()
		local row
		for _, node in menu.screen:GetDescendants() do
			if node.Name == "normal" and node:HasTag("facet-menu-item") then
				row = node
			end
		end
		clear("menu", row, "TrailingIcon", "trailing")
		menu.stop()
	end)
end)

t.describe("native segmented picker track", function()
	t.it("the selected segment sits inside the track with an even inset in every theme and control size", function()
		local packages: { any } = { themes.neutralPackage() }
		for _, module in SHIPPED do
			table.insert(packages, (module.build(themes)))
		end
		local neutralSizes = themes.neutralPackage().metrics.controlSizes
		for _, package in packages do
			local id = package.identity.id
			for _, size in { "compact", "regular", "large" } do
				local w = world(function(UI)
					return UI.Picker "P" {
						style = "segmented",
						controlSize = size,
						selected = Compose.cell("normal"),
						options = THREE,
					}
				end, { theme = package })
				local sheet = sheetFor(w, package)
				local padding = rule(sheet, ".facet-segmented::UIPadding"):GetProperties()
				local inset = padding.PaddingTop.Offset
				for _, side in { "PaddingLeft", "PaddingRight", "PaddingBottom" } do
					expect(`{id} {side}: {padding[side].Offset}`).toBe(`{id} {side}: {inset}`)
				end
				expect(inset >= 3 and inset <= 4).toBe(true)
				local track = rule(sheet, ".facet-segmented::UICorner"):GetProperties().CornerRadius.Offset
				local pill = rule(sheet, ".facet-segment::UICorner")
				expect(`{id}: segment corner {tostring(pill ~= nil)}`).toBe(`{id}: segment corner true`)
				expect(pill:GetProperties().CornerRadius.Offset).toBe(math.max(0, track - inset))
				local height = ((package.metrics.controlSizes or {})[size] or neutralSizes[size]).height
				local picker = find(w.screen, "P")
				expect(`{id} {size}: track {picker.Size.Y.Scale} {picker.Size.Y.Offset}`).toBe(
					`{id} {size}: track 0 {height}`
				)
				expect(picker.AutomaticSize.Name == "Y" or picker.AutomaticSize.Name == "XY").toBe(false)
				local segment = find(picker, "normal")
				expect(segment:HasTag("facet-segment-current")).toBe(true)
				expect(`{id} {size}: segment {segment.Size.Y.Scale} {segment.Size.Y.Offset}`).toBe(
					`{id} {size}: segment 1 0`
				)
				expect(segment.AutomaticSize.Name == "Y" or segment.AutomaticSize.Name == "XY").toBe(false)
				local limit = segment:FindFirstChildWhichIsA("UISizeConstraint")
				local inner = height - 2 * inset
				expect(limit.MinSize.Y <= inner).toBe(true)
				local top, bottom = inset, inset + inner
				expect(top >= inset and bottom <= height - inset).toBe(true)
				w.stop()
			end
		end
	end)

	t.it("a caller's fixed 44 point track keeps the segments inside it", function()
		local w = world(function(UI, _, engine)
			return UI.Picker "P" {
				style = "segmented",
				selected = Compose.cell("easy"),
				options = THREE,
				Size = engine.types.UDim2.new(1, 0, 0, 44),
				AutomaticSize = engine.types.Enum.AutomaticSize.None,
			}
		end)
		local picker = find(w.screen, "P")
		expect(picker.Size.Y.Offset).toBe(44)
		for _, key in { "easy", "normal", "hard" } do
			local segment = find(picker, key)
			expect(segment.Size.Y.Scale).toBe(1)
			expect(segment.Size.Y.Offset).toBe(0)
		end
		w.stop()
	end)
end)

t.describe("native NavBar fit", function()
	local function bar(title: string): (any, any)
		local w = world(function(UI, Host, engine)
			return UI.NavBar "Header" {
				title = title,
				titleSize = "heading",
				trailing = UI.HStack "HeaderActions" {
					gap = "s",
					align = "center",
					UI.Button "MenuButton" { icon = "more", name = "Menu", shape = "circle" },
					Host.Frame "Profile" { Size = engine.types.UDim2.fromOffset(36, 36) },
				},
			}
		end)
		local header = find(w.screen, "Header")
		header.AbsoluteSize = w.V2.new(358, 44)
		find(header, "Trailing").AbsoluteSize = w.V2.new(88, 44)
		find(header, "Primary").AbsoluteSize = w.V2.new(262, 44)
		find(header, "Center").AbsoluteSize = w.V2.new(262, 28)
		return w, header
	end

	t.it("keeps a short title and the trailing actions on one row at 390 points wide", function()
		local w, header = bar("Discover")
		expect(header:FindFirstChildWhichIsA("UIListLayout").FillDirection.Name).toBe("Horizontal")
		w.stop()
	end)

	t.it("stacks only when the title does not fit beside the actions", function()
		local w, header = bar("Every monitor in the whole office")
		expect(header:FindFirstChildWhichIsA("UIListLayout").FillDirection.Name).toBe("Vertical")
		w.stop()
	end)
end)

t.describe("native selection paint", function()
	t.it("applies the selected state during the activation that causes it", function()
		local w = world(function(UI)
			return UI.VStack "Column" {
				UI.Picker "Segments" { style = "segmented", selected = Compose.cell("easy"), options = THREE },
				UI.Toggle "Hat" { label = "Hat", value = Compose.cell(false) },
				UI.TabView "Tabs" {
					selection = Compose.cell("one"),
					indicator = "pill",
					placement = "topBar",
					tabs = {
						{
							id = "one",
							label = "One",
							content = function()
								return UI.Label "OneBody" { text = "One" }
							end,
						},
						{
							id = "two",
							label = "Two",
							content = function()
								return UI.Label "TwoBody" { text = "Two" }
							end,
						},
					},
				},
			}
		end)
		local frames = 0
		local watch = w.engine.heartbeat:Connect(function()
			frames += 1
		end)
		local segment = find(find(w.screen, "Segments"), "hard")
		segment.Activated.fire()
		expect(segment:HasTag("facet-segment-current")).toBe(true)
		expect(segment:HasTag("facet-selected")).toBe(true)
		local toggle = find(w.screen, "Hat")
		toggle.Activated.fire()
		expect(toggle:HasTag("facet-selected")).toBe(true)
		expect(find(toggle, "Indicator"):HasTag("facet-toggle-on")).toBe(true)
		local tab = find(find(w.screen, "Tabs"), "two")
		tab.Activated.fire()
		expect(tab:HasTag("facet-tab-current")).toBe(true)
		expect(tab:HasTag("facet-selected")).toBe(true)
		expect(frames).toBe(0)
		watch:Disconnect()
		w.stop()
	end)

	t.it("a pressed control keeps its highlight and a pressed current option keeps its selected paint", function()
		local w = world(function(UI)
			return UI.VStack "Empty" {}
		end)
		local sheet = sheetFor(w, themes.neutralPackage())
		local seconds = themes.neutralPackage().metrics.motion.normal
		for _, node in sheet:GetChildren() do
			local family = string.match(node.Selector, "^(%.[%w%-]+):Hover$")
			if family then
				local press = rule(sheet, family .. ":Press")
				expect(`{family}:Press {tostring(press ~= nil)}`).toBe(`{family}:Press true`)
				local hover = node:GetProperties()
				local pressed = press:GetProperties()
				for _, property in { "BackgroundColor3", "BackgroundTransparency" } do
					if hover[property] == nil then
						continue
					end
					expect(`{family} {property} {tostring(pressed[property] ~= nil)}`).toBe(`{family} {property} true`)
				end
				for property, value in pressed do
					if typeof(value) == "Color3" or string.find(property, "Transparency$") then
						expect(press:GetPropertyTransitions()[property].Time).toBe(seconds)
					end
				end
			end
		end
		for family, current in
			{
				[".facet-segment"] = ".facet-segment-current",
				[".facet-choice"] = ".facet-choice-current",
				[".facet-tab-item"] = ".facet-tab-filled",
			} :: { [string]: string }
		do
			local press = rule(sheet, family .. ":Press")
			expect(rule(sheet, current).Priority > press.Priority).toBe(true)
			expect(rule(sheet, current).Priority > rule(sheet, family .. ":Hover").Priority).toBe(true)
		end
		for _, current in { ".facet-segment-current", ".facet-choice-current" } do
			local base = rule(sheet, current):GetProperties()
			local pressed = rule(sheet, current .. ":Press")
			expect(`{current}:Press {tostring(pressed ~= nil)}`).toBe(`{current}:Press true`)
			expect(pressed:GetProperties().BackgroundColor3).toBe(base.BackgroundColor3)
		end
		w.stop()
	end)
end)

t.describe("native navigation stack paint", function()
	local function stackWorld(): (any, any, any)
		local path = Compose.cell({})
		local w = world(function(UI, Host, engine)
			return Host.Frame "Card" {
				BackgroundColor3 = engine.types.Color3.new(0.2, 0.3, 0.4),
				BackgroundTransparency = 0,
				Host.Frame "Clear" {
					BackgroundTransparency = 1,
					UI.NavigationStack "Stack" {
						path = path,
						root = {
							title = "Explorer",
							content = function()
								return UI.Button "RootAction" { label = "Motion & turning" }
							end,
						},
						destinations = {
							motion = {
								title = "Motion & turning",
								content = function()
									return UI.Button "DetailAction" { label = "Turn speed" }
								end,
							},
						},
					},
				},
			}
		end)
		return w, path, w.engine.types.Color3.new(0.2, 0.3, 0.4)
	end

	local function opaque(w: any, pages: { any }, colour: any)
		for _, page in pages do
			if page.Visible then
				expect(`{page.Name} {page.BackgroundTransparency}`).toBe(`{page.Name} 0`)
				expect(page.BackgroundColor3).toBe(colour)
			end
			for _, node in page:GetDescendants() do
				expect(node:IsA("CanvasGroup")).toBe(false)
			end
			expect(page:IsA("CanvasGroup")).toBe(false)
		end
	end

	t.it("both pages stay opaque while a push slides the new page over a shaded one", function()
		local w, path, colour = stackWorld()
		local stack = find(w.screen, "Stack")
		local root = find(stack, "@root")
		path:set({ { id = "motion" } })
		local detail = find(stack, "motion")
		local sampled = 0
		for _ = 1, 30 do
			w.step()
			if root.Visible and detail.Position.X.Scale > 0 then
				sampled += 1
				opaque(w, { root, detail }, colour)
				local shade = find(root, "Dim")
				expect(shade.BackgroundColor3).toBe(w.engine.types.Color3.new(0, 0, 0))
				expect(shade.BackgroundTransparency >= 0.9 and shade.BackgroundTransparency < 1).toBe(true)
			end
		end
		expect(sampled).toBeGreaterThan(5)
		w.step(60)
		expect(detail.Position.X.Scale).toBe(0)
		expect(root.Visible).toBe(false)
		expect(detail.BackgroundTransparency).toBe(1)
		w.stop()
	end)

	t.it("both pages stay opaque while a pop slides the page away", function()
		local w, path, colour = stackWorld()
		local stack = find(w.screen, "Stack")
		local root = find(stack, "@root")
		path:set({ { id = "motion" } })
		w.step(60)
		local detail = find(stack, "motion")
		path:set({})
		opaque(w, { root, detail }, colour)
		local sampled = 0
		for _ = 1, 30 do
			w.step()
			if not detail.isDestroyed() and detail.Position.X.Scale < 1 and root.Visible then
				sampled += 1
				opaque(w, { root, detail }, colour)
			end
		end
		expect(sampled).toBeGreaterThan(5)
		w.step(60)
		expect(detail.isDestroyed()).toBe(true)
		expect(root.BackgroundTransparency).toBe(1)
		w.stop()
	end)
end)
