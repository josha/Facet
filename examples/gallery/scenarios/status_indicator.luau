--!strict
return {
	title = "Status marks",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
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
			local shapes = {}
			for index, word in { "dot", "ring", "square", "dash" } do
				table.insert(
					shapes,
					Host.Frame(word)({
						LayoutOrder = index,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.XY,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						UI.StatusIndicator "Mark" {
							LayoutOrder = 1,
							form = word,
							status = status,
							name = word,
						},
						UI.Text "Name" {
							LayoutOrder = 2,
							text = string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2),
						},
					})
				)
			end
			local root = Host.Frame "StatusRecipe" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 16),
				}),
				UI.Text "Title" { text = "Status marks", textRole = "heading" },
				UI.Text "Guide" {
					text = "Shapes carry meaning alongside color. Counts stop growing at 99+.",
					role = "secondary",
				},
				Host.Frame "Shapes" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 24),
						Wraps = true,
					}),
					table.unpack(shapes),
				},
				UI.Picker "Status" {
					label = "Status",
					selected = status,
					options = {
						{ value = "neutral", label = "Neutral" },
						{ value = "info", label = "Info" },
						{ value = "success", label = "Success" },
						{ value = "warning", label = "Warning" },
						{ value = "error", label = "Error" },
						{ value = "accent", label = "Accent" },
					},
				},
				UI.Picker "Shape" {
					label = "Shape",
					selected = form,
					options = {
						{ value = "dot", label = "Dot" },
						{ value = "ring", label = "Ring" },
					},
				},
				Host.Frame "Live" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 12),
						Wraps = true,
					}),
					UI.StatusIndicator "Count" {
						count = count,
						status = status,
						name = "Unread",
						ref = function(value)
							record = value
						end,
					},
					UI.StatusIndicator "Cutout" {
						form = form,
						status = status,
						cutout = true,
						controlSize = "large",
					},
					UI.Button "More" {
						label = "Add 25",
						icon = "increment",
						appearance = "soft",
						onActivate = function()
							count:set(count:peek() + 25)
						end,
					},
					UI.Button "Reset" {
						label = "Clear",
						appearance = "link",
						onActivate = function()
							count:set(0)
						end,
					},
				},
			}
			return root
		end
		return {
			section = section,
			reset = reset,
			report = report,
			screen = function()
				return Host.Frame "StatusIndicator" {
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
