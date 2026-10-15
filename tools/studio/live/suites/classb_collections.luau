--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type SideCell = typeof(require("@repo/tools/typecheck/aliases").SideCell)
type SortCell = typeof(require("@repo/tools/typecheck/aliases").SortCell)
type RowActions = typeof(require("@repo/tools/typecheck/aliases").RowActions)
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

local function interactive(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps })
end

local function rows(count: number): { any }
	local out = {}
	for index = 1, count do
		out[index] = { id = "r" .. index, name = "Row " .. index, artist = "Artist " .. index, laps = index }
	end
	return out
end

local function rowOf(root: Instance, key: string): any
	local items = root:FindFirstChild("Items", true)
	return if items then items:FindFirstChild(key) else nil
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function selectedRow(): string
	local node: Instance? = GuiService.SelectedObject
	while node do
		if node.Parent and node.Parent.Name == "Items" then
			return node.Name
		end
		node = node.Parent
	end
	return "nil"
end

local function watchSelection(value: any)
	value.visited = {}
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local node: Instance? = GuiService.SelectedObject
		if node then
			table.insert(value.visited, node)
		end
	end)
end

local function hitOrder(at: Vector2): { GuiObject }
	return (Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui):GetGuiObjectsAtPosition(at.X, at.Y)
end

local function theme(t: any, pattern: string): any
	for _, entry in t.themes do
		if string.find(string.lower(entry.name), pattern, 1, true) then
			return entry
		end
	end
	return nil
end

add("cross-axis-fills-the-window", {}, function(t)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		return Host.Frame "Panes" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.Frame "Rail" {
				Size = UDim2.fromOffset(600, 200),
				BackgroundTransparency = 1,
				UI.VirtualList "Horizontal" {
					from = rows(40),
					key = "id",
					itemSize = 120,
					direction = "horizontal" :: "horizontal",
					render = function(current)
						return UI.Text({ text = current:peek().name })
					end,
				},
			} :: unknown,
			Host.Frame "Column" {
				Position = UDim2.fromOffset(640, 0),
				Size = UDim2.fromOffset(320, 400),
				BackgroundTransparency = 1,
				UI.VirtualList "Vertical" {
					from = rows(40),
					key = "id",
					itemSize = 48,
					render = function(current)
						return UI.Text({ text = current:peek().name })
					end,
				},
			},
		}
	end, { size = Vector2.new(1000, 500), frames = 20 })
	local horizontal = t.find(stage, "Horizontal")
	local vertical = t.find(stage, "Vertical")
	local card = rowOf(horizontal, "r2")
	local line = rowOf(vertical, "r2")
	t.check("the horizontal list mounted r2", card ~= nil)
	t.check("the vertical list mounted r2", line ~= nil)
	if not card or not line then
		return
	end
	t.note("horizontal window", horizontal.AbsoluteWindowSize)
	t.note("vertical window", vertical.AbsoluteWindowSize)
	t.near("a horizontal item is as tall as the list window", card.AbsoluteSize.Y, horizontal.AbsoluteWindowSize.Y, 0.5)
	t.check(
		"the horizontal window is the 200 px pane less at most a scroll bar",
		horizontal.AbsoluteWindowSize.Y >= 190
	)
	t.near("a horizontal item keeps its main extent", card.AbsoluteSize.X, 120, 0.5)
	t.near("a vertical row is as wide as the list window", line.AbsoluteSize.X, vertical.AbsoluteWindowSize.X, 0.5)
	t.check("the vertical window is the 320 px pane less at most a scroll bar", vertical.AbsoluteWindowSize.X >= 310)
	t.near("a vertical row keeps its main extent", line.AbsoluteSize.Y, 48, 0.5)
	local label = card:FindFirstChildWhichIsA("TextLabel", true)
	t.check("the content fills the item cross axis", label ~= nil and label.Parent ~= nil)
end)

