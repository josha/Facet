--!strict
--[[ THE MIDDLE OF A MOVE (match-3 motion, docs/plans/example-games-and-standalones.md
	§"Match-3 motion"; design artifacts/example-games-and-standalones/design/match3-motion.md).

	`tests/examples_games.spec.luau` already proves the board is CORRECT
	afterwards — it proved it against the instantaneous implementation too, which
	is exactly why those cases cannot be the evidence for this stage. Every case
	here is about a frame in the middle, or about an identity that an endpoint
	assertion cannot see:

	  * IDENTITY. After a swap the mounted node for tile N is the same node it
	    was. A rewrite that keyed by CELL passes every endpoint test in the suite
	    and fails this one.
	  * INTERMEDIATE POSITION. Halfway through a swap, on a scripted `dt`, both
	    tiles are painted at neither endpoint while their SOLVED rects are already
	    exact. This is the case that goes red if an instant snap comes back.
	  * ORDERING. Removal strictly precedes gravity, gravity strictly precedes
	    refill, and input unlocks strictly after the last cascade — read off a
	    frame-by-frame observation, not off the phase names alone.
	  * INTERRUPTION. A reset mid-cascade leaves the machine idle with no tick
	    hook, and nothing of the abandoned cascade behind.
	  * FULL / REDUCED PARITY. The same board, score, moves, phase log and
	    deterministic replay, with no `if reducedMotion` anywhere in the example
	    for the two runs to disagree through.
	  * NO SECOND ANIMATION SYSTEM. A source scan that finds zero today and must
	    keep finding zero.

	Everything runs headless under Lune against the FakeTarget, on a scripted
	clock: `presenter.tick(dt)` is the only thing that moves time here, so every
	assertion below is a frame this file chose. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local Facet = require("../src") :: any
local worldLib = require("./lib/world")
local sheet_model = require("../src/tokens/sheet_model")
local tokens = require("../src/tokens/tokens")
local match3 = require("../examples/gallery/examples/07_match3")

local SOURCE_PATH = "examples/gallery/examples/07_match3.luau"
local FRAME = 1 / 60

-- the worked board: swapping (1,3) <-> (2,3) completes a,a,a on row 1. It is the
-- same arrangement examples_games.spec uses, so the two files are talking about
-- the same move.
local SWAP_BOARD = {
	{ "a", "a", "b", "c", "d", "e" },
	{ "c", "d", "a", "e", "b", "c" },
	{ "e", "b", "c", "d", "a", "b" },
	{ "b", "c", "d", "e", "c", "a" },
	{ "d", "e", "b", "a", "e", "d" },
	{ "a", "c", "e", "b", "d", "c" },
}

--[[ ...AND A BOARD WHERE SOMETHING ACTUALLY FALLS.

	`SWAP_BOARD`'s run is on row 1, so it clears the TOP of three columns and
	nothing drops — a fact worth writing down, because the gravity case was first
	written against it and passed its "removal precedes gravity" ordering while
	proving nothing about a tile moving. Here the run lands on row 3, so the two
	tiles above each cleared cell fall one row each. Swapping (3,3) <-> (4,3)
	completes a,a,a across row 3; neither the board before the swap nor the board
	after it holds any other run. ]]
local DROP_BOARD = {
	{ "b", "c", "d", "e", "a", "b" },
	{ "c", "d", "e", "a", "b", "c" },
	{ "a", "a", "b", "d", "e", "a" },
	{ "d", "e", "a", "b", "c", "d" },
	{ "e", "a", "b", "c", "d", "e" },
	{ "a", "b", "c", "d", "e", "a" },
}

--[[ ON THE SHARED SUBSTRATE, because R12's trigger says so: "the next spec file
	that ADDS a builder migrates its file instead". This file was one of two that
	added one.

	`reducedMotion` goes through the substrate's named option rather than a raw
	`env:set`, which matters here more than anywhere: `motionPolicy` is DERIVED
	from that fact and setting the derived key is refused — the right refusal, and
	one this file's whole Full/Reduced parity claim rests on. ]]
local function makeWorld(opts: any?): (any, any, any)
	local options = opts or {}
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 390, h = 844 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		reducedMotion = options.reducedMotion == true,
	})
	local deps = { env = w.env, actionSystem = w.system, presenter = w.pres, adapter = w.adapter }
	return w.core, deps, w.adapter
end

--[[ SETTLE WHAT THE MOUNT ITSELF STARTED, before measuring a move.

	The board's thirty-six rows each run their ENTER transition when the region
	first mounts, and a path a structural transition owns is excluded from
	`withAnimation` by contract. So a swap fired on the mount frame is still
	painted travelling — the records land on the tile's children instead of its
	root — and reading the root would report "no travel" for a board that is
	visibly moving. Advancing past the enters first is what makes the root the
	honest place to read, and it is what a player's first swap is anyway. ]]
local function settleMount(deps: any)
	deps.presenter.refresh()
	for _ = 1, 90 do
		deps.presenter.tick(FRAME)
	end
	deps.presenter.refresh()
end

local function settleBoard(deps: any)
	for _ = 1, 600 do
		deps.presenter.tick(FRAME)
	end
	deps.presenter.refresh()
end

-- tick one frame at a time until the machine is idle, handing every frame to
-- `watch`. Bounded, so a machine that never idles fails loudly here rather than
-- hanging the suite.
local function driveToIdle(game: any, deps: any, watch: (frame: number) -> ()): number
	for frame = 1, 900 do
		deps.presenter.tick(FRAME)
		deps.presenter.refresh()
		watch(frame)
		if not game.isResolving() then
			return frame
		end
	end
	error("match3 motion: the resolve machine never returned to idle in 900 frames", 2)
end

local function newGame(core: any, deps: any): any
	local game = match3.build(Facet, core, deps)
	settleMount(deps)
	game.debugSetBoard(SWAP_BOARD)
	deps.presenter.refresh()
	return game
end

--[[ EVERY POSITION HERE IS READ RELATIVE TO THE BOARD, and that is not a
	convenience.

	The instruction line above the board is a wrapping `UI.Text` whose sentence
	changes as the game talks to the player, so the board's own y follows what the
	line currently says — it always has. A test that captured an absolute y before
	a swap and compared it after would be measuring that sentence, not the tile.
	(The alternative, pinning the hint to a fixed number of lines, is the
	fixed-px-height defect class this repo has a lesson about: a box fixed against
	unfixed content clips the day a player raises their text size.) ]]
local function boardRect(adapter: any): any
	return adapter.node("/Match3/Page/board").rect
end
local function tileRect(adapter: any, game: any, id: number): any?
	local node = adapter.node(game.tilePath(id))
	if node == nil then
		return nil
	end
	local board = boardRect(adapter)
	return {
		x = node.rect.x - board.x,
		y = node.rect.y - board.y,
		paintX = node.presentedPosition.x - board.x,
		paintY = node.presentedPosition.y - board.y,
	}
end

-- the example's source with comment-only lines removed. The header names every
-- mechanism this example deliberately does NOT use — `task.wait`, a second
-- `RunService` connection — which is exactly what a teaching example's header is
-- for, and a raw substring scan would read those sentences as the thing they warn
-- against.
local function codeLines(source: string): { string }
	local out: { string } = {}
	local inBlockComment = false
	for line in string.gmatch(source, "[^\n]*") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		if inBlockComment then
			if string.find(trimmed, "]]", 1, true) ~= nil then
				inBlockComment = false
			end
			continue
		end
		if string.sub(trimmed, 1, 4) == "--[[" then
			if string.find(trimmed, "]]", 5, true) == nil then
				inBlockComment = true
			end
			continue
		end
		if string.sub(trimmed, 1, 2) == "--" or trimmed == "" then
			continue
		end
		table.insert(out, trimmed)
	end
	return out
end

-- =====================================================================
-- Identity: a tile that moves is the SAME tile
-- =====================================================================
describe("match-3 motion: tile identity survives a move", function()
	it("the mounted node for a tile id is the same node it was before the swap", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local movedId = game.tileIdAt(1, 3) :: number
		local partnerId = game.tileIdAt(2, 3) :: number
		local movedNode = adapter.node(game.tilePath(movedId))
		local partnerNode = adapter.node(game.tilePath(partnerId))
		expect(movedNode ~= nil).toBe(true)
		local runsBefore = game.handle.root.counters().factoryRuns
		local mountedBefore = game.handle.root.counters().mounted

		game.swap(1, 3, 2, 3)
		deps.presenter.refresh()

		-- the tiles really did change places in the model...
		expect(game.tileIdAt(2, 3)).toBe(movedId)
		expect(game.tileIdAt(1, 3)).toBe(partnerId)
		-- ...and the mounted node is the SAME TABLE, not a new one at the same
		-- path. This is what a keyed region buys and what a cell-keyed rewrite
		-- cannot fake: identity, not equality.
		expect(adapter.node(game.tilePath(movedId))).toBe(movedNode)
		expect(adapter.node(game.tilePath(partnerId))).toBe(partnerNode)
		-- no row factory re-ran and nothing remounted: a move is a move
		expect(game.handle.root.counters().factoryRuns).toBe(runsBefore)
		expect(game.handle.root.counters().mounted).toBe(mountedBefore)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("every id on the board is unique, and a refill never reuses one", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		local everSeen: { [number]: boolean } = {}
		for _, id in game.tileIds() do
			expect(everSeen[id]).toBeNil()
			everSeen[id] = true
		end
		game.swap(1, 3, 2, 3)
		settleBoard(deps)
		local live = 0
		for _, id in game.tileIds() do
			live += 1
			if everSeen[id] == nil then
				everSeen[id] = true -- a refilled tile: a NEW id
			end
		end
		expect(live).toBe(game.rows * game.cols)
		-- the refill handed out ids nobody had held before
		local total = 0
		for _ in everSeen do
			total += 1
		end
		expect(total > game.rows * game.cols).toBe(true)
		game.dispose()
	end)
end)

-- =====================================================================
-- Intermediate position: the middle of the travel
-- =====================================================================
describe("match-3 motion: the two swapped tiles travel", function()
	it("halfway through the swap phase both tiles are painted at NEITHER endpoint", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local aId = game.tileIdAt(1, 3) :: number
		local bId = game.tileIdAt(2, 3) :: number
		local aStart = (tileRect(adapter, game, aId) :: any).y
		local bStart = (tileRect(adapter, game, bId) :: any).y
		expect(aStart ~= bStart).toBe(true)

		game.swap(1, 3, 2, 3)
		deps.presenter.refresh()
		-- THE SOLVER IS EXACT AND INSTANT: the rects are already the destination
		-- on the frame the call returns, which is what keeps hit-testing and focus
		-- from chasing a moving pixel.
		local a, b = tileRect(adapter, game, aId) :: any, tileRect(adapter, game, bId) :: any
		expect(a.y).toBe(bStart)
		expect(b.y).toBe(aStart)
		-- ...and the PAINT starts where each tile was
		expect(a.paintY).toBe(aStart)
		expect(b.paintY).toBe(bStart)

		-- six frames in — a third of the 0.2 s swap phase — both are between
		for _ = 1, 6 do
			deps.presenter.tick(FRAME)
		end
		deps.presenter.refresh()
		local aMid = (tileRect(adapter, game, aId) :: any).paintY
		local bMid = (tileRect(adapter, game, bId) :: any).paintY
		expect(aMid > aStart and aMid < bStart).toBe(true)
		expect(bMid < bStart and bMid > aStart).toBe(true)

		settleBoard(deps)
		expect(deps.presenter.animationRecordCount()).toBe(0)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a refused swap travels OUT and travels BACK, and says why", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		-- (1,1)a <-> (1,2)a makes no run: the pair goes and comes back
		local aId = game.tileIdAt(1, 1) :: number
		local bId = game.tileIdAt(1, 2) :: number
		local aHome = (tileRect(adapter, game, aId) :: any).x
		local bHome = (tileRect(adapter, game, bId) :: any).x
		local before = game.boardSnapshot()

		game.swap(1, 1, 1, 2)
		for _ = 1, 6 do
			deps.presenter.tick(FRAME)
		end
		deps.presenter.refresh()
		local outbound = (tileRect(adapter, game, aId) :: any).paintX
		expect(outbound > aHome and outbound < bHome).toBe(true)

		-- run to the revert phase and catch it mid-return
		local sawRevert = false
		local returning = false
		driveToIdle(game, deps, function()
			if game.phase() == "revert" then
				sawRevert = true
				local paint = (tileRect(adapter, game, aId) :: any).paintX
				if paint > aHome and paint < bHome then
					returning = true
				end
			end
		end)
		expect(sawRevert).toBe(true)
		expect(returning).toBe(true)
		-- ...and the board is exactly as it was, with the reason on screen
		expect(game.boardSnapshot()).toEqual(before)
		expect(game.moves()).toBe(0)
		expect(string.find(game.hintText(), "no run of three", 1, true) ~= nil).toBe(true)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)

-- =====================================================================
-- The six phases, each with evidence from the middle
-- =====================================================================
describe("match-3 motion: the resolve sequence is visible, in order", function()
	it("removal precedes gravity precedes refill, and input unlocks after the last cascade", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		local seen: { string } = {}
		local lockedEveryFrameBeforeTheEnd = true
		game.swap(1, 3, 2, 3)
		expect(game.isResolving()).toBe(true)
		local last = driveToIdle(game, deps, function(frame)
			local phase = game.phase()
			if seen[#seen] ~= phase then
				table.insert(seen, phase)
			end
			if phase ~= "idle" and not game.isResolving() then
				lockedEveryFrameBeforeTheEnd = false
			end
		end)
		expect(last > 1).toBe(true)
		expect(lockedEveryFrameBeforeTheEnd).toBe(true)
		expect(game.isResolving()).toBe(false)

		local function firstIndexOf(name: string): number?
			for index, phase in seen do
				if phase == name then
					return index
				end
			end
			return nil
		end
		local remove = firstIndexOf("remove") :: number
		local gravity = firstIndexOf("gravity") :: number
		local refill = firstIndexOf("refill") :: number
		expect(remove ~= nil).toBe(true)
		expect(gravity > remove).toBe(true)
		expect(refill > gravity).toBe(true)
		expect((firstIndexOf("idle") :: number) > refill).toBe(true)
		-- the log the game itself keeps agrees, and names what each step did
		local log = game.phaseLog()
		expect(log[1]).toBe("swap")
		expect(log[2]).toBe("mark")
		expect(string.match(log[3], "^remove:(%d+)$") ~= nil).toBe(true)
		expect(tonumber(string.match(log[3], "^remove:(%d+)$")) >= 3).toBe(true)
		expect(log[4]).toBe("gravity")
		expect(string.match(log[5], "^refill:(%d+)$") ~= nil).toBe(true)
		expect(log[6]).toBe("land")
		expect(log[#log]).toBe("idle")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a matched tile leaves the model and stays mounted-but-retiring while it fades", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local doomed: { number } = {}
		for _, cell in { { 1, 1 }, { 1, 2 } } do
			table.insert(doomed, game.tileIdAt(cell[1], cell[2]) :: number)
		end
		game.swap(1, 3, 2, 3)
		local retiredWhileGone = false
		local everGone = false
		driveToIdle(game, deps, function()
			local live: { [number]: boolean } = {}
			for _, id in game.tileIds() do
				live[id] = true
			end
			for _, id in doomed do
				if not live[id] then
					everGone = true
					if adapter.node(game.tilePath(id)) ~= nil then
						retiredWhileGone = true
					end
				end
			end
		end)
		expect(everGone).toBe(true)
		-- the framework held the departing row in its slot while the exit played
		expect(retiredWhileGone).toBe(true)
		-- ...and disposed it when the exit finished: nothing lingers
		settleBoard(deps)
		for _, id in doomed do
			expect(adapter.node(game.tilePath(id))).toBeNil()
		end
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a refilled tile's FIRST painted position is above the board, not its resting one", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		local before: { [number]: boolean } = {}
		for _, id in game.tileIds() do
			before[id] = true
		end
		game.swap(1, 3, 2, 3)
		local sawEnteringFromAbove = false
		local newIds: { [number]: boolean } = {}
		driveToIdle(game, deps, function()
			for _, id in game.tileIds() do
				if not before[id] then
					newIds[id] = true
					local at = tileRect(adapter, game, id)
					if at ~= nil and at.y < 0 then
						sawEnteringFromAbove = true
					end
				end
			end
		end)
		local added = 0
		for _ in newIds do
			added += 1
		end
		expect(added >= 3).toBe(true)
		expect(sawEnteringFromAbove).toBe(true)
		-- ...and every one of them has landed inside the board by the end
		for id in newIds do
			local at = tileRect(adapter, game, id)
			if at ~= nil then
				expect(at.y >= 0).toBe(true)
			end
		end
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a survivor DROPS: its painted position is between its old row and its new one", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.debugSetBoard(DROP_BOARD)
		deps.presenter.refresh()
		expect(next(game.findMatches())).toBeNil() -- the arrangement is not already won
		-- (2,1) sits above the row-3 clear and falls one row when it goes
		local survivor = game.tileIdAt(2, 1) :: number
		local homeY = (tileRect(adapter, game, survivor) :: any).y
		game.swap(3, 3, 4, 3)
		local travelledDown = false
		local restY = homeY
		driveToIdle(game, deps, function()
			local at = tileRect(adapter, game, survivor)
			if at == nil then
				return
			end
			restY = at.y
			if at.y > homeY and at.paintY > homeY and at.paintY < at.y then
				travelledDown = true
			end
		end)
		expect(restY > homeY).toBe(true) -- it really did end up lower
		expect(travelledDown).toBe(true) -- and it was seen on the way
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("a tap while the board resolves is REFUSED in words, and costs nothing", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.swap(1, 3, 2, 3)
		deps.presenter.tick(FRAME)
		deps.presenter.refresh()
		expect(game.isResolving()).toBe(true)
		local movesBefore = game.moves()
		adapter.tap(game.cellPath(6, 1))
		adapter.tap(game.cellPath(6, 2))
		expect(game.moves()).toBe(movesBefore)
		expect(string.find(game.hintText(), "still settling", 1, true) ~= nil).toBe(true)
		settleBoard(deps)
		expect(game.moves()).toBe(1) -- only the swap the player actually made
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)

-- =====================================================================
-- Navigation, after the board has rearranged itself
-- =====================================================================
describe("match-3 motion: the anchored board still navigates in two dimensions", function()
	--[[ WHY THIS NEEDS ITS OWN CASE.

		A `UI.Grid` hands the presenter per-row navigation groups for free
		(ADR-0013 layout-derived groups). A `UI.Anchor` has none to read — free
		placement is the whole point of it — so the example declares the board as
		one RECTANGLE group (`columns`, ADR-0030) plus the two groups below it,
		through the public `navigationGroups` opt. That declaration is rebuilt
		from the board's CURRENT occupancy, and the presenter re-derives it on a
		structural change, so this case asks the question after a cascade has
		moved and replaced tiles rather than only on the opening board. ]]
	it("left/right walks the lane and up/down keeps it, before AND after a cascade", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		local focus = deps.presenter.focus
		local function check(where: string)
			focus.focusOn(game.cellPath(1, 1))
			expect(focus.focused:get()).toBe(game.cellPath(1, 1))
			focus.navigateDirection("right")
			expect(focus.focused:get()).toBe(game.cellPath(1, 2))
			focus.navigateDirection("down") -- keeps the lane, moves a whole line
			expect(focus.focused:get()).toBe(game.cellPath(2, 2))
			focus.navigateDirection("left")
			expect(focus.focused:get()).toBe(game.cellPath(2, 1))
			if focus.focused:get() ~= game.cellPath(2, 1) then
				error(`board navigation broke {where}`, 2)
			end
		end
		check("on the opening board")
		game.swap(1, 3, 2, 3)
		settleBoard(deps)
		check("after a cascade moved and replaced tiles")
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("...and everything below the board is still reachable without a pointer", function()
		local core, deps = makeWorld()
		local game = newGame(core, deps)
		local focus = deps.presenter.focus
		focus.focusOn(game.cellPath(6, 1))
		focus.navigateDirection("down") -- off the bottom row, into the artwork row
		expect(focus.focused:get()).toBe(game.reloadPath)
		focus.navigateDirection("right")
		expect(focus.focused:get()).toBe(game.deliverPath)
		focus.navigateDirection("right")
		expect(focus.focused:get()).toBe(game.breakPath)
		focus.navigateDirection("down")
		expect(focus.focused:get()).toBe(game.resetPath)
		focus.navigateDirection("up")
		expect(focus.focused:get() ~= game.resetPath).toBe(true)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)
end)

-- =====================================================================
-- Interruption and reset
-- =====================================================================
describe("match-3 motion: a reset mid-cascade leaves nothing behind", function()
	it("stops the machine, drops its tick hook, and leaves no retiring row or animation record", function()
		local core, deps, adapter = makeWorld()
		local game = newGame(core, deps)
		game.swap(1, 3, 2, 3)
		-- get into the middle: run until the removal has happened and the
		-- survivors are dropping
		local reached = false
		for _ = 1, 900 do
			deps.presenter.tick(FRAME)
			deps.presenter.refresh()
			if game.phase() == "gravity" then
				reached = true
				break
			end
		end
		expect(reached).toBe(true)
		expect(game.tickHookActive()).toBe(true)
		expect(deps.presenter.animationRecordCount() > 0).toBe(true)

		adapter.tap(game.resetPath)

		-- IMMEDIATELY: the example's own bookkeeping is empty. Nothing is queued,
		-- nothing is mid-phase, and the one frame hook it registers is gone.
		expect(game.phase()).toBe("idle")
		expect(game.phaseLog()).toEqual({})
		expect(game.isResolving()).toBe(false)
		expect(game.tickHookActive()).toBe(false)
		expect(game.score()).toBe(0)
		expect(game.moves()).toBe(0)

		-- ...and once the framework's own exit cap and springs have run out (both
		-- are ITS clock, not the example's, and neither is overridable), nothing
		-- of the abandoned cascade is still on screen.
		settleBoard(deps)
		expect(deps.presenter.animationRecordCount()).toBe(0)
		local live: { [number]: boolean } = {}
		for _, id in game.tileIds() do
			live[id] = true
		end
		for _, path in adapter.paths() do
			local id = tonumber(string.match(path, "^/Match3/Page/board/tiles/%[(%d+)%]"))
			if id ~= nil then
				expect(live[id]).toBe(true)
			end
		end
		-- the machine is still usable afterwards
		game.debugSetBoard(SWAP_BOARD)
		game.swap(1, 3, 2, 3)
		settleBoard(deps)
		expect(game.moves()).toBe(1)
		expect(core:lastError()).toBeNil()
		game.dispose()
	end)

	it("dispose mid-cascade unregisters the hook and leaves the registry at baseline", function()
		local core, deps = makeWorld()
		local baseline = core:counters()
		local game = match3.build(Facet, core, deps)
		settleMount(deps)
		game.debugSetBoard(SWAP_BOARD)
		game.swap(1, 3, 2, 3)
		for _ = 1, 12 do
			deps.presenter.tick(FRAME)
		end
		expect(game.tickHookActive()).toBe(true)
		game.dispose()
		expect(game.tickHookActive()).toBe(false)
		-- ticking a presenter whose game is gone must not resurrect anything
		for _ = 1, 60 do
			deps.presenter.tick(FRAME)
		end
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
		expect(core:lastError()).toBeNil()
	end)
end)

-- =====================================================================
-- Full / reduced parity
-- =====================================================================
describe("match-3 motion: reduced motion changes the paint and nothing else", function()
	--[[ THE EXAMPLE HAS NO BRANCH FOR THIS, AND THAT IS THE POINT.

		Ordering, feedback, scoring and the final board come from the state
		machine, which runs on `presenter.onTick` — a clock, not an animation. The
		travel and the enter/exit forms come from the motion authority, whose own
		reduced-motion contract substitutes "place instantly, fire the same events
		on the same frame". So the two runs agree because there is no code path in
		which they could differ, not because a second branch was kept agreeing. ]]
	local function playOut(reduced: boolean): any
		local core, deps, adapter = makeWorld({ reducedMotion = reduced })
		local game = newGame(core, deps)
		local records = 0
		game.swap(1, 3, 2, 3)
		records = math.max(records, deps.presenter.animationRecordCount())
		driveToIdle(game, deps, function()
			records = math.max(records, deps.presenter.animationRecordCount())
		end)
		local result = {
			board = game.boardSnapshot(),
			score = game.score(),
			moves = game.moves(),
			log = game.phaseLog(),
			hint = game.hintText(),
			ids = game.tileIds(),
			records = records,
			error = core:lastError(),
		}
		game.dispose()
		return result
	end

	it("the same board, score, moves, phase log and replay under both policies", function()
		local full = playOut(false)
		local reduced = playOut(true)
		expect(reduced.board).toEqual(full.board)
		expect(reduced.score).toBe(full.score)
		expect(reduced.moves).toBe(full.moves)
		expect(reduced.log).toEqual(full.log)
		expect(reduced.hint).toBe(full.hint)
		-- deterministic replay: the same seed hands out the same ids in the same
		-- order to the same slots
		expect(reduced.ids).toEqual(full.ids)
		expect(full.error).toBeNil()
		expect(reduced.error).toBeNil()
	end)

	it("...and reduced motion installs NO animation records rather than substituting another effect", function()
		local full = playOut(false)
		local reduced = playOut(true)
		expect(full.records > 0).toBe(true)
		expect(reduced.records).toBe(0)
	end)

	it("the example contains no reduced-motion branch at all", function()
		local offenders: { string } = {}
		for _, line in codeLines(fs.readFile(SOURCE_PATH)) do
			for _, needle in { "reducedMotion", "motionPolicy", "prefersReducedMotion" } do
				if string.find(line, needle, 1, true) ~= nil then
					table.insert(offenders, `{needle}: {line}`)
				end
			end
		end
		if #offenders > 0 then
			error(`the example branches on the motion policy:\n  ` .. table.concat(offenders, "\n  "), 2)
		end
		expect(#offenders).toBe(0)
	end)
end)

-- =====================================================================
-- No second animation system
-- =====================================================================
describe("match-3 motion: the example builds no animation system of its own", function()
	local BANNED: { { needle: string, why: string } } = {
		{ needle = "TweenService", why = "the engine's own tween pipeline, outside the framework's motion model" },
		{ needle = "RunService", why = "a second frame source; `presenter.onTick` is the sanctioned one" },
		{ needle = "task.wait", why = "a timer where the state machine's clock belongs" },
		{ needle = "task.delay", why = "the same timer, spelled deferred" },
		{ needle = "task.spawn", why = "a coroutine driving presentation behind the presenter's back" },
		{ needle = "Instance.new", why = "raw instance construction" },
		{ needle = "os.clock", why = "wall time; the presenter's clock is the one that is scripted in tests" },
		{ needle = "os.time", why = "wall time again" },
		{ needle = "tick()", why = "wall time again" },
		{ needle = "setProp", why = "a direct adapter write" },
		{ needle = "GetService", why = "a direct engine service" },
	}

	it("finds none of them in a single line of its code", function()
		local found: { string } = {}
		for _, line in codeLines(fs.readFile(SOURCE_PATH)) do
			for _, entry in BANNED do
				if string.find(line, entry.needle, 1, true) ~= nil then
					table.insert(found, `{entry.needle} on \`{line}\` — {entry.why}`)
				end
			end
		end
		if #found > 0 then
			error(`the match-3 example grew a second animation system:\n  ` .. table.concat(found, "\n  "), 2)
		end
		expect(#found).toBe(0)
	end)

	it("...and it really did scan the example, which uses the four public mechanisms by name", function()
		-- the discriminator between "clean" and "scanned nothing": the file is
		-- large and it names every public seam this stage is built on
		local source = fs.readFile(SOURCE_PATH)
		expect(#source > 10000).toBe(true)
		-- ...and the stripper left real code behind rather than eating the file
		expect(#codeLines(source) > 300).toBe(true)
		for _, needle in
			{
				"presenter", -- the deps handle every mechanism hangs off
				"withAnimation",
				"onTick",
				"UI.Anchor",
				"UI.ForEach",
				"transition = { enter",
			}
		do
			expect(string.find(source, needle, 1, true) ~= nil).toBe(true)
		end
	end)
end)

-- =====================================================================
-- The tiles are still THERE, in every shipped theme
-- =====================================================================
--[[ THE FLOOR, AND WHERE THE NUMBER COMES FROM. 1.25:1 is the measurement the
	word game and the crossword took (see tests/example_word_game.spec.luau's
	block on it and docs/lessons/a-default-valued-write-never-claims.md): a plate
	declared `{ role = "surfaceStrong", blend = 0.6 }` is 1.036:1 against the page
	under Sci-Fi HUD, present in the tree and not on the screen.

	The match-3 tile's colour is an IMAGE TINT rather than a plate, and this
	rewrite did not move it — same five roles, same `blend = 1`, resolved through
	the same `sheet_model.tintColor` seam. It is held to the same floor anyway,
	because "the tile paint is unchanged" is a claim about this file's source and
	this is a measurement of the rendered tree. ]]
local VISIBLE_FLOOR = 1.25

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

describe("match-3 motion: thirty-six tiles that are actually painted, in every shipped theme", function()
	it("sweeps a real set of themes, not an empty one", function()
		expect(#THEMES >= 12).toBe(true)
	end)

	it("every tile picture clears the visibility floor against the page it sits on", function()
		local core, deps, adapter = makeWorld()
		local game = match3.build(Facet, core, deps)
		settleMount(deps)
		local problems: { string } = {}
		local checked = 0
		local worst = { ratio = math.huge, where = "" }
		for _, entry in THEMES do
			adapter.setThemePackage(entry.package, entry.themeName, nil)
			deps.presenter.refresh()
			local page = sheet_model.paletteColor(entry.theme, "surface")
			for r = 1, game.rows do
				for c = 1, game.cols do
					checked += 1
					local path = game.imagePath(r, c)
					local img = adapter.node(path)
					if img == nil then
						table.insert(problems, `{entry.id} {path}: no node at all`)
						continue
					end
					if img.rect == nil or img.rect.w <= 0 or img.rect.h <= 0 then
						table.insert(problems, `{entry.id} {path}: arranged to nothing`)
						continue
					end
					if img.tintColor == nil then
						table.insert(problems, `{entry.id} {path}: the tile has no resolved tint`)
						continue
					end
					local ratio = tokens.contrastRatio(img.tintColor, page)
					if ratio < worst.ratio then
						worst = { ratio = ratio, where = `{entry.id} {path}` }
					end
					if ratio < VISIBLE_FLOOR then
						table.insert(
							problems,
							string.format(
								"%s %s: the tile paints %.3f:1 against the page it sits on (floor %.2f)",
								entry.id,
								path,
								ratio,
								VISIBLE_FLOOR
							)
						)
					end
				end
			end
		end
		if #problems > 0 then
			error(`{#problems} invisible or missing tile(s):\n  ` .. table.concat(problems, "\n  ", 1, 8), 2)
		end
		expect(checked).toBe(#THEMES * game.rows * game.cols)
		expect(worst.ratio >= VISIBLE_FLOOR).toBe(true)
		game.dispose()
	end)

	it("...and the floor BITES: the role this example carried until this round drops under it", function()
		--[[ A check nobody has watched fail is a check that proves nothing. This
			runs the SAME metric over the SAME themes against `controlSelected` —
			the tint kind `c` carried until 2026-08-29 — and it has to come out
			BELOW the floor somewhere, or this sweep would not have caught the
			defect it was written for.

			It is a control-chrome role, and a theme keeps its selected-control
			fill within a few percent of the surface it highlights by design, which
			is why a `c` tile disappeared into the page under Classic Desktop /
			Day. The five roles the board carries now are the five that clear the
			floor at every shipped theme (see examples/gallery/examples/assets.luau). ]]
		local below: { string } = {}
		local worst = { ratio = math.huge, where = "" }
		for _, entry in THEMES do
			local page = sheet_model.paletteColor(entry.theme, "surface")
			local old = sheet_model.tintColor(entry.theme, { role = "controlSelected", blend = 1 }, "Image")
			local ratio = tokens.contrastRatio(old, page)
			if ratio < worst.ratio then
				worst = { ratio = ratio, where = entry.id }
			end
			if ratio < VISIBLE_FLOOR then
				table.insert(below, string.format("%s (%.3f:1)", entry.id, ratio))
			end
		end
		expect(#below > 0).toBe(true)
		expect(worst.where).toBe("classic_desktop/Day")
		expect(worst.ratio < VISIBLE_FLOOR).toBe(true)
		-- ...and none of the five roles the board carries now is that role
		local assets = require("../examples/gallery/examples/assets")
		for _, role in assets.match3Tints do
			expect(role ~= "controlSelected").toBe(true)
		end
	end)
end)
