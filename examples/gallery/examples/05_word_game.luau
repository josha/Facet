--!strict
-- Gallery example 6 — a Wordle-style word game.
--
-- What this example teaches:
--   * Game state modeling in plain reactive signals/memos (no game logic lives
--     in the UI layer — the UI is a pure function of the guess grid).
--   * A keyed structural grid: a 6x5 board of letter tiles, each tile a small
--     region whose letter and state color come from bindings.
--   * Multi-input: the same "type a letter" command arrives three ways — a
--     hardware key (arbitrated through the action system), an on-screen key you
--     tap (touch), or an on-screen key you move to with a gamepad and press.
--   * On-screen keyboard as three navigation-group rows, so a gamepad can move
--     left/right within a row and up/down between rows.
--   * A results modal opened through the presenter when the word is solved.
--
-- Everything runs headless: no engine calls, so the same file drives the tests
-- and a real Roblox client unchanged.

local assets = require("./assets")
local _ = assets -- (this example needs no images; kept for gallery symmetry)

local ROWS = 6
local COLS = 5
local SOLUTION = "REACT"

-- The classic three-row on-screen keyboard. Enter and Back are keys too.
local KEYBOARD = {
	{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
	{ "A", "S", "D", "F", "G", "H", "J", "K", "L" },
	{ "Enter", "Z", "X", "C", "V", "B", "N", "M", "Back" },
}

-- Per-tile state -> the surface token the tile paints with. Headless targets
-- keep the token as opaque data; a real style resolves it to a color.
local SURFACE_FOR = {
	empty = "tileEmpty",
	filled = "tileFilled",
	absent = "tileAbsent",
	present = "tilePresent",
	correct = "tileCorrect",
}

-- Score a guess against the solution the way Wordle does: exact matches first,
-- then "present" for a letter that exists elsewhere but is not already spent.
local function evaluate(guess: string, solution: string): { string }
	local states: { string } = {}
	local remaining: { [string]: number } = {}
	for i = 1, #solution do
		local ch = solution:sub(i, i)
		remaining[ch] = (remaining[ch] or 0) + 1
	end
	for i = 1, COLS do
		local g = guess:sub(i, i)
		if g == solution:sub(i, i) then
			states[i] = "correct"
			remaining[g] = (remaining[g] or 0) - 1
		end
	end
	for i = 1, COLS do
		if states[i] == nil then
			local g = guess:sub(i, i)
			if (remaining[g] or 0) > 0 then
				states[i] = "present"
				remaining[g] = remaining[g] - 1
			else
				states[i] = "absent"
			end
		end
	end
	return states
end

local function emptyRows(): { any }
	local rows = {}
	for _ = 1, ROWS do
		table.insert(rows, { letters = "", submitted = false, states = nil })
	end
	return rows
end

-- signals hold immutable snapshots: every edit produces a NEW rows table so the
-- core sees a real change and recomputes the tile bindings.
local function cloneRows(rows: { any }): { any }
	local out = {}
	for _, row in rows do
		local states = nil
		if row.states ~= nil then
			states = table.clone(row.states)
		end
		table.insert(out, { letters = row.letters, submitted = row.submitted, states = states })
	end
	return out
end

local function stateAt(rows: { any }, r: number, c: number): string
	local row = rows[r]
	if row.submitted and row.states ~= nil then
		return row.states[c]
	elseif c <= #row.letters then
		return "filled"
	end
	return "empty"
end

local function build(LuauUI: any, core: any, deps: any)
	local UI = LuauUI.UI
	local pres = deps.presenter
	local actions = deps.actionSystem

	-- gameScope owns everything this example creates so dispose() returns the
	-- registries to exactly where they were before build().
	local gameScope = core:scope("example-06-word-game")
	local function reg(readable: any): any
		gameScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	local rowsSig = reg(core:signal(emptyRows()))
	local wonSig = reg(core:signal(false))
	local curRow = 1
	local modalHandle: any = nil

	-- ---- game commands (pure state; no UI knowledge) ------------------------
	local function typeLetter(letter: string)
		if wonSig:get() or curRow > ROWS then
			return
		end
		local rows = cloneRows(rowsSig:get())
		local row = rows[curRow]
		if #row.letters < COLS then
			row.letters = row.letters .. letter
			rowsSig:set(rows)
		end
	end

	local function backspace()
		if wonSig:get() or curRow > ROWS then
			return
		end
		local rows = cloneRows(rowsSig:get())
		local row = rows[curRow]
		if #row.letters > 0 then
			row.letters = row.letters:sub(1, #row.letters - 1)
			rowsSig:set(rows)
		end
	end

	local function openResults(solved: boolean)
		modalHandle = pres.presentModal(UI.Screen({
			id = "WordleResult",
			padding = 20,
			gap = 12,
			surface = "raised",
			children = {
				UI.Text({ id = "Msg", text = if solved then "Solved!" else "Out of guesses", textSize = 26 }),
				UI.Text({ id = "Word", text = `The word was {SOLUTION}`, textSize = 16 }),
				UI.Button({ id = "Close", label = "Close" }),
			},
		}))
	end

	local function submit()
		if wonSig:get() or curRow > ROWS then
			return
		end
		local rows = cloneRows(rowsSig:get())
		local row = rows[curRow]
		if #row.letters < COLS then
			return -- row not full yet
		end
		row.states = evaluate(row.letters, SOLUTION)
		row.submitted = true
		rowsSig:set(rows)
		if row.letters == SOLUTION then
			wonSig:set(true)
			openResults(true)
		else
			curRow += 1
			if curRow > ROWS then
				openResults(false)
			end
		end
	end

	-- ---- board blueprint: 6 rows of 5 tiles, each tile a bound region --------
	local boardRows = {}
	for r = 1, ROWS do
		local tiles = {}
		for c = 1, COLS do
			local rr, cc = r, c
			local letter = reg(core:memo(function(use)
				return use(rowsSig)[rr].letters:sub(cc, cc)
			end))
			local surface = reg(core:memo(function(use)
				return SURFACE_FOR[stateAt(use(rowsSig), rr, cc)]
			end))
			tiles[c] = UI.ZStack({
				id = "tile" .. c,
				surface = surface,
				width = { type = "fixed", px = 48 },
				height = { type = "fixed", px = 48 },
				alignH = "center",
				alignV = "center",
				children = { UI.Text({ id = "ch", text = letter, textSize = 24 }) },
			})
		end
		boardRows[r] = UI.HStack({ id = "row" .. r, gap = 4, children = tiles })
	end
	local board = UI.VStack({ id = "board", gap = 4, children = boardRows })

	-- ---- on-screen keyboard: three rows of key buttons ----------------------
	-- Each key carries its APP SEMANTICS on its node onActivate: a tap, or A on
	-- the focused key, runs that key's command (type / submit / backspace). The
	-- presenter dispatches Activate here with no consumer routing, and derives
	-- the three-row 2D navigation directly from the HStack rows (ADR-0013
	-- layout-derived groups): D-pad Left/Right within a row, Up/Down between
	-- rows landing on the nearest key in the same column.
	local keyPathByLetter: { [string]: string } = {}
	local keyboardRows = {}
	for ri, keys in KEYBOARD do
		local rowId = "kbrow" .. ri
		local buttons = {}
		for ki, key in keys do
			local thisKey = key
			local label = if key == "Back" then "Bksp" else key
			buttons[ki] = UI.Button({
				id = "key_" .. key,
				label = label,
				onActivate = function()
					if thisKey == "Enter" then
						submit()
					elseif thisKey == "Back" then
						backspace()
					else
						typeLetter(thisKey)
					end
				end,
			})
			keyPathByLetter[key] = `/Wordle/kb/{rowId}/key_{key}`
		end
		keyboardRows[ri] = UI.HStack({ id = rowId, gap = 4, children = buttons })
	end
	local keyboard = UI.VStack({ id = "kb", gap = 4, children = keyboardRows })

	local screen = UI.Screen({
		id = "Wordle",
		padding = 16,
		gap = 16,
		children = {
			UI.Text({ id = "Title", text = "LuauUI Wordle", textSize = 28 }),
			board,
			keyboard,
		},
	})

	-- ---- present + wire input ----------------------------------------------
	-- Presented with NO opts: activation (tap / gamepad A on the focused key)
	-- rides each key's node onActivate, and D-pad/arrow grid navigation is
	-- auto-derived from the keyboard's HStack rows (see above).
	local handle = pres.present(screen)

	-- A dedicated, higher-priority input context for the HARDWARE keys a real
	-- keyboard sends — the genuinely app-semantic part that stays at the consumer
	-- level. It SINKS so its keys shadow the presenter's default Activate: a
	-- physical letter key TYPES into the grid (rather than activating whatever
	-- key button is focused), Enter SUBMITS the guess, and Backspace deletes.
	-- Navigation keys are intentionally NOT bound here — arrows/D-pad fall
	-- through to the presenter's auto grid navigation.
	local ctx = actions.createContext({ name = "WordleInput", priority = 2000, sink = true })
	gameScope:own(function()
		ctx.destroy()
	end)
	for i = 0, 25 do
		local letter = string.char(65 + i)
		local a = ctx.createAction("Type_" .. letter, "Bool")
		a.bind({ keyCode = letter })
		a.onPressed(function()
			typeLetter(letter)
		end)
	end
	local submitAction = ctx.createAction("Submit", "Bool")
	submitAction.bind({ keyCode = "Return" })
	submitAction.onPressed(submit)
	local backAction = ctx.createAction("Backspace", "Bool")
	backAction.bind({ keyCode = "Backspace" })
	backAction.onPressed(backspace)

	-- ---- public / test API --------------------------------------------------
	return {
		title = "Word Game (Wordle-style)",
		screen = screen,
		handle = handle,
		solution = SOLUTION,

		-- fire a hardware key through the arbitrated action pipeline
		press = function(keyCode: string)
			actions.deviceKey(keyCode, true)
			actions.deviceKey(keyCode, false)
		end,
		row = function(i: number): string
			return rowsSig:get()[i].letters
		end,
		state = function(r: number, c: number): string
			return stateAt(rowsSig:get(), r, c)
		end,
		won = function(): boolean
			return wonSig:get()
		end,
		keyPath = function(letter: string): string
			return keyPathByLetter[letter]
		end,

		dispose = function()
			if modalHandle ~= nil then
				pres.dismiss(modalHandle)
				modalHandle = nil
			end
			pres.dismiss(handle)
			gameScope:dispose()
		end,
	}
end

return {
	title = "Word Game (Wordle-style)",
	build = build,
}
