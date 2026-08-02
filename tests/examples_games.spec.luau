--!strict
-- Tests for the three game gallery examples (docs progressive tutorial 6-8):
--   06 Wordle-style word game, 07 Scrabble-style tile game, 08 match-3.
-- Each example module exports { title, build } where
--   build(LuauUI, core, deps) -> a table with the presented screen, the
--   presenter handle, and a small game/test API.
-- deps = { env, actionSystem, presenter, adapter }.
-- Everything here runs headless under Lune against the FakeTarget adapter, so
-- these double as the write-once-run-everywhere proof: no engine, no Studio.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

local wordGame = require("../examples/gallery/examples/05_word_game")
local tileGame = require("../examples/gallery/examples/06_tile_game")
local match3 = require("../examples/gallery/examples/07_match3")

-- Build a fresh headless stack (core + environment + input + adapter +
-- presenter). Baseline the core counters AFTER the presenter exists but BEFORE
-- the example builds, so a later example.dispose() can prove registry-neutral
-- teardown of everything the example itself created.
local function makeWorld(viewport: any?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	if viewport ~= nil then
		env:set("viewportRect", viewport)
	end
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local deps = { env = env, actionSystem = system, presenter = pres, adapter = adapter }
	return core, deps, adapter
end

-- fire a device key press+release through the arbitrated action pipeline (the
-- real keyboard/gamepad path; adapter.tap is the real pointer/touch path)
local function press(system: any, key: string)
	system.deviceKey(key, true)
	system.deviceKey(key, false)
end

-- =====================================================================
-- 06 — Wordle-style word game
-- =====================================================================
describe("examples/06 word game (Wordle-style)", function()
	it("mounts and renders headlessly with no runtime error", function()
		local core, deps, adapter = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
		expect(core:lastError()).toBeNil()
		-- the screen and a first-row tile both reached the adapter
		expect(adapter.node("/Wordle") == nil).toBeFalsy()
		expect(adapter.node("/Wordle/board/row1/tile1") == nil).toBeFalsy()
		game.dispose()
	end)

	it("hardware keys fill the row and a wrong guess colors the tiles", function()
		local core, deps = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
		adapter.tap(game.keyPath("R"), { pointer = "touch" })
		expect(game.row(1)).toBe("R")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("✓ ex05 keyboard: arrow keys navigate the on-screen keyboard grid (device path)", function()
		local core, deps = makeWorld()
		local game = wordGame.build(LuauUI, core, deps)
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
		local game = wordGame.build(LuauUI, core, deps)
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
-- 07 — Scrabble-style tile game
-- =====================================================================
describe("examples/07 tile game (Scrabble-style)", function()
	it("mounts and renders headlessly with no runtime error", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(LuauUI, core, deps)
		expect(core:lastError()).toBeNil()
		expect(adapter.node("/TileGame") == nil).toBeFalsy()
		expect(adapter.node(game.cellPath(1, 1)) == nil).toBeFalsy()
		expect(adapter.node(game.rackPath(1)) == nil).toBeFalsy()
		game.dispose()
	end)

	it("select-then-place moves a rack tile onto a cell and scores it", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(LuauUI, core, deps)
		expect(game.score()).toBe(0)
		local rackBefore = game.rackCount()
		local letter, value = game.rackTile(1)
		-- tap the first rack tile (select), then tap a board cell (place)
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(2, 3))
		expect(game.placedAt(2, 3)).toBe(letter)
		expect(game.score()).toBe(value)
		expect(game.rackCount()).toBe(rackBefore - 1)
		-- placing a second tile adds its value to the running score
		local _, value2 = game.rackTile(1)
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(2, 4))
		expect(game.score()).toBe(value + value2)
		game.dispose()
	end)

	it("tears down to a registry baseline after dispose", function()
		local core, deps, adapter = makeWorld()
		local baseline = core:counters()
		local game = tileGame.build(LuauUI, core, deps)
		adapter.tap(game.rackPath(1))
		adapter.tap(game.cellPath(1, 1))
		game.dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)

	-- Per-input proofs (ADR-0013): the example now carries NO activation router
	-- (each cell/tile has a node onActivate) and gains 2D grid navigation from
	-- the board's + rack's HStack rows (layout-derived groups). Pointer was the
	-- only PROVEN class; these close touch/keyboard/gamepad — including the grid
	-- nav that was STRUCTURALLY ABSENT (flat ring) in the audit.
	it("✓ ex06 touch: touch taps select a rack tile and place it on a board cell", function()
		local core, deps, adapter = makeWorld()
		local game = tileGame.build(LuauUI, core, deps)
		local letter, value = game.rackTile(1)
		adapter.tap(game.rackPath(1), { pointer = "touch" })
		adapter.tap(game.cellPath(1, 1), { pointer = "touch" })
		expect(game.placedAt(1, 1)).toBe(letter)
		expect(game.score()).toBe(value)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("✓ ex06 keyboard: arrow/Return select-then-place from the rack onto the board", function()
		local core, deps = makeWorld()
		local game = tileGame.build(LuauUI, core, deps)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		local letter, value = game.rackTile(1)
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		for _ = 1, 5 do
			press(sys, "Down") -- down the 5 board rows into the rack
		end
		expect(focus.focused:get()).toBe(game.rackPath(1))
		press(sys, "Return") -- select the rack tile
		press(sys, "Up") -- back up to the bottom board row, same column
		press(sys, "Return") -- place it
		expect(game.placedAt(5, 1)).toBe(letter)
		expect(game.score()).toBe(value)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("✓ ex06 gamepad: DPad grid navigation with ButtonA select-then-place", function()
		local core, deps = makeWorld()
		local game = tileGame.build(LuauUI, core, deps)
		local sys = deps.actionSystem
		local focus = deps.presenter.focus
		local letter, value = game.rackTile(1)
		expect(focus.focused:get()).toBe(game.cellPath(1, 1))
		for _ = 1, 5 do
			press(sys, "DPadDown")
		end
		expect(focus.focused:get()).toBe(game.rackPath(1))
		press(sys, "ButtonA") -- select the rack tile
		press(sys, "DPadUp")
		press(sys, "ButtonA") -- place it
		expect(game.placedAt(5, 1)).toBe(letter)
		expect(game.score()).toBe(value)
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
		local game = match3.build(LuauUI, core, deps)
		expect(core:lastError()).toBeNil()
		expect(adapter.node("/Match3") == nil).toBeFalsy()
		expect(adapter.node(game.cellPath(1, 1)) == nil).toBeFalsy()
		game.dispose()
	end)

	it("a swap that forms a run clears and refills, and replays deterministically", function()
		local core, deps = makeWorld()
		local game = match3.build(LuauUI, core, deps)
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
		local game2 = match3.build(LuauUI, core2, deps2)
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

	it("the board adapts between phone and desktop viewports without remounting", function()
		local core, deps, adapter = makeWorld({ x = 0, y = 0, w = 390, h = 844 }) -- phone
		local game = match3.build(LuauUI, core, deps)
		deps.presenter.refresh()
		local phoneW = adapter.node(game.cellPath(1, 1)).rect.w
		local mountedBefore = game.handle.root.counters().mounted
		local runsBefore = game.handle.root.counters().factoryRuns
		-- rotate to a desktop viewport: the cell resizes, the tree does not
		deps.env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		deps.presenter.refresh()
		local desktopW = adapter.node(game.cellPath(1, 1)).rect.w
		expect(desktopW > phoneW).toBeTruthy() -- bigger cells on the wider screen
		expect(game.handle.root.counters().mounted).toBe(mountedBefore) -- no remount
		expect(game.handle.root.counters().factoryRuns).toBe(runsBefore)
		game.dispose()
	end)

	it("async tile images resolve through the resource provider", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(LuauUI, core, deps)
		-- before completion the tiles show the pending placeholder
		local imgPath = game.imagePath(1, 1)
		expect(adapter.node(imgPath).props.image).toBe(game.pendingImage)
		-- drain the provider's pending window: resolve each requested key
		local pending = game.provider.pendingRequests()
		expect(#pending > 0).toBeTruthy()
		for _, req in pending do
			expect(game.provider.complete(req.key, req.generation, `resolved://{req.key}`)).toBe("applied")
		end
		deps.presenter.refresh()
		-- the (1,1) tile now shows the resolved asset for its kind
		local kind = game.kindAt(1, 1)
		expect(adapter.node(imgPath).props.image).toBe(`resolved://img/{kind}`)
		game.dispose()
	end)

	it("supports gamepad grid navigation across navigation-group rows", function()
		local core, deps = makeWorld()
		local game = match3.build(LuauUI, core, deps)
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
		local game = match3.build(LuauUI, core, deps)
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
		local ref = match3.build(LuauUI, core, deps)
		ref.debugSetBoard(SWAP_BOARD)
		ref.swap(1, 3, 2, 3)
		local snap = ref.boardSnapshot()
		ref.dispose()
		return snap
	end

	it("✓ ex07 pointer: tapping two adjacent tiles swaps them (matches the swap API)", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(LuauUI, core, deps)
		game.debugSetBoard(SWAP_BOARD)
		adapter.tap(game.cellPath(1, 3)) -- select
		adapter.tap(game.cellPath(2, 3)) -- adjacent -> swap
		expect(game.boardSnapshot()).toEqual(referenceAfterSwap())
		game.dispose()
	end)

	it("✓ ex07 touch: touch taps on two adjacent tiles swap them", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(LuauUI, core, deps)
		game.debugSetBoard(SWAP_BOARD)
		adapter.tap(game.cellPath(1, 3), { pointer = "touch" })
		adapter.tap(game.cellPath(2, 3), { pointer = "touch" })
		expect(game.boardSnapshot()).toEqual(referenceAfterSwap())
		game.dispose()
	end)

	it("✓ ex07 keyboard: arrow keys navigate and Return swaps adjacent tiles", function()
		local core, deps = makeWorld()
		local game = match3.build(LuauUI, core, deps)
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
		local game = match3.build(LuauUI, core, deps)
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
