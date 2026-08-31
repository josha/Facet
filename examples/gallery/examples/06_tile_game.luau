--!strict
-- ============================================================================
-- Example 6 of the Facet tutorial: a crossword tile game.
-- ============================================================================
--
-- WHAT THE PLAYER DOES
--   Seven letter tiles, six turns, a 7x7 board with a starred centre square,
--   and sixty points to reach. Pick a rack tile, tap a square, repeat, then
--   press "Submit word". The first turn has to cover the star; every turn after
--   that has to touch a letter already on the board; every word a turn creates
--   — the run along the turn's own axis AND every crossing word a placed tile
--   now sits inside — has to be in the shared dictionary. Reach sixty before the
--   turns run out and you win; run out first and you do not.
--
-- WHAT THIS REPLACED, AND WHY
--   The loop here used to be "drop any rack tile into any empty box" on a 5x5
--   grid: no dictionary, no adjacency, no word, and a win condition that was
--   simply an empty rack. It taught `UI.Grid` and nothing about a game. The
--   scaffolding survived the rewrite; the domain did not.
--
-- WHAT THIS EXAMPLE TEACHES
--   * DOMAIN RULES BELONG TO THE EXAMPLE, and they are PURE. `example.rules`
--     below is a board plus a placement in, a verdict out — no signal, no
--     presenter, no engine — which is what makes every rule in this file and
--     every refusal it can produce a headless test, and it is what keeps the
--     crossword out of `src/`. A user-interface library has no opinion about
--     English. See tests/example_tile_game.spec.luau.
--   * REFUSAL IS FEEDBACK, WITH THE EXACT PROBLEM NAMED. Nine distinct
--     refusals, nine distinct sentences, and a refused submit CHANGES NOTHING —
--     every placed tile stays where it is, so the player moves one tile rather
--     than starting the turn over. A rule that silently does nothing is
--     indistinguishable from a broken button.
--   * A BOARD IS ONE `UI.Grid`. 49 squares, one container, and the focus map
--     turns the Grid's focusables into per-row horizontal groups linked by
--     up/down exits — so a D-pad or the arrow keys cross the board with no
--     consumer navigation map. Select-then-place then works identically from a
--     mouse, a fingertip, a keyboard and a gamepad with NO per-device branch.
--   * EVERY CELL PAINTS SOMETHING. An empty square is chrome, not absence: its
--     plate is a `tint` along a role the palette contract contrast-gates, and
--     tests/example_tile_game.spec.luau measures all 49 of them against the page
--     they sit on in every shipped theme. `surfaceStrong` — the obvious choice,
--     and the one the sibling word game shipped for a mission — is the PANEL
--     colour, which every theme deliberately keeps within a few percent of the
--     page: 1.036:1 under Sci-Fi HUD, thirty rectangles present in the tree and
--     absent from the screen.
--   * COMMITTED VERSUS UNCOMMITTED IS NOT A COLOUR. A committed letter wears the
--     theme's solid `raised` plate; an uncommitted one wears its outlined `chip`
--     plate and carries a `~` mark. Both cues survive a greyscale screen.
--
-- Everything runs headless: no engine calls, so the same file drives the tests
-- and a real Roblox client unchanged.
--
-- deps used: presenter (opens the screen), actionSystem (the hardware-letter
-- convenience). See 01's header for the shared module shape.
--
-- data used: `./words`, the shared generated English word data both word games
-- run on. It is EXAMPLE CONTENT, not framework code — `src/` does not know it
-- exists — and its provenance is `words/PROVENANCE.md`.

local words = require("./words")

local example = {}
example.title = "Crossword (Scrabble-style)"

-- ===========================================================================
-- THE PURE RULES — no UI, no engine, no signals. Exported as `example.rules`
-- so the tests can play a whole turn without mounting a screen.
-- ===========================================================================

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
-- The two the dictionary owns, restated as the game's own limits so a caller
-- never has to know which module answers "how long may a word be".
rules.MIN_WORD = words.MIN_LENGTH
rules.MAX_WORD = words.MAX_LENGTH

-- THE FAMILIAR ENGLISH DISTRIBUTION, values and counts, because a player
-- already knows that Z is worth more than E and does not need to be taught it.
-- Anything else here would be a rule to learn before the first move.
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

