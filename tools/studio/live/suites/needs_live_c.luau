--!strict
local GuiService = game:GetService("GuiService")
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps })
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

local function scenario(t: any, name: string, size: Vector2?, theme: any?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, theme = theme, frames = 20 })
	return stage, built
end

local SWEEP = {
	Vector2.new(390, 844),
	Vector2.new(768, 1024),
	Vector2.new(1280, 720),
	Vector2.new(1920, 1080),
}

add("callout-page-lateral-sweep", { "navigation-1-69" }, function(t)
	for _, size in SWEEP do
		local where = `{size.X}x{size.Y}`
		local stage, built = scenario(t, "callout", size)
		built.steps.show()
		t.settle(20)
		local panel = visibleNamed(t, stage, "CalloutPanel")
		t.check(where .. " the tip callout shows", panel ~= nil)
		local found = t.offenders(stage, stage)
		t.check(where .. " nothing crosses a lateral edge with the tip shown", #found.lateral == 0, found.lateral)
		t.check(where .. " no text is clipped with the tip shown", #found.clipped == 0, found.clipped)
		built.steps.use()
		t.settle(10)
		built.steps.showSecond()
		t.settle(20)
		found = t.offenders(stage, stage)
		t.check(where .. " nothing crosses a lateral edge with the second tip", #found.lateral == 0, found.lateral)
		t.cleanup()
	end
end)

add("consumer-parts-have-rects", { "apps2-01" }, function(t)
	local module = storage:FindFirstChild("FacetConsumerScreen")
	t.check("the consumer screen module is present", module ~= nil)
	if not module then
		return
	end
	local screen = (require :: any)(module)
	local stage = t.mount(function(_, _, _, env)
		return screen.build(t.Facet, env.runtime)
	end, { size = Vector2.new(1280, 720), frames = 1 })
	for _, name in { "Title", "Blurb", "Count", "Sound", "Bump", "Close" } do
		local node = t.find(stage, name)
		t.check(
			`{name} has an on-screen rectangle at the first frame`,
			node ~= nil and node.AbsoluteSize.X > 0 and node.AbsoluteSize.Y > 0,
			node and node.AbsoluteSize
		)
		if node then
			t.inside(`{name} inside the screen`, node, stage, 1)
		end
	end
end)

local function radialItems(count: number, long: boolean): { any }
	local list = {}
	for index = 1, count do
		list[index] = {
			id = "item" .. index,
			label = if long then `Summon the travelling merchant {index}` else `Item {index}`,
			onSelect = function() end,
		}
	end
	return list
end

add("radial-list-fallback-fits", { "apps2-191" }, function(t)
	local stage = t.mount(function(UI, _, Compose)
		return UI.RadialMenu "Quick" {
			isPresented = Compose.cell(true),
			clearance = 100,
			items = radialItems(3, true),
		}
	end, { size = Vector2.new(320, 300), frames = 30 })
	local panel = visibleNamed(t, stage, "RadialPanel")
	t.check("the menu presents", panel ~= nil)
	if not panel then
		return
	end
	t.stable(panel)
	t.check(
		"small space presents the list",
		panel:GetAttribute("Presentation") == "list",
		panel:GetAttribute("Presentation")
	)
	local rows = 0
	for _, node in panel:GetDescendants() do
		if node:IsA("TextButton") and t.visible(node) and string.find(node.ContentText, "merchant", 1, true) then
			rows += 1
			t.check(`row {node.Name} label fits`, t.fits(node), { bounds = node.TextBounds, size = node.AbsoluteSize })
			t.check(`row {node.Name} at least 44 px`, node.AbsoluteSize.Y >= 43.5, node.AbsoluteSize)
		end
	end
	t.check("three rows show", rows == 3, rows)
	t.inside("the list inside the screen", panel, stage, 1)
end)

interactive("radial-list-scrolls-selection-into-view", { "apps2-191" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, _, Compose)
		return UI.RadialMenu "Quick" {
			isPresented = Compose.cell(true),
			items = radialItems(12, false),
		}
	end, { size = Vector2.new(420, 200), frames = 30 })
	value.panel = visibleNamed(t, stage, "RadialPanel")
	t.check(
		"a 420x200 space presents the list",
		value.panel ~= nil and value.panel:GetAttribute("Presentation") == "list"
	)
	value.visited = {}
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		if selected and value.panel then
			local s, w = t.rect(selected), value.panel.AbsolutePosition
			local window = value.panel.AbsoluteWindowSize
			table.insert(value.visited, {
				name = selected.Name,
				inside = s.y >= w.Y - 0.5 and s.b <= w.Y + window.Y + 0.5,
			})
		end
	end)
	t.note("selection at open", selectedName())
	return value
end, {
	afterDown = function(t, value)
		value.connection:Disconnect()
		local names, outside = {}, {}
		for _, entry in value.visited do
			table.insert(names, entry.name)
			if not entry.inside then
				table.insert(outside, entry.name)
			end
		end
		t.note("Down visits", names)
		t.check("Down walks the rows", #names >= 10, names)
		t.check("each selected row lies inside the list window", #outside == 0, outside)
		t.check("the list scrolled", value.panel.CanvasPosition.Y > 0, value.panel.CanvasPosition)
		GuiService.SelectedObject = nil
	end,
})

local QUICK = {
	Vector2.new(359, 718),
	Vector2.new(844, 390),
	Vector2.new(320, 568),
	Vector2.new(600, 320),
}

add("quick-actions-ring-fits-phones", { "apps2-194" }, function(t)
	for _, size in QUICK do
		local where = `{size.X}x{size.Y}`
		local stage, built = scenario(t, "radial_menu", size)
		for _, step in { "corner", "character" } do
			built.steps[step]()
			t.settle(6)
			built.steps.open()
			t.settle(30)
			local panel = visibleNamed(t, stage, "RadialPanel")
			t.check(`{where} {step} menu presents`, panel ~= nil)
			if panel then
				t.stable(panel)
				t.note(`{where} {step} presentation`, panel:GetAttribute("Presentation"))
				local found = t.offenders(panel, stage)
				t.check(`{where} {step} menu items inside the screen`, #found.lateral + #found.vertical == 0, found)
				t.check(`{where} {step} no clipped labels`, #found.clipped == 0, found.clipped)
			end
			built.steps.close()
			t.settle(20)
		end
		built.steps.orbit()
		built.steps.move()
		t.settle(6)
		built.steps.open()
		t.settle(30)
		local panel = visibleNamed(t, stage, "RadialPanel")
		local kinds = {}
		for _ = 1, 20 do
			t.settle(15)
			if panel then
				kinds[tostring(panel:GetAttribute("Presentation"))] = true
			end
		end
		t.note(`{where} wandering presentations`, kinds)
		if size.Y >= 390 then
			t.check(`{where} a wandering explorer keeps the ring`, kinds.radial == true and kinds.list == nil, kinds)
		end
		t.cleanup()
	end
end)

add("character-commands-ring-or-list", { "apps2-224" }, function(t)
	for _, entry in
		{
			{ size = Vector2.new(1280, 720), kind = "radial" },
			{ size = Vector2.new(960, 540), kind = "radial" },
			{ size = Vector2.new(800, 600), kind = "radial" },
			{ size = Vector2.new(677, 338), kind = "list" },
		}
	do
		local where = `{entry.size.X}x{entry.size.Y}`
		local stage, built = scenario(t, "radial_menu", entry.size)
		built.steps.character()
		t.settle(6)
		built.steps.open()
		t.settle(30)
		local panel = visibleNamed(t, stage, "RadialPanel")
		t.check(where .. " character commands present", panel ~= nil)
		if panel then
			t.stable(panel)
			t.check(
				`{where} presents the {entry.kind}`,
				panel:GetAttribute("Presentation") == entry.kind,
				panel:GetAttribute("Presentation")
			)
			local found = t.offenders(panel, stage)
			t.check(where .. " every item inside the screen", #found.lateral + #found.vertical == 0, found)
		end
		t.cleanup()
	end
end)

interactive("category-strip-dpad-keeps-page", { "apps2-225" }, function(t)
	local value = {}
	local stage, context = t.gallery({ size = Vector2.new(1280, 800), demo = "all-controls" })
	value.stage, value.context = stage, context
	t.settle(20)
	value.basics = visibleNamed(t, stage, "basics")
	value.inputs = visibleNamed(t, stage, "inputs")
	t.check("Basics and Inputs buttons found", value.basics ~= nil and value.inputs ~= nil)
	GuiService.SelectedObject = value.basics
	return value
end, {
	afterBasicsRight = function(t, value)
		t.check("DPadRight from Basics selects Writing", selectedName() == "writing", selectedName())
		GuiService.SelectedObject = value.inputs
	end,
	afterInputsRight = function(t, value)
		t.check("DPadRight from Inputs selects Actions", selectedName() == "actions", selectedName())
		t.check(
			"the strip buttons were not rebuilt",
			value.basics.Parent ~= nil and visibleNamed(t, value.stage, "inputs") == value.inputs
		)
		GuiService.SelectedObject = nil
	end,
})

local PICKER_STYLES = { "automatic", "segmented", "inline", "radioGroup", "navigationLink", "menu" }
local PICKER_SIZES = {
	Vector2.new(390, 844),
	Vector2.new(844, 390),
	Vector2.new(1080, 810),
	Vector2.new(1280, 720),
	Vector2.new(1920, 1080),
}

add("picker-style-sweep", { "navigation-3-85" }, function(t)
	local options = {
		{ value = "a", label = "Arcade handling" },
		{ value = "b", label = "Simulation handling" },
		{ value = "c", label = "Drift assist" },
		{ value = "d", label = "Rally gravel" },
	}
	for _, theme in t.themes do
		for _, size in PICKER_SIZES do
			for _, style in PICKER_STYLES do
				local where = `{theme.name} {size.X}x{size.Y} {style}`
				local opened
				local stage = t.mount(function(UI, Host, Compose)
					opened = Compose.cell(false)
					return Host.Frame "Column" {
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
						UI.Picker "Handling" {
							label = "Handling",
							style = style,
							selected = Compose.cell("b"),
							options = options,
							isPresented = opened,
							query = if style == "navigationLink" then Compose.cell("") else nil,
							LayoutOrder = 1,
						},
						UI.Text "Below" { text = "Neighbour", LayoutOrder = 2 },
					}
				end, { theme = theme.package, size = size, frames = 12 })
				local picker, below = t.find(stage, "Handling"), t.find(stage, "Below")
				t.stable(picker)
				t.check(where .. " closed picker clear of its neighbour", not overlap(t.rect(picker), t.rect(below)), {
					picker = t.rect(picker),
					below = t.rect(below),
				})
				local found = t.offenders(picker, stage)
				t.check(where .. " closed picker inside the screen", #found.lateral == 0, found.lateral)
				t.check(where .. " closed picker text not clipped", #found.clipped == 0, found.clipped)
				if style == "menu" then
					opened:set(true)
					t.settle(20)
					local panel = visibleNamed(t, stage, "MenuPanel") or visibleNamed(t, stage, "SheetPanel")
					t.check(where .. " open panel shows", panel ~= nil)
					if panel then
						t.stable(panel)
						t.inside(where .. " open panel inside the screen", panel, stage, 1)
						local rows = {}
						for _, node in panel:GetDescendants() do
							if node:IsA("TextButton") and t.visible(node) and node.ContentText ~= "" then
								table.insert(rows, t.rect(node))
							end
						end
						local crossed = 0
						for i = 1, #rows do
							for j = i + 1, #rows do
								if overlap(rows[i], rows[j]) then
									crossed += 1
								end
							end
						end
						t.check(where .. " open rows do not overlap", crossed == 0, crossed)
					end
				end
				t.cleanup()
			end
		end
	end
end)

interactive("grabber-activation-cycles-detents", { "navigation-4-38" }, function(t)
	local value = { detents = {} }
	t.mount(function(UI, _, Compose)
		value.detent = Compose.cell("medium")
		return UI.Sheet({
			isPresented = Compose.cell(true),
			detent = value.detent,
			detents = { "medium", "large", { id = "short", height = 260 } },
			title = "Loadout",
			content = function()
				return UI.Text({ text = "Pick a loadout" })
			end,
		})
	end, { frames = 20 })
	local gui = game:GetService("Players").LocalPlayer.PlayerGui
	value.grabber = visibleNamed(t, gui, "Grabber")
	t.check("the grabber shows", value.grabber ~= nil)
	GuiService.SelectedObject = value.grabber
	t.check("the grabber accepts selection", selectedName() == "Grabber", selectedName())
	return value
end, {
	afterFirst = function(t, value)
		t.check("the first press moves to large", value.detent:peek() == "large", value.detent:peek())
	end,
	afterSecond = function(t, value)
		t.check("the second press moves to the height entry", value.detent:peek() == "short", value.detent:peek())
	end,
	afterThird = function(t, value)
		t.check("the third press wraps to medium", value.detent:peek() == "medium", value.detent:peek())
		GuiService.SelectedObject = nil
	end,
})

add("nested-tabs-fit-a-short-screen", { "navigation-4-60" }, function(t)
	local stage, context = t.gallery({ size = Vector2.new(640, 320), demo = "all-controls" })
	t.settle(10)
	local navigation = visibleNamed(t, stage, "navigation")
	if navigation then
		(navigation :: any):SetAttribute("FacetLiveProbe", true)
	end
	t.check("the Navigation category exists", navigation ~= nil)
	local report = context.dispatch("report")
	t.note("report", report and report.current)
	local found = t.offenders(stage, stage)
	t.check("no tab label is clipped at 640x320", #found.clipped == 0, found.clipped)
	t.check("nothing crosses a lateral edge at 640x320", #found.lateral == 0, found.lateral)
	local body = t.find(stage, "Page") or t.find(stage, "Content")
	t.note("page body", body and body.AbsoluteSize)
	t.note("preferred text size", t.environment.preferredTextSize)
end)

add("virtual-list-clamps-across-tabs", { "navigation-4-68" }, function(t)
	local rows, selection
	local stage = t.mount(function(UI, Host, Compose)
		rows = Compose.cell((function()
			local list = {}
			for index = 1, 100 do
				list[index] = { id = tostring(index) }
			end
			return list
		end)())
		selection = Compose.cell("a")
		return UI.TabView "Tabs" {
			selection = selection,
			Size = UDim2.fromOffset(400, 360),
			tabs = {
				{
					id = "a",
					label = "List",
					content = function()
						return UI.VirtualList "List" {
							from = rows,
							key = function(item)
								return item.id
							end,
							itemSize = 100,
							Size = UDim2.fromOffset(300, 300),
							render = function(current)
								return UI.Text({ text = "Row " .. current:peek().id, Size = UDim2.fromScale(1, 1) })
							end,
						}
					end,
				},
				{
					id = "b",
					label = "Other",
					content = function()
						return Host.Frame({ Size = UDim2.fromOffset(10, 10) })
					end,
				},
			},
		}
	end, { size = Vector2.new(600, 500), frames = 20 })
	local list = visibleNamed(t, stage, "List")
	if not list then
		t.check("the list mounts", false)
		return
	end
	list.CanvasPosition = Vector2.new(0, 2050)
	t.settle(6)
	t.near("the list scrolled to 2050", list.CanvasPosition.Y, 2050, 1)
	selection:set("b")
	t.settle(6)
	local eight = {}
	for index = 1, 8 do
		eight[index] = { id = tostring(index) }
	end
	rows:set(eight)
	t.settle(6)
	selection:set("a")
	t.settle(12)
	list = visibleNamed(t, stage, "List")
	local maximum = list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y
	t.near("shorter data clamps to the new maximum", list.CanvasPosition.Y, maximum, 1)
	selection:set("b")
	t.settle(6)
	rows:set({})
	t.settle(6)
	selection:set("a")
	t.settle(12)
	list = visibleNamed(t, stage, "List")
	t.near("empty data returns to the top", list and list.CanvasPosition.Y or -1, 0, 0.5)
end)

add("type-roles-compile-to-native-fonts", { "paint-148" }, function(t)
	local roles = t.Facet.themes.TYPE_ROLES
	for _, theme in t.themes do
		local labels = {}
		local stage = t.mount(function(UI, Host)
			local children = { Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }) }
			for index, role in roles do
				local label = UI.Text({ Name = role, text = "Sample " .. role, textRole = role, LayoutOrder = index })
				labels[role] = label
				table.insert(children, label)
			end
			return Host.Frame { Size = UDim2.fromOffset(600, 600), BackgroundTransparency = 1, table.unpack(children) }
		end, { theme = theme.package, size = Vector2.new(600, 600), frames = 10 })
		local typography = theme.package.metrics.typography
		for _, role in roles do
			local label = labels[role]
			local spec = typography[role]
			if label and spec then
				t.check(
					`{theme.name} {role} carries its role tag`,
					label:HasTag("facet-type-" .. role),
					label:GetTags()
				)
				t.near(`{theme.name} {role} TextSize`, label:GetStyled("TextSize"), spec.size, 0.01)
				local face = label:GetStyled("FontFace")
				t.check(`{theme.name} {role} FontFace weight`, face.Weight.Name ~= "", tostring(face))
				t.check(
					`{theme.name} {role} TextBounds follow the size`,
					label.TextBounds.Y >= spec.size * 0.9,
					label.TextBounds
				)
			end
		end
		t.cleanup()
	end
end)

return cases
