--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local expect = Verify.expect
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local Compose: ComposeModule = Facet.Compose
	local ComposeTypes = require("../src/vendor/compose/core/reactive/types")
	local words = require("../examples/gallery/examples/words")
	type World = {
		Facet: typeof(Facet),
		Compose: typeof(Compose),
		runtime: Facet.Runtime,
		Host: RobloxHost,
		types: RobloxTypes,
		viewport: typeof(Compose.cell({ width = 0, height = 0 })),
		engine: engineLib.Engine,
		node: any,
		target: any,
		guiService: any,
		inputTarget: any,
		worldTarget: any,
		runService: { Heartbeat: typeof(engineLib.new().heartbeat) },
		[string]: any,
	}
	local function find(root: any, name: string): any
		if root.Name == name then
			return root
		end
		for _, child in root:GetChildren() do
			local hit = find(child, name)
			if hit then
				return hit
			end
		end
		return nil
	end
	local function findPath(root: any, path: string): any
		local cursor = root
		for name in string.gmatch(path, "[^/]+") do
			local hit = find(cursor, name)
			if hit then
				cursor = hit
			end
		end
		return if cursor.Name == path:match("([^/]+)$") then cursor else nil
	end
	local function tap(ctx: World, path: string)
		local node = findPath(ctx.node, path)
		node.Activated:Fire()
	end
	local function makeWorld(): World
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("Folder")
		local viewport = Compose.cell({ width = 800, height = 600 })
		return {
			node = nil,
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = engine.new("GuiService"),
			viewport = viewport,
			runService = { Heartbeat = engine.heartbeat },
			target = target,
			engine = engine,
		}
	end
	local function mountGame(ctx: World, definition: any): any
		local game
		local stop, node = ctx.runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = Facet.controls(ctx.runtime, {
				types = ctx.types,
				environment = {
					viewportSize = Compose.formula(function(use: Use): Vector2?
						local v = use(ctx.viewport)
						return ctx.types.Vector2.new(v.width, v.height)
					end),
				},
				motionLevel = (
						Compose.formula(function(use: Use): "normal" | "limited" | "none"
							return (
								if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
							) :: "none" | "normal" | "limited"
						end) :: unknown
					) :: ComposeTypes.Formula<"none" | "normal" | "limited">,
			})
			game = definition.build(ctx)
			return ctx.Host.ScreenGui "GameScreen" { game.screen() }
		end, ctx.target)
		ctx.node = node
		game.dispose = function()
			stop()
			ctx.runtime:dispose()
		end
		return game
	end
	do
		local wordGame = require("../examples/gallery/examples/05_word_game")
		local rules = wordGame.rules
		local READER_SEED = (function(): number
			for seed = 1, 100000 do
				if rules.solutionForSeed(seed) == "READER" then
					return seed
				end
			end
			error("example_word_game.spec: no seed in 1..100000 plays READER — the answer set no longer holds it", 0)
		end)()

		local function newGame(ctx: World)
			local game = mountGame(ctx, wordGame)
			game.restart(READER_SEED)
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

		verifyHarness:suite("examples/05 word game — the key ladder is monotonic", function()
			verifyHarness:case("mergeKeys returns a NEW table and keeps the strongest per letter", {
				id = "native_games::examples/05 word game — the key ladder is monotonic::mergeKeys returns a NEW table and keeps the strongest per letter",
				run = function()
					local first = rules.mergeKeys({}, "RULERS", rules.evaluate("RULERS", "READER"))
					expect(first.R):toBe("correct")
					expect(first.E):toBe("present")
					expect(first.U):toBe("absent")

					local second = rules.mergeKeys(first, "READER", rules.evaluate("READER", "READER"))
					expect(second.E):toBe("correct")
					expect(second.R):toBe("correct")
					expect(first.E):toBe("present")
				end,
			})

			verifyHarness:case("a later guess that re-tests a solved letter cannot downgrade it", {
				id = "native_games::examples/05 word game — the key ladder is monotonic::a later guess that re-tests a solved letter cannot downgrade it",
				run = function()
					local keys = rules.mergeKeys({}, "READER", rules.evaluate("READER", "READER"))
					expect(keys.R):toBe("correct")
					local after = rules.mergeKeys(keys, "ERRORS", rules.evaluate("ERRORS", "READER"))
					expect(after.R):toBe("correct")
				end,
			})
		end)

		verifyHarness:suite("examples/05 word game — the state machine", function()
			verifyHarness:case("paints key and tile state through theme status tags and outlines the active row", {
				id = "native_games::examples/05 word game — the state machine::paints key and tile state through theme status tags and outlines the active row",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					guess(game, "RULERS")
					local function key(letter)
						return findPath(ctx.node, game.keyPath(letter))
					end
					expect((key("R"):HasTag("facet-status-success"))):toBe(true)
					expect((key("E"):HasTag("facet-status-warning"))):toBe(true)
					expect((key("U"):HasTag("facet-status-neutral"))):toBe(true)
					expect((key("U"):HasTag("facet-status-success"))):toBe(false)
					for _, status in { "success", "warning", "neutral" } :: { "neutral" | "success" | "warning" } do
						expect((key("Z"):HasTag("facet-status-" .. status))):toBe(false)
					end
					local function fill(r, c)
						return findPath(ctx.node, game.tilePath(r, c) .. "/fill")
					end
					expect((fill(1, 1):HasTag("facet-status-success"))):toBe(true)
					expect((fill(1, 4):HasTag("facet-status-warning"))):toBe(true)
					expect((fill(1, 2):HasTag("facet-status-neutral"))):toBe(true)
					expect((fill(2, 1):HasTag("facet-control"))):toBe(true)
					expect((fill(2, 1):HasTag("facet-status-neutral"))):toBe(false)
					local function outline(r, c)
						return findPath(ctx.node, game.tilePath(r, c) .. "/Cursor")
					end
					expect((outline(2, 1):HasTag("facet-status-ring"))):toBe(true)
					expect((outline(2, 1).Parent:HasTag("facet-status-accent"))):toBe(true)
					expect(outline(2, 1).Enabled):toBe(true)
					expect(outline(2, 2).Enabled):toBe(false)
					expect(outline(1, 1).Enabled):toBe(false)
					guess(game, "ERRORS")
					expect(outline(2, 1).Enabled):toBe(false)
					expect(outline(3, 1).Enabled):toBe(true)
					game.dispose()
				end,
			})

			verifyHarness:case("letters land in the ACTIVE row only", {
				id = "native_games::examples/05 word game — the state machine::letters land in the ACTIVE row only",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					typeWord(game, "RULERS")
					expect((game.row(1))):toBe("RULERS")
					expect((game.row(2))):toBe("")

					game.press("X")
					expect((game.row(1))):toBe("RULERS")
					game.press("Return")
					expect((game.activeRow())):toBe(2)
					typeWord(game, "AB")
					expect((game.row(1))):toBe("RULERS")
					expect((game.row(2))):toBe("AB")
					game.dispose()
				end,
			})

			verifyHarness:case("a SHORT guess is refused with a message and does not consume a row", {
				id = "native_games::examples/05 word game — the state machine::a SHORT guess is refused with a message and does not consume a row",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					typeWord(game, "REA")
					game.press("Return")
					expect((game.activeRow())):toBe(1)
					expect((game.row(1))):toBe("REA")
					expect(string.find(game.status(), "Not enough letters") ~= nil):toBe(true)
					expect((game.state(1, 1))):toBe("filled")
					game.dispose()
				end,
			})

			verifyHarness:case("an INVALID guess is refused with a different message and does not consume a row", {
				id = "native_games::examples/05 word game — the state machine::an INVALID guess is refused with a different message and does not consume a row",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					typeWord(game, "ZZZZZZ")
					game.press("Return")
					expect((game.activeRow())):toBe(1)
					expect((game.row(1))):toBe("ZZZZZZ")

					expect(string.find(game.status(), "this game doesn't know that word") ~= nil):toBe(true)
					expect(string.find(game.status(), "ZZZZZZ", 1, true) ~= nil):toBe(true)
					expect((string.find(game.status(), "word list"))):toBeNil()
					expect((game.state(1, 3))):toBe("filled")

					game.press("Backspace")
					expect((string.find(game.status(), "this game doesn't know that word"))):toBeNil()
					game.dispose()
				end,
			})

			verifyHarness:case("a rejected guess consumes NO row, and an ordinary word the old list refused plays on", {
				id = "native_games::examples/05 word game — the state machine::a rejected guess consumes NO row, and an ordinary word the old list refused plays on",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					typeWord(game, "PLZTKZ")
					game.press("Return")
					expect((game.activeRow())):toBe(1)
					expect((game.phase())):toBe("playing")
					expect((game.state(1, 1))):toBe("filled")
					expect(string.find(game.status(), "this game doesn't know that word") ~= nil):toBe(true)

					for _ = 1, rules.COLS do
						game.press("Backspace")
					end
					guess(game, "COCOAS")
					expect((game.activeRow())):toBe(2)
					expect((game.row(1))):toBe("COCOAS")

					expectStates(game, 1, { "absent", "absent", "absent", "absent", "present", "absent" })
					game.dispose()
				end,
			})

			verifyHarness:case("four words the old thirty-four-word list rejected now play end to end", {
				id = "native_games::examples/05 word game — the state machine::four words the old thirty-four-word list rejected now play end to end",
				run = function()
					for _, word in { "COLOUR", "CENTRE", "FAVOUR", "LITRES" } do
						local ctx = makeWorld()
						local game = newGame(ctx)
						guess(game, word)
						if game.activeRow() ~= 2 then
							error(
								`"{word}" was refused: the board is still on row {game.activeRow()} and says "{game.status()}"`,
								2
							)
						end
						expect((game.row(1))):toBe(word)

						for c = 1, rules.COLS do
							local state = game.state(1, c)
							expect(state == "correct" or state == "present" or state == "absent"):toBe(true)
						end

						expect(game.keyState(string.sub(word, 1, 1)) ~= nil):toBe(true)
						game.dispose()
					end
				end,
			})

			verifyHarness:case("backspace deletes from the active row and stops at empty", {
				id = "native_games::examples/05 word game — the state machine::backspace deletes from the active row and stops at empty",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					typeWord(game, "RE")
					game.press("Backspace")
					expect((game.row(1))):toBe("R")
					game.press("Backspace")
					game.press("Backspace")
					expect((game.row(1))):toBe("")
					expect((game.state(1, 1))):toBe("caret")
					game.dispose()
				end,
			})

			verifyHarness:case("key state accumulates monotonically and never downgrades", {
				id = "native_games::examples/05 word game — the state machine::key state accumulates monotonically and never downgrades",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					guess(game, "RULERS")
					expect((game.keyState("R"))):toBe("correct")
					expect((game.keyState("E"))):toBe("present")
					expect((game.keyState("U"))):toBe("absent")
					expect((game.keyState("Z"))):toBeNil()
					guess(game, "ERRORS")
					expect((game.keyState("R"))):toBe("correct")
					expect((game.keyState("E"))):toBe("present")
					guess(game, "READER")
					expect((game.keyState("E"))):toBe("correct")
					expect((game.keyState("U"))):toBe("absent")
					game.dispose()
				end,
			})

			verifyHarness:case("a refused guess does NOT count toward the seven", {
				id = "native_games::examples/05 word game — the state machine::a refused guess does NOT count toward the seven",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					for _, word in { "RULERS", "ERRORS", "ALWAYS", "LEVELS", "SOLVED", "WALNUT" } do
						guess(game, word)
					end
					expect((game.activeRow())):toBe(7)
					guess(game, "ZZZZZZ")
					expect((game.activeRow())):toBe(7)
					expect((game.phase())):toBe("playing")
					for _ = 1, rules.COLS do
						game.press("Backspace")
					end
					guess(game, "TILING")
					expect((game.phase())):toBe("lost")
					game.dispose()
				end,
			})

			verifyHarness:case("input is dead after the game ends, except restart", {
				id = "native_games::examples/05 word game — the state machine::input is dead after the game ends, except restart",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					guess(game, "READER")
					expect((game.phase())):toBe("won")
					local before = game.row(1)
					game.press("Z")
					tap(ctx, game.keyPath("Z"))
					game.press("Backspace")
					game.press("Return")
					expect((game.row(1))):toBe(before)
					expect((game.row(2))):toBe("")
					expect((game.phase())):toBe("won")
					expect(findPath(ctx.node, game.keyPath("Z")).Interactable):toBe(false)
					expect(findPath(ctx.node, game.keyPath("Enter")).Interactable):toBe(false)
					expect(findPath(ctx.node, "/WordGuess/page/Restart").Interactable):toBe(true)
					tap(ctx, "/Close")
					tap(ctx, "/WordGuess/page/Restart")
					expect((game.phase())):toBe("playing")
					game.dispose()
				end,
			})

			verifyHarness:case("restart is deterministic: the same seed replays the same word", {
				id = "native_games::examples/05 word game — the state machine::restart is deterministic: the same seed replays the same word",
				run = function()
					local ctx = makeWorld()
					local game = mountGame(ctx, wordGame)
					expect((game.seed())):toBe(1)
					expect((game.solution())):toBe(rules.solutionForSeed(1))
					guess(game, "RULERS")
					game.restart()
					expect((game.seed())):toBe(2)
					expect((game.solution())):toBe(rules.solutionForSeed(2))

					expect((game.row(1))):toBe("")
					expect((game.activeRow())):toBe(1)
					expect((game.phase())):toBe("playing")
					expect((game.keyState("R"))):toBeNil()
					expect((game.state(1, 1))):toBe("caret")
					expect((game.state(1, 2))):toBe("empty")

					game.restart(4)
					local first = game.solution()
					guess(game, "RULERS")
					game.restart(4)
					expect((game.solution())):toBe(first)
					expect((game.row(1))):toBe("")
					game.dispose()
				end,
			})

			verifyHarness:case("restart after a loss closes the results card and re-enables the keyboard", {
				id = "native_games::examples/05 word game — the state machine::restart after a loss closes the results card and re-enables the keyboard",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					for _, word in { "RULERS", "ERRORS", "ALWAYS", "LEVELS", "SOLVED", "TILING", "WALNUT" } do
						guess(game, word)
					end
					expect((game.resultsOpen())):toBe(true)
					expect((if game.resultsOpen() then 2 else 1)):toBe(2)

					tap(ctx, "/WordGuess/page/Restart")
					expect((game.resultsOpen())):toBe(true)
					expect((game.phase())):toBe("lost")
					tap(ctx, "/Close")
					expect((if game.resultsOpen() then 2 else 1)):toBe(1)
					tap(ctx, "/WordGuess/page/Restart")
					expect((game.resultsOpen())):toBe(false)
					expect((game.phase())):toBe("playing")
					expect(findPath(ctx.node, game.keyPath("Z")).Interactable):toBe(true)
					typeWord(game, "AB")
					expect((game.row(1))):toBe("AB")
					game.dispose()
				end,
			})

			verifyHarness:case("the results card's Close button actually closes it", {
				id = "native_games::examples/05 word game — the state machine::the results card's Close button actually closes it",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					guess(game, "READER")
					expect((if game.resultsOpen() then 2 else 1)):toBe(2)
					expect(find(ctx.node, "Close") ~= nil):toBe(true)
					tap(ctx, "/Close")
					expect((game.resultsOpen())):toBe(false)
					expect((if game.resultsOpen() then 2 else 1)):toBe(1)

					expect((game.phase())):toBe("won")
					expect((game.state(1, 1))):toBe("correct")
					game.dispose()
				end,
			})

			verifyHarness:case("the results card's New game button restarts from inside the card", {
				id = "native_games::examples/05 word game — the state machine::the results card's New game button restarts from inside the card",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					guess(game, "READER")
					tap(ctx, "/Again")
					expect((if game.resultsOpen() then 2 else 1)):toBe(1)
					expect((game.phase())):toBe("playing")

					expect((game.seed())):toBe(READER_SEED + 1)
					expect((game.solution())):toBe(rules.solutionForSeed(READER_SEED + 1))
					game.dispose()
				end,
			})

			verifyHarness:case("tears down to a registry baseline after dispose", {
				id = "native_games::examples/05 word game — the state machine::tears down to a registry baseline after dispose",
				run = function()
					local ctx = makeWorld()
					local baseline = #ctx.target:GetChildren()
					local game = newGame(ctx)
					guess(game, "RULERS")
					guess(game, "READER")
					game.dispose()
					local after = #ctx.target:GetChildren()
					expect(after):toBe(baseline)
				end,
			})
		end)
	end
	do
		local tileGame = require("../examples/gallery/examples/06_tile_game")
		local rules = tileGame.rules
		local function newGame(ctx: World)
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

		verifyHarness:suite("examples/06 crossword — axis, run and connection", function()
			verifyHarness:case("connection is ORTHOGONAL: touching diagonally is not touching", {
				id = "native_games::examples/06 crossword — axis, run and connection::connection is ORTHOGONAL: touching diagonally is not touching",
				run = function()
					local seeded =
						boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })

					local orthogonal =
						rules.validate(seeded, placedOf({ { 5, 3, "O" }, { 5, 4, "N" }, { 5, 5, "E" } }), 2)
					expect(orthogonal.ok):toBe(true)

					local floating = rules.validate(seeded, placedOf({ { 6, 6, "A" }, { 6, 7, "N" } }), 2)
					expect(floating.ok):toBe(false)
					expect(floating.code):toBe("connect")
					expect(floating.message):toBe(rules.SAY.connect)

					local diagonal = rules.validate(seeded, placedOf({ { 5, 6, "A" }, { 5, 7, "N" } }), 2)
					expect(diagonal.ok):toBe(false)
					expect(diagonal.code):toBe("connect")
				end,
			})
		end)

		verifyHarness:suite("examples/06 crossword — every word a turn creates", function()
			local DON = boardOf({ ".......", ".......", ".......", "..DON..", ".......", ".......", "......." })
		end)

		verifyHarness:suite("examples/06 crossword — nine refusals, nine sentences, on screen", function()
			local function said(game: any): string
				return game.wordText()
			end

			local function hint(game: any): string
				return game.hintText()
			end

			verifyHarness:case("1 — the first turn misses the centre", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::1 — the first turn misses the centre",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)

					game.select(1)
					game.place(1, 1)
					game.select(2)
					game.place(1, 2)
					game.submit()
					expect((said(game))):toBe("Your first word has to cover the starred centre square.")
					expect((game.turn())):toBe(1)
					game.dispose()
				end,
			})

			verifyHarness:case("2 — the tiles are not in one line", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::2 — the tiles are not in one line",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					game.select(1)
					game.place(4, 4)
					game.select(2)
					game.place(5, 5)
					game.submit()
					expect((said(game))):toBe("The tiles you place in a turn go in a single row or a single column.")
					game.dispose()
				end,
			})

			verifyHarness:case("3 — a gap in the run", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::3 — a gap in the run",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					game.select(1)
					game.place(4, 4)
					game.select(2)
					game.place(4, 7)
					game.submit()
					expect((said(game))):toBe(
						"Leave no gaps — your tiles and the letters already on the board have to make one unbroken run."
					)
					game.dispose()
				end,
			})

			verifyHarness:case("4 — a later turn touches nothing", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::4 — a later turn touches nothing",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					play(game, WIN_SCRIPT, 1)
					expect((game.turn())):toBe(2)

					game.select(1)
					game.place(7, 1)
					game.select(2)
					game.place(7, 2)
					game.submit()
					expect((said(game))):toBe(
						"After the first turn, a word has to touch a letter already on the board."
					)
					game.dispose()
				end,
			})

			verifyHarness:case("5 — the main word is unknown, and the sentence names it", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::5 — the main word is unknown, and the sentence names it",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)

					game.select(1)
					game.place(4, 4)
					game.select(2)
					game.place(4, 5)
					game.select(3)
					game.place(4, 6)
					game.submit()
					expect((said(game))):toBe("EDA isn't a word this game knows.")

					expect((rules.sayUnknown("PLZTK"))):toBe("PLZTK isn't a word this game knows.")
					game.dispose()
				end,
			})

			verifyHarness:case("6 — a crossing word is unknown, and the sentence names it AND its direction", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::6 — a crossing word is unknown, and the sentence names it AND its direction",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					play(game, WIN_SCRIPT, 1)

					game.select(5)
					game.place(5, 1)
					game.select(4)
					game.place(5, 2)
					game.submit()
					expect((said(game))):toBe("That would make EA downward, and that isn't a word this game knows.")

					expect((game.pendingAt(5, 1))):toBe("A")
					expect((game.pendingAt(5, 2))):toBe("I")
					expect((game.turn())):toBe(2)
					game.dispose()
				end,
			})

			verifyHarness:case("8 — placing on an occupied square", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::8 — placing on an occupied square",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					game.select(1)
					game.place(4, 4)
					game.select(2)
					game.place(4, 4)
					expect((said(game))):toBe("That square already has a letter.")

					expect((game.selected())):toBe(2)
					game.dispose()
				end,
			})

			verifyHarness:case("8b — an off-board square takes nothing, so a stray call cannot beach a tile", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::8b — an off-board square takes nothing, so a stray call cannot beach a tile",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					game.select(1)
					game.place(9, 9)

					expect((game.selected())):toBe(1)
					game.place(4, 4)
					expect((game.selected())):toBe(nil)
					game.dispose()
				end,
			})

			verifyHarness:case("...and an uncommitted tile CAN be picked back up, which is what makes 9 a rule", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::...and an uncommitted tile CAN be picked back up, which is what makes 9 a rule",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					local letter = game.rackLetter(1)
					game.select(1)
					game.place(4, 4)
					expect((game.pendingAt(4, 4))):toBe(letter)
					expect((game.rackLetter(1))):toBeNil()
					game.place(4, 4)
					expect((game.pendingAt(4, 4))):toBeNil()
					expect((game.rackLetter(1))):toBe(letter)
					expect((said(game))):toBe("No tiles placed this turn.")
					game.dispose()
				end,
			})

			verifyHarness:case("the instruction line names the held tile, and clears on a placement", {
				id = "native_games::examples/06 crossword — nine refusals, nine sentences, on screen::the instruction line names the held tile, and clears on a placement",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					expect((hint(game))):toBe("Cover the starred square with a word to begin.")
					local letter = game.rackLetter(1)
					game.select(1)
					expect((hint(game))):toBe(`Placing {letter} — choose a square.`)
					game.place(4, 4)
					expect((hint(game))):toBe("Cover the starred square with a word to begin.")
					expect((said(game))):toBe(`{letter} isn't a word this game knows.`)
					game.dispose()
				end,
			})
		end)

		verifyHarness:suite("examples/06 crossword — commit, refill, undo, budget", function()
			verifyHarness:case("undo returns exactly the uncommitted tiles, to the slots they came from", {
				id = "native_games::examples/06 crossword — commit, refill, undo, budget::undo returns exactly the uncommitted tiles, to the slots they came from",
				run = function()
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
					expect((game.rackCount())):toBe(4)
					game.undo()
					expect((game.rackCount())):toBe(7)
					for slot = 1, 7 do
						expect((game.rackLetter(slot))):toBe(rackBefore[slot])
					end
					expect((game.dump())):toBe(before)

					expect((game.selected())):toBeNil()
					game.select(4)
					game.place(3, 4)
					expect(game.pendingAt(3, 4) ~= nil):toBe(true)
					game.dispose()
				end,
			})

			verifyHarness:case("A REFUSED SUBMIT CHANGES NOTHING — every tile stays where the player put it", {
				id = "native_games::examples/06 crossword — commit, refill, undo, budget::A REFUSED SUBMIT CHANGES NOTHING — every tile stays where the player put it",
				run = function()
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
					expect((game.dump())):toBe(before)
					expect((game.score())):toBe(0)
					expect((game.turn())):toBe(1)
					expect((game.rackCount())):toBe(4)
					expect(game.pendingAt(4, 4) ~= nil):toBe(true)
					expect(game.pendingAt(4, 5) ~= nil):toBe(true)
					expect(game.pendingAt(4, 6) ~= nil):toBe(true)
					expect((game.committedAt(4, 4))):toBeNil()

					for _ = 1, 20 do
						game.submit()
					end
					expect((game.dump())):toBe(before)
					expect(#ctx.target:GetChildren()):toBe(counters)
					game.dispose()
				end,
			})

			verifyHarness:case("the turn budget decrements only on a commit", {
				id = "native_games::examples/06 crossword — commit, refill, undo, budget::the turn budget decrements only on a commit",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					expect((game.turnsLeft())):toBe(6)
					game.submit()
					expect((game.turnsLeft())):toBe(6)
					game.select(1)
					game.place(4, 4)
					game.select(2)
					game.place(4, 5)
					game.submit()
					expect((game.turnsLeft())):toBe(6)
					game.undo()
					expect((game.turnsLeft())):toBe(6)
					play(game, WIN_SCRIPT, 1)
					expect((game.turnsLeft())):toBe(5)
					game.dispose()
				end,
			})

			verifyHarness:case("the legal-next-cell cue follows the rules, and locks with the axis", {
				id = "native_games::examples/06 crossword — commit, refill, undo, budget::the legal-next-cell cue follows the rules, and locks with the axis",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)

					expect((game.cellState(4, 4))):toBe("centre")
					expect((game.cellState(1, 1))):toBe("idle")
					game.select(1)
					game.place(4, 4)

					expect((game.cellState(4, 3))):toBe("legal")
					expect((game.cellState(3, 4))):toBe("legal")
					game.select(2)
					game.place(4, 5)

					expect((game.cellState(4, 3))):toBe("legal")
					expect((game.cellState(3, 4))):toBe("idle")
					expect((game.cellState(4, 4))):toBe("pending")
					game.dispose()
				end,
			})
		end)

		verifyHarness:suite("examples/06 crossword — both endings, and the way back", function()
			verifyHarness:case("reaching the goal wins, and the screen says which ending it was", {
				id = "native_games::examples/06 crossword — both endings, and the way back::reaching the goal wins, and the screen says which ending it was",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					play(game, WIN_SCRIPT)
					expect((game.phase())):toBe("won")
					expect((game.score())):toBe(67)
					expect(game.score() >= rules.GOAL):toBe(true)
					local hint = findPath(ctx.node, game.hintPath).Text
					expect(string.find(hint, "you win!", 1, true) ~= nil):toBe(true)
					expect(string.find(hint, "67 points", 1, true) ~= nil):toBe(true)
					expect(string.find(hint, "4 of 6 turns", 1, true) ~= nil):toBe(true)

					local dump = game.dump()
					game.select(1)
					game.place(1, 1)
					game.submit()
					expect((game.dump())):toBe(dump)

					tap(ctx, game.resetPath)
					expect((game.phase())):toBe("playing")
					expect((game.score())):toBe(0)
					game.dispose()
				end,
			})

			verifyHarness:case("spending the budget without reaching the goal loses, and says so", {
				id = "native_games::examples/06 crossword — both endings, and the way back::spending the budget without reaching the goal loses, and says so",
				run = function()
					local ctx = makeWorld()
					local game = newGame(ctx)
					play(game, LOSS_SCRIPT)
					expect((game.phase())):toBe("lost")
					expect((game.score())):toBe(14)
					expect((game.turnsLeft())):toBe(0)
					local hint = findPath(ctx.node, game.hintPath).Text
					expect(hint):toBe("Out of turns at 14 of 60 points. Press Start over to play again.")
					tap(ctx, game.resetPath)
					expect((game.phase())):toBe("playing")
					expect((game.turnsLeft())):toBe(6)
					game.dispose()
				end,
			})

			verifyHarness:case("restart returns EVERY observable to its seeded start", {
				id = "native_games::examples/06 crossword — both endings, and the way back::restart returns EVERY observable to its seeded start",
				run = function()
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
					expect(game.score() > 0):toBe(true)
					tap(ctx, game.resetPath)
					expect((game.dump())):toBe(start)
					expect((game.hintText())):toBe(startHint)
					expect((game.wordText())):toBe(startWord)
					expect((game.selected())):toBeNil()
					expect((game.turn())):toBe(1)

					play(game, WIN_SCRIPT, 1)
					expect((game.score())):toBe(16)
					game.dispose()
				end,
			})
		end)

		verifyHarness:suite("examples/06 crossword — robustness", function()
			verifyHarness:case("rapid alternating input leaves no stale selection or held tile", {
				id = "native_games::examples/06 crossword — robustness::rapid alternating input leaves no stale selection or held tile",
				run = function()
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
					expect((game.selected())):toBeNil()
					expect((game.rackCount())):toBe(7)
					expect((game.score())):toBe(0)
					expect((game.turn())):toBe(1)
					expect((game.phase())):toBe("playing")
					game.dispose()
				end,
			})

			verifyHarness:case("tears down to a registry baseline after dispose", {
				id = "native_games::examples/06 crossword — robustness::tears down to a registry baseline after dispose",
				run = function()
					local ctx = makeWorld()
					local baseline = #ctx.target:GetChildren()
					local game = newGame(ctx)
					play(game, WIN_SCRIPT, 2)
					tap(ctx, game.rackPath(1))
					tap(ctx, game.cellPath(1, 1))
					game.dispose()
					local after = #ctx.target:GetChildren()
					expect(after):toBe(baseline)
				end,
			})
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
		local function newGame(board: { { string } }?, reduced: boolean?)
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
				ctx.engine.heartbeat:Fire(0.01)
			end
			error("Match3 did not reach " .. phase)
		end
		local function sameArray(actual, expected)
			expect(#actual):toBe(#expected)
			for index, value in expected do
				expect(actual[index]):toBe(value)
			end
		end
		verifyHarness:suite("examples/07 native Match3 parity", function()
			verifyHarness:case("keeps tile identity while a valid swap travels between endpoints", {
				id = "native_games::examples/07 native Match3 parity::keeps tile identity while a valid swap travels between endpoints",
				run = function()
					local game, ctx = newGame()
					local id = game.tileIdAt(1, 3)
					local original = tile(ctx, id)
					expect(original.Position.Y.Offset):toBe(0)
					game.swap(1, 3, 2, 3)
					expect((game.tileIdAt(2, 3))):toBe(id)
					expect((tile(ctx, id))):toBe(original)
					ctx.engine.heartbeat:Fire(0.05)
					expect(original.Position.Y.Offset > 0 and original.Position.Y.Offset < 48):toBe(true)
					expect((game.phase())):toBe("swap")
					game.dispose()
					expect((original:isDestroyed())):toBe(true)
					expect((engineLib.connections(ctx.engine.heartbeat))):toBe(0)
				end,
			})

			verifyHarness:case("fades retiring tiles then drops survivors and introduces new tiles above the board", {
				id = "native_games::examples/07 native Match3 parity::fades retiring tiles then drops survivors and introduces new tiles above the board",
				run = function()
					local game, ctx = newGame(dropBoard)
					local oldIds = game.tileIds()
					local removed = tile(ctx, game.tileIdAt(3, 1))
					local survivorId = game.tileIdAt(2, 1)
					local survivor = tile(ctx, survivorId)
					game.swap(3, 3, 4, 3)
					advanceTo(game, ctx, "remove")
					expect((game.tileIdAt(3, 1))):toBe(nil)
					expect((removed:isDestroyed())):toBe(false)
					ctx.engine.heartbeat:Fire(0.04)
					expect(removed.GroupTransparency > 0 and removed.GroupTransparency < 1):toBe(true)
					advanceTo(game, ctx, "gravity")
					expect((removed:isDestroyed())):toBe(true)
					expect((game.tileIdAt(3, 1))):toBe(survivorId)
					ctx.engine.heartbeat:Fire(0.04)
					expect(survivor.Position.Y.Offset > 48 and survivor.Position.Y.Offset < 96):toBe(true)
					advanceTo(game, ctx, "refill")
					local newId = game.tileIdAt(1, 1)
					local arrived = tile(ctx, newId)
					expect((table.find(oldIds, newId))):toBe(nil)
					expect(arrived.Position.Y.Offset < 0):toBe(true)
					local startY = arrived.Position.Y.Offset
					advanceTo(game, ctx, "land")
					ctx.engine.heartbeat:Fire(0.04)
					expect(arrived.Position.Y.Offset > startY and arrived.Position.Y.Offset < 0):toBe(true)
					advanceTo(game, ctx, "idle")
					expect(#game.tileIds()):toBe(36)
					expect((game.moves())):toBe(1)
					expect(game.score() >= 3):toBe(true)
					game.dispose()
					expect((engineLib.connections(ctx.engine.heartbeat))):toBe(0)
				end,
			})

			verifyHarness:case("reverts a refused swap and keeps the board and move budget unchanged", {
				id = "native_games::examples/07 native Match3 parity::reverts a refused swap and keeps the board and move budget unchanged",
				run = function()
					local game, ctx = newGame()
					local before = game.boardSnapshot()
					local id = game.tileIdAt(1, 1)
					local original = tile(ctx, id)
					game.swap(1, 1, 1, 2)
					ctx.engine.heartbeat:Fire(0.05)
					expect(original.Position.X.Offset > 0 and original.Position.X.Offset < 48):toBe(true)
					advanceTo(game, ctx, "revert")
					local departingX = original.Position.X.Offset
					ctx.engine.heartbeat:Fire(0.05)
					expect(original.Position.X.Offset < departingX):toBe(true)
					advanceTo(game, ctx, "idle")
					sameArray(game.boardSnapshot(), before)
					expect((game.tileIdAt(1, 1))):toBe(id)
					expect((game.moves())):toBe(0)
					expect(string.find(game.hintText(), "no run", 1, true) ~= nil):toBe(true)
					game.dispose()
				end,
			})

			verifyHarness:case(
				"keeps deterministic results under native reduced motion and changes paint immediately",
				{
					id = "native_games::examples/07 native Match3 parity::keeps deterministic results under native reduced motion and changes paint immediately",
					run = function()
						local outcomes = {}
						for _, reduced in { false, true } do
							local game, ctx = newGame(swapBoard, reduced)
							local moving = tile(ctx, game.tileIdAt(1, 3))
							game.swap(1, 3, 2, 3)
							expect(moving.Position.Y.Offset):toBe(if reduced then 48 else 0)
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
						expect(outcomes[1].score):toBe(outcomes[2].score)
						expect(outcomes[1].moves):toBe(outcomes[2].moves)
						local game, ctx = newGame()
						local moving = tile(ctx, game.tileIdAt(1, 3))
						game.swap(1, 3, 2, 3)
						ctx.engine.heartbeat:Fire(0.03)
						ctx.guiService.ReducedMotionEnabled = true
						expect(moving.Position.Y.Offset):toBe(48)
						game.dispose()
						expect((engineLib.connections(ctx.guiService:GetPropertyChangedSignal("ReducedMotionEnabled")))):toBe(
							0
						)
					end,
				}
			)

			verifyHarness:case("retries failed artwork through native controls without replacing tile identity", {
				id = "native_games::examples/07 native Match3 parity::retries failed artwork through native controls without replacing tile identity",
				run = function()
					local game, ctx = newGame()
					local original = tile(ctx, game.tileIdAt(1, 1))
					local image = find(original, "img")
					local asset = image.Image
					find(ctx.node, "Break").Activated:Fire()
					expect(image.Image):toBe(game.pendingImage)
					expect(string.find(game.artStatusText(), "failed", 1, true) ~= nil):toBe(true)
					expect(find(original, "hit").Text ~= ""):toBe(true)
					find(ctx.node, "Reload").Activated:Fire()
					expect(string.find(game.artStatusText(), "loading 5", 1, true) ~= nil):toBe(true)
					find(ctx.node, "Deliver").Activated:Fire()
					expect(image.Image):toBe(asset)
					expect((game.artStatusText())):toBe("Artwork: all 5 ready")
					expect((tile(ctx, game.tileIdAt(1, 1)))):toBe(original)
					expect(find(original, "hit").Text):toBe("")
					game.dispose()
				end,
			})

			verifyHarness:case("selects detector taps once and swaps adjacent tiles with mouse and touch", {
				id = "native_games::examples/07 native Match3 parity::selects detector taps once and swaps adjacent tiles with mouse and touch",
				run = function()
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
					firstDrag.DragStart:Fire(origin)
					firstDrag.DragEnd:Fire(origin)
					expect((first:GetAttribute("selected"))):toBe(true)
					first.Activated:Fire(mouse)
					expect((first:GetAttribute("selected"))):toBe(true)
					firstDrag.DragStart:Fire(origin)
					firstDrag.DragEnd:Fire(origin)
					first.Activated:Fire(mouse)
					expect((first:GetAttribute("selected"))):toBe(false)
					firstDrag.DragStart:Fire(origin)
					firstDrag.DragEnd:Fire(origin)
					local secondDrag = find(second, "SwapDrag")
					secondDrag.DragStart:Fire(origin)
					secondDrag.DragContinue:Fire(origin + ctx.types.Vector2.new(3, 2))
					secondDrag.DragEnd:Fire(origin + ctx.types.Vector2.new(3, 2))
					second.Activated:Fire(touch)
					expect((game.isResolving())):toBe(true)
					advanceTo(game, ctx, "idle")
					expect((game.moves())):toBe(1)
					expect(game.score() >= 3):toBe(true)
					game.dispose()
				end,
			})

			verifyHarness:case(
				"uses detector release position and preserves the next keyboard activation after dragging",
				{
					id = "native_games::examples/07 native Match3 parity::uses detector release position and preserves the next keyboard activation after dragging",
					run = function()
						local game, ctx = newGame()
						local first = find(tile(ctx, game.tileIdAt(1, 1)), "hit")
						local drag = find(first, "SwapDrag")
						drag.DragStart:Fire(ctx.types.Vector2.new(20, 20))
						drag.DragEnd:Fire(ctx.types.Vector2.new(52, 20))
						first.Activated:Fire({ UserInputType = ctx.types.Enum.UserInputType.MouseButton1 })
						expect((game.isResolving())):toBe(true)
						advanceTo(game, ctx, "idle")
						expect((game.moves())):toBe(0)
						first.SelectionGained:Fire()
						find(ctx.target, "Activate").Pressed:Fire()
						expect((first:GetAttribute("selected"))):toBe(true)
						first.Activated:Fire({ UserInputType = ctx.types.Enum.UserInputType.Gamepad1 })
						expect((first:GetAttribute("selected"))):toBe(false)
						game.dispose()
					end,
				}
			)

			verifyHarness:case("cancels uncaptured releases, outside taps and drags that return to their start", {
				id = "native_games::examples/07 native Match3 parity::cancels uncaptured releases, outside taps and drags that return to their start",
				run = function()
					local game, ctx = newGame()
					local first = find(tile(ctx, game.tileIdAt(1, 1)), "hit")
					first.AbsolutePosition = ctx.types.Vector2.new(100, 100)
					first.AbsoluteSize = ctx.types.Vector2.new(44, 44)
					local drag = find(first, "SwapDrag")
					local origin = ctx.types.Vector2.new(140, 120)
					drag.DragEnd:Fire(origin)
					expect((first:GetAttribute("selected"))):toBe(false)
					drag.DragStart:Fire(origin)
					drag.DragEnd:Fire(origin + ctx.types.Vector2.new(8, 0))
					expect((first:GetAttribute("selected"))):toBe(false)
					drag.DragStart:Fire(origin)
					drag.DragContinue:Fire(origin + ctx.types.Vector2.new(32, 0))
					drag.DragEnd:Fire(origin)
					expect((first:GetAttribute("selected"))):toBe(false)
					expect((game.isResolving())):toBe(false)
					expect((game.moves())):toBe(0)
					game.dispose()
				end,
			})

			verifyHarness:case("selects with native keyboard and gamepad events and keeps grid neighbors current", {
				id = "native_games::examples/07 native Match3 parity::selects with native keyboard and gamepad events and keeps grid neighbors current",
				run = function()
					local game, ctx = newGame()
					local first = find(tile(ctx, game.tileIdAt(1, 3)), "hit")
					local second = find(tile(ctx, game.tileIdAt(2, 3)), "hit")
					expect(first.NextSelectionDown):toBe(second)
					expect(first.NextSelectionRight):toBe(find(tile(ctx, game.tileIdAt(1, 4)), "hit"))
					first.SelectionGained:Fire()
					local action = find(ctx.target, "Activate")
					expect(action ~= nil):toBe(true)
					action.Pressed:Fire()
					expect((first:GetAttribute("selected"))):toBe(true)
					first.SelectionLost:Fire()
					second.Activated:Fire({
						UserInputType = ctx.types.Enum.UserInputType.Gamepad1,
						KeyCode = ctx.types.Enum.KeyCode.ButtonA,
					})
					expect((game.isResolving())):toBe(true)
					expect(game.tileIdAt(2, 3) ~= nil):toBe(true)
					advanceTo(game, ctx, "idle")
					for row = 1, 6 do
						for col = 1, 5 do
							local hit = find(tile(ctx, game.tileIdAt(row, col)), "hit")
							expect(hit.NextSelectionRight):toBe(find(tile(ctx, game.tileIdAt(row, col + 1)), "hit"))
						end
					end
					game.dispose()
				end,
			})
		end)
	end
end
