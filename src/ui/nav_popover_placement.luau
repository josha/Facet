--!strict
local Types = require("./types")
local Nav = require("./navigation_types")
local ComposeTypes = require("../vendor/compose/core")
local materialize = require("./materialize")

export type Popover = (
	GuiObject,
	Nav.Appearance,
	(ComposeTypes.Use) -> (Vector2, Vector2),
	Nav.PopoverOptions?
) -> (ComposeTypes.Use) -> number

return function(ctx: Types.Context): Popover
	local runtime = ctx.runtime
	local D2, V2 = ctx.types.UDim2, ctx.types.Vector2
	local function popover(
		panel: GuiObject,
		amount: Nav.Appearance,
		place: (ComposeTypes.Use) -> (Vector2, Vector2),
		options: Nav.PopoverOptions?
	): (ComposeTypes.Use) -> number
		local settings: Nav.PopoverOptions = options or {}
		local rested = settings.rested
		local rise = settings.rise
		local parent = ctx.observe.Parent(panel)
		local function position(use: ComposeTypes.Use, x: number, y: number): UDim2
			local container = use(parent)
			while container and not container:IsA("GuiBase2d") do
				container = container.Parent
			end
			local extent = if container and container:IsA("GuiBase2d") then container.AbsoluteSize else V2.zero
			local left, top = math.floor(x), math.floor(y)
			return D2.new(
				if extent.X > 0 then (x - left) / extent.X else 0,
				if extent.X > 0 then left else x,
				if extent.Y > 0 then (y - top) / extent.Y else 0,
				if extent.Y > 0 then top else y
			)
		end
		local function scale(use: ComposeTypes.Use): number
			if panel:HasTag("facet-menu") or panel:HasTag("facet-popover") or panel:HasTag("facet-tooltip") then
				return 1
			end
			if (rested and not use(rested)) or (rise and rise(use) ~= nil) then
				return 1
			end
			local from = settings.from or ctx.metric("motion.materialize.anchored", use)
			return from + (1 - from) * amount(use)
		end
		if settings.pinned then
			local size = settings.size or ctx.observe.AbsoluteSize(panel)
			runtime.decorate(panel, {
				AnchorPoint = function(use: ComposeTypes.Use)
					if rise and rise(use) ~= nil then
						return V2.zero
					end
					local _, origin = place(use)
					local box = use(size)
					return V2.new(
						if box.X > 0 then math.clamp(origin.X / box.X, 0, 1) else 0,
						if box.Y > 0 then math.clamp(origin.Y / box.Y, 0, 1) else 0
					)
				end,
				Position = function(use: ComposeTypes.Use)
					local at, origin = place(use)
					local distance = if rise then rise(use) else nil
					return if distance
						then position(use, at.X, at.Y + distance * (1 - amount(use)))
						else position(use, at.X + origin.X, at.Y + origin.Y)
				end,
			})
		else
			runtime.decorate(panel, {
				Position = function(use: ComposeTypes.Use)
					local at, origin = place(use)
					local distance = if rise then rise(use) else nil
					if distance then
						return position(use, at.X, at.Y + distance * (1 - amount(use)))
					end
					local shrink = 1 - scale(use)
					return position(use, at.X + origin.X * shrink, at.Y + origin.Y * shrink)
				end,
			})
		end
		materialize(ctx, panel, assert(settings.geometry), scale, function(use: ComposeTypes.Use)
			local _, point = place(use)
			local box = if settings.size then use(settings.size) else panel.AbsoluteSize
			return V2.new(if box.X > 0 then point.X / box.X else 0.5, if box.Y > 0 then point.Y / box.Y else 0.5)
		end, panel:HasTag("facet-menu") or panel:HasTag("facet-popover") or panel:HasTag("facet-tooltip"))
		return scale
	end
	return popover
end
