--!strict

type Use = (any) -> any
type Column = {
	id: string,
	label: string,
	width: number?,
	minWidth: number?,
	resizable: boolean,
	sortable: boolean,
	value: (any) -> any,
	render: ((any) -> any)?,
}

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
	local UDim2, Enum = ctx.types.UDim2, ctx.types.Enum
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
	local filteredRows = Compose.formula(function(use: Use)
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
		return UI.Rating "Rating" {
			value = ratings[plain(item).id],
			count = 5,
		}
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
		local tracks = UI.Table "Tracks" {
			Size = UDim2.new(1, 0, 0, 328),
			widths = columnWidths,
			columns = {
				{
					id = "name",
					label = "Name",
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
					resizable = false,
					sortable = true,
					value = function(item)
						return ratings[plain(item).id]:peek()
					end,
					render = starCell,
				},
			} :: { Column },

			from = filteredRows,
			key = "id",

			sort = sortOrder,
			selectionMode = "multi",
			selection = Compose.cell({}),
			onActivate = function(item: any, _key: string, input: InputObject?, clickCount: number?)
				if input and input.UserInputType == Enum.UserInputType.MouseButton1 and (clickCount or 1) < 2 then
					return
				end
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
		}

		local function restore()
			filterText:set("")
			sortOrder:set(nil)
			baseRows:set(table.clone(TRACKS))
			nowPlaying:set(nil)
			for _, track in TRACKS do
				ratings[track.id]:set(track.rating)
			end
		end
		local COLUMN_LABELS = {
			{ id = "name", label = "Name", resizable = true },
			{ id = "artist", label = "Artist", resizable = true },
			{ id = "rating", label = "Rating", resizable = false },
		}
		local widthsText = Compose.formula(function(use)
			local overrides = use(columnWidths) :: { [string]: number }
			local parts = {}
			for _, column in COLUMN_LABELS do
				local px = overrides[column.id]
				local shown = if px ~= nil
					then `{math.floor(px + 0.5)}px`
					elseif column.resizable then "auto"
					else "locked"
				table.insert(parts, `{column.label} {shown}`)
			end
			return table.concat(parts, " · ")
		end)
		local hintText =
			"Type to filter · tap a heading to sort · drag a divider to resize · swipe a row for its actions"
		local nowPlayingText = function(use)
			local track = use(nowPlaying)
			if track == nil then
				return "Nothing playing — double-click a row, or press Return on a focused one"
			end
			return `Now playing — {track}`
		end
		local screen = UI.Screen "Playlist" {
			UI.ScrollView "Page" {
				gap = "s",
				align = "stretch",
				UI.Label "Title" { text = "Playlist", textRole = "title" },
				UI.TextInput "Filter" {
					value = filterText,
					presentation = "search",
					placeholder = "Filter tracks",
				},
				UI.Label "Hint" { text = hintText, textRole = "caption", TextWrapped = true },
				UI.Label "NowPlaying" { text = nowPlayingText, textRole = "caption", TextWrapped = true },
				UI.Label "Widths" { text = widthsText, textRole = "caption", TextWrapped = true },
				tracks,
				UI.Button "Restore" {
					label = "Restore the original playlist",
					onActivate = restore,
				},
			},
		}
		local exports = {
			from = filteredRows,
			sortedRows = sortedRows,
			baseRows = baseRows,
			sort = sortOrder,

			widths = function(): string
				return widthsText:peek()
			end,

			hint = function(): string
				return hintText
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
