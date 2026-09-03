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
local solver = require("../src/layout/solver")

local function sortedKeys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for k in set do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

local ARRANGE_SOURCE = (function(): { string }
	local body = fs.readFile("src/layout/solver.luau")
	body = body:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	local from = body:find("local function arrange%(ctx", 1)
	local to = body:find("\nfunction solver%.solve%(", from)
	return string.split(string.sub(body, from :: number, to), "\n")
end)()

--[[ ...AND THE HALF OF `arrange` THAT NOW LIVES IN ANOTHER FILE (2026-09-02, the
	T6 stack seam). The vstack/hstack branch — the largest of `arrange`'s container
	branches, and the one that reads `node.align` and four `child` props — moved to
	`src/layout/stack.luau` for the solver's Source-write headroom. The prop audits
	below are the arm's soundness argument and they scan SOURCE, so a scan that kept
	reading only the solver would have silently stopped covering that branch on the
	extraction commit: the coverage would have narrowed while every case stayed green,
	which is the hazard this repository keeps re-learning one file over
	(`tests/stack_distribution.spec.luau`'s STRUCTURAL C5, red on the same commit).

	IT IS A SEPARATE LIST FROM `ARRANGE_SOURCE` rather than an extension of it,
	because `LITERAL_AT` and `stampsAfterLiteral` are about the ENTRY LITERAL and
	that is the solver's alone — a second file in their input would have no literal
	in it and index nothing. So the two prop audits take the union and the literal
	rules take the solver. ]]
local ARRANGE_BRANCH_SOURCE = (function(): { string }
	local out = table.clone(ARRANGE_SOURCE)
	local body = fs.readFile("src/layout/stack.luau")
	body = body:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	for _, line in string.split(body, "\n") do
		table.insert(out, line)
	end
	return out
end)()

-- the line index of the entry LITERAL's own `out[node.id] = {`; everything the
-- refusal is about is written after it
local LITERAL_AT = (function(): number
	for i, line in ARRANGE_SOURCE do
		if line:match("^\tout%[node%.id%] = {") then
			return i
		end
	end
	return -1
end)()

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

	--[[ ...AND THE PARTITION ITSELF, MECHANISED — FROM THE ARRANGE SOURCE, NOT FROM
		THE SCHEMA'S CLASS COLUMN (task review round 1, Important 3).

		The property `selfPlaces` depends on is: **every prop the arrange half reads
		off the NODE is either measure-classed (so `measureContains` answers for it)
		or recorded by `selfArrangeKey`**. An earlier version of this case derived its
		set from `schema.propDirty()` — every prop declared exactly `{ "arrange" }` —
		which guards something narrower: a future `{ "arrange", "paint" }` prop, or a
		plain `{ "paint" }` prop that `arrange` starts reading, is invisible to
		`measureContains` AND to that filter. Today's schema has no multi-class
		arrange prop, so it passed for the right reason; it was not the mitigation.

		This derives the set from the code instead. Every `node.<prop>` read inside
		`arrange` (comments stripped), minus the two families that cannot reach the
		gate, must be exactly `selfArrangeKey`'s three. The two families are DERIVED
		too, not listed by hand:
		  * measure-classed per `schema.propDirty()` — `align`, `axis`, `gap`,
		    `overflow`, `padding`, `virtualSlot` today;
		  * not a schema prop AT ALL — `children`, `containerRelativeInside`,
		    `hitFloor`, `id`, `kind`, `leadingBleed`: fields `layout_node` stamps at
		    build time, with no reactive binding and therefore no dirt class. A field
		    that later BECOMES a prop leaves this family on its own and lands in the
		    remainder, where it is either measure-classed or a failure. ]]
	local SCHEMA_CLASSES: { [string]: { string } } = (function()
		local out: { [string]: { string } } = {}
		for _, props in schema.propDirty() do
			for prop, classes in props do
				out[prop] = classes
			end
		end
		return out
	end)()

	local function isMeasureClassed(prop: string): boolean
		for _, class in SCHEMA_CLASSES[prop] or {} do
			if class == "measure" then
				return true
			end
		end
		return false
	end

	local function nodeReadsIn(lines: { string }): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for _, line in lines do
			for prop in line:gmatch("node%.([%a_][%w_]*)") do
				out[prop] = true
			end
		end
		return out
	end

	it("every node prop ARRANGE reads is measure-classed, structural, or in selfArrangeKey", function()
		local reads = nodeReadsIn(ARRANGE_BRANCH_SOURCE)
		local remainder: { string } = {}
		local structural: { string } = {}
		for _, prop in sortedKeys(reads) do
			if SCHEMA_CLASSES[prop] == nil then
				table.insert(structural, prop)
			elseif not isMeasureClassed(prop) then
				table.insert(remainder, prop)
			end
		end
		-- the build-time fields, named so their membership is visible rather than
		-- inferred from a green run
		expect(structural).toEqual({
			"children",
			"containerRelativeInside",
			-- `hKey`/`wKey` are `node.path .. "|h"` / `.. "|w"`, built once where the
			-- node is built (wicked-fast A1): a pure function of IDENTITY, so a node
			-- whose key changed is a different node and the arm's question does not
			-- arise. They are the memo-offer channel's index, not a layout input.
			"hKey",
			"hitFloor",
			"id",
			"kind",
			"leadingBleed",
			"wKey",
		})
		-- ...and THE CLAIM: what is left is exactly what the entry records
		local body = fs.readFile("src/layout/solver.luau")
		body = body:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
		local key = body:match("local function selfArrangeKey.-\nend")
		expect(`keyFound={tostring(key ~= nil)}`).toBe("keyFound=true")
		expect(remainder).toEqual(sortedKeys(nodeReadsIn({ key :: string })))
		expect(remainder).toEqual({ "alignH", "alignV", "distribute" })
	end)

	it("...and the schema's own arrange-only column agrees, which is the weaker pin", function()
		--[[ Kept as a SECOND pin because it says something the scan cannot: that the
			four parent-read placement props and `hidden` are still declared
			arrange-only, so the partition's other half — "already spent in the rect we
			were handed" — is still about the props it was written about. It is weaker
			because a multi-class prop escapes it; the case above is the one that
			carries the property. ]]
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
		expect(table.concat(arrangeOnly, ",")).toBe("alignH,alignV,anchor,distribute,hidden,lineAlign,offsetX,offsetY")
		-- the four the PARENT reads off the child appear nowhere in `arrange` as
		-- `node.<prop>`, which is why the rect we were handed has already spent them
		local reads = nodeReadsIn(ARRANGE_BRANCH_SOURCE)
		for _, prop in { "anchor", "offsetX", "offsetY", "lineAlign", "hidden" } do
			expect(`{prop} read off the node in arrange={tostring(reads[prop] == true)}`).toBe(
				`{prop} read off the node in arrange=false`
			)
		end
	end)

	it("NEGATIVE CONTROL: the scan reports a node read it does not expect", function()
		-- the scan is a pure function of lines, so it is fed the defect: a paint-classed
		-- prop that `arrange` has started reading off the node
		local fake = { "\tlocal t = node.opacity", "\tlocal u = node.gap", '\tif node.kind == "grid" then' }
		expect(sortedKeys(nodeReadsIn(fake))).toEqual({ "gap", "kind", "opacity" })
		expect(`opacity measure-classed={tostring(isMeasureClassed("opacity"))}`).toBe("opacity measure-classed=false")
		-- ...so it would survive both filters and land in the remainder, which is what
		-- makes the case above fail rather than pass quietly
		expect(`opacity is a schema prop={tostring(SCHEMA_CLASSES.opacity ~= nil)}`).toBe(
			"opacity is a schema prop=true"
		)
	end)
end)

