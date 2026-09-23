--!strict

local assets = require("./assets")

local ROWS = 6
local COLS = 6
local KINDS = { "a", "b", "c", "d", "e" }
local DEFAULT_SEED = 20260720

local PHASE_SECONDS: { [string]: number } = {
	swap = 0.2,
	revert = 0.2,
	mark = 0.16,
	remove = 0.24,
	gravity = 0.26,
	refill = 0.1,
	land = 0.26,
}

local function makeRng(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

local function findMatchesIn(grid: { { string } }): { [string]: boolean }
	local matched: { [string]: boolean } = {}
	local function same(a: string?, b: string?): boolean
		return a ~= nil and a ~= "" and a == b
	end
	for r = 1, ROWS do
		local run = 1
		for c = 2, COLS + 1 do
			if c <= COLS and same(grid[r][c], grid[r][c - 1]) then
				run += 1
			else
				if run >= 3 then
					for k = c - run, c - 1 do
						matched[r .. "," .. k] = true
					end
				end
				run = 1
			end
		end
	end
	for c = 1, COLS do
		local run = 1
		for r = 2, ROWS + 1 do
			if r <= ROWS and same(grid[r][c], grid[r - 1][c]) then
				run += 1
			else
				if run >= 3 then
					for k = r - run, r - 1 do
						matched[k .. "," .. c] = true
					end
				end
				run = 1
			end
		end
	end
	return matched
end

local function hasLegalMoveIn(grid: { { string } }): boolean
	local function trySwap(r1: number, c1: number, r2: number, c2: number): boolean
		grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1]
		local any = next(findMatchesIn(grid)) ~= nil
		grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1]
		return any
	end
	for r = 1, ROWS do
		for c = 1, COLS do
			if c < COLS and trySwap(r, c, r, c + 1) then
				return true
			end
			if r < ROWS and trySwap(r, c, r + 1, c) then
				return true
			end
		end
	end
	return false
end

