--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Child = typeof(require("@repo/tools/typecheck/aliases").Child)
type IdReadOnlyValue = typeof(require("@repo/tools/typecheck/aliases").IdReadOnlyValue)
type Rect = { x: number, y: number, w: number, h: number, r: number, b: number }
type Mount = ((FacetControls, RobloxHost, ComposeModule) -> Instance, { frames: number }?) -> Instance
type RunContext = {
	Facet: { Compose: ComposeModule },
	mount: Mount,
	find: (Instance, string) -> GuiObject?,
	rect: (GuiObject) -> Rect,
	clipped: (GuiObject) -> Rect?,
	check: (string, boolean, unknown?) -> (),
	note: (string, unknown) -> (),
	settle: (number) -> (),
	device: ({ device: string, input: Enum.PreferredInput }) -> (),
}
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

type Case = {
	id: string,
	contracts: { string },
	run: ((RunContext) -> ())?,
	setup: ((RunContext) -> unknown)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function add(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () },
	keepGallery: boolean?
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps, keepGallery = keepGallery })
end

local function watchSelection(value: any)
	value.visited = {}
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		table.insert(value.visited, if selected then selected.Name else "nil")
	end)
end

local function t_visible(node: Instance): boolean
	local current: Instance? = node
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function rows(count: number): { { id: string } }
	local list = {}
	for index = 1, count do
		list[index] = { id = tostring(index) }
	end
	return list
end

add("list-keyboard-and-dpad", {}, function(t)
	local value = {}
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		return UI.VirtualList "List" {
			from = rows(100),
			key = "id",
			itemSize = 40,
			Size = UDim2.fromOffset(300, 200),
			render = function(current: IdReadOnlyValue): GuiObject
				return UI.Button {
					Name = "Row" .. current:peek().id,
					label = "Row " .. current:peek().id,
					Size = UDim2.fromScale(1, 1),
				}
			end,
		}
	end, { frames = 12 })
	value.list = t.find(stage, "List")
	GuiService.SelectedObject = t.find(stage, "Row1")
	t.check("row 1 selected at the start", selectedName() == "Row1", selectedName())
	return value
end, {
	afterDown = function(t)
		t.check("the first Down selects row 2", selectedName() == "Row2", selectedName())
	end,
	afterDpad = function(t)
		t.check("a second Down selects row 3", selectedName() == "Row3", selectedName())
	end,
	afterPast = function(t, value)
		local name = selectedName()
		local row = tonumber(string.match(name, "%d+")) or 0
		t.note("selected after moving past the band", name)
		t.check("eight Down inputs reach row 9", row == 9, name)
		local selected = GuiService.SelectedObject
		local r = selected and t.rect(selected)
		local top = value.list.AbsolutePosition.Y
		local bottom = top + value.list.AbsoluteWindowSize.Y
		t.check(
			"the canvas moves to keep the selected row fully visible",
			value.list.CanvasPosition.Y > 0 and r ~= nil and r.y >= top - 0.5 and r.b <= bottom + 0.5,
			{ row = r, window = { top, bottom }, canvas = value.list.CanvasPosition }
		)
	end,
})

add("scroll-into-view-by-gamepad", {}, function(t)
	local value = {}
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		local children: { Child } = {
			Host.UIListLayout { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
		}
		for index = 1, 20 do
			table.insert(children, UI.Button { Name = "Item" .. index, label = "Item " .. index, LayoutOrder = index })
		end
		return Host.ScrollingFrame "Plain" {
			Size = UDim2.fromOffset(300, 200),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			table.unpack(children),
		}
	end, { frames = 12 })
	value.frame = t.find(stage, "Plain")
	GuiService.SelectedObject = t.find(stage, "Item1")
	return value
end, {
	afterDpad = function(t, value)
		local selected = GuiService.SelectedObject
		if not selected then
			t.check("an item is selected", false)
			return
		end
		local s, f = t.rect(selected), t.rect(value.frame)
		t.note("selected", selected.Name)
		t.check(
			"selection moved below the first band",
			(tonumber(string.match(selected.Name, "%d+")) or 0) >= 5,
			selected.Name
		)
		t.check("canvas moved", value.frame.CanvasPosition.Y > 0, value.frame.CanvasPosition)
		t.check(
			"selected item is fully visible",
			s.y >= f.y - 0.5 and s.b <= f.b + 0.5,
			{ item = { s.y, s.b }, frame = { f.y, f.b } }
		)
	end,
})

