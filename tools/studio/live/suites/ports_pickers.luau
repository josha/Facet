--!strict
local GuiService = game:GetService("GuiService")

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

local function sameRect(a: any, b: any, tolerance: number?): boolean
	local margin = tolerance or 0.5
	return math.abs(a.x - b.x) <= margin
		and math.abs(a.y - b.y) <= margin
		and math.abs(a.w - b.w) <= margin
		and math.abs(a.h - b.h) <= margin
end

local function point(node: any, dx: number?, dy: number?): { number }
	local at, size = node.AbsolutePosition, node.AbsoluteSize
	local x = at.X + (if dx then dx else size.X / 2)
	local y = at.Y + (if dy then dy else size.Y / 2)
	return { math.floor(x + 0.5), math.floor(y + 0.5) }
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

local function sameColor(a: any, b: any): boolean
	return typeof(a) == "Color3"
		and typeof(b) == "Color3"
		and math.abs(a.R - b.R) <= 2.5 / 255
		and math.abs(a.G - b.G) <= 2.5 / 255
		and math.abs(a.B - b.B) <= 2.5 / 255
end

local function themeNamed(t: any, name: string): any
	local wanted = string.lower(string.gsub(name, "_", ""))
	for _, entry in t.themes do
		if string.lower(string.gsub(entry.name, "_", "")) == wanted then
			return entry.package
		end
	end
	return nil
end

local function pointerScreen(t: any, width: number, height: number)
	t.device({ device = "generic_handheld_720", width = width, height = height })
	local tenFoot = GuiService:IsTenFootInterface()
	if tenFoot then
		t.device({ device = "xbox", frames = 1 })
		pcall(function()
			(game:GetService("StudioDeviceSimulatorService") :: any):StopSimulationAsync()
		end)
		t.settle(30)
	end
	t.note(`screen for {width}x{height}`, {
		viewport = workspace.CurrentCamera.ViewportSize,
		preferred = tostring(game:GetService("UserInputService").PreferredInput),
		handheldWasTenFoot = tenFoot,
	})
	t.check(
		`the {width}x{height} pointer screen is not a ten-foot interface`,
		not GuiService:IsTenFootInterface(),
		GuiService:IsTenFootInterface()
	)
end

local function scenario(t: any, name: string, size: Vector2?, theme: any?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, theme = theme, frames = 20 })
	return stage, built
end

local function layerOf(stage: any): any
	return stage:FindFirstAncestorWhichIsA("ScreenGui")
end

local function partOf(root: any, name: string): any
	if root == nil then
		return nil
	end
	return root:FindFirstChild(name) or root:FindFirstChild(name, true)
end

local function found(t: any, label: string, names: { string }, nodes: { [string]: any }): boolean
	local missing = {}
	for _, key in names do
		if nodes[key] == nil then
			table.insert(missing, key)
		end
	end
	t.check(label, #missing == 0, missing)
	return #missing == 0
end

local function gridIndex(t: any, year: number, month: number, day: number, weekStart: number?): number
	for index, date in t.Facet.civilDate.monthGrid(year, month, weekStart or 1) do
		if date.year == year and date.month == month and date.day == day then
			return index
		end
	end
	return 0
end

local function watchSelection(value: any)
	value.visited = {}
	if value.connection then
		value.connection:Disconnect()
	end
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		if selected then
			table.insert(value.visited, selected.Name)
		end
	end)
end

local function sequence(value: any): string
	return table.concat(value.visited, ",")
end

local opening: { any } = {}

local function openLater(Compose: any): any
	local cell = Compose.cell(false)
	table.insert(opening, cell)
	return cell
end

local function openNow(t: any)
	t.settle(4)
	for _, cell in opening do
		cell:set(true)
	end
	table.clear(opening)
	t.settle(12)
end

local LABELLED = { "Handle", "JoinCode", "Briefing", "Fee", "Speed" }

add("fields-label-above", { "post-pickers-002", "post-pickers-005" }, function(t)
	for _, size in { Vector2.new(1280, 720), Vector2.new(320, 800) } do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "text_controls", size)
		for _, name in LABELLED do
			local field = t.find(stage, name)
			local label = partOf(field, "Label")
			local title = partOf(label, "Title")
			local input = partOf(field, "Input")
			if
				not found(
					t,
					`{where} {name} has Label, Title and Input`,
					{ "label", "title", "input" },
					{ label = label, title = title, input = input }
				)
			then
				continue
			end
			t.stable(input)
			t.stable(label)
			t.stable(title)
			t.settle(4)
			local l, ti, i = t.rect(label), t.rect(title), t.rect(input)
			t.check(`{where} {name} label sits above its Input`, l.b <= i.y + 0.5, { label = l.b, input = i.y })
			t.check(`{where} {name} label is at least 44 px tall`, l.h >= 43.5, l.h)
			t.check(`{where} {name} title bottom meets the label bottom`, math.abs(ti.b - l.b) <= 1, {
				title = { ti.y, ti.h, ti.b },
				label = { l.y, l.h, l.b },
				bounds = title.TextBounds,
			})
			t.check(`{where} {name} title stays inside the label width`, ti.x >= l.x - 0.5 and ti.r <= l.r + 0.5, {
				title = { ti.x, ti.r },
				label = { l.x, l.r },
			})
			t.check(`{where} {name} title text fits its box`, t.fits(title), { title.TextBounds, title.AbsoluteSize })
		end
		t.cleanup()
	end
	local stage = t.mount(function(UI, _, Compose)
		return UI.TextInput "Long" {
			value = Compose.cell(""),
			label = "Your full racing name as it appears on the season leaderboard",
			requiredMark = "required",
		}
	end, { size = Vector2.new(320, 400), frames = 20 })
	local label = partOf(t.find(stage, "Long"), "Label")
	local title = partOf(label, "Title")
	if not found(t, "the long label has Label and Title", { "label", "title" }, { label = label, title = title }) then
		return
	end
	t.stable(title)
	local l, ti = t.rect(label), t.rect(title)
	t.check("the long title wraps inside the 320 px label", ti.r <= l.r + 0.5 and ti.w <= 320.5, { ti.w, l.w })
	t.check("the long title text fits its wrapped box", t.fits(title), { title.TextBounds, title.AbsoluteSize })
	t.check("the long title wraps onto more than one line", title.TextBounds.Y > title.TextSize * 1.5, {
		bounds = title.TextBounds,
		size = title.TextSize,
	})
	t.check(
		"the required mark is part of the label words",
		string.sub(title.ContentText, -2) == " *",
		title.ContentText
	)
	t.check("the label grows with its wrapped title", l.h >= ti.h - 0.5, { l.h, ti.h })
	t.note("not checked", "a tap on the label putting the caret in the field is not driven here")
end)

add("fields-error-still", { "post-pickers-007" }, function(t)
	local stage, built = scenario(t, "text_controls", Vector2.new(1280, 720))
	local field = t.find(stage, "Handle")
	local input = partOf(field, "Input")
	local mark = partOf(field, "MessageMark")
	local words = partOf(field, "Validation")
	if
		not found(
			t,
			"Handle has Input, MessageMark and Validation",
			{ "input", "mark", "words" },
			{ input = input, mark = mark, words = words }
		)
	then
		return
	end
	t.stable(input)
	local rest = t.rect(input)
	t.near("the hint starts at the Input left edge at rest", words.AbsolutePosition.X, rest.x, 1)
	for round = 1, 2 do
		local result = built.steps.nameError()
		t.settle(6)
		t.stable(input)
		local now = t.rect(input)
		local shown = result.error ~= ""
		t.check(
			`round {round} ({if shown then "error on" else "error off"}): the Input keeps its position and size`,
			sameRect(now, rest),
			{ rest = { rest.x, rest.y, rest.w, rest.h }, now = { now.x, now.y, now.w, now.h } }
		)
		t.check(`round {round}: the error mark shows only with the error`, mark.Visible == shown, mark.Visible)
		if shown then
			t.stable(mark)
			t.settle(4)
			t.check(
				"the error mark is as tall as its message line",
				math.abs(mark.AbsoluteSize.Y - words.AbsoluteSize.Y) <= 1,
				{
					mark = mark.AbsoluteSize,
					size = mark.Size,
					styledSize = styled(mark, "Size"),
					line = words.AbsoluteSize,
					message = if mark.Parent then mark.Parent.AbsoluteSize else nil,
				}
			)
			t.check("the error text is on one line at 1280 px", words.AbsoluteSize.Y <= words.TextSize * 1.6, {
				words.AbsoluteSize,
				words.TextSize,
			})
		else
			t.near("the hint returns to the Input left edge", words.AbsolutePosition.X, rest.x, 1)
		end
	end
end)

add("fields-accessories", { "post-pickers-009", "post-pickers-013" }, function(t)
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Column" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout({ Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }),
			UI.TextInput "Kitted" {
				LayoutOrder = 1,
				value = Compose.cell("Ada"),
				label = "Racer",
				clearButtonMode = "always",
				leading = Host.Frame "Glyph" { Size = UDim2.fromOffset(20, 20) },
				trailing = UI.Button "Go" { label = "Go", onActivate = function() end },
			},
			UI.TextInput "Find" {
				LayoutOrder = 2,
				value = Compose.cell("coast"),
				label = "Search tracks",
				presentation = "search",
				trailing = UI.Button "Filter" { label = "Filter", onActivate = function() end },
			},
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	local input = partOf(t.find(stage, "Kitted"), "Input")
	local parts = {}
	for _, name in { "Leading", "Field", "Clear", "Trailing" } do
		parts[name] = if input then input:FindFirstChild(name) else nil
	end
	if
		found(
			t,
			"the kitted field has Input, Leading, Field, Clear and Trailing",
			{ "input", "leading", "field", "clear", "trailing" },
			{
				input = input,
				leading = parts.Leading,
				field = parts.Field,
				clear = parts.Clear,
				trailing = parts.Trailing,
			}
		)
	then
		t.stable(input)
		local previous = nil
		for _, name in { "Leading", "Field", "Clear", "Trailing" } do
			local node = parts[name]
			t.check(`{name} is visible`, t.visible(node), node.Visible)
			t.inside(`{name} lies inside the Input plate`, node, input, 1)
			if previous then
				local a, b = t.rect(parts[previous]), t.rect(node)
				t.check(`{previous} ends before {name} starts`, a.r <= b.x + 0.5, { a.r, b.x })
			end
			previous = name
		end
	end
	local search = partOf(t.find(stage, "Find"), "Input")
	local icon = partOf(search, "SearchIcon")
	local field = if search then search:FindFirstChild("Field") else nil
	local trailing = if search then search:FindFirstChild("Trailing") else nil
	if
		found(
			t,
			"the search field has Input, SearchIcon, Field and Trailing",
			{ "input", "icon", "field", "trailing" },
			{
				input = search,
				icon = icon,
				field = field,
				trailing = trailing,
			}
		)
	then
		local i, f, s = t.rect(icon), t.rect(field), t.rect(search)
		t.inside("SearchIcon lies inside the search Input", icon, search, 1)
		t.check("SearchIcon is left of the Field", i.r <= f.x + 0.5, { i.r, f.x })
		t.check("SearchIcon sits less than 40 px from the Input left edge", i.x - s.x < 40, i.x - s.x)
		t.inside("the search Trailing lies inside the Input", trailing, search, 1)
		t.check(
			"the search Trailing is right of the Field",
			t.rect(trailing).x >= f.r - 0.5,
			{ f.r, trailing.AbsolutePosition.X }
		)
	end
end)

interactive(
	"fields-control-size",
	{ "post-pickers-016" },
	"afterClick: left-click once at the screen point noted as click (the middle of the compact Input plate)",
	function(t)
		local stage = t.mount(function(UI, _, Compose)
			return UI.TextInput "Compact" {
				value = Compose.cell("Ada"),
				label = "Name",
				controlSize = "compact",
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(360, 0),
			}
		end, { size = Vector2.new(600, 300), frames = 20 })
		local root = t.find(stage, "Compact")
		local input = partOf(root, "Input")
		local target = partOf(root, "Input+target")
		local field = partOf(input, "Field")
		local value = { field = field }
		if
			not found(
				t,
				"the compact field has Input, Input+target and Field",
				{ "input", "target", "field" },
				{ input = input, target = target, field = field }
			)
		then
			return value
		end
		t.stable(input)
		t.check("the compact Input plate is shorter than 44 px", input.AbsoluteSize.Y < 44, input.AbsoluteSize.Y)
		t.check("Input+target keeps a 44 px target", target.AbsoluteSize.Y >= 43.5, target.AbsoluteSize.Y)
		t.inside("the plate sits inside its target", input, target, 0.5)
		t.note("click", point(input))
		return value
	end,
	{
		afterClick = function(t, value)
			local field = value.field
			t.check(
				"the click on the Input focuses Field",
				field ~= nil and field:IsFocused(),
				field and field:IsFocused()
			)
			if field and field:IsFocused() then
				field:ReleaseFocus()
			end
		end,
	}
)

