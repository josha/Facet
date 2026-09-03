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

	MUTATIONS RUN, 2026-09-03 (fix round 1): fifteen, of which TWELVE bite —

	  | mutation                                          | result   |
	  | `roots = nil` unconditionally                     | 13 red   |
	  | the departed enumeration takes direct children    | 3 red    |
	  | the whole-tree `table.clear(scrollHostOf)` back    | 4 red    |
	  | `pathNodeCount` zeroed instead of decremented     | 1 red    |
	  | the whole-tree `table.clear(pathNodes)` back       | 2 red    |
	  | `livePaths`' skip tests the path, not the node    | 1 red    |
	  | `ensureTree`'s skip tests the path, not the node  | 1 red    |
	  | the sweep forgets `pathNodes` and its count       | 1 red    |
	  | an ancestor root swallows a descendant root       | 1 red    |
	  | `active` stops being a node fact                  | 2 red    |
	  | the dirty scan stops asking `isNodeFact`          | 2 red    |
	  | a node-fact entry sets no `needsSolve`            | 2 red    |
	  | the sweep drops its four OTHER per-path clears    | DOES NOT |
	  | an UNCOVERED unresolvable entry is skipped        | DOES NOT |
	  | the `mounted` guard on a root is dropped          | DOES NOT |

	THE FIRST MUTATION NOW REDDENS ALMOST EVERYTHING, and that is a change from the
	first round rather than an accident: every asserted string carries `ssPasses` and
	`full`, so a case no longer only asks "did the bounded rebuild get the right
	answer" but "was the bounded path the one that ran". A forced fallback still
	produces a CORRECT tree — the differential oracle's snapshot comparison passes
	under it — and now says so out loud instead of passing silently.

	THE THREE NULL RESULTS ARE KEPT AS-IS, and each defends an outcome no shipped
	route reaches:

	  * THE SWEEP'S FOUR OTHER PER-PATH CLEARS (`scrollHostOf`, `clipHostOf`,
	    `parentNodeOf`, `inputSinks`). A departed path that RETURNS has all four
	    rewritten unconditionally by the walk, so nothing stale is ever served; a path
	    that never returns leaks four entries for the life of the surface. That is
	    unbounded growth rather than a wrong answer, which is why the drivable half of
	    the same block — `pathNodes` and its count, which is a LATCH — is the one with
	    a case above. They stay because the whole-tree `table.clear` a bounded sync no
	    longer runs is what used to do this, and `parentNodeOf`'s own comment in the
	    renderer says why a stale link is not survivable.
	  * THE UNCOVERED-UNRESOLVABLE FALLBACK and THE `mounted` GUARD are one argument
	    twice. Every route that can put an unmounted or departed path in the delta
	    creates it from a parent's `children` mutation, and all seven
	    `pushDirty(_, "structure")` sites in `mount.luau` push against the container
	    they mutated — so the topmost changed container existed before the frame and
	    resolves, and every entry below it is strictly covered by construction. The
	    branch is the difference between a wrong bound and a slow one, it is LOUD
	    (`ssFullPasses`, pinned at 0 by every case in this file and in the game's
	    rider), and it costs one loop only on a resolution failure.

	AND TWO GUARDS THAT WERE HERE IN ROUND 1 ARE GONE. The inherited-pair term in the
	skip was two hash lookups per SKIPPED child, on the hot path this round exists to
	shrink, defending a transition the schema forbids — deleted, with the invariant
	asserted instead (see "the two facts that let the skip test identity alone"). And
	`active` as a root-making prop was not a guard at all but a partial patch over a
	hole this round opened; the whole fix is in the dirty scan now, and the two
	hit-lift cases are what say so.

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
local schema = require("../src/blueprint_schema")
local fs = require("@lune/fs")

-- comments are not code: `mount.luau` describes what it does in prose, and a scan
-- that counted the prose would report the very assignment the header promises is absent
local function stripComments(source: string): string
	local out = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "\n[ \t]*%-%-[^\n]*", "\n")
	return out