-- The bag, as an ordered list of { letter, count }. 98 tiles: the familiar set
-- minus its two blanks, which §8 of the design rules out because a blank is a
-- rule the player has to learn before the first move. Order is fixed so the
-- shuffle is the ONLY source of variation and a seed replays exactly.
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
})

--[[ THE NINE REFUSALS, VERBATIM.

	Each is a distinct case in tests/example_tile_game.spec.luau, and each one is
	a SENTENCE about the board rather than a code the player has to decode. The
	two that name a word are functions below, because the word is the whole
	content of the message.

	`long` is unreachable through ordinary play and is here anyway: the board is
	seven wide, so a run cannot exceed the dictionary's seven-letter ceiling —
	but a game that hit it would otherwise call a real word "unknown", which is
	the one thing this list exists to prevent. `rules.wordVerdict` is the seam,
	and the spec drives it directly. ]]
rules.SAY = table.freeze({
	centre = "Your first word has to cover the starred centre square.",
	axis = "The tiles you place in a turn go in a single row or a single column.",
	gap = "Leave no gaps — your tiles and the letters already on the board have to make one unbroken run.",
	connect = "After the first turn, a word has to touch a letter already on the board.",
	empty = "Place at least one tile before you submit.",
	occupied = "That square already has a letter.",
	committed = "Letters from an earlier turn stay put.",
	long = "This game only knows words up to seven letters long.",
	-- ...and the two the play audit asked for on the sibling example, which are
	-- not refusals of a RULE but of an action that has no meaning yet
	nothingHeld = "Pick a letter from your rack first, then choose a square.",
	nothingPlaced = "Nothing to undo — you have not placed a tile this turn.",
})

-- A GUARD, NOT A COMMENT. `SAY.long` spells "seven" as a word because that is
-- how the sentence reads; a dictionary regenerated at a different ceiling would
-- otherwise leave the game telling the player a number that is no longer true.
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

--[[ A tiny deterministic PRNG (the classic Lehmer/Park-Miller generator), the
	same one 07_match3 refills its board from. Seeding it identically replays the
	exact same shuffle, which is what lets a test assert an exact final board. ]]
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

-- The whole bag, shuffled. Fisher-Yates from the back, so one draw of the
-- generator moves one tile and the sequence is reproducible per seed.
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

--[[ IS THERE A FIRST MOVE IN THIS RACK?

	The opening turn has to lay a word across the centre of an empty board, so
	the question is exactly "does some ordering of some subset of these letters
	spell a word the dictionary knows". Depth-first over the arrangements, asking
	at every depth of two or more, so the overwhelmingly common case (a two-letter
	word — there are 93 of them) is answered in a few dozen lookups rather than
	the 13,692-arrangement worst case.

	Returns the word it found, so the deal can report what it guaranteed. ]]
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

--[[ THE GUARANTEED OPENING.

	A deal whose rack spells nothing is a game that cannot start, and the player
	cannot see that it is their deal rather than their reading. So the deal
	CHECKS, and reshuffles from the SAME seeded stream when the check fails —
	exactly the shape 07_match3's `deal()` already uses for its legal-move
	guarantee, and bounded for the same reason: a pathological stream must not be
	able to hang the mount.

	The bound is honest about itself. If sixty-four shuffles never produce a
	playable rack the last one is dealt anyway with `opening = nil`, because a
	board the player can look at beats a mount that never returns. ]]
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

-- "ok" | "long" | "unknown". The length case is SEPARATE from the lookup case
-- because the two are different sentences to a player: one is a limit of this
-- game, the other is a claim about the word.
function rules.wordVerdict(word: string): string
	if #word > rules.MAX_WORD then
		return "long"
	end
	if not words.isWord(word) then
		return "unknown"
	end
	return "ok"
end

-- ---- reading the board -----------------------------------------------------
-- A board and a placement are both `{ [key]: letter }`. Two maps rather than
-- one, because "which of these letters may I still pick up" is a question the
-- rules answer constantly and a merged board could not.

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

-- The unbroken run of letters through (r, c) along one axis, as its cells in
-- board order. A cell with nothing in it returns an empty run.
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