interactive(
	"fields-visible-lines",
	{ "post-pickers-092" },
	"afterType: type the letter x once on the keyboard (the Crew briefing field already has keyboard focus with the caret at the end)",
	function(t)
		local lines = t.mount(function(UI, Host, Compose)
			local children: { any } = {
				Host.UIListLayout({ Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
			}
			for order, count in { 1, 3, 5 } do
				table.insert(
					children,
					UI.TextInput({
						Name = `Lines{count}`,
						LayoutOrder = order,
						value = Compose.cell("One line"),
						multiline = true,
						visibleLines = count,
						label = `{count} lines`,
					})
				)
			end
			return Host.Frame "Lines" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				table.unpack(children),
			}
		end, { size = Vector2.new(400, 700), frames = 20 })
		local heights = {}
		for _, count in { 1, 3, 5 } do
			local viewport = partOf(t.find(lines, `Lines{count}`), "Viewport")
			heights[count] = if viewport then viewport.AbsoluteSize.Y else -1
		end
		t.note("viewport heights for 1, 3 and 5 lines", { heights[1], heights[3], heights[5] })
		t.check(
			"the viewport for 1 line is shorter than 3, and 3 shorter than 5",
			heights[1] > 0 and heights[1] < heights[3] and heights[3] < heights[5],
			{ heights[1], heights[3], heights[5] }
		)
		local stage, built = scenario(t, "text_controls", Vector2.new(1280, 720))
		local briefing = t.find(stage, "Briefing")
		local viewport = partOf(briefing, "Viewport")
		local field = partOf(viewport, "Field")
		local value = { viewport = viewport, field = field }
		if
			not found(
				t,
				"Briefing has Viewport and Field",
				{ "viewport", "field" },
				{ viewport = viewport, field = field }
			)
		then
			return value
		end
		t.stable(viewport)
		local before = viewport.AbsoluteSize.Y
		built.steps.briefLines()
		t.settle(8)
		t.stable(field)
		t.near("the Briefing viewport keeps its height after 12 more lines", viewport.AbsoluteSize.Y, before, 0.5)
		t.check(
			"the Briefing Field grows taller than its viewport",
			field.AbsoluteSize.Y > viewport.AbsoluteSize.Y + 0.5,
			{ field.AbsoluteSize.Y, viewport.AbsoluteSize.Y }
		)
		field:CaptureFocus()
		t.settle(2)
		field.CursorPosition = #field.Text + 1
		t.settle(4)
		t.note("canvas before typing", viewport.CanvasPosition)
		t.note("not checked", "the scenario adds 12 lines, not 20")
		return value
	end,
	{
		afterType = function(t, value)
			local viewport, field = value.viewport, value.field
			if not viewport or not field then
				t.check("Briefing parts were found", false)
				return
			end
			t.settle(4)
			local bottom = viewport.AbsoluteCanvasSize.Y - viewport.AbsoluteWindowSize.Y
			t.note("canvas after typing", { viewport.CanvasPosition.Y, bottom })
			t.check(
				"the typed letter reached the Briefing text",
				string.find(field.Text, "x", 1, true) ~= nil,
				field.Text
			)
			t.check(
				"the caret line at the end is scrolled into view",
				bottom > 0 and viewport.CanvasPosition.Y >= bottom - 24,
				{ canvas = viewport.CanvasPosition.Y, bottom = bottom }
			)
			if field:IsFocused() then
				field:ReleaseFocus()
			end
		end,
	}
)

interactive(
	"fields-select-on-focus",
	{ "post-pickers-064", "post-pickers-066" },
	"afterAll: left-click once at the screen point noted as clickAll; afterEnd: left-click once at the screen point noted as clickEnd; afterNone: left-click once at the screen point noted as clickNone",
	function(t)
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Column" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIPadding({ PaddingLeft = UDim.new(0, 40), PaddingTop = UDim.new(0, 40) }),
				Host.UIListLayout({ Padding = UDim.new(0, 24), SortOrder = Enum.SortOrder.LayoutOrder }),
				UI.NumberInput "Speed" {
					LayoutOrder = 1,
					Size = UDim2.fromOffset(420, 0),
					value = Compose.cell("120"),
					numericValue = Compose.cell(120),
					min = 0,
					max = 300,
					step = 5,
					suffix = "km/h",
					label = "Pit lane limit",
					scrub = true,
					selectOnFocus = "all",
				},
				UI.TextInput "Tail" {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(420, 0),
					value = Compose.cell("Coastal circuit"),
					label = "Caret at the end",
					selectOnFocus = "end",
				},
				UI.TextInput "Plain" {
					LayoutOrder = 3,
					Size = UDim2.fromOffset(420, 0),
					value = Compose.cell("Coastal circuit"),
					label = "Caret where the click lands",
					selectOnFocus = "none",
				},
			}
		end, { size = Vector2.new(700, 500), frames = 20 })
		local value = {
			all = partOf(t.find(stage, "Speed"), "Field"),
			tail = partOf(t.find(stage, "Tail"), "Field"),
			plain = partOf(t.find(stage, "Plain"), "Field"),
		}
		if not found(t, "the three Field boxes were found", { "all", "tail", "plain" }, value) then
			return value
		end
		t.stable(value.plain)
		t.note("clickAll", point(value.all))
		t.note("clickEnd", point(value.tail, 12))
		t.note("clickNone", point(value.plain, 12))
		return value
	end,
	{
		afterAll = function(t, value)
			local box = value.all
			t.settle(4)
			t.check("the Speed box has focus after the click", box ~= nil and box:IsFocused())
			if box then
				t.check(
					"all: the whole number is selected after release",
					box.SelectionStart == 1 and box.CursorPosition == #box.Text + 1,
					{
						selection = box.SelectionStart,
						cursor = box.CursorPosition,
						length = #box.Text,
					}
				)
			end
		end,
		afterEnd = function(t, value)
			local box = value.tail
			t.settle(4)
			t.check("the end box has focus after the click", box ~= nil and box:IsFocused())
			if box then
				t.check(
					"end: the caret sits at the end with no selection",
					box.CursorPosition == #box.Text + 1 and box.SelectionStart == -1,
					{
						selection = box.SelectionStart,
						cursor = box.CursorPosition,
						length = #box.Text,
					}
				)
			end
		end,
		afterNone = function(t, value)
			local box = value.plain
			t.settle(4)
			t.check("the none box has focus after the click", box ~= nil and box:IsFocused())
			if box then
				t.note("none: caret after the click near the start", box.CursorPosition)
				t.check("none: no selection is written", box.SelectionStart == -1, box.SelectionStart)
				t.check(
					"none: the caret stays where the click put it, not at the end",
					box.CursorPosition >= 1 and box.CursorPosition < #box.Text + 1,
					{ cursor = box.CursorPosition, length = #box.Text }
				)
				box:ReleaseFocus()
			end
			t.note("not checked", "the touch emulator tap is not driven")
		end,
	}
)

interactive(
	"number-step-buttons",
	{ "post-pickers-031", "post-pickers-032" },
	"afterRight: press the Right arrow key once; afterRightAgain: press the Right arrow key once more",
	function(t)
		local stage, built = scenario(t, "text_controls", Vector2.new(1280, 720))
		local input = partOf(t.find(stage, "Laps"), "Input")
		local field = if input then input:FindFirstChild("Field") else nil
		local dec = if input then input:FindFirstChild("Decrement") else nil
		local inc = if input then input:FindFirstChild("Increment") else nil
		local value = { built = built, dec = dec, inc = inc }
		if
			not found(
				t,
				"Laps has Input, Field, Decrement and Increment",
				{ "input", "field", "dec", "inc" },
				{ input = input, field = field, dec = dec, inc = inc }
			)
		then
			return value
		end
		t.stable(input)
		local d, i, f = t.rect(dec), t.rect(inc), t.rect(field)
		t.near("Decrement is 44 px wide", d.w, 44, 0.5)
		t.near("Decrement is 44 px tall", d.h, 44, 0.5)
		t.near("Increment is 44 px wide", i.w, 44, 0.5)
		t.near("Increment is 44 px tall", i.h, 44, 0.5)
		t.check("the step buttons do not overlap", not overlap(d, i), { d.r, i.x })
		t.inside("Decrement lies inside the Input plate", dec, input, 1)
		t.inside("Increment lies inside the Input plate", inc, input, 1)
		t.check("Field comes before Decrement", f.r <= d.x + 0.5, { f.r, d.x })
		t.check("Decrement comes before Increment", d.r <= i.x + 0.5, { d.r, i.x })
		local clear = input:FindFirstChild("Clear")
		if clear and t.visible(clear) then
			t.check("Clear comes before Decrement", t.rect(clear).r <= d.x + 0.5, { t.rect(clear).r, d.x })
		else
			t.note("clear", "Laps shows no Clear button")
		end
		value.laps = built.report().laps
		GuiService.SelectedObject = field
		t.settle(2)
		t.check("the Laps Field holds the selection at the start", GuiService.SelectedObject == field, selectedName())
		t.note("gamepad", "D-pad movement is proven with the arrow keys, which drive the same native selection")
		return value
	end,
	{
		afterRight = function(t, value)
			t.check("Right from the Field selects Decrement", GuiService.SelectedObject == value.dec, selectedName())
			t.check("the lap count is unchanged", value.built.report().laps == value.laps, value.built.report().laps)
		end,
		afterRightAgain = function(t, value)
			t.check("Right from Decrement selects Increment", GuiService.SelectedObject == value.inc, selectedName())
			t.check(
				"the arrow key on a step button does not change the number",
				value.built.report().laps == value.laps,
				value.built.report().laps
			)
			GuiService.SelectedObject = nil
		end,
	}
)

add("number-units", { "post-pickers-027" }, function(t)
	for _, size in { Vector2.new(1280, 720), Vector2.new(320, 640) } do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "text_controls", size)
		local input = partOf(t.find(stage, "Fee"), "Input")
		local prefix = if input then input:FindFirstChild("Prefix") else nil
		local suffix = if input then input:FindFirstChild("Suffix") else nil
		local field = if input then input:FindFirstChild("Field") else nil
		if
			found(
				t,
				`{where} Fee has Input, Prefix, Field and Suffix`,
				{ "input", "prefix", "field", "suffix" },
				{ input = input, prefix = prefix, field = field, suffix = suffix }
			)
		then
			t.stable(input)
			local p, f, s = t.rect(prefix), t.rect(field), t.rect(suffix)
			t.check(`{where} Prefix ends before the Field starts`, p.r <= f.x + 0.5, { p.r, f.x })
			t.check(`{where} Suffix starts after the Field ends`, s.x >= f.r - 0.5, { s.x, f.r })
			t.inside(`{where} Prefix inside the Fee plate`, prefix, input, 1)
			t.inside(`{where} Suffix inside the Fee plate`, suffix, input, 1)
			t.check(`{where} the Fee Field keeps at least 40 px`, f.w >= 40, f.w)
		end
		t.cleanup()
	end
	t.note("text size", t.environment.preferredTextSize)
	t.note(
		"not checked",
		"the largest PreferredTextSize cannot be set from a script; run this case again after a person sets Largest"
	)
end)

add("slider-axis-live", { "post-pickers-098" }, function(t)
	local stage, built = scenario(t, "adaptive_controls", Vector2.new(1280, 720))
	local track = partOf(t.find(stage, "Balance"), "Track")
	local fill = partOf(track, "Fill")
	local thumb = partOf(track, "Thumb")
	if
		not found(
			t,
			"Balance has Track, Fill and Thumb",
			{ "track", "fill", "thumb" },
			{ track = track, fill = fill, thumb = thumb }
		)
	then
		return
	end
	t.stable(track)
	local tr, fi = t.rect(track), t.rect(fill)
	t.check("the vertical track is taller than it is wide", tr.h > tr.w, { tr.w, tr.h })
	t.near("at 50 the fill bottom meets the track bottom", fi.b, tr.b, 1)
	t.near("at 50 the fill is half the track height", fi.h, tr.h / 2, 1)
	local before = thumb.AbsolutePosition.Y + thumb.AbsoluteSize.Y / 2
	built.steps.sliderAxis()
	t.settle(6)
	t.stable(thumb)
	local after = thumb.AbsolutePosition.Y + thumb.AbsoluteSize.Y / 2
	fi = t.rect(fill)
	t.check("at 90 the thumb is higher on screen than at 50", after < before - 0.5, { at50 = before, at90 = after })
	t.near("at 90 the fill bottom still meets the track bottom", fi.b, tr.b, 1)
	t.near("at 90 the fill is nine tenths of the track", fi.h, tr.h * 0.9, 1)
end)

interactive(
	"slider-landing-live",
	{ "post-pickers-100" },
	"afterUp: press the Up arrow key once; afterSecondUp: press the Up arrow key once more",
	function(t)
		local stage, built = scenario(t, "adaptive_controls", Vector2.new(1280, 720))
		local boost = partOf(t.find(stage, "Boost"), "Track")
		local balance = partOf(t.find(stage, "Balance"), "Track")
		local value = { built = built, boost = boost, balance = balance }
		if
			not found(
				t,
				"Boost and Balance tracks were found",
				{ "boost", "balance" },
				{ boost = boost, balance = balance }
			)
		then
			return value
		end
		GuiService.SelectedObject = boost
		t.settle(4)
		t.check("the Boost track holds the selection at the start", GuiService.SelectedObject == boost, selectedName())
		local report = built.report()
		t.note("start values", { rear = report.rear, boost = report.boost })
		t.note("gamepad", "DPadUp is proven with the Up arrow key, which drives the same native selection")
		return value
	end,
	{
		afterUp = function(t, value)
			local report = value.built.report()
			t.check(
				"Up moves the selection onto the Balance track",
				GuiService.SelectedObject == value.balance,
				selectedName()
			)
			t.check("landing on Balance does not change its value", report.rear == 50, report.rear)
			t.check("leaving Boost does not change its value", report.boost == 35, report.boost)
		end,
		afterSecondUp = function(t, value)
			local report = value.built.report()
			t.check("a second Up raises Balance by one step", report.rear == 55, report.rear)
			t.check(
				"the selection stays on the Balance track",
				GuiService.SelectedObject == value.balance,
				selectedName()
			)
			GuiService.SelectedObject = nil
		end,
	}
)

local function paintedPoint(track: any, fraction: number, degrees: number): { number }
	local at, size = track.AbsolutePosition, track.AbsoluteSize
	local cx, cy = at.X + size.X / 2, at.Y + size.Y / 2
	local a = math.rad(degrees)
	local along = (fraction - 0.5) * size.X
	return {
		math.floor(cx + along * math.cos(a) + 0.5),
		math.floor(cy + along * math.sin(a) + 0.5),
	}
end

