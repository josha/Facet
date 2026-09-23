--!strict
--[[ Cards: `UI.Card` in the `UI.VirtualGrid` recipe (docs/reference/api.md#uicard).

	Hover a card, ring its cell with the arrows, or look at it on a touch screen:
	Play and More reveal on a plate beneath it and nothing beside it moves. On a
	pad, A on a card enters its actions (these cards have no body action; with one,
	the grid's Activate runs that same callback instead), the arrows stay in them,
	B leaves (after closing an open menu first). The grid keeps one browse stop per cell; each
	card reads it through `browseTarget`. The plate is inside each card's own
	envelope, and the line extent is the tallest card's measured height
	(`revealExtent.body`) — nothing here predicts text. ]]
local ITEM_COUNT = 60
-- the first frame's line before any card has measured itself: tall, the safe side
local SEED_EXTENT = 480

local COPY = {
	lastNone = "Last action: none yet",
	lastPrefix = "Last action: ",
}

return {
	title = "Cards (Card in a VirtualGrid)",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local games = table.create(ITEM_COUNT)
		for i = 1, ITEM_COUNT do
			games[i] = { id = `g{i}`, title = `Nebula Racers {i}`, players = `{(i * 7) % 40 + 1} friends playing` }
		end
		local items = Compose.cell(games)
		local last = Compose.cell(COPY.lastNone)
		local refs: { [string]: any } = {}
		local gridRef: any = nil
		-- each card's measured height by key: a line is as tall as its tallest card
		local bodies = Compose.cell({} :: { [string]: number })
		local columns = Compose.formula(function(use)
			local w = use(ctx.env:get("viewportRect")).w
			return math.max(1, math.min(4, math.floor(w / 300)))
		end)
		local function record(text: string)
			last:set(COPY.lastPrefix .. text)
		end

		local function cell(item: any, ctx2: any): any
			local key = item.id
			return UI.Card("Card")({
				image = "rbxassetid://75342910516929",
				title = function(use: any): string
					return ctx2.current(use).title
				end,
				caption = function(use: any): string
					return ctx2.current(use).players
				end,
				browseTarget = function(): string?
					local path = if gridRef ~= nil then gridRef.api.pathOf(key) else nil
					return if path ~= nil then `{path}/Hit` else nil
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
				ref = function(r: any)
					refs[key] = r
					ctx2.scope.own(function()
						if refs[key] == r then
							refs[key] = nil
						end
					end)
					Compose.watch(function(use)
						local e = use(r.api.revealExtent)
						if bodies:peek()[key] ~= e.body then
							local map = table.clone(bodies:peek())
							map[key] = e.body
							bodies:set(map)
						end
					end)
				end,
			})
		end

		local screen = function()
			return UI.Screen("Cards")({
				surface = "base",
				padding = "m",
				gap = "s",
				-- one status line: the grid keeps the room on a short landscape phone
				UI.Text("Last")({ text = last, width = UI.fill(), lineLimit = 1 }),
				UI.VirtualGrid("Games")({
					items = items,
					key = function(item: any): string
						return item.id
					end,
					columns = columns,
					itemExtent = function(line: number, use: any): number
						local lanes, list, map = use(columns), use(items), use(bodies)
						local tallest = 0
						for i = (line - 1) * lanes + 1, math.min(#list, line * lanes) do
							tallest = math.max(tallest, map[list[i].id] or 0)
						end
						return if tallest > 0 then tallest else SEED_EXTENT
					end,
					viewportExtent = "auto",
					ref = function(r: any)
						gridRef = r
					end,
					onActivate = function(item: any)
						local r = refs[item.id]
						if r ~= nil then
							r.api.enterActions()
						end
					end,
					cell = cell,
				}),
			})
		end

		return {
			screen = screen,
			steps = {
				enter = function(key: string?)
					local r = refs[key or "g1"]
					if r ~= nil then
						r.api.enterActions()
					end
					return if r ~= nil then r.dump() else nil
				end,
			},
			report = function()
				local n = 0
				for _ in refs do
					n += 1
				end
				return { mounted = n, last = last:peek() }
			end,
		}
	end,
}
