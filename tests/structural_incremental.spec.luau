--!strict
--[[ O6 — THE STRUCTURAL SYNC IS O(TREE) FOR AN O(1) CHANGE.

	Adding one plate re-walks the whole mounted tree twice and iterates the whole
	handle map once: `ensureTree` (a hash lookup and a recursive call per node,
	discovering newness one node at a time), `livePaths` (five whole-tree maps
	rebuilt from scratch after a block of `table.clear`s), and the removal sweep
	(`for path, handle in handles`, testing `alive[path]`). Only `ssZOrder` is
	inherently whole-tree, and it stays that way — NM-H4a forbids a state-dependent
	reservation, so a document-order counter renumbers everything after an insert BY
	DESIGN. `collectRetiringRoots` is whole-tree too and also stays: it answers
	"which subtrees are mid-exit", which no delta names.

	MEASURED BEFORE IT WAS BUILT (FacetBench `attr nameplates L 3`, at the T6 base):
	`ssEnsureTree` 0.109 ms + `ssLivePaths` 0.228 + `ssSweep` 0.022 = 0.359 ms of a
	1.104 ms add, and 0.061 + 0.227 + 0.058 = 0.346 of a 1.051 ms remove. `ssZOrder`
	is another 0.25-0.30 and is out of scope, which is why the ceiling here was
	stated as ~0.3 ms of the 0.6 rather than the whole of it.

	THE DELTA IS AVAILABLE AND SIMPLY WAS NOT HANDED DOWN: `refresh` holds the
	`dirty` array with its `structure` entries before it calls `structuralSync`, and
	`mount.luau` pushes every one of those against the path of the container whose
	`node.children` it just mutated — the parent, never the child that moved. So the
	entry names exactly the subtree that has to be re-derived.

	WHY THE FIVE MAPS CAN BE RE-DERIVED FROM A SUBTREE AT ALL: `scrollHostOf`,
	`clipHostOf`, `parentNodeOf`, `pathNodes` and `inputSinks` are all
	inherited-from-the-parent or per-node facts, so a subtree's values follow from
	its root's recorded pair `(scrollHostOf[root], clipHostOf[root])` and the nodes
	themselves. `alive` is the sweep's oracle and is scoped with it.

	MUTATIONS RUN, 2026-09-03: twelve, of which SIX bite —

	  | mutation                                          | result   |
	  | `roots = nil` unconditionally                     | 4 red    |
	  | the departed enumeration takes direct children    | 3 red    |
	  | the whole-tree `table.clear(scrollHostOf)` back    | 3 red    |
	  | `pathNodeCount` zeroed instead of decremented     | 1 red    |
	  | the whole-tree `table.clear(pathNodes)` back       | 2 red    |
	  | an ancestor root swallows a descendant root       | 1 red    |
	  | the skip ignores the inherited (host, clip) pair  | DOES NOT |
	  | the skip ignores node identity (path only)        | DOES NOT |
	  | `sweepDeparted` drops the five walk facts         | DOES NOT |
	  | `active` stops being a root-making prop           | DOES NOT |
	  | an UNCOVERED unresolvable entry is skipped        | DOES NOT |
	  | the `mounted` guard on a root is dropped          | DOES NOT |

	THE SIX NULL RESULTS ARE KEPT AS-IS AND HERE IS WHY EACH ONE IS UNREACHABLE, not
	merely undriven. All six defend the SAME shape — a fallback or a guard whose whole
	value is that the unsafe branch never runs — and inventing a fixture to make one
	go red would be a case written for the mutation rather than for the behaviour.

	  * THE INHERITED PAIR, and this is the one worth reading. A child's pair can only
	    change if an ancestor's class or `clipChildren` changed, and both are immutable
	    for a given node object — `clipChildren` is `reactive = false` in the schema, and
	    a class change means a NEW node, which fails the identity half anyway. So the
	    pair test is currently belt-and-braces. It stays because the skip's CLAIM is
	    about facts, not identity: "the same node under the same context" is the true
	    statement, and "the same node" alone is a statement that happens to hold.
	  * NODE IDENTITY, the same test from the other side. Making the skip a path test
	    needs a node RE-CREATED at a path its parent still lists in the same sync. No
	    fixture in either repository does that: `ForEach` reuses an entry by key, a
	    `When` branch departs before it returns, and the one route that could —
	    `ErrorBoundary` tripping twice in a frame — has no driver here.
	  * THE FIVE WALK FACTS IN `sweepDeparted`. They are latent by construction: a
	    departed path's entries are only ever READ again if that path comes back, and
	    when it does the walk overwrites them. The existing comment beside
	    `parentNodeOf` is what says they must go anyway ("a stale parent link would
	    resolve a constraint to a branch that no longer exists"), and the whole-tree
	    pass has always cleared them.
	  * `active` AS A ROOT-MAKING PROP closes a staleness that predates this change: an
	    `active` flip is `semantics`-classed and schedules no sync at all, so today it
	    is repaired only by whatever structural sync happens to run next. Bounding the
	    sync takes that accident away; naming the prop puts it back deliberately.
	  * THE UNCOVERED-UNRESOLVABLE FALLBACK and THE `mounted` GUARD are the same
	    argument twice. Every route that can put an unmounted or departed path in the
	    delta does so from inside some other entry's subtree (a region fills its
	    children on its first run; a region inside a removed subtree fires on its way
	    out), so the uncovered case is not reachable from any shipped mount path — and
	    the guard is what makes "a root has a recorded seed" true rather than usual.

	AND THE SIXTH THING IS A COUNT, NOT A MAP. `pathNodeCount` is decremented per
	departed `UI.Path` rather than zeroed, for the same reason `pathNodes` is not
	cleared: `commit_walks`' `prunable` latch reads `next(pathNodes) == nil` and
	`reculPathClips` returns early on `pathNodeCount == 0`, so a partially rebuilt
	pair does not break a rect — it silently OPENS a whole-surface prune and closes
	a live cull. Two of the cases below exist only to see that.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local path_shapes = require("../src/controls/path_shapes")

local PLATES = scene.PLATES -- 250
-- 250 plates x 6 nodes + the Screen and the Anchor + the ForEach region node.
-- `tests/lib/nameplates_scene.luau`'s header derives this shape; there is no
-- per-item wrapper, so MOUNTED is the layout count plus the region.
local MOUNTED = PLATES * scene.NODES_PER_PLATE + 2 + 1 -- 1503

--[[ THE PINS ARE EXACT AND EVERY ONE IS DERIVED, because a threshold loose enough
	to be comfortable is loose enough to pass the regression. `nameplates_scene` mounts
	ONE `ForEach` region holding all 250 plate roots, so the structure entry a churn
	produces names a container whose subtree IS the tree bar two nodes — which is why a
	bound that only scoped to the entry's subtree would have bought exactly nothing
	here, and why the walk skips a child that is the same node object under the same
	inherited (host, clip) pair. That skip is the lever; the scoping is what makes it
	reachable.

	WHAT THE PASS REPLACES, for the same drive: `ensureTree` over 1,503 nodes,
	`livePaths` over 1,503, and a sweep over all 1,503 handles. ]]
local VISITED_ADD = 16
local VISITED_REMOVE = 10

describe("O6: a structural sync visits the delta, not the tree", function()
	it("adding one plate visits 16 nodes, not 3,006", function()
		--[[ 16 = 2 + 7 + 7 + 0. TWO for the segment descent that resolves the root
			(`/S/Canvas`, then `/S/Canvas/Plates`); SEVEN for `ensureTree` — the region
			itself plus the new plate's six nodes, with all 250 surviving children skipped
			on identity; SEVEN again for `livePaths` over the same shape; and NOTHING
			departed, because an add removes nothing. ]]
		local s = scene.new()
		s.tick(3, 2)
		-- `scene.new()` calls `initialRender`, which is a full pass BY CONSTRUCTION, so
		-- the fallback counter is read as a DELTA over the drive rather than absolutely
		local before = s.stats().ssFullPasses
		s.add(1)
		expect(`visited={s.stats().lastSsVisited} full={s.stats().ssFullPasses - before}`).toBe(
			`visited={VISITED_ADD} full=0`
		)
		s.dispose()
	end)

	it("removing one plate visits 10", function()
		--[[ 10 = 2 + 1 + 1 + 6. The same two-step descent; ONE for `ensureTree` (the
			region alone — nothing was added, so every surviving child is skipped); ONE for
			`livePaths`; and SIX for the departed enumeration, which is the removed plate
			and its five descendants, named out of the per-parent index because they are
			already gone from the tree. ]]
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats().ssFullPasses
		s.remove(3)
		expect(`visited={s.stats().lastSsVisited} full={s.stats().ssFullPasses - before}`).toBe(
			`visited={VISITED_REMOVE} full=0`
		)
		s.dispose()
	end)

	it("THE FALLBACK IS LOUD: a sync with no delta takes the whole tree and counts itself", function()
		--[[ `controller.initialRender()` passes no delta, which is the one route that
			CANNOT be bounded — there is no previous walk to bound against. It is also the
			guard that stops the two cases above from passing on a fixture that falls back
			every time: a `ssFullPasses` that only ever goes up is a bounded path nobody is
			taking. ]]
		local s = scene.new()
		local before = s.stats().ssFullPasses
		s.controller.initialRender()
		expect(s.stats().ssFullPasses - before).toBe(1)
		-- two whole-tree walks, so the count is above the tree rather than near it
		expect(s.stats().lastSsVisited > MOUNTED).toBe(true)
		s.dispose()
	end)
end)

describe("O6: the differential oracle — a bounded sync builds what a full one builds", function()
	--[[ THE ONLY HONEST TEST OF A SCOPED REBUILD, and it is a DIFFERENTIAL: two
		identical scenes take identical structural steps, and one of them is forced
		through the whole-tree path afterwards. `scene.snapshot()` is every live node's
		path, rect, props, visibility, hit rect and scroll canvas — the adapter's whole
		observable — so a map this rebuild scoped WRONG shows up as a difference in what
		the engine was told, never as a counter nobody reads. ]]
	local function driveOracle(view: { id: string, w: number, h: number }): string
		local a = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
		local b = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
		local seed = 20260902
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return (seed % n) + 1
		end
		local out = "clean"
		for step = 1, 30 do
			if step % 3 == 0 then
				--[[ A RANDOM INDEX, so the departed subtree is somewhere in the middle of
					the region's children rather than always at its end — a plate root is a
					DIRECT child of the ForEach region and its five descendants are not, so a
					removal is also the case that proves the departed enumeration descends. ]]
				local i = rnd(20)
				a.remove(i)
				b.remove(i)
			else
				--[[ THE STEP NUMBER, NOT A RANDOM ONE, and it is not a detail:
					`scene.add(i)` builds its key as `add{i}`, so two adds with the same `i`
					are a DUPLICATE KEY and `ForEach` quarantines the whole region. Both arms
					quarantine identically, so the oracle stayed green while comparing two
					dead trees — caught on the first run of this file. ]]
				a.add(step)
				b.add(step)
			end
			-- b is forced through the whole-tree path by a full structural sync
			b.controller.initialRender()
			if a.snapshot() ~= b.snapshot() then
				out = `step {step} diverged from a from-scratch sync`
				break
			end
		end
		a.dispose()
		b.dispose()
		return out
	end

	it("30 random adds and removes leave the tree a from-scratch sync would build", function()
		expect(driveOracle({ id = "default", w = 1280, h = 720 })).toBe("clean")
	end)

	it("...at every device view, 320x640 included", function()
		local out: { string } = {}
		for _, view in device_views.VIEWS do
			table.insert(out, `{view.id}={driveOracle(view)}`)
		end
		local want: { string } = {}
		for _, view in device_views.VIEWS do
			table.insert(want, `{view.id}=clean`)
		end
		expect(table.concat(out, " ")).toBe(table.concat(want, " "))
		-- the sweep really did visit the narrowest supported viewport
		expect(string.find(table.concat(want, " "), "narrow-portrait=clean", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ ── THE TWO FACTS THAT LIVE OUTSIDE THE CHURN ────────────────────────────
	A bound is only safe if what it does NOT re-derive survives. This fixture puts
	a scroll host above the churn and a stroked `UI.Path` beside it, because those
	are the two per-path facts whose breakage is invisible to a rect oracle: an
	erased `scrollHostOf` moves nothing and answers the wrong window position, and
	an emptied `pathNodes`/`pathNodeCount` pair moves nothing and turns two culls
	off. ]]
local function scrollFixture(rows: number): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local items: { any } = {}
	for i = 1, rows do
		table.insert(items, { key = `r{i}` })
	end
	local rowsSignal = core:signal(items)
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.ScrollView({
				id = "List",
				height = { type = "fixed", px = 100 },
				axis = "y",
				padding = 0,
				gap = 0,
				clipChildren = true,
				children = {
					-- OUTSIDE the churn and INSIDE the scroll host: the node whose
					-- `scrollHostOf` a whole-tree clear would erase
					UI.ZStack({
						id = "Head",
						height = { type = "fixed", px = 50 },
						children = {
							UI.Path({
								id = "Ring",
								points = path_shapes.ring(),
								closed = true,
								width = { type = "fixed", px = 16 },
								height = { type = "fixed", px = 16 },
							}),
						},
					}),
					UI.ForEach({
						id = "Rows",
						items = rowsSignal,
						key = function(item: any): string
							return item.key
						end,
						row = function(item: any): any
							return UI.ZStack({ id = "Row", height = { type = "fixed", px = 50 }, children = {} })
						end,
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return {
		controller = controller,
		adapter = adapter,
		add = function()
			local next_ = table.clone(rowsSignal:get() :: any)
			table.insert(next_, { key = `r{#next_ + 1}` })
			rowsSignal:set(next_)
			controller.refresh()
		end,
		remove = function()
			local next_ = table.clone(rowsSignal:get() :: any)
			table.remove(next_)
			rowsSignal:set(next_)
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

--[[ TWO ROOTS ON ONE CHAIN. A nested `ForEach` keeps its node object while
	`mount.luau` replaces its `children` in place, so the OUTER walk skips the row that
	holds it — same node, same inherited pair — and never reaches it. The inner region
	is a root of its own and has to stay one; collapsing it into its ancestor, which is
	what an ancestor-swallows-descendant rule would do, makes exactly that change
	invisible. ]]
local function nestedFixture(): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
	local inner = core:signal({ { key = "i1" } })
	local outer = core:signal({ { key = "a" }, { key = "b" } })
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			-- ...INSIDE A SCROLL HOST, so a region that mounts during a BOUNDED sync has
			-- an inherited host to get wrong (see the second case below)
			UI.ScrollView({
				id = "List",
				height = { type = "fixed", px = 100 },
				axis = "y",
				padding = 0,
				gap = 0,
				children = {
					UI.ForEach({
						id = "Outer",
						items = outer,
						key = function(item: any): string
							return item.key
						end,
						row = function(item: any): any
							return UI.VStack({
								id = "Row",
								children = {
									UI.ForEach({
										id = "Inner",
										items = inner,
										key = function(sub: any): string
											return sub.key
										end,
										row = function(sub: any): any
											return UI.Text({ id = "Leaf", text = sub.key })
										end,
									}),
								},
							})
						end,
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return {
		controller = controller,
		adapter = adapter,
		addRow = function()
			outer:set({ { key = "a" }, { key = "b" }, { key = "c" } })
			controller.refresh()
		end,
		churnBoth = function()
			-- BOTH in one refresh, which is what puts two structure entries on one chain.
			-- The outer change REMOVES a row and the inner one ADDS a leaf, so the frame
			-- also carries the two entries the roots rule has to skip rather than refuse
			-- on: the departed row's own inner region, and the new leaf's.
			outer:set({ { key = "a" } })
			inner:set({ { key = "i1" }, { key = "i2" } })
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("O6: two structural roots on one chain", function()
	it("a nested region's change survives its ancestor's walk skipping past it", function()
		local f = nestedFixture()
		expect(f.adapter.node("/S/List/Outer/[a]/Row/Inner/[i2]/Leaf")).toBe(nil)
		f.churnBoth()
		--[[ the SURVIVING row is the case: its node object never changed, so the outer
			region's walk skips it, and only the inner region being its own root gets the
			new leaf mounted. The NEW row proves the outer half landed at the same time. ]]
		expect(f.adapter.node("/S/List/Outer/[a]/Row/Inner/[i2]/Leaf") ~= nil).toBe(true)
		-- ...and the outer half landed in the same sync: the removed row is gone
		expect(f.adapter.node("/S/List/Outer/[b]/Row")).toBe(nil)
		expect(f.controller.stats().ssFullPasses).toBe(1) -- the mount's own, and no more
		f.dispose()
	end)

	it("a region that MOUNTS during a bounded sync inherits the scroll host above it", function()
		--[[ A `ForEach` fills its children on its first run and pushes a `structure`
			entry FOR ITSELF, before anything has given it a handle — so a new row's inner
			region arrives in the delta as a path with no recorded seed. Treated as a root
			it would be walked from `scrollHostOf[path]`, which is nil, and every leaf under
			it would answer as though it were outside the list. It is skipped instead,
			because an entry that covers it is already going to walk it.

			ASSERTED THROUGH `scrollHostFor`, the public accessor the presenter and the
			autoscroll models use, rather than through the private map. ]]
		local f = nestedFixture()
		f.addRow()
		local host = f.controller.scrollHostFor("/S/List/Outer/[c]/Row/Inner/[i1]/Leaf")
		expect(if host == nil then "no host" else host.path).toBe("/S/List")
		expect(f.controller.stats().ssFullPasses).toBe(1)
		f.dispose()
	end)
end)

describe("O6: what the bound does not re-derive still has to be true", function()
	it("a node ABOVE the churn keeps its scroll host across an add and a remove", function()
		--[[ `screenRectOf` subtracts the live scroll offset by walking `scrollHostOf`,
			so a `Head` whose entry was erased answers the UNSHIFTED rect — the same
			number it had before the scroll, which is a wrong answer no rect comparison
			between two solves can see. Driven through the public accessor. ]]
		local f = scrollFixture(6)
		f.adapter.driveScroll("/S/List", { x = 0, y = 40 })
		local scrolled = f.controller.screenRectOf("/S/List/Head")
		expect(scrolled.y).toBe(-40)
		f.add()
		expect(f.controller.screenRectOf("/S/List/Head").y).toBe(-40)
		f.remove()
		expect(f.controller.screenRectOf("/S/List/Head").y).toBe(-40)
		f.dispose()
	end)

	it("...and the LIVE path cull still runs, so `pathNodeCount` matched `pathNodes`", function()
		--[[ `reculPathClips` returns early on `pathNodeCount == 0`, so a count zeroed
			while `pathNodes` still holds the ring turns the RS-PATHCLIP live cull OFF —
			and the only symptom is a ring that keeps painting after it scrolls out of
			its host, which no counter and no rect reports. `Head` spans 0..50 in a
			100px window, so scrolling 100 puts it fully outside. ]]
		local f = scrollFixture(6)
		expect(f.adapter.visibleOf("/S/List/Head/Ring")).toBe(true)
		--[[ TWENTY-ONE CHURNS, not one, and the claim is repetition rather than a second
			oracle: `pathNodes`, `pathNodeCount` and the per-parent index are all now
			maintained by DELTA across the walk and the sweep, so what this adds is that
			the assertions below hold after twenty-one structural changes rather than
			after the first. The count's only consumer is an `== 0` test, so no case can
			see the SIZE of a drift — only a drift that reaches zero, which is the arm the
			`pathNodeCount` mutation drives. ]]
		for _ = 1, 10 do
			f.add()
			f.remove()
		end
		f.add()
		f.adapter.driveScroll("/S/List", { x = 0, y = 100 })
		expect(f.adapter.visibleOf("/S/List/Head/Ring")).toBe(false)
		-- ...and back, so the case cannot pass on a ring that was simply never shown
		f.adapter.driveScroll("/S/List", { x = 0, y = 0 })
		expect(f.adapter.visibleOf("/S/List/Head/Ring")).toBe(true)
		f.dispose()
	end)

	it("a UI.Path SURVIVES a structural churn (the visible latch stays closed)", function()
		--[[ `commit_walks`' `local prunable = next(pathNodes) == nil` is the latch. A
			partially rebuilt `pathNodes` breaks no rect and no visibility VALUE — it
			OPENS the whole-surface prune on a surface that has a stroked path, which is
			invisible to every rect oracle and to every visit count except this one.

			ASSERTED THROUGH THE OBSERVABLE, never through a `pathNodes` accessor: with
			the latch closed, `visible` cannot prune, so its visit count stays ABOVE the
			dirty closure across an add and across a remove. Adding a getter for a
			private renderer table to test this would make the test pass and the surface
			worse. ]]
		local s = scene.new({ withPath = true })
		s.tick(3, 2)
		s.add(1)
		local addVisible = s.stats().lastCommitVisitsByWalk.visible
		s.remove(2)
		local removeVisible = s.stats().lastCommitVisitsByWalk.visible
		-- the dirty closure a PRUNING `visible` would stop at: the churned plate's own
		-- chain plus the region, nowhere near the whole tree
		local floor = 3 + PLATES
		expect(`add={addVisible > floor} remove={removeVisible > floor}`).toBe("add=true remove=true")
		s.dispose()
	end)
end)