--[[ A TRANSLATED SUBTREE KEEPS ITS FINDINGS — the replay gate, widened for the new
	class (task review round 1, Critical 1).

	Before O3 "not in `walkedIds`" implied "under a skip", so `solve`'s replay could
	be gated on `ctx.skipped > 0`. The arm creates a THIRD population — arranged,
	deliberately absent from `walkedIds`, and NOT under any skip — and on a solve
	where every node is either arranged or translated the gate cannot fire at all.
	The nameplates pure tick is exactly that shape (252 + 1250 == 1502, `skipped`
	0), and so is every caster tick's fifty childless `Hp` roots.

	MEASURED before the fix, on `solver.solve`: a `vstack` whose padding collapses
	its content box files THREE findings on solve 1; on solve 2, where its parent's
	padding moves it and it translates (`arranged=2 translated=1 skipped=0`),
	`#result.diagnostics` is 0 — the findings are gone, and they stay gone for as
	long as the node keeps moving. The CONTROL below is the same tree with a sibling
	that skips: `skipped=2`, the gate fires, and all three come back. That pair is
	what says the defect is the GATE and not the arm.

	The oracle further down gained a diagnostics channel for the same reason, and
	`mountedReportWorld` carries the claim through the whole renderer at every
	device view; these cases exist because a fixture that files zero findings makes
	that channel prove nothing. ]]
local function reportTree(pad: number, gap: number, quietFirst: boolean): any
	local bad = {
		kind = "vstack",
		id = "/r/bad",
		width = px(20),
		height = px(20),
		-- 40 a side on a 20px box: the content box collapses on both axes and the
		-- child overflows it, which is three findings from `arrange_reports.box`
		padding = 40,
		children = { { kind = "box", id = "/r/bad/kid", width = px(4), height = px(4), children = {} } },
	}
	local kids: { any } = { bad }
	if quietFirst then
		-- FIRST, so a `gap` change leaves it exactly where it was and it SKIPS while
		-- `bad` below it translates
		table.insert(kids, 1, {
			kind = "vstack",
			id = "/r/quiet",
			width = px(20),
			height = px(20),
			children = { { kind = "box", id = "/r/quiet/kid", width = px(4), height = px(4), children = {} } },
		})
	end
	return { kind = "vstack", id = "/r", gap = gap, padding = pad, children = kids }
end

local function findingsOf(r: any): string
	local out = {}
	for _, d in r.diagnostics do
		table.insert(out, `{d.node}|{string.sub(d.issue, 1, 28)}`)
	end
	table.sort(out)
	return `{#r.diagnostics}: ` .. table.concat(out, " ")
end

