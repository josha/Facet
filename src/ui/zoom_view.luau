--!strict
local Shared = require("./types")
local Types = require("./zoom_travel_types")
local geometry = require("./zoom_geometry")
local Motion = require("./motion")
local reducedMotion = Motion.reduced
local sessionOf = require("./drag_session")
local arbiterOf = require("./gesture_service")
local scrollLock = require("./scroll_lock")
local activation = require("./activation")
local ControlTypes = require("./control_types")
local ZoomTravelProps = require("./zoom_travel_props")

return function(ctx: Shared.Context, UI: ControlTypes.Controls)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2, E = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Enum
	UI.ZoomView = ctx.construct("ZoomView", function(spec: ZoomTravelProps.ZoomViewProps): ScrollingFrame
		assert(type(spec.content) == "function", "Facet UI.ZoomView: content is required")
		local function positive(value: number): boolean
			return value > 0 and value < math.huge
		end
		local maximum = spec.maxZoom or 4
		assert(positive(maximum), "Facet UI.ZoomView: maxZoom must be positive and finite")
		assert(spec.minZoom == nil or positive(spec.minZoom), "Facet UI.ZoomView: minZoom must be positive and finite")
		assert(spec.minZoom == nil or spec.minZoom <= maximum, "Facet UI.ZoomView: minZoom exceeds maxZoom")
		assert(
			spec.doubleTapZoom == nil or positive(spec.doubleTapZoom),
			"Facet UI.ZoomView: doubleTapZoom must be positive and finite"
		)
		local zoom: Shared.Value<number> = spec.zoom or Compose.cell(1)
		assert(positive(zoom:peek()), "Facet UI.ZoomView: zoom must be positive and finite")
		local reduce = reducedMotion(ctx)
		local ramp = runtime.ramp(zoom:peek(), { ease = ctx.motionEase("zoom") })
		local translation = Motion.forValue(ctx, V2.zero).ramp(V2.zero, { ease = ctx.motionEase("zoom") })
		local drag = sessionOf(ctx)
		local arbiter = arbiterOf(ctx)
		local contacts: { [InputObject]: boolean } = {}
		local capturedContacts: { [InputObject]: boolean } = {}
		local capturedSource: Instance? = nil
		local root: ScrollingFrame
		local contentPoint, screenPoint = V2.zero, V2.zero
		local applied = zoom:peek()
		local deferred: number? = nil
		local frozen = false
		local frozenCanvas = V2.zero
		local measured = false
		local fittedArea: Vector2? = nil
		local proposing = false
		local applying = false
		local captureTarget: number? = nil
		local stick = V2.zero
		local input, gui = ctx.config.userInputService, ctx.config.guiService
		local effectiveInput = ctx.effectiveInput()
		local function extent(): Vector2
			local size = ctx.read<<Vector2>>(spec.contentSize)
			assert(
				positive(size.X) and positive(size.Y),
				"Facet UI.ZoomView: contentSize must have positive finite axes"
			)
			return size
		end
		extent()
		local content = spec.content()
		local scaler = Host.UIScale { Name = "ZoomScale", Scale = applied }
		local canvas = Host.Frame {
			Name = "ZoomContent",
			BackgroundTransparency = 1,
			Size = function(use: Shared.Use): UDim2
				local size = ctx.read<<Vector2>>(spec.contentSize, use)
				return D2.fromOffset(size.X, size.Y)
			end,
			scaler,
			content,
		}
		local props = ctx.props(spec, {
			"contentSize",
			"content",
			"zoom",
			"focus",
			"minZoom",
			"maxZoom",
			"doubleTapZoom",
			"enabled",
			"controls",
			"followTransition",
		}, {
			Name = "ZoomView",
			Size = D2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticCanvasSize = E.AutomaticSize.None,
			ScrollingDirection = E.ScrollingDirection.XY,
			ElasticBehavior = E.ElasticBehavior.Never,
			ScrollBarThickness = 0,
			Selectable = true,
			Active = true,
			ClipsDescendants = true,
		}) :: Shared.ScrollingFrameProps
		props.ScrollingEnabled = function(use: Shared.Use): boolean
			return ctx.read(spec.enabled, use) ~= false and ctx.read(spec.ScrollingEnabled, use) ~= false
		end
		props[#props + 1] = canvas
		root = Host.ScrollingFrame(props)
		root:SetAttribute("FacetSelectionOwner", true)
		local unit = ctx.layoutUnit(root)
		local function window(): Vector2
			return root.AbsoluteWindowSize / math.max(unit:peek(), 0.001)
		end
		local function blocked(): boolean
			for pointer in contacts do
				local decision = arbiter.get(pointer)
				if decision and decision.owner ~= root and decision.owner:IsDescendantOf(root) then
					capturedContacts[pointer] = true
				end
				if
					decision
					and capturedContacts[pointer]
					and (decision.kind == "pending" or decision.kind == "drag")
				then
					return true
				end
			end
			local held = drag.state:peek()
			if held and (held.source == root or held.source:IsDescendantOf(root)) then
				capturedSource = held.source
			end
			if not held then
				capturedSource = nil
			end
			return held ~= nil and held.source == capturedSource
		end
		local function enabled(): boolean
			return ctx.read(spec.enabled) ~= false and root.Visible and not blocked()
		end
		local function bounds(): (number, number)
			local size, area = extent(), window()
			local minimum = spec.minZoom or geometry.fit(area.X, area.Y, size.X, size.Y)
			return math.min(minimum, maximum), maximum
		end
		local function clamp(value: number): number
			local minimum, max = bounds()
			return math.clamp(value, math.max(minimum, 0.001), max)
		end
		local function capture(point: Vector2?)
			translation.retarget(V2.zero, 0)
			local area, size = window(), extent()
			screenPoint = point or area / 2
			contentPoint = V2.new(
				geometry.point(
					applied,
					root.CanvasPosition.X,
					math.max(0, (area.X - size.X * applied) / 2),
					screenPoint.X
				),
				geometry.point(
					applied,
					root.CanvasPosition.Y,
					math.max(0, (area.Y - size.Y * applied) / 2),
					screenPoint.Y
				)
			)
		end
		local function focusAt(point: Vector2)
			local area, size = window(), extent()
			contentPoint, screenPoint = point, area / 2
			local x = geometry.axis(area.X, size.X, applied, contentPoint.X, screenPoint.X)
			local y = geometry.axis(area.Y, size.Y, applied, contentPoint.Y, screenPoint.Y)
			translation.retarget(V2.new(x, y) - root.CanvasPosition, 0)
		end
		local press: InputObject? = nil
		local mouseOrigin, mouseCanvas = V2.zero, V2.zero
		local mousePanning = false
		local function moveMouse(position: Vector2)
			if not enabled() then
				return
			end
			local delta = (position - mouseOrigin) / math.max(unit:peek(), 0.001)
			if not mousePanning and delta.Magnitude < 6 then
				return
			end
			mousePanning = true
			ramp.retarget(applied, 0)
			local size, area = extent() * applied, window()
			local next = mouseCanvas - delta
			root.CanvasPosition = V2.new(
				math.clamp(next.X, 0, math.max(0, size.X - area.X)),
				math.clamp(next.Y, 0, math.max(0, size.Y - area.Y))
			)
			capture()
		end
		local detector = Host.UIDragDetector {
			Name = "ZoomPanDetector",
			DragStyle = E.UIDragDetectorDragStyle.TranslatePlane,
			ResponseStyle = E.UIDragDetectorResponseStyle.CustomOffset,
			Enabled = function(use: Shared.Use): boolean
				return ctx.read(spec.enabled, use) ~= false and effectiveInput(use) == "KeyboardAndMouse"
			end,
			DragStart = function(position: Vector2)
				if press == nil then
					mouseOrigin, mouseCanvas, mousePanning = position, root.CanvasPosition, false
				end
			end,
			DragContinue = function(position: Vector2)
				if press == nil then
					moveMouse(position)
				end
			end,
			DragEnd = function()
				mousePanning = false
			end,
		}
		detector.Parent = root
		local function inset(): Vector2
			if gui then
				local top = gui:GetGuiInset()
				return top
			end
			return V2.zero
		end
		local function mousePoint(): Vector2
			return if input then input:GetMouseLocation() - inset() else V2.zero
		end
		local releaseMouseScrollers: (() -> ())? = nil
		local wheelDirection: Vector2? = nil
		local focused = true
		local refreshMouse: () -> () = function() end
		local function releaseMouse()
			if releaseMouseScrollers then
				releaseMouseScrollers()
				releaseMouseScrollers = nil
				if ctx.read(spec.enabled) == false or ctx.read(spec.ScrollingEnabled) == false then
					root.ScrollingEnabled = false
				end
			end
		end
		Compose.cleanup(releaseMouse)
		local function allowRequest(): boolean
			if ctx.read(spec.enabled) == false or not root.Visible then
				return false
			end
			if arbiter.claimCamera(root) then
				local held = drag.state:peek()
				if held then
					capturedSource = held.source
				end
				return true
			end
			return not blocked()
		end
		local function request(value: number, direct: boolean?, allowed: boolean?): boolean
			assert(positive(value), "Facet UI.ZoomView: zoom must be positive and finite")
			if not allowed and not allowRequest() then
				return false
			end
			local next = clamp(value)
			if blocked() then
				captureTarget = next
				frozen, deferred = false, nil
				root:ResetScrollVelocity()
			end
			proposing = true
			zoom:set(next)
			proposing = false
			ramp.retarget(next, if direct or reduce() then 0 else ctx.metric("motion.durations.zoom"))
			translation.retarget(V2.zero, if direct or reduce() then 0 else ctx.metric("motion.durations.zoom"))
			return true
		end
		local function fit(): boolean
			if not allowRequest() then
				return false
			end
			local area, size = window(), extent()
			if area.X <= 0 or area.Y <= 0 then
				return false
			end
			focusAt(size / 2)
			return request(geometry.fit(area.X, area.Y, size.X, size.Y), nil, true)
		end
		local function zoomTo(rect: Types.Rect): boolean
			if not allowRequest() then
				return false
			end
			local area = window()
			if area.X <= 0 or area.Y <= 0 then
				return false
			end
			local target = geometry.rectangle(area.X, area.Y, rect)
			focusAt(V2.new(rect.x + rect.w / 2, rect.y + rect.h / 2))
			return request(target, nil, true)
		end
		local function zoomAt(value: number, point: Vector2?): boolean
			if not allowRequest() then
				return false
			end
			local held = drag.state:peek()
			local focus = point
				or (
					held
					and (
						held.position
						or (
							if held.source:IsA("GuiObject")
								then held.source.AbsolutePosition + held.source.AbsoluteSize / 2
								else nil
						)
					)
				)
			capture(if focus then (focus - root.AbsolutePosition) / math.max(unit:peek(), 0.001) else nil)
			return request(value, nil, true)
		end
		local function pan(delta: Vector2)
			if not enabled() then
				return
			end
			capture()
			screenPoint -= delta
		end
		local function step(direction: number)
			if not allowRequest() then
				return
			end
			capture()
			request(zoom:peek() * ctx.metric("controls.zoom.stepRatio") ^ direction, nil, true)
		end
		local pinchActive = false
		local releasePinchScrollers: (() -> ())? = nil
		local function releasePinch()
			if releasePinchScrollers then
				releasePinchScrollers()
				releasePinchScrollers = nil
				if ctx.read(spec.enabled) == false or ctx.read(spec.ScrollingEnabled) == false then
					root.ScrollingEnabled = false
				end
			end
		end
		Compose.cleanup(releasePinch)
		local suppressed: { [GuiButton]: boolean } = {}
		local suppressing = false
		local restorePending = false
		local function restoreButtons()
			suppressing, restorePending = false, false
			for button in suppressed do
				button.Active = true
			end
			table.clear(suppressed)
		end
		local function suppressButton(node: Instance)
			if suppressing and node:IsA("GuiButton") and node.Active then
				suppressed[node] = true
				node.Active = false
			end
		end
		runtime.connect(root, "DescendantAdded", suppressButton)
		runtime.connect(root, "DescendantRemoving", function(node: Instance)
			if node:IsA("GuiButton") and suppressed[node] then
				suppressed[node] = nil
				node.Active = true
			end
		end)
		Compose.cleanup(restoreButtons)
		local function presentation(): number
			if spec.followTransition ~= true then
				return 1
			end
			local factor = 1
			local at: Instance? = root.Parent
			while at do
				local value: unknown = at:GetAttribute("FacetTransitionZoom")
				if type(value) == "number" and value > 0 then
					factor *= value
				end
				at = at.Parent
			end
			return factor
		end
		local function render(delta: number)
			if restorePending then
				restoreButtons()
			end
			refreshMouse()
			if ctx.read(spec.enabled) == false then
				pinchActive = false
				releasePinch()
			end
			if captureTarget and not blocked() then
				captureTarget = nil
				local next = deferred
				deferred = nil
				if next then
					capture()
					request(next)
				end
			end
			if blocked() and captureTarget == nil then
				if not frozen then
					frozen = true
					frozenCanvas = root.CanvasPosition
					deferred = zoom:peek()
					ramp.retarget(applied, 0)
					root:ResetScrollVelocity()
				end
				root.CanvasPosition = frozenCanvas
				return
			end
			if frozen then
				frozen = false
				local next = deferred
				deferred = nil
				if next then
					capture()
					request(next)
				end
			end
			if stick.Magnitude > 0 then
				pan(stick * ctx.metric("controls.zoom.panSpeed") * delta)
			end
			local value = clamp(ramp.value:peek())
			if reduce() then
				value = clamp(captureTarget or zoom:peek())
			end
			local area, size = window(), extent()
			if area.X <= 0 or area.Y <= 0 then
				return
			end
			if not measured then
				measured = true
				contentPoint, screenPoint = ctx.read<<Vector2?>>(spec.focus) or size / 2, area / 2
				local fitted = geometry.fit(area.X, area.Y, size.X, size.Y)
				if spec.zoom == nil or zoom:peek() <= fitted then
					value = clamp(fitted)
					request(value, true)
				end
			end
			local previous = fittedArea
			if previous and previous ~= area and not pinchActive then
				local before = math.min(geometry.fit(previous.X, previous.Y, size.X, size.Y), maximum)
				if zoom:peek() <= before * (1 + 1e-3) then
					contentPoint, screenPoint = size / 2, area / 2
					request(geometry.fit(area.X, area.Y, size.X, size.Y), true, true)
					value = clamp(ramp.value:peek())
				end
			end
			fittedArea = area
			local shown = value * presentation()
			local x, insetX = geometry.axis(area.X, size.X, shown, contentPoint.X, screenPoint.X)
			local y, insetY = geometry.axis(area.Y, size.Y, shown, contentPoint.Y, screenPoint.Y)
			local offset = if reduce() then V2.zero else translation.value:peek()
			applying = true
			scaler.Scale = shown
			canvas.Position = D2.fromOffset(insetX, insetY)
			root.CanvasSize = D2.fromOffset(math.max(area.X, size.X * shown), math.max(area.Y, size.Y * shown))
			root.CanvasPosition = V2.new(
				math.clamp(x - offset.X, 0, math.max(0, size.X * shown - area.X)),
				math.clamp(y - offset.Y, 0, math.max(0, size.Y * shown - area.Y))
			)
			applied = value
			root:SetAttribute("FacetZoom", value)
			applying = false
			local held = drag.state:peek()
			if held and held.mode == "pointer" and not held.pending and held.position then
				drag.update(held.position)
			end
		end
		runtime.connect(root, "Changed", function(property: string)
			if property == "CanvasPosition" and not applying and not frozen and not blocked() then
				capture()
			end
		end)
		local lastZoom = zoom:peek()
		local lastFocus = ctx.read<<Vector2?>>(spec.focus)
		Compose.watch(function(use: Shared.Use)
			local next = use(zoom)
			assert(positive(next), "Facet UI.ZoomView: zoom must be positive and finite")
			local focus = ctx.read<<Vector2?>>(spec.focus, use)
			if next ~= lastZoom or focus ~= lastFocus then
				if blocked() and not (proposing and captureTarget ~= nil) then
					deferred = next
				else
					if not proposing then
						capture()
					end
					if focus and (focus ~= lastFocus or not proposing) then
						focusAt(focus)
					end
					ramp.retarget(clamp(next), if reduce(use) then 0 else ctx.metric("motion.durations.zoom", use))
					translation.retarget(V2.zero, if reduce(use) then 0 else ctx.metric("motion.durations.zoom", use))
				end
				lastZoom = next
				lastFocus = focus
			end
		end)
		local pinchStart = 1
		local lastTap: { at: number, point: Vector2 }? = nil
		local pressPoint = V2.zero
		local moved = false
		local boardTap = false
		local function localPoint(point: Vector2): Vector2
			return (point - root.AbsolutePosition) / math.max(unit:peek(), 0.001)
		end
		local function inside(point: Vector2): boolean
			local localAt = localPoint(point)
			local area = window()
			return localAt.X >= 0 and localAt.Y >= 0 and localAt.X < area.X and localAt.Y < area.Y
		end
		local function ownsPoint(point: Vector2, tap: boolean): boolean
			local player = root:FindFirstAncestorWhichIsA("PlayerGui")
			if not player then
				return true
			end
			for _, hit in (player :: PlayerGui):GetGuiObjectsAtPosition(point.X, point.Y) do
				if hit == root or hit:IsDescendantOf(root) then
					local node: Instance? = hit
					while node and node ~= root do
						if
							node:IsA("GuiObject")
							and (
								node:IsA("ScrollingFrame")
								or (
									tap
									and (
										node:IsA("TextBox")
										or node:GetAttribute("FacetOwnsTaps") == true
										or (node.Active and not node:IsA("GuiButton"))
									)
								)
							)
						then
							return false
						end
						node = node.Parent
					end
					return true
				end
				if hit.Active or hit:IsA("GuiButton") or hit:IsA("TextBox") then
					return false
				end
			end
			return false
		end
		local function overPoint(point: Vector2): boolean
			if pinchActive then
				return false
			end
			if
				not focused
				or not input
				or ctx.read(spec.enabled) == false
				or not root.Visible
				or not root.Interactable
			then
				return false
			end
			if not inside(point) then
				return false
			end
			local at: Instance? = root.Parent
			while at do
				if at:IsA("GuiObject") then
					if not at.Visible or not at.Interactable then
						return false
					end
					if at.ClipsDescendants then
						local position, size = at.AbsolutePosition, at.AbsoluteSize
						if
							point.X < position.X
							or point.Y < position.Y
							or point.X >= position.X + size.X
							or point.Y >= position.Y + size.Y
						then
							return false
						end
					end
				elseif at:IsA("LayerCollector") and not at.Enabled then
					return false
				end
				at = at.Parent
			end
			return ownsPoint(point, false)
		end
		local function overMouse(): boolean
			return effectiveInput() == "KeyboardAndMouse" and overPoint(mousePoint())
		end
		local function canWheelPan(delta: Vector2): boolean
			local size, area, position = extent() * applied, window(), root.CanvasPosition
			local limit = V2.new(math.max(0, size.X - area.X), math.max(0, size.Y - area.Y))
			return (delta.X < 0 and position.X > 0.5)
				or (delta.X > 0 and position.X < limit.X - 0.5)
				or (delta.Y < 0 and position.Y > 0.5)
				or (delta.Y > 0 and position.Y < limit.Y - 0.5)
		end
		refreshMouse = function()
			if overMouse() and (wheelDirection == nil or canWheelPan(wheelDirection)) then
				if not releaseMouseScrollers then
					releaseMouseScrollers = scrollLock.holdAncestors(canvas)
					root:ResetScrollVelocity()
				end
			else
				releaseMouse()
			end
		end
		local function beginPointer(event: InputObject)
			if event.UserInputType == E.UserInputType.Touch or event.UserInputType == E.UserInputType.MouseButton1 then
				if event == press then
					return
				end
				if restorePending then
					restoreButtons()
				end
				press, pressPoint, moved = event, V2.new(event.Position.X, event.Position.Y), false
				boardTap = ownsPoint(pressPoint, true)
				local frames = runtime.host.frames
				local now = if frames then frames.now() else os.clock()
				local prior = lastTap
				if
					boardTap
					and enabled()
					and prior
					and now - prior.at <= ctx.metric("controls.zoom.doubleTapSeconds")
					and (pressPoint - prior.point).Magnitude <= ctx.metric("controls.zoom.doubleTapDistance")
				then
					activation.consume(event)
					suppressing, restorePending = true, false
					for _, node in root:GetDescendants() do
						suppressButton(node)
					end
				end
				contacts[event] = true
				arbiter.begin(event, root, pressPoint, { scroll = event.UserInputType == E.UserInputType.Touch })
				if event.UserInputType == E.UserInputType.MouseButton1 then
					mouseOrigin, mouseCanvas, mousePanning = pressPoint, root.CanvasPosition, false
				end
			end
		end
		runtime.connect(root, "InputBegan", beginPointer)
		if input then
			runtime.connect(
				input,
				"TouchPinch",
				function(points: { Vector2 }, ratio: number, _velocity: number, state: Enum.UserInputState)
					if not enabled() or #points < 2 then
						pinchActive = false
						releasePinch()
						return
					end
					local centre = (points[1] + points[2]) / 2 - inset()
					if state == E.UserInputState.Begin then
						pinchActive = inside(points[1] - inset()) and inside(points[2] - inset())
						pinchStart = applied
						capture(localPoint(centre))
						if pinchActive then
							releaseMouse()
							if not releasePinchScrollers then
								releasePinchScrollers = scrollLock.holdAncestors(canvas)
							end
							root:ResetScrollVelocity()
						end
						return
					end
					if pinchActive and positive(ratio) then
						screenPoint = localPoint(centre)
						if request(pinchStart * ratio, true) then
							render(0)
						end
						moved = true
						lastTap = nil
					end
					if state == E.UserInputState.End or state == E.UserInputState.Cancel then
						pinchActive = false
						releasePinch()
					end
				end
			)
		end
		if input then
			runtime.connect(input, "InputBegan", function(event: InputObject)
				if
					event.UserInputType == E.UserInputType.Touch
					or event.UserInputType == E.UserInputType.MouseButton1
				then
					contacts[event] = true
					if overPoint(V2.new(event.Position.X, event.Position.Y)) then
						beginPointer(event)
					end
				end
			end)
			runtime.connect(input, "InputChanged", function(event: InputObject)
				if event == press and (V2.new(event.Position.X, event.Position.Y) - pressPoint).Magnitude >= 6 then
					arbiter.move(event, V2.new(event.Position.X, event.Position.Y))
					moved, lastTap = true, nil
				end
				if event.UserInputType == E.UserInputType.MouseMovement then
					wheelDirection = nil
					refreshMouse()
					local pointer = press
					if pointer and pointer.UserInputType == E.UserInputType.MouseButton1 then
						local point = V2.new(event.Position.X, event.Position.Y)
						local kind = arbiter.move(pointer, point)
						local decision = arbiter.get(pointer)
						if kind == "pan" and decision and decision.owner == root then
							moved, lastTap = true, nil
							moveMouse(point)
						end
					end
				elseif event.UserInputType == E.UserInputType.MouseWheel then
					local control = input:IsKeyDown(E.KeyCode.LeftControl) or input:IsKeyDown(E.KeyCode.RightControl)
					local distance = -event.Position.Z * ctx.metric("controls.zoom.panStep")
					local horizontal = input:IsKeyDown(E.KeyCode.LeftShift) or input:IsKeyDown(E.KeyCode.RightShift)
					wheelDirection = if control
						then nil
						else (if horizontal then V2.new(distance, 0) else V2.new(0, distance))
					refreshMouse()
					if overMouse() and enabled() then
						if control then
							capture(localPoint(mousePoint()))
							request(zoom:peek() * ctx.metric("controls.zoom.stepRatio") ^ event.Position.Z)
						elseif wheelDirection and canWheelPan(wheelDirection) then
							ramp.retarget(applied, 0)
							pan(wheelDirection)
							render(0)
						end
					end
				end
			end)
			runtime.connect(input, "InputEnded", function(event: InputObject)
				contacts[event] = nil
				capturedContacts[event] = nil
				if event ~= press then
					return
				end
				press, mousePanning = nil, false
				restorePending = suppressing
				local decision = arbiter.get(event)
				local kind = arbiter.finish(event, root, event.UserInputState == E.UserInputState.Cancel)
				if decision and decision.owner ~= root then
					lastTap = nil
					return
				end
				if
					moved
					or not boardTap
					or not inside(V2.new(event.Position.X, event.Position.Y))
					or kind == "scroll"
					or kind == "pan"
					or event.UserInputState == E.UserInputState.Cancel
					or not enabled()
				then
					lastTap = nil
					return
				end
				local frames = runtime.host.frames
				local now = if frames then frames.now() else os.clock()
				local prior = lastTap
				if
					prior
					and now - prior.at <= ctx.metric("controls.zoom.doubleTapSeconds")
					and (pressPoint - prior.point).Magnitude <= ctx.metric("controls.zoom.doubleTapDistance")
				then
					capture(localPoint(pressPoint))
					local minimum = bounds()
					request(
						if applied > minimum + 0.001
							then minimum
							else spec.doubleTapZoom or math.min(maximum, minimum * 2)
					)
					lastTap = nil
				else
					lastTap = { at = now, point = pressPoint }
				end
			end)
			runtime.connect(input, "WindowFocused", function()
				focused = true
			end)
			runtime.connect(input, "WindowFocusReleased", function()
				focused = false
				restoreButtons()
				releaseMouse()
				releasePinch()
				arbiter.cancelOwner(root)
				table.clear(contacts)
				table.clear(capturedContacts)
				press, lastTap, pinchActive, stick = nil, nil, false, V2.zero
			end)
		end
		Compose.cleanup(function()
			arbiter.cancelOwner(root)
		end)
		local selected: Shared.ReadOnlyValue<GuiObject?> = if gui
			then ctx.observe.SelectedObject(gui)
			else Compose.cell(nil :: GuiObject?)
		local function active(use: Shared.Use): boolean
			return use(selected) == root and ctx.read(spec.enabled, use) ~= false and not blocked()
		end
		runtime.connect(root, "SelectionGained", function() end)
		for _, entry in
			{
				{ name = "ZoomIn", key = E.KeyCode.Equals, pad = E.KeyCode.ButtonR1, direction = 1 },
				{ name = "ZoomOut", key = E.KeyCode.Minus, pad = E.KeyCode.ButtonL1, direction = -1 },
			}
		do
			ctx.action(root, entry.name, { entry.key, entry.pad }, active, function()
				step(entry.direction)
			end, { sink = true, priority = 250 })
		end
		ctx.action(root, "ZoomFit", { E.KeyCode.Home, E.KeyCode.ButtonY }, active, function()
			fit()
		end, { sink = true, priority = 250 })
		for _, entry in
			{
				{ name = "PanLeft", key = E.KeyCode.A, x = -1, y = 0 },
				{ name = "PanRight", key = E.KeyCode.D, x = 1, y = 0 },
				{ name = "PanUp", key = E.KeyCode.W, x = 0, y = -1 },
				{ name = "PanDown", key = E.KeyCode.S, x = 0, y = 1 },
			}
		do
			ctx.action(root, entry.name, { entry.key }, active, function()
				pan(V2.new(entry.x, entry.y) * ctx.metric("controls.zoom.panStep"))
			end, { sink = true, priority = 250 })
		end
		ctx.action(root, "ZoomPan", { E.KeyCode.Thumbstick2 }, active, function() end, {
			sink = true,
			priority = 250,
			direction2D = function(value: Vector2)
				stick = V2.new(value.X, -value.Y)
			end,
			onReleased = function()
				stick = V2.zero
			end,
		})
		local run = ctx.config.services.RunService
		if run then
			runtime.connect(run, "PreRender", render)
		elseif runtime.host.frames then
			Compose.cleanup(runtime.host.frames.onFrame(render))
		end
		capture()
		if spec.focus then
			contentPoint = ctx.read<<Vector2?>>(spec.focus)
		end
		render(0)
		if spec.controls then
			spec.controls.fit, spec.controls.zoomTo, spec.controls.zoomAt = fit, zoomTo, zoomAt
			Compose.cleanup(function()
				if spec.controls then
					spec.controls.fit, spec.controls.zoomTo, spec.controls.zoomAt = nil, nil, nil
				end
			end)
		end
		return ctx.styled(root, "facet-zoom-view")
	end)
end
