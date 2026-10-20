--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function cell(Host: any, name: string, size: UDim2): any
	return Host.Frame(name)({ Size = size, BackgroundTransparency = 0.5 })
end

add("scroll-view-canvas-covers-rows-and-gaps", {}, function(t: any)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		return UI.ScrollView "List" {
			gap = 10,
			Size = UDim2.fromOffset(300, 100),
			cell(Host, "A", UDim2.fromOffset(300, 40)) :: unknown,
			cell(Host, "B", UDim2.fromOffset(300, 40)),
			cell(Host, "C", UDim2.fromOffset(300, 40)),
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local list = t.find(stage, "List")
	local a, c = t.find(list, "A"), t.find(list, "C")
	local padding = list:FindFirstChildWhichIsA("UIPadding")
	local vertical = if padding
		then padding:GetStyled("PaddingTop").Offset + padding:GetStyled("PaddingBottom").Offset
		else 0
	t.near("the canvas holds three rows and two gaps", list.AbsoluteCanvasSize.Y, 140 + vertical, 1)
	t.near("rows advance by their height plus the gap", c.AbsolutePosition.Y - a.AbsolutePosition.Y, 100, 1)
	t.check("the overflowing list scrolls", list.AbsoluteCanvasSize.Y > list.AbsoluteWindowSize.Y)
end)

add("horizontal-scroll-view-steps-along-x", {}, function(t: any)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		local cells = {}
		for index = 1, 5 do
			table.insert(cells, cell(Host, "Cell" .. index, UDim2.new(0, 60, 1, 0)))
		end
		return UI.ScrollView "Rail" {
			axis = "x" :: "x",
			gap = 10,
			Size = UDim2.fromOffset(200, 120),
			table.unpack((cells :: unknown) :: { unknown }),
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local rail = t.find(stage, "Rail")
	local first, second = t.find(rail, "Cell1"), t.find(rail, "Cell2")
	local padding = rail:FindFirstChildWhichIsA("UIPadding")
	local horizontal = if padding
		then padding:GetStyled("PaddingLeft").Offset + padding:GetStyled("PaddingRight").Offset
		else 0
	t.near("cells advance along x by width plus gap", second.AbsolutePosition.X - first.AbsolutePosition.X, 70, 1)
	t.near("the canvas extent is horizontal", rail.AbsoluteCanvasSize.X, 340 + horizontal, 1)
	t.near("a full-height cell fills the window height", first.AbsoluteSize.Y, rail.AbsoluteWindowSize.Y, 1)
	t.check("the rail scrolls sideways, not down", rail.AbsoluteCanvasSize.Y <= rail.AbsoluteWindowSize.Y + 1, {
		canvas = rail.AbsoluteCanvasSize,
		window = rail.AbsoluteWindowSize,
	})
end)

add("fill-stack-preserves-overflow-and-recovers", {}, function(t: any)
	for _, theme in t.themes do
		local C = t.Facet.Compose
		local size = C.cell(Vector2.new(390, 600))
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
			return UI.ScrollView "Viewport" {
				UI.VStack "Page" {
					width = "fill" :: "fill",
					height = "fill" :: "fill",
					gap = 0,
					UI.fill() :: unknown,
					Host.Frame { Name = "Header", Size = UDim2.new(1, 0, 0, 500) },
					UI.VStack "Pane" {
						width = "fill" :: "fill",
						height = "fill" :: "fill",
						UI.fill() :: unknown,
						Host.UISizeConstraint { MinSize = Vector2.new(0, 320) },
						UI.Button { Name = "Last", label = "Last item" },
					},
				},
			}
		end, { theme = theme.package, size = size })
		local viewport, page, pane = t.find(stage, "Viewport"), t.find(stage, "Page"), t.find(stage, "Pane")
		for _, height in { 600, 1000, 400, 600 } do
			size:set(Vector2.new(390, height))
			t.settle(30)
			local label = theme.name .. " height " .. height
			t.check(label .. " pane minimum", pane.AbsoluteSize.Y >= 320)
			t.check(label .. " page covers content", page.AbsoluteSize.Y >= 820)
			t.check(label .. " canvas covers page", viewport.AbsoluteCanvasSize.Y >= page.AbsoluteSize.Y - 1)
			local before = page.AbsoluteSize.Y
			t.settle(30)
			t.near(label .. " size settles", page.AbsoluteSize.Y, before)
			viewport.CanvasPosition = Vector2.new(0, 10000)
			t.settle()
			t.check(
				label .. " pane bottom reachable",
				pane.AbsolutePosition.Y + pane.AbsoluteSize.Y
					<= viewport.AbsolutePosition.Y + viewport.AbsoluteWindowSize.Y + 1
			)
		end
	end
end)

add("sheet-content-clears-theme-frame", {}, function(t: any)
	for _, theme in t.themes do
		if theme.name ~= "Neutral" and theme.name ~= "fantasy_parchment" and theme.name ~= "fantasy_ornate" then
			continue
		end
		for _, placement in { "bottom", "side" } do
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, C: any)
				return UI.Sheet {
					title = "Search & options with a title that wraps",
					placement = placement :: any,
					isPresented = C.cell(true),
					detent = C.cell("large"),
					detents = { "large" :: "large" },
					contentInset = "none" :: "none",
					content = function(): Instance
						return Host.Frame { Size = UDim2.new(1, 0, 0, 1000) }
					end,
					actions = { { id = "Done", label = "Done", onActivate = function() end } },
				}
			end, { theme = theme.package, size = Vector2.new(390, 640) })
			t.settle(20)
			local panel = t.find(stage.Parent, "SheetPanel")
			local title = t.find(panel, "Title")
			if t.visible(title) then
				title.TextSize = 32
				t.settle(12)
				t.inside(theme.name .. placement .. " enlarged title", title, title.Parent)
			else
				local caption = t.find(panel, "PlaqueCaption")
				t.check(
					theme.name .. placement .. " skin paints the title",
					t.visible(caption) and caption.Text == title.Text
				)
				t.check(theme.name .. placement .. " skin title fits", t.fits(caption))
				t.inside(theme.name .. placement .. " skin title stays on screen", caption, stage)
			end
			local carve = ((theme.package.chrome or {}).panel or {}).contentInsets or {}
			for _, name in { "Header", "SheetContent", "Actions" } do
				local node = t.find(panel, name)
				local label = theme.name .. " " .. placement .. " " .. name
				t.check(
					label .. " clears left art and spacing",
					node.AbsolutePosition.X - panel.AbsolutePosition.X >= (carve.left or 0) + 16 - 1
				)
				t.check(
					label .. " clears right art and spacing",
					node.AbsolutePosition.X + node.AbsoluteSize.X
						<= panel.AbsolutePosition.X + panel.AbsoluteSize.X - (carve.right or 0) - 16 + 1
				)
				t.inside(label .. " stays in panel", node, panel)
			end
		end
	end
