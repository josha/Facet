--!strict
local Types = require("./types")
local Env = require("./environment_types")
local activation = require("./activation")
local motion = require("./motion")
local services = setmetatable({}, { __mode = "kv" }) :: any

return function(ctx: Types.Context): any
	if services[ctx] then
		return services[ctx]
	end
	local Compose, V2, D2 = ctx.Compose, ctx.types.Vector2, ctx.types.UDim2
	local targets: { [Instance]: any } = {}
	local proxies: { [Instance]: Instance } = {}
	local current: any = nil
	local returning: { [Instance]: () -> () } = {}
	local state = Compose.cell(nil :: any)
	local service: any = { state = state }
	services[ctx] = service

	local function ancestor(node: Instance?): Instance?
		while node do
			if proxies[node] then
				return proxies[node]
			end
			if
				targets[node]
				and not (current and targets[node].passThrough and targets[node].passThrough(current.payload))
			then
				return node
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
		local source = current.source :: GuiObject
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
				if target:IsA("GuiObject") and available(target) and contains(target, at) then
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
	local function info(target: Instance): any
		return {
			source = current.source,
			target = target,
			mode = current.mode,
			operation = ctx.read(targets[target].operation or "move"),
			position = current.position,
			hit = current.hit,
			complete = function()
				return false
			end,
		}
	end
	local function validate(target: Instance, proposal: any): (boolean, string?)
		local spec = targets[target]
		if not spec or not available(target) then
			return false, "The destination is no longer available"
		end
		if current.spec.valid and not current.spec.valid() then
			return false, "The source changed"
		end
		if current.spec.operations and not table.find(current.spec.operations, proposal.operation) then
			return false, "This operation is not supported"
		end
		if spec.propose then
			spec.propose(current.payload, proposal)
		end
		if spec.accepts then
			return spec.accepts(current.payload, proposal)
		end
		return true, nil
	end
	local function leave(session: any)
		local target = session.target
		if target then
			target:SetAttribute("FacetDropState", nil)
			target:SetAttribute("FacetDropReason", nil)
			local spec = targets[target]
			if spec and spec.feedback then
				spec.feedback.Enabled = false
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
	function service.own(source: GuiObject)
		Compose.cleanup(function()
			if returning[source] then
				returning[source]()
			end
		end)
	end
	local function releaseGhost(session: any, accepted: boolean?)
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
		point = (point or session.origin) - session.pickupSize / 2 + ghost.AnchorPoint * session.previewSize
		local animated: Instance = ghost
		local stopScale: (() -> ())?
		local goal: any = { Position = localPoint(ghost, point) }
		if accepted then
			local scale = ghost:FindFirstChildWhichIsA("UIScale")
			if scale == nil then
				stopScale, scale = ctx.runtime.mount(function()
					return ctx.Host.UIScale {}
				end, ghost)
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
			if target and targets[target].onEnter then
				targets[target].onEnter(current.payload)
			end
		end
		current.hit = hit
		if target then
			local proposal = info(target)
			local accepted, reason = validate(target, proposal)
			target:SetAttribute("FacetDropState", if accepted then "accepted" else "rejected")
			target:SetAttribute("FacetDropReason", reason)
			local feedback = targets[target].feedback
			if feedback then
				feedback.Enabled = accepted
				if feedback:IsA("UIStroke") then
					feedback:RemoveTag("facet-drop-accepted")
					feedback:RemoveTag("facet-drop-rejected")
					feedback:AddTag(if accepted then "facet-drop-accepted" else "facet-drop-rejected")
				end
			end
			if targets[target].onUpdate then
				targets[target].onUpdate(current.payload, proposal, accepted, reason)
			end
		end
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
		destination:SetAttribute("FacetDropState", "pending")
		session.executing = true
		local ok, result = pcall(spec.onDrop, session.payload, proposal)
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
		spec: any,
		mode: string,
		press: InputObject?,
		preview: any,
		pickup: { position: Vector2, source: GuiObject }?
	)
		service.finish(false, "Replaced by another drag")
		if returning[source] then
			returning[source]()
		end
		local payload = if type(spec.payload) == "function" then spec.payload(source) else spec.payload
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
		if spec.mark ~= false then
			source:AddTag("facet-drag-held")
			source:SetAttribute("FacetDragHeld", true)
		end
		activation.consume(press)
		if mode == "pointer" and preview ~= false then
			local layer = source:FindFirstAncestorWhichIsA("LayerCollector")
			if layer then
				local ghost = (preview or source):Clone()
				local nodes = ghost:GetDescendants()
				table.insert(nodes, ghost)
				for _, node in nodes do
					if node:IsA("GuiObject") then
						node.Interactable, node.Active, node.Selectable = false, false, false
					elseif node:IsA("UIDragDetector") or node:IsA("InputContext") then
						(node :: any).Enabled = false
					end
				end
				ghost:RemoveTag("facet-drag-held")
				ghost:SetAttribute("FacetDragHeld", nil)
				ghost.Name, ghost.ZIndex, ghost.AnchorPoint = "DragGhost", 1000, anchor
				ghost:SetAttribute("FacetDragFeedback", true)
				ghost.Size = D2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
				ghost.Parent = layer
				current.previewSize = source.AbsoluteSize
				ghost.Position = localPoint(ghost, current.position or current.origin)
				current.ghost = ghost
			end
		end
		state:set(table.clone(current))
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
			if session.target and not available(session.target) then
				service.finish(false, "The destination was removed")
				return
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
					node = node.Parent
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
		if not current or current.mode ~= "pointer" then
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
		ghost.Position = localPoint(ghost, current.position or current.origin)
		current.ghost = ghost
	end

	function service.register(target: Instance, spec: any)
		local owned = table.clone(spec)
		local feedback
		if target:IsA("GuiObject") then
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
			feedback = (ctx.Host :: any).Highlight({
				Name = "FacetDropHighlight",
				Enabled = false,
				Adornee = Compose.static(target),
				DepthMode = ctx.types.Enum.HighlightDepthMode.Occluded,
			})
		end
		feedback.Parent = target
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