interactive(
	"slider-rotation-live",
	{ "post-pickers-102" },
	"afterTurn0: left-click once at the screen point noted as click0; afterTurn135: left-click once at the screen point given in the detail of the afterTurn0 check 'the next click point click135'; afterTurn270Scrolled: left-click once at the screen point given in the detail of the afterTurn135 check 'the next click point click270'",
	function(t)
		local value: any = {}
		local stage = t.mount(function(UI, Host, Compose)
			value.band = Compose.cell({ lower = 10, upper = 30 })
			value.turn = Compose.cell(0)
			return Host.ScrollingFrame "Scroller" {
				Size = UDim2.fromOffset(700, 520),
				CanvasSize = UDim2.fromOffset(0, 1100),
				BackgroundTransparency = 1,
				ScrollBarThickness = 6,
				Host.Frame "TiltStage" {
					Size = UDim2.fromOffset(320, 320),
					Position = UDim2.fromOffset(190, 100),
					BackgroundTransparency = 1,
					UI.Slider "Tilt" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.new(0.8, 0, 0, 0),
						value = value.band,
						min = 0,
						max = 100,
						step = 10,
						range = true,
						minGap = 10,
						rotation = value.turn,
					},
				},
			}
		end, { size = Vector2.new(800, 600), frames = 20 })
		value.scroller = t.find(stage, "Scroller")
		value.track = partOf(t.find(stage, "Tilt"), "Track")
		if not found(t, "the Tilt track was found", { "track" }, { track = value.track }) then
			return value
		end
		t.stable(value.track)
		t.note("click0", paintedPoint(value.track, 0.8, 0))
		t.note("expected", "each click at fraction 0.8 moves the nearer (upper) handle to 80; lower stays 10")
		t.note(
			"harness",
			"if UIDragDetector.DragStart does not fire on a click from the input tools, record that as the harness limit"
		)
		return value
	end,
	{
		afterTurn0 = function(t, value)
			local band = value.band:peek()
			t.check("at 0 degrees the click sets the upper handle to 80", band.upper == 80 and band.lower == 10, band)
			value.band:set({ lower = 10, upper = 30 })
			value.turn:set(135)
			t.settle(6)
			local next = paintedPoint(value.track, 0.8, 135)
			t.check("the next click point click135 lies on the screen", next[1] >= 0 and next[2] >= 0, next)
		end,
		afterTurn135 = function(t, value)
			local band = value.band:peek()
			t.check("at 135 degrees the click sets the upper handle to 80", band.upper == 80 and band.lower == 10, band)
			value.band:set({ lower = 10, upper = 30 })
			value.turn:set(270)
			value.scroller.CanvasPosition = Vector2.new(0, 60)
			t.settle(6)
			local next = paintedPoint(value.track, 0.8, 270)
			t.check("the next click point click270 lies on the screen", next[1] >= 0 and next[2] >= 0, next)
		end,
		afterTurn270Scrolled = function(t, value)
			local band = value.band:peek()
			t.check(
				"at 270 degrees on a scrolled page the click sets the upper handle to 80",
				band.upper == 80 and band.lower == 10,
				band
			)
		end,
	}
)

add("slider-range-live", { "post-pickers-104", "post-pickers-105", "post-pickers-127" }, function(t)
	local stage = scenario(t, "adaptive_controls", Vector2.new(1280, 720))
	local track = partOf(t.find(stage, "LapWindow"), "Track")
	local lower = partOf(track, "HandleLower")
	local upper = partOf(track, "HandleUpper")
	local fill = partOf(track, "Fill")
	if
		found(
			t,
			"LapWindow has Track, both handles and Fill",
			{ "track", "lower", "upper", "fill" },
			{ track = track, lower = lower, upper = upper, fill = fill }
		)
	then
		t.stable(track)
		for _, handle in { lower, upper } do
			t.check(
				`{handle.Name} is at least 44x44 on screen`,
				handle.AbsoluteSize.X >= 43.5 and handle.AbsoluteSize.Y >= 43.5,
				handle.AbsoluteSize
			)
		end
		local f = t.rect(fill)
		t.near(
			"the fill starts at the lower handle centre",
			f.x,
			lower.AbsolutePosition.X + lower.AbsoluteSize.X / 2,
			1
		)
		t.near("the fill ends at the upper handle centre", f.r, upper.AbsolutePosition.X + upper.AbsoluteSize.X / 2, 1)
	end
	t.cleanup()
	local knobs = t.mount(function(UI, Host, Compose)
		return UI.Slider "Knobs" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(420, 0),
			value = Compose.cell({ lower = 0, upper = 100 }),
			min = 0,
			max = 100,
			range = true,
			thumbContent = function(info: any)
				local edge = if info.thumb == "lower" then 16 else 36
				return Host.Frame "Art" { Size = UDim2.fromOffset(edge, edge) }
			end,
		}
	end, { size = Vector2.new(600, 200), frames = 20 })
	local knobTrack = partOf(t.find(knobs, "Knobs"), "Track")
	local low = partOf(knobTrack, "HandleLower")
	local high = partOf(knobTrack, "HandleUpper")
	local lowArt = partOf(low, "Art")
	local highArt = partOf(high, "Art")
	if
		found(
			t,
			"the custom-knob slider has both handles and their art",
			{ "low", "high", "lowArt", "highArt" },
			{ low = low, high = high, lowArt = lowArt, highArt = highArt }
		)
	then
		t.stable(knobTrack)
		local tr = t.rect(knobTrack)
		local function middle(node: any): number
			return node.AbsolutePosition.X + node.AbsoluteSize.X / 2
		end
		t.check(
			"the two knobs are drawn at different sizes",
			math.abs(lowArt.AbsoluteSize.X - highArt.AbsoluteSize.X) > 4,
			{
				lowArt.AbsoluteSize,
				highArt.AbsoluteSize,
			}
		)
		t.near("the small knob at min stops at the track start", middle(lowArt), tr.x, 1)
		t.near("the large knob at max stops at the track end", middle(highArt), tr.r, 1)
	end
	t.note(
		"not checked",
		"dragging a handle past the other to minGap needs a pointer drag, which the input tools cannot send"
	)
end)

interactive(
	"slider-thumb-auto-live",
	{ "post-pickers-116", "post-pickers-117", "post-pickers-121" },
	"afterHover: move the mouse (no button) to the screen point noted as hover; afterLeave: move the mouse (no button) to the screen point noted as away",
	function(t)
		local stage = scenario(t, "adaptive_controls", Vector2.new(1280, 720))
		local track = partOf(t.find(stage, "Boost"), "Track")
		local thumb = partOf(track, "Thumb")
		local value = { track = track, thumb = thumb }
		if not found(t, "Boost has Track and Thumb", { "track", "thumb" }, value) then
			return value
		end
		GuiService.SelectedObject = nil
		t.settle(4)
		t.check("the Boost handle is hidden at rest", not thumb.Visible, thumb.Visible)
		GuiService.SelectedObject = track
		t.settle(4)
		t.check("the Boost handle shows while its track is selected", thumb.Visible, thumb.Visible)
		GuiService.SelectedObject = nil
		t.settle(4)
		t.check("the Boost handle hides again when the selection leaves", not thumb.Visible, thumb.Visible)
		t.note("hover", point(track))
		t.note("away", point(stage, 8, 8))
		return value
	end,
	{
		afterHover = function(t, value)
			t.settle(4)
			t.check(
				"the Boost handle shows while the pointer hovers the track",
				value.thumb.Visible,
				value.track.GuiState
			)
		end,
		afterLeave = function(t, value)
			t.settle(4)
			t.check("the Boost handle hides when the pointer leaves", not value.thumb.Visible, value.track.GuiState)
			t.device({ device = "iphone_14" })
			t.settle(6)
			t.note("preferred input on the phone", tostring(game:GetService("UserInputService").PreferredInput))
			t.check(
				"the Boost handle is always visible with touch as the preferred input",
				value.thumb.Visible,
				value.thumb.Visible
			)
		end,
	}
)

add("slider-label-shrinks-live", {}, function(t)
	local stage = scenario(t, "adaptive_controls", Vector2.new(320, 640))
	for _, name in { "Brightness", "LapWindow", "Boost", "Camera", "Steer" } do
		local slider = t.find(stage, name)
		local track = partOf(slider, "Track")
		local readout = partOf(slider, "Value")
		local label = partOf(slider, "Label")
		if
			not found(
				t,
				`{name} has Track, Value and Label`,
				{ "track", "readout", "label" },
				{ track = track, readout = readout, label = label }
			)
		then
			continue
		end
		t.stable(track)
		t.check(`{name} track keeps at least 120 px at 320 px`, track.AbsoluteSize.X >= 120, track.AbsoluteSize.X)
		t.check(`{name} readout is not cut`, t.fits(readout), { readout.TextBounds, readout.AbsoluteSize })
		t.check(
			`{name} label truncates rather than overflowing`,
			label.TextTruncate == Enum.TextTruncate.AtEnd,
			tostring(label.TextTruncate)
		)
	end
	t.note("text size", t.environment.preferredTextSize)
	t.note(
		"not checked",
		"the largest PreferredTextSize cannot be set from a script; run this case again after a person sets Largest"
	)
end)

local SEP16 = { year = 2026, month = 9, day = 16 }
local TODAY = { year = 2026, month = 9, day = 23 }

local function singleSpec(Compose: any, extra: { [string]: any }): any
	local value = Compose.cell(extra.value or SEP16)
	local spec: { [string]: any } = {
		label = "Race day",
		value = value,
		onChange = function(next: any)
			value:set(next)
		end,
		clock = function()
			return extra.today or TODAY
		end,
	}
	for key, item in extra do
		if key ~= "value" and key ~= "today" then
			spec[key] = item
		end
	end
	return spec
end

local function rangeSpec(Compose: any, extra: { [string]: any }): any
	local range = Compose.cell(extra.range or {})
	local spec: { [string]: any } = {
		label = "Season window",
		selection = "range",
		range = range,
		onRangeChange = function(next: any)
			range:set(next)
		end,
		clock = function()
			return extra.today or TODAY
		end,
	}
	for key, item in extra do
		if key ~= "range" and key ~= "today" then
			spec[key] = item
		end
	end
	return spec
end

local function datePicker(t: any, make: (any, any) -> any, holder: { [string]: any }?): (any, any, any)
	local config = holder or {}
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Holder" {
			BackgroundTransparency = 1,
			Position = config.position or UDim2.fromOffset(40, 40),
			AnchorPoint = config.anchor or Vector2.zero,
			Size = config.size or UDim2.fromOffset(360, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			UI.DateTimePicker("Date")(make(Compose, UI)),
		}
	end, { frames = 20 })
	openNow(t)
	return stage, t.find(stage, "Date"), layerOf(stage)
end

local function surfaceOf(t: any, layer: any): any
	local surface = visibleNamed(t, layer, "CalendarSurface")
	if surface then
		t.stable(surface)
	end
	return surface
end

add("dtp-anchor-below", { "post-pickers-141" }, function(t)
	for _, place in
		{
			{ name = "top", position = UDim2.fromOffset(40, 40), anchor = Vector2.zero },
			{ name = "bottom", position = UDim2.new(0, 40, 1, -40), anchor = Vector2.new(0, 1) },
		}
	do
		pointerScreen(t, 1280, 720)
		local _, root, layer = datePicker(t, function(Compose)
			return singleSpec(Compose, { isPresented = openLater(Compose) })
		end, { position = place.position, anchor = place.anchor })
		local plate = partOf(root, "Field")
		local surface = surfaceOf(t, layer)
		if
			found(
				t,
				`{place.name}: the Field plate and CalendarSurface were found`,
				{ "plate", "surface" },
				{ plate = plate, surface = surface }
			)
		then
			local p, s, l = t.rect(plate), t.rect(surface), t.rect(layer)
			t.note(`{place.name} route`, root:GetAttribute("route"))
			t.check(
				`{place.name}: the calendar left edge is the plate left edge or 8 px from the screen edge`,
				math.abs(s.x - p.x) <= 1 or math.abs(s.x - (l.x + 8)) <= 1,
				{
					surface = s.x,
					plate = p.x,
				}
			)
			t.inside(`{place.name}: the calendar stays inside the screen`, surface, layer, 1)
			if place.name == "top" then
				t.near("top: the calendar hangs 4 px below the plate", s.y, p.b + 4, 1)
			else
				t.check("bottom: the calendar does not fit below the plate", p.b + 4 + s.h > l.b - 8, { p.b, s.h, l.b })
				t.near("bottom: the calendar flips above the plate", s.b, p.y - 4, 1)
			end
		end
		t.cleanup()
	end
end)

interactive(
	"dtp-icon-toggle",
	{ "post-pickers-141" },
	"afterOpen: left-click once at the screen point noted as icon; afterClose: left-click once more at the same point noted as icon; afterReopen: left-click once more at the same point noted as icon",
	function(t)
		local value: any = { reasons = {} }
		local stage, root = datePicker(t, function(Compose)
			return singleSpec(Compose, {
				onDismiss = function(reason: any)
					table.insert(value.reasons, tostring(reason))
				end,
			})
		end)
		value.root = root
		local icon = partOf(root, "Open")
		if not found(t, "the calendar icon Open was found", { "root", "icon" }, { root = root, icon = icon }) then
			return value
		end
		t.stable(icon)
		t.check("the picker starts closed", root:GetAttribute("presented") == false, root:GetAttribute("presented"))
		t.note("icon", point(icon))
		t.note("stage", stage:GetFullName())
		return value
	end,
	{
		afterOpen = function(t, value)
			t.settle(6)
			t.check(
				"the first click on the icon opens the calendar",
				value.root:GetAttribute("presented") == true,
				value.root:GetAttribute("presented")
			)
		end,
		afterClose = function(t, value)
			t.settle(6)
			t.check(
				"a click on the icon while open closes it",
				value.root:GetAttribute("presented") == false,
				value.root:GetAttribute("presented")
			)
			t.check("the close reports onDismiss outside", table.find(value.reasons, "outside") ~= nil, value.reasons)
		end,
		afterReopen = function(t, value)
			t.settle(6)
			t.check(
				"the next click opens it again",
				value.root:GetAttribute("presented") == true,
				value.root:GetAttribute("presented")
			)
		end,
	}
)

