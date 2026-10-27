--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Roblox = require("../tools/vendor/verify/src/roblox")
local Lute = require("../tools/vendor/verify/src/lute")
local Facet = require("../src")
local Shared = require("../src/ui/types")
local CameraRigTypes = require("../src/ui/camera_rig_types")
local engines = require("./lib/native_engine")

local function fixture(inertia: boolean?, smoothing: boolean?, initial: CameraRigTypes.CameraPose?)
	local roots: { Roblox.Instance } = {}
	local engine, bridge = engines.new({
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
		},
	})
	local tracking = bridge.track()
	local C, V2, V3, E = Facet.Compose, engine.types.Vector2, engine.types.Vector3, engine.types.Enum
	local player: PlayerGui = engine.new("PlayerGui")
	local input: UserInputService = engine.new("UserInputService")
	local gui: GuiService = engine.new("GuiService")
	local workspace: Workspace = engine.new("Workspace")
	local focused: TextBox? = nil
	engine.environment.fakeOn(input, "GetFocusedTextBox", function(): TextBox?
		return focused
	end)
	table.insert(roots, Roblox.assertInstance(player))
	local runtime = Facet.Roblox.createRuntime(bridge.engine)
	local Host = Facet.host(runtime)
	local motion = C.cell<<Shared.MotionLevel>>("normal")
	local enabled, blocked = C.cell(true), C.cell(false)
	local UI = Facet.controls(runtime, {
		types = engine.types,
		motionLevel = motion,
		services = {
			UserInputService = input,
			GuiService = gui,
			Workspace = workspace,
		},
	})
	local rig: Facet.CameraRig? = nil
	local button: TextButton? = nil
	local baselineConnections = engine.census().connections
	local function App(): ScreenGui
		rig = UI.cameraRig {
			inputRoot = player,
			initial = initial or { focus = V3.zero, yaw = 0, pitch = 0, distance = 10 },
			focusBounds = { min = V3.new(-2, -1, -3), max = V3.new(2, 1, 3) },
			yawBounds = V2.new(-1, 1),
			pitchBounds = V2.new(-0.5, 0.5),
			distanceBounds = V2.new(2, 20),
			presets = {
				room = { focus = V3.zero, yaw = 0, pitch = 0, distance = 10 },
				table = { focus = V3.new(1, 1, 2), yaw = 0.8, pitch = 0.3, distance = 4 },
			},
			enabled = enabled,
			blocked = blocked,
			inertia = inertia,
			smoothing = smoothing,
		}
		button = UI.Button "Control" {
			label = "Press",
			Position = engine.types.UDim2.fromOffset(10, 10),
			Size = engine.types.UDim2.fromOffset(100, 50),
		}
		UI.draggable(assert(button), { payload = "camera-test", touchPickup = "immediate" })
		return Host.ScreenGui "Application" { assert(button) }
	end
	local stop = runtime.mount(App, player)
	local backend = Roblox.inputHost.simulated(engine.environment, {
		playerGui = Roblox.assertInstance(player),
		inputService = Roblox.assertInstance(input),
		layout = assert(bridge.layout),
		inset = function()
			return { X = 0, Y = 0 }
		end,
		library = Roblox.reflectionSnapshot.library(Lute.fixture.load()),
		activationWindowSeconds = 0.5,
	})
	local function step(count: number?)
		for _ = 1, count or 1 do
			engine.environment.step(1 / 60)
			engine.heartbeat:Fire(1 / 60)
		end
	end
	step()
	backend.pointer({ x = 400, y = 300, button = "left", down = true })
	backend.pointer({ x = 400, y = 300, button = "left", down = false })
	local function fire(event: string, ...: unknown)
		engine.environment.fire(Roblox.assertInstance(input), event, ...)
	end
	local function event(kind: Enum.UserInputType, x: number?, y: number?, z: number?): InputObject
		local object: InputObject = engine.new("InputObject")
		engine.environment.poke(Roblox.assertInstance(object), "UserInputType", kind)
		engine.environment.poke(Roblox.assertInstance(object), "Position", V3.new(x or 400, y or 300, z or 0))
		return object
	end
	local function action(name: string, signal: string, value: unknown?)
		local node = assert(player:FindFirstChild(name, true))
		engine.environment.fire(Roblox.assertInstance(node), signal, value)
	end
	return {
		rig = assert(rig),
		engine = engine,
		input = input,
		player = player,
		gui = gui,
		workspace = workspace,
		V2 = V2,
		V3 = V3,
		E = E,
		UI = UI,
		button = assert(button),
		motion = motion,
		enabled = enabled,
		blocked = blocked,
		step = step,
		fire = fire,
		event = event,
		action = action,
		backend = backend,
		focusText = function(value: TextBox?)
			focused = value
		end,
		close = function()
			backend.close()
			stop()
			Verify.expect(engine.census().connections):toBe(baselineConnections)
			Verify.expect(player:FindFirstChild("FacetCameraRig")):toBe(nil)
			runtime:dispose()
			for _, object in tracking.created do
				engine.destroy(object)
			end
			tracking.stop()
			Verify.expect(engine.census().connections):toBe(0)
			Verify.expect(engine.census().live):toBe(0)
		end,
	}
