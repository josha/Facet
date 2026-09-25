--!strict
local GuiService = game:GetService("GuiService")

local cases = {}

local function add(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () },
	keepGallery: boolean?
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps, keepGallery = keepGallery })
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function watch(value: any)
	value.visited = {}
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		table.insert(value.visited, selectedName())
	end)
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

add("gallery-keyboard-reaches-demos", { "apps2-88", "navigation-3-28", "navigation-3-60" }, function(t)
	local value = {}
	local stage, context = t.gallery({ size = Vector2.new(1280, 720), demo = "all-controls" })
	value.stage, value.context = stage, context
	t.settle(20)
	GuiService.SelectedObject = visibleNamed(t, stage, "all-controls")
	t.check("the sidebar demo accepts selection", selectedName() == "all-controls", selectedName())
	watch(value)
	return value
end, {
	afterDownDown = function(t, value)
		t.check("two arrow presses reach Motion and layout", selectedName() == "motion-layout", value.visited)
	end,
	afterReturn = function(t, value)
		t.check(
			"Return changes the demo",
			value.context.selection:peek() == "motion-layout",
			value.context.selection:peek()
		)
		GuiService.SelectedObject = visibleNamed(t, value.stage, "collections")
	end,
	afterReturnAgain = function(t, value)
		t.check(
			"Return on Collections changes the demo",
			value.context.selection:peek() == "collections",
			value.context.selection:peek()
		)
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

add("held-arrow-repeats-and-stops", { "inputs-79", "apps-144" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, Host)
		local children = { Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }) }
		for index = 1, 12 do
			table.insert(children, UI.Button({ Name = "B" .. index, label = "Button " .. index, LayoutOrder = index }))
		end
		return Host.Frame "Column" {
			Size = UDim2.fromOffset(240, 700),
			BackgroundTransparency = 1,
			table.unpack(children),
		}
	end, { frames = 12 })
	GuiService.SelectedObject = t.find(stage, "B1")
	watch(value)
	return value
end, {
	afterHold = function(t, value)
		t.note("held Down visits", table.clone(value.visited))
		t.check("a held arrow repeats", #value.visited >= 4, value.visited)
		t.check(
			"the walk stops at the last control and does not wrap",
			selectedName() == "B12" and not table.find(value.visited, "B1"),
			value.visited
		)
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

add("form-controls-traverse-in-document-order", { "apps-175", "apps-192", "navigation-4-30" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Form" {
			Size = UDim2.fromOffset(360, 700),
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
			UI.Button "First" { label = "First", LayoutOrder = 1 },
			UI.Slider "Volume" { value = Compose.cell(0.5), LayoutOrder = 2 },
			UI.Stepper "Laps" { value = Compose.cell(3), min = 1, max = 9, LayoutOrder = 3 },
			UI.Toggle "Music" { value = Compose.cell(true), label = "Music", LayoutOrder = 4 },
			UI.Picker "Mode" {
				style = "segmented",
				selected = Compose.cell("a"),
				options = { { value = "a", label = "Arcade" }, { value = "b", label = "Sim" } },
				indicator = "underline",
				LayoutOrder = 5,
			},
			UI.Button "Last" { label = "Last", LayoutOrder = 6 },
		}
	end, { frames = 12 })
	value.stage = stage
	GuiService.SelectedObject = t.find(stage, "First")
	watch(value)
	return value
end, {
	afterWalk = function(t, value)
		t.note("Down visits", table.clone(value.visited))
		local order = {}
		for _, name in value.visited do
			if not table.find(order, name) then
				table.insert(order, name)
			end
		end
		t.check("the walk reaches the last control", selectedName() == "Last", value.visited)
		t.check("no selection indicator is a stop", not table.find(value.visited, "SelectionIndicator"), value.visited)
		local positions = {}
		for _, name in order do
			local node = t.find(value.stage, name)
			if node then
				table.insert(positions, node.AbsolutePosition.Y)
			end
		end
		local ordered = true
		for index = 2, #positions do
			ordered = ordered and positions[index] >= positions[index - 1] - 0.5
		end
		t.check("the walk follows document position", ordered, { order = order, y = positions })
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

add(
	"return-activates-the-selected-row",
	{ "collections-179", "collections-237", "collections-265", "collections-247" },
	function(t)
		local value = { activated = {} }
		local stage = t.mount(function(UI)
			local rows = {}
			for index = 1, 30 do
				rows[index] = { id = tostring(index) }
			end
			return UI.VirtualList "List" {
				from = rows,
				key = function(item)
					return item.id
				end,
				itemSize = 44,
				Size = UDim2.fromOffset(320, 300),
				render = function(current)
					return UI.Button({
						Name = "Row" .. current:peek().id,
						label = "Row " .. current:peek().id,
						Size = UDim2.fromScale(1, 1),
						onActivate = function()
							table.insert(value.activated, current:peek().id)
						end,
					})
				end,
			}
		end, { frames = 12 })
		GuiService.SelectedObject = t.find(stage, "Row3")
		t.check("row 3 is selected", selectedName() == "Row3", selectedName())
		return value
	end,
	{
		afterReturn = function(t, value)
			t.check(
				"Return activates the selected row once",
				#value.activated == 1 and value.activated[1] == "3",
				value.activated
			)
			GuiService.SelectedObject = nil
		end,
	}
)

add("open-tray-steps-sideways", { "collections-288", "apps2-48", "apps-188" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, _, Compose)
		return UI.RowActions "Row" {
			content = UI.Button "Content" { label = "Message", Size = UDim2.fromScale(1, 1) },
			open = Compose.cell("trailing"),
			trailing = {
				{ id = "archive", label = "Archive", onActivate = function() end },
				{ id = "flag", label = "Flag", onActivate = function() end },
				{ id = "delete", label = "Delete", role = "destructive", onActivate = function() end },
			},
			Size = UDim2.fromOffset(480, 56),
		}
	end, { frames = 16 })
	value.stage = stage
	local tray = t.find(stage, "trailing")
	local first
	for _, node in tray and tray:GetDescendants() or {} do
		if
			node:IsA("GuiButton")
			and t.visible(node)
			and (first == nil or node.AbsolutePosition.X < first.AbsolutePosition.X)
		then
			first = node
		end
	end
	t.check("the open tray shows its actions", first ~= nil)
	GuiService.SelectedObject = first
	watch(value)
	t.note("first tray action", selectedName())
	return value
end, {
	afterRight = function(t, value)
		t.note("Right visits", table.clone(value.visited))
		local tray = t.find(value.stage, "trailing")
		local inside = GuiService.SelectedObject ~= nil
			and tray ~= nil
			and GuiService.SelectedObject:IsDescendantOf(tray)
		t.check("Right walks along the tray", #value.visited >= 2 and inside, value.visited)
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

add("tab-key-traversal", { "apps-158", "apps2-169", "apps2-222", "apps-151" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Row" {
			Size = UDim2.fromOffset(600, 60),
			BackgroundTransparency = 1,
			Host.UIListLayout({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
			UI.Button "A" { label = "A" },
			UI.Button "B" { label = "B" },
			UI.Button "C" { label = "C" },
		}
	end, { frames = 10 })
	GuiService.SelectedObject = t.find(stage, "A")
	watch(value)
	return value
end, {
	afterTab = function(t, value)
		t.note("Tab visits", table.clone(value.visited))
		t.check(
			"Tab moves the selection to the next control",
			selectedName() == "B",
			{ now = selectedName(), visits = value.visited }
		)
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

return cases
