--!strict
local Types = require("./types")
local Props = require("./camera_rig_types")
local Controls = require("./control_types")
local gestureOf = require("./gesture_service")
local sessionOf = require("./drag_session")
local Motion = require("./motion")
local Core = require("../vendor/compose/core")

return function(ctx: Types.Context, UI: Controls.Controls)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local V2, V3, CF, E = ctx.types.Vector2, ctx.types.Vector3, ctx.types.CFrame, ctx.types.Enum
	UI.cameraRig = function(spec: Props.CameraRigOptions): Props.CameraRig
		local owner = assert(Compose.currentOwner(), "cameraRig requires a Compose owner")
		local input = assert(ctx.config.userInputService, "cameraRig requires UserInputService")
		local workspace = assert(ctx.config.services.Workspace, "cameraRig requires Workspace")
		local arbiter, drag = gestureOf(ctx), sessionOf(ctx)
		local reduce = Motion.reduced(ctx)
		local yawBounds = spec.yawBounds or V2.new(-math.pi, math.pi)
		local pitchBounds = spec.pitchBounds or V2.new(-math.pi / 2 + 0.01, math.pi / 2 - 0.01)
		local distanceBounds, bounds = spec.distanceBounds, spec.focusBounds
		local function finite(n: number): boolean
			return n == n and math.abs(n) < math.huge
		end
		local function range(value: Vector2)
			assert(
				finite(value.X) and finite(value.Y) and value.X <= value.Y,
				"cameraRig requires finite ordered bounds"
			)
		end
		range(yawBounds)
		range(pitchBounds)
		range(distanceBounds)
		assert(distanceBounds.X > 0, "cameraRig distance must be positive")
		assert(pitchBounds.X > -math.pi / 2 and pitchBounds.Y < math.pi / 2, "cameraRig pitch must avoid the poles")
		for _, pair in
			{
				V2.new(bounds.min.X, bounds.max.X),
				V2.new(bounds.min.Y, bounds.max.Y),
				V2.new(bounds.min.Z, bounds.max.Z),
			}
		do
			range(pair)
		end
		local function clampFocus(point: Vector3): Vector3
			assert(finite(point.X) and finite(point.Y) and finite(point.Z), "cameraRig focus must be finite")
			return V3.new(
				math.clamp(point.X, bounds.min.X, bounds.max.X),
				math.clamp(point.Y, bounds.min.Y, bounds.max.Y),
				math.clamp(point.Z, bounds.min.Z, bounds.max.Z)
			)
		end
		local function clampOrbit(value: Vector3): Vector3
			assert(finite(value.X) and finite(value.Y) and finite(value.Z), "cameraRig orbit must be finite")
			return V3.new(
				math.clamp(value.X, yawBounds.X, yawBounds.Y),
				math.clamp(value.Y, pitchBounds.X, pitchBounds.Y),
				math.clamp(value.Z, distanceBounds.X, distanceBounds.Y)
			)
		end
		local function orbitOf(pose: Props.CameraPose): Vector3
			return clampOrbit(V3.new(pose.yaw, pose.pitch, pose.distance))
		end
		local initialFocus = clampFocus(spec.initial.focus)
		local initialOrbit = orbitOf(spec.initial)
		local presets: { [string]: Props.CameraPose } = {}
		local authoredPresets: { [string]: Props.CameraPose } = spec.presets or {}
		for name, pose in authoredPresets do
			local orbit = orbitOf(pose)
			presets[name] = { focus = clampFocus(pose.focus), yaw = orbit.X, pitch = orbit.Y, distance = orbit.Z }
		end
		local sensitivity, panSensitivity = spec.orbitSensitivity or 0.005, spec.panSensitivity or 0.01
		local orbitSpeed, zoomSpeed = spec.orbitSpeed or 1.5, spec.zoomSpeed or 8
		for _, value in { sensitivity, panSensitivity, orbitSpeed, zoomSpeed } do
			assert(finite(value) and value > 0, "cameraRig input speeds must be finite and positive")
		end
		local focus = Compose.cell(initialFocus)
		local preset = Compose.cell<<string?>>(nil)
		local focusRamp: Core.Ramp<Vector3> = runtime.ramp(initialFocus, { ease = ctx.motionEase("travel") })
		local orbitRamp: Core.Ramp<Vector3> = runtime.ramp(initialOrbit, { ease = ctx.motionEase("travel") })
		local targetFocus: Vector3 = initialFocus
		local targetOrbit: Vector3 = initialOrbit
		local internal = false
		local inputMotion = false
		local direct = Compose.cell(false)
		local halted = Compose.cell(false)
		local pointer: InputObject? = nil
		local lastPoint = V2.zero
		local touchContacts: { [InputObject]: boolean } = {}
		local uiContacts: { [InputObject]: boolean } = {}
		local worldDrags: { [Instance]: boolean } = {}
		local windowFocused = true
		local panActive, pinchActive = false, false
		local panCount = 0
		local panTranslation, pinchDistance = V2.zero, initialOrbit.Z
		local releaseOrbit, releaseFocus = V3.zero, V3.zero
		local lastMove = 0
		local keys: { [string]: boolean } = {}
		local stick = V2.zero
		local function now(): number
			local frames = runtime.host.frames
			return if frames then frames.now() else os.clock()
		end
		local function available(): boolean
			local gui = ctx.config.guiService
			return windowFocused
				and ctx.read(spec.enabled) ~= false
				and ctx.read(spec.blocked) ~= true
				and not input:GetFocusedTextBox()
				and not (gui and gui.SelectedObject)
				and not arbiter.busy()
				and drag.state:peek() == nil
				and next(worldDrags) == nil
				and next(uiContacts) == nil
		end
		local function inset(): Vector2
			local gui = ctx.config.guiService
			if gui then
				local top = gui:GetGuiInset()
				return top
			end
			return V2.zero
		end
		local function empty(point: Vector2): boolean
			for _, hit in spec.inputRoot:GetGuiObjectsAtPosition(point.X, point.Y) do
				if
					hit.Active
					or hit:IsA("GuiButton")
					or hit:IsA("TextBox")
					or hit:FindFirstAncestorWhichIsA("SurfaceGui") ~= nil
				then
					return false
				end
			end
			return true
		end
		local function clear()
			pointer, panActive, pinchActive = nil, false, false
			panCount = 0
			direct:set(false)
			table.clear(touchContacts)
			releaseOrbit, releaseFocus = V3.zero, V3.zero
		end
		local travelling = Compose.cell(false)
		local function request(point: Vector3, orbit: Vector3, duration: number)
			travelling:set(duration > 0)
			targetFocus = clampFocus(point)
			targetOrbit = clampOrbit(orbit)
			focusRamp.retarget(targetFocus, if reduce() then 0 else duration)
			orbitRamp.retarget(targetOrbit, if reduce() then 0 else duration)
			internal = true
			focus:set(targetFocus)
			internal = false
		end
		local painted = function(): (Vector3, Vector3)
			return focusRamp.value:peek(), orbitRamp.value:peek()
		end
		local function haltInput()
			if inputMotion then
				local point, orbit = painted()
				request(point, orbit, 0)
				halted:set(true)
				inputMotion = false
			end
			clear()
			table.clear(keys)
			stick = V2.zero
		end
		local function interrupt()
			inputMotion = true
			halted:set(false)
			local point, orbit = painted()
			request(point, orbit, 0)
			preset:set(nil)
			releaseOrbit, releaseFocus = V3.zero, V3.zero
			lastMove = now()
		end
		local function travel(point: Vector3, orbit: Vector3)
			clear()
			inputMotion = false
			halted:set(false)
			request(point, orbit, ctx.metric("motion.durations.cameraTravel"))
		end
		Compose.watch(function(use: Types.Use)
			local name = use(preset)
			if name then
				local pose = assert(presets[name], "cameraRig preset does not exist: " .. name)
				travel(pose.focus, orbitOf(pose))
			end
		end)
		Compose.watch(function(use: Types.Use)
			local point = use(focus)
			if not internal and point ~= targetFocus then
				preset:set(nil)
				travel(point, targetOrbit)
			end
		end)
		local function settle()
			if
				spec.inertia
				and not reduce()
				and available()
				and now() - lastMove <= ctx.metric("motion.durations.cameraInertia")
			then
				local duration = ctx.metric("motion.durations.cameraInertia")
				request(targetFocus + releaseFocus * duration, targetOrbit + releaseOrbit * duration, duration)
			end
			releaseOrbit, releaseFocus = V3.zero, V3.zero
		end
		local function move(delta: Vector2, pan: boolean, velocity: Vector2?)
			local orbitDelta = if pan then V3.zero else V3.new(-delta.X * sensitivity, delta.Y * sensitivity, 0)
			local yaw = targetOrbit.X
			local function panDelta(value: Vector2): Vector3
				return (V3.new(math.cos(yaw), 0, -math.sin(yaw)) * -value.X + V3.new(0, 1, 0) * value.Y)
					* panSensitivity
			end
			local focusDelta = if pan then panDelta(delta) else V3.zero
			local elapsed = now() - lastMove
			local speed = velocity or (if elapsed > 0 then delta / elapsed else V2.zero)
			releaseOrbit = if pan then V3.zero else V3.new(-speed.X * sensitivity, speed.Y * sensitivity, 0)
			releaseFocus = if pan then panDelta(speed) else V3.zero
			lastMove = now()
			request(targetFocus + focusDelta, targetOrbit + orbitDelta, 0)
		end
		local detectorOwners: { [Instance]: Core.Owner } = {}
		local function observeDetector(node: Instance)
			if not node:IsA("DragDetector") or detectorOwners[node] then
				return
			end
			local scope = Compose.owner.createChild(owner)
			detectorOwners[node] = scope
			Compose.withOwner(scope, function()
				runtime.connect(node, "DragStart", function()
					worldDrags[node] = true
					haltInput()
				end)
				runtime.connect(node, "DragEnd", function()
					worldDrags[node] = nil
				end)
				Compose.cleanup(function()
					worldDrags[node], detectorOwners[node] = nil, nil
				end)
			end)
		end
		for _, node in workspace:GetDescendants() do
			observeDetector(node)
		end
		runtime.connect(workspace, "DescendantAdded", observeDetector)
		runtime.connect(workspace, "DescendantRemoving", function(node: Instance)
			local scope = detectorOwners[node]
			if scope then
				Compose.owner.dispose(scope)
			end
		end)
		runtime.connect(input, "InputBegan", function(event: InputObject, processed: boolean)
			local kind = event.UserInputType
			if
				kind ~= E.UserInputType.Touch
				and kind ~= E.UserInputType.MouseButton1
				and kind ~= E.UserInputType.MouseButton2
			then
				return
			end
			local point = V2.new(event.Position.X, event.Position.Y)
			if processed or not empty(point) then
				uiContacts[event] = true
				haltInput()
				return
			end
			if not available() then
				return
			end
			if event.UserInputType == E.UserInputType.Touch then
				touchContacts[event] = true
			elseif
				event.UserInputType == E.UserInputType.MouseButton1
				or event.UserInputType == E.UserInputType.MouseButton2
			then
				interrupt()
				pointer, lastPoint = event, point
				direct:set(true)
			end
		end)
		runtime.connect(input, "InputChanged", function(event: InputObject, processed: boolean)
			if
				event.UserInputType ~= E.UserInputType.MouseMovement
				and event.UserInputType ~= E.UserInputType.MouseWheel
			then
				return
			end
			if processed or not available() then
				haltInput()
				return
			end
			if event.UserInputType == E.UserInputType.MouseMovement and pointer then
				local point = V2.new(event.Position.X, event.Position.Y)
				if not empty(point) then
					clear()
					return
				end
				move(point - lastPoint, false)
				lastPoint = point
			elseif event.UserInputType == E.UserInputType.MouseWheel and empty(input:GetMouseLocation() - inset()) then
				interrupt()
				request(targetFocus, targetOrbit - V3.new(0, 0, event.Position.Z * zoomSpeed), 0)
			end
		end)
		runtime.connect(input, "InputEnded", function(event: InputObject)
			uiContacts[event] = nil
			touchContacts[event] = nil
			if event == pointer then
				pointer = nil
				settle()
				direct:set(panActive or pinchActive)
			end
		end)
		local function ownsTouches(points: { Vector2 }, processed: boolean): boolean
			if processed or not available() or #points == 0 then
				return false
			end
			local count = 0
			for _ in touchContacts do
				count += 1
			end
			if count ~= #points then
				return false
			end
			for _, point in points do
				if not empty(point - inset()) then
					return false
				end
			end
			return true
		end
		runtime.connect(
			input,
			"TouchPan",
			function(
				points: { Vector2 },
				translation: Vector2,
				velocity: Vector2,
				state: Enum.UserInputState,
				processed: boolean
			)
				if state == E.UserInputState.End or state == E.UserInputState.Cancel then
					if panActive and state == E.UserInputState.End then
						settle()
					end
					panActive = false
					direct:set(pointer ~= nil or pinchActive)
					return
				end
				if not ownsTouches(points, processed) then
					clear()
					return
				end
				if state == E.UserInputState.Begin or panCount ~= #points then
					interrupt()
					panTranslation, panActive = translation, true
					panCount = #points
					direct:set(true)
				elseif panActive then
					move(translation - panTranslation, #points >= 2, velocity)
					panTranslation = translation
				end
			end
		)
		runtime.connect(
			input,
			"TouchPinch",
			function(
				points: { Vector2 },
				scale: number,
				_velocity: number,
				state: Enum.UserInputState,
				processed: boolean
			)
				if state == E.UserInputState.End or state == E.UserInputState.Cancel then
					pinchActive = false
					direct:set(pointer ~= nil or panActive)
					return
				end
				if #points < 2 or not ownsTouches(points, processed) then
					clear()
					return
				end
				if state == E.UserInputState.Begin then
					interrupt()
					pinchDistance, pinchActive = targetOrbit.Z, true
					direct:set(true)
				elseif pinchActive and finite(scale) and scale > 0 then
					request(targetFocus, V3.new(targetOrbit.X, targetOrbit.Y, pinchDistance / scale), 0)
				end
			end
		)
		local active = Compose.cell(available())
		local context = Host.InputContext "FacetCameraRig" {
			Parent = Compose.static(spec.inputRoot),
			Priority = 250,
			Sink = true,
			Enabled = active,
		}
		for _, entry in
			{
				{ name = "CameraLeft", keys = { E.KeyCode.Left, E.KeyCode.A } },
				{ name = "CameraRight", keys = { E.KeyCode.Right, E.KeyCode.D } },
				{ name = "CameraUp", keys = { E.KeyCode.Up, E.KeyCode.W } },
				{ name = "CameraDown", keys = { E.KeyCode.Down, E.KeyCode.S } },
				{ name = "CameraIn", keys = { E.KeyCode.Equals, E.KeyCode.KeypadPlus, E.KeyCode.ButtonR2 } },
				{ name = "CameraOut", keys = { E.KeyCode.Minus, E.KeyCode.KeypadMinus, E.KeyCode.ButtonL2 } },
			}
		do
			local bindings: Types.InputActionNativeProps = {
				Name = entry.name,
				Parent = Compose.static(context),
				Type = E.InputActionType.Bool,
				Pressed = function()
					if available() then
						interrupt()
						keys[entry.name] = true
					end
				end,
				Released = function()
					keys[entry.name] = nil
				end,
			}
			for _, key in entry.keys do
				bindings[#bindings + 1] = Host.InputBinding { KeyCode = key }
			end
			Host.InputAction(bindings)
		end
		Host.InputAction "CameraOrbit" {
			Parent = Compose.static(context),
			Type = E.InputActionType.Direction2D,
			StateChanged = function(value: unknown)
				if typeof(value) == "Vector2" then
					stick = if available() then value else V2.zero
				end
			end,
			Released = function()
				stick = V2.zero
			end,
			Host.InputBinding { KeyCode = E.KeyCode.Thumbstick2 },
		}
		local spring = ctx.motionSpring("camera")
		local smoothFocus = runtime.spring(function(use: Types.Use): Vector3
			return use(focusRamp.value)
		end, {
			period = spring.period,
			damping = spring.damping,
			reducedMotion = function(use: Types.Use): boolean
				return reduce(use) or spec.smoothing ~= true or use(direct) or use(halted) or use(travelling)
			end,
		})
		local smoothOrbit = runtime.spring(function(use: Types.Use): Vector3
			return use(orbitRamp.value)
		end, {
			period = spring.period,
			damping = spring.damping,
			reducedMotion = function(use: Types.Use): boolean
				return reduce(use) or spec.smoothing ~= true or use(direct) or use(halted) or use(travelling)
			end,
		})
		local state = Compose.formula(function(use: Types.Use): Props.CameraPose
			local orbit = clampOrbit(if reduce(use) then use(orbitRamp.value) else use(smoothOrbit))
			return {
				focus = clampFocus(if reduce(use) then use(focusRamp.value) else use(smoothFocus)),
				yaw = orbit.X,
				pitch = orbit.Y,
				distance = orbit.Z,
			}
		end)
		painted = function(): (Vector3, Vector3)
			local pose = state:peek()
			return pose.focus, orbitOf(pose)
		end
		local selection = if ctx.config.guiService then ctx.observe.SelectedObject(ctx.config.guiService) else nil
		Compose.watch(function(use: Types.Use)
			if
				ctx.read(spec.enabled, use) == false
				or ctx.read(spec.blocked, use) == true
				or use(drag.state) ~= nil
				or (selection and use(selection) ~= nil)
			then
				haltInput()
			end
		end)
		Compose.watch(function(use: Types.Use)
			if reduce(use) then
				if inputMotion then
					haltInput()
				else
					request(targetFocus, targetOrbit, 0)
				end
			end
		end)
		runtime.connect(input, "TextBoxFocused", haltInput)
		local camera = Compose.formula(function(use: Types.Use): CFrame
			local pose = use(state)
			local offset = V3.new(
				math.sin(pose.yaw) * math.cos(pose.pitch),
				math.sin(pose.pitch),
				math.cos(pose.yaw) * math.cos(pose.pitch)
			) * pose.distance
			return CF.lookAt(pose.focus + offset, pose.focus)
		end)
		local function render(delta: number)
			local allowed = available()
			active:set(allowed)
			if not allowed then
				haltInput()
				return
			end
			if reduce() then
				request(targetFocus, targetOrbit, 0)
			end
			local function down(name: string): number
				return if keys[name] then 1 else 0
			end
			local x, y = down("CameraRight") - down("CameraLeft"), down("CameraUp") - down("CameraDown")
			local z = down("CameraOut") - down("CameraIn")
			local axis = if stick.Magnitude > 0.15 then stick else V2.zero
			if x ~= 0 or y ~= 0 or z ~= 0 or axis.Magnitude > 0 then
				inputMotion = true
				halted:set(false)
				preset:set(nil)
				request(
					targetFocus,
					targetOrbit + V3.new(-(x + axis.X) * orbitSpeed, (y + axis.Y) * orbitSpeed, z * zoomSpeed) * delta,
					0
				)
			end
		end
		runtime.connect(input, "WindowFocusReleased", function()
			windowFocused = false
			haltInput()
			table.clear(uiContacts)
		end)
		runtime.connect(input, "WindowFocused", function()
			windowFocused = true
		end)
		runtime.connect(input, "GamepadDisconnected", function()
			stick = V2.zero
			table.clear(keys)
		end)
		local run = ctx.config.services.RunService
		if run then
			runtime.connect(run, "PreRender", render)
		elseif runtime.host.frames then
			Compose.cleanup(runtime.host.frames.onFrame(render))
		end
		Compose.cleanup(clear)
		return {
			camera = camera,
			state = state,
			focus = focus,
			preset = preset,
			reset = function()
				preset:set(nil)
				travel(initialFocus, initialOrbit)
			end,
		}
	end
end
