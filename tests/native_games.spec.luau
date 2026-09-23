local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose
local words = require("../examples/gallery/examples/words")
local function find(root, name)
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local hit = find(child, name)
		if hit then
			return hit
		end
	end
end
local function findPath(root, path)
	local cursor = root
	for name in string.gmatch(path, "[^/]+") do
		local hit = find(cursor, name)
		if hit then
			cursor = hit
		end
	end
	return if cursor.Name == path:match("([^/]+)$") then cursor else nil
end
local function tap(ctx, path)
	local node = findPath(ctx.node, path)
	node.Activated.fire()
end
local function makeWorld()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local viewport = Compose.cell({ width = 800, height = 600 })
	return {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		guiService = engine.new("GuiService"),
		viewport = viewport,
		runService = { Heartbeat = engine.heartbeat },
		target = target,
		engine = engine,
		UI = Facet.controls(runtime, { types = engine.types, viewport = viewport }),
	}
end
local function mountGame(ctx, definition)
	local game
	local stop, node = ctx.runtime.mount(function()
		game = definition.build(ctx)
		return ctx.Host.ScreenGui({ Name = "GameScreen", game.screen() })
	end, ctx.target)
	ctx.node = node
	game.dispose = function()
		stop()
		ctx.runtime.dispose()
	end
	return game
