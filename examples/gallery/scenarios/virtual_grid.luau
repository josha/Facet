--!strict
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
local build = require("./collection_demo")
return {
	title = "Lazy grid",
	build = function(ctx: ExampleContext)
		return build(ctx, { name = "virtual_grid", title = "Lazy grid", count = 5000, grid = true })
	end,
}