add("sidebar-dpad-to-collections", {}, function(t)
	local api = workspace:WaitForChild("FacetShowcaseAPI")
	assert(api:IsA("BindableFunction"))
	local shown = api:Invoke("show", "all-controls")
	if shown.panel ~= "demos" then
		api:Invoke("panel", "demos")
	end
	t.check("the Demos panel is open", api:Invoke("report").panel == "demos")
	t.settle(10)
	local gui = (Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui):WaitForChild("FacetGallery")
	local tabs = gui:FindFirstChild("DemoList", true)
	local tab = (tabs and tabs:FindFirstChild("Demo-all-controls", true)) :: GuiObject?
	t.check("all-controls tab found", tab ~= nil)
	GuiService.SelectedObject = tab
	t.settle(2)
	t.check("all-controls tab selected", selectedName() == "Demo-all-controls", selectedName())
	local peer = tabs and tabs:FindFirstChild("Demo-collections", true)
	local across = tab ~= nil
		and peer ~= nil
		and (peer :: GuiObject).AbsolutePosition.X > tab.AbsolutePosition.X + tab.AbsoluteSize.X / 2
	t.note("demo strip axis", if across then "horizontal: press DPadRight" else "vertical: press DPadDown")
	return { across = across }
end, {
	afterDown = function(t)
		t.check("one DPadDown selects the collections tab", selectedName() == "Demo-collections", selectedName())
		GuiService.SelectedObject = nil
	end,
	afterRight = function(t)
		t.check(
			"one DPadRight along the demo strip selects the collections tab",
			selectedName() == "Demo-collections",
			selectedName()
		)
		GuiService.SelectedObject = nil
	end,
}, true)

add("power-off-traversal", {}, function(t)
	local value = {}
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
		value.built = t.scenario("inherited_subtree").build(t.context(UI, Host, Compose, env))
		return value.built.screen()
	end, { frames = 12 })
	value.stage = stage
	value.built.live:set(false)
	t.settle(6)
	GuiService.SelectedObject = t.find(stage, "PowerToggle")
	t.settle(2)
	watchSelection(value)
	return value
end, {
	afterDpad = function(t, value)
		local visited = table.clone(value.visited)
		t.note("DPadDown visits", visited)
		t.check(
			"DPadDown never selects Go or InnerGo",
			not table.find(visited, "Go") and not table.find(visited, "InnerGo"),
			visited
		)
		t.check("DPadDown reaches After", table.find(visited, "After") ~= nil, visited)
		table.clear(value.visited)
		GuiService.SelectedObject = t.find(value.stage, "PowerToggle")
		t.settle(2)
		table.clear(value.visited)
	end,
	afterTab = function(t, value)
		local visited = table.clone(value.visited)
		t.note("Tab visits", visited)
		t.check(
			"Tab never selects Go or InnerGo",
			not table.find(visited, "Go") and not table.find(visited, "InnerGo"),
			visited
		)
		t.note("Tab reaches After", table.find(visited, "After") ~= nil)
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

add("touch-drag-scrolls-reorderable-list", {}, function(t)
	local value = { reorders = 0 }
	local stage = t.mount(function(UI: FacetControls)
		return UI.VirtualList "Sortable" {
			from = rows(50),
			key = "id",
			itemSize = 44,
			reorderable = true,
			onReorder = function()
				value.reorders += 1
			end,
			Size = UDim2.fromOffset(320, 220),
			render = function(current: IdReadOnlyValue)
				return UI.Text {
					Name = "Cell" .. current:peek().id,
					text = "Row " .. current:peek().id,
					Size = UDim2.fromScale(1, 1),
				}
			end,
		}
	end, { frames = 12 })
	value.list = t.find(stage, "Sortable")
	local cell = t.find(stage, "Cell3")
	t.note("drag start", cell and cell.AbsolutePosition + cell.AbsoluteSize / 2)
	t.note("touch", t.environment.touch)
	return value
end, {
	afterDrag = function(t, value)
		t.check("the list scrolled", value.list.CanvasPosition.Y > 0, value.list.CanvasPosition)
		t.check("no reorder request", value.reorders == 0, value.reorders)
	end,
})

add("mail-swipe-and-tap", {}, function(t)
	local value = {}
	local demo = t.scenario("collection_demo")
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
		local seed = {}
		for index = 1, 6 do
			seed[index] = {
				id = "m" .. index,
				from = "Sender " .. index,
				subject = "Subject " .. index,
				preview = "Preview " .. index,
				read = false,
				flagged = false,
			}
		end
		value.built = demo(t.context(UI, Host, Compose, env), {
			name = "Mail_list",
			title = "Mail",
			rows = seed,
			count = 6,
			actions = true,
			mail = true,
			list = true,
		})
		return value.built.screen()
	end, { frames = 16 })
	value.stage = stage
	return value
end, {
	afterSwipe = function(t, value)
		local row = t.find(value.stage, "Row_m1")
		local tray = row and row:FindFirstChild("trailing")
		t.check("the trailing tray of m1 opened", tray ~= nil and tray.AbsoluteSize.X > 0, tray and tray.AbsoluteSize)
	end,
	afterTap = function(t, value)
		local read = value.built.report().read
		t.check("a tap on m5 marks it read", read.m5 == true, read)
	end,
})