add("fill-column-floors-and-hit-order", {}, function(t)
	local function mount(width: number, columns: { any }, widths: any?): any
		t.cleanup()
		return t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
			return UI.Table "Racers" {
				from = rows(6),
				key = "id",
				selectionMode = "single" :: "single",
				widths = widths or Compose.cell({}),
				columns = columns,
			}
		end, { size = Vector2.new(width, 400), frames = 20 })
	end
	local function width(stage: any, id: string): number
		local header = t.find(stage, "Header")
		local node = header and header:FindFirstChild(id)
		return if node then node.AbsoluteSize.X else -1
	end
	local narrow = mount(300, {
		{ id = "name", label = "Name", minWidth = 120, priority = "always" },
		{ id = "artist", label = "Artist", minWidth = 100, priority = "always" },
		{ id = "laps", label = "Laps", width = 96, priority = "always" },
	})
	t.note("narrow widths", { width(narrow, "name"), width(narrow, "artist"), width(narrow, "laps") })
	t.near("at 300 px the name floor binds at 120", width(narrow, "name"), 120, 0.5)
	t.near("at 300 px the artist floor binds at 100", width(narrow, "artist"), 100, 0.5)
	t.near("the fixed column keeps 96", width(narrow, "laps"), 96, 0.5)
	local mixed = mount(300, {
		{ id = "name", label = "Name", priority = "always" },
		{ id = "artist", label = "Artist", minWidth = 200, priority = "always" },
	})
	local header = t.find(mixed, "Header")
	t.note("mixed widths", { width(mixed, "name"), width(mixed, "artist"), header.AbsoluteSize.X })
	t.check("the floored fill never goes below its floor", width(mixed, "artist") >= 199.5, width(mixed, "artist"))
	t.near(
		"the two fills take the whole header between them",
		width(mixed, "name") + width(mixed, "artist"),
		header.AbsoluteSize.X,
		0.5
	)
	local primaryFloor = 48
	local textInsets = t.find(mixed, "CellTextInsets")
	t.check("the primary column has its native inset probe", textInsets ~= nil)
	local firstRow = nil
	for _, node in t.find(mixed, "Body"):GetDescendants() do
		if node.Name == "Row" and node:IsA("GuiObject") and t.visible(node) then
			local cell = node:FindFirstChild("name", true)
			local natural = cell and cell:FindFirstChild("Undisclosed", true)
			local value = cell and cell:FindFirstChild("Value", true)
			if natural and value then
				local padding = value:FindFirstChildWhichIsA("UIPadding")
				local inset = if padding
					then padding:GetStyled("PaddingLeft").Offset + padding:GetStyled("PaddingRight").Offset
					else math.max(16, if textInsets then textInsets.AbsoluteSize.X else 0)
				primaryFloor = math.max(primaryFloor, math.ceil(natural.TextBounds.X) + inset)
				t.check("primary row text fits before the remaining width is shared", value.TextFits)
				firstRow = node
			end
		end
	end
	t.note("measured primary floor", primaryFloor)
	t.check("the primary column has measured row text", firstRow ~= nil)
	t.near(
		"the fills share growth after reserving primary text",
		width(mixed, "artist") - width(mixed, "name"),
		200 - primaryFloor,
		1
	)
	local wide = mount(900, {
		{ id = "name", label = "Name", minWidth = 120, priority = "always" },
		{ id = "artist", label = "Artist", minWidth = 100, priority = "always" },
		{ id = "laps", label = "Laps", width = 96, priority = "always" },
	})
	header = t.find(wide, "Header")
	t.note("wide widths", { width(wide, "name"), width(wide, "artist"), header.AbsoluteSize.X })
	t.near(
		"wide, the fills and the fixed column fill the header",
		width(wide, "name") + width(wide, "artist") + width(wide, "laps"),
		header.AbsoluteSize.X,
		0.5
	)
	t.near("wide, the fills grow equally from their floors", width(wide, "name") - width(wide, "artist"), 20, 1)
	t.check("wide, both fills are above their floors", width(wide, "artist") > 150, width(wide, "artist"))
	local widths
	local sorted = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		widths = Compose.cell({})
		return UI.Table "Hits" {
			from = rows(6),
			key = "id",
			selectionMode = "single" :: "single",
			widths = widths,
			columns = {
				{ id = "name", label = "Name" },
				{ id = "laps", label = "Laps", width = 96 },
			},
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	widths:set({ name = 220 })
	t.settle(8)
	for _, key in { "r1", "r2", "r3" } do
		local row = rowOf(sorted, key)
		local value = row and row:FindFirstChild("name", true)
		value = value and value:FindFirstChild("Value")
		local hit = row and row:FindFirstChild("RowHit", true)
		t.check(`{key} has a value and a hit`, value ~= nil and hit ~= nil)
		if value and hit then
			t.near(`{key} resized name column is 220`, value.Parent.AbsoluteSize.X, 220, 0.5)
			local center = value.AbsolutePosition + value.AbsoluteSize / 2
			local order = hitOrder(center)
			local valueAt, hitAt = table.find(order, value), table.find(order, hit)
			t.check(
				`{key} the cell value is above the row hit`,
				valueAt ~= nil and hitAt ~= nil and valueAt < hitAt,
				{ valueAt, hitAt }
			)
		end
	end
end)

