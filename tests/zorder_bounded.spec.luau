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

	WHAT THE BOUND DOES NOT SURVIVE, stated here because the module's own argument used
	to give only the favourable half. A REORDER renumbers from the insertion point to the
	end of the parent, and that is inherent to one monotone counter: the moment a
	subtree's old range lies BELOW the counter it has to move, and so does every sibling
	after it. Measured on this fixture (250 plates, 1,503 mounted, `full=0` on all four):
	`250 -> 249` costs 258 nodes, `5 -> 40` costs 1,308, `200 -> 5` costs 1,478, `1 -> 2`
	costs 1,498. Correct in every case — the cascade is the conservative direction — but
	a reorder near the FRONT of a list is the whole-tree walk again, which is the cost it
	had before C5 and not a regression. The case below pins all four, because a per-step
	`>= mounted` guard passes at 1,478 and would let the bound vanish unnoticed.

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
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local themeSnapshot = require("../src/themes/snapshot")

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
		-- ARMED (T12): the op tail below reads `.ops()`.
		local s = scene.new({ ops = true })
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
		-- E3: these historical global-rank pins model a cross-host drag reader.
		a.controller.dragRegistry()
		b.controller.dragRegistry()
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
		local total = 0
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
			total += zNodes
			--[[ ONE Z WALK A STEP, and a running TOTAL rather than a per-step ceiling: six
				of these steps are reorders, which cost most of the tree by construction
				(see the header), so a `>= mounted` guard would pass at 1,478 of 1,503 and a
				vanished bound would read green. The total is pinned by the caller off the
				run, so any step's bound going costs a number nobody can miss. ]]
			if passes ~= 1 or full ~= 0 or zSteps ~= 1 then
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
		local mounted = a.census().mounted
		a.dispose()
		b.dispose()
		--[[ ...and the MOUNTED count rides the verdict, so the two callers below cannot
			silently be driving the same fixture. Their TOTALS coincide and that is not a
			bug: the Button sits under plate `p3`'s Row, every reorder here inserts at
			index 20-50 so the cascade starts AFTER it, every add appends and every remove
			leaves the tail on its own numbers — so p3's subtree is skipped as one probe in
			all 24 steps and its extra node is never walked. The mounted counts differing
			by one is what proves the two arms are actually different. ]]
		return `{out} total={total} mounted={mounted}`
	end

	it("24 adds, removals and reorders leave the paint order a from-scratch walk would build", function()
		expect(driveOracle({ id = "default", w = 1280, h = 720 }, false)).toBe("clean total=12997 mounted=1539")
	end)

	it("...with a hit expander on the surface, which owns the number below it", function()
		--[[ `Opts.withButton` puts a 20x16 Button under plate 3's Row: below the hit floor,
			so the hit-rect walk gives it an EXPANDER, and the walk must reserve `z - 1` for
			it. A skip that handed a kept subtree's numbers back into that reservation would
			put an expander level with a real node, and level is not above. ]]
		expect(driveOracle({ id = "default", w = 1280, h = 720 }, true)).toBe("clean total=12997 mounted=1540")
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

--[[ ── THE MEMO'S OWN LIFETIME ────────────────────────────────────────────────
	Everything above drives ONE `ForEach` that never empties and is always the dirty
	root, so no node in it can ever be both SKIPPABLE and carrying a memo that no
	longer describes it. That is a shape the fixture cannot express, and it is where
	the first version of this walk was wrong (T9 review, IMPORTANT 1): the
	`#kids > 0` guard stops a memo being WRITTEN for a childless node and never
	CLEARED one that was already there, so a container that emptied kept a memo from
	the last walk that saw its children, was renumbered by churn elsewhere without
	refreshing it, and was then skipped back onto a number it had not held for two
	walks. Both (Z1) and (Z2) went with it.

	The scene below is the reviewer's, verbatim in shape: two sibling `ForEach`
	regions and twelve plain boxes under one `VStack`, so that ONE region can empty
	while the OTHER supplies the churn that renumbers it. ]]
local function px(n: number): any
	return { type = "fixed", px = n }
end

local function memoScene(): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local a = core:signal({ "a1" })
	local b = core:signal({ "b1", "b2" })
	local function region(id: string, items: any): any
		return UI.ForEach({
			id = id,
			items = items,
			key = function(item: any)
				return item
			end,
			--[[ A ROW IS A CONTAINER, not a leaf, and that is load-bearing twice: only a
				node with children earns a memo entry, so a row template that is one Box
				would make `zMemoEntries` blind to a departed row's entry — which is the
				line `zOrder.forget` exists to clear. ]]
			row = function(_item: any)
				return UI.VStack({
					id = "R",
					padding = 0,
					gap = 0,
					children = { UI.Box({ id = "Dot", width = px(20), height = px(6) }) },
				})
			end,
		})
	end
	local kids: { any } = { region("A", a), region("B", b) }
	for i = 1, 12 do
		table.insert(kids, UI.Box({ id = `C{i}`, width = px(20), height = px(6) }))
	end
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = { UI.VStack({ id = "V", padding = 0, gap = 0, children = kids }) },
		})
	)
	local adapter = fake_target.new({ ops = true })
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return {
		core = core,
		env = env,
		adapter = adapter,
		controller = controller,
		root = root,
		setA = function(list: { string })
			a:set(list)
			controller.refresh()
		end,
		setB = function(list: { string })
			b:set(list)
			controller.refresh()
		end,
	}
