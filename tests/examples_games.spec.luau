--!strict
-- Tests for the three game gallery examples (docs progressive tutorial 6-8):
--   06 Wordle-style word game, 07 Scrabble-style tile game, 08 match-3.
-- Each example module exports { title, build } where
--   build(Facet, core, deps) -> a table with the presented screen, the
--   presenter handle, and a small game/test API.
-- deps = { env, actionSystem, presenter, adapter }.
-- Everything here runs headless under Lune against the FakeTarget adapter, so
-- these double as the write-once-run-everywhere proof: no engine, no Studio.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local wordGame = require("../examples/gallery/examples/05_word_game")
local tileGame = require("../examples/gallery/examples/06_tile_game")
local match3 = require("../examples/gallery/examples/07_match3")
local assets = require("../examples/gallery/examples/assets")
local standard_icons = require("../src/themes/standard_icons")

-- Build a fresh headless stack (core + environment + input + adapter +
-- presenter). Baseline the core counters AFTER the presenter exists but BEFORE
-- the example builds, so a later example.dispose() can prove registry-neutral
-- teardown of everything the example itself created.
local function makeWorld(viewport: any?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	if viewport ~= nil then
		env:set("viewportRect", viewport)
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = pres, adapter = adapter }
	return core, deps, adapter
end

