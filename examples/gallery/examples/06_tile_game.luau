--!strict

local words = require("./words")

type Use = (any) -> any

local example = {}
example.title = "Crossword (Scrabble-style)"

local SIZE = 7
local CENTRE = 4
local RACK_SIZE = 7
local TURNS = 6
local GOAL = 60
local BONUS_TILES = 5
local BONUS = 10
local DEFAULT_SEED = 20260829
local DEAL_ATTEMPTS = 64

local rules = {}
rules.SIZE = SIZE
rules.CENTRE = CENTRE
rules.RACK_SIZE = RACK_SIZE
rules.TURNS = TURNS
rules.GOAL = GOAL
rules.BONUS_TILES = BONUS_TILES
rules.BONUS = BONUS
rules.DEFAULT_SEED = DEFAULT_SEED
rules.DEAL_ATTEMPTS = DEAL_ATTEMPTS

rules.MIN_WORD = words.MIN_LENGTH
rules.MAX_WORD = words.MAX_LENGTH

rules.VALUES = table.freeze({
	A = 1,
	B = 3,
	C = 3,
	D = 2,
	E = 1,
	F = 4,
	G = 2,
	H = 4,
	I = 1,
	J = 8,
	K = 5,
	L = 1,
	M = 3,
	N = 1,
	O = 1,
	P = 3,
	Q = 10,
	R = 1,
	S = 1,
	T = 1,
	U = 1,
	V = 4,
	W = 4,
	X = 8,
	Y = 4,
	Z = 10,
})

rules.DISTRIBUTION = table.freeze({
	{ "A", 9 },
	{ "B", 2 },
	{ "C", 2 },
	{ "D", 4 },
	{ "E", 12 },
	{ "F", 2 },
	{ "G", 3 },
	{ "H", 2 },
	{ "I", 9 },
	{ "J", 1 },
	{ "K", 1 },
	{ "L", 4 },
	{ "M", 2 },
	{ "N", 6 },
	{ "O", 8 },
	{ "P", 2 },
	{ "Q", 1 },
	{ "R", 6 },
	{ "S", 4 },
	{ "T", 6 },
	{ "U", 4 },
	{ "V", 2 },
	{ "W", 2 },
	{ "X", 1 },
	{ "Y", 2 },
	{ "Z", 1 },
} :: { { string | number } })

rules.SAY = table.freeze({
	centre = "Your first word has to cover the starred centre square.",
	axis = "The tiles you place in a turn go in a single row or a single column.",
	gap = "Leave no gaps — your tiles and the letters already on the board have to make one unbroken run.",
	connect = "After the first turn, a word has to touch a letter already on the board.",
	empty = "Place at least one tile before you submit.",
	occupied = "That square already has a letter.",
	committed = "Letters from an earlier turn stay put.",
	long = "This game only knows words up to seven letters long.",

	nothingHeld = "Pick a letter from your rack first, then choose a square.",
	nothingPlaced = "Nothing to undo — you have not placed a tile this turn.",
})

assert(rules.MAX_WORD == 7, "06_tile_game: SAY.long spells the seven-letter ceiling out; the dictionary moved")

function rules.sayUnknown(word: string): string
	return `{word} isn't a word this game knows.`
end

function rules.sayUnknownCrossing(word: string, axis: string): string
	local direction = if axis == "col" then "downward" else "across"
	return `That would make {word} {direction}, and that isn't a word this game knows.`
end

function rules.key(r: number, c: number): string
	return r .. "," .. c
end

function rules.value(letter: string): number
	return (rules.VALUES :: any)[letter] or 0
end

function rules.onBoard(r: number, c: number): boolean
	return r >= 1 and r <= SIZE and c >= 1 and c <= SIZE
end