end)

table.insert(cases, {
	id = "files-nested-touch-handoff",
	contracts = {},
	keepGallery = true,
	setup = function(t: any)
		workspace.FacetShowcaseAPI:Invoke("show", "files")
		t.settle(20)
		local layer = game:GetService("Players").LocalPlayer.PlayerGui.FacetGallery
		local outer = t.find(layer, "FileViewport")
		local inner = t.find(outer, "primary")
		return { outer = outer, inner = inner, before = 0, edge = 0 }
	end,
	steps = {
		top = function(t: any, s: any)
			s.inner:ResetScrollVelocity()
			s.outer:ResetScrollVelocity()
			s.inner.CanvasPosition = Vector2.zero
			s.outer.CanvasPosition = Vector2.new(0, 100)
			t.settle(10)
			s.before = s.outer.CanvasPosition.Y
			s.edge = s.inner.CanvasPosition.Y
			t.check("outer has room toward top", s.before > 20)
		end,
		upstream = function(t: any, s: any)
			t.settle(30)
			t.check("swipe over file tile scrolls outer toward top", s.outer.CanvasPosition.Y < s.before - 20)
			t.near("inner stays at top", s.inner.CanvasPosition.Y, s.edge, 2)
			t.check("touch release restores inner", s.inner.ScrollingEnabled)
		end,
		bottom = function(t: any, s: any)
			s.inner:ResetScrollVelocity()
			s.outer:ResetScrollVelocity()
			s.outer.CanvasPosition = Vector2.new(0, 20)
			for _ = 1, 3 do
				s.inner.CanvasPosition = Vector2.new(0, 1000000)
				t.settle(10)
			end
			t.near(
				"inner starts at bottom",
				s.inner.CanvasPosition.Y,
				s.inner.AbsoluteCanvasSize.Y - s.inner.AbsoluteWindowSize.Y,
				2
			)
			s.before = s.outer.CanvasPosition.Y
			s.edge = s.inner.CanvasPosition.Y
			t.check(
				"outer has room toward bottom",
				s.outer.AbsoluteCanvasSize.Y - s.outer.AbsoluteWindowSize.Y > s.before + 20
			)
		end,
		downstream = function(t: any, s: any)
			t.settle(30)
			t.check("swipe over file tile scrolls outer toward bottom", s.outer.CanvasPosition.Y > s.before + 20)
			t.near("inner stays at bottom", s.inner.CanvasPosition.Y, s.edge, 2)
			t.check("touch release restores inner", s.inner.ScrollingEnabled)
		end,
	},
})