-- The placed cells in board order (row-major). The rules never depend on the
-- ORDER a player placed their tiles in — only on where they ended up — so every
-- verdict is a pure function of the two maps.
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

--[[ THE AXIS, AND THE ONE CASE THAT MAKES IT INTERESTING.

	Two or more tiles fix an axis: they share a row or they share a column, and
	if they share neither the turn is refused. ONE tile fixes nothing — the
	player has not said which way they are building yet — so the axis is read off
	the BOARD instead: a lone tile that extends a column and not a row is a
	column word, and anything else (including a lone tile at a crossing, and a
	lone tile on an empty board) is read across. Both runs are still validated;
	this only decides which one is called the main word and which is called a
	crossing.

	Returns nil when the tiles are neither collinear form. ]]
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

--[[ validate(board, placed, turn) -> Verdict.

	THE ORDER OF THE CHECKS IS ITSELF A PRODUCT DECISION: the shape of what the
	player just did first (nothing placed, not in a line, a hole in the run),
	then the board rules that make a turn legal at all (the centre, the
	connection), and only then the dictionary. A player who has scattered three
	tiles across the board is told about the scatter, not about the nonsense word
	the scatter happens to spell. ]]
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

	-- ONE UNBROKEN RUN: every square between the first and last tile of the turn
	-- is filled, by this turn's tiles or by letters already on the board.
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

	-- EVERY WORD THE TURN CREATED. The main run first — the full line along the
	-- turn's axis INCLUDING committed letters at either end — and then the
	-- perpendicular run through each placed tile that is now longer than one
	-- letter. A single tile dropped between two committed words makes three
	-- words, and all three have to be real.
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

	-- THE SCORE: every letter in every word, once per word it appears in — a
	-- letter at a crossing is paid for twice because it is doing two jobs — plus
	-- ten for emptying five or more of the rack in one turn.
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

--[[ THE CELLS THAT COULD STILL TAKE A TILE.

	Before the axis is locked, that is every empty square touching a letter —
	committed or placed this turn — plus the starred centre on the opening turn.
	Once two tiles have named a row or a column, it is the empty squares on that
	line, because everything else would break the single-line rule the next
	submit is going to check anyway.

	It is derived, never stored: a legal-cell set kept in a signal is a second
	copy of the rules that can disagree with the first. ]]
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

-- ===========================================================================
-- PRESENTATION VOCABULARY — every value below names a THEME role or a theme
-- metric. There is not a raw colour or a device pixel in this file.
-- ===========================================================================

--[[ A SQUARE IS A FLOOR, NOT A CAP, and on this board it is also what makes a
	seven-wide grid fit a 320px phone.

	`targetSizes.minimum` is the theme's own smallest comfortable target, and
	`minMax` with it as the MIN lets the square grow with the player's text-size
	preference instead of clipping the letter inside it (the defect class
	of a px height fixed against unfixed content). `itemSizing = "uniform"` then
	makes the Grid hug seven of them where there is room — 7 x 44 + 6 gaps = 332
	on a tablet, a desktop and a TV — and DIVIDE the offer where there is not:
	the narrowest supported viewport (320x640) has 288px of page, so the lanes
	come out at 37 and the framework's own minimum-target expander keeps the tap
	band at 44. Measured both ways; a fixed px square would simply have painted
	44px off the right of that screen. ]]
local CELL: any = { type = "minMax", min = "targetSizes.minimum" }
local FILL: any = { type = "fill", weight = 1 }

--[[ CELL STATE -> the continuous colour channel, as a blend along a theme role.

	WHY NOT `surfaceStrong`, WHICH IS THE OBVIOUS CHOICE. It is the PANEL colour,
	and every shipped theme deliberately keeps a panel within a few percent of
	the page it sits on: measured across all fifteen themes in `examples/themes`,
	`{ role = "surfaceStrong", blend = 0.6 }` reaches 1.036:1 against the page
	under Sci-Fi HUD and never better than 1.223:1 anywhere. That is a board of
	forty-nine rectangles that is perfectly present in the tree, correct in every
	property probe, and not on the screen — the failure
	a default-valued write produces, and the one the
	sibling word game shipped for a whole mission.

	`contentSecondary` and `accent` are both contrast-gated against `surface` by
	the palette contract, so a small blend along either is a plate a player can
	actually see in every theme. tests/example_tile_game.spec.luau measures all
	five states in all fifteen themes and pins a 1.25:1 floor. ]]
