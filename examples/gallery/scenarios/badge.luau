--!strict
return {
	title = "Badges",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local status, rung = Compose.cell("neutral"), Compose.cell("compact")
		local rootPath, controller, record
		local function report()
			return { status = status:peek(), controlSize = rung:peek() }
		end
		local function choose(word)
			status:set(word)
			return report()
		end
		local function reset()
			status:set("neutral")
			rung:set("compact")
		end
		local function section()
			Compose.cleanup(function()
				rootPath, controller, record = nil, nil, nil
			end)
			local root = Host.Frame "BadgeRecipe" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Small labels",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Text({
					LayoutOrder = 2,
					Name = "Guide",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Badges identify something. They do not take focus or run actions.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({
					LayoutOrder = 3,
					Name = "Forms",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 12),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Wraps = true,
					}),
					UI.Badge({
						LayoutOrder = 1,
						Name = "Standard",
						label = "Ready",
						icon = "status.info",
						status = status,
						controlSize = rung,
						ref = function(value)
							record = value
						end,
					}),
					UI.Badge({
						LayoutOrder = 2,
						Name = "Marked",
						label = "Server",
						appearance = "status",
						status = status,
						controlSize = rung,
					}),
					UI.Badge({
						LayoutOrder = 3,
						Name = "Utility",
						label = "Beta",
						appearance = "utility",
						icon = "status.info",
						controlSize = rung,
					}),
					UI.Badge({
						LayoutOrder = 4,
						Name = "Media",
						label = "Featured",
						icon = "status.success",

						status = status,
						controlSize = rung,
					}),
				}),
				UI.Picker "Status" {
					LayoutOrder = 4,
					label = "Status",
					selected = status,
					options = {
						{ value = "neutral", label = "Neutral" },
						{ value = "warning", label = "Warning" },
						{ value = "error", label = "Error" },
					},
				},
				UI.Picker "Size" {
					LayoutOrder = 5,
					label = "Size",
					selected = rung,
					options = {
						{ value = "compact", label = "Compact" },
						{ value = "large", label = "Large" },
					},
				},
				Host.Frame({
					LayoutOrder = 6,
					Name = "Hosts",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 24),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Wraps = true,
					}),
					UI.badged(UI.Button({ Name = "Inbox", LayoutOrder = 1, label = "Inbox" }), 120),
					UI.badged(UI.Button({ Name = "Alerts", LayoutOrder = 2, label = "Alerts", icon = "menu" }), true),
					UI.badged(UI.Avatar({ Name = "Friend", LayoutOrder = 3, name = "Alder" }), 3),
				}),
			}
			return root
		end
		return {
			section = section,
			reset = reset,
			report = report,
			screen = function()
				return Host.Frame "Badge" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Host.UIPadding({
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					}),
					Host.ScrollingFrame "Content" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 6,
						Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
						section(),
					},
				}
			end,
			steps = {
				neutral = function()
					return choose("neutral")
				end,
				warning = function()
					return choose("warning")
				end,
				error = function()
					return choose("error")
				end,
			},
		}
	end,
}