add("selected-scroll-rows", {}, function(t)
	local gui = game:GetService("GuiService")
	local select
	local stage = t.mount(function(UI: FacetControls, _: RobloxHost, C)
		local target = C.cell(nil :: GuiObject?)
		C.watch(function(use)
			gui.SelectedObject = use(target)
		end)
		select = function(node: GuiObject)
			target:set(node)
		end
		local rows = {}
		for index = 1, 16 do
			table.insert(rows, UI.Button("Row" .. index)({ label = "Row " .. index, Size = UDim2.fromOffset(260, 44) }))
		end
		return UI.ScrollView "List" { Size = UDim2.fromOffset(300, 200), gap = 8, table.unpack(rows) }
	end, { size = Vector2.new(400, 400), frames = 30 })
	require(game:GetService("ReplicatedStorage").FacetLive).press({ "LeftShift" })
	local list = t.find(stage, "List")
	for _, index in { 1, 5, 10, 16, 10, 5, 1 } do
		local row = t.find(list, "Row" .. index)
		select(row)
		local samples = {}
		for frame = 1, 6 do
			t.settle(1)
			local top = row.AbsolutePosition.Y - list.AbsolutePosition.Y
			table.insert(samples, { top = top, canvas = list.CanvasPosition.Y })
			t.check(
				"row " .. index .. " frame " .. frame,
				top >= -1 and top + row.AbsoluteSize.Y <= list.AbsoluteWindowSize.Y + 1,
				samples
			)
		end
		t.note("row " .. index, samples)
	end
	gui.SelectedObject = nil
end)

