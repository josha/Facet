--!strict
local build = require("./collection_demo")
return {
	title = "Measured item extents",
	build = function(ctx)
		return build(ctx, { name = "measured_extents", title = "Measured item extents", count = 400, measure = true })
	end,
}
