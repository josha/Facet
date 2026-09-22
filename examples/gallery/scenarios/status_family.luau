--!strict
-- Existing passive-status recipes share one scrolling tab and one reset.
return {
	title = "Status",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local marks = require("./status_indicator").build(ctx)
		local badges = require("./badge").build(ctx)
		local function reset()
			marks.reset()
			badges.reset()
		end
		return {
			screen = function()
				return UI.Screen("StatusFamily")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						UI.VStack("Recipes")({
							width = UI.fill(),
							gap = "l",
							UI.Button("Reset")({ label = "Reset status", onActivate = reset }),
							marks.section(),
							badges.section(),
						}),
					}),
				})
			end,
			reset = reset,
			steps = { reset = reset },
			report = function()
				local status, badge = marks.report(), badges.report()
				return if status and badge then { status = status, badge = badge } else nil
			end,
		}
	end,
}
