--!strict
--[[ O3 — A SUBTREE THAT ONLY MOVED IS RE-BASED, NOT RE-ENTERED.

	The arrange skip (`solver.luau`, `arrange`'s reuse gate) is on ABSOLUTE-rect
	identity: a moved plate fails `pr.x == rect.x` at its root and at every
	descendant, so 250 moves arrange 1,502 nodes. But an unchanged subtree that
	moved is its old rects plus one delta, known without walking it — and the rect
	map is copy-on-write (`solve`'s `out = ctx.reuse.previous.rects`), so writing
	it is a delta write per descendant with no re-entry.

	THE PINS AND THEIR ARITHMETIC (fixture: 250 plates x 6 nodes + the Canvas
	anchor + the Screen root = 1,502 layout nodes; the ForEach region is NOT a
	layout node — `layout_node.luau:1263-1275` splices its children into the
	enclosing flow):
	  pure tick        arranged 252 = Screen + Canvas + 250 plate roots (each is
	                   in `dirtyContains` — its own offsetX wrote the dirt — so it
	                   takes the ORDINARY entry write, and its 5 descendants are
	                   re-based by `translateDescendants`)
	                   translated 1,250 = 250 x 5
	  caster tick      arranged 402 / translated 1,100 — READ OFF THE RUN, see
	                   below.

	THE CASTER SPLIT WAS NOT SETTLED ON PAPER, AND THE RUN SETTLED IT: the plan
	carried two candidate derivations and **(b) is what the shipped arm does**.
	(a) predicted 302/1,200 — the plate root arranged, its Row/Name/Lvl/Hp
	translated under it — and it is WRONG, because `translatable` does not require
	the node to be clean, only that no CHILD of it is dirty. On a caster tick the
	plate root has a dirty child (`Cast`), so it takes the ordinary arrange and
	descends; its `Row` is then clean, the same size (`width = fill()` inside a
	`px(180)` plate) and moved, so `Row` is ITSELF a translate root (arranged 1,
	translating Name + Lvl = 2), and `Hp` is a childless translate root (arranged
	1, translating 0 — `translateDescendants` over no children returns true, so it
	is a translate root that re-bases nothing). Per caster: arranged 4 (Plate, Row,
	Hp, Cast) + translated 2 = 6 nodes. Totals 2 + 200 + 50*4 = 402 arranged and
	200*5 + 50*2 = 1,100 translated — measured, `arranged=402 translated=1100`.
	Both derivations sum to 1,502, so the invariant cannot tell them apart; only
	the run can, which is why this paragraph records WHICH ONE and why.

	The caster plate root does NOT resize under either derivation — the fixture's
	plate is `width = px(180)`, `height = content`, and the cast bar's height is
	fixed — so no plate hugs its bar. Confirmed by the run: had it resized, the
	root would have failed the shared size test and its children could not have
	become translate roots at all.

	AND THE ROOT'S OWN DIRT HAS TO BE DIRT ITS PARENT ALREADY SPENT. `translatable`
	answers for the subtree; `solver.selfPlaces` answers for the root, and it exists
	because the arm was WRONG without it — see the second `describe` in this file,
	which drives the three shapes that broke and the partition that decides them.

	PROP-DIRT: NOTHING MOVES (Step 7). **The translate class is derived from rect
	deltas, not from a prop class.** No `dirty = { … }` entry changes,
	`LAYOUT_CLASSES` in `layout_prop_dirt.spec.luau` is untouched, and the
	renderer's prop-class dispatch is untouched. The arrange-only audit T3 added at
	the foot of that spec still holds because it asserts `lastMeasured`, which this
	task only drives DOWN — and it is the check that CAUGHT the `distribute` hole,
	so the audit is doing exactly the job it was added for. `selfPlaces` reads the
	dirt SETS the solver is already handed (`measureContains`) and three node fields
	it already carries; it classifies nothing and it declares nothing. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY -- 50
local LAYOUT = PLATES * scene.NODES_PER_PLATE + 2 -- 1502
local ARRANGED_TICK = PLATES + 2 -- 252
local TRANSLATED_TICK = PLATES * (scene.NODES_PER_PLATE - 1) -- 1250
-- READ OFF THE RUN (derivation (b), see the header): per caster the Plate root,
-- its Row, its Hp and its Cast are all arranged — Row and Hp because they are
-- themselves translate ROOTS under a plate the `Cast` dirt forced open.
local ARRANGED_CASTS = PLATES + 2 + CASTERS * 3 -- 402
local TRANSLATED_CASTS = (PLATES - CASTERS) * 5 + CASTERS * 2 -- 1100

describe("O3: a moved-not-resized subtree translates", function()
	it("a pure tick arranges the roots and translates the rest", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local st = s.stats()
		expect(`arranged={st.lastArranged} translated={st.lastTranslated}`).toBe(
			`arranged={ARRANGED_TICK} translated={TRANSLATED_TICK}`
		)
		s.dispose()
	end)

	it("a caster tick arranges the bars too", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local st = s.stats()
		expect(`arranged={st.lastArranged} translated={st.lastTranslated}`).toBe(
			`arranged={ARRANGED_CASTS} translated={TRANSLATED_CASTS}`
		)
		s.dispose()
	end)

	it("a pure tick now measures NOTHING (the pin T3 could not reach)", function()
		-- T3's floor was `PLATES * 2`: the plate's own arrange descended into two
		-- fixed x fixed, PLAN_SKIP leaves that `measureUncached` counts on every
		-- touch. The translate arm does not descend at all, so the touches stop.
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		expect(s.stats().lastMeasured).toBe(0)
		s.dispose()
	end)

	it("the work invariant holds and every translated node is a rect insert", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local st = s.stats()
		-- `lastSolveSkipped`, NOT `lastSkipped`: the renderer writes `lastSkipped`
		-- only when skipped > 0, so on a step that skipped nothing it still holds
		-- the PREVIOUS step's number and an invariant reading it would pass or fail
		-- on history. The sum is `nodeStore.nodes` by construction (the renderer
		-- derives `skipped` from it), so what this line actually pins is that the
		-- fixture really has LAYOUT layout nodes — and `lastLayoutNodes` says so
		-- directly, which is why both are asserted.
		expect(st.lastLayoutNodes).toBe(LAYOUT)
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(LAYOUT)
		-- ...and THIS one is the independent pin: nothing derives `rectInserts`
		-- from `arranged`, so an arm that counted a write it did not make shows up
		-- here and nowhere else.
		expect(st.lastRectInserts).toBe(st.lastArranged + st.lastTranslated)
		s.dispose()
	end)

	it("THE TRANSLATE ROOT'S OWN RECT MOVES (the pin no counter can make)", function()
		-- The counter pins above all pass on a translate arm that returns from the
		-- skip site without writing `out[node.id]` — `arranged`, `translated` and
		-- `rectInserts` are all incremented, and the plate simply never moves on
		-- screen. This is the assertion that catches it: the ADAPTER's rect for a
		-- plate root, before and after, differs by exactly the delta.
		local s = scene.new()
		s.tick(3, 2)
		local path = "/S/Canvas/Plates/[p7]/Plate"
		local before = s.adapter.liveNodes()[path].rect
		s.tick(3, 2)
		local after = s.adapter.liveNodes()[path].rect
		expect(`dx={after.x - before.x} dy={after.y - before.y}`).toBe("dx=3 dy=2")
		-- ...and a descendant of it moved by the same delta, from the re-based run
		local kidPath = "/S/Canvas/Plates/[p7]/Plate/Hp"
		local kidAfter = s.adapter.liveNodes()[kidPath].rect
		s.tick(3, 2)
		local kidNext = s.adapter.liveNodes()[kidPath].rect
		expect(`dx={kidNext.x - kidAfter.x} dy={kidNext.y - kidAfter.y}`).toBe("dx=3 dy=2")
		s.dispose()
	end)

	it("the writes are REAL and they all still happen (the flat tree, profile §1)", function()
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats().rectWrites
		s.tick(3, 2)
		expect(s.stats().rectWrites - before).toBe(PLATES * scene.NODES_PER_PLATE) -- 1500
		s.dispose()
	end)

	it("...at every device view, including 320x640", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.tick(3, 2)
			local st = s.stats()
			expect(`{view.id}:{st.lastArranged}/{st.lastTranslated}`).toBe(
				`{view.id}:{ARRANGED_TICK}/{TRANSLATED_TICK}`
			)
			s.dispose()
		end
	end)
end)

--[[ THE DIRT THAT MOVES A NODE'S OWN CHILDREN IS NOT THE DIRT THAT MOVED THE NODE
	— the defect the first draft of this arm shipped, and the reason
	`solver.selfPlaces` exists.

	`translatable` proves nothing INSIDE the subtree changed. It says nothing about
	the ROOT's own change, and the plan's argument for letting a dirty root
	translate ("its own offset moved it") is true only for the props a PARENT reads
	off a child. A node's own `gap`, `distribute` or `alignH` re-places its children
	inside a box whose SIZE never moves — so the shared size test passes, the skip
	does not fire because the node is dirty, and the arm re-based a subtree that
	needed re-arranging.

	MEASURED, all three, against a forced full solve, before the predicate existed:
	  * `gap` 4 -> 12 on a fixed 300x40 HStack, driven with `offsetX`: child B at
	    x=44 where a full solve puts it at 52.
	  * `distribute` "spaceBetween" -> "center" on the same stack: children left
	    pinned at 20/300 where a full solve puts them at 150/170.
	  * `alignH` "start" -> "center" on a fixed 300x40 ZStack: child at x=20 where a
	    full solve puts it at 160.
	The `distribute` one was found by the SUITE (`layout_prop_dirt.spec`'s
	arrange-only audit, "driving each of them measures NOTHING and lands a FULL
	solve's geometry"), not by this file — which is why the fourth case below pins
	the partition mechanically instead of trusting the reasoning.

	AND THE FOURTH DRIVE IS THE ONE A PRESENCE TEST FAILS. An earlier form of the
	predicate refused a node that CARRIED one of the three props; driving a reactive
	`distribute` from "spaceEvenly" back to `nil` is reachable (no throw, no
	refusal), and at that moment `node.distribute` is nil, so a presence test calls
	it translatable while its children still need re-spreading. The shipped
	predicate records the three on the entry and compares BY VALUE. ]]
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local fs = require("@lune/fs")
local schema = require("../src/blueprint_schema")

local function px(n: number): any
	return { type = "fixed", px = n }
end

--[[ A FIXED-SIZE CONTAINER WITH TWO FIXED CHILDREN, driven on `offsetX` (so the
	container really does move and really is dirty) and on ONE self-placement prop.
	`kind` picks the container, `prop` the second drive. Both children are fixed x
	fixed so nothing here can resize: every divergence this fixture can produce is a
	re-placement the arm skipped. ]]
local function placeWorld(kind: string, prop: string, incremental: boolean, view: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local sig = core:signal(nil :: any)
	local dx = core:signal(0)
	local inner: any = {
		id = "Bar",
		anchor = "topLeft",
		offsetX = dx,
		padding = 0,
		width = px(300),
		height = px(40),
		children = {
			UI.Box({ id = "A", width = px(20), height = px(20) }),
			UI.Box({ id = "B", width = px(20), height = px(20) }),
		},
	}
	inner[prop] = sig
	-- `gap` is a stack prop; UI.ZStack refuses it outright, which is itself the
	-- proof that these two containers are not interchangeable fixtures
	if kind ~= "zstack" and inner.gap == nil then
		inner.gap = 0
	end
	local body = if kind == "zstack" then UI.ZStack(inner) else UI.HStack(inner)
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "C",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { body },
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = incremental,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	local w: any = {}
	function w.drive(value: any, x: number)
		sig:set(value)
		dx:set(x)
		controller.refresh()
	end
	function w.rects(): string
		local out = {}
		for path, node in adapter.liveNodes() do
			local r = node.rect
			table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}`)
		end
		table.sort(out)
		return table.concat(out, "\n")
	end
	function w.stats(): any
		return controller.stats()
	end
	function w.dispose()
		controller.dispose()
		root.dispose()
	end
	return w
end

describe("O3: a translate root's own layout prop still re-places its children", function()
	local CASES: { any } = {
		-- `gap` is MEASURE-classed, so `measureContains` is what refuses it
		{ name = "gap", kind = "hstack", prop = "gap", values = { 4, 12, 12, 2 } },
		-- `distribute` is ARRANGE-classed and read off the node ITSELF: the case the
		-- suite found, and the reason `selfArrange` is on the entry
		{
			name = "distribute",
			kind = "hstack",
			prop = "distribute",
			values = { "spaceBetween", "center", "end", "spaceEvenly" },
		},
		-- ...and the same for a ZStack's own `alignH` default
		{ name = "alignH", kind = "zstack", prop = "alignH", values = { "start", "center", "end", "end" } },
		-- THE VALUE-NOT-PRESENCE DRIVE: the prop goes back to absent
		{ name = "distribute-to-nil", kind = "hstack", prop = "distribute", values = { "spaceEvenly", nil, "center" } },
	}
	for _, case in CASES do
		it(`{case.name}: a moved container whose own {case.prop} changed agrees with a full solve`, function()
			for _, view in device_views.VIEWS do
				local a = placeWorld(case.kind, case.prop, true, view)
				local c = placeWorld(case.kind, case.prop, false, view)
				for step = 1, #case.values + 1 do
					-- `values` may hold a nil, so index it directly rather than iterating
					a.drive(case.values[step], step * 10)
					c.drive(case.values[step], step * 10)
					if a.rects() ~= c.rects() then
						error(`{case.name}/{view.id}: step {step} diverged from a FULL solve`, 0)
					end
				end
				a.dispose()
				c.dispose()
			end
		end)
	end

	--[[ ...AND THE PARTITION ITSELF, MECHANISED. `selfPlaces` refuses a dirty
		translate root on two grounds: measure-classed self-dirt (`measureContains`
		answers for it) and the arrange-classed props the node's own body reads
		(recorded on the entry by `selfArrangeKey` and compared by value). The second
		half is a claim about which of the schema's arrange-only props appear as
		`node.<prop>` in the solver — so it is derived from both files rather than
		transcribed, and a ninth arrange-only prop, or a new `node.<prop>` read of an
		existing one, reddens this case instead of silently falsifying the comment. ]]
	it("selfArrangeKey covers exactly the arrange-only props the solver reads off the NODE", function()
		-- `propDirty()` is keyed by CLASS and the same prop appears under every class
		-- that accepts it, so the set has to be built before it is listed
		local seen: { [string]: boolean } = {}
		local arrangeOnly: { string } = {}
		for _, props in schema.propDirty() do
			for prop, classes in props do
				if #classes == 1 and classes[1] == "arrange" and not seen[prop] then
					seen[prop] = true
					table.insert(arrangeOnly, prop)
				end
			end
		end
		table.sort(arrangeOnly)
		-- the same eight `layout_prop_dirt.spec` pins; asserted here too because the
		-- partition below is a statement ABOUT this set
		expect(table.concat(arrangeOnly, ",")).toBe("alignH,alignV,anchor,distribute,hidden,lineAlign,offsetX,offsetY")
		-- comments name plenty of props; only CODE decides what arrange reads
		local source = fs.readFile("src/layout/solver.luau")
		source = source:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
		local selfRead: { string } = {}
		for _, prop in arrangeOnly do
			if source:find(`node%.{prop}[^%w_]`) ~= nil then
				table.insert(selfRead, prop)
			end
		end
		expect(table.concat(selfRead, ",")).toBe("alignH,alignV,distribute")
		-- ...and every one of them is in the recorded key. `selfArrangeKey`'s body is
		-- read out of the source so this cannot pass on a key that dropped one.
		local key = source:match("local function selfArrangeKey.-\nend")
		expect(`found={tostring(key ~= nil)}`).toBe("found=true")
		for _, prop in selfRead do
			expect(`{prop} in selfArrangeKey={tostring((key :: string):find(`node%.{prop}[^%w_]`) ~= nil)}`).toBe(
				`{prop} in selfArrangeKey=true`
			)
		end
	end)
end)

--[[ THE CHAIN BREAK, PINNED. `translateDescendants` writes `entry.prev =
	prevEntry` for the next commit's identity compare and then clears
	`prevEntry.prev` — without that one line, tick N's entry holds N-1, which holds
	N-2, forever, and a few hundred ticks retain hundreds of thousands of entries.

	IT IS NOT PINNED ON `collectgarbage("count")`, AND THAT IS A MEASUREMENT, NOT A
	PREFERENCE. Lune's `collectgarbage` accepts only `"count"` — no forced
	collection (`tests/adaptive_defaults.spec.luau` and `tools/lune/bench.luau` both
	record it) — so a KB delta over 200 ticks reports whatever the incremental
	collector happened to have swept. Measured with the chain break IN PLACE and
	allocation-pressure churn on both readings: **+50,417 KB**, because 200 ticks
	allocate 250,000 replacement entries as GARBAGE and the collector had not
	finished with them. An instrument that reads +50 MB on the HEALTHY build cannot
	report a leak, so this uses the two channels that can:

	  1. THE CHAIN DEPTH, read straight off the entry. Deterministic, no collector
	     involved: after three solves, `entry.prev` exists (the commit reads it) and
	     `entry.prev.prev` does not.
	  2. THE ENTRY REALLY DIES, via a weak-keyed canary and the churn idiom
	     `adaptive_defaults.spec.luau` established — with its control, so a green
	     result is the design's doing and not the collector's laziness.

	Both run on `solver.solve` DIRECTLY (the idiom `rect_cow.spec.luau` uses),
	because the entry table is the thing under test and the controller does not
	publish it. A hand-built `reuse` carries no `measureContains`, so `selfPlaces`
	refuses every DIRTY root here — which is why the drive dirties the ROOT and the
	translate roots under it are its CLEAN children. ]]
local solver = require("../src/layout/solver")

local function chainTree(pad: number): any
	local children = {}
	for g = 1, 3 do
		local kids = {}
		for i = 1, 3 do
			table.insert(kids, { kind = "box", id = `/root/g{g}/l{i}`, width = px(12), height = px(8), children = {} })
		end
		-- FIXED width on the group, so a fractional `padding` on the root moves it
		-- without ever RESIZING it: the shared size test has to keep passing or the
		-- three cases below are measuring the ordinary arrange
		table.insert(children, { kind = "vstack", id = `/root/g{g}`, width = px(12), gap = 2, children = kids })
	end
	return { kind = "vstack", id = "/root", gap = 4, padding = pad, children = children }
end

local function rectKey(r: any): string
	local out = {}
	for id, entry in r.rects do
		local rc = entry.rect
		table.insert(out, `{id}|{rc.x},{rc.y},{rc.w},{rc.h}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

describe("O3: the re-based entries do not retain the history of a plate", function()
	--[[ THE ARITHMETIC IS A ROUND TRIP, NOT A RUNNING TOTAL — found as a defect by
		the SUITE, not by this file. Re-basing a descendant as `old + (new - old)`
		accumulates one rounding per solve: `tests/table.spec`'s two reorder-handle
		cases drive a reveal spring for tens of frames and read back
		35.99999999999998 for a row whose closed x is exactly 36. The shipped form
		re-derives the child's offset FROM THE ROOT's current origin every time, so a
		subtree this arm itself produced has an exactly-representable offset and the
		answer is idempotent. This is that shape, minimised: a fixed-size container
		whose own `offsetX` walks sixty FRACTIONAL steps out and comes back to 0. ]]
	it("a translate root that returns to where it started puts its subtree back EXACTLY", function()
		local view = device_views.VIEWS[1]
		-- `placeWorld`'s second signal is left at 0 throughout, so the ONLY dirt on
		-- every step is the container's own `offsetX` — the arrange-only, parent-read
		-- placement prop the arm exists for
		local w = placeWorld("hstack", "gap", true, view)
		w.drive(0, 0)
		local home = w.rects()
		local steps = 0
		for i = 1, 60 do
			w.drive(0, i * 0.1)
			steps += if w.stats().lastTranslated > 0 then 1 else 0
		end
		-- every one of the sixty really took the arm, so the round trip below is
		-- sixty re-basings and not sixty ordinary arranges
		expect(`translatedSteps={steps}`).toBe("translatedSteps=60")
		w.drive(0, 0)
		expect(w.rects()).toBe(home)
		w.dispose()
	end)

	it("an entry holds the one it superseded and NOT the one before that", function()
		local vp = { w = 400, h = 800 }
		local dirty = { ["/root"] = true }
		local r = solver.solve(chainTree(0), vp, {})
		for pad = 1, 3 do
			r = solver.solve(chainTree(pad), vp, { reuse = { previous = r, dirtyContains = dirty } })
		end
		-- it really translated, or the two reads below are about nothing
		expect(`translated={r.work.translated > 0}`).toBe("translated=true")
		local leaf = r.rects["/root/g2/l2"]
		expect(`moveOnly={tostring(leaf.moveOnly)} prev={tostring(leaf.prev ~= nil)}`).toBe("moveOnly=true prev=true")
		expect(`chain={tostring(leaf.prev.prev)}`).toBe("chain=nil")
	end)

	it("...and the superseded entry is actually collectable", function()
		local vp = { w = 400, h = 800 }
		local dirty = { ["/root"] = true }
		local watched: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
		-- the CONTROL from `adaptive_defaults.spec.luau`: an entry that MUST die if
		-- anything died at all, so a green result is not the collector being idle
		local canary: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
		canary[{}] = true
		local r = solver.solve(chainTree(0), vp, {})
		r = solver.solve(chainTree(1), vp, { reuse = { previous = r, dirtyContains = dirty } })
		-- the entry written by solve 2, held ONLY weakly from here on
		watched[r.rects["/root/g2/l2"]] = true
		for pad = 2, 12 do
			r = solver.solve(chainTree(pad), vp, { reuse = { previous = r, dirtyContains = dirty } })
		end
		-- enough short-lived tables that anything unreachable has certainly gone
		for _ = 1, 12 do
			local waste = table.create(20000)
			for i = 1, 20000 do
				waste[i] = { i }
			end
		end
		local collected = true
		for _ in canary do
			collected = false
		end
		local retained = false
		for _ in watched do
			retained = true
		end
		if not collected then
			-- the churn did not collect under this run; the case says so rather than
			-- passing on an assertion it could not compel
			expect("the churn did not collect - inconclusive, not green").toBe(
				"the churn did not collect - inconclusive, not green"
			)
		else
			expect(`retained={retained}`).toBe("retained=false")
		end
	end)
end)

--[[ THE ORACLE'S ARMS, the same three as `tests/measure_split.spec.luau`'s. `a` is
	the shipped configuration (cross-solve measure slates ON, incremental arrange ON
	— the arm lives inside the second), `b` keeps incremental arrange but throws the
	slates away, and `c` forces a FULL solve every refresh and is the ground truth.
	An arm that re-based a subtree it should have re-entered shows up as `a`
	disagreeing with `c`. The channel compared is `scene.snapshot()` — every live
	node's rect, hit rect, scroll region, visibility and adapter props, sorted. ]]
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

-- see `measure_split`'s note: the tree SHAPE is what correctness depends on and it
-- is per-plate identical, so 20 plates exercises every branch 250 does (4 casters,
-- the overflow plate beside plates that fit, the ForEach region, `scaleOffset`).
-- The COUNT pins above run at the full 250.
local ORACLE_PLATES = 20

describe("O3 oracle: byte-equal to a full solve, every view, every step kind", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, visibility, hit rects and scroll regions survive the arm`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
				end
				for step = 1, 4 do
					local dx, dy = step * 3, step * 2
					a.tick(dx, dy)
					b.tick(dx, dy)
					c.tick(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: tick {step} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= b.snapshot() then
						error(`{label}: tick {step} diverged from the memo-less solve`, 0)
					end
					a.tickWithCasts(dx, dy)
					b.tickWithCasts(dx, dy)
					c.tickWithCasts(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: caster tick {step} diverged from a FULL solve`, 0)
					end
					a.hp(7, 0.1 * step)
					b.hp(7, 0.1 * step)
					c.hp(7, 0.1 * step)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: hp {step} diverged from a FULL solve`, 0)
					end
					--[[ ...AND THE STRUCTURAL ARM, which the three drives above never
						reach and which the arm has its own stake in: on the structural
						path `measureContains` is ALIASED to `structuralPlan.contains`, so
						`selfPlaces` refuses every dirty root there, and `translatable`
						refuses any child `structural_scope.widen` named. Keyed by `step`,
						not a constant: `scene.add` mints the key `add{i}` and a ForEach
						treats a duplicate key as a HARD error. ]]
					a.add(step)
					b.add(step)
					c.add(step)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: add {step} diverged from a FULL solve`, 0)
					end
					-- ...and the tick right after it, because a structural solve's own
					-- rects are only half the claim: the NEXT incremental solve runs
					-- against a rect map the structural one only partly rewrote
					a.tick(dx, dy)
					b.tick(dx, dy)
					c.tick(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: tick-after-add {step} diverged from a FULL solve`, 0)
					end
					-- ...and `remove` takes an INDEX, so removing the row just added
					-- (the last one) is what returns the list to its previous shape
					local added = #a.items
					a.remove(added)
					b.remove(added)
					c.remove(added)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: remove {step} diverged from a FULL solve`, 0)
					end
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)
