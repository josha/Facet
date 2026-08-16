--!strict
-- ============================================================================
-- Example 7 of the LuauUI tutorial: a match-3 board.
-- ============================================================================
--
-- WHAT THIS TEACHES
--   * async images   — every tile kind's picture is acquired through a resource
--                      provider that models the ready / pending / FAILED states a
--                      real texture load has. The three states are on screen and
--                      the failed one is recoverable, because "it is still
--                      loading" and "it will never load" look identical to a
--                      player unless you say which one it is
--   * adaptive layout — the board is ONE `UI.Grid` sized from the theme's own
--                      metrics, so it lays out sensibly on any screen without the
--                      example measuring anything or naming a device
--   * deterministic simulation — matches clear, gravity falls and the board
--                      refills from a SEEDED sequence, so a test can replay a
--                      swap and get the same board every time
--   * multi-input    — a tile is a picture with a transparent button over it, so
--                      a tap, a click, Return on the focused tile and a gamepad
--                      "A" all select it; the Grid gives the board its 2D
--                      navigation for free
--
-- WHAT THE PLAYER SEES
--   A title, a one-line instruction that changes as they play, score and move
--   counters, the board, an artwork row that reports and drives the image
--   states, and a "New board" button. Tapping a tile selects it; tapping an
--   ADJACENT tile swaps them if that makes a run of three, and says why not if it
--   does not. The opening board is generated with no run already on it and with
--   at least one legal move available.
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

