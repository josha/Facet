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
local MEASURED_STEADY = 0
-- ...and a caster tick keeps ONLY its caster term (T4, `14c3459d`, was 652): the
-- `(PLATES - CASTERS) * 2` half was the 200 quiet plates' arrange descent and the
-- translate arm removes it, leaving each of the 50 casters at 5 (its refused root,
-- plus `Hp`/`Cast` on both the measure and the arrange descent) and the two
-- ancestors every caster's measure dirt closes over.
local MEASURED_STEADY_CASTERS = CASTERS * 5 + 2 -- 252
-- READ OFF THE RUN, instrumented at T2 (`solver.measureUncached`, temporary
-- counter, reverted before commit) as 1502 distinct nodes measured once PLUS the
-- 500 Hp/Cast boxes measured a SECOND time by the vstack arrange branch. T4
-- (`14c3459d`) removes that second touch here too — the cold tick's plates have
-- already moved and their subtrees are clean, so they translate — and what is left
-- is exactly the 1502 distinct measures. See "the first tick after mount pays a
-- one-time cold solve".
local MEASURED_COLD = LAYOUT -- 1502
-- the O3 split of `lastArranged` (T4, `14c3459d`), read off the run: the Screen,
-- the Canvas and the 250 plate ROOTS take the ordinary entry write and each
-- re-bases its 5 descendants.
local ARRANGED_STEADY = PLATES + 2 -- 252
local TRANSLATED_STEADY = PLATES * (scene.NODES_PER_PLATE - 1) -- 1250
-- the COMMIT's own dirty closure on a steady pure tick, and T5's (`4b0f5e19`) pin for
-- seven of the eight walks: Screen + Canvas + the ForEach region + one root per
-- plate. `tests/commit_translate.spec.luau` carries the derivation, the caster
-- column (303, and `rectPass` 403) and the four-arm adapter oracle behind it.
local VISITS_PRUNED = PLATES + 3 -- 253

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
		-- MEASURED_STEADY is the number READ OFF THE RUN and written in as a
		-- literal, with the header note beside it. It is the "currently N"
		-- every later demonstrator quotes, so it is on disk rather than in a
		-- memory of a profiling session. Moved 1252 -> 500 by T3's
		-- measure/arrange dirt split (`157ed3c9`), and 500 -> 0 by T4's
		-- translate arm (`14c3459d`).
		expect(st.lastMeasured).toBe(MEASURED_STEADY)
		-- ...and `lastArranged` is no longer the whole tree (T4, `14c3459d`): the
		-- 1250 nodes that only MOVED are a class of their own now, and the two
		-- halves still have to add up to the tree.
		expect(st.lastArranged).toBe(ARRANGED_STEADY)
		expect(st.lastTranslated).toBe(TRANSLATED_STEADY)
		expect(st.lastArranged + st.lastTranslated).toBe(LAYOUT)
		expect(st.lastRectInserts).toBe(LAYOUT)
		expect(st.lastNodeBuilds).toBe(PLATES + 2) -- 252: the moved plates + Canvas + Screen, dirtyContains
		-- CUMULATIVE since `scene.new()` (Fix round 2, I-1): `rectWrites` is
		-- never reset per-commit, only incremented on an actual value change.
		-- STILL TRUE UNDER T5's RUN ARM (`4b0f5e19`, review round 1): a translated
		-- subtree is emitted from the solver's flat run rather than walked for, but
		-- every element of that run goes through the same `rect_pass.applyOne` the
		-- walk uses, so the minimal-write contract has exactly one implementation.
		-- `tests/commit_translate.spec`'s zero-delta case is the pin. READ OFF THE RUN: initialRender's own solve
		-- writes every rect once (1502, everything is new) and each of the two
		-- ticks since writes 1500 more (LAYOUT minus the 2 static ancestors,
		-- Screen and Canvas, whose fill rect never moves) = 1502+1500+1500=4502.
		expect(st.rectWrites).toBe(4502)
		-- the EXACT aggregate (Fix round 2, I-1): the sum of the eight per-walk
		-- counts below, and the only exact pin of the aggregate in this repo —
		-- the old `>= MOUNTED * 7` bound could never fail (a walk silently
		-- publishing twice would still sail past a MOUNTED * 7 floor).
		expect(st.lastCommitVisits).toBe(VISITS_PRUNED * 7 + MOUNTED) -- 3274
		-- the per-walk breakdown this task exists to publish, MOVED BY T5
		-- (`4b0f5e19`) from the whole tree to the dirty closure: the six walks whose
		-- output cannot read a position take `skip(node, true)` and prune a
		-- moved subtree away, `rectPass` stops AT each translate root and emits
		-- the solver's run, and `hitRects` still walks everything because it
		-- centres its target-floor expander on `r.x`/`r.y`.
		local byWalk = st.lastCommitVisitsByWalk
		for _, name in { "harvest", "textScale", "padding", "textVerdicts", "visible", "scrollRegions", "rectPass" } do
			expect(`{name}={byWalk[name]}`).toBe(`{name}={VISITS_PRUNED}`)
		end
		expect(`hitRects={byWalk.hitRects}`).toBe(`hitRects={MOUNTED}`)
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
		-- ...and the cold tick translates exactly as a steady one does (T4): what
		-- makes it cold is the measure store, not the arrange half.
		expect(st.lastArranged).toBe(ARRANGED_STEADY)
		expect(st.lastTranslated).toBe(TRANSLATED_STEADY)
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
		-- plates + 2 ancestors. BEFORE T3, comparing `lastMeasured` here did
		-- NOT bite — the steady measure touched every Hp/Cast box regardless of
		-- caster activity, so a pure and a caster tick read the identical 1252
		-- and `lastNodeBuilds` was the only counter that moved. T3's split
		-- separated them (`157ed3c9`): the caster's `width` dirt is
		-- measure-classed, so only the 50 caster plate roots lose their slate.
		expect(mixed.lastNodeBuilds).toBe(PLATES + 2 + CASTERS) -- 302
		expect(pure.lastMeasured).toBe(MEASURED_STEADY) -- 0
		expect(mixed.lastMeasured).toBe(MEASURED_STEADY_CASTERS) -- 252
		-- ...and the caster tick's ARRANGE half is derivation (b), read off the run
		-- (T4, `14c3459d`): 4 arranged per caster (Plate, Row, Hp, Cast) because
		-- `Row` and `Hp` are themselves translate roots under a plate the `Cast`
		-- dirt forced open. `tests/translate_arm.spec` carries the arithmetic.
		expect(mixed.lastArranged).toBe(PLATES + 2 + CASTERS * 3) -- 402
		expect(mixed.lastTranslated).toBe((PLATES - CASTERS) * 5 + CASTERS * 2) -- 1100
		expect(mixed.lastArranged + mixed.lastTranslated).toBe(LAYOUT)
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
		s.tick(3, 2)
		-- READ OFF THE RUN, and re-split by T4 (`14c3459d`): the tree grew by one
		-- plate, so the arrange half grew by exactly its ROOT and the translate half
		-- by its five descendants. The SUM still matches the naive expression
		-- (LAYOUT plus one plate's own six layout nodes), which is the pin the
		-- add/remove case is actually about.
		local afterTick = s.stats()
		expect(afterTick.lastArranged).toBe(ARRANGED_STEADY + 1) -- 253
		expect(afterTick.lastTranslated).toBe(TRANSLATED_STEADY + (scene.NODES_PER_PLATE - 1)) -- 1255
		expect(afterTick.lastArranged + afterTick.lastTranslated).toBe(LAYOUT + scene.NODES_PER_PLATE)
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
		-- READ OFF THE RUN: `withPath` adds exactly one node — the `UI.Path`
		-- Spark leaf, Canvas's second child alongside the ForEach — to both
		-- `mounted` and `layout`. `overflow` only widens plate p1's own box
		-- (no node added or removed), so it moves neither count on its own.
		expect(`plates={c.plates} casters={c.casters} mounted={c.mounted} layout={c.layout}`).toBe(
			`plates={PLATES} casters={CASTERS} mounted={MOUNTED + 1} layout={LAYOUT + 1}`
		)
		s.tick(3, 2) -- warm-up
		s.tick(3, 2)
		-- READ OFF THE RUN, AND IT STILL DISAGREES WITH THE NAIVE "+1"
		-- EXPRESSION, now on the far side of T4 (`14c3459d`): the Spark leaf is
		-- a layout node (`layout` reads LAYOUT + 1 above) and it is neither
		-- arranged nor translated on a translate-only tick — it lands on the
		-- rect it already had and the SKIP catches it, which `lastSolveSkipped`
		-- says directly. Mechanism instrumented this time, so the three
		-- outcomes below account for every node.
		local st = s.stats()
		expect(st.lastArranged).toBe(ARRANGED_STEADY) -- 252
		expect(st.lastTranslated).toBe(TRANSLATED_STEADY) -- 1250
		expect(st.lastSolveSkipped).toBe(1) -- the Spark leaf, and only it
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(LAYOUT + 1)
		s.dispose()
	end)
end)