end

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
		local before = s.stats()
		s.add(1)
		local st = s.stats()
		--[[ `ssPasses` IS IN EVERY STRING, and it is not decoration: `lastSsVisited` is a
			LAST capture, so a drive that ran two syncs would report only the second one's
			count and a drive that ran none would re-assert the previous step's. The pin
			only means "this step visited 16 nodes" once it also says how many syncs the
			step caused. ]]
		expect(
			`visited={st.lastSsVisited} ssPasses={st.ssPasses - before.ssPasses}`
				.. ` full={st.ssFullPasses - before.ssFullPasses}`
		).toBe(`visited={VISITED_ADD} ssPasses=1 full=0`)
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
		local before = s.stats()
		s.remove(3)
		local st = s.stats()
		expect(
			`visited={st.lastSsVisited} ssPasses={st.ssPasses - before.ssPasses}`
				.. ` full={st.ssFullPasses - before.ssFullPasses}`
		).toBe(`visited={VISITED_REMOVE} ssPasses=1 full=0`)
		s.dispose()
	end)

	it("THE FALLBACK IS LOUD: a sync with no delta takes the whole tree and counts itself", function()
		--[[ `controller.initialRender()` passes no delta, which is the one route that
			CANNOT be bounded — there is no previous walk to bound against. It is also the
			guard that stops the two cases above from passing on a fixture that falls back
			every time: a `ssFullPasses` that only ever goes up is a bounded path nobody is
			taking. ]]
		local s = scene.new()
		local before = s.stats()
		s.controller.initialRender()
		local st = s.stats()
		-- two whole-tree walks, so the count is above the tree rather than near it
		expect(
			`ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`
				.. ` overTree={tostring(st.lastSsVisited > MOUNTED)}`
		).toBe("ssPasses=1 full=1 overTree=true")
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
			local beforeA = a.stats()
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
			--[[ ...AND EACH DRIVE CAUSED EXACTLY ONE BOUNDED SYNC. Checked per step rather
				than at the end: a run that fell back on step 7 and was bounded for the other
				29 would still compare clean, and the oracle would then be reporting the
				FALLBACK's correctness rather than the bound's. ]]
			local afterA = a.stats()
			local passes = afterA.ssPasses - beforeA.ssPasses
			local full = afterA.ssFullPasses - beforeA.ssFullPasses
			if passes ~= 1 or full ~= 0 then
				out = `step {step} ran ssPasses={passes} full={full}`
				break
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
		-- the sweep really did visit the narrowest supported viewport, read off the
		-- RESULT rather than off the literal this case just built (review M6)
		expect(string.find(table.concat(out, " "), "narrow-portrait=clean", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ ── THE TWO FACTS THAT LIVE OUTSIDE THE CHURN ────────────────────────────
	A bound is only safe if what it does NOT re-derive survives. This fixture puts
	a scroll host above the churn and a stroked `UI.Path` beside it, because those
	are the two per-path facts whose breakage is invisible to a rect oracle: an
	erased `scrollHostOf` moves nothing and answers the wrong window position, and
	an emptied `pathNodes`/`pathNodeCount` pair moves nothing and turns two culls
	off. ]]
local function ring(id: string): any
	return UI.Path({
		id = id,
		points = path_shapes.ring(),
		closed = true,
		width = { type = "fixed", px = 16 },
		height = { type = "fixed", px = 16 },
	})
end

local function scrollFixture(rows: number, opts: { removableRing: boolean? }?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local items: { any } = {}
	for i = 1, rows do
		table.insert(items, { key = `r{i}` })
	end
	local rowsSignal = core:signal(items)
	local ringOn = core:signal(true)
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
						children = { if (opts or {}).removableRing then UI.Box({ id = "Plain" }) else ring("Ring") },
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
					--[[ ...AND THE ONE `UI.Path` THAT CAN LEAVE, behind a `When` so the whole
						surface can be emptied of stroked paths while the tree around it stays
						the same size — which is what makes the latch-reopens case a contrast
						rather than a smaller tree. ]]
					if (opts or {}).removableRing
						then UI.When({
							id = "Tip",
							condition = ringOn,
							thenView = function(): any
								return UI.ZStack({
									id = "Box",
									height = { type = "fixed", px = 20 },
									children = { ring("Ring") },
								})
							end,
						})
						else UI.Box({ id = "Tip", height = { type = "fixed", px = 20 } }),
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
		dropRing = function()
			ringOn:set(false)
			controller.refresh()
		end,
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

--[[ ── C1: A NODE FACT THE WALK READS IS A STRUCTURE CHANGE ─────────────────
	`inputSinks` is written ONLY by `livePaths`, and `active` is the one prop it
	reads that is `reactive = true` (`dirty = { "semantics" }`). Before this round a
	lone `active` flip ran no structural sync either — but the next whole-tree sync
	from anywhere in the tree rebuilt `inputSinks` from scratch and repaired it. A
	BOUNDED sync does not: the flipped node's object never changed, so every later
	sync skips it and the stale verdict stands FOR THE LIFE OF THE SURFACE. That is a
	behaviour change, so the flip now schedules its own sync.

	ASSERTED THROUGH THE HIT-LIFT OBSERVABLE, never through `inputSinks`. A control
	under the touch floor gets an invisible expander (`Btn` is 20x20 against a 44px
	floor, so its expander spans -12..32 x 88..132); where that expander reaches PAST
	its host into a rect that can SINK input, `render/hit_lift` walks the host's
	branch AFTER the target's. `Sink` is 20x20 at x=26, so the expander reaches it and
	the button's own painted rect (0..20) does not — which is exactly the overhang the
	lift exists for, and `active` is the only reason `Sink` is a sinker at all. ]]
local function sinkFixture(): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	local active = core:signal(true)
	local rows = core:signal({ { key = "r1" } })
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			UI.Anchor({
				id = "Board",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Button({
						id = "Btn",
						label = "",
						anchor = "topLeft",
						offsetX = 0,
						offsetY = 100,
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 20 },
					}),
					UI.ZStack({
						id = "Sink",
						anchor = "topLeft",
						offsetX = 26,
						offsetY = 100,
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 20 },
						active = active,
						children = {},
					}),
					-- the CHURN, and it is deliberately far from both: the bounded walk it
					-- schedules has no reason to visit `Sink`
					UI.ForEach({
						id = "Rows",
						items = rows,
						key = function(item: any): string
							return item.key
						end,
						row = function(item: any): any
							return UI.ZStack({
								id = "Row",
								anchor = "topLeft",
								offsetX = 200,
								offsetY = 300,
								width = { type = "fixed", px = 10 },
								height = { type = "fixed", px = 10 },
								children = {},
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
	local function paintOrder(): string
		return `btn={adapter.node("/S/Board/Btn").z} sink={adapter.node("/S/Board/Sink").z}`
	end
	return {
		controller = controller,
		adapter = adapter,
		paintOrder = paintOrder,
		setActive = function(on: boolean)
			active:set(on)
			controller.refresh()
		end,
		churn = function()
			rows:set({ { key = "r1" }, { key = "r2" } })
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

--[[ ── THE INVARIANT THE IDENTITY SKIP RESTS ON, MADE EXECUTABLE ─────────────
	`livePaths` skips a child on node identity ALONE. That is sound only because the
	inherited `(nextHost, nextClip)` pair is a function of the ancestors' CLASS and
	`clipChildren`, and neither can move for a node table that did not change. The
	first draft of this round paid two extra hash lookups per SKIPPED child to
	re-check the pair — on the hot path the round exists to shrink, for a transition
	the schema forbids. The term is gone and these two cases are what replaced it: if
	either fact stops holding, this file goes red rather than the framework going
	quietly wrong. ]]
--[[ ── THE OTHER HALF: A PATH REUSED BY A DIFFERENT NODE ─────────────────────
	The skip's identity term is what the renderer's own sweep comment has warned about
	for years — "paths are REUSED across a remount". `mount.luau` disposes a
	`ForEach` key's row and nils its entry when the key leaves, and builds a FRESH
	node at the SAME `rowPath` when it returns. Two `rows:set` calls inside one
	refresh window (each settles synchronously outside a flush) therefore leave the
	OLD node object in the per-parent index and a NEW one in `node.children` at the
	same path, and a skip that tested only "was this path here before" would skip it —
	so a re-created row's new descendants would never be created at all. ]]
local function remountFixture(): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 600 })
	-- a PLAIN upvalue, not a signal: reading a signal inside the row factory would
	-- make the row re-run on its own and remount the very node this case is watching
	local withExtra = false
	local items = core:signal({ { key = "a" }, { key = "k" } })
	local bp = UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			-- ...INSIDE A SCROLL HOST, because `ensureTree`'s identity term and
			-- `livePaths`' are two separate skips: the first decides whether the new
			-- node gets a HANDLE, the second whether it gets its per-path FACTS, and only
			-- a host above the churn can see the second one go missing
			UI.ScrollView({
				id = "Host",
				height = { type = "fixed", px = 120 },
				axis = "y",
				padding = 0,
				gap = 0,
				children = {
					UI.ForEach({
						id = "List",
						items = items,
						key = function(item: any): string
							return item.key
						end,
						row = function(item: any): any
							local kids: { any } = { UI.Text({ id = "Base", text = item.key }) }
							if withExtra then
								table.insert(kids, UI.Text({ id = "Extra", text = "x" }))
							end
							return UI.VStack({ id = "Row", children = kids })
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
		leaveAndReturn = function()
			-- ONE refresh window, two sets: `k` leaves, the shape grows a leaf, `k` returns
			items:set({ { key = "a" } })
			withExtra = true
			items:set({ { key = "a" }, { key = "k" } })
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("O6: a path reused by a DIFFERENT node table is re-derived, not skipped", function()
	it("a key that leaves and returns in one refresh window brings its new leaf with it", function()
		local f = remountFixture()
		expect(f.adapter.node("/S/Host/List/[k]/Row/Extra")).toBe(nil)
		local before = f.controller.stats()
		f.leaveAndReturn()
		local st = f.controller.stats()
		--[[ THE OLD ROW IS GONE AND THE NEW ONE IS WHOLE. `Extra` is the assertion that
			matters: it exists only in the second shape, so a skip that kept the old node's
			subtree would leave it uncreated while every path around it looked correct. ]]
		expect(
			`extra={tostring(f.adapter.node("/S/Host/List/[k]/Row/Extra") ~= nil)}`
				.. ` base={tostring(f.adapter.node("/S/Host/List/[k]/Row/Base") ~= nil)}`
				.. ` ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`
		).toBe("extra=true base=true ssPasses=1 full=0")
		--[[ ...AND ITS PER-PATH FACTS LANDED TOO, which is the OTHER skip. `ensureTree`
			decides whether the new leaf gets a handle; `livePaths` decides whether it gets
			a `scrollHostOf` entry, and a leaf that answers "no host" is a leaf whose window
			position ignores the scroll offset. Read through the public accessor. ]]
		local host = f.controller.scrollHostFor("/S/Host/List/[k]/Row/Extra")
		expect(if host == nil then "no host" else host.path).toBe("/S/Host")
		-- ...and the untouched sibling did NOT grow one, so the case is about the
		-- remounted key rather than about the whole list being rebuilt
		expect(f.adapter.node("/S/Host/List/[a]/Row/Extra")).toBe(nil)
		f.dispose()
	end)
end)

describe("O6: the two facts that let the skip test identity alone", function()
	it("`clipChildren` is NOT reactive, so a clip host cannot appear under an unchanged node", function()
		local spec = (schema.forClass("VStack") :: any).props.clipChildren
		expect(`declared={spec ~= nil} reactive={tostring(spec ~= nil and spec.reactive == true)}`).toBe(
			"declared=true reactive=false"
		)
		--[[ ...and it is a SHARED prop, so the reading is the same for every container
			class rather than for the one this case happened to ask. ]]
		expect(spec.shared).toBe(true)
	end)

	it("a class change builds a NEW node table: `mount.luau` never assigns `.class`", function()
		--[[ The other half, and it is a source pin because there is no route to drive it:
			a mounted node's `class` is written only in the table constructors that BUILD a
			node (`class = bp.class` and the three region literals). An assignment to
			`something.class` would be a class changing under a live node table — the exact
			transition the skip assumes cannot happen. ]]
		local source = fs.readFile("src/mount.luau")
		local offenders: { string } = {}
		for line in string.gmatch(stripComments(source), "\n([^\n]*)") do
			if string.match(line, "[%a_][%w_]*%.class%s*=[^=]") ~= nil then
				table.insert(offenders, string.match(line, "^%s*(.-)%s*$") :: string)
			end
		end
		expect(table.concat(offenders, " | ")).toBe("")
		-- NEGATIVE CONTROL: the scan reports an assignment when there is one
		expect(#(function(): { string }
			local out: { string } = {}
			for line in string.gmatch('\nnode.class = "Box"\n', "\n([^\n]*)") do
				if string.match(line, "[%a_][%w_]*%.class%s*=[^=]") ~= nil then
					table.insert(out, line)
				end
			end
			return out
		end)()).toBe(1)
	end)
end)

describe("O6: a reactive node fact the live-path walk reads schedules its own sync", function()
	it("a backdrop that STOPS sinking stops lifting the button over it", function()
		--[[ THE NUMBERS, DERIVED. `syncZOrder` is a document-order counter with a
			reserved slot per hit-floor class, so the unlifted order is declaration order
			(`Btn` before `Sink`) and the lifted one walks `Btn`'s branch after `Sink`'s.
			Both readings are exact and both are pinned: a relation alone would pass on a
			pair that stopped being ordered at all. ]]
		local f = sinkFixture()
		local before = f.controller.stats()
		expect(f.paintOrder()).toBe("btn=5 sink=3") -- lifted: `Sink` sinks input
		local solves = f.controller.stats().solves
		f.setActive(false)
		local st = f.controller.stats()
		expect(
			`{f.paintOrder()} ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`
				.. ` solves={st.solves - solves}`
		).toBe("btn=4 sink=5 ssPasses=1 full=0 solves=1")
		--[[ ...AND IT STAYS REPAIRED THROUGH A CHURN SOMEWHERE ELSE, which is the half
			that fails without the fix: the bounded sync the churn schedules skips `Sink`
			(same node object), so if the flip had not scheduled its own sync there would
			never be another chance to re-derive it. ]]
		local mid = f.controller.stats()
		f.churn()
		local after = f.controller.stats()
		expect(`{f.paintOrder()} ssPasses={after.ssPasses - mid.ssPasses} full={after.ssFullPasses - mid.ssFullPasses}`).toBe(
			"btn=4 sink=5 ssPasses=1 full=0"
		)
		f.dispose()
	end)

	it("...and a backdrop that STARTS sinking begins lifting it, on its own frame", function()
		-- the other direction, which the hit-lift defect family is equally bitten by:
		-- a sinker invisible to the lift advertises a band it cannot deliver
		local f = sinkFixture()
		f.setActive(false)
		expect(f.paintOrder()).toBe("btn=4 sink=5")
		local before = f.controller.stats()
		f.setActive(true)
		local st = f.controller.stats()
		expect(`{f.paintOrder()} ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`).toBe(
			"btn=5 sink=3 ssPasses=1 full=0"
		)
		f.dispose()
	end)
end)

describe("O6: two structural roots on one chain", function()
	it("a nested region's change survives its ancestor's walk skipping past it", function()
		local f = nestedFixture()
		expect(f.adapter.node("/S/List/Outer/[a]/Row/Inner/[i2]/Leaf")).toBe(nil)
		local before = f.controller.stats()
		f.churnBoth()
		local st = f.controller.stats()
		--[[ the SURVIVING row is the case: its node object never changed, so the outer
			region's walk skips it, and only the inner region being its own root gets the
			new leaf mounted. The NEW row proves the outer half landed at the same time. ]]
		expect(f.adapter.node("/S/List/Outer/[a]/Row/Inner/[i2]/Leaf") ~= nil).toBe(true)
		-- ...and the outer half landed in the same sync: the removed row is gone
		expect(f.adapter.node("/S/List/Outer/[b]/Row")).toBe(nil)
		expect(`ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`).toBe(
			"ssPasses=1 full=0"
		)
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
		local before = f.controller.stats()
		f.addRow()
		local st = f.controller.stats()
		local host = f.controller.scrollHostFor("/S/List/Outer/[c]/Row/Inner/[i1]/Leaf")
		expect(
			`host={if host == nil then "none" else host.path}`
				.. ` ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`
		).toBe("host=/S/List ssPasses=1 full=0")
		f.dispose()
	end)
end)

describe("O6: what the bound does not re-derive still has to be true", function()
	it("when the LAST UI.Path leaves, the latch REOPENS — the sweep's own clear", function()
		--[[ THE OTHER HALF OF `sweepDeparted`'s five per-path clears, and the only one
			with an observable: the whole-tree `table.clear(pathNodes)` a bounded sync no
			longer runs used to be what forgot a departed path's `UI.Path`. If the sweep
			did not clear it and decrement the count, `next(pathNodes) ~= nil` would keep
			`visible`'s whole-surface prune SHUT for the life of the surface — after the
			last ring had left the tree. The ring rides a `When` so it can leave while the
			tree around it stays the same size, which is what makes this a contrast rather
			than a smaller tree. ]]
		local f = scrollFixture(6, { removableRing = true })
		local before = f.controller.stats()
		expect(before.lastCommitVisitsByWalk.visible).toBe(14) -- latch shut: the whole surface
		f.dropRing()
		local st = f.controller.stats()
		expect(
			`visible={st.lastCommitVisitsByWalk.visible} ssPasses={st.ssPasses - before.ssPasses}`
				.. ` full={st.ssFullPasses - before.ssFullPasses}`
		).toBe("visible=4 ssPasses=1 full=0")
		-- ...and it STAYS open on the next structural change, so this is the latch and
		-- not one frame's dirt
		f.add()
		expect(f.controller.stats().lastCommitVisitsByWalk.visible).toBe(5)
		f.dispose()
	end)

	it("a node ABOVE the churn keeps its scroll host across an add and a remove", function()
		--[[ `screenRectOf` subtracts the live scroll offset by walking `scrollHostOf`,
			so a `Head` whose entry was erased answers the UNSHIFTED rect — the same
			number it had before the scroll, which is a wrong answer no rect comparison
			between two solves can see. Driven through the public accessor. ]]
		local f = scrollFixture(6)
		f.adapter.driveScroll("/S/List", { x = 0, y = 40 })
		expect(f.controller.screenRectOf("/S/List/Head").y).toBe(-40)
		local before = f.controller.stats()
		f.add()
		f.remove()
		local st = f.controller.stats()
		expect(
			`y={f.controller.screenRectOf("/S/List/Head").y}`
				.. ` ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`
		).toBe("y=-40 ssPasses=2 full=0")
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
		local before = f.controller.stats()
		f.add()
		local st = f.controller.stats()
		f.adapter.driveScroll("/S/List", { x = 0, y = 100 })
		local gone = f.adapter.visibleOf("/S/List/Head/Ring")
		-- ...and back, so the case cannot pass on a ring that was simply never shown
		f.adapter.driveScroll("/S/List", { x = 0, y = 0 })
		expect(
			`out={tostring(gone)} back={tostring(f.adapter.visibleOf("/S/List/Head/Ring"))}`
				.. ` ssPasses={st.ssPasses - before.ssPasses} full={st.ssFullPasses - before.ssFullPasses}`
		).toBe("out=false back=true ssPasses=1 full=0")
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
		--[[ PINNED EXACTLY rather than against a floor (review CF1). The brief wrote this
			case as `> floor` before the number was derivable, and a threshold where `toBe`
			is available is the rubric's own defect. The numbers ARE derivable and the
			contrast is the whole point: with the latch CLOSED the walk visits the mounted
			tree (1,503 plus the churn's own nodes); the SAME drives on a scene with no
			`UI.Path` visit 9 and 3, which is the dirty closure a pruning `visible` stops
			at. A broken latch is that 1,510 collapsing to 9, silently. ]]
		local s = scene.new({ withPath = true })
		s.tick(3, 2)
		local b1 = s.stats()
		s.add(1)
		local a1 = s.stats()
		local b2 = s.stats()
		s.remove(2)
		local a2 = s.stats()
		expect(
			`add={a1.lastCommitVisitsByWalk.visible} remove={a2.lastCommitVisitsByWalk.visible}`
				.. ` ssPasses={a1.ssPasses - b1.ssPasses}/{a2.ssPasses - b2.ssPasses}`
				.. ` full={a2.ssFullPasses - b1.ssFullPasses}`
		).toBe("add=1510 remove=1504 ssPasses=1/1 full=0")
		s.dispose()
		--[[ THE OTHER ARM OF THE SAME COMPARISON, in the same case so the two numbers
			cannot drift apart: the identical drives on a scene with no stroked path. ]]
		local plain = scene.new()
		plain.tick(3, 2)
		plain.add(1)
		local plainAdd = plain.stats().lastCommitVisitsByWalk.visible
		plain.remove(2)
		expect(`add={plainAdd} remove={plain.stats().lastCommitVisitsByWalk.visible}`).toBe("add=9 remove=3")
		plain.dispose()
	end)
end)
