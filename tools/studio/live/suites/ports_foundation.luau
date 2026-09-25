--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	plan: string,
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, plan = plan, setup = setup, steps = steps })
end

local INK = Color3.new(0.97, 0.97, 0.98)
local ON_INK = Color3.new(0.07, 0.07, 0.08)

local function rgb(color: Color3): { r: number, g: number, b: number }
	return { r = color.R, g = color.G, b = color.B }
end

local function toColor(value: any): Color3
	if typeof(value) == "Color3" then
		return value
	end
	return Color3.new(value.r, value.g, value.b)
end

local function sameColor(a: any, b: any): boolean
	return typeof(a) == "Color3"
		and typeof(b) == "Color3"
		and math.abs(a.R - b.R) <= 2.5 / 255
		and math.abs(a.G - b.G) <= 2.5 / 255
		and math.abs(a.B - b.B) <= 2.5 / 255
end

local function channel(value: number): number
	return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
end

local function luminance(color: Color3): number
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function contrast(a: Color3, b: Color3): number
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

local function distance(a: Color3, b: Color3): number
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B)
end

local function styled(node: any, property: string): any
	local ok, value = pcall(function()
		return node:GetStyled(property)
	end)
	if ok and value ~= nil then
		return value
	end
	return node[property]
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function point(node: any): { number }
	local inset = GuiService:GetGuiInset()
	local at, size = node.AbsolutePosition, node.AbsoluteSize
	return { math.floor(at.X + size.X / 2 + inset.X + 0.5), math.floor(at.Y + size.Y / 2 + inset.Y + 0.5) }
end

local function define(t: any, name: string, fields: { [string]: any }): any
	local themes = t.Facet.themes
	local spec: { [string]: any } = {
		base = themes.neutralPackage(),
		identity = { id = string.lower(name), displayName = name, schemaVersion = themes.SCHEMA, version = "1.0.0" },
	}
	for key, value in fields do
		spec[key] = value
	end
	local package, report = themes.define(spec)
	assert(package ~= nil, `{name} theme: {report and report.errors[1] and report.errors[1].message}`)
	return package
end

local function authored(t: any, name: string, extra: { [string]: any }, palette: string?): any
	local neutral = t.Facet.themes.neutralPackage()
	local chosen = neutral.style.themes[1]
	for _, entry in neutral.style.themes do
		if palette and entry.name == palette then
			chosen = entry
		end
	end
	local merged = table.clone(chosen.extra)
	for key, value in extra do
		merged[key] = value
	end
	return define(t, name, {
		style = { defaultTheme = name, themes = { { name = name, colors = chosen.colors, extra = merged } } },
	})
end

local function paletteNamed(package: any, name: string): any
	for _, entry in package.style.themes do
		if entry.name == name then
			return entry
		end
	end
	return package.style.themes[1]
end

local function rulesOf(stage: Instance): { [string]: any }
	local found = {}
	local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	local sheet = gui and gui:FindFirstChildWhichIsA("StyleSheet")
	for _, node in if sheet then sheet:GetDescendants() else {} do
		if node:IsA("StyleRule") then
			found[(node :: any).Selector] = node
		end
	end
	return found
end

local function desktop(t: any)
	local simulator = game:GetService("StudioDeviceSimulatorService") :: any
	pcall(function()
		simulator:StopSimulationAsync()
	end)
	t.settle(30)
end

local function inputFacts(): { [string]: any }
	return {
		touch = UserInputService.TouchEnabled,
		gamepad = UserInputService.GamepadEnabled,
		mouse = UserInputService.MouseEnabled,
		preferred = tostring(UserInputService.PreferredInput),
	}
end

local MENU_ROWS = { "a", "b", "c" }
local PICKER_ROWS = { "slow", "normal", "fast" }

local function rowRects(t: any, panel: any, ids: { string }): { any }
	local out = {}
	for _, id in ids do
		local row = panel and panel:FindFirstChild(id, true)
		table.insert(out, if row then { id = id, node = row, rect = t.rect(row) } else { id = id })
	end
	return out
end

local function checkRows(t: any, where: string, panel: any, ids: { string }, height: number)
	t.check(`{where} panel is open`, panel ~= nil)
	if not panel then
		return
	end
	t.stable(panel)
	local rows = rowRects(t, panel, ids)
	for index, row in rows do
		if not row.rect then
			t.check(`{where} row {row.id} found`, false)
			continue
		end
		t.near(`{where} row {row.id} is {height} px`, row.rect.h, height, 0.5)
		local following = rows[index + 1]
		if following and following.rect then
			t.check(`{where} rows {row.id} and {following.id} do not overlap`, not overlap(row.rect, following.rect), {
				row.rect.y,
				row.rect.b,
				following.rect.y,
			})
		end
	end
end

