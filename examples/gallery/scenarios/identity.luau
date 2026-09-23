--!strict

return {
	title = "Identity",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose = ctx.Compose
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
				return Host.Frame({
					Name = "Identity",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame({
						Name = "Content",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIPadding({
							PaddingTop = UDim.new(0, 8),
							PaddingBottom = UDim.new(0, 8),
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
						Host.Frame({
							Name = "Recipes",
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 24),
							}),
							UI.Button({

								Name = "Reset",
								label = "Reset identity",
								onActivate = reset,
							}),
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
				if avatar.dispose then
					avatar.dispose()
				end
				if group.dispose then
					group.dispose()
				end
			end,
		}
	end,
}