end

return function(harness: Verify.Harness)
	harness:case("cameraRig clamps initial pose and commanded focus", function(t)
		local engine = engines.new()
		local w = fixture(
			nil,
			nil,
			{ focus = engine.types.Vector3.new(100, -100, 100), yaw = 100, pitch = -100, distance = 100 }
		)
		t:defer(w.close)
		local pose = w.rig.state:peek()
		t:expect(pose.yaw):toBe(1)
		t:expect(pose.pitch):toBe(-0.5)
		t:expect(pose.distance):toBe(20)
		t:expect(pose.focus):toBe(w.V3.new(2, -1, 3))
		w.rig.focus:set(w.V3.new(-100, 100, -100))
		w.step(60)
		t:expect(w.rig.focus:peek()):toBe(w.V3.new(-2, 1, -3))
		t:expect(w.rig.state:peek().focus):toBe(w.V3.new(-2, 1, -3))
	end)
	harness:case("cameraRig orbits from either mouse drag and clamps wheel zoom", function(t)
		local w = fixture()
		t:defer(w.close)
		for _, kind in { w.E.UserInputType.MouseButton1, w.E.UserInputType.MouseButton2 } do
			local press = w.event(kind)
			w.fire("InputBegan", press, false)
			w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 10000, 10000), false)
			w.fire("InputEnded", press, false)
			t:expect(w.rig.state:peek().yaw):toBe(-1)
			t:expect(w.rig.state:peek().pitch):toBe(0.5)
			w.rig.reset()
			w.step(60)
		end
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 100), false)
		t:expect(w.rig.state:peek().distance):toBe(2)
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, -100), false)
		t:expect(w.rig.state:peek().distance):toBe(20)
	end)
	harness:case("cameraRig touch orbit pinch and two finger pan stay bounded", function(t)
		local w = fixture()
		t:defer(w.close)
		local one, two = w.event(w.E.UserInputType.Touch), w.event(w.E.UserInputType.Touch, 500, 300)
		local points = { w.V2.new(400, 300) }
		w.fire("InputBegan", one, false)
		w.fire("TouchPan", points, w.V2.zero, w.V2.zero, w.E.UserInputState.Begin, false)
		w.fire("TouchPan", points, w.V2.new(100, 50), w.V2.zero, w.E.UserInputState.Change, false)
		t:expect(w.rig.state:peek().yaw):toBe(-0.5)
		t:expect(w.rig.state:peek().pitch):toBe(0.25)
		w.fire("TouchPan", points, w.V2.new(100, 50), w.V2.zero, w.E.UserInputState.End, false)
		w.fire("InputBegan", two, false)
		table.insert(points, w.V2.new(500, 300))
		w.fire("TouchPan", points, w.V2.zero, w.V2.zero, w.E.UserInputState.Begin, false)
		w.fire("TouchPinch", points, 1, 0, w.E.UserInputState.Begin, false)
		w.fire("TouchPinch", points, 100, 0, w.E.UserInputState.Change, false)
		w.fire("TouchPan", points, w.V2.new(10000, 10000), w.V2.zero, w.E.UserInputState.Change, false)
		local pose = w.rig.state:peek()
		t:expect(pose.distance):toBe(2)
		t:expect(pose.focus.X):toBe(-2)
		t:expect(pose.focus.Y):toBe(1)
		t:expect(pose.yaw):toBe(-0.5)
		w.fire("TouchPinch", points, 0.001, 0, w.E.UserInputState.Change, false)
		t:expect(w.rig.state:peek().distance):toBe(20)
	end)
	harness:case("cameraRig keyboard paths use native bindings and stop at release", function(t)
		local w = fixture()
		t:defer(w.close)
		for _, code in
			{ "W", "Up", "S", "Down", "A", "Left", "D", "Right", "Equals", "KeypadPlus", "Minus", "KeypadMinus" }
		do
			w.backend.key({ code = code, down = true })
			w.step(4)
			w.backend.key({ code = code, down = false })
			local pose = w.rig.state:peek()
			t:expect(pose.yaw ~= 0 or pose.pitch ~= 0 or pose.distance ~= 10):toBe(true)
			w.step(4)
			t:expect(w.rig.state:peek()):toBe(pose)
			w.rig.reset()
			w.step(60)
		end
	end)
	harness:case("cameraRig gamepad right stick and both triggers move and release", function(t)
		local w = fixture()
		t:defer(w.close)
		w.action("CameraOrbit", "StateChanged", w.V2.new(0.5, 0.5))
		w.fire("InputChanged", w.event(w.E.UserInputType.Gamepad1), true)
		w.step(10)
		t:expect(w.rig.state:peek().yaw < 0):toBe(true)
		t:expect(w.rig.state:peek().pitch > 0):toBe(true)
		w.action("CameraOrbit", "Released")
		w.action("CameraIn", "Pressed")
		w.step(10)
		t:expect(w.rig.state:peek().distance < 10):toBe(true)
		w.action("CameraIn", "Released")
		local distance = w.rig.state:peek().distance
		w.action("CameraOut", "Pressed")
		w.step(10)
		t:expect(w.rig.state:peek().distance > distance):toBe(true)
		w.action("CameraOut", "Released")
		local before = w.rig.camera:peek()
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
	end)
	harness:case("cameraRig ignores UI presses processed gestures and selected controls", function(t)
		local w = fixture(true, true)
		t:defer(w.close)
		local before = w.rig.camera:peek()
		w.backend.pointer({ x = 30, y = 30, button = "left", down = true })
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 60, 30), true)
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.backend.pointer({ x = 60, y = 30, button = "left", down = false })
		w.fire("InputBegan", w.event(w.E.UserInputType.MouseButton2), true)
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 700, 500), false)
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), true)
		w.gui.SelectedObject = w.button
		w.action("CameraOrbit", "StateChanged", w.V2.new(1, 1))
		w.action("CameraIn", "Pressed")
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
	end)
	harness:case("cameraRig yields to active world drags and explicit game drags", function(t)
		local w = fixture(true, true)
		t:defer(w.close)
		local part: Part = w.engine.new("Part")
		part.Parent = w.workspace
		local detector: DragDetector = w.engine.new("DragDetector")
		detector.Parent = part
		w.fire("InputBegan", w.event(w.E.UserInputType.MouseButton2), false)
		w.engine.environment.fire(Roblox.assertInstance(detector), "DragStart")
		local before = w.rig.camera:peek()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 700, 500), false)
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), false)
		w.step(20)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.engine.environment.fire(Roblox.assertInstance(detector), "DragEnd")
		w.blocked:set(true)
		w.action("CameraOrbit", "StateChanged", w.V2.new(1, 1))
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.blocked:set(false)
		w.step()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), false)
		w.step(10)
		t:expect(w.rig.camera:peek() == before):toBe(false)
	end)
	harness:case("cameraRig yields to a Facet drag after the pointer leaves its source", function(t)
		local w = fixture(true, true)
		t:defer(w.close)
		local press = w.event(w.E.UserInputType.MouseButton1, 30, 30)
		local source = Roblox.assertInstance(w.button)
		w.engine.environment.fire(source, "InputBegan", press)
		local pendingCamera = w.rig.camera:peek()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), false)
		t:expect(w.rig.camera:peek()):toBe(pendingCamera)
		local detector = Roblox.assertInstance(assert(w.button:FindFirstChild("FacetDragDetector")))
		w.engine.environment.fire(detector, "DragStart", w.V2.new(30, 30))
		w.engine.environment.fire(detector, "DragContinue", w.V2.new(200, 200))
		w.step()
		t:expect(w.button:GetAttribute("FacetDragHeld")):toBe(true)
		local before = w.rig.camera:peek()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 500, 400), false)
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), false)
		w.action("CameraOrbit", "StateChanged", w.V2.new(1, 1))
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.engine.environment.fire(detector, "DragEnd", w.V2.new(500, 400))
		w.fire("InputEnded", press, false)
	end)
	harness:case("cameraRig preset travel retargets and reset restores its initial pose", function(t)
		local w = fixture()
		t:defer(w.close)
		local initial = w.rig.camera:peek()
		w.rig.preset:set("table")
		t:expect(w.rig.camera:peek()):toBe(initial)
		w.step(5)
		local middle = w.rig.state:peek()
		t:expect(middle.focus.X > 0 and middle.focus.X < 1):toBe(true)
		t:expect(middle.distance > 4 and middle.distance < 10):toBe(true)
		w.rig.preset:set("room")
		t:expect(w.rig.state:peek().focus):toBe(middle.focus)
		w.step(60)
		t:expect(w.rig.camera:peek()):toBe(initial)
		w.rig.preset:set("table")
		w.step(60)
		t:expect(w.rig.state:peek().distance):toBe(4)
		t:expect(w.rig.preset:peek()):toBe("table")
		w.rig.reset()
		w.step(60)
		t:expect(w.rig.preset:peek()):toBe(nil)
		t:expect(w.rig.camera:peek()):toBe(initial)
	end)
	harness:case("cameraRig inertia continues after release and reduced motion cuts travel", function(t)
		local w = fixture(true, true)
		t:defer(w.close)
		local press = w.event(w.E.UserInputType.MouseButton2)
		w.fire("InputBegan", press, false)
		w.step()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 410, 300), false)
		w.fire("InputEnded", press, false)
		local released = w.rig.state:peek().yaw
		w.step(3)
		t:expect(w.rig.state:peek().yaw < released):toBe(true)
		w.motion:set("limited")
		w.rig.preset:set("table")
		t:expect(w.rig.state:peek().focus):toBe(w.V3.new(1, 1, 2))
		t:expect(w.rig.state:peek().distance):toBe(4)
		w.rig.reset()
		t:expect(w.rig.state:peek().yaw):toBe(0)
		w.fire("InputBegan", press, false)
		w.step()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 410, 300), false)
		w.fire("InputEnded", press, false)
		local before = w.rig.camera:peek()
		w.step(30)
		t:expect(w.rig.camera:peek()):toBe(before)
	end)
	harness:case("cameraRig stops held input on disable window loss and disconnect", function(t)
		local w = fixture()
		t:defer(w.close)
		w.action("CameraOrbit", "StateChanged", w.V2.new(1, 1))
		w.step(3)
		w.fire("WindowFocusReleased")
		local before = w.rig.camera:peek()
		w.fire("WindowFocused")
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.fire("WindowFocused")
		w.action("CameraOrbit", "StateChanged", w.V2.new(1, 1))
		w.fire("GamepadDisconnected", w.E.UserInputType.Gamepad1)
		w.step(10)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.enabled:set(false)
		w.step()
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), false)
		t:expect(w.rig.camera:peek()):toBe(before)
	end)
	harness:case("cameraRig freezes inertia when a UI press or a world drag takes input", function(t)
		for _, worldDrag in { false, true } do
			local w = fixture(true, true)
			t:defer(w.close)
			local press = w.event(w.E.UserInputType.MouseButton2)
			w.fire("InputBegan", press, false)
			w.step()
			w.fire("InputChanged", w.event(w.E.UserInputType.MouseMovement, 410, 300), false)
			w.fire("InputEnded", press, false)
			w.step(2)
			local before = w.rig.camera:peek()
			if worldDrag then
				local detector: DragDetector = w.engine.new("DragDetector")
				detector.Parent = w.workspace
				w.engine.environment.fire(Roblox.assertInstance(detector), "DragStart")
			else
				w.fire("InputBegan", w.event(w.E.UserInputType.Touch), true)
			end
			w.step(30)
			t:expect(w.rig.camera:peek()):toBe(before)
		end
	end)
	harness:case("cameraRig cuts an active trip when engine reduced motion changes", function(t)
		local w = fixture(true, true)
		t:defer(w.close)
		w.rig.preset:set("table")
		w.step(3)
		w.engine.environment.poke(Roblox.assertInstance(w.gui), "ReducedMotionEnabled", true)
		t:expect(w.rig.state:peek().distance):toBe(4)
		t:expect(w.rig.state:peek().focus):toBe(w.V3.new(1, 1, 2))
		w.motion:set("none")
		w.rig.reset()
		t:expect(w.rig.state:peek().distance):toBe(10)
	end)
	harness:case("cameraRig releases removed world detector subscriptions while mounted", function(t)
		local w = fixture()
		t:defer(w.close)
		local connections = w.engine.census().connections
		for _ = 1, 3 do
			local detector: DragDetector = w.engine.new("DragDetector")
			detector.Parent = w.workspace
			t:expect(w.engine.census().connections):toBe(connections + 2)
			w.engine.environment.fire(Roblox.assertInstance(detector), "DragStart")
			detector:Destroy()
			t:expect(w.engine.census().connections):toBe(connections)
		end
		w.fire("InputChanged", w.event(w.E.UserInputType.MouseWheel, 400, 300, 1), false)
		t:expect(w.rig.state:peek().distance):toBe(2)
	end)
	harness:case("cameraRig pointer takeover starts at the rendered pose during smoothed travel", function(t)
		local w = fixture(true, true)
		t:defer(w.close)
		w.rig.preset:set("table")
		w.step(5)
		local before = w.rig.camera:peek()
		w.fire("InputBegan", w.event(w.E.UserInputType.MouseButton2), false)
		t:expect(w.rig.camera:peek()):toBe(before)
		w.step(5)
		t:expect(w.rig.camera:peek()):toBe(before)
		t:expect(w.rig.preset:peek()):toBe(nil)
	end)
end
