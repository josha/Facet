--!strict
local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local Shared = require("../src/ui/types")
local ZoomTypes = require("../src/ui/zoom_travel_types")
local engineLib = require("./lib/native_engine")
local geometry = require("../src/ui/zoom_geometry")
local travelGeometry = require("../src/ui/travel_geometry")

local function inputWorld()
	local engine = engineLib.new({ lenientProperties = true })
	local C = Facet.Compose
	local runtime = Facet.Roblox.createRuntime(engine)
	local Host = (runtime.constructors :: unknown) :: Shared.Host
	local input, gui = engine.new("UserInputService"), engine.new("GuiService")
	local V2, E = engine.types.Vector2, engine.types.Enum
	local mouse, control = V2.new(220, 236), false
	gui.GetGuiInset = function(): (Vector2, Vector2)
		return V2.new(0, 56), V2.zero
	end
	input.GetMouseLocation = function(): Vector2
		return mouse
	end
	input.IsKeyDown = function(_service: UserInputService, key: Enum.KeyCode): boolean
		return control and (key == E.KeyCode.LeftControl or key == E.KeyCode.RightControl)
	end
	local UI = Facet.controls(runtime, { types = engine.types, userInputService = input, guiService = gui })
	local view: ScrollingFrame
	local outer: ScrollingFrame
	local zoom = C.cell(2)
	local enabled = C.cell(true)
	local player = engine.new("PlayerGui")
	local stop = runtime.mount(function()
		view = UI.ZoomView {
			enabled = enabled,
			zoom = zoom,
			contentSize = V2.new(1000, 1000),
			content = function(): GuiObject
				return Host.Frame { Name = "Board" }
			end,
		}
		outer = Host.ScrollingFrame { view :: unknown }
		return Host.ScreenGui { outer :: unknown }
	end, player)
	player.GetGuiObjectsAtPosition = function()
		return { view:FindFirstChild("ZoomContent"), view, outer }
	end
	outer.AbsolutePosition, outer.AbsoluteSize = V2.zero, V2.new(600, 600)
	view.AbsolutePosition = V2.new(20, 30)
	view.AbsoluteWindowSize = V2.new(400, 400)
	view.ResetScrollVelocity = function() end
	outer.ResetScrollVelocity = function() end
	engine.heartbeat:Fire(0.016)
	local scale = view:FindFirstChild("ZoomScale", true) :: UIScale
	local function event(kind: Enum.UserInputType, point: Vector2, state: Enum.UserInputState): InputObject
		local value = engine.new("InputObject")
		value.UserInputType, value.UserInputState = kind, state
		value.Position = engine.types.Vector3.new(point.X, point.Y, 0)
		return value
	end
	return {
		player = player,
		engine = engine,
		input = input,
		gui = gui,
		view = view,
		outer = outer,
		enabled = enabled,
		zoom = zoom,
		scale = scale,
		event = event,
		setMouse = function(point: Vector2)
			mouse = point
		end,
		setControl = function(value: boolean)
			control = value
		end,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

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

		harness:case("pans from separate native mouse movement objects before the next frame", function(t)
			local w = inputWorld()
			t:defer(w.stop)
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			local button = w.event(E.UserInputType.MouseButton1, V2.new(220, 180), E.UserInputState.Begin)
			local nativeView = (w.view :: unknown) :: { InputBegan: engineLib.Signal<InputObject> }
			nativeView.InputBegan:Fire(button)
			w.input.InputBegan:Fire(button, true)
			local before = w.view.CanvasPosition
			for index = 1, 5 do
				local at = V2.new(220 + index * 10, 180 + index * 4)
				w.setMouse(at + V2.new(0, 56))
				local movement = w.event(E.UserInputType.MouseMovement, at, E.UserInputState.Change)
				w.input.InputChanged:Fire(movement, true)
				t:expect((w.view.CanvasPosition - (before - V2.new(index * 10, index * 4))).Magnitude < 0.001)
					:toBe(true)
			end
			t:expect(button.Position.X):toBe(220)
			local detector = (w.view:FindFirstChild("ZoomPanDetector") :: unknown) :: {
				DragStart: engineLib.Signal<Vector2>,
				DragContinue: engineLib.Signal<Vector2>,
			}
			local atRest = w.view.CanvasPosition
			detector.DragStart:Fire(V2.new(270, 256))
			detector.DragContinue:Fire(V2.new(300, 256))
			t:expect(w.view.CanvasPosition):toBe(atRest)
			local endAt = w.view.CanvasPosition
			w.input.InputEnded:Fire(button, true)
			w.setMouse(V2.new(300, 256))
			w.input.InputChanged:Fire(
				w.event(E.UserInputType.MouseMovement, V2.new(300, 200), E.UserInputState.Change),
				true
			)
			t:expect(w.view.CanvasPosition):toBe(endAt)
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.view.CanvasPosition):toBe(endAt)
		end)

		harness:case("accepts zero-scale pinch begin and preserves the inset-adjusted focus", function(t)
			local w = inputWorld()
			t:defer(w.stop)
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			local before = w.view.CanvasPosition
			local localAt = V2.new(200, 150)
			local point = (localAt + before) / w.scale.Scale
			w.input.TouchPinch:Fire({ V2.new(170, 186), V2.new(270, 286) }, 0, 0, E.UserInputState.Begin, true)
			t:expect(w.scale.Scale):toBe(2)
			for index = 1, 10 do
				local ratio = 1 + index / 20
				w.input.TouchPinch:Fire({ V2.new(170, 186), V2.new(270, 286) }, ratio, 0, E.UserInputState.Change, true)
				t:expect(w.scale.Scale):toBe(2 * ratio)
				t:expect((point * w.scale.Scale - w.view.CanvasPosition - localAt).Magnitude < 0.001):toBe(true)
			end
			local last = w.scale.Scale
			w.input.TouchPinch:Fire({}, 0, 0, E.UserInputState.End, true)
			t:expect(w.scale.Scale):toBe(last)
		end)

		harness:case("keeps Ctrl-wheel focus and plain wheel inside the board", function(t)
			local w = inputWorld()
			t:defer(w.stop)
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			w.input.InputChanged:Fire(
				w.event(E.UserInputType.MouseMovement, V2.new(220, 180), E.UserInputState.Change),
				true
			)
			local before = w.view.CanvasPosition
			local localAt = V2.new(200, 150)
			local point = (localAt + before) / w.scale.Scale
			local outer = w.outer.CanvasPosition
			local wheel = w.event(E.UserInputType.MouseWheel, V2.zero, E.UserInputState.Change)
			wheel.Position = w.engine.types.Vector3.new(0, 0, 1)
			w.setControl(true)
			w.input.InputChanged:Fire(wheel, true)
			if w.view.ScrollingEnabled then
				w.view.CanvasPosition += V2.new(0, -40)
			elseif w.outer.ScrollingEnabled then
				w.outer.CanvasPosition += V2.new(0, -40)
			end
			for _ = 1, 20 do
				w.engine.heartbeat:Fire(0.016)
				t:expect((point * w.scale.Scale - w.view.CanvasPosition - localAt).Magnitude < 0.001):toBe(true)
			end
			t:expect(w.outer.CanvasPosition):toBe(outer)
			w.setControl(false)
			before = w.view.CanvasPosition
			w.input.InputChanged:Fire(wheel, true)
			if w.view.ScrollingEnabled then
				w.view.CanvasPosition += V2.new(0, -40)
			elseif w.outer.ScrollingEnabled then
				w.outer.CanvasPosition += V2.new(0, -40)
			end
			t:expect(w.view.CanvasPosition.Y < before.Y):toBe(true)
			t:expect(w.outer.CanvasPosition):toBe(outer)
			w.setMouse(V2.new(700, 756))
			w.input.InputChanged:Fire(
				w.event(E.UserInputType.MouseMovement, V2.new(700, 700), E.UserInputState.Change),
				false
			)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
		end)

		harness:case("releases wheel ownership for overlays focus loss disable and disposal", function(t)
			local w = inputWorld()
			t:defer(w.stop)
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			local movement = w.event(E.UserInputType.MouseMovement, V2.new(220, 180), E.UserInputState.Change)
			w.input.InputChanged:Fire(movement, true)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			w.input.WindowFocusReleased:Fire()
			t:expect(w.outer.ScrollingEnabled):toBe(true)
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
			w.input.WindowFocused:Fire()
			w.input.InputChanged:Fire(movement, true)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			local blocker = w.engine.new("TextButton")
			w.player.GetGuiObjectsAtPosition = function()
				return { blocker, w.view, w.outer }
			end
			w.input.InputChanged:Fire(movement, true)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
			w.player.GetGuiObjectsAtPosition = function()
				return { w.view, w.outer }
			end
			w.view.Visible = false
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
			w.view.Visible = true
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			w.enabled:set(false)
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
			t:expect(w.view.ScrollingEnabled):toBe(false)
			w.enabled:set(true)
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			w.outer.ClipsDescendants = true
			w.outer.AbsolutePosition, w.outer.AbsoluteSize = V2.zero, V2.new(100, 100)
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
			w.outer.ClipsDescendants = false
			w.engine.heartbeat:Fire(0.016)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			w.stop()
			t:expect(w.outer.ScrollingEnabled):toBe(true)
		end)

		harness:case("keeps pinch scroll ownership across a mouse to touch switch", function(t)
			local w = inputWorld()
			t:defer(w.stop)
			local V2, E = w.engine.types.Vector2, w.engine.types.Enum
			w.input.InputChanged:Fire(
				w.event(E.UserInputType.MouseMovement, V2.new(220, 180), E.UserInputState.Change),
				true
			)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			w.input.PreferredInput = E.PreferredInput.Touch
			w.input.TouchPinch:Fire({ V2.new(170, 186), V2.new(270, 286) }, 0, 0, E.UserInputState.Begin, true)
			w.input.TouchPinch:Fire({ V2.new(170, 186), V2.new(270, 286) }, 1.25, 0, E.UserInputState.Change, true)
			t:expect(w.view.ScrollingEnabled):toBe(false)
			t:expect(w.outer.ScrollingEnabled):toBe(false)
			w.input.TouchPinch:Fire({}, 0, 0, E.UserInputState.End, true)
			t:expect(w.view.ScrollingEnabled):toBe(true)
			t:expect(w.outer.ScrollingEnabled):toBe(true)
		end)

		harness:case("permits one capture-time camera request and defers later zoom", function(t)
			local engine = engineLib.new({ lenientProperties = true })
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: Shared.Host
			local input = engine.new("UserInputService")
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

		harness:case("capture camera keeps overlay contact and releases onto the drawn target", function(t)
			local engine = engineLib.new({ lenientProperties = true })
			local C = Facet.Compose
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: Shared.Host
			local input, run = engine.new("UserInputService"), engine.new("RunService")
			run.PreRender = VerifyRoblox.testEnvironment().newSignal()
			local player, screen = engine.new("PlayerGui"), engine.new("ScreenGui")
			screen.Parent = player
			local config = { types = engine.types, userInputService = input, services = { RunService = run } }
			local ctx = require("../src/ui/context")(C, runtime, config)
			local drag = require("../src/ui/drag_session")(ctx)
			local UI = ({} :: unknown) :: ZoomTypes.Controls
			require("../src/ui/zoom_view")(ctx, UI)
			local zoom, controls = C.cell(0.4), {} :: Facet.ZoomControls
			local view: ScrollingFrame
			local tile: TextButton
			local a, b = engine.new("Frame"), engine.new("Frame")
			local placed: GuiObject? = nil
			local stop = runtime.mount(function()
				view = UI.ZoomView {
					zoom = zoom,
					controls = controls,
					contentSize = engine.types.Vector2.new(1000, 1000),
					content = function(): GuiObject
						tile = Host.TextButton {}
						drag.own(tile)
						return tile
					end,
				}
				drag.register(a, {
					onDrop = function()
						placed = a
					end,
				})
				drag.register(b, {
					onDrop = function()
						placed = b
					end,
				})
				return view
			end, screen)
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			a.Parent, b.Parent = view, view
			view.AbsoluteWindowSize = engine.types.Vector2.new(400, 400)
			local methods = (view :: unknown) :: { ResetScrollVelocity: () -> () }
			methods.ResetScrollVelocity = function() end
			run.PreRender:Fire(0)
			local scale = view:FindFirstChild("ZoomScale", true) :: UIScale
			local V2 = engine.types.Vector2
			local function measure()
				a.AbsolutePosition = V2.new(600, 550) * scale.Scale - view.CanvasPosition
				b.AbsolutePosition = V2.new(500, 550) * scale.Scale - view.CanvasPosition
				a.AbsoluteSize, b.AbsoluteSize = V2.new(50, 50) * scale.Scale, V2.new(30, 50) * scale.Scale
			end
			measure()
			view.Changed:Connect(function(property: string)
				if property == "CanvasPosition" then
					measure()
				end
			end)
			player.GetGuiObjectsAtPosition = function(_player: PlayerGui, x: number, y: number)
				local hits: { GuiObject } = {}
				for _, node in { a, b } do
					local p, size = node.AbsolutePosition, node.AbsoluteSize
					if x >= p.X and x < p.X + size.X and y >= p.Y and y < p.Y + size.Y then
						table.insert(hits, node)
					end
				end
				return hits
			end
			tile.AbsolutePosition, tile.AbsoluteSize = V2.new(170, 200), V2.new(44, 44)
			local point = V2.new(190, 220)
			drag.begin(tile, {
				payload = "tile",
				onStart = function()
					t:expect(assert(controls.zoomAt)(2)):toBe(true)
					t:expect(assert(controls.fit)()):toBe(false)
				end,
				onEnd = function()
					t:expect(assert(controls.fit)()):toBe(true)
				end,
			}, "pointer", nil, nil, { position = point, source = tile :: GuiObject })
			local held = assert(drag.state:peek())
			local ghost = assert(held.ghost)
			t:expect(ghost.Parent == screen):toBe(true)
			local duration = ctx.metric("motion.durations.zoom")
			local previous = scale.Scale
			for frame = 1, math.ceil(duration * 120) + 1 do
				if frame == 2 then
					point = V2.new(250, 230)
					drag.update(point)
				end
				engine.heartbeat:Fire(1 / 120)
				run.PreRender:Fire(1 / 120)
				t:expect(scale.Scale >= previous):toBe(true)
				t:expect(math.abs(475 * scale.Scale - view.CanvasPosition.X - 190) < 0.001):toBe(true)
				local contact = V2.new(ghost.Position.X.Offset, ghost.Position.Y.Offset)
					+ (held.pickupAnchor - ghost.AnchorPoint) * held.pickupSize
				t:expect((contact - point).Magnitude <= 1):toBe(true)
				previous = scale.Scale
			end
			t:expect(scale.Scale):toBe(2)
			t:expect(assert(drag.state:peek()).target):toBe(b)
			drag.commit(nil)
			t:expect(placed):toBe(b)
			for _ = 1, math.ceil(duration * 120) + 2 do
				engine.heartbeat:Fire(1 / 120)
				run.PreRender:Fire(1 / 120)
			end
			t:expect(scale.Scale):toBe(0.4)
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
