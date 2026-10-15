--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
local build = require("./collection_demo")
return {
	title = "Variable item extents",
	build = function(ctx: ExampleContext): Built
		return build(ctx, { name = "variable_extents", title = "Variable item extents", count = 400, variable = true })
	end,
}