add("dtp-grid-layout", { "post-pickers-155" }, function(t)
	local _, root = datePicker(t, function(Compose)
		return rangeSpec(Compose, {
			style = "inline",
			range = { start = { year = 2026, month = 9, day = 10 }, finish = { year = 2026, month = 9, day = 15 } },
		})
	end, { size = UDim2.fromOffset(1000, 0) })
	if not found(t, "the inline range picker was found", { "root" }, { root = root }) then
		return
	end
	t.check("a 1000 px range shows two months", root:GetAttribute("dual") == true, root:GetAttribute("dual"))
	local panes = {}
	for k = 1, 2 do
		local pane = partOf(root, `Pane{k}`)
		local days = partOf(pane, "Days")
		local weekdays = partOf(pane, "Weekdays")
		if
			not found(
				t,
				`Pane{k} has Days and Weekdays`,
				{ "pane", "days", "weekdays" },
				{ pane = pane, days = days, weekdays = weekdays }
			)
		then
			continue
		end
		panes[k] = pane
		t.stable(days)
		local origin = t.rect(days)
		local wrong = {}
		for i = 1, 42 do
			local cell = days:FindFirstChild(`D{i}`)
			if not cell then
				table.insert(wrong, `D{i} missing`)
				continue
			end
			local c = t.rect(cell)
			local column, row = (i - 1) % 7, math.floor((i - 1) / 7)
			if
				math.abs(c.w - 44) > 0.5
				or math.abs(c.h - 44) > 0.5
				or math.abs(c.x - (origin.x + column * 44)) > 0.5
				or math.abs(c.y - (origin.y + row * 44)) > 0.5
			then
				table.insert(wrong, { `D{i}`, c.x - origin.x, c.y - origin.y, c.w, c.h })
			end
		end
		t.check(`Pane{k} lays 42 cells as six rows of seven 44x44 cells`, #wrong == 0, wrong)
		local misaligned = {}
		for c = 1, 7 do
			local name = weekdays:FindFirstChild(`W{c}`)
			local cell = days:FindFirstChild(`D{c}`)
			if name and cell then
				local a = name.AbsolutePosition.X + name.AbsoluteSize.X / 2
				local b = cell.AbsolutePosition.X + cell.AbsoluteSize.X / 2
				if math.abs(a - b) > 1 then
					table.insert(misaligned, { c, a, b })
				end
			else
				table.insert(misaligned, `W{c} or D{c} missing`)
			end
		end
		t.check(`Pane{k} weekday names sit over their columns`, #misaligned == 0, misaligned)
	end
	if panes[1] and panes[2] then
		local a, b = t.rect(panes[1]), t.rect(panes[2])
		t.check("the two panes sit side by side", math.abs(a.y - b.y) <= 1 and b.x > a.r, { a.y, b.y })
		t.near("the panes are 24 px apart", b.x - a.r, 24, 1)
	end
end)

interactive(
	"dtp-native-navigation",
	{ "post-pickers-144", "post-pickers-145" },
	"afterUpWalk: press the Up arrow key 3 times; afterDownWalk: press the Down arrow key 3 times; afterDraftDown: press the Down arrow key 3 times; afterInlineDown: press the Down arrow key 3 times",
	function(t)
		local value: any = {}
		local stage = t.mount(function(UI, Host, Compose)
			value.open = openLater(Compose)
			return Host.Frame "Holder" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(360, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				UI.DateTimePicker("Date")(singleSpec(Compose, {
					value = { year = 2026, month = 9, day = 16, hour = 14, minute = 30 },
					time = true,
					draft = true,
					isPresented = value.open,
				})),
			}
		end, { frames = 20 })
		openNow(t)
		local layer = layerOf(stage)
		surfaceOf(t, layer)
		local days = partOf(visibleNamed(t, layer, "Pane1"), "Days")
		value.start = gridIndex(t, 2026, 9, 16)
		value.days = days
		if not found(t, "the open calendar Days grid was found", { "days" }, { days = days }) then
			return value
		end
		GuiService.SelectedObject = days:FindFirstChild(`D{value.start}`)
		t.settle(4)
		t.check("Sep 16 holds the selection at the start", selectedName() == `D{value.start}`, selectedName())
		watchSelection(value)
		t.note("expected up walk", { `D{value.start - 7}`, `D{value.start - 14}`, "Month" })
		t.note("gamepad", "D-pad movement is proven with the arrow keys, which drive the same native selection")
		return value
	end,
	{
		afterUpWalk = function(t, value)
			local s = value.start
			t.note("up walk", value.visited)
			t.check(
				"Up walks Sep 9, Sep 2, then leaves the first week for the Month menu, one step per press",
				sequence(value) == `D{s - 7},D{s - 14},Month`,
				value.visited
			)
			GuiService.SelectedObject = value.days:FindFirstChild(`D{s}`)
			t.settle(2)
			watchSelection(value)
		end,
		afterDownWalk = function(t, value)
			local s = value.start
			local selected = GuiService.SelectedObject
			t.note("down walk", value.visited)
			t.check(
				"Down walks Sep 23, Sep 30, then leaves the last week for the Hour field",
				sequence(value) == `D{s + 7},D{s + 14},Field`
					and selected ~= nil
					and selected:FindFirstAncestor("Hour") ~= nil,
				value.visited
			)
			value.open:set(false)
			t.settle(6)
			local stage = t.mount(function(UI, Host, Compose)
				value.open = openLater(Compose)
				return Host.Frame "Holder" {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(40, 40),
					Size = UDim2.fromOffset(360, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.DateTimePicker("Date")(singleSpec(Compose, { draft = true, isPresented = value.open })),
				}
			end, { frames = 20 })
			openNow(t)
			local layer = layerOf(stage)
			surfaceOf(t, layer)
			value.days = partOf(visibleNamed(t, layer, "Pane1"), "Days")
			GuiService.SelectedObject = if value.days then value.days:FindFirstChild(`D{s}`) else nil
			t.settle(4)
			watchSelection(value)
		end,
		afterDraftDown = function(t, value)
			local s = value.start
			t.note("draft down walk", value.visited)
			t.check(
				"without time, Down from the last week reaches the first action ResetAll",
				sequence(value) == `D{s + 7},D{s + 14},ResetAll`,
				value.visited
			)
			value.open:set(false)
			t.settle(6)
			local stage = t.mount(function(UI, Host, Compose)
				return Host.Frame "Column" {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(40, 40),
					Size = UDim2.fromOffset(360, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({ Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
					UI.DateTimePicker("Date")(singleSpec(Compose, { style = "inline", LayoutOrder = 1 })),
					UI.Button "Below" { label = "Below", LayoutOrder = 2, onActivate = function() end },
				}
			end, { frames = 20 })
			value.days = partOf(t.find(stage, "Pane1"), "Days")
			GuiService.SelectedObject = if value.days then value.days:FindFirstChild(`D{s}`) else nil
			t.settle(4)
			watchSelection(value)
		end,
		afterInlineDown = function(t, value)
			local s = value.start
			t.note("inline down walk", value.visited)
			t.check(
				"inline without draft, Down from the last week reaches the next control below",
				sequence(value) == `D{s + 7},D{s + 14},Below`,
				value.visited
			)
			if value.connection then
				value.connection:Disconnect()
			end
			GuiService.SelectedObject = nil
		end,
	}
)

local function phoneChecks(t: any, where: string, root: any, layer: any, portrait: boolean)
	local surface = surfaceOf(t, layer)
	local apply = if surface then visibleNamed(t, surface, "Apply") else nil
	local days = if surface then partOf(visibleNamed(t, surface, "Pane1"), "Days") else nil
	if
		not found(
			t,
			`{where}: the CalendarSurface, Days and Apply were found`,
			{ "surface", "apply", "days" },
			{ surface = surface, apply = apply, days = days }
		)
	then
		return
	end
	local l, s = t.rect(layer), t.rect(surface)
	t.note(`{where} route`, root:GetAttribute("route"))
	t.inside(`{where}: the calendar stays inside the screen`, surface, layer, 1)
	if portrait then
		t.check(
			`{where}: the calendar opens as a sheet`,
			root:GetAttribute("route") == "sheet",
			root:GetAttribute("route")
		)
		t.near(`{where}: the sheet spans the screen width minus 24 px`, s.w, l.w - 24, 1)
		local bad = {}
		for i = 1, 42 do
			local cell = days:FindFirstChild(`D{i}`)
			if cell and cell.Selectable then
				local seen = t.clipped(cell)
				local c = t.rect(cell)
				if
					c.w < 43.5
					or c.h < 43.5
					or seen == nil
					or math.abs(seen.w - c.w) > 0.5
					or math.abs(seen.h - c.h) > 0.5
					or c.x < l.x - 0.5
					or c.r > l.r + 0.5
					or c.y < l.y - 0.5
					or c.b > l.b + 0.5
				then
					table.insert(bad, { cell.Name, c.w, c.h, seen ~= nil })
				end
			end
		end
		t.check(`{where}: every day cell is at least 44x44 and fully on screen`, #bad == 0, bad)
		local seen = t.clipped(apply)
		t.check(
			`{where}: Apply is fully on screen without scrolling`,
			seen ~= nil and math.abs(seen.h - apply.AbsoluteSize.Y) <= 0.5,
			seen
		)
		t.inside(`{where}: Apply inside the screen`, apply, layer, 1)
	else
		local small = {}
		for i = 1, 42 do
			local cell = days:FindFirstChild(`D{i}`)
			if cell and cell.Selectable then
				local c = t.rect(cell)
				if c.w < 43.5 or c.h < 43.5 or c.x < l.x - 0.5 or c.r > l.r + 0.5 then
					table.insert(small, { cell.Name, c.w, c.h, c.x, c.r })
				end
			end
		end
		t.check(`{where}: every day cell is at least 44x44 and inside the screen width`, #small == 0, small)
		t.check(`{where}: the calendar is capped to the screen height`, s.h <= l.h - 16 + 1, { s.h, l.h })
		surface.CanvasPosition = Vector2.new(0, surface.AbsoluteCanvasSize.Y)
		t.settle(4)
		local seen = t.clipped(apply)
		t.check(
			`{where}: Apply is reachable by scrolling the CalendarSurface`,
			seen ~= nil and math.abs(seen.h - apply.AbsoluteSize.Y) <= 0.5,
			{ seen = seen, canvas = surface.CanvasPosition }
		)
		t.inside(`{where}: Apply inside the screen after scrolling`, apply, layer, 1)
	end
end

add("dtp-phone-fit", { "post-pickers-157" }, function(t)
	local preset = {
		{
			id = "week",
			label = "This week",
			range = function(day: any)
				return { start = day, finish = t.Facet.civilDate.addDays(day, 6) }
			end,
		},
	}
	for _, turn in
		{
			{ name = "portrait", orientation = Enum.ScreenOrientation.Portrait },
			{ name = "landscape", orientation = Enum.ScreenOrientation.LandscapeRight },
		}
	do
		t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, orientation = turn.orientation })
		t.note(`{turn.name} viewport`, workspace.CurrentCamera.ViewportSize)
		t.note(`{turn.name} preferred input`, tostring(game:GetService("UserInputService").PreferredInput))
		local _, root, layer = datePicker(t, function(Compose)
			return singleSpec(Compose, { draft = true, isPresented = openLater(Compose) })
		end, { position = UDim2.fromOffset(16, 16), size = UDim2.new(1, -32, 0, 0) })
		phoneChecks(t, `{turn.name} single`, root, layer, turn.name == "portrait")
		t.cleanup()
		t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, orientation = turn.orientation })
		local _, rangeRoot, rangeLayer = datePicker(t, function(Compose)
			return rangeSpec(Compose, { draft = true, presets = preset, isPresented = openLater(Compose) })
		end, { position = UDim2.fromOffset(16, 16), size = UDim2.new(1, -32, 0, 0) })
		phoneChecks(t, `{turn.name} range`, rangeRoot, rangeLayer, turn.name == "portrait")
		t.cleanup()
	end
	t.note("opened by", "isPresented = true rather than a tap on the Show button")
end)

add("dtp-panel-hugs", { "post-pickers-158" }, function(t)
	pointerScreen(t, 1280, 720)
	local _, root, layer = datePicker(t, function(Compose)
		return singleSpec(Compose, { isPresented = openLater(Compose) })
	end)
	local surface = surfaceOf(t, layer)
	local calendar = if surface then partOf(surface, "Calendar") else nil
	local header = partOf(calendar, "Header")
	local panes = partOf(calendar, "Panes")
	if
		not found(
			t,
			"the Calendar, Header and Panes were found",
			{ "calendar", "header", "panes" },
			{ calendar = calendar, header = header, panes = panes }
		)
	then
		return
	end
	t.note("route", root:GetAttribute("route"))
	t.note("preferred input", tostring(game:GetService("UserInputService").PreferredInput))
	local c = t.rect(calendar)
	t.near("the header is one 44 px line", header.AbsoluteSize.Y, 44, 0.5)
	local rule = partOf(calendar, "HeaderRule")
	local weekdays = partOf(partOf(panes, "Pane1"), "Weekdays")
	if rule and weekdays then
		t.near(
			"no caption sits between the rule and the weekdays",
			weekdays.AbsolutePosition.Y - (rule.AbsolutePosition.Y + rule.AbsoluteSize.Y),
			16,
			1
		)
	else
		t.check("the HeaderRule and the weekdays were found", false)
	end
	t.near("the side inset is 16 px", panes.AbsolutePosition.X - c.x, 16, 1)
	local lowest, shown = -math.huge, {}
	for _, child in calendar:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child.AbsoluteSize.Y > 0.5 then
			table.insert(shown, child.Name)
			lowest = math.max(lowest, child.AbsolutePosition.Y + child.AbsoluteSize.Y)
		end
	end
	t.note("visible calendar parts", shown)
	t.near("the bottom inset equals the side inset", c.b - lowest, 16, 1)
	t.check("no time section is built", partOf(calendar, "Time") == nil)
	t.check("no presets row is built", partOf(calendar, "Presets") == nil)
	local actions = calendar:FindFirstChild("Actions")
	t.check(
		"no footer shows for a single date without draft",
		actions == nil or not actions.Visible,
		actions and actions.Visible
	)
end)

add("dtp-paint", { "post-pickers-148" }, function(t)
	local package = t.themes[1].package
	for _, name in { "Dark", "Light" } do
		local palette
		for _, entry in package.style.themes do
			if entry.name == name then
				palette = entry
			end
		end
		if not palette then
			t.check(`{name} palette exists in the Standard theme`, false)
			continue
		end
		local function tone(key: string): Color3
			local rgb = palette.colors[key] or (palette.extra and palette.extra[key])
			return Color3.new(rgb.r, rgb.g, rgb.b)
		end
		local today = { year = 2026, month = 12, day = 9 }
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Column" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(760, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 24),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Host.Frame "SpanBox" {
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(360, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.DateTimePicker("Span")(rangeSpec(Compose, {
						style = "inline",
						today = today,
						min = { year = 2026, month = 12, day = 2 },
						range = {
							start = { year = 2026, month = 12, day = 5 },
							finish = { year = 2026, month = 12, day = 20 },
						},
					})),
				},
				Host.Frame "SingleBox" {
					LayoutOrder = 2,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(360, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.DateTimePicker("Single")(singleSpec(Compose, {
						style = "inline",
						today = today,
						value = { year = 2026, month = 12, day = 12 },
					})),
				},
			}
		end, { palette = name, frames = 20 })
		local spanDays = partOf(partOf(t.find(stage, "Span"), "Pane1"), "Days")
		local singleDays = partOf(partOf(t.find(stage, "Single"), "Pane1"), "Days")
		if
			not found(
				t,
				`{name}: both day grids were found`,
				{ "span", "single" },
				{ span = spanDays, single = singleDays }
			)
		then
			t.cleanup()
			continue
		end
		local function cell(days: any, day: number, month: number?): any
			for index, date in t.Facet.civilDate.monthGrid(2026, 12, 1) do
				if date.month == (month or 12) and date.day == day then
					return days:FindFirstChild(`D{index}`)
				end
			end
			return nil
		end
		local function layer(days: any, day: number, part: string, month: number?): any
			local node = cell(days, day, month)
			return if node then partOf(node, part) else nil
		end
		for _, day in { 5, 20 } do
			local disc, number = layer(spanDays, day, "Disc"), layer(spanDays, day, "Day")
			t.check(
				`{name} Dec {day}: the range end shows its disc`,
				disc ~= nil and disc.Visible,
				disc and disc.Visible
			)
			if disc and number then
				t.check(
					`{name} Dec {day}: the end disc is content coloured`,
					sameColor(styled(disc, "BackgroundColor3"), tone("content")),
					styled(disc, "BackgroundColor3")
				)
				t.check(
					`{name} Dec {day}: the end numeral is surface coloured`,
					sameColor(styled(number, "TextColor3"), tone("surface")),
					styled(number, "TextColor3")
				)
			end
		end
		local band = layer(spanDays, 9, "Band")
		if band then
			t.check(`{name} Dec 9: the band shows inside the range`, band.Visible, band.Visible)
			local leading, trailing = band:FindFirstChild("Leading"), band:FindFirstChild("Trailing")
			t.check(
				`{name} Dec 9: both band halves show mid-week`,
				leading and trailing and leading.Visible and trailing.Visible,
				{
					leading and leading.Visible,
					trailing and trailing.Visible,
				}
			)
			if leading then
				t.check(
					`{name} Dec 9: the band is controlSelected`,
					sameColor(styled(leading, "BackgroundColor3"), tone("controlSelected")),
					styled(leading, "BackgroundColor3")
				)
			end
		else
			t.check(`{name} Dec 9 band found`, false)
		end
		for _, edge in
			{
				{ day = 6, half = "Leading" },
				{ day = 12, half = "Trailing" },
				{ day = 13, half = "Leading" },
				{ day = 19, half = "Trailing" },
			}
		do
			local cap = layer(spanDays, edge.day, "Cap")
			local b = layer(spanDays, edge.day, "Band")
			local half = if b then b:FindFirstChild(edge.half) else nil
			t.check(
				`{name} Dec {edge.day}: the band rounds at the week edge`,
				cap ~= nil and cap.Visible and half ~= nil and not half.Visible,
				{
					cap = cap and cap.Visible,
					half = half and half.Visible,
				}
			)
		end
		local inMonth, outside = layer(spanDays, 9, "Day"), layer(spanDays, 29, "Day", 11)
		if inMonth and outside then
			local strong, dim = styled(inMonth, "FontFace"), styled(outside, "FontFace")
			t.check(
				`{name}: days of the shown month are SemiBold`,
				strong.Weight == Enum.FontWeight.SemiBold,
				tostring(strong.Weight)
			)
			t.check(
				`{name}: a neighbour's days are Regular`,
				dim.Weight == Enum.FontWeight.Regular,
				tostring(dim.Weight)
			)
			t.check(
				`{name}: a neighbour's days are dim`,
				sameColor(styled(outside, "TextColor3"), tone("contentSecondary")),
				styled(outside, "TextColor3")
			)
		else
			t.check(`{name}: Dec 9 and Nov 29 numerals found`, false)
		end
		local strike = layer(spanDays, 1, "Strike")
		t.check(
			`{name} Dec 1: an unavailable day shows the strike line`,
			strike ~= nil and strike.Visible,
			strike and strike.Visible
		)
		local ring = layer(spanDays, 9, "Today")
		t.check(`{name} Dec 9: today shows its ring`, ring ~= nil and ring.Visible, ring and ring.Visible)
		if ring then
			local stroke = ring:FindFirstChildWhichIsA("UIStroke")
			t.note(
				`{name} today ring stroke colour`,
				if stroke then tostring(styled(stroke, "Color")) else "no UIStroke child"
			)
		end
		local disc, number = layer(singleDays, 12, "Disc"), layer(singleDays, 12, "Day")
		t.check(
			`{name} single Dec 12: the chosen day shows its disc`,
			disc ~= nil and disc.Visible,
			disc and disc.Visible
		)
		if disc and number then
			t.check(
				`{name} single: the chosen disc is accent`,
				sameColor(styled(disc, "BackgroundColor3"), tone("accent")),
				styled(disc, "BackgroundColor3")
			)
			t.check(
				`{name} single: the chosen numeral is onAccent`,
				sameColor(styled(number, "TextColor3"), tone("onAccent")),
				styled(number, "TextColor3")
			)
		end
		t.cleanup()
	end
end)

interactive(
	"dtp-menu-centred",
	{ "post-pickers-139" },
	"afterReturn: press Return once (the Year menu button holds the selection)",
	function(t)
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Holder" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(360, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				UI.DateTimePicker("Date")(singleSpec(Compose, { style = "inline" })),
			}
		end, { frames = 20 })
		local year = t.find(stage, "Year")
		local value = { layer = layerOf(stage), year = year }
		if not found(t, "the Year menu button was found", { "year" }, { year = year }) then
			return value
		end
		GuiService.SelectedObject = year
		t.settle(4)
		t.check("the Year button holds the selection", GuiService.SelectedObject == year, selectedName())
		t.note(
			"gamepad",
			"ButtonA arrives as keyboard input; Return drives the same native activation of the selected button"
		)
		return value
	end,
	{
		afterReturn = function(t, value)
			t.settle(10)
			local panel = visibleNamed(t, value.layer, "MenuPanel")
			if not panel then
				t.check("the Year menu opened", false)
				return
			end
			t.stable(panel)
			local rows = partOf(panel, "MenuRows")
			local count = 0
			if rows then
				for _, child in rows:GetChildren() do
					if child:IsA("GuiButton") then
						count += 1
					end
				end
			end
			t.note("year rows", count)
			local selected = GuiService.SelectedObject
			t.check(
				"the shown year 2026 holds the selection",
				selected ~= nil and selected.Name == "2026",
				selectedName()
			)
			if selected then
				local p, s = panel.AbsolutePosition, t.rect(selected)
				local bottom = p.Y + panel.AbsoluteWindowSize.Y
				t.check("the 2026 row is scrolled into view", s.y >= p.Y - 0.5 and s.b <= bottom + 0.5, {
					row = { s.y, s.b },
					window = { p.Y, bottom },
				})
			end
			t.inside("the Year menu stays inside the screen", panel, value.layer, 1)
			GuiService.SelectedObject = nil
		end,
	}
)

local function contentStart(t: any, row: any): number
	local left = math.huge
	for _, node in row:GetDescendants() do
		if node:IsA("GuiObject") and t.visible(node) and node.AbsoluteSize.X > 0.5 and node.AbsoluteSize.Y > 0.5 then
			local text = (node:IsA("TextLabel") and node.ContentText ~= "")
			local skinned = node:FindFirstAncestor("SkinBoundary") ~= nil or node.Name == "SkinBoundary"
			if not skinned and (text or node:IsA("ImageLabel") or node.Name == "Indicator") then
				left = math.min(left, node.AbsolutePosition.X)
			end
		end
	end
	return left
end

local function labelX(row: any, words: string): number?
	for _, node in row:GetDescendants() do
		if node:IsA("TextLabel") and node.ContentText == words then
			return node.AbsolutePosition.X
		end
	end
	return nil
end

add("toggle-row-align", { "post-pickers-097", "post-pickers-133" }, function(t)
	for _, themeName in { "Neutral", "PixelQuest", "FantasyOrnate" } do
		local package = themeNamed(t, themeName)
		if not package then
			t.note(`{themeName}`, "theme package is not in ReplicatedStorage.FacetThemes; skipped")
			continue
		end
		local stage = scenario(t, "action_controls", Vector2.new(932, 900), package)
		local rows = {
			{ node = t.find(stage, "Equipment"), words = "Manage equipment" },
			{ node = t.find(stage, "Assist"), words = "Driving assistance" },
			{ node = t.find(stage, "Music"), words = "Music volume" },
		}
		if
			not found(
				t,
				`{themeName}: the Button, Toggle and Slider rows were found`,
				{ "button", "toggle", "slider" },
				{
					button = rows[1].node,
					toggle = rows[2].node,
					slider = rows[3].node,
				}
			)
		then
			t.cleanup()
			continue
		end
		t.stable(rows[3].node)
		local starts, labels = {}, {}
		for index, row in rows do
			starts[index] = contentStart(t, row.node)
			labels[index] = labelX(row.node, row.words) or -1
		end
		t.note(`{themeName} content start x`, starts)
		t.note(`{themeName} label x`, labels)
		t.check(
			`{themeName}: the three rows start their icon column at the same x`,
			math.abs(starts[1] - starts[2]) <= 1 and math.abs(starts[1] - starts[3]) <= 1,
			starts
		)
		t.check(
			`{themeName}: the three rows start their labels at the same x`,
			math.abs(labels[1] - labels[2]) <= 1 and math.abs(labels[1] - labels[3]) <= 1,
			labels
		)
		local toggle = rows[2].node
		t.check(
			`{themeName}: the switch row shows no plate at rest`,
			styled(toggle, "BackgroundTransparency") >= 0.99,
			styled(toggle, "BackgroundTransparency")
		)
		GuiService.SelectedObject = toggle
		t.settle(6)
		t.check(
			`{themeName}: the switch row shows no plate when selected`,
			styled(toggle, "BackgroundTransparency") >= 0.99,
			styled(toggle, "BackgroundTransparency")
		)
		GuiService.SelectedObject = nil
		t.cleanup()
	end
	t.note("not checked", "the hover state needs a pointer over the row")
end)

interactive(
	"chip-edit-live",
	{ "post-pickers-075", "post-pickers-079" },
	"afterDelete: press Delete or ButtonX once (the Friends chip holds the selection)",
	function(t)
		local value: any = {}
		local stage = t.mount(function(UI, Host, Compose)
			value.tokens = Compose.cell({ "Rain", "No assists", "Friends" })
			local editing = Compose.cell(true)
			local chosen = Compose.cell({})
			return Host.ScrollingFrame "Tokens" {
				Position = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(700, 60),
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 6,
				Host.Frame "Row" {
					BackgroundTransparency = 1,
					Size = UDim2.new(),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					Compose.OrderedCollection({
						from = value.tokens,
						key = function(item)
							return item
						end,
						render = function(current)
							local item = current:peek()
							return UI.Chip(item)({
								label = item,
								controlSize = "compact",
								selected = function(use)
									return use(chosen)[item] == true
								end,
								onToggle = function(next)
									local copy = table.clone(chosen:peek())
									copy[item] = next
									chosen:set(copy)
								end,
								editing = editing,
								onRemove = function()
									local rest = {}
									for _, entry in value.tokens:peek() do
										if entry ~= item then
											table.insert(rest, entry)
										end
									end
									value.tokens:set(rest)
								end,
							})
						end,
					}),
				},
			}
		end, { size = Vector2.new(800, 200), frames = 20 })
		local row = t.find(stage, "Row")
		if not found(t, "the chip row was found", { "row" }, { row = row }) then
			return value
		end
		t.stable(row)
		for _, name in { "Rain", "No assists", "Friends" } do
			local chip = row:FindFirstChild(name)
			local mark = partOf(chip, "Remove")
			if
				not found(
					t,
					`{name} chip and its Remove mark were found`,
					{ "chip", "mark" },
					{ chip = chip, mark = mark }
				)
			then
				continue
			end
			t.check(`{name}: the Remove mark shows while editing`, t.visible(mark), mark.Visible)
			t.inside(`{name}: the Remove mark lies inside the chip`, mark, chip, 0.5)
			local stops = {}
			for _, node in chip:GetDescendants() do
				if node:IsA("GuiObject") and node.Selectable then
					table.insert(stops, node.Name)
				end
			end
			t.check(`{name}: the chip keeps one selection stop`, chip.Selectable and #stops == 0, stops)
		end
		GuiService.SelectedObject = row:FindFirstChild("Friends")
		t.settle(4)
		t.check("the last chip Friends holds the selection", selectedName() == "Friends", selectedName())
		t.note("removal key", "the driver presses Delete or ButtonX; live.press records the delivered input")
		return value
	end,
	{
		afterDelete = function(t, value)
			t.settle(6)
			local tokens = value.tokens:peek()
			t.check("Delete removes exactly one chip", #tokens == 2, tokens)
			t.check("the removed chip is Friends", table.find(tokens, "Friends") == nil, tokens)
			t.check("the new last chip No assists takes the selection", selectedName() == "No assists", selectedName())
			GuiService.SelectedObject = nil
		end,
	}
)

add("picker-field-live", { "post-pickers-045", "post-pickers-082" }, function(t)
	local stage, built = scenario(t, "selection_controls", Vector2.new(1280, 720))
	local driver = t.find(stage, "Driver")
	local control = partOf(driver, "Control")
	local label = if control then control:FindFirstChild("Label") or partOf(control, "Label") else nil
	local trigger = partOf(control, "Trigger")
	if
		not found(
			t,
			"Driver has Control, Label and Trigger",
			{ "control", "label", "trigger" },
			{ control = control, label = label, trigger = trigger }
		)
	then
		return
	end
	t.stable(trigger)
	local l, tr = t.rect(label), t.rect(trigger)
	t.check("the Trigger sits below the Label", tr.y >= l.b - 0.5, { trigger = tr.y, label = l.b })
	t.near("the Trigger starts at the Label left edge", tr.x, l.x, 1)
	t.check("the Trigger is narrower than 400 px", tr.w < 400, tr.w)
	t.check("the required mark rides the label", string.sub(label.ContentText, -2) == " *", label.ContentText)
	local result = built.steps.driverError()
	t.settle(6)
	t.stable(trigger)
	t.check("the error is on", result.error ~= "", result)
	t.check(
		"the error does not move the Trigger",
		sameRect(t.rect(trigger), tr),
		{ before = tr, after = t.rect(trigger) }
	)
	t.check("the Trigger takes the danger paint", trigger:HasTag("facet-invalid"), trigger:GetTags())
	local words = partOf(driver, "Validation")
	t.check(
		"the error replaces the hint",
		words ~= nil and words.ContentText == result.error,
		words and words.ContentText
	)
	local stroke = trigger:FindFirstChildWhichIsA("UIStroke", true)
	t.note(
		"trigger stroke colour with the error",
		if stroke then tostring(styled(stroke, "Color")) else "no UIStroke instance"
	)
	built.steps.driverError()
	t.settle(6)
	t.check("clearing the error removes the danger paint", not trigger:HasTag("facet-invalid"), trigger:GetTags())
end)

local DRIVER_NAMES = { "Ada", "Bo", "Cy", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kai", "Lu" }

local function driverPicker(t: any, first: string, value: any): any
	return t.mount(function(UI, _, Compose)
		local options = {}
		for i, name in DRIVER_NAMES do
			table.insert(options, {
				value = "d" .. i,
				label = name,
				avatar = { name = name },
				badge = if i == 2 then 3 else nil,
				sectionTitle = if i == 1 then "Crew" elseif i == 5 then "Rivals" else nil,
			})
		end
		value.driver = Compose.cell(first)
		value.open = Compose.cell(false)
		value.changes = 0
		return UI.Picker "Driver" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(400, 0),
			label = "Driver",
			requiredMark = "required",
			hint = "Who takes the wheel for this race.",
			style = "menu",
			maxHeight = 220,
			selected = value.driver,
			options = options,
			isPresented = value.open,
			onChange = function()
				value.changes += 1
			end,
		}
	end, { size = Vector2.new(1280, 720), frames = 20 })
end

add("picker-menu-scroll-live", { "post-pickers-049", "post-pickers-051", "post-pickers-085" }, function(t)
	local value: any = {}
	local stage = driverPicker(t, "d10", value)
	local trigger = t.find(stage, "Trigger")
	GuiService.SelectedObject = trigger
	value.open:set(true)
	t.settle(20)
	local panel = visibleNamed(t, stage, "MenuPanel")
	if not found(t, "the Driver menu opened", { "panel" }, { panel = panel }) then
		return
	end
	t.stable(panel)
	local p = t.rect(panel)
	t.check("the menu panel is at most 220 px tall", p.h <= 220.5, p.h)
	t.check("the rows scroll inside the panel", panel.AbsoluteCanvasSize.Y > panel.AbsoluteWindowSize.Y + 0.5, {
		canvas = panel.AbsoluteCanvasSize.Y,
		window = panel.AbsoluteWindowSize.Y,
	})
	local rows = partOf(panel, "MenuRows")
	local cut = {}
	for i, name in DRIVER_NAMES do
		local row = if rows then rows:FindFirstChild("d" .. i) else nil
		local words = nil
		if row then
			for _, node in row:GetDescendants() do
				if node:IsA("TextLabel") and node.ContentText == name then
					words = node
				end
			end
		end
		if not row or not words then
			table.insert(cut, `{name} missing`)
		elseif not t.fits(words) or t.rect(words).r > p.r - panel.ScrollBarThickness + 0.5 then
			table.insert(cut, { name, words.TextBounds, words.AbsoluteSize, t.rect(words).r, p.r })
		end
	end
	t.check("every avatar row keeps its name visible with the scroll bar reserved", #cut == 0, cut)
	local selected = GuiService.SelectedObject
	t.check("the chosen row d10 holds the selection", selected ~= nil and selected.Name == "d10", selectedName())
	if selected then
		local s = t.rect(selected)
		local bottom = p.y + panel.AbsoluteWindowSize.Y
		t.check("the chosen row is scrolled into view", s.y >= p.y - 0.5 and s.b <= bottom + 0.5, {
			row = { s.y, s.b },
			window = { p.y, bottom },
		})
	end
	t.inside("the menu stays inside the screen", panel, stage, 1)
	value.open:set(false)
	GuiService.SelectedObject = nil
	t.note("not checked", "mouse and touch opening routes; this case opens the menu through isPresented")
end)

interactive(
	"pickers-avatar-row-press",
	{ "post-pickers-053" },
	"afterClick: left-click once at the screen point noted as avatar (the avatar circle of the second row, Bo)",
	function(t)
		local value: any = {}
		local stage = driverPicker(t, "d3", value)
		value.open:set(true)
		t.settle(20)
		local panel = visibleNamed(t, stage, "MenuPanel")
		local row = if panel then partOf(panel, "d2") else nil
		local avatar = partOf(row, "Avatar")
		if
			not found(
				t,
				"the open menu, row d2 and its Avatar were found",
				{ "panel", "row", "avatar" },
				{ panel = panel, row = row, avatar = avatar }
			)
		then
			return value
		end
		t.stable(panel)
		GuiService.SelectedObject = nil
		t.settle(2)
		local selectable = {}
		for _, node in avatar:GetDescendants() do
			if node:IsA("GuiObject") and node.Selectable then
				table.insert(selectable, node.Name)
			end
		end
		t.check("the avatar never takes gamepad selection", not avatar.Selectable and #selectable == 0, selectable)
		local seen = t.clipped(avatar)
		t.check("the avatar of row d2 is visible in the panel", seen ~= nil, seen)
		t.note("avatar", point(avatar))
		t.note("not checked", "touch tap and gamepad A are not driven; the mouse click proves the press passes through")
		return value
	end,
	{
		afterClick = function(t, value)
			t.settle(8)
			t.check("the click on the avatar selects row d2", value.driver:peek() == "d2", value.driver:peek())
			t.check("the row is selected once", value.changes == 1, value.changes)
			t.check("the menu closes after the choice", value.open:peek() == false, value.open:peek())
		end,
	}
)

add("picker-cards-live", { "post-pickers-062" }, function(t)
	local stage = scenario(t, "selection_controls", Vector2.new(390, 844))
	local mode = t.find(stage, "Mode")
	local cards: { [string]: any } = {}
	for _, key in { "sprint", "endurance", "night" } do
		cards[key] = partOf(mode, "Card-" .. key)
	end
	if not found(t, "the three race cards were found", { "sprint", "endurance", "night" }, cards) then
		return
	end
	t.stable(cards.night)
	local rows = {}
	for key, card in cards do
		local r = t.rect(card)
		rows[math.floor(r.y + 0.5)] = true
		t.check(`{key} card stays inside the 390 px screen`, r.x >= -0.5 and r.r <= 390.5, { r.x, r.r })
		local description = partOf(card, "Description")
		if description then
			t.inside(`{key} description lies inside its card`, description, card, 1)
			t.check(
				`{key} description text fits its box`,
				t.fits(description),
				{ description.TextBounds, description.AbsoluteSize }
			)
		else
			t.check(`{key} description found`, false)
		end
	end
	local count = 0
	for _ in rows do
		count += 1
	end
	t.check("the cards wrap onto more than one line", count > 1, count)
end)

add("picker-segmented-live", { "post-pickers-058" }, function(t)
	for _, themeName in { "Neutral", "PixelQuest" } do
		local package = themeNamed(t, themeName)
		if not package then
			t.note(`{themeName}`, "theme package is not in ReplicatedStorage.FacetThemes; skipped")
			continue
		end
		local stage = scenario(t, "selection_controls", Vector2.new(1280, 720), package)
		local strip = t.find(stage, "Laps")
		local segments = {}
		for _, key in { "3", "5", "10" } do
			segments[key] = if strip then strip:FindFirstChild(key) else nil
		end
		if
			not found(
				t,
				`{themeName}: the lap strip and its three segments were found`,
				{ "strip", "three", "five", "ten" },
				{
					strip = strip,
					three = segments["3"],
					five = segments["5"],
					ten = segments["10"],
				}
			)
		then
			t.cleanup()
			continue
		end
		t.stable(strip)
		local list = { segments["3"], segments["5"], segments["10"] }
		for _, segment in list do
			t.check(
				`{themeName} segment {segment.Name} is shorter than 44 px`,
				segment.AbsoluteSize.Y < 44,
				segment.AbsoluteSize.Y
			)
			t.check(
				`{themeName} segment {segment.Name} is at least 44 px wide`,
				segment.AbsoluteSize.X >= 43.5,
				segment.AbsoluteSize.X
			)
		end
		for index = 1, 2 do
			t.check(
				`{themeName}: segments {list[index].Name} and {list[index + 1].Name} do not share a pixel`,
				not overlap(t.rect(list[index]), t.rect(list[index + 1])),
				{ t.rect(list[index]).r, t.rect(list[index + 1]).x }
			)
		end
		t.check(
			`{themeName}: the strip reserves a whole 44 px target`,
			strip.AbsoluteSize.Y >= 43.5,
			strip.AbsoluteSize.Y
		)
		local corners = strip:FindFirstChild("Corners")
		t.check(
			`{themeName}: the strip has pill ends`,
			corners ~= nil and corners.CornerRadius.Scale == 1,
			corners and corners.CornerRadius
		)
		t.check(`{themeName}: the strip is stroked`, strip:HasTag("facet-segmented-stroke"), strip:GetTags())
		t.check(
			`{themeName}: the selected segment 5 is marked current`,
			segments["5"]:HasTag("facet-segment-current"),
			segments["5"]:GetTags()
		)
		local fill = segments["5"]:FindFirstChildWhichIsA("UICorner")
		t.note(
			`{themeName} selected segment corner`,
			if fill then fill.CornerRadius else "no UICorner instance; read the StyleSheet rule"
		)
		t.cleanup()
	end
	t.note("not checked", "the hairline stroke weight and the fill silhouette are paint; confirm on a screen capture")
end)

local ALL_MODES = { "swatches", "spectrum", "sliders", "brick" }
local SHOWS = { "ShowSwatches", "ShowSpectrum", "ShowSliders", "ShowBricks" }

local function rotated(first: number): { string }
	local out = {}
	for index = 0, #ALL_MODES - 1 do
		table.insert(out, ALL_MODES[(first - 1 + index) % #ALL_MODES + 1])
	end
	return out
end

local function colorSpec(Compose: any, extra: { [string]: any }): (any, any)
	local value = Compose.cell(extra.value or Color3.fromRGB(46, 125, 255))
	local spec: { [string]: any } = {
		value = value,
		onChange = function(next: any)
			value:set(next)
		end,
	}
	if extra.alpha then
		local alpha = Compose.cell(1)
		spec.alpha = alpha
		spec.onAlphaChange = function(next: any)
			alpha:set(next)
		end
	end
	for key, item in extra do
		if key ~= "value" and key ~= "alpha" then
			spec[key] = item
		end
	end
	return spec, value
end

local function openPanel(t: any, layer: any): any
	t.settle(12)
	local modal = visibleNamed(t, layer, "ColorPickerModal")
	local panel = if modal then visibleNamed(t, modal, "Panel") else nil
	if panel then
		t.stable(panel)
	end
	return panel
end

add("color-hidden-technique-size", { "post-pickers-169" }, function(t)
	for _, screen in
		{
			{ name = "900x900 pointer", device = { device = "xbox", width = 900, height = 900 } },
			{
				name = "390x844 touch",
				device = { device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait },
			},
		}
	do
		t.device(screen.device)
		local opens = {}
		local stage = t.mount(function(UI, Host, Compose)
			local children: { any } = {
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 16),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			}
			for index = 1, 4 do
				opens[index] = Compose.cell(false)
				table.insert(
					children,
					UI.ColorPicker(`Well{index}`)((colorSpec(Compose, {
						LayoutOrder = index,
						modes = rotated(index),
						isPresented = opens[index],
					})))
				)
			end
			return Host.Frame "Wells" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 16),
				Size = UDim2.new(1, -32, 0, 44),
				table.unpack(children),
			}
		end, { frames = 20 })
		local layer = layerOf(stage)
		local panels, bodies = {}, {}
		for index = 1, 4 do
			opens[index]:set(true)
			local panel = openPanel(t, layer)
			local body = partOf(panel, "Body")
			local technique = partOf(panel, "Technique")
			if
				found(
					t,
					`{screen.name} tab {ALL_MODES[index]}: Panel, Body and Technique were found`,
					{ "panel", "body", "technique" },
					{
						panel = panel,
						body = body,
						technique = technique,
					}
				)
			then
				local tallest, sizes = 0, {}
				for _, name in SHOWS do
					local show = technique:FindFirstChild(name)
					local height = if show then show.AbsoluteSize.Y else -1
					sizes[name] = { height = height, visible = show and show.Visible }
					tallest = math.max(tallest, height)
					t.check(
						`{screen.name} tab {ALL_MODES[index]}: {name} reports a height while {if show
								and show.Visible
							then "shown"
							else "hidden"}`,
						height > 0.5,
						height
					)
				end
				t.near(
					`{screen.name} tab {ALL_MODES[index]}: Technique keeps the tallest technique's height`,
					technique.AbsoluteSize.Y,
					tallest,
					1
				)
				panels[index], bodies[index] = panel.AbsoluteSize.Y, body.AbsoluteSize.Y
				t.note(
					`{screen.name} tab {ALL_MODES[index]} heights`,
					{ panel = panel.AbsoluteSize.Y, body = body.AbsoluteSize.Y, shows = sizes }
				)
			end
			opens[index]:set(false)
			t.settle(8)
		end
		local steady = #panels == 4
		for index = 2, #panels do
			steady = steady and math.abs(panels[index] - panels[1]) <= 1 and math.abs(bodies[index] - bodies[1]) <= 1
		end
		t.check(
			`{screen.name}: a tab switch never resizes the panel or its body`,
			steady,
			{ panels = panels, bodies = bodies }
		)
		t.cleanup()
	end
	t.note("tab switch", "each tab is shown by opening a well whose first mode is that tab; the mode set is the same")
end)

add("color-placement-real-layout", { "post-pickers-165", "post-pickers-167", "post-pickers-168" }, function(t)
	for _, screen in { Vector2.new(1542, 1044), Vector2.new(1542, 560) } do
		local where = `{screen.X}x{screen.Y}`
		pointerScreen(t, screen.X, screen.Y)
		local opens, names = {}, {}
		local stage = t.mount(function(UI, Host, Compose)
			local children: { any } = {}
			for _, spot in
				{
					{ name = "Top", anchor = Vector2.new(0, 0), y = UDim.new(0, 16) },
					{ name = "Middle", anchor = Vector2.new(0, 0.5), y = UDim.new(0.5, 0) },
					{ name = "Bottom", anchor = Vector2.new(0, 1), y = UDim.new(1, -16) },
				}
			do
				for _, kind in { "Labelled", "Bare" } do
					local name = kind .. spot.name
					opens[name] = Compose.cell(false)
					table.insert(names, name)
					table.insert(
						children,
						Host.Frame({
							Name = name .. "Box",
							BackgroundTransparency = 1,
							AnchorPoint = spot.anchor,
							Position = UDim2.new(
								if kind == "Labelled" then 0 else 0.5,
								16,
								spot.y.Scale,
								spot.y.Offset
							),
							Size = UDim2.fromOffset(if kind == "Labelled" then 360 else 44, 44),
							UI.ColorPicker(name)((colorSpec(Compose, {
								label = if kind == "Labelled" then "Kart body" else nil,
								modes = ALL_MODES,
								alpha = true,
								isPresented = opens[name],
							}))),
						})
					)
				end
			end
			return Host.Frame "Screen" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				table.unpack(children),
			}
		end, { frames = 20 })
		local layer = layerOf(stage)
		for _, name in names do
			local root = t.find(stage, name)
			local well = partOf(root, "Well")
			if not well then
				t.check(`{where} {name}: Well found`, false)
				continue
			end
			if string.sub(name, 1, 4) == "Bare" then
				t.check(
					`{where} {name}: the bare well is at least 44x44`,
					well.AbsoluteSize.X >= 43.5 and well.AbsoluteSize.Y >= 43.5,
					well.AbsoluteSize
				)
			else
				t.check(
					`{where} {name}: the labelled well is at least 44 px tall`,
					well.AbsoluteSize.Y >= 43.5,
					well.AbsoluteSize
				)
			end
			opens[name]:set(true)
			local panel = openPanel(t, layer)
			if panel then
				local placement = root:GetAttribute("placement")
				t.note(`{where} {name} placement`, { placement, t.rect(panel) })
				t.check(`{where} {name}: the panel never covers its well`, not overlap(t.rect(panel), t.rect(well)), {
					panel = t.rect(panel),
					well = t.rect(well),
				})
				t.inside(`{where} {name}: the panel stays inside the screen`, panel, layer, 1)
				if t.rect(layer).h < 600 and name == "BareMiddle" then
					t.check(
						`{where} {name}: the bare middle well opens beside`,
						placement == "left" or placement == "right",
						placement
					)
				end
				local body = partOf(panel, "Body")
				if body then
					t.note(`{where} {name} body scrolls`, body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y + 0.5)
				end
			else
				t.check(`{where} {name}: the panel opened`, false)
			end
			opens[name]:set(false)
			t.settle(8)
		end
		t.cleanup()
	end
end)

interactive(
	"color-grid-wraps-two-dimensions",
	{ "post-pickers-171" },
	"afterDown: press the Down arrow key once; afterRight: press the Right arrow key once",
	function(t)
		t.device({ device = "xbox", width = 900, height = 900 })
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Box" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(44, 44),
				UI.ColorPicker("Well")(
					(colorSpec(Compose, { modes = { "swatches" }, isPresented = openLater(Compose) }))
				),
			}
		end, { frames = 20 })
		openNow(t)
		local panel = openPanel(t, layerOf(stage))
		local grid = partOf(panel, "Swatches")
		local value: any = { cells = {} }
		if not found(t, "the swatch grid was found", { "panel", "grid" }, { panel = panel, grid = grid }) then
			return value
		end
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") then
				table.insert(value.cells, child)
			end
		end
		table.sort(value.cells, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local cells = value.cells
		t.check("the default grid has at least 12 swatches", #cells >= 12, #cells)
		if #cells < 12 then
			return value
		end
		t.near("the grid is 8 cells and 7 gaps wide", grid.AbsoluteSize.X, 8 * 44 + 7 * 4, 0.5)
		local rowOne = true
		for index = 2, 8 do
			rowOne = rowOne and math.abs(cells[index].AbsolutePosition.Y - cells[1].AbsolutePosition.Y) <= 0.5
		end
		t.check("the first 8 cells share one row", rowOne)
		t.check(
			"the 9th cell starts the second row",
			math.abs(cells[9].AbsolutePosition.X - cells[1].AbsolutePosition.X) <= 0.5
		)
		t.near("the rows are 4 px apart", cells[9].AbsolutePosition.Y - t.rect(cells[1]).b, 4, 0.5)
		GuiService.SelectedObject = cells[3]
		t.settle(4)
		t.check("cell 3 holds the selection", GuiService.SelectedObject == cells[3], selectedName())
		t.note("targets", { three = cells[3].Name, eleven = cells[11].Name, twelve = cells[12].Name })
		t.note("gamepad", "D-pad movement is proven with the arrow keys, which drive the same native selection")
		return value
	end,
	{
		afterDown = function(t, value)
			t.check(
				"Down from cell 3 selects cell 11",
				value.cells[11] ~= nil and GuiService.SelectedObject == value.cells[11],
				selectedName()
			)
		end,
		afterRight = function(t, value)
			t.check(
				"Right from cell 11 selects cell 12",
				value.cells[12] ~= nil and GuiService.SelectedObject == value.cells[12],
				selectedName()
			)
			GuiService.SelectedObject = nil
		end,
	}
)

local function strokeOf(node: any): any
	for _, child in node:GetChildren() do
		if child:IsA("UIStroke") then
			return child
		end
	end
	return nil
end

add("color-plane-layers-and-ring", { "post-pickers-188", "post-pickers-179" }, function(t)
	local value
	local stage = t.mount(function(UI, Host, Compose)
		local spec
		spec, value = colorSpec(Compose, { label = "Accent", style = "inline", modes = { "spectrum" }, alpha = true })
		return Host.Frame "Box" {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(360, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			UI.ColorPicker("Accent")(spec),
		}
	end, { frames = 20 })
	local root = t.find(stage, "Accent")
	local plane = partOf(root, "Plane")
	local fieldNode = if plane then plane:FindFirstChild("Field") else nil
	local hue = if fieldNode then fieldNode:FindFirstChild("Hue") else nil
	local shade = if fieldNode then fieldNode:FindFirstChild("Value") else nil
	local surface = if plane then plane:FindFirstChild("Surface") else nil
	local ring = if plane then plane:FindFirstChild("Ring") else nil
	if
		not found(t, "the plane layers, Surface and Ring were found", { "plane", "hue", "shade", "surface", "ring" }, {
			plane = plane,
			hue = hue,
			shade = shade,
			surface = surface,
			ring = ring,
		})
	then
		return
	end
	t.stable(plane)
	local across = hue:FindFirstChildWhichIsA("UIGradient")
	local down = shade:FindFirstChildWhichIsA("UIGradient")
	local h = value:peek():ToHSV()
	local pure = Color3.fromHSV(h, 1, 1)
	if across and down then
		local keys = across.Color.Keypoints
		t.check(
			"the across layer runs white to the hue",
			sameColor(keys[1].Value, Color3.new(1, 1, 1)) and sameColor(keys[#keys].Value, pure),
			{
				tostring(keys[1].Value),
				tostring(keys[#keys].Value),
				tostring(pure),
			}
		)
		t.check(
			"the across layer is horizontal with two stops",
			across.Rotation == 0 and #keys == 2,
			{ across.Rotation, #keys }
		)
		local fade = down.Transparency.Keypoints
		t.check(
			"the down layer is black fading from transparent at the top to opaque at the bottom",
			down.Rotation == 90
				and sameColor(shade.BackgroundColor3, Color3.new(0, 0, 0))
				and fade[1].Value == 1
				and fade[#fade].Value == 0,
			{ down.Rotation, tostring(shade.BackgroundColor3), fade[1].Value, fade[#fade].Value }
		)
	else
		t.check("both plane layers carry a UIGradient", false)
	end
	t.check("the drag Surface covers the painted plane exactly", sameRect(t.rect(surface), t.rect(plane)), {
		surface = t.rect(surface),
		plane = t.rect(plane),
	})
	for _, case in
		{
			{ name = "46,125,255", color = Color3.fromRGB(46, 125, 255) },
			{ name = "white", color = Color3.new(1, 1, 1) },
			{ name = "pure red", color = Color3.new(1, 0, 0) },
			{ name = "black", color = Color3.new(0, 0, 0) },
		}
	do
		value:set(case.color)
		t.settle(6)
		local p = t.rect(plane)
		local _, s, v = case.color:ToHSV()
		local cx = ring.AbsolutePosition.X + ring.AbsoluteSize.X / 2
		local cy = ring.AbsolutePosition.Y + ring.AbsoluteSize.Y / 2
		t.check(`{case.name}: the ring shows`, ring.Visible, ring.Visible)
		t.inside(`{case.name}: the whole ring stays on the plane`, ring, plane, 0.5)
		t.near(
			`{case.name}: the ring sits over the colour's brightness`,
			cy,
			p.y + math.clamp((1 - v) * p.h, 10, p.h - 10),
			1
		)
		if case.name ~= "black" then
			t.near(
				`{case.name}: the ring sits over the colour's saturation`,
				cx,
				p.x + math.clamp(s * p.w, 10, p.w - 10),
				1
			)
		end
	end
	local rings = t.all(root, "Ring")
	t.check("the plane, hue strip and opacity strip each carry a ring", #rings >= 3, #rings)
	for index, node in rings do
		local outer = strokeOf(node)
		local band = node:FindFirstChild("Band")
		local middle = if band then strokeOf(band) else nil
		local inner = if band then band:FindFirstChild("Inner") else nil
		local hairline = if inner then strokeOf(inner) else nil
		local ok = outer ~= nil
			and middle ~= nil
			and hairline ~= nil
			and sameColor(styled(outer, "Color"), Color3.new(0, 0, 0))
			and styled(outer, "Thickness") == 1
			and sameColor(styled(middle, "Color"), Color3.new(1, 1, 1))
			and styled(middle, "Thickness") == 3
			and sameColor(styled(hairline, "Color"), Color3.new(0, 0, 0))
			and styled(hairline, "Thickness") == 1
		t.check(
			`ring {index} ({node.Parent and node.Parent.Name}) is black hairline, white 3 px band, black hairline`,
			ok,
			{
				outer = outer and { tostring(styled(outer, "Color")), styled(outer, "Thickness") },
				middle = middle and { tostring(styled(middle, "Color")), styled(middle, "Thickness") },
				inner = hairline and { tostring(styled(hairline, "Color")), styled(hairline, "Thickness") },
			}
		)
	end
	t.note(
		"not checked",
		"banding and ring legibility are pixels; a screen capture must confirm them. Drag tracking needs a pointer drag."
	)
end)

add("color-touch-bubble-room", { "post-pickers-183" }, function(t)
	t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, orientation = Enum.ScreenOrientation.Portrait })
	t.note("preferred input", tostring(game:GetService("UserInputService").PreferredInput))
	local inlineValue, sheetValue
	local stage = t.mount(function(UI, Host, Compose)
		local inlineSpec, sheetSpec
		inlineSpec, inlineValue = colorSpec(Compose, { style = "inline", modes = { "spectrum" }, alpha = true })
		sheetSpec, sheetValue =
			colorSpec(Compose, { modes = { "spectrum" }, alpha = true, isPresented = openLater(Compose) })
		return Host.Frame "Column" {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.new(1, -32, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Host.UIListLayout({ Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }),
			Host.Frame "SheetBox" {
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(44, 44),
				UI.ColorPicker("Sheet")(sheetSpec),
			},
			UI.ColorPicker("Inline")(inlineSpec),
		}
	end, { frames = 20 })
	openNow(t)
	local layer = layerOf(stage)
	inlineValue:set(Color3.new(1, 1, 1))
	sheetValue:set(Color3.new(1, 1, 1))
	t.settle(8)
	local sheetModal = visibleNamed(t, layer, "ColorPickerModal")
	local inlineRoot = t.find(stage, "Inline")
	for _, entry in
		{
			{ name = "inline", root = inlineRoot, panel = partOf(inlineRoot, "Panel") },
			{ name = "sheet", root = sheetModal, panel = if sheetModal then partOf(sheetModal, "Panel") else nil },
		}
	do
		if
			not found(t, `{entry.name}: panel found`, { "root", "panel" }, { root = entry.root, panel = entry.panel })
		then
			continue
		end
		t.stable(entry.panel)
		local bubbles = t.all(entry.panel, "Bubble")
		t.check(`{entry.name}: the plane, hue and opacity bubbles exist`, #bubbles >= 3, #bubbles)
		for _, bubble in bubbles do
			local owner = if bubble.Parent then bubble.Parent.Name else "?"
			local b = t.rect(bubble)
			local seen = t.clipped(bubble)
			t.inside(`{entry.name} {owner} bubble at the top edge stays inside the panel`, bubble, entry.panel, 1)
			t.inside(`{entry.name} {owner} bubble stays on screen`, bubble, layer, 1)
			t.check(
				`{entry.name} {owner} bubble is not clipped by the panel body`,
				seen ~= nil and math.abs(seen.w - b.w) <= 0.5 and math.abs(seen.h - b.h) <= 0.5,
				{ bubble = b, seen = seen }
			)
		end
	end
	t.note(
		"measured without a drag",
		"bubbles are laid out while hidden; their Visible needs a touch drag, which the input tools cannot send"
	)
end)

add("color-phone-sheet-apply-on-screen", { "post-pickers-182" }, function(t)
	for _, turn in
		{
			{ name = "portrait", orientation = Enum.ScreenOrientation.Portrait },
			{ name = "landscape", orientation = Enum.ScreenOrientation.LandscapeRight },
		}
	do
		t.device({ device = "iphone_14", input = Enum.PreferredInput.Touch, orientation = turn.orientation })
		local opens = {}
		local stage = t.mount(function(UI, Host, Compose)
			local children: { any } = {
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 16),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			}
			for index, mode in ALL_MODES do
				opens[mode] = Compose.cell(false)
				table.insert(
					children,
					UI.ColorPicker(`Well{index}`)((colorSpec(Compose, {
						LayoutOrder = index,
						modes = { mode },
						draft = true,
						isPresented = opens[mode],
					})))
				)
			end
			return Host.Frame "Wells" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 16),
				Size = UDim2.new(1, -32, 0, 44),
				table.unpack(children),
			}
		end, { frames = 20 })
		local layer = layerOf(stage)
		for index, mode in ALL_MODES do
			local where = `{turn.name} {mode}`
			local root = t.find(stage, `Well{index}`)
			local well = partOf(root, "Well")
			opens[mode]:set(true)
			local panel = openPanel(t, layer)
			local apply = if panel then visibleNamed(t, panel, "Apply") else nil
			local readout = if panel then partOf(panel, "Readout") else nil
			if
				found(
					t,
					`{where}: panel, Apply and Readout were found`,
					{ "panel", "apply", "readout", "well" },
					{ panel = panel, apply = apply, readout = readout, well = well }
				)
			then
				local placement = root:GetAttribute("placement")
				t.note(`{where} placement`, placement)
				t.note(`{where} layer and input`, {
					layer.AbsoluteSize,
					game:GetService("UserInputService").PreferredInput,
				})
				t.inside(`{where}: the panel stays inside the screen`, panel, layer, 1)
				if turn.name == "portrait" then
					t.check(`{where}: the panel is a sheet`, placement == "sheet", placement)
					for _, node in { apply, readout } do
						local seen = t.clipped(node)
						t.check(
							`{where}: {node.Name} is fully on screen`,
							seen ~= nil and math.abs(seen.h - node.AbsoluteSize.Y) <= 0.5,
							seen
						)
						t.inside(`{where}: {node.Name} inside the screen`, node, layer, 1)
					end
					local small = {}
					for _, node in panel:GetDescendants() do
						if
							node:IsA("GuiObject")
							and t.visible(node)
							and t.clipped(node) ~= nil
							and (node:IsA("GuiButton") or node.Name == "Track" or node.Name == "Input" or node.Name == "Surface")
							and (node.AbsoluteSize.X < 43.5 or node.AbsoluteSize.Y < 43.5)
						then
							table.insert(small, { node.Name, node.AbsoluteSize })
						end
					end
					t.check(`{where}: every target is at least 44x44`, #small == 0, small)
				else
					t.check(
						`{where}: the anchored panel does not cover the well`,
						not overlap(t.rect(panel), t.rect(well)),
						{
							panel = t.rect(panel),
							well = t.rect(well),
						}
					)
					local seen = t.clipped(apply)
					t.check(`{where}: Apply is at least 44 px tall`, apply.AbsoluteSize.Y >= 43.5, apply.AbsoluteSize)
					t.check(
						`{where}: Apply is fully on screen`,
						seen ~= nil and math.abs(seen.h - apply.AbsoluteSize.Y) <= 0.5,
						seen
					)
					t.inside(`{where}: Apply inside the screen`, apply, layer, 1)
					local small = {}
					for _, node in panel:GetDescendants() do
						if
							node:IsA("GuiObject")
							and t.visible(node)
							and t.clipped(node) ~= nil
							and (node:IsA("GuiButton") or node.Name == "Track" or node.Name == "Input" or node.Name == "Surface")
							and (node.AbsoluteSize.X < 43.5 or node.AbsoluteSize.Y < 43.5)
						then
							table.insert(small, { node.Name, node.AbsoluteSize })
						end
					end
					t.check(`{where}: every target is at least 44x44`, #small == 0, small)
				end
			end
			opens[mode]:set(false)
			t.settle(8)
		end
		t.cleanup()
	end
end)

local function tenFootCheck(t: any): boolean
	t.device({ device = "xbox", width = 1280, height = 720 })
	local tenFoot = GuiService:IsTenFootInterface()
	t.check("the xbox emulator reports IsTenFootInterface() true", tenFoot, tenFoot)
	return tenFoot
end

local function centred(t: any, name: string, node: any, layer: any)
	local n, l = t.rect(node), t.rect(layer)
	t.check(
		`{name} is centred on the screen`,
		math.abs((n.x + n.w / 2) - (l.x + l.w / 2)) <= 1.5 and math.abs((n.y + n.h / 2) - (l.y + l.h / 2)) <= 1.5
			or (n.h >= l.h - 17 and math.abs((n.x + n.w / 2) - (l.x + l.w / 2)) <= 1.5),
		{
			node = { n.x, n.y, n.w, n.h },
			layer = { l.x, l.y, l.w, l.h },
		}
	)
end

local function scrimOf(t: any, name: string, modal: any, layer: any)
	local catcher = if modal then modal:FindFirstChild("DismissOutside", true) else nil
	if not catcher then
		t.check(`{name} scrim found`, false)
		return
	end
	local shade = styled(catcher, "BackgroundTransparency")
	t.check(`{name} shows a scrim behind the sheet`, shade < 0.95, shade)
	t.inside(`{name} scrim covers the screen`, layer, catcher, 1)
end

add("dtp-ten-foot", { "post-pickers-159" }, function(t)
	if not tenFootCheck(t) then
		return
	end
	local _, root, layer = datePicker(t, function(Compose)
		return singleSpec(Compose, { isPresented = openLater(Compose) })
	end)
	local surface = surfaceOf(t, layer)
	local modal = visibleNamed(t, layer, "CalendarModal")
	local done = if surface then visibleNamed(t, surface, "Done") else nil
	if
		not found(t, "the ten-foot calendar, its modal and Done were found", { "surface", "modal", "done" }, {
			surface = surface,
			modal = modal,
			done = done,
		})
	then
		return
	end
	t.check("the calendar routes to a sheet", root:GetAttribute("route") == "sheet", root:GetAttribute("route"))
	centred(t, "the calendar sheet", surface, layer)
	scrimOf(t, "the calendar", modal, layer)
	t.check("Done is shown and selectable", done.Selectable and t.clipped(done) ~= nil, done.Selectable)
	local selected = GuiService.SelectedObject
	t.check(
		"selection lands inside the calendar",
		selected ~= nil and selected:IsDescendantOf(surface),
		if selected then selected:GetFullName() else "nil"
	)
	GuiService.SelectedObject = nil
	t.note(
		"not checked",
		"B cannot be sent by the input tools, so closing with B and the return of selection to the calendar icon are not checked"
	)
end)

interactive(
	"dtp-ten-foot-pad-open-and-back",
	{ "post-pickers-159", "post-pickers-144", "post-pickers-145" },
	"afterOpen: press ButtonA once (the calendar icon holds the selection); afterBack: press ButtonB once",
	function(t)
		local value: any = {}
		if not tenFootCheck(t) then
			return value
		end
		local stage, root, layer = datePicker(t, function(Compose)
			return singleSpec(Compose, {})
		end)
		value.stage, value.root, value.layer = stage, root, layer
		value.open = if root then visibleNamed(t, root, "Open") else nil
		if not found(t, "the calendar icon was found", { "open" }, { open = value.open }) then
			return value
		end
		GuiService.SelectedObject = value.open
		t.settle(2)
		t.check("the calendar icon holds the selection", GuiService.SelectedObject == value.open, selectedName())
		return value
	end,
	{
		afterOpen = function(t, value)
			t.settle(12)
			local surface = surfaceOf(t, value.layer)
			t.check("ButtonA on the calendar icon opens the calendar", surface ~= nil)
			t.check(
				"the calendar routes to a sheet",
				value.root:GetAttribute("route") == "sheet",
				value.root:GetAttribute("route")
			)
			local selected = GuiService.SelectedObject
			t.check(
				"selection lands inside the calendar",
				surface ~= nil and selected ~= nil and selected:IsDescendantOf(surface),
				if selected then selected:GetFullName() else "nil"
			)
		end,
		afterBack = function(t, value)
			t.settle(12)
			t.check("ButtonB closes the calendar", visibleNamed(t, value.layer, "CalendarSurface") == nil)
			t.check(
				"the selection returns to the calendar icon",
				GuiService.SelectedObject == value.open,
				selectedName()
			)
			GuiService.SelectedObject = nil
		end,
	}
)

interactive(
	"color-ten-foot-pad-open-and-back",
	{ "post-pickers-178" },
	"afterOpen: press ButtonA once (the well holds the selection); afterBack: press ButtonB once",
	function(t)
		local value: any = {}
		if not tenFootCheck(t) then
			return value
		end
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Box" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(44, 44),
				UI.ColorPicker("Well")((colorSpec(Compose, { modes = { "spectrum", "swatches" } }))),
			}
		end, { frames = 20 })
		value.layer = layerOf(stage)
		value.well = t.find(stage, "Well")
		local target = value.well
		if target and not (target:IsA("GuiObject") and target.Selectable) then
			for _, node in target:GetDescendants() do
				if node:IsA("GuiButton") and node.Selectable and t.visible(node) then
					target = node
					break
				end
			end
		end
		value.target = target
		if not found(t, "the well was found", { "target" }, { target = target }) then
			return value
		end
		GuiService.SelectedObject = target
		t.settle(2)
		t.check("the well holds the selection", GuiService.SelectedObject == target, selectedName())
		return value
	end,
	{
		afterOpen = function(t, value)
			t.settle(12)
			local panel = openPanel(t, value.layer)
			t.check("ButtonA on the well opens the colour panel", panel ~= nil)
			local selected = GuiService.SelectedObject
			t.check(
				"selection lands inside the panel",
				panel ~= nil and selected ~= nil and selected:IsDescendantOf(panel),
				if selected then selected:GetFullName() else "nil"
			)
		end,
		afterBack = function(t, value)
			t.settle(12)
			t.check("ButtonB closes the colour panel", visibleNamed(t, value.layer, "ColorPickerModal") == nil)
			t.check("the selection returns to the well", GuiService.SelectedObject == value.target, selectedName())
			GuiService.SelectedObject = nil
		end,
	}
)

interactive(
	"color-ten-foot-center",
	{ "post-pickers-178" },
	"afterDown: press the Down arrow key 8 times; afterUp: press the Up arrow key 8 times",
	function(t)
		local value: any = {}
		if not tenFootCheck(t) then
			return value
		end
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Box" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(44, 44),
				UI.ColorPicker("Well")(
					(colorSpec(Compose, { modes = { "spectrum", "swatches" }, isPresented = openLater(Compose) }))
				),
			}
		end, { frames = 20 })
		openNow(t)
		local layer = layerOf(stage)
		local panel = openPanel(t, layer)
		local modal = visibleNamed(t, layer, "ColorPickerModal")
		local done = if panel then visibleNamed(t, panel, "Done") else nil
		local surface = if panel then visibleNamed(t, panel, "Surface") else nil
		if
			not found(
				t,
				"the ten-foot panel, modal, Done and plane were found",
				{ "panel", "modal", "done", "surface" },
				{
					panel = panel,
					modal = modal,
					done = done,
					surface = surface,
				}
			)
		then
			return value
		end
		local root = t.find(stage, "Well")
		t.check(
			"the panel is placed as the centred sheet",
			root:GetAttribute("placement") == "center",
			root:GetAttribute("placement")
		)
		centred(t, "the colour panel", panel, layer)
		scrimOf(t, "the colour panel", modal, layer)
		t.check("Done is shown and selectable", done.Selectable and t.clipped(done) ~= nil, done.Selectable)
		t.check("the plane is selectable", surface.Selectable and t.clipped(surface) ~= nil, surface.Selectable)
		t.note(
			"selection at open",
			if GuiService.SelectedObject then GuiService.SelectedObject:GetFullName() else "nil"
		)
		if GuiService.SelectedObject == nil or not GuiService.SelectedObject:IsDescendantOf(panel) then
			GuiService.SelectedObject = surface
			t.settle(2)
		end
		value.done, value.surface = done, surface
		watchSelection(value)
		t.note("gamepad", "D-pad movement is proven with the arrow keys, which drive the same native selection")
		t.note("not checked", "B cannot be sent by the input tools")
		return value
	end,
	{
		afterDown = function(t, value)
			t.check("Down reaches Done by gamepad selection", table.find(value.visited, "Done") ~= nil, value.visited)
			watchSelection(value)
		end,
		afterUp = function(t, value)
			t.check(
				"Up reaches the plane by gamepad selection",
				table.find(value.visited, "Surface") ~= nil,
				value.visited
			)
			if value.connection then
				value.connection:Disconnect()
			end
			GuiService.SelectedObject = nil
		end,
	}
)

return cases
