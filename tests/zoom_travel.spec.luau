--!strict
local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local Shared = require("../src/ui/types")
local ZoomTypes = require("../src/ui/zoom_travel_types")
local engineLib = require("./lib/native_engine")
local geometry = require("../src/ui/zoom_geometry")
local travelGeometry = require("../src/ui/travel_geometry")

return function(harness: Verify.Harness)
	harness:suite("zoom and travel", function()
		harness:case("holds a focus point on every scale sample and clamps each edge", function(t)
			for index = 0, 120 do
				local scale = 0.5 + index / 120 * 2
				local offset, inset = geometry.axis(400, 1000, scale, 500, 200)
				t:expect(math.abs(500 * scale + inset - offset - 200) < 0.000001):toBe(true)
				t:expect(offset >= 0 and offset <= 1000 * scale - 400):toBe(true)
			end
			local low = geometry.axis(400, 1000, 2, -100, 200)
			local high = geometry.axis(400, 1000, 2, 2000, 200)
			t:expect(low):toBe(0)
			t:expect(high):toBe(1600)
			local offset, inset = geometry.axis(400, 100, 1, 50, 200)
			t:expect(offset):toBe(0)
			t:expect(inset):toBe(150)
			t:expect(geometry.point(1, offset, inset, 200)):toBe(50)
			t:expect(geometry.rectangle(400, 300, { x = 10, y = 10, w = 100, h = 100 })):toBe(3)
		end)

		harness:case("samples straight and arc paths at both endpoints and in flight", function(t)
			local last = -math.huge
			for index = 0, 60 do
				local progress = index / 60
				local x = travelGeometry.point(20, 420, progress)
				t:expect(x >= last):toBe(true)
				t:expect(travelGeometry.arc(progress, 48) <= 0):toBe(true)
				last = x
			end
			t:expect(travelGeometry.arc(0, 48)):toBe(0)
			t:expect(travelGeometry.arc(1, 48)):toBe(0)
			t:expect(travelGeometry.arc(0.5, 48)):toBe(-48)
		end)

		harness:case("applies pinch and pointer pan in input callbacks and freezes child drag", function(t)
			local engine = engineLib.new({ lenientProperties = true })
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: Shared.Host
			local input = engine.new("UserInputService")
			input.TouchPinch = VerifyRoblox.testEnvironment().newSignal()
			local gui = engine.new("GuiService")
			local UI = Facet.controls(runtime, { types = engine.types, userInputService = input, guiService = gui })
			local zoom: Facet.Cell<number>
			local view: ScrollingFrame
			local tile: TextButton
			local controls: Facet.ZoomControls = {}
			local enabled: Facet.Cell<boolean>
			local stop = runtime.mount(function()
				zoom = C.cell(1)
				enabled = C.cell(true)
				view = UI.ZoomView {
					contentSize = engine.types.Vector2.new(1000, 1000),
					zoom = zoom,
					controls = controls,
					enabled = enabled,
					content = function(): GuiObject
						tile = Host.TextButton { Name = "Tile", Size = engine.types.UDim2.fromOffset(60, 60) }
						return tile
					end,
				}
				return Host.ScreenGui { view }
			end, engine.new("Folder"))
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			view.AbsoluteWindowSize = engine.types.Vector2.new(400, 400)
			local resets = 0
			local nativeMethods = (view :: unknown) :: { ResetScrollVelocity: () -> () }
			nativeMethods.ResetScrollVelocity = function()
				resets += 1
			end
			engine.heartbeat:Fire(0.016)
			local count = #engine.made
			local canvas = view:FindFirstChild("ZoomContent") :: Frame
			local scale = canvas:FindFirstChild("ZoomScale") :: UIScale
			assert(controls.zoomTo)({ x = 400, y = 400, w = 200, h = 200 })
			local previous = scale.Scale
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
				t:expect(scale.Scale >= previous):toBe(true)
				t:expect(math.abs(500 * scale.Scale - view.CanvasPosition.X - 200) < 0.001):toBe(true)
				previous = scale.Scale
			end
			t:expect(scale.Scale):toBe(2)
			t:expect(#engine.made):toBe(count)
			local V2, E = engine.types.Vector2, engine.types.Enum
			input.TouchPinch:Fire({ V2.new(150, 150), V2.new(250, 250) }, 1, 0, E.UserInputState.Begin, false)
			input.TouchPinch:Fire({ V2.new(150, 150), V2.new(250, 250) }, 1.25, 0, E.UserInputState.Change, false)
			t:expect(scale.Scale):toBe(2.5)
			engine.heartbeat:Fire(0.016)
			t:expect(scale.Scale):toBe(2.5)
			t:expect(view.ScrollingEnabled):toBe(false)
			t:expect(math.abs(500 * scale.Scale - view.CanvasPosition.X - 200) < 0.001):toBe(true)
			input.TouchPinch:Fire({}, 1.25, 0, E.UserInputState.End, false)
			t:expect(view.ScrollingEnabled):toBe(true)
			assert(controls.zoomTo)({ x = 400, y = 400, w = 200, h = 200 })
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
			end
			local pointer = engine.new("InputObject")
			pointer.UserInputType = engine.types.Enum.UserInputType.Touch
			input.InputBegan:Fire(pointer, false)
			local owner = C.createRootOwner(function() end, runtime.reactor)
			local arbiter
			C.withOwner(owner.owner, function()
				arbiter = UI.gestureArbiter(tile)
			end)
			t:defer(owner.dispose)
			arbiter.begin(pointer, engine.types.Vector2.new(10, 10), { pickup = "immediate" })
			zoom:set(3)
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
				t:expect(scale.Scale):toBe(2)
			end
			arbiter.move(pointer, engine.types.Vector2.new(100, 100))
			tile.Parent = nil
			for _ = 1, 10 do
				engine.heartbeat:Fire(0.016)
				t:expect(scale.Scale):toBe(2)
			end
			tile.Parent = canvas
			arbiter.finish(pointer)
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
			end
			t:expect(scale.Scale):toBe(3)
			t:expect(resets):toBe(2)
			t:expect(#engine.made):toBe(count + 1)
			gui.SelectedObject = view
			for _, node in engine.made do
				if node.Name == "ZoomOut" and node:IsA("InputAction") then
					node.Pressed:Fire()
				end
			end
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
			end
			t:expect(math.abs(scale.Scale - 2.4) < 0.001):toBe(true)
			local detector = view:FindFirstChild("ZoomPanDetector")
			assert(detector)
			local before = view.CanvasPosition
			local native = (
				detector :: unknown
			) :: { DragStart: engineLib.Signal<Vector2>, DragContinue: engineLib.Signal<Vector2> }
			native.DragStart:Fire(V2.new(200, 200))
			native.DragContinue:Fire(V2.new(250, 200))
			t:expect(math.abs(view.CanvasPosition.X - before.X + 50) < 0.001):toBe(true)
			engine.heartbeat:Fire(0.016)
			t:expect(math.abs(view.CanvasPosition.X - before.X + 50) < 0.001):toBe(true)
			enabled:set(false)
			t:expect(view.ScrollingEnabled):toBe(false)
			t:expect(assert(controls.fit)()):toBe(false)
		end)

		harness:case("permits one capture-time camera request and defers later zoom", function(t)
			local engine = engineLib.new({ lenientProperties = true })
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: Shared.Host
			local input = engine.new("UserInputService")
			input.TouchPinch = VerifyRoblox.testEnvironment().newSignal()
			local config = { types = engine.types, userInputService = input }
			local ctx = require("../src/ui/context")(C, runtime, config)
			local drag = require("../src/ui/drag_session")(ctx)
			local UI = ({} :: unknown) :: ZoomTypes.Controls
			require("../src/ui/zoom_view")(ctx, UI)
			local zoom: Facet.Cell<number>
			local view: ScrollingFrame
			local tile: TextButton
			local controls: Facet.ZoomControls = {}
			local stop = runtime.mount(function()
				zoom = C.cell(1)
				view = UI.ZoomView {
					zoom = zoom,
					controls = controls,
					contentSize = engine.types.Vector2.new(1000, 1000),
					content = function(): GuiObject
						tile = Host.TextButton { Size = engine.types.UDim2.fromOffset(60, 60) }
						drag.own(tile)
						return tile
					end,
				}
				return Host.ScreenGui { view }
			end, engine.new("Folder"))
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			view.AbsoluteWindowSize = engine.types.Vector2.new(400, 400)
			local methods = (view :: unknown) :: { ResetScrollVelocity: () -> () }
			methods.ResetScrollVelocity = function() end
			engine.heartbeat:Fire(0.016)
			local scale = view:FindFirstChild("ZoomScale", true) :: UIScale
			drag.begin(tile, {
				payload = "tile",
				onStart = function()
					t:expect(assert(controls.zoomTo)({ x = 400, y = 400, w = 200, h = 200 })):toBe(true)
					t:expect(assert(controls.fit)()):toBe(false)
				end,
			}, "pointer", nil, false, { position = engine.types.Vector2.new(20, 20), source = tile :: GuiObject })
			t:expect(assert(controls.fit)()):toBe(false)
			zoom:set(3)
			local previous = scale.Scale
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
				t:expect(scale.Scale >= previous and scale.Scale <= 2):toBe(true)
				t:expect(math.abs(500 * scale.Scale - view.CanvasPosition.X - 200) < 0.001):toBe(true)
				previous = scale.Scale
			end
			t:expect(scale.Scale):toBe(2)
			local before = view.CanvasPosition
			local detector = (view:FindFirstChild("ZoomPanDetector") :: unknown) :: {
				DragStart: engineLib.Signal<Vector2>,
				DragContinue: engineLib.Signal<Vector2>,
			}
			detector.DragStart:Fire(engine.types.Vector2.new(200, 200))
			detector.DragContinue:Fire(engine.types.Vector2.new(250, 200))
			t:expect(view.CanvasPosition):toBe(before)
			drag.finish(true)
			for _ = 1, 20 do
				engine.heartbeat:Fire(0.016)
			end
			t:expect(scale.Scale):toBe(3)
		end)

		harness:case("measures the render sample before and after the Compose clock step", function(t)
			local engine = engineLib.new({ lenientProperties = true })
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: Shared.Host
			local run = engine.new("RunService")
			run.PreRender = VerifyRoblox.testEnvironment().newSignal()
			local UI = Facet.controls(runtime, { types = engine.types, services = { RunService = run } })
			local zoom: Facet.Cell<number>
			local view: ScrollingFrame
			local stop = runtime.mount(function()
				zoom = C.cell(1)
				view = UI.ZoomView {
					zoom = zoom,
					contentSize = engine.types.Vector2.new(1000, 1000),
					content = function(): GuiObject
						return Host.Frame {}
					end,
				}
				return Host.ScreenGui { view }
			end, engine.new("Folder"))
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			view.AbsoluteWindowSize = engine.types.Vector2.new(400, 400)
			run.PreRender:Fire(0)
			local scale = view:FindFirstChild("ZoomScale", true) :: UIScale
			zoom:set(2)
			run.PreRender:Fire(1 / 60)
			t:expect(scale.Scale):toBe(1)
			engine.heartbeat:Fire(1 / 60)
			run.PreRender:Fire(1 / 60)
			t:expect(scale.Scale > 1 and scale.Scale < 2):toBe(true)
			local previous = scale.Scale
			zoom:set(0.8)
			run.PreRender:Fire(0)
			t:expect(scale.Scale):toBe(previous)
			for _ = 1, 20 do
				engine.heartbeat:Fire(1 / 60)
				run.PreRender:Fire(1 / 60)
				t:expect(scale.Scale <= previous):toBe(true)
				previous = scale.Scale
			end
			t:expect(scale.Scale):toBe(0.8)
		end)

		harness:case("retargets travel from its sampled position and hands off the same carrier", function(t)
			local engine = engineLib.new()
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: Shared.Host
			local overlay = engine.new("Frame")
			local screen = engine.new("ScreenGui")
			screen.Parent = engine.new("Folder")
			overlay.Parent = screen
			overlay.AbsolutePosition = engine.types.Vector2.zero
			overlay.AbsoluteSize = engine.types.Vector2.new(600, 400)
			local first, second = engine.new("Frame"), engine.new("Frame")
			first.Parent, second.Parent = overlay, overlay
			first.ClipsDescendants, second.ClipsDescendants = true, true
			first.AbsolutePosition, second.AbsolutePosition =
				engine.types.Vector2.new(20, 20), engine.types.Vector2.new(420, 220)
			first.AbsoluteSize, second.AbsoluteSize = engine.types.Vector2.new(60, 60), engine.types.Vector2.new(80, 80)
			local UI = Facet.controls(runtime, { types = engine.types, overlayParent = overlay })
			local destination: Facet.Cell<GuiObject>
			local reduced: Facet.Cell<Shared.MotionLevel>
			local content: Frame
			local wrapper: Frame
			local mounts = 0
			local landed = 0
			local stop = runtime.mount(function()
				destination = C.cell(first :: GuiObject)
				reduced = C.cell("normal" :: Shared.MotionLevel)
				local controls =
					Facet.controls(runtime, { types = engine.types, overlayParent = overlay, motionLevel = reduced })
				wrapper = Host.Frame {
					controls.Travel {
						destination = destination,
						path = "arc" :: "arc",
						onLanded = function(_target: GuiObject)
							landed += 1
						end,
						content = function(): GuiObject
							mounts += 1
							content = Host.Frame { Name = "Travelling", Size = engine.types.UDim2.fromScale(1, 1) }
							return content
						end,
					},
				}
				return wrapper
			end, overlay)
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			engine.heartbeat:Fire(0.016)
			local carrier = content
			t:expect(carrier.Parent == first):toBe(true)
			t:expect(landed):toBe(1)
			carrier.AbsolutePosition, carrier.AbsoluteSize = first.AbsolutePosition, first.AbsoluteSize
			local count = #engine.made
			destination:set(second)
			local previous = carrier.Position.X.Offset
			for _ = 1, 6 do
				engine.heartbeat:Fire(0.016)
				t:expect(carrier.Parent == overlay):toBe(true)
				t:expect(carrier.Position.X.Offset >= previous):toBe(true)
				previous = carrier.Position.X.Offset
			end
			local current = carrier.Position
			destination:set(first)
			t:expect(carrier.Position):toBe(current)
			for _ = 1, 30 do
				engine.heartbeat:Fire(0.016)
			end
			t:expect(content == carrier):toBe(true)
			t:expect(carrier.Parent == first):toBe(true)
			t:expect(carrier.Visible):toBe(true)
			t:expect(landed):toBe(2)
			t:expect(#engine.made):toBe(count)
			reduced:set("limited")
			destination:set(second)
			t:expect(carrier.Parent == second):toBe(true)
			t:expect(landed):toBe(3)
			wrapper.Visible = false
			engine.heartbeat:Fire(0.016)
			wrapper.Visible = true
			engine.heartbeat:Fire(0.016)
			t:expect(mounts):toBe(1)
			t:expect(content == carrier):toBe(true)
			t:expect(carrier.Parent == second):toBe(true)
		end)
	end)
end
