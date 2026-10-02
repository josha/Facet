--!strict

return {
	title = "Identity",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose: typeof(require("@repo/src/vendor/compose/core")) = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
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
						} :: unknown,
						avatar.section(),
						group.section(),
					},
				}
			end,
			report = function()
				local face, roster = avatar.report(), group.report()
				return if face and roster then { avatar = face, group = roster } else nil
			end,
			dispose = function()
				local avatarCleanup = (avatar :: unknown) :: { dispose: (() -> ())? }
				local groupCleanup = (group :: unknown) :: { dispose: (() -> ())? }
				if avatarCleanup.dispose then
					avatarCleanup.dispose()
				end
				if groupCleanup.dispose then
					groupCleanup.dispose()
				end
			end,
		}
	end,
}
