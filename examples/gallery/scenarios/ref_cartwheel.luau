--!strict
return {
	title = "Cartwheel",
	build = function(ctx)
		local module = ctx.load("reference", "p2_cartwheel")
		assert(module, "Reference application is not replicated")
		return module.build(ctx)
	end,
}
