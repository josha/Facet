--!strict
local Types = require("./types")
local EngineTypes = require("./engine_types")
local Drag = require("./drag_types")
local Env = require("./environment_types")
local activation = require("./activation")
local motion = require("./motion")
local services = setmetatable({} :: { [Types.Context]: Drag.Service }, { __mode = "kv" })

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
			local target = proxies[node] or node
			local spec = targets[target]
			local pass = current and spec and spec.passThrough and spec.passThrough(current.payload)
			if current and spec and spec.collectionAxis and current.mode == "pointer" and current.position then
				local axis = spec.collectionAxis
				local gui = target :: GuiObject
				local extent = if axis == "X" then gui.AbsoluteSize.X else gui.AbsoluteSize.Y
				local offset = if axis == "X"
					then current.position.X - gui.AbsolutePosition.X
					else current.position.Y - gui.AbsolutePosition.Y
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
			for _, node in (playerGui :: PlayerGui):GetGuiObjectsAtPosition(at.X, at.Y) do
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
		if camera then
			local ray = camera:ScreenPointToRay(at.X, at.Y)
			local hit = assert(workspace):Raycast(ray.Origin, ray.Direction * 10000)
			return if hit then ancestor(hit.Instance) else nil, hit
		end
		return nil, nil
	end
	local function info(target: Instance): Drag.Proposal
		local session = current :: Drag.Session
		return {
			source = session.source,
			target = target :: Env.DropDestination,
			mode = session.mode,
			operation = ctx.read(targets[target].operation or "move") :: Env.DropOperation,
			position = session.position,
			hit = session.hit,
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
	local function localPoint(ghost: GuiObject, position: Vector2): UDim2
		local layer = ghost.Parent
		local origin = if layer and layer:IsA("GuiBase2d") then layer.AbsolutePosition else V2.zero
		local scale = 1
		if layer then
			for _, child in layer:GetChildren() do
				if child:IsA("UIScale") and child.Scale > 0 then
					scale = child.Scale
				end
			end
		end
		return D2.fromOffset((position.X - origin.X) / scale, (position.Y - origin.Y) / scale)
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
		label.Text = if session.spec.statusLabels == false
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
			label.Text ..= " to " .. ctx.read(targets[session.target].label)
		end
		if session.mode == "armed" and not session.pending then
			local input = (session.effectiveInput :: (Types.Use?) -> "Touch" | "Gamepad" | "KeyboardAndMouse")(nil)
			if label.Text ~= "" then
				label.Text ..= " · "
			end
			label.Text ..= if input == "Gamepad"
				then "A: drop · B: cancel"
				elseif input == "Touch" then "Tap a destination"
				else "Enter: drop · Esc: cancel · Tab: destination"
			if input == "Gamepad" and session.spec.navigationHint then
				label.Text ..= " · " .. session.spec.navigationHint
			end
		end
		local panel = label.Parent :: GuiObject
		panel.Visible = label.Text ~= ""
			and (session.pending or session.mode == "armed" or not session.accepted or session.operation ~= "move")
		local layer = panel.Parent :: GuiBase2d
		local destination = session.target and targets[session.target]
		local anchor = destination and (destination.focusTarget or session.target)
		local point = session.position
			or (if anchor and anchor:IsA("GuiObject") then anchor.AbsolutePosition else session.origin)
		local at = localPoint(panel, point)
		local origin = layer.AbsolutePosition
		local boundsAt = localPoint(panel, origin + layer.AbsoluteSize)
		local sizeAt = localPoint(panel, origin + panel.AbsoluteSize)
		local size = V2.new(sizeAt.X.Offset, sizeAt.Y.Offset)
		local bounds = V2.new(boundsAt.X.Offset, boundsAt.Y.Offset)
		local gap = ctx.metric("space.s")
		local ghost = session.ghost
		if session.mode == "armed" and ghost then
			local preview = session.armedPreview
			local origin = if preview
					and preview.Parent
					and (session.target == nil or session.target == session.source)
				then preview.AbsolutePosition
				else point
			local pickup = localPoint(ghost, origin)
			local extent = session.previewSize :: Vector2
			local beside = anchor and anchor:IsA("GuiObject") and session.target ~= session.source
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
	function service.own(source: GuiObject)
		Compose.cleanup(function()
			if returning[source] then
				returning[source]()
			end
		end)
	end
	local function releaseGhost(session: Drag.Session, accepted: boolean?)
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
		local gui, tweens = ctx.config.guiService, ctx.config.services.TweenService
		local reduced = motion.resolve(
			ctx.read(ctx.config.motionLevel),
			gui ~= nil and gui.ReducedMotionEnabled == true
		) ~= "normal"
		if reduced or not tweens or (not accepted and not available(session.source)) or not ghost.Parent then
			destroy()
			return
		end
		local point = if session.spec.returnPosition
			then session.spec.returnPosition()
			else session.source.AbsolutePosition + session.source.AbsoluteSize / 2
		point = (point or session.origin)
			- session.pickupSize / 2
			+ ghost.AnchorPoint * (session.previewSize :: Vector2)
		local animated: Instance = ghost
		local stopScale: (() -> ())?
		local goal: { Position: UDim2?, Scale: number? } = { Position = localPoint(ghost, point) }
		if accepted then
			local scale = ghost:FindFirstChildWhichIsA("UIScale")
			if scale == nil then
				local stop, mounted = ctx.runtime.mount(function()
					return ctx.Host.UIScale {}
				end, ghost)
				stopScale, scale = stop, mounted :: UIScale
			end
			animated, goal = assert(scale), { Scale = 0 }
		end
		local playback = tweens:Create(
			animated,
			ctx.types.TweenInfo.new(
				ctx.metric(if accepted then "motion.fast" else "motion.durations.glide"),
				ctx.motionStyle("scroll"),
				ctx.types.Enum.EasingDirection.Out
			),
			goal
		)
		local completed: RBXScriptConnection?
		local stopped = false
		local function stop()
			if stopped then
				return
			end
			stopped = true
			returning[session.source] = nil
			if completed then
				completed:Disconnect()
			end
			playback:Cancel()
			if stopScale then
				stopScale()
			end
			destroy()
		end
		returning[session.source] = stop
		completed = playback.Completed:Connect(stop)
		playback:Play()
	end
	function service.finish(accepted: boolean?, reason: string?)
		local session = current
		if not session then
			return
		end
		current = nil
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
		releaseGhost(session, accepted)
		if session.highlight then
			session.highlight:Destroy()
		end
		session.source:RemoveTag("facet-drag-held")
		session.source:SetAttribute("FacetDragHeld", nil)
		if session.press and accepted == true then
			local stop: (() -> ())? = nil
			stop = assert(ctx.runtime.host.frames).onFrame(function()
				activation.release(session.press)
				if stop then
					stop()
				end
			end)
		end
		if session.spec.onEnd then
			session.spec.onEnd(accepted == true, reason)
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
			target:SetAttribute("FacetDropState", if accepted then "accepted" else "rejected")
			target:SetAttribute("FacetDropReason", reason)
			local feedback = targets[target].feedback
			if feedback then
				((feedback :: unknown) :: { Enabled: boolean }).Enabled = accepted
				if feedback:IsA("UIStroke") then
					feedback:RemoveTag("facet-drop-accepted")
					feedback:RemoveTag("facet-drop-rejected")
					feedback:AddTag(if accepted then "facet-drop-accepted" else "facet-drop-rejected")
				end
			end
			local onUpdate = targets[target].onUpdate
			if onUpdate then
				onUpdate(current.payload, proposal, accepted, reason)
			end
		end
		updateStatus(current)
		state:set(table.clone(current))
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
	function service.commit(target: Instance?): boolean
		if not current or current.pending then
			return false
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
		updateStatus(session)
		state:set(table.clone(session))
		destination:SetAttribute("FacetDropState", "pending")
		session.executing = true
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
		source: GuiObject,
		spec: Drag.SourceSpec,
		mode: "pointer" | "armed",
		press: InputObject?,
		preview: (GuiObject | false)?,
		pickup: { position: Vector2, source: GuiObject }?
	)
		service.finish(false, "Replaced by another drag")
		if returning[source] then
			returning[source]()
		end
		local payload = if type(spec.payload) == "function"
			then (spec.payload :: (GuiObject) -> unknown)(source)
			else spec.payload
		if payload == nil then
			return
		end
		local picked = if pickup then pickup.source else source
		local size = picked.AbsoluteSize
		local offset = if pickup then pickup.position - picked.AbsolutePosition else size / 2
		local anchor = V2.new(
			if size.X > 0 then math.clamp(offset.X / size.X, 0, 1) else 0.5,
			if size.Y > 0 then math.clamp(offset.Y / size.Y, 0, 1) else 0.5
		)
		current = {
			pickupSize = size,
			pickupAnchor = anchor,
			position = if mode == "pointer" and pickup then pickup.position else nil,
			source = source,
			spec = spec,
			mode = mode,
			payload = payload,
			press = press,
			origin = if spec.returnPosition
				then spec.returnPosition()
				else source.AbsolutePosition + source.AbsoluteSize / 2,
		}
		local layer = source:FindFirstAncestorWhichIsA("LayerCollector")
		if layer then
			local session = current :: Drag.Session
			session.stopStatus = ctx.runtime.mount(function()
				session.effectiveInput = ctx.effectiveInput()
				local label = ctx.styled(
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
				session.status = label
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
					label,
				}
				return ctx.styled(ctx.Host.Frame(panelProps), "tooltip")
			end, layer)
			updateStatus(session)
		end
		if spec.mark ~= false then
			source:AddTag("facet-drag-held")
			source:SetAttribute("FacetDragHeld", true)
		end
		activation.consume(press)
		if preview ~= false then
			local layer = source:FindFirstAncestorWhichIsA("LayerCollector")
			if layer then
				local ghost = (preview or source):Clone()
				local nodes = ghost:GetDescendants()
				table.insert(nodes, ghost)
				for _, node in nodes do
					if node:IsA("GuiObject") then
						node.Interactable, node.Active, node.Selectable = false, false, false
					elseif node:IsA("UIDragDetector") or node:IsA("InputContext") then
						((node :: unknown) :: { Enabled: boolean }).Enabled = false
					end
				end
				ghost:RemoveTag("facet-drag-held")
				ghost:SetAttribute("FacetDragHeld", nil)
				ghost.Name, ghost.ZIndex, ghost.AnchorPoint = "DragGhost", 1000, anchor
				ghost:SetAttribute("FacetDragFeedback", true)
				ghost.Size = D2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
				ghost.Parent = layer
				local active = current :: Drag.Session
				active.previewSize = source.AbsoluteSize
				ghost.Position =
					localPoint(ghost, (current :: Drag.Session).position or (current :: Drag.Session).origin)
				active.ghost = ghost
				raiseStatus(ghost)
			end
		end
		state:set(table.clone(current :: Drag.Session))
		if spec.onStart then
			spec.onStart(payload, mode)
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
						local before = node.CanvasPosition
						local limit = node.AbsoluteCanvasSize - size
						local next = V2.new(
							math.clamp(before.X + speed(at.X, size.X) * 600 * delta, 0, math.max(0, limit.X)),
							math.clamp(before.Y + speed(at.Y, size.Y) * 600 * delta, 0, math.max(0, limit.Y))
						)
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
		local ghost = image:Clone()
		local size = image.Size
		local unit = body:FindFirstChild("LayoutUnit") :: GuiObject?
		local scale = if unit and unit.AbsoluteSize.X > 0 then unit.AbsoluteSize.X else 1
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
		if scale ~= 1 then
			current.stopPreview = ctx.runtime.mount(function()
				return ctx.Host.UIScale { Scale = scale }
			end, ghost)
		end
		current.previewSize = extent
		current.armedPreview = if current.mode == "armed" then image else nil
		ghost.Position = localPoint(ghost, (current :: Drag.Session).position or (current :: Drag.Session).origin)
		current.ghost = ghost
		raiseStatus(ghost)
	end

	function service.register(target: Instance, spec: Drag.TargetSpec)
		local owned = (table.clone(spec) :: unknown) :: Drag.RegisteredTarget
		local feedback: (UIStroke | Highlight)?
		if spec.feedback == false then
			feedback = nil
		elseif target:IsA("GuiObject") then
			feedback = ctx.Host.UIStroke({
				Name = "FacetDropOutline",
				Enabled = false,
				Thickness = function(use)
					return ctx.metric("strokes.hairline", use)
				end,
				ApplyStrokeMode = ctx.types.Enum.ApplyStrokeMode.Border,
				BorderStrokePosition = ctx.types.Enum.BorderStrokePosition.Inner,
			})
		else
			feedback = ctx.Host.Highlight({
				Name = "FacetDropHighlight",
				FillTransparency = 1,
				Enabled = false,
				Adornee = Compose.static(target),
				DepthMode = ctx.types.Enum.HighlightDepthMode.Occluded,
			})
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
