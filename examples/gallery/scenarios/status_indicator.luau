--!strict
return {
	title = "Status marks",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local status, form, count = Compose.cell("neutral"), Compose.cell("dot"), Compose.cell(0)
		local rootPath, controller, record
		local function report()
			return { count = count:peek(), form = form:peek(), status = status:peek() }
		end
		local function choose(word)
			status:set(word)
			return report()
		end
		local function reset()
			status:set("neutral")
			form:set("dot")
			count:set(0)
		end
		local function section()
			Compose.cleanup(function()
				rootPath, controller, record = nil, nil, nil
			end)
			local shapes, words = {}, {}
			for _, word in { "dot", "ring", "square", "dash" } do
				table.insert(
					shapes,
					Host.Frame({
						Name = word,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						UI.StatusIndicator({
							LayoutOrder = 1,
							Name = "Mark",
							form = word,
							status = status,
							name = word,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "Name",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Text = word,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					})
				)
			end
			for _, word in { "neutral", "info", "success", "warning", "error", "accent" } do
				table.insert(
					words,
					UI.Button({
						Name = word,
						label = word,
						onActivate = function()
							choose(word)
						end,
					})
				)
			end
			local root = Host.Frame({
				Name = "StatusRecipe",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Label({
					LayoutOrder = 1,
					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Status marks",
					TextSize = 22,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Guide",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Shapes carry meaning alongside color. Counts stop growing at 99+.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({
					LayoutOrder = 3,
					Name = "Shapes",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 24),
						Wraps = true,
					}),
					table.unpack(shapes),
				}),
				Host.Frame({
					LayoutOrder = 4,
					Name = "Live",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
					}),
					UI.StatusIndicator({
						LayoutOrder = 1,
						Name = "Count",
						count = count,
						status = status,
						name = "Unread",
						ref = function(value)
							record = value
						end,
					}),
					UI.StatusIndicator({
						LayoutOrder = 2,
						Name = "Cutout",
						form = form,
						status = status,
						cutout = true,
						controlSize = "large",
					}),
				}),
				Host.Frame({
					LayoutOrder = 5,
					Name = "Statuses",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					table.unpack(words),
				}),
				Host.Frame({
					LayoutOrder = 6,
					Name = "Commands",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						Wraps = true,
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "More",
						label = "Add 25",
						onActivate = function()
							count:set(count:peek() + 25)
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Reset",
						label = "Clear count",
						onActivate = function()
							count:set(0)
						end,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Shape",
						label = "Toggle ring",
						onActivate = function()
							form:set(if form:peek() == "dot" then "ring" else "dot")
						end,
					}),
				}),
			})
			return root
		end
		return {
			section = section,
			reset = reset,
			report = report,
			screen = function()
				return Host.Frame({
					Name = "StatusIndicator",
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
						section(),
					}),
				})
			end,
			steps = {
				warning = function()
					return choose("warning")
				end,
				error = function()
					return choose("error")
				end,
				neutral = function()
					return choose("neutral")
				end,
				capped = function()
					count:set(1000)
					return report()
				end,
				ring = function()
					form:set("ring")
					return report()
				end,
			},
		}
	end,
}
