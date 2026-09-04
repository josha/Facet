--!strict
--[[ THE NAMEPLATES SCENE — the arena's workload, headless, as a Facet fixture.

	`FacetBench/frameworks/facet/adapter.luau:48-90` maps the bench's `canvas` to
	`UI.Anchor` and its `list` to `UI.ForEach` with the placement props on the
	TEMPLATE ROOT, and `layout_node.luau:1263-1275` splices a ForEach's children
	into the enclosing flow — so the layout tree is one `anchor` with 250 direct
	plate roots, each an `hstack`/`vstack` carrying `anchor = "topLeft"` plus a
	reactive `offsetX`/`offsetY`. That is the tree every demonstrator in the
	wicked-fast round pins, so it lives here rather than in one spec.

	THE MOUNTED SHAPE, WHICH IS NOT THE LAYOUT SHAPE, AND THE COUNTS DEPEND ON IT.
	`mount.luau:273-281` builds ONE region node for the ForEach (`class="ForEach"`,
	`path` = the ForEach's own path) whose `children` array (assigned at `:452`) is
	the rows' own roots. `mount.luau:357` builds `rowPath = `{path}/[{key}]`` and
	passes it to `mountNode` as a PARENT path, and `mountNode` computes
	`path = parentPath .. "/" .. id` (`:595-596`) — so **there is no per-item
	wrapper node**: the row's `Plate` sits directly in the region's children at
	`…/[p1]/Plate`, and `…/[p1]` is a path string with nothing mounted at it.
	MOUNTED is therefore LAYOUT + 1 (the region), and the 250 `…/[pN]` strings
	`markNodeDirty` writes can never become commit visits.

	AND THERE IS A `UI.Screen` ROOT, because `mountLib.mount(core, bp)` mounts the
	blueprint it is handed at `"" .. "/" .. id` (`mount.luau:713-714`, `:596`) —
	the root node IS whatever it is given. Every sibling perf spec wraps in a
	Screen (`tests/commit_scope.spec.luau:739`, RR
	`facet_measure_fanout_contract.spec.luau:110`), so this one does too rather
	than being the only fixture whose root is an Anchor.

	TWO UPDATE STEPS, BECAUSE A TICK IS NOT 250 PURE TRANSLATES (profile §1/§6).
	`tick` moves every plate and touches nothing else. `tickWithCasts` moves every
	plate AND advances the Cast bar of a deterministic one-in-five subset — a
	MEASURE-class write (`{ type = "fixed", px = cast * 100 }`) whose dirt closes
	over the bar's ancestors up to the plate root. Roughly 20 % of the arena's
	plates are casters (41-43 live at L, seeded); here the set is exact — 50 —
	because a pinned count is worth more to a demonstrator than a matched sample.

	NO FIXED x FIXED ANCESTOR ABOVE A PLATE, ON PURPOSE — AND THE TWO FIXED x FIXED
	LEAVES STILL COUNT UNTIL T4. `measure_facts.luau:409-412` classifies a
	fixed-width AND fixed-height non-text node `PLAN_SKIP`, and
	`solver.luau:1720-1722` sends a PLAN_SKIP node straight to `measureUncached`,
	which increments `ctx.measured` EVERY time it is touched — no memo, no slate,
	no dirty test. The anchor branch measures all 250 children on every arrange, so
	a fixed x fixed Canvas or plate root would make a small `lastMeasured` pin
	unreachable by construction and the T3 demonstrator would be measuring the
	fixture. The Canvas fills and the plate root is fixed-width + content-height,
	which is what that constraint buys.

	`Hp` and `Cast` ARE fixed x fixed, and the earlier claim that they "sit at the
	LEAVES where nothing re-enters them" is FALSE UNTIL T4 LANDS: a moved plate
	root fails the arrange skip, takes the vstack arrange branch, and that branch
	measures each non-hug child (`solver.luau:3290-3340`). So both are touched, per
	plate, per tick — `lastMeasured == PLATES * 2` on a pure tick after T3, and
	only T4's translate arm (which stops re-entering the subtree at all) takes it
	to 0. T3's spec pins the 500; T4's pins the 0.

	THE FIRST TICK IS COLD, AND EVERY LATER ONE IS THE STEADY NUMBER — pinned by
	two SEPARATE cases in `tests/nameplates_baseline.spec.luau` rather than one
	(discovered running T2's baseline spec, 2026-09-02; corrected in Fix round 1
	after the controller's own probe, since the round's "currently N" has to be
	the number every later demonstrator actually ticks against, not a one-time
	first-frame cost). `scene.new()` -> `controller.attach` does its own solve
	(`controller.initialRender()`), which fills `lastResult` but is not itself a
	REUSE solve. `lastMeasured` on the first `tick`/`tickWithCasts` call after
	that reads 2002 (the COLD number, `MEASURED_COLD`); every tick after it reads
	the steady 500 on a pure tick and 652 on a caster tick (`MEASURED_STEADY` /
	`MEASURED_STEADY_CASTERS`, both moved off a shared 1252 by T3's measure/arrange
	dirt split). The scene's own baseline is that steady pair, not `MEASURED_COLD` —
	see the spec's "a pure tick" case (which discards one warm-up tick before
	pinning) versus its "the first tick after mount pays a one-time cold solve" case.

	`lastNodeBuilds` is NOT the cold/steady lever — probed directly (Fix round 1):
	it reads the SAME 252 (the 250 moved plates + Canvas + Screen, `dirtyContains`)
	on the cold first tick, on a steady pure tick, and on every steady pure tick
	after that; only a CASTER tick moves it, to 302 (the 50 caster boxes joining
	`dirtyContains`). So the 750-measure gap between cold and steady is not a
	rebuilt-node story. The COLD number IS instrumented (`solver.measureUncached`,
	temporary counter, reverted before commit): 1502 distinct nodes measured once
	PLUS the 500 `Hp`/`Cast` boxes a second time (the vstack arrange branch
	above) — see the spec's cold case for the full by-kind breakdown. THE STEADY
	NUMBER IS NOW INSTRUMENTED TOO (T3, the same bucket technique): the pre-split
	1252 read as `LAYOUT - PLATES`, but that identity was a coincidence of two
	unrelated terms — 1000 PLAN_SKIP touches on the `Hp`/`Cast` boxes (twice each,
	the plate's measure pass and its arrange pass) plus 252 slate refusals — and
	`tests/measure_split.spec.luau` carries the bucket table for each tick kind. A
	caller comparing two ticks against each other (T2's own fourth case did,
	originally, comparing `lastMeasured`) must either take both from the steady
	state or expect the first to be inflated. Before T3 a pure and a caster tick
	read the identical steady `lastMeasured` and only `lastNodeBuilds` separated
	them; after T3 both counters do. ]]
local UI = require("../../src/blueprint")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local renderer = require("../../src/render/renderer")
local customFactory = require("../../src/core/custom")
local path_shapes = require("../../src/controls/path_shapes")
local fake_target = require("./fake_target")

local nameplates_scene = {}

nameplates_scene.PLATES = 250
nameplates_scene.NODES_PER_PLATE = 6 -- Plate, Row, Name, Lvl, Hp, Cast
nameplates_scene.CASTER_EVERY = 5 -- every 5th plate advances its cast bar

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

export type Opts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	plates: number?,
	incremental: boolean?, -- renderer.attach `incrementalLayout` (default true)
	measureReuse: boolean?, -- default true
	commitScope: boolean?, -- default true
	fractional: boolean?, -- offsets as { scale, offset } instead of plain px
	overflow: boolean?, -- plate 1 is 2,000 px wide: its subtree leaves the anchor
	--[[ add one `UI.Path` leaf UNDER PLATE 3 — inside a coordinate-space host, not
		beside the ForEach where it first sat. Two latches want it and they want it in
		the same place: `visible`'s prune (`commit_walks.luau`, `local prunable =
		next(pathNodes) == nil`) closes wherever the Path is, and the translate lane's
		`spaceHostHasPath` gate can only be exercised by a Path that has a space host
		above it. Moved rather than duplicated so there is ONE Path fixture: a second
		one would let the two latches drift apart. ]]
	withPath: boolean?,
	-- plate 3's Row carries a 20x16 `UI.Button`: below the hit floor, so the
	-- `hitRects` walk gives it an EXPANDER — the lane's `hit_lift` serve needs an
	-- expander to exist somewhere on the surface, and one on a DESCENDANT of a
	-- moving host (never on the host itself) is what row 10 of the owed list says
	-- lanes rather than refuses.
	withButton: boolean?,
	-- every plate root binds `anchor` to a signal (default "topLeft") so an anchor
	-- FLIP is a placement write the lane must take. Off, the prop is the literal
	-- every other spec pins.
	reactiveAnchor: boolean?,
	--[[ carry a reactive `lineAlign` on every plate root, and expose `scene.align`.
		`lineAlign` under an `Anchor` parent is INERT — the anchor branch reads
		`anchor`/`offsetX`/`offsetY` and nothing else — so driving it DIRTIES every
		plate and MOVES nothing, which is the solver's `dx = dy = 0` translate arm
		(`tests/translate_arm.spec.luau` drives the same shape on a ScrollView and a
		Composition). It is the only drive on this fixture that produces a translate
		run whose every rect is already on screen, which is what `rect_pass`'s
		minimal-write contract has to survive. ]]
	inertAlign: boolean?,
	--[[ THE COORDINATE-SPACE TRIGGER (Plan C), default ON — threaded straight to
		`renderer.attach`'s `translateHosts`. It exists so an oracle can raise the
		SAME reactive fixture with no coordinate-space hosts at all and drive it
		through the IDENTICAL step list: a mount-only comparison against a different
		world (static offsets) would prove nothing about the only thing that changed,
		which is a MOVE. Off, every plate root is an ordinary node again and every
		rect is stored in window space. ]]
	hosts: boolean?,
}

-- `layout` is the LAYOUT-NODE count (`stats().lastLayoutNodes`, i.e. the solver's
-- `nodeStore.nodes`); `nodeBuilds` is what `stats().lastNodeBuilds` reports — the
-- number of node tables CONSTRUCTED on the last build, which is near zero on a
-- steady tick with a warm P3 store and is not a tree size at all. They had the
-- same name in an earlier draft of this fixture, which is exactly how a census
-- stops being a census.
export type Census = { mounted: number, layout: number, nodeBuilds: number, plates: number, casters: number }

function nameplates_scene.new(opts: Opts?)
	local o: Opts = opts or {}
	local n = o.plates or nameplates_scene.PLATES
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 1280, h = 720 })

	local items = {}
	for i = 1, n do
		local caster = i % nameplates_scene.CASTER_EVERY == 0
		items[i] = {
			key = `p{i}`,
			caster = caster,
			x = core:signal((i * 37) % 1200),
			y = core:signal((i * 53) % 680),
			hp = core:signal(0.5 + ((i % 7) / 14)),
			cast = core:signal(if caster then 0.25 else 0),
			-- see `scene.hide`: authored `hidden`, false on every plate, so the tree
			-- this fixture mounts is the one every earlier pin was taken on
			hidden = core:signal(false),
			-- ...and see `scene.nudgeLabel`: a placement prop on a TEXT LEAF
			labelAlign = core:signal("start"),
			-- see `Opts.reactiveAnchor`/`scene.anchorFlip`
			anchor = core:signal("topLeft"),
			name = `Racer {i}`,
			lvl = tostring(10 + (i % 30)),
		}
	end
	local rows = core:signal(items)
	-- see `Opts.inertAlign`: bound only when the opt is on, so the default tree is
	-- byte-identical to what every other spec pins.
	local alignSignal = core:signal("start")

	local function offsetOf(item: any, axis: "x" | "y"): any
		local sig = if axis == "x" then item.x else item.y
		if not o.fractional then
			return sig
		end
		-- the RascalRally minimap idiom (`FacetSponsor/MapCanvas.luau:230-236`):
		-- a scaleOffset metric, so `offsetPx` resolves it against the anchor's
		-- inner extent and the answer is viewport-dependent
		return core:memo(function(use: any)
			local v = use(sig)
			-- ...and NIL PASSES THROUGH AS NIL, because `scene.clearOffset` is a real
			-- drive on this fixture too: dividing a cleared offset by the viewport
			-- quarantines the memo, and a quarantined memo makes the step it was driving
			-- prove nothing.
			if v == nil then
				return nil
			end
			return { scale = (v :: number) / 1280, offset = -9 }
		end)
	end

	local plateWidth = if o.overflow then 2000 else 180
	local children: { any } = {
		UI.ForEach({
			id = "Plates",
			items = rows,
			key = function(item: any)
				return item.key
			end,
			row = function(item: any)
				local rowChildren: { any } = {
					UI.Text({ id = "Name", textSize = 14, text = item.name }),
					UI.Text({ id = "Lvl", textSize = 12, text = item.lvl, lineAlign = item.labelAlign }),
				}
				if o.withButton and item.key == "p3" then
					table.insert(rowChildren, UI.Button({ id = "Btn", width = px(20), height = px(16), label = "b" }))
				end
				local plateChildren: { any } = {
					UI.HStack({
						id = "Row",
						padding = 0,
						gap = 4,
						width = fill(),
						height = px(16),
						children = rowChildren,
					}),
					UI.Box({
						id = "Hp",
						height = px(6),
						width = core:memo(function(use: any)
							return px(100 * (use(item.hp) :: number))
						end),
					}),
					UI.Box({
						id = "Cast",
						height = px(4),
						width = core:memo(function(use: any)
							return px(100 * (use(item.cast) :: number))
						end),
					}),
				}
				if o.withPath and item.key == "p3" then
					-- see `Opts.withPath`: the points come from `src/controls/path_shapes`
					-- rather than two literals, because `UI.Path`'s own doc says `points`
					-- are normalized Path2D control points from `Facet.pathShapes`
					-- (`blueprint_schema.luau:2615-2621`), and it is the idiom
					-- `tests/commit_scope.spec.luau:759` already uses for this latch.
					table.insert(plateChildren, UI.Path({ id = "Spark", points = path_shapes.ring(), thickness = 2 }))
				end
				return UI.VStack({
					id = "Plate",
					anchor = if o.reactiveAnchor then item.anchor else "topLeft",
					offsetX = offsetOf(item, "x"),
					offsetY = offsetOf(item, "y"),
					lineAlign = if o.inertAlign then alignSignal else nil,
					hidden = item.hidden,
					padding = 0,
					gap = 2,
					width = px(if item.key == "p1" then plateWidth else 180),
					height = { type = "content" },
					children = plateChildren,
				})
			end,
		}),
	}
	local bp = UI.Screen({
		id = "S",
		children = { UI.Anchor({ id = "Canvas", width = fill(), height = fill(), children = children }) },
	})

	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = o.incremental ~= false,
		measureReuse = o.measureReuse ~= false,
		layoutNodeReuse = true,
		commitScope = o.commitScope ~= false,
		translateHosts = o.hosts ~= false,
	})
	controller.initialRender()

	local scene: any = {
		core = core,
		env = env,
		adapter = adapter,
		controller = controller,
		items = items,
		rows = rows,
	}

	function scene.tick(dx: number, dy: number)
		for _, item in items do
			item.x:set((item.x:get() :: number) + dx)
			item.y:set((item.y:get() :: number) + dy)
		end
		controller.refresh()
	end

	function scene.tickWithCasts(dx: number, dy: number)
		for _, item in items do
			item.x:set((item.x:get() :: number) + dx)
			item.y:set((item.y:get() :: number) + dy)
			if item.caster then
				-- 0.05 per tick, wrapping: never an equal write (an equal write is
				-- skipped by the signal and the caster would silently stop being one)
				local next_ = (item.cast:get() :: number) + 0.05
				item.cast:set(if next_ > 1 then 0.05 else next_)
			end
		end
		controller.refresh()
	end

	-- THE ZERO-DELTA DRIVE (`Opts.inertAlign`). Every plate root is dirtied and none
	-- of them moves, so all 250 take the translate arm with `dx = dy = 0` and every
	-- re-based descendant lands on the rect it is already painted at.
	function scene.align(value: string)
		alignSignal:set(value)
		controller.refresh()
	end

	--[[ THE ONE ARRANGE-CLASS PROP THE COMMIT'S SET KEEPS (wicked-fast T5b).
		`hidden` is `dirty = { "arrange" }` like `offsetX`, but `harvest`, `visible`
		and `hitRects` all read it, so it is the one arrange prop the commit-side
		dirty set must NOT drop. This is the drive that says so.

		NO EARLIER PIN MOVES. The prop is authored `false` on every plate and no
		other step here writes it — `authoredHidden` only ever registers a `true`
		(`renderer.luau`, the mount sweep and the `hiddenTouched` re-read), so a
		fixture that never calls this method mounts and solves exactly as it did
		before the signal existed. ]]
	function scene.hide(i: number, on: boolean)
		items[i].hidden:set(on)
		controller.refresh()
	end

	--[[ A PURE-ARRANGE PROP ON A TEXT LEAF (wicked-fast T5b, review round 1, I1).
		Every other placement drive on this fixture writes the plate ROOT — a VStack
		container — and the four arrange-blind walks write for `Text`, `Button` and
		`ScrollView` and for nothing else, so no earlier step here moves a placement
		prop on a node whose walk output can be observed. `lineAlign` on the `Name`
		Text is that step: an HStack reads its child's `lineAlign` on the cross axis
		(`solver.luau:3497`, `child.lineAlign or child.align or node.align`).

		IT IS ON `Lvl`, NOT `Name`, AND THE 1px IS THE WHOLE REASON. `Row` is 16px
		tall; `Name` measures 61x16 and fills it, so a cross-axis alignment has NO
		ROOM there and the drive would be INERT — a step that moves nothing makes
		every differential taken across it vacuous. `Lvl` measures 15x15 in the same
		16px row, so "start" -> "end" moves it by exactly one pixel, which is a
		difference a snapshot can see. The spec that drives this asserts the move
		rather than assuming it.

		BOUND AT `"start"` AND INERT UNTIL DRIVEN, so no earlier pin moves — measured
		by re-running `nameplates_baseline`, `commit_translate` and this task's own
		spec before and after the binding was added. ]]
	function scene.nudgeLabel(i: number, value: string)
		items[i].labelAlign:set(value)
		controller.refresh()
	end

	--[[ AN ANCHOR FLIP IS A PLACEMENT WRITE (Plan C, T5). `anchor` is `dirty =
		{ "arrange" }` exactly as `offsetX` is, and it is the one placement prop whose
		new value changes the plate's rect through a DIFFERENT term of
		`placement.anchorPlace` — the factor rather than the offset — so a lane that
		re-derived the offset alone would place it wrong. Needs `Opts.reactiveAnchor`;
		with the prop authored as a literal there is nothing to write.

		"topLeft" <-> "top" and not, say, "bottomRight": the plate is 180 px wide in a
		1280 px anchor, so the horizontal factor moves it by 550 px, which is a
		difference any rect column can see, while the vertical factor stays 0 so the
		plate cannot leave the box and trip the containment gate. ]]
	function scene.anchorFlip(i: number)
		local item = items[i]
		item.anchor:set(if item.anchor:get() == "topLeft" then "top" else "topLeft")
		controller.refresh()
	end

	-- ...and the drive that DOES leave the parent's inner box: the lane refuses a
	-- host whose old or new rect is not fully inside it, because that is the frame
	-- the solve would have filed (or withdrawn) a containment finding on.
	function scene.moveOut(i: number)
		items[i].x:set(-500)
		controller.refresh()
	end

	--[[ THE NIL-FLIP DRIVE. `layout_node.build` derives `placementProps` — a nine-prop
		PRESENCE flag — and the parent-side `inertPlacement` audit from these props, and
		both move only when a prop APPEARS or DISAPPEARS. The lane serves values, not
		presence, so this write has to reach the solve. ]]
	function scene.clearOffset(i: number)
		scene.setOffsetX(i, nil)
	end

	-- ...and the write back, which the nil-flip drive NEEDS: `tick` reads
	-- `item.x:get() + dx`, so a plate left at `nil` makes every later tick an
	-- arithmetic error on nil. A driver that clears an offset restores it.
	function scene.setOffsetX(i: number, value: number?)
		items[i].x:set(value)
		controller.refresh()
	end

	function scene.hp(i: number, fraction: number)
		items[i].hp:set(fraction)
		controller.refresh()
	end

	function scene.add(i: number)
		local caster = i % nameplates_scene.CASTER_EVERY == 0
		local item = {
			key = `add{i}`,
			caster = caster,
			x = core:signal((i * 11) % 1200),
			y = core:signal((i * 17) % 680),
			hp = core:signal(0.5),
			cast = core:signal(if caster then 0.25 else 0),
			hidden = core:signal(false),
			labelAlign = core:signal("start"),
			anchor = core:signal("topLeft"),
			name = `Added {i}`,
			lvl = "1",
		}
		local next_ = table.clone(rows:get() :: any)
		table.insert(next_, item)
		rows:set(next_)
		-- KEEP `items` IN SYNC (wicked-fast T2, Fix round 2, I-2). `tick`,
		-- `tickWithCasts` and `census` all read the OUTER `items` local, not
		-- `rows`'s own value — `rows` is the REACTIVE signal the ForEach binds
		-- to, `items` is this module's own iteration table, and the two used to
		-- diverge the moment either method ran: `rows` grew or shrank, `items`
		-- did not, so a tick after an `add` moved every OLD plate and silently
		-- left the new one standing still, and `census().plates` (`= #items`)
		-- kept reporting the pre-add count. The caster flag needs no separate
		-- re-derivation — it already lives on each item in `next_`, added at
		-- construction time above — so reassigning `items` is the whole fix.
		items = next_
		scene.items = items -- the public snapshot must not lag either
		controller.refresh()
	end

	function scene.remove(i: number)
		local next_ = table.clone(rows:get() :: any)
		table.remove(next_, i)
		rows:set(next_)
		-- see `scene.add`'s comment: `items` must track `rows`, not lag it.
		items = next_
		scene.items = items
		controller.refresh()
	end

	function scene.census(): Census
		local mounted = 0
		local function walk(node: any)
			mounted += 1
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
		local casters = 0
		for _, item in items do
			if item.caster then
				casters += 1
			end
		end
		local st = controller.stats() :: any
		return {
			mounted = mounted,
			layout = st.lastLayoutNodes,
			nodeBuilds = st.lastNodeBuilds,
			plates = #items,
			casters = casters,
		}
	end

	function scene.stats(): any
		return controller.stats()
	end

	-- every live node's rect and every per-path fact the eight walks own — the
	-- COMMIT oracle, not just the solver's (copied from `commit_scope.spec`'s
	-- `painted` so the two read the same channels)
	--[[ BY VALUE, TO THE BOTTOM — and it used to stop one level down. A prop table
		was flattened as `k2=tostring(v2)`, so a prop whose value is a table OF tables
		(`UI.Path`'s `points`, nine `{ x, y }` records) serialized as nine table
		ADDRESSES. Two arms of an oracle build their own point tables, so the
		`withPath` fixture compared unequal at MOUNT, before any solve had run — a
		snapshot that reports an identity difference as a paint difference is not an
		oracle channel. Recursion with sorted keys makes it a value compare at any
		depth; the depth bound is belt-and-braces against a cyclic prop, which no
		blueprint prop is. ]]
	local function ser(v: any, depth: number): string
		if type(v) ~= "table" then
			return tostring(v)
		end
		if depth <= 0 then
			return "…"
		end
		local inner = {}
		for k, item in v do
			table.insert(inner, `{tostring(k)}={ser(item, depth - 1)}`)
		end
		table.sort(inner)
		return `\{{table.concat(inner, ",")}\}`
	end

	local function fmtRect(r: any): string
		return if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`
	end

	--[[ THE PUBLIC CHANNELS JOINED THE SNAPSHOT WITH PLAN C, and each is here for a
		reason a raw-rect column cannot serve:

		  `pos`/`psize` — the ENGINE window position and size the adapter composed. A
		    stored rect that becomes host-relative is an internal change; what a
		    player sees is this, and it must not move.
		  `focus` — the focus flags, which `presentation_channel` writes for a node
		    whose rect it read; a focused node inside a moved host is the reader that
		    would show it if that channel had learned the wrong space.
		  `ro`/`sro` — `controller.rectOf` and `controller.screenRectOf`, the two
		    PUBLIC reads the whole campaign promises not to move.
		  `diag` — `controller.diagnostics()`, which is where the absolute readers
		    (the composition resolver's `atRoot`, the audits) would file a different
		    finding if a rect reached them in the wrong space.

		AND `pos == sro` IS ASSERTED AS AN IDENTITY, per line, emitting `POSMISMATCH`
		into the line when it does not hold. Two arms of an oracle can go stale in
		step with each other — the fake composes `presentedPosition` at `setRect`, and
		under Plan C a host move produces ONE `setRect` — so the only honest
		instrument is one that checks the fake's composed position against the public
		reader rather than against another arm. ]]
	function scene.snapshot(): string
		local out = {}
		local diag = controller.diagnostics()
		local diagKeys = {}
		for _, finding in diag do
			table.insert(diagKeys, `{finding.node}:{finding.issue}`)
		end
		table.sort(diagKeys)
		local diagKey = table.concat(diagKeys, ";")
		for path, node in adapter.liveNodes() do
			local props = {}
			for k, v in node.props or {} do
				table.insert(props, `{k}={ser(v, 6)}`)
			end
			table.sort(props)
			-- `storedRect` is the column arm `e` (no coordinate-space hosts) is EXPECTED
			-- to differ on — it is the change. `node.rect` is the WINDOW rect on both
			-- targets, so it belongs with the public reads below.
			local r, hit, region = node.storedRect, node.hitRect, node.scrollRegion
			local pp, ps = node.presentedPosition, node.presentedSize
			local sro = controller.screenRectOf(path)
			local posOk = pp == nil or sro == nil or (pp.x == sro.x and pp.y == sro.y)
			table.insert(
				out,
				`{path}|{fmtRect(r)}|{table.concat(props, ",")}`
					.. `|vis={tostring(node.visible)}`
					.. `|hit={fmtRect(hit)}`
					.. `|canvas={if region then `{region.contentW},{region.contentH}` else "-"}`
					.. `|pos={if pp then `{pp.x},{pp.y}` else "-"}`
					.. `|psize={if ps then `{ps.w},{ps.h}` else "-"}`
					.. `|focus={tostring(node.focused)},{tostring(node.focusProfile)},{tostring(node.focusLift)}`
					.. `|ro={fmtRect(controller.rectOf(path))}`
					.. `|sro={fmtRect(sro)}`
					.. (if posOk then "" else "|POSMISMATCH")
			)
		end
		table.sort(out)
		table.insert(out, `diagKey={diagKey}`)
		return table.concat(out, "\n")
	end

	-- the STORED rect column alone, which arm `e` (no coordinate-space hosts) is
	-- EXPECTED to differ on — that difference is the change. Everything else in
	-- `snapshot()` must match it exactly.
	function scene.publicSnapshot(): string
		local out = {}
		for _, line in string.split(scene.snapshot(), "\n") do
			local head, tail = string.match(line, "^([^|]*)|[^|]*|(.*)$")
			table.insert(out, if head == nil then line else `{head}|{tail}`)
		end
		return table.concat(out, "\n")
	end

	function scene.dispose()
		controller.dispose()
		root.dispose()
	end

	return scene
end

return nameplates_scene
