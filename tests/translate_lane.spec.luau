--!strict
--[[ THE TRANSLATE LANE (Plan C, C6): a refresh whose only layout-class dirt is a
	placement prop on coordinate-space hosts SOLVES NOTHING. Per host the lane
	re-places it with `placement.anchorPlace` — the solver's own function — writes
	the solver's entry in place, and calls `setRect` once. Anything else that would
	need a solve is handed to the solve as the REMAINDER, so a caster tick lanes
	200 plates and solves the 50 casters in one incremental solve.

	THE LIST OF WHAT THE SKIPPED FUNCTIONS PUBLISH, with the verdict per channel,
	is in the campaign ledger
	(`.superpowers/sdd/2026-09-03-facet-parity-C/progress.md`, "Task 5 — the owed
	list", 27 rows) and is what every case below drives.

	HOW "SOLVES NOTHING" IS MEASURED, AND WHAT IS DELIBERATELY NOT MEASURED. Every
	pin is a DELTA of `stats.solves` across the drive, plus the per-refresh
	`stats.lastLaneTranslates`. Never `stats.lastCommitVisits == 0`: the whole
	`stats.last*` family reports the PREVIOUS solve by doctrine and the lane does
	not zero it, so a pin on it would pass for the wrong reason on a frame the lane
	never ran. A commit runs only inside `solveAndApply`, so a `solves` delta of 0
	IS "no commit ran". The entry-identity claim is proved on the NEXT solve, not
	on the lane tick. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local path_shapes = require("../src/controls/path_shapes")
local fake_target = require("./lib/fake_target")
local fs = require("@lune/fs")
local motionClock = require("../src/motion/clock")

local PLATES, CASTERS = scene.PLATES, scene.PLATES // scene.CASTER_EVERY

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

-- the four counters that say what a refresh did, as DELTAS across `fn`
local function deltas(s: any, fn: () -> ()): string
	local a, ew = s.stats(), s.adapter.engineWrites()
	fn()
	local b = s.stats()
	return `solves={b.solves - a.solves} lane={b.lastLaneTranslates} rectWrites={b.rectWrites - a.rectWrites}`
		.. ` engineWrites={s.adapter.engineWrites() - ew}`
end

-- the same hand-built world every spec in this tree uses
-- (`tests/translate_host.spec.luau:60-88`): one core, one environment, the real
-- mount, the fake target and `renderer.attach`.
local function world(build: (any) -> any, viewport: any?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", viewport or { x = 0, y = 0, w = 400, h = 300 })
	local root = mountLib.mount(core, build(core))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	return {
		core = core,
		env = env,
		adapter = adapter,
		controller = controller,
		stats = function()
			return controller.stats()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("translate lane: an all-placement tick solves nothing", function()
	it("a pure tick solves nothing: one lane translate, one rect, one engine write per plate", function()
		local s = scene.new()
		s.tick(3, 2) -- warm: the first tick after mount pays the cold solve
		expect(deltas(s, function()
			s.tick(3, 2)
		end)).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)

	it("a caster tick lanes the movers and solves only the casters", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		--[[ READ OFF THE RUN, and it is not the arithmetic the plan predicted. ALL 250
			plate roots lane, casters included: the lane keys on the ENTRY, and a caster's
			extra dirt is a MEASURE write on its `Cast` bar — a different path. What
			reaches the solve as the remainder is those 50 measure entries, so the frame
			solves once, for the bars, and the 250 rect writes the lane already made are
			not repeated (`rect_pass.applyOne` compares by value and finds them equal).
			300 = the 250 laned hosts + the 50 resized bars. ]]
		expect(deltas(s, function()
			s.tickWithCasts(3, 2)
		end)).toBe(`solves=1 lane={PLATES} rectWrites={PLATES + CASTERS} engineWrites={PLATES + CASTERS}`)
		s.dispose()
	end)

	it("an anchor flip is a placement write and lanes", function()
		local s = scene.new({ reactiveAnchor = true })
		s.tick(3, 2)
		expect(deltas(s, function()
			s.anchorFlip(7)
		end)).toBe("solves=0 lane=1 rectWrites=1 engineWrites=1")
		s.dispose()
	end)

	it("a fractional (scaleOffset) offset lanes", function()
		local s = scene.new({ fractional = true })
		s.tick(3, 2)
		expect(deltas(s, function()
			s.tick(3, 2)
		end)).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)

	it("...and a METRIC-NAME offset is refused: the theme, not the lane, resolves it", function()
		local sig
		local w = world(function(core: any): any
			sig = core:signal("space.s")
			return UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "Canvas",
						width = fill(),
						height = fill(),
						children = {
							UI.VStack({
								id = "Host",
								anchor = "topLeft",
								offsetX = sig,
								offsetY = 10,
								width = px(60),
								height = px(40),
								children = { UI.Box({ id = "Kid", width = px(20), height = px(20) }) },
							}),
						},
					}),
				},
			})
		end)
		expect(`hosts:{w.adapter.hostCount()}`).toBe("hosts:1")
		expect(deltas(w, function()
			sig:set("space.xl")
			w.controller.refresh()
		end)).toBe("solves=1 lane=0 rectWrites=1 engineWrites=1")
		w.dispose()
	end)

	it("a host that leaves its parent's box still lanes — because no finding exists to file", function()
		--[[ THE PLAN ASKED FOR A CONTAINMENT GATE HERE and the measurement says there is
			nothing for it to protect. `arrange_reports.containment` has exactly one caller
			(the case below pins it): `stack.arrange`. The ANCHOR branch never reports
			about where it put a child — its own doc says anchors "place children outside
			their box by design" — so a plate driven wholly outside the 1280 px anchor
			changes `controller.diagnostics()` from 0 findings to 0 findings, on the solve
			AND on the lane. Driving it BOTH ways is the point: a case that only checked
			the laned side would pass if the solve had quietly started filing one. ]]
		local s = scene.new()
		s.tick(3, 2)
		local before = #s.controller.diagnostics()
		local laned = deltas(s, function()
			s.moveOut(5)
		end)
		local afterLane = #s.controller.diagnostics()
		-- ...and the same drive on an arm with no coordinate-space hosts, which cannot
		-- lane at all and takes the whole thing through the solver
		local c = scene.new({ hosts = false })
		c.tick(3, 2)
		local solved = deltas(c, function()
			c.moveOut(5)
		end)
		expect(`{laned} diag={before}->{afterLane} | solved={solved} diag={#c.controller.diagnostics()}`).toBe(
			"solves=0 lane=1 rectWrites=1 engineWrites=1 diag=0->0 |"
				.. " solved=solves=1 lane=0 rectWrites=6 engineWrites=6 diag=0"
		)
		s.dispose()
		c.dispose()
	end)

	it("...and the ONE caller of the containment report is the stack arrange, not the anchor", function()
		--[[ THE PIN THAT KEEPS THE COMMENT ABOVE HONEST. The lane accepts a host whose
			LAYOUT PARENT is an `anchor` and no other kind, and it files no arrange-time
			report of its own. Both halves of that bargain are asserted here: the
			containment report has one call site and it is the stack's, and the report a
			node's own arrange makes (`arrange_reports.box`) reads `rect.w`/`rect.h` and
			never x or y — so a MOVE publishes nothing through either. The day the anchor
			branch gains a report, this reddens and the lane's gate list is short by one. ]]
		local solver = fs.readFile("src/layout/solver.luau")
		local sites: { string } = {}
		for line in string.gmatch(solver, "[^\n]+") do
			if string.find(line, "noteContainment", 1, true) ~= nil and string.find(line, "--", 1, true) == nil then
				table.insert(sites, string.match(line, "^%s*(.-)%s*$") :: string)
			end
		end
		expect(sites).toEqual({
			"local noteContainment = arrange_reports.containment",
			"stackLib.arrange(STACK_DEPS, ctx, node, innerX, innerY, innerW, innerH, gap, arrange, noteContainment, out)",
		})
		local reports = fs.readFile("src/layout/arrange_reports.luau")
		local box = string.match(reports, "\nfunction arrange_reports%.box(.-)\nend\n") :: string
		assert(box ~= nil, "no `arrange_reports.box` to read")
		expect(
			`box reads x/y:{string.find(box, "rect.x", 1, true) ~= nil or string.find(box, "rect.y", 1, true) ~= nil}`
		).toBe("box reads x/y:false")
	end)

	it("GATE: a host that is ITSELF a hit expander takes the solve; one BELOW it lanes", function()
		--[[ the host's own `want` is centred on its rect and only the `hitRects` walk
			recomputes it, so a host carrying an expander is refused. A DESCENDANT's
			expander is host-relative and did not move in its own space, so its host
			lanes — and the lane SERVES `hit_lift` after applying, which is what
			re-evaluates an overhang the move created. ]]
		local s = scene.new({ withButton = true }) -- plate 3's Row carries a 20x16 Button
		s.tick(3, 2)
		expect(deltas(s, function()
			s.tick(3, 2)
		end)).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)

	it("GATE: a host whose subtree contains a Path takes the solve, its neighbours lane", function()
		-- `spaceHostHasPath[path]`, filled on `livePaths`' EXISTING Path latch — the
		-- only gate the `visible` walk needs
		local s = scene.new({ withPath = true }) -- plate 3 carries a UI.Path
		s.tick(3, 2)
		expect(deltas(s, function()
			s.tick(3, 2)
		end)).toBe(`solves=1 lane={PLATES - 1} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)

	it("GATE: a host with a Composition beneath it takes the solve", function()
		--[[ THE ONE THING A MOVE RE-ARRANGES BELOW ITSELF, and the plan's channel table
			did not list it. T3 measured the mechanism: a Composition's exclusions are
			WINDOW-space by contract and are converted into its own box, so moving the box
			takes a different set of lanes — but under a coordinate space the host's move
			re-bases nothing, and both the translate arm and the ordinary arrange skip the
			body. The solver answers with `Ctx.spaceCompositions`/`noSkipDepth`; the lane
			has no arrange to suspend, so it refuses the host. Without this gate
			`translate_host.spec`'s "a Composition inside a moved host resolves against its
			WINDOW-space origin" goes red on the first slide. ]]
		local slide
		local w = world(function(core: any): any
			slide = core:signal(0)
			return UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "A",
						width = fill(),
						height = fill(),
						children = {
							UI.ZStack({
								id = "Wrap",
								anchor = "topLeft",
								offsetX = core:signal(0),
								offsetY = slide,
								width = px(300),
								height = px(200),
								children = {
									UI.Composition({
										id = "Comp",
										arrangements = { "column" },
										laneGap = 12,
										groupGap = 8,
										width = px(300),
										height = px(200),
										exclusions = { { x = 0, y = 0, w = 150, h = 150 } },
										groups = {
											{ id = "main", lane = "main", sizing = "fill", minWidth = 100 },
										},
										children = {
											UI.Region({
												id = "R1",
												group = "main",
												rank = 1,
												children = { UI.Box({ id = "r1a", width = px(80), height = px(30) }) },
											}),
										},
									}),
								},
							}),
						},
					}),
				},
			})
		end, { x = 0, y = 0, w = 400, h = 600 })
		expect(`hosted:{w.adapter.isHost("/S/A/Wrap")}`).toBe("hosted:true")
		expect(deltas(w, function()
			slide:set(40)
			w.controller.refresh()
			-- 3 writes, READ OFF THE RUN: the host, and the two nodes the composition
			-- re-placed once its exclusions landed in a different part of the moved box —
			-- which is exactly the work a laned move would have skipped
		end)).toBe("solves=1 lane=0 rectWrites=3 engineWrites=3")
		w.dispose()
	end)

	it("GATE: a nil-flip placement write takes the solve", function()
		-- `placementProps` and the parent's `inertPlacement` audit move on a PRESENCE
		-- flip and nothing in the lane serves them
		local s = scene.new()
		s.tick(3, 2)
		expect(deltas(s, function()
			s.clearOffset(5)
		end)).toBe("solves=1 lane=0 rectWrites=1 engineWrites=1")
		s.dispose()
	end)

	it("GATE: an armed withAnimation commit solves", function()
		-- a REAL session, built the way `present/with_animation` builds one: the armed
		-- commit installs records and those records need a live spring, so a stub
		-- would be testing the stub
		local s = scene.new()
		s.tick(3, 2)
		local clock = motionClock.new(s.core)
		s.controller.armAnimation({
			newSpring = function()
				return clock:spring(1, "container")
			end,
			carriesVelocity = true,
		})
		local d = deltas(s, function()
			s.tick(3, 2)
		end)
		s.controller.disarmAnimation()
		expect(d).toBe(`solves=1 lane=0 rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)

	it("GATE: a hidden host is the remainder, and its neighbours still lane", function()
		-- a refused host does not stop the others: it is handed to the solve, so the
		-- frame solves ONCE for one plate and lanes the other 249
		local s = scene.new()
		s.tick(3, 2)
		s.hide(4, true)
		expect(deltas(s, function()
			s.tick(3, 2)
		end)).toBe(`solves=1 lane={PLATES - 1} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)

	it("the solver's entry is updated in place so the next commit prunes the host", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2) -- steady
		local casterVisits = (s.stats() :: any).lastCommitVisitsByWalk.harvest
		local laneTick = deltas(s, function()
			s.tick(3, 2) -- a LANE tick between two solves
		end)
		s.tickWithCasts(3, 2)
		expect(`{laneTick} harvest={(s.stats() :: any).lastCommitVisitsByWalk.harvest}`).toBe(
			`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES} harvest={casterVisits}`
		)
		s.dispose()
	end)

	it("a lane tick then an unrelated solve leaves the host at the LANED position", function()
		--[[ the failure this pins is the stale warm-store build: the lane marks no
			`nodeDirty`, so the next build takes the warm-store hit for the laned host
			and must return it with the placement the lane applied. ]]
		local s = scene.new()
		s.tick(3, 2)
		local laneTick = deltas(s, function()
			s.tick(3, 2)
		end)
		expect(laneTick).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		local laned = s.controller.rectOf("/S/Canvas/Plates/[p7]/Plate")
		s.hp(1, 0.9) -- an unrelated MEASURE write on plate 1: a solve
		local after = s.controller.rectOf("/S/Canvas/Plates/[p7]/Plate")
		expect(`x={after.x},y={after.y}`).toBe(`x={laned.x},y={laned.y}`)
		s.dispose()
	end)

	it("a solved listener fires after a lane tick, so a consumer re-reads its geometry", function()
		local s = scene.new()
		s.tick(3, 2)
		local fired = 0
		local off = s.controller.onSolved(function()
			fired += 1
		end)
		local d = deltas(s, function()
			s.tick(3, 2)
		end)
		expect(`{d} fired={fired}`).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES} fired=1`)
		off()
		s.dispose()
	end)
end)

describe("translate lane: the hit_lift serve and the Path count", function()
	--[[ A MOVING HOST WHOSE DESCENDANT CARRIES AN EXPANDER, and a static sink beside
		it that the expander reaches into once the host has moved. No counter can
		decide that cheaply, so the lane calls `hit_lift.refresh` — the same function
		the commit calls, with the commit's own `adapter.setHitRect` guard — and
		`syncZOrder()` when it says the lift moved. ]]
	local function overhangWorld(): (any, any)
		local sig
		local w = world(function(core: any): any
			sig = core:signal(0)
			return UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "Canvas",
						width = fill(),
						height = fill(),
						children = {
							UI.VStack({
								id = "Host",
								anchor = "topLeft",
								offsetX = sig,
								offsetY = 0,
								width = px(40),
								height = px(20),
								children = { UI.Button({ id = "Btn", width = px(20), height = px(16), label = "b" }) },
							}),
							UI.Button({
								id = "Far",
								anchor = "topLeft",
								offsetX = 200,
								offsetY = 0,
								width = px(60),
								height = px(60),
								label = "far",
							}),
						},
					}),
				},
			})
		end)
		return w, sig
	end

	it("SERVE: a lane tick re-evaluates the overhang lift the move created", function()
		local w, sig = overhangWorld()
		local btn = "/S/Canvas/Host/Btn"
		local far = "/S/Canvas/Far"
		local beforeZ = `btn>far:{w.adapter.node(btn).z > w.adapter.node(far).z}`
		local d = deltas(w, function()
			sig:set(170)
			w.controller.refresh()
		end)
		local afterZ = `btn>far:{w.adapter.node(btn).z > w.adapter.node(far).z}`
		expect(`{d} before={beforeZ} after={afterZ}`).toBe(
			"solves=0 lane=1 rectWrites=1 engineWrites=1 before=btn>far:false after=btn>far:true"
		)
		w.dispose()
	end)

	it("three bounded syncs then a Path removal — the host lanes again", function()
		--[[ the count must be ONE however many times `livePaths` re-walks the same live
			Path. Three bounded structural syncs that touch the host's subtree, then the
			Path leaves: `spaceHostHasPath[host]` is gone and the host lanes. With an
			unconditional `+1` per walk the count would be 4, the removal's `-1` would
			leave 3, and the host would never lane again. ]]
		local offset, extra, hasPath
		local w = world(function(core: any): any
			offset = core:signal(0)
			extra = core:signal(false)
			hasPath = core:signal(true)
			return UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "Canvas",
						width = fill(),
						height = fill(),
						children = {
							UI.VStack({
								id = "Host",
								anchor = "topLeft",
								offsetX = offset,
								offsetY = 0,
								width = px(80),
								height = px(60),
								children = {
									UI.Box({ id = "Kid", width = px(20), height = px(20) }),
									UI.When({
										id = "Maybe",
										condition = extra,
										thenView = function()
											return UI.Box({ id = "Extra", width = px(10), height = px(10) })
										end,
									}),
									UI.When({
										id = "MaybePath",
										condition = hasPath,
										thenView = function()
											return UI.Path({
												id = "Spark",
												points = path_shapes.ring(),
												thickness = 2,
											})
										end,
									}),
								},
							}),
						},
					}),
				},
			})
		end)
		-- with a Path under it the host is REFUSED, however many bounded syncs run
		local gated = {}
		for i = 1, 3 do
			extra:set(i % 2 == 1)
			w.controller.refresh()
			table.insert(
				gated,
				deltas(w, function()
					offset:set(offset:get() + 1)
					w.controller.refresh()
				end)
			)
		end
		expect(table.concat(gated, " | ")).toBe(
			"solves=1 lane=0 rectWrites=1 engineWrites=1 | solves=1 lane=0 rectWrites=1 engineWrites=1"
				.. " | solves=1 lane=0 rectWrites=1 engineWrites=1"
		)
		-- ...and the moment the Path leaves, the count is back to nothing and it lanes
		hasPath:set(false)
		w.controller.refresh()
		expect(deltas(w, function()
			offset:set(offset:get() + 1)
			w.controller.refresh()
		end)).toBe("solves=0 lane=1 rectWrites=1 engineWrites=1")
		w.dispose()
	end)
end)
