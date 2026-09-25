--!strict
local ITEM_COUNT = 60
local CARD_LIFT = 1.04
local SEED_EXTENT = 320

local COPY = {
	title = "Cards",
	hint = "Hover a card or select its cell to show Play and More. On a gamepad, A enters the actions and B leaves.",
	lastNone = "Last action: none yet",
	lastPrefix = "Last action: ",
}

return {
	title = "Cards (Card in a VirtualGrid)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx)
		local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Enum = Enum }
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local viewport = ctx.viewport or Compose.cell({ width = 1280, height = 720 })
		local games = table.create(ITEM_COUNT)
		for index = 1, ITEM_COUNT do
			games[index] = {
				id = `g{index}`,
				title = `Nebula Racers {index}`,
				players = `{(index * 7) % 40 + 1} friends playing`,
			}
		end
		local items = Compose.cell(games)
		local last = Compose.cell(copy.lastNone)
		local controls: { [string]: any } = {}
		local cards: { [string]: any } = {}
		local columns = Compose.formula(function(use)
			return math.max(1, math.min(4, math.floor(use(viewport).width / 300)))
		end)
		local function gutter(extent: number): number
			local grown = math.ceil(extent * CARD_LIFT) - extent
			return math.max(16, grown)
		end
		local function record(text: string)
			last:set(copy.lastPrefix .. text)
		end
		local function render(current, _placement, key)
			local table_ = {}
			controls[key] = table_
			local card = UI.Card({
				Name = "Card",
				image = "rbxassetid://75342910516929",
				title = function(use)
					return use(current).title
				end,
				caption = function(use)
					return use(current).players
				end,
				controls = table_,
				browseTarget = function()
					local node = cards[key]
					local content = if node then node.Parent else nil
					return if content then content:FindFirstChild("RowHit") else nil
				end,
				primaryAction = {
					label = "Play",
					onActivate = function()
						record(`play {key}`)
					end,
				},
				menu = {
					items = {
						{
							id = "hide",
							label = "Not interested",
							onSelect = function()
								record(`hid {key}`)
							end,
						},
					},
				},
			})
			cards[key] = card
			Compose.cleanup(function()
				if cards[key] == card then
					cards[key] = nil
					controls[key] = nil
				end
			end)
			return card
		end
		local function screen()
			return Host.Frame "Cards" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Host.UIPadding({
					PaddingTop = UDim.new(0, 16),
					PaddingBottom = UDim.new(0, 16),
					PaddingLeft = UDim.new(0, 16),
					PaddingRight = UDim.new(0, 16),
				}),
				Host.UIListLayout({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				UI.Label({
					Name = "Last",
					LayoutOrder = 1,
					Text = last,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.VirtualGrid({
					Name = "Games",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 1, -40),
					from = items,
					key = "id",
					columns = columns,
					itemSize = SEED_EXTENT,
					measure = true,
					crossGap = function(use)
						return gutter(math.ceil(use(viewport).width / use(columns)))
					end,
					gap = gutter(SEED_EXTENT),
					onActivate = function(_item, key)
						local entry = controls[key]
						if entry and entry.enterActions then
							entry.enterActions()
						end
					end,
					render = render,
				}),
			}
		end
		return {
			screen = screen,
			controls = controls,
			steps = {
				enter = function(key: string?)
					local entry = controls[key or "g1"]
					return entry ~= nil and entry.enterActions ~= nil and entry.enterActions()
				end,
			},
			report = function()
				local mounted = 0
				for _ in cards do
					mounted += 1
				end
				return { mounted = mounted, last = last:peek() }
			end,
		}
	end,
}
