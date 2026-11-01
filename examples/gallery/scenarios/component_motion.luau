--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ExampleContext = typeof(require("@repo/examples/types").Context)
type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
type OrderedPlacement = typeof(require("@repo/tools/typecheck/aliases").OrderedPlacementReadOnly)
type Use = typeof(require("@repo/tools/typecheck/aliases").Use)
type Item = { id: string, name: string, price: number }
type CollectionStatus = {
	mode: "windowed" | "all",
	direction: "horizontal" | "vertical",
	total: number,
	retained: number,
	first: number,
	last: number,
	firstRow: number,
	lastRow: number,
	rowCount: number,
	extent: number,
	following: boolean,
	desiredOffset: number?,
	measured: number,
}
type Latest = {
	expanded: boolean?,
	selected: string?,
	balance: number?,
	affordable: boolean?,
	first: string?,
}
type Commands = {
	toggle: (() -> ())?,
	reverse: (() -> ())?,
	buy: (() -> ())?,
	reset: (() -> ())?,
}

return {
	title = "Automatic motion",
	ledgerRows = {},
	build = function(ctx: ExampleContext)
		local UI, Compose: ComposeModule = ctx.UI, ctx.Compose
		local Host = ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Vector2, Color3, Enum =
			nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
		local commands: Commands = {}
		local latest: Latest = {}
		local function Section(props: { title: string, footer: GuiObject, children: { Instance } })
			local rows: { Instance } = {}
			for _, child in props.children do
				table.insert(rows, child)
			end
			local children: { Instance } = {
				Host.UIListLayout {
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				},
				UI.Text {

					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					text = props.title,
					textRole = "body",
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				Host.Frame "Rows" {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) },
					table.unpack(rows),
				},
				props.footer,
			}
			return Host.Frame {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				table.unpack(children),
			}
		end

		local function arrival(): ReadOnlyValue<number>
			local runtime = ctx.runtime
			if runtime == nil then
				return Compose.cell(1)
			end
			local shown = Compose.cell(0)
			local fade = runtime.tween(function(use: Use)
				return use(shown)
			end, { seconds = 0.2 })
			shown:set(1)
			return fade
		end
		local function Inventory()
			local expanded = Compose.cell(false)
			local selected = Compose.cell("scanner")
			local initialItems: { Item } = {
				{ id = "scanner", name = "Scanner", price = 40 },
				{ id = "grapple", name = "Grapple", price = 60 },
				{ id = "beacon", name = "Beacon", price = 20 },
			}
			local items = Compose.cell(initialItems)
			local balance = Compose.cell(100)
			local noStatus: CollectionStatus? = nil
			local rowStatus: Value<CollectionStatus?> = Compose.cell(noStatus)

			local runtime = ctx.runtime
			local displayedBalance: ReadOnlyValue<number> = if runtime
				then runtime.tween(function(use: Use)
					return use(balance)
				end, { seconds = 0.35 })
				else balance
			local item = Compose.formula(function(use: Use)
				local list = use(items)
				for _, candidate in list do
					if candidate.id == use(selected) then
						return candidate
					end
				end
				return list[1]
			end)
			local affordable = Compose.formula(function(use: Use)
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
			local function reset()
				balance:set(100)
			end
			commands.reset = reset
			Compose.watch(function(use: Use)
				latest = {
					expanded = use(expanded),
					selected = use(selected),
					balance = use(balance),
					affordable = use(affordable),
					first = use(items)[1].id,
				}
			end)
			local function ItemRow(current: ReadOnlyValue<Item>, placement: OrderedPlacement): GuiObject
				return Host.Frame {
					Name = "Card-" .. current:peek().id,
					LayoutOrder = function(use: Use)
						return use(placement).index
					end,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					UI.Button "Select" {
						row = {
							title = function(use: Use)
								return use(current).name
							end,
							value = `{current:peek().price} credits`,
						},
						onActivate = function()
							selected:set(current:peek().id)
						end,
					},
				}
			end
			return Host.Frame "AutomaticMotion" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				UI.ScrollView "Page" {
					padding = 16,
					gap = 16,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ScrollBarThickness = 6,
					Section {
						title = "Equipment",
						footer = UI.Text {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
							text = function(use: Use)
								return `Balance: {math.floor(use(displayedBalance) + 0.5)} credits`
							end,
							TextWrapped = true,
							TextYAlignment = Enum.TextYAlignment.Top,
							TextXAlignment = Enum.TextXAlignment.Left,
						},
						children = {
							UI.VirtualList "Items" {
								from = items,
								key = function(entry: Item)
									return entry.id
								end,
								mode = "all",
								measure = true,
								itemSize = 56,
								gap = 8,
								status = rowStatus,
								ScrollingEnabled = false,
								ScrollBarThickness = 0,
								Size = function(use: Use)
									local current = use(rowStatus)
									return UDim2.new(1, 0, 0, if current then current.extent else 0)
								end,
								render = ItemRow,
							},
						},
					},
					UI.Toggle "DetailsToggle" { label = "Show details", value = expanded },
					Host.Frame "Details" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Compose.show(expanded, function()
							local alpha = arrival()
							return Host.CanvasGroup "Panel" {
								GroupTransparency = function(use: Use)
									return 1 - use(alpha)
								end,
								BackgroundTransparency = 1,
								Size = UDim2.new(1, 0, 0, 0),
								AutomaticSize = Enum.AutomaticSize.Y,
								Host.UIPadding {
									PaddingTop = UDim.new(0, 8),
									PaddingBottom = UDim.new(0, 8),
									PaddingLeft = UDim.new(0, 8),
									PaddingRight = UDim.new(0, 8),
								},
								UI.Text {
									BackgroundTransparency = 1,
									BorderSizePixel = 0,
									Size = UDim2.new(1, 0, 0, 0),
									AutomaticSize = Enum.AutomaticSize.Y,
									text = function(use: Use)
										return `{use(item).name} costs {use(item).price} credits. Its row stays the same when reordered.`
									end,
									TextWrapped = true,
									TextYAlignment = Enum.TextYAlignment.Top,
									TextXAlignment = Enum.TextXAlignment.Left,
								},
							}
						end),
					},
					UI.Button "Buy" {
						label = "Buy selected",
						enabled = affordable,
						onActivate = buy,
					},
					UI.Button "Reverse" { label = "Reverse order", onActivate = reverse },
					UI.Button "Reset" {
						label = "Reset balance",
						onActivate = reset,
					},
				},
			}
		end
		return {
			screen = Inventory,
			present = {},
			steps = {
				toggle = function()
					assert(commands.toggle)()
					return latest
				end,
				reverse = function()
					assert(commands.reverse)()
					return latest
				end,
				buy = function()
					assert(commands.buy)()
					return latest
				end,
				resetBalance = function()
					assert(commands.reset)()
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