describe("O3: a translated subtree keeps its findings", function()
	local VP = { w = 400, h = 400 }
	local DIRT = { ["/r"] = true }

	it("a solve where NOTHING skipped still replays what the translated subtree filed", function()
		local first = solver.solve(reportTree(0, 4, false), VP, {})
		local before = findingsOf(first)
		expect(`solve1={before}`).toBe(
			"solve1=3: /r/bad|content box collapses to 0px /r/bad|content box collapses to 0px "
				.. "/r/bad|content overflows this vstac"
		)
		local second = solver.solve(reportTree(6, 4, false), VP, { reuse = { previous = first, dirtyContains = DIRT } })
		-- the shape that makes the old gate unreachable: every node is arranged or
		-- translated, so `skipped` is 0 and there is nothing for a `skipped > 0` test
		-- to fire on
		expect(`arranged={second.work.arranged} translated={second.work.translated} skipped={second.work.skipped}`).toBe(
			"arranged=2 translated=1 skipped=0"
		)
		expect(`solve2={findingsOf(second)}`).toBe(`solve2={before}`)
	end)

	it("CONTROL: the same tree WITH a skip replays them, which is what makes it the gate", function()
		--[[ Identical fixture, driven on `gap` instead of `padding` and with a quiet
			sibling FIRST: the sibling lands on the rect it already had and skips, `bad`
			below it still translates, and `skipped` is 2. This case was GREEN before
			the fix and stays green after it — its job is to show that what the case
			above catches is the gate's reach, not the arm losing findings some other
			way. ]]
		local first = solver.solve(reportTree(0, 4, true), VP, {})
		local before = findingsOf(first)
		local second = solver.solve(reportTree(0, 10, true), VP, { reuse = { previous = first, dirtyContains = DIRT } })
		expect(`arranged={second.work.arranged} translated={second.work.translated} skipped={second.work.skipped}`).toBe(
			"arranged=2 translated=1 skipped=2"
		)
		expect(`solve2={findingsOf(second)}`).toBe(`solve2={before}`)
	end)

	it("...and they keep replaying: ten translating solves in a row, never once dropped", function()
		-- a single replay is not the claim; the claim is that a subtree which keeps
		-- moving keeps its findings for as long as it moves
		local r = solver.solve(reportTree(0, 4, false), VP, {})
		local before = findingsOf(r)
		for pad = 1, 10 do
			r = solver.solve(reportTree(pad, 4, false), VP, { reuse = { previous = r, dirtyContains = DIRT } })
			expect(`pad{pad}={findingsOf(r)}`).toBe(`pad{pad}={before}`)
		end
	end)
end)

--[[ THE ENTRY IS NOT THE LITERAL — the instrument the rect oracle could not be
	(task review round 1, Critical 2).

	`arrange`'s entry literal is only HALF an entry for two kinds. A `scroll` node's
	own branch stamps `contentSize`, `padding`, `barInset` and a computed `overflow`
	onto `out[node.id]` AFTER the literal; a `composition` node stamps
	`composition`. A translate root returns before its branch ever runs, so it wrote
	the literal and nothing else — and every one of those fields silently became
	`nil` while the rect stayed perfect. Downstream, same commit:
	`rect_pass` publishes `lastBarInsets[path] = entry.barInset` unconditionally, so
	`controller.scrollBarInsetOf` starts answering nil and a table header loses its
	scrollbar gutter; `commit_walks` gates the scroll-region write on
	`entry.contentSize ~= nil`, so the host drops out of `scrollRegions` entirely (no
	`setScrollRegion`, no autoscroll refresh, no path-clip observer); and
	`lastCompositions[path] = entry.composition` goes nil for a composition root.

	MEASURED before the fix, through the renderer: a moved `ScrollView` went
	`contentSize=true padding=true overflow=scroll` -> `false/false/nil`, and a moved
	`Composition` went `composition=true` -> `false`. The rects and every child were
	unchanged, which is exactly why the rect oracle stayed green.

	THE RULING IS REFUSE, NOT CARRY FORWARD: a node whose own branch writes entry
	fields after the literal is never a translate root (`literalIsWholeEntry`). Its
	subtree still translates when the node ABOVE it is the root — a translated
	DESCENDANT is a `table.clone` of its previous entry and carries every field
	forward — so the refusal costs one entry write on the node itself.

	AND THE CLASS IS WIDER THAN "MOVED". The arm fires with a ZERO delta whenever a
	node is dirty for a reason `selfPlaces` clears and lands where it already was
	(`tdx = 0`, not `nil`) — so both drives below are real: `offsetX`, which moves
	it, and an inert `lineAlign` under an `Anchor` parent, which dirties it and moves
	nothing. ]]
local function ser(v: any, depth: number): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	if depth > 8 then
		return "<deep>"
	end
	local parts = {}
	for k, val in v do
		table.insert(parts, `{tostring(k)}={ser(val, depth + 1)}`)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

--[[ EVERY FIELD OF EVERY ENTRY, MODULO EXACTLY `moveOnly` AND `prev` — the two the
	arm is allowed to add and the commit is the only reader of. Anything else that
	differs between an incremental solve and a forced full one is a defect of this
	arm, whatever the rects say.

	...AND `offerW`/`offerH` ARE NO LONGER AMONG THEM (wicked-fast T6, 2026-09-02),
	which is this comment's whole history reversed and is worth stating as such.

	WHAT THIS FILE USED TO SAY, and it was true when it was written: `ctx.offers` was
	written ONLY inside `measureUncached`, so any node served from the per-solve memo
	or a cross-solve slate recorded `nil` there — true of every SKIPPED node's
	inherited entry and of every ancestor on an incremental solve, and of none of them
	on a forced full one. Observed on `/S`, `/S/C` and `[p5]/Plate/Row`: `offerH=718
	offerW=359` on the full arm, absent on the incremental one. The two fields were
	therefore excluded here and asked only of the arm's own entries.

	WHY IT IS NOT TRUE ANY MORE: that asymmetry was a DEFECT of the offer channel, not
	a property of it, and T6 fixed it at the source — `measure`'s memo-hit path now
	records the offer too, because the memo KEY IS the offer and saying so costs two
	table writes and no string (`node.wKey`/`node.hKey`). So an incremental solve and
	a forced full one record the same offers for the same nodes, and the exclusion
	that was honest before would now be hiding the very thing it was written to
	describe. The fields are compared like every other one, and `armOfferDiff` below
	is upgraded from "ask the memo-LESS arm" to an EQUALITY across both arms. ]]
