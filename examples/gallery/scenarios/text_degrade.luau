--!strict

local STOPS: { { value: string, width: number? } } = {
	{ value = "roomy", width = nil },
	{ value = "snug", width = 200 },
	{ value = "tight", width = 165 },
	{ value = "impossible", width = 110 },
}

local WRAP_COLUMN: { [string]: number } = {
	roomy = 240,
	snug = 170,
	tight = 110,
	impossible = 70,
}

local SORT_COMPACT = "Srt"

local COPY = {
	title = "What a label gives up first",
	lead = "Narrow the row. It says it shorter and reflows before anything is cut, and cropping is the last thing it does.",
	widthLabel = "Room",
	roomy = "Roomy",
	snug = "Snug",
	tight = "Tight",
	impossible = "Impossible",
	rowHeading = "Three labels, one row",

	sortLabel = "Sorting",

	rankLabel = "Best fit",

	dateLabel = "Newest",
	wrapHeading = "One phrase, one narrowing column",
	wrapBody = "Wrapping is right only while the longest word fits",
	footnote = "Clip is the floor, never the first move.",
}

return {
	title = "Text degrade cascade (rulings 1 and 5)",
	ledgerRows = { "R-1", "R-5" },
	copy = COPY,
	stops = STOPS,
	sortCompact = SORT_COMPACT,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum

		local stop = Compose.cell("roomy")
		local rowWidth = Compose.formula(function(use)
			local chosen = use(stop)
			for _, entry in STOPS do
				if entry.value == chosen then
					return if entry.width == nil then UDim.new(1, 0) else UDim.new(0, entry.width)
				end
			end
			return UDim.new(1, 0)
		end)
		local columnWidth = Compose.formula(function(use)
			return UDim.new(0, WRAP_COLUMN[use(stop)] or WRAP_COLUMN.roomy)
		end)

		local function widthPicker()
			return UI.Picker({
				Name = "Room",
				label = COPY.widthLabel,
				style = "segmented",
				options = {
					{ value = "roomy", label = COPY.roomy },
					{ value = "snug", label = COPY.snug },
					{ value = "tight", label = COPY.tight },
					{ value = "impossible", label = COPY.impossible },
				},
				selected = stop,
			})
		end

		local function screen()
			return Host.Frame({
				Name = "TextDegrade",
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

						Name = "Title",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = COPY.title,
						TextSize = 28,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({

						Name = "Lead",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = COPY.lead,
						TextSize = 12,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					widthPicker(),
					Host.Frame({

						Name = "RowPanel",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 16),
							PaddingBottom = UDim.new(0, 16),
							PaddingLeft = UDim.new(0, 16),
							PaddingRight = UDim.new(0, 16),
						}),
						UI.Label({
							LayoutOrder = 1,
							Name = "RowHeading",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Text = COPY.rowHeading,
							TextSize = 12,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						Host.Frame({
							LayoutOrder = 2,
							Name = "Row",
							BackgroundTransparency = 1,
							Size = function(use)
								return UDim2.new(use(rowWidth).Scale, use(rowWidth).Offset, 0, 0)
							end,
							AutomaticSize = Enum.AutomaticSize.Y,
							Host.UIListLayout({
								FillDirection = Enum.FillDirection.Horizontal,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Padding = UDim.new(0, 4),
							}),
							UI.Button({
								LayoutOrder = 1,
								Name = "Sort",
								label = COPY.sortLabel,

								onActivate = function() end,
							}),
							UI.Label({
								LayoutOrder = 2,
								Name = "Rank",
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Text = COPY.rankLabel,
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
							UI.Label({
								LayoutOrder = 3,
								Name = "Date",
								BackgroundTransparency = 1,
								BorderSizePixel = 0,
								Size = UDim2.new(0, 60, 0, 0),
								AutomaticSize = Enum.AutomaticSize.XY,
								Text = COPY.dateLabel,
								TextWrapped = true,
								TextYAlignment = Enum.TextYAlignment.Top,
								TextXAlignment = Enum.TextXAlignment.Left,
							}),
						}),
					}),
					Host.Frame({

						Name = "WrapPanel",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Host.UIListLayout({
							FillDirection = Enum.FillDirection.Vertical,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
						Host.UIPadding({
							PaddingTop = UDim.new(0, 16),
							PaddingBottom = UDim.new(0, 16),
							PaddingLeft = UDim.new(0, 16),
							PaddingRight = UDim.new(0, 16),
						}),
						UI.Label({
							LayoutOrder = 1,
							Name = "WrapHeading",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							Text = COPY.wrapHeading,
							TextSize = 12,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						UI.Label({
							LayoutOrder = 2,
							Name = "WrapBody",
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = function(use)
								return UDim2.new(use(columnWidth).Scale, use(columnWidth).Offset, 0, 0)
							end,
							AutomaticSize = Enum.AutomaticSize.Y,
							Text = COPY.wrapBody,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
					}),
					UI.Label({

						Name = "Footnote",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = COPY.footnote,
						TextSize = 12,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				}),
			})
		end

		return {
			screen = screen,
			present = {},

			stop = stop,

			steps = {

				setStop = function(_built: any, payload: string?)
					local value = payload
					local known = false
					for _, entry in STOPS do
						if entry.value == value then
							known = true
						end
					end
					stop:set(if known then value else "roomy")
					return { stop = stop:peek() }
				end,
			},

			report = function()
				return { stop = stop:peek(), stops = #STOPS }
			end,

			dispose = function() end,
		}
	end,
}
