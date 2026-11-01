--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Roblox = require("../tools/vendor/verify/src/roblox")
local Facet = require("../src")
local context = require("../src/ui/context")
local sessionOf = require("../src/ui/drag_session")
local worldOf = require("../src/ui/drag_world")
local gestureOf = require("../src/ui/gesture_service")
local engines = require("./lib/native_engine")
local planePoint = require("../src/ui/drag_plane")
local Native = require("../src/ui/engine_types")

local function fixture(test: Verify.Context, level: ("normal" | "limited" | "none")?)
	local engine, bridge = engines.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local world: Workspace = engine.new("Workspace")
	local screen: ScreenGui = engine.new("ScreenGui")
	local input: UserInputService = engine.new("UserInputService")
	local gui: GuiService = engine.new("GuiService")
	local parent: Folder = engine.new("Folder")
	screen.Parent = parent
	local config: Facet.ControlOptions = {
		types = engine.types,
		motionLevel = level or "normal",
		inputParent = screen,
		userInputService = input,
		guiService = gui,
		services = { Workspace = world },
	}
	local ctx = context(Facet.Compose, runtime, config)
	local session = sessionOf(ctx)
	local Host = Facet.host(runtime)
	local source: BasePart = engine.new("Part")
	source.Anchored = true
	source.CFrame = engine.types.CFrame.new(0, 1, 0)
	source.Parent = world
	local focus: GuiObject = engine.new("TextButton")
	focus.Parent = screen
	local target: BasePart = engine.new("Part")
	target.CFrame = engine.types.CFrame.new(4, 0, 0)
	target.Size = engine.types.Vector3.new(2, 1, 2)
	target.Parent = world
	local goal = engine.types.CFrame.new(4, 1, 0)
	local drops: { Facet.DropInfo } = {}
	local starts, ends, enters, leaves = 0, 0, 0, 0
	local options: Facet.WorldDragOptions = { plane = engine.types.CFrame.identity, lift = 0.5, focusTarget = focus }
	local spec: Facet.DraggableSpec = {
		payload = "tile",
		world = options,
		onStart = function()
			starts += 1
		end,
		onEnd = function()
			ends += 1
		end,
	}
	local nativeBeforeMount = engine.census()
	local registrations = function(): number
		return 0
	end
	local stop = runtime.mount(function()
		local owner = assert(Facet.Compose.currentOwner())
		registrations = function(): number
			return Facet.Compose.owner.size(owner)
		end
		worldOf(ctx, source, spec, session)
		session.register(target, {
			worldPlacement = goal,
			onEnter = function()
				enters += 1
			end,
			onLeave = function()
				leaves += 1
			end,
			onDrop = function(payload: unknown, info: Facet.DropInfo): boolean
				Verify.expect(payload):toBe("tile")
				table.insert(drops, info)
				return true
			end,
		})
		return Host.Folder { Name = "WorldDragOwner" }
	end, parent)
	test:defer(function()
		stop()
		runtime:dispose()
		world:Destroy()
		parent:Destroy()
		input:Destroy()
		gui:Destroy()
	end)
	return {
		engine = engine,
		runtime = runtime,
		ctx = ctx,
		world = world,
		screen = screen,
		input = input,
		gui = gui,
		source = source,
		target = target,
		focus = focus,
		session = session,
		options = options,
		goal = goal,
		drops = drops,
		stop = stop,
		nativeBeforeMount = nativeBeforeMount,
		registrations = registrations,
		counts = function()
			return { starts = starts, ends = ends, enters = enters, leaves = leaves }
		end,
		begin = function(mode: "pointer" | "armed")
			session.begin(source, {
				payload = spec.payload,
				world = options,
				onStart = spec.onStart,
				onEnd = spec.onEnd,
			}, mode, nil, false)
		end,
	}
end