add("cell-insets-and-header-contrast", {}, function(t)
	local stage = t.mount(function(UI: FacetControls)
		return UI.Table "Racers" {
			from = rows(4),
			key = "id",
			columns = {
				{ id = "name", label = "Name" },
				{ id = "laps", label = "Laps", width = 120 },
			},
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	local header = t.find(stage, "Header")
	local row = rowOf(stage, "r1")
	local cell = row and row:FindFirstChild("name", true)
	local value = cell and cell:FindFirstChild("Value")
	local sort = header and header:FindFirstChild("name") and header.name:FindFirstChild("Sort")
	t.check("the cell and header title exist", value ~= nil and sort ~= nil)
	if not value or not sort then
		return
	end
	local gui = stage:FindFirstAncestorWhichIsA("ScreenGui")
	local sheet = gui and gui:FindFirstChildWhichIsA("StyleSheet")
	local function rulePadding(node: any): UDim?
		local found: UDim? = nil
		for _, rule in if sheet then sheet:GetChildren() else {} do
			if rule:IsA("StyleRule") then
				local tag = string.match(rule.Selector, "^%.([%w%-]+)::UIPadding$")
				local padding = if tag and node:HasTag(tag) then rule:GetProperty("PaddingLeft") else nil
				if typeof(padding) == "UDim" then
					found = padding
				end
			end
		end
		return found
	end
	local function textLeft(node: any): number
		local left = node.AbsolutePosition.X
		local component = node:FindFirstChildWhichIsA("UIPadding")
		local padding = if component then component:GetStyled("PaddingLeft") else rulePadding(node)
		if padding then
			left += padding.Offset + padding.Scale * node.AbsoluteSize.X
		end
		return left
	end
	local caption = nil
	for _, node in sort:GetDescendants() do
		if node:IsA("TextLabel") and node.ContentText ~= "" then
			caption = node
		end
	end
	local titleNode = caption or sort
	t.note("value", { x = value.AbsolutePosition.X, w = value.AbsoluteSize.X, padded = textLeft(value) })
	t.check(
		"the cell value takes its inset from a UIPadding component or a UIPadding style rule",
		value:FindFirstChildWhichIsA("UIPadding") ~= nil or rulePadding(value) ~= nil,
		value:GetTags()
	)
	t.note("cell", { x = cell.AbsolutePosition.X, y = cell.AbsolutePosition.Y, h = cell.AbsoluteSize.Y })
	t.note("title", { x = titleNode.AbsolutePosition.X, padded = textLeft(titleNode), name = titleNode.Name })
	t.note(
		"sort children",
		(function()
			local names = {}
			for _, child in sort:GetChildren() do
				table.insert(names, child.ClassName .. ":" .. child.Name)
			end
			return names
		end)()
	)
	local inset = textLeft(value) - cell.AbsolutePosition.X
	t.check("cell text is inset from the cell left edge", inset >= 8, inset)
	t.near(
		"cell text starts where the header title starts",
		textLeft(value) - cell.AbsolutePosition.X,
		textLeft(titleNode) - header.name.AbsolutePosition.X,
		0.5
	)
	local top = value.AbsolutePosition.Y + (value.AbsoluteSize.Y - value.TextBounds.Y) / 2
	local bottom = cell.AbsolutePosition.Y + cell.AbsoluteSize.Y - (top + value.TextBounds.Y)
	t.near("cell text is centred vertically", top - cell.AbsolutePosition.Y, bottom, 1)
	local content = value:GetStyled("TextColor3")
	local title = titleNode:GetStyled("TextColor3")
	t.note("colors", { value = tostring(content), title = tostring(title) })
	t.check(
		"the header title uses the full content color of the cells",
		title == content,
		{ tostring(title), tostring(content) }
	)
end)

add("page-scroll-moves-the-table-body", {}, function(t)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule)
		return Host.ScrollingFrame "Page" {
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.fromOffset(0, 1600),
			BackgroundTransparency = 1,
			Host.Frame "Spacer" { Size = UDim2.fromOffset(10, 200), BackgroundTransparency = 1 } :: unknown,
			Host.Frame "Holder" {
				Position = UDim2.fromOffset(0, 200),
				Size = UDim2.fromOffset(500, 600),
				BackgroundTransparency = 1,
				UI.Table "Racers" {
					from = rows(12),
					key = "id",
					scrolls = false,
					reorderable = true,
					editing = Compose.cell(true),
					onReorder = function() end,
					columns = { { id = "name", label = "Name" } },
				},
			},
		}
	end, { size = Vector2.new(600, 500), frames = 20 })
	local page = t.find(stage, "Page")
	local body = t.find(stage, "Body")
	local handle = rowOf(body, "r1") and rowOf(body, "r1"):FindFirstChild("Move", true)
	t.check("the body and a handle mounted", body ~= nil and handle ~= nil)
	if not body or not handle then
		return
	end
	local before, handleBefore = body.AbsolutePosition, handle.AbsolutePosition
	page.CanvasPosition = Vector2.new(0, 120)
	t.settle(4)
	t.near("the page scrolled 120", page.CanvasPosition.Y, 120, 0.01)
	t.near("the body moved up by exactly the page scroll", body.AbsolutePosition.Y, before.Y - 120, 0.01)
	t.near("the handle moved up by exactly the page scroll", handle.AbsolutePosition.Y, handleBefore.Y - 120, 0.01)
	t.near("the body kept its canvas offset", body.CanvasPosition.Y, 0, 0.01)
end)