local function build(ctx: any)
	local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
	local nativeTypes = ctx.types or { UDim = UDim, UDim2 = UDim2, Vector2 = Vector2, Color3 = Color3, Enum = Enum }
	local UDim, UDim2, Vector2, Color3, Enum =
		nativeTypes.UDim, nativeTypes.UDim2, nativeTypes.Vector2, nativeTypes.Color3, nativeTypes.Enum
	local reducedMotion = Compose.cell(ctx.guiService ~= nil and ctx.guiService.ReducedMotionEnabled == true)
	if ctx.guiService then
		local connection = ctx.guiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			reducedMotion:set(ctx.guiService.ReducedMotionEnabled == true)
		end)
		Compose.cleanup(function()
			connection:Disconnect()
		end)
	end
	local seed = DEFAULT_SEED

	local rng = makeRng(seed)
	local function nextKind(): string
		return KINDS[math.floor(rng() * #KINDS) + 1]
	end
	local function collapseIn(grid: { { string } })
		for c = 1, COLS do
			local stack: { string } = {}
			for r = ROWS, 1, -1 do
				if grid[r][c] ~= nil then
					table.insert(stack, grid[r][c])
				end
			end
			for r = ROWS, 1, -1 do
				local idx = ROWS - r + 1
				grid[r][c] = if stack[idx] ~= nil then stack[idx] else nextKind()
			end
		end
	end
	local function dealKinds(): { { string } }
		local grid: { { string } } = {}
		for r = 1, ROWS do
			grid[r] = {}
			for c = 1, COLS do
				grid[r][c] = nextKind()
			end
		end
		for _ = 1, 64 do
			while true do
				local matched = findMatchesIn(grid)
				if next(matched) == nil then
					break
				end
				for key in matched do
					local rs, cs = key:match("(%d+),(%d+)")
					grid[tonumber(rs) :: number][tonumber(cs) :: number] = nil :: any
				end
				collapseIn(grid)
			end
			if hasLegalMoveIn(grid) then
				return grid
			end
			for r = 1, ROWS do
				for c = 1, COLS do
					grid[r][c] = nextKind()
				end
			end
		end
		return grid
	end
	type Tile = {
		id: number,
		kind: string,
		row: number,
		col: number,
		spawnRow: number?,
		setKind: any,
		setPosition: any,
		setMarked: any,
		setLeaving: any,
		hit: any,
	}
	local board: { { Tile? } } = {}
	for r = 1, ROWS do
		board[r] = {}
	end
	local nextTileId = 0
	local function newTile(kind: string, row: number, col: number): Tile
		nextTileId += 1
		return {
			id = nextTileId,
			kind = kind,
			row = row,
			col = col,
			spawnRow = nil,
			setKind = nil,
			setPosition = nil,
			setMarked = nil,
			setLeaving = nil,
		}
	end
	local function kindGrid(): { { string } }
		local grid: { { string } } = {}
		for r = 1, ROWS do
			grid[r] = {}
			for c = 1, COLS do
				local tile = board[r][c]
				grid[r][c] = if tile ~= nil then tile.kind else ""
			end
		end
		return grid
	end
	local function findMatches(): { [string]: boolean }
		return findMatchesIn(kindGrid())
	end
	local function hasLegalMove(): boolean
		return hasLegalMoveIn(kindGrid())
	end
	local syncSelection
	local items = Compose.cell({} :: { { id: number } })

	local leaving: { Tile } = {}
	local function publish()
		local out: { { id: number } } = {}
		for _, tile in leaving do
			table.insert(out, { id = tile.id })
		end
		for r = 1, ROWS do
			for c = 1, COLS do
				local tile = board[r][c]
				if tile ~= nil then
					table.insert(out, { id = tile.id })
				end
			end
		end
		items:set(out)
		if syncSelection then
			syncSelection()
		end
	end
	local function syncPositions()
		for r = 1, ROWS do
			for c = 1, COLS do
				local tile = board[r][c]
				if tile ~= nil and tile.setPosition ~= nil then
					tile.setPosition({ row = tile.row, col = tile.col })
				end
			end
		end
	end
	local function syncKinds()
		for r = 1, ROWS do
			for c = 1, COLS do
				local tile = board[r][c]
				if tile ~= nil and tile.setKind ~= nil then
					tile.setKind(tile.kind)
				end
			end
		end
	end
	local score = Compose.cell(0)
	local moves = Compose.cell(0)
	local message = Compose.cell("")
	local resolving = Compose.cell(false)
	local selected = Compose.cell(nil :: { number }?)
	local kindHandle = {}
	for _, kind in KINDS do
		kindHandle[kind] = { state = Compose.cell("ready"), value = Compose.cell(assets.match3Tiles[kind].image) }
	end
	local PENDING = assets.pending
	local function deliverArt()
		local delivered = 0
		for kind, held in kindHandle do
			if held.state:peek() == "pending" then
				held.value:set(assets.match3Tiles[kind].image)
				held.state:set("ready")
				delivered += 1
			end
		end
		return delivered
	end
	local function requestArt(kind)
		kindHandle[kind].value:set(nil)
		kindHandle[kind].state:set("pending")
	end
	local function reloadArt()
		for _, kind in KINDS do
			requestArt(kind)
		end
		message:set("Artwork re-requested — the tiles show the loading placeholder until it arrives.")
	end
	local function failArt()
		kindHandle[KINDS[1]].state:set("failed")
		message:set("One tile kind failed to load. Re-request artwork, then deliver artwork.")
	end
	local artStatus = Compose.formula(function(use)
		local pending, failed, ready = 0, 0, 0
		for _, kind in KINDS do
			local state = use(kindHandle[kind].state)
			if state == "ready" then
				ready += 1
			elseif state == "failed" then
				failed += 1
			else
				pending += 1
			end
		end
		if failed > 0 then
			return `Artwork: {failed} failed, {ready} ready`
		end
		if pending > 0 then
			return `Artwork: loading {pending} of {#KINDS}`
		end
		return `Artwork: all {ready} ready`
	end)
	local activateTile: (tile: Tile) -> ()
	local beginSwap: (number, number, number, number) -> ()
	local tilesById: { [number]: Tile } = {}
	syncSelection = function()
		for row = 1, ROWS do
			for col = 1, COLS do
				local tile = board[row][col]
				if tile and tile.hit then
					local left, right = board[row][col - 1], board[row][col + 1]
					local up, down =
						if row > 1 then board[row - 1][col] else nil, if row < ROWS then board[row + 1][col] else nil
					tile.hit.NextSelectionLeft = if left then left.hit else tile.hit
					tile.hit.NextSelectionRight = if right then right.hit else tile.hit
					tile.hit.NextSelectionUp = if up then up.hit else nil
					tile.hit.NextSelectionDown = if down then down.hit else nil
				end
			end
		end
	end
	local function TileView(item: any)
		local tile = tilesById[item:peek().id]
		local kind = Compose.cell(tile.kind)
		local position = Compose.cell({
			row = if tile.spawnRow ~= nil then tile.spawnRow else tile.row,
			col = tile.col,
		})
		local marked = Compose.cell(false)

		local dragOrigin, dragDelta
		local dragMoved = false
		function tile.setKind(value)
			kind:set(value)
		end
		function tile.setPosition(value)
			position:set(value)
		end
		function tile.setMarked(value)
			marked:set(value)
		end
		local isLeaving = Compose.cell(false)
		function tile.setLeaving(value)
			isLeaving:set(value)
		end
		Compose.cleanup(function()
			tile.setKind, tile.setPosition, tile.setMarked, tile.setLeaving, tile.hit = nil, nil, nil, nil, nil
		end)
		local image = Compose.formula(function(use)
			local handle = kindHandle[use(kind)]
			if use(handle.state) ~= "ready" then
				return PENDING
			end
			local resolved = use(handle.value)
			return if resolved ~= nil then resolved else PENDING
		end)

		local fallbackLabel = Compose.formula(function(use)
			local current = use(kind)
			local ready = use(kindHandle[current].state) == "ready"
			return if ready then "" else assets.match3Tiles[current].label
		end)
		local picked = Compose.formula(function(use)
			if use(marked) then
				return true
			end
			local sel = use(selected)
			local at = use(position)
			return sel ~= nil and sel[1] == at.row and sel[2] == at.col
		end)
		local targetPosition = Compose.formula(function(use)
			local at = use(position)
			return UDim2.fromOffset((at.col - 1) * 48, (at.row - 1) * 48)
		end)
		local targetTransparency = Compose.formula(function(use)
			return if use(isLeaving) then 1 else 0
		end)
		local movingPosition = ctx.runtime.spring(function(use)
			return use(targetPosition)
		end, { period = 0.18, damping = 1 })
		local fading = ctx.runtime.tween(function(use)
			return use(targetTransparency)
		end, { seconds = 0.16 })
		return Host.CanvasGroup({
			Name = `tile{tile.id}`,
			GroupTransparency = function(use)
				return if use(reducedMotion) then use(targetTransparency) else use(fading)
			end,
			BackgroundTransparency = 1,
			Size = function(use)
				return UDim2.new(0, 44, 0, 44)
			end,
			AnchorPoint = Vector2.new(0, 0),
			Position = function(use)
				return if use(reducedMotion) then use(targetPosition) else use(movingPosition)
			end,
			Host.ImageLabel({
				Name = "img",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				Image = image,
			}),
			UI.Button({
				Name = "hit",
				ref = function(node)
					tile.hit = node
				end,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.new(1, 0, 1, 0),
				label = fallbackLabel,
				selected = picked,
				TextSize = 16,
				Host.UIStroke({
					Name = "Selection",
					Thickness = 3,
					Color = Color3.new(1, 1, 1),
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Transparency = function(use)
						return if use(picked) then 0 else 1
					end,
				}),
				onActivate = function(input)
					if
						input
						and (
							input.UserInputType == Enum.UserInputType.MouseButton1
							or input.UserInputType == Enum.UserInputType.Touch
						)
					then
						return
					end
					activateTile(tile)
				end,
				Host.UIDragDetector({
					Name = "SwapDrag",
					ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset,
					Enabled = function(use)
						return not use(resolving)
					end,
					DragStart = function(at)
						dragOrigin = if resolving:peek() then nil else at
						dragDelta = nil
						dragMoved = false
					end,
					DragContinue = function(at)
						if dragOrigin then
							dragDelta = at - dragOrigin
							dragMoved = dragMoved or dragDelta.Magnitude >= 16
						end
					end,
					DragEnd = function(at)
						local origin = dragOrigin
						local delta = if origin and at then at - origin else dragDelta
						dragOrigin, dragDelta = nil, nil
						if not origin or resolving:peek() or not tile.hit then
							return
						end
						if delta and delta.Magnitude >= 16 then
							local horizontal = math.abs(delta.X) > math.abs(delta.Y)
							local r = tile.row + (if horizontal then 0 else (if delta.Y > 0 then 1 else -1))
							local c = tile.col + (if horizontal then (if delta.X > 0 then 1 else -1) else 0)
							if r >= 1 and r <= ROWS and c >= 1 and c <= COLS then
								selected:set(nil)
								beginSwap(tile.row, tile.col, r, c)
							end
						elseif at and not dragMoved then
							local position, size = tile.hit.AbsolutePosition, tile.hit.AbsoluteSize
							if
								at.X >= position.X
								and at.Y >= position.Y
								and at.X < position.X + size.X
								and at.Y < position.Y + size.Y
							then
								activateTile(tile)
							end
						end
					end,
				}),
			}),
		})
	end
	local function boardView()
		local node = Host.Frame({
			Name = "board",
			BackgroundTransparency = 1,
			Size = function(use)
				return UDim2.new(0, COLS * 48, 0, ROWS * 48)
			end,
			Compose.OrderedCollection({
				from = items,
				key = function(item)
					return item.id
				end,
				render = TileView,
			}),
		})
		syncSelection()
		return node
	end
	local function dealBoard()
		local grid = dealKinds()
		tilesById = {}
		table.clear(leaving)
		for r = 1, ROWS do
			for c = 1, COLS do
				local tile = newTile(grid[r][c], r, c)
				board[r][c] = tile
				tilesById[tile.id] = tile
			end
		end
		publish()
	end
	dealBoard()
	local phase = "idle"
	local elapsed = 0
	local phaseLog: { string } = {}
	local pendingSwap: { number }? = nil
	local unsubTick: (() -> ())? = nil
	local enterPhase: (name: string) -> ()
	local function stopTicking()
		if unsubTick ~= nil then
			unsubTick()
			unsubTick = nil
		end
	end
	Compose.cleanup(stopTicking)
	local function tileAt(r: number, c: number): Tile?
		return board[r][c]
	end
	local clearedThisRun = 0
	local swapScored = false
	local function settleMessage()
		if not swapScored then
			return
		end
		local cleared = clearedThisRun
		message:set(`Cleared {cleared} tiles.`)
		if not hasLegalMove() then
			dealBoard()
			message:set(`Cleared {cleared} tiles — no moves left, so the board was re-dealt.`)
		end
	end
	local PHASE_ACTION: { [string]: () -> () } = {
		swap = function()
			local move = pendingSwap :: { number }
			ctx.runtime:batch(function()
				local a, b = tileAt(move[1], move[2]) :: Tile, tileAt(move[3], move[4]) :: Tile
				a.row, a.col, b.row, b.col = b.row, b.col, a.row, a.col
				board[a.row][a.col], board[b.row][b.col] = a, b
				syncPositions()
				publish()
			end)
		end,
		revert = function()
			local move = pendingSwap :: { number }
			ctx.runtime:batch(function()
				local a, b = tileAt(move[1], move[2]) :: Tile, tileAt(move[3], move[4]) :: Tile
				a.row, a.col, b.row, b.col = b.row, b.col, a.row, a.col
				board[a.row][a.col], board[b.row][b.col] = a, b
				syncPositions()
				publish()
			end)
			message:set("That swap makes no run of three. Try a different pair.")
		end,
		mark = function()
			for key in findMatches() do
				local rs, cs = key:match("(%d+),(%d+)")
				local tile = board[tonumber(rs) :: number][tonumber(cs) :: number]
				if tile ~= nil and tile.setMarked ~= nil then
					tile.setMarked(true)
				end
			end
		end,
		remove = function()
			local cleared = 0
			for key in findMatches() do
				local rs, cs = key:match("(%d+),(%d+)")
				local r, c = tonumber(rs) :: number, tonumber(cs) :: number
				local tile = board[r][c]
				if tile ~= nil then
					tilesById[tile.id] = nil
					board[r][c] = nil
					table.insert(leaving, tile)
					if tile.setLeaving ~= nil then
						tile.setLeaving(true)
					end
					cleared += 1
				end
			end
			clearedThisRun += cleared
			if cleared > 0 then
				score:set(score:peek() + cleared)
			end
			publish()
			phaseLog[#phaseLog] = `remove:{cleared}`
		end,
		gravity = function()
			ctx.runtime:batch(function()
				table.clear(leaving)
				for c = 1, COLS do
					local stack: { Tile } = {}
					for r = ROWS, 1, -1 do
						local tile = board[r][c]
						if tile ~= nil then
							table.insert(stack, tile)
						end
						board[r][c] = nil
					end
					for i, tile in stack do
						local r = ROWS - i + 1
						tile.row = r
						board[r][c] = tile
					end
				end
				syncPositions()
				publish()
			end)
		end,
		refill = function()
			local added = 0
			for c = 1, COLS do
				local holes = 0
				for r = 1, ROWS do
					if board[r][c] == nil then
						holes += 1
					end
				end
				for r = holes, 1, -1 do
					local tile = newTile(nextKind(), r, c)
					tile.spawnRow = r - holes
					board[r][c] = tile
					tilesById[tile.id] = tile
					added += 1
				end
			end
			publish()
			phaseLog[#phaseLog] = `refill:{added}`
		end,
		land = function()
			ctx.runtime:batch(function()
				for r = 1, ROWS do
					for c = 1, COLS do
						local tile = board[r][c]
						if tile ~= nil then
							tile.spawnRow = nil
						end
					end
				end
				syncPositions()
			end)
		end,
		idle = function()
			pendingSwap = nil
			stopTicking()
			resolving:set(false)
			settleMessage()
			clearedThisRun = 0
			swapScored = false
		end,
	}
	enterPhase = function(name: string)
		phase = name
		elapsed = 0
		table.insert(phaseLog, name)
		local action = PHASE_ACTION[name]
		if action ~= nil then
			action()
		end
	end
	local function advance()
		if phase == "swap" then
			if next(findMatches()) ~= nil then
				moves:set(moves:peek() + 1)
				swapScored = true
				enterPhase("mark")
			else
				enterPhase("revert")
			end
		elseif phase == "revert" then
			enterPhase("idle")
		elseif phase == "mark" then
			enterPhase("remove")
		elseif phase == "remove" then
			enterPhase("gravity")
		elseif phase == "gravity" then
			enterPhase("refill")
		elseif phase == "refill" then
			enterPhase("land")
		elseif phase == "land" then
			if next(findMatches()) ~= nil then
				enterPhase("mark")
			else
				enterPhase("idle")
			end
		end
	end
	local function onFrame(dt: number)
		local duration = PHASE_SECONDS[phase]
		if duration == nil then
			return
		end
		elapsed += dt
		if elapsed >= duration then
			advance()
		end
	end
	beginSwap = function(r1: number, c1: number, r2: number, c2: number)
		pendingSwap = { r1, c1, r2, c2 }
		clearedThisRun = 0
		swapScored = false
		resolving:set(true)
		if unsubTick == nil then
			local connection = (ctx.runService or game:GetService("RunService")).Heartbeat:Connect(onFrame)
			unsubTick = function()
				connection:Disconnect()
			end
		end
		enterPhase("swap")
	end
	activateTile = function(tile: Tile)
		if resolving:peek() then
			message:set("The board is still settling — wait for the tiles to land.")
			return
		end
		local r, c = tile.row, tile.col
		local sel = selected:peek()
		if sel == nil then
			selected:set({ r, c })
			message:set("")
		elseif sel[1] == r and sel[2] == c then
			selected:set(nil)
			message:set("")
		elseif math.abs(sel[1] - r) + math.abs(sel[2] - c) == 1 then
			selected:set(nil)
			message:set("")
			beginSwap(sel[1], sel[2], r, c)
		else
			selected:set({ r, c })
			message:set("Tiles have to touch to swap. Pick a neighbour of the tile you chose.")
		end
	end
	local function reset()
		stopTicking()
		phase = "idle"
		elapsed = 0
		pendingSwap = nil
		clearedThisRun = 0
		swapScored = false
		table.clear(phaseLog)
		resolving:set(false)
		selected:set(nil)
		score:set(0)
		moves:set(0)
		rng = makeRng(seed)
		dealBoard()
		message:set("")
	end
	local hint: any
	local function Match3()
		hint = Compose.formula(function(use)
			local said = use(message)
			if said ~= "" then
				return said
			end
			if use(resolving) then
				return "The board is settling — tiles are clearing, dropping and refilling."
			end
			if use(selected) == nil then
				return "Drag a tile onto a neighbor, or select two neighboring tiles. Three in a row clears."
			end
			return "Now tap a tile next to it — or tap the same tile again to put it down."
		end)
		local scoreText = Compose.formula(function(use)
			return `Score {use(score)}`
		end)
		local movesText = Compose.formula(function(use)
			return `{use(moves)} swaps`
		end)
		return Host.Frame({
			Name = "Match3",
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
					Text = "Facet Match-3",
					TextSize = 28,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				UI.Label({

					Name = "Hint",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = hint,
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({

					Name = "Stats",
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Host.UIListLayout({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 16),
						Wraps = true,
					}),
					UI.Label({
						LayoutOrder = 1,
						Name = "Score",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = scoreText,
						TextSize = 16,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					UI.Label({
						LayoutOrder = 2,
						Name = "Moves",
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = movesText,
						TextSize = 16,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				}),
				boardView(),
				UI.Label({

					Name = "ArtStatus",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = artStatus,
					TextSize = 16,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Host.Frame({

					Name = "Art",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Host.UIGridLayout({
						SortOrder = Enum.SortOrder.LayoutOrder,
						CellSize = UDim2.new(1 / 2, -8, 0, 120),
						CellPadding = UDim2.fromOffset(8, 8),
					}),
					UI.Button({
						LayoutOrder = 1,
						Name = "Reload",
						label = "Re-request artwork",
						onActivate = reloadArt,
					}),
					UI.Button({
						LayoutOrder = 2,
						Name = "Deliver",
						label = "Deliver artwork",
						onActivate = function()
							local n = deliverArt()
							message:set(
								if n > 0 then `Delivered {n} tile pictures.` else "Nothing was waiting to be delivered."
							)
						end,
					}),
					UI.Button({
						LayoutOrder = 3,
						Name = "Break",
						label = "Fail a load",
						onActivate = failArt,
					}),
				}),
				UI.Button({

					Name = "Reset",
					label = "New board",
					onActivate = reset,
				}),
			}),
		})
	end
	local function tilePath(id: number): string
		return `/Match3/Page/board/tiles/tile{id}`
	end

	return {
		title = "Match-3",
		screen = Match3,
		pendingImage = PENDING,
		rows = ROWS,
		cols = COLS,
		kindAt = function(r: number, c: number): string
			local tile = board[r][c]
			return if tile ~= nil then tile.kind else ""
		end,
		boardSnapshot = function(): { string }
			local out = {}
			for r = 1, ROWS do
				for c = 1, COLS do
					local tile = board[r][c]
					table.insert(out, if tile ~= nil then tile.kind else "")
				end
			end
			return out
		end,
		score = function(): number
			return score:peek()
		end,
		moves = function(): number
			return moves:peek()
		end,
		hintText = function(): string
			return hint:peek()
		end,
		artStatusText = function(): string
			return artStatus:peek()
		end,
		hasLegalMove = hasLegalMove,
		findMatches = findMatches,
		reset = reset,
		deliverArt = deliverArt,
		tileIdAt = function(r: number, c: number): number?
			local tile = board[r][c]
			return if tile ~= nil then tile.id else nil
		end,
		tileIds = function(): { number }
			local out: { number } = {}
			for r = 1, ROWS do
				for c = 1, COLS do
					local tile = board[r][c]
					if tile ~= nil then
						table.insert(out, tile.id)
					end
				end
			end
			return out
		end,
		tilePath = tilePath,
		phase = function(): string
			return phase
		end,
		phaseLog = function(): { string }
			return table.clone(phaseLog)
		end,
		isResolving = function(): boolean
			return resolving:peek()
		end,
		tickHookActive = function(): boolean
			return unsubTick ~= nil
		end,
		cellPath = function(r: number, c: number): string
			local tile = board[r][c]
			return if tile ~= nil then `{tilePath(tile.id)}/hit` else "/Match3/Page/board/tiles/none/hit"
		end,
		imagePath = function(r: number, c: number): string
			local tile = board[r][c]
			return if tile ~= nil then `{tilePath(tile.id)}/img` else "/Match3/Page/board/tiles/none/img"
		end,
		hintPath = "/Match3/Page/Hint",
		artStatusPath = "/Match3/Page/ArtStatus",
		reloadPath = "/Match3/Page/Art/Reload",
		deliverPath = "/Match3/Page/Art/Deliver",
		breakPath = "/Match3/Page/Art/Break",
		resetPath = "/Match3/Page/Reset",
		swap = function(r1: number, c1: number, r2: number, c2: number)
			if resolving:peek() then
				return
			end
			beginSwap(r1, c1, r2, c2)
		end,
		debugSetBoard = function(board2d: { { string } })
			for r = 1, ROWS do
				for c = 1, COLS do
					local tile = board[r][c]
					if tile ~= nil then
						tile.kind = board2d[r][c]
					end
				end
			end
			syncKinds()
		end,
		dispose = function()
			stopTicking()
		end,
	}
end
return {
	title = "Match-3",
	build = build,
}