interactive(
	"dense-menu-and-picker-rows",
	{
		"post-port26-009",
		"post-port26-010",
		"post-port26-011",
		"post-port26-017",
		"post-port26-020",
	},
	"setup opens the Menu under mouse-only input; step pointer; click the middle of row b; step clicked; step touch; step gamepad; step desktop; click the Picker trigger; step picker; step pickertouch",
	function(t)
		desktop(t)
		local value: { [string]: any } = { chosen = nil }
		local dense = define(t, "Dense", { metrics = { targetSizes = { minimum = 44, pointer = 28 } } })
		local stage = t.mount(function(UI, Host, Compose)
			value.open = Compose.cell(true)
			local function item(id: string, label: string): any
				return {
					id = id,
					label = label,
					onSelect = function()
						value.chosen = id
					end,
				}
			end
			return Host.Frame "Board" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				UI.Menu({
					Name = "Options",
					label = "Options",
					items = { item("a", "Alpha"), item("b", "Beta"), item("c", "Gamma") },
					isPresented = value.open,
					Position = UDim2.fromOffset(120, 80),
				}),
				UI.Picker({
					Name = "Speed",
					style = "menu",
					selected = Compose.cell("normal"),
					options = {
						{ value = "slow", label = "Slow" },
						{ value = "normal", label = "Normal" },
						{ value = "fast", label = "Fast" },
					},
					Position = UDim2.fromOffset(480, 80),
					Size = UDim2.fromOffset(200, 44),
				}),
			}
		end, { theme = dense, size = Vector2.new(800, 600), frames = 20 })
		value.stage = stage
		t.settle(20)
		value.panel = visibleNamed(t, stage, "MenuPanel")
		return value
	end,
	{
		pointer = function(t, value)
			t.note("pointer input", inputFacts())
			t.check(
				"the input is pointer-only",
				not UserInputService.TouchEnabled and not UserInputService.GamepadEnabled,
				inputFacts()
			)
			checkRows(t, "pointer menu", value.panel, MENU_ROWS, 28)
			local row = value.panel and value.panel:FindFirstChild("b", true)
			value.target = if row then point(row) else nil
			t.note("row b click point", value.target)
		end,
		clicked = function(t, value)
			t.check("the click on row b chose b", value.chosen == "b", value.chosen)
			value.open:set(true)
			t.settle(20)
			value.panel = visibleNamed(t, value.stage, "MenuPanel")
		end,
		touch = function(t, value)
			t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
			t.note("touch input", inputFacts())
			t.check("touch is available", UserInputService.TouchEnabled, inputFacts())
			checkRows(t, "touch menu (same panel)", value.panel, MENU_ROWS, 44)
			t.check(
				"the panel stayed open",
				value.panel ~= nil and value.panel.Parent ~= nil and t.visible(value.panel)
			)
		end,
		gamepad = function(t, value)
			t.device({ device = "xbox", input = Enum.PreferredInput.Gamepad })
			t.note("gamepad input", inputFacts())
			t.check("a gamepad is available", UserInputService.GamepadEnabled, inputFacts())
			checkRows(t, "gamepad menu (same panel)", value.panel, MENU_ROWS, 44)
		end,
		desktop = function(t, value)
			desktop(t)
			t.note("desktop input", inputFacts())
			checkRows(t, "back to pointer menu (same panel)", value.panel, MENU_ROWS, 28)
			value.open:set(false)
			t.settle(20)
			local trigger = t.find(value.stage, "Speed")
			trigger = trigger and trigger:FindFirstChild("Trigger", true)
			value.trigger = if trigger then point(trigger) else nil
			t.note("picker trigger point", value.trigger)
		end,
		picker = function(t, value)
			value.pickerPanel = visibleNamed(t, value.stage, "MenuPanel")
			checkRows(t, "pointer picker", value.pickerPanel, PICKER_ROWS, 28)
		end,
		pickertouch = function(t, value)
			t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
			checkRows(t, "touch picker (same panel)", value.pickerPanel, PICKER_ROWS, 44)
		end,
	}
)

local OPTIONS = {
	{ value = "slow", label = "Slow" },
	{ value = "normal", label = "Normal" },
	{ value = "fast", label = "Fast" },
}

local function startPicker(t: any, size: Vector2): any
	return t.mount(function(UI, Host, Compose)
		return Host.Frame "Toolbar" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			UI.HStack "Bar" {
				gap = "s",
				align = "center",
				UI.Picker "Motion" {
					label = "Motion",
					style = "menu",
					valueAlignment = "start",
					sizing = "hug",
					controlSize = "compact",
					options = OPTIONS,
					selected = Compose.cell("normal"),
				},
				UI.Button "Reset" { label = "Reset" },
			},
		}
	end, { size = size, frames = 20 })
end