end
do
	local wordGame = require("../examples/gallery/examples/05_word_game")
	local rules = wordGame.rules
	local REACT_SEED = (function(): number
		for seed = 1, 100000 do
			if rules.solutionForSeed(seed) == "REACT" then
				return seed
			end
		end
		error("example_word_game.spec: no seed in 1..100000 plays REACT — the answer set no longer holds it", 0)
	end)()

	local function newGame(ctx)
		local game = mountGame(ctx, wordGame)
		game.restart(REACT_SEED)
		return game
	end
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

	describe("examples/05 word game — the pure scoring rules", function()
		it("scores a plain guess with no repeated letters", function()
			local s = rules.evaluate("RULES", "REACT")
			expect(s[1]).toBe("correct")
			expect(s[2]).toBe("absent")
			expect(s[3]).toBe("absent")
			expect(s[4]).toBe("present")
			expect(s[5]).toBe("absent")
		end)

		it("a guess with a DOUBLED letter against a solution holding ONE spends the budget once", function()
			local s = rules.evaluate("ERROR", "CRANE")
			expect(s[1]).toBe("present")
			expect(s[2]).toBe("correct")
			expect(s[3]).toBe("absent")
			expect(s[4]).toBe("absent")
			expect(s[5]).toBe("absent")
		end)

		it("a SOLUTION with a doubled letter pays a misplaced guess letter from what the exact match left", function()
			local s = rules.evaluate("LEVEL", "LLAMA")
			expect(s[1]).toBe("correct")
			expect(s[2]).toBe("absent")
			expect(s[3]).toBe("absent")
			expect(s[4]).toBe("absent")
			expect(s[5]).toBe("present")
		end)

		it("BOTH doubled: two exact matches and one misplaced, all from a budget of two", function()
			local s = rules.evaluate("HOBBY", "ABBEY")
			expect(s[1]).toBe("absent")
			expect(s[2]).toBe("absent")
			expect(s[3]).toBe("correct")
			expect(s[4]).toBe("present")
			expect(s[5]).toBe("correct")
		end)

		it("an EXACT match consumes the budget BEFORE an earlier misplaced copy of the same letter", function()
			local s = rules.evaluate("AWARE", "CRANE")
			expect(s[1]).toBe("absent")
			expect(s[2]).toBe("absent")
			expect(s[3]).toBe("correct")
			expect(s[4]).toBe("present")
			expect(s[5]).toBe("correct")
		end)

		it("three copies against two: the excess is absent", function()
			local s = rules.evaluate("EERIE", "REACT")
			expect(s[1]).toBe("absent")
			expect(s[2]).toBe("correct")
			expect(s[3]).toBe("present")
			expect(s[4]).toBe("absent")
			expect(s[5]).toBe("absent")
		end)

		it("the whole solution scores correct", function()
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
			for seed = 1, 200 do
				local answer = rules.solutionForSeed(seed)
				expect(rules.isSolution(answer)).toBe(true)
				expect(rules.validate(answer)).toBe("ok")
			end

			for _, word in { "RULES", "TILES", "ADIEU", "FJORD", "MOCHA", "SUSHI" } do
				expect(rules.validate(word)).toBe("ok")
				expect(rules.isSolution(word)).toBe(false)
			end
		end)

		it("the answer set is a SUBSET of the accepted set, and strictly smaller", function()
			expect(rules.solutionCount > 1000).toBe(true)
			expect(rules.acceptedCount > 3000).toBe(true)
			expect(rules.solutionCount < rules.acceptedCount).toBe(true)
		end)

		it("accepts ordinary words the old hand-typed list refused", function()
			for _, word in { "ADIEU", "FJORD", "MOCHA", "NINJA", "SUSHI", "WALTZ", "SALSA", "ZESTY" } do
				if rules.validate(word) ~= "ok" then
					error(
						`the game still refuses "{word}" — accepting it is the whole point of the shared word data`,
						2
					)
				end
			end
		end)

		it("takes a guess in whatever case it arrives in", function()
			expect(rules.validate("CRANE")).toBe("ok")
			expect(rules.isWord("crane")).toBe(true)
			expect(rules.isWord("CrAnE")).toBe(true)

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

			local second = rules.mergeKeys(first, "REACT", rules.evaluate("REACT", "REACT"))
			expect(second.E).toBe("correct")
			expect(second.R).toBe("correct")
			expect(first.E).toBe("present")
		end)

		it("a later guess that re-tests a solved letter cannot downgrade it", function()
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
			for _, seed in { 1, 2, 7, 41, 1000, 65535, 1e6 } do
				local word = rules.solutionForSeed(seed)
				expect(#word).toBe(rules.COLS)
				expect(rules.isSolution(word)).toBe(true)
				expect(rules.validate(word)).toBe("ok")
			end
		end)

		it("the game plays in UPPERCASE even though the data is lowercase", function()
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

	describe("examples/05 word game — the state machine", function()
		it("starts on a visible six-by-five board with a caret in the first cell", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			for r = 1, rules.ROWS do
				for c = 1, rules.COLS do
					expect(findPath(ctx.node, game.tilePath(r, c)) ~= nil).toBe(true)
				end
			end
			expect(game.state(1, 1)).toBe("caret")
			expect(game.mark(1, 1)).toBe("_")
			expect(game.state(1, 2)).toBe("empty")
			expect(game.state(2, 1)).toBe("empty")
			expect(game.activeRow()).toBe(1)
			game.dispose()
		end)

		it("every tile paints a REAL tint — the plate is never invisible", function()
			local ctx = makeWorld()
			local game = newGame(ctx)

			for r = 1, rules.ROWS do
				for c = 1, rules.COLS do
					local fill = findPath(ctx.node, game.tilePath(r, c) .. "/fill")
					expect(fill ~= nil).toBe(true)
					expect(fill.BackgroundColor3 ~= nil).toBe(true)
					expect(fill.BackgroundColor3 ~= nil).toBe(true)
					expect(fill.BackgroundTransparency).toBe(0)
				end
			end
			game.dispose()
		end)

		it("letters land in the ACTIVE row only", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			typeWord(game, "RULES")
			expect(game.row(1)).toBe("RULES")
			expect(game.row(2)).toBe("")

			game.press("X")
			expect(game.row(1)).toBe("RULES")
			game.press("Return")
			expect(game.activeRow()).toBe(2)
			typeWord(game, "AB")
			expect(game.row(1)).toBe("RULES")
			expect(game.row(2)).toBe("AB")
			game.dispose()
		end)

		it("a SHORT guess is refused with a message and does not consume a row", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			typeWord(game, "REA")
			game.press("Return")
			expect(game.activeRow()).toBe(1)
			expect(game.row(1)).toBe("REA")
			expect(string.find(game.status(), "Not enough letters") ~= nil).toBe(true)
			expect(game.state(1, 1)).toBe("filled")
			game.dispose()
		end)

		it("an INVALID guess is refused with a different message and does not consume a row", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			typeWord(game, "ZZZZZ")
			game.press("Return")
			expect(game.activeRow()).toBe(1)
			expect(game.row(1)).toBe("ZZZZZ")

			expect(string.find(game.status(), "this game doesn't know that word") ~= nil).toBe(true)
			expect(string.find(game.status(), "ZZZZZ", 1, true) ~= nil).toBe(true)
			expect(string.find(game.status(), "word list")).toBeNil()
			expect(game.state(1, 3)).toBe("filled")

			game.press("Backspace")
			expect(string.find(game.status(), "this game doesn't know that word")).toBeNil()
			game.dispose()
		end)

		it("a rejected guess consumes NO row, and an ordinary word the old list refused plays on", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			typeWord(game, "PLZTK")
			game.press("Return")
			expect(game.activeRow()).toBe(1)
			expect(game.phase()).toBe("playing")
			expect(game.state(1, 1)).toBe("filled")
			expect(string.find(game.status(), "this game doesn't know that word") ~= nil).toBe(true)

			for _ = 1, rules.COLS do
				game.press("Backspace")
			end
			guess(game, "MOCHA")
			expect(game.activeRow()).toBe(2)
			expect(game.row(1)).toBe("MOCHA")

			expectStates(game, 1, { "absent", "absent", "present", "absent", "present" })
			game.dispose()
		end)

		it("four words the old thirty-four-word list rejected now play end to end", function()
			for _, word in { "ADIEU", "FJORD", "NINJA", "ZESTY" } do
				local ctx = makeWorld()
				local game = newGame(ctx)
				guess(game, word)
				if game.activeRow() ~= 2 then
					error(
						`"{word}" was refused: the board is still on row {game.activeRow()} and says "{game.status()}"`,
						2
					)
				end
				expect(game.row(1)).toBe(word)

				for c = 1, rules.COLS do
					local state = game.state(1, c)
					expect(state == "correct" or state == "present" or state == "absent").toBe(true)
				end

				expect(game.keyState(string.sub(word, 1, 1)) ~= nil).toBe(true)
				game.dispose()
			end
		end)

		it("backspace deletes from the active row and stops at empty", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
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
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "RULES")
			expectStates(game, 1, { "correct", "absent", "absent", "present", "absent" })
			expect(game.mark(1, 1)).toBe("v")
			expect(game.mark(1, 4)).toBe("~")
			expect(game.mark(1, 2)).toBe("x")
			expect(game.activeRow()).toBe(2)
			guess(game, "ERROR")
			expectStates(game, 1, { "correct", "absent", "absent", "present", "absent" })
			expect(game.activeRow()).toBe(3)
			game.dispose()
		end)

		it("the duplicate-letter rule reaches the board, not just the scorer", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "ERROR")
			expectStates(game, 1, { "present", "present", "absent", "absent", "absent" })
			game.dispose()
		end)

		it("key state accumulates monotonically and never downgrades", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "RULES")
			expect(game.keyState("R")).toBe("correct")
			expect(game.keyState("E")).toBe("present")
			expect(game.keyState("U")).toBe("absent")
			expect(game.keyState("Z")).toBeNil()
			guess(game, "ERROR")
			expect(game.keyState("R")).toBe("correct")
			expect(game.keyState("E")).toBe("present")
			guess(game, "REACT")
			expect(game.keyState("E")).toBe("correct")
			expect(game.keyState("U")).toBe("absent")
			game.dispose()
		end)

		it("wins when the solution is submitted, and opens the results card", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "RULES")
			guess(game, "REACT")
			expect(game.phase()).toBe("won")
			expect(game.won()).toBe(true)
			expect(string.find(game.status(), "Solved in 2 guesses") ~= nil).toBe(true)
			expect(game.resultsOpen()).toBe(true)
			expect((if game.resultsOpen() then 2 else 1)).toBe(2)
			game.dispose()
		end)

		it("loses after SIX accepted wrong guesses and reveals the word", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
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

			expectStates(game, 1, { "correct", "absent", "absent", "present", "absent" })
			game.dispose()
		end)

		it("a refused guess does NOT count toward the six", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			for _, word in { "RULES", "ERROR", "AWARE", "LEVEL", "SOLVE" } do
				guess(game, word)
			end
			expect(game.activeRow()).toBe(6)
			guess(game, "ZZZZZ")
			expect(game.activeRow()).toBe(6)
			expect(game.phase()).toBe("playing")
			for _ = 1, 5 do
				game.press("Backspace")
			end
			guess(game, "TILES")
			expect(game.phase()).toBe("lost")
			game.dispose()
		end)

		it("input is dead after the game ends, except restart", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "REACT")
			expect(game.phase()).toBe("won")
			local before = game.row(1)
			game.press("Z")
			tap(ctx, game.keyPath("Z"))
			game.press("Backspace")
			game.press("Return")
			expect(game.row(1)).toBe(before)
			expect(game.row(2)).toBe("")
			expect(game.phase()).toBe("won")
			expect(findPath(ctx.node, game.keyPath("Z")).Interactable).toBe(false)
			expect(findPath(ctx.node, game.keyPath("Enter")).Interactable).toBe(false)
			expect(findPath(ctx.node, "/Wordle/page/col/Restart").Interactable).toBe(true)
			tap(ctx, "/Close")
			tap(ctx, "/Wordle/page/col/Restart")
			expect(game.phase()).toBe("playing")
			game.dispose()
		end)

		it("restart is deterministic: the same seed replays the same word", function()
			local ctx = makeWorld()
			local game = mountGame(ctx, wordGame)
			expect(game.seed()).toBe(1)
			expect(game.solution()).toBe(rules.solutionForSeed(1))
			guess(game, "RULES")
			game.restart()
			expect(game.seed()).toBe(2)
			expect(game.solution()).toBe(rules.solutionForSeed(2))

			expect(game.row(1)).toBe("")
			expect(game.activeRow()).toBe(1)
			expect(game.phase()).toBe("playing")
			expect(game.keyState("R")).toBeNil()
			expect(game.state(1, 1)).toBe("caret")
			expect(game.state(1, 2)).toBe("empty")

			game.restart(4)
			local first = game.solution()
			guess(game, "RULES")
			game.restart(4)
			expect(game.solution()).toBe(first)
			expect(game.row(1)).toBe("")
			game.dispose()
		end)

		it("restart after a loss closes the results card and re-enables the keyboard", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			for _, word in { "RULES", "ERROR", "AWARE", "LEVEL", "SOLVE", "TILES" } do
				guess(game, word)
			end
			expect(game.resultsOpen()).toBe(true)
			expect((if game.resultsOpen() then 2 else 1)).toBe(2)

			tap(ctx, "/Wordle/page/col/Restart")
			expect(game.resultsOpen()).toBe(true)
			expect(game.phase()).toBe("lost")
			tap(ctx, "/Close")
			expect((if game.resultsOpen() then 2 else 1)).toBe(1)
			tap(ctx, "/Wordle/page/col/Restart")
			expect(game.resultsOpen()).toBe(false)
			expect(game.phase()).toBe("playing")
			expect(findPath(ctx.node, game.keyPath("Z")).Interactable).toBe(true)
			typeWord(game, "AB")
			expect(game.row(1)).toBe("AB")
			game.dispose()
		end)

		it("the results card's Close button actually closes it", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "REACT")
			expect((if game.resultsOpen() then 2 else 1)).toBe(2)
			expect(find(ctx.node, "Close") ~= nil).toBe(true)
			tap(ctx, "/Close")
			expect(game.resultsOpen()).toBe(false)
			expect((if game.resultsOpen() then 2 else 1)).toBe(1)

			expect(game.phase()).toBe("won")
			expect(game.state(1, 1)).toBe("correct")
			game.dispose()
		end)

		it("the results card's New game button restarts from inside the card", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			guess(game, "REACT")
			tap(ctx, "/Again")
			expect((if game.resultsOpen() then 2 else 1)).toBe(1)
			expect(game.phase()).toBe("playing")

			expect(game.seed()).toBe(REACT_SEED + 1)
			expect(game.solution()).toBe(rules.solutionForSeed(REACT_SEED + 1))
			game.dispose()
		end)

		it("tears down to a registry baseline after dispose", function()
			local ctx = makeWorld()
			local baseline = #ctx.target:GetChildren()
			local game = newGame(ctx)
			guess(game, "RULES")
			guess(game, "REACT")
			game.dispose()
			local after = #ctx.target:GetChildren()
			expect(after).toBe(baseline)
		end)
	end)
