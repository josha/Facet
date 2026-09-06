--!strict
--[[ T15 — A REBUILT CONTAINER KEEPS THE CHILDREN ARRAY IT BUILT LAST TICK.

	P3's store answers a CLEAN container in two hash probes and returns its whole
	subtree (`render/layout_node.luau`'s warm-hit arm). A container that MISSES pays a
	different bill: a fresh array, a fresh `appendChild` closure over eight upvalues,
	and one `toLayoutNode` call plus one `table.insert` for every child — where almost
	every one of those calls is itself a warm hit that constructs nothing. So
	`lastNodeBuilds` reads 2 while the loop underneath it runs a thousand times, and
	no counter this framework had could see that. `lastBuildChildVisits` is that
	number, and this file is the mechanism that removes it.

	── THE OWED LIST ────────────────────────────────────────────────────────────────
	Every channel the rebuild loop spends per child, and what serves it when the array
	is kept instead. Written before the code; the ledger carries the same twelve rows.

	 #  channel                          verdict
	 1  `store.nodes += hit.n` per child SERVED BY THE CONTAINER'S OWN `n`. The entry
	                                     records `n = store.nodes - nodesAtEntry`, so
	                                     `store.nodes = nodesAtEntry + prior.n` is the
	                                     same arithmetic done once. Case: "the reused
	                                     array costs the store exactly the subtree it
	                                     stands for"
	 2  `store.built`/`nodes` for the    UNCHANGED. Only the child loop is bounded, so
	    CONTAINER                        `lastNodeBuilds` falls by the children and
	                                     never by the container
	 3  `builtIds` collection            GATED OFF: `store.builtIds == nil` is a term
	                                     of the predicate. A structural solve spends
	                                     the list as a licence to SKIP subtrees
	                                     (`render/structural_scope.widen`), and a
	                                     reused array constructs no child, so the list
	                                     would be short by the whole subtree. Case: "a
	                                     build that COLLECTS never reuses"
	 4  the When/ForEach/ErrorBoundary   SERVED BY THE `store.dirty` CHILD SCAN. A
	    splice in `appendChild`          region's children are replaced wholesale at
	                                     `mount.luau:450` and mutated IN PLACE at
	                                     `:197` (When exit-finish) and `:465` (ForEach
	                                     exit-finish), each followed by
	                                     `pushDirty(path, "structure")` (`:202`,
	                                     `:470`). `renderer.luau`'s `markDirtyIn` walks
	                                     path string PREFIXES, so the region's own path
	                                     is in `store.dirty` whenever any descendant
	                                     is. Two cases, one per exit-finish site
	 5  `hit.axis`/`hit.clip` per child  ▲ NOT SERVED, AND THE PLAN SAID IT WAS. The
	                                     claim was "`childAxis` is a pure function of
	                                     `kind`, and `kind` is fixed for a mounted
	                                     node". `kind` is NOT fixed:
	                                     `AdaptiveStack.axis`
	                                     (`layout_node.luau:529`), `wrap` on a
	                                     `VStack`/`HStack` (`:523`, `:544`) and a
	                                     `Button` gaining children (`:560`) are
	                                     prop-decides-kind seams that RE-SOLVE AND
	                                     NEVER REMOUNT. So the pair a container hands
	                                     its children is recorded as `kidsAxis`/
	                                     `kidsClip` and compared. The first version
	                                     shipped without it and `tests/adaptive.spec`'s
	                                     "follows an AdaptiveStack's axis flip with no
	                                     rebuild" went red with a Divider 280px wide
	                                     where it must be 1. The container's own
	                                     `axis`/`clip` are kept beside them because
	                                     this is the same entry gate the `cmemo`
	                                     carrier rides, but `parentAxis` is not an
	                                     input to any child, so that half is
	                                     conservative and the cases say which is which
	 6  `hostSpace` (`instance_boundary  NOT RE-RESOLVED AT HEAD EITHER. A clean child
	    .createOptsFor`)                 is a warm hit that returns the layout node
	                                     built on an earlier tick with `hostSpace`
	                                     already stamped; the arm removes the two hash
	                                     probes that reached it, not a resolution
	 7  `textOf` and the (font,size)     NOT A BUILD-TIME CHANNEL. The index is written
	    text index (T18-A)               at MEASURE time (`solver.luau`'s
	                                     `ctx.textIndex.record`). A kept array holds
	                                     the SAME layout nodes, so the solver walks and
	                                     re-registers exactly what it walked at HEAD.
	                                     Case: "A SETTLE OVER A KEPT ARRAY", which
	                                     drives an unmeasured word over an array the
	                                     previous tick kept and compares the surface
	                                     against ITSELF rebuilt from scratch
	 8  `analyzeBoundaries` inputs       NOT A CONSUMER. `controller.analyzeBoundaries`
	                                     re-solves the layout root the last build
	                                     produced; it never calls `layout_node.build`.
	                                     See the A-9 answer in the task report
	 9  `auditPlacement` and the         RUN OVER THE REUSED ARRAY AND ANSWER
	    `subtreeHasScroll`/`Composition` IDENTICALLY: both read the array AFTER the
	    /`containerRelativeInside` fold  block, and only fields of the child layout
	                                     nodes, which are the same tables
	10  NODE IDENTITY for every          PRESERVED AS A THEOREM. Reuse fires only when
	    downstream reader                the entry exists (so every child had one), the
	                                     mount children table is the SAME OBJECT, and
	                                     no mount child is in `store.dirty`. Under
	                                     those terms every child's own `toLayoutNode`
	                                     would have taken the warm-hit arm and returned
	                                     the very table already in the array. A LENGTH
	                                     compare would accept a swap and hand a reader
	                                     a lost or duplicated node
	11  THE ARRAY IS NEVER MUTATED       Once reused it is shared between two layout
	    AFTER PUBLICATION                nodes across ticks, so an in-place edit is a
	                                     cross-tick aliasing bug. Pinned by source scan
	12  the gate's OWN residual          BOOKED BEFORE THE RUN, and it is the finding.
	                                     See below

	── WHAT THIS ARM CAN REACH, AND WHAT IT PROVABLY CANNOT ─────────────────────────
	`store.dirty` is ancestor-closed over path prefixes. So a container holding a dirty
	DESCENDANT always fails the scan, and a container holding none never arrives here
	at all — it is served whole by the warm-hit arm. The arm therefore fires for
	exactly one shape: **a container dirtied for its OWN reasons whose every child
	subtree is clean** — an animating panel width, a gap or padding that moves with a
	theme, a sidebar that resizes over a static list. On the 1,000-row fixture below
	that is `lastBuildChildVisits` 1,003 -> 1.

	It is ALSO why the five FacetBench arena workloads never reach it: every one of
	their drives writes a signal on a LEAF, so the container that owns the thousand-
	child loop is on that leaf's dirty ancestor chain. Measured at this commit with a
	temporary census, all five workloads, every step kind: the arm fires ZERO times and
	its refusal costs 0-6 extra hash probes a solve (128 on `nameplates updateItems`,
	against 374 child visits). The arena has no workload whose CONTAINER prop moves.
	That is a gap in the arena, not a dead mechanism, and the task report carries both
	numbers rather than one.

	── THE COUNTER'S OWN NUMBER ─────────────────────────────────────────────────────
	`lastBuildChildVisits` counts one `toLayoutNode` call per position the rebuild loop
	visited — spliced regions counted at the grandchildren they contribute and never at
	the region itself, because a region has no layout node. It is NOT `lastNodeBuilds`:
	almost every visit is a warm hit that constructs nothing, which is exactly why
	`lastNodeBuilds` cannot see the loop.

	Every count pin below carries `solves=N`, because a drive that solves ZERO times
	silently re-asserts the previous solve's counters, and `lastLayoutNodes` is pinned
	UNMOVED in the same block as every counter that moves — a kept array that lost or
	duplicated a node would move it. Every number was read off the run at this commit
	with the warm-up drive discarded. ]]

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

--[[ THE SMALLEST MOUNTED-NODE SHAPE `layout_node.build` ACCEPTS — `class`, `path`,
	`props`, `children` are the only four fields it reads (`node_reuse.spec`'s own
	`stub`, repeated rather than shared because that file's pins are a statement about
	the STORE and these are a statement about the child LOOP; a shared helper would
	make one file's fixture a function of the other's). It is the only way to drive
	the two gate terms a blueprint cannot reach — a container whose parent AXIS moved,
	and one that ENTERED a clipper — for the reason `node_reuse.spec` states: the
	mount layer's identity model forbids re-parenting a mounted node. ]]
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

describe("T15: the gate, driven against `layout_node.build` directly", function()
	it("a container dirtied for its OWN reasons keeps the array, and every child table with it", function()
		local kids = leaves("/r", 8)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(`built={store.built} visits={store.childVisits} nodes={store.nodes}`).toBe("built=9 visits=8 nodes=9")
		--[[ THE DIRTY SET IS THE RENDERER'S, SPELLED OUT: the container's own path and
			nothing below it — what `markDirtyIn` produces for a prop write on the
			container itself. ]]
		local second = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true })
		expect(`built={store.built} visits={store.childVisits} nodes={store.nodes}`).toBe("built=1 visits=0 nodes=9")
		-- owed row 10: the array is the SAME TABLE and holds the SAME child nodes
		expect(second.children).toBe(first.children)
		expect(second).never().toBe(first)
		local same = true
		for i, child in first.children do
			if second.children[i] ~= child then
				same = false
			end
		end
		expect(`children={#second.children} identical={same}`).toBe("children=8 identical=true")
	end)

	it("a DIRTY CHILD refuses the arm, and the clean siblings are still served one by one", function()
		local kids = leaves("/r", 8)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local second = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true, ["/r/c3"] = true })
		expect(`built={store.built} visits={store.childVisits} nodes={store.nodes}`).toBe("built=2 visits=8 nodes=9")
		expect(second.children).never().toBe(first.children)
		expect(second.children[3]).never().toBe(first.children[3])
		expect(second.children[4]).toBe(first.children[4])
	end)

	it("a build that COLLECTS never reuses, so `builtIds` describes the whole subtree", function()
		--[[ OWED ROW 3. `builtIds` is the STRUCTURAL solve's licence to skip subtrees
			(`render/structural_scope.widen`, called from `renderer.luau` with
			`nodeStore.builtIds`), and its COMPLEMENT is what that pass trusts. A reused
			array constructs no child, so a collecting build that took this arm would
			hand the widen a list short by the whole subtree and the pass would skip
			nodes it had to visit. `collect` is `build`'s seventh parameter and its ONE
			caller passes `structural ~= nil`. ]]
		local kids = leaves("/r", 8)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true }, true)
		--[[ `ids=1` and not 9 IS THE POINT, and it is the arithmetic that makes the
			gate necessary. `builtIds` records CONSTRUCTED nodes, and the eight children
			are clean, so each is a warm hit that records nothing — the list holds the
			container alone. `visits=8` is what says the arm refused: had it reused, the
			loop would not have run and the eight warm hits would not have happened, so
			`structural_scope.widen` would be handed the identical list while the tree
			it describes had never been walked. ]]
		expect(`visits={store.childVisits} ids={#(store.builtIds :: any)}`).toBe("visits=8 ids=1")
	end)

	it("AXIS: a container whose PARENT AXIS moved rebuilds its array", function()
		--[[ OWED ROW 5, and it is driven here because the mount layer cannot produce
			it: `parentAxis` and `insideClipper` ride the recursion, so a container can
			need a different tree with no prop and no child having moved. The children
			were built with `childAxis`, a pure function of the CONTAINER's `kind`, so
			the container's own `axis` term is what stands between them and a tree built
			for the wrong flow. ]]
		local mid = stub("VStack", "/r/m", {}, leaves("/r/m", 6))
		local row = stub("HStack", "/r", {}, { mid })
		local store = layout_node.newStore()
		layout_node.build(store, row, NEUTRAL, 1, 0, nil)
		expect(`visits={store.childVisits}`).toBe("visits=7")
		-- the same `mid` TABLE under a vertical parent: the warm hit refuses on
		-- `hit.axis`, the rebuild reaches the arm, and the arm refuses on `prior.axis`
		local column = stub("VStack", "/r", {}, { mid })
		layout_node.build(store, column, NEUTRAL, 1, 0, {})
		expect(`visits={store.childVisits}`).toBe("visits=7")
	end)

	it("CLIP: a container that ENTERS a clipper rebuilds its array", function()
		local mid = stub("VStack", "/r/m", {}, leaves("/r/m", 6))
		local plain = stub("VStack", "/r", {}, { mid })
		local store = layout_node.newStore()
		layout_node.build(store, plain, NEUTRAL, 1, 0, nil)
		layout_node.build(store, plain, NEUTRAL, 1, 0, {})
		expect(`served visits={store.childVisits} built={store.built}`).toBe("served visits=0 built=0")
		local scroller = stub("ScrollView", "/r", { axis = "y" }, { mid })
		layout_node.build(store, scroller, NEUTRAL, 1, 0, {})
		expect(`visits={store.childVisits}`).toBe("visits=7")
	end)

	it("KIDS AXIS: an `AdaptiveStack` that flips does NOT serve its children a stale tree", function()
		--[[ THE DEFECT THE SUITE CAUGHT, and the plan's owed row 5 asserted it could
			not happen. The claim was "`childAxis` is a pure function of `kind`, and
			`kind` is fixed for a mounted node". `kind` is NOT fixed: `AdaptiveStack`
			derives it from a REACTIVE `axis` prop (`layout_node.luau:529`), `VStack`/
			`HStack` from `wrap` (`:523`, `:544`), and `Button` from whether it has
			children (`:560`) — three prop-decides-kind seams whose stated guarantee is
			that a flip re-solves and never remounts.

			So an `AdaptiveStack` whose axis signal moves is dirty on its OWN path with
			clean children — this arm's exact shape — and the container's `axis`/`clip`
			pair says nothing about it, because that pair is where the CONTAINER sits,
			not what it imposes. `tests/adaptive.spec`'s "follows an AdaptiveStack's axis
			flip with no rebuild" is the live witness (a Divider 280px wide where it must
			be 1); this is the same fact at the store's own seam. ]]
		local kids = leaves("/r", 6)
		local flip = stub("AdaptiveStack", "/r", { axis = "y" }, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, flip, NEUTRAL, 1, 0, nil)
		layout_node.build(store, flip, NEUTRAL, 1, 0, {})
		expect(`served visits={store.childVisits} built={store.built}`).toBe("served visits=0 built=0")
		-- the SAME mounted node, one prop moved: `kind` goes vstack -> hstack and every
		-- child must be rebuilt under `childAxis = "x"`
		flip.props = { axis = "x" }
		local flipped = layout_node.build(store, flip, NEUTRAL, 1, 0, { ["/r"] = true })
		expect(`visits={store.childVisits} built={store.built}`).toBe("visits=6 built=7")
		expect(flipped.children).never().toBe(first.children)
		expect(flipped.children[1]).never().toBe(first.children[1])
	end)

	it("KIDS CLIP: a container that BECOMES a clipper rebuilds under the new clip", function()
		--[[ The same argument on the other half of the pair. `kind == "scroll"` is
			fixed per class today, so this is driven at the seam rather than through a
			blueprint — `kidsClip` is recorded as the VALUE the children were handed
			rather than argued from the class, which is what makes the term exact
			instead of an inference that a later class could falsify the way
			`AdaptiveStack` falsified the axis one. ]]
		local kids = leaves("/r", 6)
		local plain = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		layout_node.build(store, plain, NEUTRAL, 1, 0, nil)
		layout_node.build(store, plain, NEUTRAL, 1, 0, { ["/r"] = true })
		expect(`kept visits={store.childVisits}`).toBe("kept visits=0")
		-- the entry now carries `kidsClip = false`; a build INSIDE a clipper hands the
		-- children `true`, and the recorded pair refuses
		local built = layout_node.toLayoutNode(plain, NEUTRAL, 1, 0, nil, true, store)
		expect(`visits={store.childVisits} children={#built.children}`).toBe("visits=6 children=6")
	end)

	it("IDENTITY, NOT LENGTH: the same children in a different order are a different array", function()
		--[[ THE TERM THE PLAN NAMED AND THE SHAPE IT NAMED ARE NOT THE SAME THING. A
			length compare would accept a SWAP — the same count, the same clean children,
			a different sequence — and serve every downstream reader an array whose
			order is last tick's. That is a lost-and-duplicated node in every consumer
			that walks `children`: focus order, the commit's document order, `mIds`.

			▲ AND IT IS DRIVEN HERE BECAUSE THE MOUNT LAYER CANNOT PRODUCE IT. The only
			writers of a mounted node's `children` after mount are the region
			reconcilers (`mount.luau:450`, `:197`, `:465`), and a region is spliced away
			in `appendChild` so it never owns a layout node and never reaches this gate.
			For every node that DOES reach it, `node.children` is the array built at
			mount. So a length mutation is a structural NULL against a blueprint drive,
			and this seam case is the only witness the term can have — recorded rather
			than asserted, because "the mutation did not bite" and "the term is
			unnecessary" are different claims. ]]
		local kids = leaves("/r", 4)
		local root = stub("VStack", "/r", {}, kids)
		local store = layout_node.newStore()
		local first = layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		local firstIds = `{first.children[1].id},{first.children[4].id}`
		-- a NEW table, the same four child tables, the first and last swapped
		root.children = { kids[4], kids[2], kids[3], kids[1] }
		local swapped = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true })
		expect(`visits={store.childVisits}`).toBe("visits=4")
		expect(firstIds).toBe("/r/c1,/r/c4")
		expect(`{swapped.children[1].id},{swapped.children[4].id}`).toBe("/r/c4,/r/c1")
	end)

	it("a container that never built an array before cannot reuse one", function()
		--[[ `prior.childArray ~= nil` is not decoration: a container whose previous
			build had NO children records no array, and a later build that grows children
			must not read a nil into `layoutNode.children`. Driven on the SAME mounted
			node, because that is the only way an entry with a nil `childArray` can be
			the `prior` of a build with children — and, like the swap above, it is a
			structural null against a blueprint drive for the same reason. ]]
		local root = stub("VStack", "/r", {}, {})
		local store = layout_node.newStore()
		layout_node.build(store, root, NEUTRAL, 1, 0, nil)
		expect(`visits={store.childVisits} built={store.built}`).toBe("visits=0 built=1")
		root.children = leaves("/r", 3)
		local grown = layout_node.build(store, root, NEUTRAL, 1, 0, { ["/r"] = true })
		expect(`visits={store.childVisits} built={store.built} kids={#grown.children}`).toBe("visits=3 built=4 kids=3")
	end)
end)

