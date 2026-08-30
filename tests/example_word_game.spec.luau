--!strict
-- The word game's PURE rules and its state machine (roadmap Step 10, EQ-9).
--
-- Two halves, deliberately separated:
--   1. `example.rules` — scoring, the key ladder, the seed, and the two
--      questions the game asks the shared generated word data. No signals, no
--      adapter, no presenter: a table in, a table out.
--      Every duplicate-letter shape the real game can produce is pinned here,
--      because the letter-budget rule is the only genuinely subtle part of
--      Wordle and it is invisible in the mounted screen until it is wrong.
--   2. the built game — refusals that do not consume a row, retained rows,
--      monotonic key state, win, loss with the word revealed, input disabled
--      after the end, and a deterministic seeded restart.
--
-- ...plus three PAINT cases that a rules test structurally cannot reach, each
-- written against a rendered tree rather than against this file's reading of the
-- example's source: every board cell is visible in EVERY shipped theme, the
-- active row's cue survives with colour ignored, and the board still holds its
-- letters at the largest text preference.
--
-- The MOUNTED input paths (pointer/touch/keyboard/gamepad) live in
-- tests/examples_games.spec.luau beside the other two games; this file owns the
-- rules and the machine.
--
-- THE WORD DATA ITSELF IS NOT RE-PROVEN HERE. Its counts, its sortedness, its
-- provenance hashes and its seed mixing are `tests/example_word_data.spec.luau`;
-- this file only asks whether the GAME asks it the right questions.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local sheet_model = require("../src/tokens/sheet_model")
local tokens = require("../src/tokens/tokens")
local large_text = require("./lib/large_text")
local wordGame = require("../examples/gallery/examples/05_word_game")

local rules = wordGame.rules

-- a compact phone MINUS the CoreGui topbar inset: the viewport this example is
-- most likely to be unplayable on, and the one a dev-machine viewport hides
local PHONE = { x = 0, y = 0, w = 360, h = 633 }

--[[ THE SEED THAT PLAYS THE WORKED EXAMPLE.

	Every scoring case below is written against REACT — it is the word the
	tutorial's own prose quotes, and RULES/ERROR/AWARE/EERIE against it are the
	four duplicate-letter shapes the two-pass rule exists for. The answer now
	comes from the shared generated set of 2,096, whose seed is MIXED rather than
	indexed, so "seed 1" is no longer REACT and pretending otherwise would be a
	fiction the data could break at any regeneration.

	So the spec ASKS which seed plays REACT instead of assuming one. The search
	is a pure function of the data, it costs a few thousand modulo operations,
	and if REACT ever leaves the answer set this fails LOUDLY at load with the
	reason rather than turning twenty cases into puzzles about a different word. ]]
local REACT_SEED = (function(): number
	for seed = 1, 100000 do
		if rules.solutionForSeed(seed) == "REACT" then
			return seed
		end
	end
	error("example_word_game.spec: no seed in 1..100000 plays REACT — the answer set no longer holds it", 0)
end)()

