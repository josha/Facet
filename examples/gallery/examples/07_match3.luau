--!strict
-- ============================================================================
-- Example 7 of the Facet tutorial: a match-3 board that MOVES.
-- ============================================================================
--
-- WHAT THIS TEACHES
--   * stable identity  — the board is a set of TILES, each with an `id` handed
--                      out once and never reused, rendered through a keyed
--                      `UI.ForEach`. A swap is the same two tiles changing
--                      places, not two pictures changing inside two stationary
--                      boxes, and the framework is what keeps a moved tile's
--                      mounted node, scopes and state
--   * motion           — the board's `animation` paints every tile whose box
--                      changed travelling from where it was to where it is. The
--                      LAYOUT lands instantly and exactly, so hit-testing and
--                      focus never chase a moving pixel, and the board stays
--                      honest while it looks alive
--   * a clock, not a timer — the resolve sequence (mark, remove, drop, refill,
--                      cascade) is a state machine on `presenter.onTick`, the
--                      one sanctioned frame source outside the motion clock. No
--                      `task.wait`, no second `RunService` connection, and a
--                      headless test drives every intermediate frame with a
--                      scripted `dt`
--   * async images     — every tile kind's picture is acquired through a
--                      resource provider that models the ready / pending /
--                      FAILED states a real texture load has. The three states
--                      are on screen and the failed one is recoverable, because
--                      "it is still loading" and "it will never load" look
--                      identical to a player unless you say which one it is
--   * deterministic simulation — matches clear, gravity falls and the board
--                      refills from a SEEDED sequence, so a test can replay a
--                      swap and get the same board every time
--   * multi-input      — a tile is a picture with a transparent button over it,
--                      so a tap, a click, Return on the focused tile and a
--                      gamepad "A" all select it
--
-- WHAT THE PLAYER SEES
--   A title, a one-line instruction that changes as they play, score and move
--   counters, the board, an artwork row that reports and drives the image
--   states, and a "New board" button. Tapping a tile selects it; tapping an
--   ADJACENT tile slides the two together, keeps the swap if it made a run and
--   slides them back if it did not. A run marks, clears, drops the survivors and
--   refills from the top, cascading until nothing is left to clear — and the
--   board says so rather than swallowing taps while it settles. The opening
--   board is generated with no run already on it and with at least one legal
--   move available.
--
-- REDUCED MOTION IS NOT THIS FILE'S BUSINESS, and the absence is deliberate:
-- there is no `reducedMotion` branch anywhere below. Automatic layout animation and the
-- structural transitions both ride the motion authority, whose own contract
-- places instantly and fires the same events on the same frame when a player
-- asks for less motion. Ordering, feedback, scoring and the final board come
-- from the state machine, which is driven by the clock rather than by the
-- animation — so the two runs agree by construction instead of by a second code
-- path that has to be kept agreeing.
--
-- Runs headless against the FakeTarget: no engine calls.
--
-- deps used: presenter (see 01's header for the shared module shape).

local assets = require("./assets")

local ROWS = 6
local COLS = 6
local KINDS = { "a", "b", "c", "d", "e" }
local DEFAULT_SEED = 20260720

-- A tile is a tap target first and a picture second, so it is sized from the
-- theme's own large-control height rather than a pixel count this file guessed.
-- A denser package makes the board denser; a chunky touch package makes it
-- chunkier. THE EXAMPLE NAMES NO DEVICE.
local CELL: any = { type = "fixed", px = "controlSizes.large.height" }
-- ...and the board is exactly six of those across and six down. `content rows`
-- is the framework's own way to say "N rows of this metric", so the
-- board tracks the same theme metric its tiles do with no arithmetic here.
local BOARD_WIDTH: any = { type = "content", rows = COLS, of = "controlSizes.large.height" }
local BOARD_HEIGHT: any = { type = "content", rows = ROWS, of = "controlSizes.large.height" }

-- `object` is the framework's motion class for a thing that moves as itself (a
-- tile), against `container` for a box that grows. A class is a NAME here as it
-- is everywhere else — the example asks for a feel, it does not tune a spring.
local TILE_MOTION = "object"

--[[ THE RESOLUTION PHASES, in seconds of PRESENTER CLOCK time.

	These are the example's own pacing decision and the only numbers in this file
	that are about time. They are spent by `presenter.onTick`, so the headless
	suite advances them with a scripted `dt` and every frame in between is a
	deterministic assertion rather than a race.

	The sum after a removal (remove + gravity + refill + land = 0.86 s) is
	deliberately longer than the framework's flat 500 ms exit cap, so a matched
	tile has always finished retiring by the time the cascade comes back round. ]]