add("compact-gallery-selected-rects", {}, function(t)
	local gui = game:GetService("GuiService")
	for _, page in { "garage", "hud" } do
		local stage, context = t.gallery({ size = Vector2.new(390, 400), demo = page })
		context.dispatch("input", "Gamepad")
		t.settle(30)
		require(game:GetService("ReplicatedStorage").FacetLive).press({ "LeftShift" })
		local nodes = {}
		for _, node in stage:GetDescendants() do
			if
				node:IsA("GuiButton")
				and node.Selectable
				and t.visible(node)
				and node:FindFirstAncestorWhichIsA("ScrollingFrame")
			then
				table.insert(nodes, node)
			end
		end
		table.sort(nodes, function(a, b)
			return a.AbsolutePosition.Y < b.AbsolutePosition.Y
		end)
		for _, node in nodes do
			gui.SelectedObject = node
			local samples = {}
			for frame = 1, 6 do
				t.settle(1)
				local ancestor = node:FindFirstAncestorWhichIsA("ScrollingFrame")
				local top = node.AbsolutePosition.Y - ancestor.AbsolutePosition.Y
				table.insert(samples, {
					top = top,
					h = node.AbsoluteSize.Y,
					window = ancestor.AbsoluteWindowSize.Y,
					canvas = ancestor.CanvasPosition.Y,
					path = node:GetFullName(),
				})
				t.check(
					page .. " " .. node.Name .. " frame " .. frame,
					top >= -1 and top + node.AbsoluteSize.Y <= ancestor.AbsoluteWindowSize.Y + 1,
					samples
				)
			end
			t.note(page .. " " .. node.Name, samples)
		end
		gui.SelectedObject = nil
	end
end)