local function clampCase(t: any, direction: "horizontal" | "vertical", kind: string)
	local stage = t.mount(function(UI: FacetControls)
		local spec = {
			from = rows(200),
			key = "id",
			itemSize = 40,
			direction = direction,
			render = function(current)
				return UI.Text({ Name = "Text", text = current:peek().name, Size = UDim2.fromScale(1, 1) })
			end,
			Size = if direction == "horizontal" then UDim2.fromOffset(470, 300) else UDim2.fromOffset(300, 190),
		}
		if kind == "grid" then
			spec.columns = 4
			spec.itemSize = 100
			spec.Size = if direction == "horizontal" then UDim2.fromOffset(450, 400) else UDim2.fromOffset(400, 250)
			return UI.VirtualGrid(spec)
		end
		return UI.VirtualList(spec)
	end, { size = Vector2.new(800, 600), frames = 20 })
	local root = stage:FindFirstChildWhichIsA("ScrollingFrame", true)
	local horizontal = direction == "horizontal"
	local where = `{kind} {direction}`
	t.note(where .. " window", root.AbsoluteWindowSize)
	local window = t.rect(root)
	local extent = if kind == "grid" then 100 else 40
	local window_main = if horizontal then root.AbsoluteWindowSize.X else root.AbsoluteWindowSize.Y
	local lastIndex = math.floor(window_main / extent) + 1
	local partialKey = if kind == "grid" then "r" .. ((lastIndex - 1) * 4 + 1) else "r" .. lastIndex
	local partial = rowOf(root, partialKey)
	t.check(where .. " the partial line is mounted", partial ~= nil, partialKey)
	if partial then
		local seen = t.clipped(partial)
		local expected = window_main - (lastIndex - 1) * extent
		t.check(where .. " the partial line is visible", seen ~= nil)
		if seen then
			t.near(
				where .. " the partial line is cropped at the window edge",
				if horizontal then seen.w else seen.h,
				expected,
				0.5
			)
			t.inside(where .. " the visible part lies inside the window", seen, {
				x = window.x,
				y = window.y,
				r = window.x + root.AbsoluteWindowSize.X,
				b = window.y + root.AbsoluteWindowSize.Y,
				w = 0,
				h = 0,
			})
		end
	end
	root.CanvasPosition = if horizontal then Vector2.new(-300, 0) else Vector2.new(0, -300)
	t.settle(4)
	t.near(
		where .. " the engine clamps a negative offset to 0",
		if horizontal then root.CanvasPosition.X else root.CanvasPosition.Y,
		0,
		0.01
	)
	t.check(where .. " the first line stays mounted", rowOf(root, "r1") ~= nil)
	local first = rowOf(root, "r1")
	if first then
		t.near(
			where .. " the first line sits at the window start",
			if horizontal then first.AbsolutePosition.X else first.AbsolutePosition.Y,
			if horizontal then window.x else window.y,
			0.5
		)
	end
	root.CanvasPosition = if horizontal then Vector2.new(1e6, 0) else Vector2.new(0, 1e6)
	t.settle(6)
	local max = if horizontal
		then root.AbsoluteCanvasSize.X - root.AbsoluteWindowSize.X
		else root.AbsoluteCanvasSize.Y - root.AbsoluteWindowSize.Y
	t.near(
		where .. " the engine clamps a huge offset to the canvas end",
		if horizontal then root.CanvasPosition.X else root.CanvasPosition.Y,
		max,
		0.5
	)
	t.check(where .. " the last item is mounted at the end", rowOf(root, "r200") ~= nil)
end

add("partial-lines-crop-and-offsets-clamp", {}, function(t)
	clampCase(t, "vertical", "list")
	t.cleanup()
	clampCase(t, "vertical", "grid")
	t.cleanup()
	clampCase(t, "horizontal", "grid")
	t.cleanup()
	clampCase(t, "horizontal", "list")
end)

add("tray-actions-meet-the-touch-floor", {}, function(t)
	local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		return UI.RowActions "Row" {
			open = Compose.cell("trailing" :: "leading" | "trailing" | nil),
			Size = UDim2.new(0, 400, 0, 44),
			content = UI.Text({ text = "Row" }),
			trailing = {
				{ id = "flag", label = "Flag" },
				{ id = "delete", label = "Delete", role = "destructive" :: "destructive" },
			},
		}
	end, { size = Vector2.new(600, 300), frames = 30 })
	local row = t.find(stage, "Row")
	local tray = row and row:FindFirstChild("trailing")
	t.check("the tray is open", tray ~= nil and tray.Visible and tray.AbsoluteSize.X > 0)
	if not tray then
		return
	end
	for _, id in { "flag", "delete" } do
		local button = tray:FindFirstChild(id)
		t.check(`{id} is a selectable button`, button ~= nil and button:IsA("GuiButton") and button.Selectable)
		if button then
			t.check(`{id} is at least 44 px tall`, button.AbsoluteSize.Y >= 43.5, button.AbsoluteSize)
			t.check(`{id} label fits`, t.fits(button) or (function()
				for _, node in button:GetDescendants() do
					if node:IsA("TextLabel") and node.ContentText ~= "" then
						return t.fits(node)
					end
				end
				return false
			end)())
		end
	end
	local delete, flag = tray:FindFirstChild("delete"), tray:FindFirstChild("flag")
	if delete and flag then
		local danger, plain = delete:GetStyled("BackgroundColor3"), flag:GetStyled("BackgroundColor3")
		t.note("plates", {
			delete = { tostring(danger), delete:GetTags(), delete.BackgroundTransparency },
			flag = { tostring(plain), flag:GetTags(), flag.BackgroundTransparency },
		})
		t.check(
			"the destructive plate paints differently from the default plate",
			danger ~= plain,
			{ tostring(danger), tostring(plain) }
		)
	end
end)