local PHASE_SECONDS: { [string]: number } = {
	swap = 0.2,
	revert = 0.2,
	mark = 0.16,
	remove = 0.24,
	gravity = 0.26,
	refill = 0.1,
	land = 0.26,
}

-- A tiny deterministic PRNG (a classic Lehmer/park-miller generator). Seeding it
-- identically replays the exact same refill sequence, which is what lets a test
-- predict the board after a swap.
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

-- ---- pure board rules, over a plain grid of kinds -------------------------
-- These are the rules the game plays by, and they are written against a plain
-- `{ { kind } }` so the DEALER and the LIVE BOARD can both ask them. Nothing
-- here knows about tiles, identity or motion.

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

-- is there ANY adjacent pair whose swap makes a run? A board with no legal
-- move is a dead end the player cannot see, so it is checked rather than hoped.
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

local function build(Facet: any, core: any, deps: any)
	local UI = Facet.View
	local pres = deps.presenter
	local seed = DEFAULT_SEED
	-- The game model owns phase timing and resources across row lifetimes.
	local gameScope = core:scope("example-07-match3")
	local function reg(readable: any): any
		gameScope:own(readable)
		return readable
	end
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
	local items = reg(core:signal({} :: { { id: number } }))
	local function publish()
		local out: { { id: number } } = {}
		for r = 1, ROWS do
			for c = 1, COLS do
				local tile = board[r][c]
				if tile ~= nil then
					table.insert(out, { id = tile.id })
				end
			end
		end
		items:set(out)
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
	local score = reg(core:signal(0))
	local moves = reg(core:signal(0))
	local message = reg(core:signal(""))
	local resolving = reg(core:signal(false))
	local selected = reg(core:signal(nil :: { number }?))
	local provider = Facet.newResourceProvider(core, { maxConcurrent = 8 })
	local kindHandle: { [string]: any } = {}
	for _, kind in KINDS do
		kindHandle[kind] = provider.acquire(gameScope, `img/{kind}`)
	end
	gameScope:own(function()
		for _, handle in kindHandle do
			handle.release()
		end
	end)
	local PENDING = assets.pending
	local function deliverArt(): number
		local delivered = 0
		for _, request in provider.pendingRequests() do
			local kind = string.match(request.key, "^img/(.+)$")
			local art = if kind ~= nil then assets.match3Tiles[kind] else nil
			if art ~= nil and provider.complete(request.key, request.generation, art.image) == "applied" then
				delivered += 1
			end
		end
		return delivered
	end
	deliverArt()
	local function requestArt(kind: string)
		local key = `img/{kind}`
		provider.invalidate(key)
		local fresh = provider.acquire(gameScope, key)
		kindHandle[kind].release()
		kindHandle[kind] = fresh
	end
	local function reloadArt()
		for _, kind in KINDS do
			requestArt(kind)
		end
		message:set("Artwork re-requested — the tiles show the loading placeholder until it arrives.")
	end
	local function failArt()
		local first = provider.pendingRequests()[1]
		if first == nil then
			requestArt("a")
			first = provider.pendingRequests()[1]
		end
		if first ~= nil then
			provider.fail(first.key, first.generation, "the transport dropped it")
			message:set('One tile kind failed to load. Press "Re-request artwork", then "Deliver artwork".')
		end
	end
	local artStatus = reg(core:memo(function(use)
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
	end))
	local activateTile: (tile: Tile) -> ()
	local beginSwap: (number, number, number, number) -> ()
	local tilesById: { [number]: Tile } = {}
	local TileView = Facet.component(function(ui, props)
		local tile = tilesById[props.item().id]
		local kind, setKind = ui.state(tile.kind)
		local position, setPosition = ui.state({
			row = if tile.spawnRow ~= nil then tile.spawnRow else tile.row,
			col = tile.col,
		})
		local marked, setMarked = ui.state(false)
		tile.setKind, tile.setPosition, tile.setMarked = setKind, setPosition, setMarked
		ui.own(function()
			tile.setKind, tile.setPosition, tile.setMarked = nil, nil, nil
		end)
		local selection, isResolving = ui.read(selected), ui.read(resolving)
		local images = {}
		for name, handle in kindHandle do
			images[name] = { state = ui.read(handle.state), value = ui.read(handle.value) }
		end
		local offsetX = ui.memo(function()
			return { scale = (position().col - 1) / COLS }
		end)
		local offsetY = ui.memo(function()
			return { scale = (position().row - 1) / ROWS }
		end)
		local image = ui.memo(function()
			local handle = images[kind()]
			if handle.state() ~= "ready" then
				return PENDING
			end
			local resolved = handle.value()
			return if resolved ~= nil then resolved else PENDING
		end)
		local tint = ui.memo(function()
			return { role = assets.match3Tints[kind()], blend = 1 }
		end)
		local fallbackLabel = ui.memo(function()
			local kind = kind()
			local ready = images[kind].state() == "ready"
			return if ready then "" else assets.match3Tiles[kind].label
		end)
		local picked = ui.memo(function()
			if marked() then
				return true
			end
			local sel = selection()
			local at = position()
			return sel ~= nil and sel[1] == at.row and sel[2] == at.col
		end)
		-- Tile hit targets need primitive selected/surface paint; the component
		-- still owns state and Facet owns focus, dragging and layout.
		return UI.ZStack({
			id = "cell",
			canvasGroup = true,
			width = CELL,
			height = CELL,
			anchor = "topLeft",
			offsetX = offsetX,
			offsetY = offsetY,
			UI.Image({
				id = "img",
				image = image,
				tint = tint,
				margin = "xs",
				width = UI.fill(),
				height = UI.fill(),
			}),
			UI.dropTarget(
				UI.draggable(
					Facet.UI.Button({
						id = "hit",
						label = fallbackLabel,
						surface = "plain",
						selected = picked,
						textSize = "control",
						width = UI.fill(),
						height = UI.fill(),
						onActivate = function()
							activateTile(tile)
						end,
					}),
					{
						payload = { kind = "match3", tile = tile },
						enabled = ui.memo(function()
							return not isResolving()
						end),
						proxy = function()
							return UI.Image({ image = image, tint = tint, width = UI.fill(), height = UI.fill() })
						end,
					}
				),
				{
					accepts = function(payload)
						local source = type(payload) == "table" and payload.kind == "match3" and payload.tile
						return source ~= nil
							and source ~= false
							and not resolving:get()
							and board[source.row][source.col] == source
							and math.abs(source.row - tile.row) + math.abs(source.col - tile.col) == 1,
							"Tiles must be neighbors"
					end,
					onDrop = function(payload)
						selected:set(nil)
						message:set("")
						beginSwap(payload.tile.row, payload.tile.col, tile.row, tile.col)
					end,
				}
			),
		})
	end)
	local boardView = UI.Anchor({
		id = "board",
		animation = { layout = TILE_MOTION },
		overflow = "clip",
		width = BOARD_WIDTH,
		height = BOARD_HEIGHT,
		UI.ForEach({
			id = "tiles",
			items = items,
			key = "id",
			row = function(item)
				return TileView({ item = item })
			end,
			transition = { enter = "materialize", exit = "fade", class = TILE_MOTION },
		}),
	})
	local function dealBoard()
		local grid = dealKinds()
		tilesById = {}
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
	gameScope:own(stopTicking)
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
			core:transaction(function()
				local a, b = tileAt(move[1], move[2]) :: Tile, tileAt(move[3], move[4]) :: Tile
				a.row, a.col, b.row, b.col = b.row, b.col, a.row, a.col
				board[a.row][a.col], board[b.row][b.col] = a, b
				syncPositions()
				publish()
			end)
		end,
		revert = function()
			local move = pendingSwap :: { number }
			core:transaction(function()
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
					cleared += 1
				end
			end
			clearedThisRun += cleared
			if cleared > 0 then
				score:set(score:get() + cleared)
			end
			publish()
			phaseLog[#phaseLog] = `remove:{cleared}`
		end,
		gravity = function()
			core:transaction(function()
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
			core:transaction(function()
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
				moves:set(moves:get() + 1)
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
			unsubTick = pres.onTick(onFrame)
		end
		enterPhase("swap")
	end
	activateTile = function(tile: Tile)
		if resolving:get() then
			message:set("The board is still settling — wait for the tiles to land.")
			return
		end
		local r, c = tile.row, tile.col
		local sel = selected:get()
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
	local Match3 = Facet.component(function(ui)
		local messageNow = ui.read(message)
		local resolvingNow = ui.read(resolving)
		local selectedNow = ui.read(selected)
		local scoreNow = ui.read(score)
		local movesNow = ui.read(moves)
		hint = ui.memo(function()
			local said = messageNow()
			if said ~= "" then
				return said
			end
			if resolvingNow() then
				return "The board is settling — tiles are clearing, dropping and refilling."
			end
			if selectedNow() == nil then
				return "Drag a tile onto a neighbor, or select two neighboring tiles. Three in a row clears."
			end
			return "Now tap a tile next to it — or tap the same tile again to put it down."
		end)
		local scoreText = ui.memo(function()
			return `Score {scoreNow()}`
		end)
		local movesText = ui.memo(function()
			return `{movesNow()} swaps`
		end)
		return UI.Screen({
			id = "Match3",
			surface = "base",
			padding = "m",
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = UI.fill(),
				height = UI.fill(),
				UI.Text({ id = "Title", text = "Facet Match-3", textSize = "title" }),
				UI.Text({ id = "Hint", text = hint, textSize = "body", role = "secondary" }),
				UI.HStack({
					id = "Stats",
					wrap = true,
					gap = "m",
					align = "center",
					UI.Text({ id = "Score", text = scoreText, textSize = "numeral" }),
					UI.Text({ id = "Moves", text = movesText, textSize = "label", role = "secondary" }),
				}),
				boardView,
				UI.Text({ id = "ArtStatus", text = artStatus, textSize = "label", role = "secondary" }),
				UI.Grid({
					id = "Art",
					minColumnWidth = "intrinsic",
					gap = "s",
					width = UI.fill(),
					UI.Button({ id = "Reload", label = "Re-request artwork", onActivate = reloadArt }),
					UI.Button({
						id = "Deliver",
						label = "Deliver artwork",
						onActivate = function()
							local n = deliverArt()
							message:set(
								if n > 0 then `Delivered {n} tile pictures.` else "Nothing was waiting to be delivered."
							)
						end,
					}),
					UI.Button({ id = "Break", label = "Fail a load", onActivate = failArt }),
				}),
				UI.Button({ id = "Reset", label = "New board", onActivate = reset }),
			}),
		})
	end)
	local screen = Match3({})
	local function tilePath(id: number): string
		return `/Match3/Page/board/tiles/[{id}]/cell`
	end
	-- THE BOARD DECLARES ITS OWN 2D NAVIGATION: tiles are freely placed in an
	-- Anchor, so the layout cannot infer rows. Use the current board order.
	local function navigationGroups(): any
		local tiles: { string } = {}
		for r = 1, ROWS do
			for c = 1, COLS do
				local tile = board[r][c]
				if tile ~= nil then
					table.insert(tiles, `{tilePath(tile.id)}/hit`)
				end
			end
		end
		return {
			{
				name = "board",
				axis = "horizontal",
				entry = "nearest",
				columns = COLS,
				order = tiles,
				exit = { down = "art" },
			},
			{
				name = "art",
				axis = "horizontal",
				entry = "nearest",
				order = {
					"/Match3/Page/Art/Reload",
					"/Match3/Page/Art/Deliver",
					"/Match3/Page/Art/Break",
				},
				exit = { up = "board", down = "reset" },
			},
			{
				name = "reset",
				axis = "vertical",
				entry = "nearest",
				order = { "/Match3/Page/Reset" },
				exit = { up = "art" },
			},
		}
	end
	local handle = pres.present(screen, { navigationGroups = navigationGroups })
	return {
		title = "Match-3",
		screen = screen,
		handle = handle,
		provider = provider,
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
			return score:get()
		end,
		moves = function(): number
			return moves:get()
		end,
		hintText = function(): string
			return hint()
		end,
		artStatusText = function(): string
			return artStatus:get()
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
			return resolving:get()
		end,
		tickHookActive = function(): boolean
			return unsubTick ~= nil
		end,
		cellPath = function(r: number, c: number): string
			local tile = board[r][c]
			return if tile ~= nil then `{tilePath(tile.id)}/hit` else "/Match3/Page/board/tiles/[none]/cell/hit"
		end,
		imagePath = function(r: number, c: number): string
			local tile = board[r][c]
			return if tile ~= nil then `{tilePath(tile.id)}/img` else "/Match3/Page/board/tiles/[none]/cell/img"
		end,
		hintPath = "/Match3/Page/Hint",
		artStatusPath = "/Match3/Page/ArtStatus",
		reloadPath = "/Match3/Page/Art/Reload",
		deliverPath = "/Match3/Page/Art/Deliver",
		breakPath = "/Match3/Page/Art/Break",
		resetPath = "/Match3/Page/Reset",
		swap = function(r1: number, c1: number, r2: number, c2: number)
			if resolving:get() then
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
			pres.dismiss(handle)
			gameScope:dispose()
		end,
	}
end
return {
	title = "Match-3",
	build = build,
}