add("picker-start-inline", { "post-port26-018" }, function(t)
	desktop(t)
	local stage = startPicker(t, Vector2.new(1280, 700))
	local picker = t.find(stage, "Motion")
	local label = picker and picker:FindFirstChild("Label", true)
	local trigger = picker and picker:FindFirstChild("Trigger", true)
	t.check("the picker has a title and a trigger", label ~= nil and trigger ~= nil)
	if not (picker and label and trigger) then
		return
	end
	t.stable(picker)
	local l, g, p = t.rect(label), t.rect(trigger), t.rect(picker)
	t.note("rects", { label = { l.x, l.y, l.w, l.h }, trigger = { g.x, g.y, g.w, g.h }, pair = { p.x, p.y, p.w, p.h } })
	t.near("title and trigger share one midline", l.y + l.h / 2, g.y + g.h / 2, 1)
	t.check("the trigger is right of the title", g.x >= l.r - 0.5, { l.r, g.x })
	t.check("the gap is less than 32 px", g.x - l.r < 32, g.x - l.r)
	t.check("the pair is less than 400 px wide", p.w < 400, p.w)
	t.check("the title fits", t.fits(label), label.TextBounds)
	t.note("preferred text size", tostring(GuiService.PreferredTextSize))
end)

add("picker-touch-row", { "post-port26-019" }, function(t)
	t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
	local stage = startPicker(t, Vector2.new(390, 400))
	local picker = t.find(stage, "Motion")
	local label = picker and picker:FindFirstChild("Label", true)
	local trigger = picker and picker:FindFirstChild("Trigger", true)
	t.check("touch input", UserInputService.TouchEnabled, inputFacts())
	t.check("the picker has a title and a trigger", label ~= nil and trigger ~= nil)
	if not (picker and label and trigger) then
		return
	end
	t.stable(picker)
	local l, g = t.rect(label), t.rect(trigger)
	t.note("rects", { label = { l.x, l.y, l.w, l.h }, trigger = { g.x, g.y, g.w, g.h } })
	t.check("the trigger is wider than 48 px", g.w > 48, g.w)
	t.check(
		"the trigger sits next to the title",
		g.x >= l.r - 0.5 and math.abs((l.y + l.h / 2) - (g.y + g.h / 2)) <= 1,
		{
			l.r,
			g.x,
		}
	)
	local shown = 0
	for _, node in trigger:GetDescendants() do
		if node:IsA("TextLabel") and node.ContentText == "Normal" and t.visible(node) then
			shown += 1
			t.check("the whole value shows", t.fits(node), { node.TextBounds, node.AbsoluteSize })
		end
	end
	if trigger:IsA("TextButton") and trigger.ContentText ~= "" then
		shown += 1
		t.check(
			"the whole value shows",
			t.fits(trigger) and string.find(trigger.ContentText, "Normal", 1, true) ~= nil,
			{
				trigger.ContentText,
				trigger.TextBounds,
				trigger.AbsoluteSize,
			}
		)
	end
	t.check("the value text is drawn", shown > 0)
end)