local SHARED_SKIP = { moveOnly = true, prev = true }

-- every entry, modulo the four above
local function entryKey(rects: any): string
	local out = {}
	for id, entry in rects do
		local parts = {}
		for k, v in entry do
			if not SHARED_SKIP[k] then
				table.insert(parts, `{tostring(k)}={ser(v, 0)}`)
			end
		end
		table.sort(parts)
		table.insert(out, `{id}|{table.concat(parts, ",")}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

--[[ ...AND WHAT THE ARM OWES THE OFFER CHANNEL, in the two halves that together
	cover every entry the arm wrote. `entryKey` above cannot ask for either, because
	the channel is best-effort and the memo makes it asymmetric.

	DESCENDANTS (`work.translatedPaths`) are `table.clone`s, so their offers must be
	exactly the ones they superseded — untouched, not recomputed and not dropped.
	Local and deterministic, and it has to be asked this way rather than against the
	full arm: the nil-vs-number difference reaches clones too. `[p5]/Plate/Row` was
	ARRANGED on an earlier solve whose measure hit the memo, so its entry recorded
	`offerW = nil` and every clone after it carries the nil while a forced full solve
	writes 359. Measured.

	ROOTS (`work.translatedRoots`) get the stronger question, against the FULL-SOLVE
	arm — and since T6 (2026-09-02) it is asked of BOTH incremental arms, which is
	this paragraph's own history reversed. What it used to say, and why:

	  | arm                                   | translate root's offer | full solve |
	  | `a` memo ON, incremental ON  (cold)   | 359x718                | 359x718    |
	  | `a` memo ON, incremental ON  (steady) | **nil x nil**          | 359x718    |
	  | `b` memo OFF, incremental ON (steady) | 359x718                | 359x718    |

	The literal stamps `offerW = ctx.offers[<key>]`, `ctx.offers` was written ONLY
	inside `measureUncached`, and on a steady tick every plate root's measure hits its
	cross-solve slate — which is exactly what T3 bought — so `a`'s roots recorded nil.
	The question was therefore asked of `b` alone, because asking it of `a` would have
	been red forever for a reason that was not this arm's.

	T6 REMOVED THE REASON. `measure`'s memo-hit path records the offer too (the memo
	KEY is the offer), so `a` and `b` now answer identically and the loop below runs
	over BOTH arms' roots. THE EQUALITY IS THE POINT: an arm whose offers agree with a
	full solve only when the memo is off is an arm with a channel that goes dark on
	exactly the ticks the framework was optimised for. This is the check that would
	have caught the nil in the first place, and it is why T6's anchor arm — whose
	whole precondition is `prev.offerW == innerW` — could not have worked before it.

	THE SETS ARE `work.translatedPaths`/`translatedRoots`, NOT "every entry carrying
	`moveOnly`", and the difference is a fact worth writing down for T5: `moveOnly`
	is a property of the SOLVE THAT LAST WROTE THE ENTRY, not of this one. The rect
	map is copy-on-write, so a node that translated on tick N and then SKIPPED on
	tick N+1 still carries `moveOnly = true` on tick N+1 — measured here, on
	`[p2]/Plate` across a `tick` followed by an `hp` drive. The two work lists are
	this solve's own, in document order. ]]
local function armOfferDiff(aResult: any, bResult: any, cRects: any): string?
	local work = aResult.work or {}
	local bWork = bResult.work or {}
	local roots = 0
	-- BOTH incremental arms, against the full solve, since T6: `a` is the SHIPPED
	-- configuration and it is the one whose answer used to be nil. Named in the
	-- message so a failure says which arm went dark.
	for _, arm in
		{ { id = "a(memo)", result = aResult, work = work }, { id = "b(memo-less)", result = bResult, work = bWork } }
	do
		for path in arm.work.translatedRoots or {} do
			if arm.id == "b(memo-less)" then
				roots += 1
			end
			local mine, theirs = arm.result.rects[path], cRects[path]
			if theirs == nil then
				return `{path}: a translate root the FULL solve has no entry for ({arm.id})`
			end
			if mine.offerW ~= theirs.offerW or mine.offerH ~= theirs.offerH then
				return `{path}: {arm.id} ROOT offers {tostring(mine.offerW)}x{tostring(mine.offerH)} against a full solve's {tostring(
					theirs.offerW
				)}x{tostring(theirs.offerH)}`
			end
		end
	end
	-- ...and the memo-less arm really did take the arm on this step, or the loop
	-- above is a loop over nothing and the root half proves nothing
	if roots == 0 and #(work.translatedPaths or {}) > 0 then
		return "the shipped arm translated but the memo-less arm recorded no root"
	end
	for i, path in work.translatedPaths or {} do
		local entry = (work.translatedEntries or {})[i]
		if entry == nil or entry ~= aResult.rects[path] then
			return `{path}: translatedEntries[{i}] is not the entry in the map`
		end
		local was = entry.prev
		if was == nil then
			return `{path}: a re-based entry with no \`prev\``
		end
		if entry.offerW ~= was.offerW or entry.offerH ~= was.offerH then
			return `{path}: offers changed {tostring(was.offerW)}x{tostring(was.offerH)} -> {tostring(entry.offerW)}x{tostring(
				entry.offerH
			)}`
		end
	end
	return nil
