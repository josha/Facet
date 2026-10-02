--!strict
type ExampleContext = typeof(require("@repo/examples/types")(nil :: any))
return {
	title = "Glade",
	build = function(ctx: ExampleContext)
		local module = ctx.load("reference", "p1_glade")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
