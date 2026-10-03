--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local component = require(script.Parent:WaitForChild("Furnish"))

return {
	name = "Furnish",
	previews = {
		{
			name = "Design",
			render = function(ctx: { UI: Facet.Controls })
				return component(ctx.UI)
			end,
		},
	},
}