add("tab-rung", { "post-port26-025" }, function(t)
	desktop(t)
	local stage = t.mount(function(UI, Host, Compose)
		return UI.TabView "Pages" {
			placement = "topBar",
			controlSize = "compact",
			selection = Compose.cell("a"),
			tabs = {
				{
					id = "a",
					label = "Alpha",
					content = function()
						return Host.Frame { Name = "PA", BackgroundTransparency = 1 }
					end,
				},
				{
					id = "b",
					label = "Beta",
					content = function()
						return Host.Frame { Name = "PB", BackgroundTransparency = 1 }
					end,
				},
			},
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	local strip = t.find(stage, "Tabs")
	t.check("the strip exists", strip ~= nil)
	if not strip then
		return
	end
	t.stable(strip)
	local s = t.rect(strip)
	t.near("the strip is 44 px", s.h, 44, 0.5)
	for _, id in { "a", "b" } do
		local tab = strip:FindFirstChild(id, true)
		t.check(`tab {id} found`, tab ~= nil)
		if tab then
			local r = t.rect(tab)
			t.near(`tab {id} is 36 px`, r.h, 36, 0.5)
			t.near(`tab {id} is centred in the strip`, r.y + r.h / 2, s.y + s.h / 2, 1)
		end
	end
	local indicator = visibleNamed(t, stage, "SelectionIndicator")
	local selected = strip:FindFirstChild("a", true)
	t.check("the underline exists", indicator ~= nil)
	if indicator and selected then
		local u, r = t.rect(indicator), t.rect(selected)
		t.note("underline", { u.x, u.y, u.w, u.h })
		t.near("the underline sits at the bottom of the tab", u.b, r.b, 1)
		t.check("the underline is under the chosen tab", u.x >= r.x - 1 and u.r <= r.r + 1, { u.x, u.r, r.x, r.r })
	end
end)

interactive(
	"sheet-adaptive",
	{ "post-port26-024" },
	"setup presents the adaptive Sheet at 1200x800 with the mouse and samples the slide; step phone; step narrow",
	function(t)
		desktop(t)
		local value: { [string]: any } = {}
		local stage = t.mount(function(UI, Host, Compose)
			value.size = Compose.cell(Vector2.new(1200, 800))
			value.presented = Compose.cell(false)
			return UI.Sheet "Sheet" {
				isPresented = value.presented,
				detent = Compose.cell("medium"),
				placement = "adaptive",
				title = "Inspector",
				content = function()
					return Host.Frame { Name = "Copy", BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 120) }
				end,
			}
		end, { size = Vector2.new(1200, 800), frames = 12 })
		value.stage = stage
		value.presented:set(true)
		local samples = {}
		for _ = 1, 40 do
			task.wait()
			local panel = visibleNamed(t, stage, "SheetPanel")
			if panel then
				table.insert(samples, panel.AbsolutePosition.X)
			end
		end
		local panel = visibleNamed(t, stage, "SheetPanel")
		t.check("the sheet is shown", panel ~= nil)
		if not panel then
			return value
		end
		t.stable(panel)
		local p, room = t.rect(panel), t.rect(stage)
		t.note(
			"desktop",
			{ panel = { p.x, p.y, p.w, p.h }, room = { room.x, room.y, room.w, room.h }, input = inputFacts() }
		)
		t.check(
			"placement is side",
			panel:GetAttribute("FacetPlacement") == "side",
			panel:GetAttribute("FacetPlacement")
		)
		t.near("the panel right edge is the room right edge", p.r, room.r, 1)
		t.check("the panel is narrower than the room", p.w < room.w - 100, p.w)
		t.note("slide x samples", samples)
		t.check(
			"it slid in from the right edge",
			#samples > 2 and samples[1] > p.x + 20,
			{ first = samples[1], final = p.x }
		)
		return value
	end,
	{
		phone = function(t, value)
			t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, restore = "xbox" })
			local panel = visibleNamed(t, value.stage, "SheetPanel")
			t.check("the sheet is shown", panel ~= nil)
			if panel then
				t.stable(panel)
				local p, room = t.rect(panel), t.rect(value.stage)
				t.check(
					"touch moves it to the bottom",
					panel:GetAttribute("FacetPlacement") == "bottom",
					panel:GetAttribute("FacetPlacement")
				)
				t.near("the panel bottom is the room bottom", p.b, room.b, 1)
				t.near("the panel is centred", p.x + p.w / 2, room.x + room.w / 2, 1)
			end
		end,
		narrow = function(t, value)
			desktop(t)
			t.cleanup()
			local stage = t.mount(function(UI, Host, Compose)
				return UI.Sheet "Sheet" {
					isPresented = Compose.cell(true),
					detent = Compose.cell("medium"),
					placement = "adaptive",
					title = "Inspector",
					content = function()
						return Host.Frame { Name = "Copy", BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 120) }
					end,
				}
			end, { size = Vector2.new(390, 800), frames = 20 })
			local panel = visibleNamed(t, stage, "SheetPanel")
			t.check("the narrow sheet is shown", panel ~= nil)
			if panel then
				t.stable(panel)
				local p, room = t.rect(panel), t.rect(stage)
				t.check("the input is the mouse", not UserInputService.TouchEnabled, inputFacts())
				t.check(
					"390 px keeps the bottom",
					panel:GetAttribute("FacetPlacement") == "bottom",
					panel:GetAttribute("FacetPlacement")
				)
				t.near("the panel bottom is the room bottom", p.b, room.b, 1)
			end
		end,
	}
)

add("outline-indent", { "post-port26-014" }, function(t)
	desktop(t)
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Board" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			UI.DisclosureGroup "G" {
				label = "Components",
				appearance = "outline",
				textSize = "label",
				indent = "m",
				expanded = Compose.cell(true),
				Size = UDim2.fromOffset(320, 0),
				content = function()
					return Host.TextLabel {
						Name = "Row",
						Text = "Button",
						Size = UDim2.fromOffset(120, 28),
						BackgroundTransparency = 1,
					}
				end,
			},
		}
	end, { size = Vector2.new(600, 400), frames = 30 })
	local group = t.find(stage, "G")
	local row = t.find(stage, "Row")
	local header = t.find(stage, "Header")
	t.check("the group, header and row exist", group ~= nil and row ~= nil and header ~= nil)
	if not (group and row and header) then
		return
	end
	t.stable(row)
	local g, r = t.rect(group), t.rect(row)
	t.note("rects", { group = { g.x, g.y, g.w, g.h }, row = { r.x, r.y, r.w, r.h } })
	t.near("the content is 16 px right of the group edge", r.x - g.x, 16, 0.5)
	t.check("the header has no selected tag", not header:HasTag("facet-selected"), header:GetTags())
	local plate = styled(header, "BackgroundTransparency")
	t.check("the expanded header paints no plate", plate == 1, plate)
	local title = header:FindFirstChild("Title", true)
	t.check("the header title exists", title ~= nil)
	if title then
		local neutral = t.Facet.themes.neutralPackage()
		local expected = neutral.metrics and neutral.metrics.typeRoles and neutral.metrics.typeRoles.label
		local size = styled(title, "TextSize")
		t.note("label role", expected)
		t.near("the title is at the label type size", size, 14, 0.01)
	end