local function build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI
	local pres = deps.presenter
	local seed = DEFAULT_SEED

	local gameScope = core:scope("example-07-match3")
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

	local score = reg(core:signal(0))
	local moves = reg(core:signal(0))
	local message = reg(core:signal(""))

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

	-- gravity: existing tiles fall to the bottom of their column, new tiles enter
	-- from the top drawn from the seeded sequence (column by column, bottom to
	-- top — a fixed order so replays match).
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

	-- resolve(scoring) -> how many tiles cleared in total, chains included
	local function resolve(scoring: boolean): number
		local cleared = 0
		while true do
			local matched = findMatches()
			if next(matched) == nil then
				break
			end
			for key in matched do
				cleared += 1
				local rs, cs = key:match("(%d+),(%d+)")
				grid[tonumber(rs) :: number][tonumber(cs) :: number] = nil :: any
			end
			collapse()
		end
		if scoring and cleared > 0 then
			score:set(score:get() + cleared)
		end
		return cleared
	end

	-- is there ANY adjacent pair whose swap makes a run? A board with no legal
	-- move is a dead end the player cannot see, so it is checked rather than hoped.
	local function hasLegalMove(): boolean
		local function trySwap(r1: number, c1: number, r2: number, c2: number): boolean
			grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1]
			local any = next(findMatches()) ~= nil
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

	-- THE OPENING BOARD IS NOT ALREADY WON, AND NOT ALREADY STUCK
	-- (example-quality-pass). The board used to be filled cell by cell and shown
	-- as-is, so a seed could open on a run the player never made — the game
	-- scoring itself before the first tap — or on a board with no legal move at
	-- all. `resolve(false)` clears any accidental opening run WITHOUT scoring it,
	-- and the loop re-deals until a move exists. Bounded, so a pathological seed
	-- cannot hang the mount.
	local function deal()
		for _ = 1, 64 do
			resolve(false)
			if hasLegalMove() then
				return
			end
			for r = 1, ROWS do
				for c = 1, COLS do
					grid[r][c] = nextKind()
				end
			end
		end
	end
	deal()
	syncAll()

	-- ---- async images: one provider handle per tile kind --------------------
	-- Generous concurrency so every kind is in the active window at once.
	local provider = LuauUI.newResourceProvider(core, { maxConcurrent = 8 })
	local kindHandle: { [string]: any } = {}
	for _, kind in KINDS do
		kindHandle[kind] = provider.acquire(gameScope, `img/{kind}`)
	end
	gameScope:own(function()
		-- the handles are scope-owned already; this keeps the provider's own
		-- bookkeeping from outliving the example
		for _, handle in kindHandle do
			handle.release()
		end
	end)
	local PENDING = assets.pending

	-- Drain whatever the provider currently has in flight, answering each request
	-- with that kind's real asset. THIS IS THE TRANSPORT — in a real client it
	-- would be the engine's texture pipeline; here the example plays that part so
	-- the lesson is deterministic and has no timers in it.
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

	-- delivered once at build, so the board is playable from the first frame
	deliverArt()

	-- RE-REQUEST WITHOUT DROPPING THE KEY TO ZERO HANDLES. The provider owns one
	-- state/value/error signal set per key and DISPOSES them when the last handle
	-- releases; a fresh acquire then builds new ones. So releasing before
	-- acquiring silently swaps the signals a mounted memo is subscribed to, and
	-- every tile goes on painting the last art forever while the provider happily
	-- re-fetches. Acquire FIRST (refcount 2), then release the old handle: the
	-- entry never hits zero, the signals survive, and the mounted board sees the
	-- state go back to pending.
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
			-- nothing in flight: put one back in flight, then fail it
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

	-- ---- board blueprint ----------------------------------------------------
	local selected = reg(core:signal(nil :: { number }?))
	local activateCell: (r: number, c: number) -> () -- forward-declared (below)
	local cells = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local rr, cc = r, c
			-- the tile's image: the resolved asset for its current kind, or the
			-- pending placeholder until that kind's image arrives.
			-- THE PLACEHOLDER FOLLOWS THE STATE, NOT THE VALUE. The provider keeps
			-- the last-known value across a re-request (deliberately: it avoids a
			-- flicker when a key is refetched), so a tile that keyed on `value ~= nil`
			-- would go on showing stale art while its state read "pending", and a
			-- FAILED key would look identical to a ready one. Reading the state is
			-- what makes the three states actually distinguishable on screen.
			local image = reg(core:memo(function(use)
				local kind = use(kindSig[rr][cc])
				local handle = kindHandle[kind]
				if use(handle.state) ~= "ready" then
					return PENDING
				end
				local resolved = use(handle.value)
				return if resolved ~= nil then resolved else PENDING
			end))
			-- the kind's SHAPE is the primary cue, its colour the accelerator; the
			-- ASCII label is what is left if art is unavailable entirely, so five
			-- kinds stay distinguishable in every one of the three states.
			local tint = reg(core:memo(function(use)
				return { role = assets.match3Tints[use(kindSig[rr][cc])], blend = 1 }
			end))
			local fallbackLabel = reg(core:memo(function(use)
				local kind = use(kindSig[rr][cc])
				local ready = use(kindHandle[kind].state) == "ready"
				return if ready then "" else assets.match3Tiles[kind].label
			end))
			local isSelected = reg(core:memo(function(use)
				local sel = use(selected)
				return sel ~= nil and sel[1] == rr and sel[2] == cc
			end))
			cells[#cells + 1] = UI.ZStack({
				id = `cell{r}_{c}`,
				width = CELL,
				height = CELL,
				children = {
					UI.Image({
						id = "img",
						image = image,
						tint = tint,
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
					}),
					-- the hit target: focusable + tappable, fills the tile; its
					-- `selected` prop reflects the current selection, and its label
					-- is the fallback symbol while the picture is not there. Its
					-- node onActivate carries the APP SEMANTICS (select / swap
					-- adjacency) — the presenter dispatches Activate (tap, or A on
					-- the focused tile) here with no consumer routing (ADR-0013).
					UI.Button({
						id = "hit",
						label = fallbackLabel,
						surface = "plain",
						selected = isSelected,
						textSize = "control",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
						onActivate = function()
							activateCell(rr, cc)
						end,
					}),
				},
			})
		end
	end
	local board = UI.Grid({
		id = "board",
		columns = COLS,
		itemSizing = "uniform",
		gap = "xs",
		children = cells,
	})

	-- ---- select-then-swap ---------------------------------------------------
	-- swap two tiles; keep the swap only if it forms a match (classic match-3),
	-- otherwise revert AND SAY SO. NOTE: the tiles change instantly here. Sliding
	-- them across cells would animate a LAYOUT position over time, which is a
	-- separate expansion gate, so it is intentionally not built.
	local function swapCells(r1: number, c1: number, r2: number, c2: number)
		grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1]
		if next(findMatches()) == nil then
			grid[r1][c1], grid[r2][c2] = grid[r2][c2], grid[r1][c1] -- revert
			message:set("That swap makes no run of three. Try a different pair.")
		else
			moves:set(moves:get() + 1)
			local cleared = resolve(true)
			message:set(`Cleared {cleared} tiles.`)
			if not hasLegalMove() then
				-- a board with no move left is a dead end the player cannot see:
				-- re-deal rather than let them tap forever
				deal()
				message:set(`Cleared {cleared} tiles — no moves left, so the board was re-dealt.`)
			end
		end
		syncAll()
	end

	activateCell = function(r: number, c: number)
		local sel = selected:get()
		if sel == nil then
			selected:set({ r, c })
			message:set("")
		elseif sel[1] == r and sel[2] == c then
			selected:set(nil) -- tapping the selected tile puts it down
			message:set("")
		elseif math.abs(sel[1] - r) + math.abs(sel[2] - c) == 1 then
			swapCells(sel[1], sel[2], r, c) -- adjacent: swap
			selected:set(nil)
		else
			selected:set({ r, c }) -- non-adjacent: move the selection
			message:set("Tiles have to touch to swap. Pick a neighbour of the tile you chose.")
		end
	end

	local function reset()
		selected:set(nil)
		score:set(0)
		moves:set(0)
		rng = makeRng(seed)
		for r = 1, ROWS do
			for c = 1, COLS do
				grid[r][c] = nextKind()
			end
		end
		deal()
		syncAll()
		message:set("")
	end

	-- ---- the instruction line ----------------------------------------------
	local hint = reg(core:memo(function(use)
		local said = use(message)
		if said ~= "" then
			return said
		end
		if use(selected) == nil then
			return "Tap a tile, then tap a tile next to it to swap them. Three in a row clears."
		end
		return "Now tap a tile next to it — or tap the same tile again to put it down."
	end))
	local scoreText = reg(core:memo(function(use)
		return `Score {use(score)}`
	end))
	local movesText = reg(core:memo(function(use)
		return `{use(moves)} swaps`
	end))

	local screen = UI.Screen({
		id = "Match3",
		surface = "base",
		padding = "m",
		children = {
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Title", text = "LuauUI Match-3", textSize = "title" }),
					UI.Text({ id = "Hint", text = hint, textSize = "body", role = "secondary" }),
					-- ...AND THE SCORE ROW WRAPS, for the same reason the artwork
					-- controls below do. `numeral` + `label` at the Largest text
					-- preference measure 256+122 = 378px of a 328px phone row, and a
					-- row that cannot wrap paints `0 swaps` off the right screen edge
					-- (measured 2026-08-15: off x by 43px at +14, 82px at 320x640).
					-- Neither figure is decoration — the move count is the thing the
					-- player is playing against.
					UI.HStack({
						id = "Stats",
						wrap = true,
						gap = "m",
						align = "center",
						children = {
							UI.Text({ id = "Score", text = scoreText, textSize = "numeral" }),
							UI.Text({ id = "Moves", text = movesText, textSize = "label", role = "secondary" }),
						},
					}),
					board,
					UI.Text({ id = "ArtStatus", text = artStatus, textSize = "label", role = "secondary" }),
					-- THE ARTWORK CONTROLS WRAP (device report 2026-08-12, IMG_3690:
					-- "Fail a load" sliced by the right screen edge on a portrait
					-- phone). Three buttons carrying full sentences need ~580px of
					-- row; a 359px phone has 327. As an HStack the row simply painted
					-- past its own box — the solver said so on every phone viewport
					-- ("content overflows this hstack by 253px on the main axis") and
					-- nothing read it.
					--
					-- A Grid with `minColumnWidth = "intrinsic"` is the declarative
					-- form: the column count is derived from the widest child's own
					-- measured width under the ACTIVE theme's font, every solve. One
					-- column on a phone, one row on a desktop, and no viewport
					-- arithmetic to keep in sync — the lesson's "state the intent, do
					-- not compute the answer". The three buttons stay direct children,
					-- so every path this example publishes is unchanged.
					UI.Grid({
						id = "Art",
						minColumnWidth = "intrinsic",
						gap = "s",
						width = { type = "fill", weight = 1 },
						children = {
							UI.Button({ id = "Reload", label = "Re-request artwork", onActivate = reloadArt }),
							UI.Button({
								id = "Deliver",
								label = "Deliver artwork",
								onActivate = function()
									local n = deliverArt()
									message:set(
										if n > 0
											then `Delivered {n} tile pictures.`
											else "Nothing was waiting to be delivered."
									)
								end,
							}),
							UI.Button({ id = "Break", label = "Fail a load", onActivate = failArt }),
						},
					}),
					UI.Button({ id = "Reset", label = "New board", onActivate = reset }),
				},
			}),
		},
	})

	-- Presented with NO opts. Each tile's node onActivate handles select/swap, and
	-- the presenter derives 2D grid navigation from the board Grid automatically
	-- (ADR-0013 layout-derived groups): D-pad crosses the board and A activates,
	-- and the Grid's boundary rows link into the artwork row and the New-board
	-- button so nothing below the board is unreachable.
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
		score = function(): number
			return score:get()
		end,
		moves = function(): number
			return moves:get()
		end,
		hintText = function(): string
			return hint:get()
		end,
		artStatusText = function(): string
			return artStatus:get()
		end,
		hasLegalMove = hasLegalMove,
		findMatches = findMatches,
		reset = reset,
		deliverArt = deliverArt,
		cellPath = function(r: number, c: number): string
			return `/Match3/Page/board/cell{r}_{c}/hit`
		end,
		imagePath = function(r: number, c: number): string
			return `/Match3/Page/board/cell{r}_{c}/img`
		end,
		hintPath = "/Match3/Page/Hint",
		artStatusPath = "/Match3/Page/ArtStatus",
		reloadPath = "/Match3/Page/Art/Reload",
		deliverPath = "/Match3/Page/Art/Deliver",
		breakPath = "/Match3/Page/Art/Break",
		resetPath = "/Match3/Page/Reset",
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
