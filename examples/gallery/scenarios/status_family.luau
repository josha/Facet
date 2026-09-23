--!strict

return {
	title = "Status",
	ledgerRows = {},
	build = function(ctx: any)
		local UI = ctx.UI
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local marks = require("./status_indicator").build(ctx)
		local badges = require("./badge").build(ctx)
		local function reset()
			marks.reset()
			badges.reset()
		end
		return {
			screen = function()
				return Host.Frame({
					Name = "StatusFamily",
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
								label = "Reset status",
								onActivate = reset,
							}),
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