end)

add("selection-marks", { "post-port26-026", "post-port26-027", "post-port26-028", "post-port26-030" }, function(t)
	desktop(t)
	local package = authored(t, "Ink", { selection = rgb(INK), onSelection = rgb(ON_INK) })
	local stage = t.mount(function(UI, Host, Compose)
		return UI.VStack "Board" {
			gap = "s",
			UI.Chip "Pick" { label = "Pick", selected = Compose.cell(true) },
			UI.Toggle "Check" { label = "Check", presentation = "checkbox", value = Compose.cell(true) },
			UI.Toggle "Sound" { label = "Sound", value = Compose.cell(true) },
			UI.Slider "Vol" { value = Compose.cell(0.5), min = 0, max = 1 },
			UI.TabView "Pages" {
				placement = "topBar",
				indicator = "underline",
				selection = Compose.cell("a"),
				Size = UDim2.fromOffset(400, 120),
				tabs = {
					{
						id = "a",
						label = "A",
						content = function()
							return Host.Frame { Name = "PA", BackgroundTransparency = 1 }
						end,
					},
					{
						id = "b",
						label = "B",
						content = function()
							return Host.Frame { Name = "PB", BackgroundTransparency = 1 }
						end,
					},
				},
			},
		}
	end, { theme = package, size = Vector2.new(800, 600), frames = 30 })
	local function paint(where: string, node: any, property: string, want: Color3)
		t.check(`{where} found`, node ~= nil)
		if node then
			local got = styled(node, property)
			t.check(`{where} {property} is the authored ink`, sameColor(got, want), tostring(got))
		end
	end
	local chip = t.find(stage, "Pick")
	paint("chosen Chip plate", chip, "BackgroundColor3", INK)
	paint("chosen Chip text", chip, "TextColor3", ON_INK)
	local check = t.find(stage, "Check")
	local box = check and check:FindFirstChild("Indicator", true)
	paint("checked box", box, "BackgroundColor3", INK)
	local tick = box and box:FindFirstChild("Check")
	t.check("the tick is visible", tick ~= nil and t.visible(tick))
	paint("tick", tick, "ImageColor3", ON_INK)
	local sound = t.find(stage, "Sound")
	local track = sound and sound:FindFirstChild("Indicator", true)
	paint("switch track", track, "BackgroundColor3", INK)
	paint("switch knob", track and track:FindFirstChild("Mark"), "BackgroundColor3", ON_INK)
	local fill = nil
	local vol = t.find(stage, "Vol")
	for _, node in if vol then vol:GetDescendants() else {} do
		if node:HasTag("facet-slider-fill") then
			fill = node
		end
	end
	paint("slider fill", fill, "BackgroundColor3", INK)
	paint("tab underline", visibleNamed(t, stage, "SelectionIndicator"), "BackgroundColor3", INK)
end)

interactive(
	"selection-mark-hover",
	{ "post-port26-029", "post-port26-030" },
	"setup mounts a chosen Chip under an authored selection; move the mouse over the chip; step hovered",
	function(t)
		desktop(t)
		local package = authored(t, "InkHover", { selection = rgb(INK), onSelection = rgb(ON_INK) })
		local value: { [string]: any } = {}
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Board" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				UI.Chip "Pick" { label = "Pick", selected = Compose.cell(true), Position = UDim2.fromOffset(200, 200) },
			}
		end, { theme = package, size = Vector2.new(800, 600), frames = 20 })
		value.chip = t.find(stage, "Pick")
		value.target = if value.chip then point(value.chip) else nil
		t.note("chip point", value.target)
		return value
	end,
	{
		hovered = function(t, value)
			local chip = value.chip
			t.check(
				"the chip is hovered",
				chip and chip.GuiState == Enum.GuiState.Hover,
				chip and tostring(chip.GuiState)
			)
			local got = chip and styled(chip, "BackgroundColor3")
			t.check("the hovered chosen chip keeps the ink", sameColor(got, INK), tostring(got))
		end,
	}
)

