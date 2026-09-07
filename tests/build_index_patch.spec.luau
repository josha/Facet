--!strict
--[[ D2a — A REBUILT CONTAINER PATCHES ITS KEPT CHILDREN ARRAY AT THE DIRTY INDICES.

	T15 gave a container the licence to keep the children array it built last tick, and
	measured that on the five FacetBench arena workloads the arm fires ZERO times: every
	one of their drives writes a signal on a LEAF, `store.dirty` is ancestor-closed, so
	every container on the dirty chain holds a dirty child and the scan falsifies the
	gate. The container then rebuilds a fresh array and re-visits EVERY child — 1,126
	warm store hits on `battle_hud L updateItem-hp`, `toLayoutNode` 0.146 ms of a
	0.364 ms class (FacetBench §D1). Ruling A-9 named the remedy and Plan C deferred it
	for scope. This file is that remedy: the array's VALUES are copied and only the
	indices whose child is dirty are re-run.

	── THE OWED LIST ────────────────────────────────────────────────────────────────
	Everything `toLayoutNode` publishes for a child the patch no longer calls it for,
	and what serves each. Written before the code; the ledger carries the same rows.

	 #  channel                          verdict
	 1  the ARRAY ELEMENT                SERVED BY THE COPY. A clean child's call would
	    (`table.insert(children, …)`)     have taken the warm-hit arm at
	                                     `layout_node.luau`'s entry block and returned
	                                     `hit.built` — the very table already standing
	                                     at that index. `table.move` into a FRESH array
	                                     reproduces it exactly, and the array it reads
	                                     is never written into (T15's owed row 11)
	 2  `store.nodes += hit.n`           SERVED BY ARITHMETIC, and it is the fragile
	                                     part. `nodesAtEntry + prior.n` is "as if every
	                                     child served"; each rebuilt index subtracts the
	                                     size ITS OWN entry recorded (read before the
	                                     rebuild overwrites the entry) and the
	                                     `toLayoutNode` call adds the size it builds.
	                                     `lastLayoutNodes` is pinned UNMOVED in every
	                                     case below
	 3  `store.built` / `lastNodeBuilds` UNCHANGED BY CONSTRUCTION. A clean child SERVES,
	                                     and the serve returns before `store.built += 1`
	                                     — so the counter never saw those children at
	                                     HEAD either. Pinned UNMOVED beside `nodes`
	 4  `store.builtIds` on a            GATED OFF, the same term T15 rides:
	    COLLECTING build                 `store.builtIds == nil`. A structural solve
	                                     spends the list as a licence to SKIP subtrees
	                                     (`structural_scope.widen`) and a patched array
	                                     constructs only the dirty children, so the list
	                                     would be short by every clean one. Case: "a
	                                     build that COLLECTS never patches"
	 5  `store.childVisits`              DELIBERATELY REDUCED — it IS the lever's
	                                     counter (`stats.lastBuildChildVisits`)
	 6  the When/ForEach/ErrorBoundary   SERVED BY THE REGION RECORD, and this is the
	    SPLICE                           term T15's dirty scan used to serve. A dirty
	                                     grandchild marks its region's path too
	                                     (`markDirtyIn` climbs prefixes), so "a region
	                                     under me is dirty" is the shape this arm exists
	                                     for and cannot be the gate. What distinguishes
	                                     a region whose CONTENT moved is that
	                                     `mount.luau` either replaces its children table
	                                     (`:450`, `:218`, `:234`) or `table.remove`s
	                                     from it (`:197`, `:465`) — never anything else
	                                     — so identity AND length, recorded per region
	                                     and re-read per patch, sees every writer. Four
	                                     cases: the two mutation shapes, the lazy pass's
	                                     own stronger check, and the collecting build
	 7  `hit.axis` / `hit.clip` per      SERVED BY `kidsAxis`/`kidsClip`, unchanged from
	    child                            T15: the gate records the pair the children
	                                     were HANDED, so a clean child under an
	                                     unchanged pair would have hit
	 8  `subtreeHasScroll` /             SERVED BY COUNTS ON THE ENTRY, not by booleans.
	    `subtreeHasComposition` /        The post-children fold was three ORs over the
	    `containerRelativeInside`        array; an OR cannot be UNDONE, so a patched
	                                     child that LOSES a mark would leave a stale
	                                     true. The entry carries the POPULATION of each
	                                     mark and the patch subtracts the child it
	                                     replaces before adding the one it built. Case:
	                                     "the container-relative mark FALLS"
	 9  `solver.auditPlacement` over     SERVED BY THE SAME COUNTING. The audit's first
	    the array                        act per child is `if child.placementProps ==
	                                     nil then continue end`, so a container none of
	                                     whose children carries one can only return nil.
	                                     `kidPlaced` is that population; a non-zero
	                                     count still runs the walk. Case: "the placement
	                                     audit"
	10  `cmemo` (ruling A-8)             UNCHANGED. Its gate is `kids`/`axis`/`clip`,
	                                     every term of which the patch's gate already
	                                     requires, so the carrier is preserved exactly
	                                     as it is on the full-rebuild arm at HEAD
	11  NODE IDENTITY for every          PRESERVED AS A THEOREM, and asserted per slot:
	    downstream reader                a clean index holds the SAME table it held, a
	                                     patched index holds a new one, and `#children`
	                                     is unmoved. The three layers of validation are
	                                     the container's own children identity, the
	                                     region records, and — on the pass that builds
	                                     the index — `store.byNode[child].built` being
	                                     the very node at that position
	12  the cost of the patch itself     BOUNDED BY A BUDGET. The dirty SET is walked
	                                     (O(depth) on a leaf edit) instead of the
	                                     children; a dirt set wider than a quarter of
	                                     the array refuses, because rebuilding most of
	                                     the array AND paying the scan is the one way
	                                     this arm could cost more than it saves

	── THE REFUSAL COUNTER ──────────────────────────────────────────────────────────
	`store.patchRefused` lives on the store and NOT on `controller.stats()`, on purpose:
	`renderer.luau` is 28 characters from this campaign's Source-write STOP line and a
	refusal count is not worth a seam. Every refusal case below drives
	`layout_node.build` directly and reads it there; the surface-level cases pin the
	refusal the way the lever is felt instead — `lastBuildChildVisits` staying at the
	whole child count.

	Every count pin carries `solves=N` where it is read off a controller, because a
	drive that solves zero times silently re-asserts the previous solve's counters, and
	`lastLayoutNodes` is pinned in the same block as every counter that moves. Every
	number was read off the run.

	── THE MUTATION BATTERY: 15 RUN, 12 BITE, 3 RECORDED NULLS ──────────────────────
	The three that do not bite are cost-only by construction and are recorded rather
	than chased, because "the mutation did not bite" and "the term is unnecessary" are
	different claims. (a) `kidPlaced` not DECREMENTED on the patch: the count only ever
	drifts upward, so the audit runs a walk it did not need and reports the same nil —
	a lost saving, never a lost finding. (b) the audit gate forced always-on: the same
	statement from the other side. (c) the index not carried forward by the KEPT arm:
	the next patch rebuilds it lazily and answers identically, one walk later. Their
	INVERSES all bite (M10/M11: an increment dropped loses a real finding), which is
	what says the count itself is load-bearing and only its thrift is unwitnessed.

	HOW THESE PINS READ AT THE PARENT SHA (`7b97dd80`): the counter cases are all RED
	there — `visits` reads the whole child count and `store.patchRefused` does not
	exist, so the file does not run. Falsifiability rests on the FacetBench arm C
	(counter kept, mechanism off) and on the mutation battery in the ledger. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/deep_stack_scene")
local device_views = require("./lib/device_views")
local layout_node = require("../src/render/layout_node")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local NEUTRAL = (require("../src/themes/snapshot") :: any).neutral()

local function px(n: number): any
	return { type = "fixed", px = n }
end

-- the same four-field mounted-node stub `node_reuse.spec` and T15 use, repeated for
-- the reason T15 states: these pins are a statement about the PATCH, and a shared
-- helper would make one file's fixture a function of another's
local function stub(class: string, path: string, props: any, children: { any }?): any
	return { class = class, path = path, props = props or {}, children = children or {} }
end

local function leaves(parentPath: string, n: number): { any }
	local out: { any } = {}
	for i = 1, n do
		out[i] = stub("Box", `{parentPath}/c{i}`, { width = px(10), height = px(10) })
	end
	return out
end

local function line(store: any): string
	return `built={store.built} visits={store.childVisits} nodes={store.nodes} refused={store.patchRefused}`
end

describe("D2a: the patch, driven against `layout_node.build` directly", function()
	it("THE HEADLINE: one dirty child costs one visit and the other 999 stand", function()
		local kids = leaves("/r", 1000)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(line(store)).toBe("built=1001 visits=1000 nodes=1001 refused=0")
		--[[ THE LEAF-EDIT DIRTY SET, spelled out as `markDirtyIn` produces it: the child
			and its ancestor. This is the shape T15's scan refuses on, and at
			`7b97dd80` it costs the whole thousand-visit loop. ]]
		local second = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c500"] = true })
		expect(line(store)).toBe("built=2 visits=1 nodes=1001 refused=0")
		-- owed row 11, per slot: one new table, every other the same table
		expect(second.children[500]).never().toBe(first.children[500])
		expect(second.children[499]).toBe(first.children[499])
		expect(second.children[1000]).toBe(first.children[1000])
		expect(second.children).never().toBe(first.children)
		expect(`kids={#second.children}`).toBe("kids=1000")
	end)

	it("THE INDEX IS OVER THE SPLICED POSITIONS, not over the mount children", function()
		--[[ OWED ROW 6. `appendChild` splices a region's children into the parent's
			flow, and on every arena workload the thousand-child loop IS such a splice —
			one `UI.ForEach` under a stack. An index over `node.children` would be an
			index over ONE region and would reach nothing, so the index is built over the
			flat list the splice produces and keyed by the GRANDCHILD's path. ]]
		local inner = leaves("/r/F", 20)
		local region = stub("ForEach", "/r/F", {}, inner)
		local root = stub("VStack", "/r", {}, { region })
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(line(store)).toBe("built=21 visits=20 nodes=21 refused=0")
		-- the region's own path is dirty by ancestor closure, and that is NOT a refusal
		local second =
			layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=2 visits=1 nodes=21 refused=0")
		expect(second.children[7]).never().toBe(first.children[7])
		expect(second.children[6]).toBe(first.children[6])
		expect(`id={second.children[7].id} kids={#second.children}`).toBe("id=/r/F/c7 kids=20")
	end)

	it("a region whose children table is REPLACED refuses, and the whole loop runs", function()
		--[[ OWED ROW 6, `mount.luau:450`/`:218`/`:234`. The recorded region triple is
			(node, children table, length); a wholesale replacement moves the identity,
			which the patch re-reads off the region node on every tick without walking
			anything. Driven on a build where the INDEX already exists, so it is the
			recorded triple doing the work and not the lazy pass's stronger check. ]]
		local inner = leaves("/r/F", 20)
		local region = stub("ForEach", "/r/F", {}, inner)
		local root = stub("VStack", "/r", {}, { region })
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		-- tick 2 builds the index and patches
		layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=2 visits=1 nodes=21 refused=0")
		-- ...and now the reconciler's wholesale replacement, with the SAME children
		local swapped: { any } = {}
		table.move(inner, 1, 20, 1, swapped)
		region.children = swapped
		layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=2 visits=20 nodes=21 refused=1")
	end)

	it("a region that loses an element IN PLACE refuses, which identity alone cannot see", function()
		--[[ OWED ROW 6, `mount.luau:197`/`:465` — the two exit-finish sites, where
			`table.remove` mutates the region's array on a frame of the coordinator's
			choosing and no table anywhere changes identity. Length is what sees it, and
			it is exact because `table.remove` is the ONLY in-place writer in the mount
			layer: there is no in-place insertion and no in-place replacement. ]]
		local inner = leaves("/r/F", 20)
		local region = stub("ForEach", "/r/F", {}, inner)
		local root = stub("VStack", "/r", {}, { region })
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=2 visits=1 nodes=21 refused=0")
		table.remove(inner, 20)
		local shrunk =
			layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=2 visits=19 nodes=20 refused=1")
		expect(`kids={#shrunk.children}`).toBe("kids=19")
	end)

	it("NEGATIVE CONTROL 1: the lazy pass refuses slots whose mounted child has no entry", function()
		--[[ OWED ROW 11, LAYER 3, the `entry == nil` half. Before a container has an
			index there is nothing recorded to compare, so the pass that BUILDS the index
			verifies every slot the harder way — `store.byNode[child].built` must be the
			very layout node standing at that position. Here the region's children are
			replaced with a fresh set of stubs at the IDENTICAL paths, which no path- or
			length-keyed check could tell from the originals, and the entries they would
			need do not exist. ]]
		local region = stub("ForEach", "/r/F", {}, leaves("/r/F", 20))
		local root = stub("VStack", "/r", {}, { region })
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		region.children = leaves("/r/F", 20) -- same paths, different tables
		local built =
			layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=21 visits=20 nodes=21 refused=1")
		expect(`kids={#built.children}`).toBe("kids=20")
	end)

	it("NEGATIVE CONTROL 2: ...and slots whose entry exists but describes a DIFFERENT position", function()
		--[[ THE OTHER HALF, and the mutation that showed control 1 could not reach it:
			with `entry == nil` alone the term looks sufficient, because a fresh stub has
			no entry. A REORDER has an entry for every child — it is the same twenty
			mounted nodes — and only `entry.built ~= childArray[n]` sees that position 1
			now holds the node whose layout tree is standing at position 20. Serve that
			and every downstream reader that walks `children` (focus order, the commit's
			document order, `mIds`) gets last tick's sequence, forever. ]]
		local inner = leaves("/r/F", 20)
		local region = stub("ForEach", "/r/F", {}, inner)
		local root = stub("VStack", "/r", {}, { region })
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local swapped: { any } = {}
		table.move(inner, 1, 20, 1, swapped)
		swapped[1], swapped[20] = swapped[20], swapped[1]
		region.children = swapped
		local built =
			layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=2 visits=20 nodes=21 refused=1")
		expect(`{built.children[1].id},{built.children[20].id}`).toBe("/r/F/c20,/r/F/c1")
		expect(`was={first.children[1].id}`).toBe("was=/r/F/c1")
	end)

	it("NEGATIVE CONTROL 3: ...and a CLEAN slot whose mounted child has no entry at all", function()
		--[[ THE THIRD SHAPE, and the mutation that showed control 1 could not reach it
			either: control 1 replaces every child, so the DIRTY one is among them and
			`patchIndices`' own missing-entry refusal on the dirty index catches it
			without the lazy pass's `entry == nil` term ever mattering. Replace ONE CLEAN
			slot instead and no dirty-index check can see it — the patch would copy the
			layout node the old child built and hand it to a mounted node that never
			produced it. ]]
		local inner = leaves("/r/F", 20)
		local region = stub("ForEach", "/r/F", {}, inner)
		local root = stub("VStack", "/r", {}, { region })
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local swapped: { any } = {}
		table.move(inner, 1, 20, 1, swapped)
		swapped[12] = stub("Box", "/r/F/c12", { width = px(10), height = px(10) })
		region.children = swapped
		layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/F"] = true, ["/r/F/c7"] = true })
		expect(line(store)).toBe("built=3 visits=20 nodes=21 refused=1")
	end)

	it("the placement audit fires on the FULL pass too, off the same count", function()
		--[[ The count is the audit's gate on EVERY arm, so the full-rebuild arm has to
			fill it or a container built cold would never report an inert prop. Its own
			case because the patch case starts from a container that carries none. ]]
		local kids = leaves("/r", 8)
		kids[3].props = { width = px(10), height = px(10), anchor = "topLeft" }
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local found = (first :: any).inertPlacement
		expect(`inert={if found == nil then "nil" else `{#found}:{found[1].node}`}`).toBe("inert=1:/r/c3")
	end)

	it("the scroll and composition marks track the patched child, in both directions", function()
		--[[ OWED ROW 8's other two counts. `subtreeHasScroll` and
			`subtreeHasComposition` gate the measure serve, so a stale TRUE costs the
			serve tree-wide and a stale FALSE serves a node whose ScrollView or
			Composition publishes a channel the served tuple cannot carry
			(`tests/measure_serve.spec.luau` carries the channel table). Driven at the
			seam because the FALL direction needs a container to lose a marked
			descendant, which in production is a region reconcile — a structural build,
			which refuses the patch — so this is the only witness the arithmetic can
			have, and it is recorded rather than asserted. ]]
		local kids = leaves("/r", 20)
		local scroller = stub("ScrollView", "/r/c7/s", { axis = "y" }, {})
		local composed = stub("Composition", "/r/c9/z", {}, {})
		kids[7] = stub("VStack", "/r/c7", {}, { scroller })
		kids[9] = stub("VStack", "/r/c9", {}, { composed })
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(`scroll={tostring(first.subtreeHasScroll)} comp={tostring(first.subtreeHasComposition)}`).toBe(
			"scroll=true comp=true"
		)
		kids[7].children = {}
		kids[9].children = {}
		local fallen =
			layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c7"] = true, ["/r/c9"] = true })
		expect(line(store)).toBe("built=3 visits=2 nodes=21 refused=0")
		expect(`scroll={tostring(fallen.subtreeHasScroll)} comp={tostring(fallen.subtreeHasComposition)}`).toBe(
			"scroll=nil comp=nil"
		)
		kids[7].children = { scroller }
		kids[9].children = { composed }
		local back =
			layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c7"] = true, ["/r/c9"] = true })
		expect(
			`scroll={tostring(back.subtreeHasScroll)} comp={tostring(back.subtreeHasComposition)} visits={store.childVisits}`
		).toBe("scroll=true comp=true visits=4")
	end)

	it("THE BUDGET: a dirt set wider than a quarter of the array refuses", function()
		--[[ OWED ROW 12. The patch walks the DIRTY SET, so a wide dirt set costs a scan
			the full pass does not pay — and if most of the array is going to be rebuilt
			anyway, that scan is pure loss. The budget is `max(4, n // 4)`: with 20
			children, five dirty children patch and six refuse. Read off the run. ]]
		local kids = leaves("/r", 20)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local five: { [string]: boolean } = { ["/r"] = true }
		for i = 1, 5 do
			five[`/r/c{i}`] = true
		end
		layout_node.build(store, root, NEUTRAL, 1, 0, five)
		expect(line(store)).toBe("built=6 visits=5 nodes=21 refused=0")
		local six = table.clone(five)
		six["/r/c6"] = true
		layout_node.build(store, root, NEUTRAL, 1, 0, six)
		expect(line(store)).toBe("built=7 visits=20 nodes=21 refused=1")
	end)

	it("a build that COLLECTS never patches, so `builtIds` describes the whole subtree", function()
		--[[ OWED ROW 4, the same term T15's kept array rides. The gate refuses BEFORE
			the patch is attempted, which is why `refused` stays 0: a refusal counted
			here would be counting the structural solve, not a patch that could not be
			validated. ]]
		local kids = leaves("/r", 20)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c3"] = true }, true)
		expect(line(store)).toBe("built=2 visits=20 nodes=21 refused=0")
		expect(`ids={#(store.builtIds :: any)}`).toBe("ids=2")
	end)

	it("the container-relative mark FALLS when the patched child loses it", function()
		--[[ OWED ROW 8, and it is why the entry carries POPULATIONS and not booleans. An
			OR over the array cannot be undone: a patch that only ORed the rebuilt child's
			marks into the previous answer would leave `containerRelativeInside` true
			forever once any child had ever carried it, and the solver refuses its arrange
			skip for a marked subtree — a permanent, silent loss of the skip. `crelLater`
			in `deep_stack_scene` is the production drive of exactly this flip. ]]
		local kids = leaves("/r", 20)
		kids[7] = stub("Box", "/r/c7", { width = { type = "containerRelative", fraction = 0.5 }, height = px(10) })
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(`inside={tostring(first.containerRelativeInside)}`).toBe("inside=true")
		kids[7].props = { width = px(10), height = px(10) }
		local second = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c7"] = true })
		expect(line(store)).toBe("built=2 visits=1 nodes=21 refused=0")
		expect(`inside={tostring(second.containerRelativeInside)}`).toBe("inside=nil")
		-- ...and back, which is the ADD half of the same arithmetic
		kids[7].props = { width = { type = "containerRelative", fraction = 0.5 }, height = px(10) }
		local third = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c7"] = true })
		expect(`inside={tostring(third.containerRelativeInside)} visits={store.childVisits}`).toBe(
			"inside=true visits=1"
		)
	end)

	it("the placement audit's population is counted, and a patched child that gains one is audited", function()
		--[[ OWED ROW 9. `auditPlacement` walks the array to reject each child on one
			field; `kidPlaced` hoists that rejection out of the loop, so a container whose
			children carry no placement prop answers nil without a walk. The count has to
			MOVE with the patch or a newly-inert prop would never be reported. ]]
		local kids = leaves("/r", 20)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(`inert={tostring(first.inertPlacement)}`).toBe("inert=nil")
		-- `anchor` is read by an `anchor` parent and by nothing a vstack does
		kids[7].props = { width = px(10), height = px(10), anchor = "topLeft" }
		local second = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c7"] = true })
		expect(line(store)).toBe("built=2 visits=1 nodes=21 refused=0")
		local found = (second :: any).inertPlacement
		expect(`inert={if found == nil then "nil" else `{#found}:{found[1].node}:{found[1].filedBy}`}`).toBe(
			"inert=1:/r/c7:/r"
		)
		-- ...and it goes away again when the prop does
		kids[7].props = { width = px(10), height = px(10) }
		local third = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c7"] = true })
		expect(`inert={tostring((third :: any).inertPlacement)} visits={store.childVisits}`).toBe("inert=nil visits=1")
	end)
end)

--[[ ── THE PUBLISHED COUNTER, ON REAL SURFACES ─────────────────────────────────
	`deep_stack_scene`'s LEAF drives are the ones this lever exists for, and they are
	the drives T15 measured as unreachable. `lastNodeBuilds` and `lastLayoutNodes` are
	pinned in the same string as `visits` in every case: the patch's whole risk is the
	`store.nodes` arithmetic, and those two are what an off-by-one subtree would move. ]]
local function statLine(s: any, before: any): string
	local st = s.stats()
	return `solves={st.solves - before.solves} visits={st.lastBuildChildVisits} builds={st.lastNodeBuilds} nodes={st.lastLayoutNodes}`
end

describe("D2a: the counter, on the thousand-row list", function()
	it("THE HEADLINE: a leaf write visits one child per container on the dirty chain", function()
		local s = scene.new({ rows = 1000 })
		s.text(1, "warm") -- the warm-up drive, discarded
		local before = s.stats()
		s.text(500, "x")
		expect(statLine(s, before)).toBe("solves=1 visits=3 builds=4 nodes=3002")
		--[[ A WIDTH WRITE on the row itself, which is measure-classed on the ROW rather
			than on its text leaf — a shorter dirty chain, and the same one visit per
			container on it. ]]
		before = s.stats()
		s.width(500, 40)
		expect(statLine(s, before)).toBe("solves=1 visits=2 builds=3 nodes=3002")
		s.dispose()
	end)

	it("...and a SPLICED region under the list is indexed at its grandchildren", function()
		--[[ The production shape: `List` holds a `UI.ForEach` whose rows are spliced
			into its flat child list, so a write inside a spliced row marks the region's
			own path by ancestor closure and the patch must index PAST it. The structural
			steps beside it are the refusal: an insert is a collecting build. ]]
		local s = scene.new({ rows = 200, foreach = true })
		s.insertItem("k1")
		s.insertItemKind("k2", "text")
		local before = s.stats()
		s.text(50, "x")
		expect(statLine(s, before)).toBe("solves=1 visits=3 builds=4 nodes=606")
		before = s.stats()
		s.insertItem("k3")
		expect(statLine(s, before)).toBe("solves=1 visits=206 builds=3 nodes=607")
		-- ...and the tick after the structural one patches again from a fresh index
		before = s.stats()
		s.text(50, "y")
		expect(statLine(s, before)).toBe("solves=1 visits=3 builds=4 nodes=607")
		s.dispose()
	end)
end)

--[[ ── THE WALK THE OUTPUT BUDGET DID NOT BOUND (Plan D, D3b) ──────────────────
	`patchIndices` walks `store.dirty` — the WHOLE pass's dirt, not this container's
	share of it — and until D3b the only budget on it capped what it RETURNED. On a
	narrow leaf edit the two are the same thing: the dirty set IS the ancestor chain.
	On a WIDE push they are not, and Plan D's own cutoff sweep is where that surfaced:
	1,000 settled text leaves delivered at once put ~2,000 entries in the set, every one
	of the 1,000 rebuilt two-child rows read all 2,000 to find its single dirty child,
	and the push route went from 24.2 ms at the Plan D base to 62.6 ms at `aeaf17de`
	(`.superpowers/.../d3b/cutoff-*.txt`; D2c's twin walk in `layout/stack` is the
	larger half and `tests/stack_replay_candidates.spec.luau` pins that one).

	`store.patchProbes` is the counter, and it is the only one that can see this: a
	container that walks two thousand entries and then patches successfully leaves
	`patchRefused` at 0, `childVisits` at 1 and every other number exactly where the
	narrow case leaves it. The cases below pin the walk and the fallback TOGETHER,
	because the fix is a TRADE — the wide arm now pays `visits` it did not pay before
	(the full pass, which is the pre-D2a arm verbatim) to stop paying probes. ]]
describe("D3b: the dirty-set WALK is bounded, not only the array it rebuilds", function()
	-- one thousand two-child rows under one list: the sweep's shape, without the text
	-- route, so the dirt is exactly what the drive names and nothing else
	local function rowTree(): (any, { [string]: boolean }, { [string]: boolean })
		local rows: { any } = {}
		local wide: { [string]: boolean } = { ["/r"] = true }
		for i = 1, 1000 do
			local a = stub("Box", `/r/row{i}/a`, { width = px(10), height = px(10) })
			local b = stub("Box", `/r/row{i}/b`, { width = px(10), height = px(10) })
			rows[i] = stub("HStack", `/r/row{i}`, {}, { a, b })
			wide[`/r/row{i}`] = true
			wide[`/r/row{i}/a`] = true
		end
		return stub("VStack", "/r", {}, rows), wide, { ["/r"] = true, ["/r/row500"] = true, ["/r/row500/a"] = true }
	end

	it("THE HEADLINE: a wide push reads a bounded slice of the dirty set, not all of it", function()
		local root, wide, narrow = rowTree()
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(`{line(store)} probes={store.patchProbes}`).toBe("built=3001 visits=3000 nodes=3001 refused=0 probes=0")
		--[[ THE NARROW DRIVE FIRST, on the same tree, as the control: three dirty paths,
			two containers on the chain, three probes each, and the patch serves both. This
			is the case the budget must not touch and the number the wide drive is read
			against. ]]
		layout_node.build(store, root, NEUTRAL, 1, 0, narrow)
		expect(`{line(store)} probes={store.patchProbes}`).toBe("built=3 visits=2 nodes=3001 refused=0 probes=6")
		--[[ ...AND THE WIDE ONE. 2,001 dirty paths, 1,001 containers, and 1,001 probes
			for the whole pass: the list is built first and its budget is its child count,
			so its walk stops at 1,001 and every row under it — budget 64, the floor —
			refuses on that recorded bound without walking at all. The battery prices the
			two guards separately: without the per-pass bound this drive reads 66,001 (65
			per container), without the early return 2,001 (the whole set, once), and
			without either the product of them. What it costs instead is the FULL PASS at every refusing
			container, 3,000 visits, which is exactly what T15 and the pre-D2a build spent
			on the same tree (the mount line above). ]]
		layout_node.build(store, root, NEUTRAL, 1, 0, wide)
		expect(`{line(store)} probes={store.patchProbes}`).toBe(
			"built=2001 visits=3000 nodes=3001 refused=1001 probes=1001"
		)
	end)

	it("the budget is spent BEFORE the index is, so a refusing tick has paid nothing", function()
		--[[ `stack_measure`'s owed row A10 states the rule and this is the same one: the
			bare count runs ahead of `indexKids`, so the wide arm never builds the
			path->index map or re-reads the region triples. The witness is the LAZY index
			itself — after a wide-only tick the container still has no index, so the next
			NARROW tick is the one that builds it, three probes per container on the chain
			and six for the pass, exactly what the same drive costs on a store that never
			saw the wide one. ]]
		local root, wide, narrow = rowTree()
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		layout_node.build(store, root, NEUTRAL, 1, 0, wide)
		local prior = store.byNode[(root :: any).children[500]]
		expect(`index={tostring(prior.kidIndex)} refused={store.patchRefused}`).toBe("index=nil refused=1001")
		layout_node.build(store, root, NEUTRAL, 1, 0, narrow)
		expect(`{line(store)} probes={store.patchProbes}`).toBe("built=3 visits=2 nodes=3001 refused=0 probes=6")
		expect(`index={tostring(prior.kidIndex ~= nil)}`).toBe("index=true")
	end)
end)

--[[ ── THE PRODUCTION DIRT SHAPE ───────────────────────────────────────────────
	The arena workloads put the THOUSAND ROWS THEMSELVES inside one `UI.ForEach` and
	drive a per-item signal on one row's leaf (`FacetBench/frameworks/facet/NOTES.md`
	branch 2). `deep_stack_scene`'s `foreach` arm is a small region BEFORE its rows, so
	it cannot be that shape — this fixture is, and it is where `lastBuildChildVisits`
	falls from the whole list to the dirty chain. ]]
local function foreachRows(rows: number)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
	local items: { any } = {}
	local signals: { any } = {}
	for i = 1, rows do
		signals[i] = core:signal(`row {i}`)
		items[i] = { key = `k{i}`, at = i }
	end
	local list = core:signal(items)
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "List",
					gap = 2,
					children = {
						UI.ForEach({
							id = "F",
							items = list,
							key = function(item: any): string
								return item.key
							end,
							row = function(item: any)
								return UI.HStack({
									id = "Row",
									children = {
										UI.Text({ id = "T", textSize = 12, text = signals[item.at] }),
										UI.Box({ id = "B", width = px(12), height = px(8) }),
									},
								})
							end,
						}),
					},
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return { core = core, root = root, controller = controller, signals = signals, list = list }
end

describe("D2a: the production dirt shape — the rows ARE the region's children", function()
	it("a per-item signal on one row visits the dirty chain and not the list", function()
		local arm = foreachRows(200)
		arm.signals[7]:set("warm")
		arm.controller.refresh()
		local before = arm.controller.stats()
		arm.signals[7]:set("moved")
		arm.controller.refresh()
		local st = arm.controller.stats()
		expect(
			`solves={st.solves - before.solves} visits={st.lastBuildChildVisits} builds={st.lastNodeBuilds} nodes={st.lastLayoutNodes}`
		).toBe("solves=1 visits=3 builds=4 nodes=602")
		arm.root.dispose()
	end)
end)

--[[ ── THE DIFFERENTIAL ORACLE ─────────────────────────────────────────────────
	The switch-independent arm, per the campaign rule: arm `c` forces a FULL solve every
	refresh, where `dirty` reaches `build` as nil, `store.byNode` is replaced and this
	whole mechanism is structurally unreachable. Arm `b` throws the cross-solve measure
	slates away and keeps the incremental arrange, so it exercises the patch under a
	different measure regime. The drives are LEAF writes — the shape the patch serves,
	which T15's own oracle drove only incidentally — interleaved with the container-prop
	writes that take the kept-array arm and, on the `foreach` fixture, with structural
	inserts that refuse both.

	`listWidth+label` is in the set because a `text` node spliced among the rows is the
	one child of `List` whose measure the container memo must refuse on every tick, and
	it is a child the patch may rebuild. ]]
local ORACLE_ROWS = 12

local function arms(view: any, opts: any): (any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base)
	local b = table.clone(base)
	b.measureReuse = false
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false
	return scene.new(a), scene.new(b), scene.new(c)
end

describe("D2a oracle: byte-equal to a full solve, every view", function()
	local FIXTURES: { any } = {
		{ name = "leaf", rows = ORACLE_ROWS, listWidth = true },
		{ name = "leaf+foreach", rows = ORACLE_ROWS, listWidth = true, foreach = true },
		{ name = "leaf+label+nested", rows = ORACLE_ROWS, listWidth = true, label = true, nested = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects and the public readers survive the patched array`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				local function agree(step: string)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {step} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= b.snapshot() then
						error(`{label}: {step} diverged from the slate-less solve`, 0)
					end
				end
				agree("mount")
				for step = 1, 3 do
					a.text(step + 1, `t{step}`)
					b.text(step + 1, `t{step}`)
					c.text(step + 1, `t{step}`)
					agree(`text {step}`)
					a.width(step + 2, 20 + step)
					b.width(step + 2, 20 + step)
					c.width(step + 2, 20 + step)
					agree(`width {step}`)
					a.listWidth(300 + step * 11)
					b.listWidth(300 + step * 11)
					c.listWidth(300 + step * 11)
					agree(`listWidth {step}`)
					if fixture.foreach then
						a.insertItem(`k{step}`)
						b.insertItem(`k{step}`)
						c.insertItem(`k{step}`)
						agree(`insert {step}`)
						a.text(step + 1, `u{step}`)
						b.text(step + 1, `u{step}`)
						c.text(step + 1, `u{step}`)
						agree(`text after insert {step}`)
						a.removeItem(`k{step}`)
						b.removeItem(`k{step}`)
						c.removeItem(`k{step}`)
						agree(`remove {step}`)
					end
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)