end

--[[ The solver's rect map is not on the controller's public surface and this task
	adds nothing to it, so the entry channel is opened the way FacetBench's own
	`attr` driver opens one: wrap the module function for the duration of one case
	and put it back. `renderer.luau` calls `solver.solve(...)` as a field lookup, so
	the wrapper is on the shipped path; it is restored even when the body throws. ]]
local capturedResult: any = nil
local function withEntryCapture(fn: () -> ())
	local real = solver.solve
	solver.solve = function(...)
		local r = real(...)
		capturedResult = r
		return r
	end
	local ok, err = pcall(fn)
	solver.solve = real
	capturedResult = nil
	if not ok then
		error(err, 0)
	end
end

local function branchFieldWorld(incremental: boolean, memoReuse: boolean, view: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local dx = core:signal(0)
	-- `lineAlign` under an `Anchor` parent is INERT — the anchor branch reads
	-- `anchor`/`offsetX`/`offsetY` and nothing else — so driving it dirties the node
	-- and moves it by exactly zero, which is the `tdx = 0` arm
	local la = core:signal("start")
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "C",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.ScrollView({
							id = "Scroll",
							axis = "y",
							anchor = "topLeft",
							offsetX = dx,
							lineAlign = la,
							width = px(80),
							height = px(50),
							gap = 2,
							children = {
								UI.Box({ id = "a", width = px(60), height = px(30) }),
								UI.Box({ id = "b", width = px(60), height = px(30) }),
								UI.Box({ id = "c", width = px(60), height = px(30) }),
							},
						}),
						UI.Composition({
							id = "Comp",
							arrangements = { "threeLane", "column" },
							laneGap = 12,
							groupGap = 8,
							anchor = "topLeft",
							offsetY = dx,
							lineAlign = la,
							width = px(400),
							height = px(300),
							groups = {
								{ id = "lead", lane = "lead", sizing = "hug", place = "center" },
								{ id = "main", lane = "main", sizing = "fill", minWidth = 120 },
							},
							children = {
								UI.Region({
									id = "R1",
									group = "lead",
									rank = 2,
									children = { UI.Box({ id = "r1a", width = px(100), height = px(40) }) },
								}),
								UI.Region({
									id = "R2",
									group = "main",
									rank = 1,
									sizing = "fill",
									children = { UI.Box({ id = "r2a", width = px(120), height = px(60) }) },
								}),
							},
						}),
					},
				}),
			},
		})
	)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = incremental,
		measureReuse = memoReuse,
		layoutNodeReuse = true,
		commitScope = true,
	})
	controller.initialRender()
	local w: any = { controller = controller }
	function w.drive(x: number, align: string)
		dx:set(x)
		la:set(align)
		controller.refresh()
	end
	function w.entries(): any
		return capturedResult
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

--[[ THE REFUSAL'S COMPLETENESS, MECHANISED. The two cases above prove the two
	kinds that stamp fields today are refused; this proves the LIST is the list. It
	scans `arrange` itself — from `local function arrange` to `function solver.solve`,
	comments stripped — for every write onto the node's own entry AFTER the literal,
	resolves the `if node.kind == "…"` branch each one sits in, and pins that set of
	kinds EQUAL to the set `literalIsWholeEntry` refuses. A third kind that starts
	stamping a field, or a new field on an existing one, reddens this case; nobody
	has to remember to come back and edit it. ]]
-- every `out[node.id].<field> =` / `entry.<field> =` write after the literal, with
-- the `if node.kind == "…"` branch it sits in (empty = every kind reaches it)
local function stampsAfterLiteral(lines: { string }, at: number): ({ [string]: boolean }, { [string]: boolean })
	local fields: { [string]: boolean } = {}
	local kinds: { [string]: boolean } = {}
	for i = at + 1, #lines do
		local field = lines[i]:match("out%[node%.id%]%.([%a_][%w_]*) =")
			or lines[i]:match("^\t\tentry%.([%a_][%w_]*) =")
		if field ~= nil then
			fields[field] = true
			for j = i - 1, at + 1, -1 do
				if lines[j]:match("^\tif node%.kind ==") ~= nil then
					for kind in lines[j]:gmatch('node%.kind == "([%w_]+)"') do
						kinds[kind] = true
					end
					break
				end
			end
		end
	end
	return fields, kinds
end