local function departureCase(t: any, entry: any, edge: string, scroll: boolean)
	local fired = 0
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		local action = {
			id = "delete",
			label = "Delete",
			role = "destructive" :: "destructive",
			onActivate = function()
				fired += 1
			end,
		}
		local list = {
			Name = "Rows",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }) :: unknown,
			Host.UIPadding({
				PaddingLeft = UDim.new(0, 17),
				PaddingRight = UDim.new(0, 17),
				PaddingTop = UDim.new(0, 17),
			}),
			UI.RowActions "Row" {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 70),
				leading = if edge == "leading" then { action } else nil,
				trailing = if edge == "trailing" then { action } else nil,
				content = UI.Button({ Name = "Body", label = "Body", Size = UDim2.fromScale(1, 1) }),
			},
			Host.Frame "Next" { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1 },
		}
		local host = if scroll
			then Host.ScrollingFrame "Scroll" {
				Position = UDim2.fromOffset(16, 16),
				Size = UDim2.new(1, -32, 0, 300),
				CanvasSize = UDim2.fromOffset(0, 600),
				BackgroundTransparency = 1,
				Host.Frame(list),
			}
			else Host.Frame "Scroll" {
				Position = UDim2.fromOffset(16, 16),
				Size = UDim2.new(1, -32, 0, 300),
				BackgroundTransparency = 1,
				Host.Frame(list),
			}
		return host
	end, { size = Vector2.new(900, 400), theme = entry.package, motionLevel = "normal", frames = 30 })
	local where = `{entry.name} {edge} scroll={scroll}`
	local row = t.find(stage, "Row")
	local nextFrame = t.find(stage, "Next")
	local body = t.find(stage, "Body")
	local content = row and row:FindFirstChild("Content")
	t.check(where .. " the row mounted", row ~= nil and nextFrame ~= nil and body ~= nil and content ~= nil)
	if not row or not nextFrame or not body or not content then
		return
	end
	t.stable(row)
	local restY = nextFrame.AbsolutePosition.Y
	GuiService.SelectedObject = body
	t.settle(2)
	local inputAction = nil
	for _, node in stage:FindFirstAncestorWhichIsA("ScreenGui"):GetDescendants() do
		if node:IsA("InputContext") and node.Name == "FacetRowActionsDelete" and node.Enabled then
			inputAction = node:FindFirstChild("RowActionsDelete")
		end
	end
	t.check(where .. " the delete action exists", inputAction ~= nil)
	if not inputAction then
		GuiService.SelectedObject = nil
		return
	end
	inputAction:Fire(true)
	inputAction:Fire(false)
	GuiService.SelectedObject = nil
	local collapsedFrames, leaks, frames = 0, {}, 0
	for _ = 1, 120 do
		RunService.RenderStepped:Wait()
		frames += 1
		if row.Parent == nil or fired > 0 then
			break
		end
		if nextFrame.AbsolutePosition.Y < restY - 1 then
			collapsedFrames += 1
			for _, node in content:GetDescendants() do
				if node:IsA("GuiObject") and t.visible(node) and node.AbsoluteSize.X > 0.5 then
					local seen = t.clipped(node)
					if seen then
						table.insert(leaks, { node.Name, seen.x, seen.w, nextFrame.AbsolutePosition.Y })
					end
				end
			end
			local seen = t.clipped(content)
			if seen then
				table.insert(leaks, { "Content", seen.x, seen.w })
			end
		end
	end
	t.note(where .. " frames", { frames = frames, collapsed = collapsedFrames })
	t.check(
		where .. " the row collapsed over several frames before the action ran",
		collapsedFrames >= 2,
		collapsedFrames
	)
	t.check(where .. " nothing of the departing row paints while the next row rises", #leaks == 0, leaks)
	t.settle(10)
	t.check(where .. " the action ran exactly once", fired == 1, fired)
end

add("departure-clears-before-reflow", {}, function(t)
	local list = { t.themes[1] }
	local ornate = theme(t, "ornate") or theme(t, "fantasy")
	if ornate then
		table.insert(list, ornate)
	end
	t.note(
		"themes",
		(function()
			local names = {}
			for _, entry in list do
				table.insert(names, entry.name)
			end
			return names
		end)()
	)
	t.check("an ornate package is available", ornate ~= nil)
	for _, entry in list do
		for _, scroll in { true, false } do
			for _, edge in { "leading", "trailing" } :: { "leading" | "trailing" } do
				departureCase(t, entry, edge, scroll)
				t.cleanup()
			end
		end
	end
end)

add("plate-decoration-stays-inside-the-band", {}, function(t)
	local list = { t.themes[1] }
	local ornate = theme(t, "ornate") or theme(t, "fantasy")
	if ornate then
		table.insert(list, ornate)
	end
	for _, entry in list do
		local open
		local stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
			open = (function(value: ("leading" | "trailing")?): SideCell
				return Compose.cell(value)
			end)(nil)
			return UI.RowActions "Row" {
				open = open,
				Size = UDim2.new(0, 500, 0, 56),
				content = UI.Button({ label = "Row", Size = UDim2.fromScale(1, 1) }),
				trailing = {
					{ id = "flag", label = "Flag" },
					{ id = "delete", label = "Delete", role = "destructive" :: "destructive" },
				},
			}
		end, { size = Vector2.new(700, 300), theme = entry.package, motionLevel = "normal", frames = 20 })
		local row = t.find(stage, "Row")
		local tray = row:FindFirstChild("trailing")
		local worst, narrowest, sampled, overhang, plateWidth = 0, math.huge, 0, 0, math.huge
		local function sample()
			if not tray.Visible or tray.AbsoluteSize.X < 0.5 then
				return
			end
			local band = t.rect(tray)
			for _, id in { "flag", "delete" } do
				local plate = tray:FindFirstChild(id)
				if plate and plate.AbsoluteSize.X > 0 then
					sampled += 1
					narrowest = math.min(narrowest, band.w)
					plateWidth = math.min(plateWidth, plate.AbsoluteSize.X)
					for _, node in plate:GetDescendants() do
						if node:IsA("GuiObject") and t.visible(node) and node.AbsoluteSize.X > 0.5 then
							local raw = t.rect(node)
							overhang = math.max(overhang, band.x - raw.x, raw.r - band.r)
							local seen = t.clipped(node)
							if seen then
								worst =
									math.max(worst, band.x - seen.x, seen.r - band.r, band.y - seen.y, seen.b - band.b)
							end
						end
					end
				end
			end
		end
		open:set("trailing")
		for _ = 1, 40 do
			RunService.RenderStepped:Wait()
			sample()
		end
		open:set(nil)
		for _ = 1, 60 do
			RunService.RenderStepped:Wait()
			sample()
		end
		t.note(
			entry.name .. " sample",
			{ sampled = sampled, narrowest = narrowest, rawOverhang = overhang, plateWidth = plateWidth }
		)
		t.check(entry.name .. " the flight sampled mounted plates", sampled >= 20, sampled)
		t.check(
			entry.name .. " the close flight narrowed the band below 8 px over a mounted plate",
			narrowest < 8,
			narrowest
		)
		t.check(entry.name .. " a fixed-width plate overhung the narrowed band before clipping", overhang > 8, overhang)
		t.check(entry.name .. " no painted plate decoration leaves the band", worst <= 0.5, worst)
		t.cleanup()
	end
end)

