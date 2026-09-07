--!strict
--[[ A HOST IS A COORDINATE SPACE (Plan C, C1). A container whose placement is
	REACTIVE and that has children is a real engine parent AND the origin its
	subtree's rects are stored against. A nameplate move is then ONE stored rect
	and ONE engine write; its five descendants' rects do not change in their own
	space, so `rect_pass.applyOne` finds them equal and writes nothing.

	THE PINS AND THEIR ARITHMETIC (fixture: 250 plates x 6 nodes):
	  pure tick      rectWrites 250 (was 1,500) · engineWrites 250 (was 1,500)
	                 solves **0** since T5: `render/translate_lane` consumes all 250
	                 placement entries and hands the solve an empty remainder, so the
	                 frame never solves and never opens a commit
	  caster tick    rectWrites 250 + 50 (the Cast bar resized) · engineWrites
	                 250 + 50 — READ OFF THE RUN, both columns
	PUBLIC NUMBERS DO NOT MOVE: `rectOf`/`screenRectOf` for plate 7's Name leaf at
	tick 2 are the literals below, READ OFF THE RUN AT HEAD `a46f84c4` BEFORE this
	task and kept by construction (composition on read).

	AND THE SECOND HALF OF THIS FILE IS THE READER AUDIT. Every reader in the
	campaign's rect-reader census that is not "composes through the controller"
	has a pin here: the hit expander and the hit lift, `scrollToVisible`,
	`coverRect`, the selection indicator, a cross-space recycle, a focused node,
	the two REFUSALS (a `ScrollView` and a `clipChildren` container are never
	coordinate spaces), the fake target's own composed position, and the cull.
	The audit table itself lives in the campaign ledger
	(`.superpowers/sdd/2026-09-03-facet-parity-C/progress.md`). ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local fs = require("@lune/fs")

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local path_shapes = require("../src/controls/path_shapes")
local fake_target = require("./lib/fake_target")
local list_scene = require("./lib/row_host_scene")

local PLATES, CASTERS = scene.PLATES, scene.PLATES // scene.CASTER_EVERY
-- READ OFF THE RUN AT HEAD `a46f84c4`, before this task touched `src/` — the
-- probe was: mount `nameplates_scene`, `tick(3, 2)` twice, print both reads.
local NAME_RECT_AT_HEAD = "x=265,y=375,w=61,h=16"
local NAME_SCREEN_RECT_AT_HEAD = "x=265,y=375,w=61,h=16"

local function fmt(r: any): string
	return if r == nil then "nil" else `x={r.x},y={r.y},w={r.w},h={r.h}`
end

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

--[[ A HAND-BUILT WORLD, the idiom every spec in this tree uses
	(`tests/layout_prop_dirt.spec.luau:395-422`): one core, one environment, the
	real mount, the fake target and `renderer.attach`. `opts` is threaded to
	`attach` so the reader-audit pins can raise arm `e`'s `translateHosts = false`
	against the very same blueprint. ]]
local function world(build: (any) -> any, viewport: any?, opts: any?): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", viewport or { x = 0, y = 0, w = 400, h = 300 })
	local root = mountLib.mount(core, build(core))
	local adapter = fake_target.new()
	local attach: any = {
		rootPolicy = "edgeToEdge",
		incrementalLayout = true,
		measureReuse = true,
		layoutNodeReuse = true,
		commitScope = true,
	}
	for k, v in opts or {} do
		attach[k] = v
	end
	local controller = renderer.attach(core, root, env, adapter, attach)
	controller.initialRender()
	return {
		core = core,
		env = env,
		root = root,
		adapter = adapter,
		controller = controller,
		refresh = function()
			controller.refresh()
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

--[[ THE STORED RECT PLUS EVERY SPACE HOST ABOVE IT — the identity that says a
	host-relative store composes back to the public window answer.

	`storedRect`, NOT `rect`: the fake target reports `node.rect` as the WINDOW rect
	on both targets (every containment rule, overlap sweep and pointer coordinate in
	the suite means that by it), and keeps exactly what the renderer handed it under
	`storedRect`. This helper is the one place that reads the second. ]]
local function composed(adapter: any, path: string): string
	local stored = adapter.node(path).storedRect
	local hx, hy = 0, 0
	local h = adapter.hostOf(path)
	while h ~= nil do
		if h.hostSpace then
			hx, hy = hx + h.rect.x, hy + h.rect.y
		end
		h = adapter.hostOf(h.path)
	end
	return `{stored.x + hx},{stored.y + hy}`
end

describe("translate host: one write per plate, today's numbers on every read", function()
	it("a pure tick writes one rect and one engine Position per plate", function()
		local s = scene.new()
		s.tick(3, 2) -- warm
		local rw, ew, solves = s.stats().rectWrites, s.adapter.engineWrites(), s.stats().solves
		s.tick(3, 2)
		local st = s.stats()
		expect(
			`rectWrites={st.rectWrites - rw} engineWrites={s.adapter.engineWrites() - ew} solves={st.solves - solves}`
		).toBe(`rectWrites={PLATES} engineWrites={PLATES} solves=0`)
		local name = "/S/Canvas/Plates/[p7]/Plate/Row/Name"
		expect(fmt(s.controller.rectOf(name))).toBe(NAME_RECT_AT_HEAD)
		expect(fmt(s.controller.screenRectOf(name))).toBe(NAME_SCREEN_RECT_AT_HEAD)
		--[[ THE STORED RECT IS HOST-RELATIVE, pinned as the IDENTITY it actually is:
			`stored + the host chain's origin == screenRectOf`. A threshold
			("stored.x < 180") passes on a coincidence and would still pass if the rect
			were absolute on a plate that happens to sit near the left edge. ]]
		local sr = s.controller.screenRectOf(name)
		expect(`composed={composed(s.adapter, name)}`).toBe(`composed={sr.x},{sr.y}`)
		-- ...and the engine window position is the public one
		local pos = s.adapter.node(name).presentedPosition
		expect(`pos={pos.x},{pos.y}`).toBe(`pos={sr.x},{sr.y}`)
		expect(`hosts={s.adapter.hostCount()}`).toBe(`hosts={PLATES}`)
		s.dispose()
	end)

	it("a caster tick adds exactly the Cast bars' writes", function()
		local s = scene.new()
		s.tickWithCasts(3, 2) -- warm
		local rw, ew = s.stats().rectWrites, s.adapter.engineWrites()
		s.tickWithCasts(3, 2)
		local st = s.stats()
		expect(`rectWrites={st.rectWrites - rw} engineWrites={s.adapter.engineWrites() - ew} solves=1`).toBe(
			`rectWrites={PLATES + CASTERS} engineWrites={PLATES + CASTERS} solves=1`
		)
		s.dispose()
	end)
end)

describe("translate host: the reader audit, one pin per reader that had to change", function()
	--[[ (g)/(h) THE TWO REFUSALS, and they are the implementation of ruling R-2
		rather than a restatement of it. `offsetX`/`offsetY`/`anchor` are `shared`
		props, so `UI.ScrollView({ offsetX = signal, … })` and
		`UI.VStack({ clipChildren = true, offsetY = signal, … })` both reach the
		fifth trigger's branch. Either one becoming a coordinate space would change
		the meaning of every raw-rect reader inside every list Facet ships —
		`scroll_into_view` subtracts a raw host rect from a raw target rect, and a
		ScrollView READS `offsetX/Y` for its own axis. Both are refused ABOVE the
		trigger, and both are still registered as ordinary hosts. ]]
	it("a ScrollView with a reactive offsetX is a host but NOT a coordinate space", function()
		local w = world(function(core: any): any
			return UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "SV",
						offsetX = core:signal(0),
						width = px(200),
						height = px(120),
						children = { UI.Box({ id = "Row", width = px(180), height = px(400) }) },
					}),
				},
			})
		end)
		expect(`isHost={w.adapter.isHost("/S/SV")}`).toBe("isHost=true")
		local host = w.adapter.hostOf("/S/SV/Row")
		expect(
			`host={if host == nil then "nil" else host.path} space={tostring(host ~= nil and host.hostSpace == true)}`
		).toBe("host=/S/SV space=false")
		-- ...and the child's stored rect is still the ABSOLUTE one
		expect(`stored={fmt(w.adapter.node("/S/SV/Row").storedRect)}`).toBe(
			`stored={fmt(w.controller.rectOf("/S/SV/Row"))}`
		)
		w.dispose()
	end)

	it("a clipChildren container with a reactive offsetY is a host but NOT a coordinate space", function()
		local w = world(function(core: any): any
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Clip",
						clipChildren = true,
						offsetY = core:signal(0),
						width = px(200),
						height = px(120),
						children = { UI.Box({ id = "Row", width = px(180), height = px(40) }) },
					}),
				},
			})
		end)
		local host = w.adapter.hostOf("/S/Clip/Row")
		expect(
			`host={if host == nil then "nil" else host.path} space={tostring(host ~= nil and host.hostSpace == true)}`
		).toBe("host=/S/Clip space=false")
		expect(`stored={fmt(w.adapter.node("/S/Clip/Row").storedRect)}`).toBe(
			`stored={fmt(w.controller.rectOf("/S/Clip/Row"))}`
		)
		w.dispose()
	end)

	it("a reactive placement is the fifth trigger on a CONTAINER and never on a leaf", function()
		local w = world(function(core: any): any
			return UI.Screen({
				id = "S",
				children = {
					UI.Anchor({
						id = "Canvas",
						width = fill(),
						height = fill(),
						children = {
							UI.VStack({
								id = "Box",
								anchor = "topLeft",
								offsetX = core:signal(10),
								offsetY = core:signal(20),
								width = px(60),
								height = { type = "content" },
								children = { UI.Text({ id = "T", text = "hi", textSize = 12 }) },
							}),
							UI.Box({
								id = "Leaf",
								anchor = "topLeft",
								offsetX = core:signal(200),
								offsetY = core:signal(20),
								width = px(30),
								height = px(30),
							}),
						},
					}),
				},
			})
		end)
		expect(`box={w.adapter.isHost("/S/Canvas/Box")} leaf={w.adapter.isHost("/S/Canvas/Leaf")}`).toBe(
			"box=true leaf=false"
		)
		w.dispose()
	end)

	--[[ A HOST THAT IS A TRANSLATE **DESCENDANT**, not a translate ROOT (D6a fix
		round, 2026-09-07). The solver already refuses to re-base a host it reaches as
		the root of a move — it records an EMPTY run and returns — and that ruling was
		made nowhere for a host reached one level down, inside a subtree the arm walks.
		`layout/translate_arm.translateDescendants` re-based every descendant it found,
		host or not: the host's own rect (correct — it lives in its parent's space) and
		then, a second time and by the same delta, every rect stored in the host's OWN
		space. Two bases, one arm.

		THE SHAPE IS SHIPPED, NOT INVENTED. `RowActions-<key>` is an `Anchor` holding
		the sliding tray; the tray's `offsetX` is reactive, so the tray is a coordinate
		space and the anchor is not. A row leaving above it moves the anchor and leaves
		the tray where it is — 98 such runs in `tests/playlist_columns.spec` at the head
		before this fix, each re-basing 16 tray descendants that had not moved, and NO
		spec in the tree read one of them. This fixture is that shape at its smallest: a
		spacer above a cell, so shrinking the spacer moves the cell and nothing else.

		FOUR CHANNELS, because a position pin alone would not say which base was wrong:
		the stored (host-relative) rect, which must not move AT ALL; the composed
		window position, against a forced FULL solve; the public `rectOf`, same; and
		`lastTranslated`, which is 1 — the tray's own entry — where it was 3. ]]
	it("a host inside a MOVED anchor keeps its subtree in its own space", function()
		local sig: { spacer: any } = { spacer = nil }
		local function build(core: any): any
			local spacer = core:signal(60)
			sig.spacer = spacer
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "List",
						padding = 0,
						gap = 0,
						width = fill(),
						height = { type = "content" },
						children = {
							UI.Box({
								id = "Spacer",
								width = fill(),
								height = core:memo(function(use: any): any
									return px(use(spacer) :: number)
								end),
							}),
							UI.Anchor({
								id = "Cell",
								width = fill(),
								height = px(60),
								children = {
									UI.VStack({
										id = "Tray",
										anchor = "topLeft",
										offsetX = core:signal(8),
										offsetY = core:signal(4),
										padding = 0,
										gap = 0,
										width = px(120),
										height = { type = "content" },
										children = {
											UI.Text({ id = "A", text = "one", textSize = 12 }),
											UI.Text({ id = "B", text = "two", textSize = 12 }),
										},
									}),
								},
							}),
						},
					}),
				},
			})
		end
		local a = world(build)
		local aSpacer = sig.spacer
		-- the ground truth: both solver halves off, so every rect is placed from scratch
		local c = world(build, nil, { incrementalLayout = false, measureReuse = false })
		local cSpacer = sig.spacer

		-- NON-VACUITY: the tray really is a coordinate space and the cell really is not
		expect(`tray={a.adapter.isHost("/S/List/Cell/Tray")} cell={a.adapter.isHost("/S/List/Cell")}`).toBe(
			"tray=true cell=false"
		)
		local storedBefore = a.adapter.node("/S/List/Cell/Tray/A").storedRect
		aSpacer:set(20)
		a.refresh()
		cSpacer:set(20)
		c.refresh()

		-- (1) the cell moved and the tray moved with it — otherwise nothing is proved
		expect(`cellY={a.adapter.node("/S/List/Cell").rect.y}`).toBe("cellY=20")
		-- (2) NOTHING in the tray's own space moved
		local storedAfter = a.adapter.node("/S/List/Cell/Tray/A").storedRect
		expect(`{storedAfter.x},{storedAfter.y}`).toBe(`{storedBefore.x},{storedBefore.y}`)
		-- (3) and (4): the composed window position and the public reader both equal a
		-- forced full solve's, on every leaf of the tray
		for _, id in { "A", "B" } do
			local path = `/S/List/Cell/Tray/{id}`
			expect(`{id} composed={composed(a.adapter, path)}`).toBe(`{id} composed={composed(c.adapter, path)}`)
			expect(`{id} rectOf={fmt(a.controller.rectOf(path))}`).toBe(`{id} rectOf={fmt(c.controller.rectOf(path))}`)
		end
		-- (5) THE COUNT: the run re-bases the tray's own entry and stops there
		expect(a.controller.stats().lastTranslated).toBe(1)
		a.dispose()
		c.dispose()
	end)

	--[[ ...AND THE ONE DESCENDANT THAT MAY NOT BE STOPPED AT. Stopping the walk at a
		host is right for every rect stored in its space and WRONG for a composition
		below it: `composition_resolve` converts author `exclusions` out of WINDOW space
		and decides `atRoot` by comparing the placed y to the root rect, so a host that
		moves carries a resolution computed at a position it no longer occupies. The arm
		already refuses a composition it meets DIRECTLY; the host stop would have walked
		straight past one. `ctx.spaceCompositions` is the map the solver fills for
		exactly this question and that `arrange`'s anchor arm already asks — asked here
		by the same pair of terms.

		THE SAME SHIPPED SHAPE as the case above with a `Composition` inside the tray,
		so the refusal is driven rather than argued: arm `a` must agree with a world
		that has no coordinate-space hosts at all, on `screenRectOf` for every painted
		path and on the findings. ]]
	it("a host holding a COMPOSITION is refused as a translate descendant", function()
		local spacers: { any } = {}
		local function build(core: any): any
			local spacer = core:signal(120)
			table.insert(spacers, spacer)
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "List",
						padding = 0,
						gap = 0,
						width = fill(),
						height = { type = "content" },
						children = {
							UI.Box({
								id = "Spacer",
								width = fill(),
								height = core:memo(function(use: any): any
									return px(use(spacer) :: number)
								end),
							}),
							UI.Anchor({
								id = "Cell",
								width = fill(),
								height = px(300),
								children = {
									UI.ZStack({
										id = "Wrap",
										anchor = "topLeft",
										offsetX = core:signal(0),
										offsetY = core:signal(0),
										width = px(400),
										height = px(300),
										children = {
											UI.Composition({
												id = "Comp",
												arrangements = { "column" },
												laneGap = 12,
												groupGap = 8,
												width = px(400),
												height = px(300),
												-- window-space by contract: move the box and a
												-- different set of lanes is taken out
												exclusions = { { x = 0, y = 0, w = 200, h = 200 } },
												groups = {
													{ id = "main", lane = "main", sizing = "fill", minWidth = 120 },
												},
												children = {
													UI.Region({
														id = "R1",
														group = "main",
														rank = 1,
														children = {
															UI.Box({ id = "r1a", width = px(100), height = px(40) }),
														},
													}),
												},
											}),
										},
									}),
								},
							}),
						},
					}),
				},
			})
		end
		local a = world(build, { x = 0, y = 0, w = 400, h = 600 })
		local e = world(build, { x = 0, y = 0, w = 400, h = 600 }, { translateHosts = false })
		expect(`hosted={a.adapter.isHost("/S/List/Cell/Wrap")} flat={e.adapter.isHost("/S/List/Cell/Wrap")}`).toBe(
			"hosted=true flat=false"
		)
		local function shot(w: any): string
			local out: { string } = {}
			for _, p in w.adapter.paths() do
				table.insert(out, `{p}|{fmt(w.controller.screenRectOf(p))}`)
			end
			table.sort(out)
			local diag: { string } = {}
			for _, finding in w.controller.diagnostics() do
				table.insert(diag, `{finding.node}:{finding.issue}`)
			end
			table.sort(diag)
			return table.concat(out, "\n") .. "\ndiag=" .. table.concat(diag, ";")
		end
		for _, v in { 40, 8, 96 } do
			spacers[1]:set(v)
			spacers[2]:set(v)
			a.refresh()
			e.refresh()
			expect(`spacer {v}: {shot(a) == shot(e)}`).toBe(`spacer {v}: true`)
		end
		-- non-vacuity: the composition really is under the host, and the cell really moved
		expect(`comp={a.adapter.hostOf("/S/List/Cell/Wrap/Comp").path}`).toBe("comp=/S/List/Cell/Wrap")
		expect(`y={a.controller.screenRectOf("/S/List/Cell").y}`).toBe("y=96")
		a.dispose()
		e.dispose()
	end)

	--[[ THE FIFTH TRIGGER, AND THE COUNT IT BUYS (Plan D, D6a). A `ForEach` item root
		spliced into a stack is a coordinate space, so a LIST SHIFT — the banner above
		the rows leaving, every row below it moving up by 60 — is one rect and one
		engine write PER ROW instead of one per box. Read off the run on a 300-row list
		whose rows carry four children each:

		  hosts off   1,501 rects / 1,501 engine writes, 1,500 translated
		  hosts on      301 rects /   301 engine writes,   300 translated   (5.0x)

		AND THE PRICE IS PINNED BESIDE THE WIN, because a lever whose cost is not in
		the same assertion is a lever nobody can re-judge later: a coordinate space is a
		REAL Instance, so the same 300 rows leave the elidable set — `elided` 302 -> 2,
		i.e. +300 GuiObjects that the flat tree did not materialise. The trade is 1,200
		writes per shift against 300 instances for the life of the surface, and it is
		why the trigger is the `ForEach`'s items alone rather than every stack inside a
		stack (`mount.markRow`).

		THE SHIFT IS DRIVEN TWICE, off and back on, because the two directions take
		different arms of the solver's reuse gate and only one of them was ever
		exercised by a fixture in this tree. ]]
	it("a list shift writes one rect per ROW, and the rows cost one Instance each", function()
		local function measure(hosts: boolean): string
			local s = list_scene.new({ viewport = { x = 0, y = 0, w = 400, h = 800 }, rows = 300, hosts = hosts })
			-- a warm-up write: the first refresh after `initialRender` is structural
			s.write(1, "warm")
			local before = s.stats() :: any
			local r0, e0 = before.rectWrites, before.engineWrites
			s.branch(false)
			local off = s.stats() :: any
			local r1, e1 = off.rectWrites, off.engineWrites
			s.branch(true)
			local on = s.stats() :: any
			local spaces = 0
			for _, path in s.adapter.paths() do
				if s.adapter.hostSpaceAt(path) == true then
					spaces += 1
				end
			end
			local out = `off={r1 - r0}/{e1 - e0} on={on.rectWrites - r1}/{on.engineWrites - e1} `
				.. `translated={on.lastTranslated} spaces={spaces} elided={on.elided}`
			s.dispose()
			return out
		end
		expect(measure(false)).toBe("off=1501/1501 on=1501/1501 translated=1500 spaces=0 elided=302")
		expect(measure(true)).toBe("off=301/301 on=301/301 translated=300 spaces=300 elided=2")
	end)

	--[[ ...AND THE POOL IS UNTOUCHED, WHICH WAS AN OPEN QUESTION AND IS NOW A
		MEASUREMENT. The brief that asked for the fifth trigger flagged a risk it could
		not price on paper: a coordinate space is a registered instance host, hosts have
		their own recycle bucket (`render/recycle_key`), and if a hosted row could not
		PARK then every `removeItem`/`addItem` on a list would give back the recycling
		the pool exists for. Driven both ways on the same 200-row list — 50 removals
		then 50 inserts — the four lifecycle counters are IDENTICAL with hosts on and
		off, to the unit. A hosted row parks and is recycled exactly as a flat one is,
		so the count lever costs the pool nothing and needs no length gate. ]]
	it("a hosted row parks and recycles exactly as a flat one does", function()
		local function churn(hosts: boolean): string
			local s = list_scene.new({ viewport = { x = 0, y = 0, w = 400, h = 800 }, rows = 200, hosts = hosts })
			s.write(1, "warm")
			local b = s.stats() :: any
			local c0, p0, y0, x0 = b.creates, b.parked, b.recycled, b.removes
			for _ = 1, 50 do
				s.remove(1)
			end
			local m = s.stats() :: any
			local out = `remove: creates={m.creates - c0} parked={m.parked - p0} `
				.. `recycled={m.recycled - y0} removes={m.removes - x0}`
			local c1, p1, y1, x1 = m.creates, m.parked, m.recycled, m.removes
			for _ = 1, 50 do
				s.insert(1)
			end
			local a = s.stats() :: any
			out ..= ` | add: creates={a.creates - c1} parked={a.parked - p1} ` .. `recycled={a.recycled - y1} removes={a.removes - x1}`
			s.dispose()
			return out
		end
		local flat = churn(false)
		expect(flat).toBe(
			"remove: creates=0 parked=64 recycled=0 removes=250 | add: creates=186 parked=0 recycled=64 removes=0"
		)
		expect(churn(true)).toBe(flat)
	end)

	--[[ THE THREE TERMS OF THE FIFTH TRIGGER, EACH DRIVEN ON ITS OWN (D6a). The
		predicate is "a `ForEach` item root, spliced into a stack, with two or more
		children", and each clause is there for a reason that can be stated as a
		measurement rather than as an intention:

		  IN A STACK — a `ForEach` under an `Anchor` places each row by its own
		    offset, so a shift is not a line shift and the rows have no shared move to
		    ride. Hosting them would buy an Instance apiece and no write. (It is also
		    the shipped nameplate/minimap shape, where the rows are already hosts by
		    the FIRST trigger and a second space inside each would be pure cost.)
		  TWO OR MORE CHILDREN — a one-child row costs the same single write hosted or
		    not, and hosting it spends a real Instance for nothing.
		  A CONTAINER CLASS — `ROW_HOST`; a leaf has no subtree for the engine to carry.

		Three worlds, same drive, one census each. ]]
	it("a row earns its coordinate space by being in a stack, with children", function()
		local function census(build: (any) -> any): number
			local w = world(build)
			local n = 0
			for _, path in w.adapter.paths() do
				if w.adapter.hostSpaceAt(path) == true then
					n += 1
				end
			end
			w.dispose()
			return n
		end
		local ITEMS = { { key = "a" }, { key = "b" }, { key = "c" } }
		local function rowsForEach(core: any, kids: number): any
			return UI.ForEach({
				id = "Rows",
				items = core:signal(ITEMS),
				key = function(item: any): string
					return item.key
				end,
				row = function(): any
					local children: { any } = { UI.Box({ id = "A", width = px(10), height = px(10) }) }
					if kids > 1 then
						table.insert(children, UI.Box({ id = "B", width = px(10), height = px(10) }))
					end
					return UI.VStack({
						id = "Row",
						padding = 0,
						gap = 0,
						width = fill(),
						height = px(20),
						children = children,
					})
				end,
			})
		end
		local inStackTwo = census(function(core: any): any
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "L",
						padding = 0,
						gap = 0,
						width = fill(),
						height = fill(),
						children = {
							rowsForEach(core, 2),
						},
					}),
				},
			})
		end)
		local inStackOne = census(function(core: any): any
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "L",
						padding = 0,
						gap = 0,
						width = fill(),
						height = fill(),
						children = {
							rowsForEach(core, 1),
						},
					}),
				},
			})
		end)
		local underAnchor = census(function(core: any): any
			return UI.Screen({
				id = "S",
				children = {
					UI.Anchor({ id = "L", width = fill(), height = fill(), children = { rowsForEach(core, 2) } }),
				},
			})
		end)
		expect(`stack2={inStackTwo} stack1={inStackOne} anchor={underAnchor}`).toBe("stack2=3 stack1=0 anchor=0")
	end)

	--[[ (a) THE HIT EXPANDER AND (k) THE HIT LIFT, on the same world, because they
		are the same reader seen twice. A 20x20 Button is below the 44px touch floor,
		so the framework grows it an expander — and `hit_lift` decides paint ORDER by
		asking whether that expander reaches PAST its own host into a sibling that
		sinks presses. Both rects come off THIS solve's map, and under a moved host
		they can sit in different coordinate spaces, so both are composed through the
		commit span's own origin function. Composed against `lastRects` instead, the
		lift would answer one frame late — which is what the mutation for this pin
		is (hand `hit_lift.refresh` `hostOriginOf`).

		THE STORED HIT RECT IS PINNED TOO, not just the z verdict. `growWithin`
		returns `want`, `setHitRect` stores it, and `applyHitExpander` re-bases it by
		the host origin — which is ZERO under a coordinate space. So the stored rect
		must stay in the ENTRY's own space; a z assertion alone cannot see it. ]]
	it("a hit expander under a MOVED host is composed on the same solve it moves", function()
		local off = { sig = nil :: any }
		local w = world(function(core: any): any
			off.sig = core:signal(0)
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
								offsetX = off.sig,
								offsetY = core:signal(0),
								width = px(20),
								height = px(20),
								children = { UI.Button({ id = "Small", label = "s", width = px(20), height = px(20) }) },
							}),
							UI.Button({
								id = "Static",
								label = "S",
								anchor = "topLeft",
								offsetX = core:signal(200),
								offsetY = core:signal(0),
								width = px(60),
								height = px(60),
							}),
						},
					}),
				},
			})
		end)
		local SMALL = "/S/Canvas/Host/Small"
		expect(`space={tostring(w.adapter.hostOf(SMALL).hostSpace == true)}`).toBe("space=true")
		--[[ THE BAND IS STORED IN THE ENTRY'S SPACE and reported in window space, the
			same split `rect`/`storedRect` has. `applyHitExpander` subtracts the host
			origin — ZERO under a coordinate space, because the band is already relative
			— so `storedHitRect` plus the host chain IS `hitRect`, and `hitRect` is
			where the 44px floor actually sits. ]]
		local hit = w.adapter.hitRectOf(SMALL)
		local sro = w.controller.screenRectOf(SMALL)
		local host = w.adapter.hostOf(SMALL)
		local storedHit = w.adapter.node(SMALL).storedHitRect
		expect(`hit={hit.w}x{hit.h} at {hit.x},{hit.y}`).toBe(`hit=44x44 at {sro.x - 12},{sro.y - 12}`)
		expect(`composed={storedHit.x + host.rect.x},{storedHit.y + host.rect.y}`).toBe(`composed={hit.x},{hit.y}`)
		-- MOVE THE HOST so the 44px floor reaches into the static button, and read the
		-- lift on the SAME solve
		local before = w.adapter.node("/S/Canvas/Static").z
		off.sig:set(170)
		w.refresh()
		local after = w.adapter.node("/S/Canvas/Static").z
		local smallZ = w.adapter.node(SMALL).z
		expect(`overhang={w.controller.screenRectOf(SMALL).x + 32 > 200} lifted={after ~= before or smallZ > after}`).toBe(
			"overhang=true lifted=true"
		)
		-- ...and the band never left the entry's space across the move: the STORED
		-- rect plus the host chain is still exactly where the floor is drawn
		local hit2 = w.adapter.hitRectOf(SMALL)
		local host2 = w.adapter.hostOf(SMALL)
		local storedHit2 = w.adapter.node(SMALL).storedHitRect
		local sro2 = w.controller.screenRectOf(SMALL)
		expect(`composed={storedHit2.x + host2.rect.x},{storedHit2.y + host2.rect.y}`).toBe(
			`composed={sro2.x - 12},{sro2.y - 12}`
		)
		expect(`window={hit2.x},{hit2.y}`).toBe(`window={sro2.x - 12},{sro2.y - 12}`)
		expect(w.core:lastError()).toBeNil()
		w.dispose()
	end)

	--[[ (b) `scrollToVisible` THROUGH A SPACE HOST. Its arithmetic is
		`target - host`, over `lastRects` — two rects that can now sit in different
		coordinate spaces. A ScrollView is never itself a space host (refused above),
		but it can sit inside one, and then BOTH its own rect and its rows' are
		host-relative. The number this returns must be the number it returned before
		coordinate spaces existed, which is what the no-host arm establishes. ]]
	it("scrollToVisible answers the same offset inside a moved host as outside one", function()
		local function build(core: any): any
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
								offsetX = core:signal(30),
								offsetY = core:signal(40),
								width = px(200),
								height = px(120),
								children = {
									UI.ScrollView({
										id = "List",
										axis = "y",
										width = px(200),
										height = px(120),
										children = {
											UI.Box({ id = "R1", width = px(180), height = px(80) }),
											UI.Box({ id = "R2", width = px(180), height = px(80) }),
											UI.Box({ id = "R3", width = px(180), height = px(80) }),
										},
									}),
								},
							}),
						},
					}),
				},
			})
		end
		local ROW = "/S/Canvas/Host/List/R3"
		local LIST = "/S/Canvas/Host/List"
		local a = world(build)
		local e = world(build, nil, { translateHosts = false })
		expect(`moved={a.controller.scrollToVisible(ROW)}`).toBe(`moved={e.controller.scrollToVisible(ROW)}`)
		local pa, pe = a.controller.scrollPosition(LIST), e.controller.scrollPosition(LIST)
		expect(`x={pa.x} y={pa.y}`).toBe(`x={pe.x} y={pe.y}`)
		-- ...and the arm really is hosted, so the comparison is not vacuous. `hostOf`
		-- answers the NEAREST host, which for a row is the ScrollView — the
		-- coordinate space is one level further out, above the list itself.
		expect(`listHost={a.adapter.hostOf(LIST).hostSpace == true} rowHost={a.adapter.hostOf(ROW).hostSpace == true}`).toBe(
			"listHost=true rowHost=false"
		)
		a.dispose()
		e.dispose()
	end)

	--[[ (c) `coverRect()` is a UNION over `lastRects`, and a union over rects in two
		different origins is not a box on the screen. The host here is moved PAST the
		right edge of the canvas that fills the surface, so the box's window rect is
		the only thing that can extend the union — and an uncomposed union would stop
		at the canvas and never notice. ]]
	it("coverRect unions window-space boxes, not host-relative ones", function()
		local off = { sig = nil :: any }
		local w = world(function(core: any): any
			off.sig = core:signal(0)
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
								offsetX = off.sig,
								offsetY = core:signal(50),
								width = px(60),
								height = px(40),
								children = { UI.Box({ id = "Only", width = px(60), height = px(40) }) },
							}),
						},
					}),
				},
			})
		end)
		local ONLY = "/S/Canvas/Host/Only"
		off.sig:set(380)
		w.refresh()
		local cover = w.controller.coverRect()
		local sro = w.controller.screenRectOf(ONLY)
		-- the canvas fills 400x300; the box now reaches 440, so the union's right edge
		-- IS the composed box. Read host-relative it would be 60, inside the canvas,
		-- and this number would be 400.
		expect(`right={cover.x + cover.w}`).toBe(`right={sro.x + sro.w}`)
		expect(`right={cover.x + cover.w}`).toBe("right=440")
		w.dispose()
	end)

	--[[ (d) THE SELECTION INDICATOR, which reads RAW `rectOf` on nodes that share a
		parent (`selection_indicator.luau`'s own note): the host origin cancels in the
		subtraction, so it needs no composition — but only because the indicator layer
		and the segments really do share one space. Inside a moved host they still do,
		and the DELTA between the bar and its segment is what must not move. ]]
	it("a selection indicator inside a moved host keeps its delta to the selected segment", function()
		local off = { sig = nil :: any }
		local w = world(function(core: any): any
			off.sig = core:signal(0)
			local seg = function(id: string, width: number): any
				return UI.Button({ id = id, label = id, width = px(width), height = px(48) })
			end
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
								offsetX = off.sig,
								offsetY = core:signal(10),
								width = px(200),
								height = px(48),
								children = {
									UI.HStack({ id = "Strip", gap = 0, children = { seg("A", 120), seg("B", 80) } }),
								},
							}),
						},
					}),
				},
			})
		end)
		local A = "/S/Canvas/Host/Strip/A"
		local B = "/S/Canvas/Host/Strip/B"
		local function delta(): string
			local a, b = w.controller.rectOf(A), w.controller.rectOf(B)
			return `{b.x - a.x},{b.y - a.y}`
		end
		local was = delta()
		off.sig:set(120)
		w.refresh()
		-- the two segments share a parent, so their difference is space-invariant —
		-- which is exactly why the indicator needs no composition
		expect(`delta={delta()}`).toBe(`delta={was}`)
		-- ...and both really did move in window space
		expect(`moved={w.controller.screenRectOf(A).x ~= 0}`).toBe("moved=true")
		w.dispose()
	end)

	--[[ (e) A RECYCLE ACROSS SPACES. `restoreParkedProps` carries the rect record
		from a parked instance onto its new path — and beneath a coordinate-space host
		a rect is host-relative, so a carry into a DIFFERENT space would hand
		`rect_pass` a rect in the wrong origin that compares equal by value and
		suppresses the write it owed. The guard drops it instead; what this pin
		asserts is that the re-adopted node reads exactly where the full-solve arm
		puts it. ]]
	it("a node recycled across coordinate spaces lands where a full solve puts it", function()
		local a = scene.new({ plates = 6 })
		local c = scene.new({ plates = 6, incremental = false, measureReuse = false })
		for _, w in { a, c } do
			w.tick(3, 2)
			w.remove(6)
			w.add(1)
			w.tick(4, 3)
		end
		expect(`recycled={a.stats().recycled > 0 or a.stats().parkRefused > 0}`).toBe("recycled=true")
		expect(a.publicSnapshot()).toBe(c.publicSnapshot())
		a.dispose()
		c.dispose()
	end)

	--[[ (f) A FOCUSED NODE INSIDE A MOVED HOST. `presentation_channel` writes the
		focus record for the node whose rect it read; the flags must survive a host
		move, and the float ring's placement is `applyRect`'s third host-origin site. ]]
	it("a focused node inside a moved host keeps its focus record across the move", function()
		local off = { sig = nil :: any }
		local w = world(function(core: any): any
			off.sig = core:signal(0)
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
								offsetX = off.sig,
								offsetY = core:signal(20),
								width = px(80),
								height = px(48),
								children = { UI.Button({ id = "Btn", label = "b", width = px(80), height = px(48) }) },
							}),
						},
					}),
				},
			})
		end)
		local BTN = "/S/Canvas/Host/Btn"
		w.controller.setFocusPath(BTN, true)
		w.refresh()
		local lift = w.adapter.node(BTN).focusLift
		off.sig:set(140)
		w.refresh()
		local node = w.adapter.node(BTN)
		expect(`focused={tostring(node.focused)} lift={tostring(node.focusLift)}`).toBe(
			`focused=true lift={tostring(lift)}`
		)
		-- ...and the engine position the ring rides is the public one
		local sro = w.controller.screenRectOf(BTN)
		expect(`pos={node.presentedPosition.x},{node.presentedPosition.y}`).toBe(`pos={sro.x},{sro.y}`)
		w.dispose()
	end)

	--[[ A COMPOSITION UNDER A COORDINATE-SPACE HOST (Plan C ruling R-13, and the
		reason the create-time Composition SCAN was dropped). `composition_resolve`
		decides `atRoot` and keys its cache on a WINDOW-space origin, and author
		`exclusions` are window-space rects converted into the box — so a composition
		whose box is stored host-relative would resolve against the wrong origin and
		take out the wrong lanes. The solver carries `ctx.spaceOX`/`ctx.spaceOY` down
		the walk and hands the arrange-time `resolve` the shifted numbers, which is
		exact at any time — including for a `Composition` a `When` mounts under an
		already-registered host later, which a create-time scan could never see.

		AUTHORABLE UNDER AN ORDINARY CONTAINER: the shape below is
		`tests/redteam_closing_round.spec.luau`'s own composition world, mounted the
		SHIPPED way instead of with the trigger off, so `Wrap` really is a coordinate
		space. The two arms must agree on every public column and on `diagKey`. ]]
	it("a Composition inside a moved host resolves against its WINDOW-space origin", function()
		local function build(core: any, slide: any): any
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
								width = px(400),
								height = px(300),
								children = {
									UI.Composition({
										id = "Comp",
										arrangements = { "column" },
										laneGap = 12,
										groupGap = 8,
										width = px(400),
										height = px(300),
										-- window-space by contract, converted into the box: move
										-- the box and a different set of lanes is taken out
										exclusions = { { x = 0, y = 0, w = 200, h = 200 } },
										groups = {
											{ id = "main", lane = "main", sizing = "fill", minWidth = 120 },
										},
										children = {
											UI.Region({
												id = "R1",
												group = "main",
												rank = 1,
												children = { UI.Box({ id = "r1a", width = px(100), height = px(40) }) },
											}),
										},
									}),
								},
							}),
						},
					}),
				},
			})
		end
		local slides: { any } = {}
		local function makeWorld(hosts: boolean): any
			local w = world(function(core: any): any
				local slide = core:signal(0)
				table.insert(slides, slide)
				return build(core, slide)
			end, { x = 0, y = 0, w = 400, h = 600 }, if hosts then nil else { translateHosts = false })
			return w
		end
		local a = makeWorld(true)
		local e = makeWorld(false)
		expect(`hosted={a.adapter.isHost("/S/A/Wrap")} flat={e.adapter.isHost("/S/A/Wrap")}`).toBe(
			"hosted=true flat=false"
		)
		local function drive(v: number)
			slides[1]:set(v)
			slides[2]:set(v)
			a.refresh()
			e.refresh()
		end
		local function shot(w: any): string
			local out: { string } = {}
			for _, p in w.adapter.paths() do
				local sro = w.controller.screenRectOf(p)
				table.insert(out, `{p}|{fmt(sro)}`)
			end
			table.sort(out)
			local diag: { string } = {}
			for _, finding in w.controller.diagnostics() do
				table.insert(diag, `{finding.node}:{finding.issue}`)
			end
			table.sort(diag)
			return table.concat(out, "\n") .. "\ndiag=" .. table.concat(diag, ";")
		end
		for _, v in { 7, 23, 61 } do
			drive(v)
			expect(`slide {v}: {shot(a) == shot(e)}`).toBe(`slide {v}: true`)
		end
		-- ...and it is not vacuous: the composition really is under the host, and the
		-- host really moved
		expect(`comp={a.adapter.hostOf("/S/A/Wrap/Comp").path}`).toBe("comp=/S/A/Wrap")
		expect(`y={a.controller.screenRectOf("/S/A/Wrap").y}`).toBe("y=61")
		a.dispose()
		e.dispose()
	end)

	--[[ THE DECISION IS MADE ONCE AND BY ONE WRITER (fix round 1, Important 1).
		`instance_boundary.createOptsFor` MEMOISES its coordinate-space answer on the
		mounted node, because `render/layout_node` asks the same question and neither
		caller is guaranteed to ask first. `false` is a memoised answer, not an absent
		one: a container that is EMPTY when it is first asked must stay a non-host for
		its life, or it would re-evaluate to `true` after the adapter had already
		registered nothing and the solver would store its subtree relative to a parent
		that does not exist — every rect under it wrong by the origin.

		THE SHAPE IS THE `When` THE KNOWN LIMIT NAMES: a container that mounts with no
		children and gains them later. Both sides must agree afterwards, which is what
		the two assertions are — the ADAPTER (no host registered) and the SOLVER (the
		child's stored rect is still absolute). ]]
	it("a container empty at its first ask stays a NON-host after it gains children", function()
		--[[ DRIVEN ON THE PREDICATE ITSELF, because that is where the decision is made
			and where the bug was. A mounted tree is built whole before `ensureTree`
			walks it, so "empty at the first ask" is not a shape a blueprint can be
			authored into — it is a shape the ORDER of the two callers produces, and the
			memo is what makes the order stop mattering. Asking the function directly is
			the only instrument that can put the two asks in that order on purpose. ]]
		local boundary = require("../src/render/instance_boundary")
		local empty: any = {
			class = "VStack",
			props = {},
			dynamicProps = { offsetX = true },
			children = {},
		}
		expect(`empty asks -> {tostring(boundary.createOptsFor(empty))}`).toBe("empty asks -> nil")
		expect(`memoised={tostring(empty.hostSpace)}`).toBe("memoised=false")
		-- ...and NOW it gains children. The answer must not change: the adapter has
		-- already been told there is no host here.
		empty.children = { { class = "Box" } }
		expect(`after children -> {tostring(boundary.createOptsFor(empty))}`).toBe("after children -> nil")
		expect(`still={tostring(empty.hostSpace)}`).toBe("still=false")

		--[[ ...AND THERE IS EXACTLY ONE WRITER OF THE FIELD, which is what makes the
			memo hold. `renderer.ensureTree` used to stamp it too and stamped `nil` over
			the memoised `false`, which is precisely how the answer could change. The
			source pin is the guard: a second writer reintroduces the defect and nothing
			else in the suite would see it, because it needs the two asks in one order. ]]
		local rendererSrc = fs.readFile("src/render/renderer.luau")
		local layoutNodeSrc = fs.readFile("src/render/layout_node.luau")
		local boundarySrc = fs.readFile("src/render/instance_boundary.luau")
		local function writes(source: string): number
			local n = 0
			for _ in string.gmatch(source, "node%.hostSpace%s*=[^=]") do
				n += 1
			end
			return n
		end
		expect(`renderer writes={writes(rendererSrc)}`).toBe("renderer writes=0")
		expect(`layout_node writes={writes(layoutNodeSrc)}`).toBe("layout_node writes=0")
		--[[ FIVE WRITE SITES SINCE 2026-09-07 (RED-TEAM C-10, then F2), AND STILL ONE
			WRITER. `createOptsFor`'s early returns — `opacity`/`canvasGroup`,
			`scale`/`rotation`, `ScrollView`/`clipChildren`, and the `translateHosts =
			false` feature switch — used to return ABOVE the memo block without answering
			the field, so a container whose reactive `opacity` went number -> nil was a
			non-host on its first ask and a candidate on its second: the exact shape this
			case is about, arriving through a different door. Each of them now decides the
			field, all five sites are inside this one function, and the count is pinned so
			a SIXTH cannot appear in another module unnoticed. ]]
		expect(`boundary writes={writes(boundarySrc)}`).toBe("boundary writes=5")
		--[[ ...AND EVERY ONE OF THEM IS FIRST-ANSWER-WINS, which is the property the
			count alone cannot carry. Four are the literal `if node.hostSpace == nil`
			shape; the fifth is the memo block's `decided == nil`, the same test through
			a local it has already read. A write without either guard would be a stamp,
			which is what `renderer.ensureTree` used to do. ]]
		local guarded = 0
		for _ in string.gmatch(boundarySrc, "if node%.hostSpace == nil then%s*\n%s*node%.hostSpace = ") do
			guarded += 1
		end
		expect(`guarded={guarded} + the memo block's own`).toBe("guarded=4 + the memo block's own")
		-- NEGATIVE CONTROL: the scan really does see a write
		expect(`control={writes("\n\tnode.hostSpace = true\n")}`).toBe("control=1")
	end)

	--[[ ...AND THE PROPERTY THE COUNT CANNOT CARRY: EVERY RETURN DECIDES (RED-TEAM F2).

		The write-site count above is the same class of check C-4 had just fixed for the
		closed write-set audit — it counts WRITES, so a return that decides nothing is
		invisible to it, which is precisely the defect the writes exist to prevent. And
		one was: `if opts ~= nil and opts.translateHosts == false then return nil end`
		left the field absent on every ask, so `decisions()` climbed forever in the arm
		this whole file compares against, and "every path through this function decides"
		was false while the commit that claimed it was green.

		THE SCAN IS AN EQUALITY WITH NO REMEMBERED EXCEPTION, which is the
		`measure`-returns-through-`record` idiom from `tests/measure_serve.spec.luau`. It
		reads the region of the function AFTER `decisions += 1`, and that boundary is
		structural rather than an excuse: the counter's own contract is that it counts
		asks which found the field undecided, so the `props == nil` return above it is
		not an ask at all. Below it, `returns == decisions` — and it is an equality only
		because the memo block ends in ONE return; two would have needed an off-by-one
		nobody could tell from a missing decision. ]]
	it("every RETURN of `createOptsFor` past the counter decides the field, by source scan", function()
		local boundarySrc = fs.readFile("src/render/instance_boundary.luau")
		--[[ comments first, both forms: this function's block comments are full of the
			words `return` and `node.hostSpace =` and every one of them would be counted. ]]
		local stripped = string.gsub("\n" .. boundarySrc, "%-%-%[%[.-%]%]", " ")
		stripped = string.gsub(stripped, "\n[ \t]*%-%-[^\n]*", "\n")
		local body = string.match(stripped, "\nfunction instance_boundary%.createOptsFor.-\nend\n")
		assert(body ~= nil, "could not isolate `createOptsFor`'s body")
		local counted = string.match(body :: string, "decisions %+= 1(.*)")
		assert(counted ~= nil, "could not find the undecided-arrival counter")
		local function scan(source: string, pattern: string): number
			local n = 0
			for _ in string.gmatch(source, pattern) do
				n += 1
			end
			return n
		end
		expect(
			`returns={scan(counted :: string, "%f[%w]return%f[%W]")} decides={scan(
				counted :: string,
				"node%.hostSpace%s*=[^=]"
			)}`
		).toBe("returns=5 decides=5")
		--[[ NEGATIVE CONTROL: the scan really reads both halves, and a fabricated
			non-deciding return really does break the equality it is asked to hold. ]]
		local fake = "\nfunction instance_boundary.createOptsFor(node)\n\tdecisions += 1\n"
			.. "\tif a then\n\t\tnode.hostSpace = false\n\t\treturn nil\n\tend\n\treturn nil\nend\n"
		local fakeBody = string.match(fake, "decisions %+= 1(.*)") :: string
		expect(`returns={scan(fakeBody, "%f[%w]return%f[%W]")} decides={scan(fakeBody, "node%.hostSpace%s*=[^=]")}`).toBe(
			"returns=2 decides=1"
		)
	end)

	--[[ ...AND THE ARM THE SCAN IS ABOUT, DRIVEN (RED-TEAM F2). `translateHosts = false`
		is the oracle arm every host case in this file compares against, so a counter that
		is meaningless there is a counter that cannot be read where a divergence would be
		diagnosed. Before the fix this climbed by one per container per rebuild, forever;
		the field is now decided `false` on the first ask and the second one reads it back.

		SAFE BECAUSE THE FLAG IS FIXED AT ATTACH: `renderer.ensureTree`'s `opts` and
		`render/layout_node`'s `store.attachOpts` are the one `RendererAttachOpts` the
		surface was attached with, so `false` here can never be contradicted by the other
		asker. ]]
	it("under `translateHosts = false` the verdict is decided ONCE, not re-asked forever", function()
		local boundary = require("../src/render/instance_boundary")
		local e = world(function(_core: any)
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "List",
						children = {
							UI.ZStack({
								id = "Row",
								children = { UI.Box({ id = "A" }), UI.Box({ id = "B" }) },
							}),
						},
					}),
				},
			})
		end, { x = 0, y = 0, w = 400, h = 300 }, { translateHosts = false, layoutNodeReuse = false })
		--[[ `layoutNodeReuse = false` IS THE DRIVE, and it is a shipped switch rather than
			a contrivance: with the store's reuse arm on, a viewport change re-solves
			without rebuilding a clean node, so `hostSpaceOf` is never re-asked and a
			counter case would pass by asking nothing at all — measured, at `decided=0`
			with the fix REVERTED. Off, every refresh builds every node and therefore asks
			every container, which is the repetition the memo exists to absorb. ]]
		local before = boundary.decisions()
		e.env:set("viewportRect", { x = 0, y = 0, w = 401, h = 300 })
		e.refresh()
		e.env:set("viewportRect", { x = 0, y = 0, w = 402, h = 300 })
		e.refresh()
		expect(`decided={boundary.decisions() - before}`).toBe("decided=0")
		-- ...and NOT vacuous: the arm really is the no-host one, so the row is not a
		-- coordinate space and its children's rects are stored absolutely
		expect(`host={tostring(e.adapter.hostOf("/S/List/Row/A") ~= nil)}`).toBe("host=false")
		e.dispose()
	end)

	--[[ A COMPOSITION THAT LEAVES GIVES THE SHORTCUT BACK (fix round 1, minor 5).
		`Ctx.spaceCompositions` marks every coordinate-space host above a composition,
		and such a host suspends BOTH the skip and the translate arm for its own body —
		because a composition's resolution is a function of the window origin the host
		itself moves. Left unpruned, a host whose composition unmounts would carry that
		cost for the surface's life. It is pruned where it is filled: the origin rebind
		clears the host's own entry as its body starts, so a composition that is gone
		stops re-marking it. `lastArranged` is the instrument — with the composition
		standing the host walks its whole subtree, without it the host records an empty
		run and arranges nothing beneath it. ]]
	it("a composition that unmounts lets its host take the move-only shortcut again", function()
		local st = { on = nil :: any, slide = nil :: any }
		local w = world(function(core: any): any
			st.on = core:signal(true)
			st.slide = core:signal(0)
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
								offsetY = st.slide,
								width = px(400),
								height = px(300),
								children = {
									UI.When({
										id = "Gate",
										condition = st.on,
										thenView = function()
											return UI.Composition({
												id = "Comp",
												arrangements = { "column" },
												laneGap = 12,
												groupGap = 8,
												width = px(400),
												height = px(300),
												exclusions = { { x = 0, y = 0, w = 200, h = 200 } },
												groups = {
													{ id = "main", lane = "main", sizing = "fill", minWidth = 120 },
												},
												children = {
													UI.Region({
														id = "R1",
														group = "main",
														rank = 1,
														children = {
															UI.Box({ id = "r1a", width = px(100), height = px(40) }),
														},
													}),
												},
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
		local function slideTo(v: number): number
			st.slide:set(v)
			w.refresh()
			return (w.controller.stats() :: any).lastArranged
		end
		slideTo(7) -- warm: the first drive after mount is the fill pass
		local withComposition = slideTo(23)
		-- the host really is a coordinate space, and it really is walking its subtree
		expect(`space={tostring(w.adapter.hostOf("/S/A/Wrap/Gate/then/Comp").hostSpace == true)}`).toBe("space=true")
		expect(`walks its subtree={withComposition > 3}`).toBe("walks its subtree=true")

		st.on:set(false)
		w.refresh()
		expect(w.adapter.node("/S/A/Wrap/Gate/then/Comp")).toBeNil()
		slideTo(41) -- the structural solve is not the measurement; the next move is
		local withoutComposition = slideTo(59)
		expect(`shortcut back={withoutComposition < withComposition}`).toBe("shortcut back=true")
		expect(w.core:lastError()).toBeNil()
		w.dispose()
	end)

	--[[ (i) THE FAKE'S COMPOSED POSITION DOES NOT GO STALE. Under Plan C a host move
		produces exactly ONE `setRect` and zero for its descendants — that is the
		point — so a fake that composed `presentedPosition` only at its own `setRect`
		would keep every descendant's pre-move value forever, and two hosted arms of
		an oracle would go stale together and still compare equal. The mutation for
		this pin is "delete the subtree recompose in `fake_target.setRect`". ]]
	it("every descendant's engine position follows a host move on the first tick", function()
		local s = scene.new({ plates = 4 })
		s.tick(3, 2)
		s.tick(11, 7)
		for _, leaf in { "Row/Name", "Row/Lvl", "Hp", "Cast" } do
			local path = `/S/Canvas/Plates/[p2]/Plate/{leaf}`
			local pos = s.adapter.node(path).presentedPosition
			local sro = s.controller.screenRectOf(path)
			expect(`{leaf} pos={pos.x},{pos.y}`).toBe(`{leaf} pos={sro.x},{sro.y}`)
		end
		s.dispose()
	end)

	--[[ (j) THE CULL COMPOSES AGAINST *THIS* SOLVE'S ORIGIN. A stroked `UI.Path`'s
		visibility is decided against its CLIP HOST's box, over the solve's FRESH
		rects (`paintedRectIn` -> `originIn`), because a cull run against last frame's
		geometry is the one-frame lag that makes a re-sorted row flash outside its
		list. Moving the space host far enough takes the path out of the clip box, and
		the verdict must flip on the SAME solve. ]]
	it("a path leaving its clip box because its host moved is culled on that solve", function()
		local off = { sig = nil :: any }
		local w = world(function(core: any): any
			off.sig = core:signal(0)
			return UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Clip",
						clipChildren = true,
						width = px(120),
						height = px(120),
						children = {
							UI.Anchor({
								id = "Canvas",
								width = fill(),
								height = fill(),
								children = {
									UI.VStack({
										id = "Host",
										anchor = "topLeft",
										offsetX = off.sig,
										offsetY = core:signal(0),
										width = px(40),
										height = px(40),
										children = {
											UI.Path({ id = "Spark", points = path_shapes.ring(), thickness = 2 }),
										},
									}),
								},
							}),
						},
					}),
				},
			})
		end)
		local SPARK = "/S/Clip/Canvas/Host/Spark"
		expect(`space={tostring(w.adapter.hostOf(SPARK).hostSpace == true)}`).toBe("space=true")
		expect(`visible={tostring(w.adapter.node(SPARK).visible)}`).toBe("visible=true")
		-- push the host clean out of the 120px clip box, and read the verdict on the
		-- SAME refresh that moved it
		off.sig:set(400)
		w.refresh()
		expect(`visible={tostring(w.adapter.node(SPARK).visible)}`).toBe("visible=false")
		-- ...and back
		off.sig:set(0)
		w.refresh()
		expect(`visible={tostring(w.adapter.node(SPARK).visible)}`).toBe("visible=true")
		w.dispose()
	end)
end)