-- fire a device key press+release through the arbitrated action pipeline (the
-- real keyboard/gamepad path; adapter.tap is the real pointer/touch path)
local function press(system: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
end

--[[ THE WORD GAME'S WORKED PUZZLE.

	05's answers come from the shared generated word data (2,096 of them), and
	its seed is MIXED rather than indexed, so seed 1 is not REACT and no seed is
	REACT by construction. The cases below are written against REACT because its
	scoring against RULES is the tutorial's own worked example, so they ASK which
	seed plays it and restart onto that seed — the same public door the "New game"
	button uses. Searching, rather than pinning a number, is what keeps this
	honest the day the data is regenerated. ]]
local WORD_SEED = (function(): number
	for seed = 1, 100000 do
		if (wordGame :: any).rules.solutionForSeed(seed) == "REACT" then
			return seed
		end
	end
	error("examples_games.spec: no seed in 1..100000 plays REACT — the answer set no longer holds it", 0)
end)()

local function buildWordGame(core: any, deps: any): any
	local game = wordGame.build(Facet, core, deps)
	game.restart(WORD_SEED)
	return game
end

-- =====================================================================
-- 05 — Wordle-style word game
-- =====================================================================
describe("examples/05 word game (Wordle-style)", function()
	it("mounts and renders headlessly with no runtime error", function()
		local core, deps, adapter = makeWorld()
		local game = buildWordGame(core, deps)
		expect(core:lastError()).toBeNil()
		-- the screen and a first-row tile both reached the adapter
		expect(adapter.node("/Wordle") == nil).toBeFalsy()
		expect(adapter.node(game.tilePath(1, 1)) == nil).toBeFalsy()
		game.dispose()
	end)

	it("hardware keys fill the row and a wrong guess colors the tiles", function()
		local core, deps = makeWorld()
		local game = buildWordGame(core, deps)
		-- solution is REACT; guess RULES: R is correct, E is present (wrong
		-- spot), U/L/S absent
		for _, ch in { "R", "U", "L", "E", "S" } do
			game.press(ch)
		end
		expect(game.row(1)).toBe("RULES")
		game.press("Return")
		expect(game.state(1, 1)).toBe("correct") -- R
		expect(game.state(1, 4)).toBe("present") -- E is in REACT, wrong column
		expect(game.state(1, 3)).toBe("absent") -- L not in REACT
		expect(game.won()).toBe(false)
		expect(deps.presenter.depth()).toBe(1) -- no results modal yet
		game.dispose()
	end)

	it("backspace deletes, and the winning word opens the results modal", function()
		local core, deps = makeWorld()
		local game = buildWordGame(core, deps)
		game.press("R")
		game.press("X")
		game.press("Backspace") -- undo the X
		expect(game.row(1)).toBe("R")
		for _, ch in { "E", "A", "C", "T" } do
			game.press(ch)
		end
		expect(game.row(1)).toBe("REACT")
		game.press("Return")
		expect(game.won()).toBe(true)
		expect(game.state(1, 5)).toBe("correct")
		-- the presenter opened the results modal on top of the board
		expect(deps.presenter.depth()).toBe(2)
		game.dispose()
	end)

	it("the on-screen keyboard is three navigation-group rows a gamepad can cross", function()
		local core, deps = makeWorld()
		local game = buildWordGame(core, deps)
		local focus = deps.presenter.focus
		-- focus enters the first key of the top row
		expect(focus.focused:get()).toBe(game.keyPath("Q"))
		focus.navigateDirection("right")
		expect(focus.focused:get()).toBe(game.keyPath("W"))
		-- crossing down lands on the nearest key of the second row (entry=nearest)
		focus.navigateDirection("down")
		expect(focus.focused:get()).toBe(game.keyPath("S"))
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps = makeWorld()
		local baseline = core:counters()
		local game = buildWordGame(core, deps)
		for _, ch in { "R", "E", "A", "C", "T", "Return" } do
			game.press(ch)
		end
		game.dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)

	-- Per-input proofs (ADR-0013): the example now carries NO nav-group build,
	-- no focus-scope swap, and no nav-key context — the on-screen keyboard's
	-- HStack rows yield layout-derived 2D navigation, and each key's node
	-- onActivate types/submits. The custom context now binds only the genuinely
	-- app-semantic HARDWARE keys (letters/Return/Backspace). These close the
	-- pointer + touch cells (UNPROVEN) and promote gamepad from PARTIAL to real
	-- device DPad + ButtonA.
	it("✓ ex05 pointer: tapping on-screen keys fills the row and Enter submits", function()
		local core, deps, adapter = makeWorld()
		local game = buildWordGame(core, deps)
		for _, ch in { "R", "E", "A", "C", "T" } do
			adapter.tap(game.keyPath(ch)) -- mouse click on the on-screen key
		end
		expect(game.row(1)).toBe("REACT")
		adapter.tap(game.keyPath("Enter")) -- Enter key submits (its node onActivate)
		expect(game.won()).toBe(true)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("✓ ex05 touch: a touch tap on an on-screen key types its letter", function()
		local core, deps, adapter = makeWorld()
		local game = buildWordGame(core, deps)
		adapter.tap(game.keyPath("R"), { pointer = "touch" })
		expect(game.row(1)).toBe("R")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("✓ ex05 keyboard: arrow keys navigate the on-screen keyboard grid (device path)", function()
		local core, deps = makeWorld()
		local game = buildWordGame(core, deps)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		expect(focus.focused:get()).toBe(game.keyPath("Q"))
		press(sys, "Right")
		expect(focus.focused:get()).toBe(game.keyPath("W"))
		press(sys, "Down") -- crosses to row 2, nearest column
		expect(focus.focused:get()).toBe(game.keyPath("S"))
		game.dispose()
	end)

	it("✓ ex05 gamepad: DPad navigates the keyboard and ButtonA types the focused key", function()
		local core, deps = makeWorld()
		local game = buildWordGame(core, deps)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		expect(focus.focused:get()).toBe(game.keyPath("Q"))
		press(sys, "DPadRight")
		expect(focus.focused:get()).toBe(game.keyPath("W"))
		press(sys, "ButtonA") -- A on the focused key types it (node onActivate)
		expect(game.row(1)).toBe("W")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)

-- =====================================================================
-- 06 — the crossword tile game
--
-- THE "07" IN THE describe NAME BELOW IS A STALE LABEL that predates the
-- gallery renumbering; the file is `06_tile_game.luau` and the four-input
-- cases inside it are the `ex06` rows the gate greps. It is left standing
-- rather than corrected because those two facts are worth one comment and
-- a rename would move a pinned line for nothing.
--
-- WHAT LIVES HERE, AND WHAT DOES NOT. This block owns the MOUNTED input
-- proofs: every action the game has, reached through a real device path,
-- with no per-device branch in the example. The rules, the nine refusals,
-- the turn loop, the endings, the determinism and the paint are
-- tests/example_tile_game.spec.luau — a rules table that takes a board and
-- a placement and returns a verdict does not need a screen to be tested,
-- and that is the whole reason it is a rules table.
-- =====================================================================
describe("examples/07 tile game (Scrabble-style)", function()
	it("mounts and renders headlessly with no runtime error", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		expect(core:lastError()).toBeNil()
		expect(adapter.node("/TileGame") == nil).toBeFalsy()
		-- all forty-nine squares, both plates deep, and the seven rack slots
		expect(adapter.node(game.cellPath(1, 1)) == nil).toBeFalsy()
		expect(adapter.node(game.cellPath(7, 7)) == nil).toBeFalsy()
		expect(adapter.node(game.platePath(4, 4)) == nil).toBeFalsy()
		expect(adapter.node(game.rackPath(1)) == nil).toBeFalsy()
		expect(adapter.node(game.rackPath(7)) == nil).toBeFalsy()
		expect(adapter.node(game.submitPath) == nil).toBeFalsy()
		expect(adapter.node(game.undoPath) == nil).toBeFalsy()
		game.dispose()
	end)

	it("select-then-place moves a rack tile onto a board square", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		local letter = game.rackLetter(1)
		-- tap the first rack tile (select), then tap a board square (place)
		adapter.tap(game.rackPath(1))
		expect(game.selected()).toBe(1)
		adapter.tap(game.cellPath(4, 4))
		expect(game.letterAt(4, 4)).toBe(letter)
		expect(game.rackLetter(1)).toBeNil()
		expect(game.selected()).toBeNil()
		-- ...and the whole turn commits and scores through the two action buttons
		adapter.tap(game.rackPath(3))
		adapter.tap(game.cellPath(4, 5))
		adapter.tap(game.undoPath)
		expect(game.rackCount()).toBe(7)
		expect(game.letterAt(4, 4)).toBeNil()
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps, adapter = makeWorld()
		local baseline = core:counters()
		local game = tileGame.build(Facet, core, deps)
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(4, 4))
		adapter.tap(game.submitPath)
		game.dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)

	-- Per-input proofs (ADR-0013): the example carries NO activation router
	-- (each square, rack tile and action has a node onActivate) and gains 2D
	-- grid navigation from the board's and the rack's Grids (layout-derived
	-- groups). Every case below drives the SAME select-then-place path — the
	-- one the design requires to be complete on its own — through a different
	-- device, and then reaches Submit and Undo, which are new this round.
	it("✓ ex06 touch: touch taps select a rack tile and place it on a board cell", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		local first = game.rackLetter(1)
		local second = game.rackLetter(3)
		adapter.tap(game.rackPath(1), { pointer = "touch" })
		adapter.tap(game.cellPath(4, 4), { pointer = "touch" })
		expect(game.letterAt(4, 4)).toBe(first)
		-- ...and the two turn verbs are reachable by fingertip too: place a
		-- second tile, take the whole turn back, and prove the rack is whole
		adapter.tap(game.rackPath(3), { pointer = "touch" })
		adapter.tap(game.cellPath(4, 5), { pointer = "touch" })
		expect(game.letterAt(4, 5)).toBe(second)
		adapter.tap(game.undoPath, { pointer = "touch" })
		expect(game.rackCount()).toBe(7)
		expect(game.letterAt(4, 4)).toBeNil()
		-- ...and a touch submit with nothing placed still answers
		adapter.tap(game.submitPath, { pointer = "touch" })
		deps.presenter.refresh()
		expect(adapter.node(game.wordPath).props.text).toBe("Place at least one tile before you submit.")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	-- REACHABILITY, NOT A PRESS COUNT. These used to assert "five Downs lands on
	-- the rack", which is a fact about how many rows the board happened to have
	-- and reddens on any layout change that is not a defect. What the row is
	-- actually for is: from the initial focus, the D-pad/arrow keys can REACH the
	-- rack and the actions, and Activate there does the thing.
	local function pressUntil(sys: any, focus: any, key: string, wanted: string): boolean
		for _ = 1, 16 do
			if focus.focused:get() == wanted then
				return true
			end
			press(sys, key)
		end
		return focus.focused:get() == wanted
	end

	-- Reaching ONE of the two actions is two moves, not one: down from the rack
	-- lands on whichever action shares the rack tile's column, and the row is then
	-- stepped along. Written this way the case stays a REACHABILITY claim — "the
	-- D-pad can get there" — rather than a press count that reddens on any layout
	-- change that is not a defect.
	local function reachAction(sys: any, focus: any, down: string, side: string, wanted: string, other: string): boolean
		for _ = 1, 16 do
			local at = focus.focused:get()
			if at == wanted then
				return true
			end
			press(sys, if at == other then side else down)
		end
		return focus.focused:get() == wanted
	end

	it("✓ ex06 keyboard: arrow/Return select-then-place from the rack onto the board", function()
		local core, deps = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		local letter = game.rackLetter(1)
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		expect(pressUntil(sys, focus, "Down", game.rackPath(1))).toBe(true)
		press(sys, "Return") -- select the rack tile
		expect(game.selected()).toBe(1)
		expect(pressUntil(sys, focus, "Up", game.cellPath(7, 1))).toBe(true)
		press(sys, "Return") -- place it
		expect(game.letterAt(7, 1)).toBe(letter)
		-- ...and Undo is reachable and works from the keyboard alone
		expect(reachAction(sys, focus, "Down", "Right", game.undoPath, game.submitPath)).toBe(true)
		press(sys, "Return")
		expect(game.letterAt(7, 1)).toBeNil()
		expect(game.rackCount()).toBe(7)
		-- THE TYPED-LETTER SHORTCUT, which is a convenience ON TOP of the path
		-- above and never the only way in: with a board square focused, a
		-- hardware letter that is on the rack lands there.
		for _ = 1, 12 do
			press(sys, "Up")
		end
		local at = focus.focused:get()
		local row, column = string.match(at, "cell(%d+)_(%d+)/tap$")
		expect(row ~= nil).toBe(true)
		game.press(letter :: string)
		expect(game.letterAt(tonumber(row) :: number, tonumber(column) :: number)).toBe(letter)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("✓ ex06 gamepad: DPad grid navigation with ButtonA select-then-place", function()
		local core, deps = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		local letter = game.rackLetter(1)
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		expect(pressUntil(sys, focus, "DPadDown", game.rackPath(1))).toBe(true)
		press(sys, "ButtonA") -- select the rack tile
		expect(pressUntil(sys, focus, "DPadUp", game.cellPath(7, 1))).toBe(true)
		press(sys, "ButtonA") -- place it
		expect(game.letterAt(7, 1)).toBe(letter)
		-- ...and the D-pad crosses the board a square at a time, which is what
		-- the Grid's derived row groups are for
		press(sys, "DPadRight")
		expect(focus.focused:get()).toBe(game.cellPath(7, 2))
		-- ...and Submit answers a gamepad A like anything else
		expect(reachAction(sys, focus, "DPadDown", "DPadLeft", game.submitPath, game.undoPath)).toBe(true)
		press(sys, "ButtonA")
		expect(game.turn()).toBe(1) -- refused: a lone tile in row 7 is no word
		expect(game.letterAt(7, 1)).toBe(letter) -- ...and the refusal kept it
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	-- ========================================================================
	-- WHAT THE PLAY AUDIT FOUND (example-quality-pass, 2026-08-06). Driven live
	-- in Studio, the game placed tiles correctly and explained NOTHING: tapping
	-- a square with nothing picked up, tapping an occupied square, and tapping
	-- an already-played rack slot were all completely silent. The nine refusals
	-- the crossword rules now produce are each a case in
	-- tests/example_tile_game.spec.luau; these two stay here because they are
	-- about the MOUNTED tree — the sentence has to reach a node.
	-- ========================================================================
	it("placing with nothing picked up says so instead of doing nothing", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		local before = game.wordText()
		adapter.tap(game.cellPath(1, 1))
		expect(game.letterAt(1, 1)).toBeNil()
		expect(game.wordText() ~= before).toBe(true)
		expect(string.find(game.wordText(), "Pick a letter", 1, true) ~= nil).toBe(true)
		expect(string.find(game.wordText(), "first", 1, true) ~= nil).toBe(true)
		-- and the visible node really carries it, not just the model
		deps.presenter.refresh()
		expect(adapter.node(game.wordPath).props.text).toBe(game.wordText())
		game.dispose()
	end)

	it("progress and the goal are visible, and the readouts are ARRANGED to something", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(Facet, core, deps)
		deps.presenter.refresh()
		expect(adapter.node("/TileGame/Page/Stats/Score").props.text).toBe("0 of 60 points")
		expect(adapter.node("/TileGame/Page/Stats/Progress").props.text).toBe("6 turns left")
		-- ...AND THAT THEY ARE ARRANGED TO SOMETHING. This test was once called
		-- "visible" while proving only that a node with that path carried that
		-- text, and both are equally true of a node the solver arranged to a zero
		-- rect — which is exactly what a losing `ViewThatFits` candidate is, and
		-- how these two readouts spent a mission off their published paths under
		-- a green suite (2026-08-13). The sweep across every viewport lives in
		-- tests/example_readouts.spec.luau; this is the same claim at the size
		-- this example's own tests use.
		for _, path in
			{
				"/TileGame/Page/Stats/Score",
				"/TileGame/Page/Stats/Progress",
				"/TileGame/Page/Word",
				"/TileGame/Page/Actions/Submit",
				"/TileGame/Page/Actions/Undo",
			}
		do
			local rect = adapter.node(path).rect
			expect(rect.w > 0 and rect.h > 0).toBe(true)
		end
		-- ...and a committed turn moves both readouts
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(4, 4))
		adapter.tap(game.rackPath(5))
		adapter.tap(game.cellPath(4, 5))
		adapter.tap(game.submitPath)
		deps.presenter.refresh()
		expect(adapter.node("/TileGame/Page/Stats/Score").props.text).toBe("2 of 60 points")
		expect(adapter.node("/TileGame/Page/Stats/Progress").props.text).toBe("5 turns left")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)

-- =====================================================================
-- 08 — match-3 with async image tiles and adaptive layout
-- =====================================================================
describe("examples/08 match-3", function()
	it("mounts and renders headlessly with no runtime error", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		expect(core:lastError()).toBeNil()
		expect(adapter.node("/Match3") == nil).toBeFalsy()
		expect(adapter.node(game.cellPath(1, 1)) == nil).toBeFalsy()
		game.dispose()
	end)

	it("a swap that forms a run clears and refills, and replays deterministically", function()
		local core, deps = makeWorld()
		local game = match3.build(Facet, core, deps)
		-- arrange a board where swapping (1,3)<->(2,3) completes a horizontal
		-- run of three 'a' tiles on row 1. Kinds: a,b,c,d,e.
		game.debugSetBoard({
			{ "a", "a", "b", "c", "d", "e" },
			{ "c", "d", "a", "e", "b", "c" },
			{ "e", "b", "c", "d", "a", "b" },
			{ "b", "c", "d", "e", "c", "a" },
			{ "d", "e", "b", "a", "e", "d" },
			{ "a", "c", "e", "b", "d", "c" },
		})
		game.swap(1, 3, 2, 3) -- brings an 'a' up to complete a,a,a on row 1
		-- the three matched cells are no longer 'a','a','a' held in place: they
		-- cleared and the board refilled (no empty holes remain)
		local snap = game.boardSnapshot()
		for _, kind in snap do
			expect(kind ~= nil and kind ~= "").toBeTruthy()
		end
		-- determinism: a second game with the same seed, board, and swap lands
		-- on an identical board — tests replay exactly (§ seeded refill).
		local core2, deps2 = makeWorld()
		local game2 = match3.build(Facet, core2, deps2)
		game2.debugSetBoard({
			{ "a", "a", "b", "c", "d", "e" },
			{ "c", "d", "a", "e", "b", "c" },
			{ "e", "b", "c", "d", "a", "b" },
			{ "b", "c", "d", "e", "c", "a" },
			{ "d", "e", "b", "a", "e", "d" },
			{ "a", "c", "e", "b", "d", "c" },
		})
		game2.swap(1, 3, 2, 3)
		expect(game2.boardSnapshot()).toEqual(snap)
		game.dispose()
		game2.dispose()
	end)

	it("the board reflows across viewports without remounting, and the example names no device", function()
		-- THIS TEST USED TO ASSERT THE DEFECT (example-quality-pass, 2026-08-06).
		-- It required `desktopW > phoneW`, which was only true because the example
		-- computed its own cell size from `env sizeClass` -> 40/56/72 px: imperative
		-- responsive geometry inside a consumer, the thing Facet owns. The tile is
		-- now a THEME metric, so what matters is that a viewport change reflows the
		-- page without rebuilding it, and that the tile never drops below the
		-- theme's own touch floor at any of them.
		local core, deps, adapter = makeWorld({ x = 0, y = 0, w = 390, h = 844 }) -- phone
		local game = match3.build(Facet, core, deps)
		deps.presenter.refresh()
		local mountedBefore = game.handle.root.counters().mounted
		local runsBefore = game.handle.root.counters().factoryRuns
		local phone = adapter.node(game.cellPath(1, 1)).rect
		expect(phone.w >= 44).toBe(true)
		expect(phone.h >= 44).toBe(true)
		-- the whole 6-wide board fits a narrow phone rather than running off it
		expect(adapter.node("/Match3/Page/board").rect.w <= 390).toBe(true)
		for _, viewport in
			{
				{ x = 0, y = 0, w = 844, h = 390 }, -- the same phone, landscape
				{ x = 0, y = 0, w = 1280, h = 720 }, -- desktop
				{ x = 0, y = 0, w = 1920, h = 1080 }, -- ten-foot
			}
		do
			deps.env:set("viewportRect", viewport)
			deps.presenter.refresh()
			local cell = adapter.node(game.cellPath(1, 1)).rect
			expect(cell.w >= 44).toBe(true)
			expect(cell.h >= 44).toBe(true)
			expect(game.handle.root.counters().mounted).toBe(mountedBefore) -- no remount
			expect(game.handle.root.counters().factoryRuns).toBe(runsBefore)
		end
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("the board is PLAYABLE from the first frame: art is delivered at build", function()
		-- the audit found every one of the thirty-six tiles showing the pending
		-- placeholder forever, because the header said "the caller drains the
		-- provider" and the gallery host never did. A tutorial whose board is
		-- unreadable until someone runs a script is not a tutorial.
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		deps.presenter.refresh()
		local kind = game.kindAt(1, 1)
		expect(adapter.node(game.imagePath(1, 1)).props.image).toBe(assets.match3Tiles[kind].image)
		expect(game.artStatusText()).toBe("Artwork: all 5 ready")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("re-request -> pending -> deliver is the async lesson, driven from the screen", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		deps.presenter.refresh()
		adapter.tap(game.reloadPath)
		deps.presenter.refresh()
		-- every tile is back on the placeholder, and the status says how many
		expect(adapter.node(game.imagePath(1, 1)).props.image).toBe(game.pendingImage)
		expect(game.artStatusText()).toBe("Artwork: loading 5 of 5")
		-- ...and the FALLBACK symbol is showing, so the five kinds are still
		-- distinguishable while there is no art at all
		local kind = game.kindAt(1, 1)
		expect(adapter.node(game.cellPath(1, 1)).props.label).toBe(assets.match3Tiles[kind].label)
		adapter.tap(game.deliverPath)
		deps.presenter.refresh()
		expect(adapter.node(game.imagePath(1, 1)).props.image).toBe(assets.match3Tiles[kind].image)
		expect(game.artStatusText()).toBe("Artwork: all 5 ready")
		expect(adapter.node(game.cellPath(1, 1)).props.label).toBe("")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a FAILED load is visible and recoverable, which is the half that was missing", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		deps.presenter.refresh()
		adapter.tap(game.breakPath)
		deps.presenter.refresh()
		expect(string.find(game.artStatusText(), "failed", 1, true) ~= nil).toBe(true)
		expect(string.find(game.hintText(), "failed to load", 1, true) ~= nil).toBe(true)
		expect(string.find(game.hintText(), "Re-request artwork", 1, true) ~= nil).toBe(true)
		-- recovery: re-request puts it back in flight, deliver resolves it
		adapter.tap(game.reloadPath)
		adapter.tap(game.deliverPath)
		deps.presenter.refresh()
		expect(game.artStatusText()).toBe("Artwork: all 5 ready")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("the five tile kinds carry five DISTINCT shapes, and the ids are the framework's own art", function()
		-- five identical dark squares is what the audit photographed. Distinctness
		-- is a property of the CONTENT, so it is asserted over the content table,
		-- and each id is pinned to the framework icon it came from so a re-upload
		-- fails here instead of silently blanking the board.
		local seenImage: { [string]: boolean } = {}
		local seenLabel: { [string]: boolean } = {}
		local count = 0
		for kind, art in assets.match3Tiles do
			count += 1
			expect(seenImage[art.image]).toBeNil()
			expect(seenLabel[art.label]).toBeNil()
			seenImage[art.image] = true
			seenLabel[art.label] = true
			local record = standard_icons.ART[art.iconName]
			expect(record ~= nil).toBe(true)
			expect(record.contentId).toBe(art.image)
			-- and every kind carries a semantic tint role, never a literal colour
			expect(type(assets.match3Tints[kind])).toBe("string")
		end
		expect(count).toBe(5)
	end)

	-- ========================================================================
	-- THE OPENING BOARD (example-quality-pass, 2026-08-06). The board used to be
	-- filled cell by cell and shown as-is, with no resolve pass: a seed could open
	-- on a run the player never made, and nothing checked that a legal move
	-- existed at all. Both are dead ends a player cannot see and cannot fix.
	-- ========================================================================
	it("opens with no run already on the board", function()
		local core, deps = makeWorld()
		local game = match3.build(Facet, core, deps)
		expect(next(game.findMatches())).toBeNil()
		expect(game.score()).toBe(0) -- and it did not score the run it cleared while dealing
		expect(game.moves()).toBe(0)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("opens with at least one legal move", function()
		local core, deps = makeWorld()
		local game = match3.build(Facet, core, deps)
		expect(game.hasLegalMove()).toBe(true)
		game.dispose()
	end)

	it("...and so does every board a reset deals", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		for _ = 1, 8 do
			adapter.tap(game.resetPath)
			expect(next(game.findMatches())).toBeNil()
			expect(game.hasLegalMove()).toBe(true)
		end
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a swap that makes no run is refused WITH A REASON, and costs no move", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		game.debugSetBoard({
			{ "a", "b", "c", "d", "e", "a" },
			{ "b", "c", "d", "e", "a", "b" },
			{ "c", "d", "e", "a", "b", "c" },
			{ "d", "e", "a", "b", "c", "d" },
			{ "e", "a", "b", "c", "d", "e" },
			{ "a", "b", "c", "d", "e", "a" },
		})
		local before = game.boardSnapshot()
		adapter.tap(game.cellPath(1, 1))
		adapter.tap(game.cellPath(1, 2)) -- adjacent, but makes nothing
		expect(game.boardSnapshot()).toEqual(before)
		expect(game.moves()).toBe(0)
		expect(game.score()).toBe(0)
		expect(string.find(game.hintText(), "no run of three", 1, true) ~= nil).toBe(true)
		game.dispose()
	end)

	it("tapping a NON-adjacent tile says tiles have to touch", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		adapter.tap(game.cellPath(1, 1))
		adapter.tap(game.cellPath(4, 4))
		expect(string.find(game.hintText(), "have to touch", 1, true) ~= nil).toBe(true)
		expect(game.moves()).toBe(0)
		game.dispose()
	end)

	it("tapping the selected tile again puts it down", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		deps.presenter.refresh()
		adapter.tap(game.cellPath(2, 2))
		deps.presenter.refresh()
		expect(adapter.node(game.cellPath(2, 2)).props.selected).toBe(true)
		adapter.tap(game.cellPath(2, 2))
		deps.presenter.refresh()
		expect(adapter.node(game.cellPath(2, 2)).props.selected).toBe(false)
		game.dispose()
	end)

	it("a swap SCORES what it clears, counts the move, and chains resolve in one go", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		-- swapping (1,3)<->(2,3) completes a,a,a on row 1
		game.debugSetBoard({
			{ "a", "a", "b", "c", "d", "e" },
			{ "c", "d", "a", "e", "b", "c" },
			{ "e", "b", "c", "d", "a", "b" },
			{ "b", "c", "d", "e", "c", "a" },
			{ "d", "e", "b", "a", "e", "d" },
			{ "a", "c", "e", "b", "d", "c" },
		})
		adapter.tap(game.cellPath(1, 3))
		adapter.tap(game.cellPath(2, 3))
		expect(game.moves()).toBe(1)
		expect(game.score() >= 3).toBe(true) -- at least the run of three it made
		expect(string.find(game.hintText(), "Cleared", 1, true) ~= nil).toBe(true)
		-- and the board it left has no run standing: every chain resolved
		expect(next(game.findMatches())).toBeNil()
		-- no holes
		for _, kind in game.boardSnapshot() do
			expect(kind ~= nil and kind ~= "").toBeTruthy()
		end
		game.dispose()
	end)

	it("reset returns score, moves, selection and the message to their start values", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		local startHint = game.hintText()
		local startBoard = game.boardSnapshot()
		adapter.tap(game.cellPath(1, 1))
		adapter.tap(game.cellPath(4, 4)) -- leave a selection AND a refusal
		adapter.tap(game.resetPath)
		expect(game.score()).toBe(0)
		expect(game.moves()).toBe(0)
		expect(game.hintText()).toBe(startHint)
		-- deterministic: the same seed deals the same opening board again
		expect(game.boardSnapshot()).toEqual(startBoard)
		deps.presenter.refresh()
		expect(adapter.node(game.cellPath(1, 1)).props.selected).toBe(false)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("rapid tapping and resetting leaves no stale selection or error", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		for _ = 1, 15 do
			adapter.tap(game.cellPath(1, 1))
			adapter.tap(game.cellPath(1, 2))
			adapter.tap(game.cellPath(6, 6))
			adapter.tap(game.reloadPath)
			adapter.tap(game.breakPath)
			adapter.tap(game.deliverPath)
			adapter.tap(game.resetPath)
		end
		expect(game.score()).toBe(0)
		expect(game.moves()).toBe(0)
		expect(game.hasLegalMove()).toBe(true)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("supports gamepad grid navigation across navigation-group rows", function()
		local core, deps = makeWorld()
		local game = match3.build(Facet, core, deps)
		local focus = deps.presenter.focus
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		focus.navigateDirection("right")
		expect(focus.focused:get()).toBe(game.cellPath(1, 2))
		focus.navigateDirection("down") -- crosses to the next row, same column
		expect(focus.focused:get()).toBe(game.cellPath(2, 2))
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps = makeWorld()
		local baseline = core:counters()
		local game = match3.build(Facet, core, deps)
		game.swap(1, 1, 1, 2)
		game.dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)

	-- Per-input proofs (ADR-0013): the example now carries NO activation router,
	-- no focus-scope swap, and no custom nav context — each tile has a node
	-- onActivate (select/swap) and the board's HStack rows yield layout-derived
	-- 2D navigation. The audit had gamepad only PARTIAL (focus-API) and every
	-- other class UNPROVEN (swaps went through the direct game.swap API). Each
	-- proof drives a real device path and is checked against that same swap API.
	local SWAP_BOARD = {
		{ "a", "a", "b", "c", "d", "e" },
		{ "c", "d", "a", "e", "b", "c" },
		{ "e", "b", "c", "d", "a", "b" },
		{ "b", "c", "d", "e", "c", "a" },
		{ "d", "e", "b", "a", "e", "d" },
		{ "a", "c", "e", "b", "d", "c" },
	}
	-- the board that the direct swap API (1,3)<->(2,3) produces from SWAP_BOARD
	local function referenceAfterSwap(): { string }
		local core, deps = makeWorld()
		local ref = match3.build(Facet, core, deps)
		ref.debugSetBoard(SWAP_BOARD)
		ref.swap(1, 3, 2, 3)
		local snap = ref.boardSnapshot()
		ref.dispose()
		return snap
	end

	it("✓ ex07 pointer: tapping two adjacent tiles swaps them (matches the swap API)", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		game.debugSetBoard(SWAP_BOARD)
		adapter.tap(game.cellPath(1, 3)) -- select
		adapter.tap(game.cellPath(2, 3)) -- adjacent -> swap
		expect(game.boardSnapshot()).toEqual(referenceAfterSwap())
		game.dispose()
	end)

	it("✓ ex07 touch: touch taps on two adjacent tiles swap them", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		game.debugSetBoard(SWAP_BOARD)
		adapter.tap(game.cellPath(1, 3), { pointer = "touch" })
		adapter.tap(game.cellPath(2, 3), { pointer = "touch" })
		expect(game.boardSnapshot()).toEqual(referenceAfterSwap())
		game.dispose()
	end)

	it("✓ ex07 keyboard: arrow keys navigate and Return swaps adjacent tiles", function()
		local core, deps = makeWorld()
		local game = match3.build(Facet, core, deps)
		game.debugSetBoard(SWAP_BOARD)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		press(sys, "Right")
		press(sys, "Right")
		expect(focus.focused:get()).toBe(game.cellPath(1, 3))
		press(sys, "Return") -- select (1,3)
		press(sys, "Down") -- to (2,3)
		press(sys, "Return") -- swap
		expect(game.boardSnapshot()).toEqual(referenceAfterSwap())
		game.dispose()
	end)

	it("✓ ex07 gamepad: DPad navigation and ButtonA swaps adjacent tiles", function()
		local core, deps = makeWorld()
		local game = match3.build(Facet, core, deps)
		game.debugSetBoard(SWAP_BOARD)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		press(sys, "DPadRight")
		press(sys, "DPadRight")
		expect(focus.focused:get()).toBe(game.cellPath(1, 3))
		press(sys, "ButtonA") -- select (1,3)
		press(sys, "DPadDown") -- to (2,3)
		press(sys, "ButtonA") -- swap
		expect(game.boardSnapshot()).toEqual(referenceAfterSwap())
		game.dispose()
	end)
end)
