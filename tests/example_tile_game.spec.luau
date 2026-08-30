--!strict
-- The crossword tile game's PURE rules, its turn loop, and what it paints.
--
-- Three halves, deliberately separated:
--   1. `example.rules` — the bag, the deal, the axis, the run, the words a turn
--      creates and what they score. A board and a placement in, a verdict out:
--      no signals, no adapter, no presenter, so every rule in the design and
--      every one of its nine refusals is a headless test rather than a Studio
--      session. That separation is also what keeps the crossword out of `src/`.
--   2. the built game — select-then-place, commit and refill, undo, a refused
--      submit that changes NOTHING, the turn budget, both endings, restart, and
--      a seeded replay that lands on an identical board.
--   3. PAINT — every one of the forty-nine cells is visible against the page it
--      sits on in every shipped theme, and the committed/uncommitted cue
--      survives with colour ignored. A rules test structurally cannot reach
--      either.
--
-- The MOUNTED four-input paths (pointer/touch/keyboard/gamepad) live in
-- tests/examples_games.spec.luau beside the other two games; this file owns the
-- rules, the machine and the plates.
--
-- THE WORD DATA ITSELF IS NOT RE-PROVEN HERE. Its counts, its sortedness, its
-- provenance hashes and its bisection are `tests/example_word_data.spec.luau`;
-- this file only asks whether the GAME asks it the right questions.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local worldLib = require("./lib/world")
local sheet_model = require("../src/tokens/sheet_model")
local tokens = require("../src/tokens/tokens")
local words = require("../examples/gallery/examples/words")
local tileGame = require("../examples/gallery/examples/06_tile_game")

local rules = tileGame.rules

--[[ ON THE SHARED SUBSTRATE, because R12's trigger says so: "the next spec file
	that ADDS a builder migrates its file instead". This file was one of two that
	added one, and `tests/world_substrate.spec.luau` counted them.

	What the substrate buys here is not tidiness. Its keyword-only options table
	cannot transpose the adapter and the action system — the collision that
	commissioned it, where Luau binds an action system to a variable called
	`adapter` without a word and the spec fails three edits later in a file nobody
	touched. It also sets `viewportRect` BEFORE the presenter exists, so no solve
	ever runs against an unset 1x1 viewport. ]]
local function makeWorld(viewport: any?)
	local w = worldLib.new({ viewport = viewport or { x = 0, y = 0, w = 800, h = 600 } })
	local deps = { env = w.env, actionSystem = w.system, presenter = w.pres, adapter = w.adapter }
	return w.core, deps, w.adapter
end

local function newGame(core: any, deps: any): any
	return tileGame.build(Facet, core, deps)
end

-- A board written as seven strings, because a crossword rule is about a PICTURE
-- and a picture argues with a reader better than fourteen table entries.
local function boardOf(rows: { string }): { [string]: string }
	local out: { [string]: string } = {}
	for r, row in rows do
		for c = 1, #row do
			local ch = string.sub(row, c, c)
			if ch ~= "." then
				out[rules.key(r, c)] = ch
			end
		end
	end
	return out
end

local function placedOf(list: { { any } }): { [string]: string }
	local out: { [string]: string } = {}
	for _, move in list do
		out[rules.key(move[1] :: number, move[2] :: number)] = move[3] :: string
	end
	return out
end

local EMPTY = boardOf({ ".......", ".......", ".......", ".......", ".......", ".......", "......." })

--[[ THE WORKED GAME, and why it is written out rather than searched for.

	Seed 20260829 deals EDAIREE, and this script is a real playthrough of it:
	EARED across the centre row, IODIDE down the fifth column THROUGH the D that
	turn one committed, QUALIA across row two (crossing that same column at its
	I), and NIPS across row five through the I. Four turns, 67 points, three
	five-tile bonuses.

	It is a LITERAL because that is what makes it evidence: a script the test
	computes is a script that agrees with whatever the rules currently do. Each
	entry is { rack slot, row, column } and the slots are the ones the seeded
	deal and its refills actually hand out — so if the bag, the shuffle, the
	refill order or any rule moves, this stops being a legal game and says so. ]]
local WIN_SCRIPT: { { { number } } } = {
	{ { 1, 4, 1 }, { 3, 4, 2 }, { 5, 4, 3 }, { 6, 4, 4 }, { 2, 4, 5 } }, -- EARED, +16
	{ { 4, 2, 5 }, { 3, 3, 5 }, { 6, 5, 5 }, { 2, 6, 5 }, { 7, 7, 5 } }, -- IODIDE, +18
	{ { 1, 2, 1 }, { 4, 2, 2 }, { 5, 2, 3 }, { 6, 2, 4 }, { 7, 2, 6 } }, -- QUALIA, +25
	{ { 2, 5, 4 }, { 1, 5, 6 }, { 6, 5, 7 } }, -- NIPS, +8 -> 67, won
}

-- ...and the same seed played for the smallest legal word every turn, which
-- spends the whole budget and loses. Two-letter words, one or two tiles a turn.
local LOSS_SCRIPT: { { { number } } } = {
	{ { 1, 4, 3 }, { 5, 4, 4 } }, -- ER
	{ { 6, 3, 4 } }, -- ER (downward)
	{ { 3, 4, 5 } }, -- ERA
	{ { 4, 5, 5 } }, -- AI
	{ { 2, 5, 6 } }, -- ID
	{ { 2, 5, 3 } }, -- EN
}

local function play(game: any, script: { { { number } } }, upTo: number?)
	for turn, moves in script do
		if upTo ~= nil and turn > upTo then
			return
		end
		for _, move in moves do
			game.select(move[1])
			game.place(move[2], move[3])
		end
		game.submit()
	end
end

