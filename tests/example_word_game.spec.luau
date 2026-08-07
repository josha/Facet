--!strict
-- The word game's PURE rules and its state machine (roadmap Step 10, EQ-9).
--
-- Two halves, deliberately separated:
--   1. `example.rules` — scoring, the key ladder, the two word lists and the
--      seed. No signals, no adapter, no presenter: a table in, a table out.
--      Every duplicate-letter shape the real game can produce is pinned here,
--      because the letter-budget rule is the only genuinely subtle part of
--      Wordle and it is invisible in the mounted screen until it is wrong.
--   2. the built game — refusals that do not consume a row, retained rows,
--      monotonic key state, win, loss with the word revealed, input disabled
--      after the end, and a deterministic seeded restart.
--
-- The MOUNTED input paths (pointer/touch/keyboard/gamepad) live in
-- tests/examples_games.spec.luau beside the other two games; this file owns the
-- rules and the machine.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local wordGame = require("../examples/gallery/examples/05_word_game")

local rules = wordGame.rules

-- a compact phone MINUS the CoreGui topbar inset: the viewport this example is
-- most likely to be unplayable on, and the one a dev-machine viewport hides
local PHONE = { x = 0, y = 0, w = 360, h = 633 }

local function makeWorld(viewport: any?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", viewport or { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = pres, adapter = adapter }
	return core, deps, adapter
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
		for _, word in rules.SOLUTIONS do
			local s = rules.evaluate(word, word)
			for c = 1, rules.COLS do
				expect(s[c]).toBe("correct")
			end
		end
	end)
end)

describe("examples/05 word game — validation and the two word lists", function()
	it("refuses a guess shorter than five letters", function()
		expect(rules.validate("")).toBe("short")
		expect(rules.validate("REAC")).toBe("short")
	end)

	it("refuses a five-letter non-word", function()
		expect(rules.validate("ZZZZZ")).toBe("unknown")
		expect(rules.validate("QWERT")).toBe("unknown")
	end)

	it("accepts every solution AND the wider guess list", function()
		for _, word in rules.SOLUTIONS do
			expect(rules.ACCEPTED[word]).toBe(true)
		end
		for _, word in { "RULES", "ERROR", "AWARE", "LEVEL", "HOBBY", "EERIE" } do
			expect(rules.validate(word)).toBe("ok")
		end
	end)

	it("the solution list is a SUBSET of the accepted list, and strictly smaller", function()
		local accepted = 0
		for _ in rules.ACCEPTED do
			accepted += 1
		end
		expect(accepted > #rules.SOLUTIONS).toBe(true)
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

	it("consecutive seeds walk the solution list and wrap", function()
		local n = #rules.SOLUTIONS
		for i = 1, n do
			expect(rules.solutionForSeed(i)).toBe(rules.SOLUTIONS[i])
		end
		expect(rules.solutionForSeed(n + 1)).toBe(rules.SOLUTIONS[1])
	end)

	it("seed 1 is REACT, the word the tutorial text quotes", function()
		expect(rules.solutionForSeed(1)).toBe("REACT")
	end)
end)

-- ===========================================================================
describe("examples/05 word game — the state machine", function()
	it("starts on a visible six-by-five board with a caret in the first cell", function()
		local core, deps, adapter = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
		typeWord(game, "ZZZZZ")
		game.press("Return")
		expect(game.activeRow()).toBe(1)
		expect(game.row(1)).toBe("ZZZZZ")
		expect(string.find(game.status(), "not in this tutorial's word list") ~= nil).toBe(true)
		expect(game.state(1, 3)).toBe("filled")
		-- ...and typing again clears the refusal
		game.press("Backspace")
		expect(string.find(game.status(), "not in this tutorial's word list")).toBeNil()
		game.dispose()
	end)

	it("backspace deletes from the active row and stops at empty", function()
		local core, deps = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
		guess(game, "ERROR") -- vs REACT: E present, R correct, then R/O/R absent
		expectStates(game, 1, { "present", "present", "absent", "absent", "absent" })
		game.dispose()
	end)

	it("key state accumulates monotonically and never downgrades", function()
		local core, deps = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local core, deps = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
		expect(game.seed()).toBe(1)
		expect(game.solution()).toBe("REACT")
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
		guess(game, "REACT")
		adapter.tap("/WordleResult/centre/Card/Again")
		expect(deps.presenter.depth()).toBe(1)
		expect(game.phase()).toBe("playing")
		expect(game.seed()).toBe(2)
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps = makeWorld()
		local baseline = core:counters()
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
		assertClean(game.handle, "360x633 portrait, empty board")
		guess(game, "RULES")
		deps.presenter.refresh()
		assertClean(game.handle, "360x633 portrait, one scored row")
		game.dispose()
	end)

	it("the board and every key stay inside the phone's width", function()
		local core, deps = makeWorld(PHONE)
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
		local page = adapter.node("/Wordle/page")
		expect(page ~= nil).toBe(true)
		expect(page.class).toBe("ScrollView")
		game.dispose()
	end)
end)