add("tray-grows-with-text-size", {}, function(t)
	local value = {}
	local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		return UI.RowActions "Row" {
			content = UI.Text { text = "Message", Size = UDim2.fromScale(1, 1) },
			open = Compose.cell("trailing" :: "leading" | "trailing" | nil),
			onOpenChange = function() end,
			trailing = {
				{
					id = "delete",
					label = "Delete",
					role = "destructive" :: "destructive",
					onActivate = function() end,
				},
			},
			Size = UDim2.fromOffset(360, 56),
		}
	end, { frames = 12 })
	value.tray = t.find(stage, "trailing")
	value.before = value.tray.AbsoluteSize.X
	value.size = t.environment.preferredTextSize
	t.note("tray width before", value.before)
	return value
end, {
	afterChange = function(t, value)
		local label
		for _, node in value.tray:GetDescendants() do
			if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text ~= "" then
				label = node
			end
		end
		local width = value.tray.AbsoluteSize.X
		t.note("text size", { before = value.size, after = tostring(GuiService.PreferredTextSize) })
		t.note("tray width after", width)
		t.check("tray is at least the label width plus 32", label ~= nil and width >= label.TextBounds.X + 32 - 0.5, {
			width = width,
			label = label and label.TextBounds,
		})
		t.check("tray width followed the text size", width ~= value.before, { before = value.before, after = width })
	end,
})

local function within(node: Instance?, ancestor: Instance?): boolean
	return node ~= nil and ancestor ~= nil and (node == ancestor or node:IsDescendantOf(ancestor))
end

type BooleanCell = typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
type ModalState = {
	sheet: BooleanCell,
	alert: BooleanCell,
	visited: { string },
	panel: GuiObject?,
	stage: Instance,
	gui: LayerCollector?,
	connection: RBXScriptConnection?,
}
type StepContext = {
	note: (string, unknown) -> (),
	check: (string, boolean, unknown?) -> (),
	settle: (number) -> (),
}

local function modalFixture(mount: Mount, withSheet: boolean, actions: { any }): ModalState
	local sheet: BooleanCell?
	local alert: BooleanCell?
	local stage = mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
		sheet = Compose.cell(withSheet)
		alert = Compose.cell(not withSheet)
		return Host.Frame "Base" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) },
			UI.Button "Background" { label = "Background", LayoutOrder = 1 },
			UI.Button "Background2" { label = "Background two", LayoutOrder = 2 },
			UI.Sheet {
				isPresented = sheet,
				detent = Compose.cell("medium"),
				title = "Loadout",
				content = function(): Instance
					return Host.Frame "SheetList" {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) },
						UI.Button "First" { label = "First", LayoutOrder = 1 },
						UI.Button "Second" { label = "Second", LayoutOrder = 2 },
						UI.Button "Third" { label = "Third", LayoutOrder = 3 },
					}
				end,
			},
			UI.Alert { isPresented = alert, title = "Leave the match?", actions = actions },
		}
	end, { frames = 14 })
	local value: ModalState = {
		sheet = assert(sheet),
		alert = assert(alert),
		visited = {},
		stage = stage,
		gui = stage:FindFirstAncestorWhichIsA("LayerCollector"),
	}
	watchSelection(value)
	return value
end

local function panelOf(value: any): GuiObject?
	for _, name in { "AlertPanel", "SheetPanel" } do
		for _, node in value.gui:GetDescendants() do
			if node.Name == name and node:IsA("GuiObject") and t_visible(node) then
				return node
			end
		end
	end
	return nil