interactive(
	"underline-live",
	{ "post-port26-008" },
	"setup mounts hover and always link Buttons; step rest; move the mouse over More; step hovered; move the mouse to 20,500; step left; step selected",
	function(t)
		desktop(t)
		local value: { [string]: any } = {}
		local stage = t.mount(function(UI, Host)
			return Host.Frame "Board" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				UI.Button "More" {
					label = "Learn more",
					appearance = "link",
					underline = "hover",
					Position = UDim2.fromOffset(200, 200),
				},
				UI.Button "Always" {
					label = "Terms",
					appearance = "link",
					underline = "always",
					Position = UDim2.fromOffset(200, 300),
				},
			}
		end, { size = Vector2.new(800, 600), frames = 20 })
		value.more = t.find(stage, "More")
		value.always = t.find(stage, "Always")
		value.target = if value.more then point(value.more) else nil
		t.note("More point", value.target)
		return value
	end,
	{
		rest = function(t, value)
			t.check(
				"hover link has no underline at rest",
				value.more and value.more.Text == "Learn more",
				value.more and value.more.Text
			)
			t.check(
				"always link is underlined at rest",
				value.always and value.always.Text == "<u>Terms</u>" and value.always.RichText,
				value.always and value.always.Text
			)
		end,
		hovered = function(t, value)
			t.check("More is hovered", value.more.GuiState == Enum.GuiState.Hover, tostring(value.more.GuiState))
			t.check("hover underlines the label", value.more.Text == "<u>Learn more</u>", value.more.Text)
		end,
		left = function(t, value)
			t.check("More is idle", value.more.GuiState == Enum.GuiState.Idle, tostring(value.more.GuiState))
			t.check("leaving clears the underline", value.more.Text == "Learn more", value.more.Text)
		end,
		selected = function(t, value)
			GuiService.SelectedObject = value.more
			t.settle(4)
			t.check("More holds the selection", selectedName() == "More", selectedName())
			t.check("selection underlines the label", value.more.Text == "<u>Learn more</u>", value.more.Text)
			GuiService.SelectedObject = nil
			t.settle(4)
			t.check("clearing the selection clears it", value.more.Text == "Learn more", value.more.Text)
		end,
	}
)

interactive(
	"inverse-paint",
	{ "post-port26-036" },
	"setup mounts the inverse Button in Neutral Dark and Light; move the mouse over Dark; step darkhover; mouse down; step darkpress; mouse up and move over Light; step lighthover",
	function(t)
		desktop(t)
		local value: { [string]: any } = {}
		local neutral = t.themes[1].package
		value.palettes = {}
		for _, entry in neutral.style.themes do
			table.insert(value.palettes, entry.name)
		end
		t.note("palettes", value.palettes)
		local dark, light = "Dark", "Light"
		value.colors = { Dark = paletteNamed(neutral, dark).colors, Light = paletteNamed(neutral, light).colors }
		value.buttons = {}
		for index, name in { dark, light } do
			local stage = t.mount(function(UI, Host)
				return Host.Frame "Board" {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					UI.Button "Inv" {
						label = "Invert",
						appearance = "inverse",
						Position = UDim2.fromOffset(100 + (index - 1) * 400, 200),
					},
				}
			end, { palette = name, size = Vector2.new(800, 600), frames = 20 })
			local button = t.find(stage, "Inv")
			value.buttons[name] = button
			local colors = value.colors[name]
			local plate, text = styled(button, "BackgroundColor3"), styled(button, "TextColor3")
			t.check(`{name} plate is contentStrong`, sameColor(plate, toColor(colors.contentStrong)), tostring(plate))
			t.check(`{name} text is surface`, sameColor(text, toColor(colors.surface)), tostring(text))
			t.check(`{name} plate is opaque`, styled(button, "BackgroundTransparency") == 0)
			value[name .. "Rest"] = plate
			value[name .. "Point"] = point(button)
		end
		t.note("points", { value.DarkPoint, value.LightPoint })
		return value
	end,
	(function()
		local function stateCheck(name: string, state: Enum.GuiState, label: string)
			return function(t, value)
				local button = value.buttons[name]
				t.check(`{name} is {label}`, button.GuiState == state, tostring(button.GuiState))
				local plate, text = styled(button, "BackgroundColor3"), styled(button, "TextColor3")
				local rest = value[name .. "Rest"]
				t.note(`{name} {label}`, { plate = tostring(plate), text = tostring(text) })
				t.check(
					`{name} {label} plate moves from rest toward the text colour`,
					distance(plate, text) < distance(rest, text) - 0.02,
					{ state = distance(plate, text), rest = distance(rest, text) }
				)
				t.check(`{name} {label} text stays readable`, contrast(plate, text) >= 4.5, contrast(plate, text))
			end
		end
		return {
			darkhover = stateCheck("Dark", Enum.GuiState.Hover, "hover"),
			darkpress = stateCheck("Dark", Enum.GuiState.Press, "press"),
			lighthover = stateCheck("Light", Enum.GuiState.Hover, "hover"),
			lightpress = stateCheck("Light", Enum.GuiState.Press, "press"),
		}
	end)()
)

