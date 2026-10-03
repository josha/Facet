--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
return {
	title = "Cartwheel",
	build = function(ctx: ExampleContext)
		local module = ctx.load("reference", "p2_cartwheel")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
