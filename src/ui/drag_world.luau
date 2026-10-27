--!strict
local Types = require("./types")
local Env = require("./environment_types")
local Drag = require("./drag_types")
local gestureOf = require("./gesture_service")
local activation = require("./activation")

return function(ctx: Types.Context, source: BasePart | Model, spec: Env.DraggableSpec, service: Drag.Service)
	local options = assert(spec.world, "Facet world draggable needs world.plane")
	assert(options.focusTarget, "Facet world draggable needs world.focusTarget")
	assert(
		options.lift == nil or (options.lift >= 0 and options.lift < math.huge),
		"Facet world lift must be finite and nonnegative"
	)
	local function anchored(part: BasePart)
		assert(part.Anchored, "Facet world draggable parts must be anchored")
	end
	if source:IsA("BasePart") then
		anchored(source)
	end
	for _, part in source:GetDescendants() do
		if part:IsA("BasePart") then
			anchored(part)
		end
	end
	local Compose, E = ctx.Compose, ctx.types.Enum
	local input, gui = ctx.config.userInputService, ctx.config.guiService
	local arbiter = gestureOf(ctx)
	local pressed: InputObject? = nil
	local detected = false
	local function held(): boolean
		local session = service.state:peek()
		return session ~= nil and session.source == source
	end
	Compose.watch(function(use)
		local session = use(service.state)
		if session == nil or session.source ~= source then
			arbiter.cancelOwner(source)
		end
	end)
	local function enabled(use: Types.Use?): boolean
		return (spec.enabled == nil or ctx.read(spec.enabled, use)) and (spec.valid == nil or spec.valid())
	end
	local owned: Drag.SourceSpec = {
		payload = spec.payload,
		world = options,
		enabled = spec.enabled,
		statusLabels = spec.statusLabels,
		operations = spec.operations,
		onStart = spec.onStart,
	}
	owned.valid = function()
		return source.Parent ~= nil and enabled(nil)
	end
	owned.onEnd = function(accepted, reason)
		arbiter.cancelOwner(source)
		pressed = nil
		if spec.onEnd then
			spec.onEnd(accepted, reason)
		end
	end
	service.own(source)
	local function begin(mode: "pointer" | "armed", pointer: InputObject?)
		if service.state:peek() or not enabled(nil) then
			return
		end
		service.begin(source, owned, mode, pointer, false)
	end
	local function at(pointer: InputObject): Vector2
		return ctx.types.Vector2.new(pointer.Position.X, pointer.Position.Y)
	end
	local function pointerHit(pointer: InputObject): boolean
		local players = ctx.config.services.Players
		local player = players and players.LocalPlayer
		local playerGui = player and player:FindFirstChildWhichIsA("PlayerGui")
		local position = at(pointer)
		if playerGui then
			for _, node in playerGui:GetGuiObjectsAtPosition(position.X, position.Y) do
				local transparency = node:GetStyled("BackgroundTransparency")
				if
					node:GetAttribute("FacetDropPassThrough") ~= true
					and (
						node.Active
						or node:IsA("GuiButton")
						or node:IsA("TextBox")
						or (type(transparency) == "number" and transparency < 1)
					)
				then
					return false
				end
			end
		end
		local world = ctx.config.services.Workspace
		local camera = world and world.CurrentCamera
		if not camera then
			return false
		end
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		local hit = assert(world):Raycast(ray.Origin, ray.Direction * 10000)
		return hit ~= nil and (rawequal(hit.Instance, source) or hit.Instance:IsDescendantOf(source))
	end
	local function embodied(): boolean
		local players = ctx.config.services.Players
		local player = players and players.LocalPlayer
		return player ~= nil and player.Character ~= nil
	end
	local function claim(pointer: InputObject): boolean
		if not pointerHit(pointer) then
			return false
		end
		local position = at(pointer)
		if
			not arbiter.begin(pointer, source, position, { pickup = "immediate" })
			or not arbiter.claim(pointer, source, "drag")
		then
			return false
		end
		pressed = pointer
		activation.consume(pointer)
		return true
	end
	local detector = ctx.Host.DragDetector {
		Name = "FacetWorldDragDetector",
		RunLocally = true,
		DragStyle = E.DragDetectorDragStyle.TranslatePlane,
		ResponseStyle = E.DragDetectorResponseStyle.Custom,
		PermissionPolicy = E.DragDetectorPermissionPolicy.Everybody,
		Axis = options.plane.UpVector,
		MaxActivationDistance = options.maxActivationDistance,
		Enabled = function(use)
			local session = use(service.state)
			return enabled(use)
				and (session == nil or (session.source == source and session.mode == "pointer" and not session.pending))
		end,
		DragStart = function()
			if not input or service.state:peek() then
				return
			end
			detected = true
			if not pressed then
				for _, pointer in input:GetMouseButtonsPressed() do
					if pointer.UserInputType == E.UserInputType.MouseButton1 and claim(pointer) then
						break
					end
				end
			end
			if pressed and claim(pressed) then
				begin("pointer", pressed)
			end
		end,
		DragEnd = function()
			detected = false
			if held() then
				if pressed and pressed.UserInputState == E.UserInputState.Cancel then
					service.finish(false, "Cancelled")
				else
					service.commit(nil)
				end
			end
			arbiter.cancelOwner(source)
			pressed = nil
		end,
	}
	detector.Parent = source
	if input then
		ctx.runtime.connect(input, "InputBegan", function(pointer: InputObject, processed: boolean)
			local session = service.state:peek()
			if
				session
				and session.source == source
				and session.mode == "pointer"
				and pointer.UserInputType == E.UserInputType.Touch
				and pressed ~= nil
				and pressed.UserInputType ~= E.UserInputType.Touch
			then
				pressed = pointer
				return
			end
			if
				(not processed or detected)
				and enabled(nil)
				and service.state:peek() == nil
				and (pointer.UserInputType == E.UserInputType.MouseButton1 or pointer.UserInputType == E.UserInputType.Touch)
				and pointerHit(pointer)
			then
				pressed = pointer
				if (detected or not embodied()) and claim(pointer) then
					begin("pointer", pointer)
				end
			end
		end)
		ctx.runtime.connect(input, "InputChanged", function(pointer: InputObject)
			if
				held()
				and pressed
				and (
					pointer == pressed
					or (
						pressed.UserInputType == E.UserInputType.MouseButton1
						and pointer.UserInputType == E.UserInputType.MouseMovement
					)
				)
			then
				service.update(at(pointer))
			end
		end)
		ctx.runtime.connect(input, "InputEnded", function(pointer: InputObject)
			if pointer ~= pressed then
				return
			end
			if held() then
				if pointer.UserInputState == E.UserInputState.Cancel then
					service.finish(false, "Cancelled")
				else
					if pointer.UserInputType == E.UserInputType.Touch then
						service.update(at(pointer))
					end
					service.commit(nil)
				end
			end
			arbiter.cancelOwner(source)
			pressed = nil
			detected = false
		end)
		ctx.runtime.connect(input, "WindowFocusReleased", function()
			arbiter.cancelOwner(source)
			pressed = nil
			detected = false
			if held() then
				service.finish(false, "Window lost focus")
			end
		end)
	end
	local focus = options.focusTarget
	local selected = if gui then ctx.observe.SelectedObject(gui) else nil
	if focus then
		local function pickUp(): boolean
			begin("armed", nil)
			return held()
		end
		Compose.cleanup(activation.intercept(focus, pickUp))
		ctx.action(focus, "WorldDragPickUp", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
			return use(service.state) == nil and enabled(use) and selected ~= nil and use(selected) == focus
		end, function()
			pickUp()
		end, { priority = 250 })
	end
	if selected then
		Compose.watch(function(use)
			local target = use(selected)
			local session = service.state:peek()
			if session and session.source == source and session.mode == "armed" then
				service.hover(service.targetOf(target), nil)
			end
		end)
	end
	ctx.action(focus or source, "WorldDragCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use)
		local session = use(service.state)
		return session ~= nil and session.source == source
	end, function()
		service.finish(false, "Cancelled")
	end, { priority = 250 })
	Compose.cleanup(function()
		arbiter.cancelOwner(source)
		if held() then
			service.finish(false, "The source was removed")
		end
	end)
end
