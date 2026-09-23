--!strict
return {
	title = "Foyer",
	build = function(ctx)
		local module = ctx.load("reference", "p4_foyer")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