describe("O3: the refusal names every kind that stamps an entry field after the literal", function()
	it("the scan finds the literal, and the kinds it finds are the kinds the arm refuses", function()
		expect(`literalFound={LITERAL_AT > 0}`).toBe("literalFound=true")
		local fields, kinds = stampsAfterLiteral(ARRANGE_SOURCE, LITERAL_AT)
		--[[ THE FIELDS, so a NEW field on an existing branch is a visible change here
			rather than a silent one. `moveOnly` and `prev` are the arm's own pair and
			the only two `entryKey` above is allowed to ignore — they are in this set for
			exactly that reason: the day a third one appears, the oracle's modulo and
			this pin move together or this line fails. ]]
		expect(sortedKeys(fields)).toEqual({
			"barInset",
			"composition",
			"contentSize",
			"moveOnly",
			"overflow",
			"padding",
			"prev",
		})
		-- `moveOnly`/`prev` sit outside every `node.kind` branch, so they contribute
		-- no kind; what is left is exactly what `literalIsWholeEntry` refuses
		expect(sortedKeys(kinds)).toEqual({ "composition", "scroll" })
		-- ...and the predicate itself, read out of the source rather than trusted
		local refused: { string } = {}
		local body = fs.readFile("src/layout/solver.luau")
		body = body:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
		local fn = body:match("local function literalIsWholeEntry.-\nend")
		expect(`predicateFound={tostring(fn ~= nil)}`).toBe("predicateFound=true")
		for kind in (fn :: string):gmatch('kind ~= "([%w_]+)"') do
			table.insert(refused, kind)
		end
		table.sort(refused)
		expect(refused).toEqual(sortedKeys(kinds))
	end)

	it("NEGATIVE CONTROL: the scan reports a new kind and a new field", function()
		--[[ The scan is a pure function of a list of lines, so it is fed a source that
			has the defect this pin exists to catch: a third branch stamping a field
			after the literal. A scan that could not see it would pass the case above
			for the wrong reason forever. ]]
		local fake = {
			"\tout[node.id] = {",
			"\t\trect = rect,",
			"\t}",
			'\tif node.kind == "grid" then',
			"\t\tout[node.id].columns = 3",
			"\t\tout[node.id].lanes = 2",
			"\tend",
			'\tif node.kind == "scroll" or node.kind == "hwrap" then',
			"\t\tout[node.id].contentSize = x",
			"\tend",
		}
		local fields, kinds = stampsAfterLiteral(fake, 3)
		expect(sortedKeys(fields)).toEqual({ "columns", "contentSize", "lanes" })
		expect(sortedKeys(kinds)).toEqual({ "grid", "hwrap", "scroll" })
		-- ...and a write BEFORE the literal is not one of these
		expect(sortedKeys((stampsAfterLiteral(fake, 9)))).toEqual({})
	end)
end)

describe("O3: a node whose branch stamps entry fields is never a translate root", function()
	--[[ Both drives, on both kinds, at every device view. The channel is the WHOLE
		entry (`entryKey`), so this closes the class rather than the two fields the
		reviewer happened to name: a third kind that starts stamping a field after the
		literal fails here without anyone editing this case. ]]
	local DRIVES: { any } = {
		-- MOVED: `offsetX`/`offsetY` change, the node lands somewhere new
		{ name = "moved", steps = { { 7, "start" }, { 14, "start" }, { 21, "start" } } },
		-- ZERO DELTA: an inert `lineAlign` dirties the node and moves it nowhere
		{ name = "zero-delta", steps = { { 0, "center" }, { 0, "end" }, { 0, "start" } } },
	}
	for _, drive in DRIVES do
		it(`{drive.name}: a scroll root and a composition root keep every entry field`, function()
			withEntryCapture(function()
				for _, view in device_views.VIEWS do
					local a = branchFieldWorld(true, true, view)
					-- the MEMO-LESS incremental arm: same translate arm, every measure
					-- uncached, so its translate roots carry real offers (see `armOfferDiff`)
					local b = branchFieldWorld(true, false, view)
					local c = branchFieldWorld(false, false, view)
					for step, values in drive.steps do
						a.drive(values[1], values[2])
						local aResult = a.entries()
						local ae = entryKey(aResult.rects)
						b.drive(values[1], values[2])
						local bResult = b.entries()
						c.drive(values[1], values[2])
						local cRects = c.entries().rects
						if ae ~= entryKey(cRects) then
							error(`{drive.name}/{view.id}: step {step} entry diverged from a FULL solve`, 0)
						end
						local offerDiff = armOfferDiff(aResult, bResult, cRects)
						if offerDiff ~= nil then
							error(`{drive.name}/{view.id}: step {step} the arm broke the offer channel: {offerDiff}`, 0)
						end
					end
					a.dispose()
					b.dispose()
					c.dispose()
				end
			end)
		end)
	end

	it("...and the fixture really exercises the arm (or the two cases above are vacuous)", function()
		local w = branchFieldWorld(true, true, device_views.VIEWS[1])
		w.drive(7, "start")
		w.drive(14, "start")
		-- the SUBTREES still translate; what the refusal costs is the two roots
		expect(`translated>0={w.stats().lastTranslated > 0}`).toBe("translated>0=true")
		w.dispose()
	end)
end)

--[[ THE DIAGNOSTICS CHANNEL of the oracle (task review round 1, Critical 1).
	`scene.snapshot()` reads the ADAPTER, and a lost finding never reaches the
	adapter — the arm could silence `controller.diagnostics()` for a whole subtree
	and every rect would still match.

	AND ON THESE THREE FIXTURES IT READS 0 = 0, MEASURED — `plain`, `overflow` and
	`fractional` all file ZERO findings at the swept viewports, because a nameplate
	is a well-formed tree and the overflowing plate sits under an `Anchor`, which
	`placementAudit.routesOverflow` excuses. So this channel is a GUARD against a
	later change to the fixture, not evidence: it is `mountedReportWorld` below that
	carries the claim through the renderer at every view, and the two
	`solver.solve` cases above that carry it at the seam. Said here rather than left
	to be inferred from a green run. ]]
local function diagKey(w: any): string
	local out = {}
	for _, d in w.controller.diagnostics() do
		table.insert(out, `{d.node}|{string.sub(d.issue, 1, 32)}`)
	end
	table.sort(out)
	return `{#out}: ` .. table.concat(out, " ")
