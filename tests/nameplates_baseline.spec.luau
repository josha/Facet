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
	  | `lastMeasured` on a tick   | T3 | 500 = PLATES x 2 (pure) / read off the run (casters) |
	  | `lastMeasured` on a tick   | T4 | 0 (pure) — the translate arm stops re-entering the subtree |
	  | `lastArranged`             | T4 | 252 (pure) / 302 (casters, see T4 Step 1's competing derivation) |
	  | `lastRectInserts`          | T4 | arranged + translated = 1,502 |
	  | every per-walk visit count | T5 | 253 (pure) / 303 (casters); hitRects stays 1,503 |
	  | the four hidden-blind walks | T5b (if built) | 3 on a pure tick |
	  | the census, `rectWrites`   | never | 1,503 mounted / 1,502 layout / 1,500 writes |

	253 is Screen + Canvas + the ForEach region + one root per plate. The 250
	`…/[pN]` strings `markNodeDirty` also writes have NO mounted node behind them
	(`mount.luau:357` uses `rowPath` as a parent path), and `skip` is only ever
	asked about real nodes — so they are dirty PATHS and never commit VISITS.

	`MEASURED_TICK` (wicked-fast T2, Step 6): READ OFF THE RUN, not derived on
	paper — `lune run tests/run_one nameplates_baseline` first reported 2002 where
	this comment guessed 502, and 2002 is what is pinned. Instrumented directly
	(`solver.measureUncached`, reverted before this commit): of the 2002 measure
	calls this first tick makes, exactly 1502 are DISTINCT nodes — every layout
	node, once, which is the "full re-measure" the case's own name promises — and
	the other 500 land on the very set the fixture header already names: the 500
	`Hp`/`Cast` boxes (`kind=box`, PLATES * 2), each measured TWICE in the same
	solve. The first hit is the ordinary top-down measure every node gets; the
	second is exactly the mechanism the header already describes for these two
	leaves — a moved plate root fails the arrange skip and the vstack arrange
	branch (`solver.luau:3290-3340`) re-measures each non-hug child on top of
	that. `MEASURED_TICK = LAYOUT + PLATES * 2 = 2002`. T3 removes the double
	count (500 -> 0 extra); T4 removes the base pass too. ]]
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
-- READ OFF THE RUN (Step 6): LAYOUT nodes measured once each, plus the 500
-- Hp/Cast boxes measured a second time by the vstack arrange branch. See the
-- header note above for the instrumented breakdown.
local MEASURED_TICK = LAYOUT + PLATES * 2 -- 2002

describe("nameplates baseline — the numbers the wicked-fast round starts from", function()
	it("the fixture is the tree the plan says it is", function()
		local s = scene.new()
		local c = s.census()
		expect(`plates={c.plates} casters={c.casters} mounted={c.mounted} layout={c.layout}`).toBe(
			`plates={PLATES} casters={CASTERS} mounted={MOUNTED} layout={LAYOUT}`
		)
		s.dispose()
	end)

	it("a pure tick: a full arrange, a full re-measure, eight whole-tree walks", function()
		local s = scene.new()
		s.tick(3, 2)
		local st = s.stats()
		-- MEASURED_TICK is the number Step 6 of this task READS OFF THE RUN and
		-- writes in as a literal, with the plan-verdict breakdown that explains it
		-- in a comment beside it. It is the "currently N" every later demonstrator
		-- quotes, so it is on disk rather than in a memory of a profiling session.
		expect(st.lastMeasured).toBe(MEASURED_TICK)
		expect(st.lastArranged).toBe(LAYOUT)
		expect(st.lastRectInserts).toBe(LAYOUT)
		expect(st.rectWrites > 0 and st.lastCommitVisits >= MOUNTED * 7).toBe(true)
		-- the per-walk breakdown this task exists to publish
		local byWalk = st.lastCommitVisitsByWalk
		for _, name in
			{ "harvest", "textScale", "padding", "textVerdicts", "visible", "hitRects", "scrollRegions", "rectPass" }
		do
			expect(`{name}={byWalk[name]}`).toBe(`{name}={MOUNTED}`)
		end
		s.dispose()
	end)

	it("...and a caster tick moves the same numbers (the mixed-dirt step exists and bites)", function()
		local s = scene.new()
		-- WARM-UP, discarded (wicked-fast T2, Step 6 finding). The FIRST refresh
		-- after `scene.new()` pays a one-time cost the case above pins at 2002:
		-- every layout node the fresh scene has not solved incrementally yet gets
		-- rebuilt for the 252 paths `dirtyContains` covers (see `lastNodeBuilds`).
		-- Comparing that cold tick against a second one — pure or mixed — would
		-- attribute the one-time cost to whichever mechanism happened to run
		-- second, which is not what this case is asking. One tick absorbs it;
		-- every tick after is the steady 1252 this case actually compares.
		s.tick(3, 2)
		s.tick(3, 2)
		local pure = s.stats().lastMeasured
		s.tickWithCasts(3, 2)
		local mixed = s.stats().lastMeasured
		expect(mixed >= pure).toBe(true)
		expect(s.stats().lastArranged).toBe(LAYOUT)
		s.dispose()
	end)
end)