local CELL_TINT: { [string]: any } = {
	-- an empty square with nothing to do yet: quiet, and still a square
	idle = { role = "contentSecondary", blend = 0.2 },
	-- an empty square this turn could still use
	legal = { role = "accent", blend = 0.3 },
	-- the starred centre, before anything covers it
	centre = { role = "accent", blend = 0.3 },
	-- a letter placed this turn and not yet committed
	pending = { role = "accent", blend = 0.6 },
	-- a letter from an earlier turn: settled, and no longer the player's to move
	committed = { role = "contentSecondary", blend = 0.5 },
}

--[[ ...AND THE STRUCTURE, which is the cue that survives a greyscale screen.

	`chip` is the theme's own small OUTLINED plate and `raised` is its solid
	panel, both drawn by the theme's chrome rules rather than by this file. So
	"is this letter mine to move" is a BORDER against a FILL, not two shades of
	one colour — the same ruling the word game's active row is under.

	WRITTEN AS LITERAL `surface` VALUES, which is not an accident: an enum prop
	accepts any string and silently paints nothing when it is not a member, and spelled this way
	`tools/lune/check_example_drift` checks every one of them against the Box
	surface enum the renderer actually resolves. ]]
local CELL_SURFACE: { [string]: string } = {
	idle = "plain",
	legal = "plain",
	centre = "plain",
	pending = "chip",
	committed = "raised",
}

