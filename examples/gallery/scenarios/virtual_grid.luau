--!strict
local build = require("./collection_demo")
return {
	title = "Lazy grid",
	build = function(ctx)
		return build(ctx, { name = "virtual_grid", title = "Lazy grid", count = 5000, grid = true })
	end,
}
