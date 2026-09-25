--!strict
local build = require("./collection_demo")
return {
	title = "Variable item extents",
	build = function(ctx)
		return build(ctx, { name = "variable_extents", title = "Variable item extents", count = 400, variable = true })
	end,
}
