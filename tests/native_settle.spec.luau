--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FolderConstructor = typeof(require("@repo/tools/typecheck/aliases").FolderConstructor)
	local FixtureCollectionTypes = require("../src/ui/collection_types")

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local Vector2 = require("@lune/roblox").Vector2

	local FRAME = 1 / 60

	local function sheet(extra: { [string]: any }?, options: any?): any
		local detent = Compose.cell("medium")
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			local spec: any = {
				isPresented = Compose.cell(true),
				detent = detent,
				title = "Race details",
				content = function(): Instance
					return Host.TextLabel "Copy" { Text = "Body" }
				end,
			}
			for key, value in (extra or {} :: { [string]: any }) do
				spec[key] = value
			end
			return UI.Sheet "Sheet"(spec)
		end, options)
		w.detent = detent
		local modal = w.find("Modal")
		modal.AbsoluteSize = (options and options.room) or Vector2.new(800, 600)
		w.advance(1 / 300, 2)
		w.advance(0.5, 10)
		return w
	end

	verifyHarness:suite("settle: the sheet", function()
		verifyHarness:case("a programmatic detent change eases in and out instead of moving at constant speed", {
			id = "native_settle::settle: the sheet::a programmatic detent change eases in and out instead of moving at constant speed",
			run = function()
				local w = sheet()
				local panel = w.find("SheetPanel")
				local start = panel.Size.Y.Offset
				w.detent:set("large")
				local heights = { start }
				for _ = 1, 30 do
					w.advance(FRAME)
					table.insert(heights, panel.Size.Y.Offset)
				end
				local first, middle = heights[2] - heights[1], heights[8] - heights[7]
				Verify.expect(first < middle):toBe(true)
				Verify.expect(heights[#heights]):toBe(heights[#heights - 1])
				w.stop()
			end,
		})

		verifyHarness:case("a side pull released short springs back carrying the release velocity", {
			id = "native_settle::settle: the sheet::a side pull released short springs back carrying the release velocity",
			run = function()
				local w = sheet({ placement = "side" :: "side" }, { room = Vector2.new(1200, 800) })
				local panel = w.find("SheetPanel")
				local drag = w.find("UIDragDetector")
				drag.DragStart.fire(w.Vector2.new(100, 300))
				w.tick(0.05)
				drag.DragContinue.fire(w.Vector2.new(110, 300))
				w.tick(0.05)
				drag.DragContinue.fire(w.Vector2.new(140, 300))
				Verify.expect(panel.Position.X.Offset):toBe(40)
				drag.DragEnd.fire()
				w.advance(FRAME)
				Verify.expect(panel.Position.X.Offset > 40):toBe(true)
				w.advance(1, 60)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a dismissal-disabled side sheet grabbed mid spring-back continues from where it is drawn", {
			id = "native_settle::settle: the sheet::a dismissal-disabled side sheet grabbed mid spring-back continues from where it is drawn",
			run = function()
				local w = sheet(
					{ placement = "side" :: "side", interactiveDismissDisabled = true },
					{ room = Vector2.new(1200, 800) }
				)
				local panel = w.find("SheetPanel")
				local drag = w.find("UIDragDetector")
				drag.DragStart.fire(w.Vector2.new(100, 300))
				w.tick(0.05)
				drag.DragContinue.fire(w.Vector2.new(300, 300))
				Verify.expect(panel.Position.X.Offset):toBe(40)
				w.tick(0.3)
				drag.DragEnd.fire()
				w.advance(FRAME)
				w.advance(FRAME)
				local drawn = panel.Position.X.Offset
				Verify.expect(drawn > 0 and drawn < 40):toBe(true)
				drag.DragStart.fire(w.Vector2.new(500, 300))
				drag.DragContinue.fire(w.Vector2.new(505, 300))
				Verify.expect(math.abs(panel.Position.X.Offset - drawn) <= 2):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a room that shrinks below the sheet minimum mid-settle keeps painting", {
			id = "native_settle::settle: the sheet::a room that shrinks below the sheet minimum mid-settle keeps painting",
			run = function()
				local w = sheet()
				local panel = w.find("SheetPanel")
				w.detent:set("large")
				w.advance(FRAME)
				w.advance(FRAME)
				w.find("Modal").AbsoluteSize = Vector2.new(800, 150)
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect(panel.Size.Y.Offset <= 150):toBe(true)
				w.advance(1, 30)
				w.stop()
			end,
		})

		verifyHarness:case("reduced motion lands a detent change at once", {
			id = "native_settle::settle: the sheet::reduced motion lands a detent change at once",
			run = function()
				local w = sheet(nil, { motionLevel = "none" })
				local panel = w.find("SheetPanel")
				w.detent:set("large")
				local goal = panel.Size.Y.Offset
				w.advance(FRAME)
				Verify.expect(panel.Size.Y.Offset):toBe(goal)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("settle: row actions", function()
		verifyHarness:case("a fast swipe that opens the tray keeps moving on the first frame after release", {
			id = "native_settle::settle: row actions::a fast swipe that opens the tray keeps moving on the first frame after release",
			run = function()
				local w = overlay.new(function(UI: FacetControls)
					return UI.RowActions({
						fullSwipe = false,
						content = UI.Button "Body" { label = "Row" } :: GuiObject,
						trailing = { { id = "Archive", label = "Archive" } :: FixtureCollectionTypes.RowAction },
					})
				end)
				local content = w.find("Content")
				local node = content.Parent
				node.AbsoluteSize = Vector2.new(320, 44)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart.fire(Vector2.new(300, 20))
				w.advance(FRAME)
				detector.DragContinue.fire(Vector2.new(280, 20))
				w.advance(FRAME)
				detector.DragContinue.fire(Vector2.new(250, 20))
				local released = content.Position.X.Offset
				detector.DragEnd.fire()
				w.advance(FRAME)
				Verify.expect(content.Position.X.Offset < released):toBe(true)
				w.advance(1, 60)
				Verify.expect(content.Position.X.Offset < -40):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a grab mid-settle starts the finger from the painted offset", {
			id = "native_settle::settle: row actions::a grab mid-settle starts the finger from the painted offset",
			run = function()
				local w = overlay.new(function(UI: FacetControls)
					return UI.RowActions({
						fullSwipe = false,
						content = UI.Button "Body" { label = "Row" } :: GuiObject,
						trailing = { { id = "Archive", label = "Archive" } :: FixtureCollectionTypes.RowAction },
					})
				end)
				local content = w.find("Content")
				local node = content.Parent
				node.AbsoluteSize = Vector2.new(320, 44)
				local detector = node:FindFirstChild("SwipeGrip", true):FindFirstChildWhichIsA("UIDragDetector")
				detector.DragStart.fire(Vector2.new(300, 20))
				w.advance(FRAME)
				detector.DragContinue.fire(Vector2.new(240, 20))
				w.advance(0.2, 2)
				detector.DragEnd.fire()
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				local painted = content.Position.X.Offset
				Verify.expect(painted < -60 and painted > -88):toBe(true)
				detector.DragStart.fire(Vector2.new(200, 20))
				detector.DragContinue.fire(Vector2.new(209, 20))
				Verify.expect(math.abs(content.Position.X.Offset - (painted + 9)) <= 1):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("settle: the primitive", function()
		local Roblox = require("../src/vendor/compose/roblox")
		local context = require("../src/ui/context")
		local settle = require("../src/ui/settle")
		local engineLib = require("./lib/native_engine")
		local function run(build: (any) -> ()): (any, () -> ())
			local engine = engineLib.new()
			local runtime: ComposeRuntime = Roblox.createRuntime(engine)
			local stop = runtime.mount(function()
				build(context(Compose, runtime, { types = engine.types, services = {}, motionLevel = "normal" }))
				return ((runtime.constructors.Folder :: unknown) :: FolderConstructor)({})
			end, engine.new("Folder"))
			return engine, function()
				stop()
				runtime:dispose()
			end
		end

		verifyHarness:case("a release velocity past motion.fling.maxSpeed is clamped before it seeds the spring", {
			id = "native_settle::settle: the primitive::a release velocity past motion.fling.maxSpeed is clamped before it seeds the spring",
			run = function()
				local s: any
				local engine, stop = run(function(ctx)
					s = settle(ctx, function(): number
						return 0
					end, { period = 0.2, damping = 1 })
				end)
				Verify.expect((s.launch(0, 100000))):toBe(true)
				local farthest = 0
				for _ = 1, 120 do
					engine.heartbeat.fire(FRAME)
					farthest = math.max(farthest, s.value:peek() or 0)
				end
				Verify.expect(farthest > 10 and farthest < 60):toBe(true)
				Verify.expect((s.value:peek())):toBeNil()
				stop()
			end,
		})

		verifyHarness:case("a spring that goes non-finite halts at its target instead of running every frame", {
			id = "native_settle::settle: the primitive::a spring that goes non-finite halts at its target instead of running every frame",
			run = function()
				local s: any
				local engine, stop = run(function(ctx)
					s = settle(ctx, function(): number
						return 10
					end, { period = 0, damping = 1 })
				end)
				s.launch(0, 0)
				engine.heartbeat.fire(FRAME)
				engine.heartbeat.fire(FRAME)
				Verify.expect((s.value:peek())):toBeNil()
				Verify.expect((engine.heartbeat.count())):toBe(0)
				stop()
			end,
		})

		verifyHarness:case("a caller's own reduced reader decides, and launch reports that nothing started", {
			id = "native_settle::settle: the primitive::a caller's own reduced reader decides, and launch reports that nothing started",
			run = function()
				local s: any
				local _, stop = run(function(ctx)
					s = settle(ctx, function(): number
						return 0
					end, { period = 0.2, damping = 1 }, function(): boolean
						return true
					end)
				end)
				Verify.expect((s.launch(10, 0))):toBe(false)
				Verify.expect((s.value:peek())):toBeNil()
				stop()
			end,
		})
	end)

	verifyHarness:suite("settle: the sheet follows the finger", function()
		local function scrimAlpha(w: any): number
			return w.find("ScrimFade").Transparency.Keypoints[1].Value
		end

		verifyHarness:case("the scrim lightens with the drag toward dismissal", {
			id = "native_settle::settle: the sheet follows the finger::the scrim lightens with the drag toward dismissal",
			run = function()
				local w = sheet()
				local rest = scrimAlpha(w)
				local drag = w.find("UIDragDetector")
				drag.DragStart.fire(w.Vector2.new(0, 0))
				w.tick(0.2)
				drag.DragContinue.fire(w.Vector2.new(0, 150))
				local half = scrimAlpha(w)
				Verify.expect(half > rest):toBe(true)
				drag.DragContinue.fire(w.Vector2.new(0, 250))
				Verify.expect(scrimAlpha(w) > half):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the scrim stays whole while the sheet grows to a larger detent", {
			id = "native_settle::settle: the sheet follows the finger::the scrim stays whole while the sheet grows to a larger detent",
			run = function()
				local w = sheet()
				local rest = scrimAlpha(w)
				w.detent:set("large")
				for _ = 1, 40 do
					w.advance(FRAME)
					Verify.expect((scrimAlpha(w))):toBe(rest)
				end
				w.stop()
			end,
		})

		verifyHarness:case("a dismissal-disabled sheet keeps its scrim while dragged", {
			id = "native_settle::settle: the sheet follows the finger::a dismissal-disabled sheet keeps its scrim while dragged",
			run = function()
				local w = sheet({ interactiveDismissDisabled = true })
				local rest = scrimAlpha(w)
				local drag = w.find("UIDragDetector")
				drag.DragStart.fire(w.Vector2.new(0, 0))
				w.tick(0.2)
				drag.DragContinue.fire(w.Vector2.new(0, 150))
				Verify.expect((scrimAlpha(w))):toBe(rest)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a fast flick settles past its detent once and comes back; a slow release never overshoots",
			{
				id = "native_settle::settle: the sheet follows the finger::a fast flick settles past its detent once and comes back; a slow release never overshoots",
				run = function()
					for _, fast in { true, false } do
						local w = sheet()
						local panel = w.find("SheetPanel")
						local drag = w.find("UIDragDetector")
						drag.DragStart.fire(w.Vector2.new(0, 0))
						if fast then
							w.tick(0.01)
							drag.DragContinue.fire(w.Vector2.new(0, -20))
							w.tick(0.01)
							drag.DragContinue.fire(w.Vector2.new(0, -40))
						else
							w.tick(0.1)
							drag.DragContinue.fire(w.Vector2.new(0, -20))
							w.tick(0.1)
							drag.DragContinue.fire(w.Vector2.new(0, -40))
						end
						local released = panel.Size.Y.Offset
						drag.DragEnd.fire()
						local heights = {}
						for _ = 1, 90 do
							w.advance(FRAME)
							table.insert(heights, panel.Size.Y.Offset)
						end
						local goal = heights[#heights]
						local toward = if goal > released then 1 else -1
						local beyond = 0
						for _, height in heights do
							beyond = math.max(beyond, (height - goal) * toward)
						end
						if fast then
							Verify.expect(toward):toBe(1)
							Verify.expect(beyond > 0):toBe(true)
							Verify.expect(beyond < goal * 0.02 + 1):toBe(true)
						else
							Verify.expect(beyond):toBe(0)
						end
						w.stop()
					end
				end,
			}
		)
	end)
end