-- ===========================================================================
-- THE PURE RULES
-- ===========================================================================
describe("examples/06 crossword — the rules are pure", function()
	it("the board, the rack, the budget and the goal are the design's numbers", function()
		expect(rules.SIZE).toBe(7)
		expect(rules.CENTRE).toBe(4)
		expect(rules.RACK_SIZE).toBe(7)
		expect(rules.TURNS).toBe(6)
		expect(rules.GOAL).toBe(60)
		expect(rules.BONUS_TILES).toBe(5)
		expect(rules.BONUS).toBe(10)
	end)

	it("the letter values are the familiar English ones", function()
		-- a player already knows Z is worth more than E, and does not need to be
		-- taught a distribution this game invented
		for _, letter in { "A", "E", "I", "O", "U", "N", "R", "S", "T", "L" } do
			expect(rules.value(letter)).toBe(1)
		end
		for _, letter in { "D", "G" } do
			expect(rules.value(letter)).toBe(2)
		end
		for _, letter in { "B", "C", "M", "P" } do
			expect(rules.value(letter)).toBe(3)
		end
		for _, letter in { "F", "H", "V", "W", "Y" } do
			expect(rules.value(letter)).toBe(4)
		end
		expect(rules.value("K")).toBe(5)
		expect(rules.value("J")).toBe(8)
		expect(rules.value("X")).toBe(8)
		expect(rules.value("Q")).toBe(10)
		expect(rules.value("Z")).toBe(10)
	end)

	it("the bag is the 98-tile familiar multiset, with no blanks", function()
		local total = 0
		for _, entry in rules.DISTRIBUTION do
			total += entry[2] :: number
		end
		expect(total).toBe(98)
		local bag = rules.newBag(rules.makeRng(1))
		expect(#bag).toBe(98)
		-- and it holds only letters this game can score: a blank would be a rule
		-- the player has to learn before the first move (design §8)
		for _, letter in bag do
			expect(rules.value(letter) > 0).toBe(true)
		end
	end)
end)

describe("examples/06 crossword — axis, run and connection", function()
	it("a turn's tiles lie in one row or one column, and scattered tiles are refused", function()
		local across = rules.validate(EMPTY, placedOf({ { 4, 3, "C" }, { 4, 4, "A" }, { 4, 5, "T" } }), 1)
		expect(across.ok).toBe(true)
		expect(across.axis).toBe("row")
		local down = rules.validate(EMPTY, placedOf({ { 3, 4, "C" }, { 4, 4, "A" }, { 5, 4, "T" } }), 1)
		expect(down.ok).toBe(true)
		expect(down.axis).toBe("col")
		local scattered = rules.validate(EMPTY, placedOf({ { 4, 4, "C" }, { 5, 5, "A" } }), 1)
		expect(scattered.ok).toBe(false)
		expect(scattered.code).toBe("axis")
		expect(scattered.message).toBe(rules.SAY.axis)
	end)

	it("ONE tile does not fix an axis — the board does", function()
		--[[ The design is explicit: "The very first tile of a turn does not fix an
			axis; the second one does." So a lone tile is read against what is
			already there — a tile that extends a column and not a row is a column
			word, a tile that extends a row is a row word, and a tile at a crossing
			is read across with the column as its crossing word. ]]
		local column = boardOf({ ".......", ".......", "...C...", "...A...", ".......", ".......", "......." })
		local extendsDown = rules.validate(column, placedOf({ { 5, 4, "T" } }), 2)
		expect(extendsDown.ok).toBe(true)
		expect(extendsDown.axis).toBe("col")
		expect((extendsDown.made :: any)[1].word).toBe("CAT")

		local row = boardOf({ ".......", ".......", ".......", "..CA...", ".......", ".......", "......." })
		local extendsAcross = rules.validate(row, placedOf({ { 4, 5, "T" } }), 2)
		expect(extendsAcross.ok).toBe(true)
		expect(extendsAcross.axis).toBe("row")
		expect((extendsAcross.made :: any)[1].word).toBe("CAT")

		-- a lone tile at a crossing makes TWO words, and both are validated
		local cross = boardOf({ ".......", ".......", "...D...", "..D.G..", "...N...", ".......", "......." })
		local both = rules.validate(cross, placedOf({ { 4, 4, "O" } }), 2)
		expect(both.ok).toBe(true)
		expect(both.axis).toBe("row")
		expect(#(both.made :: any)).toBe(2)
		expect((both.made :: any)[1].word).toBe("DOG")
		expect((both.made :: any)[2].word).toBe("DON")
	end)

	it("a gap in the run is refused, and a gap CLOSED by a committed letter is not", function()
		local centred = boardOf({ ".......", ".......", ".......", "...A...", ".......", ".......", "......." })
		-- C _ _ T with nothing in the middle: two of the four squares are empty
		local holed = rules.validate(centred, placedOf({ { 4, 2, "C" }, { 4, 6, "T" } }), 2)
		expect(holed.ok).toBe(false)
		expect(holed.code).toBe("gap")
		expect(holed.message).toBe(rules.SAY.gap)
		-- ...and the same two tiles either side of the committed A ARE one run
		local closed = rules.validate(centred, placedOf({ { 4, 3, "C" }, { 4, 5, "T" } }), 2)
		expect(closed.ok).toBe(true)
		expect((closed.made :: any)[1].word).toBe("CAT")
	end)

	it("the main word is read THROUGH committed letters at both ends", function()
		-- C and T are already on the board; the turn places only the A between
		-- them, and the word the turn made is the whole run, not the one tile
		local ends = boardOf({ ".......", ".......", ".......", "..C.T..", ".......", ".......", "......." })
		local verdict = rules.validate(ends, placedOf({ { 4, 4, "A" } }), 2)
		expect(verdict.ok).toBe(true)
		expect((verdict.made :: any)[1].word).toBe("CAT")
		-- ...and every letter in it is paid for, committed ones included: C 3 + A 1 + T 1
		expect(verdict.score).toBe(5)
	end)

	it("the first turn must cover the starred centre, and later turns must not", function()
		local offCentre = rules.validate(EMPTY, placedOf({ { 2, 2, "C" }, { 2, 3, "A" }, { 2, 4, "T" } }), 1)
		expect(offCentre.ok).toBe(false)
		expect(offCentre.code).toBe("centre")
		expect(offCentre.message).toBe(rules.SAY.centre)
		-- the same three tiles one square to the right DO cover (4,4)
		local onCentre = rules.validate(EMPTY, placedOf({ { 4, 3, "C" }, { 4, 4, "A" }, { 4, 5, "T" } }), 1)
		expect(onCentre.ok).toBe(true)
		-- ...and after turn one the centre is not asked about at all: this turn
		-- puts nothing on (4,4) and is accepted
		local later = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })
		local away = rules.validate(later, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
		expect(away.ok).toBe(true)
		expect(away.axis).toBe("row")
	end)

	it("connection is ORTHOGONAL: touching diagonally is not touching", function()
		local seeded = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })
		-- (5,3) shares an edge with the D directly above it
		local orthogonal = rules.validate(seeded, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
		expect(orthogonal.ok).toBe(true)
		-- (6,6) and (6,7) share an edge with nothing at all
		local floating = rules.validate(seeded, placedOf({ { 6, 6, "A" }, { 6, 7, "N" } }), 2)
		expect(floating.ok).toBe(false)
		expect(floating.code).toBe("connect")
		expect(floating.message).toBe(rules.SAY.connect)
		-- ...and DIAGONAL contact is still no contact: (5,6) is corner-to-corner
		-- with the N at (4,5) and shares an edge with nothing.
		local diagonal = rules.validate(seeded, placedOf({ { 5, 6, "A" }, { 5, 7, "N" } }), 2)
		expect(diagonal.ok).toBe(false)
		expect(diagonal.code).toBe("connect")
	end)
end)