end
do
	local tileGame = require("../examples/gallery/examples/06_tile_game")
	local rules = tileGame.rules
	local function newGame(ctx)
		return mountGame(ctx, tileGame)
	end
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

	local WIN_SCRIPT: { { { number } } } = {
		{ { 1, 4, 1 }, { 3, 4, 2 }, { 5, 4, 3 }, { 6, 4, 4 }, { 2, 4, 5 } },
		{ { 4, 2, 5 }, { 3, 3, 5 }, { 6, 5, 5 }, { 2, 6, 5 }, { 7, 7, 5 } },
		{ { 1, 2, 1 }, { 4, 2, 2 }, { 5, 2, 3 }, { 6, 2, 4 }, { 7, 2, 6 } },
		{ { 2, 5, 4 }, { 1, 5, 6 }, { 6, 5, 7 } },
	}

	local LOSS_SCRIPT: { { { number } } } = {
		{ { 1, 4, 3 }, { 5, 4, 4 } },
		{ { 6, 3, 4 } },
		{ { 3, 4, 5 } },
		{ { 4, 5, 5 } },
		{ { 2, 5, 6 } },
		{ { 2, 5, 3 } },
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

			local holed = rules.validate(centred, placedOf({ { 4, 2, "C" }, { 4, 6, "T" } }), 2)
			expect(holed.ok).toBe(false)
			expect(holed.code).toBe("gap")
			expect(holed.message).toBe(rules.SAY.gap)

			local closed = rules.validate(centred, placedOf({ { 4, 3, "C" }, { 4, 5, "T" } }), 2)
			expect(closed.ok).toBe(true)
			expect((closed.made :: any)[1].word).toBe("CAT")
		end)

		it("the main word is read THROUGH committed letters at both ends", function()
			local ends = boardOf({ ".......", ".......", ".......", "..C.T..", ".......", ".......", "......." })
			local verdict = rules.validate(ends, placedOf({ { 4, 4, "A" } }), 2)
			expect(verdict.ok).toBe(true)
			expect((verdict.made :: any)[1].word).toBe("CAT")

			expect(verdict.score).toBe(5)
		end)

		it("the first turn must cover the starred centre, and later turns must not", function()
			local offCentre = rules.validate(EMPTY, placedOf({ { 2, 2, "C" }, { 2, 3, "A" }, { 2, 4, "T" } }), 1)
			expect(offCentre.ok).toBe(false)
			expect(offCentre.code).toBe("centre")
			expect(offCentre.message).toBe(rules.SAY.centre)

			local onCentre = rules.validate(EMPTY, placedOf({ { 4, 3, "C" }, { 4, 4, "A" }, { 4, 5, "T" } }), 1)
			expect(onCentre.ok).toBe(true)

			local later = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })
			local away = rules.validate(later, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
			expect(away.ok).toBe(true)
			expect(away.axis).toBe("row")
		end)

		it("connection is ORTHOGONAL: touching diagonally is not touching", function()
			local seeded = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })

			local orthogonal = rules.validate(seeded, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
			expect(orthogonal.ok).toBe(true)

			local floating = rules.validate(seeded, placedOf({ { 6, 6, "A" }, { 6, 7, "N" } }), 2)
			expect(floating.ok).toBe(false)
			expect(floating.code).toBe("connect")
			expect(floating.message).toBe(rules.SAY.connect)

			local diagonal = rules.validate(seeded, placedOf({ { 5, 6, "A" }, { 5, 7, "N" } }), 2)
			expect(diagonal.ok).toBe(false)
			expect(diagonal.code).toBe("connect")
		end)
	end)

	describe("examples/06 crossword — every word a turn creates", function()
		local DON = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })

		it("every perpendicular word a placed tile now sits inside is extracted and validated", function()
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
			local dog = boardOf({ ".......", ".......", ".......", "..DOG..", ".......", ".......", "......." })
			local verdict = rules.validate(dog, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
			expect(verdict.ok).toBe(false)
			expect(verdict.code).toBe("unknownCrossing")
			expect(verdict.word).toBe("GE")
			expect(verdict.message).toBe("That would make GE downward, and that isn't a word this game knows.")

			expect(rules.sayUnknownCrossing("QXZ", "row")).toBe(
				"That would make QXZ across, and that isn't a word this game knows."
			)
		end)

		it("the score counts every letter in every word, once per word it appears in", function()
			local verdict = rules.validate(DON, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)

			expect(verdict.score).toBe(10)
			expect(verdict.bonus).toBe(0)
			local made = verdict.made :: any
			expect(made[1].score).toBe(3)
			expect(made[2].score).toBe(3)
			expect(made[3].score).toBe(2)
			expect(made[4].score).toBe(2)

			expect(made[1].score + made[2].score + made[3].score + made[4].score).toBe(verdict.score)
		end)

		it("using five or more rack tiles in one turn adds ten", function()
			local four =
				rules.validate(EMPTY, placedOf({ { 4, 3, "H" }, { 4, 4, "E" }, { 4, 5, "N" }, { 4, 6, "S" } }), 1)
			expect(four.ok).toBe(true)
			expect(four.tiles).toBe(4)
			expect(four.bonus).toBe(0)
			expect(four.score).toBe(4 + 1 + 1 + 1)

			local five = rules.validate(
				EMPTY,
				placedOf({ { 4, 2, "E" }, { 4, 3, "A" }, { 4, 4, "R" }, { 4, 5, "E" }, { 4, 6, "D" } }),
				1
			)
			expect(five.ok).toBe(true)
			expect(five.tiles).toBe(5)
			expect(five.bonus).toBe(10)
			expect(five.score).toBe(1 + 1 + 1 + 1 + 2 + 10)

			expect(string.find(five.message, "+10 for using 5 tiles", 1, true) ~= nil).toBe(true)
		end)
	end)

	describe("examples/06 crossword — the dictionary is the shared module", function()
		it("accepts and rejects through `words`, not through a list this game keeps", function()
			for _, word in { "EARED", "IODIDE", "QUALIA", "NIPS", "DON", "QI" } do
				expect(rules.wordVerdict(word)).toBe("ok")
				expect(words.isWord(word)).toBe(true)
			end
			expect(rules.wordVerdict("PLZTK")).toBe("unknown")
			expect(rules.wordVerdict("A")).toBe("unknown")
		end)

		it("a run the dictionary CANNOT judge is refused by name, not called unknown", function()
			expect(words.isWord("ELEPHANT")).toBe(false)
			expect(rules.wordVerdict("ELEPHANT")).toBe("long")
			expect(rules.SAY.long).toBe("This game only knows words up to seven letters long.")
			expect(rules.MAX_WORD).toBe(words.MAX_LENGTH)

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
			local worst = 0
			for seed = 1, 200 do
				local dealt = rules.deal(rules.makeRng(seed))
				if dealt.opening == nil then
					error(`seed {seed} dealt {table.concat(dealt.rack)} with no opening word`, 2)
				end
				worst = math.max(worst, dealt.attempts)
			end
			expect(worst <= rules.DEAL_ATTEMPTS).toBe(true)

			expect(worst <= 3).toBe(true)
		end)

		it("openingWord finds a word from a SUBSET in any order, and nil when there is none", function()
			expect(rules.openingWord({ "T", "A", "C" }) ~= nil).toBe(true)
			expect(rules.openingWord({ "C", "A", "T", "X", "Z", "Q", "V" }) ~= nil).toBe(true)
			expect(rules.openingWord({ "V", "V", "V" })).toBeNil()
		end)
	end)

	describe("examples/06 crossword — nine refusals, nine sentences, on screen", function()
		local function said(game: any): string
			return game.wordText()
		end

		local function hint(game: any): string
			return game.hintText()
		end

		it("1 — the first turn misses the centre", function()
			local ctx = makeWorld()
			local game = newGame(ctx)

			game.select(1)
			game.place(1, 1)
			game.select(2)
			game.place(1, 2)
			game.submit()
			expect(said(game)).toBe("Your first word has to cover the starred centre square.")
			expect(game.turn()).toBe(1)
			game.dispose()
		end)

		it("2 — the tiles are not in one line", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.select(1)
			game.place(4, 4)
			game.select(2)
			game.place(5, 5)
			game.submit()
			expect(said(game)).toBe("The tiles you place in a turn go in a single row or a single column.")
			game.dispose()
		end)

		it("3 — a gap in the run", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.select(1)
			game.place(4, 4)
			game.select(2)
			game.place(4, 7)
			game.submit()
			expect(said(game)).toBe(
				"Leave no gaps — your tiles and the letters already on the board have to make one unbroken run."
			)
			game.dispose()
		end)

		it("4 — a later turn touches nothing", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT, 1)
			expect(game.turn()).toBe(2)

			game.select(1)
			game.place(7, 1)
			game.select(2)
			game.place(7, 2)
			game.submit()
			expect(said(game)).toBe("After the first turn, a word has to touch a letter already on the board.")
			game.dispose()
		end)

		it("5 — the main word is unknown, and the sentence names it", function()
			local ctx = makeWorld()
			local game = newGame(ctx)

			game.select(1)
			game.place(4, 4)
			game.select(2)
			game.place(4, 5)
			game.select(3)
			game.place(4, 6)
			game.submit()
			expect(said(game)).toBe("EDA isn't a word this game knows.")

			expect(rules.sayUnknown("PLZTK")).toBe("PLZTK isn't a word this game knows.")
			game.dispose()
		end)

		it("6 — a crossing word is unknown, and the sentence names it AND its direction", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT, 1)

			game.select(5)
			game.place(5, 1)
			game.select(4)
			game.place(5, 2)
			game.submit()
			expect(said(game)).toBe("That would make EA downward, and that isn't a word this game knows.")

			expect(game.pendingAt(5, 1)).toBe("A")
			expect(game.pendingAt(5, 2)).toBe("I")
			expect(game.turn()).toBe(2)
			game.dispose()
		end)

		it("7 — submit with nothing placed", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.submit()
			expect(said(game)).toBe("Place at least one tile before you submit.")
			game.dispose()
		end)

		it("8 — placing on an occupied square", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.select(1)
			game.place(4, 4)
			game.select(2)
			game.place(4, 4)
			expect(said(game)).toBe("That square already has a letter.")

			expect(game.selected()).toBe(2)
			game.dispose()
		end)

		it("8b — an off-board square takes nothing, so a stray call cannot beach a tile", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.select(1)
			game.place(9, 9)

			expect(game.selected()).toBe(1)
			game.place(4, 4)
			expect(game.selected()).toBe(nil)
			game.dispose()
		end)

		it("9 — picking up a letter from an earlier turn", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT, 1)
			expect(game.committedAt(4, 1)).toBe("E")
			game.place(4, 1)
			expect(said(game)).toBe("Letters from an earlier turn stay put.")
			expect(game.committedAt(4, 1)).toBe("E")
			game.dispose()
		end)

		it("...and an uncommitted tile CAN be picked back up, which is what makes 9 a rule", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			local letter = game.rackLetter(1)
			game.select(1)
			game.place(4, 4)
			expect(game.pendingAt(4, 4)).toBe(letter)
			expect(game.rackLetter(1)).toBeNil()
			game.place(4, 4)
			expect(game.pendingAt(4, 4)).toBeNil()
			expect(game.rackLetter(1)).toBe(letter)
			expect(said(game)).toBe("No tiles placed this turn.")
			game.dispose()
		end)

		it("...and tapping an empty square with nothing held explains itself too", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.place(1, 1)
			expect(said(game)).toBe("Pick a letter from your rack first, then choose a square.")

			expect(hint(game)).toBe("Cover the starred square with a word to begin.")
			game.dispose()
		end)

		it("the instruction line names the held tile, and clears on a placement", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			expect(hint(game)).toBe("Cover the starred square with a word to begin.")
			local letter = game.rackLetter(1)
			game.select(1)
			expect(hint(game)).toBe(`Placing {letter} — choose a square.`)
			game.place(4, 4)
			expect(hint(game)).toBe("Cover the starred square with a word to begin.")
			expect(said(game)).toBe(`{letter} isn't a word this game knows.`)
			game.dispose()
		end)
	end)

	describe("examples/06 crossword — commit, refill, undo, budget", function()
		it("a committed turn scores, banks the letters, and refills the rack to seven", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT, 1)
			expect(game.score()).toBe(16)
			expect(game.committedAt(4, 1)).toBe("E")
			expect(game.committedAt(4, 5)).toBe("D")
			expect(game.pendingAt(4, 1)).toBeNil()
			expect(game.rackCount()).toBe(7)

			expect(game.turn()).toBe(2)
			game.dispose()
		end)

		it("undo returns exactly the uncommitted tiles, to the slots they came from", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT, 1)
			local before = game.dump()
			local rackBefore = {}
			for slot = 1, 7 do
				rackBefore[slot] = game.rackLetter(slot)
			end

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

			expect(game.selected()).toBeNil()
			game.select(4)
			game.place(3, 4)
			expect(game.pendingAt(3, 4) ~= nil).toBe(true)
			game.dispose()
		end)

		it("undo with nothing placed says so instead of doing nothing", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.undo()
			expect(findPath(ctx.node, game.wordPath).Text).toBe(
				"Nothing to undo — you have not placed a tile this turn."
			)
			game.dispose()
		end)

		it("A REFUSED SUBMIT CHANGES NOTHING — every tile stays where the player put it", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			game.select(1)
			game.place(4, 4)
			game.select(2)
			game.place(4, 5)
			game.select(3)
			game.place(4, 6)
			local before = game.dump()
			local counters = #ctx.target:GetChildren()
			game.submit()
			expect(game.dump()).toBe(before)
			expect(game.score()).toBe(0)
			expect(game.turn()).toBe(1)
			expect(game.rackCount()).toBe(4)
			expect(game.pendingAt(4, 4) ~= nil).toBe(true)
			expect(game.pendingAt(4, 5) ~= nil).toBe(true)
			expect(game.pendingAt(4, 6) ~= nil).toBe(true)
			expect(game.committedAt(4, 4)).toBeNil()

			for _ = 1, 20 do
				game.submit()
			end
			expect(game.dump()).toBe(before)
			expect(#ctx.target:GetChildren()).toBe(counters)
			game.dispose()
		end)

		it("the turn budget decrements only on a commit", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			expect(game.turnsLeft()).toBe(6)
			game.submit()
			expect(game.turnsLeft()).toBe(6)
			game.select(1)
			game.place(4, 4)
			game.select(2)
			game.place(4, 5)
			game.submit()
			expect(game.turnsLeft()).toBe(6)
			game.undo()
			expect(game.turnsLeft()).toBe(6)
			play(game, WIN_SCRIPT, 1)
			expect(game.turnsLeft()).toBe(5)
			game.dispose()
		end)

		it("the legal-next-cell cue follows the rules, and locks with the axis", function()
			local ctx = makeWorld()
			local game = newGame(ctx)

			expect(game.cellState(4, 4)).toBe("centre")
			expect(game.cellState(1, 1)).toBe("idle")
			game.select(1)
			game.place(4, 4)

			expect(game.cellState(4, 3)).toBe("legal")
			expect(game.cellState(3, 4)).toBe("legal")
			game.select(2)
			game.place(4, 5)

			expect(game.cellState(4, 3)).toBe("legal")
			expect(game.cellState(3, 4)).toBe("idle")
			expect(game.cellState(4, 4)).toBe("pending")
			game.dispose()
		end)
	end)

	describe("examples/06 crossword — both endings, and the way back", function()
		it("reaching the goal wins, and the screen says which ending it was", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT)
			expect(game.phase()).toBe("won")
			expect(game.score()).toBe(67)
			expect(game.score() >= rules.GOAL).toBe(true)
			local hint = findPath(ctx.node, game.hintPath).Text
			expect(string.find(hint, "you win!", 1, true) ~= nil).toBe(true)
			expect(string.find(hint, "67 points", 1, true) ~= nil).toBe(true)
			expect(string.find(hint, "4 of 6 turns", 1, true) ~= nil).toBe(true)

			local dump = game.dump()
			game.select(1)
			game.place(1, 1)
			game.submit()
			expect(game.dump()).toBe(dump)

			tap(ctx, game.resetPath)
			expect(game.phase()).toBe("playing")
			expect(game.score()).toBe(0)
			game.dispose()
		end)

		it("spending the budget without reaching the goal loses, and says so", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			play(game, LOSS_SCRIPT)
			expect(game.phase()).toBe("lost")
			expect(game.score()).toBe(14)
			expect(game.turnsLeft()).toBe(0)
			local hint = findPath(ctx.node, game.hintPath).Text
			expect(hint).toBe("Out of turns at 14 of 60 points. Press Start over to play again.")
			tap(ctx, game.resetPath)
			expect(game.phase()).toBe("playing")
			expect(game.turnsLeft()).toBe(6)
			game.dispose()
		end)

		it("restart returns EVERY observable to its seeded start", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			local start = game.dump()
			local startHint = game.hintText()
			local startWord = game.wordText()
			play(game, WIN_SCRIPT, 2)
			game.select(1)
			game.place(1, 1)
			game.select(2)
			game.place(4, 1)
			expect(game.score() > 0).toBe(true)
			tap(ctx, game.resetPath)
			expect(game.dump()).toBe(start)
			expect(game.hintText()).toBe(startHint)
			expect(game.wordText()).toBe(startWord)
			expect(game.selected()).toBeNil()
			expect(game.turn()).toBe(1)

			play(game, WIN_SCRIPT, 1)
			expect(game.score()).toBe(16)
			game.dispose()
		end)
	end)

	describe("examples/06 crossword — determinism", function()
		it("the same seed deals the same rack and the same bag", function()
			local ctx = makeWorld()
			local a = newGame(ctx)
			local ctx2 = makeWorld()
			local b = newGame(ctx2)
			for slot = 1, 7 do
				expect(b.rackLetter(slot)).toBe(a.rackLetter(slot))
			end
			expect(b.dump()).toBe(a.dump())

			play(a, WIN_SCRIPT, 1)
			play(b, WIN_SCRIPT, 1)
			expect(b.dump()).toBe(a.dump())

			b.reset(rules.DEFAULT_SEED + 1)
			expect(b.dump() ~= a.dump()).toBe(true)
			a.dispose()
			b.dispose()
		end)

		it("a fixed script on a fixed seed lands on the same board, score and dump", function()
			local ctx = makeWorld()
			local a = newGame(ctx)
			play(a, WIN_SCRIPT)
			expect(a.dump()).toBe(
				"......./QUALIA./....O../EARED../...NIPS/....D../....E..|rack=EARVGEL|score=67|turn=5|phase=won"
			)
			local ctx2 = makeWorld()
			local b = newGame(ctx2)
			play(b, WIN_SCRIPT)
			expect(b.dump()).toBe(a.dump())

			b.reset(rules.DEFAULT_SEED)
			play(b, WIN_SCRIPT)
			expect(b.dump()).toBe(a.dump())
			a.dispose()
			b.dispose()
		end)
	end)

	describe("examples/06 crossword — robustness", function()
		it("rapid alternating input leaves no stale selection or held tile", function()
			local ctx = makeWorld()
			local game = newGame(ctx)
			for _ = 1, 20 do
				tap(ctx, game.rackPath(1))
				tap(ctx, game.cellPath(4, 4))
				tap(ctx, game.cellPath(4, 4))
				tap(ctx, game.submitPath)
				tap(ctx, game.undoPath)
				tap(ctx, game.rackPath(2))
				tap(ctx, game.rackPath(2))
				tap(ctx, game.resetPath)
			end
			expect(game.selected()).toBeNil()
			expect(game.rackCount()).toBe(7)
			expect(game.score()).toBe(0)
			expect(game.turn()).toBe(1)
			expect(game.phase()).toBe("playing")
			game.dispose()
		end)

		it("tears down to a registry baseline after dispose", function()
			local ctx = makeWorld()
			local baseline = #ctx.target:GetChildren()
			local game = newGame(ctx)
			play(game, WIN_SCRIPT, 2)
			tap(ctx, game.rackPath(1))
			tap(ctx, game.cellPath(1, 1))
			game.dispose()
			local after = #ctx.target:GetChildren()
			expect(after).toBe(baseline)
		end)
	end)