end

--[[ ...AND THE READING IS PER PARENT, because that is what the engine consumes and
	what a global rank comparison can hide: two siblings under one `VStack` are exactly
	the pair `ZIndexBehavior.Sibling` orders. `Z2` is asked of the WHOLE tree, because a
	duplicate anywhere is a tie the hit expander's reserved `z - 1` is guaranteed
	against. ]]
local function walkPaths(node: any, out: { string })
	table.insert(out, node.path)
	for _, child in node.children do
		walkPaths(child, out)
	end
end

local function parentOf(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function siblingOrder(rig: any): string
	local paths: { string } = {}
	walkPaths(rig.root.node, paths)
	local z: { [string]: number } = {}
	local byParent: { [string]: { string } } = {}
	local order: { string } = {}
	for _, path in paths do
		local node = rig.adapter.node(path)
		if node ~= nil and node.z ~= nil then
			z[path] = node.z
			local parent = parentOf(path)
			if byParent[parent] == nil then
				byParent[parent] = {}
				table.insert(order, parent)
			end
			table.insert(byParent[parent], path)
		end
	end
	table.sort(order)
	local out: { string } = {}
	for _, parent in order do
		local kids = byParent[parent]
		table.sort(kids, function(x, y)
			return z[x] < z[y]
		end)
		table.insert(out, `{parent}[{table.concat(kids, ",")}]`)
	end
	return table.concat(out, " ")
end

local function duplicateZ(rig: any): string
	local paths: { string } = {}
	walkPaths(rig.root.node, paths)
	local seen: { [number]: string } = {}
	for _, path in paths do
		local node = rig.adapter.node(path)
		if node ~= nil and node.z ~= nil then
			if seen[node.z] ~= nil then
				return `{seen[node.z]} and {path} both hold z {node.z}`
			end
			seen[node.z] = path
		end
	end
	return "none"
end

describe("C5: a container that empties does not keep a memo", function()
	it("an emptied region, renumbered by its sibling's churn, still paints in order", function()
		--[[ THE FOUR STEPS, and each one is an ordinary public-API drive: B empties, A
			grows (which renumbers B without refreshing a memo it no longer writes), A
			shrinks back (which walks the counter to exactly B's stale entry value and
			skips it). Against an arm forced through the whole-tree walk after every step,
			`solves` is whatever the drives cause — the claim here is paint order, not
			solve count, and `ssFullPasses` is the guard that says the arm under test
			never fell back. ]]
		local live = memoScene()
		local oracle = memoScene()
		local steps: { { region: string, items: { string } } } = {
			{ region = "B", items = {} },
			{ region = "A", items = { "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11" } },
			{ region = "A", items = { "a1" } },
			{ region = "B", items = { "b1", "b2", "b3" } },
		}
		local verdict = "clean"
		for index, step in steps do
			local before = live.controller.stats()
			if step.region == "A" then
				live.setA(step.items)
				oracle.setA(step.items)
			else
				live.setB(step.items)
				oracle.setB(step.items)
			end
			local after = live.controller.stats()
			if after.ssFullPasses ~= before.ssFullPasses then
				verdict = `step {index} fell back to a whole-tree sync`
				break
			end
			oracle.controller.initialRender()
			local dup = duplicateZ(live)
			if dup ~= "none" then
				verdict = `step {index} (Z2): {dup}`
				break
			end
			if siblingOrder(live) ~= siblingOrder(oracle) then
				verdict = `step {index} (Z1): {siblingOrder(live)} vs {siblingOrder(oracle)}`
				break
			end
		end
		expect(verdict).toBe("clean")
	end)

	it("...and the memo goes with a path that departs and comes back a different size", function()
		--[[ `zOrder.forget` (`renderer.luau`'s removal sweep) — the other half of the
			memo's lifetime, and the one the churn fixture never reaches because it never
			reuses a path. `ForEach` keys the row path by the item, so dropping "b1" and
			bringing it back with a different subtree under it is a path REUSED across a
			remount: a memo that survived would describe the old subtree's span. ]]
		local live = memoScene()
		local oracle = memoScene()
		for _, items in { { "b2" }, { "b1", "b2", "b3", "b4" }, { "b1" } } do
			live.setB(items)
			oracle.setB(items)
			oracle.controller.initialRender()
		end
		expect(`dup:{duplicateZ(live)} order:{siblingOrder(live) == siblingOrder(oracle)}`).toBe("dup:none order:true")
	end)

	it("A THEME IS A THIRD TERM: a snapshot the walk has not seen takes the whole tree", function()
		--[[ The expander reservation is `effectiveHitFloor(node.class, zMetrics)` — the
			CLASS and the theme snapshot — so a package whose metrics move a class's hit
			floor changes what every node of that class reserves, and a skipped subtree
			would keep a numbering with no gap under it. Nothing else covers that: the
			commit's whole-tree re-run fires only when the overhang LIFT SET changes
			(`render/hit_lift`'s `refresh` compares the lifted PAIRS, not the rects), and a
			new expander that overhangs nobody changes no pair. So the walk compares the
			snapshot's IDENTITY with the one it last reserved against, and one it has not
			seen is a forced full walk — conservative by construction, since the
			alternative is a wrong number rather than a slow one.

			DRIVEN ON THE BOUNDED FIXTURE, because that is the only shape where "forced" and
			"bounded" are different numbers: the drive commits a SECOND resolution of the
			framework's own default package (same values, different table — what committing
			a package produces, and the smallest thing an identity test can see). Read off
			the run: the themed sync walks the tree, and the one after it is back to the
			ordinary add bound, which is what says the forced walk was keyed on the snapshot
			rather than a bound that has stopped working. ]]
		local s = scene.new()
		local before = s.stats()
		s.add(1)
		local warm = s.stats()
		s.env:set("themeMetrics", themeSnapshot.resolve(themeSnapshot.neutralPackage(), nil, {}, nil))
		s.add(2)
		local themed = s.stats()
		s.add(3)
		local after = s.stats()
		expect(
			`warm={warm.zVisits - before.zVisits} themed={themed.zVisits - warm.zVisits}`
				.. ` tree={s.census().mounted - PER} next={after.zVisits - themed.zVisits}`
				.. ` full={after.ssFullPasses - before.ssFullPasses}`
			--[[ `themed` is the WHOLE tree as it stands after two adds (`MOUNTED + 2 * PER`),
			and `next` is the ordinary add bound two plates later — the descent, the 252
			surviving plate roots, and the new plate's six. ]]
		).toBe(
			`warm={Z_ADD} themed={MOUNTED + 2 * PER} tree={MOUNTED + 2 * PER}`
				.. ` next={DESCENT + PLATES + 2 + PER} full=0`
		)
		s.dispose()
	end)

	it("A LEAF EARNS NO MEMO ENTRY, and the counter says so — after a departure too", function()
		--[[ THE RULE THAT COST 16 % TO FIND (report §5.1) AND NOTHING TO BREAK. Giving a
			leaf an entry is CORRECT — skipping a leaf and walking it produce the same
			numbers — so no differential can see the guard go, and the +16 % `setState`
			charge would come back silently. `stats.zMemoEntries` is the witness: it is the
			LIVE size of the memo, maintained on the two transitions rather than counted,
			and it must equal the number of nodes that have children.

			Read off the run on the fixture above: 15 mounted nodes with children out of
			`{mounted}` — the Screen, the VStack, the two regions and the eleven rows. ]]
		local live = memoScene()
		--[[ GROW THEN SHRINK, so the count is asked of a surface that has DEPARTED rows
			behind it: the memo of a path that left is cleared by `zOrder.forget` in the
			renderer's removal sweep, and without that line the gauge above ends higher
			than the tree has parents — which is this case's second bite. ]]
		live.setA({ "a1", "a2", "a3", "a4", "a5", "a6" })
		live.setA({ "a1", "a2", "a3" })
		local paths: { string } = {}
		walkPaths(live.root.node, paths)
		local parents = 0
		local function countParents(node: any)
			if node.children ~= nil and #node.children > 0 then
				parents += 1
			end
			for _, child in node.children do
				countParents(child)
			end
		end
		countParents(live.root.node)
		expect(`memo={live.controller.stats().zMemoEntries} parents={parents} mounted={#paths}`).toBe(
			`memo={parents} parents={parents} mounted={#paths}`
		)
	end)
end)

describe("C5: what the bound does NOT survive — a reorder", function()
	it("a reorder renumbers from the insertion point to the end of the parent", function()
		--[[ THE COST OF A REORDER IS DECIDED BY WHERE IT INSERTS, not by how far the item
			travelled, and one monotone counter cannot do better: the moment a subtree's
			old range lies BELOW the counter it has to be renumbered, and so does every
			sibling after it. Near the tail that is almost nothing; near the head it is the
			whole-tree walk again — which is what this cost was BEFORE C5, so it is a
			missing win and not a regression.

			All four read off the run, each on a fresh 250-plate fixture, each `full=0`
			(bounded — the walk is not falling back, it is refusing to skip). They are
			pinned exactly rather than under a ceiling because a `>= mounted` guard passes
			at 1,478 of 1,503, which is how the differential above ran six effectively
			unbounded steps without saying so (T9 review, IMPORTANT 2). ]]
		local function reorder(from: number, to: number): string
			local s = scene.new()
			s.controller.dragRegistry()
			local before = s.stats()
			local rows = table.clone(s.rows:get() :: any)
			table.insert(rows, to, table.remove(rows, from) :: any)
			s.rows:set(rows)
			s.controller.refresh()
			local st = s.stats()
			local out = `{s.stats().zVisits - before.zVisits}`
				.. `/{st.zPasses - before.zPasses}/{st.ssFullPasses - before.ssFullPasses}`
			s.dispose()
			return out
		end
		expect(`tail={reorder(250, 249)} forward={reorder(5, 40)}` .. ` back={reorder(200, 5)} head={reorder(1, 2)}`).toBe(
			"tail=258/1/0 forward=1308/1/0 back=1478/1/0 head=1498/1/0"
		)
	end)
end)

describe("paint order waits for materialized descendants before caching a subtree", function()
	for _, containersPresent in { false, true } do
		it(
			"bounded sync assigns descendants seen before their handles existed, containers present "
				.. tostring(containersPresent),
			function()
				local function node(path, class, children)
					return { path = path, class = class, props = {}, children = children or {} }
				end
				local label = node("/S/TopHome/Center/Bar/Current", "Text")
				local toggle = node("/S/TopHome/Center/Bar/Toggle", "Button")
				local bar = node("/S/TopHome/Center/Bar", "HStack", { label, toggle })
				local center = node("/S/TopHome/Center", "ZStack", { bar })
				local home = node("/S/TopHome", "VStack", { center })
				local root = node("/S", "Screen", { home })
				local nodes = { root, home, center, bar, label, toggle }
				local handles = { [root.path] = {}, [home.path] = {} }
				if containersPresent then
					handles[center.path] = {}
					handles[bar.path] = {}
				end
				local metrics = themeSnapshot.neutral()
				local order = require("../src/render/z_order").new({
					adapter = {
						setZOrder = function(handle, z)
							handle.z = z
						end,
					},
					root = { node = root },
					handles = handles,
					lastZ = {},
					hitLift = { any = false },
					metrics = function()
						return metrics
					end,
					stats = { zMemoEntries = 0, zPasses = 0, zVisits = 0 },
				})
				-- Native geometry/hit-lift can see the mounted tree before ensureTree has
				-- created all its handles. This walk must not make that branch skippable.
				order.sync(nil)
				expect(handles[label.path]).toBeNil()
				for _, entry in nodes do
					if not handles[entry.path] then
						handles[entry.path] = {}
					end
				end
				order.sync({ { path = home.path, node = home } })
				local previous = 0
				for _, entry in nodes do
					local z = handles[entry.path].z
					expect({ path = entry.path, assigned = type(z) == "number" }).toEqual({
						path = entry.path,
						assigned = true,
					})
					expect(z > previous).toBe(true)
					previous = z
				end
			end
		)
	end
end)
