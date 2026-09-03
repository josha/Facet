--!strict
--[[ O4 + N1 — THE COMMIT UNDER A TRANSLATE.

	Of the eight walks, five are provably position-independent, `visible` is too
	on any surface without a stroked `UI.Path`, and only `hitRects` and
	`rect_pass` genuinely need to see a move (commit-seams 1.11). They all
	descend anyway, because `skip` compares ENTRY TABLE IDENTITY
	(`commit_walks.luau`'s `skip`) and a moved node has a new entry table.

	So a translated entry carries `moveOnly` and a `prev` pointer at the table it
	superseded, and a walk that cannot depend on position asks `skip(node, true)`
	— which accepts "same entry as last commit" OR "a move away from the entry I
	last committed". `visible` passes `true` only when its existing whole-surface
	`prunable` latch is open, so one `UI.Path` still closes it, exactly as today.

	And `rect_pass` stops at a translate root: the 1,500 writes are real (flat
	engine tree, profile §1) but the WALK and the `rectsEqual` compare are not —
	the run the solver recorded is the subtree in document order, and every rect
	in it provably differs from what was last written, so the compare is dead
	work. `lastCommitEntry` is still maintained for every applied path
	(`scope.noteEntry`), or the next commit's prune would compare against a
	two-ticks-old table and descend everything — which is why every counter case
	below ticks TWICE.

	THE FLOOR IS `|nodeDirty|`, NOT ZERO. `skip` refuses for any path in
	`nodeDirty`, and every plate root wrote a prop this tick, so the six pruned
	walks visit exactly the dirty closure and stop at its edge. Getting below that
	needs a class-aware `nodeDirty` (an arrange-class prop write that does not mark
	the COMMIT's set) and that is a separate task. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY
-- layout nodes + the ForEach REGION. There is no per-item wrapper node
-- (`mount.luau:357` uses `rowPath` as a parent path; `:595-596` mounts the row's
-- own root at `…/[pN]/Plate`), so this is LAYOUT + 1.
local MOUNTED = PLATES * scene.NODES_PER_PLATE + 2 + 1 -- 1503
-- the VISITED closure: Screen, Canvas, the region, one root per plate. The 250
-- `…/[pN]` strings `markNodeDirty` also writes have no node behind them and `skip`
-- is never asked about them.
local DIRTY_TICK = 3 + PLATES -- 253
local DIRTY_CASTS = DIRTY_TICK + CASTERS -- 303
-- the six walks whose output cannot read a position. `rect_pass` is the seventh
-- that stops at a moved subtree, but it stops for a DIFFERENT reason — it stops AT
-- each translate root and emits the run, rather than pruning the root away — so it
-- gets its own number on a mixed tick (see `RECTPASS_CASTS`).
local MOVE_BLIND = { "harvest", "textScale", "padding", "textVerdicts", "visible", "scrollRegions" }
--[[ ...AND ON A CASTER TICK `rectPass` IS 403, NOT 303 — READ OFF THE RUN, and the
	plan's own table predicted 303. The two numbers differ because the two prunes are
	different questions, which is exactly what this spec is for.

	Under T4's settled derivation (b) a caster's plate root is NOT a translate root
	(`translatable` refuses it: its `Cast` child is dirty), and `Row` and `Hp` become
	translate roots UNDER it — `Row` with a two-node span, `Hp` with an EMPTY one
	(a childless root still records a run). A move-blind walk prunes `Row` and `Hp`
	away and visits 4 - 2 = 2 nodes per caster plus the 250 roots = 303. `rect_pass`
	cannot: it must WRITE `Row`'s and `Hp`'s own rects, so it visits them and stops
	there. 4 per caster (Plate, Row, Hp, Cast), 1 per quiet plate, + 3 ancestors. ]]
local RECTPASS_CASTS = 3 + (PLATES - CASTERS) + CASTERS * 4 -- 403

describe("O4/N1: seven walks stop at a moved subtree, hitRects does not", function()
	it("a pure tick", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in MOVE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_TICK}`)
		end
		-- every plate root IS a translate root on a pure tick, so `rect_pass` stops
		-- at exactly the same 253 nodes the move-blind walks prune down to
		expect(`rectPass={by.rectPass}`).toBe(`rectPass={DIRTY_TICK}`)
		expect(`hitRects={by.hitRects}`).toBe(`hitRects={MOUNTED}`)
		s.dispose()
	end)

	it("a caster tick pays for the cast bars and nothing else", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in MOVE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_CASTS}`)
		end
		expect(`rectPass={by.rectPass}`).toBe(`rectPass={RECTPASS_CASTS}`)
		expect(`hitRects={by.hitRects}`).toBe(`hitRects={MOUNTED}`)
		s.dispose()
	end)

	it("the writes are all still there", function()
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats().rectWrites
		s.tick(3, 2)
		expect(s.stats().rectWrites - before).toBe(PLATES * scene.NODES_PER_PLATE)
		s.dispose()
	end)

	it("ONE UI.Path closes the visible prune, and only that one", function()
		local s = scene.new({ withPath = true })
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		-- EXACTLY the whole tree, `Spark` included (task review round 1, minor 5). A
		-- threshold could not tell 254 from 1504, and the claim is that the latch
		-- opens the WHOLE walk, not that it opens a bit of it.
		expect(`visible={by.visible}`).toBe(`visible={MOUNTED + 1}`)
		-- ...and `harvest` is UNCHANGED at DIRTY_TICK, not DIRTY_TICK + 1. The Spark
		-- Path leaf is never dirty (nothing writes it) and its rect never moves, so
		-- its entry keeps identity and `skip` prunes it like any other clean node.
		-- The `visible` half above is the real assertion of this test: one stroked
		-- path opens the whole-surface latch and nothing else changes.
		expect(`harvest={by.harvest}`).toBe(`harvest={DIRTY_TICK}`)
		s.dispose()
	end)

	it("a ZERO-DELTA translate writes NOTHING, and still prunes", function()
		--[[ THE MINIMAL-WRITE CONTRACT UNDER THE RUN (task review round 1, Important
			1). "A translate means the subtree MOVED" is FALSE: `arrange` takes the
			translate arm whenever the size is unchanged and the node is not (clean AND
			unmoved), so a root dirtied by a prop `selfPlaces` clears and landing where
			it already was translates with `dx = dy = 0` and records a run like any
			other. `Opts.inertAlign` is that drive on this fixture — a reactive
			`lineAlign` on every plate, inert under the `Anchor` parent — and the
			counters below prove it really is the arm (252 arranged + 1250 translated,
			the same split a moving tick produces).

			Every rect in that run is the rect already on screen, so the honest number
			of adapter writes is ZERO. The first version of this arm skipped the
			`rectsEqual` compare on a delta argument and re-sent all 1,250; nothing in
			the snapshot oracle can see a redundant same-value write, which is why this
			pin is a COUNTER and why it is here rather than left to an argument.

			The 250 `lineAlign`-under-an-Anchor diagnostics the drive files are expected
			— that inertness is exactly what makes the delta zero, and `auditPlacement`
			reports it by design. ]]
		local s = scene.new({ inertAlign = true })
		s.tick(3, 2) -- warm: the scene's first refresh is a cold solve
		s.align("center")
		s.align("end")
		local before = s.stats().rectWrites
		s.align("start")
		local st = s.stats()
		expect(`rectWrites delta={st.rectWrites - before}`).toBe("rectWrites delta=0")
		-- ...and it IS the translate arm, not a solve that skipped everything
		expect(`arranged={st.lastArranged} translated={st.lastTranslated}`).toBe(
			`arranged={PLATES + 2} translated={PLATES * (scene.NODES_PER_PLATE - 1)}`
		)
		-- ...and the prune is still on: a zero-delta run is not a special case for it
		local by = st.lastCommitVisitsByWalk
		for _, name in MOVE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_TICK}`)
		end
		expect(`rectPass={by.rectPass}`).toBe(`rectPass={DIRTY_TICK}`)
		s.dispose()
	end)
end)

--[[ `skip`'s THIRD ANSWER, PINNED DIRECTLY (task review round 1, minor 4).

	`commit_walks.new(ctx)` is constructed here with a hand-built ctx because the
	case is about ONE predicate on ONE table shape, and the shape is not reachable
	from a blueprint in two lines: an entry with `moveOnly = true` and `prev = nil`
	on a path the commit has never noted. It is REACHABLE in production — the
	solver's rollback (`solver.luau`, "REFUSED, AND ROLLED BACK") restores an entry
	whose `prev` was cleared by the write that superseded it, while `moveOnly` stays
	set because it is sticky — and `lastCommitEntry` is nil for any path the commit
	never had a handle for (the P5 guard). Without the `last ~= nil` clause the
	move-blind test reads `nil == nil` and prunes that node forever.

	Two harvests, because `pruning` also requires the scale/theme/offset STAMP to be
	unchanged and the first call is the one that sets it. ]]
local commit_walks = require("../src/render/commit_walks")

local function armedWalks(): (any, any)
	local function tbl(): any
		return {}
	end
	local ctx: any = {
		adapter = {},
		handles = tbl(),
		stats = { lastCommitVisits = 0, lastCommitVisitsByWalk = {}, propWrites = 0, rectWrites = 0 },
		rectsEqual = function(a: any, b: any): boolean
			return a == b
		end,
		paintedRectIn = function(): any
			return nil
		end,
		pathEscapesClip = function(): boolean
			return false
		end,
		reculPathClips = function() end,
		lastTextSize = tbl(),
		lastTextFont = tbl(),
		lastPadding = tbl(),
		lastCompact = tbl(),
		lastWrapped = tbl(),
		lastVisible = tbl(),
		lastHitRects = tbl(),
		lastScrollRegions = tbl(),
		scrollAutoscroll = tbl(),
		pathClipObservers = tbl(),
		solverHidden = tbl(),
		paintHeld = tbl(),
		pathNodes = tbl(),
		inputSinks = tbl(),
		lastCommitEntry = tbl(),
		hiddenRoots = tbl(),
		lastCompositions = tbl(),
		lastTextFacts = tbl(),
		authoredHidden = tbl(),
	}
	return commit_walks.new(ctx), ctx
end

describe("O4: a move-blind skip needs an entry it ACTUALLY committed", function()
	it("a sticky moveOnly entry with no prev, on a never-noted path, is NOT skipped", function()
		local walks, ctx = armedWalks()
		local leaf = { path = "/S/A", class = "Box", props = {}, children = {} }
		local root = { path = "/S", class = "Screen", props = {}, children = { leaf } }
		-- the rollback shape: `moveOnly` survived, `prev` was cleared
		local restored = { rect = { x = 0, y = 0, w = 10, h = 10 }, moveOnly = true, prev = nil }
		local rects = { ["/S"] = { rect = { x = 0, y = 0, w = 100, h = 100 } }, ["/S/A"] = restored }
		local metrics = {}
		local dirty = { ["/S"] = true }
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`armed={walks.scope.armed()}`).toBe("armed=true")
		-- THE CASE: nothing was ever committed for this path, so nothing about it can
		-- be "unchanged since the commit before"
		expect(`never-noted={walks.scope.skip(leaf, true)}`).toBe("never-noted=false")

		-- ...and the two answers that MUST still be yes, or the clause above would be
		-- passing by breaking the feature it guards
		ctx.lastCommitEntry["/S/A"] = restored
		expect(`same-entry={walks.scope.skip(leaf, true)}`).toBe("same-entry=true")
		local moved = { rect = { x = 5, y = 0, w = 10, h = 10 }, moveOnly = true, prev = restored }
		rects["/S/A"] = moved
		walks.harvest(root, rects, true, dirty, 1, metrics, 0)
		expect(`moved-from-noted={walks.scope.skip(leaf, true)}`).toBe("moved-from-noted=true")
		-- ...and a walk that READS a position gets none of it
		expect(`not-move-blind={walks.scope.skip(leaf)}`).toBe("not-move-blind=false")
	end)
end)

--[[ THE COMMIT ORACLE — FOUR ARMS, AND THE FOURTH IS THIS TASK'S REAL CONTROL.

	T3/T4's `arms()` varies `measureReuse` and `incremental` only, which is the
	right control for a SOLVER task and the wrong one for this one. The subject
	here is the COMMIT prune, and `Opts` already exposes `commitScope`; an oracle
	that never turns it off compares this task's fix against itself.

	The channel is `scene.snapshot()` — every live node's rect, hit rect, scroll
	region, visibility and every prop the fake adapter holds, sorted. That is what
	the adapter was TOLD, which is what a commit task has to prove; T4's own oracle
	proved the rect MAP and cannot stand in for it. ]]
local function arms(view: any, opts: any): (any, any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base) -- everything ON: the shipped configuration
	local b = table.clone(base)
	b.measureReuse = false -- memo OFF, incremental + commit prune ON
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false -- BOTH solver halves OFF: a forced full solve, and no translate
	-- `commitScope` off is the pre-P4 build: every walk descends the whole tree and
	-- writes what it finds, and `rect_pass` is handed no run to shortcut. If the
	-- pruned commit and the unpruned one ever tell the adapter different things,
	-- THIS is the arm that says so — `c` cannot, because it still runs the prune.
	local d = table.clone(base)
	d.commitScope = false
	return scene.new(a), scene.new(b), scene.new(c), scene.new(d)
end

-- see `translate_arm`'s note: the tree SHAPE is what correctness depends on and it
-- is per-plate identical, so 20 plates exercises every branch 250 does. The COUNT
-- pins above run at the full 250.
local ORACLE_PLATES = 20

describe("O4/N1 oracle: the ADAPTER is told the same thing, every view, every step", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
		-- the sixth variant, and the one this task adds: with a stroked path on the
		-- surface `visible` takes the full walk while the other six still prune, so
		-- the mixed shape is the one an oracle most needs to see
		{ name = "withPath", plates = ORACLE_PLATES, withPath = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, visibility, hit rects, scroll regions and props survive`, function()
			for _, view in device_views.VIEWS do
				local a, b, c, d = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				-- `b` and `d` are DRIVEN on every step and `d` COMPARED on every step:
				-- an arm that skips a drive falls out of sync with the other three and
				-- the next comparison is about the drive it missed, not about the fix.
				local function step(what: string, compareB: boolean, drive: (any) -> ())
					drive(a)
					drive(b)
					drive(c)
					drive(d)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {what} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= d.snapshot() then
						error(`{label}: {what} diverged from an UNPRUNED commit`, 0)
					end
					if compareB and a.snapshot() ~= b.snapshot() then
						error(`{label}: {what} diverged from the memo-less solve`, 0)
					end
				end

				-- NON-VACUITY (task review round 1, minor 7). Four empty adapters
				-- compare equal four ways, so the oracle has to prove it is looking at
				-- a painted surface before any of its comparisons mean anything.
				if #a.snapshot() == 0 then
					error(`{label}: the fixture painted NOTHING — every comparison below is vacuous`, 0)
				end
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
				end
				if a.snapshot() ~= d.snapshot() then
					error(`{label}: diverged from an UNPRUNED commit at mount`, 0)
				end
				for round = 1, 3 do
					local dx, dy = round * 3, round * 2
					step(`tick {round}`, true, function(w)
						w.tick(dx, dy)
					end)
					step(`caster tick {round}`, false, function(w)
						w.tickWithCasts(dx, dy)
					end)
					step(`hp {round}`, false, function(w)
						w.hp(7, 0.1 * round)
					end)
					-- the structural arm: `scene.add` mints the key `add{i}`, and a
					-- ForEach treats a duplicate key as a HARD error, so it is keyed by
					-- `round` rather than a constant
					step(`add {round}`, false, function(w)
						w.add(round)
					end)
					-- ...and the tick right after it, because a structural commit does
					-- not prune and the NEXT one prunes against what it recorded
					step(`tick-after-add {round}`, false, function(w)
						w.tick(dx, dy)
					end)
					local added = #a.items
					step(`remove {round}`, false, function(w)
						w.remove(added)
					end)
				end
				a.dispose()
				b.dispose()
				c.dispose()
				d.dispose()
			end
		end)
	end
end)
