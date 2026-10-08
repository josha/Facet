--!strict
local Shared = require("./types")
local Types = require("./zoom_travel_types")
local Nav = require("./navigation_types")
local engine = require("./travel_engine")
local reducedMotion = require("./motion").reduced

return function(ctx: Shared.Context, UI: Types.Controls, surfaces: Nav.Surfaces)
	local Compose, Host, runtime = ctx.Compose, ctx.Host, ctx.runtime
	local D2, V2 = ctx.types.UDim2, ctx.types.Vector2
	UI.Travel = ctx.construct("Travel", function(spec: Types.TravelProps): Frame
		assert(type(spec.content) == "function", "Facet UI.Travel: content is required")
		local anchor =
			Host.Frame(ctx.props(spec, { "destination", "content", "path", "onLanded", "motion", "transparency" }, {
				Name = "Travel",
				BackgroundTransparency = 1,
				Size = D2.fromOffset(0, 0),
			}))
		local node = spec.content()
		local styleCopy = Host.StyleLink {}
		styleCopy.Parent = node
		local reduce = reducedMotion(ctx)
		local owner = assert(Compose.currentOwner())
		local destination: GuiObject = ctx.read(spec.destination)
		local previous: GuiObject? = nil
		local parent: GuiBase2d? = nil
		local overlay: GuiBase2d? = nil
		local values = { 0, 0, 0, 0, 1 }
		local target = table.clone(values)
		local inPlace = false
		local moving = false
		local motion: engine.Handle
		local units: { [GuiBase2d]: Shared.Readable<number> } = {}
		local function bounds(slot: GuiObject): { number }
			local point, size = slot.AbsolutePosition, slot.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				point = V2.new(slot.Position.X.Offset, slot.Position.Y.Offset)
				size = V2.new(slot.Size.X.Offset, slot.Size.Y.Offset)
			end
			return { point.X, point.Y, size.X, size.Y, 1 }
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
				while current and current ~= root do
					if
						current:FindFirstChildWhichIsA("UIScale")
						or (current:IsA("GuiObject") and (current :: GuiObject).ClipsDescendants)
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
				then root :: GuiBase2d
				else nil
		end
		local function paint(sample: { number })
			if owner.isDisposed() then
				return
			end
			values = table.clone(sample)
			local container = parent
			if not container then
				return
			end
			local unit = math.max(units[container]:peek(), 0.001)
			local arc = if spec.path == "arc" and spec.motion ~= "spring"
				then -4 * ctx.metric("motion.distances.travelArc") * sample[5] * (1 - sample[5])
				else 0
			values[2] += arc * unit
			node.Position = D2.fromOffset(
				(sample[1] - container.AbsolutePosition.X) / unit,
				(sample[2] - container.AbsolutePosition.Y) / unit + arc
			)
			node.Size = D2.fromOffset(sample[3] / unit, sample[4] / unit)
			node.Visible = destination.Parent ~= nil
			if node.Parent ~= container then
				node.Parent = container
			end
		end
		local function land()
			moving = false
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
			reduced = reduce,
			motion = spec.motion or "ease",
			duration = ctx.metric("motion.durations.travel"),
			ease = ctx.motionEase("travel"),
			spring = ctx.motionSpring("travel"),
		})
		local function retarget()
			if owner.isDisposed() then
				return
			end
			if not destination.Parent then
				node.Visible = false
				return
			end
			target = bounds(destination)
			if not moving and previous and node.AbsoluteSize.X > 0 and node.AbsoluteSize.Y > 0 then
				values =
					{ node.AbsolutePosition.X, node.AbsolutePosition.Y, node.AbsoluteSize.X, node.AbsoluteSize.Y, 1 }
			end
			if target[3] <= 0 or target[4] <= 0 then
				return
			end
			local same = if previous then common(previous, destination) else common(destination, destination)
			inPlace = same ~= nil
			parent = same or overlay
			if not parent then
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
				moving = true
				values[5] = 0
				motion.rebase(values)
				anchor:SetAttribute("FacetTravelMoving", true)
				motion.retarget()
			end
		end
		local portal = surfaces.overlay(anchor, true, function(): Instance
			overlay = surfaces.parent(anchor)
			local holder = Host.Folder { Name = "TravelPortal" }
			runtime.connect(holder, "ChildAdded", function(child: Instance)
				if child:IsA("StyleLink") then
					local source = child :: StyleLink
					styleCopy.StyleSheet = source.StyleSheet
					runtime.connect(source, "Changed", function(property: string)
						if property == "StyleSheet" and not owner.isDisposed() then
							styleCopy.StyleSheet = source.StyleSheet
						end
					end)
				end
			end)
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
			destination = next
			retarget()
		end)
		runtime.connect(anchor, "AncestryChanged", retarget)
		Compose.watch(function(use: Shared.Use)
			if reduce(use) and moving then
				motion.retarget()
			end
		end)
		if spec.transparency then
			assert(node:IsA("CanvasGroup"), "Facet UI.Travel: transparency requires CanvasGroup content")
			local group = node :: CanvasGroup
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
	end)
end
