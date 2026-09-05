--!strict
--[[ C5 — THE PAINT-ORDER WALK IS THE LAST WHOLE-TREE PASS IN A STRUCTURAL SYNC.

	After O6 bounded `ensureTree`, `livePaths` and the removal sweep, adding one plate
	to a 250-row surface visited 16 nodes for those three and 1,503 for `syncZOrder`.
	MEASURED, headless, on `nameplates_scene` at 250 plates, medians over 80 syncs:
	`ssZOrder` 0.3504 ms of a 0.4946 ms `structuralSync` — 71 % of the pass, and 28.5 %
	/ 36.9 % of FacetBench's `nameplates addItem-plates` / `removeItem-plates` classes.

	WHAT THE BRIEF EXPECTED, AND WHAT THE RUN SAID. The plan proposed walking from each
	root's nearest COORDINATE-SPACE HOST ancestor. On this fixture the structural delta
	is one entry — `structure` at `/S/Canvas/Plates`, the ForEach region — and that
	path's `geometry.hostSpaceOf` is `nil`: the region is not a coordinate-space host
	and has none above it. So the host rule resolves to "the whole tree" here and buys
	nothing, and the plan's target of `NODES_PER_PLATE + 2` is unreachable by ANY exact
	algorithm on this shape: the changed parent's `children` array is a NEW table, so
	finding where in document order the change sits is an O(#children) scan. The floor
	is the descent plus that parent's children, and the pins below are exactly that.

	THE PROPERTY THE BOUND RESTS ON, because it is NOT byte-equality of `handle.z`. A
	single running pre-order counter renumbers everything after an insertion, so a walk
	that stops early cannot reproduce a whole-tree walk's integers. It does not need
	to. `ZIndexBehavior.Sibling` orders SIBLINGS within a parent and lets the hierarchy
	carry the rest, and the drag registry reads `lastZ` as a paint-order TIE-BREAK
	(`render/drag_bridge`) — a comparison, never a value. So the walk owes

	  (Z1) z strictly increasing over its own visit order, and (Z2) every number
	  distinct, so a hit expander's reserved `z - 1` is nobody else's z,

	and gaps are free. `render/z_order.luau` carries the argument for why a skip
	MAINTAINS (Z1) — including through a reorder — and the differential here is
	therefore the RANKING of every z-bearing path against a from-scratch walk's, which
	is strictly stronger than a value diff: a value diff also passes a walk that
	assigned the right numbers in the wrong ORDER, and it FAILS a correct bounded walk
	for the one reason that does not matter.

	AND THE COUNTERS ARE CUMULATIVE, read as a delta with `zPasses` beside them. A
	frame can run TWO z walks — this bounded one, and the commit's hit-lift re-run,
	which is whole-tree and lands after it whenever the overhang lift moved. A `last`
	capture would report whichever ran second, so a pin built on one would silently be
	measuring the re-run on any surface that has an expander (which is what it did on
	Rascal Rally's racer list — see that repo's `facet_structural_incremental.spec`).

	THE ORACLE ARM IS `controller.initialRender()`, not an attach opt.
	`RendererAttachOpts.structuralReuse` does NOT gate the structural sync's bound
	(`renderer.luau:1642`, read only at `:2484` and `:2954` — it gates the SOLVE's
	reuse), so an arm raised with it off is bounded exactly like the arm under test and
	the differential would compare a thing against itself. A sync with no delta is the
	one route that cannot be bounded, which is the same oracle
	`tests/structural_incremental.spec.luau` uses for O6. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

local PLATES = scene.PLATES
local PER = scene.NODES_PER_PLATE
-- the same derivation `tests/structural_incremental.spec.luau` states: no per-item
-- wrapper node, plus the Screen, the Anchor and the one ForEach region
local MOUNTED = PLATES * PER + 2 + 1 -- 1503

--[[ THE DESCENT is the three nodes above the change — `/S`, `/S/Canvas` and the region
	`/S/Canvas/Plates` — every one of which is an ancestor of the dirty root and so may
	not be skipped. Everything below is one O(1) memo probe per surviving plate root,
	because a plate root is a DIRECT child of the region and its five descendants are
	not: the skip takes the root and its whole subtree in one step. ]]
local DESCENT = 3
local Z_ADD = DESCENT + PLATES + PER -- 259: the descent, 250 skips, the new plate
local Z_REMOVE = DESCENT + (PLATES - 1) -- 252: the descent and the 249 survivors

--[[ THE Z READING, off the adapter rather than off `lastZ`: `fake_target.setZOrder`
	stores the number on the handle (`handle.z`), and `adapter.node(path)` is the only
	published way to it. A path with no handle — the ForEach region's `…/[pN]` strings
	are not nodes at all — simply has no z, and the SET of z-bearing paths is itself
	part of what the differential compares. ]]
local function zOf(s: any): ({ string }, { [string]: number })
	local order: { string } = {}
	local z: { [string]: number } = {}
	for _, path in s.paths() do
		local node = s.adapter.node(path)
		if node ~= nil and node.z ~= nil then
			table.insert(order, path)
			z[path] = node.z
		end
	end
	return order, z
end

-- ...and the RANK: the same paths, sorted by the number they were given. Two arms
-- agree when this list agrees, whatever the numbers themselves are.
local function rankOf(s: any): { string }
	local order, z = zOf(s)
	local ranked = table.clone(order)
	table.sort(ranked, function(a, b)
		return z[a] < z[b]
	end)
	return ranked
end

local function firstDiff(a: { string }, b: { string }): string?
	if #a ~= #b then
		return `lengths {#a} vs {#b}`
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return `rank {i}: {a[i]} vs {b[i]}`
		end
	end
	return nil
end

describe("C5: the paint-order walk skips to the change", function()
	it("adding one plate walks 259 nodes, not 1,503", function()
		local s = scene.new()
		s.tick(3, 2)
		--[[ A DELTA, because `scene.new()` calls `initialRender` and that is a whole-tree
			walk BY CONSTRUCTION; and `ssPasses` is in the string for the reason O6's own
			pins put it there — `lastZVisited` is a LAST capture, so a drive that ran two
			syncs would report only the second and one that ran none would re-assert
			history. ]]
		local before = s.stats()
		s.add(1)
		local st = s.stats()
		expect(
			`zVisits={st.zVisits - before.zVisits} zPasses={st.zPasses - before.zPasses}`
				.. ` ssPasses={st.ssPasses - before.ssPasses}`
				.. ` full={st.ssFullPasses - before.ssFullPasses} mounted={s.census().mounted}`
		).toBe(`zVisits={Z_ADD} zPasses=1 ssPasses=1 full=0 mounted={MOUNTED + PER}`)
		s.dispose()
	end)

	it("removing one plate walks 252, and owes not one z write", function()
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats()
		--[[ THE OP TAIL, from a mark taken before the drive: `adapter.ops()` is the
			session's whole log, and the initial render's own 1,503 z writes are in it. A
			count over the whole list reads 1,503 and says nothing about this step — which
			is what it did on this case's first run. ]]
		local mark = #s.adapter.ops()
		s.remove(3)
		local st = s.stats()
		--[[ THE REMOVE IS THE PURE CASE. Everything after the hole keeps its numbers —
			still strictly increasing in the new document order, with a gap where the plate
			was — so the walk assigns nothing at all and `z ` never appears in the tail. ]]
		local ops = s.adapter.ops()
		local zWrites = 0
		for i = mark + 1, #ops do
			if string.sub(ops[i], 1, 2) == "z " then
				zWrites += 1
			end
		end
		expect(
			`zVisits={st.zVisits - before.zVisits} zPasses={st.zPasses - before.zPasses}`
				.. ` ssPasses={st.ssPasses - before.ssPasses}`
				.. ` full={st.ssFullPasses - before.ssFullPasses} zWrites={zWrites}`
		).toBe(`zVisits={Z_REMOVE} zPasses=1 ssPasses=1 full=0 zWrites=0`)
		s.dispose()
	end)

	it("THE NEGATIVE CONTROL: a sync with no delta walks the whole tree, as it always did", function()
		--[[ `controller.initialRender()` passes no delta, which is the one route that
			cannot be bounded, and it is also the guard that stops the two cases above from
			passing on a fixture that never takes the bounded path: a count that is always
			the tree is a skip nobody is reaching. ]]
		local s = scene.new()
		local st = s.stats()
		expect(`initial={st.zVisits} passes={st.zPasses} mounted={s.census().mounted}`).toBe(
			`initial={MOUNTED} passes=1 mounted={MOUNTED}`
		)
		local mid = s.stats()
		s.add(1)
		expect(`bounded={s.stats().zVisits - mid.zVisits}`).toBe(`bounded={Z_ADD}`)
		local mark = s.stats()
		s.controller.initialRender()
		expect(`forced={s.stats().zVisits - mark.zVisits}`).toBe(`forced={MOUNTED + PER}`)
		s.dispose()
	end)
end)

describe("C5: the differential — a bounded walk paints in the order a full one paints", function()
	--[[ TWO IDENTICAL SCENES take identical structural steps and one of them is forced
		through the whole-tree walk after each; the arms are compared by RANK, for the
		reason the header gives. The step list mixes appends, mid-list removals and a
		REORDER, because a reorder is the case the skip's soundness argument turns on:
		it is the one drive where a subtree the walk keeps has MOVED. ]]
	local function driveOracle(view: { id: string, w: number, h: number }, withButton: boolean): string
		local viewport = { x = 0, y = 0, w = view.w, h = view.h }
		local a = scene.new({ viewport = viewport, withButton = withButton })
		local b = scene.new({ viewport = viewport, withButton = withButton })
		local seed = 20260904
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return (seed % n) + 1
		end
		local function reorder(s: any, from: number, to: number)
			local rows = table.clone(s.rows:get() :: any)
			table.insert(rows, to, table.remove(rows, from) :: any)
			s.rows:set(rows)
			s.controller.refresh()
		end
		local out = "clean"
		for step = 1, 24 do
			local beforeA = a.stats()
			if step % 4 == 0 then
				local i = rnd(20)
				a.remove(i)
				b.remove(i)
			elseif step % 4 == 2 then
				-- a plate root moves from the front of the region's children to the middle,
				-- so the walk meets a subtree whose kept numbers are ABOVE the counter
				local from, to = rnd(10), 20 + rnd(30)
				reorder(a, from, to)
				reorder(b, from, to)
			else
				-- the step number, not a random one: `scene.add(i)` keys on `add{i}` and two
				-- adds with the same `i` are a duplicate key the ForEach quarantines
				a.add(step)
				b.add(step)
			end
			local afterA = a.stats()
			local passes = afterA.ssPasses - beforeA.ssPasses
			local full = afterA.ssFullPasses - beforeA.ssFullPasses
			--[[ ...AND EACH DRIVE WAS BOUNDED, checked per step: a run that fell back once
				and compared clean for the other 23 would be reporting the FALLBACK's
				correctness. `zVisited < MOUNTED` is the C5 half of the same guard — a
				bounded structural sync whose z walk still took the tree is exactly the
				regression this file exists to catch. ]]
			local zSteps = afterA.zPasses - beforeA.zPasses
			local zNodes = afterA.zVisits - beforeA.zVisits
			if passes ~= 1 or full ~= 0 or zSteps ~= 1 or zNodes >= a.census().mounted then
				out = `step {step} ran ssPasses={passes} full={full} zPasses={zSteps} zVisits={zNodes}`
				break
			end
			b.controller.initialRender()
			local diff = firstDiff(rankOf(a), rankOf(b))
			if diff ~= nil then
				out = `step {step} diverged from a from-scratch walk: {diff}`
				break
			end
			-- ...and (Z1)/(Z2) inside the bounded arm itself, on ITS OWN terms: strictly
			-- increasing over the fixture's declaration order, which is the walk's visit
			-- order here, and no number handed out twice
			local order, z = zOf(a)
			local prev, seen = -1, {}
			for _, path in order do
				if z[path] <= prev then
					out = `step {step} not increasing at {path}: {z[path]} after {prev}`
					break
				end
				if seen[z[path]] then
					out = `step {step} duplicate z {z[path]} at {path}`
					break
				end
				seen[z[path]] = true
				prev = z[path]
			end
			if out ~= "clean" then
				break
			end
		end
		a.dispose()
		b.dispose()
		return out
	end

	it("24 adds, removals and reorders leave the paint order a from-scratch walk would build", function()
		expect(driveOracle({ id = "default", w = 1280, h = 720 }, false)).toBe("clean")
	end)

	it("...with a hit expander on the surface, which owns the number below it", function()
		--[[ `Opts.withButton` puts a 20x16 Button under plate 3's Row: below the hit floor,
			so the hit-rect walk gives it an EXPANDER, and the walk must reserve `z - 1` for
			it. A skip that handed a kept subtree's numbers back into that reservation would
			put an expander level with a real node, and level is not above. ]]
		expect(driveOracle({ id = "default", w = 1280, h = 720 }, true)).toBe("clean")
	end)

	it("the arms do NOT agree on the VALUES, which is the claim this file is making", function()
		--[[ Stated as a case rather than as prose, so that nobody re-pins this differential
			to byte-equality and quietly deletes the bound to make it pass. A removal leaves
			a gap the bounded walk never closes; the from-scratch arm has no gap. ]]
		local a = scene.new()
		local b = scene.new()
		a.remove(3)
		b.remove(3)
		b.controller.initialRender()
		local _, az = zOf(a)
		local _, bz = zOf(b)
		local differing = 0
		for path, value in az do
			if bz[path] ~= value then
				differing += 1
			end
		end
		expect(`ranks equal:{firstDiff(rankOf(a), rankOf(b)) == nil} values differing:{differing > 0}`).toBe(
			"ranks equal:true values differing:true"
		)
		a.dispose()
		b.dispose()
	end)
end)

describe("C5: the compaction latch pays the gaps back", function()
	it("sustained churn forces one whole-tree walk and holds the numbers near the tree", function()
		--[[ THE GUARD, DRIVEN. Each add/remove pair moves the high-water mark by a plate's
			worth and gives none of it back, so an unbounded scheme would drift the counter
			for as long as the surface churns. `z_order` remembers where the last whole-tree
			walk ended and makes the next walk whole-tree once a bounded one ends past twice
			it — so the numbers stay within a small factor of the tree instead of merely
			under an int32 ceiling, and the cost is one full walk per hundreds of steps.

			Read off the run: the first compaction lands part-way through, and the highest z
			on the surface afterwards is bounded by that rule rather than by the step count. ]]
		local s = scene.new()
		local compactions = 0
		local highest = 0
		for step = 1, 320 do
			local before = s.stats()
			s.add(step)
			local mid = s.stats()
			if mid.zVisits - before.zVisits >= s.census().mounted then
				compactions += 1
			end
			s.remove(3)
			if s.stats().zVisits - mid.zVisits >= s.census().mounted then
				compactions += 1
			end
		end
		local _, z = zOf(s)
		for _, value in z do
			if value > highest then
				highest = value
			end
		end
		-- 320 add/remove pairs at six nodes a pair is ~1,920 counter-increments of drift
		-- against a 1,503-node tree; without the latch the highest z would be past 3,400
		expect(`compactions>0:{compactions > 0} highest<={highest <= MOUNTED * 2 + 64}`).toBe(
			"compactions>0:true highest<=true"
		)
		s.dispose()
	end)
end)
