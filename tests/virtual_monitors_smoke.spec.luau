--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Compose = require("../src/vendor/compose/core")
local Roblox = require("../src/vendor/compose/roblox")
local Facet = require("../src")
local engineModule = require("./lib/native_engine")
local modelModule = require("../examples/virtual_monitors/model")
local screens = require("../examples/virtual_monitors/screens")
local overlay = require("./lib/overlay_world")
local nativeDrag = require("./lib/native_drag")
local spatial = require("../examples/virtual_monitors/spatial")

local function hasPaintedRow(feed: ScrollingFrame): boolean
	local layer = assert(feed:FindFirstChild("Items"))
	for _, slot in layer:GetChildren() do
		if slot:IsA("Frame") then
			local offset = slot.Position.Y.Offset - feed.CanvasPosition.Y
			if offset < feed.AbsoluteWindowSize.Y and offset + slot.Size.Y.Offset > 0 then
				return true
			end
		end
	end
	return false
end

return function(harness: Verify.Harness)
	harness:case("a ScrollView sinks input before a monitor ClickDetector", {
		id = "virtual_monitors_smoke::a ScrollView sinks input before a monitor ClickDetector",
		run = function()
			local world = overlay.new(function(UI)
				return UI.ScrollView { Name = "MonitorViewport" }
			end)
			Verify.expect(overlay.find(world.screen, "MonitorViewport").Active):toBe(true)
			world.stop()
		end,
	})
	harness:case("sorting at the top keeps a painted row in the native viewport", {
		id = "virtual_monitors_smoke::sorting at the top keeps a painted row in the native viewport",
		run = function()
			local rows = Compose.cell({ "a", "b", "c", "d", "e", "f", "g", "h" })
			local world = overlay.new(function(UI, Host)
				return UI.VirtualList {
					Name = "Feed",
					from = rows,
					key = function(value)
						return value
					end,
					itemSize = 100,
					CanvasPosition = function()
						return require("@lune/roblox").Vector2.zero
					end,
					render = function(current)
						return Host.Frame { Name = current:peek() }
					end,
				}
			end)
			local feed = overlay.find(world.screen, "Feed")
			feed.AbsoluteWindowSize = world.Vector2.new(389, 100)
			world.advance(0.1, 6)
			rows:set({ "h", "g", "f", "e", "d", "c", "b", "a" })
			world.advance(0.1, 6)
			local visible = false
			for _, slot in overlay.find(feed, "Items"):GetChildren() do
				if slot:IsA("Frame") then
					local offset = slot.Position.Y.Offset - feed.CanvasPosition.Y
					visible = visible or (offset < 100 and offset + slot.Size.Y.Offset > 0)
				end
			end
			Verify.expect(visible):toBe(true)
			world.stop()
		end,
	})
	harness:case("a compact Spatial monitor keeps its mode toolbar when scrolled", {
		id = "virtual_monitors_smoke::a compact Spatial monitor keeps its mode toolbar when scrolled",
		run = function()
			local engine = engineModule.new()
			local runtime = Roblox.createRuntime(engine)
			local target = engine.new("ScreenGui")
			local owner = Compose.createRootOwner(function()
				local model = modelModule.new(Compose)
				Compose.cleanup(model.dispose)
				local views = screens.create(
					Facet,
					runtime,
					{ model = model, types = engine.types, spatial = true, motionLevel = "none" }
				)
				local stop, mounted = runtime.mount(views.Discover, target)
				local node = mounted :: Frame
				node.AbsoluteSize = engine.types.Vector2.new(389, 271)
				model.discoveryScroll:set(200)
				Verify.expect((node:FindFirstChild("Header", true) :: GuiObject).Visible):toBe(true)
				stop()
			end, runtime.reactor)
			owner.dispose()
			runtime:dispose()
		end,
	})
	harness:case("a new collection scroll request overrides sorting anchor retention", {
		id = "virtual_monitors_smoke::a new collection scroll request overrides sorting anchor retention",
		run = function()
			local rows = Compose.cell({ "a", "b", "c", "d", "e", "f" })
			local request = Compose.cell(0)
			local world = overlay.new(function(UI, Host)
				return UI.VirtualList {
					Name = "Feed",
					from = rows,
					itemSize = 100,
					CanvasPosition = function(use)
						use(request)
						return require("@lune/roblox").Vector2.zero
					end,
					render = function()
						return Host.Frame {}
					end,
				}
			end)
			local feed = overlay.find(world.screen, "Feed")
			feed.AbsoluteWindowSize = world.Vector2.new(389, 200)
			world.advance(0.1, 6)
			feed.CanvasPosition = world.Vector2.new(0, 200)
			rows:set({ "f", "e", "d", "c", "b", "a" })
			request:set(1)
			world.advance(0.1, 6)
			Verify.expect(feed.CanvasPosition.Y):toBe(0)
			world.stop()
		end,
	})
	harness:case("compact monitor canvases keep text at the viewport scale", {
		id = "virtual_monitors_smoke::compact monitor canvases keep text at the viewport scale",
		run = function()
			local width, height = spatial.canvasSize(389)
			Verify.expect(width):toBe(389)
			Verify.expect(math.abs(height / width - 640 / 920) < 0.002):toBe(true)
			local wide = spatial.canvasSize(1914)
			Verify.expect(wide):toBe(920)
			Verify.expect(spatial.contentHeight(389, 762)):toBe(762)
			Verify.expect(spatial.contentHeight(1914, 759)):toBe(640)
		end,
	})
	harness:case("an attached count badge does not start above its host", {
		id = "virtual_monitors_smoke::an attached count badge does not start above its host",
		run = function()
			local world = overlay.new(function(UI)
				return UI.badged(UI.Button { Name = "Saved", label = "Saved" }, 1)
			end)
			local seal = overlay.find(world.screen, "CornerBadge")
			Verify.expect(seal.AnchorPoint.Y):toBe(0)
			Verify.expect(seal.Parent.Position.Y.Scale):toBe(0)
			world.stop()
		end,
	})
	harness:case("a stationary press on draggable card artwork activates its card once", {
		id = "virtual_monitors_smoke::a stationary press on draggable card artwork activates its card once",
		run = function()
			local activations = 0
			local world = overlay.new(function(UI, Host)
				return UI.Card {
					title = "Afterlight",
					onActivate = function()
						activations += 1
					end,
					artwork = function()
						local artwork = Host.Frame { Name = "Artwork" }
						UI.draggable(artwork, { payload = "1" })
						return artwork
					end,
				}
			end)
			local artwork = overlay.find(world.screen, "FacetDragDetector").Parent
			artwork.AbsolutePosition = world.Vector2.zero
			artwork.AbsoluteSize = world.Vector2.new(100, 100)
			nativeDrag.measure(artwork)
			local press = {
				UserInputType = world.Enum.UserInputType.MouseButton1,
				UserInputState = world.Enum.UserInputState.Begin,
				Position = world.engine.types.Vector3.new(50, 50, 0),
			}
			nativeDrag.press(artwork, press)
			press.UserInputState = world.Enum.UserInputState.End
			nativeDrag.finish(world.input, press)
			Verify.expect(activations):toBe(1)
			overlay.find(world.screen, "Body").Activated:Fire(press, 1)
			Verify.expect(activations):toBe(1)
			press.UserInputState = world.Enum.UserInputState.Begin
			world.input.InputBegan:Fire(press)
			press.UserInputState = world.Enum.UserInputState.End
			overlay.find(world.screen, "Body").Activated:Fire(press, 1)
			Verify.expect(activations):toBe(2)
			world.stop()
		end,
	})
	harness:case("Discover requests another batch at the displayed result end", {
		id = "virtual_monitors_smoke::Discover requests another batch at the displayed result end",
		run = function()
			local owner = Compose.createRootOwner(function()
				local model = modelModule.new(Compose)
				Compose.cleanup(model.dispose)
				model.catalog.seen(3, 36)
				model.catalog.step()
				Verify.expect(#model.catalog.items:peek()):toBe(36)
				model.catalog.seen(35, 36)
				model.catalog.step()
				Verify.expect(#model.catalog.items:peek()):toBe(72)
			end)
			owner.dispose()
		end,
	})
	harness:case("sorted Discover does not load while the top viewport is idle", {
		id = "virtual_monitors_smoke::sorted Discover does not load while the top viewport is idle",
		run = function()
			local engine = engineModule.new()
			local runtime = Roblox.createRuntime(engine)
			local target = engine.new("ScreenGui")
			local owner = Compose.createRootOwner(function()
				local model = modelModule.new(Compose)
				Compose.cleanup(model.dispose)
				model.mode:set("Screen")
				local views =
					screens.create(Facet, runtime, { model = model, types = engine.types, motionLevel = "none" })
				local stop, node = runtime.mount(views.Discover, target)
				local grid = (node :: Instance):FindFirstChild("Games", true) :: ScrollingFrame
				grid.AbsoluteWindowSize = engine.types.Vector2.new(389, 350)
				model.step(1 / 60, false)
				model.sort:set("rating")
				for _ = 1, 10 do
					model.step(1 / 60, false)
					engine.heartbeat:Fire(1 / 60)
				end
				local count = #model.catalog.items:peek()
				for _ = 1, 60 do
					model.step(1 / 60, false)
					engine.heartbeat:Fire(1 / 60)
					Verify.expect(#model.catalog.items:peek()):toBe(count)
				end
				grid.CanvasPosition = engine.types.Vector2.new(0, 500)
				model.sort:set("recommended")
				for _ = 1, 10 do
					model.step(1 / 60, false)
					engine.heartbeat:Fire(1 / 60)
					grid = (node :: Instance):FindFirstChild("Games", true) :: ScrollingFrame
					Verify.expect(grid.CanvasPosition.Y):toBe(0)
					Verify.expect(hasPaintedRow(grid)):toBe(true)
				end
				grid.CanvasPosition = engine.types.Vector2.new(0, 500)
				model.genre:set("Adventure")
				for _ = 1, 10 do
					model.step(1 / 60, false)
					engine.heartbeat:Fire(1 / 60)
				end
				grid = (node :: Instance):FindFirstChild("Games", true) :: ScrollingFrame
				Verify.expect(grid.CanvasPosition.Y):toBe(0)
				Verify.expect(hasPaintedRow(grid)):toBe(true)
				for _, query in { "Afterlight", "" } do
					grid.CanvasPosition = engine.types.Vector2.new(0, 500)
					model.query:set(query)
					for _ = 1, 10 do
						model.step(1 / 60, false)
						engine.heartbeat:Fire(1 / 60)
						Verify.expect(grid.CanvasPosition.Y):toBe(0)
						Verify.expect(hasPaintedRow(grid)):toBe(true)
					end
				end
				stop()
			end, runtime.reactor)
			owner.dispose()
			runtime:dispose()
		end,
	})
end
