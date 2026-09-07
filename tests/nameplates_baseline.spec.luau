--!strict
--[[ THE BEFORE NUMBERS, ON DISK (wicked-fast T2). Every later demonstrator in
	this round reads a "currently N" from here rather than from a memory of a
	profiling run, so an improvement cannot be a moved goalpost. The arena's own
	numbers (1,489 arranged / 1,241 measured / 1,488 writes on a 1,465-layout-node
	tree) are the WORKLOAD's; these are this FIXTURE's, and they are not the same
	tree — `FacetBench/docs/profiling/2026-09-02-nameplates-attribution.md` is the
	workload's record.

	THESE PINS MOVE, AND THE TASK THAT MOVES ONE UPDATES IT WITH THE MEASUREMENT
	THAT LICENSED IT — never by loosening the assertion (ENGINEERING.md: "pin
	every human-locked baseline and fail on drift"). The schedule is known in
	advance, so an unexpected move is a finding:

	  | pin | moved by | to |
	  |---|---|---|
	  | `lastMeasured` on a STEADY tick | T3 ✅ `157ed3c9` | 500 = PLATES x 2 (pure) / 652 (casters), both read off the run — see `MEASURED_STEADY` |
	  | `lastMeasured` on a STEADY tick | T4 ✅ `14c3459d` | **0 (pure)** / **252 (casters)** — the translate arm stops re-entering the subtree, so the 200 quiet plates cost nothing at all and only the 50 refused caster roots (`CASTERS x 5 + 2`) are left. READ OFF THE RUN |
	  | `lastMeasured` on the COLD tick | T4 ✅ `14c3459d` | **1502** (was 2002). NOT A SCHEDULED MOVE AND THEREFORE A FINDING, in the direction the round wants: the cold tick's 2002 was 1502 distinct nodes plus the 500 `Hp`/`Cast` boxes touched a SECOND time by the plate's vstack ARRANGE descent. The translate arm removes that descent on the cold tick too — the plates moved and their subtrees were clean even on the first tick after mount — so the second touch is gone and the remaining 1502 is every layout node measured exactly once |
	  | `lastNodeBuilds`           | T3 ✅ `157ed3c9` | **THE PREDICTION WAS WRONG AND IS CORRECTED RATHER THAN LEFT STANDING: it did NOT move.** 252 pure / 302 casters, before and after. T3 rewrote the dirty closure into two sets, but `nodeDirty` — which is what `layout_node.build` counts builds against — is a THIRD set (`renderer.luau`'s `markNodeDirty`, every class, accumulated across refreshes), and the split never touched it. The counter T3 does move is `lastMeasured` |
	  | `lastArranged`             | T4 ✅ `14c3459d` | 252 (pure) / **402** (casters) + `lastTranslated` 1250 / 1100. The two competing derivations in T4 Step 1 were settled BY THE RUN and it is **(b)**: `translatable` does not require the root to be clean, so a caster's plate root (dirty child `Cast`) takes the ordinary arrange and its own `Row` and `Hp` become translate ROOTS under it — 4 arranged + 2 translated per caster. `tests/translate_arm.spec` carries the arithmetic |
	  | `lastRectInserts`          | T4 ✅ `14c3459d` | arranged + translated = 1,502, unchanged in TOTAL and re-split |
	  | every per-walk visit count | T5 ✅ `4b0f5e19` | 253 (pure) / 303 (casters) for the six MOVE-BLIND walks; `rectPass` 253 (pure) / **403** (casters, NOT the 303 the plan predicted — see `tests/commit_translate.spec`); `hitRects` stays 1,503 |
	  | the four arrange-blind walks | T5b ✅ `da7fc3a9` | **3** on a pure tick (was 253) / **103** on a caster tick (was 303). `textScale`, `padding`, `textVerdicts` and `scrollRegions` name no arrange-class prop, so they are answered against a COMMIT-side dirty set that the seven pure placement props never enter, and T4's `moveOnly` stamp on the translate ROOT — inert until this — prunes all 250 plate roots. `harvest`/`visible` keep the all-classes set (they read `hidden`) and so keep 253/303; `hitRects` and `rectPass` are untouched |
	  | ALL OF THEM               | T6 ✅ `262117dc` | **NOTHING MOVED, and that is a fact rather than an oversight.** T6 gave the anchor arrange branch a third arm — a child with nothing MEASURE-classed dirty inside it and the identical offer takes its w/h from its own previous rect instead of a `measure` call — and on this fixture it fires for all 250 plates on a pure tick and for 200 of them on a caster tick. NONE of the counters above can see it: `lastMeasured` is incremented inside `measureUncached`, and every call the arm removes was a memo HIT that returned before reaching it. The counters that move are the new `work.anchorReused` / `work.anchorOffered` pair, pinned in `tests/anchor_arrange.spec.luau`, and they are read off `solver.solve`'s result rather than off `stats()` because this task adds nothing to the controller's public surface. **The task brief predicted `lastMeasured` would show the 250 and it could not** — recorded here because a demonstrator built on it would have been green before the change and green after |
	  | EVERY PURE-TICK PIN        | T5 ✅ (Plan C, C6) | **THE PURE TICK STOPPED SOLVING.** `render/translate_lane` consumes all 250 placement entries, so `refresh` hands the solve an empty remainder: `solves` delta **0**, `lastLaneTranslates` **250**, 250 rect and 250 engine writes, and the whole `stats.last*` family reports the PREVIOUS solve unchanged. Every solve-side pin in this file therefore moved to the CASTER tick, which still carries MEASURE dirt no lane may take. Three of them are SMALLER than the caster column this file used to carry — 302 arranged → **102**, 302 builds → **102**, 303 visits → **103** — because the laned plate roots never reach the classifier and so never enter `nodeDirty` or the commit's dirty set. `lastMeasured` on a caster tick did NOT move (252): the plates it counts were already the casters' own |
	  | `lastMeasured`, caster tick | C2 ✅ (Plan C, T6) | **252 → 152 steady, 1602 → 1552 cold.** `measure`'s node-resident serve answers a clean node from numbers on the node itself, and under a caster only the `Cast` box is measure-dirty: both `Hp` touches are served on a steady tick (−100) and its SECOND touch on the cold one (−50, the first being genuinely cold). The pure-tick column is unmoved because a pure tick does not solve at all (C6). The new counters are `work.measureCalls`/`measureServed` → `stats.lastMeasureCalls`/`lastMeasureServed`, pinned in `tests/measure_serve.spec.luau` on a fixture whose shape a stack — not an anchor — can show |
	  | the census, `rectWrites`   | never | 1,503 mounted / 1,502 layout / 1,500 writes |

	253 is Screen + Canvas + the ForEach region + one root per plate. The 250
	`…/[pN]` strings `markNodeDirty` also writes have NO mounted node behind them
	(`mount.luau:357` uses `rowPath` as a parent path), and `skip` is only ever
	asked about real nodes — so they are dirty PATHS and never commit VISITS.

	THE PURE-TICK CONSTANTS ARE HISTORY NOW, NOT DECLARATIONS. `MEASURED_STEADY` (0),
	`MEASURED_COLD` (1502), `ARRANGED_STEADY` (252), `SKIPPED_STEADY` (1250),
	`VISITS_PRUNED` (253) and `VISITS_ARRANGE_BLIND` (3) were all read on a PURE tick,
	and since Plan C's C6 a pure tick never reaches the solver — so they were deleted
	rather than left standing as locals nothing reads. Their values are recorded here
	and in the table above; the live pins are the `*_CASTER` family below. The
	paragraphs that follow are their derivations, kept because they are the record of
	how each was measured.

	`MEASURED_STEADY` and `MEASURED_COLD` (wicked-fast T2, Fix round 1 — the
	controller's ruling): the "currently N" a later demonstrator quotes must be
	the STEADY tick, not the scene's cold first one, so `MEASURED_STEADY` is what
	the second case below pins and `MEASURED_COLD` is its own small case, not the
	round's baseline.

	`MEASURED_STEADY` READ OFF THE RUN, AND MOVED BY T3 (`157ed3c9`) FROM 1252 TO
	500 — and the mechanism T2 recorded as NOT INSTRUMENTED now is. T2 pinned
	`1252 = LAYOUT - PLATES` as an arithmetic identity it had not traced; T3
	bucketed `ctx.measured` by `memoPlan` verdict, node kind, path leaf and dirty-set
	membership (temporary counters, reverted before commit) and the 1252 was 1000
	PLAN_SKIP touches on the 500 `Hp`/`Cast` boxes (each touched twice — the plate's
	measure pass AND its vstack arrange pass) plus 252 slate refusals (the 250 moved
	plate roots + Canvas + Screen, every one of them named by `dirtyContains`). The
	`LAYOUT - PLATES` identity was a coincidence of those two terms, not a mechanism.
	T3's measure/arrange split lets the 252 arrange-only nodes keep their slates, so
	the plate's measure pass no longer descends and only its ARRANGE pass touches the
	two PLAN_SKIP leaves: 500 = PLATES x 2. `tests/measure_split.spec.luau` carries
	the full bucket tables for both ticks.

	`MEASURED_STEADY_CASTERS` IS NOW A SEPARATE NUMBER (652), which is the point of
	T3: before the split a pure and a caster tick read the identical 1252, because
	the steady measure touched every `Hp`/`Cast` box regardless of caster activity.
	After it, only the 50 caster plate roots are refused, and 652 =
	(PLATES - CASTERS) x 2 + CASTERS x 5 + 2. `lastNodeBuilds` reads 252 on a steady
	pure tick and 302 on a steady caster tick BEFORE AND AFTER T3 — READ OFF THE RUN,
	not derived — the 250 moved plates + Canvas + Screen, plus the 50 caster boxes
	when a caster tick adds them.

	...AND T4 (`14c3459d`) TOOK BOTH OF THOSE MEASURE NUMBERS APART AGAIN, because
	the arm it adds removes the ARRANGE descent that produced every one of the
	PLAN_SKIP touches. A moved-not-resized plate whose children are all clean is
	re-based by one delta and never entered, so its two `Hp`/`Cast` leaves are not
	touched at all: the pure tick's 500 is 0, and the caster tick's 652 loses its
	`(PLATES - CASTERS) * 2` term and keeps only the 50 casters' own 5 + the 2
	ancestors = 252. The COLD tick moved with them (2002 -> 1502) and that one was
	NOT on the schedule — see the table above; it is the same mechanism, and the
	direction is the round's. What did NOT move: `lastNodeBuilds` (252/302 — builds
	are counted against `nodeDirty`, a third set neither T3 nor T4 touches),
	`rectWrites` (1500 a tick — the writes are real in a flat engine tree and the
	arm makes the same ones), `lastRectInserts` (1502, re-split into 252 arranged +
	1250 translated) and every per-walk commit visit (T5's business). ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

local PLATES = scene.PLATES
-- + the Canvas anchor + the Screen root. The ForEach region is NOT a layout node:
-- `layout_node.luau:1263-1275` splices its children into the enclosing flow.
local LAYOUT = PLATES * scene.NODES_PER_PLATE + 2 -- 1502
-- ...+ the ForEach REGION, and nothing else. There is no per-item wrapper node
-- (`mount.luau:357` uses `rowPath` as a parent path; the row's own root is mounted
-- at `…/[pN]/Plate` by `:595-596`), so this is LAYOUT + 1, not LAYOUT + PLATES + 1.
local MOUNTED = LAYOUT + 1 -- 1503
local CASTERS = PLATES // scene.CASTER_EVERY -- 50
-- READ OFF THE RUN. T3 (`157ed3c9`) took it from `LAYOUT - PLATES` = 1252 to
-- `PLATES * 2` = 500 (the plate's ARRANGE pass touching its two PLAN_SKIP leaves);
-- T4 (`14c3459d`) takes it to ZERO, because the translate arm never enters the
-- plate at all and the arrange descent that made those touches is gone. There is
-- nothing left to measure on a steady pure tick: every node's slate is adopted and
-- hit, and no PLAN_SKIP leaf is touched. See `tests/measure_split.spec.luau` and
-- `tests/translate_arm.spec.luau` for the buckets and the arm.
-- ...and a caster tick keeps ONLY its caster term (T4, `14c3459d`, was 652): the
-- `(PLATES - CASTERS) * 2` half was the 200 quiet plates' arrange descent and the
-- translate arm removes it, leaving each of the 50 casters at 5 (its refused root,
-- plus `Hp`/`Cast` on both the measure and the arrange descent) and the two
-- ancestors every caster's measure dirt closes over.
-- ...AND PLAN C's C2 TOOK THE PER-CASTER TERM FROM 5 TO 3 (252 -> 152, read off the
-- run): `Hp` is measure-CLEAN under a caster — only the cast bar's width moved — so
-- `measure`'s node-resident serve answers both of its touches from the node's own
-- last answer and neither reaches `measureUncached`. What is left per caster is the
-- refused root once and `Cast` twice. `tests/measure_split.spec.luau` carries the
-- bucket table and `tests/measure_serve.spec.luau` the serve's channel table.
local MEASURED_STEADY_CASTERS = CASTERS * 3 + 2 -- 152
-- READ OFF THE RUN, instrumented at T2 (`solver.measureUncached`, temporary
-- counter, reverted before commit) as 1502 distinct nodes measured once PLUS the
-- 500 Hp/Cast boxes measured a SECOND time by the vstack arrange branch. T4
-- (`14c3459d`) removes that second touch here too — the cold tick's plates have
-- already moved and their subtrees are clean, so they translate — and what is left
-- is exactly the 1502 distinct measures. See "the first tick after mount pays a
-- one-time cold solve".
-- the O3 split of `lastArranged` (T4, `14c3459d`), read off the run: the Screen,
-- the Canvas and the 250 plate ROOTS take the ordinary entry write and each
-- re-bases its 5 descendants.
--[[ MOVED TO ZERO BY PLAN C's C1, and the mechanism is worth stating because the
	number looks like a lost measurement. A plate root carries a REACTIVE
	`offsetX`/`offsetY` and has children, so it is now a COORDINATE SPACE: its
	subtree's rects are stored relative to it, a move of the root re-bases nothing,
	and `arrange` records an EMPTY translate run and returns before its own body.
	The 1,250 descendants are therefore neither arranged NOR translated — they are
	not entered at all, which `lastSolveSkipped` says directly, and the three
	outcomes still account for every layout node. `tests/translate_arm.spec.luau`
	keeps the arm's own numbers on a `hosts = false` mount. ]]
local TRANSLATED_STEADY = 0
-- the COMMIT's own dirty closure on a steady pure tick, and T5's (`4b0f5e19`) pin for
-- seven of the eight walks: Screen + Canvas + the ForEach region + one root per
-- plate. `tests/commit_translate.spec.luau` carries the derivation, the caster
-- column (303, and `rectPass` 403) and the four-arm adapter oracle behind it.
-- ...and T5b's (`da7fc3a9`) floor for the four walks that read no arrange-class
-- prop at all: Screen + Canvas + the ForEach region, every plate root pruned by
-- T4's translate-root stamp. `tests/commit_dirt_classes.spec.luau` carries the
-- per-prop audit, the caster column (103) and the four-arm oracle.
--[[ ── THE CASTER-TICK FAMILY (Plan C, C6 — the translate lane) ────────────────
	A PURE TICK NO LONGER SOLVES AT ALL, so the numbers above have no tick to be
	read on: `stats.last*` is the PREVIOUS solve's by doctrine and the lane does not
	zero it. Every solve-side pin in this file therefore moved to the CASTER tick,
	which is the cheapest step this fixture has that still reaches the solver — the
	50 `Cast` bars carry MEASURE dirt, which no lane may take.

	ALL FIVE ARE READ OFF THE RUN, and three of them are smaller than the caster
	column this file used to carry (302 arranged / 302 builds / 303 visits): the
	lane CONSUMES the 250 plate roots' placement entries, so they never reach the
	classifier, never enter `nodeDirty` and never enter the commit's dirty set. What
	is left of a caster tick is the 50 casters and the two ancestors above them.
	`MEASURED_STEADY_CASTERS` did NOT move — the plates it counts were already the
	casters' own. ]]
local ARRANGED_CASTER = CASTERS * 2 + 2 -- 102: each caster's root and its Cast box, plus Canvas + Screen
local BUILDS_CASTER = CASTERS * 2 + 2 -- 102, the same set
local SKIPPED_CASTER = LAYOUT - ARRANGED_CASTER -- 1400
local VISITS_CASTER = CASTERS * 2 + 3 -- 103, on all EIGHT walks
--[[ ...and the cold caster tick, the one-time measure-store cost this fixture pays
	on its first solve after mount (the lane defers it: `initialRender`'s own fill
	pass clears the store and a laned tick never re-fills it).

	PLAN C's C2 TOOK IT FROM 1602 TO 1552, and the 50 are exactly identifiable. 1602
	was 1502 distinct nodes measured once PLUS the 100 second touches of the 50
	casters' `Hp` and `Cast` boxes (the refused plate root's measure descent, then
	its arrange descent). The FIRST touch of each node is still cold — nothing has
	recorded a tuple for it yet — but the SECOND touch of `Hp` is now served, because
	`Hp` is measure-clean under a caster and the measure descent recorded its answer
	moments earlier IN THIS SOLVE. `Cast` is measure-dirty and refuses. So the serve
	removes 50 and only 50, which is also the cleanest demonstration in this file
	that the serve has an INTRA-solve half as well as a cross-solve one. ]]
--[[ RE-RECORDED 2026-09-06 (Plan D, D5): 1,552 -> 152, i.e. THE COLD COLUMN IS GONE
	and equals the steady one. `initialRender`'s fill pass clears the measure STORE, so
	the first solve after mount has no cross-solve slate — but D5 makes the mount's own
	full solve record the node-resident slots, and those are what this solve was
	re-measuring 1,400 nodes to rediscover. The case below is kept and its name with it:
	the number it pins is now an EQUALITY between the two columns, which is a stronger
	statement of the same claim (the lane defers a cost that no longer exists) and goes
	red the moment either mechanism regresses. ]]
local MEASURED_COLD_CASTERS = 152 -- was 1602 before C2, 1552 before D5

describe("nameplates baseline — the numbers the wicked-fast round starts from", function()
	it("the fixture is the tree the plan says it is", function()
		local s = scene.new()
		local c = s.census()
		expect(`plates={c.plates} casters={c.casters} mounted={c.mounted} layout={c.layout}`).toBe(
			`plates={PLATES} casters={CASTERS} mounted={MOUNTED} layout={LAYOUT}`
		)
		s.dispose()
	end)

	it("a pure tick LANES: no solve at all, one rect and one engine write per plate", function()
		--[[ THE HEADLINE OF PLAN C's C6. Every dirty entry on this tick is a placement
			prop on a coordinate-space host, so `render/translate_lane` consumes all 250,
			re-places each with the solver's own `placement.anchorPlace`, writes the
			solver's entry in place and calls `setRect` once — and the remainder handed to
			the rest of `refresh` is empty, so no solve runs and no commit opens.

			MEASURED AS DELTAS, AND DELIBERATELY NOT AS `stats.last*`. The whole `last*`
			family reports the PREVIOUS solve and the lane does not zero it, so a pin on
			`lastCommitVisits == 0` would pass for the wrong reason. A commit runs only
			inside `solveAndApply`, so a `solves` delta of 0 IS "no commit ran" — and the
			second half of this case asserts the staleness directly, because a reader who
			does not know it is the doctrine will misread every number in this file. ]]
		local s = scene.new()
		s.tick(3, 2) -- warm: the first tick after mount is laned too, see the cold case
		local before = s.stats()
		local ew = s.adapter.engineWrites()
		s.tick(3, 2)
		local st = s.stats()
		expect(
			`solves={st.solves - before.solves} lane={st.lastLaneTranslates}`
				.. ` rectWrites={st.rectWrites - before.rectWrites}`
				.. ` engineWrites={s.adapter.engineWrites() - ew}`
		).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		-- ...and every solve counter is EXACTLY what it was before the tick
		expect(
			`arranged={st.lastArranged} measured={st.lastMeasured} builds={st.lastNodeBuilds}`
				.. ` visits={st.lastCommitVisits}`
		).toBe(
			`arranged={before.lastArranged} measured={before.lastMeasured} builds={before.lastNodeBuilds}`
				.. ` visits={before.lastCommitVisits}`
		)
		s.dispose()
	end)

	it("...and the CASTER tick is the solve: the arrange halves, the walks, the cumulative writes", function()
		--[[ THE SOLVE-SIDE TABLE THIS FILE HAS ALWAYS CARRIED, moved to the step that
			still reaches the solver. The 50 `Cast` bars carry MEASURE dirt, which no lane
			may take, so a caster tick lanes the 250 movers and solves the 50 — and the
			solve it takes is much smaller than the caster tick this file used to pin,
			because the laned plate roots never reach the classifier at all. ]]
		local s = scene.new()
		s.tickWithCasts(3, 2) -- warm: the first solve after mount is the cold one
		s.tickWithCasts(3, 2)
		local st = s.stats()
		expect(st.lastMeasured).toBe(MEASURED_STEADY_CASTERS) -- 252, unmoved by the lane
		expect(st.lastArranged).toBe(ARRANGED_CASTER)
		expect(st.lastTranslated).toBe(TRANSLATED_STEADY)
		expect(st.lastSolveSkipped).toBe(SKIPPED_CASTER)
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(LAYOUT)
		-- ...and a rect insert per node the solve actually entered, which is the arrange
		-- half alone (Plan C, C1): a subtree stored in its host's space keeps its entries
		expect(st.lastRectInserts).toBe(ARRANGED_CASTER)
		expect(st.lastNodeBuilds).toBe(BUILDS_CASTER)
		--[[ CUMULATIVE since `scene.new()`: `rectWrites` is never reset per commit, only
			incremented on an actual value change. `initialRender`'s own solve writes
			every rect once (1502, everything is new); each caster tick since writes the
			250 laned plate ROOTS plus the 50 resized `Cast` bars. 1502 + 300 + 300. ]]
		expect(st.rectWrites).toBe(LAYOUT + 2 * (PLATES + CASTERS))
		-- the EXACT aggregate: the sum of the eight per-walk counts below, and the only
		-- exact pin of the aggregate in this repo — the old `>= MOUNTED * 7` bound could
		-- never fail (a walk silently publishing twice would sail past it).
		expect(st.lastCommitVisits).toBe(VISITS_CASTER * 8)
		--[[ ...AND ALL EIGHT WALKS AGREE NOW, which they did not before the lane. T5b
			split them into a pruned six and an arrange-blind four because the arrange-
			blind set could ignore a plate root that only MOVED; a laned frame never
			reaches the commit at all, so on a caster tick the only dirt any walk sees is
			the casters' own MEASURE dirt — which every walk reads. The split is still
			real and `tests/commit_dirt_classes.spec.luau` is where it is driven; it
			simply has nothing to separate on this step. ]]
		local byWalk = st.lastCommitVisitsByWalk
		for _, name in
			{ "harvest", "visible", "rectPass", "hitRects", "textScale", "padding", "textVerdicts", "scrollRegions" }
		do
			expect(`{name}={byWalk[name]}`).toBe(`{name}={VISITS_CASTER}`)
		end
		s.dispose()
	end)

	it("the first SOLVE after mount pays a one-time cold measure, and the lane defers it", function()
		--[[ `initialRender`'s own fill pass CLEARS the measure store, so this fixture's
			first solve after mount always re-measures the whole tree. What Plan C's C6
			changed is WHICH refresh pays it: a pure tick lanes and never solves, so the
			cold cost is deferred to the first step that carries measure dirt. Driven on
			the caster tick for that reason, and both columns are read off the run —
			1552 against a steady 152 since C2, whose serve takes exactly the 50 `Hp`
			second touches out of the cold column and the 100 `Hp` touches out of the
			steady one. ]]
		local s = scene.new()
		s.tickWithCasts(3, 2)
		local cold = s.stats()
		s.tickWithCasts(3, 2)
		local steady = s.stats()
		expect(`cold={cold.lastMeasured} steady={steady.lastMeasured}`).toBe(
			`cold={MEASURED_COLD_CASTERS} steady={MEASURED_STEADY_CASTERS}`
		)
		-- ...and what makes it cold is the measure store, not the arrange or build half:
		-- both are identical on the two solves
		expect(`arranged={cold.lastArranged} builds={cold.lastNodeBuilds}`).toBe(
			`arranged={ARRANGED_CASTER} builds={BUILDS_CASTER}`
		)
		s.dispose()
	end)

	it("...and the mixed-dirt step exists and bites: the pure tick lanes, the caster tick solves", function()
		--[[ THE TWO STEPS THIS FIXTURE OFFERS, and the difference between them is now
			categorical rather than a counter. A pure tick's dirt is placement on
			coordinate-space hosts and NOTHING else, so the lane takes all 250 and the
			frame never solves. A caster tick adds a `{ type = "fixed", px = cast * 100 }`
			write on 50 `Cast` bars — MEASURE-classed, which no lane may take — so those
			50 are handed to the solve as the remainder and the frame solves once.

			BEFORE T3 THIS COMPARISON DID NOT BITE at all: the steady measure touched
			every Hp/Cast box regardless of caster activity, so a pure and a caster tick
			read the identical `lastMeasured` and only `lastNodeBuilds` moved. T3's split
			separated them; C6 separates them again, at the level of whether a solve
			happened. ]]
		local s = scene.new()
		s.tickWithCasts(3, 2) -- warm past the cold measure
		s.tickWithCasts(3, 2)
		local before = s.stats()
		s.tick(3, 2)
		local pure = s.stats()
		expect(`solves={pure.solves - before.solves} lane={pure.lastLaneTranslates}`).toBe(`solves=0 lane={PLATES}`)
		s.tickWithCasts(3, 2)
		local mixed = s.stats()
		expect(`solves={mixed.solves - pure.solves} lane={mixed.lastLaneTranslates}`).toBe(`solves=1 lane={PLATES}`)
		-- ...and the solve it took is the casters and their two ancestors, in every
		-- counter the solve publishes
		expect(
			`builds={mixed.lastNodeBuilds} arranged={mixed.lastArranged} measured={mixed.lastMeasured}`
				.. ` translated={mixed.lastTranslated}`
		).toBe(
			`builds={BUILDS_CASTER} arranged={ARRANGED_CASTER} measured={MEASURED_STEADY_CASTERS}`
				.. ` translated={TRANSLATED_STEADY}`
		)
		expect(mixed.lastArranged + mixed.lastTranslated + mixed.lastSolveSkipped).toBe(LAYOUT)
		s.dispose()
	end)

	it("add/remove keep items and rows in sync (a census that lags is not a census)", function()
		local s = scene.new()
		-- I-2 (Fix round 2): `add`/`remove` used to mutate a clone of `rows`
		-- but never update `items` — exactly the trap the fixture's own
		-- `Census` type doc warns about above ("They had the same name in an
		-- earlier draft of this fixture, which is exactly how a census stops
		-- being a census"). `census().plates` reads `#items`, so an add that
		-- did not update `items` reported the PRE-add count forever, and
		-- `tick`/`tickWithCasts` (which also iterate `items`, not `rows`)
		-- never touched the new plate's signals at all — it stood still while
		-- every other plate moved.
		s.add(251)
		-- the public `s.items` snapshot is re-pointed too (re-review note):
		-- a reader that iterates it after an add sees the new plate
		expect(#s.items).toBe(PLATES + 1)
		local afterAdd = s.census()
		expect(`plates={afterAdd.plates} mounted={afterAdd.mounted} layout={afterAdd.layout}`).toBe(
			`plates={PLATES + 1} mounted={MOUNTED + scene.NODES_PER_PLATE} layout={LAYOUT + scene.NODES_PER_PLATE}`
		)
		--[[ A CASTER TICK, NOT A PURE ONE, SINCE PLAN C's C6: a pure tick lanes and
			publishes no solve counters at all, so the three outcomes below would be read
			off whatever solve ran last. The claim is unchanged — the three still account
			for every layout node, and the tree really did grow by one plate's worth. ]]
		s.tickWithCasts(3, 2)
		local afterTick = s.stats()
		expect(afterTick.lastArranged).toBe(ARRANGED_CASTER)
		expect(afterTick.lastTranslated).toBe(TRANSLATED_STEADY) -- 0 since Plan C, C1
		expect(afterTick.lastSolveSkipped).toBe(SKIPPED_CASTER + scene.NODES_PER_PLATE)
		expect(afterTick.lastArranged + afterTick.lastTranslated + afterTick.lastSolveSkipped).toBe(
			LAYOUT + scene.NODES_PER_PLATE
		)
		s.remove(251)
		expect(#s.items).toBe(PLATES)
		local afterRemove = s.census()
		expect(`plates={afterRemove.plates} mounted={afterRemove.mounted} layout={afterRemove.layout}`).toBe(
			`plates={PLATES} mounted={MOUNTED} layout={LAYOUT}`
		)
		s.dispose()
	end)

	it("overflow + withPath change the tree shape the option plumbing promises", function()
		-- `fractional` is checked but NOT included here (M-7): with
		-- `fractional = true` alone, census reads byte-identical to the
		-- defaults (`mounted`/`layout`/`plates` unchanged) — it changes
		-- VALUES (offsetX/offsetY become `{ scale, offset }` tables instead of
		-- plain signals) and never the tree shape, so it has nothing for a
		-- shape smoke test to prove.
		local s = scene.new({ withPath = true, overflow = true })
		local c = s.census()
		-- READ OFF THE RUN: `withPath` adds exactly one node — the `UI.Path` Spark
		-- leaf, which since Plan C's C6 sits UNDER PLATE 3 rather than beside the
		-- ForEach, because both latches that want it want it inside a coordinate-space
		-- host. `overflow` only widens plate p1's own box (no node added or removed),
		-- so it moves neither count on its own.
		expect(`plates={c.plates} casters={c.casters} mounted={c.mounted} layout={c.layout}`).toBe(
			`plates={PLATES} casters={CASTERS} mounted={MOUNTED + 1} layout={LAYOUT + 1}`
		)
		s.tick(3, 2) -- warm-up
		local before = s.stats()
		s.tick(3, 2)
		--[[ AND THE SPARK'S HOST IS THE ONE PLATE THAT CANNOT LANE (Plan C, C6). A
			stroked path's visibility is decided against its CLIP host's box in WINDOW
			space, which a host move changes and only the `visible` commit walk
			recomputes — so `render/translate_lane` refuses a host with a `UI.Path`
			beneath it and hands that one plate to the solve. 249 lane; the frame solves
			once, for plate 3 alone; and 250 rects are still written, 249 by the lane and
			one by the commit. READ OFF THE RUN. ]]
		local st = s.stats()
		expect(
			`solves={st.solves - before.solves} lane={st.lastLaneTranslates}`
				.. ` rectWrites={st.rectWrites - before.rectWrites}`
		).toBe(`solves=1 lane={PLATES - 1} rectWrites={PLATES}`)
		-- ...and the solve that one plate took is three nodes: its root, plus Canvas and
		-- Screen above it. The Spark leaf itself is neither arranged nor translated — it
		-- lands on the rect it already had and the SKIP catches it — and the three
		-- outcomes account for every node of the +1 tree.
		expect(st.lastArranged).toBe(3)
		expect(st.lastTranslated).toBe(TRANSLATED_STEADY) -- 0 since Plan C, C1
		expect(st.lastSolveSkipped).toBe(LAYOUT + 1 - 3)
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(LAYOUT + 1)
		s.dispose()
	end)
end)
