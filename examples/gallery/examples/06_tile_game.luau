--!strict
-- ============================================================================
-- Example 6 of the LuauUI tutorial: a Scrabble-style tile game.
-- ============================================================================
--
-- WHAT THIS TEACHES
--   * composition at scale — a 5x5 board is ONE `UI.Grid`, not a hand-rolled
--     stack of rows, and the grid gives the board its 2D focus navigation for
--     free (per-row groups linked by up/down exits, so a D-pad crosses it)
--   * selection state    — one signal holds "which rack slot is picked up"; the
--     rack tiles and board cells are pure bindings over it
--   * derived state      — score and progress are memos over the placements, so
--     they can never drift out of sync with the board
--   * REFUSAL IS FEEDBACK — every move the rules reject says WHY, on screen. A
--     rule that silently does nothing is indistinguishable from a broken button
--
-- WHAT THE PLAYER SEES
--   A title, a one-line instruction that changes as they play, a score and a
--   progress readout, the board, the rack, and a "Start over" button. Picking a
--   rack tile highlights it and the instruction becomes "now tap a square";
--   placing it scores the tile and blanks its rack slot. Tapping an occupied
--   square, or a square with nothing picked up, or an already-played rack slot,
--   each explain themselves in the message line instead of doing nothing.
--
-- Interaction rides the presenter's normal Activate path, so a touch tap, a
-- mouse click, Return on the focused control and a gamepad "A" all do the same
-- thing. Runs headless against the FakeTarget: no engine calls.
--
-- deps used: presenter (see 01's header for the shared module shape).

local BOARD_ROWS = 5
local BOARD_COLS = 5

-- The starting rack: { letter, Scrabble point value }. CONTENT, not style —
-- these are the game's own data and are deliberately literal.
local RACK = {
	{ "C", 3 },
	{ "A", 1 },
	{ "T", 1 },
	{ "E", 1 },
	{ "R", 1 },
	{ "S", 1 },
	{ "D", 2 },
}

-- A board square is a big tap target. `targetSizes.minimum` is the theme's own
-- touch floor, so the squares grow with a denser or a chunkier package instead
-- of being a pixel count guessed once on one device.
local CELL: any = { type = "fixed", px = "controlSizes.large.height" }

local function cellKey(r: number, c: number): string
	return r .. "," .. c
end

local function build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI
	local pres = deps.presenter

	local gameScope = core:scope("example-06-tile-game")
	local function reg(readable: any): any
		gameScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	-- selected rack slot index (nil = nothing picked up)
	local selected = reg(core:signal(nil :: number?))
	-- which rack slots have been played onto the board
	local placedSlots = reg(core:signal({} :: { [number]: boolean }))
	-- board cell key -> { letter, value }
	local placements = reg(core:signal({} :: { [string]: any }))
	-- the one-line explanation of the last refused move ("" = nothing to say).
	-- It is CLEARED by every successful move, so a stale complaint can never sit
	-- under a board the player has since changed.
	local message = reg(core:signal(""))

	-- derived score: sum of the values of every placed tile
	local score = reg(core:memo(function(use)
		local cells = use(placements)
		local total = 0
		for _, p in cells do
			total += p.value
		end
		return total
	end))

	local placedCount = reg(core:memo(function(use)
		local n = 0
		for _ in use(placedSlots) do
			n += 1
		end
		return n
	end))

	local finished = reg(core:memo(function(use)
		return use(placedCount) >= #RACK
	end))

	-- ---- commands -----------------------------------------------------------
	-- Each refusal names its own reason. That is the whole difference between
	-- "the button is broken" and "I understand the rule".
	local function selectSlot(slot: number)
		if placedSlots:get()[slot] == true then
			message:set("That tile is already on the board. Pick one that still has a letter.")
			return
		end
		selected:set(slot)
		message:set("")
	end

	local function placeAt(r: number, c: number)
		local slot = selected:get()
		if slot == nil then
			message:set("Pick a letter from your rack first, then tap a square.")
			return
		end
		local key = cellKey(r, c)
		if placements:get()[key] ~= nil then
			message:set(`Row {r}, column {c} already has a letter. Choose an empty square.`)
			return
		end
		local tile = RACK[slot]
		local nextPlacements = table.clone(placements:get())
		nextPlacements[key] = { letter = tile[1], value = tile[2] }
		placements:set(nextPlacements)
		local nextPlaced = table.clone(placedSlots:get())
		nextPlaced[slot] = true
		placedSlots:set(nextPlaced)
		selected:set(nil)
		message:set("")
	end

	-- DETERMINISTIC RESET. Everything the game can change is written back to the
	-- value it was constructed with — including the selection and the message, so
	-- a reset cannot leave a highlighted rack tile or a stale complaint behind.
	local function reset()
		selected:set(nil)
		placedSlots:set({})
		placements:set({})
		message:set("")
	end

	-- ---- the instruction line ----------------------------------------------
	-- ONE line that always says what to do next. It prefers the message (a
	-- refusal the player needs to read) and otherwise describes the current step.
	local hint = reg(core:memo(function(use)
		local said = use(message)
		if said ~= "" then
			return said
		end
		if use(finished) then
			return "Rack empty — that is the whole game. Press Start over to play again."
		end
		local slot = use(selected)
		if slot == nil then
			return "Pick a letter from your rack, then tap an empty square to place it."
		end
		return `Holding {RACK[slot][1]} — tap an empty square to place it.`
	end))

	local scoreText = reg(core:memo(function(use)
		return `Score {use(score)}`
	end))
	local progressText = reg(core:memo(function(use)
		return `{use(placedCount)} of {#RACK} tiles placed`
	end))

	-- ---- board: ONE Grid of 25 squares --------------------------------------
	-- `UI.Grid` with a fixed column count is the container for a board. It also
	-- earns the 2D focus story: the focus map turns a Grid's focusables into
	-- per-row horizontal groups linked by up/down exits, so a D-pad or the arrow
	-- keys cross the board with no consumer navigation map.
	local cells = {}
	for r = 1, BOARD_ROWS do
		for c = 1, BOARD_COLS do
			local rr, cc = r, c
			local key = cellKey(r, c)
			local label = reg(core:memo(function(use)
				local p = use(placements)[key]
				return if p ~= nil then p.letter else ""
			end))
			-- an empty square that can accept the held tile reads as available;
			-- an occupied one reads as taken. Both are semantic surfaces, not
			-- colours this file invented.
			local surface = reg(core:memo(function(use)
				return if use(placements)[key] ~= nil then "raised" else "control"
			end))
			cells[#cells + 1] = UI.Button({
				id = `cell{r}_{c}`,
				label = label,
				surface = surface,
				width = CELL,
				height = CELL,
				textSize = "control",
				-- APP SEMANTICS on the node: activating a board square (tap, or
				-- Return/A on the focused square) places the held rack tile here.
				-- The presenter dispatches Activate with no consumer routing
				-- (ADR-0013); select-then-place is the app's own rule.
				onActivate = function()
					placeAt(rr, cc)
				end,
			})
		end
	end
	local board = UI.Grid({
		id = "board",
		columns = BOARD_COLS,
		itemSizing = "uniform",
		gap = "xs",
		children = cells,
	})

	-- ---- rack: one button per starting tile ---------------------------------
	-- A played slot keeps its place (so the rack does not reshuffle under the
	-- player's finger) but is DISABLED and labelled, rather than being a blank
	-- button that looks pressable and silently does nothing.
	local rackTiles = {}
	for i, tile in RACK do
		local slot = i
		local played = reg(core:memo(function(use)
			return use(placedSlots)[slot] == true
		end))
		local label = reg(core:memo(function(use)
			return if use(played) then "·" else tile[1]
		end))
		local enabled = reg(core:memo(function(use)
			return not use(played)
		end))
		local isSelected = reg(core:memo(function(use)
			return use(selected) == slot
		end))
		rackTiles[i] = UI.Button({
			id = "rt" .. i,
			label = label,
			enabled = enabled,
			selected = isSelected,
			width = CELL,
			height = CELL,
			textSize = "control",
			-- APP SEMANTICS: activating a rack tile picks that slot up.
			onActivate = function()
				selectSlot(slot)
			end,
		})
	end
	local rack = UI.Grid({
		id = "rack",
		columns = #RACK,
		itemSizing = "uniform",
		gap = "xs",
		children = rackTiles,
	})

	-- ---- the screen ---------------------------------------------------------
	-- `surface = "base"` so the tutorial reads as a screen rather than loose text
	-- floating over whatever 3D world the place happens to have, and the page is
	-- a ScrollView so a short landscape phone can still reach the rack and the
	-- Start-over button.
	local screen = UI.Screen({
		id = "TileGame",
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
					UI.Text({ id = "Title", text = "LuauUI Tiles", textSize = "title" }),
					UI.Text({ id = "Hint", text = hint, textSize = "body", role = "secondary" }),
					-- THE STATS LINE WRAPS (overflow sweep, 320x640: as a plain HStack
					-- the two readouts needed 307px of row and the page's padded
					-- width there is 280, so the line simply painted past its own
					-- box). `UI.Grid` with `minColumnWidth = "intrinsic"` is the
					-- declarative form of "side by side where they fit, stacked where
					-- they do not": the column count is derived from the widest
					-- child's own measured width under the ACTIVE theme's font, every
					-- solve — two columns on a phone, one on a 320px phone, no
					-- viewport arithmetic to keep in sync. It is the same answer
					-- 07_match3's artwork row takes, for the same reason.
					--
					-- NOT `UI.ViewThatFits`. A candidate ladder would need each
					-- readout written TWICE, once per candidate, and the framework
					-- keeps the losing candidate mounted at a deliberate zero rect —
					-- so half the declared content is unreachable at every viewport
					-- and both copies answer `adapter.node(...)` identically. The
					-- readouts stay DIRECT children here, at the paths this example
					-- has always published (`/Stats/Score`, `/Stats/Progress`), which
					-- is what tests/example_readouts.spec.luau pins.
					UI.Grid({
						id = "Stats",
						minColumnWidth = "intrinsic",
						gap = "s",
						width = { type = "fill", weight = 1 },
						children = {
							UI.Text({ id = "Score", text = scoreText, textSize = "numeral" }),
							UI.Text({
								id = "Progress",
								text = progressText,
								textSize = "label",
								role = "secondary",
							}),
						},
					}),
					board,
					UI.Text({ id = "RackLabel", text = "Your rack", textSize = "label", role = "secondary" }),
					rack,
					UI.Button({ id = "Reset", label = "Start over", onActivate = reset }),
				},
			}),
		},
	})

	-- Presented with NO opts: each square and rack tile carries its own Activate
	-- handler (above), and the presenter derives 2D grid navigation from the two
	-- Grids automatically (ADR-0013 layout-derived groups) — so a D-pad crosses
	-- the board and A places, with no consumer wiring.
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
		-- what the instruction line currently says (the visible refusal/next step)
		hintText = function(): string
			return hint:get()
		end,
		finished = function(): boolean
			return finished:get()
		end,
		reset = reset,
		rackPath = function(i: number): string
			return `/TileGame/Page/rack/rt{nthAvailable(i)}`
		end,
		cellPath = function(r: number, c: number): string
			return `/TileGame/Page/board/cell{r}_{c}`
		end,
		hintPath = "/TileGame/Page/Hint",
		resetPath = "/TileGame/Page/Reset",

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
