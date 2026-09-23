--!strict
return {
	title = "Sipworks",
	build = function(ctx)
		local module = ctx.load("reference", "p3_sipworks")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
