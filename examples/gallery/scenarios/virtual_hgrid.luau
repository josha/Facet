--!strict
local build = require("./collection_demo")
return {
	title = "Lazy grid, sideways",
	build = function(ctx)
		return build(
			ctx,
			{ name = "virtual_hgrid", title = "Lazy grid, sideways", count = 5000, grid = true, horizontal = true }
		)
	end,
}