add("strong-divider-and-pane", { "post-port26-021", "post-port26-033", "post-port26-035" }, function(t)
	desktop(t)
	local stage = t.mount(function(_, Host)
		local hairline = Host.Frame "Hairline" { Size = UDim2.fromOffset(400, 1), Position = UDim2.fromOffset(20, 40) }
		hairline:AddTag("facet-divider")
		local strong = Host.Frame "Strong" { Size = UDim2.fromOffset(400, 1), Position = UDim2.fromOffset(20, 80) }
		strong:AddTag("facet-divider")
		strong:AddTag("facet-divider-strong")
		local pane = Host.Frame "Pane" { Size = UDim2.fromOffset(240, 160), Position = UDim2.fromOffset(20, 120) }
		pane:AddTag("facet-pane")
		return Host.Frame "Board" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			hairline,
			strong,
			pane,
		}
	end, { size = Vector2.new(800, 600), frames = 20 })
	local hairline, strong, pane = t.find(stage, "Hairline"), t.find(stage, "Strong"), t.find(stage, "Pane")
	t.check("fixtures found", hairline ~= nil and strong ~= nil and pane ~= nil)
	if not (hairline and strong and pane) then
		return
	end
	t.check("the strong divider has its tag", strong:HasTag("facet-divider-strong"), strong:GetTags())
	local a, b = styled(hairline, "BackgroundTransparency"), styled(strong, "BackgroundTransparency")
	t.note("divider transparency", { hairline = a, strong = b })
	t.check("the strong divider is heavier than the hairline", b < a - 0.05, { hairline = a, strong = b })
	t.near("the strong divider is 0.76 transparent", b, 0.76, 0.005)
	local colors = t.themes[1].package.style.themes[1].colors
	local fill = styled(pane, "BackgroundColor3")
	t.check("the pane fill is surfaceStrong", sameColor(fill, toColor(colors.surfaceStrong)), tostring(fill))
	t.check("the pane is opaque", styled(pane, "BackgroundTransparency") == 0, styled(pane, "BackgroundTransparency"))
	local rules = rulesOf(stage)
	local decorated = {}
	for selector in rules do
		if string.find(selector, "facet-pane::", 1, true) then
			table.insert(decorated, selector)
		end
	end
	t.check("no rule gives the pane a corner or a stroke", #decorated == 0, decorated)
	t.check(
		"the pane has no corner or stroke child",
		pane:FindFirstChildWhichIsA("UICorner") == nil and pane:FindFirstChildWhichIsA("UIStroke") == nil
	)
end)

add("dim-disabled-plates", { "post-port26-032" }, function(t)
	desktop(t)
	local package = authored(t, "Dim", { dimDisabledPlates = true })
	local colors = package.style.themes[1].colors
	local looks = {
		{ name = "Standard", props = {} },
		{ name = "Emphasis", props = { appearance = "emphasis" } },
		{ name = "Soft", props = { appearance = "soft" } },
		{ name = "Inverse", props = { appearance = "inverse" } },
		{ name = "Destructive", props = { role = "destructive" } },
	}
	local stage = t.mount(function(UI, Host, Compose)
		local rows = { Name = "Board", gap = "s" }
		for _, look in looks do
			for _, on in { true, false } do
				local props = table.clone(look.props)
				props.Name = look.name .. (if on then "On" else "Off")
				props.label = look.name
				props.enabled = on
				table.insert(rows, UI.Button(props))
			end
		end
		table.insert(rows, UI.Toggle "BoxOn" { label = "Box", presentation = "checkbox", value = Compose.cell(true) })
		table.insert(
			rows,
			UI.Toggle "BoxOff" { label = "Box", presentation = "checkbox", value = Compose.cell(true), enabled = false }
		)
		return UI.VStack(rows)
	end, { theme = package, size = Vector2.new(800, 900), frames = 30 })
	local page = toColor(colors.surface)
	local function compare(where: string, on: any, off: any)
		t.check(`{where} found`, on ~= nil and off ~= nil)
		if not (on and off) then
			return
		end
		local a, b = styled(on, "BackgroundColor3"), styled(off, "BackgroundColor3")
		t.note(where, { enabled = tostring(a), disabled = tostring(b) })
		t.check(
			`{where} disabled plate is nearer the page`,
			distance(b, page) < distance(a, page) - 0.02,
			{ enabled = distance(a, page), disabled = distance(b, page) }
		)
	end
	for _, look in looks do
		local on, off = t.find(stage, look.name .. "On"), t.find(stage, look.name .. "Off")
		compare(look.name, on, off)
		if on and off then
			local ta, tb = styled(on, "TextTransparency"), styled(off, "TextTransparency")
			local ca, cb = styled(on, "TextColor3"), styled(off, "TextColor3")
			t.check(
				`{look.name} label fades with the plate`,
				tb > ta + 0.05 or not sameColor(ca, cb),
				{ enabled = { ta, tostring(ca) }, disabled = { tb, tostring(cb) } }
			)
		end
	end
	local boxOn, boxOff = t.find(stage, "BoxOn"), t.find(stage, "BoxOff")
	compare(
		"checked checkbox",
		boxOn and boxOn:FindFirstChild("Indicator", true),
		boxOff and boxOff:FindFirstChild("Indicator", true)
	)
end)

