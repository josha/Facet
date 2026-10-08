--!strict
local Shared = require("./types")
local Env = require("./environment_types")
local activation = require("./activation")
local DragTypes = require("./drag_types")
local sessionOf = require("./drag_session")
local gestureOf = require("./gesture_service")
local Gesture = require("./gesture_arbitration")
local scrollLock = require("./scroll_lock")
local pointerOf = require("./drag_pointer")

return function(ctx: Shared.Context, UI: Env.EnvironmentControls)
	local Compose, Host, E = ctx.Compose, ctx.Host, ctx.types.Enum
	local service = sessionOf(ctx)
	local arbiter = gestureOf(ctx)
	UI.gestureArbiter = function(surface: GuiObject): Gesture.Binding
		assert(Compose.currentOwner() ~= nil, "Facet UI.gestureArbiter must run inside a Compose owner")
		Compose.cleanup(function()
			arbiter.cancelOwner(surface)
		end)
		return {
			begin = function(pointer, position, options)
				return arbiter.begin(pointer, surface, position, options)
			end,
			move = arbiter.move,
			claim = function(pointer, kind)
				return arbiter.claim(pointer, surface, kind)
			end,
			get = arbiter.get,
			finish = function(pointer, cancelled)
				return arbiter.finish(pointer, surface, cancelled)
			end,
		}
	end
	local input, gui = ctx.config.userInputService, ctx.config.guiService
	local function keyActivation(node: GuiObject, callback: () -> boolean): boolean
		if not activation.marked(node) then
			return false
		end
		Compose.cleanup(activation.intercept(node, function(value: unknown): boolean
			local kind = if value then (value :: InputObject).UserInputType else nil
			if kind == E.UserInputType.MouseButton1 or kind == E.UserInputType.Touch then
				return false
			end
			return callback()
		end))
		return true
	end
	UI.draggable = function(source: GuiObject, spec: Env.DraggableSpec)
		assert(Compose.currentOwner() ~= nil, "Facet UI.draggable must run inside a component or Compose owner")
		assert(spec.payload ~= nil, "Facet UI.draggable needs a payload")
		assert(
			spec.touchPickup == nil or spec.touchPickup == "longPress" or spec.touchPickup == "immediate",
			"Facet UI.draggable touchPickup must be longPress or immediate"
		)
		assert(
			spec.touchDragAxis == nil
				or spec.touchDragAxis == "X"
				or spec.touchDragAxis == "Y"
				or spec.touchDragAxis == "XY",
			"Facet UI.draggable touchDragAxis must be X, Y or XY"
		)
		service.own(source)
		local pressed: InputObject? = nil
		local origin: Vector2? = nil
		local active, dragged = false, false
		local scrolling = false
		local eligible: boolean? = nil
		local releaseScrollers: (() -> ())? = nil
		local function held(): boolean
			local current = service.state:peek()
			return current ~= nil and current.source == source
		end
		local function enabled(use: Shared.Use?): boolean
			return spec.enabled == nil or ctx.read(spec.enabled, use) == true
		end
		local function unlock()
			if releaseScrollers then
				releaseScrollers()
				releaseScrollers = nil
			end
		end
		local ownedSpec = table.clone(spec) :: DragTypes.SourceSpec
		ownedSpec.valid = function()
			return enabled(nil) and (spec.valid == nil or spec.valid())
		end
		ownedSpec.onEnd = function(accepted, reason)
			active = false
			unlock()
			if spec.onEnd then
				spec.onEnd(accepted, reason)
			end
		end
		local function begin(mode: "pointer" | "armed")
			service.begin(
				source,
				ownedSpec,
				mode,
				pressed,
				nil,
				if origin then { position = origin, source = source } else nil
			)
			active = held()
			if not active then
				unlock()
			end
			dragged = true
		end
		local function lock()
			if not releaseScrollers then
				releaseScrollers = scrollLock.holdAncestors(source)
			end
		end
		local function contact(position: Vector2): Vector2
			return if pressed and pressed.UserInputType == E.UserInputType.Touch
				then ctx.types.Vector2.new(pressed.Position.X, pressed.Position.Y)
				else position
		end
		local detector = Host.UIDragDetector({
			Name = "FacetDragDetector",
			DragStyle = E.UIDragDetectorDragStyle.TranslatePlane,
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use)
				return enabled(use) and ctx.effectiveInput()(use) ~= "Touch"
			end,
			DragStart = function(position)
				origin = if eligible == false then nil else pointerOf(ctx, position)
			end,
			DragContinue = function(position)
				position = pointerOf(ctx, position)
				if not active and origin and (position - origin).Magnitude >= 6 and enabled(nil) then
					local touch = pressed ~= nil and pressed.UserInputType == E.UserInputType.Touch

					if not touch and (pressed == nil or arbiter.move(pressed, position) == "drag") then
						lock()
						begin("pointer")
					end
				end
				if active then
					service.update(position)
				end
			end,
			DragEnd = function(position)
				position = pointerOf(ctx, position)
				local tap = origin ~= nil and not dragged and (position - origin).Magnitude < 6
				origin = nil
				if active then
					service.update(position)
					service.commit(nil)
				elseif tap and enabled(nil) then
					if activation.trigger(source, pressed, 1) then
						activation.consume(pressed)
					end
				end
			end,
		})
		detector.Parent = source
		ctx.runtime.connect(source, "InputBegan", function(value: InputObject)
			if value.UserInputType == E.UserInputType.MouseButton1 or value.UserInputType == E.UserInputType.Touch then
				if active then
					return
				end
				eligible = false
				local at = ctx.types.Vector2.new(value.Position.X, value.Position.Y)
				local hit = spec.hitArea or source
				local offset, size = at - hit.AbsolutePosition, hit.AbsoluteSize
				if spec.hitArea and (offset.X < 0 or offset.Y < 0 or offset.X >= size.X or offset.Y >= size.Y) then
					return
				end
				if
					not enabled(nil)
					or not arbiter.begin(value, source, at, {
						pickup = if value.UserInputType == E.UserInputType.Touch
							then spec.touchPickup or "longPress"
							else "immediate",
						axis = spec.touchDragAxis or "XY",
						scroll = source:FindFirstAncestorWhichIsA("ScrollingFrame") ~= nil,
					})
				then
					return
				end
				eligible = true
				activation.release(value)
				pressed, dragged, scrolling = value, false, false
				origin = at
			end
		end)
		ctx.runtime.connect(source, "TouchLongPress", function(positions: { Vector2 }, phase: Enum.UserInputState)
			if phase ~= E.UserInputState.Begin or not enabled(nil) or active or spec.touchPickup == "immediate" then
				return
			end
			if not pressed or not arbiter.claim(pressed, source, "drag") then
				return
			end
			lock()
			begin("pointer")
			if positions[1] then
				service.update(contact(pointerOf(ctx, positions[1])))
			end
		end)
		if input then
			ctx.runtime.connect(input, "InputChanged", function(value: InputObject)
				if value ~= pressed or value.UserInputType ~= E.UserInputType.Touch then
					return
				end
				local position = ctx.types.Vector2.new(value.Position.X, value.Position.Y)
				local kind = arbiter.move(value, position)
				if not active and kind == "drag" and enabled(nil) then
					lock()
					begin("pointer")
				elseif kind == "scroll" or kind == "pan" then
					scrolling = true
				end
				if active then
					service.update(position)
				end
			end)
			ctx.runtime.connect(input, "InputEnded", function(value: InputObject)
				if value == pressed then
					arbiter.finish(value, source, value.UserInputState == E.UserInputState.Cancel)
				end
				if value == pressed and value.UserInputState == E.UserInputState.Cancel then
					origin, eligible = nil, false
					dragged, scrolling = true, true
					activation.consume(value)
					if held() then
						service.finish(false, "Cancelled")
					end
				end
				if active and value == pressed and value.UserInputType == E.UserInputType.Touch then
					service.update(ctx.types.Vector2.new(value.Position.X, value.Position.Y))
					service.commit(nil)
				end
				if
					value == pressed
					and spec.armOnTap
					and value.UserInputState ~= E.UserInputState.Cancel
					and value.UserInputType == E.UserInputType.Touch
					and not dragged
					and not scrolling
					and not active
					and service.state:peek() == nil
				then
					begin("armed")
				end
			end)
			ctx.runtime.connect(input, "WindowFocusReleased", function()
				arbiter.cancelOwner(source)
				pressed = nil
				if held() then
					service.finish(false, "Window lost focus")
				end
			end)
		end
		local selected = if gui then ctx.observe.SelectedObject(gui) else nil
		if selected then
			Compose.watch(function(use)
				local target = use(selected)
				local current = service.state:peek()
				if current and current.source == source and current.mode == "armed" then
					service.hover(service.targetOf(target), nil)
				end
			end)
		end
		local function pickUp(): boolean
			if service.state:peek() ~= nil or not enabled(nil) then
				return false
			end
			begin("armed")
			return true
		end
		if not keyActivation(source, pickUp) then
			ctx.action(source, "DragPickUp", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
				local node = if selected then use(selected) else nil
				return use(service.state) == nil
					and enabled(use)
					and node ~= nil
					and (node == source or node:IsDescendantOf(source))
			end, pickUp, { priority = 250 })
		end
		ctx.action(source, "DragCancel", { E.KeyCode.Escape, E.KeyCode.ButtonB }, function(use)
			local current = use(service.state)
			return current ~= nil and current.source == source
		end, function()
			service.finish(false, "Cancelled")
		end, { priority = 250 })
		Compose.cleanup(function()
			arbiter.cancelOwner(source)
			if held() then
				service.finish(false, "The source was removed")
			end
			unlock()
		end)
	end
	UI.dropTarget = function(target: Env.DropDestination, spec: Env.DropTargetSpec)
		assert(Compose.currentOwner() ~= nil, "Facet UI.dropTarget must run inside a component or Compose owner")
		assert(type(spec.onDrop) == "function", "Facet UI.dropTarget needs onDrop")
		service.register(target, (spec :: unknown) :: DragTypes.TargetSpec)
		local focusTarget = spec.focusTarget or (if target:IsA("GuiObject") then target else nil)
		if not focusTarget then
			return
		end
		local function drop(): boolean
			local current = service.state:peek()
			if not current or current.mode ~= "armed" then
				return false
			end
			service.commit(target)
			return true
		end
		ctx.runtime.connect(focusTarget, "InputBegan", function(value: InputObject)
			if value.UserInputType == E.UserInputType.MouseButton1 or value.UserInputType == E.UserInputType.Touch then
				if drop() then
					activation.consume(value)
				end
			end
		end)
		if not keyActivation(focusTarget, drop) then
			local selected = if gui then ctx.observe.SelectedObject(gui) else nil
			ctx.action(focusTarget, "DragDrop", { E.KeyCode.Return, E.KeyCode.ButtonA }, function(use)
				local current = use(service.state)
				return current ~= nil and current.mode == "armed" and selected ~= nil and use(selected) == focusTarget
			end, drop, { priority = 250 })
		end
	end
end
