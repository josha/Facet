--!strict
local Types = require("./types")
local ComposeTypes = require("../vendor/compose/core")

type Surfaces = ComposeTypes.Value<{ [GuiObject]: boolean }>

local registries = setmetatable({} :: { [Types.Context]: Surfaces }, { __mode = "k" })

local function registry(ctx: Types.Context): Surfaces
	local surfaces = registries[ctx]
	if surfaces == nil then
		local created: Surfaces = ctx.Compose.cell({})
		registries[ctx] = created
		return created
	end
	return surfaces
end

local function mark(ctx: Types.Context, surface: GuiObject, preparing: boolean)
	surface:SetAttribute("FacetPreparing", preparing)
	local surfaces = registry(ctx)
	if (surfaces:peek()[surface] == true) == preparing then
		return
	end
	local next = table.clone(surfaces:peek())
	if preparing then
		next[surface] = true
	else
		next[surface] = nil
	end
	surfaces:set(next)
end

local function begin(ctx: Types.Context, surface: GuiObject)
	mark(ctx, surface, true)
	ctx.Compose.cleanup(function()
		local surfaces = registry(ctx)
		if surfaces:peek()[surface] then
			local next = table.clone(surfaces:peek())
			next[surface] = nil
			surfaces:set(next)
		end
	end)
end

local function within(ctx: Types.Context, root: Instance, use: ComposeTypes.Use): boolean
	for surface in use(registry(ctx)) do
		if surface:IsDescendantOf(root) then
			return true
		end
	end
	return false
end

return {
	begin = begin,
	finish = function(ctx: Types.Context, surface: GuiObject)
		mark(ctx, surface, false)
	end,
	within = within,
}
