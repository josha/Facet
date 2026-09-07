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
	the COMMIT's set) and that is a separate task.

	...AND T5b (`tests/commit_dirt_classes.spec.luau`) IS THAT TASK, so four of the
	six pins below have MOVED WITH IT: `textScale`, `padding`, `textVerdicts` and
	`scrollRegions` name no arrange-class prop, so they ask `skip(node, true, true)`
	and are answered against a commit-side dirty set the seven pure placement props
	never enter — 253 -> 3 on a pure tick, 303 -> 103 on a caster one. `harvest` and
	`visible` still read `hidden` (arrange-classed) and keep the all-classes set, so
	the numbers this file pinned for THEM are unchanged, and so is `rect_pass`'s. ]]
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
--[[ ...AND A CASTER TICK IS 103 SINCE PLAN C's C6, not the 303 it was. The lane
	CONSUMES the 250 plate roots' placement entries before `refresh` classifies
	anything, so those roots never enter `nodeDirty` OR the commit's dirty set. What
	is left of a caster tick's dirt is the 50 `Cast` bars' MEASURE writes, which no
	lane may take, and it closes over each caster's own root: 3 + 50 * 2. It is now
	the SAME number as `ARRANGE_BLIND_CASTS` — the two sets have nothing left to
	differ on when the only dirt is measure-classed — and both are pinned separately
	anyway, because they are two derivations that happen to agree. ]]
local DIRTY_CASTS = 3 + CASTERS * 2 -- 103
--[[ the walks whose output cannot read a position AND that still carry the
	all-classes dirty set, so `|nodeDirty|` is still their floor. `rect_pass` is a
	third that stops at a moved subtree, but it stops for a DIFFERENT reason — it
	stops AT each translate root and emits the run, rather than pruning the root away
	— so it gets its own number on a mixed tick (see `RECTPASS_CASTS`).

	THE OTHER FOUR MOVED IN T5b and are pinned in `tests/commit_dirt_classes.spec`
	instead: they read no arrange-class prop, so a pure placement write does not put
	their nodes in the set they are answered against, and T4's `moveOnly` stamp on
	the translate ROOT (inert until then) prunes the plate roots themselves. ]]
local MOVE_BLIND = { "harvest", "visible" }
-- what those four read on the same drives, so this file's own table stays whole
local ARRANGE_BLIND = { "textScale", "padding", "textVerdicts", "scrollRegions" }
-- 3 = Screen + Canvas + the ForEach region; a caster tick adds its 50 roots and
-- their 50 dirty `Cast` boxes (a `width` write is measure-classed and is kept)
local ARRANGE_BLIND_TICK = 3
local ARRANGE_BLIND_CASTS = 3 + CASTERS * 2 -- 103
--[[ ...AND ON A CASTER TICK `rectPass` IS 403, NOT 303 — READ OFF THE RUN, and the
	plan's own table predicted 303. The two numbers differ because the two prunes are
	different questions, which is exactly what this spec is for.

	Under T4's settled derivation (b) a caster's plate root is NOT a translate root
	(`translatable` refuses it: its `Cast` child is dirty), and `Row` and `Hp` become
	translate roots UNDER it — `Row` with a two-node span, `Hp` with an EMPTY one
	(a childless root still records a run). A move-blind walk prunes `Row` and `Hp`
	away and visits 4 - 2 = 2 nodes per caster plus the 250 roots = 303.

	AND `rect_pass` NOW STOPS THERE TOO (Plan C, C1), which is why this number moved
	403 -> 303. It used to have to WRITE `Row`'s and `Hp`'s own rects, because both
	had moved in window space. Beneath a coordinate-space plate root neither moves at
	all — only the `Cast` bar RESIZED — so the run collapses to the same 2 nodes per
	caster the move-blind walks visit. It is now the same number as `DIRTY_CASTS`,
	and it is pinned separately anyway: they are two different derivations that
	happen to agree, and a future change that moves one must not silently move the
	other. ]]
--
-- ...AND IT IS 103 SINCE PLAN C's C6, for the reason `DIRTY_CASTS` gives: the 250
-- laned plate roots are not in the commit's set at all, so `rect_pass` has the same
-- 50 casters to walk that every other walk does. The three derivations agree on
-- this step; each is still pinned on its own.
local RECTPASS_CASTS = 3 + CASTERS * 2 -- 103

