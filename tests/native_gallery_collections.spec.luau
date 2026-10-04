--!strict
local nativeDrag = require("./lib/native_drag")

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
local requireDynamic = require :: (any) -> any
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose: ComposeModule = Facet.Compose

local function find(node: any, name: string): any
	if node.Name == name then
		return node
	end
	for _, child in node:GetChildren() do
		local found = find(child, name)
		if found then
			return found
		end
	end
	return nil
end

local function mount(name: string, size: { width: number, height: number }?)
	local engine = engineLib.new()
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
	local target, guiService = engine.new("Folder"), engine.new("GuiService")
	local inputService = engine.new("UserInputService")
	inputService.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	local keys = {}
	inputService.GetFocusedTextBox = function()
		return nil
	end
	inputService.IsKeyDown = function(_, code)
		return keys[code.Name] == true
	end
	local viewport = Compose.cell(size or { width = 1280, height = 720 })
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = (runtime.constructors :: unknown) :: RobloxHost,
		types = engine.types,
		viewport = viewport,
		guiService = guiService,
		runService = { Heartbeat = engine.heartbeat },
		UI = Facet.controls(runtime, {
			types = engine.types,
			viewport = viewport,
			guiService = guiService,
			services = { GuiService = guiService, UserInputService = inputService },
			inputParent = target,
			motionLevel = "none",
		}),
	}
	local built
	local baseline = engine.census()
	local stop, node: any = runtime.mount(function()
		built = requireDynamic("../examples/gallery/scenarios/" .. name).build(ctx)
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	return built,
		node,
		function()
			stop()
			runtime:dispose()
		end,
		engine,
		{
			gui = guiService,
			keys = keys,
			input = inputService,
			target = target,
			baseline = baseline,
			viewport = viewport,
		}
end

local function action(root, name: string)
	for _, child in root:GetChildren() do
		if child:IsA("InputContext") and child.Name == "Facet" .. name and child.Enabled then
			return child:FindFirstChild(name)
		end
	end
	return nil
end

local function contains(node, value)
	if (node:IsA("TextLabel") or node:IsA("TextButton")) and string.find(node.Text, value, 1, true) then
		return true
	end
	for _, child in node:GetChildren() do
		if contains(child, value) then
			return true
		end
	end
	return false
end

local function viewport(node, engine, width, height)
	node.AbsoluteSize = engine.types.Vector2.new(width, height)
	node.AbsoluteWindowSize = engine.types.Vector2.new(width, height)
end

local function swipe(row, engine, startX, endX)
	row.AbsoluteSize = engine.types.Vector2.new(320, 112)
	local detector = row:FindFirstChildWhichIsA("UIDragDetector", true)
	detector.DragStart.fire(engine.types.Vector2.new(startX, 20))
	detector.DragContinue.fire(engine.types.Vector2.new(endX, 20))
	detector.DragEnd.fire()
end

t.describe("native gallery collections", function()
	t.it("reveals distant entrants selects an unmounted range and moves keyed rows", function()
		local built, node, stop, engine, world = mount("table_virtualized")
		local tableNode, body = find(node, "Collection"), find(node, "Body")
		tableNode.AbsoluteSize = engine.types.Vector2.new(800, 440)
		viewport(body, engine, 800, 400)
		nativeDrag.measure(body)
		t.expect(built.report().count).toBe(2000)
		t.expect(built.report().status.retained < 30).toBe(true)
		t.expect(contains(node, "Entrant") and contains(node, "Team") and contains(node, "Best lap")).toBe(true)
		t.expect(contains(node, "Rustbucket") and contains(node, "#1")).toBe(true)
		t.expect(find(node, "Columns")).toBe(nil)
		t.expect(find(node, "TextSize")).toBe(nil)
		find(node, "Range").Activated.fire()
		t.expect(built.report().selectedCount).toBe(201)
		t.expect(built.report().selection.e900 and built.report().selection.e1100).toBe(true)
		t.expect(find(body, "e1500")).toBe(nil)
		find(node, "Move").Activated.fire()
		t.expect(built.report().rows[1499].id).toBe("e1500")
		t.expect(built.report().moves).toBe(1)
		find(node, "Reveal").Activated.fire()
		t.expect(body.CanvasPosition.Y > 40000).toBe(true)
		t.expect(find(body, "e1500") ~= nil).toBe(true)
		t.expect(built.report().status.first > 1400).toBe(true)
		t.expect(string.find(find(node, "Status").Text, tostring(built.report().status.first), 1, true) ~= nil)
			.toBe(true)
		t.expect(find(node, "Edit")).toBeNil()
		world.input.PreferredInput = engine.types.Enum.PreferredInput.Touch
		find(node, "Edit").Activated.fire()
		t.expect(find(find(body, "e1500"), "Move").Visible).toBe(true)
		t.expect(built.report().selectedCount).toBe(201)
		find(node, "Reset").Activated.fire()
		t.expect(built.report().selectedCount).toBe(0)
		t.expect(built.report().rows[1500].id).toBe("e1500")
		t.expect(body.CanvasPosition.Y).toBe(0)
		stop()
	end)

	t.it("shows seeded mail state and applies idempotent read visible flag and chosen deletion", function()
		local built, node, stop, engine = mount("row_actions")
		local list = find(node, "Mail_list")
		local body = find(list, "Collection")
		viewport(body, engine, 700, 240)
		local function mail(row)
			return {
				unread = find(row, "Unread").Visible,
				flagged = find(row, "Flag").Visible,
				from = find(row, "From").Text,
				subject = find(row, "Subject").Text,
				preview = find(row, "Preview").Text,
			}
		end
		t.expect(mail(find(list, "Row_m1"))).toEqual({
			unread = true,
			flagged = false,
			from = "Ari Foyer",
			subject = "Kickoff notes",
			preview = "Quick recap from the sync — three follow-ups, none urgent.",
		})
		t.expect(mail(find(list, "Row_m2")).unread).toBe(false)
		t.expect(mail(find(list, "Row_m3")).flagged).toBe(true)
		t.expect(contains(find(list, "Row_m1"), "Unread · ")).toBe(false)
		t.expect(find(find(list, "Row_m1"), "Flag"):IsA("ImageLabel")).toBe(true)
		t.expect(find(find(list, "Row_m1"), "Unread"):IsA("GuiObject")).toBe(true)
		t.expect(find(find(list, "Row_m1"), "Subject"):HasTag("facet-type-label")).toBe(true)
		t.expect(find(find(list, "Row_m1"), "Preview"):HasTag("facet-type-caption")).toBe(true)
		t.expect(find(find(list, "Row_m1"), "From"):HasTag("facet-type-body")).toBe(true)
		t.expect(built.report().surfaces.list.status.extent).toBe(6 * 76 + 5 * 8)
		for _ = 1, 2 do
			swipe(find(list, "Row_m1"), engine, 10, 300)
		end
		t.expect(built.report().surfaces.list.read.m1).toBe(true)
		t.expect(mail(find(list, "Row_m1")).unread).toBe(false)
		local row = find(list, "Row_m1")
		swipe(row, engine, 240, 100)
		find(row, "flag").Activated.fire()
		t.expect(mail(row).flagged).toBe(true)
		find(list, "Jump").Activated.fire()
		t.expect(body.CanvasPosition.Y > 0).toBe(true)
		t.expect(built.report().surfaces.list.status.total).toBe(6)
		t.expect(built.report().surfaces.list.status.retained).toBe(6)
		t.expect(find(list, "Columns")).toBe(nil)
		swipe(find(list, "Row_m4"), engine, 300, 10)
		t.expect(built.report().surfaces.list.count).toBe(5)
		t.expect(find(list, "Row_m4")).toBe(nil)
		t.expect(find(list, "Row_m3") ~= nil and find(list, "Row_m5") ~= nil).toBe(true)
		stop()
	end)

	t.it("uses mail table activation editing and native row reorder with independent state", function()
		local built, node, stop, engine, world = mount("row_actions")
		find(node, "table").Activated.fire()
		local page = find(node, "Mail_table")
		local tableNode, body = find(page, "Collection"), find(page, "Body")
		tableNode.AbsoluteSize = engine.types.Vector2.new(800, 440)
		viewport(body, engine, 800, 400)
		nativeDrag.measure(body)
		t.expect(contains(page, "From") and contains(page, "Subject")).toBe(true)
		t.expect(contains(find(body, "m1"), "Ari Foyer")).toBe(true)
		find(find(body, "m1"), "RowHit").Activated.fire()
		t.expect(built.report().surfaces.table.read.m1).toBe(true)
		t.expect(built.report().surfaces.list.read.m1).toBe(false)
		t.expect(find(find(body, "m1"), "Unread").Visible).toBe(false)
		t.expect(find(find(body, "m2"), "Subject").Text).toBe("Order confirmed")
		t.expect(find(find(body, "m1"), "Move").Visible).toBe(false)
		t.expect(find(page, "Edit")).toBeNil()
		world.input.PreferredInput = engine.types.Enum.PreferredInput.Touch
		find(page, "Edit").Activated.fire()
		local handle = find(find(body, "m1"), "Move")
		t.expect(handle.Visible).toBe(true)
		local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(10, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 250))
		detector.DragEnd.fire()
		t.expect(built.report().surfaces.table.moves).toBe(1)
		t.expect(built.report().surfaces.table.rows[1].id ~= "m1").toBe(true)
		find(page, "Jump").Activated.fire()
		t.expect(body.CanvasPosition.Y > 0).toBe(true)
		t.expect(built.report().surfaces.table.status.first > 0).toBe(true)
		stop()
	end)

	t.it("changes grid columns and rendered text through relevant native toolbar actions", function()
		for _, name in { "virtual_grid", "virtual_hgrid" } do
			local built, node, stop, engine = mount(name)
			local body = find(node, "Collection")
			viewport(body, engine, 640, 320)
			local before = built.report().status.rowCount
			find(node, "Columns").Activated.fire()
			t.expect(built.report().status.rowCount).toBe(before * 2)
			local item = find(body, "Item_1")
			find(node, "TextSize").Activated.fire()
			t.expect(item.TextSize).toBe(24)
			find(node, "Jump").Activated.fire()
			t.expect(if name == "virtual_hgrid" then body.CanvasPosition.X > 0 else body.CanvasPosition.Y > 0)
				.toBe(true)
			t.expect(built.report().status.retained < 100).toBe(true)
			find(node, "Reverse").Activated.fire()
			t.expect(built.report().rows[1].id).toBe("5000")
			stop()
		end
	end)

	t.it("keeps variable and native measured posts anchored across all text offsets", function()
		for _, name in { "variable_extents", "measured_extents" } do
			local built, node, stop, engine = mount(name)
			local body = find(node, "Collection")
			viewport(body, engine, 600, 320)
			find(node, "Jump").Activated.fire()
			local first = built.report().status.first
			local originalExtent = built.report().status.extent
			for _, offset in { 4, 10, 14, 0 } do
				find(node, "TextOffset" .. offset).Activated.fire()
				t.expect(find(body, "PostTitle").TextSize).toBe(15 + offset)
				t.expect(find(body, "PostBody").TextSize).toBe(13 + offset)
				if name == "measured_extents" then
					local post = find(body, "Post_" .. first)
					post.AbsoluteSize = engine.types.Vector2.new(600, 100 + offset * 4)
				end
				t.expect(built.report().status.first).toBe(first)
				t.expect(built.report().status.retained < 20).toBe(true)
			end
			if name == "variable_extents" then
				find(node, "TextOffset14").Activated.fire()
				t.expect(built.report().status.extent > originalExtent).toBe(true)
				find(node, "Mode").Activated.fire()
				t.expect(built.report().extents["1"]).toBe(84)
				t.expect(built.report().status.first).toBe(first)
			else
				t.expect(built.report().status.measured > 0).toBe(true)
			end
			t.expect(built.report().built >= built.report().mounted).toBe(true)
			t.expect(find(node, "Actions"):FindFirstChildWhichIsA("UIListLayout").Wraps).toBe(true)
			t.expect(find(node, "Toolbar").AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
			stop()
		end
	end)

	t.it("moves the collection toolbar beside the rows when the page is short and wide", function()
		local _, node, stop, engine = mount("measured_extents")
		local scroll = find(node, "ToolbarScroll")
		local page = scroll.Parent
		local layout = page:FindFirstChildWhichIsA("UIListLayout")
		local collection = find(page, "Collection")
		t.expect(layout.FillDirection).toBe(engine.types.Enum.FillDirection.Vertical)
		page.AbsoluteSize = engine.types.Vector2.new(644, 213)
		t.expect(layout.FillDirection).toBe(engine.types.Enum.FillDirection.Horizontal)
		t.expect(math.abs(scroll.Size.X.Scale - 0.4) < 1e-6).toBe(true)
		t.expect(scroll.Size.Y.Scale).toBe(1)
		t.expect(scroll.AutomaticCanvasSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(collection.Size.Y.Scale).toBe(1)
		page.AbsoluteSize = engine.types.Vector2.new(401, 560)
		t.expect(layout.FillDirection).toBe(engine.types.Enum.FillDirection.Vertical)
		t.expect(scroll.Size.X.Scale).toBe(1)
		t.expect(scroll.AutomaticSize).toBe(engine.types.Enum.AutomaticSize.Y)
		t.expect(collection.Size.X.Scale).toBe(1)
		stop()
	end)

	t.it("renders three racing shelves with measured widths track art and native selection", function()
		local built, node, stop, engine = mount("card_rail")
		for _, name in { "Rail", "WeekendRail", "RecommendedRail" } do
			local rail = find(node, name)
			viewport(rail, engine, 400, 300)
			t.expect(built.report().rails[name].itemExtent).toBe(352)
			t.expect(built.report().rails[name].status.total).toBe(400)
			t.expect(built.report().rails[name].status.retained < 12).toBe(true)
			t.expect(contains(rail, "Livery 001") and contains(rail, "Rally")).toBe(true)
			local preview = find(rail, "Preview")
			t.expect(preview:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio).toBe(16 / 9)
			t.expect(#find(preview, "Track"):GetControlPoints()).toBe(17)
			find(rail, "Card_c1").Activated.fire()
			t.expect(built.report().selectedKey).toBe("c1")
		end
		viewport(find(node, "Rail"), engine, 1000, 300)
		t.expect(built.report().rails.Rail.itemExtent).toBe(244)
		t.expect(built.report().rails.WeekendRail.itemExtent).toBe(352)
		t.expect(contains(find(node, "Selected"), "Selected: Livery 001 · Rally")).toBe(true)
		t.expect(built.report().shelves).toBe(3)
		stop()
	end)

	t.it("opens the mail row menu with Shift+Return on a selected row and runs a chosen item", function()
		local built, node, stop, engine, world = mount("row_actions")
		local list = find(node, "Mail_list")
		viewport(find(list, "Collection"), engine, 700, 240)
		local row = find(list, "Row_m1")
		row.AbsoluteSize = engine.types.Vector2.new(700, 112)
		local content = find(row, "Item_m1")
		t.expect(action(world.target, "RowActionsToggle")).toBeNil()
		world.gui.SelectedObject = content
		t.expect(world.gui.SelectedObject).toBe(content)
		local toggle = action(world.target, "RowActionsToggle")
		t.expect(toggle ~= nil).toBe(true)
		local binding = toggle:FindFirstChildWhichIsA("InputBinding")
		t.expect(binding.KeyCode).toBe(engine.types.Enum.KeyCode.Return)
		t.expect(
			binding.PrimaryModifier == engine.types.Enum.KeyCode.LeftShift
				or binding.PrimaryModifier == engine.types.Enum.KeyCode.RightShift
		).toBe(true)
		t.expect(find(world.target, "MenuPanel")).toBeNil()
		toggle.Pressed.fire()
		local panel = find(world.target, "MenuPanel")
		t.expect(panel ~= nil).toBe(true)
		for _, id in { "leading:read", "trailing:delete", "trailing:flag" } do
			t.expect(find(panel, id) ~= nil).toBe(true)
		end
		t.expect(contains(panel, "Mark read") and contains(panel, "Delete") and contains(panel, "Flag")).toBe(true)
		t.expect(built.report().surfaces.list.read.m1).toBe(false)
		t.expect(built.report().surfaces.list.count).toBe(6)
		find(panel, "trailing:flag").Activated.fire()
		t.expect(find(world.target, "MenuPanel")).toBeNil()
		t.expect(built.report().surfaces.list.flagged.m1).toBe(true)
		t.expect(built.report().surfaces.list.count).toBe(6)
		stop()
	end)

	t.it("selects a mail table row in edit mode, deletes it from the toolbar and swipes a row open", function()
		local built, node, stop, engine, world = mount("row_actions")
		find(node, "table").Activated.fire()
		local page = find(node, "Mail_table")
		local tableNode, body = find(page, "Collection"), find(page, "Body")
		tableNode.AbsoluteSize = engine.types.Vector2.new(800, 440)
		viewport(body, engine, 800, 400)
		nativeDrag.measure(body)
		t.expect(find(find(body, "m2"), "SelectMark").Visible).toBe(false)
		world.input.PreferredInput = engine.types.Enum.PreferredInput.Touch
		find(page, "Edit").Activated.fire()
		t.expect(find(find(body, "m2"), "SelectMark").Visible).toBe(true)
		find(find(body, "m2"), "RowHit").Activated.fire({ UserInputType = engine.types.Enum.UserInputType.Touch }, 1)
		t.expect(find(find(find(body, "m2"), "SelectMark"), "Check").Visible).toBe(true)
		find(page, "DeleteSelected").Activated.fire({ UserInputType = engine.types.Enum.UserInputType.Touch })
		t.expect(built.report().surfaces.table.count).toBe(5)
		for _, item in built.report().surfaces.table.rows do
			t.expect(item.id ~= "m2").toBe(true)
		end
		t.expect(find(body, "m2")).toBeNil()
		find(page, "Edit").Activated.fire()
		world.input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		local order = {}
		for index, item in built.report().surfaces.table.rows do
			order[index] = item.id
		end
		local row = find(find(body, "m1"), "Row_m1")
		t.expect(find(row, "trailing").Visible).toBe(false)
		row.AbsoluteSize = engine.types.Vector2.new(800, 100)
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(700, 50))
		detector.DragContinue.fire(engine.types.Vector2.new(520, 50))
		detector.DragEnd.fire()
		t.expect(find(row, "trailing").Visible).toBe(true)
		t.expect(find(find(row, "trailing"), "delete") ~= nil).toBe(true)
		t.expect(built.report().surfaces.table.moves).toBe(0)
		t.expect(built.report().surfaces.table.count).toBe(5)
		for index, item in built.report().surfaces.table.rows do
			t.expect(item.id).toBe(order[index])
		end
		t.expect(built.report().surfaces.table.read.m1).toBe(false)
		stop()
	end)

	t.it("mounts the virtual mail surface alone and swipes deletes and opens row menus from each input", function()
		local built, node, stop, engine, world = mount("row_actions")
		t.expect(find(node, "Mail_list").Parent.Visible).toBe(true)
		t.expect(find(node, "Mail_virtual")).toBeNil()
		find(node, "virtual").Activated.fire()
		t.expect(built.report().active).toBe("virtual")
		local page = find(node, "Mail_virtual")
		t.expect(page.Parent.Visible).toBe(true)
		t.expect(find(node, "Mail_list").Parent.Visible).toBe(false)
		t.expect(find(node, "Mail_table")).toBeNil()
		local body = find(page, "Collection")
		t.expect(body:IsA("ScrollingFrame")).toBe(true)
		viewport(body, engine, 700, 480)
		t.expect(built.report().surfaces.virtual.count).toBe(6)
		local row = find(page, "Row_m1")
		row.AbsoluteSize = engine.types.Vector2.new(700, 112)
		local detector = row:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(650, 50))
		detector.DragContinue.fire(engine.types.Vector2.new(520, 50))
		detector.DragEnd.fire()
		t.expect(find(row, "trailing").Visible).toBe(true)
		t.expect(built.report().surfaces.virtual.count).toBe(6)
		swipe(find(page, "Row_m4"), engine, 300, 10)
		t.expect(built.report().surfaces.virtual.count).toBe(5)
		t.expect(find(page, "Row_m4")).toBeNil()
		local content = find(find(page, "Row_m3"), "Item_m3")
		world.gui.SelectedObject = content
		local delete = action(world.target, "RowActionsDelete")
		t.expect(delete ~= nil).toBe(true)
		delete.Pressed.fire()
		t.expect(built.report().surfaces.virtual.count).toBe(4)
		t.expect(find(page, "Row_m3")).toBeNil()
		for _, item in built.report().surfaces.virtual.rows do
			t.expect(item.id ~= "m3" and item.id ~= "m4").toBe(true)
		end
		local second = find(find(page, "Row_m2"), "Item_m2")
		world.gui.SelectedObject = second
		local reveal = action(world.target, "RowActionsReveal")
		local keys = {}
		for _, binding in reveal:GetChildren() do
			table.insert(keys, binding.KeyCode.Name)
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "ButtonX", "Menu" })
		reveal.Pressed.fire()
		local panel = find(world.target, "MenuPanel")
		t.expect(panel ~= nil).toBe(true)
		t.expect(find(panel, "leading:read") ~= nil and find(panel, "trailing:flag") ~= nil).toBe(true)
		t.expect(built.report().surfaces.virtual.count).toBe(4)
		local held = find(page, "Row_m5")
		held.AbsoluteSize = engine.types.Vector2.new(700, 112)
		local heldDetector = held:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
		heldDetector.DragStart.fire(engine.types.Vector2.new(650, 50))
		heldDetector.DragContinue.fire(engine.types.Vector2.new(560, 50))
		stop()
		t.expect(find(world.target, "MenuPanel")).toBeNil()
		local after = engine.census()
		t.expect(after.live).toBe(world.baseline.live)
		t.expect(after.connections).toBe(world.baseline.connections)
	end)

	t.it("drops the mail heading on a short landscape and keeps the first row on every surface", function()
		local tall, tallNode, stopTall = mount("row_actions", { width = 1280, height = 720 })
		t.expect(find(find(tallNode, "Mail_list"), "Title").Visible).toBe(true)
		t.expect(tall.report().surfaces.list.count).toBe(6)
		stopTall()
		local built, node, stop, engine, world = mount("row_actions", { width = 844, height = 390 })
		for _, kind in { "list", "table", "virtual" } :: { "list" | "table" | "virtual" } do
			find(node, kind).Activated.fire()
			local page = find(node, "Mail_" .. kind)
			local title = find(find(page, "Toolbar"), "Title")
			t.expect(title.Visible).toBe(false)
			t.expect(find(page, "Collection"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
				.toBe(engine.types.Enum.UIFlexMode.Fill)
			local body = if kind == "table" then find(page, "Body") else find(page, "Collection")
			viewport(body, engine, 844, 200)
			t.expect(find(body, "Row_m1") ~= nil).toBe(true)
			t.expect(built.report().surfaces[kind].status.first).toBe(1)
		end
		world.viewport:set({ width = 844, height = 720 })
		t.expect(find(find(node, "Mail_virtual"), "Title").Visible).toBe(true)
		stop()
	end)
end)

t.describe("file library workbench", function()
	local function file(model, key)
		for _, item in model.rows:peek() do
			if item.id == tostring(key) then
				return item
			end
		end
		error("Missing file " .. tostring(key))
	end
	t.it("edits desktop cells directly and uses Edit on coarse inputs with one permission toggle", function()
		local built, node, stop, engine, world = mount("collection_workbench")
		for _, input in { "KeyboardAndMouse", "Touch", "Gamepad" } do
			world.input.PreferredInput = (engine.types.Enum.PreferredInput :: any)[input]
			for _, mode in { "icons", "list", "details" } do
				find(find(node, "ViewMode"), mode).Activated.fire()
				local collection = find(node, "primary")
				collection.AbsoluteSize = engine.types.Vector2.new(800, 400)
				viewport(if mode == "details" then find(collection, "Body") else collection, engine, 800, 400)
				local coarse = input ~= "KeyboardAndMouse"
				t.expect(find(node, "Edit").Visible).toBe(coarse)
				t.expect(find(collection, "Rename") ~= nil).toBe(true)
				t.expect(find(collection, "Rename"):FindFirstChildWhichIsA("TextBox", true).TextEditable)
					.toBe(not coarse)
				if coarse then
					find(node, "Edit").Activated.fire()
					t.expect(find(collection, "Rename") ~= nil).toBe(true)
				end
				find(node, "EnableEditing").Activated.fire()
				t.expect(built.model.editingEnabled:peek()).toBe(false)
				t.expect(find(collection, "Rename"):FindFirstChildWhichIsA("TextBox", true).TextEditable).toBe(false)
				t.expect(find(node, "Create").Interactable).toBe(false)
				t.expect(find(node, "LabelGreen").Interactable).toBe(false)
				find(node, "EnableEditing").Activated.fire()
				if coarse then
					find(node, "Edit").Activated.fire()
				end
				t.expect(find(collection, "Rename") ~= nil).toBe(true)
				if mode == "details" then
					t.expect(contains(collection, "Kind")).toBe(true)
				end
				if coarse then
					find(node, "Edit").Activated.fire()
				end
			end
		end
		stop()
	end)

	t.it("keeps compact icons in multiple columns and binds the grid size slider", function()
		local built, node, stop, engine, world = mount("collection_workbench", { width = 390, height = 844 })
		world.input.PreferredInput = engine.types.Enum.PreferredInput.Touch
		local grid = find(node, "primary")
		viewport(grid, engine, 350, 400)
		local first, second = find(grid, "1"), find(grid, "2")
		t.expect(second.Position.Y.Offset).toBe(first.Position.Y.Offset)
		t.expect(second.Position.X.Offset > first.Position.X.Offset).toBe(true)
		find(node, "Edit").Activated.fire()
		t.expect(find(first, "Cells").Size.X.Offset).toBe(0)
		world.gui.SelectedObject = find(node, "GridSize")
		local increase = action(world.target, "Increase")
		t.expect(increase ~= nil).toBe(true)
		increase.Pressed.fire()
		increase.Released.fire()
		t.expect(built.model.gridSize:peek()).toBe(160)
		built.model.gridSize:set(260)
		t.expect(second.Position.Y.Offset > first.Position.Y.Offset).toBe(true)
		built.model.mode:set("list")
		t.expect(find(node, "GridSize").Visible).toBe(false)
		stop()
	end)

	t.it("moves selected files through native collection reorder and gates all writes", function()
		local built, node, stop, engine, world = mount("collection_workbench")
		local model = built.model
		model.mode:set("list")
		local body = find(node, "primary")
		viewport(body, engine, 700, 1200)
		world.input.PreferredInput = engine.types.Enum.PreferredInput.Touch
		find(node, "Edit").Activated.fire()
		model.selection:set({ ["1"] = true, ["2"] = true })
		local detector = find(find(body, "1"), "Move"):FindFirstChildWhichIsA("UIDragDetector")
		detector.DragStart.fire(engine.types.Vector2.new(10, 10))
		detector.DragContinue.fire(engine.types.Vector2.new(10, 1000))
		detector.DragEnd.fire()
		t.expect(model.rows:peek()[4].id ~= "1").toBe(true)
		local moved = {}
		for i, item in model.rows:peek() do
			if item.id == "1" or item.id == "2" then
				table.insert(moved, i)
			end
		end
		t.expect(moved[2]).toBe(moved[1] + 1)
		local hiddenBefore = {}
		for _, item in model.rows:peek() do
			if not string.find(item.name, "Coast", 1, true) then
				table.insert(hiddenBefore, item.id)
			end
		end
		model.query:set("Coast")
		model.reorder({ "1" }, 0)
		local hiddenAfter, visible = {}, {}
		for _, item in model.rows:peek() do
			table.insert(if string.find(item.name, "Coast", 1, true) then visible else hiddenAfter, item.id)
		end
		t.expect(hiddenAfter).toEqual(hiddenBefore)
		t.expect(visible[1]).toBe("1")
		t.expect(visible[2]).toBe("5")
		local before = model.rows:peek()
		find(node, "EnableEditing").Activated.fire()
		model.change("1", "name", "Blocked")
		model.change(nil, "color", "Green")
		model.remove({ "1" })
		model.reorder({ "1" }, 2)
		built.steps.create()
		built.steps.undo()
		t.expect(model.rows:peek()).toBe(before)
		stop()
	end)

	t.it("labels the whole selection across filtering and deletes it once with undo", function()
		local built, node, stop = mount("collection_workbench")
		local model, selected = built.model, {}
		local labeled = 0
		for _, item in model.rows:peek() do
			if item.color ~= "None" then
				labeled += 1
			end
		end
		t.expect(labeled).toBe(2)
		t.expect(find(node, "LabelGreen").Interactable).toBe(false)
		for i = 1, 10 do
			selected[tostring(i)] = true
		end
		model.selection:set(selected)
		t.expect(find(node, "LabelGreen").Interactable).toBe(true)
		model.query:set("001")
		find(node, "LabelGreen").Activated.fire()
		for i = 1, 10 do
			t.expect(file(model, i).color).toBe("Green")
		end
		model.change("11", "color", "Red")
		t.expect(file(model, "11").color).toBe("Red")
		t.expect(file(model, "1").color).toBe("Green")
		model.change(nil, "color", "None")
		for i = 1, 10 do
			t.expect(file(model, i).color).toBe("None")
		end
		model.query:set("missing")
		find(node, "Delete").Activated.fire()
		t.expect(built.report().count).toBe(17)
		t.expect(next(model.selection:peek())).toBeNil()
		built.steps.undo()
		t.expect(built.report().count).toBe(27)
		for i = 1, 10 do
			t.expect(model.selection:peek()[tostring(i)]).toBe(true)
		end
		stop()
	end)

	t.it("shares files and durable drafts through view switches creation deletion and undo", function()
		local built, node, stop = mount("collection_workbench")
		local model = built.model
		t.expect(built.report().count).toBe(27)
		model.editing:set(true)
		model.draft("1"):set({ text = "Unfinished name", original = file(model, "1").name })
		for _, mode in { "list", "details", "icons" } do
			model.mode:set(mode)
			t.expect(model.draft("1"):peek().text).toBe("Unfinished name")
		end
		model.linked:set(true)
		model.change("1", "name", "Shared name")
		t.expect(file(model, "1").name).toBe("Shared name")
		model.selection:set({ ["1"] = true })
		model.query:set("missing")
		t.expect(model.selection:peek()["1"]).toBe(true)
		built.steps.create()
		t.expect(built.report().count).toBe(28)
		t.expect(model.query:peek()).toBe("")
		model.remove({ "25" })
		t.expect(built.report().count).toBe(27)
		built.steps.undo()
		t.expect(built.report().count).toBe(28)
		t.expect(model.selection:peek()["25"]).toBe(true)
		built.steps.large()
		t.expect(built.report().count).toBe(1003)
		stop()
	end)
end)

t.describe("file library folders", function()
	t.it("opens folders with desktop double click or touch and gamepad activation, then goes back", function()
		for _, inputName in { "MouseButton1", "Touch", "Gamepad1" } do
			local built, node, stop, engine, world = mount("collection_workbench")
			local model = built.model
			model.query:set("Environments")
			local body = find(node, "primary")
			viewport(body, engine, 700, 600)
			local hit = find(find(body, "environments"), "RowHit")
			local input = {
				UserInputType = if inputName == "MouseButton1"
					then engine.types.Enum.UserInputType.MouseButton1
					elseif inputName == "Touch" then engine.types.Enum.UserInputType.Touch
					else engine.types.Enum.UserInputType.Gamepad1,
			}
			hit.Activated.fire(input, 0)
			if inputName == "MouseButton1" then
				t.expect(#model.path:peek()).toBe(0)
				hit.Activated.fire(input, 1)
			end
			t.expect(model.path:peek()[1].value).toBe("environments")
			t.expect(next(model.selection:peek())).toBeNil()
			local back = action(world.target, "NavigationBack")
			t.expect(back ~= nil).toBe(true)
			back.Pressed.fire()
			back.Released.fire()
			t.expect(#model.path:peek()).toBe(0)
			t.expect(action(world.target, "NavigationBack")).toBeNil()
			stop()
		end
	end)
	t.it("moves and copies complete folders, rejects cycles, and restores deleted descendants", function()
		local built, _, stop = mount("collection_workbench")
		local model = built.model
		local function item(key)
			for _, row in model.rows:peek() do
				if row.id == key then
					return row
				end
			end
			return nil
		end
		local folder = item("environments")
		local payload = { kind = "files", collection = "library", items = { folder }, keys = { folder.id } }
		t.expect(model.receive("library", "archive").accepts(payload)).toBe(false)
		t.expect(model.receive("library", "materials").onDrop(payload, { operation = "move" })).toBe(true)
		t.expect(item("environments").parent).toBe("materials")
		t.expect(item("archive").parent).toBe("environments")
		built.steps.undo()
		t.expect(item("environments").parent).toBeNil()
		local count = #model.rows:peek()
		t.expect(model.receive("library", "materials").onDrop(payload, { operation = "copy" })).toBe(true)
		t.expect(#model.rows:peek() > count + 1).toBe(true)
		local unique = {}
		for _, row in model.rows:peek() do
			t.expect(unique[row.id]).toBeNil()
			unique[row.id] = true
		end
		built.steps.undo()
		model.openFolder(item("archive"))
		t.expect(#model.path:peek()).toBe(2)
		model.remove({ "environments" })
		t.expect(item("archive")).toBeNil()
		t.expect(#model.path:peek()).toBe(0)
		built.steps.undo()
		t.expect(item("archive").parent).toBe("environments")
		t.expect(#model.rows:peek()).toBe(count)
		stop()
	end)
end)