describe("examples/06 crossword — every word a turn creates", function()
	-- The board for the crossing cases: DON already committed across row four.
	local DON = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })

	it("every perpendicular word a placed tile now sits inside is extracted and validated", function()
		--   . . D O N . .
		--   . . O N E . .
		-- three tiles placed, FOUR words made: the main run plus one crossing per
		-- tile, and all four have to be real.
		local verdict = rules.validate(DON, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
		expect(verdict.ok).toBe(true)
		local made = verdict.made :: any
		expect(#made).toBe(4)
		expect(made[1].word).toBe("ONE")
		expect(made[1].axis).toBe("row")
		expect(made[2].word).toBe("DO")
		expect(made[3].word).toBe("ON")
		expect(made[4].word).toBe("NE")
		for i = 2, 4 do
			expect(made[i].axis).toBe("col")
		end
	end)

	it("a crossing word the dictionary does not know refuses the whole turn, BY NAME", function()
		-- DOG across row four; ONE under it makes DO and ON (both real) and GE,
		-- which is not. The first two crossings passing is the point: the check
		-- is every crossing, not the first one.
		local dog = boardOf({ ".......", ".......", ".......", "..DOG..", ".......", ".......", "......." })
		local verdict = rules.validate(dog, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
		expect(verdict.ok).toBe(false)
		expect(verdict.code).toBe("unknownCrossing")
		expect(verdict.word).toBe("GE")
		expect(verdict.message).toBe("That would make GE downward, and that isn't a word this game knows.")
		-- ...and the direction is named from the CROSSING's axis, not the turn's:
		-- a turn built down a column makes its crossings across.
		expect(rules.sayUnknownCrossing("QXZ", "row")).toBe(
			"That would make QXZ across, and that isn't a word this game knows."
		)
	end)

	it("the score counts every letter in every word, once per word it appears in", function()
		local verdict = rules.validate(DON, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
		-- ONE 1+1+1 = 3, DO 2+1 = 3, ON 1+1 = 2, NE 1+1 = 2  ->  10
		expect(verdict.score).toBe(10)
		expect(verdict.bonus).toBe(0)
		local made = verdict.made :: any
		expect(made[1].score).toBe(3)
		expect(made[2].score).toBe(3)
		expect(made[3].score).toBe(2)
		expect(made[4].score).toBe(2)
		-- the O the turn placed at (5,3) is paid for TWICE — once in ONE and once
		-- in DO — because it is doing two jobs. The committed D is paid once.
		expect(made[1].score + made[2].score + made[3].score + made[4].score).toBe(verdict.score)
	end)

	it("using five or more rack tiles in one turn adds ten", function()
		local four = rules.validate(EMPTY, placedOf({ { 4, 3, "H" }, { 4, 4, "E" }, { 4, 5, "N" }, { 4, 6, "S" } }), 1)
		expect(four.ok).toBe(true)
		expect(four.tiles).toBe(4)
		expect(four.bonus).toBe(0)
		expect(four.score).toBe(4 + 1 + 1 + 1) -- H4 E1 N1 S1

		local five = rules.validate(
			EMPTY,
			placedOf({ { 4, 2, "E" }, { 4, 3, "A" }, { 4, 4, "R" }, { 4, 5, "E" }, { 4, 6, "D" } }),
			1
		)
		expect(five.ok).toBe(true)
		expect(five.tiles).toBe(5)
		expect(five.bonus).toBe(10)
		expect(five.score).toBe(1 + 1 + 1 + 1 + 2 + 10)
		-- and the bonus is visible in the sentence the player reads
		expect(string.find(five.message, "+10 for using 5 tiles", 1, true) ~= nil).toBe(true)
	end)
end)

describe("examples/06 crossword — the dictionary is the shared module", function()
	it("accepts and rejects through `words`, not through a list this game keeps", function()
		-- every word the worked game plays, and every one of them is far outside
		-- the thirty-four-entry hand-written list the sibling example used to ship
		for _, word in { "EARED", "IODIDE", "QUALIA", "NIPS", "DON", "QI" } do
			expect(rules.wordVerdict(word)).toBe("ok")
			expect(words.isWord(word)).toBe(true)
		end
		expect(rules.wordVerdict("PLZTK")).toBe("unknown")
		expect(rules.wordVerdict("A")).toBe("unknown") -- one letter is not a word
	end)

	it("a run the dictionary CANNOT judge is refused by name, not called unknown", function()
		--[[ The shared data carries lengths two to seven, so an eight-letter run
			is a question it cannot answer — and answering it "that isn't a word"
			would be a claim the game is not entitled to make (design §8). The
			board is seven wide, so this is unreachable through ordinary play and
			the seam is driven directly; it exists so that a wider board, or a
			regenerated dictionary, cannot quietly start lying. ]]
		expect(words.isWord("ELEPHANT")).toBe(false) -- what the naive path would see
		expect(rules.wordVerdict("ELEPHANT")).toBe("long") -- what this game says instead
		expect(rules.SAY.long).toBe("This game only knows words up to seven letters long.")
		expect(rules.MAX_WORD).toBe(words.MAX_LENGTH)
		-- ...and the run a 7x7 board can produce never exceeds it, which is why no
		-- placement in this file can reach the message
		expect(rules.SIZE <= words.MAX_LENGTH).toBe(true)
	end)
end)

describe("examples/06 crossword — the deal guarantees an opening", function()
	it("the shipped seed deals a rack that spells something across the centre", function()
		local dealt = rules.deal(rules.makeRng(rules.DEFAULT_SEED))
		expect(#dealt.rack).toBe(7)
		expect(dealt.opening ~= nil).toBe(true)
		expect(#(dealt.opening :: string) >= rules.MIN_WORD).toBe(true)
		expect(words.isWord(dealt.opening :: string)).toBe(true)
	end)

	it("...and so does every seed in a wide sweep, inside the attempt bound", function()
		-- the same guarantee 07_match3's deal() makes for its legal opening move.
		-- A rack that spells nothing is a game the player cannot start and cannot
		-- see is unstartable.
		local worst = 0
		for seed = 1, 200 do
			local dealt = rules.deal(rules.makeRng(seed))
			if dealt.opening == nil then
				error(`seed {seed} dealt {table.concat(dealt.rack)} with no opening word`, 2)
			end
			worst = math.max(worst, dealt.attempts)
		end
		expect(worst <= rules.DEAL_ATTEMPTS).toBe(true)
		-- 93 two-letter words in the bank makes the first shuffle almost always
		-- enough; a bound that is regularly spent would mean the check is wrong
		expect(worst <= 3).toBe(true)
	end)

	it("openingWord finds a word from a SUBSET in any order, and nil when there is none", function()
		expect(rules.openingWord({ "T", "A", "C" }) ~= nil).toBe(true)
		expect(rules.openingWord({ "C", "A", "T", "X", "Z", "Q", "V" }) ~= nil).toBe(true)
		expect(rules.openingWord({ "V", "V", "V" })).toBeNil()
	end)
end)

-- ===========================================================================
-- THE NINE REFUSALS, EACH ON SCREEN
-- ===========================================================================
--[[ "The rule fired" and "the player was told" are different claims, and only
	the second one is the lesson. Every case below reads the sentence off the
	RENDERED node, not off the model, because a message the tree does not carry
	is a message nobody receives. ]]
describe("examples/06 crossword — nine refusals, nine sentences, on screen", function()
	local function said(game: any, deps: any, adapter: any): string
		deps.presenter.refresh()
		return adapter.node(game.wordPath).props.text
	end

	local function hint(game: any, deps: any, adapter: any): string
		deps.presenter.refresh()
		return adapter.node(game.hintPath).props.text
	end

	it("1 — the first turn misses the centre", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		-- a legal two-letter run in row 1, nowhere near the star
		game.select(1)
		game.place(1, 1)
		game.select(2)
		game.place(1, 2)
		game.submit()
		expect(said(game, deps, adapter)).toBe("Your first word has to cover the starred centre square.")
		expect(game.turn()).toBe(1)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("2 — the tiles are not in one line", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.select(1)
		game.place(4, 4)
		game.select(2)
		game.place(5, 5)
		game.submit()
		expect(said(game, deps, adapter)).toBe("The tiles you place in a turn go in a single row or a single column.")
		game.dispose()
	end)

	it("3 — a gap in the run", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.select(1)
		game.place(4, 4)
		game.select(2)
		game.place(4, 7)
		game.submit()
		expect(said(game, deps, adapter)).toBe(
			"Leave no gaps — your tiles and the letters already on the board have to make one unbroken run."
		)
		game.dispose()
	end)

	it("4 — a later turn touches nothing", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 1)
		expect(game.turn()).toBe(2)
		-- two tiles in the last row, a clear square away from everything
		game.select(1)
		game.place(7, 1)
		game.select(2)
		game.place(7, 2)
		game.submit()
		expect(said(game, deps, adapter)).toBe(
			"After the first turn, a word has to touch a letter already on the board."
		)
		game.dispose()
	end)

	it("5 — the main word is unknown, and the sentence names it", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		-- the seeded rack is EDAIREE; E-D-A across the centre is not a word
		game.select(1)
		game.place(4, 4)
		game.select(2)
		game.place(4, 5)
		game.select(3)
		game.place(4, 6)
		game.submit()
		expect(said(game, deps, adapter)).toBe("EDA isn't a word this game knows.")
		-- ...and the design's own example sentence is the same shape
		expect(rules.sayUnknown("PLZTK")).toBe("PLZTK isn't a word this game knows.")
		game.dispose()
	end)

	it("6 — a crossing word is unknown, and the sentence names it AND its direction", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 1) -- EARED across row 4; the refilled rack is QDOIAIE
		-- AI under the E and the A makes a real MAIN word and two crossings, and
		-- the first of them — EA, down column one — is not a word
		game.select(5)
		game.place(5, 1)
		game.select(4)
		game.place(5, 2)
		game.submit()
		expect(said(game, deps, adapter)).toBe("That would make EA downward, and that isn't a word this game knows.")
		-- ...and the turn is untouched: the two tiles are still where they were
		expect(game.pendingAt(5, 1)).toBe("A")
		expect(game.pendingAt(5, 2)).toBe("I")
		expect(game.turn()).toBe(2)
		game.dispose()
	end)

	it("7 — submit with nothing placed", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.submit()
		expect(said(game, deps, adapter)).toBe("Place at least one tile before you submit.")
		game.dispose()
	end)

	it("8 — placing on an occupied square", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.select(1)
		game.place(4, 4)
		game.select(2)
		game.place(4, 4)
		expect(said(game, deps, adapter)).toBe("That square already has a letter.")
		-- ...and the tile is still held, so the player can put it somewhere else
		expect(game.selected()).toBe(2)
		game.dispose()
	end)

	it("9 — picking up a letter from an earlier turn", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 1)
		expect(game.committedAt(4, 1)).toBe("E")
		game.place(4, 1) -- nothing held, and that square is not this turn's
		expect(said(game, deps, adapter)).toBe("Letters from an earlier turn stay put.")
		expect(game.committedAt(4, 1)).toBe("E")
		game.dispose()
	end)

	it("...and an uncommitted tile CAN be picked back up, which is what makes 9 a rule", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local letter = game.rackLetter(1)
		game.select(1)
		game.place(4, 4)
		expect(game.pendingAt(4, 4)).toBe(letter)
		expect(game.rackLetter(1)).toBeNil()
		game.place(4, 4) -- nothing held, and this square IS this turn's
		expect(game.pendingAt(4, 4)).toBeNil()
		expect(game.rackLetter(1)).toBe(letter) -- back in the slot it came from
		expect(said(game, deps, adapter)).toBe("No tiles placed this turn.")
		game.dispose()
	end)

	it("...and tapping an empty square with nothing held explains itself too", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.place(1, 1)
		expect(said(game, deps, adapter)).toBe("Pick a letter from your rack first, then choose a square.")
		-- the INSTRUCTION line is not the message line: it goes on saying what to
		-- do, which on turn one is still "cover the star"
		expect(hint(game, deps, adapter)).toBe("Cover the starred square with a word to begin.")
		game.dispose()
	end)

	it("the instruction line names the held tile, and clears on a placement", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		expect(hint(game, deps, adapter)).toBe("Cover the starred square with a word to begin.")
		local letter = game.rackLetter(1)
		game.select(1)
		expect(hint(game, deps, adapter)).toBe(`Placing {letter} — choose a square.`)
		game.place(4, 4)
		expect(hint(game, deps, adapter)).toBe("Cover the starred square with a word to begin.")
		expect(said(game, deps, adapter)).toBe(`{letter} isn't a word this game knows.`)
		game.dispose()
	end)
end)

-- ===========================================================================
-- THE TURN LOOP
-- ===========================================================================
describe("examples/06 crossword — commit, refill, undo, budget", function()
	it("a committed turn scores, banks the letters, and refills the rack to seven", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 1)
		expect(game.score()).toBe(16)
		expect(game.committedAt(4, 1)).toBe("E")
		expect(game.committedAt(4, 5)).toBe("D")
		expect(game.pendingAt(4, 1)).toBeNil()
		expect(game.rackCount()).toBe(7)
		-- the refill came from the bag, in slot order, so the five spent slots
		-- hold five NEW letters rather than the five that were played
		expect(game.turn()).toBe(2)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("undo returns exactly the uncommitted tiles, to the slots they came from", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 1)
		local before = game.dump()
		local rackBefore = {}
		for slot = 1, 7 do
			rackBefore[slot] = game.rackLetter(slot)
		end
		-- place three of turn two's tiles, then take them all back
		game.select(4)
		game.place(2, 5)
		game.select(3)
		game.place(3, 5)
		game.select(6)
		game.place(5, 5)
		expect(game.rackCount()).toBe(4)
		game.undo()
		expect(game.rackCount()).toBe(7)
		for slot = 1, 7 do
			expect(game.rackLetter(slot)).toBe(rackBefore[slot])
		end
		expect(game.dump()).toBe(before)
		-- ...and the axis is unlocked: a turn built the OTHER way is legal again
		expect(game.selected()).toBeNil()
		game.select(4)
		game.place(3, 4)
		expect(game.pendingAt(3, 4) ~= nil).toBe(true)
		game.dispose()
	end)

	it("undo with nothing placed says so instead of doing nothing", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.undo()
		deps.presenter.refresh()
		expect(adapter.node(game.wordPath).props.text).toBe("Nothing to undo — you have not placed a tile this turn.")
		game.dispose()
	end)

	it("A REFUSED SUBMIT CHANGES NOTHING — every tile stays where the player put it", function()
		--[[ The whole point of the refusal contract. A submit that dropped the
			turn would make the player rebuild a five-tile word from an empty rack
			because one letter was wrong; this one leaves the board alone so they
			move one tile. ]]
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		game.select(1)
		game.place(4, 4)
		game.select(2)
		game.place(4, 5)
		game.select(3)
		game.place(4, 6)
		local before = game.dump()
		local counters = core:counters()
		game.submit()
		expect(game.dump()).toBe(before)
		expect(game.score()).toBe(0)
		expect(game.turn()).toBe(1)
		expect(game.rackCount()).toBe(4)
		expect(game.pendingAt(4, 4) ~= nil).toBe(true)
		expect(game.pendingAt(4, 5) ~= nil).toBe(true)
		expect(game.pendingAt(4, 6) ~= nil).toBe(true)
		expect(game.committedAt(4, 4)).toBeNil()
		-- ...and refusing it twenty more times still changes nothing
		for _ = 1, 20 do
			game.submit()
		end
		expect(game.dump()).toBe(before)
		expect(core:counters().signals).toBe(counters.signals)
		game.dispose()
	end)

	it("the turn budget decrements only on a commit", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		expect(game.turnsLeft()).toBe(6)
		game.submit() -- nothing placed
		expect(game.turnsLeft()).toBe(6)
		game.select(1)
		game.place(4, 4)
		game.select(2)
		game.place(4, 5)
		game.submit() -- ED is not a word
		expect(game.turnsLeft()).toBe(6)
		game.undo()
		expect(game.turnsLeft()).toBe(6)
		play(game, WIN_SCRIPT, 1)
		expect(game.turnsLeft()).toBe(5)
		game.dispose()
	end)

	it("the legal-next-cell cue follows the rules, and locks with the axis", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		-- turn one, nothing placed: the star is the only square that can start
		expect(game.cellState(4, 4)).toBe("centre")
		expect(game.cellState(1, 1)).toBe("idle")
		game.select(1)
		game.place(4, 4)
		-- one tile: the axis is NOT locked, so all four neighbours are live
		expect(game.cellState(4, 3)).toBe("legal")
		expect(game.cellState(3, 4)).toBe("legal")
		game.select(2)
		game.place(4, 5)
		-- two tiles in row four: the axis is locked, so the column is not offered
		expect(game.cellState(4, 3)).toBe("legal")
		expect(game.cellState(3, 4)).toBe("idle")
		expect(game.cellState(4, 4)).toBe("pending")
		game.dispose()
	end)
end)

-- ===========================================================================
-- ENDINGS, RESTART, DETERMINISM
-- ===========================================================================
describe("examples/06 crossword — both endings, and the way back", function()
	it("reaching the goal wins, and the screen says which ending it was", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT)
		expect(game.phase()).toBe("won")
		expect(game.score()).toBe(67)
		expect(game.score() >= rules.GOAL).toBe(true)
		deps.presenter.refresh()
		local hint = adapter.node(game.hintPath).props.text
		expect(string.find(hint, "you win!", 1, true) ~= nil).toBe(true)
		expect(string.find(hint, "67 points", 1, true) ~= nil).toBe(true)
		expect(string.find(hint, "4 of 6 turns", 1, true) ~= nil).toBe(true)
		-- ...and the game is closed: the rack is dead and nothing else lands
		local dump = game.dump()
		game.select(1)
		game.place(1, 1)
		game.submit()
		expect(game.dump()).toBe(dump)
		-- ...but Start over still works, which is what "offers restart" means
		adapter.tap(game.resetPath)
		expect(game.phase()).toBe("playing")
		expect(game.score()).toBe(0)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("spending the budget without reaching the goal loses, and says so", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		play(game, LOSS_SCRIPT)
		expect(game.phase()).toBe("lost")
		expect(game.score()).toBe(14)
		expect(game.turnsLeft()).toBe(0)
		deps.presenter.refresh()
		local hint = adapter.node(game.hintPath).props.text
		expect(hint).toBe("Out of turns at 14 of 60 points. Press Start over to play again.")
		adapter.tap(game.resetPath)
		expect(game.phase()).toBe("playing")
		expect(game.turnsLeft()).toBe(6)
		game.dispose()
	end)

	it("restart returns EVERY observable to its seeded start", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local start = game.dump()
		local startHint = game.hintText()
		local startWord = game.wordText()
		play(game, WIN_SCRIPT, 2)
		game.select(1)
		game.place(1, 1) -- ...and leave an uncommitted tile
		game.select(2) -- ...and a held one
		game.place(4, 1) -- ...and a refusal on screen
		expect(game.score() > 0).toBe(true)
		adapter.tap(game.resetPath)
		expect(game.dump()).toBe(start)
		expect(game.hintText()).toBe(startHint)
		expect(game.wordText()).toBe(startWord)
		expect(game.selected()).toBeNil()
		expect(game.turn()).toBe(1)
		-- ...and the board is genuinely playable again, from the same first move
		play(game, WIN_SCRIPT, 1)
		expect(game.score()).toBe(16)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)

describe("examples/06 crossword — determinism", function()
	it("the same seed deals the same rack and the same bag", function()
		local core, deps = makeWorld()
		local a = newGame(core, deps)
		local core2, deps2 = makeWorld()
		local b = newGame(core2, deps2)
		for slot = 1, 7 do
			expect(b.rackLetter(slot)).toBe(a.rackLetter(slot))
		end
		expect(b.dump()).toBe(a.dump())
		-- the BAG too, which the rack alone cannot prove: one committed turn
		-- refills five slots straight out of it
		play(a, WIN_SCRIPT, 1)
		play(b, WIN_SCRIPT, 1)
		expect(b.dump()).toBe(a.dump())
		-- ...and a different seed really is a different game
		b.reset(rules.DEFAULT_SEED + 1)
		expect(b.dump() ~= a.dump()).toBe(true)
		a.dispose()
		b.dispose()
	end)

	it("a fixed script on a fixed seed lands on the same board, score and dump", function()
		local core, deps = makeWorld()
		local a = newGame(core, deps)
		play(a, WIN_SCRIPT)
		expect(a.dump()).toBe(
			"......./QUALIA./....O../EARED../...NIPS/....D../....E..|rack=EARVGEL|score=67|turn=5|phase=won"
		)
		local core2, deps2 = makeWorld()
		local b = newGame(core2, deps2)
		play(b, WIN_SCRIPT)
		expect(b.dump()).toBe(a.dump())
		-- ...and a restart onto the same seed replays it a third time
		b.reset(rules.DEFAULT_SEED)
		play(b, WIN_SCRIPT)
		expect(b.dump()).toBe(a.dump())
		a.dispose()
		b.dispose()
	end)
end)

describe("examples/06 crossword — robustness", function()
	it("rapid alternating input leaves no stale selection or held tile", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		for _ = 1, 20 do
			adapter.tap(game.rackPath(1))
			adapter.tap(game.cellPath(4, 4))
			adapter.tap(game.cellPath(4, 4))
			adapter.tap(game.submitPath)
			adapter.tap(game.undoPath)
			adapter.tap(game.rackPath(2))
			adapter.tap(game.rackPath(2))
			adapter.tap(game.resetPath)
		end
		expect(game.selected()).toBeNil()
		expect(game.rackCount()).toBe(7)
		expect(game.score()).toBe(0)
		expect(game.turn()).toBe(1)
		expect(game.phase()).toBe("playing")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps, adapter = makeWorld()
		local baseline = core:counters()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 2)
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(1, 1))
		game.dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)
end)

-- ===========================================================================
-- PAINT
-- ===========================================================================
--[[ WHY A PAINT CASE EXISTS AT ALL, AND WHY IT MEASURES THE RENDERED NODE.

	A board of forty-nine rectangles that is perfectly present in the tree,
	correct in every property probe, and INVISIBLE on the screen is a real defect
	class this repository has shipped twice — most recently thirty cells of the
	sibling word game, whose empty plate measured 1.036:1 against the page under
	Sci-Fi HUD. Geometry
	cannot see it and neither can a source review, because the declaration reads
	perfectly well.

	Headless, the closest honest instrument is the RENDERED TREE plus the theme's
	own resolver: the adapter records the colour it actually resolved for each
	node (`node.tintColor`, recomputed on every theme commit exactly as the real
	target's `refreshThemedPaint` does), and `sheet_model.paletteColor` says what
	the surface behind it paints. Comparing those two can be asked of all fifteen
	shipped themes instead of the one a screenshot shows. ]]

local THEMES: { { id: string, package: any?, themeName: string?, theme: any } } = (function()
	local out: { { id: string, package: any?, themeName: string?, theme: any } } = {}
	local neutral = Facet.themes.neutralPackage()
	for _, theme in neutral.style.themes do
		table.insert(out, { id = `studio-neutral/{theme.name}`, package = nil, themeName = nil, theme = theme })
	end
	local names = fs.readDir("examples/themes")
	table.sort(names)
	for _, file in names do
		local id = string.match(file, "^(.+)%.luau$")
		if id == nil then
			continue
		end
		local module = (require)(`../examples/themes/{id}`) :: any
		if type(module.build) ~= "function" then
			continue
		end
		local package = module.build(Facet.themes)
		for _, theme in package.style.themes do
			table.insert(out, { id = `{id}/{theme.name}`, package = package, themeName = theme.name, theme = theme })
		end
	end
	return out
end)()

-- The same floor the word game's board is held to, for the same reason and from
-- the same measurement: `surfaceStrong` cannot reach 1.25 at ANY blend in ANY
-- shipped theme, and the quietest plate this board wants to paint clears it.
-- It is a REGRESSION FENCE, not an accessibility grade.
local VISIBLE_FLOOR = 1.25

describe("examples/06 crossword — forty-nine cells that are actually there, in every theme", function()
	it("sweeps a real set of themes, not an empty one", function()
		-- a sweep over nothing passes every assertion inside it
		expect(#THEMES >= 12).toBe(true)
	end)

	it("every cell state paints a plate the player can see, under every theme", function()
		--[[ TWO BOARDS, because no single board carries all five plates: the
			starred centre only exists while (4,4) is EMPTY, and it stops existing
			the moment the opening word covers it. So the sweep visits an untouched
			board (star, legal cells, idle squares) and a mid-turn one (committed
			letters, uncommitted letters, the legal run they lock, idle squares),
			and asserts afterwards that between them it really saw all five. ]]
		local problems: { string } = {}
		local checked = 0
		local seen: { [string]: boolean } = {}
		local worst = { ratio = math.huge, where = "" }

		local function sweep(game: any, deps: any, adapter: any)
			for _, entry in THEMES do
				adapter.setThemePackage(entry.package, entry.themeName, nil)
				deps.presenter.refresh()
				local page = sheet_model.paletteColor(entry.theme, "surface")
				for r = 1, rules.SIZE do
					for c = 1, rules.SIZE do
						checked += 1
						local state = game.cellState(r, c)
						seen[state] = true
						local path = game.platePath(r, c)
						local plate = adapter.node(path)
						if plate == nil then
							table.insert(problems, `{entry.id} {path}: no node at all`)
							continue
						end
						if plate.rect == nil or plate.rect.w <= 0 or plate.rect.h <= 0 then
							table.insert(problems, `{entry.id} {path}: arranged to nothing`)
							continue
						end
						-- a tint that paints must carry BOTH halves: the colour claim
						-- and an opaque alpha. A colour with no fill is the invisible
						-- plate this case exists for.
						if plate.tintColor == nil or plate.tintTransparency ~= 0 then
							table.insert(problems, `{entry.id} {path}: tint is not an opaque fill`)
							continue
						end
						local ratio = tokens.contrastRatio(plate.tintColor, page)
						if ratio < worst.ratio then
							worst = { ratio = ratio, where = `{entry.id} {path} ({state})` }
						end
						if ratio < VISIBLE_FLOOR then
							table.insert(
								problems,
								string.format(
									"%s %s (%s): the plate is %.3f:1 against the page it sits on (floor %.2f)",
									entry.id,
									path,
									state,
									ratio,
									VISIBLE_FLOOR
								)
							)
						end
					end
				end
			end
		end

		local coreA, depsA, adapterA = makeWorld()
		local fresh = newGame(coreA, depsA)
		sweep(fresh, depsA, adapterA)
		fresh.dispose()

		local coreB, depsB, adapterB = makeWorld()
		local played = newGame(coreB, depsB)
		play(played, WIN_SCRIPT, 1)
		played.select(4)
		played.place(2, 5)
		played.select(3)
		played.place(3, 5)
		sweep(played, depsB, adapterB)
		played.dispose()

		if #problems > 0 then
			error(`{#problems} invisible or missing board cell(s):\n  ` .. table.concat(problems, "\n  ", 1, 8), 2)
		end
		expect(checked).toBe(2 * #THEMES * rules.SIZE * rules.SIZE)
		expect(worst.ratio >= VISIBLE_FLOOR).toBe(true)
		-- ...and the sweep really did see all five plates, not one repeated 98 times
		for _, state in { "idle", "legal", "centre", "pending", "committed" } do
			expect(seen[state]).toBe(true)
		end
		expect(coreA:lastError()).toBeNil()
		expect(coreB:lastError()).toBeNil()
	end)

	it("...and the floor BITES: the plate the word game used to paint clears it nowhere", function()
		--[[ A check nobody has watched fail is a check that proves nothing. This
			runs the SAME metric over the SAME themes against the declaration that
			hid thirty invisible cells for a mission, and it must fail in every one
			of them. The blend is the SHIPPED 0.6: measured, the role only reaches
			the floor at all at 0.8 and above, and then in exactly one theme of the
			fifteen (classic_desktop/Day, 1.256:1) — which is the same finding said
			twice, that a panel colour cannot carry a plate. ]]
		local cleared: { string } = {}
		local best = 0
		for _, entry in THEMES do
			local page = sheet_model.paletteColor(entry.theme, "surface")
			local old = sheet_model.tintColor(entry.theme, { role = "surfaceStrong", blend = 0.6 }, "Box")
			local ratio = tokens.contrastRatio(old, page)
			best = math.max(best, ratio)
			if ratio >= VISIBLE_FLOOR then
				table.insert(cleared, string.format("%s (%.3f:1)", entry.id, ratio))
			end
		end
		if #cleared > 0 then
			error(
				`the surfaceStrong plate clears the floor in {#cleared} case(s) (e.g. {cleared[1]}), so this `
					.. "floor would not catch the defect it was written for",
				2
			)
		end
		expect(best < VISIBLE_FLOOR).toBe(true)
	end)
end)

describe("examples/06 crossword — committed versus uncommitted is not a colour", function()
	--[[ WHAT THESE CASES MAY READ. Nothing in this block looks at a tint, a blend
		or a colour — that is the whole claim. If every assertion here still holds
		with the paint channel deleted, then a player who cannot separate two
		washes of one role still knows which letters are still theirs to move. ]]
	it("a committed letter wears a solid plate and an uncommitted one wears an outline", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		play(game, WIN_SCRIPT, 1)
		game.select(4)
		game.place(2, 5)
		deps.presenter.refresh()
		expect(game.cellState(4, 1)).toBe("committed")
		expect(game.cellState(2, 5)).toBe("pending")
		-- read off the RENDERED node, not off the example's own table
		expect(adapter.node(game.platePath(4, 1)).props.surface).toBe("raised")
		expect(adapter.node(game.platePath(2, 5)).props.surface).toBe("chip")
		-- ...and they are DIFFERENT, which is the whole claim
		expect(adapter.node(game.platePath(4, 1)).props.surface ~= adapter.node(game.platePath(2, 5)).props.surface).toBe(
			true
		)
		game.dispose()
	end)

	it("...and the same fact a third time, in ASCII, for a screen with no colour at all", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		expect(game.cellMark(4, 4)).toBe("*") -- the star the first turn has to cover
		play(game, WIN_SCRIPT, 1)
		game.select(4)
		game.place(2, 5)
		deps.presenter.refresh()
		expect(adapter.node(game.markPath(2, 5)).props.text).toBe("~") -- still yours
		expect(adapter.node(game.markPath(4, 1)).props.text).toBe("") -- settled
		expect(adapter.node(game.markPath(3, 5)).props.text).toBe("+") -- a legal next square
		-- every mark is plain ASCII, because ASCII is the only range every Roblox
		-- font is guaranteed to draw
		for _, mark in { "", "+", "*", "~" } do
			expect(string.match(mark, "^[%w%p]*$") ~= nil).toBe(true)
		end
		game.dispose()
	end)

	it("a spent rack slot is DISABLED, not a live-looking blank button", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		deps.presenter.refresh()
		expect(adapter.node(game.rackPath(1)).props.enabled).toBe(true)
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(4, 4))
		deps.presenter.refresh()
		local spent = adapter.node(game.rackPath(1))
		expect(spent.props.enabled).toBe(false)
		expect(spent.props.label).toBe("·")
		-- and it really is inert: tapping it changes nothing at all
		local before = game.dump()
		adapter.tap(game.rackPath(1))
		expect(game.dump()).toBe(before)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)