local function within(node: Instance?, root: Instance?): boolean
	return node ~= nil and root ~= nil and (node == root or node:IsDescendantOf(root))
end

local function screenCenter(node: any): { number }
	local inset = GuiService:GetGuiInset()
	local center = node.AbsolutePosition + node.AbsoluteSize / 2
	return { math.floor(center.X + 0.5), math.floor(center.Y + inset.Y + 0.5) }
end

interactive("tray-keys-and-hover", {}, function(t)
	local value = { fired = {} }
	value.stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		value.open = (function(value: ("leading" | "trailing")?): SideCell
			return Compose.cell(value)
		end)(nil)
		return UI.RowActions "Row" {
			open = value.open,
			Size = UDim2.new(0, 500, 0, 56),
			content = UI.Button({ Name = "Body", label = "Row body", Size = UDim2.fromScale(1, 1) }),
			trailing = {
				{
					id = "flag",
					label = "Flag",
					onActivate = function()
						table.insert(value.fired, "flag")
					end,
				},
				{
					id = "delete",
					label = "Delete",
					onActivate = function()
						table.insert(value.fired, "delete")
					end,
				},
			},
		}
	end, { size = Vector2.new(700, 300), frames = 20 })
	local row = t.find(value.stage, "Row")
	GuiService.SelectedObject = t.find(row, "Body")
	t.settle(2)
	value.open:set("trailing")
	t.settle(10)
	value.tray = row:FindFirstChild("trailing")
	t.check("opening the tray selects its first action", selectedName() == "flag", selectedName())
	return value
end, {
	afterRight = function(t, value)
		t.check("Right moves the native selection to the next tray action", selectedName() == "delete", selectedName())
	end,
	afterReturn = function(t, value)
		t.check(
			"Return runs the selected tray action once",
			#value.fired == 1 and value.fired[1] == "delete",
			value.fired
		)
		t.check("the tray closed after the action", value.open:peek() == nil, value.open:peek())
		GuiService.SelectedObject = nil
		value.open:set("trailing")
		t.settle(12)
		local flag = value.tray:FindFirstChild("flag")
		value.idle = tostring(flag:GetStyled("BackgroundColor3"))
		t.note("flag path", flag:GetFullName())
		t.note("flag screen center", screenCenter(flag))
	end,
	afterHover = function(t, value)
		local flag = value.tray:FindFirstChild("flag")
		t.check(
			"the pointer puts the tray action in the Hover state",
			flag.GuiState == Enum.GuiState.Hover,
			flag.GuiState
		)
		local hovered = tostring(flag:GetStyled("BackgroundColor3"))
		t.check("the hovered plate paints the hover color", hovered ~= value.idle, { value.idle, hovered })
	end,
})