end

table.insert(cases, {
	id = "sheet-traps-and-orders-selection",
	contracts = {},
	setup = function(t: RunContext)
		local value = modalFixture(t.mount, false, { { id = "ok", label = "OK" } })
		value.alert:set(false)
		t.settle(6)
		GuiService.SelectedObject = t.find(value.stage, "Background")
		t.settle(4)
		value.sheet:set(true)
		t.settle(20)
		value.panel = panelOf(value)
		t.note("selection after present", selectedName())
		t.check(
			"presenting the sheet selects the first selectable in document order",
			selectedName() == "Grabber",
			selectedName()
		)
		table.clear(value.visited)
		return value
	end,
	steps = {
		afterDown = function(t: StepContext, value: ModalState)
			t.note("Down visits", table.clone(value.visited))
			local stops = {}
			for _, name in value.visited do
				local node = value.panel and value.panel:FindFirstChild(name, true)
				if not (node and node:IsA("ScrollingFrame")) then
					table.insert(stops, name)
				end
			end
			t.note("Down stops without scroll containers", stops)
			local handle = value.panel and value.panel:FindFirstChild("DragHandle", true)
			t.check(
				"the drag handle is a passive frame",
				handle ~= nil and handle:IsA("Frame") and not handle.Selectable
			)
			local close = value.panel and value.panel:FindFirstChild("Close", true)
			t.check("the docked sheet hides its duplicate Close command", close ~= nil and not t_visible(close))
			t.check(
				"Down walks the sheet controls in document order",
				table.concat(stops, ",") == "First,Second,Third",
				value.visited
			)
			t.check("Down stops at Third", selectedName() == "Third", selectedName())
			table.clear(value.visited)
		end,
		afterAll = function(t: StepContext, value: ModalState)
			local outside = {}
			for _, name in value.visited do
				if name == "Background" or name == "Background2" then
					table.insert(outside, name)
				end
			end
			t.note("four-direction visits", table.clone(value.visited))
			t.check(
				"selection never leaves the sheet",
				#outside == 0 and within(GuiService.SelectedObject, value.panel),
				{
					outside = outside,
					now = selectedName(),
				}
			)
			table.clear(value.visited)
		end,
		afterBack = function(t: StepContext, value: ModalState)
			t.check("ButtonB dismisses the sheet", value.sheet:peek() == false, value.sheet:peek())
			t.check(
				"Back returns the selection to the control that held it",
				selectedName() == "Background",
				selectedName()
			)
			assert(value.connection):Disconnect()
			GuiService.SelectedObject = nil
		end,
	},
})

table.insert(cases, {
	id = "alert-selection-stays-inside",
	contracts = {},
	setup = function(t: RunContext)
		local value = modalFixture(t.mount, true, {
			{ id = "stay", label = "Stay", role = "cancel" :: "cancel" },
			{ id = "save", label = "Save and leave" },
			{ id = "leave", label = "Leave without saving", role = "destructive" :: "destructive" },
		})
		GuiService.SelectedObject = t.find(value.stage, "Background")
		t.settle(6)
		value.alert:set(true)
		t.settle(10)
		value.sheet:set(false)
		t.settle(10)
		value.panel = panelOf(value)
		t.check(
			"the alert is on top after the covered sheet leaves",
			value.panel ~= nil and value.panel.Name == "AlertPanel",
			value.panel and value.panel.Name
		)
		t.check("selection starts in the alert", within(GuiService.SelectedObject, value.panel), selectedName())
		t.note("initial alert selection", selectedName())
		table.clear(value.visited)
		return value
	end,
	steps = {
		afterDown = function(t: StepContext, value: ModalState)
			t.note("Down visits", table.clone(value.visited))
			t.check("Down at the last action stays on Stay", selectedName() == "stay", value.visited)
			t.check("two Downs stay inside the alert", within(GuiService.SelectedObject, value.panel), selectedName())
			table.clear(value.visited)
		end,
		afterUp = function(t: StepContext, value: ModalState)
			t.note("Up visits", table.clone(value.visited))
			t.check(
				"the first Up from Stay reaches the stacked destructive action",
				value.visited[1] == "leave",
				value.visited
			)
			t.check(
				"Up walks the stacked actions and stops at the top action",
				table.concat(value.visited, ",") == "leave,save" and selectedName() == "save",
				value.visited
			)
			t.check("Up stays inside the alert", within(GuiService.SelectedObject, value.panel), selectedName())
			table.clear(value.visited)
		end,
		afterActivate = function(t: StepContext, value: ModalState)
			t.check("ButtonA on an alert action closes the alert", value.alert:peek() == false, value.alert:peek())
			t.check("the selection returns to the control that held it", selectedName() == "Background", selectedName())
			assert(value.connection):Disconnect()
			GuiService.SelectedObject = nil
		end,
	},
})

