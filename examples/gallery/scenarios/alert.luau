--!strict
return {
	title = "Alerts and confirmations",
	ledgerRows = {},
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local status = Compose.cell("The save is ready to replace.")
		local presented = Compose.cell(false)
		local function open()
			presented:set(true)
			return true
		end
		local function reset()
			presented:set(false)
			status:set("The save is ready to replace.")
		end
		local function Example()
			return Host.Frame({
				Name = "Alert",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame({
					Name = "Page",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					UI.Label({
						LayoutOrder = 1,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = "Alerts and confirmations",
						TextSize = 28,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 2,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = "A brief decision stays compact. Cancel leads a desktop row; phones and televisions stack the actions with cancel last.",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 3,
						Name = "Status",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = status,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Button({
						LayoutOrder = 4,
						Name = "Open",
						label = "Replace checkpoint…",
						onActivate = open,
					}),
					UI.Button({
						LayoutOrder = 5,
						Name = "Reset",
						label = "Reset",
						onActivate = reset,
					}),
				}),
				UI.Alert({
					Name = "ReplaceSave",
					title = "Replace this save?",
					severity = "critical",
					message = "Your current progress will replace the previous checkpoint.",
					isPresented = presented,
					actions = {
						{
							id = "Cancel",
							label = "Keep previous",
							role = "cancel",
							onActivate = function()
								status:set("Previous save kept.")
							end,
						},
						{
							id = "Replace",
							label = "Replace save",
							role = "destructive",
							onActivate = function()
								status:set("Checkpoint replaced.")
							end,
						},
					},
				}),
			})
		end
		return {
			screen = Example,
			steps = { open = open, reset = reset },
			states = function()
				return { { id = "confirmation", kind = "dialog", open = open } }
			end,
			report = function()
				return { status = status:peek(), alert = { presented = presented:peek() } }
			end,
			dispose = function() end,
		}
	end,
}
