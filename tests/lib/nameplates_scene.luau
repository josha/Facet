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
	the steady 1252 (`MEASURED_STEADY = LAYOUT - PLATES`). The scene's own
	baseline is `MEASURED_STEADY`, not `MEASURED_COLD` — see the spec's "a pure
	tick" case (which discards one warm-up tick before pinning) versus its "the
	first tick after mount pays a one-time cold solve" case.

	`lastNodeBuilds` is NOT the cold/steady lever — probed directly (Fix round 1):
	it reads the SAME 252 (the 250 moved plates + Canvas + Screen, `dirtyContains`)
	on the cold first tick, on a steady pure tick, and on every steady pure tick
	after that; only a CASTER tick moves it, to 302 (the 50 caster boxes joining
	`dirtyContains`). So the 750-measure gap between cold and steady is not a
	rebuilt-node story. The COLD number IS instrumented (`solver.measureUncached`,
	temporary counter, reverted before commit): 1502 distinct nodes measured once
	PLUS the 500 `Hp`/`Cast` boxes a second time (the vstack arrange branch
	above) — see the spec's cold case for the full by-kind breakdown. WHY THE
	STEADY NUMBER IS 250 LOWER THAN A FULL PASS (1252 = LAYOUT - PLATES, i.e.
	every plate's five descendants but not the plate root itself) is NOT
	instrumented; the spec pins the arithmetic, not the mechanism. A caller
	comparing two ticks against each other (T2's own fourth case did, originally,
	comparing `lastMeasured`) must either take both from the steady state or
	expect the first to be inflated — and even then, before T3, a pure and a
	caster tick read the identical steady `lastMeasured`; `lastNodeBuilds` is the
	counter a caster tick actually moves today. ]]
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
	withPath: boolean?, -- add one UI.Path leaf: the `visible` prune latch closes
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
			name = `Racer {i}`,
			lvl = tostring(10 + (i % 30)),
		}
	end
	local rows = core:signal(items)

	local function offsetOf(item: any, axis: "x" | "y"): any
		local sig = if axis == "x" then item.x else item.y
		if not o.fractional then
			return sig
		end
		-- the RascalRally minimap idiom (`FacetSponsor/MapCanvas.luau:230-236`):
		-- a scaleOffset metric, so `offsetPx` resolves it against the anchor's
		-- inner extent and the answer is viewport-dependent
		return core:memo(function(use: any)
			local v = use(sig) :: number
			return { scale = v / 1280, offset = -9 }
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
				return UI.VStack({
					id = "Plate",
					anchor = "topLeft",
					offsetX = offsetOf(item, "x"),
					offsetY = offsetOf(item, "y"),
					padding = 0,
					gap = 2,
					width = px(if item.key == "p1" then plateWidth else 180),
					height = { type = "content" },
					children = {
						UI.HStack({
							id = "Row",
							padding = 0,
							gap = 4,
							width = fill(),
							height = px(16),
							children = {
								UI.Text({ id = "Name", textSize = 14, text = item.name }),
								UI.Text({ id = "Lvl", textSize = 12, text = item.lvl }),
							},
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
					},
				})
			end,
		}),
	}
	if o.withPath then
		-- one stroked path anywhere on the surface shuts `visible`'s prune for the
		-- life of the surface (`commit_walks.luau:842`, `local prunable = next(pathNodes) == nil`).
		-- The points come from `src/controls/path_shapes` rather than two literals:
		-- `UI.Path`'s own doc says `points` are normalized Path2D control points from
		-- `Facet.pathShapes` (`blueprint_schema.luau:2615-2621`), and it is the idiom
		-- `tests/commit_scope.spec.luau:759` already uses for exactly this latch.
		table.insert(children, UI.Path({ id = "Spark", points = path_shapes.ring(), thickness = 2 }))
	end
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
	function scene.snapshot(): string
		local out = {}
		for path, node in adapter.liveNodes() do
			local props = {}
			for k, v in node.props or {} do
				if type(v) == "table" then
					local inner = {}
					for k2, v2 in v do
						table.insert(inner, `{tostring(k2)}={tostring(v2)}`)
					end
					table.sort(inner)
					table.insert(props, `{k}=\{{table.concat(inner, ",")}\}`)
				else
					table.insert(props, `{k}={tostring(v)}`)
				end
			end
			table.sort(props)
			local r, hit, region = node.rect, node.hitRect, node.scrollRegion
			table.insert(
				out,
				`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`
					.. `|vis={tostring(node.visible)}`
					.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
					.. `|canvas={if region then `{region.contentW},{region.contentH}` else "-"}`
			)
		end
		table.sort(out)
		return table.concat(out, "\n")
	end

	function scene.dispose()
		controller.dispose()
		root.dispose()
	end

	return scene
end

return nameplates_scene
