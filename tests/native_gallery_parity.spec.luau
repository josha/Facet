--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	local requireDynamic = require :: (any) -> any
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

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
				Verify.expect(#target:GetChildren()):toBe(0)
			end
	end
	local function near(a: number, b)
		assert(math.abs(a - b) < 0.001, string.format("expected %.8f near %.8f", a, b))
	end

	verifyHarness:suite("restored native gallery parity", function()
		verifyHarness:case("reports and navigates Journey across measured widths native edits and declared steps", {
			id = "native_gallery_parity::restored native gallery parity::reports and navigates Journey across measured widths native edits and declared steps",
			run = function()
				local built, node, ctx, _, close = mount("navigation_stack")
				local root = find(node, "NavigationFlow")
				local search = find(find(node, "Search"), "Field")
				Verify.expect(built.report().axis):toBe("x")
				root.AbsoluteSize = ctx.types.Vector2.new(390, 720)
				Verify.expect(built.report().axis):toBe("y")
				Verify.expect(find(node, "SearchLayout"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(ctx.types.Enum.FillDirection.Vertical)
				search:CaptureFocus()
				search.Text = "forest"
				Verify.expect(built.report().matches):toBe(1)
				find(node, "Result-forest").Activated.fire()
				Verify.expect(built.report().navigation.depth):toBe(1)
				Verify.expect(built.report().destination):toBe("forest")
				local notes = find(node, "Notes")
				notes:CaptureFocus()
				notes.Text = "Bring a map."
				notes.FocusLost.fire(false)
				root.AbsoluteSize = ctx.types.Vector2.new(900, 720)
				Verify.expect(built.report().axis):toBe("x")
				Verify.expect(find(node, "Columns"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(ctx.types.Enum.FillDirection.Horizontal)
				Verify.expect(find(node, "Writing").Size.X.Scale):toBe(0.5)
				find(node, "Review").Activated.fire()
				Verify.expect(built.report().navigation.depth):toBe(2)
				Verify.expect((find(node, "DestinationError"))):toBe(nil)
				Verify.expect(built.report().notes):toBe("Bring a map.")
				find(find(node, "review"), "Back").Activated.fire()
				Verify.expect(built.report().navigation.depth):toBe(1)
				Verify.expect((find(node, "Notes"))):toBe(notes)
				built.steps.review()
				Verify.expect((find(node, "DestinationError"))):toBe(nil)
				find(node, "StartAgain").Activated.fire()
				Verify.expect(built.report().navigation.depth):toBe(0)
				Verify.expect((find(find(node, "Search"), "Field"))):toBe(search)
				built.steps.noResults()
				Verify.expect(built.report().matches):toBe(0)
				built.steps.clearSearch()
				Verify.expect(built.report().matches):toBe(3)
				built.steps.search()
				Verify.expect(built.report().matches):toBe(1)
				built.steps.push()
				Verify.expect(built.report().navigation.depth):toBe(1)
				Verify.expect((built.steps.back())):toBe(true)
				Verify.expect((built.steps.back())):toBe(false)
				built.steps.reset()
				Verify.expect(built.report().navigation.depth):toBe(0)
				close()
				Verify.expect((root:GetPropertyChangedSignal("AbsoluteSize").count())):toBe(0)
			end,
		})
		verifyHarness:case(
			"keeps the journey details rows inside their column: the words hug and a spacer takes the rest",
			{
				id = "native_gallery_parity::restored native gallery parity::keeps the journey details rows inside their column: the words hug and a spacer takes the rest",
				run = function()
					local built, node, _, _, close = mount("navigation_stack")
					built.steps.push()
					for _, rowName in { "Baseline", "LastBaseline" } do
						local row = find(node, rowName)
						Verify.expect(`{rowName}: {row.Size.X.Scale}`):toBe(`{rowName}: 1`)
						for _, child in row:GetChildren() do
							if child:IsA("TextLabel") then
								Verify.expect(`{rowName}/{child.Text}: {child.Size.X.Scale}`)
									:toBe(`{rowName}/{child.Text}: 0`)
							end
						end
					end
					Verify.expect(
						find(find(node, "Baseline"), "FlexibleGap"):FindFirstChildWhichIsA("UIFlexItem") ~= nil
					)
						:toBe(true)
					local back = find(find(node, "details"), "Back")
					Verify.expect(back.AutomaticSize.Name .. " " .. back.Size.X.Scale .. " " .. back.Size.X.Offset)
						:toBe("XY 0 0")
					Verify.expect(back:FindFirstChild("Title", true).AutomaticSize.Name):toBe("XY")
					close()
				end,
			}
		)
		verifyHarness:case("reverses automatic equipment rows without changing their instances or balance", {
			id = "native_gallery_parity::restored native gallery parity::reverses automatic equipment rows without changing their instances or balance",
			run = function()
				local built, node, _, _, close = mount("component_motion")
				local scanner, beacon = find(node, "Card-scanner"), find(node, "Card-beacon")
				Verify.expect(scanner.LayoutOrder):toBe(1)
				find(node, "Reverse").Activated.fire()
				Verify.expect(scanner.LayoutOrder):toBe(3)
				Verify.expect(beacon.LayoutOrder):toBe(1)
				find(node, "Buy").Activated.fire()
				Verify.expect(built.report().balance):toBe(60)
				find(node, "Reverse").Activated.fire()
				Verify.expect((find(node, "Card-scanner"))):toBe(scanner)
				Verify.expect(scanner.LayoutOrder):toBe(1)
				Verify.expect(built.report().balance):toBe(60)
				close()
			end,
		})
		verifyHarness:case("glides the automatic equipment rows to their reversed places", {
			id = "native_gallery_parity::restored native gallery parity::glides the automatic equipment rows to their reversed places",
			run = function()
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
				Verify.expect(during > before and during < landing):toBe(true)
				for _ = 1, 30 do
					engine.heartbeat.fire(1 / 60)
				end
				Verify.expect(row.Position.Y.Offset):toBe(landing)
				close()
			end,
		})
		verifyHarness:case(
			"runs shared color size rotation fade order and detail changes while charge remains informational",
			{
				id = "native_gallery_parity::restored native gallery parity::runs shared color size rotation fade order and detail changes while charge remains informational",
				run = function()
					local built, node, _, engine, close = mount("with_animation")
					local alpha, pip, puck = find(node, "Alpha"), find(node, "Pip"), find(node, "Puck")
					local initialColor = puck.BackgroundColor3
					near(puck.Position.X.Offset, 0)
					find(node, "Animate").Activated.fire()
					engine.heartbeat.fire(0.05)
					local r = built.report()
					Verify.expect(r.progress > 0 and r.progress < 1):toBe(true)
					near(find(node, "GrowingCard").Size.Y.Offset, math.floor(64 + 64 * r.progress))
					near(find(node, "Badge").Rotation, 90 * r.progress)
					near(alpha.Position.Y.Offset, math.floor(96 * r.progress))
					Verify.expect(puck.BackgroundColor3 ~= initialColor):toBe(true)
					Verify.expect((find(node, "Pip"))):toBe(pip)
					Verify.expect(pip.Size.X.Offset):toBe(16)
					Verify.expect(find(node, "DetailPanel") ~= nil):toBe(true)
					local arrival = find(node, "DetailArrival").GroupTransparency
					Verify.expect(arrival > 0 and arrival < 1):toBe(true)
					built.reduced:set(true)
					near(find(node, "GrowingCard").Size.Y.Offset, 128)
					Verify.expect(built.report().charge < 1):toBe(true)
					engine.heartbeat.fire(1.3)
					near(built.report().charge, 1)
					find(node, "Animate").Activated.fire()
					near(puck.Position.X.Offset, 0)
					near(alpha.Position.Y.Offset, 0)
					Verify.expect((find(node, "Alpha"))):toBe(alpha)
					Verify.expect((find(node, "DetailPanel"))):toBe(nil)
					close()
					Verify.expect((engine.heartbeat.count())):toBe(0)
				end,
			}
		)
		verifyHarness:case(
			"keeps cooldown curve race and panel duration independent with real easing and readable endpoints",
			{
				id = "native_gallery_parity::restored native gallery parity::keeps cooldown curve race and panel duration independent with real easing and readable endpoints",
				run = function()
					local built, node, _, engine, close = mount("time_curves")
					local marker = find(find(node, "Linear"), "Marker")
					near(marker.Position.X.Offset, 0)
					find(node, "Launch").Activated.fire()
					engine.heartbeat.fire(0.1)
					local r = built.report()
					near(r.curves.Linear, 0.25)
					Verify.expect(r.curves.Quad > r.curves.Linear):toBe(true)
					Verify.expect(r.curves.Back > r.curves.Quad):toBe(true)
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
					Verify.expect(built.report().cooldown > 0 and built.report().cooldown < 1):toBe(true)
					close()
					Verify.expect((engine.heartbeat.count())):toBe(0)
				end,
			}
		)
		verifyHarness:case(
			"measures three independent containers and preserves native cards across guides and replay changes",
			{
				id = "native_gallery_parity::restored native gallery parity::measures three independent containers and preserves native cards across guides and replay changes",
				run = function()
					local built, node, ctx, _, close = mount("container_grid")
					local sidebar, column, board = find(node, "Sidebar"), find(node, "Column"), find(node, "Board")
					sidebar.AbsoluteSize = ctx.types.Vector2.new(360, 300)
					column.AbsoluteSize = ctx.types.Vector2.new(720, 300)
					board.AbsoluteSize = ctx.types.Vector2.new(1040, 300)
					local r = built.report()
					Verify.expect(r.Sidebar.columns):toBe(3)
					Verify.expect(r.Column.columns):toBe(6)
					Verify.expect(r.Board.columns):toBe(12)
					local standings, replay = find(sidebar, "Standings"), find(sidebar, "Media")
					sidebar.AbsoluteSize = ctx.types.Vector2.new(1040, 300)
					Verify.expect(built.report().Sidebar.columns):toBe(12)
					Verify.expect(built.report().Column.columns):toBe(6)
					Verify.expect((find(sidebar, "Standings"))):toBe(standings)
					find(node, "Replays").Activated.fire()
					Verify.expect(replay.Visible):toBe(false)
					find(node, "Replays").Activated.fire()
					Verify.expect((find(sidebar, "Media"))):toBe(replay)
					Verify.expect(replay.Visible):toBe(true)
					find(node, "GuidesToggle").Activated.fire()
					Verify.expect(find(sidebar, "Lane12").Visible):toBe(true)
					find(node, "Resize").Activated.fire()
					Verify.expect(sidebar:FindFirstChildWhichIsA("UISizeConstraint").MaxSize.X):toBe(1040)
					close()
				end,
			}
		)
		verifyHarness:case(
			"clamps the objective separates crowded markers respects the HUD band and only occludes supplies",
			{
				id = "native_gallery_parity::restored native gallery parity::clamps the objective separates crowded markers respects the HUD band and only occludes supplies",
				run = function()
					local built, node, ctx, _, close = mount("world_markers")
					local map = find(node, "Map")
					map.AbsoluteSize = ctx.types.Vector2.new(309, 360)
					local objective = find(map, "A")
					find(node, "Move").Activated.fire()
					Verify.expect(find(objective, "Direction").Visible):toBe(true)
					Verify.expect(objective.Position.X.Offset + objective.Size.X.Offset <= 309):toBe(true)
					find(node, "Move").Activated.fire()
					find(node, "Crowd").Activated.fire()
					local rows = built.report().markers
					for i = 1, 3 do
						Verify.expect(rows[i].y >= 64 and rows[i].y + 48 <= 360):toBe(true)
						for j = i + 1, 3 do
							Verify.expect(math.abs(rows[i].y - rows[j].y) >= 56):toBe(true)
						end
					end
					find(node, "Hide").Activated.fire()
					Verify.expect(find(map, "A").Visible):toBe(true)
					Verify.expect(find(map, "B").Visible):toBe(true)
					Verify.expect(find(map, "C").Visible):toBe(false)
					objective.Activated.fire()
					Verify.expect(built.report().selected):toBe("Objective")
					ctx.pageVisible:set(false)
					Verify.expect(objective.Visible):toBe(false)
					Verify.expect(#ctx.worldTarget:GetChildren()):toBe(0)
					close()
				end,
			}
		)
		verifyHarness:case("an urgent toast waits for a showing toast's read floor, then takes the weakest slot", {
			id = "native_gallery_parity::restored native gallery parity::an urgent toast waits for a showing toast's read floor, then takes the weakest slot",
			run = function()
				local built, node, ctx, engine, close = mount("sponsor_toast")
				ctx.reducedMotion:set(true)
				for i = 1, 3 do
					built.show("Reading " .. i, "Keep reading", { duration = 8, readFloor = 1.5, priority = i })
				end
				built.show("Urgent", "Wait for read floor", { priority = 9 })
				engine.heartbeat.fire(1 / 60)
				Verify.expect(built.report().visible):toBe(3)
				Verify.expect(built.report().queued):toBe(1)
				engine.heartbeat.fire(1)
				Verify.expect(built.report().queued):toBe(1)
				engine.heartbeat.fire(0.6)
				local shown = {}
				for _, row in built.report().rows do
					shown[row.title] = built.report().states[row.id]
				end
				Verify.expect(shown.Urgent):toBe("visible")
				Verify.expect(shown["Reading 1"] ~= "visible"):toBe(true)
				Verify.expect(shown["Reading 2"]):toBe("visible")
				find(node, "Beneath").Activated.fire()
				Verify.expect(built.report().presses):toBe(1)
				built.steps.clear()
				engine.heartbeat.fire(0.5)
				Verify.expect(#built.report().rows):toBe(0)
				close()
				Verify.expect((engine.heartbeat.count())):toBe(0)
			end,
		})
		verifyHarness:case(
			"retains nested color overrides and control paint while disabling focus and activation together",
			{
				id = "native_gallery_parity::restored native gallery parity::retains nested color overrides and control paint while disabling focus and activation together",
				run = function()
					local built, node, ctx, _, close = mount("inherited_subtree")
					local hero, note, inner = find(node, "HeroTitle"), find(node, "Note"), find(node, "Sub")
					local heroColor, noteColor, innerColor = hero.TextColor3, note.TextColor3, inner.TextColor3
					local go, nested = find(node, "Go"), find(node, "InnerGo")
					local controlColor = go.TextColor3
					built.blend:set(100)
					Verify.expect(hero.TextColor3 ~= heroColor):toBe(true)
					Verify.expect(note.TextColor3):toBe(noteColor)
					Verify.expect(inner.TextColor3):toBe(innerColor)
					Verify.expect(go.TextColor3):toBe(controlColor)
					ctx.guiService.SelectedObject = nested
					find(node, "PowerToggle").Activated.fire()
					Verify.expect(ctx.guiService.SelectedObject):toBe(find(node, "After"))
					go.Activated.fire()
					nested.Activated.fire()
					Verify.expect(built.report().engaged):toBe(0)
					find(node, "After").Activated.fire()
					nested.Activated.fire()
					Verify.expect(built.report().engaged):toBe(1)
					close()
				end,
			}
		)
	end)
end
