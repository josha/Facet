--!strict

return {
	title = "Automatic motion",
	ledgerRows = {},
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local Compose = ctx.Compose
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local commands, latest = {}, {}
		local function Section(props)
			local rows = { gap = "s" }
			for _, child in props.children do
				table.insert(rows, child)
			end
			return Host.Frame({
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				UI.Label({

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = props.title,
					textRole = "body",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame "Rows" {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
					table.unpack(rows),
				},
				props.footer,
			})
		end

		local function arrival(): any
			local runtime = ctx.runtime
			if runtime == nil then
				return 1
			end
			local shown = Compose.cell(0)
			local fade = runtime.tween(function(use)
				return use(shown)
			end, { seconds = 0.2 })
			shown:set(1)
			return fade
		end
		local function Inventory()
			local expanded = Compose.cell(false)
			local selected = Compose.cell("scanner")
			local items = Compose.cell({
				{ id = "scanner", name = "Scanner", price = 40 },
				{ id = "grapple", name = "Grapple", price = 60 },
				{ id = "beacon", name = "Beacon", price = 20 },
			})
			local balance = Compose.cell(100)

			local runtime = ctx.runtime
			local displayedBalance = if runtime
				then runtime.tween(function(use)
					return use(balance)
				end, { seconds = 0.35 })
				else balance
			local item = Compose.formula(function(use)
				local list = use(items)
				for _, candidate in list do
					if candidate.id == use(selected) then
						return candidate
					end
				end
				return list[1]
			end)
			local affordable = Compose.formula(function(use)
				return use(balance) >= use(item).price
			end)
			local function buy()
				if affordable:peek() then
					balance:set(balance:peek() - item:peek().price)
				end
			end
			local function reverse()
				local list, reversed = items:peek(), {}
				for i = #list, 1, -1 do
					table.insert(reversed, list[i])
				end
				items:set(reversed)
			end
			commands.toggle = function()
				expanded:set(not expanded:peek())
			end
			commands.reverse, commands.buy = reverse, buy
			commands.reset = function()
				balance:set(100)
			end
			Compose.watch(function(use)
				latest = {
					expanded = use(expanded),
					selected = use(selected),
					balance = use(balance),
					affordable = use(affordable),
					first = use(items)[1].id,
				}
			end)
			local function ItemRow(current, placement)
				return Host.Frame({
					Name = "Card-" .. current:peek().id,
					LayoutOrder = function(use)
						return use(placement).index
					end,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.Button "Select" {
						row = {
							title = function(use)
								return use(current).name
							end,
							value = `{current:peek().price} credits`,
						},
						onActivate = function()
							selected:set(current:peek().id)
						end,
					},
				})
			end
			return Host.Frame "AutomaticMotion" {
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
						Padding = UDim.new(0, 16),
					}),
					Section({
						title = "Equipment",
						footer = UI.Label({
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = function(use)
								return `Balance: {math.floor(use(displayedBalance) + 0.5)} credits`
							end,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						}),
						children = {
							Compose.OrderedCollection({
								from = items,
								key = function(entry)
									return entry.id
								end,
								render = ItemRow,
							}),
						},
					}),
					UI.Toggle "DetailsToggle" {
						label = "Show details",
						value = expanded,
					},
					Host.Frame "Details" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Compose.show(expanded, function()
							local alpha = arrival()
							return Host.CanvasGroup({
								GroupTransparency = function(use)
									return 1 - use(alpha)
								end,
								Name = "Panel",
								BackgroundTransparency = 1,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Host.UIPadding({
									PaddingTop = UDim.new(0, 8),
									PaddingBottom = UDim.new(0, 8),
									PaddingLeft = UDim.new(0, 8),
									PaddingRight = UDim.new(0, 8),
								}),
								UI.Label({
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									text = function(use)
										return `{use(item).name} costs {use(item).price} credits. Its row stays the same when reordered.`
									end,
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								}),
							})
						end),
					},
					UI.Button "Buy" {
						label = "Buy selected",
						enabled = affordable,
						onActivate = buy,
					},
					UI.Button "Reverse" {
						label = "Reverse order",
						onActivate = reverse,
					},
					UI.Button "Reset" {
						label = "Reset balance",
						onActivate = commands.reset,
					},
				},
			}
		end
		return {
			screen = Inventory,
			present = {},
			steps = {
				toggle = function()
					commands.toggle()
					return latest
				end,
				reverse = function()
					commands.reverse()
					return latest
				end,
				buy = function()
					commands.buy()
					return latest
				end,
				resetBalance = function()
					commands.reset()
					return latest
				end,
			},
			report = function()
				return latest
			end,
			dispose = function() end,
		}
	end,
}
