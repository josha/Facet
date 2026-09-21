--!strict
-- One child tab keeps individual identity and rosters together in Indicators.
return {
	title = "Identity",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local avatar = require("./avatar").build(ctx)
		local group = require("./avatar_group").build(ctx)
		return {
			screen = function()
				return UI.Screen("Identity")({
					surface = "base",
					padding = "m",
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = "s",
						UI.VStack("Recipes")({ width = UI.fill(), gap = "l", avatar.section(), group.section() }),
					}),
				})
			end,
			report = function()
				return { avatar = avatar.report(), group = group.report() }
			end,
			dispose = function()
				avatar.dispose()
				group.dispose()
			end,
		}
	end,
}
