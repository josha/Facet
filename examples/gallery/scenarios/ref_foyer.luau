--!strict
type ExampleContext = typeof(require("@repo/examples/types").Context)
return {
	title = "Foyer",
	build = function(ctx: ExampleContext)
		local module = ctx.load("reference", "p4_foyer")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
