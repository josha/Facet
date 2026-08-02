--!strict
-- Gallery example 7 — a Scrabble-style tile game.
--
-- What this example teaches:
--   * Composition at scale: a 5x5 board built as a stack of rows, plus a rack
--     of letter tiles, all from the same handful of primitives.
--   * Selection state: tap a rack tile to SELECT it, then tap a board cell to
--     PLACE it. Selection is one signal; the tiles and cells are pure bindings
--     over it. (This is deliberately NOT drag-and-drop — pick-and-place by
--     dragging is a Phase 5 pattern; select-then-place needs nothing new.)
--   * Derived state: the score is a memo over the placed tiles, so it can never
--     drift out of sync with the board.
--
-- Interaction rides the presenter's normal Activate path, so a touch tap, a
-- mouse click, and a gamepad "A" on the focused tile all place a tile the same
-- way. Runs headless against the FakeTarget.

local BOARD_ROWS = 5
local BOARD_COLS = 5

-- The starting rack: { letter, Scrabble point value }.
local RACK = {
	{ "C", 3 },
	{ "A", 1 },
	{ "T", 1 },
	{ "E", 1 },
	{ "R", 1 },
	{ "S", 1 },
	{ "D", 2 },
}

local function cellKey(r: number, c: number): string
	return r .. "," .. c
end

local function build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI
	local pres = deps.presenter

	local gameScope = core:scope("example-07-tile-game")
	local function reg(readable: any): any
		gameScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	-- selected rack slot index (nil = nothing selected)
	local selected = reg(core:signal(nil :: number?))
	-- which rack slots have been played onto the board
	local placedSlots = reg(core:signal({} :: { [number]: boolean }))
	-- board cell key -> { letter, value }
	local placements = reg(core:signal({} :: { [string]: any }))

	-- derived score: sum of the values of every placed tile
	local score = reg(core:memo(function(use)
		local cells = use(placements)
		local total = 0
		for _, p in cells do
			total += p.value
		end
		return total
	end))

	-- ---- commands -----------------------------------------------------------
	local function selectSlot(slot: number)
		if placedSlots:get()[slot] == true then
			return -- already played onto the board
		end
		selected:set(slot)
	end

	local function placeAt(r: number, c: number)
		local slot = selected:get()
		if slot == nil then
			return
		end
		local key = cellKey(r, c)
		if placements:get()[key] ~= nil then
			return -- cell already occupied
		end
		local tile = RACK[slot]
		local nextPlacements = table.clone(placements:get())
		nextPlacements[key] = { letter = tile[1], value = tile[2] }
		placements:set(nextPlacements)
		local nextPlaced = table.clone(placedSlots:get())
		nextPlaced[slot] = true
		placedSlots:set(nextPlaced)
		selected:set(nil)
	end

	-- ---- board: 5 rows of 5 cells; each cell shows its placed letter --------
	local boardRows = {}
	for r = 1, BOARD_ROWS do
		local cells = {}
		for c = 1, BOARD_COLS do
			local rr, cc = r, c
			local key = cellKey(r, c)
			local label = reg(core:memo(function(use)
				local p = use(placements)[key]
				return if p ~= nil then p.letter else ""
			end))
			cells[c] = UI.Button({
				id = "cell" .. c,
				label = label,
				width = { type = "fixed", px = 44 },
				height = { type = "fixed", px = 44 },
				-- APP SEMANTICS on the node: activating a board cell (tap, or
				-- Return/A on the focused cell) places the selected rack tile
				-- here. The presenter dispatches Activate with no consumer
				-- routing (ADR-0013); select-then-place is the app's own rule.
				onActivate = function()
					placeAt(rr, cc)
				end,
			})
		end
		boardRows[r] = UI.HStack({ id = "brow" .. r, gap = 4, children = cells })
	end
	local board = UI.VStack({ id = "board", gap = 4, children = boardRows })

	-- ---- rack: one button per starting tile; placed tiles go blank+disabled --
	local rackTiles = {}
	for i, tile in RACK do
		local slot = i
		local label = reg(core:memo(function(use)
			return if use(placedSlots)[slot] then "" else tile[1]
		end))
		local enabled = reg(core:memo(function(use)
			return not use(placedSlots)[slot]
		end))
		local isSelected = reg(core:memo(function(use)
			return use(selected) == slot
		end))
		rackTiles[i] = UI.Button({
			id = "rt" .. i,
			label = label,
			enabled = enabled,
			selected = isSelected,
			width = { type = "fixed", px = 40 },
			height = { type = "fixed", px = 48 },
			-- APP SEMANTICS: activating a rack tile selects that slot.
			onActivate = function()
				selectSlot(slot)
			end,
		})
	end
	local rack = UI.HStack({ id = "rack", gap = 6, children = rackTiles })

	local scoreText = reg(core:memo(function(use)
		return `Score: {use(score)}`
	end))

	local screen = UI.Screen({
		id = "TileGame",
		padding = 16,
		gap = 16,
		children = {
			UI.Text({ id = "Title", text = "LuauUI Tiles", textSize = 28 }),
			UI.Text({ id = "Score", text = scoreText, textSize = 18 }),
			board,
			rack,
		},
	})

	-- Presented with NO opts: each tile/cell carries its own Activate handler
	-- (above), and the presenter derives 2D grid navigation from the board's and
	-- rack's HStack rows automatically (ADR-0013 layout-derived groups) — so a
	-- gamepad D-pad crosses the grid and A places, with no consumer wiring.
	local handle = pres.present(screen)

	-- helper: the slot index of the i-th tile still on the rack
	local function nthAvailable(i: number): number?
		local seen = 0
		for slot = 1, #RACK do
			if not placedSlots:get()[slot] then
				seen += 1
				if seen == i then
					return slot
				end
			end
		end
		return nil
	end

	return {
		title = "Tile Game (Scrabble-style)",
		screen = screen,
		handle = handle,

		score = function(): number
			return score:get()
		end,
		placedAt = function(r: number, c: number): string?
			local p = placements:get()[cellKey(r, c)]
			return if p ~= nil then p.letter else nil
		end,
		rackCount = function(): number
			local n = 0
			for slot = 1, #RACK do
				if not placedSlots:get()[slot] then
					n += 1
				end
			end
			return n
		end,
		-- letter and value of the i-th tile currently on the rack
		rackTile = function(i: number): (string, number)
			local slot = nthAvailable(i) :: number
			local tile = RACK[slot]
			return tile[1], tile[2]
		end,
		rackPath = function(i: number): string
			return `/TileGame/rack/rt{nthAvailable(i)}`
		end,
		cellPath = function(r: number, c: number): string
			return `/TileGame/board/brow{r}/cell{c}`
		end,

		dispose = function()
			pres.dismiss(handle)
			gameScope:dispose()
		end,
	}
end

return {
	title = "Tile Game (Scrabble-style)",
	build = build,
}