add("confirm-dialog-left-right", {}, function(t)
	local value = {}
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
		local ctx = t.context(UI, Host, Compose, env)
		ctx.load = function() end
		local folder = game:GetService("ReplicatedStorage"):WaitForChild("FacetExamples")
		value.built = (require :: any)(folder:WaitForChild("04_confirm_dialog")).build(ctx)
		return if type(value.built) == "function" then value.built() else value.built.screen()
	end, { frames = 14 })
	value.stage = stage
	value.gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
	watchSelection(value)
	t.note("delete button", t.find(stage, "Delete") and t.find(stage, "Delete"):GetFullName())
	return value
end, {
	afterOpen = function(t, value)
		local cancel = nil
		for _, node in value.gui:GetDescendants() do
			if node.Name == "Cancel" and node:IsA("GuiButton") and t_visible(node) then
				cancel = node
			end
		end
		t.check("the dialog shows Cancel", cancel ~= nil)
		GuiService.SelectedObject = cancel
		value.cancel = cancel
		table.clear(value.visited)
	end,
	afterRight = function(t, value)
		t.check("Right selects Confirm", selectedName() == "Confirm", value.visited)
	end,
	afterLeft = function(t, value)
		t.check("Left selects Cancel", selectedName() == "Cancel", value.visited)
	end,
	afterBack = function(t, value)
		local open = false
		for _, node in value.gui:GetDescendants() do
			if node.Name == "Cancel" and node:IsA("GuiButton") and t_visible(node) then
				open = true
			end
		end
		t.check("ButtonB dismisses the dialog", not open)
		t.check("Back returns the selection to Delete", selectedName() == "Delete", selectedName())
		value.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

add("return-and-space-activate-once", {}, function(t)
	local value = { count = 0 }
	local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		value.enabled = Compose.cell(true)
		return UI.Button "Counter" {
			label = "Count",
			enabled = value.enabled,
			onActivate = function()
				value.count += 1
			end,
		}
	end, { frames = 10 })
	value.button = t.find(stage, "Counter")
	GuiService.SelectedObject = value.button
	return value
end, {
	afterReturn = function(t, value)
		t.check("Return activates once", value.count == 1, value.count)
	end,
	afterSpace = function(t, value)
		t.check("Space activates once more", value.count == 2, value.count)
		value.enabled:set(false)
		t.settle(4)
		t.check("a disabled Button is not selectable", value.button.Selectable == false, value.button.Selectable)
		GuiService.SelectedObject = value.button
	end,
	afterDisabled = function(t, value)
		t.check("a disabled Button ignores Return and Space", value.count == 2, value.count)
		GuiService.SelectedObject = nil
	end,
})

add("shift-return-opens-row-menu", {}, function(t)
	local value = { count = 0 }
	local stage = t.mount(function(UI: FacetControls)
		return UI.RowActions "Row" {
			content = UI.Button "Content" {
				label = "Message",
				Size = UDim2.fromScale(1, 1),
				onActivate = function()
					value.count += 1
				end,
			},
			trailing = {
				{ id = "delete", label = "Delete", role = "destructive" :: "destructive", onActivate = function() end },
			},
			Size = UDim2.fromOffset(360, 56),
		}
	end, { frames = 10 })
	value.stage = stage
	local content
	for _, node in stage:GetDescendants() do
		if node.Name == "Content" and node:IsA("GuiButton") then
			content = node
		end
	end
	GuiService.SelectedObject = content
	t.check(
		"the row content button is selected",
		GuiService.SelectedObject == content and content ~= nil,
		selectedName()
	)
	return value
end, {
	afterShiftReturn = function(t, value)
		local menu = nil
		for _, node in value.stage.Parent:GetDescendants() do
			if node.Name == "MenuPanel" and node:IsA("GuiObject") and t_visible(node) then
				menu = node
			end
		end
		t.check("Shift+Return opens the row actions menu", menu ~= nil)
		t.check("Shift+Return does not activate the content", value.count == 0, value.count)
	end,
	afterReturn = function(t, value)
		t.check("Return activates the content once", value.count == 1, value.count)
		GuiService.SelectedObject = nil
	end,
})