function rules.makeRng(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

function rules.newBag(rng: () -> number): { string }
	local bag: { string } = {}
	for _, entry in rules.DISTRIBUTION do
		for _ = 1, entry[2] :: number do
			table.insert(bag, entry[1] :: string)
		end
	end
	for i = #bag, 2, -1 do
		local j = math.floor(rng() * i) + 1
		bag[i], bag[j] = bag[j], bag[i]
	end
	return bag
end

function rules.openingWord(rack: { string }): string?
	local n = #rack
	local used = table.create(n, false)
	local letters: { string } = {}
	local found: string? = nil
	local deepest = math.min(n, rules.MAX_WORD)
	local function walk(depth: number)
		if depth >= rules.MIN_WORD then
			local candidate = table.concat(letters)
			if words.isWord(candidate) then
				found = candidate
				return
			end
		end
		if depth >= deepest then
			return
		end
		for i = 1, n do
			if not used[i] then
				used[i] = true
				letters[depth + 1] = rack[i]
				walk(depth + 1)
				letters[depth + 1] = nil
				used[i] = false
				if found ~= nil then
					return
				end
			end
		end
	end
	walk(0)
	return found
end

export type Deal = { rack: { string }, bag: { string }, opening: string?, attempts: number }

function rules.deal(rng: () -> number): Deal
	local bag: { string } = {}
	local rack: { string } = {}
	local opening: string? = nil
	local attempts = 0
	for attempt = 1, DEAL_ATTEMPTS do
		attempts = attempt
		bag = rules.newBag(rng)
		rack = {}
		for i = 1, RACK_SIZE do
			rack[i] = bag[i]
		end
		opening = rules.openingWord(rack)
		if opening ~= nil then
			break
		end
	end
	local rest: { string } = {}
	for i = RACK_SIZE + 1, #bag do
		table.insert(rest, bag[i])
	end
	return { rack = rack, bag = rest, opening = opening, attempts = attempts }
end

function rules.wordVerdict(word: string): string
	if #word > rules.MAX_WORD then
		return "long"
	end
	if not words.isWord(word) then
		return "unknown"
	end
	return "ok"
end

local STEPS = table.freeze({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } })

local function letterAt(board: { [string]: string }, placed: { [string]: string }, r: number, c: number): string?
	if not rules.onBoard(r, c) then
		return nil
	end
	local key = rules.key(r, c)
	local pending = placed[key]
	if pending ~= nil then
		return pending
	end
	return board[key]
end

rules.letterAt = letterAt

function rules.runThrough(
	board: { [string]: string },
	placed: { [string]: string },
	r: number,
	c: number,
	axis: string
): { { r: number, c: number } }
	if letterAt(board, placed, r, c) == nil then
		return {}
	end
	local dr = if axis == "col" then 1 else 0
	local dc = if axis == "col" then 0 else 1
	local sr, sc = r, c
	while letterAt(board, placed, sr - dr, sc - dc) ~= nil do
		sr -= dr
		sc -= dc
	end
	local cells: { { r: number, c: number } } = {}
	local er, ec = sr, sc
	while letterAt(board, placed, er, ec) ~= nil do
		table.insert(cells, { r = er, c = ec })
		er += dr
		ec += dc
	end
	return cells
end

function rules.wordOf(
	board: { [string]: string },
	placed: { [string]: string },
	cells: { { r: number, c: number } }
): string
	local out: { string } = {}
	for _, cell in cells do
		table.insert(out, letterAt(board, placed, cell.r, cell.c) :: string)
	end
	return table.concat(out)
end

function rules.placedCells(placed: { [string]: string }): { { r: number, c: number } }
	local cells: { { r: number, c: number } } = {}
	for r = 1, SIZE do
		for c = 1, SIZE do
			if placed[rules.key(r, c)] ~= nil then
				table.insert(cells, { r = r, c = c })
			end
		end
	end
	return cells
end

