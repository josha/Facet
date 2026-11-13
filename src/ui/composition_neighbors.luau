--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")
local Placement = require("./overlay_placement")

export type Neighbor = {
	position: ComposeTypes.ReadOnlyValue<Vector2>,
	size: ComposeTypes.ReadOnlyValue<Vector2>,
	shown: ComposeTypes.ReadOnlyValue<boolean>,
}

local neighbors = {}

function neighbors.of(ctx: Types.Context, inside: GuiObject): { Neighbor }
	local own: Instance? = inside
	local zones: Instance? = nil
	while own do
		local zone = own.Parent
		local above = if zone then zone.Parent else nil
		if type(own:GetAttribute("FacetForm")) == "number" and above and above.Name == "Zones" then
			zones = above
			break
		end
		own = zone
	end
	local found: { Neighbor } = {}
	if zones == nil then
		return found
	end
	local function add(node: Instance)
		if node ~= own and node:IsA("GuiObject") then
			table.insert(found, {
				position = ctx.observe.AbsolutePosition(node),
				size = ctx.observe.AbsoluteSize(node),
				shown = ctx.observe.Visible(node),
			})
		end
	end
	for _, child in zones:GetChildren() do
		if child:IsA("GuiButton") then
			add(child)
		else
			for _, region in child:GetChildren() do
				if type(region:GetAttribute("FacetForm")) == "number" then
					add(region)
				end
			end
		end
	end
	return found
end

function neighbors.rects(found: { Neighbor }, origin: Vector2, use: ComposeTypes.Use): { Placement.Rect }
	local rects: { Placement.Rect } = {}
	for _, neighbor in found do
		local size = use(neighbor.size)
		if use(neighbor.shown) and size.X > 0 and size.Y > 0 then
			local at = use(neighbor.position)
			table.insert(rects, { x = at.X - origin.X, y = at.Y - origin.Y, w = size.X, h = size.Y })
		end
	end
	return rects
end

return neighbors
