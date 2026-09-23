--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

local function find(node, name)
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

local function mount(name)
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target, guiService = engine.new("Folder"), engine.new("GuiService")
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		guiService = guiService,
		runService = { Heartbeat = engine.heartbeat },
		UI = Facet.controls(runtime, {
			types = engine.types,
			viewport = viewport,
			guiService = guiService,
			services = { GuiService = guiService },
			inputParent = target,
			reducedMotion = true,
		}),
	}
	local built
	local stop, node = runtime.mount(function()
		built = require("../examples/gallery/scenarios/" .. name).build(ctx)
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	return built, node, function()
		stop()
		runtime.dispose()
	end, engine
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
		local built, node, stop, engine = mount("table_virtualized")
		local tableNode, body = find(node, "Collection"), find(node, "Body")
		tableNode.AbsoluteSize = engine.types.Vector2.new(800, 440)
		viewport(body, engine, 800, 400)
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
		find(node, "Edit").Activated.fire()
		t.expect(find(find(body, "e1500"), "Move").Interactable).toBe(true)
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
		t.expect(contains(find(list, "Row_m1"), "Unread · Kickoff notes")).toBe(true)
		t.expect(contains(find(list, "Row_m2"), "Read · Order confirmed")).toBe(true)
		t.expect(contains(find(list, "Row_m3"), "Unread · Flagged · Weekly digest")).toBe(true)
		t.expect(contains(find(list, "Row_m1"), "Ari Foyer")).toBe(true)
		t.expect(contains(find(list, "Row_m1"), "Quick recap from the sync")).toBe(true)
		for _ = 1, 2 do
			swipe(find(list, "Row_m1"), engine, 10, 300)
		end
		t.expect(built.report().surfaces.list.read.m1).toBe(true)
		t.expect(contains(find(list, "Row_m1"), "Read · Kickoff notes")).toBe(true)
		local row = find(list, "Row_m1")
		swipe(row, engine, 240, 100)
		find(row, "flag").Activated.fire()
		t.expect(contains(row, "Read · Flagged · Kickoff notes")).toBe(true)
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
		local built, node, stop, engine = mount("row_actions")
		find(node, "table").Activated.fire()
		local page = find(node, "Mail_table")
		local tableNode, body = find(page, "Collection"), find(page, "Body")
		tableNode.AbsoluteSize = engine.types.Vector2.new(800, 440)
		viewport(body, engine, 800, 400)
		t.expect(contains(page, "From") and contains(page, "Subject")).toBe(true)
		t.expect(contains(find(body, "m1"), "Ari Foyer")).toBe(true)
		find(find(body, "m1"), "RowHit").Activated.fire()
		t.expect(built.report().surfaces.table.read.m1).toBe(true)
		t.expect(built.report().surfaces.list.read.m1).toBe(false)
		t.expect(contains(find(body, "m1"), "Read · Kickoff notes")).toBe(true)
		t.expect(find(find(body, "m1"), "Move").Interactable).toBe(false)
		find(page, "Edit").Activated.fire()
		local handle = find(find(body, "m1"), "Move")
		t.expect(handle.Interactable).toBe(true)
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

	t.it("renders three racing shelves with measured widths track art and native selection", function()
		local built, node, stop, engine = mount("card_rail")
		for _, name in { "Rail", "WeekendRail", "RecommendedRail" } do
			local rail = find(node, name)
			viewport(rail, engine, 400, 300)
			t.expect(built.report().rails[name].itemExtent).toBe(360)
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
		t.expect(built.report().rails.Rail.itemExtent).toBe(240)
		t.expect(built.report().rails.WeekendRail.itemExtent).toBe(360)
		t.expect(contains(find(node, "Selected"), "Selected: Livery 001 · Rally")).toBe(true)
		t.expect(built.report().shelves).toBe(3)
		stop()
	end)
end)
