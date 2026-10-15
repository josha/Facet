--!strict

type ExampleContext = typeof(require("@repo/examples/types").Context)
type PlaylistBuilt = { [string]: unknown, screen: () -> Instance, dispose: () -> () }
type TableColumn = typeof(require("@repo/tools/typecheck/aliases").TableColumn)
type RowAction = typeof(require("@repo/tools/typecheck/aliases").RowAction)
type RowActionsOptions = typeof(require("@repo/tools/typecheck/aliases").RowActionsOptions)

type Readable<T> = { peek: (Readable<T>) -> T }
type Cell<T> = Readable<T> & { set: (Cell<T>, T) -> (), update: (Cell<T>, (T) -> T) -> () }
type Use = <T>(Readable<T>) -> T
type Sort = { column: string, direction: "ascending" | "descending" }
type Track = { id: string, name: string, artist: string, length: number, rating: number }

local example = {}
example.title = "Playlist Table"
local TRACKS: { Track } = {
	{ id = "neon", name = "Neon Straightaway", artist = "Chrome Coyote", length = 214, rating = 4 },
	{ id = "drift", name = "Drift City Nights", artist = "Nine Volt", length = 187, rating = 3 },
	{ id = "turbo", name = "Turbo Cascade", artist = "Paper Lantern", length = 243, rating = 5 },
	{ id = "pit", name = "Pit Lane Shuffle", artist = "Rustbucket", length = 158, rating = 2 },
	{ id = "photo", name = "Photo Finish", artist = "Bad Weather", length = 201, rating = 0 },
	{ id = "apex", name = "Apex Bloom", artist = "Nine Volt", length = 176, rating = 3 },
}
function example.build(ctx: ExampleContext)
	local UI, Compose = ctx.UI, ctx.Compose
	local UDim2, Enum = ctx.types.UDim2, ctx.types.Enum
	local built: PlaylistBuilt = {
		screen = function(): Instance
			error("the playlist screen is not ready")
		end,
		dispose = function() end,
	}

	local baseRows = Compose.cell(table.clone(TRACKS))
	local filterText = Compose.cell("")
	local nothingPlaying: string? = nil
	local nowPlaying: Cell<string?> = Compose.cell(nothingPlaying)
	local unsorted: Sort? = nil
	local sortOrder: Cell<Sort?> = Compose.cell(unsorted)
	local noWidths: { [string]: number } = {}
	local columnWidths = Compose.cell(noWidths)
	local ratings: { [string]: typeof(Compose.cell(0)) } = {}
	for _, track in TRACKS do
		ratings[track.id] = Compose.cell(track.rating)
	end
	local sortedRows = Compose.formula(function(use: Use)
		local all = use(baseRows)
		local order = use(sortOrder)
		if order == nil then
			return all
		end
		local column, direction = order.column, order.direction
		local index: { [string]: number } = {}
		for i, track in all do
			index[track.id] = i
		end
		local ratingKeys: { [string]: number } = {}
		local textKeys: { [string]: string } = {}
		for _, track in all do
			if column == "rating" then
				ratingKeys[track.id] = use(ratings[track.id])
			elseif column == "artist" then
				textKeys[track.id] = track.artist
			else
				textKeys[track.id] = track.name
			end
		end
		local out = table.clone(all)
		table.sort(out, function(a, b)
			local same, ascending
			if column == "rating" then
				local av, bv = ratingKeys[a.id], ratingKeys[b.id]
				same, ascending = av == bv, av < bv
			else
				local av, bv = textKeys[a.id], textKeys[b.id]
				same, ascending = av == bv, av < bv
			end
			if same then
				return index[a.id] < index[b.id]
			end
			return if direction == "ascending" then ascending else not ascending
		end)
		return out
	end)
	local filteredRows = Compose.formula(function(use: Use)
		local query = string.lower(use(filterText))
		local all = use(sortedRows)
		if query == "" then
			return all
		end
		local out: { Track } = {}
		for _, track in all do
			if string.find(string.lower(track.name), query, 1, true) ~= nil then
				table.insert(out, track)
			end
		end
		return out
	end)
	local function bakeManualOrder(): { Track }
		if sortOrder:peek() ~= nil then
			baseRows:set(table.clone(sortedRows:peek()))
			sortOrder:set(nil)
		end
		return baseRows:peek()
	end
	local function starCell(item: Readable<Track>)
		return UI.Rating "Rating" { value = ratings[item:peek().id], count = 5 }
	end

	local function removeTrack(id: string)
		local out: { Track } = {}
		for _, track in baseRows:peek() do
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
		for _, track in baseRows:peek() do
			if track.id == id then
				present = true
				break
			end
		end
		if not present then
			return
		end
		local moved: Track? = nil
		local rest: { Track } = {}
		for _, track in bakeManualOrder() do
			if track.id == id then
				moved = track
			else
				table.insert(rest, track)
			end
		end
		table.insert(rest, 1, assert(moved))
		baseRows:set(rest)
	end
	local function reorder(keys: { string }, toIndex: number)
		if filterText:peek() ~= "" then
			return
		end
		if #keys == 0 then
			return
		end
		local moving: { Track }, staying: { Track } = {}, {}
		local movingSet: { [string]: boolean } = {}
		for _, key in keys do
			movingSet[key] = true
		end
		for _, track in bakeManualOrder() do
			table.insert(if movingSet[track.id] then moving else staying, track)
		end
		local out: { Track } = {}
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
	built.screen = function()
		local columns: { TableColumn } = {
			{
				id = "name",
				label = "Name",
				wrap = false,
				minWidth = 90,
				resizable = true,
				sortable = true,
				value = function(item: Track)
					return item.name
				end,
			},
			{
				id = "artist",
				label = "Artist",
				wrap = false,
				minWidth = 72,
				priority = 1,
				resizable = true,
				sortable = true,
				value = function(item: Track)
					return item.artist
				end,
			},
			{
				id = "rating",
				label = "Rating",
				priority = 2,
				width = 144,
				resizable = false,
				sortable = true,
				value = function(item: Track)
					return ratings[item.id]:peek()
				end,
				render = starCell,
				detailRender = starCell,
			},
		}
		local noSelection: { [string]: boolean } = {}
		local tracks = UI.Table "Tracks" {
			Size = UDim2.new(1, 0, 0, 328),
			widths = columnWidths,
			columns = columns,

			from = filteredRows,
			key = "id",

			sort = sortOrder,
			selectionMode = "multiple",
			selection = Compose.cell(noSelection),
			onActivate = function(item: Track, _key: string, input: InputObject?, clickCount: number?)
				if input and input.UserInputType == Enum.UserInputType.MouseButton1 and (clickCount or 0) < 1 then
					return
				end
				nowPlaying:set(item.name)
			end,
			reorderable = true,
			deletable = true,
			onDelete = function(keys: { string })
				for _, id in keys do
					removeTrack(id)
				end
			end,

			rowActions = function(item: Readable<Track>)
				local id = item:peek().id
				local leading: { RowAction } = {
					{
						id = "top",
						label = "Top",
						icon = "chevron.up",
						onActivate = function()
							moveToTop(id)
						end,
					},
				}
				local trailing: { RowAction } = {
					{
						id = "remove",
						label = "Remove",
						icon = "trash",
						role = "destructive",
						onActivate = function()
							removeTrack(id)
						end,
					},
				}
				local actions: RowActionsOptions = { leading = leading, trailing = trailing, fullSwipe = true }
				return actions
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
		local widthsText = Compose.formula(function(use: Use)
			local overrides = use(columnWidths)
			local parts: { string } = {}
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
			"Type to filter · tap a heading to sort · drag a divider to resize · drag a row to move it · Delete removes the selected rows · swipe a row for its actions"
		local nowPlayingText = function(use: Use)
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
				UI.Text "Title" { text = "Playlist", textRole = "title" },
				UI.TextInput "Filter" {
					value = filterText,
					presentation = "search",
					placeholder = "Filter tracks",
				},
				UI.Text "EmptyResult" {
					Visible = function(use: Use)
						return #use(filteredRows) == 0
					end,
					text = function(use: Use)
						return if #use(baseRows) == 0
							then "No tracks in this playlist. Restore the original playlist to add them again."
							else "No tracks match this filter. Clear the filter to show all tracks."
					end,
					TextWrapped = true,
				},
				UI.Text "Hint" { text = hintText, textRole = "caption", TextWrapped = true },
				UI.Text "NowPlaying" {
					text = nowPlayingText,
					textRole = "caption",
					TextWrapped = true,
				},
				UI.Text "Widths" { text = widthsText, textRole = "caption", TextWrapped = true },
				tracks,
				UI.Button "Restore" {
					label = "Restore the original playlist",
					onActivate = restore,
				},
			},
		}
		local exports: { [string]: unknown } = {
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
	return built
end
return example
