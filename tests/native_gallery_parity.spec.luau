--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
local requireDynamic = require :: (any) -> any
type Readable<T> = { peek: (Readable<T>) -> T }
type Use = <T>(Readable<T>) -> T
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose: ComposeModule = Facet.Compose
local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local result = find(child, name)
		if result then
			return result
		end
	end
	return nil
end
local function mount(name: string)
	local engine = engineLib.new()
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local gui = engine.new("GuiService")
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		Host = (runtime.constructors :: unknown) :: RobloxHost,
		runtime = runtime,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		guiService = gui,
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		runService = { Heartbeat = engine.heartbeat },
		reducedMotion = Compose.cell(false),
		pageVisible = Compose.cell(true),
	}
	ctx.UI = Facet.controls(runtime, {
		types = engine.types,
		viewport = ctx.viewport,
		guiService = gui,
		services = { GuiService = gui },
		inputParent = target,
		motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
			return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
		end) :: unknown) :: MotionLevel,
	})
	local built
	local stop, node: any = runtime.mount(function()
		built = requireDynamic("../examples/gallery/scenarios/" .. name).build(ctx)
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	return built,
		node,
		ctx,
		engine,
		function()
			stop()
			runtime:dispose()
			t.expect(#target:GetChildren()).toBe(0)
		end
end
local function near(a: number, b)
	assert(math.abs(a - b) < 0.001, string.format("expected %.8f near %.8f", a, b))
end

t.describe("restored native gallery parity", function()
	t.it("reports and navigates Journey across measured widths native edits and declared steps", function()
		local built, node, ctx, _, close = mount("navigation_stack")
		local root = find(node, "NavigationFlow")
		local search = find(node, "Search")
		t.expect(built.report().axis).toBe("x")
		root.AbsoluteSize = ctx.types.Vector2.new(390, 720)
		t.expect(built.report().axis).toBe("y")
		t.expect(find(node, "SearchLayout"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(ctx.types.Enum.FillDirection.Vertical)
		search:CaptureFocus()
		search.Text = "forest"
		t.expect(built.report().matches).toBe(1)
		find(node, "Result-forest").Activated.fire()
		t.expect(built.report().navigation.depth).toBe(1)
		t.expect(built.report().destination).toBe("forest")
		local notes = find(node, "Notes")
		notes:CaptureFocus()
		notes.Text = "Bring a map."
		notes.FocusLost.fire(false)
		root.AbsoluteSize = ctx.types.Vector2.new(900, 720)
		t.expect(built.report().axis).toBe("x")
		t.expect(find(node, "Columns"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(ctx.types.Enum.FillDirection.Horizontal)
		t.expect(find(node, "Writing").Size.X.Scale).toBe(0.5)
		find(node, "Review").Activated.fire()
		t.expect(built.report().navigation.depth).toBe(2)
		t.expect(find(node, "DestinationError")).toBe(nil)
		t.expect(built.report().notes).toBe("Bring a map.")
		find(find(node, "review"), "Back").Activated.fire()
		t.expect(built.report().navigation.depth).toBe(1)
		t.expect(find(node, "Notes")).toBe(notes)
		built.steps.review()
		t.expect(find(node, "DestinationError")).toBe(nil)
		find(node, "StartAgain").Activated.fire()
		t.expect(built.report().navigation.depth).toBe(0)
		t.expect(find(node, "Search")).toBe(search)
		built.steps.noResults()
		t.expect(built.report().matches).toBe(0)
		built.steps.clearSearch()
		t.expect(built.report().matches).toBe(3)
		built.steps.search()
		t.expect(built.report().matches).toBe(1)
		built.steps.push()
		t.expect(built.report().navigation.depth).toBe(1)
		t.expect(built.steps.back()).toBe(true)
		t.expect(built.steps.back()).toBe(false)
		built.steps.reset()
		t.expect(built.report().navigation.depth).toBe(0)
		close()
		t.expect(root:GetPropertyChangedSignal("AbsoluteSize").count()).toBe(0)
	end)
	t.it("keeps the journey details rows inside their column: the words hug and a spacer takes the rest", function()
		local built, node, _, _, close = mount("navigation_stack")
		built.steps.push()
		for _, rowName in { "Baseline", "LastBaseline" } do
			local row = find(node, rowName)
			t.expect(`{rowName}: {row.Size.X.Scale}`).toBe(`{rowName}: 1`)
			for _, child in row:GetChildren() do
				if child:IsA("TextLabel") then
					t.expect(`{rowName}/{child.Text}: {child.Size.X.Scale}`).toBe(`{rowName}/{child.Text}: 0`)
				end
			end
		end
		t.expect(find(find(node, "Baseline"), "FlexibleGap"):FindFirstChildWhichIsA("UIFlexItem") ~= nil).toBe(true)
		local back = find(find(node, "details"), "Back")
		t.expect(back.AutomaticSize.Name .. " " .. back.Size.X.Scale .. " " .. back.Size.X.Offset).toBe("XY 0 0")
		t.expect(back:FindFirstChild("Title", true).AutomaticSize.Name).toBe("XY")
		close()
	end)
	t.it("reverses automatic equipment rows without changing their instances or balance", function()
		local built, node, _, _, close = mount("component_motion")
		local scanner, beacon = find(node, "Card-scanner"), find(node, "Card-beacon")
		t.expect(scanner.LayoutOrder).toBe(1)
		find(node, "Reverse").Activated.fire()
		t.expect(scanner.LayoutOrder).toBe(3)
		t.expect(beacon.LayoutOrder).toBe(1)
		find(node, "Buy").Activated.fire()
		t.expect(built.report().balance).toBe(60)
		find(node, "Reverse").Activated.fire()
		t.expect(find(node, "Card-scanner")).toBe(scanner)
		t.expect(scanner.LayoutOrder).toBe(1)
		t.expect(built.report().balance).toBe(60)
		close()
	end)
	t.it("glides the automatic equipment rows to their reversed places", function()
		local _, node, _, engine, close = mount("component_motion")
		local list = find(node, "Items")
		list.AbsoluteWindowSize = engine.types.Vector2.new(400, 400)
		list.AbsoluteSize = engine.types.Vector2.new(400, 400)
		engine.heartbeat.fire(1 / 60)
		local row = find(node, "Card-scanner").Parent.Parent
		local before = row.Position.Y.Offset
		find(node, "Reverse").Activated.fire()
		local landing = 2 * (56 + 8)
		engine.heartbeat.fire(0.05)
		local during = row.Position.Y.Offset
		t.expect(during > before and during < landing).toBe(true)
		for _ = 1, 30 do
			engine.heartbeat.fire(1 / 60)
		end
		t.expect(row.Position.Y.Offset).toBe(landing)
		close()
	end)
	t.it("runs shared color size rotation fade order and detail changes while charge remains informational", function()
		local built, node, _, engine, close = mount("with_animation")
		local alpha, pip, puck = find(node, "Alpha"), find(node, "Pip"), find(node, "Puck")
		local initialColor = puck.BackgroundColor3
		near(puck.Position.X.Offset, 0)
		find(node, "Animate").Activated.fire()
		engine.heartbeat.fire(0.05)
		local r = built.report()
		t.expect(r.progress > 0 and r.progress < 1).toBe(true)
		near(find(node, "GrowingCard").Size.Y.Offset, math.floor(64 + 64 * r.progress))
		near(find(node, "Badge").Rotation, 90 * r.progress)
		near(alpha.Position.Y.Offset, math.floor(96 * r.progress))
		t.expect(puck.BackgroundColor3 ~= initialColor).toBe(true)
		t.expect(find(node, "Pip")).toBe(pip)
		t.expect(pip.Size.X.Offset).toBe(16)
		t.expect(find(node, "DetailPanel") ~= nil).toBe(true)
		local arrival = find(node, "DetailArrival").GroupTransparency
		t.expect(arrival > 0 and arrival < 1).toBe(true)
		built.reduced:set(true)
		near(find(node, "GrowingCard").Size.Y.Offset, 128)
		t.expect(built.report().charge < 1).toBe(true)
		engine.heartbeat.fire(1.3)
		near(built.report().charge, 1)
		find(node, "Animate").Activated.fire()
		near(puck.Position.X.Offset, 0)
		near(alpha.Position.Y.Offset, 0)
		t.expect(find(node, "Alpha")).toBe(alpha)
		t.expect(find(node, "DetailPanel")).toBe(nil)
		close()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)
	t.it("keeps cooldown curve race and panel duration independent with real easing and readable endpoints", function()
		local built, node, _, engine, close = mount("time_curves")
		local marker = find(find(node, "Linear"), "Marker")
		near(marker.Position.X.Offset, 0)
		find(node, "Launch").Activated.fire()
		engine.heartbeat.fire(0.1)
		local r = built.report()
		near(r.curves.Linear, 0.25)
		t.expect(r.curves.Quad > r.curves.Linear).toBe(true)
		t.expect(r.curves.Back > r.curves.Quad).toBe(true)
		near(r.cooldown, 0)
		near(r.panelProgress, 0)
		find(node, "RunRace").Activated.fire()
		engine.heartbeat.fire(0.25)
		near(built.report().cooldown, 0.5)
		near(built.report().elapsed, 0.25)
		find(node, "FlyPanel").Activated.fire()
		engine.heartbeat.fire(0.225)
		near(built.report().panelProgress, 0.5)
		near(find(node, "GrowingPanel").Size.Y.Offset, 96)
		engine.heartbeat.fire(0.3)
		near(marker.Position.X.Scale, 1)
		near(marker.Position.X.Offset, -28)
		built.reduced:set(true)
		find(node, "Launch").Activated.fire()
		near(marker.Position.X.Scale, 0)
		near(marker.Position.X.Offset, 0)
		find(node, "RunRace").Activated.fire()
		engine.heartbeat.fire(0.1)
		t.expect(built.report().cooldown > 0 and built.report().cooldown < 1).toBe(true)
		close()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)
	t.it("measures three independent containers and preserves native cards across guides and replay changes", function()
		local built, node, ctx, _, close = mount("container_grid")
		local sidebar, column, board = find(node, "Sidebar"), find(node, "Column"), find(node, "Board")
		sidebar.AbsoluteSize = ctx.types.Vector2.new(360, 300)
		column.AbsoluteSize = ctx.types.Vector2.new(720, 300)
		board.AbsoluteSize = ctx.types.Vector2.new(1040, 300)
		local r = built.report()
		t.expect(r.Sidebar.columns).toBe(3)
		t.expect(r.Column.columns).toBe(6)
		t.expect(r.Board.columns).toBe(12)
		local standings, replay = find(sidebar, "Standings"), find(sidebar, "Media")
		sidebar.AbsoluteSize = ctx.types.Vector2.new(1040, 300)
		t.expect(built.report().Sidebar.columns).toBe(12)
		t.expect(built.report().Column.columns).toBe(6)
		t.expect(find(sidebar, "Standings")).toBe(standings)
		find(node, "Replays").Activated.fire()
		t.expect(replay.Visible).toBe(false)
		find(node, "Replays").Activated.fire()
		t.expect(find(sidebar, "Media")).toBe(replay)
		t.expect(replay.Visible).toBe(true)
		find(node, "GuidesToggle").Activated.fire()
		t.expect(find(sidebar, "Lane12").Visible).toBe(true)
		find(node, "Resize").Activated.fire()
		t.expect(sidebar:FindFirstChildWhichIsA("UISizeConstraint").MaxSize.X).toBe(1040)
		close()
	end)
	t.it("clamps the objective separates crowded markers respects the HUD band and only occludes supplies", function()
		local built, node, ctx, _, close = mount("world_markers")
		local map = find(node, "Map")
		map.AbsoluteSize = ctx.types.Vector2.new(309, 360)
		local objective = find(map, "A")
		find(node, "Move").Activated.fire()
		t.expect(find(objective, "Direction").Visible).toBe(true)
		t.expect(objective.Position.X.Offset + objective.Size.X.Offset <= 309).toBe(true)
		find(node, "Move").Activated.fire()
		find(node, "Crowd").Activated.fire()
		local rows = built.report().markers
		for i = 1, 3 do
			t.expect(rows[i].y >= 64 and rows[i].y + 48 <= 360).toBe(true)
			for j = i + 1, 3 do
				t.expect(math.abs(rows[i].y - rows[j].y) >= 56).toBe(true)
			end
		end
		find(node, "Hide").Activated.fire()
		t.expect(find(map, "A").Visible).toBe(true)
		t.expect(find(map, "B").Visible).toBe(true)
		t.expect(find(map, "C").Visible).toBe(false)
		objective.Activated.fire()
		t.expect(built.report().selected).toBe("Objective")
		ctx.pageVisible:set(false)
		t.expect(objective.Visible).toBe(false)
		t.expect(#ctx.worldTarget:GetChildren()).toBe(0)
		close()
	end)
	t.it("an urgent toast waits for a showing toast's read floor, then takes the weakest slot", function()
		local built, node, ctx, engine, close = mount("sponsor_toast")
		ctx.reducedMotion:set(true)
		for i = 1, 3 do
			built.show("Reading " .. i, "Keep reading", { duration = 8, readFloor = 1.5, priority = i })
		end
		built.show("Urgent", "Wait for read floor", { priority = 9 })
		engine.heartbeat.fire(1 / 60)
		t.expect(built.report().visible).toBe(3)
		t.expect(built.report().queued).toBe(1)
		engine.heartbeat.fire(1)
		t.expect(built.report().queued).toBe(1)
		engine.heartbeat.fire(0.6)
		local shown = {}
		for _, row in built.report().rows do
			shown[row.title] = built.report().states[row.id]
		end
		t.expect(shown.Urgent).toBe("visible")
		t.expect(shown["Reading 1"] ~= "visible").toBe(true)
		t.expect(shown["Reading 2"]).toBe("visible")
		find(node, "Beneath").Activated.fire()
		t.expect(built.report().presses).toBe(1)
		built.steps.clear()
		engine.heartbeat.fire(0.5)
		t.expect(#built.report().rows).toBe(0)
		close()
		t.expect(engine.heartbeat.count()).toBe(0)
	end)
	t.it("retains nested color overrides and control paint while disabling focus and activation together", function()
		local built, node, ctx, _, close = mount("inherited_subtree")
		local hero, note, inner = find(node, "HeroTitle"), find(node, "Note"), find(node, "Sub")
		local heroColor, noteColor, innerColor = hero.TextColor3, note.TextColor3, inner.TextColor3
		local go, nested = find(node, "Go"), find(node, "InnerGo")
		local controlColor = go.TextColor3
		built.blend:set(100)
		t.expect(hero.TextColor3 ~= heroColor).toBe(true)
		t.expect(note.TextColor3).toBe(noteColor)
		t.expect(inner.TextColor3).toBe(innerColor)
		t.expect(go.TextColor3).toBe(controlColor)
		ctx.guiService.SelectedObject = nested
		find(node, "PowerToggle").Activated.fire()
		t.expect(ctx.guiService.SelectedObject).toBe(find(node, "After"))
		go.Activated.fire()
		nested.Activated.fire()
		t.expect(built.report().engaged).toBe(0)
		find(node, "After").Activated.fire()
		nested.Activated.fire()
		t.expect(built.report().engaged).toBe(1)
		close()
	end)
end)
