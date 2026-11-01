--!strict
local Types = require("./types")
local EngineTypes = require("./engine_types")
local Drag = require("./drag_types")
local Env = require("./environment_types")
local activation = require("./activation")
local motion = require("./motion")
local travel = require("./drag_travel")
local gestureOf = require("./gesture_service")
local worldVisual = require("./drag_world_visual")
local services: { [Types.Context]: Drag.Service } = setmetatable({}, { __mode = "kv" })
type StatusPanel = {
	frame: GuiObject,
	label: TextLabel,
	input: (Types.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse",
	stop: () -> (),
}

local function payloadOf<T>(value: T, source: Env.DropDestination): unknown
	if type(value) == "function" then
		local ok, payload = pcall(value, source)
		if not ok then
			error(payload, 0)
		end
		return payload
	end
	return value
end

return function(ctx: Types.Context): Drag.Service
	if services[ctx] then
		return services[ctx]
	end
	local Compose, V2, D2 = ctx.Compose, ctx.types.Vector2, ctx.types.UDim2
	local targets: { [Instance]: Drag.RegisteredTarget } = {}
	local proxies: { [Instance]: Instance } = {}
	local current: Drag.Session? = nil
	local returning: { [Instance]: () -> () } = {}
	local state = Compose.cell(nil :: Drag.Session?)
	local service = { state = state } :: Drag.Service
	services[ctx] = service

	local function ancestor(node: Instance?): Instance?
		while node do
			local session = current
			local target = proxies[node] or node
			local spec = targets[target]
			local pass = session and spec and spec.passThrough and spec.passThrough(session.payload)
			if session and spec and spec.collectionAxis and session.mode == "pointer" and session.position then
				local position = session.position
				local axis = spec.collectionAxis
				local gui = target :: GuiObject
				local extent = if axis == "X" then gui.AbsoluteSize.X else gui.AbsoluteSize.Y
				local offset = if axis == "X"
					then position.X - gui.AbsolutePosition.X
					else position.Y - gui.AbsolutePosition.Y
				local parent = target.Parent
				while parent and not targets[parent] do
					parent = parent.Parent
				end
				pass = pass or (parent ~= nil and (offset < extent * 0.25 or offset > extent * 0.75))
			end
			if spec and not pass then
				return target
			end
			node = node.Parent
		end
		return nil
	end
	local function available(node: Instance): boolean
		if node.Parent == nil then
			return false
		end
		local at: Instance? = node
		while at do
			if at:IsA("GuiObject") and not at.Visible then
				return false
			elseif at:IsA("ScreenGui") and not at.Enabled then
				return false
			end
			at = at.Parent
		end
		return true
	end
	local function contains(node: GuiObject, at: Vector2): boolean
		local origin = node.AbsolutePosition
		local size = if node:IsA("ScrollingFrame") then node.AbsoluteWindowSize else node.AbsoluteSize
		return at.X >= origin.X and at.Y >= origin.Y and at.X <= origin.X + size.X and at.Y <= origin.Y + size.Y
	end
	local function hitTest(at: Vector2): (Instance?, RaycastResult?)
		local source = (current :: Drag.Session).source
		local playerGui = source:FindFirstAncestorWhichIsA("BasePlayerGui")
		local players = ctx.config.services.Players
		if playerGui == nil and players and players.LocalPlayer then
			playerGui = players.LocalPlayer:FindFirstChildWhichIsA("PlayerGui")
		end
		if playerGui then
			for _, node in playerGui:GetGuiObjectsAtPosition(at.X, at.Y) do
				local excluded, pass = false, node:GetAttribute("FacetDropPassThrough") == true
				local parent: Instance? = node
				while parent do
					if parent:GetAttribute("FacetDragFeedback") == true then
						excluded = true
						break
					end
					parent = parent.Parent
				end
				if not excluded and available(node) then
					local target = ancestor(node)
					if target then
						return target, nil
					end
					if
						not pass
						and (
							node.Active
							or node:IsA("GuiButton")
							or node:IsA("TextBox")
							or (node:GetStyled("BackgroundTransparency") :: number) < 1
						)
					then
						return nil, nil
					end
				end
			end
		else
			local best: GuiObject? = nil
			for target in targets do
				if
					target:IsA("GuiObject")
					and available(target)
					and contains(target, at)
					and ancestor(target) == target
				then
					local clipped = false
					local parent = target.Parent
					while parent do
						if parent:IsA("GuiObject") and parent.ClipsDescendants and not contains(parent, at) then
							clipped = true
							break
						end
						parent = parent.Parent
					end
					if not clipped and (best == nil or target:IsDescendantOf(best) or target.ZIndex > best.ZIndex) then
						best = target
					end
				end
			end
			if best then
				return best, nil
			end
		end
		local workspace = ctx.config.services.Workspace
		local camera = if workspace then workspace.CurrentCamera else nil
		local world = false
		for target in targets do
			if not target:IsA("GuiObject") then
				world = true
				break
			end
		end
		if camera and world then
			local ray = camera:ScreenPointToRay(at.X, at.Y)
			local params = ctx.types.RaycastParams.new()
			if not source:IsA("GuiObject") then
				params.FilterDescendantsInstances = { source }
			end
			local hit = assert(workspace):Raycast(ray.Origin, ray.Direction * 10000, params)
			return if hit then ancestor(hit.Instance) else nil, hit
		end
		return nil, nil
	end
	local function info(target: Instance): Drag.Proposal
		local session = current :: Drag.Session
		return {
			source = session.source,
			target = (target :: unknown) :: Env.DropDestination,
			mode = session.mode,
			operation = ctx.read(targets[target].operation or "move") :: Env.DropOperation,
			position = session.position,
			hit = session.hit,
			placement = ctx.read<<Env.DropPlacement?>>(targets[target].placement),
			worldPlacement = ctx.read<<CFrame?>>(targets[target].worldPlacement),
			complete = function()
				return false
			end,
		}
	end
	local function validate(target: Instance, proposal: Drag.Proposal): (boolean, string?)
		local session = current :: Drag.Session
		local valid = session.spec.valid
		local operations = session.spec.operations
		local spec = targets[target]
		if not spec or not available(target) then
			return false, "The destination is no longer available"
		end
		if valid and not valid() then
			return false, "The source changed"
		end
		if operations and not table.find(operations, proposal.operation) then
			return false, "This operation is not supported"
		end
		if spec.propose then
			spec.propose(session.payload, proposal)
		end
		if spec.accepts then
			return spec.accepts(session.payload, proposal)
		end
		return true, nil
	end
	local function leave(session: Drag.Session)
		local target = session.target
		if target then
			target:SetAttribute("FacetDropState", nil)
			target:SetAttribute("FacetDropReason", nil)
			local spec = targets[target]
			if spec and spec.feedback then
				((spec.feedback :: unknown) :: { Enabled: boolean }).Enabled = false
			end
			if spec and spec.onLeave then
				spec.onLeave(session.payload)
			end
		end
	end
	local function heldScale(ghost: GuiObject, value: number): (() -> (), UIScale)
		local stop, mounted = ctx.runtime.mount(function()
			return ctx.Host.UIScale { Scale = value }
		end, ghost)
		local created = (mounted :: UIScale):Clone()
		stop()
		created.Parent = ghost
		return function()
			created:Destroy()
		end, created
	end
	local function nativeScale(node: Instance?): number
		local scaler = node and node:FindFirstChildWhichIsA("UIScale")
		return if scaler and scaler.Scale > 0 then scaler.Scale else 1
	end
	local function effectiveScale(node: Instance?, stop: Instance?): number
		local scale = 1
		while node and node ~= stop do
			scale *= nativeScale(node)
			node = node.Parent
		end
		return scale
	end
	local function frameOf(node: GuiObject): (Vector2, number)
		local layer = node.Parent
		local origin = if layer and layer:IsA("GuiBase2d") then layer.AbsolutePosition else V2.zero
		return origin, nativeScale(layer)
	end
	local function toLocal(origin: Vector2, scale: number, position: Vector2): UDim2
		return D2.fromOffset((position.X - origin.X) / scale, (position.Y - origin.Y) / scale)
	end
	local function localPoint(ghost: GuiObject, position: Vector2): UDim2
		local origin, scale = frameOf(ghost)
		return toLocal(origin, scale, position)
	end
	local function localExtent(ghost: GuiObject, extent: Vector2): UDim2
		local scale = nativeScale(ghost.Parent) * nativeScale(ghost)
		return D2.fromOffset(extent.X / scale, extent.Y / scale)
	end
	local function raiseStatus(ghost: GuiObject)
		local label = (current :: Drag.Session).status
		if not label then
			return
		end
		local top = ghost.ZIndex
		for _, node in ghost:GetDescendants() do
			if node:IsA("GuiObject") or node:IsA("Path2D") then
				top = math.max(top, node.ZIndex)
			end
		end
		(label.Parent :: GuiObject).ZIndex = top + 1
		label.ZIndex = top + 2
	end

	local function updateStatus(session: Drag.Session)
		local label = session.status
		if not label then
			return
		end
		local text: string = if session.spec.statusLabels == false
			then ""
			elseif session.pending then "Waiting for confirmation…"
			elseif session.accepted then ({ move = "Move", copy = "Copy", apply = "Apply" })[session.operation]
			elseif session.target then session.reason or "Cannot drop here"
			elseif session.mode == "armed" then "Choose a destination"
			else "Cannot drop here"
		if
			session.spec.statusLabels ~= false
			and session.accepted
			and session.target
			and targets[session.target].label
			and not session.pending
		then
			text ..= " to " .. ctx.read<<string>>(assert(targets[session.target].label))
		end
		if session.mode == "armed" and not session.pending then
			local input = (session.effectiveInput :: (Types.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse")(nil)
			text ..= if text ~= "" then " · " else ""
			text ..= if input == "Gamepad"
				then "A: drop · B: cancel"
				elseif input == "Touch" then "Tap a destination"
				else "Enter: drop · Esc: cancel · Tab: destination"
			if input == "Gamepad" and session.spec.navigationHint then
				text ..= " · " .. session.spec.navigationHint
			end
		end
		if label.Text ~= text then
			label.Text = text
		end
		local panel = label.Parent :: GuiObject
		panel.Visible = text ~= ""
			and (session.pending or session.mode == "armed" or not session.accepted or session.operation ~= "move")
		if not panel.Visible and session.mode ~= "armed" then
			return
		end
		local layer = panel.Parent :: GuiBase2d
		local destination = session.target and targets[session.target]
		local anchor = destination and (destination.focusTarget or session.target)
		local held = session.source
		local camera = ctx.config.services.Workspace and ctx.config.services.Workspace.CurrentCamera
		local projected: Vector2? = nil
		local gui = ctx.config.guiService
		if session.spec.world and camera and not held:IsA("GuiObject") then
			local pivot = (held :: PVInstance):GetPivot().Position
			local viewport, visible = camera:WorldToViewportPoint(pivot)
			if visible then
				local inset = if layer:IsA("ScreenGui")
						and not layer.IgnoreGuiInset
						and gui
					then gui:GetGuiInset()
					else V2.zero
				projected = V2.new(viewport.X, viewport.Y) - inset
			end
		end
		local point = projected
			or session.position
			or (if anchor and anchor:IsA("GuiObject") then anchor.AbsolutePosition else session.origin)
		local panelOrigin, panelScale = frameOf(panel)
		local at = toLocal(panelOrigin, panelScale, point)
		local origin = layer.AbsolutePosition
		local boundsAt = toLocal(panelOrigin, panelScale, origin + layer.AbsoluteSize)
		local sizeAt = toLocal(panelOrigin, panelScale, origin + panel.AbsoluteSize)
		local size = V2.new(sizeAt.X.Offset, sizeAt.Y.Offset)
		local bounds = V2.new(boundsAt.X.Offset, boundsAt.Y.Offset)
		local gap = ctx.metric("space.s")
		local ghost = session.ghost
		if session.mode == "armed" and ghost then
			local preview = session.armedPreview
			local origin = if preview
					and preview.Parent
					and (session.target == nil or rawequal(session.target, session.source))
				then preview.AbsolutePosition
				else point
			local pickup = localPoint(ghost, origin)
			local extent = session.previewSize :: Vector2
			local beside = anchor and anchor:IsA("GuiObject") and not rawequal(session.target, session.source)
			local x = pickup.X.Offset + gap
			local y = pickup.Y.Offset + gap
			if beside then
				local guiAnchor = anchor :: GuiObject
				local edge = localPoint(ghost, guiAnchor.AbsolutePosition + guiAnchor.AbsoluteSize)
				x = edge.X.Offset + gap
				y = pickup.Y.Offset - extent.Y - size.Y - gap * 3
				if y < gap and edge.Y.Offset + extent.Y + size.Y + gap * 3 <= bounds.Y then
					y = edge.Y.Offset + gap
				end
			end
			ghost.AnchorPoint = V2.zero
			ghost.Position = D2.fromOffset(
				math.clamp(x, gap, math.max(gap, bounds.X - extent.X - gap)),
				math.clamp(y, gap, math.max(gap, bounds.Y - extent.Y - size.Y - gap * 3))
			)
			at = D2.fromOffset(
				ghost.Position.X.Offset - gap,
				ghost.Position.Y.Offset + extent.Y + gap - ctx.metric("targetSizes.minimum")
			)
		end
		(label:FindFirstChildWhichIsA("UISizeConstraint") :: UISizeConstraint).MaxSize =
			V2.new(math.max(1, math.min(280, bounds.X - gap * 4)), math.huge)
		panel.Position = D2.fromOffset(
			math.clamp(at.X.Offset + gap, gap, math.max(gap, bounds.X - size.X - gap)),
			math.clamp(at.Y.Offset + ctx.metric("targetSizes.minimum"), gap, math.max(gap, bounds.Y - size.Y - gap))
		)
	end
	local panels: { [GuiBase2d]: StatusPanel } = {}
	local owners = 0
	local function releasePanels()
		for layer, panel in panels do
			panels[layer] = nil
			panel.stop()
		end
	end
	local function statusPanel(layer: GuiBase2d): StatusPanel
		local label: TextLabel? = nil
		local shell: Frame? = nil
		local input: ((Types.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse")? = nil
		local stop = ctx.runtime.mount(function()
			local effective = ctx.effectiveInput()
			input = effective
			local text = ctx.styled(
				ctx.Host.TextLabel {
					Name = "DragStatusText",
					Size = D2.fromOffset(0, 0),
					AutomaticSize = ctx.types.Enum.AutomaticSize.XY,
					TextWrapped = true,
					Text = "Choose a destination",
					ZIndex = 1002,
					ctx.Host.UISizeConstraint {
						MaxSize = V2.new(math.max(1, math.min(280, layer.AbsoluteSize.X - 32)), math.huge),
					},
				},
				"text"
			)
			label = text
			Compose.watch(function(use)
				effective(use)
				local session = current
				if session and session.status == text then
					updateStatus(session)
				end
			end)
			local panelProps: Types.FrameProps = {
				Name = "DragStatus",
				Size = D2.fromOffset(0, 0),
				AutomaticSize = ctx.types.Enum.AutomaticSize.XY,
				ZIndex = 1001,
				Attributes = { FacetDragFeedback = true } :: EngineTypes.Attributes,
				ctx.Host.UIPadding {
					PaddingTop = ctx.types.UDim.new(0, ctx.metric("space.s")),
					PaddingBottom = ctx.types.UDim.new(0, ctx.metric("space.s")),
					PaddingLeft = ctx.types.UDim.new(0, ctx.metric("space.s")),
					PaddingRight = ctx.types.UDim.new(0, ctx.metric("space.s")),
				},
				text,
			}
			local made = ctx.styled(ctx.Host.Frame(panelProps), "tooltip")
			shell = made
			return made
		end, layer)
		return { frame = assert(shell), label = assert(label), input = assert(input), stop = stop }
	end
	function service.own(source: Env.DropDestination)
		owners += 1
		Compose.cleanup(function()
			if returning[source] then
				returning[source]()
			end
			owners -= 1
			if owners == 0 and current == nil then
				releasePanels()
			end
		end)
	end
	local function releaseFeedbackGhost(session: Drag.Session, accepted: boolean?)
		local ghost = session.ghost
		if not ghost then
			return
		end
		local function destroy()
			if session.stopPreview then
				session.stopPreview()
			end
			ghost:Destroy()
		end
		local gui = ctx.config.guiService
		local reduced = motion.resolve(
			ctx.read(ctx.config.motionLevel),
			gui ~= nil and gui.ReducedMotionEnabled == true
		) ~= "normal"
		if reduced or (not accepted and not available(session.source)) or not ghost.Parent then
			destroy()
			return
		end
		local point = if session.spec.returnPosition
			then session.spec.returnPosition()
			elseif session.source:IsA("GuiObject") then session.source.AbsolutePosition
				+ session.source.AbsoluteSize / 2
			else session.origin
		point = (point or session.origin)
			- session.pickupSize / 2
			+ ghost.AnchorPoint
				* (assert(session.previewSize) / (session.liftScale or session.spec.previewScale or 1))
		local from, goal = ghost.Position, localPoint(ghost, point)
		local scale: UIScale?
		local stopScale: (() -> ())?
		local originalScale = 1
		if accepted or session.spec.previewScale ~= nil then
			scale = ghost:FindFirstChildWhichIsA("UIScale")
			if not scale then
				stopScale, scale = heldScale(ghost, 1)
			end
			originalScale = assert(scale).Scale
		end
		local stopMotion: (() -> ())?
		local stopped = false
		local function stop()
			if stopped then
				return
			end
			stopped = true
			returning[session.source] = nil
			if stopMotion then
				stopMotion()
			end
			if stopScale then
				stopScale()
			end
			destroy()
		end
		returning[session.source] = stop
		stopMotion = travel(ctx, assert(ghost.Parent), function(progress)
			if scale then
				scale.Scale = if accepted
					then originalScale * (1 - progress)
					else originalScale
						* (1 + (1 / (session.liftScale or session.spec.previewScale or 1) - 1) * progress)
				if not accepted then
					ghost.Position = from:Lerp(goal, progress)
				end
			else
				ghost.Position = from:Lerp(goal, progress)
			end
		end, stop)
	end
	local function releaseGhost(session: Drag.Session, accepted: boolean?, complete: () -> ())
		if not session.spec.returnTravel and not session.travelled then
			complete()
			releaseFeedbackGhost(session, accepted)
			return
		end
		local ghost = session.ghost
		if not ghost then
			complete()
			return
		end
		local function destroy()
			if session.stopPreview then
				session.stopPreview()
			end
			ghost:Destroy()
			complete()
		end
		local gui = ctx.config.guiService
		local reduced = motion.resolve(
			ctx.read(ctx.config.motionLevel),
			gui ~= nil and gui.ReducedMotionEnabled == true
		) ~= "normal"
		if
			reduced
			or (session.travelled and accepted)
			or (not accepted and not available(session.source))
			or not ghost.Parent
		then
			destroy()
			return
		end
		local point = if session.spec.returnPosition
			then session.spec.returnPosition()
			elseif session.source:IsA("GuiObject") then session.source.AbsolutePosition
				+ session.source.AbsoluteSize / 2
			else session.origin
		point = (point or session.origin)
			- session.pickupSize / 2
			+ ghost.AnchorPoint
				* (assert(session.previewSize) / (session.liftScale or session.spec.previewScale or 1))
		local from, goal = ghost.Position, localPoint(ghost, point)
		local scale: UIScale?
		local stopScale: (() -> ())?
		local originalScale = 1
		if accepted or session.spec.previewScale ~= nil then
			scale = ghost:FindFirstChildWhichIsA("UIScale")
			if not scale then
				stopScale, scale = heldScale(ghost, 1)
			end
			originalScale = assert(scale).Scale
		end
		local stopMotion: (() -> ())?
		local stopped = false
		local function stop()
			if stopped then
				return
			end
			stopped = true
			returning[session.source] = nil
			if stopMotion then
				stopMotion()
			end
			if stopScale then
				stopScale()
			end
			destroy()
		end
		returning[session.source] = stop
		stopMotion = travel(ctx, assert(ghost.Parent), function(progress)
			if scale then
				scale.Scale = if accepted
					then originalScale * (1 - progress)
					else originalScale
						* (1 + (1 / (session.liftScale or session.spec.previewScale or 1) - 1) * progress)
				if not accepted then
					ghost.Position = from:Lerp(goal, progress)
				end
			else
				ghost.Position = from:Lerp(goal, progress)
			end
		end, stop)
	end
	function service.finish(accepted: boolean?, reason: string?)
		local session = current
		if not session then
			return
		end
		current = nil
		if session.stopLift then
			session.stopLift()
			session.stopLift = nil
		end
		if session.stopTravel then
			session.stopTravel()
			session.stopTravel = nil
		end
		state:set(nil)
		if session.stop then
			session.stop()
		end
		leave(session)
		if session.pendingTarget and session.pendingTarget ~= session.target then
			session.pendingTarget:SetAttribute("FacetDropState", nil)
			session.pendingTarget:SetAttribute("FacetDropReason", nil)
		end
		if session.stopStatus then
			session.stopStatus()
		end
		local concluded = false
		local function conclude()
			if concluded then
				return
			end
			concluded = true
			returning[session.source] = nil
			session.source:RemoveTag("facet-drag-held")
			session.source:SetAttribute("FacetDragHeld", nil)
			if session.spec.onEnd then
				session.spec.onEnd(accepted == true, reason)
			end
		end
		if session.world then
			local stop = session.world.release(accepted == true, conclude)
			if not concluded then
				returning[session.source] = stop
			end
		elseif accepted or not session.spec.returnTravel then
			conclude()
		end
		if not session.world then
			releaseGhost(session, accepted, conclude)
		end
		if session.highlight then
			session.highlight:Destroy()
		end
		if session.press and accepted == true then
			local stop: (() -> ())? = nil
			stop = assert(ctx.runtime.host.frames).onFrame(function()
				activation.release(session.press)
				if stop then
					stop()
				end
			end)
		end
	end
	function service.hover(target: Instance?, hit: RaycastResult?)
		if not current or current.pending then
			return
		end
		if current.target ~= target then
			leave(current)
			current.target = target
			if current.highlight then
				current.highlight:Destroy()
				current.highlight = nil
			end
			local onEnter = target and targets[target].onEnter
			if onEnter then
				onEnter(current.payload)
			end
		end
		current.hit = hit
		current.accepted, current.reason, current.operation = false, nil, nil
		if target then
			local proposal = info(target)
			local accepted, reason = validate(target, proposal)
			current.accepted, current.reason, current.operation = accepted, reason, proposal.operation
			local dropState = if accepted then "accepted" else "rejected"
			if target:GetAttribute("FacetDropState") ~= dropState then
				target:SetAttribute("FacetDropState", dropState)
			end
			if target:GetAttribute("FacetDropReason") ~= reason then
				target:SetAttribute("FacetDropReason", reason)
			end
			local feedback = targets[target].feedback
			if feedback then
				local outline = (feedback :: unknown) :: { Enabled: boolean }
				if outline.Enabled ~= accepted then
					outline.Enabled = accepted
				end
				if feedback:IsA("UIStroke") then
					local shown = if accepted then "facet-drop-accepted" else "facet-drop-rejected"
					local hidden = if accepted then "facet-drop-rejected" else "facet-drop-accepted"
					if feedback:HasTag(hidden) then
						feedback:RemoveTag(hidden)
					end
					if not feedback:HasTag(shown) then
						feedback:AddTag(shown)
					end
				end
			end
			local onUpdate = targets[target].onUpdate
			if onUpdate then
				onUpdate(current.payload, proposal, accepted, reason)
			end
		end
		if current.world then
			local spec = target and targets[target]
			local placement = spec and spec.worldPlacement
			current.world.move(
				current.position,
				if current.accepted and placement then ctx.read<<CFrame?>>(placement) else nil
			)
		end
		updateStatus(current)
		local shown = state:peek()
		if
			shown == nil
			or shown.source ~= current.source
			or shown.target ~= current.target
			or shown.hit ~= current.hit
			or shown.accepted ~= current.accepted
			or shown.reason ~= current.reason
			or shown.operation ~= current.operation
			or shown.pending ~= current.pending
			or shown.mode ~= current.mode
		then
			state:set(table.clone(current))
		else
			local snapshot = (shown :: unknown) :: { [string]: unknown }
			local live = (current :: unknown) :: { [string]: unknown }
			for key in snapshot do
				if live[key] == nil then
					snapshot[key] = nil
				end
			end
			for key, value in live do
				snapshot[key] = value
			end
		end
	end
	function service.update(position: Vector2)
		if not current or current.pending then
			return
		end
		current.position = position
		local ghost = current.ghost
		if ghost then
			ghost.Position = localPoint(ghost, position)
		end
		service.hover(hitTest(position))
	end
	function service.commit(target: Instance?, position: Vector2?): boolean
		if not current or current.pending then
			return false
		end
		if position then
			current.position = position
		end
		if target == nil and current.mode == "pointer" and current.position then
			service.hover(hitTest(current.position))
		end
		target = target or current.target
		if not target or not targets[target] then
			service.finish(false, "No destination")
			return false
		end
		local session, spec, destination = current, targets[target], target
		local proposal = info(destination)
		local accepted, reason = validate(destination, proposal)
		if not accepted then
			service.finish(false, reason)
			if spec.onReject then
				spec.onReject(session.payload, reason)
			end
			return false
		end
		if session.world and not session.travelled then
			session.world.move(session.position, proposal.worldPlacement)
			session.pending = true
			session.pendingTarget = destination
			destination:SetAttribute("FacetDropState", "pending")
			state:set(table.clone(session))
			session.world.land(function()
				if current ~= session then
					return
				end
				session.pending = false
				session.travelled = true
				service.commit(destination)
			end)
			return true
		end
		if spec.travel and not session.travelled and session.ghost then
			local ghost = session.ghost
			local gui = ctx.config.guiService
			local reduced = motion.resolve(
				ctx.read(ctx.config.motionLevel),
				gui ~= nil and gui.ReducedMotionEnabled == true
			) ~= "normal"
			local rect = if spec.landing
				then spec.landing(proposal)
				elseif destination:IsA("GuiObject") then {
					x = destination.AbsolutePosition.X,
					y = destination.AbsolutePosition.Y,
					w = destination.AbsoluteSize.X,
					h = destination.AbsoluteSize.Y,
				}
				else nil
			if rect and not reduced then
				session.pending = true
				session.pendingTarget = destination
				destination:SetAttribute("FacetDropState", "pending")
				state:set(table.clone(session))
				local from = ghost.Position
				local previewSize = session.previewSize or session.pickupSize
				local lift = session.spec.previewScale or 1
				local goalExtent = V2.new(
					rect.w * (if session.pickupSize.X > 0 then previewSize.X / session.pickupSize.X else 1),
					rect.h * (if session.pickupSize.Y > 0 then previewSize.Y / session.pickupSize.Y else 1)
				) / (session.liftScale or lift)
				local goal = localPoint(ghost, V2.new(rect.x, rect.y) + ghost.AnchorPoint * goalExtent)
				local scaler = ghost:FindFirstChildWhichIsA("UIScale")
				local capturedScale = nativeScale(ghost)
				local goalScale = if session.pickupSize.X > 0
						and session.pickupSize.Y > 0
						and rect.w > 0
						and rect.h > 0
					then capturedScale / (session.liftScale or lift) * math.min(
						rect.w / session.pickupSize.X,
						rect.h / session.pickupSize.Y
					)
					else capturedScale
				if not scaler then
					local stop, created = heldScale(ghost, capturedScale)
					scaler = created
					local previous = session.stopPreview
					session.stopPreview = function()
						if previous then
							previous()
						end
						stop()
					end
				end
				local movingScale = assert(scaler)
				session.stopTravel = travel(ctx, assert(ghost.Parent), function(progress)
					movingScale.Scale = capturedScale + (goalScale - capturedScale) * progress
					ghost.Position = from:Lerp(goal, progress)
					ghost.Size = localExtent(ghost, previewSize:Lerp(goalExtent, progress))
				end, function()
					if current ~= session then
						return
					end
					session.pending = false
					session.travelled = true
					service.commit(destination)
				end)
				return true
			end
		end
		local completed = false
		proposal.complete = function(ok: boolean, why: string?): boolean
			if completed or current ~= session then
				return false
			end
			completed = true
			if ok then
				ok, why = validate(destination, proposal)
			end
			service.finish(ok, why)
			if not ok and spec.onReject then
				spec.onReject(session.payload, why)
			end
			return ok
		end
		session.pending = true
		session.pendingTarget = destination
		session.executing = true
		updateStatus(session)
		state:set(session)
		destination:SetAttribute("FacetDropState", "pending")
		local ok, result =
			pcall(spec.onDrop :: (unknown, Env.DropInfo) -> (boolean | "pending")?, session.payload, proposal)
		session.executing = false
		if not ok then
			proposal.complete(false, tostring(result))
			return false
		end
		if result ~= "pending" and not completed and current == session then
			completed = true
			service.finish(result ~= false, if result == false then "Drop rejected" else nil)
			if result == false and spec.onReject then
				spec.onReject(session.payload, "Drop rejected")
			end
		end
		return result ~= false
	end
	function service.begin(
		source: Env.DropDestination,
		spec: Drag.SourceSpec,
		mode: "pointer" | "armed",
		press: InputObject?,
		preview: (GuiObject | false)?,
		pickup: { position: Vector2, source: GuiObject }?
	)
		if current then
			return
		end
		if returning[source] then
			returning[source]()
		end
		local payload = payloadOf(spec.payload, source)
		if payload == nil then
			return
		end
		local picked = if pickup then pickup.source else source
		local size = if picked:IsA("GuiObject") then picked.AbsoluteSize else V2.zero
		local offset = if pickup then pickup.position - pickup.source.AbsolutePosition else size / 2
		local lift = if spec.liftValue then spec.liftValue:peek() else spec.previewScale or 1
		local pressedLift = if spec.liftValue then lift else 1
		local anchor = V2.new(
			if size.X > 0 then math.clamp((offset.X / size.X + (pressedLift - 1) / 2) / pressedLift, 0, 1) else 0.5,
			if size.Y > 0 then math.clamp((offset.Y / size.Y + (pressedLift - 1) / 2) / pressedLift, 0, 1) else 0.5
		)
		local created: Drag.Session = {
			pickupSize = size,
			liftScale = lift,
			pickupAnchor = anchor,
			position = if mode == "pointer" and pickup
				then pickup.position
				elseif mode == "pointer" and press then V2.new(press.Position.X, press.Position.Y)
				else nil,
			source = source,
			spec = spec,
			mode = mode,
			payload = payload,
			press = press,
			origin = if spec.returnPosition
				then spec.returnPosition()
				elseif source:IsA("GuiObject") then source.AbsolutePosition + source.AbsoluteSize / 2
				else V2.zero,
		}
		current = created
		if not source:IsA("GuiObject") then
			created.world = worldVisual(ctx, source, assert(spec.world), created.position)
		end
		local statusSource = if spec.world then spec.world.focusTarget else source
		local layer: GuiBase2d? = statusSource:FindFirstAncestorWhichIsA("LayerCollector")
		local stopScreen: (() -> ())? = nil
		if spec.world and (layer == nil or not layer:IsA("ScreenGui")) then
			local overlay = ctx.config.overlayParent
			if overlay and overlay:IsA("GuiBase2d") then
				layer = overlay
			else
				local players = ctx.config.services.Players
				local player = players and players.LocalPlayer
				local playerGui = player and player:FindFirstChildWhichIsA("PlayerGui")
				if playerGui then
					local stop, screen = ctx.runtime.mount(function()
						return ctx.Host.ScreenGui {
							Name = "FacetWorldDragStatus",
							ResetOnSpawn = false,
							DisplayOrder = 1000,
						}
					end, playerGui)
					stopScreen = stop
					layer = screen :: ScreenGui
				end
			end
		end
		if layer then
			local session = created
			local panel: StatusPanel
			if spec.world then
				local made = statusPanel(layer)
				panel = made
				session.stopStatus = function()
					made.stop()
					if stopScreen then
						stopScreen()
					end
				end
			else
				local cached = panels[layer]
				if cached == nil or cached.frame.Parent ~= layer then
					cached = statusPanel(layer)
					panels[layer] = cached
				end
				local shown = cached
				panel = shown
				shown.frame.Visible = true
				session.stopStatus = function()
					shown.frame.Visible = false
				end
			end
			session.status = panel.label
			session.effectiveInput = panel.input
			updateStatus(session)
		end
		activation.consume(press)
		if preview ~= false and source:IsA("GuiObject") then
			local layer = source:FindFirstAncestorWhichIsA("LayerCollector")
			if layer then
				local liftedVisual = if lift ~= 1
						and spec.liftVisual
						and spec.liftVisual.Visible
					then spec.liftVisual
					else nil
				local visual = liftedVisual or spec.preview or preview or source
				local ghost = visual:Clone()
				local nodes = ghost:GetDescendants()
				table.insert(nodes, ghost)
				for _, node in nodes do
					if node:IsA("GuiObject") then
						node.Interactable, node.Active, node.Selectable = false, false, false
					elseif node:IsA("UIDragDetector") then
						node.Enabled = false
					elseif node:IsA("InputContext") then
						node.Enabled = false
					end
				end
				ghost:RemoveTag("facet-drag-held")
				ghost:SetAttribute("FacetDragHeld", nil)
				ghost.Name, ghost.ZIndex, ghost.AnchorPoint = "DragGhost", 1000, anchor
				ghost:SetAttribute("FacetDragFeedback", true)
				ghost.Parent = layer
				assert(lift > 0 and lift < math.huge, "Facet drag previewScale must be positive and finite")
				local baseScale = effectiveScale(visual, layer) / (if liftedVisual then lift else 1)
				local capturedScale = baseScale * lift
				local scaler = ghost:FindFirstChildWhichIsA("UIScale")
				if scaler then
					scaler.Scale = capturedScale
				elseif capturedScale ~= 1 then
					created.stopPreview = heldScale(ghost, capturedScale)
				end
				local inherited = nativeScale(layer) * baseScale
				ghost.Size = D2.fromOffset(source.AbsoluteSize.X / inherited, source.AbsoluteSize.Y / inherited)
				local active = created
				active.previewSize = source.AbsoluteSize * lift
				ghost.Position = localPoint(ghost, (created).position or (created).origin)
				active.ghost = ghost
				if spec.liftValue and spec.liftCarry and created.mode ~= "armed" then
					spec.liftCarry()
				end
				local liftValue = spec.liftValue
				if liftValue then
					local transform = ghost:FindFirstChildWhichIsA("UIScale")
					if not transform then
						active.stopPreview, transform = heldScale(ghost, capturedScale)
					end
					local held: UIScale = assert(transform)
					local stopLift = ctx.runtime.mountFragment(function()
						Compose.watch(function(use)
							local magnification = use(liftValue)
							held.Scale = baseScale * magnification
							active.previewSize = size * magnification
							active.liftScale = magnification
						end)
						return {}
					end, ghost)
					active.stopLift = stopLift
				end
				raiseStatus(ghost)
			end
		end
		if spec.mark ~= false then
			source:AddTag("facet-drag-held")
			source:SetAttribute("FacetDragHeld", true)
		end
		state:set(table.clone(created))
		local onStart = spec.onStart
		if onStart then
			gestureOf(ctx).capture(source, function()
				onStart(payload, mode)
			end)
		end
		local session = current
		if not session then
			return
		end
		session.stop = assert(ctx.runtime.host.frames).onFrame(function(delta)
			if current ~= session then
				return
			end
			if spec.valid and not spec.valid() then
				service.finish(false, "The source changed")
				return
			end
			local destination = session.pendingTarget or session.target
			if destination and not available(destination) then
				service.finish(false, "The destination was removed")
				return
			end
			updateStatus(session)
			if session.mode == "armed" and not session.pending then
				service.hover(session.target, nil)
			end
			if session.position and not session.pending then
				service.update(session.position)
				local node = session.target
				local destination = if node then targets[node] else nil
				if destination and destination.autoscroll == false then
					return
				end
				if destination and destination.scroll then
					if destination.scroll(session.position, delta) then
						return
					end
					node = (node :: Instance).Parent
				end
				while node do
					if node:IsA("ScrollingFrame") and node.ScrollingEnabled then
						local at = session.position - node.AbsolutePosition
						local size = node.AbsoluteWindowSize
						local function speed(p: number, extent: number)
							local edge = math.min(40, extent / 4)
							if edge <= 0 or p < 0 or p > extent then
								return 0
							end
							return if p < edge
								then -(edge - p) / edge
								elseif p > extent - edge then (p - extent + edge) / edge
								else 0
						end
						local speedX, speedY = speed(at.X, size.X), speed(at.Y, size.Y)
						local armed = session.scrollArmed or {}
						session.scrollArmed = armed
						if not armed[node] then
							local inside = at.X >= 0 and at.Y >= 0 and at.X <= size.X and at.Y <= size.Y
							armed[node] = session.source:IsDescendantOf(node)
								or (inside and speedX == 0 and speedY == 0)
						end
						local before = node.CanvasPosition
						local limit = node.AbsoluteCanvasSize - size
						local next = if armed[node]
							then V2.new(
								math.clamp(before.X + speedX * 600 * delta, 0, math.max(0, limit.X)),
								math.clamp(before.Y + speedY * 600 * delta, 0, math.max(0, limit.Y))
							)
							else before
						if next ~= before then
							node.CanvasPosition = next
							break
						end
					end
					node = node.Parent
				end
			end
		end)
	end
	function service.preview(image: GuiObject, body: ScrollingFrame, frontSize: UDim2?)
		if not current then
			return
		end
		local layer = body:FindFirstAncestorWhichIsA("LayerCollector")
		if not layer then
			return
		end
		if current.ghost then
			if current.stopPreview then
				current.stopPreview()
				current.stopPreview = nil
			end
			current.ghost:Destroy()
		end
		if current.stopLift then
			current.stopLift()
			current.stopLift = nil
		end
		local ghost = image:Clone()
		local size = image.Size
		local unit = body:FindFirstChild("LayoutUnit") :: GuiObject?
		local scale = if unit and unit.AbsoluteSize.X > 0 then unit.AbsoluteSize.X else 1
		local lift = current.spec.previewScale or 1
		assert(lift > 0 and lift < math.huge, "Facet drag previewScale must be positive and finite")
		local extent = V2.new(
			size.X.Offset * scale + size.X.Scale * body.AbsoluteWindowSize.X,
			size.Y.Offset * scale + size.Y.Scale * body.AbsoluteWindowSize.Y
		)
		ghost.Size = D2.fromOffset(extent.X / scale, extent.Y / scale)
		local front = if frontSize
			then V2.new(
				frontSize.X.Offset * scale + frontSize.X.Scale * extent.X,
				frontSize.Y.Offset * scale + frontSize.Y.Scale * extent.Y
			)
			else extent
		ghost.Name, ghost.Visible = "DragGhost", true
		ghost.AnchorPoint = V2.new(
			if extent.X > 0 then current.pickupAnchor.X * front.X / extent.X else 0.5,
			if extent.Y > 0 then current.pickupAnchor.Y * front.Y / extent.Y else 0.5
		)
		ghost:SetAttribute("FacetDragFeedback", true)
		ghost.Parent = layer
		local liftValue = current.spec.liftValue
		if liftValue then
			local active = current
			local stopScale, transform = heldScale(ghost, scale * liftValue:peek())
			active.stopPreview = stopScale
			active.stopLift = ctx.runtime.mountFragment(function()
				Compose.watch(function(use)
					local magnification = use(liftValue)
					transform.Scale = scale * magnification
					active.previewSize = extent * magnification
					active.liftScale = magnification
				end)
				return {}
			end, ghost)
		elseif scale * lift ~= 1 then
			current.stopPreview = heldScale(ghost, scale * lift)
		end
		current.previewSize = extent * (current.liftScale or lift)
		current.armedPreview = if current.mode == "armed" then image else nil
		ghost.Position = localPoint(ghost, current.position or current.origin)
		current.ghost = ghost
		if liftValue and current.spec.liftCarry and current.mode ~= "armed" then
			current.spec.liftCarry()
		end
		raiseStatus(ghost)
	end

	function service.register(target: Instance, spec: Drag.TargetSpec)
		local owned = (table.clone(spec) :: unknown) :: Drag.RegisteredTarget
		local feedback: (UIStroke | Highlight)?
		if spec.feedback == false then
			feedback = nil
		elseif target:IsA("GuiObject") then
			feedback = ctx.Host.UIStroke {
				Name = "FacetDropOutline",
				Enabled = false,
				Thickness = function(use)
					return ctx.metric("strokes.hairline", use)
				end,
				ApplyStrokeMode = ctx.types.Enum.ApplyStrokeMode.Border,
				BorderStrokePosition = ctx.types.Enum.BorderStrokePosition.Inner,
			}
		else
			feedback = ctx.Host.Highlight {
				Name = "FacetDropHighlight",
				FillTransparency = 1,
				Enabled = false,
				Adornee = Compose.static(target),
				DepthMode = ctx.types.Enum.HighlightDepthMode.Occluded,
			}
		end
		if feedback then
			((feedback :: unknown) :: { Parent: Instance? }).Parent = target
		end
		owned.feedback = feedback
		targets[target] = owned
		if spec.focusTarget then
			proxies[spec.focusTarget] = target
		end
		Compose.cleanup(function()
			if current and not current.executing and current.target == target then
				service.finish(false, "The destination was removed")
			end
			targets[target] = nil
			if spec.focusTarget then
				proxies[spec.focusTarget] = nil
			end
		end)
	end
	service.targetOf = ancestor
	return service
end