end

--[[ ...AND THE SAME CLAIM THROUGH THE WHOLE RENDERER, at every device view: a
	MOUNTED subtree that files findings and translates every step. The oracle's own
	fixtures file nothing (see `diagKey`), and `solver.solve` cases do not exercise
	the closure that builds `dirtyContains`, `controller.diagnostics()`'s own copy,
	or the commit — so this is the arm's diagnostics claim on the shipped path. ]]
local function mountedReportWorld(incremental: boolean, view: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local dx = core:signal(0)
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.Anchor({
					id = "C",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.VStack({
							id = "Wrap",
							anchor = "topLeft",
							offsetX = dx,
							width = px(60),
							height = px(60),
							children = {
								-- 40 a side on a 20px box: the content box collapses on both
								-- axes and the child overflows it — three findings, filed by
								-- `arrange_reports.box` on a node INSIDE the translated subtree
								UI.VStack({
									id = "Bad",
									padding = 40,
									width = px(20),
									height = px(20),
									children = { UI.Box({ id = "Kid", width = px(4), height = px(4) }) },
								}),
							},
						}),
					},
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
	local w: any = { controller = controller }
	function w.drive(x: number)
		dx:set(x)
		controller.refresh()
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

describe("O3: a translated subtree keeps its findings, through the whole renderer", function()
	it("the findings survive every step, at every device view", function()
		for _, view in device_views.VIEWS do
			local a = mountedReportWorld(true, view)
			local c = mountedReportWorld(false, view)
			-- the fixture really files something, or the comparison below is 0 == 0
			-- and proves nothing (measured: 3)
			expect(`{view.id}:{#a.controller.diagnostics()}`).toBe(`{view.id}:3`)
			for step = 1, 4 do
				a.drive(step * 7)
				c.drive(step * 7)
				if diagKey(a) ~= diagKey(c) then
					error(`{view.id}: step {step} diagnostics diverged from a FULL solve`, 0)
				end
				-- ...and the arm really is engaged on this fixture, or the case is
				-- measuring the ordinary arrange
				if a.stats().lastTranslated == 0 then
					error(`{view.id}: step {step} did not translate — this fixture is not exercising the arm`, 0)
				end
			end
			a.dispose()
			c.dispose()
		end
	end)
end)

local function rectKey(r: any): string
	local out = {}
	for id, entry in r.rects do
		local rc = entry.rect
		table.insert(out, `{id}|{rc.x},{rc.y},{rc.w},{rc.h}`)
	end
	table.sort(out)
	return table.concat(out, "\n")
end

--[[ A REFUSED TRANSLATE PUTS THE MAP BACK, not just the counters (task review
	round 1, Minor 4).

	`translateDescendants` writes as it goes and returns false when it meets a node
	the previous solve never recorded. The caller rolls the COUNTERS back and takes
	the ordinary arrange, whose comment claims "the dispatch below rewrites every
	descendant" — true only while the intervening nodes are dirty, which is exactly
	the premise the guard distrusts. Left in the map, a partial run's clone IS the
	previous entry as far as the next `arrange` call can tell: the skip compares
	against `reuse.previous.rects`, which IS `out`, so a clean intermediate node
	finds the RE-BASED rect there, compares equal to where it is going, and SKIPS —
	taking its whole subtree with it.

	MEASURED before the fix, on `solver.solve`, with a new grandchild the dirt set
	does not name (the shape the guard exists for): `/root/A/B` and `/root/A/B/C`
	both carry `moveOnly = true` while `translatedPaths` is EMPTY — the counters say
	nothing was translated and the map says two nodes were — and `/root/A/B/D`, the
	new node, is MISSING FROM THE MAP ENTIRELY, because the skip at `B` meant nobody
	ever walked it. That is a lost rect, not a cosmetic flag. One loop restoring
	`out` makes the rollback as complete as its comment claims. ]]
local function rollbackTree(pad: number, withNew: boolean): any
	local inner: { any } = { { kind = "box", id = "/root/A/B/C", width = px(6), height = px(6), children = {} } }
	if withNew then
		table.insert(inner, { kind = "box", id = "/root/A/B/D", width = px(6), height = px(6), children = {} })
	end
	return {
		kind = "vstack",
		id = "/root",
		padding = pad,
		children = {
			{
				kind = "vstack",
				id = "/root/A",
				width = px(40),
				height = px(40),
				children = {
					{ kind = "vstack", id = "/root/A/B", width = px(30), height = px(30), children = inner },
				},
			},
		},
	}
end

describe("O3: a refused translate leaves no trace", function()
	local VP = { w = 200, h = 200 }

	it("the map has no clone the work record cannot account for, and no missing node", function()
		local first = solver.solve(rollbackTree(0, false), VP, {})
		-- a full solve marks nothing, so every `moveOnly` below belongs to solve 2
		for id, entry in first.rects do
			expect(`{id} moveOnly={tostring(entry.moveOnly)}`).toBe(`{id} moveOnly=nil`)
		end
		local second = solver.solve(
			rollbackTree(9, true),
			VP,
			{ reuse = { previous = first, dirtyContains = { ["/root"] = true }, measureContains = {} } }
		)
		-- the refusal really happened: the arm wrote two entries and gave them back
		expect(`translated={second.work.translated} paths={#second.work.translatedPaths}`).toBe("translated=0 paths=0")
		local accounted: { [string]: boolean } = {}
		for _, path in second.work.translatedPaths do
			accounted[path] = true
		end
		for id in second.work.translatedRoots do
			accounted[id] = true
		end
		local orphans: { string } = {}
		for id, entry in second.rects do
			if entry.moveOnly == true and not accounted[id] then
				table.insert(orphans, id)
			end
		end
		table.sort(orphans)
		expect(orphans).toEqual({})
		-- ...and THE CONSEQUENCE, which is the reason this is not a cosmetic pin: a
		-- clean intermediate node that skips over a clone never walks its subtree, so
		-- the node the previous solve did not have never gets a rect at all
		local full = solver.solve(rollbackTree(9, true), VP, {})
		expect(rectKey(second)).toBe(rectKey(full))
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
	  2. THE ENTRY REALLY DIES — a WITNESS, not a pin, and its title says so. A
	     weak-keyed watch plus the churn idiom `adaptive_defaults.spec.luau`
	     established, with that file's control canary: when the churn does not
	     collect under the full suite the case reports INCONCLUSIVE rather than
	     asserting something it could not compel. The deterministic claim is (1).

	Both run on `solver.solve` DIRECTLY (the idiom `rect_cow.spec.luau` uses),
	because the entry table is the thing under test and the controller does not
	publish it. A hand-built `reuse` carries no `measureContains`, so `selfPlaces`
	refuses every DIRTY root here — which is why the drive dirties the ROOT and the
	translate roots under it are its CLEAN children. ]]
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

	it(
		"...and the superseded entry is unreachable — a WITNESS, inconclusive if the churn does not collect",
		function()
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
		end
	)
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
		it(`{fixture.name}: rects, visibility, hit rects, scroll regions, ENTRIES and findings survive`, function()
			withEntryCapture(function()
				for _, view in device_views.VIEWS do
					local a, b, c = arms(view, fixture)
					local label = `{fixture.name}/{view.id}`
					--[[ ONE STEP, FOUR CHANNELS. `drive` is a function so the three arms take
						the identical action, and the ENTRY maps are captured immediately after
						each arm's own drive — `withEntryCapture` records the last solve, and
						the three worlds solve in turn. `alsoB` is the memo-less arm, compared
						on the plain tick alone exactly as before.

						THE ENTRY CHANNEL (task review round 1, Critical 2) is what closes the
						half-entry class for EVERY kind rather than the two that were caught:
						`scene.snapshot()` reads the adapter, and a field like `contentSize`
						that never reaches a walk is invisible there. ]]
					-- `b` is DRIVEN on every step and COMPARED on the plain tick alone: an
					-- arm that skips a drive falls out of sync with the other two and the
					-- next comparison is about the drive it missed, not about the solver
					local function step(what: string, compareB: boolean, drive: (any) -> ())
						drive(a)
						local aResult = capturedResult
						drive(b)
						local bResult = capturedResult
						drive(c)
						local cRects = capturedResult.rects
						if a.snapshot() ~= c.snapshot() then
							error(`{label}: {what} diverged from a FULL solve`, 0)
						end
						if compareB and a.snapshot() ~= b.snapshot() then
							error(`{label}: {what} diverged from the memo-less solve`, 0)
						end
						if diagKey(a) ~= diagKey(c) then
							error(`{label}: {what} diagnostics diverged from a FULL solve`, 0)
						end
						if entryKey(aResult.rects) ~= entryKey(cRects) then
							error(`{label}: {what} ENTRY diverged from a FULL solve`, 0)
						end
						local offerDiff = armOfferDiff(aResult, bResult, cRects)
						if offerDiff ~= nil then
							error(`{label}: {what} the arm broke the offer channel: {offerDiff}`, 0)
						end
					end

					if a.snapshot() ~= c.snapshot() then
						error(`{label}: diverged from a FULL solve at mount`, 0)
					end
					if diagKey(a) ~= diagKey(c) then
						error(`{label}: diagnostics diverged from a FULL solve at mount`, 0)
					end
					for round = 1, 4 do
						local dx, dy = round * 3, round * 2
						step(`tick {round}`, true, function(w)
							w.tick(dx, dy)
						end)
						step(`caster tick {round}`, false, function(w)
							w.tickWithCasts(dx, dy)
						end)
						step(`hp {round}`, false, function(w)
							w.hp(7, 0.1 * round)
						end)
						--[[ ...AND THE STRUCTURAL ARM, which the three drives above never
							reach and which the arm has its own stake in: on the structural
							path `measureContains` is ALIASED to `structuralPlan.contains`, so
							`selfPlaces` refuses every dirty root there, and `translatable`
							refuses any child `structural_scope.widen` named. Keyed by `round`,
							not a constant: `scene.add` mints the key `add{i}` and a ForEach
							treats a duplicate key as a HARD error. ]]
						step(`add {round}`, false, function(w)
							w.add(round)
						end)
						-- ...and the tick right after it, because a structural solve's own
						-- rects are only half the claim: the NEXT incremental solve runs
						-- against a rect map the structural one only partly rewrote
						step(`tick-after-add {round}`, false, function(w)
							w.tick(dx, dy)
						end)
						-- ...and `remove` takes an INDEX, so removing the row just added
						-- (the last one) is what returns the list to its previous shape
						local added = #a.items
						step(`remove {round}`, false, function(w)
							w.remove(added)
						end)
					end
					a.dispose()
					b.dispose()
					c.dispose()
				end
			end)
		end)
	end
end)
