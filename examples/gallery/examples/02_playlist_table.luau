--!strict

local example = {}
example.title = "Playlist Table"
local TRACKS = {
	{ id = "neon", name = "Neon Straightaway", artist = "Chrome Coyote", length = 214, rating = 4 },
	{ id = "drift", name = "Drift City Nights", artist = "Nine Volt", length = 187, rating = 3 },
	{ id = "turbo", name = "Turbo Cascade", artist = "Paper Lantern", length = 243, rating = 5 },
	{ id = "pit", name = "Pit Lane Shuffle", artist = "Rustbucket", length = 158, rating = 2 },
	{ id = "photo", name = "Photo Finish", artist = "Bad Weather", length = 201, rating = 0 },
	{ id = "apex", name = "Apex Bloom", artist = "Nine Volt", length = 176, rating = 3 },
}
function example.build(ctx: any)
	local UI, Compose = ctx.UI, ctx.Compose
	local Host = ctx.Host
	local Compose = ctx.Compose
	local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
	local UDim, UDim2, Vector2, Color3, Enum =
		nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
	local built: any = {}

	local function plain(item: any): any
		return if Compose.isReadable(item) then item:peek() else item
	end
	local baseRows = Compose.cell(table.clone(TRACKS))
	local filterText = Compose.cell("")
	local nowPlaying = Compose.cell(nil :: string?)
	local sortOrder = Compose.cell(nil :: { column: string, direction: string }?)
	local columnWidths = Compose.cell({})
	local ratings: { [string]: any } = {}
	for _, track in TRACKS do
		ratings[track.id] = Compose.cell(track.rating)
	end
	local sortedRows = Compose.formula(function(use)
		local all = use(baseRows) :: { any }
		local order = use(sortOrder)
		if order == nil then
			return all
		end
		local index: { [string]: number } = {}
		for i, track in all do
			index[track.id] = i
		end
		local keys: { [string]: any } = {}
		for _, track in all do
			if order.column == "rating" then
				keys[track.id] = use(ratings[track.id])
			elseif order.column == "artist" then
				keys[track.id] = track.artist
			else
				keys[track.id] = track.name
			end
		end
		local out = table.clone(all)
		table.sort(out, function(a, b)
			local av, bv = keys[a.id], keys[b.id]
			if av == bv then
				return index[a.id] < index[b.id]
			end
			if order.direction == "ascending" then
				return av < bv
			end
			return av > bv
		end)
		return out
	end)
	local filteredRows = Compose.formula(function(use)
		local query = string.lower(use(filterText))
		local all = use(sortedRows) :: { any }
		if query == "" then
			return all
		end
		local out = {}
		for _, track in all do
			if string.find(string.lower(track.name), query, 1, true) ~= nil then
				table.insert(out, track)
			end
		end
		return out
	end)
	local function bakeManualOrder(): { any }
		if sortOrder:peek() ~= nil then
			baseRows:set(table.clone(sortedRows:peek() :: { any }))
			sortOrder:set(nil)
		end
		return baseRows:peek() :: { any }
	end
	local function starCell(item: any)
		return UI.Rating({
			Name = "Rating",
			value = ratings[plain(item).id],
			count = 5,
		})
	end

	local function removeTrack(id: string)
		local out = {}
		for _, track in baseRows:peek() :: { any } do
			if track.id ~= id then
				table.insert(out, track)
			end
		end
		baseRows:set(out)
		for _, track in TRACKS do
			if track.id == id and nowPlaying:peek() == track.name then
				nowPlaying:set(nil)
			end
		end
	end
	local function moveToTop(id: string)
		local present = false
		for _, track in baseRows:peek() :: { any } do
			if track.id == id then
				present = true
				break
			end
		end
		if not present then
			return
		end
		local moved, rest = nil, {}
		for _, track in bakeManualOrder() do
			if track.id == id then
				moved = track
			else
				table.insert(rest, track)
			end
		end
		table.insert(rest, 1, moved)
		baseRows:set(rest)
	end
	local function reorder(keys: { string }, toIndex: number)
		if filterText:peek() ~= "" then
			return
		end
		if #keys == 0 then
			return
		end
		local moving, staying = {}, {}
		local movingSet: { [string]: boolean } = {}
		for _, key in keys do
			movingSet[key] = true
		end
		for _, track in bakeManualOrder() do
			table.insert(if movingSet[track.id] then moving else staying, track)
		end
		local out = {}
		for i = 1, toIndex do
			table.insert(out, staying[i])
		end
		for _, track in moving do
			table.insert(out, track)
		end
		for i = toIndex + 1, #staying do
			table.insert(out, staying[i])
		end
		baseRows:set(out)
	end
	function built.screen()
		local tracks = UI.Table({
			Name = "Tracks",
			Size = UDim2.new(1, 0, 0, 328),
			widths = columnWidths,
			columns = {
				{
					id = "name",
					label = "Name",
					width = 220,
					minWidth = 90,
					resizable = true,
					sortable = true,
					value = function(item)
						return plain(item).name
					end,
				},
				{
					id = "artist",
					label = "Artist",
					width = 220,
					minWidth = 72,
					resizable = true,
					sortable = true,
					value = function(item)
						return plain(item).artist
					end,
				},
				{
					id = "rating",
					label = "Rating",
					width = 144,
					sortable = true,
					value = function(item)
						return ratings[plain(item).id]:peek()
					end,
					render = starCell,
				},
			},

			from = filteredRows,
			key = function(item)
				return plain(item).id
			end,

			sort = sortOrder,
			selectionMode = "multi",
			selection = Compose.cell({}),
			onActivate = function(item: any, _key: string)
				nowPlaying:set(plain(item).name)
			end,
			reorderable = true,

			rowActions = function(item: any)
				local id = plain(item).id
				return {
					leading = {
						{
							id = "top",
							label = "Top",
							icon = "chevron.up",
							onActivate = function()
								moveToTop(id)
							end,
						},
					},
					trailing = {
						{
							id = "remove",
							label = "Remove",
							icon = "trash",
							role = "destructive",
							onActivate = function()
								removeTrack(id)
							end,
						},
					},
					fullSwipe = true,
				}
			end,
			onReorder = reorder,
		})

		local function restore()
			filterText:set("")
			sortOrder:set(nil)
			baseRows:set(table.clone(TRACKS))
			nowPlaying:set(nil)
			for _, track in TRACKS do
				ratings[track.id]:set(track.rating)
			end
		end
		local COLUMN_LABELS = { { "name", "Name", true }, { "artist", "Artist", true }, { "rating", "Rating", false } }
		local widthsText = Compose.formula(function(use)
			local overrides = use(columnWidths) :: { [string]: number }
			local hidden = {} :: { string }
			local hiddenSet: { [string]: boolean } = {}
			for _, id in hidden do
				hiddenSet[id] = true
			end
			local parts = {}
			for _, column in COLUMN_LABELS do
				local id, label, resizable = column[1] :: string, column[2] :: string, column[3] :: boolean
				local px = overrides[id]
				local shown = if hiddenSet[id]
					then "hidden"
					elseif px ~= nil then `{math.floor(px + 0.5)}px`
					elseif resizable then "auto"
					else "locked"
				table.insert(parts, `{label} {shown}`)
			end
			local line = table.concat(parts, " · ")
			return if #hidden > 0 then `{line} · {#hidden} hidden` else line
		end)
		local hintText = Compose.formula(function(use)
			local selected = nil :: string?
			if selected == nil then
				return "Type to filter · tap a heading to sort · drag a divider to resize · swipe a row for its actions"
			end
			local label = "Rating"
			for _, column in COLUMN_LABELS do
				if column[1] == selected then
					label = column[2] :: string
				end
			end
			return `{label} has the keys: , and . resize it, ↑/↓ sorts`
		end)
		local nowPlayingText = function(use)
			local track = use(nowPlaying)
			if track == nil then
				return "Nothing playing — double-click a row, or press Return on a focused one"
			end
			return `Now playing — {track}`
		end
		local screen = Host.Frame({
			Name = "Playlist",
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
					Padding = UDim.new(0, 8),
				}),
				UI.Label({

					Name = "Title",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = "Playlist",
					TextSize = 28,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.TextInput({

					Name = "Filter",
					value = filterText,
					presentation = "search",
					placeholder = "Filter tracks",
				}),
				UI.Label({

					Name = "Hint",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = hintText,
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					Name = "NowPlaying",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = nowPlayingText,
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					Name = "Widths",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = widthsText,
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				tracks,
				UI.Button({

					Name = "Restore",
					label = "Restore the original playlist",
					onActivate = restore,
				}),
			}),
		})
		local exports = {
			from = filteredRows,
			sortedRows = sortedRows,
			baseRows = baseRows,
			sort = sortOrder,

			widths = function(): string
				return widthsText:peek()
			end,

			hint = function(): string
				return hintText:peek()
			end,
			reorder = reorder,
			moveToTop = moveToTop,
			removeTrack = removeTrack,
			filterText = filterText,

			nowPlaying = nowPlaying,
			nowPlayingPath = "/Playlist/Page/NowPlaying",
			ratingFor = function(id: string)
				return ratings[id]
			end,
			columnWidths = columnWidths,
			restore = restore,
			restorePath = "/Playlist/Page/Restore",
		}
		for key, value in exports do
			built[key] = value
		end
		return screen
	end
	built.dispose = function() end
	return built
end
return example