function rules.axisOf(
	board: { [string]: string },
	placed: { [string]: string },
	cells: { { r: number, c: number } }
): string?
	if #cells == 0 then
		return nil
	end
	if #cells == 1 then
		local only = cells[1]
		local down = #rules.runThrough(board, placed, only.r, only.c, "col")
		local across = #rules.runThrough(board, placed, only.r, only.c, "row")
		return if down >= rules.MIN_WORD and across < rules.MIN_WORD then "col" else "row"
	end
	local sameRow, sameCol = true, true
	for _, cell in cells do
		if cell.r ~= cells[1].r then
			sameRow = false
		end
		if cell.c ~= cells[1].c then
			sameCol = false
		end
	end
	if sameRow then
		return "row"
	elseif sameCol then
		return "col"
	end
	return nil
end

export type Made = { word: string, axis: string, cells: { { r: number, c: number } }, score: number }
export type Verdict = {
	ok: boolean,
	code: string?,
	message: string,
	word: string?,
	axis: string?,
	made: { Made }?,
	score: number?,
	bonus: number?,
	tiles: number?,
}

local function refuse(code: string, message: string, word: string?): Verdict
	return { ok = false, code = code, message = message, word = word }
end

function rules.validate(board: { [string]: string }, placed: { [string]: string }, turn: number): Verdict
	local cells = rules.placedCells(placed)
	if #cells == 0 then
		return refuse("empty", rules.SAY.empty)
	end
	for _, cell in cells do
		if board[rules.key(cell.r, cell.c)] ~= nil then
			return refuse("occupied", rules.SAY.occupied)
		end
	end

	local axis = rules.axisOf(board, placed, cells)
	if axis == nil then
		return refuse("axis", rules.SAY.axis)
	end

	local line = if axis == "row" then cells[1].r else cells[1].c
	local lo, hi = math.huge, -math.huge
	for _, cell in cells do
		local along = if axis == "row" then cell.c else cell.r
		lo = math.min(lo, along)
		hi = math.max(hi, along)
	end
	for along = lo, hi do
		local r = if axis == "row" then line else along
		local c = if axis == "row" then along else line
		if letterAt(board, placed, r, c) == nil then
			return refuse("gap", rules.SAY.gap)
		end
	end

	if turn <= 1 then
		if placed[rules.key(CENTRE, CENTRE)] == nil then
			return refuse("centre", rules.SAY.centre)
		end
	else
		local touches = false
		for _, cell in cells do
			for _, step in STEPS do
				local r, c = cell.r + step[1] :: number, cell.c + step[2] :: number
				if rules.onBoard(r, c) and board[rules.key(r, c)] ~= nil then
					touches = true
					break
				end
			end
			if touches then
				break
			end
		end
		if not touches then
			return refuse("connect", rules.SAY.connect)
		end
	end

	local made: { Made } = {}
	local function add(cellsOf: { { r: number, c: number } }, wordAxis: string, crossing: boolean): Verdict?
		local word = rules.wordOf(board, placed, cellsOf)
		local verdict = rules.wordVerdict(word)
		if verdict == "long" then
			return refuse("long", rules.SAY.long, word)
		elseif verdict == "unknown" then
			if crossing then
				return refuse("unknownCrossing", rules.sayUnknownCrossing(word, wordAxis), word)
			end
			return refuse("unknown", rules.sayUnknown(word), word)
		end
		local score = 0
		for i = 1, #word do
			score += rules.value(string.sub(word, i, i))
		end
		table.insert(made, { word = word, axis = wordAxis, cells = cellsOf, score = score })
		return nil
	end

	local mainCells = rules.runThrough(board, placed, cells[1].r, cells[1].c, axis)
	local bad = add(mainCells, axis, false)
	if bad ~= nil then
		return bad
	end

	local crossAxis = if axis == "row" then "col" else "row"
	for _, cell in cells do
		local crossCells = rules.runThrough(board, placed, cell.r, cell.c, crossAxis)
		if #crossCells >= rules.MIN_WORD then
			bad = add(crossCells, crossAxis, true)
			if bad ~= nil then
				return bad
			end
		end
	end

	local total = 0
	for _, entry in made do
		total += entry.score
	end
	local bonus = if #cells >= BONUS_TILES then BONUS else 0
	local main = made[1].word
	local message = if bonus > 0
		then `Making {main} — {total + bonus} points (+{BONUS} for using {#cells} tiles)`
		else `Making {main} — {total} points`
	return {
		ok = true,
		message = message,
		axis = axis,
		made = made,
		score = total + bonus,
		bonus = bonus,
		tiles = #cells,
	}