interactive("header-sort-keys", {}, function(t)
	local value = {}
	value.stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		value.sort = (function(value: { column: string, direction: "ascending" | "descending" }?): SortCell
			return Compose.cell(value)
		end)(nil)
		return UI.Table "Racers" {
			from = rows(8),
			key = "id",
			sort = value.sort,
			selectionMode = "single" :: "single",
			columns = {
				{ id = "name", label = "Name", resizable = false },
				{ id = "laps", label = "Laps", width = 140, resizable = false },
			},
		}
	end, { size = Vector2.new(600, 500), frames = 20 })
	local header = t.find(value.stage, "Header")
	value.nameSort = header.name.Sort
	value.lapsSort = header.laps.Sort
	GuiService.SelectedObject = value.nameSort
	t.settle(2)
	t.check("the name sort button holds the selection", GuiService.SelectedObject == value.nameSort)
	return value
end, {
	afterReturn = function(t, value)
		local order = value.sort:peek()
		t.check(
			"Return sorts by name ascending",
			order and order.column == "name" and order.direction == "ascending",
			order
		)
	end,
	afterReturnAgain = function(t, value)
		local order = value.sort:peek()
		t.check(
			"a second Return flips to descending",
			order and order.column == "name" and order.direction == "descending",
			order
		)
	end,
	afterRight = function(t, value)
		t.check("Right walks to the next sort header", GuiService.SelectedObject == value.lapsSort, selectedName())
	end,
	afterReturnLaps = function(t, value)
		local order = value.sort:peek()
		t.check(
			"Return on the second header sorts it ascending",
			order and order.column == "laps" and order.direction == "ascending",
			order
		)
	end,
	afterDown = function(t, value)
		local selected = GuiService.SelectedObject
		t.check("Down leaves the header for a row", selected ~= nil and selected.Name == "RowHit", selectedName())
		t.note("row after Down", selectedRow())
	end,
	afterUp = function(t, value)
		t.check(
			"Up re-enters the header",
			GuiService.SelectedObject == value.lapsSort or GuiService.SelectedObject == value.nameSort,
			selectedName()
		)
		GuiService.SelectedObject = nil
	end,
})

interactive("left-reaches-this-rows-minus", {}, function(t)
	local value = { fired = {} }
	value.stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		return UI.Table "Racers" {
			from = rows(6),
			key = "id",
			selectionMode = "single" :: "single",
			editing = Compose.cell(true),
			columns = { { id = "name", label = "Name" }, { id = "laps", label = "Laps", width = 120 } },
			rowActions = function(_, key): RowActions?
				return {
					trailing = {
						{
							id = "delete",
							label = "Delete",
							role = "destructive" :: "destructive",
							onActivate = function()
								table.insert(value.fired, "delete:" .. key)
							end,
						},
					},
				}
			end,
		}
	end, { size = Vector2.new(700, 500), frames = 24 })
	local hit = rowOf(value.stage, "r2"):FindFirstChild("RowHit", true)
	GuiService.SelectedObject = hit
	t.settle(2)
	t.check("r2 holds the selection", GuiService.SelectedObject == hit, selectedName())
	return value
end, {
	afterLeft = function(t, value)
		local selected = GuiService.SelectedObject
		t.check("Left selects a minus", selected ~= nil and selected.Name == "Delete", selectedName())
		t.check("the minus belongs to r2", selectedRow() == "r2", selectedRow())
	end,
	afterReturn = function(t, value)
		t.check("Return deletes r2 only", #value.fired == 1 and value.fired[1] == "delete:r2", value.fired)
		GuiService.SelectedObject = nil
	end,
})