interactive(
	"xsmall-rung",
	{ "post-port26-004", "post-port26-005", "post-port26-006" },
	"setup mounts an xsmall Button with an icon and an xsmall Chip; click the button; step button; click the chip; step chip",
	function(t)
		desktop(t)
		local value: { [string]: any } = { clicks = 0 }
		local stage = t.mount(function(UI, Host, Compose)
			value.chosen = Compose.cell(false)
			return Host.Frame "Board" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				UI.Button "Tiny" {
					label = "Go",
					icon = "close",
					controlSize = "xsmall",
					Position = UDim2.fromOffset(200, 200),
					onActivate = function()
						value.clicks += 1
					end,
				},
				UI.Chip "TinyChip" {
					label = "Tag",
					controlSize = "xsmall",
					selected = value.chosen,
					onToggle = function(next)
						value.chosen:set(next)
					end,
					Position = UDim2.fromOffset(200, 300),
				},
			}
		end, { size = Vector2.new(800, 600), frames = 20 })
		for _, name in { "Tiny", "TinyChip" } do
			local node = t.find(stage, name)
			t.check(`{name} found`, node ~= nil)
			if node then
				t.near(`{name} plate is 28 px`, node.AbsoluteSize.Y, 28, 0.5)
				t.check(`{name} carries xsmall`, node:GetAttribute("controlSize") == "xsmall")
				local padding = node:FindFirstChildWhichIsA("UIPadding")
				local left = padding and styled(padding, "PaddingLeft")
				local right = padding and styled(padding, "PaddingRight")
				t.check(
					`{name} side padding is 4 px`,
					left ~= nil and right ~= nil and left.Offset == 4 and right.Offset == 4,
					{ left = left and left.Offset, right = right and right.Offset }
				)
				value[name] = point(node)
			end
		end
		local tiny = t.find(stage, "Tiny")
		local icon = tiny and tiny:FindFirstChild("LeadingIcon", true)
		t.check("the xsmall icon exists", icon ~= nil)
		if icon then
			t.near("the icon is 12 px", icon.AbsoluteSize.X, 12, 0.5)
			t.near("the icon is 12 px high", icon.AbsoluteSize.Y, 12, 0.5)
		end
		t.note("points", { button = value.Tiny, chip = value.TinyChip })
		return value
	end,
	{
		button = function(t, value)
			t.check("the mouse click activated the xsmall button", value.clicks == 1, value.clicks)
		end,
		chip = function(t, value)
			t.check("the mouse click toggled the xsmall chip", value.chosen:peek() == true, value.chosen:peek())
		end,
	}
)

add("utility-stroke", { "post-port26-034" }, function(t)
	desktop(t)
	local package = define(t, "Utility", { metrics = { strokes = { hairline = 1, utility = 2 } } })
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Board" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			UI.Button "Util" { label = "Utility", appearance = "utility", Position = UDim2.fromOffset(200, 200) },
			UI.Button "Plain" { label = "Standard", Position = UDim2.fromOffset(400, 200) },
		}
	end, { theme = package, size = Vector2.new(800, 600), frames = 20 })
	local button = t.find(stage, "Util")
	t.check("the utility button exists", button ~= nil)
	if not button then
		return
	end
	t.check("it carries the utility tag", button:HasTag("facet-appearance-utility"), button:GetTags())
	local rule = rulesOf(stage)[".facet-appearance-utility::UIStroke"]
	t.check("the live sheet has the utility outline rule", rule ~= nil)
	if rule then
		t.check("the outline is 2 px", rule:GetProperty("Thickness") == 2, rule:GetProperties())
		t.check(
			"the outline is visible",
			(rule:GetProperty("Transparency") :: number) < 1,
			rule:GetProperty("Transparency")
		)
	end
	local b = t.rect(button)
	local label = if button:IsA("TextButton") and button.ContentText ~= ""
		then button
		else button:FindFirstChild("Title", true)
	t.check("the label exists", label ~= nil)
	if label then
		t.check("the label fits", t.fits(label), { label.TextBounds, label.AbsoluteSize })
		local bounds = label.TextBounds
		local lx = label.AbsolutePosition.X + (label.AbsoluteSize.X - bounds.X) / 2
		t.check(
			"the label text clears the 2 px outline",
			lx >= b.x + 2 and lx + bounds.X <= b.r - 2,
			{ text = { lx, lx + bounds.X }, plate = { b.x, b.r } }
		)
	end
end)

return cases
