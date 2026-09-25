local STOPS = { 1, 0.7, 0.4, 0.15 }
return {
	title = "Canvas group: one fade, or three",
	build = function(ctx)
		local Host, UI, Compose = ctx.Host, ctx.UI, ctx.Compose
		local UDim, UDim2, Vector2, Color3, Enum =
			ctx.types.UDim, ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
		local opacity, showing = Compose.cell(0.4), Compose.cell(false)
		local fade = ctx.runtime.tween(function(use)
			return if use(showing) then 0 else 1
		end, { seconds = 0.2 })
		local colors = { Color3.fromRGB(65, 130, 220), Color3.fromRGB(220, 75, 95), Color3.fromRGB(240, 235, 225) }
		local function plates(individual)
			local nodes = {}
			for index, size in { 132, 92, 52 } do
				nodes[index] = Host.CanvasGroup({
					Name = "Plate" .. index,
					Size = UDim2.fromOffset(size, size),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = colors[index],
					BorderSizePixel = 0,
					GroupTransparency = if individual
						then function(use)
							return 1 - use(opacity)
						end
						else 0,
				})
			end
			return table.unpack(nodes)
		end
		local function screen()
			local choices = {}
			for _, value in STOPS do
				table.insert(
					choices,
					UI.Button({
						label = string.format("%d%%", value * 100),
						onActivate = function()
							opacity:set(value)
						end,
					})
				)
			end
			return Host.ScrollingFrame "CanvasGroupDemo" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
				UI.Text({ LayoutOrder = 1, text = "One fade, or three", TextSize = 24 }),
				UI.Text({
					LayoutOrder = 2,
					text = "The same plates and opacity. One CanvasGroup composites the image before fading it; separate groups reveal every overlap.",
				}),
				Host.Frame({
					LayoutOrder = 3,
					Name = "Stops",
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundTransparency = 1,
					Host.UIListLayout({
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 8),
					}),
					table.unpack(choices),
				}),
				UI.Text({ LayoutOrder = 4, text = "One group" }),
				Host.CanvasGroup({
					LayoutOrder = 5,
					Name = "OneGroup",
					Size = UDim2.fromOffset(180, 160),
					BackgroundTransparency = 1,
					GroupTransparency = function(use)
						return 1 - use(opacity)
					end,
					plates(false),
				}),
				UI.Text({ LayoutOrder = 6, text = "Three groups" }),
				Host.Frame({
					LayoutOrder = 7,
					Name = "ManyGroups",
					Size = UDim2.fromOffset(180, 160),
					BackgroundTransparency = 1,
					plates(true),
				}),
				UI.Button({
					LayoutOrder = 8,
					Name = "Show",
					label = "Show / hide the fading panel",
					onActivate = function()
						showing:set(not showing:peek())
					end,
				}),
				Host.CanvasGroup({
					LayoutOrder = 9,
					Name = "Arrival",
					Size = UDim2.new(1, 0, 0, 64),
					BackgroundColor3 = colors[1],
					GroupTransparency = fade,
					UI.Text({ text = "Compose owns the tween; CanvasGroup owns the compositing." }),
				}),
			}
		end
		return {
			screen = screen,
			opacity = opacity,
			steps = {
				show = function()
					showing:set(not showing:peek())
				end,
			},
			report = function()
				return { opacity = opacity:peek(), showing = showing:peek() }
			end,
		}
	end,
}