add("skinned-part-hover-state", {}, function(t)
	local value = {}
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
		return Host.Frame "Column" {
			Size = UDim2.fromOffset(360, 300),
			BackgroundTransparency = 1,
			Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) },
			UI.Toggle "Toggle" { value = Compose.cell(false), label = "On", LayoutOrder = 1 },
			UI.Stepper "Stepper" { value = Compose.cell(2), min = 0, max = 5, LayoutOrder = 2 },
			UI.Slider "Slider" { value = Compose.cell(0.5), LayoutOrder = 3 },
		}
	end, { frames = 10 })
	value.stage = stage
	value.parts = {
		Indicator = t.find(t.find(stage, "Toggle"), "Indicator"),
		Stepper = t.find(stage, "Stepper"),
		Thumb = t.find(t.find(stage, "Slider"), "Thumb"),
	}
	local paths = {}
	for name, node in value.parts :: { [string]: Instance? } do
		paths[name] = node and node:GetFullName()
	end
	t.note("parts", paths)
	return value
end, {
	hoverIndicator = function(t, value)
		local node = value.parts.Indicator
		t.note("Indicator state on hover", node and tostring(node.GuiState))
		t.check(
			"Indicator enters Hover",
			node ~= nil and node.GuiState == Enum.GuiState.Hover,
			node and tostring(node.GuiState)
		)
	end,
	hoverStepper = function(t, value)
		local node = value.parts.Stepper
		t.check(
			"Stepper root enters Hover",
			node ~= nil and node.GuiState == Enum.GuiState.Hover,
			node and tostring(node.GuiState)
		)
	end,
	hoverThumb = function(t, value)
		local node = value.parts.Thumb
		t.check(
			"Slider Thumb enters Hover",
			node ~= nil and node.GuiState == Enum.GuiState.Hover,
			node and tostring(node.GuiState)
		)
	end,
})

table.insert(cases, {
	id = "sheet-native-selection-order",
	contracts = {},
	run = function(t: RunContext)
		local value = modalFixture(t.mount, true, {})
		value.alert:set(false)
		t.settle(30)
		local panel = panelOf(value)
		t.check("the sheet panel mounts", panel ~= nil)
		if not panel then
			return
		end
		local handle = panel:FindFirstChild("DragHandle", true)
		t.note("passive sheet parts", { pill = panel:FindFirstChild("Pill", true), handle = handle })
		t.check("the drag handle is a passive frame", handle ~= nil and handle:IsA("Frame") and not handle.Selectable)
		for _, name in { "Grabber", "First", "Second", "Third" } do
			local target = panel:FindFirstChild(name, true)
			t.check(name .. " mounts", target ~= nil)
			assert(target and target:IsA("GuiObject"))
			GuiService.SelectedObject = target
			t.settle(2)
			t.check(name .. " keeps native selection inside the panel", within(GuiService.SelectedObject, panel))
			t.check(name .. " is visible", target ~= nil and t_visible(target))
		end
		local close = panel:FindFirstChild("Close", true)
		t.check("a docked Sheet with a grabber shows no Close", close == nil or not t_visible(close))
		local grabber = panel:FindFirstChild("Grabber", true)
		local first = panel:FindFirstChild("First", true)
		t.check(
			"the grabber links Down to the first task entry",
			grabber ~= nil and grabber:IsA("GuiObject") and grabber.NextSelectionDown == first
		)
		local watched = (value) :: { connection: RBXScriptConnection }
		watched.connection:Disconnect()
		GuiService.SelectedObject = nil
	end,
})

