--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

return {
	title = "Identity",
	ledgerRows = {},
	build = function(ctx: ExampleContext)
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose: ComposeModule = ctx.Compose
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
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
				return Host.Frame "Identity" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					UI.ScrollView "Content" {
						padding = 16,
						gap = 24,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						ScrollBarThickness = 6,
						UI.Button "Reset" {
							label = "Reset identity",
							onActivate = reset,
						},
						avatar.section(),
						group.section(),
					},
				}
			end,
			report = function()
				local face, roster = avatar.report(), group.report()
				return if face and roster then { avatar = face, group = roster } else nil
			end,
		}
	end,
}
