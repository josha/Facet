--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local context = require("../src/ui/context")
local Environment = require("../src/ui/environment_types")
local registerDrag = require("../src/ui/drag")
local activation = require("../src/ui/activation")
local DragTypes = require("../src/ui/drag_types")
local sessionOf = require("../src/ui/drag_session")
local gestureOf = require("../src/ui/gesture_service")
local engineLib = require("./lib/native_engine")

return function(harness: Verify.Harness)
	local function fixture()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local playerGui, screen = engine.new("PlayerGui"), engine.new("ScreenGui")
		screen.Parent = playerGui
		local source, target = engine.new("TextButton"), engine.new("TextButton")
		source.Parent, target.Parent = screen, screen
		source.AbsolutePosition, source.AbsoluteSize =
			engine.types.Vector2.new(20, 50), engine.types.Vector2.new(80, 60)
		target.AbsolutePosition, target.AbsoluteSize =
			engine.types.Vector2.new(240, 160), engine.types.Vector2.new(60, 60)
		local hits = { target }
		playerGui.GetGuiObjectsAtPosition = function()
			return hits
		end
		local input = engine.new("UserInputService")
		local ctx = context(
			Facet.Compose,
			runtime,
			{ types = engine.types, userInputService = input, services = { TweenService = engine.new("TweenService") } }
		)
		local service = sessionOf(ctx)
		local owner = Facet.Compose.createRootOwner(function() end, runtime.reactor)
		Facet.Compose.withOwner(owner.owner, function()
			service.own(source)
		end)
		return {
			engine = engine,
			input = input,
			bind = function(spec: Facet.DraggableSpec)
				Facet.Compose.withOwner(owner.owner, function()
					local UI = ({} :: unknown) :: Environment.EnvironmentControls
					registerDrag(ctx, UI)
					UI.draggable(source, spec)
				end)
			end,
			arbiter = gestureOf(ctx),
			useMeasuredHits = function(nodes: { GuiObject })
				playerGui.GetGuiObjectsAtPosition = function(_playerGui: PlayerGui, x: number, y: number)
					local measured: { GuiObject } = {}
					for _, node in nodes do
						local at, size = node.AbsolutePosition, node.AbsoluteSize
						if x >= at.X and y >= at.Y and x < at.X + size.X and y < at.Y + size.Y then
							table.insert(measured, node)
						end
					end
					return measured
				end
			end,
			registerAt = function(node: GuiObject, spec: Facet.DropTargetSpec)
				Facet.Compose.withOwner(owner.owner, function()
					service.register(node, (spec :: unknown) :: DragTypes.TargetSpec)
				end)
			end,
			runtime = runtime,
			service = service,
			source = source,
			target = target,
			screen = screen,
			register = function(spec: Facet.DropTargetSpec)
				Facet.Compose.withOwner(owner.owner, function()
					service.register(target, (spec :: unknown) :: DragTypes.TargetSpec)
				end)
			end,
			begin = function(spec: Facet.DraggableSpec?)
				service.begin(
					source,
					(spec or { payload = "tile", returnTravel = true }) :: DragTypes.SourceSpec,
					"pointer",
					nil,
					nil,
					{ position = engine.types.Vector2.new(28, 95), source = source }
				)
			end,
			stop = function()
				service.finish(false)
				owner.dispose()
				runtime:dispose()
			end,
		}
	end
	harness:suite("container travel", function()
		harness:case("default return and accepted shrink sample the shared engine without native tweens", function()
			local w = fixture()
			w.begin({ payload = "tile" })
			w.service.update(w.engine.types.Vector2.new(300, 400))
			local ghost = assert(w.screen:FindFirstChild("DragGhost")) :: GuiObject
			w.service.finish(false)
			Verify.expect(w.service.state:peek()):toBeNil()
			local previous = ghost.Position
			for _ = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				Verify.expect(ghost.Position.X.Offset <= previous.X.Offset):toBe(true)
				Verify.expect(ghost.Position.Y.Offset <= previous.Y.Offset):toBe(true)
				previous = ghost.Position
			end
			Verify.expect(ghost.Position):toBe(w.engine.types.UDim2.fromOffset(28, 95))
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			local commits = 0
			w.register({
				onDrop = function()
					commits += 1
				end,
			})
			w.begin({ payload = "tile" })
			ghost = assert(w.screen:FindFirstChild("DragGhost")) :: GuiObject
			w.service.commit(w.target)
			Verify.expect(commits):toBe(1)
			local scale = assert(ghost:FindFirstChildWhichIsA("UIScale"))
			local previousScale = scale.Scale
			for _ = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				Verify.expect(scale.Scale >= 0 and scale.Scale <= previousScale):toBe(true)
				previousScale = scale.Scale
			end
			Verify.expect(scale.Scale):toBe(0)
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			w.stop()
		end)
		harness:case("capture scope and each frame refresh targets through a moving camera", function()
			local w = fixture()
			local V2 = w.engine.types.Vector2
			local second: GuiObject = w.engine.new("TextButton")
			second.Parent = w.screen
			second.AbsoluteSize = V2.new(60, 60)
			second.AbsolutePosition = V2.new(400, 160)
			local placed: Instance? = nil
			w.register({
				onDrop = function()
					placed = w.target
				end,
			})
			w.registerAt(second, {
				onDrop = function()
					placed = second
				end,
			})
			w.useMeasuredHits({ w.target, second })
			w.begin({
				payload = "tile",
				onStart = function()
					Verify.expect(w.arbiter.claimCamera(second)):toBe(false)
					Verify.expect(w.arbiter.claimCamera(w.source)):toBe(true)
				end,
			})
			w.service.update(V2.new(270, 180))
			for frame = 1, 60 do
				w.target.AbsolutePosition = V2.new(240 - frame, 160)
				second.AbsolutePosition = V2.new(380 - frame * 2, 160)
				w.engine.heartbeat:Fire(1 / 120)
				local expected = if frame < 30 then w.target elseif frame < 55 then nil else second
				Verify.expect(assert(w.service.state:peek()).target):toBe(expected)
				Verify.expect(w.arbiter.claimCamera(w.source)):toBe(false)
			end
			second.AbsolutePosition = V2.new(400, 160)
			w.target.AbsolutePosition = V2.new(240, 160)
			w.service.commit(nil)
			Verify.expect(placed):toBe(w.target)
			w.stop()
		end)
		harness:case("writes contact before every frame without a tween or layout settle", function()
			local w = fixture()
			w.register({ onDrop = function() end })
			w.begin()
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			for frame = 1, 120 do
				local point = w.engine.types.Vector2.new(30 + frame * 1.3, 100 + math.sin(frame) * 10)
				w.service.update(point)
				Verify.expect(math.abs(ghost.Position.X.Offset - point.X) <= 1):toBe(true)
				Verify.expect(math.abs(ghost.Position.Y.Offset - point.Y) <= 1):toBe(true)
				w.engine.heartbeat:Fire(1 / 60)
				Verify.expect(math.abs(ghost.Position.X.Offset - point.X) <= 1):toBe(true)
				Verify.expect(ghost.AnchorPoint):toEqual(w.engine.types.Vector2.new(0.1, 0.75))
			end
			w.stop()
		end)
		harness:case("travels continuously and commits only at arrival", function()
			local w = fixture()
			local commits = 0
			w.register({
				travel = true,
				onDrop = function()
					commits += 1
					return true
				end,
			})
			w.begin()
			w.service.update(w.engine.types.Vector2.new(200, 120))
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			Verify.expect(w.service.commit(w.target)):toBe(true)
			Verify.expect(commits):toBe(0)
			local previous = ghost.Position.X.Offset
			local moved = false
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				if w.service.state:peek() then
					Verify.expect(ghost.Position.X.Offset >= previous):toBe(true)
					Verify.expect(ghost.Position.X.Offset <= 246):toBe(true)
					moved = moved or ghost.Position.X.Offset > previous
					previous = ghost.Position.X.Offset
					Verify.expect(commits):toBe(0)
				end
			end
			Verify.expect(moved):toBe(true)
			Verify.expect(commits):toBe(1)
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			w.stop()
		end)
		harness:case("touch pickup locks all scroll ancestors and rejects late long press", function()
			for _, pickup in { "immediate", "longPress" } do
				local w = fixture()
				local outer, inner = w.engine.new("ScrollingFrame"), w.engine.new("ScrollingFrame")
				outer.Parent, inner.Parent, w.source.Parent = w.screen, outer, inner
				outer.ScrollingEnabled, inner.ScrollingEnabled = true, false
				w.bind({ payload = "tile", returnTravel = true, touchPickup = pickup :: "immediate" | "longPress" })
				local event = {
					Position = w.engine.types.Vector3.new(28, 95, 0),
					UserInputType = w.engine.types.Enum.UserInputType.Touch,
					UserInputState = w.engine.types.Enum.UserInputState.Begin,
				}
				w.source.InputBegan:Fire(event)
				event.Position = w.engine.types.Vector3.new(36, 95, 0)
				w.input.InputChanged:Fire(event)
				if pickup == "immediate" then
					Verify.expect(assert(w.service.state:peek()).source):toBe(w.source)
					Verify.expect(outer.ScrollingEnabled):toBe(false)
					Verify.expect(inner.ScrollingEnabled):toBe(false)
				else
					w.source.TouchLongPress:Fire(
						{ w.engine.types.Vector2.new(36, 95) },
						w.engine.types.Enum.UserInputState.Begin
					)
					Verify.expect(w.service.state:peek()):toBeNil()
					Verify.expect(outer.ScrollingEnabled):toBe(true)
				end
				w.stop()
				Verify.expect(outer.ScrollingEnabled):toBe(true)
				Verify.expect(inner.ScrollingEnabled):toBe(false)
			end
		end)
		harness:case("paint outside a bounded hit area cannot start a native mouse drag", function()
			local w = fixture()
			local hit = w.engine.new("Frame")
			hit.Parent = w.source
			hit.AbsolutePosition = w.engine.types.Vector2.new(20, 50)
			hit.AbsoluteSize = w.engine.types.Vector2.new(40, 60)
			w.bind({ payload = "tile", hitArea = hit })
			local at = w.engine.types.Vector2.new(60, 95)
			w.source.InputBegan:Fire({
				Position = w.engine.types.Vector3.new(at.X, at.Y, 0),
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = w.engine.types.Enum.UserInputState.Begin,
			})
			local detector = assert(w.source:FindFirstChildWhichIsA("UIDragDetector"))
			detector.DragStart:Fire(at)
			detector.DragContinue:Fire(at + w.engine.types.Vector2.new(30, 0))
			Verify.expect(w.service.state:peek()):toBeNil()
			w.stop()
		end)
		harness:case("a mouse tap calls the source press once without a drag", function()
			local w = fixture()
			local presses = 0
			local disconnect = activation.provide(w.source, function()
				presses += 1
			end)
			w.bind({ payload = "tile" })
			local at = w.engine.types.Vector2.new(28, 95)
			w.source.InputBegan:Fire({
				Position = w.engine.types.Vector3.new(at.X, at.Y, 0),
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = w.engine.types.Enum.UserInputState.Begin,
			})
			local detector = assert(w.source:FindFirstChildWhichIsA("UIDragDetector"))
			detector.DragStart:Fire(at)
			detector.DragEnd:Fire(at)
			Verify.expect(presses):toBe(1)
			Verify.expect(w.service.state:peek()):toBeNil()
			disconnect()
			w.stop()
		end)
		harness:case("a second source cannot replace the captured tile", function()
			local w = fixture()
			w.begin()
			local first = assert(w.service.state:peek())
			w.service.begin(w.target, { payload = "neighbour" }, "pointer", nil, nil)
			Verify.expect(assert(w.service.state:peek()).source):toBe(first.source)
			Verify.expect(assert(w.service.state:peek()).payload):toBe("tile")
			w.stop()
		end)
		harness:case("cancel returns along a sampled path and holds the recess until arrival", function()
			local w = fixture()
			w.begin()
			w.service.update(w.engine.types.Vector2.new(200, 120))
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			w.service.finish(false, "Cancelled")
			Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBe(true)
			local previous = ghost.Position.X.Offset
			local moved = false
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				if w.screen:FindFirstChild("DragGhost") then
					Verify.expect(ghost.Position.X.Offset <= previous):toBe(true)
					Verify.expect(ghost.Position.X.Offset >= 28):toBe(true)
					moved = moved or ghost.Position.X.Offset < previous
					previous = ghost.Position.X.Offset
					Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBe(true)
				end
			end
			Verify.expect(moved):toBe(true)
			Verify.expect(w.screen:FindFirstChild("DragGhost")):toBeNil()
			Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBeNil()
			w.stop()
		end)
		harness:case("scaled screen coordinates remain exact while a scroll parent moves", function()
			local w = fixture()
			local scale = w.engine.new("UIScale")
			scale.Scale, scale.Parent = 0.75, w.screen
			w.screen.AbsolutePosition = w.engine.types.Vector2.new(4, 18)
			local scroll = w.engine.new("ScrollingFrame")
			scroll.Parent, w.source.Parent = w.screen, scroll
			w.begin()
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			for frame = 1, 120 do
				local point = w.engine.types.Vector2.new(30 + frame, 95 + frame * 0.5)
				scroll.CanvasPosition = w.engine.types.Vector2.new(frame, frame * 2)
				w.service.update(point)
				w.engine.heartbeat:Fire(1 / 60)
				local contact = w.screen.AbsolutePosition
					+ w.engine.types.Vector2.new(ghost.Position.X.Offset, ghost.Position.Y.Offset) * 0.75
				Verify.expect((contact - point).Magnitude <= 1):toBe(true)
			end
			w.stop()
		end)
		harness:case("landing removes source zoom from the whole preview on every sample", function()
			local w = fixture()
			local zoom = w.engine.new("Frame")
			zoom.Parent, w.source.Parent = w.screen, zoom
			local sourceScale = w.engine.new("UIScale")
			sourceScale.Scale, sourceScale.Parent = 3, zoom
			w.source.AbsoluteSize = w.engine.types.Vector2.new(240, 180)
			local commits = 0
			w.register({
				travel = true,
				onDrop = function()
					commits += 1
				end,
			})
			w.begin()
			w.service.update(w.engine.types.Vector2.new(200, 120))
			local ghost = assert(w.screen:FindFirstChild("DragGhost"))
			local scale = assert(ghost:FindFirstChildWhichIsA("UIScale"))
			Verify.expect(scale.Scale):toBe(3)
			w.service.commit(w.target)
			local previous = scale.Scale
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 120)
				if w.service.state:peek() then
					Verify.expect(scale.Scale <= previous and scale.Scale >= 1):toBe(true)
					Verify.expect(ghost.Size.X.Offset * scale.Scale >= 59):toBe(true)
					Verify.expect(ghost.Size.X.Offset * scale.Scale <= 240):toBe(true)
					Verify.expect(ghost.Size.Y.Offset * scale.Scale >= 59):toBe(true)
					Verify.expect(ghost.Size.Y.Offset * scale.Scale <= 180):toBe(true)
					previous = scale.Scale
				end
			end
			Verify.expect(scale.Scale):toBe(1)
			Verify.expect(commits):toBe(1)
			w.stop()
		end)
		harness:case("cancellation during travel prevents a model commit", function()
			local w = fixture()
			local commits = 0
			w.register({
				travel = true,
				onDrop = function()
					commits += 1
				end,
			})
			w.begin()
			w.service.commit(w.target)
			w.engine.heartbeat:Fire(1 / 60)
			w.service.finish(false, "Cancelled")
			for frame = 1, 60 do
				w.engine.heartbeat:Fire(1 / 60)
			end
			Verify.expect(commits):toBe(0)
			Verify.expect(w.service.state:peek()):toBeNil()
			w.stop()
		end)
	end)
end