interactive("collapsed-column-leaves-the-ring", {}, function(t)
	local value = {}
	value.stage = t.mount(function(UI: FacetControls)
		return UI.Table "Racers" {
			from = rows(6),
			key = "id",
			selectionMode = "single" :: "single",
			columns = {
				{ id = "name", label = "Name", minWidth = 200 },
				{ id = "laps", label = "Laps", width = 120, minWidth = 120 },
			},
		}
	end, { size = Vector2.new(280, 500), frames = 24 })
	local header = t.find(value.stage, "Header")
	value.hidden = header.laps
	t.check("the laps column is collapsed", header.laps.Visible == false)
	t.check("a More button shows on the rows", rowOf(value.stage, "r1"):FindFirstChild("Details", true) ~= nil)
	GuiService.SelectedObject = header.name.Sort
	t.settle(2)
	watchSelection(value)
	return value
end, {
	afterWalk = function(t, value)
		value.connection:Disconnect()
		local names, hidden = {}, {}
		for _, node in value.visited do
			table.insert(names, node.Name)
			if not t.visible(node) then
				table.insert(hidden, node:GetFullName())
			end
		end
		t.note("visited", names)
		t.check("the walk visited several stops", #names >= 3, names)
		t.check("no hidden node was ever selected", #hidden == 0, hidden)
		local details = rowOf(value.stage, "r1"):FindFirstChild("Details", true)
		GuiService.SelectedObject = details
		t.settle(2)
	end,
	afterReturn = function(t, value)
		local plate = nil
		for _, node in value.stage:FindFirstAncestorWhichIsA("ScreenGui"):GetDescendants() do
			if node.Name == "FullValue" and t.visible(node) then
				plate = node
			end
		end
		t.check(
			"Return opens the plate with the collapsed value",
			plate ~= nil and plate.ContentText == "1",
			plate and plate.ContentText
		)
		GuiService.SelectedObject = nil
	end,
})

interactive("return-toggles-multi-selection", {}, function(t)
	local value = {}
	value.stage = t.mount(function(UI: FacetControls, _, Compose: ComposeModule)
		value.selection = Compose.cell({})
		return UI.Table "Racers" {
			from = rows(6),
			key = "id",
			selection = value.selection,
			selectionMode = "multiple" :: "multiple",
			editing = Compose.cell(true),
			columns = { { id = "name", label = "Name" } },
		}
	end, { size = Vector2.new(500, 400), frames = 20 })
	GuiService.SelectedObject = rowOf(value.stage, "r1"):FindFirstChild("RowHit", true)
	t.settle(2)
	return value
end, {
	afterReturn = function(t, value)
		t.check("Return selects r1", value.selection:peek().r1 == true, value.selection:peek())
	end,
	afterDown = function(t, value)
		t.check("Down moves to r2", selectedRow() == "r2", selectedRow())
		t.check(
			"Down keeps the selection",
			value.selection:peek().r1 == true and not value.selection:peek().r2,
			value.selection:peek()
		)
	end,
	afterReturnTwo = function(t, value)
		local now = value.selection:peek()
		t.check("Return adds r2", now.r1 == true and now.r2 == true, now)
	end,
	afterReturnThree = function(t, value)
		local now = value.selection:peek()
		t.check("Return again removes r2", now.r1 == true and not now.r2, now)
		GuiService.SelectedObject = nil
	end,
})

interactive("horizontal-list-keys", {}, function(t)
	local value = { activations = {} }
	value.stage = t.mount(function(UI: FacetControls)
		return UI.VirtualList "Strip" {
			from = rows(40),
			key = "id",
			itemSize = 140,
			direction = "horizontal" :: "horizontal",
			Size = UDim2.fromOffset(600, 120),
			onActivate = function(item: any, _, input: InputObject?)
				table.insert(value.activations, { item.id, if input then assert(input).KeyCode.Name else "nil" })
			end,
			render = function(current)
				return UI.Text({ text = current:peek().name })
			end,
		}
	end, { size = Vector2.new(800, 400), frames = 20 })
	value.strip = t.find(value.stage, "Strip")
	GuiService.SelectedObject = rowOf(value.strip, "r1"):FindFirstChild("RowHit", true)
	t.settle(2)
	return value
end, {
	afterRight = function(t, value)
		t.check("Right moves along the strip", selectedRow() == "r2", selectedRow())
		t.check("moving activates nothing", #value.activations == 0, value.activations)
	end,
	afterReturn = function(t, value)
		t.check(
			"Return activates the selected item once",
			#value.activations == 1 and value.activations[1][1] == "r2",
			value.activations
		)
		value.strip.CanvasPosition = Vector2.new(700, 0)
		t.settle(6)
		t.check("an engine scroll activates nothing", #value.activations == 1, value.activations)
		GuiService.SelectedObject = nil
	end,
})

interactive("drag-across-rows-after-page-scroll", {}, function(t)
	local value = { reorders = {} }
	value.stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		return Host.ScrollingFrame "Page" {
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.fromOffset(0, 1400),
			BackgroundTransparency = 1,
			Host.Frame "Holder" {
				Position = UDim2.fromOffset(0, 200),
				Size = UDim2.fromOffset(500, 700),
				BackgroundTransparency = 1,
				UI.Table "Racers" {
					from = rows(10),
					key = "id",
					scrolls = false,
					header = false,
					reorderable = true,
					onReorder = function(keys, slot)
						table.insert(value.reorders, { keys = keys, slot = slot })
					end,
					columns = { { id = "name", label = "Name" } },
				},
			},
		}
	end, { size = Vector2.new(600, 600), frames = 20 })
	local page = t.find(value.stage, "Page")
	page.CanvasPosition = Vector2.new(0, 120)
	t.settle(4)
	value.body = t.find(value.stage, "Body")
	local handle = rowOf(value.body, "r1"):FindFirstChild("Move", true)
	value.height = rowOf(value.body, "r1").AbsoluteSize.Y
	local start = screenCenter(handle)
	value.start = start
	t.note("handle start", start)
	t.note("row height", value.height)
	t.note("path", {
		start,
		{ start[1], start[2] + math.floor(value.height) },
		{ start[1], start[2] + math.floor(value.height * 2.2) },
	})
	return value
end, {
	afterDrag = function(t, value)
		t.note("reorders", value.reorders)
		local expectedSlot = 2
		t.check("one reorder committed", #value.reorders == 1, value.reorders)
		local first = value.reorders[1]
		t.check("the original row r1 moved", first ~= nil and first.keys[1] == "r1" and #first.keys == 1, first)
		t.check(
			"the slot is the row under the pointer after the page scroll",
			first ~= nil and first.slot == expectedSlot,
			first and first.slot
		)
		t.check("the drag feedback is gone", value.stage:FindFirstChild("DragLabel", true) == nil)
	end,
})

return cases
