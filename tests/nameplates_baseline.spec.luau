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
	  | `lastMeasured` on a STEADY tick | T3 | 500 = PLATES x 2 (pure) / read off the run (casters) |
	  | `lastMeasured` on a STEADY tick | T4 | 0 (pure) — the translate arm stops re-entering the subtree |
	  | `lastNodeBuilds`           | T3 | moves off 252 pure / 302 casters — the value after is read off the run when T3 rewrites the dirty closure |
	  | `lastArranged`             | T4 | 252 (pure) / 302 (casters, see T4 Step 1's competing derivation) |
	  | `lastRectInserts`          | T4 | arranged + translated = 1,502 |
	  | every per-walk visit count | T5 | 253 (pure) / 303 (casters); hitRects stays 1,503 |
	  | the four hidden-blind walks | T5b (if built) | 3 on a pure tick |
	  | the census, `rectWrites`   | never | 1,503 mounted / 1,502 layout / 1,500 writes |

	253 is Screen + Canvas + the ForEach region + one root per plate. The 250
	`…/[pN]` strings `markNodeDirty` also writes have NO mounted node behind them
	(`mount.luau:357` uses `rowPath` as a parent path), and `skip` is only ever
	asked about real nodes — so they are dirty PATHS and never commit VISITS.

	`MEASURED_STEADY` and `MEASURED_COLD` (wicked-fast T2, Fix round 1 — the
	controller's ruling): the "currently N" a later demonstrator quotes must be
	the STEADY tick, not the scene's cold first one, so `MEASURED_STEADY` is what
	the second case below pins and `MEASURED_COLD` is its own small case, not the
	round's baseline.

	`MEASURED_STEADY` READ OFF THE RUN: every tick after the scene's first reads
	1252 = every layout node measured once EXCEPT the 250 plate roots
	(1502 - 250). MECHANISM NOT INSTRUMENTED — unlike the cold tick (see "the
	first tick after mount pays a one-time cold solve" below, which IS
	instrumented), I did not trace which nodes drop out of the steady measure;
	only that the arithmetic identity holds on every steady tick observed, pure
	or with casters (the fourth case). `lastNodeBuilds` reads 252 on a steady
	pure tick and 302 on a steady caster tick either way — READ OFF THE RUN, not
	derived — the 250 moved plates + Canvas + Screen (`dirtyContains`), plus the
	50 caster boxes when a caster tick adds them to that set. ]]
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
-- READ OFF THE RUN, mechanism not instrumented (see the header note above):
-- every layout node measured once EXCEPT the 250 plate roots.
local MEASURED_STEADY = LAYOUT - PLATES -- 1252
-- READ OFF THE RUN, instrumented (`solver.measureUncached`, temporary counter,
-- reverted before commit): 1502 distinct nodes measured once, PLUS the 500
-- Hp/Cast boxes measured a second time by the vstack arrange branch — see "the
-- first tick after mount pays a one-time cold solve" for the full breakdown.
local MEASURED_COLD = LAYOUT + PLATES * 2 -- 2002

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
		-- WARM-UP, discarded (wicked-fast T2, Fix round 1). The scene's FIRST
		-- refresh after `scene.new()` pays a one-time cold-solve cost — its own
		-- case below, "the first tick after mount pays a one-time cold solve".
		-- This case pins the STEADY tick — the number every later demonstrator
		-- in this round actually reads "currently N" from — so one discarded
		-- tick absorbs the cold cost before the pinned measurement.
		s.tick(3, 2)
		s.tick(3, 2)
		local st = s.stats()
		-- MEASURED_STEADY is the number Fix round 1 READS OFF THE RUN and
		-- writes in as a literal, with the header note beside it. It is the
		-- "currently N" every later demonstrator quotes, so it is on disk
		-- rather than in a memory of a profiling session.
		expect(st.lastMeasured).toBe(MEASURED_STEADY)
		expect(st.lastArranged).toBe(LAYOUT)
		expect(st.lastRectInserts).toBe(LAYOUT)
		expect(st.lastNodeBuilds).toBe(PLATES + 2) -- 252: the moved plates + Canvas + Screen, dirtyContains
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

	it("the first tick after mount pays a one-time cold solve", function()
		local s = scene.new()
		s.tick(3, 2)
		local st = s.stats()
		-- MEASURED_COLD, instrumented directly (`solver.measureUncached`,
		-- temporary counter, reverted before commit): of the 2002 measure calls
		-- this first tick makes, exactly 1502 are DISTINCT nodes — every layout
		-- node, once — and the other 500 land on the 500 Hp/Cast boxes
		-- (`kind=box`), each measured TWICE in the same solve. By solver kind:
		-- vstack=251, hstack=250, text=500, anchor=1 (each measured once,
		-- matching LAYOUT's own count of each), plus box=1000 calls across 500
		-- distinct nodes (measured twice: 251+250+500+1+1000=2002,
		-- 251+250+500+1+500=1502 distinct). This is the scene's FIRST solve
		-- eligible for `layoutNodeReuse` (`initialRender` is not itself a reuse
		-- solve) — which is also why `lastNodeBuilds` reads the SAME 252 here
		-- as on a steady tick below: builds is not what makes this tick cold.
		expect(st.lastMeasured).toBe(MEASURED_COLD)
		expect(st.lastArranged).toBe(LAYOUT)
		expect(st.lastNodeBuilds).toBe(PLATES + 2) -- 252 — same as a steady tick
		s.dispose()
	end)

	it("...and a caster tick moves lastNodeBuilds (the mixed-dirt step exists and bites)", function()
		local s = scene.new()
		-- WARM-UP, discarded — see the steady case above.
		s.tick(3, 2)
		s.tick(3, 2)
		local pure = s.stats()
		expect(pure.lastNodeBuilds).toBe(PLATES + 2) -- 252
		s.tickWithCasts(3, 2)
		local mixed = s.stats()
		-- the 50 caster boxes join `dirtyContains` alongside the 250 moved
		-- plates + 2 ancestors (Fix round 1: comparing `lastMeasured` here does
		-- NOT bite before T3 — the steady measure already touches every
		-- Hp/Cast box regardless of caster activity, so a pure and a caster
		-- tick read the identical 1252. `lastNodeBuilds` is the counter that
		-- DOES move today; T3's own demonstrator is where `lastMeasured` for a
		-- pure vs. a caster tick diverges — 500 pure / read off the run for
		-- casters, per the header table above).
		expect(mixed.lastNodeBuilds).toBe(PLATES + 2 + CASTERS) -- 302
		expect(pure.lastMeasured).toBe(MEASURED_STEADY)
		expect(mixed.lastMeasured).toBe(MEASURED_STEADY)
		expect(mixed.lastArranged).toBe(LAYOUT)
		s.dispose()
	end)
end)
