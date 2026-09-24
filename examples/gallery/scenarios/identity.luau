--!strict
-- One child tab keeps individual identity and rosters together in Status.
return {
	title = "Identity",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local avatar = require("./avatar").build(ctx)
		local group = require("./avatar_group").build(ctx)
		local function reset()
			avatar.reset()
			group.reset()
		end
		return {
			reset = reset,
			steps = { reset = reset },
			screen = function()
				return UI.Screen("Identity")({
					surface = "base",
					padding = { top = "m", bottom = "m" },
					UI.ScrollView("Content")({
						width = UI.fill(),
						height = UI.fill(),
						padding = { left = "m", right = "m" },
						padding = "s",
						UI.VStack("Recipes")({
							width = UI.fill(),
							gap = "l",
							UI.Button("Reset")({ label = "Reset identity", onActivate = reset }),
							avatar.section(),
							group.section(),
						}),
					}),
				})
			end,
			report = function()
				local face, roster = avatar.report(), group.report()
				return if face and roster then { avatar = face, group = roster } else nil
			end,
			dispose = function()
				avatar.dispose()
				group.dispose()
			end,
		}
	end,
}
