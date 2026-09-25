--!strict

return {
	title = "Loading silhouettes",
	ledgerRows = {},
	build = function(ctx)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local loading, first = Compose.cell(true), Compose.cell(true)
		local rootPath, controller
		local records = {}
		local function report()
			return {
				loading = loading:peek(),
				first = first:peek(),
				reduced = if ctx.reducedMotion then ctx.reducedMotion:peek() else false,
			}
		end
		local function command(cell, value)
			cell:set(value)
			return report()
		end
		local function motion(value)
			if ctx.motionPreference then
				ctx.motionPreference:set(value)
			end
			return report()
		end

		local function section()
			Compose.cleanup(function()
				rootPath, controller = nil, nil
				table.clear(records)
			end)
			local root = Host.Frame "SkeletonRecipe" {
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
					text = "Loading silhouettes",
					textRole = "heading",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({
					LayoutOrder = 2,
					Name = "Note",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = "Reserve a place for content while it loads. Reduced motion keeps the shapes still.",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({
					LayoutOrder = 3,
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
						Name = "Load",
						label = "Loading",
						onActivate = function()
							loading:set(true)
						end,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Ready",
						label = "Loaded",
						onActivate = function()
							loading:set(false)
						end,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Reduce",
						label = "Reduce motion",
						onActivate = function()
							motion(true)
						end,
					}),
					UI.Button({
						LayoutOrder = 4,
						Name = "Animate",
						label = "Full motion",
						onActivate = function()
							motion(false)
						end,
					}),
				}),
				Host.Frame({
					LayoutOrder = 4,
					Name = "Pending",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Compose.show(loading, function()
						Compose.cleanup(function()
							table.clear(records)
						end)
						return Host.Frame "Placeholders" {
							BackgroundTransparency = 1,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({
								FillDirection = Enum.FillDirection.Vertical,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 16),
							}),
							Host.Frame({
								LayoutOrder = 1,
								Name = "First",
								BackgroundTransparency = 1,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Compose.show(first, function()
									return UI.Skeleton "Card" {
										form = "box",
									}
								end),
							}),
							UI.Skeleton({
								LayoutOrder = 2,
								Name = "Face",
								form = "circle",
								ref = function(record)
									records.face = record
								end,
							}),
							UI.Skeleton({
								LayoutOrder = 3,
								Name = "Copy",
								form = "line",
								lines = 3,
							}),
						}
					end, function()
						return UI.Label "ReadyCopy" {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = "Your next race is ready.",
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}
					end),
				}),
			}
			return root
		end
		return {
			section = section,
			screen = function()
				return Host.Frame "Skeleton" {
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
			report = report,
			steps = {
				loading = function()
					return command(loading, true)
				end,
				loaded = function()
					return command(loading, false)
				end,
				removeFirst = function()
					return command(first, false)
				end,
				restoreFirst = function()
					return command(first, true)
				end,
				reduced = function()
					return motion(true)
				end,
				full = function()
					return motion(false)
				end,
			},
			reset = function()
				loading:set(true)
				first:set(true)
				motion(false)
			end,
		}
	end,
}