add("sipworks-native-selection-reveals-cards", {}, function(t)
	local gui = game:GetService("GuiService")
	for _, sample in
		{
			{ size = Vector2.new(1688, 792), distance = "ten-foot" },
			{ size = Vector2.new(390, 400), distance = "near" },
		}
	do
		local size = sample.size
		local stage, context = t.gallery({ size = size, demo = "sipworks" })
		context.viewingDistance:set(sample.distance)
		context.dispatch("input", "Gamepad")
		t.settle(30)
		local viewport = context.environmentFacts.viewportSize:peek()
		t.near(`{size} preview viewport width`, viewport.X, size.X, 0.5)
		t.near(`{size} preview viewport height`, viewport.Y, size.Y, 0.5)
		require(game:GetService("ReplicatedStorage").FacetLive).press({ "LeftShift" })
		local seen: { [Instance]: boolean } = {}
		local count = 0
		for _ = 1, 20 do
			local nodes: { GuiObject } = {}
			for _, node in stage:GetDescendants() do
				if
					node.Name == "Body"
					and node:IsA("GuiButton")
					and node.Selectable
					and t.visible(node)
					and not seen[node]
				then
					table.insert(nodes, node)
				end
			end
			table.sort(nodes, function(a, b)
				return a.AbsolutePosition.Y < b.AbsolutePosition.Y
			end)
			local node = nodes[1]
			if not node then
				break
			end
			seen[node] = true
			count += 1
			gui.SelectedObject = node
			for frame = 1, 8 do
				t.settle(1)
				local clipped = t.clipped(node)
				t.check(
					`{size} card {count} frame {frame} stays visible and selected`,
					t.visible(node) and gui.SelectedObject == node and clipped ~= nil,
					{ path = node:GetFullName(), rect = t.rect(node), clipped = clipped }
				)
			end
		end
		t.check("the probe reaches recipe cards", count >= 5, count)
		gui.SelectedObject = nil
		t.cleanup()
	end
	local errors = {}
	for _, message in game:GetService("LogService"):GetLogHistory() do
		if
			message.messageType == Enum.MessageType.MessageError and string.find(message.message, "LayoutUnit", 1, true)
		then
			table.insert(errors, message.message)
		end
	end
	t.check("screens release layout probes without native errors", #errors == 0, errors)
end)

add("table-header-uses-native-scroll-window", {}, function(t)
	local stage = t.mount(function(UI: FacetControls)
		return UI.Table "Data" {
			from = { { id = "one", name = "First" } },
			key = "id",
			Size = UDim2.fromOffset(180, 200),
			columns = {
				{ id = "name", label = "Name", width = 260 },
				{ id = "id", label = "Identifier", width = 140 },
			},
		}
	end, { size = Vector2.new(400, 300), frames = 60 })
	local tableNode = assert(stage:FindFirstChild("Data"))
	local body = assert(tableNode:FindFirstChild("Body")) :: ScrollingFrame
	local header = assert(tableNode:FindFirstChild("Header")) :: ScrollingFrame
	t.check("the header uses a native scroll window", header:IsA("ScrollingFrame"))
	t.near("the header window matches the body window", header.AbsoluteWindowSize.X, body.AbsoluteWindowSize.X, 1)
	t.check("the columns keep their full width", header.AbsoluteCanvasSize.X >= 400)
	body.CanvasPosition = Vector2.new(10000, 0)
	t.settle(6)
	t.check("the body scrolls sideways", body.CanvasPosition.X > 0)
	t.near("the header follows the body", header.CanvasPosition.X, body.CanvasPosition.X, 0.5)
	body.CanvasPosition = Vector2.zero
	t.settle(6)
	local last = assert(header:FindFirstChild("id")):FindFirstChild("Sort") :: GuiObject
	game:GetService("GuiService").SelectedObject = last
	t.settle(12)
	t.near("native selection keeps both windows aligned", header.CanvasPosition.X, body.CanvasPosition.X, 0.5)
	t.check("the selected heading is visible", t.clipped(last) ~= nil)
	game:GetService("GuiService").SelectedObject = nil
end)

add("table-columns-stay-stable-when-vertical-overflow-changes", {}, function(t)
	local setRows: ((number) -> ())? = nil
	local stage = t.mount(function(UI: FacetControls, _Host: RobloxHost, Compose: ComposeModule)
		local count = Compose.cell(1)
		setRows = function(value: number)
			count:set(value)
		end
		return UI.Table "Data" {
			from = function(use: Use)
				local rows = {}
				for index = 1, use(count) do
					table.insert(rows, { id = tostring(index), name = "Track" })
				end
				return rows
			end,
			key = "id",
			Size = UDim2.fromOffset(354, 200),
			columns = {
				{ id = "name", label = "Name", minWidth = 220 },
				{ id = "id", label = "Rating", minWidth = 130, priority = 1 },
			},
		}
	end, { size = Vector2.new(400, 300), frames = 60 })
	local tableNode = assert(stage:FindFirstChild("Data"))
	local body = assert(tableNode:FindFirstChild("Body")) :: ScrollingFrame
	local rating = assert(assert(tableNode:FindFirstChild("Header")):FindFirstChild("id")) :: GuiObject
	local shown = rating.Visible
	t.check("the first collection fits vertically", body.AbsoluteCanvasSize.Y <= body.AbsoluteWindowSize.Y)
	assert(setRows)(20)
	t.settle(60)
	t.check("the expanded collection scrolls vertically", body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y)
	t.check("vertical overflow preserves the responsive columns", rating.Visible == shown)
	assert(setRows)(1)
	t.settle(60)
	t.check("removing vertical overflow preserves the responsive columns", rating.Visible == shown)
end)

add("keyboard-selection-keeps-pointer-drag-surfaces-out-of-navigation", {}, function(t)
	local stage = t.mount(
		function(
			UI: FacetControls,
			_Host: RobloxHost,
			Compose: typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		)
			return UI.Table "Data" {
				from = { { id = "one", name = "First" }, { id = "two", name = "Second" } },
				key = "id",
				Size = UDim2.fromOffset(400, 250),
				columns = {
					{ id = "name", label = "Name", width = 180 },
					{ id = "id", label = "Identifier", width = 140 },
				},
				selection = Compose.cell({} :: { [string]: boolean }),
				selectionMode = "single" :: "single",
				reorderable = true,
				onReorder = function() end,
				rowActions = function(): typeof(require("@repo/tools/typecheck/aliases").RowActionsOptions)
					return { trailing = { { id = "delete", label = "Delete", onActivate = function() end } } }
				end,
			}
		end,
		{ size = Vector2.new(500, 400), frames = 60 }
	)
	local gui = game:GetService("GuiService")
	local input = game:GetService("UserInputService")
	type Virtual = { SendMousePosition: (Virtual, Vector2) -> () }
	local virtual = ((input :: unknown) :: { CreateVirtualInput: (unknown) -> Virtual }):CreateVirtualInput()
	local live = require(game:GetService("ReplicatedStorage").FacetLive)
	local first = assert(stage:FindFirstChild("one", true)):FindFirstChild("RowHit", true) :: GuiObject
	local second = assert(stage:FindFirstChild("two", true)):FindFirstChild("RowHit", true) :: GuiObject
	local detector = assert(stage:FindFirstChild("FacetCollectionDrag", true)) :: UIDragDetector
	local inset = gui:GetGuiInset()
	for index, key in { "Up", "Down", "Left", "Right" } do
		virtual:SendMousePosition(stage.AbsolutePosition + inset + Vector2.new(8 + index, 8))
		t.settle(3)
		t.check("pointer movement enables native drag", detector.Enabled)
		gui.SelectedObject = first
		t.settle(2)
		live.press({ key })
		t.settle(3)
		local selected = gui.SelectedObject
		t.check("keyboard selection uses a selectable target", selected ~= nil and selected.Selectable, selected)
		t.check("keyboard navigation disables pointer drag", not detector.Enabled)
		if key == "Down" then
			t.check("Down reaches the next row", selected == second, selected)
		end
	end
	local header = assert(assert(stage:FindFirstChild("Data")):FindFirstChild("Header"))
	local firstColumn = assert(header:FindFirstChild("name")) :: GuiObject
	local firstHeading = assert(firstColumn:FindFirstChild("Sort")) :: GuiObject
	local secondHeading = assert(assert(header:FindFirstChild("id")):FindFirstChild("Sort")) :: GuiObject
	gui.SelectedObject = firstHeading
	live.press({ "Right" })
	t.settle(3)
	t.check("Right reaches the next heading", gui.SelectedObject == secondHeading)
	local lastColumn = secondHeading.Parent :: GuiObject
	local width = lastColumn.AbsoluteSize.X
	live.press({ "Period" })
	t.settle(3)
	t.check("a heading keeps keyboard resize", lastColumn.AbsoluteSize.X > width)
	live.press({ "Comma" })
	t.settle(3)
	t.near("keyboard resize can restore the width", lastColumn.AbsoluteSize.X, width, 1)
	virtual:SendMousePosition(stage.AbsolutePosition + inset + Vector2.new(20, 8))
	t.settle(3)
	t.check("pointer drag resumes after keyboard navigation", detector.Enabled)
	gui.SelectedObject = nil
end)

add("inline-color-picker-keeps-keyboard-selection-in-the-page", {}, function(t)
	local stage = t.mount(function(UI: FacetControls, _Host: RobloxHost, Compose: ComposeModule)
		return UI.ScrollView "Page" {
			Size = UDim2.fromOffset(380, 190),
			gap = 16,
			UI.Toggle "Before" { label = "Refuse changes", value = Compose.cell(false) } :: unknown,
			UI.ColorPicker "Accent" {
				label = "Accent",
				style = "inline" :: "inline",
				modes = { "spectrum" :: "spectrum" },
				value = Color3.new(1, 0, 0),
				onChange = function() end,
			},
		}
	end, { size = Vector2.new(500, 400), frames = 60 })
	local gui = game:GetService("GuiService")
	local live = require(game:GetService("ReplicatedStorage").FacetLive)
	local before = assert(stage:FindFirstChild("Before", true)) :: GuiObject
	local plane = assert(assert(stage:FindFirstChild("Plane", true)):FindFirstChild("Surface")) :: GuiObject
	live.press({ "LeftShift" })
	gui.SelectedObject = plane
	t.settle(10)
	live.press({ "Up" })
	t.settle(10)
	t.check("Up leaves the inline technique for the previous page control", gui.SelectedObject == before)
	live.press({ "Down" })
	t.settle(10)
	t.check("Down returns to the inline technique", gui.SelectedObject == plane)
	gui.SelectedObject = nil
end)

return cases