local function makeWorld(viewport: any?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", viewport or { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = pres, adapter = adapter }
	return core, deps, adapter
end

-- Build the game and put it on the REACT puzzle. `restart(seed)` is the
-- example's own public door onto a named puzzle — the same one the "New game"
-- button uses — so a test that replays a seed drives exactly what a player does.
local function newGame(core: any, deps: any): any
	local game = wordGame.build(Facet, core, deps)
	game.restart(REACT_SEED)
	return game
end

-- type a whole word through the HARDWARE key path (the arbitrated action
-- pipeline), never by calling typeLetter — the same rule the gate applies to
-- the Studio rows, kept here so the headless suite cannot drift from it.
local function typeWord(game: any, word: string)
	for i = 1, #word do
		game.press(word:sub(i, i))
	end
end

local function guess(game: any, word: string)
	typeWord(game, word)
	game.press("Return")
end

local function states(game: any, row: number): { string }
	local out = {}
	for c = 1, rules.COLS do
		out[c] = game.state(row, c)
	end
	return out
end

local function expectStates(game: any, row: number, expected: { string })
	local actual = states(game, row)
	for c = 1, rules.COLS do
		if actual[c] ~= expected[c] then
			error(
				`row {row} column {c}: expected '{expected[c]}' but the board says '{actual[c]}' `
					.. `(whole row: {table.concat(actual, ",")})`,
				2
			)
		end
	end
end

-- ===========================================================================
describe("examples/05 word game — the pure scoring rules", function()
	it("scores a plain guess with no repeated letters", function()
		-- REACT vs RULES: R exact, E present (wrong column), U/L/S nowhere
		local s = rules.evaluate("RULES", "REACT")
		expect(s[1]).toBe("correct") -- R
		expect(s[2]).toBe("absent") -- U
		expect(s[3]).toBe("absent") -- L
		expect(s[4]).toBe("present") -- E is in REACT, column 2
		expect(s[5]).toBe("absent") -- S
	end)

	it("a guess with a DOUBLED letter against a solution holding ONE spends the budget once", function()
		-- CRANE holds a single R; ERROR asks for three.
		local s = rules.evaluate("ERROR", "CRANE")
		expect(s[1]).toBe("present") -- E: CRANE's E is unspent
		expect(s[2]).toBe("correct") -- R in column 2 IS CRANE's R
		expect(s[3]).toBe("absent") -- the R budget is gone
		expect(s[4]).toBe("absent") -- O
		expect(s[5]).toBe("absent") -- ...and the third R too
	end)

	it("a SOLUTION with a doubled letter pays a misplaced guess letter from what the exact match left", function()
		-- LLAMA holds two L's; LEVEL asks for two, one of them exact.
		local s = rules.evaluate("LEVEL", "LLAMA")
		expect(s[1]).toBe("correct") -- L in column 1
		expect(s[2]).toBe("absent") -- E
		expect(s[3]).toBe("absent") -- V
		expect(s[4]).toBe("absent") -- E
		expect(s[5]).toBe("present") -- the second L, paid from the remaining budget
	end)

	it("BOTH doubled: two exact matches and one misplaced, all from a budget of two", function()
		-- ABBEY holds two B's; HOBBY asks for two.
		local s = rules.evaluate("HOBBY", "ABBEY")
		expect(s[1]).toBe("absent") -- H
		expect(s[2]).toBe("absent") -- O
		expect(s[3]).toBe("correct") -- B in column 3
		expect(s[4]).toBe("present") -- the second B, from the one remaining
		expect(s[5]).toBe("correct") -- Y
	end)

	it("an EXACT match consumes the budget BEFORE an earlier misplaced copy of the same letter", function()
		-- THE case the two passes exist for: AWARE's column-3 A is exact, so
		-- CRANE's only A is already spent by the time column 1 is scored. A
		-- single left-to-right pass would paint column 1 `present` instead.
		local s = rules.evaluate("AWARE", "CRANE")
		expect(s[1]).toBe("absent") -- NOT present: the A budget went to column 3
		expect(s[2]).toBe("absent") -- W
		expect(s[3]).toBe("correct") -- A
		expect(s[4]).toBe("present") -- R
		expect(s[5]).toBe("correct") -- E
	end)

	it("three copies against two: the excess is absent", function()
		local s = rules.evaluate("EERIE", "REACT")
		expect(s[1]).toBe("absent") -- REACT has one E and column 2 takes it
		expect(s[2]).toBe("correct") -- E
		expect(s[3]).toBe("present") -- R
		expect(s[4]).toBe("absent") -- I
		expect(s[5]).toBe("absent") -- the third E
	end)

	it("the whole solution scores correct", function()
		-- a spread of REAL answers, taken through the seed the game itself uses
		for seed = 1, 60 do
			local word = rules.solutionForSeed(seed)
			local s = rules.evaluate(word, word)
			for c = 1, rules.COLS do
				expect(s[c]).toBe("correct")
			end
		end
	end)
end)

describe("examples/05 word game — validation and the two generated sets", function()
	it("refuses a guess shorter than five letters", function()
		expect(rules.validate("")).toBe("short")
		expect(rules.validate("REAC")).toBe("short")
	end)

	it("refuses a five-letter non-word", function()
		expect(rules.validate("ZZZZZ")).toBe("unknown")
		expect(rules.validate("QWERT")).toBe("unknown")
		expect(rules.validate("PLZTK")).toBe("unknown")
	end)

	it("accepts every solution AND the wider guess list", function()
		-- EVERY ANSWER IS AN ACCEPTED GUESS. A puzzle whose answer the game would
		-- refuse cannot be won, and neither set can see that on its own — so the
		-- game asks it of the pair, over the seeds it will actually deal out.
		for seed = 1, 200 do
			local answer = rules.solutionForSeed(seed)
			expect(rules.isSolution(answer)).toBe(true)
			expect(rules.validate(answer)).toBe("ok")
		end
		-- ...and the wider set really is wider: these are guesses a player would
		-- reasonably try, none of which are answers
		for _, word in { "RULES", "TILES", "ADIEU", "FJORD", "MOCHA", "SUSHI" } do
			expect(rules.validate(word)).toBe("ok")
			expect(rules.isSolution(word)).toBe(false)
		end
	end)

	it("the answer set is a SUBSET of the accepted set, and strictly smaller", function()
		-- The counts replace the two literal tables this file used to walk. They
		-- are the same claim — the answers are the smaller, more familiar half —
		-- asked of data too large to enumerate in an assertion.
		expect(rules.solutionCount > 1000).toBe(true)
		expect(rules.acceptedCount > 3000).toBe(true)
		expect(rules.solutionCount < rules.acceptedCount).toBe(true)
	end)

	it("accepts ordinary words the old hand-typed list refused", function()
		--[[ THE POINT OF THE REPLACEMENT, as its own case at the GAME's door
			rather than the data's: `rules.validate` is what the player's Enter key
			reaches, and every one of these was "not a word" to it until the shared
			set landed. ]]
		for _, word in { "ADIEU", "FJORD", "MOCHA", "NINJA", "SUSHI", "WALTZ", "SALSA", "ZESTY" } do
			if rules.validate(word) ~= "ok" then
				error(`the game still refuses "{word}" — accepting it is the whole point of the shared word data`, 2)
			end
		end
	end)

	it("takes a guess in whatever case it arrives in", function()
		-- the game types in uppercase and the data is lowercase; the flip is the
		-- word module's job, and this is the case that says the game relies on it
		expect(rules.validate("CRANE")).toBe("ok")
		expect(rules.isWord("crane")).toBe(true)
		expect(rules.isWord("CrAnE")).toBe(true)
		-- ...but a length that is not this board's is still not a guess
		expect(rules.isWord("CRANES")).toBe(false)
		expect(rules.isWord("CRAN")).toBe(false)
	end)
end)

describe("examples/05 word game — the key ladder is monotonic", function()
	it("ranks correct above present above absent", function()
		expect(rules.strongest("absent", "present")).toBe("present")
		expect(rules.strongest("present", "correct")).toBe("correct")
		expect(rules.strongest("absent", "correct")).toBe("correct")
	end)

	it("never downgrades on later, weaker evidence", function()
		expect(rules.strongest("correct", "present")).toBe("correct")
		expect(rules.strongest("correct", "absent")).toBe("correct")
		expect(rules.strongest("present", "absent")).toBe("present")
	end)

	it("an unknown key takes whatever the first evidence says", function()
		expect(rules.strongest(nil, "absent")).toBe("absent")
		expect(rules.strongest("present", nil)).toBe("present")
	end)

	it("mergeKeys returns a NEW table and keeps the strongest per letter", function()
		local first = rules.mergeKeys({}, "RULES", rules.evaluate("RULES", "REACT"))
		expect(first.R).toBe("correct")
		expect(first.E).toBe("present")
		expect(first.U).toBe("absent")
		-- REACT itself now makes E correct and leaves R correct
		local second = rules.mergeKeys(first, "REACT", rules.evaluate("REACT", "REACT"))
		expect(second.E).toBe("correct")
		expect(second.R).toBe("correct")
		expect(first.E).toBe("present") -- the first table was not mutated
	end)

	it("a later guess that re-tests a solved letter cannot downgrade it", function()
		-- REACT solved; now guess ERROR, where the second/third R are `absent`
		local keys = rules.mergeKeys({}, "REACT", rules.evaluate("REACT", "REACT"))
		expect(keys.R).toBe("correct")
		local after = rules.mergeKeys(keys, "ERROR", rules.evaluate("ERROR", "REACT"))
		expect(after.R).toBe("correct")
	end)
end)

describe("examples/05 word game — the deterministic seed", function()
	it("the same seed always yields the same word", function()
		expect(rules.solutionForSeed(1)).toBe(rules.solutionForSeed(1))
		expect(rules.solutionForSeed(4)).toBe(rules.solutionForSeed(4))
	end)

	it("every seed lands on a real answer, and a seed past the end wraps", function()
		-- The mapping itself (mixing, coverage, wrap) is proven over the data in
		-- tests/example_word_data.spec.luau. What belongs HERE is that the game's
		-- own seed door never hands the board something it could not accept.
		for _, seed in { 1, 2, 7, 41, 1000, 65535, 1e6 } do
			local word = rules.solutionForSeed(seed)
			expect(#word).toBe(rules.COLS)
			expect(rules.isSolution(word)).toBe(true)
			expect(rules.validate(word)).toBe("ok")
		end
	end)

	it("the game plays in UPPERCASE even though the data is lowercase", function()
		-- the whole board, the typed letters and the key ladder are uppercase, so
		-- an answer that arrived lowercase would never match a guess
		for _, seed in { 1, 2, REACT_SEED, 4096 } do
			local word = rules.solutionForSeed(seed)
			expect(word).toBe(string.upper(word))
		end
	end)

	it("REACT is reachable, and it is the seed the rest of this file plays", function()
		expect(rules.solutionForSeed(REACT_SEED)).toBe("REACT")
		expect(rules.solutionForSeed(REACT_SEED)).toBe(rules.solutionForSeed(REACT_SEED))
	end)
end)

-- ===========================================================================
describe("examples/05 word game — the state machine", function()
	it("starts on a visible six-by-five board with a caret in the first cell", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		expect(core:lastError()).toBeNil()
		for r = 1, rules.ROWS do
			for c = 1, rules.COLS do
				expect(adapter.node(game.tilePath(r, c)) ~= nil).toBe(true)
			end
		end
		expect(game.state(1, 1)).toBe("caret")
		expect(game.mark(1, 1)).toBe("_")
		expect(game.state(1, 2)).toBe("empty")
		expect(game.state(2, 1)).toBe("empty") -- the caret is in the ACTIVE row only
		expect(game.activeRow()).toBe(1)
		game.dispose()
	end)

	it("every tile paints a REAL tint — the plate is never invisible", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		-- the defect this pins: a bound value outside a closed enum used to be
		-- accepted and paint nothing, so all thirty tiles rendered transparent
		for r = 1, rules.ROWS do
			for c = 1, rules.COLS do
				local fill = adapter.node(game.tilePath(r, c) .. "/fill")
				expect(fill ~= nil).toBe(true)
				expect(fill.props.tint ~= nil).toBe(true)
				expect(fill.tintColor ~= nil).toBe(true)
				expect(fill.tintTransparency).toBe(0)
			end
		end
		game.dispose()
	end)

	it("letters land in the ACTIVE row only", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		typeWord(game, "RULES")
		expect(game.row(1)).toBe("RULES")
		expect(game.row(2)).toBe("")
		-- a sixth letter has nowhere to go
		game.press("X")
		expect(game.row(1)).toBe("RULES")
		game.press("Return")
		expect(game.activeRow()).toBe(2)
		typeWord(game, "AB")
		expect(game.row(1)).toBe("RULES") -- the scored row is untouched
		expect(game.row(2)).toBe("AB")
		game.dispose()
	end)

	it("a SHORT guess is refused with a message and does not consume a row", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		typeWord(game, "REA")
		game.press("Return")
		expect(game.activeRow()).toBe(1)
		expect(game.row(1)).toBe("REA") -- the letters survive the refusal
		expect(string.find(game.status(), "Not enough letters") ~= nil).toBe(true)
		expect(game.state(1, 1)).toBe("filled") -- not scored
		game.dispose()
	end)

	it("an INVALID guess is refused with a different message and does not consume a row", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		typeWord(game, "ZZZZZ")
		game.press("Return")
		expect(game.activeRow()).toBe(1)
		expect(game.row(1)).toBe("ZZZZZ")
		--[[ THE REFUSAL IS A FACT ABOUT THIS GAME. It used to point at a list the
			example kept in its own source, which is two claims a player should
			never be handed: that there is a list, and that being outside it is
			their problem. The message now says what is actually true — this game
			did not recognise the word — and it names the word back so the player
			can see what was read. The last assertion is the one that keeps the
			old shape from creeping back in under new wording. ]]
		expect(string.find(game.status(), "this game doesn't know that word") ~= nil).toBe(true)
		expect(string.find(game.status(), "ZZZZZ", 1, true) ~= nil).toBe(true)
		expect(string.find(game.status(), "word list")).toBeNil()
		expect(game.state(1, 3)).toBe("filled")
		-- ...and typing again clears the refusal
		game.press("Backspace")
		expect(string.find(game.status(), "this game doesn't know that word")).toBeNil()
		game.dispose()
	end)

	it("a rejected guess consumes NO row, and an ordinary word the old list refused plays on", function()
		--[[ RED-FIRST, and the two halves are one case on purpose: a refusal that
			eats a row and a word that should never have been refused are the same
			player-facing failure — "the game took a turn off me for typing
			English". ]]
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		typeWord(game, "PLZTK")
		game.press("Return")
		expect(game.activeRow()).toBe(1) -- no row consumed
		expect(game.phase()).toBe("playing")
		expect(game.state(1, 1)).toBe("filled") -- not scored
		expect(string.find(game.status(), "this game doesn't know that word") ~= nil).toBe(true)
		-- ...now the same five keystrokes' worth of an ordinary word DOES play
		for _ = 1, rules.COLS do
			game.press("Backspace")
		end
		guess(game, "MOCHA")
		expect(game.activeRow()).toBe(2) -- the row was consumed this time
		expect(game.row(1)).toBe("MOCHA")
		-- vs REACT: M/O/H nowhere, C and A both in the word but in other columns
		expectStates(game, 1, { "absent", "absent", "present", "absent", "present" })
		game.dispose()
	end)

	it("four words the old thirty-four-word list rejected now play end to end", function()
		for _, word in { "ADIEU", "FJORD", "NINJA", "ZESTY" } do
			local core, deps = makeWorld()
			local game = newGame(core, deps)
			guess(game, word)
			if game.activeRow() ~= 2 then
				error(
					`"{word}" was refused: the board is still on row {game.activeRow()} and says "{game.status()}"`,
					2
				)
			end
			expect(game.row(1)).toBe(word)
			-- a scored row is a scored row: five verdicts, none of them a
			-- pre-submission state
			for c = 1, rules.COLS do
				local state = game.state(1, c)
				expect(state == "correct" or state == "present" or state == "absent").toBe(true)
			end
			-- ...and the key ladder learned from it, which is what "played" means
			expect(game.keyState(string.sub(word, 1, 1)) ~= nil).toBe(true)
			game.dispose()
		end
	end)

	it("backspace deletes from the active row and stops at empty", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		typeWord(game, "RE")
		game.press("Backspace")
		expect(game.row(1)).toBe("R")
		game.press("Backspace")
		game.press("Backspace")
		expect(game.row(1)).toBe("")
		expect(game.state(1, 1)).toBe("caret")
		game.dispose()
	end)

	it("a scored row keeps its verdict AND its marks while the next row becomes active", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		guess(game, "RULES") -- vs REACT
		expectStates(game, 1, { "correct", "absent", "absent", "present", "absent" })
		expect(game.mark(1, 1)).toBe("v")
		expect(game.mark(1, 4)).toBe("~")
		expect(game.mark(1, 2)).toBe("x")
		expect(game.activeRow()).toBe(2)
		guess(game, "ERROR")
		expectStates(game, 1, { "correct", "absent", "absent", "present", "absent" }) -- unchanged
		expect(game.activeRow()).toBe(3)
		game.dispose()
	end)

	it("the duplicate-letter rule reaches the board, not just the scorer", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		guess(game, "ERROR") -- vs REACT: E present, R correct, then R/O/R absent
		expectStates(game, 1, { "present", "present", "absent", "absent", "absent" })
		game.dispose()
	end)

	it("key state accumulates monotonically and never downgrades", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		guess(game, "RULES") -- R correct, E present, U/L/S absent
		expect(game.keyState("R")).toBe("correct")
		expect(game.keyState("E")).toBe("present")
		expect(game.keyState("U")).toBe("absent")
		expect(game.keyState("Z")).toBeNil() -- untouched letters stay unknown
		guess(game, "ERROR") -- E present again, R present/absent in later columns
		expect(game.keyState("R")).toBe("correct") -- NOT downgraded
		expect(game.keyState("E")).toBe("present")
		guess(game, "REACT") -- solves; E is now correct
		expect(game.keyState("E")).toBe("correct")
		expect(game.keyState("U")).toBe("absent") -- and the greys stay grey
		game.dispose()
	end)

	it("wins when the solution is submitted, and opens the results card", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		guess(game, "RULES")
		guess(game, "REACT")
		expect(game.phase()).toBe("won")
		expect(game.won()).toBe(true)
		expect(string.find(game.status(), "Solved in 2 guesses") ~= nil).toBe(true)
		expect(game.resultsOpen()).toBe(true)
		expect(deps.presenter.depth()).toBe(2)
		game.dispose()
	end)

	it("loses after SIX accepted wrong guesses and reveals the word", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		local six = { "RULES", "ERROR", "AWARE", "LEVEL", "SOLVE", "TILES" }
		for i, word in six do
			expect(game.phase()).toBe("playing")
			guess(game, word)
			expect(game.row(i)).toBe(word)
		end
		expect(game.phase()).toBe("lost")
		expect(game.lost()).toBe(true)
		expect(string.find(game.status(), "the word was REACT") ~= nil).toBe(true)
		expect(game.resultsOpen()).toBe(true)
		-- the losing board keeps every scored row
		expectStates(game, 1, { "correct", "absent", "absent", "present", "absent" })
		game.dispose()
	end)

	it("a refused guess does NOT count toward the six", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		for _, word in { "RULES", "ERROR", "AWARE", "LEVEL", "SOLVE" } do
			guess(game, word)
		end
		expect(game.activeRow()).toBe(6)
		guess(game, "ZZZZZ") -- invalid
		expect(game.activeRow()).toBe(6)
		expect(game.phase()).toBe("playing")
		for _ = 1, 5 do
			game.press("Backspace")
		end
		guess(game, "TILES") -- the sixth ACCEPTED guess
		expect(game.phase()).toBe("lost")
		game.dispose()
	end)

	it("input is dead after the game ends, except restart", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		guess(game, "REACT")
		expect(game.phase()).toBe("won")
		local before = game.row(1)
		game.press("Z") -- hardware
		adapter.tap(game.keyPath("Z")) -- on-screen
		game.press("Backspace")
		game.press("Return")
		expect(game.row(1)).toBe(before)
		expect(game.row(2)).toBe("")
		expect(game.phase()).toBe("won")
		-- ...and the keyboard SAYS it is dead
		deps.presenter.refresh()
		expect(adapter.node(game.keyPath("Z")).props.enabled).toBe(false)
		expect(adapter.node(game.keyPath("Enter")).props.enabled).toBe(false)
		expect(adapter.node("/Wordle/page/col/Restart").props.enabled).toBeNil()
		game.dispose()
	end)

	it("restart is deterministic: the same seed replays the same word", function()
		-- built, NOT restarted: the game's own opening seed is 1, and its answer is
		-- whatever the shared data deals that seed
		local core, deps = makeWorld()
		local game = wordGame.build(Facet, core, deps)
		expect(game.seed()).toBe(1)
		expect(game.solution()).toBe(rules.solutionForSeed(1))
		guess(game, "RULES")
		game.restart() -- advances the seed
		expect(game.seed()).toBe(2)
		expect(game.solution()).toBe(rules.solutionForSeed(2))
		-- everything is back to the opening position
		expect(game.row(1)).toBe("")
		expect(game.activeRow()).toBe(1)
		expect(game.phase()).toBe("playing")
		expect(game.keyState("R")).toBeNil()
		expect(game.state(1, 1)).toBe("caret")
		expect(game.state(1, 2)).toBe("empty")
		-- jumping to a named seed is reproducible
		game.restart(4)
		local first = game.solution()
		guess(game, "RULES")
		game.restart(4)
		expect(game.solution()).toBe(first)
		expect(game.row(1)).toBe("")
		game.dispose()
	end)

	it("restart after a loss closes the results card and re-enables the keyboard", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		for _, word in { "RULES", "ERROR", "AWARE", "LEVEL", "SOLVE", "TILES" } do
			guess(game, word)
		end
		expect(game.resultsOpen()).toBe(true)
		expect(deps.presenter.depth()).toBe(2)
		-- while the card is up it OWNS the screen: a tap on the base "New game"
		-- does not reach through it (the presenter's modal exclusivity), so a
		-- player either uses the card's own button or dismisses it first
		adapter.tap("/Wordle/page/col/Restart")
		expect(game.resultsOpen()).toBe(true)
		expect(game.phase()).toBe("lost")
		adapter.tap("/WordleResult/centre/Card/Close")
		expect(deps.presenter.depth()).toBe(1)
		adapter.tap("/Wordle/page/col/Restart")
		expect(game.resultsOpen()).toBe(false)
		expect(game.phase()).toBe("playing")
		deps.presenter.refresh()
		expect(adapter.node(game.keyPath("Z")).props.enabled).toBe(true)
		typeWord(game, "AB")
		expect(game.row(1)).toBe("AB")
		game.dispose()
	end)

	it("the results card's Close button actually closes it", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		guess(game, "REACT")
		expect(deps.presenter.depth()).toBe(2)
		expect(adapter.node("/WordleResult/centre/Card/Close") ~= nil).toBe(true)
		adapter.tap("/WordleResult/centre/Card/Close")
		expect(game.resultsOpen()).toBe(false)
		expect(deps.presenter.depth()).toBe(1)
		-- the board is still there, still finished, still readable
		expect(game.phase()).toBe("won")
		expect(game.state(1, 1)).toBe("correct")
		game.dispose()
	end)

	it("the results card's New game button restarts from inside the card", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		guess(game, "REACT")
		adapter.tap("/WordleResult/centre/Card/Again")
		expect(deps.presenter.depth()).toBe(1)
		expect(game.phase()).toBe("playing")
		-- the card's own button takes the NEXT seed, exactly as the page's does
		expect(game.seed()).toBe(REACT_SEED + 1)
		expect(game.solution()).toBe(rules.solutionForSeed(REACT_SEED + 1))
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps = makeWorld()
		local baseline = core:counters()
		local game = newGame(core, deps)
		guess(game, "RULES")
		guess(game, "REACT")
		game.dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)
end)

-- ===========================================================================
describe("examples/05 word game — it fits and stays operable on a phone", function()
	local function assertClean(handle: any, where: string)
		local findings = handle.controller.diagnostics()
		if #findings > 0 then
			local first = findings[1]
			error(`layout finding at {where}: {tostring(first.node)}: {tostring(first.issue)}`, 2)
		end
	end

	it("the solver reports NO layout finding on a compact phone", function()
		local core, deps = makeWorld(PHONE)
		local game = newGame(core, deps)
		assertClean(game.handle, "360x633 portrait, empty board")
		guess(game, "RULES")
		deps.presenter.refresh()
		assertClean(game.handle, "360x633 portrait, one scored row")
		game.dispose()
	end)

	it("the board and every key stay inside the phone's width", function()
		local core, deps = makeWorld(PHONE)
		local game = newGame(core, deps)
		local rectOf = game.handle.controller.rectOf
		local board = rectOf("/Wordle/page/col/board")
		expect(board ~= nil).toBe(true)
		expect(board.x >= 0).toBe(true)
		expect(board.x + board.w <= PHONE.w).toBe(true)
		expect(board.w > 0 and board.h > 0).toBe(true)
		for _, letter in { "Q", "P", "A", "L", "Z", "M", "Enter", "Back" } do
			local key = rectOf(game.keyPath(letter))
			expect(key ~= nil).toBe(true)
			expect(key.x >= 0).toBe(true)
			expect(key.x + key.w <= PHONE.w).toBe(true)
			expect(key.h > 0).toBe(true)
		end
		game.dispose()
	end)

	it("a tile is square and the board is six rows of five", function()
		local core, deps = makeWorld(PHONE)
		local game = newGame(core, deps)
		local rectOf = game.handle.controller.rectOf
		local first = rectOf(game.tilePath(1, 1))
		expect(first.w).toBe(first.h)
		-- columns advance to the right, rows advance down
		expect(rectOf(game.tilePath(1, 2)).x > first.x).toBe(true)
		expect(rectOf(game.tilePath(1, 2)).y).toBe(first.y)
		expect(rectOf(game.tilePath(2, 1)).y > first.y).toBe(true)
		expect(rectOf(game.tilePath(2, 1)).x).toBe(first.x)
		expect(rectOf(game.tilePath(6, 5)) ~= nil).toBe(true)
		game.dispose()
	end)

	it("the page is a scroll host, so the largest text size cannot strand the keyboard", function()
		local core, deps, adapter = makeWorld(PHONE)
		local game = newGame(core, deps)
		local page = adapter.node("/Wordle/page")
		expect(page ~= nil).toBe(true)
		expect(page.class).toBe("ScrollView")
		game.dispose()
	end)
end)

-- ===========================================================================
--[[ THE PAINT CASES.

	Everything above this line is a fact about the model: a state name, a row
	index, a status string. Not one of them can see an INVISIBLE RECTANGLE —
	`docs/lessons/a-default-valued-write-never-claims.md` is the record of a
	fade that ran perfectly over three plates nobody could see, found by a screen
	capture after several hundred correct property readings had missed it.

	Headless, the closest honest instrument is the RENDERED TREE plus the theme's
	own resolver: the adapter records the colour it actually resolved for each
	node (`node.tintColor`, recomputed on every theme commit exactly as the real
	target's `refreshThemedPaint` does), and `sheet_model.paletteColor` says what
	the surface behind it paints. Comparing those two is not a substitute for a
	capture, but it is the thing a capture would be measuring, and it can be
	asked of all fifteen shipped themes instead of the one a screenshot shows. ]]

-- Every theme in `examples/themes` that is a PACKAGE, plus the library's own
-- neutral one. Read from the directory rather than listed here: a package added
-- beside these is swept the day it lands, and one that stops building fails
-- rather than quietly leaving the sweep.
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
		-- `examples/themes` also holds contributed CONTROL fixtures, which are not
		-- packages and carry no palette; a package is exactly a module with a
		-- `build`, which is the entry point the theme picker itself calls.
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

--[[ THE FLOOR, AND WHERE THE NUMBER COMES FROM.

	1.25:1 is not a standard, it is a MEASUREMENT with a margin. The declaration
	this example used to carry — `{ role = "surfaceStrong", blend = 0.6 }` — is
	1.036:1 against the page under Sci-Fi HUD and never better than 1.223:1 in any
	shipped theme, because `surfaceStrong` is the PANEL colour and every theme
	deliberately keeps a panel within a few percent of the page it sits on. A
	board of thirty such rectangles is present in the tree, correct in every
	property probe, and not there on the screen.

	The floor is therefore set where it separates "a plate" from "the page":
	comfortably above the whole `surfaceStrong` family (which cannot reach 1.25 at
	ANY blend, in ANY shipped theme — the control case below pins that), and below
	the quietest plate the board actually wants to paint. It is a REGRESSION
	FENCE, not an accessibility grade; the contrast a scored tile owes its LETTER
	is the palette contract's business and is gated there. ]]
local VISIBLE_FLOOR = 1.25

describe("examples/05 word game — thirty cells that are actually there, in every shipped theme", function()
	it("sweeps a real set of themes, not an empty one", function()
		-- Trap 4 from the manifest checker: a sweep over nothing passes every
		-- assertion inside it. There are eleven package files that build today.
		expect(#THEMES >= 12).toBe(true)
	end)

	it("every one of the thirty cells is present AND painted at startup, under every theme", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local problems: { string } = {}
		local checked = 0
		local worst = { ratio = math.huge, where = "" }
		for _, entry in THEMES do
			-- the commit a player's theme swap makes, on the already-mounted tree
			adapter.setThemePackage(entry.package, entry.themeName, nil)
			deps.presenter.refresh()
			-- what the Screen's own `base` surface paints BEHIND the board
			local page = sheet_model.paletteColor(entry.theme, "surface")
			for r = 1, rules.ROWS do
				for c = 1, rules.COLS do
					checked += 1
					local path = `{game.tilePath(r, c)}/fill`
					local fill = adapter.node(path)
					if fill == nil then
						table.insert(problems, `{entry.id} {path}: no node at all`)
						continue
					end
					if fill.rect == nil or fill.rect.w <= 0 or fill.rect.h <= 0 then
						table.insert(problems, `{entry.id} {path}: arranged to nothing`)
						continue
					end
					-- a tint that paints must carry BOTH halves: the colour claim and
					-- an opaque alpha. A colour with no fill is the invisible plate.
					if fill.tintColor == nil or fill.tintTransparency ~= 0 then
						table.insert(problems, `{entry.id} {path}: tint is not an opaque fill`)
						continue
					end
					local ratio = tokens.contrastRatio(fill.tintColor, page)
					if ratio < worst.ratio then
						worst = { ratio = ratio, where = `{entry.id} {path}` }
					end
					if ratio < VISIBLE_FLOOR then
						table.insert(
							problems,
							string.format(
								"%s %s: the plate is %.3f:1 against the page it sits on (floor %.2f) — "
									.. "rgb %.3f/%.3f/%.3f on rgb %.3f/%.3f/%.3f",
								entry.id,
								path,
								ratio,
								VISIBLE_FLOOR,
								fill.tintColor.r,
								fill.tintColor.g,
								fill.tintColor.b,
								page.r,
								page.g,
								page.b
							)
						)
					end
				end
			end
		end
		if #problems > 0 then
			error(`{#problems} invisible or missing board cell(s):\n  ` .. table.concat(problems, "\n  ", 1, 8), 2)
		end
		expect(checked).toBe(#THEMES * rules.ROWS * rules.COLS)
		expect(worst.ratio >= VISIBLE_FLOOR).toBe(true)
		game.dispose()
	end)

	it("...and the floor BITES: the plate this example used to paint cannot clear it anywhere", function()
		--[[ A check nobody has watched fail is a check that proves nothing. This
			runs the SAME metric over the SAME themes against the declaration the
			example carried until this round, and it must fail in every one of
			them — at any blend, because the role is the problem, not the amount. ]]
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
				`the old surfaceStrong plate clears the floor in {#cleared} theme(s) (e.g. {cleared[1]}), so this `
					.. "floor would not have caught the defect it was written for",
				2
			)
		end
		-- ...and it is not a near miss: the best the old plate ever managed, in
		-- fifteen themes, is well under the floor
		expect(best < VISIBLE_FLOOR).toBe(true)
	end)
end)

describe("examples/05 word game — the active row's cue is not a colour", function()
	--[[ WHAT THESE CASES MAY READ. Nothing in this block looks at a tint, a
		blend or a colour — that is the whole claim. If every assertion here still
		holds with the paint channel deleted, then a player who cannot separate two
		washes of one role still knows which row is taking their letters. ]]
	local function surfacesByRow(game: any, adapter: any): { { string } }
		local out: { { string } } = {}
		for r = 1, rules.ROWS do
			local row: { string } = {}
			for c = 1, rules.COLS do
				local fill = adapter.node(`{game.tilePath(r, c)}/fill`)
				row[c] = tostring(if fill ~= nil then fill.props.surface else nil)
			end
			out[r] = row
		end
		return out
	end

	it("the caret's PAINT is the empty cell's paint — so colour cannot be the cue", function()
		-- The cue used to be blend 1 against blend 0.6 of one role, which is a
		-- difference in colour and nothing else. The two plates are now identical
		-- BY CONSTRUCTION, which is what forces the cue to live somewhere a
		-- greyscale screen can still show it.
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		expect(game.state(1, 1)).toBe("caret")
		expect(game.state(1, 2)).toBe("empty")
		local caret, empty = game.tint(1, 1), game.tint(1, 2)
		expect(caret.role).toBe(empty.role)
		expect(caret.blend).toBe(empty.blend)
		game.dispose()
	end)

	it("every cell of the ACTIVE row wears the outlined plate, and no other row does", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local rows = surfacesByRow(game, adapter)
		for c = 1, rules.COLS do
			expect(rows[1][c]).toBe("chip")
		end
		for r = 2, rules.ROWS do
			for c = 1, rules.COLS do
				expect(rows[r][c]).toBe("plain")
			end
		end
		game.dispose()
	end)

	it("the outline FOLLOWS the active row, and leaves when nothing is taking letters", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		guess(game, "RULES")
		deps.presenter.refresh()
		local rows = surfacesByRow(game, adapter)
		expect(rows[1][1]).toBe("plain") -- the scored row hands the outline on
		expect(rows[2][1]).toBe("chip")
		expect(rows[3][1]).toBe("plain")
		-- ...and when the game ends there is no active row, so nothing is outlined
		guess(game, "REACT")
		deps.presenter.refresh()
		expect(game.phase()).toBe("won")
		for r = 1, rules.ROWS do
			for c = 1, rules.COLS do
				expect(adapter.node(`{game.tilePath(r, c)}/fill`).props.surface).toBe("plain")
			end
		end
		game.dispose()
	end)

	it("the NEXT LETTER's cell carries a mark that no other cell carries", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		local carets = 0
		for r = 1, rules.ROWS do
			for c = 1, rules.COLS do
				if game.mark(r, c) == "_" then
					carets += 1
					expect(r).toBe(1)
					expect(c).toBe(1)
				end
			end
		end
		expect(carets).toBe(1)
		-- ...and it walks along the row as letters land
		typeWord(game, "RU")
		carets = 0
		for c = 1, rules.COLS do
			if game.mark(1, c) == "_" then
				carets += 1
				expect(c).toBe(3)
			end
		end
		expect(carets).toBe(1)
		game.dispose()
	end)
end)

describe("examples/05 word game — the board holds its letters at every text size", function()
	--[[ THE AXIS, AND THE DEFECT IT FOUND. `preferredTextOffset` is the additive
		px the engine paints every text node with — { 0, 4, 10, 14 }, measured, the
		whole domain of what a player can choose (tests/lib/large_text.luau). A
		tile is sized from a theme metric and the LETTER inside it is not, which is
		the shape `docs/lessons/facet-fixed-px-heights.md` names: this board's tile
		was a `fixed` px cap, and under Fantasy Parchment at the largest preference
		the glyph measured 49px in a 44px box and painted over its neighbours. The
		solver said so; nothing was asking it at that preference.

		Both reference packages, because the second one is where it bit: a theme
		with a taller type ramp reaches the ceiling three preferences earlier. ]]
	it("every letter and mark on the board still has a box that holds it", function()
		for _, theme in large_text.THEMES do
			local core, deps, adapter = makeWorld(PHONE)
			if theme.metrics ~= nil then
				deps.env:set("themeMetrics", theme.metrics)
			end
			local game = newGame(core, deps)
			guess(game, "RULES") -- one scored row plus five untouched ones
			typeWord(game, "ERR") -- ...and a half-typed row, so `filled` is on screen too
			for _, preference in large_text.PREFERENCES do
				deps.env:set("preferredTextOffset", preference.offset)
				deps.presenter.refresh()
				local where = `{theme.id} at {preference.name} (+{preference.offset})`
				-- 1. the solver's own verdict on the board, which is the instrument
				--    that saw the overflow first
				for _, finding in game.handle.controller.diagnostics() do
					if string.find(tostring(finding.node), "/board/", 1, true) ~= nil then
						error(`{where}: {tostring(finding.node)}: {tostring(finding.issue)}`, 2)
					end
				end
				-- 2. ...and the published measurement of every glyph on it
				for r = 1, rules.ROWS do
					for c = 1, rules.COLS do
						for _, id in { "ch", "mark" } do
							local path = `{game.tilePath(r, c)}/{id}`
							local facts = game.handle.controller.textAt(path)
							if facts == nil or type(facts.text) ~= "string" or facts.text == "" then
								continue -- an empty cell draws no glyph, which is not a defect
							end
							local node = adapter.node(path)
							local rect = if node ~= nil then node.rect else nil
							if rect == nil or rect.w <= 0.5 or rect.h <= 0.5 then
								error(`{where}: {path} draws '{facts.text}' in a box nothing can be read out of`, 2)
							end
							if facts.truncated == true then
								error(`{where}: {path} had to cut '{facts.text}' — a board letter is never elided`, 2)
							end
						end
					end
				end
				-- 3. ...and the board still fits the phone it is on
				local board = game.handle.controller.rectOf("/Wordle/page/col/board")
				if board == nil or board.x < 0 or board.x + board.w > PHONE.w then
					error(`{where}: the board no longer fits the phone's width`, 2)
				end
			end
			game.dispose()
		end
	end)
end)