end

do
	local match3 = require("../examples/gallery/examples/07_match3")
	local swapBoard = {
		{ "a", "a", "b", "c", "d", "e" },
		{ "c", "d", "a", "e", "b", "c" },
		{ "e", "b", "c", "d", "a", "b" },
		{ "b", "c", "d", "e", "c", "a" },
		{ "d", "e", "b", "a", "e", "d" },
		{ "a", "c", "e", "b", "d", "c" },
	}
	local dropBoard = {
		{ "b", "c", "d", "e", "a", "b" },
		{ "c", "d", "e", "a", "b", "c" },
		{ "a", "a", "b", "d", "e", "a" },
		{ "d", "e", "a", "b", "c", "d" },
		{ "e", "a", "b", "c", "d", "e" },
		{ "a", "b", "c", "d", "e", "a" },
	}
	local function newGame(board, reduced)
		local ctx = makeWorld()
		ctx.guiService.ReducedMotionEnabled = reduced == true
		local game = mountGame(ctx, match3)
		game.debugSetBoard(board or swapBoard)
		return game, ctx
	end
	local function tile(ctx, id)
		return find(ctx.node, "tile" .. id)
	end
	local function advanceTo(game, ctx, phase)
		for _ = 1, 2400 do
			if game.phase() == phase then
				return
			end
			ctx.engine.heartbeat.fire(0.01)
		end
		error("Match3 did not reach " .. phase)
	end
	local function sameArray(actual, expected)
		expect(#actual).toBe(#expected)
		for index, value in expected do
			expect(actual[index]).toBe(value)
		end
	end
	describe("examples/07 native Match3 parity", function()
		it("keeps tile identity while a valid swap travels between endpoints", function()
			local game, ctx = newGame()
			local id = game.tileIdAt(1, 3)
			local original = tile(ctx, id)
			expect(original.Position.Y.Offset).toBe(0)
			game.swap(1, 3, 2, 3)
			expect(game.tileIdAt(2, 3)).toBe(id)
			expect(tile(ctx, id)).toBe(original)
			ctx.engine.heartbeat.fire(0.05)
			expect(original.Position.Y.Offset > 0 and original.Position.Y.Offset < 48).toBe(true)
			expect(game.phase()).toBe("swap")
			game.dispose()
			expect(original.isDestroyed()).toBe(true)
			expect(ctx.engine.heartbeat.count()).toBe(0)
		end)

		it("fades retiring tiles then drops survivors and introduces new tiles above the board", function()
			local game, ctx = newGame(dropBoard)
			local oldIds = game.tileIds()
			local removed = tile(ctx, game.tileIdAt(3, 1))
			local survivorId = game.tileIdAt(2, 1)
			local survivor = tile(ctx, survivorId)
			game.swap(3, 3, 4, 3)
			advanceTo(game, ctx, "remove")
			expect(game.tileIdAt(3, 1)).toBe(nil)
			expect(removed.isDestroyed()).toBe(false)
			ctx.engine.heartbeat.fire(0.04)
			expect(removed.GroupTransparency > 0 and removed.GroupTransparency < 1).toBe(true)
			advanceTo(game, ctx, "gravity")
			expect(removed.isDestroyed()).toBe(true)
			expect(game.tileIdAt(3, 1)).toBe(survivorId)
			ctx.engine.heartbeat.fire(0.04)
			expect(survivor.Position.Y.Offset > 48 and survivor.Position.Y.Offset < 96).toBe(true)
			advanceTo(game, ctx, "refill")
			local newId = game.tileIdAt(1, 1)
			local arrived = tile(ctx, newId)
			expect(table.find(oldIds, newId)).toBe(nil)
			expect(arrived.Position.Y.Offset < 0).toBe(true)
			local startY = arrived.Position.Y.Offset
			advanceTo(game, ctx, "land")
			ctx.engine.heartbeat.fire(0.04)
			expect(arrived.Position.Y.Offset > startY and arrived.Position.Y.Offset < 0).toBe(true)
			advanceTo(game, ctx, "idle")
			expect(#game.tileIds()).toBe(36)
			expect(game.moves()).toBe(1)
			expect(game.score() >= 3).toBe(true)
			game.dispose()
			expect(ctx.engine.heartbeat.count()).toBe(0)
		end)

		it("reverts a refused swap and keeps the board and move budget unchanged", function()
			local game, ctx = newGame()
			local before = game.boardSnapshot()
			local id = game.tileIdAt(1, 1)
			local original = tile(ctx, id)
			game.swap(1, 1, 1, 2)
			ctx.engine.heartbeat.fire(0.05)
			expect(original.Position.X.Offset > 0 and original.Position.X.Offset < 48).toBe(true)
			advanceTo(game, ctx, "revert")
			local departingX = original.Position.X.Offset
			ctx.engine.heartbeat.fire(0.05)
			expect(original.Position.X.Offset < departingX).toBe(true)
			advanceTo(game, ctx, "idle")
			sameArray(game.boardSnapshot(), before)
			expect(game.tileIdAt(1, 1)).toBe(id)
			expect(game.moves()).toBe(0)
			expect(string.find(game.hintText(), "no run", 1, true) ~= nil).toBe(true)
			game.dispose()
		end)

		it("keeps deterministic results under native reduced motion and changes paint immediately", function()
			local outcomes = {}
			for _, reduced in { false, true } do
				local game, ctx = newGame(swapBoard, reduced)
				local moving = tile(ctx, game.tileIdAt(1, 3))
				game.swap(1, 3, 2, 3)
				expect(moving.Position.Y.Offset).toBe(if reduced then 48 else 0)
				advanceTo(game, ctx, "idle")
				table.insert(outcomes, {
					board = game.boardSnapshot(),
					score = game.score(),
					moves = game.moves(),
					log = game.phaseLog(),
					ids = game.tileIds(),
				})
				game.dispose()
			end
			sameArray(outcomes[1].board, outcomes[2].board)
			sameArray(outcomes[1].log, outcomes[2].log)
			sameArray(outcomes[1].ids, outcomes[2].ids)
			expect(outcomes[1].score).toBe(outcomes[2].score)
			expect(outcomes[1].moves).toBe(outcomes[2].moves)
			local game, ctx = newGame()
			local moving = tile(ctx, game.tileIdAt(1, 3))
			game.swap(1, 3, 2, 3)
			ctx.engine.heartbeat.fire(0.03)
			ctx.guiService.ReducedMotionEnabled = true
			expect(moving.Position.Y.Offset).toBe(48)
			game.dispose()
			expect(ctx.guiService:GetPropertyChangedSignal("ReducedMotionEnabled").count()).toBe(0)
		end)

		it("retries failed artwork through native controls without replacing tile identity", function()
			local game, ctx = newGame()
			local original = tile(ctx, game.tileIdAt(1, 1))
			local image = find(original, "img")
			local asset = image.Image
			find(ctx.node, "Break").Activated.fire()
			expect(image.Image).toBe(game.pendingImage)
			expect(string.find(game.artStatusText(), "failed", 1, true) ~= nil).toBe(true)
			expect(find(original, "hit").Text ~= "").toBe(true)
			find(ctx.node, "Reload").Activated.fire()
			expect(string.find(game.artStatusText(), "loading 5", 1, true) ~= nil).toBe(true)
			find(ctx.node, "Deliver").Activated.fire()
			expect(image.Image).toBe(asset)
			expect(game.artStatusText()).toBe("Artwork: all 5 ready")
			expect(tile(ctx, game.tileIdAt(1, 1))).toBe(original)
			expect(find(original, "hit").Text).toBe("")
			game.dispose()
		end)

		it("selects detector taps once and swaps adjacent tiles with mouse and touch", function()
			local game, ctx = newGame()
			local first = find(tile(ctx, game.tileIdAt(1, 3)), "hit")
			local second = find(tile(ctx, game.tileIdAt(2, 3)), "hit")
			for _, hit in { first, second } do
				hit.AbsolutePosition = ctx.types.Vector2.new(100, 100)
				hit.AbsoluteSize = ctx.types.Vector2.new(44, 44)
			end
			local origin = ctx.types.Vector2.new(120, 120)
			local mouse = { UserInputType = ctx.types.Enum.UserInputType.MouseButton1 }
			local touch = { UserInputType = ctx.types.Enum.UserInputType.Touch }
			local firstDrag = find(first, "SwapDrag")
			firstDrag.DragStart.fire(origin)
			firstDrag.DragEnd.fire(origin)
			expect(first:GetAttribute("selected")).toBe(true)
			first.Activated.fire(mouse)
			expect(first:GetAttribute("selected")).toBe(true)
			firstDrag.DragStart.fire(origin)
			firstDrag.DragEnd.fire(origin)
			first.Activated.fire(mouse)
			expect(first:GetAttribute("selected")).toBe(false)
			firstDrag.DragStart.fire(origin)
			firstDrag.DragEnd.fire(origin)
			local secondDrag = find(second, "SwapDrag")
			secondDrag.DragStart.fire(origin)
			secondDrag.DragContinue.fire(origin + ctx.types.Vector2.new(3, 2))
			secondDrag.DragEnd.fire(origin + ctx.types.Vector2.new(3, 2))
			second.Activated.fire(touch)
			expect(game.isResolving()).toBe(true)
			advanceTo(game, ctx, "idle")
			expect(game.moves()).toBe(1)
			expect(game.score() >= 3).toBe(true)
			game.dispose()
		end)

		it("uses detector release position and preserves the next keyboard activation after dragging", function()
			local game, ctx = newGame()
			local first = find(tile(ctx, game.tileIdAt(1, 1)), "hit")
			local drag = find(first, "SwapDrag")
			drag.DragStart.fire(ctx.types.Vector2.new(20, 20))
			drag.DragEnd.fire(ctx.types.Vector2.new(52, 20))
			first.Activated.fire({ UserInputType = ctx.types.Enum.UserInputType.MouseButton1 })
			expect(game.isResolving()).toBe(true)
			advanceTo(game, ctx, "idle")
			expect(game.moves()).toBe(0)
			first.SelectionGained.fire()
			find(ctx.target, "Activate").Pressed.fire()
			expect(first:GetAttribute("selected")).toBe(true)
			first.Activated.fire({ UserInputType = ctx.types.Enum.UserInputType.Gamepad1 })
			expect(first:GetAttribute("selected")).toBe(false)
			game.dispose()
		end)

		it("cancels uncaptured releases, outside taps and drags that return to their start", function()
			local game, ctx = newGame()
			local first = find(tile(ctx, game.tileIdAt(1, 1)), "hit")
			first.AbsolutePosition = ctx.types.Vector2.new(100, 100)
			first.AbsoluteSize = ctx.types.Vector2.new(44, 44)
			local drag = find(first, "SwapDrag")
			local origin = ctx.types.Vector2.new(140, 120)
			drag.DragEnd.fire(origin)
			expect(first:GetAttribute("selected")).toBe(false)
			drag.DragStart.fire(origin)
			drag.DragEnd.fire(origin + ctx.types.Vector2.new(8, 0))
			expect(first:GetAttribute("selected")).toBe(false)
			drag.DragStart.fire(origin)
			drag.DragContinue.fire(origin + ctx.types.Vector2.new(32, 0))
			drag.DragEnd.fire(origin)
			expect(first:GetAttribute("selected")).toBe(false)
			expect(game.isResolving()).toBe(false)
			expect(game.moves()).toBe(0)
			game.dispose()
		end)

		it("selects with native keyboard and gamepad events and keeps grid neighbors current", function()
			local game, ctx = newGame()
			local first = find(tile(ctx, game.tileIdAt(1, 3)), "hit")
			local second = find(tile(ctx, game.tileIdAt(2, 3)), "hit")
			expect(first.NextSelectionDown).toBe(second)
			expect(first.NextSelectionRight).toBe(find(tile(ctx, game.tileIdAt(1, 4)), "hit"))
			first.SelectionGained.fire()
			local action = find(ctx.target, "Activate")
			expect(action ~= nil).toBe(true)
			action.Pressed.fire()
			expect(first:GetAttribute("selected")).toBe(true)
			first.SelectionLost.fire()
			second.Activated.fire({
				UserInputType = ctx.types.Enum.UserInputType.Gamepad1,
				KeyCode = ctx.types.Enum.KeyCode.ButtonA,
			})
			expect(game.isResolving()).toBe(true)
			expect(game.tileIdAt(2, 3) ~= nil).toBe(true)
			advanceTo(game, ctx, "idle")
			for row = 1, 6 do
				for col = 1, 5 do
					local hit = find(tile(ctx, game.tileIdAt(row, col)), "hit")
					expect(hit.NextSelectionRight).toBe(find(tile(ctx, game.tileIdAt(row, col + 1)), "hit"))
				end
			end
			game.dispose()
		end)
	end)
end