end

function rules.legalCells(
	board: { [string]: string },
	placed: { [string]: string },
	turn: number
): { [string]: boolean }
	local legal: { [string]: boolean } = {}
	local cells = rules.placedCells(placed)
	local axis = if #cells >= 2 then rules.axisOf(board, placed, cells) else nil
	if axis ~= nil then
		local line = if axis == "row" then cells[1].r else cells[1].c
		for along = 1, SIZE do
			local r = if axis == "row" then line else along
			local c = if axis == "row" then along else line
			if letterAt(board, placed, r, c) == nil then
				legal[rules.key(r, c)] = true
			end
		end
		return legal
	end
	if turn <= 1 and letterAt(board, placed, CENTRE, CENTRE) == nil then
		legal[rules.key(CENTRE, CENTRE)] = true
	end
	for r = 1, SIZE do
		for c = 1, SIZE do
			if letterAt(board, placed, r, c) ~= nil then
				for _, step in STEPS do
					local nr, nc = r + step[1] :: number, c + step[2] :: number
					if rules.onBoard(nr, nc) and letterAt(board, placed, nr, nc) == nil then
						legal[rules.key(nr, nc)] = true
					end
				end
			end
		end
	end
	return legal
end

example.rules = rules

local CELL_TINT: { [string]: any } = {

	idle = { role = "contentSecondary", blend = 0.2 },

	legal = { role = "accent", blend = 0.3 },

	centre = { role = "accent", blend = 0.3 },

	pending = { role = "accent", blend = 0.6 },

	committed = { role = "contentSecondary", blend = 0.5 },
}

local CELL_SURFACE: { [string]: string } = {
	idle = "plain",
	legal = "plain",
	centre = "plain",
	pending = "chip",
	committed = "raised",
}

local CELL_MARK: { [string]: string } = {
	idle = "",
	legal = "+",
	centre = "★",
	pending = "~",
	committed = "",
}