describe("O4/N1: seven walks stop at a moved subtree, hitRects does not", function()
	it("a pure tick opens NO COMMIT AT ALL, so there is nothing for a walk to prune", function()
		--[[ THE STRONGEST FORM OF THIS FILE'S CLAIM, and Plan C's C6 is what makes it
			available. A pure tick's every dirty entry is a placement prop on a
			coordinate-space host, so `render/translate_lane` consumes all of them and the
			solve — and therefore the commit, and therefore all eight walks — never runs.

			PINNED AS A `solves` DELTA, NEVER AS `lastCommitVisits == 0`: the whole
			`stats.last*` family reports the PREVIOUS solve by doctrine and the lane does
			not zero it, so a pin on the visit counts would pass for the wrong reason. A
			commit runs only inside `solveAndApply`. The staleness itself is asserted
			below, so a reader cannot mistake the numbers for this tick's. ]]
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats()
		s.tick(3, 2)
		local st = s.stats()
		expect(`solves={st.solves - before.solves} lane={st.lastLaneTranslates}`).toBe(`solves=0 lane={PLATES}`)
		expect(`visits={st.lastCommitVisits}`).toBe(`visits={before.lastCommitVisits}`)
		s.dispose()
	end)

	it("...and with the LANE OFF the same tick is the eight-walk prune this file pins", function()
		--[[ `hosts = false` is the pre-Plan-C world byte for byte, and it is where the
			PRUNE itself is still observable on a placement-only tick: no coordinate-space
			hosts means no lane, so the frame solves and commits and every walk answers
			its own dirty set. The prune is a property of the commit, not of the storage
			change, so this is the honest place to drive it. ]]
		local s = scene.new({ hosts = false })
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in MOVE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_TICK}`)
		end
		-- ...and the four T5b answers against the commit-side set instead
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={ARRANGE_BLIND_TICK}`)
		end
		-- every plate root IS a translate root on a pure tick, so `rect_pass` stops
		-- at exactly the same 253 nodes the all-classes walks prune down to
		expect(`rectPass={by.rectPass}`).toBe(`rectPass={DIRTY_TICK}`)
		--[[ ...AND `hitRects` JOINED THEM (Plan C, C1), which is the one clause of
			this file's header that stopped being true. It centres its target-floor
			expander on `r.x`/`r.y`, so it had to see every move — and under a
			coordinate space a moved plate's descendants DO NOT MOVE in their own
			space: their entry tables are the ones the last commit saw, `skip` matches
			on plain identity, and the walk stops at the dirty closure. A consequence
			of the storage change, not a new prune. ]]
		--[[ ...AND THEN IT LEFT THEM AGAIN (Plan D, D6b): this scene declares no input
			sink, so the walk is refused outright and never reaches the prune this
			clause described. The prune itself is unchanged and is pinned where it can
			still be seen — `tests/hit_rect_refusal.spec.luau`'s Button case keeps a
			sink on the surface and reads the walk running. ]]
		expect(`hitRects={by.hitRects}`).toBe("hitRects=0")
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
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={ARRANGE_BLIND_CASTS}`)
		end
		expect(`rectPass={by.rectPass}`).toBe(`rectPass={RECTPASS_CASTS}`)
		-- ...refused, for the reason the case above states (D6b): no sink, no walk
		expect(`hitRects={by.hitRects}`).toBe("hitRects=0")
		s.dispose()
	end)

	it("the writes are ONE PER PLATE (Plan C, C1 moved them; the prune did not)", function()
		--[[ THIS FILE'S OWN POINT IS THAT A PRUNE MUST NOT DROP A WRITE IT OWED, and
			that is still what this case says — the number it says it about moved.
			Under a flat tree the 1,500 writes were all real. With the plate root a
			coordinate space its subtree's rects do not change in their own space, so
			`rect_pass.applyOne` compares equal and sends 250. The differential case
			below is what proves the missing 1,250 are unnecessary rather than lost. ]]
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats().rectWrites
		s.tick(3, 2)
		expect(s.stats().rectWrites - before).toBe(PLATES)
		s.dispose()
	end)

	it("ONE UI.Path closes the visible prune, and only that one", function()
		--[[ AND SINCE PLAN C's C6 THIS DRIVE IS ALSO THE LANE'S OWN `visible` GATE. The
			Spark leaf sits under plate 3, so plate 3 is the one host
			`render/translate_lane` refuses — a stroked path's visibility is decided
			against its clip host's box in WINDOW space, which a host move changes and
			only this walk recomputes. 249 plates lane, plate 3 is the remainder, and the
			frame commits for it alone: `harvest` sees 4 nodes (Screen, Canvas, the region
			and that one plate) while `visible` walks EXACTLY the whole tree, `Spark`
			included, because the latch is whole-surface. A threshold could not tell 5
			from 1504, and the claim is that the latch opens the WHOLE walk. ]]
		local s = scene.new({ withPath = true })
		s.tick(3, 2)
		s.tick(3, 2)
		local st = s.stats()
		local by = st.lastCommitVisitsByWalk
		expect(`lane={st.lastLaneTranslates}`).toBe(`lane={PLATES - 1}`)
		expect(`visible={by.visible}`).toBe(`visible={MOUNTED + 1}`)
		expect(`harvest={by.harvest}`).toBe("harvest=4")
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
		-- ...and it IS a real per-plate arrange, not a solve that skipped everything.
		-- `translated` is 0 since Plan C's C1: a coordinate-space root records an
		-- EMPTY run, so its 1,250 descendants are never entered at all — which is
		-- exactly why the delta above is zero without a single `rectsEqual` compare.
		expect(`arranged={st.lastArranged} translated={st.lastTranslated}`).toBe(`arranged={PLATES + 2} translated=0`)
		-- ...and the prune is still on: a zero-delta run is not a special case for it
		local by = st.lastCommitVisitsByWalk
		for _, name in MOVE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_TICK}`)
		end
		-- ...and the T5b four prune the 250 zero-delta roots away too: a run whose
		-- delta is zero is not a special case for either set
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={ARRANGE_BLIND_TICK}`)
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
		-- THE RECYCLE-KEY WORN-SET DEP (T8 R3, re-review Minor 3). `CommitCtx`
		-- declares it and `commit_walks.new` binds it unguarded, so a hand-built
		-- record that omits it is a latent nil call the day a fixture here grows
		-- a leaf Button with a compact form. A no-op recorder: nothing in this
		-- file asserts on the worn set, only that the ladder can run at all.
		noteWorn = function() end,
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