-- ...and the same facts a THIRD time, without colour and without chrome. Plain
-- ASCII, because ASCII is the only range every Roblox font is guaranteed to
-- draw (the rule the framework's own icon fallbacks follow).
local CELL_MARK: { [string]: string } = {
	idle = "",
	legal = "+",
	centre = "*",
	pending = "~",
	committed = "",
}

-- ===========================================================================

function example.build(Facet: any, core: any, deps: any)
	local UI = Facet.UI
	local pres = deps.presenter
	local actions = deps.actionSystem

	-- gameScope owns everything this example creates, so dispose() returns the
	-- registries to exactly where they were before build().
	local gameScope = core:scope("example-06-tile-game")
	local function reg(readable: any): any
		gameScope:own(function()
			readable:dispose()
		end)
		return readable
	end

	-- ---- state --------------------------------------------------------------
	-- The bag and its cursor are PLAIN LOCALS, not signals: nothing on screen
	-- reads them, and a signal nobody binds is a subscription that costs and
	-- teaches nothing. Everything a player can see is below.
	local seedSig = reg(core:signal(DEFAULT_SEED))
	local boardSig = reg(core:signal({} :: { [string]: string }))
	local pendingSig = reg(core:signal({} :: { [string]: string }))
	-- rack slot -> letter. A slot emptied by a placement stays empty (and
	-- disabled) until the turn is committed or undone, so the rack never
	-- reshuffles under the player's finger.
	local rackSig = reg(core:signal({} :: { [number]: string }))
	-- which rack slot each placed tile came from, so Undo can put it back where
	-- it was rather than wherever there happens to be room
	local originSig = reg(core:signal({} :: { [string]: number }))
	local selectedSig = reg(core:signal(nil :: number?))
	local scoreSig = reg(core:signal(0))
	local turnSig = reg(core:signal(1))
	local phaseSig = reg(core:signal("playing")) -- "playing" | "won" | "lost"
	local noticeSig = reg(core:signal(""))

	local bag: { string } = {}
	local bagAt = 1
	local opening: string? = nil
	local dealAttempts = 0

	local function playing(): boolean
		return phaseSig:get() == "playing"
	end

	--[[ THE DEAL, and the reset. Everything the game can change is written back
		to the value it was constructed with — including the selection and the
		message, so a restart cannot leave a highlighted rack tile or a stale
		complaint behind. ]]
	local function restart(seed: number?)
		local nextSeed = if seed ~= nil then math.floor(seed) else seedSig:get()
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
		core:transaction(function()
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

	-- ---- commands (pure state; they know nothing about the view) ------------

	local function selectSlot(slot: number)
		if not playing() then
			return
		end
		if rackSig:get()[slot] == nil then
			return -- the slot is empty and its button is disabled; nothing to say
		end
		core:transaction(function()
			-- activating the held tile again puts it down, which is the only way
			-- back out of "holding" that does not need a second control
			selectedSig:set(if selectedSig:get() == slot then nil else slot)
			noticeSig:set("")
		end)
	end

	-- Activating a board square: place the held tile, or pick an uncommitted one
	-- back up. Every branch that cannot act says why.
	local function activateCell(r: number, c: number)
		if not playing() then
			return
		end
		if not rules.onBoard(r, c) then
			-- no rendered square exists off the board, so nothing a player can
			-- press reaches here; the guard keeps a scripted call equally inert
			return
		end
		local key = rules.key(r, c)
		local slot = selectedSig:get()
		local committed = boardSig:get()[key]
		local pendingLetter = pendingSig:get()[key]
		if slot == nil then
			if committed ~= nil then
				noticeSig:set(rules.SAY.committed)
				return
			end
			if pendingLetter ~= nil then
				-- put it back on the rack it came from
				local origin = table.clone(originSig:get())
				local rack = table.clone(rackSig:get())
				local pending = table.clone(pendingSig:get())
				rack[origin[key]] = pendingLetter
				pending[key] = nil
				origin[key] = nil
				core:transaction(function()
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
		local letter = rackSig:get()[slot]
		if letter == nil then
			return
		end
		local rack = table.clone(rackSig:get())
		local pending = table.clone(pendingSig:get())
		local origin = table.clone(originSig:get())
		rack[slot] = nil
		pending[key] = letter
		origin[key] = slot
		core:transaction(function()
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
		local pending = pendingSig:get()
		if next(pending) == nil then
			noticeSig:set(rules.SAY.nothingPlaced)
			return
		end
		local rack = table.clone(rackSig:get())
		local origin = originSig:get()
		for key, letter in pending do
			rack[origin[key]] = letter
		end
		core:transaction(function()
			rackSig:set(rack)
			pendingSig:set({})
			originSig:set({})
			selectedSig:set(nil)
			noticeSig:set("")
		end)
	end

	--[[ SUBMIT, and the whole point of the refusal contract: a turn the rules
		reject changes NOTHING. Not the board, not the rack, not the turn count,
		not the selection — so the player moves one tile and tries again rather
		than rebuilding the word from an empty rack. ]]
	local function submit()
		if not playing() then
			return
		end
		local board = boardSig:get()
		local pending = pendingSig:get()
		local verdict = rules.validate(board, pending, turnSig:get())
		if not verdict.ok then
			noticeSig:set(verdict.message)
			return
		end
		local nextBoard = table.clone(board)
		for key, letter in pending do
			nextBoard[key] = letter
		end
		-- refill from the bag, in slot order, so a seed replays exactly
		local rack = table.clone(rackSig:get())
		for slot = 1, RACK_SIZE do
			if rack[slot] == nil and bagAt <= #bag then
				rack[slot] = bag[bagAt]
				bagAt += 1
			end
		end
		local nextScore = scoreSig:get() + (verdict.score :: number)
		local nextTurn = turnSig:get() + 1
		local phase = "playing"
		if nextScore >= GOAL then
			phase = "won"
		elseif nextTurn > TURNS then
			phase = "lost"
		end
		core:transaction(function()
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

	-- ---- derived readouts ---------------------------------------------------
	local turnsLeft = reg(core:memo(function(use)
		return math.max(0, TURNS - (use(turnSig) - 1))
	end))

	local scoreText = reg(core:memo(function(use)
		return `{use(scoreSig)} of {GOAL} points`
	end))

	local progressText = reg(core:memo(function(use)
		local left = use(turnsLeft)
		return `{left} {if left == 1 then "turn" else "turns"} left`
	end))

	-- THE LIVE VERDICT. It is the same `rules.validate` the Submit button runs,
	-- asked every time the board changes — so the player reads the reason BEFORE
	-- they press, and a refused submit tells them nothing they were not already
	-- being told. That is the whole reason the rules are pure.
	local verdictSig = reg(core:memo(function(use)
		local pending = use(pendingSig)
		if next(pending) == nil then
			return nil
		end
		return rules.validate(use(boardSig), pending, use(turnSig))
	end))

	-- ONE MESSAGE LINE, not two. `notice` is what the player's last press did;
	-- when there is nothing to report it falls through to the live verdict, so
	-- the line always describes the board underneath it.
	local wordText = reg(core:memo(function(use)
		local notice = use(noticeSig)
		if notice ~= "" then
			return notice
		end
		local verdict = use(verdictSig)
		if verdict == nil then
			return "No tiles placed this turn."
		end
		return verdict.message
	end))

	-- ...and ONE INSTRUCTION LINE that always says what to do next.
	local hintText = reg(core:memo(function(use)
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
	end))

	-- ---- the board: ONE Grid of 49 squares ----------------------------------
	-- `UI.Grid` with a fixed column count is the container for a board, and it
	-- earns the 2D focus story with it: the focus map turns a Grid's focusables
	-- into per-row horizontal groups linked by up/down exits, so a D-pad or the
	-- arrow keys cross the board with no consumer navigation map.
	local cellStateOf: { [string]: any } = {}
	local cells = {}
	for r = 1, SIZE do
		for c = 1, SIZE do
			local rr, cc = r, c
			local key = rules.key(r, c)
			local state = reg(core:memo(function(use)
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
			end))
			cellStateOf[key] = state
			local label = reg(core:memo(function(use)
				return letterAt(use(boardSig), use(pendingSig), rr, cc) or ""
			end))
			local tint = reg(core:memo(function(use)
				return CELL_TINT[use(state)]
			end))
			local surface = reg(core:memo(function(use)
				return CELL_SURFACE[use(state)]
			end))
			local mark = reg(core:memo(function(use)
				return CELL_MARK[use(state)]
			end))
			table.insert(
				cells,
				UI.ZStack({
					id = `cell{r}_{c}`,
					width = CELL,
					height = CELL,
					alignH = "center",
					alignV = "center",
					children = {
						-- THE PLATE. A Box's one paint channel is `tint`, so this is
						-- where the state colour lives; `surface` beside it is the
						-- theme's own chrome, and the two do not fight — the tint is an
						-- explicit per-node claim on the fill, the surface is a tag the
						-- theme's border and corner rules hang off. It is a SEPARATE
						-- node from the button on top of it because a Button has no
						-- tint channel, and a plate nothing can measure is a plate
						-- nobody can prove is painted.
						UI.Box({ id = "plate", width = FILL, height = FILL, tint = tint, surface = surface }),
						UI.Text({
							id = "mark",
							text = mark,
							textSize = "caption",
							role = "secondary",
							alignH = "end",
							alignV = "end",
						}),
						-- ...and the interactive layer, LAST so it is the topmost node
						-- and takes the gesture (a GuiButton sinks input; whatever is
						-- under it gets nothing). `plain` is the explicit declaration
						-- that it paints no plate of its own, so the Box below shows
						-- through — without it every theme falls a Button through to
						-- its `control` slot and paints one anyway.
						UI.Button({
							id = "tap",
							label = label,
							surface = "plain",
							padding = 0,
							width = FILL,
							height = FILL,
							textSize = "control",
							-- APP SEMANTICS on the node: activating a square (tap, or
							-- Return/A on the focused square) places the held tile. The
							-- presenter dispatches Activate with no consumer routing; select-then-place is the app's own rule.
							onActivate = function()
								activateCell(rr, cc)
							end,
						}),
					},
				})
			)
		end
	end
	local board = UI.Grid({
		id = "board",
		columns = SIZE,
		itemSizing = "uniform",
		gap = "xs",
		rowGap = "xs",
		children = cells,
	})

	-- ---- rack: one button per slot ------------------------------------------
	-- A slot emptied onto the board keeps its place and is DISABLED with a spent
	-- marker, rather than being a blank button that looks pressable and silently
	-- does nothing.
	local rackTiles = {}
	for i = 1, RACK_SIZE do
		local slot = i
		local letter = reg(core:memo(function(use)
			return use(rackSig)[slot]
		end))
		local label = reg(core:memo(function(use)
			return use(letter) or "·"
		end))
		local enabled = reg(core:memo(function(use)
			return use(letter) ~= nil and use(phaseSig) == "playing"
		end))
		local isSelected = reg(core:memo(function(use)
			return use(selectedSig) == slot
		end))
		rackTiles[i] = UI.Button({
			id = "rt" .. i,
			label = label,
			enabled = enabled,
			selected = isSelected,
			width = CELL,
			height = CELL,
			textSize = "control",
			-- APP SEMANTICS: activating a rack tile picks that slot up, and
			-- activating the held one puts it down again.
			onActivate = function()
				selectSlot(slot)
			end,
		})
	end
	local rack = UI.Grid({
		id = "rack",
		columns = RACK_SIZE,
		itemSizing = "uniform",
		gap = "xs",
		children = rackTiles,
	})

	-- ---- the screen ---------------------------------------------------------
	local screen = UI.Screen({
		id = "TileGame",
		-- `surface = "base"` so the tutorial reads as a screen rather than loose
		-- text floating over whatever 3D world the place happens to have.
		surface = "base",
		padding = "m",
		children = {
			-- A 7x7 board plus a rack plus three lines of copy is tall: the page
			-- is a ScrollView so a short landscape phone can still reach Submit.
			UI.ScrollView({
				id = "Page",
				axis = "y",
				gap = "s",
				width = FILL,
				height = FILL,
				children = {
					UI.Text({ id = "Title", text = "Facet Crossword", textSize = "title" }),
					-- THE GOAL AND THE BUDGET IN ONE LINE, and it WRAPS. As a plain
					-- HStack the two readouts needed 307px of row and the page's
					-- padded width at 320x640 is 280, so the line simply painted past
					-- its own box. `UI.Grid` with `minColumnWidth = "intrinsic"` is
					-- the declarative form of "side by side where they fit, stacked
					-- where they do not": the column count is derived from the widest
					-- child's own measured width under the ACTIVE theme's font, every
					-- solve — two columns on a phone, one on a 320px phone, and no
					-- viewport arithmetic to keep in sync.
					--
					-- NOT `UI.ViewThatFits`. A candidate ladder would need each
					-- readout written TWICE and the framework keeps the losing
					-- candidate mounted at a deliberate zero rect — so half the
					-- declared content is unreachable at every viewport and both
					-- copies answer `adapter.node(...)` identically. The readouts stay
					-- DIRECT children here, at the paths this example has always
					-- published, which is what tests/example_readouts.spec.luau pins.
					UI.Grid({
						id = "Stats",
						minColumnWidth = "intrinsic",
						gap = "s",
						width = FILL,
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
					UI.Text({ id = "Hint", text = hintText, textSize = "body", role = "secondary" }),
					UI.Text({ id = "Word", text = wordText, textSize = "label" }),
					board,
					UI.Text({ id = "RackLabel", text = "Your rack", textSize = "label", role = "secondary" }),
					rack,
					-- The two turn verbs. A Grid for the same reason the stats line is
					-- one: two full-sentence buttons do not fit a 320px row, and a
					-- derived column count stacks them there without a viewport test.
					UI.Grid({
						id = "Actions",
						minColumnWidth = "intrinsic",
						gap = "s",
						width = FILL,
						children = {
							UI.Button({ id = "Submit", label = "Submit word", onActivate = submit }),
							UI.Button({ id = "Undo", label = "Undo turn", onActivate = undo }),
						},
					}),
					UI.Button({
						id = "Reset",
						label = "Start over",
						onActivate = function()
							restart(DEFAULT_SEED)
						end,
					}),
				},
			}),
		},
	})

	-- Presented with NO opts: each square, rack tile and action carries its own
	-- Activate handler, and the presenter derives 2D grid navigation from the two
	-- Grids automatically (layout-derived groups) — so a D-pad crosses
	-- the board and A places, with no consumer wiring.
	local handle = pres.present(screen)

	--[[ THE HARDWARE-LETTER CONVENIENCE, and what it is NOT.

		With a board square focused, typing a letter that is on the rack places it
		there. That is a shortcut ON TOP OF select-then-place, never the only way
		in: every action in this game is reachable by pointer, touch, keyboard and
		gamepad through the Activate path alone, which is what the four-input
		requirement is met by. Navigation keys are deliberately NOT bound, so the
		arrows and the D-pad still fall through to the presenter's own grid
		navigation. ]]
	local focusedCell = function(): (number?, number?)
		local path = pres.focus.focused:get()
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
		local rack = rackSig:get()
		for slot = 1, RACK_SIZE do
			if rack[slot] == letter then
				selectedSig:set(slot)
				activateCell(r :: number, c :: number)
				return
			end
		end
		noticeSig:set(`There is no {letter} on your rack.`)
	end

	local ctx = actions.createContext({ name = "CrosswordInput", priority = 2000, sink = true })
	gameScope:own(function()
		ctx.destroy()
	end)
	for i = 0, 25 do
		local letter = string.char(65 + i)
		local action = ctx.createAction("Type_" .. letter, "Bool")
		action.bind({ keyCode = letter })
		action.onPressed(function()
			typeLetter(letter)
		end)
	end

	-- ---- public / test API --------------------------------------------------
	return {
		title = example.title,
		screen = screen,
		handle = handle,
		rules = rules,

		-- fire a hardware key through the arbitrated action pipeline
		press = function(keyCode: string)
			actions.deviceKey(keyCode, true)
			actions.deviceKey(keyCode, false)
		end,

		-- commands, at the same door the buttons use
		select = selectSlot,
		place = activateCell,
		submit = submit,
		undo = undo,
		reset = function(seed: number?)
			restart(seed or DEFAULT_SEED)
		end,

		-- observables
		seed = function(): number
			return seedSig:get()
		end,
		opening = function(): string?
			return opening
		end,
		dealAttempts = function(): number
			return dealAttempts
		end,
		letterAt = function(r: number, c: number): string?
			return letterAt(boardSig:get(), pendingSig:get(), r, c)
		end,
		committedAt = function(r: number, c: number): string?
			return boardSig:get()[rules.key(r, c)]
		end,
		pendingAt = function(r: number, c: number): string?
			return pendingSig:get()[rules.key(r, c)]
		end,
		cellState = function(r: number, c: number): string
			return cellStateOf[rules.key(r, c)]:get()
		end,
		cellTint = function(r: number, c: number): any
			return CELL_TINT[cellStateOf[rules.key(r, c)]:get()]
		end,
		cellSurface = function(r: number, c: number): string
			return CELL_SURFACE[cellStateOf[rules.key(r, c)]:get()]
		end,
		cellMark = function(r: number, c: number): string
			return CELL_MARK[cellStateOf[rules.key(r, c)]:get()]
		end,
		rackLetter = function(slot: number): string?
			return rackSig:get()[slot]
		end,
		rackCount = function(): number
			local n = 0
			for slot = 1, RACK_SIZE do
				if rackSig:get()[slot] ~= nil then
					n += 1
				end
			end
			return n
		end,
		selected = function(): number?
			return selectedSig:get()
		end,
		score = function(): number
			return scoreSig:get()
		end,
		turn = function(): number
			return turnSig:get()
		end,
		turnsLeft = function(): number
			return turnsLeft:get()
		end,
		phase = function(): string
			return phaseSig:get()
		end,
		hintText = function(): string
			return hintText:get()
		end,
		wordText = function(): string
			return wordText:get()
		end,
		scoreText = function(): string
			return scoreText:get()
		end,
		progressText = function(): string
			return progressText:get()
		end,
		verdict = function(): any
			return verdictSig:get()
		end,
		-- ONE string that carries every observable a replay has to reproduce, so
		-- "the same seed and the same script land on the same game" is a single
		-- comparison rather than twenty
		dump = function(): string
			local out: { string } = {}
			for r = 1, SIZE do
				local row: { string } = {}
				for c = 1, SIZE do
					table.insert(row, letterAt(boardSig:get(), pendingSig:get(), r, c) or ".")
				end
				table.insert(out, table.concat(row))
			end
			local rack: { string } = {}
			for slot = 1, RACK_SIZE do
				table.insert(rack, rackSig:get()[slot] or ".")
			end
			return table.concat(out, "/")
				.. `|rack={table.concat(rack)}|score={scoreSig:get()}|turn={turnSig:get()}|phase={phaseSig:get()}`
		end,

		-- paths
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

		dispose = function()
			pres.dismiss(handle)
			gameScope:dispose()
		end,
	}
end

return example
