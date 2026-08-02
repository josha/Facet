--!strict
-- Gallery example 8 — a match-3 game: the write-once-run-everywhere showcase.
--
-- What this example teaches:
--   * Adaptive layout: the tiles size themselves from the environment's size
--     class (phone / tablet / desktop), so the SAME tree lays out sensibly on
--     any screen without being rebuilt.
--   * Async images: each tile kind's picture is acquired through a resource
--     provider that models the ready / pending states a real texture load has.
--     Nothing assumes an image is present the instant a tile appears.
--   * Multi-input: a tile is an image with a transparent button on top, so a
--     touch tap and a gamepad "A" on the focused tile both select it; a grid of
--     navigation groups lets a gamepad move around the board.
--   * Deterministic simulation: matches clear and the board refills from a
--     seeded sequence, so a test can replay a swap and get the same board every
--     time.
--
-- Presentation stays simple: tiles change their image and size via plain
-- property/opacity changes. Sliding a tile smoothly from one cell to another is
-- layout-space animation, which is a Phase 5 feature — see the note in swap().
--
-- Runs headless against the FakeTarget: the provider is drained by the caller
-- (a test, or a real client's texture transport), never by this file.

local assets = require("./assets")

local ROWS = 6
local COLS = 6
local KINDS = { "a", "b", "c", "d", "e" }
local DEFAULT_SEED = 20260720

-- A tiny deterministic PRNG (a classic Lehmer/park-miller generator). Seeding
-- it identically replays the exact same refill sequence, which is what lets a
-- test predict the board after a swap.
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

local function build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI
	local pres = deps.presenter
	local env = deps.env
	local seed = DEFAULT_SEED

	local gameScope = core:scope("example-08-match3")
	local function reg(readable: any): any
		gameScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	local rng = makeRng(seed)
	local function nextKind(): string
		return KINDS[math.floor(rng() * #KINDS) + 1]
	end

	-- grid[r][c] is the authoritative board; kindSig mirrors it for rendering so
	-- only the cells that actually changed repaint.
	local grid: { { string } } = {}
	local kindSig: { { any } } = {}
	for r = 1, ROWS do
		grid[r] = {}
		kindSig[r] = {}
		for c = 1, COLS do
			grid[r][c] = nextKind()
			kindSig[r][c] = reg(core:signal(grid[r][c]))
		end
	end
	local function syncAll()
		for r = 1, ROWS do
			for c = 1, COLS do
				kindSig[r][c]:set(grid[r][c])
			end
		end
	end

	-- ---- match / collapse / refill (pure board logic) -----------------------
	local function findMatches(): { [string]: boolean }
		local matched: { [string]: boolean } = {}
		for r = 1, ROWS do
			local run = 1
			for c = 2, COLS + 1 do
				if c <= COLS and grid[r][c] == grid[r][c - 1] then
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
				if r <= ROWS and grid[r][c] == grid[r - 1][c] then
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

	-- gravity: existing tiles fall to the bottom of their column, new tiles
	-- enter from the top drawn from the seeded sequence (column by column,
	-- bottom to top — a fixed order so replays match).
	local function collapse()
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

	local function resolve()
		while true do
			local matched = findMatches()
			if next(matched) == nil then
				break
			end
			for key in matched do
				local rs, cs = key:match("(%d+),(%d+)")
				grid[tonumber(rs) :: number][tonumber(cs) :: number] = nil :: any
			end
			collapse()
		end
	end

	-- swap two tiles; keep the swap only if it forms a match (classic match-3),
	-- otherwise revert. NOTE: the tiles change instantly here. Sliding them
	-- across cells would animate a LAYOUT position over time — layout-space
	-- animation is a Phase 5 expansion gate, so it is intentionally not built.
	local function swapCells(r1: number, c1: number, r2: number, c2: number)
		grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1]
		if next(findMatches()) == nil then
			grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1] -- revert
		else
			resolve()
		end
		syncAll()
	end

	-- ---- async images: one provider handle per tile kind --------------------
	-- generous concurrency so every kind is in the active window at once; the
	-- caller drains them (tests call provider.complete; a client's transport
	-- would map each key to the id in assets.match3Tiles).
	local provider = LuauUI.newResourceProvider(core, { maxConcurrent = 8 })
	local kindHandle: { [string]: any } = {}
	for _, kind in KINDS do
		kindHandle[kind] = provider.acquire(gameScope, `img/{kind}`)
	end
	local PENDING = assets.pending

	-- adaptive tile size: a bound Dim that tracks the environment size class.
	-- Changing it re-solves layout (a size change), never a remount.
	local cellDim = reg(core:memo(function(use)
		local sizeClass = use(env:get("sizeClass"))
		local px = if sizeClass == "compact" then 40 elseif sizeClass == "regular" then 56 else 72
		return { type = "fixed", px = px }
	end))

	-- ---- board blueprint ----------------------------------------------------
	local selected = reg(core:signal(nil :: { number }?))
	local activateCell: (r: number, c: number) -> () -- forward-declared (below)
	local cellPathByRc: { [string]: string } = {}
	local boardRows = {}
	for r = 1, ROWS do
		local rowId = "mrow" .. r
		local cells = {}
		for c = 1, COLS do
			local rr, cc = r, c
			-- the tile's image: the resolved asset for its current kind, or the
			-- pending placeholder until that kind's image finishes loading.
			local image = reg(core:memo(function(use)
				local kind = use(kindSig[rr][cc])
				local resolved = use(kindHandle[kind].value)
				return if resolved ~= nil then resolved else PENDING
			end))
			local isSelected = reg(core:memo(function(use)
				local sel = use(selected)
				return sel ~= nil and sel[1] == rr and sel[2] == cc
			end))
			local cellPath = `/Match3/board/{rowId}/cell{c}`
			cellPathByRc[rr .. "," .. cc] = cellPath
			cells[c] = UI.ZStack({
				id = "cell" .. c,
				width = cellDim,
				height = cellDim,
				children = {
					UI.Image({
						id = "img",
						image = image,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
					}),
					-- the transparent hit target: focusable + tappable, fills the
					-- tile; its `selected` prop reflects the current selection. Its
					-- node onActivate carries the APP SEMANTICS (select / swap
					-- adjacency) — the presenter dispatches Activate (tap, or A on
					-- the focused tile) here with no consumer routing (ADR-0013).
					UI.Button({
						id = "hit",
						label = "",
						selected = isSelected,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						onActivate = function()
							activateCell(rr, cc)
						end,
					}),
				},
			})
		end
		boardRows[r] = UI.HStack({ id = rowId, gap = 4, children = cells })
	end
	local board = UI.VStack({ id = "board", gap = 4, children = boardRows })

	local screen = UI.Screen({
		id = "Match3",
		padding = 16,
		gap = 12,
		children = {
			UI.Text({ id = "Title", text = "LuauUI Match-3", textSize = 28 }),
			board,
		},
	})

	-- ---- select-then-swap ---------------------------------------------------
	activateCell = function(r: number, c: number)
		local sel = selected:get()
		if sel == nil then
			selected:set({ r, c })
		elseif math.abs(sel[1] - r) + math.abs(sel[2] - c) == 1 then
			swapCells(sel[1], sel[2], r, c) -- adjacent: swap
			selected:set(nil)
		else
			selected:set({ r, c }) -- non-adjacent: move the selection
		end
	end

	-- Presented with NO opts. Each tile's node onActivate handles select/swap,
	-- and the presenter derives 2D grid navigation from the board's HStack rows
	-- automatically (ADR-0013 layout-derived groups): D-pad crosses the grid
	-- (Left/Right within a row, Up/Down keeping the column) and A activates —
	-- no grouped-scope swap and no custom navigation context needed.
	local handle = pres.present(screen)

	-- ---- public / test API --------------------------------------------------
	return {
		title = "Match-3",
		screen = screen,
		handle = handle,
		provider = provider,
		pendingImage = PENDING,
		rows = ROWS,
		cols = COLS,

		kindAt = function(r: number, c: number): string
			return grid[r][c]
		end,
		boardSnapshot = function(): { string }
			local out = {}
			for r = 1, ROWS do
				for c = 1, COLS do
					table.insert(out, grid[r][c])
				end
			end
			return out
		end,
		cellPath = function(r: number, c: number): string
			return cellPathByRc[r .. "," .. c] .. "/hit"
		end,
		imagePath = function(r: number, c: number): string
			return cellPathByRc[r .. "," .. c] .. "/img"
		end,
		swap = swapCells,
		-- test hook: install an exact board (no auto-resolve) so a swap scenario
		-- is reproducible.
		debugSetBoard = function(board2d: { { string } })
			for r = 1, ROWS do
				for c = 1, COLS do
					grid[r][c] = board2d[r][c]
				end
			end
			syncAll()
		end,

		dispose = function()
			pres.dismiss(handle)
			gameScope:dispose()
		end,
	}
end

return {
	title = "Match-3",
	build = build,
}