for _, scenario in { "replacement", "ancestor-detached", "nested" } do
	table.insert(cases, {
		id = "sheet-content-" .. scenario,
		contracts = {},
		keepGallery = false,
		run = function(t: RunContext)
			t.device({ device = "xbox", input = Enum.PreferredInput.Gamepad })
			local Compose: ComposeModule = t.Facet.Compose
			local opened, child, detail, ready =
				Compose.cell(false), Compose.cell(false), Compose.cell(false), Compose.cell(true)
			local tracked: GuiObject? = nil
			local history: { { selected: string, formerParent: string, size: Vector2 } } = {}
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
				local connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
					local selected = GuiService.SelectedObject
					table.insert(history, {
						selected = if selected then selected:GetFullName() else "nil",
						formerParent = if tracked and tracked.Parent then tracked.Parent:GetFullName() else "nil",
						size = if selected then selected.AbsoluteSize else Vector2.zero,
					})
				end)
				Compose.cleanup(function()
					connection:Disconnect()
				end)
				return Host.Frame "Base" {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					UI.Button "Opener" { label = "Open equipment" },
					UI.Sheet {
						isPresented = opened,
						title = "Equipment",
						placement = "center",
						content = function()
							return Host.Frame "Body" {
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								BackgroundTransparency = 1,
								Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder },
								Compose.show(ready, function()
									return Compose.show(detail, function()
										return UI.Button "Equip" { label = "Equip" }
									end, function()
										return Host.Frame "Branch" {
											Size = UDim2.new(1, 0, 0, 44),
											BackgroundTransparency = 1,
											UI.Button "Inspect" { label = "Inspect", Size = UDim2.fromScale(1, 1) },
										}
									end)
								end),
								Compose.show(function()
									return scenario == "ancestor-detached"
								end, function()
									return UI.Button "Spare" { label = "Spare", LayoutOrder = 2 }
								end),
								UI.Sheet {
									isPresented = child,
									title = "Details",
									placement = "center",
									content = function()
										return UI.Button "ChildAction" { label = "Continue" }
									end,
								},
							}
						end,
					},
				}
			end)
			local gui = assert(stage:FindFirstAncestorWhichIsA("LayerCollector"))
			local opener = t.find(stage, "Opener")
			GuiService.SelectedObject = opener
			opened:set(true)
			t.settle(20)
			local panel = t.find(gui, "SheetPanel")
			local errors: { string } = {}
			for _, node in stage:GetDescendants() do
				local problem = node:GetAttribute("FacetError")
				if problem then
					table.insert(errors, `{node:GetFullName()}: {tostring(problem)}`)
				end
			end
			t.check("the parent panel is mounted", panel ~= nil, errors)
			if not panel then
				return
			end
			local removed = assert(t.find(panel, "Inspect"))
			tracked = removed
			GuiService.SelectedObject = removed
			t.settle(2)
			t.note("before replacement", {
				selected = GuiService.SelectedObject,
				parent = removed.Parent,
				panel = panel,
				bounds = t.rect(removed),
			})
			t.check(
				"the original target is selected in the retained panel",
				GuiService.SelectedObject == removed and within(removed, panel)
			)
			local nested: GuiObject? = nil
			if scenario == "nested" then
				child:set(true)
				t.settle(20)
				nested = t.find(gui, "ChildAction")
				t.check(
					"the child owns selection",
					GuiService.SelectedObject == nested and nested ~= nil,
					selectedName()
				)
			end
			if scenario == "ancestor-detached" then
				local branch = assert(removed.Parent)
				branch.Parent = nil
				t.check(
					"the selected control stays parented to its detached ancestor",
					removed.Parent == branch and branch.Parent == nil
				)
			else
				detail:set(true)
				t.check("the selected branch is disposed", removed.Parent == nil)
			end
			t.settle(20)
			local candidate = t.find(panel, "Equip")
			t.note("replacement candidate", {
				candidate = candidate,
				bounds = candidate and t.rect(candidate),
				selectable = candidate and candidate.Selectable,
				interactable = candidate and candidate.Interactable,
				visible = candidate and t_visible(candidate),
			})
			t.note("selection history", history)
			t.note("after replacement", {
				selected = GuiService.SelectedObject,
				removedParent = removed.Parent,
				retainedPanel = panel.Parent ~= nil,
			})
			if scenario == "nested" then
				t.check(
					"parent content replacement does not steal child focus",
					GuiService.SelectedObject == nested,
					selectedName()
				)
				child:set(false)
				t.settle(20)
			end
			local expected = if scenario == "ancestor-detached" then "Spare" else "Equip"
			local selected = GuiService.SelectedObject
			t.note(
				"recovered selection",
				{ selected = selected, parent = selected and selected.Parent, bounds = selected and t.rect(selected) }
			)
			t.check("the same parent panel is retained", t.find(gui, "SheetPanel") == panel)
			t.check(
				"selection reaches the available body action",
				selected ~= nil and selected.Name == expected,
				selectedName()
			)
			t.check(
				"the recovered target belongs to the panel and has native bounds",
				selected ~= nil
					and within(selected, panel)
					and selected.Selectable
					and selected.Interactable
					and t_visible(selected)
					and selected.AbsoluteSize.X > 0
					and selected.AbsoluteSize.Y > 0
			)
			if scenario == "replacement" then
				ready:set(false)
				t.settle(20)
				t.check("an empty body falls back to Close", selectedName() == "Close", selectedName())
				ready:set(true)
				t.settle(20)
				t.check(
					"late content replaces the provisional Close selection",
					selectedName() == "Equip",
					selectedName()
				)
			end
			opened:set(false)
			t.settle(20)
			t.note("after close", { selected = GuiService.SelectedObject, opener = opener })
			t.check("closing restores the original opener", GuiService.SelectedObject == opener, selectedName())
			GuiService.SelectedObject = nil
		end,
	})