function example.build(ctx: any)
	local UI, Compose, Host = ctx.UI, ctx.Compose, ctx.Host
	local UDim2, Vector2, Color3, Enum = ctx.types.UDim2, ctx.types.Vector2, ctx.types.Color3, ctx.types.Enum
	local function paletteColor(use: any, role: string): Color3
		local package = if ctx.theme then use(ctx.theme) else ctx.Facet.themes.neutralPackage()
		local mode = if ctx.themeMode then use(ctx.themeMode) else package.style.defaultTheme
		local chosen = package.style.themes[1]
		for _, candidate in package.style.themes do
			if candidate.name == mode then
				chosen = candidate
			end
		end
		local rgb = chosen.colors[role] or (chosen.extra or {})[role] or chosen.colors.content
		return Color3.new(rgb.r, rgb.g, rgb.b)
	end

	local seedSig = Compose.cell(DEFAULT_SEED)
	local boardSig = Compose.cell({} :: { [string]: string })
	local pendingSig = Compose.cell({} :: { [string]: string })
	local rackSig = Compose.cell({} :: { [number]: string })
	local originSig = Compose.cell({} :: { [string]: number })
	local selectedSig = Compose.cell(nil :: number?)
	local scoreSig = Compose.cell(0)
	local turnSig = Compose.cell(1)
	local phaseSig = Compose.cell("playing")
	local noticeSig = Compose.cell("")
	local bag: { string } = {}
	local bagAt = 1
	local opening: string? = nil
	local dealAttempts = 0
	local function playing(): boolean
		return phaseSig:peek() == "playing"
	end
	local function restart(seed: number?)
		local nextSeed = if seed ~= nil then math.floor(seed) else seedSig:peek()
		local rng = rules.makeRng(nextSeed)
		local dealt = rules.deal(rng)
		bag = dealt.bag
		bagAt = 1
		opening = dealt.opening
		dealAttempts = dealt.attempts
		local rack: { [number]: string } = {}
		for i = 1, RACK_SIZE do
			rack[i] = dealt.rack[i]
		end
		ctx.runtime:batch(function()
			seedSig:set(nextSeed)
			boardSig:set({})
			pendingSig:set({})
			originSig:set({})
			rackSig:set(rack)
			selectedSig:set(nil)
			scoreSig:set(0)
			turnSig:set(1)
			phaseSig:set("playing")
			noticeSig:set("")
		end)
	end
	local function selectSlot(slot: number)
		if not playing() then
			return
		end
		if rackSig:peek()[slot] == nil then
			return
		end
		ctx.runtime:batch(function()
			selectedSig:set(if selectedSig:peek() == slot then nil else slot)
			noticeSig:set("")
		end)
	end
	local function activateCell(r: number, c: number)
		if not playing() then
			return
		end
		if not rules.onBoard(r, c) then
			return
		end
		local key = rules.key(r, c)
		local slot = selectedSig:peek()
		local committed = boardSig:peek()[key]
		local pendingLetter = pendingSig:peek()[key]
		if slot == nil then
			if committed ~= nil then
				noticeSig:set(rules.SAY.committed)
				return
			end
			if pendingLetter ~= nil then
				local origin = table.clone(originSig:peek())
				local rack = table.clone(rackSig:peek())
				local pending = table.clone(pendingSig:peek())
				rack[origin[key]] = pendingLetter
				pending[key] = nil
				origin[key] = nil
				ctx.runtime:batch(function()
					rackSig:set(rack)
					pendingSig:set(pending)
					originSig:set(origin)
					noticeSig:set("")
				end)
				return
			end
			noticeSig:set(rules.SAY.nothingHeld)
			return
		end
		if committed ~= nil or pendingLetter ~= nil then
			noticeSig:set(rules.SAY.occupied)
			return
		end
		local letter = rackSig:peek()[slot]
		if letter == nil then
			return
		end
		local rack = table.clone(rackSig:peek())
		local pending = table.clone(pendingSig:peek())
		local origin = table.clone(originSig:peek())
		rack[slot] = nil
		pending[key] = letter
		origin[key] = slot
		ctx.runtime:batch(function()
			rackSig:set(rack)
			pendingSig:set(pending)
			originSig:set(origin)
			selectedSig:set(nil)
			noticeSig:set("")
		end)
	end
	local function undo()
		if not playing() then
			return
		end
		local pending = pendingSig:peek()
		if next(pending) == nil then
			noticeSig:set(rules.SAY.nothingPlaced)
			return
		end
		local rack = table.clone(rackSig:peek())
		local origin = originSig:peek()
		for key, letter in pending do
			rack[origin[key]] = letter
		end
		ctx.runtime:batch(function()
			rackSig:set(rack)
			pendingSig:set({})
			originSig:set({})
			selectedSig:set(nil)
			noticeSig:set("")
		end)
	end
	local function submit()
		if not playing() then
			return
		end
		local board = boardSig:peek()
		local pending = pendingSig:peek()
		local verdict = rules.validate(board, pending, turnSig:peek())
		if not verdict.ok then
			noticeSig:set(verdict.message)
			return
		end
		local nextBoard = table.clone(board)
		for key, letter in pending do
			nextBoard[key] = letter
		end
		local rack = table.clone(rackSig:peek())
		for slot = 1, RACK_SIZE do
			if rack[slot] == nil and bagAt <= #bag then
				rack[slot] = bag[bagAt]
				bagAt += 1
			end
		end
		local nextScore = scoreSig:peek() + (verdict.score :: number)
		local nextTurn = turnSig:peek() + 1
		local phase = "playing"
		if nextScore >= GOAL then
			phase = "won"
		elseif nextTurn > TURNS then
			phase = "lost"
		end
		ctx.runtime:batch(function()
			boardSig:set(nextBoard)
			pendingSig:set({})
			originSig:set({})
			rackSig:set(rack)
			selectedSig:set(nil)
			scoreSig:set(nextScore)
			turnSig:set(nextTurn)
			phaseSig:set(phase)
			noticeSig:set(verdict.message)
		end)
	end
	restart(DEFAULT_SEED)
	local turnsLeft: any
	local scoreText: any
	local progressText: any
	local verdictSig: any
	local wordText: any
	local hintText: any
	local cellStateOf: { [string]: any } = {}
	local function Crossword()
		turnsLeft = Compose.formula(function(use: Use)
			return math.max(0, TURNS - (use(turnSig) - 1))
		end)
		scoreText = Compose.formula(function(use)
			return `{use(scoreSig)} of {GOAL} points`
		end)
		progressText = Compose.formula(function(use)
			local left = use(turnsLeft)
			return `{left} {if left == 1 then "turn" else "turns"} left`
		end)
		verdictSig = Compose.formula(function(use: Use): Verdict?
			local pending = use(pendingSig)
			if next(pending) == nil then
				return nil
			end
			return rules.validate(use(boardSig), pending, use(turnSig))
		end)
		wordText = Compose.formula(function(use: Use)
			local notice = use(noticeSig)
			if notice ~= "" then
				return notice
			end
			local verdict: Verdict? = use(verdictSig)
			if verdict == nil then
				return "No tiles placed this turn."
			end
			return verdict.message
		end)
		hintText = Compose.formula(function(use: Use)
			local phase = use(phaseSig)
			if phase == "won" then
				return `You reached {use(scoreSig)} points in {use(turnSig) - 1} of {TURNS} turns — you win! `
					.. "Press Start over to play again."
			elseif phase == "lost" then
				return `Out of turns at {use(scoreSig)} of {GOAL} points. Press Start over to play again.`
			end
			local slot = use(selectedSig)
			if slot ~= nil then
				return `Placing {use(rackSig)[slot]} — choose a square.`
			end
			if use(turnSig) <= 1 and next(use(boardSig)) == nil then
				return "Cover the starred square with a word to begin."
			end
			return "Pick a letter from your rack, then choose a square."
		end)
		local function narrow()
			return Host.UISizeConstraint({ MaxSize = Vector2.new(360, math.huge) })
		end
		local cells: { any } = { columns = SIZE, gap = "xs", aspectRatio = 1, narrow() }
		for r = 1, SIZE do
			for c = 1, SIZE do
				local rr, cc = r, c
				local key = rules.key(r, c)
				local state = Compose.formula(function(use: Use)
					if use(pendingSig)[key] ~= nil then
						return "pending"
					end
					if use(boardSig)[key] ~= nil then
						return "committed"
					end
					if rules.legalCells(use(boardSig), use(pendingSig), use(turnSig))[key] then
						return if rr == CENTRE and cc == CENTRE then "centre" else "legal"
					end
					return if rr == CENTRE and cc == CENTRE then "centre" else "idle"
				end)
				cellStateOf[key] = state
				local label = Compose.formula(function(use)
					return letterAt(use(boardSig), use(pendingSig), rr, cc) or ""
				end)
				local tint = Compose.formula(function(use)
					return CELL_TINT[use(state)]
				end)
				local surface = Compose.formula(function(use)
					return CELL_SURFACE[use(state)]
				end)
				local mark = Compose.formula(function(use)
					return CELL_MARK[use(state)]
				end)
				table.insert(
					cells,
					UI.ZStack(`cell{r}_{c}`)({
						width = 44,
						height = 44,
						UI.Label "mark" { text = mark, textRole = "caption" },
						UI.Button "tap" {
							Size = UDim2.fromScale(1, 1),
							label = function(use: Use)
								return use(label) .. use(mark)
							end,
							name = function(use)
								local letter = use(label)
								local base = if letter ~= ""
									then `Row {r}, column {c}, {letter}`
									else `Row {r}, column {c}`
								local current = use(state)
								return if current == "pending"
									then base .. ", not submitted"
									elseif current == "centre" then base .. ", start square"
									else base
							end,
							BackgroundColor3 = function(use)
								local cellTint = use(tint)
								return paletteColor(use, "surface"):Lerp(
									paletteColor(use, cellTint.role),
									cellTint.blend
								)
							end,
							TextColor3 = function(use)
								return paletteColor(use, "contentStrong")
							end,
							TextSize = 16,
							onActivate = function()
								activateCell(rr, cc)
							end,
							Host.UIStroke "Outline" {
								ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
								Color = function(use)
									return paletteColor(use, "contentStrong")
								end,
								Thickness = 2,
								Enabled = function(use)
									return use(surface) == CELL_SURFACE.pending
								end,
							},
							Host.UIPadding {},
						},
					})
				)
			end
		end
		local rackTiles: { any } = { columns = RACK_SIZE, gap = "xs", cellHeight = 48, narrow() }
		for i = 1, RACK_SIZE do
			local slot = i
			local letter = Compose.formula(function(use)
				return use(rackSig)[slot]
			end)
			local label = Compose.formula(function(use)
				return use(letter) or "·"
			end)
			local enabled = Compose.formula(function(use)
				return use(letter) ~= nil and use(phaseSig) == "playing"
			end)
			local isSelected = Compose.formula(function(use)
				return use(selectedSig) == slot
			end)
			table.insert(
				rackTiles,
				UI.Button("rt" .. i)({
					AutomaticSize = Enum.AutomaticSize.None,
					label = label,
					enabled = enabled,
					selected = isSelected,
					TextSize = 16,
					onActivate = function()
						selectSlot(slot)
					end,
				})
			)
		end
		return UI.Screen "TileGame" {
			UI.ScrollView "Page" {
				gap = "s",
				align = "stretch",
				UI.Label "Title" { text = "Facet Crossword", textRole = "title", TextWrapped = true },
				UI.HStack "Stats" {
					wrap = true,
					gap = "m",
					width = "fill",
					UI.Label "Score" { text = scoreText },
					UI.Label "Progress" { text = progressText },
				},
				UI.Label "Hint" { text = hintText, TextWrapped = true },
				UI.Label "Word" { text = wordText, TextWrapped = true },
				UI.Grid "board"(cells),
				UI.Label "RackLabel" { text = "Your rack", TextWrapped = true },
				UI.Grid "rack"(rackTiles),
				UI.HStack "Actions" {
					gap = "s",
					width = "fill",
					UI.Button "Submit" { label = "Submit word", onActivate = submit, UI.fill() },
					UI.Button "Undo" { label = "Undo turn", onActivate = undo, UI.fill() },
				},
				UI.Button "Reset" {
					label = "Start over",
					onActivate = function()
						restart(DEFAULT_SEED)
					end,
				},
			},
		}
	end

	local focusedCell = function(): (number?, number?)
		local node = ctx.guiService and ctx.guiService.SelectedObject
		local path = if node then node:GetFullName():gsub("%.", "/") else nil
		if type(path) ~= "string" then
			return nil, nil
		end
		local r, c = string.match(path, "/board/cell(%d+)_(%d+)/tap$")
		if r == nil then
			return nil, nil
		end
		return tonumber(r), tonumber(c)
	end
	local function typeLetter(letter: string)
		local r, c = focusedCell()
		if r == nil or c == nil then
			return
		end
		local rack = rackSig:peek()
		for slot = 1, RACK_SIZE do
			if rack[slot] == letter then
				selectedSig:set(slot)
				activateCell(r :: number, c :: number)
				return
			end
		end
		noticeSig:set(`There is no {letter} on your rack.`)
	end
	local bindings = {}
	for i = 0, 25 do
		local letter = string.char(65 + i)
		table.insert(
			bindings,
			Host.InputAction({
				Name = "Type_" .. letter,
				Type = Enum.InputActionType.Bool,
				Pressed = function()
					typeLetter(letter)
				end,
				Host.InputBinding({ KeyCode = Enum.KeyCode[letter] }),
			})
		)
	end
	Host.InputContext "CrosswordInput" {
		Parent = ctx.inputTarget,
		Priority = 2000,
		Sink = true,
		table.unpack(bindings),
	}

	return {
		title = example.title,
		screen = Crossword,
		rules = rules,
		press = function(keyCode: string)
			typeLetter(keyCode)
		end,
		select = selectSlot,
		place = activateCell,
		submit = submit,
		undo = undo,
		reset = function(seed: number?)
			restart(seed or DEFAULT_SEED)
		end,
		seed = function(): number
			return seedSig:peek()
		end,
		opening = function(): string?
			return opening
		end,
		dealAttempts = function(): number
			return dealAttempts
		end,
		letterAt = function(r: number, c: number): string?
			return letterAt(boardSig:peek(), pendingSig:peek(), r, c)
		end,
		committedAt = function(r: number, c: number): string?
			return boardSig:peek()[rules.key(r, c)]
		end,
		pendingAt = function(r: number, c: number): string?
			return pendingSig:peek()[rules.key(r, c)]
		end,
		cellState = function(r: number, c: number): string
			return cellStateOf[rules.key(r, c)]:peek()
		end,
		cellTint = function(r: number, c: number): any
			return CELL_TINT[cellStateOf[rules.key(r, c)]:peek()]
		end,
		cellSurface = function(r: number, c: number): string
			return CELL_SURFACE[cellStateOf[rules.key(r, c)]:peek()]
		end,
		cellMark = function(r: number, c: number): string
			return CELL_MARK[cellStateOf[rules.key(r, c)]:peek()]
		end,
		rackLetter = function(slot: number): string?
			return rackSig:peek()[slot]
		end,
		rackCount = function(): number
			local n = 0
			for slot = 1, RACK_SIZE do
				if rackSig:peek()[slot] ~= nil then
					n += 1
				end
			end
			return n
		end,
		selected = function(): number?
			return selectedSig:peek()
		end,
		score = function(): number
			return scoreSig:peek()
		end,
		turn = function(): number
			return turnSig:peek()
		end,
		turnsLeft = function(): number
			return turnsLeft:peek()
		end,
		phase = function(): string
			return phaseSig:peek()
		end,
		hintText = function(): string
			return hintText:peek()
		end,
		wordText = function(): string
			return wordText:peek()
		end,
		scoreText = function(): string
			return scoreText:peek()
		end,
		progressText = function(): string
			return progressText:peek()
		end,
		verdict = function(): any
			return verdictSig:peek()
		end,
		dump = function(): string
			local out: { string } = {}
			for r = 1, SIZE do
				local row: { string } = {}
				for c = 1, SIZE do
					table.insert(row, letterAt(boardSig:peek(), pendingSig:peek(), r, c) or ".")
				end
				table.insert(out, table.concat(row))
			end
			local rack: { string } = {}
			for slot = 1, RACK_SIZE do
				table.insert(rack, rackSig:peek()[slot] or ".")
			end
			return table.concat(out, "/")
				.. `|rack={table.concat(rack)}|score={scoreSig:peek()}|turn={turnSig:peek()}|phase={phaseSig:peek()}`
		end,
		cellPath = function(r: number, c: number): string
			return `/TileGame/Page/board/cell{r}_{c}/tap`
		end,
		platePath = function(r: number, c: number): string
			return `/TileGame/Page/board/cell{r}_{c}/plate`
		end,
		markPath = function(r: number, c: number): string
			return `/TileGame/Page/board/cell{r}_{c}/mark`
		end,
		rackPath = function(slot: number): string
			return `/TileGame/Page/rack/rt{slot}`
		end,
		hintPath = "/TileGame/Page/Hint",
		wordPath = "/TileGame/Page/Word",
		submitPath = "/TileGame/Page/Actions/Submit",
		undoPath = "/TileGame/Page/Actions/Undo",
		resetPath = "/TileGame/Page/Reset",
		dispose = function() end,
	}
end
return example
