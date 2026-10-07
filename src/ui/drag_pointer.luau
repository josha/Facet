--!strict
local Types = require("./types")

return function(ctx: Types.Context, position: Vector2): Vector2
	local gui = ctx.config.guiService
	local parent = ctx.config.inputParent
	if gui and gui.GetGuiInset and not (parent and parent:IsA("PluginGui")) then
		return position - gui:GetGuiInset()
	end
	return position
end
