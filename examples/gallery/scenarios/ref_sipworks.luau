--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
return {
	title = "Sipworks",
	build = function(ctx: ExampleContext)
		local module = ctx.load("reference", "p3_sipworks")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