end

table.insert(cases, {
	id = "demo-strip-native-selection-axis",
	contracts = {},
	keepGallery = true,
	run = function(t: RunContext)
		t.device({ device = "xbox", input = Enum.PreferredInput.Gamepad })
		local api = workspace:WaitForChild("FacetShowcaseAPI")
		assert(api:IsA("BindableFunction"))
		api:Invoke("show", "all-controls")
		api:Invoke("panel", "demos")
		t.settle(10)
		local gui = Players.LocalPlayer.PlayerGui:WaitForChild("FacetGallery")
		local tabs = gui:FindFirstChild("DemoList", true)
		local tab = tabs and tabs:FindFirstChild("Demo-all-controls", true)
		local peer = tabs and tabs:FindFirstChild("Demo-collections", true)
		t.check("both demo tabs mount", tab ~= nil and peer ~= nil)
		if not tab or not peer then
			return
		end
		assert(tab:IsA("GuiObject") and peer:IsA("GuiObject"))
		local across = peer.AbsolutePosition.X > tab.AbsolutePosition.X + tab.AbsoluteSize.X / 2
		t.note("demo strip geometry", {
			first = t.rect(tab),
			next = t.rect(peer),
			across = across,
			down = tab.NextSelectionDown,
			right = tab.NextSelectionRight,
		})
		GuiService.SelectedObject = tab
		t.settle(2)
		t.note(
			"selection before move",
			{ selected = GuiService.SelectedObject, expected = tab, clipped = t.clipped(tab) }
		)
		GuiService.SelectedObject = peer
		for frame = 1, 4 do
			t.settle(1)
			local ancestors = {}
			local at = peer.Parent
			while at and not at:IsA("LayerCollector") do
				if at:IsA("GuiObject") then
					table.insert(ancestors, {
						name = at.Name,
						rect = t.rect(at),
						visible = at.Visible,
						canvas = if at:IsA("ScrollingFrame") then at.AbsoluteCanvasSize else nil,
						window = if at:IsA("ScrollingFrame") then at.AbsoluteWindowSize else nil,
						offset = if at:IsA("ScrollingFrame") then at.CanvasPosition else nil,
					})
				end
				at = at.Parent
			end
			t.note("collections frame " .. frame, {
				ancestors = ancestors,
				rect = t.rect(peer),
				clipped = t.clipped(peer),
				selected = GuiService.SelectedObject,
			})
			t.check(
				"the collections tab stays selected on frame " .. frame,
				GuiService.SelectedObject == peer and t_visible(peer) and t.clipped(peer) ~= nil
			)
		end
		GuiService.SelectedObject = nil
	end,
})

table.insert(cases, {
	id = "sidebar-selection-setup-keeps-open-panel",
	contracts = {},
	keepGallery = true,
	run = function(t: RunContext)
		local api = workspace:WaitForChild("FacetShowcaseAPI")
		assert(api:IsA("BindableFunction"))
		local before = api:Invoke("report")
		if before.panel ~= "demos" then
			api:Invoke("panel", "demos")
		end
		t.settle(30)
		t.check("the Demos panel is already open before setup", api:Invoke("report").panel == "demos")
		for _, case in cases do
			if case.id == "sidebar-dpad-to-collections" then
				assert(case.setup)(t)
				break
			end
		end
		t.check("sidebar setup keeps the Demos panel open", api:Invoke("report").panel == "demos")
		t.settle(30)
		local selected = GuiService.SelectedObject
		t.note("selection after repeated setup", selected)
		t.check(
			"the initial row stays selected after the panel settles",
			selected ~= nil and selected.Name == "Demo-all-controls" and t_visible(selected)
		)
		GuiService.SelectedObject = nil
	end,
})

return cases
