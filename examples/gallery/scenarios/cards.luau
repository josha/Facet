--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ReadOnlyValue<T> = { peek: (ReadOnlyValue<T>) -> T }
type Use = <T>(ReadOnlyValue<T>) -> T
type ExampleContext = typeof(require("@repo/examples/types").Context)
type Built = typeof(require("@repo/examples/types").Built)
type CardControls = typeof(require("@repo/tools/typecheck/aliases").CardControls)
type Game = { id: string, title: string, players: string }
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
	build = function(ctx: ExampleContext): Built
		local UI, Compose: ComposeModule, Host = ctx.UI, ctx.Compose, ctx.Host
		local nativeTypes = ctx.types
		local UDim, UDim2, Enum = nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Enum
		local copy = ctx.copy or COPY
		local viewport: ReadOnlyValue<{ width: number, height: number }> = ctx.viewport
			or Compose.cell({ width = 1280, height = 720 })
		local games: { Game } = table.create(ITEM_COUNT)
		for index = 1, ITEM_COUNT do
			games[index] = {
				id = `g{index}`,
				title = `Nebula Racers {index}`,
				players = `{(index * 7) % 40 + 1} friends playing`,
			}
		end
		local items = Compose.cell(games)
		local last = Compose.cell(copy.lastNone)
		local controls: { [string]: CardControls } = {}
		local cards: { [string]: Frame } = {}
		local columns = Compose.formula(function(use: Use)
			return math.max(1, math.min(4, math.floor(use(viewport).width / 300)))
		end)
		local function gutter(extent: number): number
			local grown = math.ceil(extent * CARD_LIFT) - extent
			return math.max(16, grown)
		end
		local function record(text: string)
			last:set(copy.lastPrefix .. text)
		end
		local function render(current: ReadOnlyValue<Game>, _placement: unknown, key: ReadOnlyValue<string>): GuiObject
			local table_: CardControls = {}
			local card = UI.Card "Card" {
				image = "rbxassetid://75342910516929",
				title = function(use: Use)
					return use(current).title
				end,
				caption = function(use: Use)
					return use(current).players
				end,
				controls = table_,
				browseTarget = function(): GuiObject?
					local node = cards[key:peek()]
					local content = if node then node.Parent else nil
					local hit = if content then content:FindFirstChild("RowHit") else nil
					if hit and hit:IsA("GuiObject") then
						return hit
					end
					return nil
				end,
				primaryAction = {
					label = "Play",
					onActivate = function()
						record(`play {key:peek()}`)
					end,
				},
				menu = {
					items = {
						{
							id = "hide",
							label = "Not interested",
							onSelect = function()
								record(`hid {key:peek()}`)
							end,
						},
					},
				},
			}
			local held: string? = nil
			local function forget()
				if held ~= nil and cards[held] == card then
					cards[held], controls[held] = nil, nil
				end
			end
			Compose.watch(function(use: Use)
				forget()
				local now = use(key)
				held = now
				cards[now], controls[now] = card, table_
			end)
			Compose.cleanup(forget)
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
				UI.Text "Last" {
					LayoutOrder = 1,
					text = last,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
				},
				UI.VirtualGrid "Games" {
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 1, -40),
					from = items,
					key = "id",
					columns = columns,
					itemSize = SEED_EXTENT,
					measure = true,
					crossGap = function(use: Use)
						return gutter(math.ceil(use(viewport).width / use(columns)))
					end,
					gap = gutter(SEED_EXTENT),
					onActivate = function(_item: Game, key: string)
						local entry = controls[key]
						if entry and entry.enterActions then
							entry.enterActions()
						end
					end,
					render = render,
				},
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
