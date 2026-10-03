--!strict

local Facet = require(game.ReplicatedStorage.Facet)
local component = require(script.Parent:WaitForChild("Wall"))

return {
	name = "Wall",
	previews = {
		{
			name = "Design",
			render = function(ctx: { UI: Facet.Controls })
				return component(ctx.UI)
			end,
		},
	},
}