--[[ ── THE PUBLISHED COUNTER, ON A REAL SURFACE ────────────────────────────────
	`deep_stack_scene`'s `listWidth`/`listPad` arms are the drives this lever exists
	for: a signal bound to the CONTAINER's own width or vertical padding, with a
	thousand clean rows under it. `scene.text` is the opposite drive and is carried in
	the same block, because "the arm fires" and "the arm refuses when it must" are one
	claim. ]]
local function statLine(s: any, before: any): string
	local st = s.stats()
	return `solves={st.solves - before.solves} visits={st.lastBuildChildVisits} builds={st.lastNodeBuilds} nodes={st.lastLayoutNodes}`
end

describe("T15: the counter, on the thousand-row list", function()
	it("THE HEADLINE: the list's own width moves and ONE child is visited", function()
		local s = scene.new({ rows = 1000, listWidth = true, listPad = true })
		s.text(5, "warm") -- the warm-up drive, discarded
		local warm = s.stats()
		expect(statLine(s, { solves = warm.solves - 1 })).toBe("solves=1 visits=1003 builds=4 nodes=3002")
		--[[ THE CONTAINER'S OWN WIDTH. `List` is measure-dirty, its thousand rows are
			not, and the array it built last tick is the array it would build now. The
			one remaining visit is the SCREEN's — its single child is `List`, which IS
			dirty, so the screen's own one-element array is rebuilt exactly as before. ]]
		local before = s.stats()
		s.listWidth(340)
		expect(statLine(s, before)).toBe("solves=1 visits=1 builds=2 nodes=3002")
		before = s.stats()
		s.listPad(7)
		expect(statLine(s, before)).toBe("solves=1 visits=1 builds=2 nodes=3002")
		-- ...and a LEAF write puts the loop straight back, because the row is dirty
		before = s.stats()
		s.text(9, "z")
		expect(statLine(s, before)).toBe("solves=1 visits=1003 builds=4 nodes=3002")
		s.dispose()
	end)

	it("a row spliced into the region rebuilds the array, and the node count grows by it", function()
		--[[ OWED ROW 4 / OWED ROW 10. The `UI.ForEach` region sits BEFORE the rows, so
			an insert shifts every later index of `List`'s spliced flat child list while
			`List`'s own mount children table stays the same OBJECT — the identity term
			alone would carry the stale array. What refuses it is the `store.dirty` scan:
			`mount.luau:450` replaces the REGION's children and `pushDirty(path,
			"structure")` marks the region's own path, which is a mount child of `List`.
			THE SITE THIS CASE DRIVES is that wholesale replacement; the two exit-finish
			sites are driven below. ]]
		local s = scene.new({ rows = 200, foreach = true, listWidth = true })
		s.text(5, "warm")
		local before = s.stats()
		s.insertItem("k1")
		expect(statLine(s, before)).toBe("solves=1 visits=204 builds=3 nodes=605")
		before = s.stats()
		s.removeItem("k1")
		expect(statLine(s, before)).toBe("solves=1 visits=203 builds=2 nodes=604")
		s.dispose()
	end)
end)

--[[ ── THE TWO EXIT-FINISH SITES ───────────────────────────────────────────────
	`mount.luau:197` (When) and `:465` (ForEach) `table.remove` from `node.children`
	IN PLACE, on a frame of the coordinator's choosing, long after the reconcile that
	started the exit. Table identity is blind to both. Each is followed by
	`pushDirty(path, "structure")` (`:202`, `:470`) on the REGION's path, and the
	region is a mount child of the container this arm is about — so the scan sees what
	identity cannot. A scripted coordinator hands the test the `done` callback so
	"the exit completes" is something the case decides. ]]
local FADE = { enter = "fade" }

local function scripted()
	local pending: { [string]: () -> () } = {}
	local coordinator: any = {}
	function coordinator.shouldRetire(_path: string, node: any): any?
		return node.transition
	end
	function coordinator.beginExit(path: string, _node: any, _spec: any, done: () -> ())
		pending[path] = done
	end
	function coordinator.cancelExit(path: string)
		pending[path] = nil
	end
	function coordinator.beginEnter() end
	function coordinator.release(path: string)
		pending[path] = nil
	end
	return {
		coordinator = coordinator,
		finish = function(path: string)
			local done = pending[path]
			expect(done ~= nil).toBe(true)
			pending[path] = nil
			(done :: () -> ())()
		end,
	}
end

describe("T15: the two exit-finish sites the identity term is blind to", function()
	local function build(region: "foreach" | "when")
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 720 })
		local script = scripted()
		local width = core:signal(900)
		local items = core:signal({ { key = "a" }, { key = "b" } })
		local on = core:signal(true)
		local kids: { any } = {}
		if region == "foreach" then
			kids[1] = UI.ForEach({
				id = "F",
				items = items,
				transition = FADE,
				key = function(item: any): string
					return item.key
				end,
				row = function(_item: any)
					return UI.ZStack({
						id = "Item",
						canvasGroup = true,
						children = { UI.Box({ id = "A", width = px(24), height = px(8) }) },
					})
				end,
			})
		else
			kids[1] = UI.When({
				id = "W",
				condition = on,
				transition = FADE,
				thenView = function()
					return UI.ZStack({
						id = "Item",
						canvasGroup = true,
						children = { UI.Box({ id = "A", width = px(24), height = px(8) }) },
					})
				end,
			})
		end
		for i = 1, 24 do
			kids[#kids + 1] = UI.HStack({
				id = `R{i}`,
				children = { UI.Box({ id = "A", width = px(10), height = px(6) }) },
			})
		end
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "List",
						gap = 2,
						width = core:memo(function(use: any)
							return px(use(width) :: number)
						end),
						children = kids,
					}),
				},
			}),
			{ transitions = script.coordinator }
		)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return {
			core = core,
			root = root,
			controller = controller,
			script = script,
			width = width,
			items = items,
			on = on,
		}
	end

	local function line(arm: any, before: any): string
		local st = arm.controller.stats()
		return `solves={st.solves - before.solves} visits={st.lastBuildChildVisits} nodes={st.lastLayoutNodes}`
	end

	it("ForEach exit-finish (`mount.luau:465`): the in-place remove is caught by the scan", function()
		local arm = build("foreach")
		arm.width:set(880)
		arm.controller.refresh()
		local before = arm.controller.stats()
		-- the arm FIRES on this fixture, which is what makes the refusal below a fact
		arm.width:set(870)
		arm.controller.refresh()
		expect(line(arm, before)).toBe("solves=1 visits=1 nodes=54")
		-- the reconcile: `b` starts exiting and HOLDS its slot (`mount.luau:450`)
		arm.items:set({ { key = "a" } })
		arm.controller.refresh()
		before = arm.controller.stats()
		--[[ ...and now the FINISH, on its own frame: `table.remove(node.children,
			index)` on the region's array, `pushDirty(path, "structure")` at `:470`, and
			no table anywhere changed identity. The scan is the only thing that sees it,
			and `lastLayoutNodes` falling by one is the witness that the flat list
			actually lost the row. ]]
		arm.script.finish("/S/List/F/[b]/Item")
		arm.controller.refresh()
		expect(line(arm, before)).toBe("solves=1 visits=26 nodes=52")
		arm.root.dispose()
	end)

	it("When exit-finish (`mount.luau:197`): the same in-place remove, the same scan", function()
		local arm = build("when")
		arm.width:set(880)
		arm.controller.refresh()
		local before = arm.controller.stats()
		arm.width:set(870)
		arm.controller.refresh()
		expect(line(arm, before)).toBe("solves=1 visits=1 nodes=52")
		arm.on:set(false)
		arm.controller.refresh()
		before = arm.controller.stats()
		arm.script.finish("/S/List/W/then/Item")
		arm.controller.refresh()
		expect(line(arm, before)).toBe("solves=1 visits=25 nodes=50")
		arm.root.dispose()
	end)
end)

--[[ ── THE INVARIANT, AS A SOURCE SCAN ──────────────────────────────────────────
	Owed row 11. The moment an array is reused it is shared between two `layoutNode`s
	across ticks, so an in-place edit is a cross-tick aliasing bug that no rect
	comparison on a single tick can see. There is nothing to assert at runtime — the
	property is "no line of `src/` ever writes into it" — so it is asserted about the
	source, with the whole of `src/layout` and `src/render` in scope, because a reader
	one module away is exactly where such a write would appear. ]]
describe("T15: a published children array is never mutated", function()
	it("the only writer of a layout node's `children` in the framework is the fresh-array arm", function()
		local fs = require("@lune/fs")
		local offenders: { string } = {}
		local checked = 0
		local function sweep(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					sweep(path)
				elseif string.sub(entry, -5) == ".luau" then
					checked += 1
					local src = fs.readFile(path)
					for line in string.gmatch(src, "[^\n]+") do
						local trimmed = string.match(line, "^%s*(.-)%s*$") or line
						if string.sub(trimmed, 1, 2) == "--" then
							continue
						end
						--[[ THE TWO SHAPES A MUTATION TAKES: an indexed assignment into
							a children array, and an insert/remove against one. The
							fresh-array arm's own `table.insert(\n\t\t\t\t\tlayoutNode
							.children,` is wrapped across lines by stylua and so is
							matched by the multi-line search below, not here. ]]
						if string.match(trimmed, "children%s*%[[^%]]+%]%s*=") ~= nil then
							table.insert(offenders, `{path}: {trimmed}`)
						end
						if string.match(trimmed, "table%.remove%s*%(%s*[%w_.]*children") ~= nil then
							table.insert(offenders, `{path}: {trimmed}`)
						end
					end
				end
			end
		end
		sweep("src/layout")
		sweep("src/render")
		expect(`checked>10={checked > 10} offenders={table.concat(offenders, " | ")}`).toBe(
			"checked>10=true offenders="
		)
	end)

	it("`layout_node` inserts into `layoutNode.children` in exactly one place, and it is the fresh arm", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/render/layout_node.luau")
		local inserts = 0
		for _ in string.gmatch(src, "table%.insert%(%s*layoutNode%.children") do
			inserts += 1
		end
		local fresh = 0
		for _ in string.gmatch(src, "layoutNode%.children = {}") do
			fresh += 1
		end
		local adopts = 0
		for _ in string.gmatch(src, "layoutNode%.children = prior%.childArray") do
			adopts += 1
		end
		expect(`inserts={inserts} fresh={fresh} adopts={adopts}`).toBe("inserts=1 fresh=1 adopts=1")
	end)
end)

--[[ ── THE DIFFERENTIAL ORACLE ─────────────────────────────────────────────────
	Arm `a` is the shipped configuration, `b` throws the cross-solve measure SLATES
	away and keeps the incremental arrange, and `c` forces a FULL solve every refresh
	— where `dirty` reaches `build` as nil, the store's `byNode` table is replaced, and
	this arm is structurally unreachable. `c` is the ground truth.

	THIS TASK HAS NO DEDICATED OFF-SWITCH, and the honest version says so:
	`node_reuse`'s `layoutNodeReuse = false` is `store.reuse`, the WHOLE store's
	off-switch, which disables the per-child warm hit as well. The arm's own refusals
	are what the cases above exercise; arm `c` is what proves the geometry.

	THE DRIVES INTERLEAVE A STRUCTURAL STEP with the container-prop writes on purpose:
	a kept array has to survive an insert into a spliced region on the very next tick.

	THE SETTLE IS NOT IN THIS DIFFERENTIAL, and the reason is measured rather than
	assumed. Delivering text widths (`fake_target.deliverTextWidths`) makes all THREE
	arms disagree with each other on `compact-phone-portrait` — arm `a` reads 36 px for
	"Row 1" where arm `c` reads 44 — and **that divergence reproduces BYTE-IDENTICALLY
	at `06ab8826` with this mechanism stashed**, on a run where both arms queued a batch
	and both were answered. It is a property of how a full-solve arm and an incremental
	arm absorb a settled correction, it is older than this task, and the task report
	books it. Putting it in this differential would make a red that says nothing about a
	kept array.

	SO THE SETTLE GETS ITS OWN CASE AND ITS OWN ORACLE, one arm against ITSELF: drive,
	settle, snapshot; then nudge the viewport away and back — two FULL solves, each with
	`dirty == nil`, which replaces `store.byNode` and rebuilds every layout node from
	scratch — and snapshot again. A kept array that had gone stale across the settle is
	exactly the difference between those two snapshots, and no second arm is needed to
	see it. The counters in the same case are what say the settle ran over a kept array
	at all: the container's own width write visits ZERO children while
	`lastTextDirtyPaths` is non-zero. ]]
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

-- drive one arm to the SETTLED state the way `text_settle_closure.spec` does:
-- solve, answer every outstanding batch, repeat until nothing is outstanding
local function settle(s: any)
	for _ = 1, 8 do
		s.controller.refresh()
		if s.adapter.textBatchCount() == 0 then
			break
		end
		s.adapter.deliverTextWidths(function(word: string, size: number, _font: string): number?
			return math.max(1, #word * size * 0.5)
		end)
	end
	s.controller.refresh()
end

describe("T15 oracle: byte-equal to a full solve, every view", function()
	local FIXTURES: { any } = {
		{ name = "listWidth", rows = ORACLE_ROWS, listWidth = true, listPad = true },
		{ name = "listWidth+foreach", rows = ORACLE_ROWS, listWidth = true, listPad = true, foreach = true },
		{ name = "listWidth+label", rows = ORACLE_ROWS, listWidth = true, listPad = true, label = true },
		{ name = "listWidth+nested", rows = ORACLE_ROWS, listWidth = true, listPad = true, nested = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects and the public readers survive the kept array`, function()
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
					-- the drive this arm is FOR: the container's own width, then its pad
					a.listWidth(300 + step * 11)
					b.listWidth(300 + step * 11)
					c.listWidth(300 + step * 11)
					agree(`listWidth {step}`)
					a.listPad(step)
					b.listPad(step)
					c.listPad(step)
					agree(`listPad {step}`)
					-- ...and a LEAF write straight after it, over the array just kept
					a.text(step + 1, `t{step}`)
					b.text(step + 1, `t{step}`)
					c.text(step + 1, `t{step}`)
					agree(`text {step}`)
					if fixture.foreach then
						-- the STRUCTURAL step, interleaved: an insert into the spliced
						-- region on the tick after a kept array
						a.insertItem(`k{step}`)
						b.insertItem(`k{step}`)
						c.insertItem(`k{step}`)
						agree(`insert {step}`)
						a.listWidth(280 + step)
						b.listWidth(280 + step)
						c.listWidth(280 + step)
						agree(`listWidth after insert {step}`)
						a.removeItem(`k{step}`)
						b.removeItem(`k{step}`)
						c.removeItem(`k{step}`)
						agree(`remove {step}`)
					end
					a.viewport(view.w - step, view.h - step)
					b.viewport(view.w - step, view.h - step)
					c.viewport(view.w - step, view.h - step)
					agree(`viewport {step}`)
				end
				a.listWidth(333)
				b.listWidth(333)
				c.listWidth(333)
				agree("listWidth, last")
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end

	it("A SETTLE OVER A KEPT ARRAY, against the same surface rebuilt from scratch", function()
		--[[ OWED ROW 7, with its own oracle. A settled session's learned word arrives as
			`measure` dirt on the paths that use its (font,size) key — paths whose layout
			nodes this arm did not rebuild — and the text index is written at MEASURE
			time (`solver.luau`'s `ctx.textIndex.record`), never at build time. So a kept
			array cannot skip a registration; what it COULD do is hand the solver a
			stale set of text nodes to walk, and that is what this compares.

			THE ORACLE IS THE SURFACE AGAINST ITSELF. A viewport nudge away and back is
			two FULL solves — `dirty` reaches `build` as nil, `store.byNode` is replaced,
			every layout node is constructed again — at the identical geometry. If the
			kept array had lost, duplicated or staled a node, the rebuild lands on
			different rects. ]]
		for _, view in device_views.VIEWS do
			local s = scene.new({
				rows = 12,
				listWidth = true,
				listPad = true,
				label = true,
				viewport = { x = 0, y = 0, w = view.w, h = view.h },
			})
			settle(s)
			--[[ A WORD NOBODY HAS MEASURED, and it has to be unique PER VIEW: the text
				metrics cache is module-level and lives for the whole process, so a word
				learned on the first view is already known on the second and the settle
				pushes nothing. ]]
			s.text(3, `first-word-{view.id}`)
			settle(s)
			-- the container's own width, over a settled tree: the arm fires here
			local before = s.stats()
			s.listWidth(math.max(120, view.w - 40))
			local st = s.stats()
			--[[ ONE visit, not zero, and it is the SCREEN's: `List` is dirty, so the
				screen rebuilds its own one-element array exactly as it always did. The
				thousand-child loop under `List` is the one that stops running. ]]
			expect(`{view.id} solves={st.solves - before.solves} visits={st.lastBuildChildVisits}`).toBe(
				`{view.id} solves=1 visits=1`
			)
			-- ...and one more settle ON TOP of the array just kept, with the paths it
			-- pushed as the witness that a settle actually happened here
			s.text(5, `second-word-{view.id}`)
			local pushed = 0
			for _ = 1, 8 do
				s.controller.refresh()
				pushed = math.max(pushed, (s.stats() :: any).lastTextDirtyPaths)
				if s.adapter.textBatchCount() == 0 then
					break
				end
				s.adapter.deliverTextWidths(function(word: string, size: number, _font: string): number?
					return math.max(1, #word * size * 0.5)
				end)
			end
			s.controller.refresh()
			expect(`{view.id} pushedPaths>0={pushed > 0}`).toBe(`{view.id} pushedPaths>0=true`)
			local kept = s.snapshot()
			-- the rebuild: two full solves at the identical geometry
			s.viewport(view.w - 7, view.h - 7)
			s.viewport(view.w, view.h)
			if s.snapshot() ~= kept then
				error(`{view.id}: the kept array disagreed with a from-scratch rebuild`, 0)
			end
			s.dispose()
		end
	end)
end)
