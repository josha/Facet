--!strict
local Shared = require("./types")
local Nav = require("./navigation_types")
local engine = require("./travel_engine")
local ControlTypes = require("./control_types")
local ZoomTravelProps = require("./zoom_travel_props")
local reducedMotion = require("./motion").reduced

return function(ctx: Shared.Context, UI: ControlTypes.Controls, surfaces: Nav.Surfaces)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2 = ctx.types.UDim2, ctx.types.Vector2
	local function build(spec: ZoomTravelProps.TravelProps): Frame
		assert(type(spec.content) == "function", "Facet UI.Travel: content is required")
		local anchor = Host.Frame(ctx.props(spec, {
			"destination",
			"content",
			"path",
			"onLanded",
			"motion",
			"transparency",
			"stagger",
			"lift",
			"onStarted",
		}, {
			Name = "Travel",
			BackgroundTransparency = 1,
			Size = D2.fromOffset(0, 0),
		}))
		local node = spec.content()
		runtime.decorate(node, { AutomaticSize = ctx.types.Enum.AutomaticSize.None })
		local restingDepth = node.ZIndex
		local liftScale: UIScale? = nil
		if spec.lift then
			liftScale = node:FindFirstChildWhichIsA("UIScale") :: UIScale?
			if not liftScale then
				liftScale = Host.UIScale { Name = "TravelLift", Parent = Compose.static(node) }
			end
		end
		local restingScale = if liftScale then liftScale.Scale else 1
		local liftStart, lifted = 1, 1
		local styleCopy = Host.StyleLink {}
		styleCopy.Parent = node
		local reduce = reducedMotion(ctx)
		local owner = assert(Compose.currentOwner())
		local destination: GuiObject = ctx.read(spec.destination)
		local watchedDestination: GuiObject? = nil
		local releaseDestination: (() -> ())? = nil
		Compose.cleanup(function()
			if releaseDestination then
				releaseDestination()
			end
		end)
		local function retire()
			if task and task.defer then
				task.defer(Compose.owner.dispose, owner)
			else
				Compose.owner.dispose(owner)
			end
		end
		runtime.connect(node, "Destroying", retire)
		runtime.connect(anchor, "Destroying", retire)
		local previous: GuiObject? = nil
		local parent: GuiBase2d? = nil
		local overlay: GuiBase2d? = nil
		local values = { 0, 0, 0, 0, 1 }
		local target = table.clone(values)
		local inPlace = false
		local moving = false
		local motion: engine.Handle
		local units: { [GuiBase2d]: Shared.ReadOnlyValue<number> } = {}
		local function contentInsets(slot: GuiObject): (number, number, number, number)
			local unit = 1
			local at: Instance? = slot
			while at do
				local scale = at:FindFirstChildWhichIsA("UIScale") :: UIScale?
				if scale then
					unit *= scale:GetStyled("Scale") :: number
				end
				at = at.Parent
			end
			local border = if (slot:GetStyled("BorderMode") :: Enum.BorderMode) == ctx.types.Enum.BorderMode.Inset
				then (slot:GetStyled("BorderSizePixel") :: number) * unit
				else 0
			local left, top, right, bottom = border, border, border, border
			local padding = slot:FindFirstChildWhichIsA("UIPadding") :: UIPadding?
			if padding then
				local size = slot.AbsoluteSize
				local function pixels(property: string, dimension: number): number
					local value = padding:GetStyled(property) :: UDim
					return value.Scale * math.max(0, dimension - border * 2) + value.Offset * unit
				end
				left += pixels("PaddingLeft", size.X)
				right += pixels("PaddingRight", size.X)
				top += pixels("PaddingTop", size.Y)
				bottom += pixels("PaddingBottom", size.Y)
			end
			return left, top, right, bottom
		end
		local function bounds(slot: GuiObject): { number }
			local point, size = slot.AbsolutePosition, slot.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				point = V2.new(slot.Position.X.Offset, slot.Position.Y.Offset)
				size = V2.new(slot.Size.X.Offset, slot.Size.Y.Offset)
			end
			local left, top, right, bottom = contentInsets(slot)
			return {
				point.X + left,
				point.Y + top,
				math.max(0, size.X - left - right),
				math.max(0, size.Y - top - bottom),
				1,
			}
		end
		local function common(a: GuiObject, b: GuiObject): GuiBase2d?
			local ancestors: { Instance } = {}
			local at: Instance? = a.Parent
			while at do
				table.insert(ancestors, at)
				at = at.Parent
			end
			at = b.Parent
			while at and not table.find(ancestors, at) do
				at = at.Parent
			end
			local root = at
			local function clear(slot: GuiObject): boolean
				local current: Instance? = slot
				while current do
					if
						current:FindFirstChildWhichIsA("UIScale")
						or (current:IsA("GuiObject") and current.ClipsDescendants)
					then
						return false
					end
					current = current.Parent
				end
				return true
			end
			return if root
					and root:IsA("GuiBase2d")
					and not root:FindFirstChildWhichIsA("UILayout")
					and clear(a)
					and clear(b)
				then root
				else nil
		end
		local function paint(sample: { number })
			if Compose.owner.isDisposed(owner) then
				return
			end
			if previous and (destination.Parent == nil or node.Parent == nil) then
				Compose.owner.dispose(owner)
				return
			end
			values = table.clone(sample)
			local container = parent
			if not container then
				return
			end
			local unit = math.max(units[container]:peek(), 0.001)
			local progress = math.clamp(sample[5], 0, 1)
			lifted = if moving and spec.lift
				then liftStart
					+ (1 - liftStart) * progress
					+ (ctx.metric("motion.scales.travelLift") - 1) * 4 * progress * (1 - progress)
				else 1
			if liftScale then
				liftScale.Scale = restingScale * lifted
			end
			local arc = if spec.path == "arc" and spec.motion ~= "spring"
				then -4 * ctx.metric("motion.distances.travelArc") * sample[5] * (1 - sample[5])
				else 0
			values[2] += arc * unit
			local origin = container.AbsolutePosition
			if container:IsA("ScrollingFrame") then
				origin -= container.CanvasPosition
			end
			if container:IsA("GuiObject") then
				local left, top = contentInsets(container)
				origin += V2.new(left, top)
			end
			node.Position = D2.fromOffset(
				(sample[1] - origin.X - sample[3] * (lifted - 1) / 2) / unit,
				(sample[2] - origin.Y - sample[4] * (lifted - 1) / 2) / unit + arc
			)
			node.Size = D2.fromOffset(sample[3] / unit, sample[4] / unit)
			node.Visible = true
			if node.Parent ~= container then
				node.Parent = container
			end
		end
		local function land()
			if Compose.owner.isDisposed(owner) or destination.Parent == nil then
				Compose.owner.dispose(owner)
				return
			end
			moving = false
			local depth = restingDepth
			local ownDepth = destination:GetStyled("ZIndex") :: number
			if ownDepth > restingDepth or destination:IsA("GuiButton") then
				depth = math.max(depth, ownDepth + 1)
			end
			for _, child in destination:GetDescendants() do
				if child:IsA("GuiObject") and child ~= node and not child:IsDescendantOf(node) then
					local paintDepth = child:GetStyled("ZIndex") :: number
					if paintDepth >= restingDepth then
						depth = math.max(depth, paintDepth + 1)
					end
				end
			end
			node.ZIndex = depth
			liftStart, lifted = 1, 1
			if not inPlace then
				parent = destination
				if not units[destination] then
					Compose.withOwner(owner, function()
						units[destination] = ctx.layoutUnit(destination)
					end)
				end
			end
			motion.snap(target)
			previous = destination
			anchor:SetAttribute("FacetTravelMoving", false)
			if spec.onLanded then
				spec.onLanded(destination)
			end
		end
		local function raise()
			local floor = restingDepth
			local container = parent
			if container then
				for _, sibling in container:GetChildren() do
					if sibling:IsA("GuiObject") and sibling ~= node then
						floor = math.max(floor, sibling.ZIndex)
					end
				end
			end
			node.ZIndex = floor + motion.depth
		end
		motion = engine(ctx, {
			initial = values,
			carrier = node,
			target = function()
				local goal = bounds(destination)
				if spec.path == "arc" and spec.motion == "spring" then
					local unit = if parent and units[parent] then units[parent]:peek() else 1
					goal[2] -= 4 * ctx.metric("motion.distances.travelArc") * unit * values[5] * (1 - values[5])
				end
				return goal
			end,
			sample = paint,
			complete = land,
			start = function()
				if spec.onStarted then
					spec.onStarted(destination)
				end
			end,
			delay = function()
				local index = if type(spec.stagger) == "function" then spec.stagger() else spec.stagger or 0
				assert(index >= 0 and index < math.huge, "Facet UI.Travel: stagger must be finite and nonnegative")
				return index * ctx.metric("motion.durations.travelStagger")
			end,
			reduced = reduce,
			motion = spec.motion or "ease",
			duration = ctx.metric("motion.durations.travel"),
			ease = ctx.motionEase("travel"),
			spring = ctx.motionSpring("travel"),
		})
		motion.snap(values)
		local function retarget()
			if Compose.owner.isDisposed(owner) then
				return
			end
			if previous and node.Parent == nil then
				Compose.owner.dispose(owner)
				return
			end
			if not destination.Parent then
				if previous then
					Compose.owner.dispose(owner)
					return
				end
				node.Visible = false
				return
			end
			target = bounds(destination)
			if previous == destination and not moving then
				motion.snap(target)
				return
			end
			if not moving and previous and node.AbsoluteSize.X > 0 and node.AbsoluteSize.Y > 0 then
				values =
					{ node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y, 1 }
			end
			if target[3] <= 0 or target[4] <= 0 then
				return
			end
			if not moving and previous and previous ~= destination then
				local settled = true
				for index = 1, 4 do
					settled = settled and math.abs(values[index] - target[index]) < 0.5
				end
				if settled then
					inPlace = false
					land()
					return
				end
			end
			local same = if previous then common(previous, destination) else common(destination, destination)
			inPlace = same ~= nil
			parent = same or overlay
			if not parent then
				if previous == nil and not moving then
					land()
				end
				return
			end
			if not units[parent] then
				local container = parent
				Compose.withOwner(owner, function()
					units[container] = ctx.layoutUnit(container)
				end)
			end
			if previous == nil and not moving then
				land()
			else
				liftStart = lifted
				moving = true
				values[5] = 0
				raise()
				paint(values)
				motion.rebase(values)
				anchor:SetAttribute("FacetTravelMoving", true)
				motion.retarget()
			end
		end
		local portal = surfaces.overlay(anchor, true, function(): Instance
			overlay = surfaces.parent(anchor)
			if overlay and not units[overlay] then
				local container = overlay
				Compose.withOwner(owner, function()
					units[container] = ctx.layoutUnit(container)
				end)
			end
			local holder = Host.Folder { Name = "TravelPortal" }
			runtime.connect(
				holder,
				"ChildAdded",
				Compose.bindOwner(function(child: Instance)
					if child:IsA("StyleLink") then
						local source = child
						styleCopy.StyleSheet = source.StyleSheet
						runtime.connect(source, "Changed", function(property: string)
							if property == "StyleSheet" and not Compose.owner.isDisposed(owner) then
								styleCopy.StyleSheet = source.StyleSheet
							end
						end)
					end
				end)
			)
			retarget()
			return holder
		end)
		runtime.mountFragment(function()
			return { portal }
		end, anchor)
		Compose.watch(function(use: Shared.Use)
			local next: GuiObject = ctx.read(spec.destination, use)
			assert(next:IsA("GuiObject"), "Facet UI.Travel: destination must be a GuiObject")
			ctx.read(ctx.observe.AbsolutePosition(next), use)
			ctx.read(ctx.observe.AbsoluteSize(next), use)
			ctx.read(ctx.observe.Position(next), use)
			if watchedDestination ~= next then
				if releaseDestination then
					releaseDestination()
				end
				watchedDestination = next
				Compose.withOwner(owner, function()
					releaseDestination = runtime.connect(next, "Destroying", retire)
				end)
			end
			local changed = destination ~= next
			destination = next
			if moving and not changed then
				target = bounds(destination)
			else
				retarget()
			end
		end)
		runtime.connect(anchor, "AncestryChanged", retarget)
		Compose.watch(function(use: Shared.Use)
			if reduce(use) and moving then
				motion.retarget()
			end
		end)
		if spec.transparency then
			assert(node:IsA("CanvasGroup"), "Facet UI.Travel: transparency requires CanvasGroup content")
			local group = node
			local fade = runtime.tween(function(use: Shared.Use)
				return ctx.read(spec.transparency, use)
			end, {
				seconds = ctx.metric("motion.durations.travelFade"),
				ease = ctx.motionEase("travel"),
				reducedMotion = reduce,
			})
			Compose.watch(function(use: Shared.Use)
				group.GroupTransparency = use(fade)
			end)
		end
		return anchor
	end
	UI.Travel = ctx.construct("Travel", function(spec: ZoomTravelProps.TravelProps): Frame
		local owner = Compose.owner.createChild(assert(Compose.currentOwner()))
		return Compose.withOwner(owner, function(): Frame
			return build(spec)
		end)
	end)
end