return function(h: Verify.Harness)
	h:case("world pointer rays intersect an authored horizontal or tilted plane", function()
		local V3, CF = engines.types.Vector3, engines.types.CFrame
		local horizontal = planePoint(V3.new(1, 10, 3), V3.new(1, -2, 0), CF.new(0, 2, 0))
		Verify.expect(horizontal):toBe(V3.new(5, 2, 3))
		local tilted = CF.new(0, 0, 2) * CF.Angles(math.pi / 2, 0, 0)
		local point = assert(planePoint(V3.new(3, 4, 10), V3.new(0, 0, -1), tilted))
		Verify.expect((point - V3.new(3, 4, 2)).Magnitude < 1e-6):toBe(true)
	end)
	h:case("parallel and backwards world pointer rays keep the last position", function()
		local V3, CF = engines.types.Vector3, engines.types.CFrame
		Verify.expect(planePoint(V3.new(0, 10, 0), V3.xAxis, CF.identity)):toBeNil()
		Verify.expect(planePoint(V3.new(0, 10, 0), V3.yAxis, CF.identity)):toBeNil()
	end)
	h:case("world sessions hover, snap and drop through the shared proposal", function(test)
		local w = fixture(test)
		w.begin("pointer")
		w.engine.heartbeat:Fire(1)
		Verify.expect(w.source:GetPivot().Position.Y):toBe(1.5)
		w.session.hover(w.target)
		Verify.expect(w.target:GetAttribute("FacetDropState")):toBe("accepted")
		Verify.expect(w.source:GetPivot().Position.X):toBe(4)
		Verify.expect(w.source:GetPivot().Position.Y):toBe(1.5)
		Verify.expect(w.session.commit(w.target)):toBe(true)
		Verify.expect(#w.drops):toBe(0)
		w.engine.heartbeat:Fire(1)
		Verify.expect(#w.drops):toBe(1)
		Verify.expect(w.drops[1].source):toBe(w.source)
		Verify.expect(w.drops[1].worldPlacement):toBe(w.goal)
		Verify.expect(w.source:GetPivot()):toBe(w.goal)
		Verify.expect(w.session.state:peek()):toBeNil()
		Verify.expect(w.counts()):toEqual({ starts = 1, ends = 1, enters = 1, leaves = 1 })
	end)
	h:case("cancel returns the held object and stops return resources", function(test)
		local w = fixture(test)
		local baseline = w.engine.census()
		w.begin("armed")
		w.engine.heartbeat:Fire(1)
		w.session.hover(w.target)
		w.session.finish(false, "Cancelled")
		Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBe(true)
		w.engine.heartbeat:Fire(1)
		Verify.expect(w.source:GetPivot()):toBe(w.engine.types.CFrame.new(0, 1, 0))
		Verify.expect(w.source:GetAttribute("FacetDragHeld")):toBeNil()
		Verify.expect(#w.drops):toBe(0)
		Verify.expect(w.engine.census()):toEqual(baseline)
	end)
	local function reducedMotionCase(level: "limited" | "none")
		h:case("world " .. level .. " motion has no lift or travel", function(test)
			local w = fixture(test, level)
			w.begin("armed")
			Verify.expect(w.source:GetPivot().Position.Y):toBe(1)
			w.session.hover(w.target)
			Verify.expect(w.source:GetPivot()):toBe(w.goal)
			w.session.finish(false)
			Verify.expect(w.source:GetPivot()):toBe(w.engine.types.CFrame.new(0, 1, 0))
			w.begin("armed")
			w.session.commit(w.target)
			Verify.expect(#w.drops):toBe(1)
			Verify.expect(w.source:GetPivot()):toBe(w.goal)
		end)
	end
	reducedMotionCase("limited")
	reducedMotionCase("none")
	h:case("keyboard and gamepad pickup bindings start one armed session", function(test)
		local w = fixture(test, "none")
		local pickup = assert(w.screen:FindFirstChild("WorldDragPickUp", true))
		Verify.expect(pickup:IsA("InputAction")):toBe(true)
		local keys = {}
		for _, child in pickup:GetChildren() do
			if child:IsA("InputBinding") then
				keys[child.KeyCode.Name] = true
			end
		end
		Verify.expect(keys.Return):toBe(true)
		Verify.expect(keys.ButtonA):toBe(true)
		w.engine.environment.poke(Roblox.assertInstance(w.gui), "SelectedObject", w.focus)
		w.engine.environment.fire(Roblox.assertInstance(pickup), "Pressed")
		Verify.expect(assert(w.session.state:peek()).mode):toBe("armed")
		w.session.hover(w.target)
		w.session.commit(w.target)
		Verify.expect(w.drops[1].mode):toBe("armed")
		Verify.expect(w.counts().starts):toBe(1)
	end)
	h:case("a UI source and a world source use one placement handler", function(test)
		local w = fixture(test, "none")
		local placed: { Facet.DropInfo } = {}
		local function place(payload: unknown, info: Facet.DropInfo): boolean
			Verify.expect(payload):toBe("tile")
			Verify.expect(assert(info.placement).column):toBe(3)
			table.insert(placed, info)
			return true
		end
		local stop = w.runtime.mount(function()
			w.session.register(w.target, {
				worldPlacement = w.goal,
				placement = { column = 3, row = 1, width = 1, height = 1 },
				onDrop = place,
			})
			return w.runtime.constructors.Folder {}
		end, w.screen)
		test:defer(stop)
		w.session.begin(w.focus, { payload = "tile" }, "armed", nil, false)
		w.session.commit(w.target)
		w.begin("armed")
		w.session.commit(w.target)
		Verify.expect(#placed):toBe(2)
		Verify.expect(placed[1].source):toBe(w.focus)
		Verify.expect(placed[2].source):toBe(w.source)
		Verify.expect(placed[1].operation):toBe(placed[2].operation)
		Verify.expect(placed[1].worldPlacement):toBe(placed[2].worldPlacement)
		Verify.expect(placed[1].complete(true)):toBe(false)
		Verify.expect(placed[2].complete(true)):toBe(false)
	end)
	h:case("world arbitration denies a competing UI or camera owner", function(test)
		local w = fixture(test, "none")
		local pointer: InputObject = w.engine.new("InputObject")
		local arbiter = gestureOf(w.ctx)
		local origin = w.engine.types.Vector2.zero
		w.begin("armed")
		Verify.expect(arbiter.begin(pointer, w.source, origin, { pickup = "immediate" })):toBe(true)
		Verify.expect(arbiter.claim(pointer, w.source, "drag")):toBe(true)
		Verify.expect(arbiter.begin(pointer, w.focus, origin, { pickup = "immediate" })):toBe(false)
		Verify.expect(arbiter.claim(pointer, w.focus, "pan")):toBe(false)
		Verify.expect(assert(arbiter.get(pointer)).owner):toBe(w.source)
		w.session.finish(false)
		Verify.expect(arbiter.get(pointer)):toBeNil()
	end)
	h:case("world teardown cancels landing and pending return without leaks", function(test)
		local w = fixture(test)
		w.begin("armed")
		w.session.hover(w.target)
		w.session.commit(w.target)
		w.stop()
		w.engine.heartbeat:Fire(1)
		Verify.expect(w.session.state:peek()):toBeNil()
		Verify.expect(w.source:GetPivot()):toBe(w.engine.types.CFrame.new(0, 1, 0))
		Verify.expect(w.source:FindFirstChild("FacetWorldDragDetector")):toBeNil()
		Verify.expect(w.source:FindFirstChild("FacetWorldDragLift")):toBeNil()
		Verify.expect(w.source:FindFirstChild("FacetDragTravel")):toBeNil()
		Verify.expect(#w.drops):toBe(0)
		Verify.expect(w.counts().ends):toBe(1)
		Verify.expect(w.registrations()):toBe(0)
		Verify.expect(w.engine.census()):toEqual(w.nativeBeforeMount)
	end)
	h:case("world raycasts use the double's block geometry and source filter", function(test)
		local w = fixture(test, "none")
		local V3 = w.engine.types.Vector3
		local params = w.engine.types.RaycastParams.new()
		params.FilterDescendantsInstances = { w.source }
		local hit = w.world:Raycast(V3.new(4, 10, 0), V3.new(0, -20, 0), params)
		Verify.expect(assert(hit).Instance):toBe(w.target)
		Verify.expect(assert(hit).Position.Y):toBe(0.5)
	end)
	h:case("public world pickup and destination actions share completion", function(test)
		local w = fixture(test, "none")
		local controlOptions: Facet.ControlOptions = {
			types = w.engine.types,
			motionLevel = "none",
			userInputService = w.input,
			guiService = w.gui,
			inputParent = w.screen,
			services = { Workspace = w.world },
		}
		local UI = Facet.controls(w.runtime, controlOptions)
		local received: Facet.DropInfo? = nil
		local stop = w.runtime.mount(function()
			local Host = w.ctx.Host
			local pickup = Host.TextButton { Name = "PublicPickup" }
			local destination = Host.TextButton { Name = "PublicDestination" }
			local tile = Host.Part { Anchored = true, Parent = Facet.Compose.static(w.world) }
			local options: Facet.WorldDragOptions = {
				plane = w.engine.types.CFrame.identity,
				focusTarget = pickup,
			}
			UI.draggable(tile, { payload = "tile", world = options })
			local targetSpec: Facet.DropTargetSpec = {
				focusTarget = destination,
				worldPlacement = w.goal,
				onDrop = function(payload: unknown, info: Facet.DropInfo): boolean
					Verify.expect(payload):toBe("tile")
					received = info
					return true
				end,
			}
			UI.dropTarget(w.target, targetSpec)
			local panel: Native.FrameNativeProps = { pickup, destination }
			return Host.Frame(panel)
		end, w.screen)
		test:defer(stop)
		local pickup = assert(w.screen:FindFirstChild("PublicPickup", true))
		local destination = assert(w.screen:FindFirstChild("PublicDestination", true))
		w.engine.environment.poke(Roblox.assertInstance(w.gui), "SelectedObject", pickup)
		local actions: { Instance } = {}
		for _, node in w.screen:GetDescendants() do
			if
				node:IsA("InputAction")
				and node.Name == "WorldDragPickUp"
				and node.Parent
				and node.Parent:IsA("InputContext")
				and node.Parent.Enabled
			then
				table.insert(actions, node)
			end
		end
		Verify.expect(#actions):toBe(1)
		w.engine.environment.fire(Roblox.assertInstance(actions[1]), "Pressed")
		w.engine.environment.poke(Roblox.assertInstance(w.gui), "SelectedObject", destination)
		local drop = assert(w.screen:FindFirstChild("DragDrop", true))
		local event: InputObject = w.engine.new("InputObject")
		event.KeyCode = w.engine.types.Enum.KeyCode.ButtonA
		event.UserInputType = w.engine.types.Enum.UserInputType.Gamepad1
		w.engine.environment.fire(Roblox.assertInstance(drop), "Pressed", event)
		local info = assert(received)
		Verify.expect(info.mode):toBe("armed")
		Verify.expect(info.position):toBeNil()
		Verify.expect(info.source:IsA("BasePart")):toBe(true)
		Verify.expect(info.target):toBe(w.target)
		Verify.expect(info.worldPlacement):toBe(w.goal)
	end)
	h:case("a press on the world hit area drags past the threshold and leaves a tap to the button", function(test)
		local w = fixture(test, "none")
		local controlOptions: Facet.ControlOptions = {
			types = w.engine.types,
			motionLevel = "none",
			userInputService = w.input,
			guiService = w.gui,
			inputParent = w.screen,
			services = { Workspace = w.world },
		}
		local UI = Facet.controls(w.runtime, controlOptions)
		local starts, ended = 0, 0
		local stop = w.runtime.mount(function()
			local Host = w.ctx.Host
			local slot = Host.TextButton { Name = "SlotButton" }
			local tile = Host.Part { Anchored = true, Parent = Facet.Compose.static(w.world) }
			local options: Facet.WorldDragOptions = {
				plane = w.engine.types.CFrame.identity,
				focusTarget = slot,
				hitArea = slot,
			}
			UI.draggable(tile, {
				payload = "tile",
				world = options,
				onStart = function()
					starts += 1
				end,
				onEnd = function()
					ended += 1
				end,
			})
			local panel: Native.FrameNativeProps = { slot }
			return Host.Frame(panel)
		end, w.screen)
		test:defer(stop)
		local slot = Roblox.assertInstance(assert(w.screen:FindFirstChild("SlotButton", true)))
		local input = Roblox.assertInstance(w.input)
		local function pointer(x: number): { [string]: unknown }
			return {
				UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
				UserInputState = w.engine.types.Enum.UserInputState.Begin,
				Position = w.engine.types.Vector3.new(x, 10, 0),
			}
		end
		local function move(x: number): { [string]: unknown }
			return {
				UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
				Position = w.engine.types.Vector3.new(x, 10, 0),
			}
		end
		local function press(pointerObject: { [string]: unknown })
			local screen = pointerObject.Position
			pointerObject.Position = w.engine.types.Vector3.new(400, 300, 0)
			w.engine.environment.fire(slot, "InputBegan", pointerObject)
			pointerObject.Position = screen
			w.engine.environment.fire(input, "InputBegan", pointerObject, true)
		end
		local tap = pointer(10)
		press(tap)
		w.engine.environment.fire(input, "InputChanged", move(12))
		Verify.expect(starts):toBe(0)
		w.engine.environment.fire(input, "InputEnded", tap)
		Verify.expect(starts):toBe(0)
		local held = pointer(10)
		press(held)
		w.engine.environment.fire(input, "InputChanged", move(30))
		Verify.expect(starts):toBe(1)
		Verify.expect(ended):toBe(0)
		w.engine.environment.fire(input, "InputEnded", held)
		Verify.expect(ended):toBe(1)
	end)
	h:case("a tap on a Facet Button that is the hit area and focus target arms pickup", function(test)
		local w = fixture(test, "none")
		local controlOptions: Facet.ControlOptions = {
			types = w.engine.types,
			motionLevel = "none",
			userInputService = w.input,
			guiService = w.gui,
			inputParent = w.screen,
			services = { Workspace = w.world },
		}
		local UI = Facet.controls(w.runtime, controlOptions)
		local modes: { string } = {}
		local ends: { string } = {}
		local stop = w.runtime.mount(function()
			local Host = w.ctx.Host
			local slot = UI.Button "SlotButton" { label = "Tile" }
			local tile = Host.Part { Anchored = true, Parent = Facet.Compose.static(w.world) }
			local options: Facet.WorldDragOptions = {
				plane = w.engine.types.CFrame.identity,
				focusTarget = slot,
				hitArea = slot,
			}
			UI.draggable(tile, {
				payload = "tile",
				world = options,
				onStart = function(_payload: unknown, mode: "pointer" | "armed")
					table.insert(modes, mode)
				end,
				onEnd = function(_accepted: boolean, reason: string?)
					table.insert(ends, reason or "")
				end,
			})
			local panel: Native.FrameNativeProps = { slot }
			return Host.Frame(panel)
		end, w.screen)
		test:defer(stop)
		local slot = Roblox.assertInstance(assert(w.screen:FindFirstChild("SlotButton", true)))
		local input = Roblox.assertInstance(w.input)
		local tap = {
			UserInputType = w.engine.types.Enum.UserInputType.MouseButton1,
			UserInputState = w.engine.types.Enum.UserInputState.Begin,
			Position = w.engine.types.Vector3.new(10, 10, 0),
		}
		tap.Position = w.engine.types.Vector3.new(400, 300, 0)
		w.engine.environment.fire(slot, "InputBegan", tap)
		tap.Position = w.engine.types.Vector3.new(10, 10, 0)
		w.engine.environment.fire(input, "InputBegan", tap, true)
		w.engine.environment.fire(input, "InputChanged", {
			UserInputType = w.engine.types.Enum.UserInputType.MouseMovement,
			Position = w.engine.types.Vector3.new(10, 10, 0),
		})
		w.engine.environment.fire(slot, "Activated", tap, 1)
		w.engine.environment.fire(input, "InputEnded", tap)
		Verify.expect(#modes):toBe(1)
		Verify.expect(modes[1]):toBe("armed")
		Verify.expect(#ends):toBe(0)
	end)
	h:case(
		"an armed world drag from a SurfaceGui shows its status in the overlay and follows the input type",
		function(test)
			local w = fixture(test, "none")
			local overlay: Frame = w.engine.new("Frame")
			overlay.Parent = w.screen
			local controlOptions: Facet.ControlOptions = {
				types = w.engine.types,
				motionLevel = "none",
				userInputService = w.input,
				guiService = w.gui,
				inputParent = w.screen,
				overlayParent = overlay,
				services = { Workspace = w.world },
			}
			local UI = Facet.controls(w.runtime, controlOptions)
			local surface: SurfaceGui = w.engine.new("SurfaceGui")
			surface.Parent = w.screen
			local stop = w.runtime.mount(function()
				local Host = w.ctx.Host
				local slot = Host.TextButton { Name = "SlotButton" }
				local tile = Host.Part { Anchored = true, Parent = Facet.Compose.static(w.world) }
				local options: Facet.WorldDragOptions = {
					plane = w.engine.types.CFrame.identity,
					focusTarget = slot,
				}
				UI.draggable(tile, { payload = "tile", world = options })
				local panel: Native.FrameNativeProps = { slot }
				return Host.Frame(panel)
			end, surface)
			test:defer(stop)
			local Enum = w.engine.types.Enum
			w.engine.environment.poke(Roblox.assertInstance(w.input), "PreferredInput", Enum.PreferredInput.Gamepad)
			local pickup = assert(surface:FindFirstChild("SlotButton", true))
			w.engine.environment.poke(Roblox.assertInstance(w.gui), "SelectedObject", pickup)
			local action: Instance? = nil
			for _, node in w.screen:GetDescendants() do
				if node:IsA("InputAction") and node.Name == "WorldDragPickUp" then
					action = node
				end
			end
			w.engine.environment.fire(Roblox.assertInstance(assert(action)), "Pressed")
			local status = assert(overlay:FindFirstChild("DragStatusText", true))
			assert(status:IsA("TextLabel"))
			Verify.expect(surface:FindFirstChild("DragStatusText", true)):toBeNil()
			Verify.expect(string.find(status.Text, "A: drop", 1, true) ~= nil):toBe(true)
			w.engine.environment.poke(
				Roblox.assertInstance(w.input),
				"PreferredInput",
				Enum.PreferredInput.KeyboardAndMouse
			)
			Verify.expect((string.find(status.Text, "A: drop", 1, true))):toBeNil()
			Verify.expect(string.find(status.Text, "Enter: drop", 1, true) ~= nil):toBe(true)
		end
	)
	h:case("world pending completion validates once and ignores late replies", function(test)
		local w = fixture(test, "none")
		local legal = true
		local pending: Facet.DropInfo? = nil
		local rejections = 0
		local stop = w.runtime.mount(function()
			w.session.register(w.target, {
				worldPlacement = w.goal,
				accepts = function()
					return legal, "Occupied"
				end,
				onReject = function()
					rejections += 1
				end,
				onDrop = function(_payload: unknown, info: Facet.DropInfo): "pending"
					pending = info
					return "pending"
				end,
			})
			return w.runtime.constructors.Folder {}
		end, w.screen)
		test:defer(stop)
		w.begin("armed")
		w.session.commit(w.target)
		Verify.expect(w.target:GetAttribute("FacetDropState")):toBe("pending")
		Verify.expect(w.session.commit(w.target)):toBe(false)
		legal = false
		Verify.expect(assert(pending).complete(true)):toBe(false)
		Verify.expect(assert(pending).complete(true)):toBe(false)
		Verify.expect(rejections):toBe(1)
		Verify.expect(w.source:GetPivot()):toBe(w.engine.types.CFrame.new(0, 1, 0))
	end)
	h:case("world model pivots snap and restore together", function(test)
		local w = fixture(test, "none")
		local model: Model = w.engine.new("Model")
		model.Parent = w.world
		w.source.Parent = model
		local original = model:GetPivot()
		w.session.begin(model, { payload = "tile", world = w.options }, "armed", nil, false)
		w.session.hover(w.target)
		Verify.expect(model:GetPivot()):toBe(w.goal)
		w.session.finish(false)
		Verify.expect(model:GetPivot()):toBe(original)
	end)
	h:case("the engine reduced motion preference suppresses world lift", function(test)
		local w = fixture(test)
		w.engine.environment.poke(Roblox.assertInstance(w.gui), "ReducedMotionEnabled", true)
		w.begin("armed")
		w.engine.heartbeat:Fire(1)
		Verify.expect(w.source:GetPivot().Position.Y):toBe(1)
		w.session.commit(w.target)
		Verify.expect(#w.drops):toBe(1)
	end)
end
