--!strict
return {
	title = "Glade",
	build = function(ctx)
		local module = ctx.load("reference", "p1_glade")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
