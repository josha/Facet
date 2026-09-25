--!strict

local COPY = {
	title = "Progress and activity",
	caption = "Adjust progress to compare the bar and ring. Activity indicators keep moving while work is running.",
	determinate = "Downloading",
	indeterminate = "Working",
	spinner = "Spinner (dots)",
	bar = "Download progress",
	adjust = "Adjust progress",
}

return {
	title = "Progress and activity",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local progress = Compose.cell(0.25)
		local rung = Compose.cell(nil)
		local rootPath, controller
		local placeholders = require("./skeleton").build(ctx)
		local function reset()
			progress:set(0.25)
			rung:set(nil)
			placeholders.reset()
		end
		local function percent(v)
			return string.format("%d%%", math.floor(v * 100 + 0.5))
		end
		local function screen()
			Compose.cleanup(function()
				rootPath, controller = nil, nil
			end)
			local root = Host.Frame "ProgressRing" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.ScrollingFrame "Page" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 6,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),
					UI.Label "Title" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.title,
						textRole = "heading",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Label "Caption" {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.caption,
						textRole = "caption",
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					UI.Label({

						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.adjust,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Slider "AdjustProgress" {
						value = progress,
						min = 0,
						max = 1,
						step = 0.05,
					},
					UI.Label({

						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						text = COPY.bar,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.ProgressView "Bar" {
						value = progress,
						showValue = true,
						endLabel = function(use)
							return `{math.floor(use(progress) * 5)} of 5`
						end,
						format = percent,
						segments = 5,
						trail = { delay = 0.3, duration = 0.35 },
					},
					UI.ProgressView "Ring" {
						label = COPY.determinate,
						value = progress,
						presentation = "circular",
						diameter = 120,
						showValue = true,
						format = percent,
					},
					UI.ProgressView "Busy" {
						label = COPY.indeterminate,
						presentation = "circular",
						controlSize = rung,
						endLabel = "Connecting",
					},
					UI.ProgressView "Dots" {
						label = COPY.spinner,
						presentation = "spinner",
						controlSize = rung,
					},
					Host.Frame "Sizes" {
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
							Name = "Compact",
							label = "Compact",
							onActivate = function()
								rung:set("compact")
							end,
						}),
						UI.Button({
							LayoutOrder = 2,
							Name = "Regular",
							label = "Regular",
							onActivate = function()
								rung:set("regular")
							end,
						}),
						UI.Button({
							LayoutOrder = 3,
							Name = "Large",
							label = "Large",
							onActivate = function()
								rung:set("large")
							end,
						}),
					},
					UI.Button "Reset" {
						label = "Reset progress",
						onActivate = reset,
					},
					placeholders.section(),
				},
			}
			return root
		end
		local function report()
			return { loading = placeholders.report(), progress = progress:peek(), controlSize = rung:peek() }
		end
		local function setProgress(value)
			progress:set(math.clamp(value, 0, 1))
			return report()
		end
		return {
			screen = screen,
			present = {},
			reset = reset,
			steps = {
				reset = reset,
				sizeCompact = function()
					rung:set("compact")
					return report()
				end,
				sizeLarge = function()
					rung:set("large")
					return report()
				end,
				sizeDefault = function()
					rung:set(nil)
					return report()
				end,
				setProgress10 = function()
					return setProgress(0.10)
				end,
				setProgress65 = function()
					return setProgress(0.65)
				end,
				setProgress100 = function()
					return setProgress(1)
				end,
			},
			report = report,
		}
	end,
}
