--!strict
--[[ T14 — A STACK RE-PLACES ONLY THE CHILDREN THAT MOVED.

	T13 made a container stop ASKING its clean children (the measure side) and T13b
	stopped it WALKING them (`stack_measure`). Neither touched ARRANGE: on the arena's
	`battle_hud L updateItem-hp`, a one-leaf write entered `arrangeBody` **1,109 times
	to run FIVE bodies** — the placement loop built a `childRect` for every one of a
	thousand rows, handed each to `arrange`, and 1,104 of them reached the early skip at
	the top of `arrangeBody` and returned. The skip was already free; GETTING THERE was
	the bill, and no counter on `work` could see it (`arranged` is incremented BELOW
	that skip's own `return`).

	── THE CONDITION ────────────────────────────────────────────────────────────────
	NO MAIN EXTENT MOVED. A stack's main axis is a CURSOR: every child's position is
	the sum of every earlier child's margin-inclusive main extent plus the gaps. So if
	the box, the gap, the axis, the container's `align`/`distribute` and every dirty
	child's main contribution are what they were, then `fixedMain`, `gaps`, `availMain`,
	`remaining`, `fillPx`, `shrunk`, `clipMain`, `lead`/`step` and every cursor position
	are the values they were — and nothing on the main axis can have moved, including
	for the dirty children.

	...AND A CROSS EXTENT THAT MOVED COSTS ONE CHILD. The cross axis has no cursor:
	`desired[idx]`'s cross extent is read at exactly ONE place (`crossSize`) and no
	sibling reads it. So a dirty child whose main extent stood still and whose CROSS
	extent moved is re-placed here, with the two lines the placement loop spends on it,
	and every other child keeps its rect. **That is the shape the arena's `updateItem-hp`
	class is made of** — a value-driven bar inside a row makes the ROW's measured WIDTH
	follow it, and the enclosing thousand-row VStack sees a pure cross-extent change on
	one child. Without this half, the plan's own measured survival table says the replay
	fires on ZERO of that class's 1.9 stack entries.

	── THE OWED LIST (the ledger's "Task 14", written before the code) ──────────────
	  #  channel                          verdict
	  1  `place` -> the entry write        SERVED BY NOT BEING NEEDED. `out` IS
	                                       `reuse.previous.rects` (`solver.luau`'s
	                                       `local out = … ctx.reuse.previous.rects`)
	                                       and the gate requires `reuse ~= nil`, so a
	                                       child this arm does not place already owns
	                                       the entry that describes it. `arrangeBody`
	                                       writes one on every path except its own
	                                       clean-and-unmoved skip, which by definition
	                                       leaves the entry it found. Case: "the entry
	                                       of a child the replay did not place"
	  2  `noteContainment`                 REPLAYED FOR EVERY CHILD. Its findings carry
	                                       `filedBy = parentId` and `solve`'s diagnostic
	                                       replay drops any previous finding whose filer
	                                       was WALKED — a replaying container always is.
	                                       Gated on `pNoted`, which is exact: with no
	                                       finding on the recording pass, every rect and
	                                       the box unchanged means there is none now.
	                                       Case: "a containment finding about a CLEAN
	                                       child survives"
	  3  the container's own two           RE-FILED FROM `pIssues`. Neither the overflow
	     diagnostics                       diagnostic nor the `distribute` conflict
	                                       carries a `filedBy`, so the replay keys them
	                                       on the CONTAINER, which is walked, and drops
	                                       the previous copy — while this arm returns
	                                       before `availMain` exists. An overflowing
	                                       stack that stopped reporting from its first
	                                       replay onward, silently and forever, is the
	                                       worst outcome this task could have had.
	                                       Case: "an overflowing stack keeps reporting"
	  4  `ctx.walkedIds[child.id]`         NOT SERVED, AND IDENTICAL TO HEAD: a clean
	                                       child's `arrangeBody` returned above that
	                                       write at HEAD too
	  5  `ctx.arranged`/`rectInserts`      NOT SERVED, AND IT IS THE ACCEPTANCE TEST.
	                                       Both bumps sit BELOW the skip's `return`, so
	                                       a clean child cost zero at HEAD. Pinned
	                                       UNMOVED beside every counter that falls
	  6  the pass-1 / hug-pass `measure`   SERVED from `pMain`/`pCross`, T14's own
	                                       arrays, recorded at the ARRANGE offer
	                                       `(innerW, innerH)` — never from T13's
	                                       `mMain`, which is recorded at `(innerMaxW,
	                                       innerMaxH)` (ruling A-9)
	  7  `ctx.offers[child]`               NOT WRITTEN, AND NOT NEEDED: a skipped child
	                                       builds no fresh entry, so `offerW`/`offerH`
	                                       keep the values the previous solve filed at
	                                       the same `innerW`/`innerH` — both gate terms.
	                                       See "the offer pair" below
	  8  `textStates`/`compact`/`textFacts`  NOT REPUBLISHED, AND IDENTICAL TO HEAD's
	                                       OUTCOME: they are read only where a WALKED
	                                       node's entry is built
	  9  a skipped child's own measure-time  CARRIED FORWARD by the solve-level replay
	     findings                          (it is absent from `walkedIds`), with
	                                       `ctx.measureQuiet` as the gate for the
	                                       parent-filed class — the anchor arm's fourth
	                                       gate, here for the identical reason
	 10  the shrink pass's and the fill      REFUSED PER CHILD by `pFlag`, in BOTH
	     pass's SECOND measurements        directions, which is also what catches a dim
	                                       flipping type at an unchanged content size
	 11  document order                    UNCHANGED: the replay walks `children` in
	                                       order and interleaves `noteContainment` and
	                                       `place` exactly as the placement loop does
	 12  `arrangeEntries`/`placeSkipped`    THE COUNTERS. `lastArrangeEntries` cannot
	                                       fall below the container count, so the
	                                       per-child census is published beside it
	 13  the scan's own O(n) residual       BOOKED AND MEASURED: per CLEAN child it is
	                                       one interned-string compare and one hash
	                                       probe. The four field compares are asked of
	                                       DIRTY children only, because a clean child's
	                                       props cannot have moved — a prop write is
	                                       what makes a node dirty

	── THE OFFER PAIR, WHICH T13 AND T13b BOTH OWED AND NEITHER COULD WITNESS ──────
	Both tasks recorded `child.oMemo` (a served child's back-pointer to its container's
	memo, whose key IS the offer) as a BEHAVIOURAL NULL: deleting it left both suites
	green, because `stack.arrange`'s pass 1 re-measured every stack child and `measure`
	wrote `ctx.offers` itself. Both reports named T14 as the task that makes it
	load-bearing. **It does not, and this file says so with two cases rather than
	inheriting the claim.** The replay does not place a clean child at all, so no fresh
	entry literal is built for it and its `offerW`/`offerH` are the ones the previous
	solve filed — at the same `innerW`/`innerH`, both gate terms. What the two cases
	pin instead is the failure the fallback can actually have: an ABSENT pair disarms
	the anchor arms (a counter, never a rect) and a WRONG one ARMS a rect-serving skip
	on a false match (a rect). See the two cases under "the offer pair".

	── WHAT IS BOOKED, NOT BUILT: THE PREFIX REBASE ─────────────────────────────────
	When a dirty child's MAIN extent moves by delta, every later sibling moves by
	exactly delta and the earlier ones do not — an O(dirty) placement with a suffix
	shift. It is refused here, and the five terms that make it a second lever rather
	than a relaxation of this one are: a `fill` sibling must be RESIZED (its share is a
	function of `remaining`, which moved) and not shifted; `distribute` re-derives
	`lead`/`step` from `remaining`; `clipMain` re-clips every child against the box
	edge; the shrink pass re-runs against a new deficit; and an `aspect` child's
	other axis follows. Measured cost of the refusal, on the arena at this task's
	parent SHA, is in `docs/studio-runs/2026-09-03-facet-parity.md` §C12. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local solver = require("../src/layout/solver")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")
local device_views = require("./lib/device_views")
local scene = require("./lib/deep_stack_scene")
local text_metrics = require("../src/layout/text_metrics")

local ROWS = 1000

--[[ ONE DRIVE, AND WHAT IT COST, in the shape `container_memo` established. The four
	counters that must NOT move ride the same string as the two that must, because the
	claim is about how they move TOGETHER: a lever that removed a placement would move
	`arranged`, and a lever that removed a rect would move `inserts`. ]]
local capture = { result = nil :: any, opts = nil :: any, root = nil :: any, viewport = nil :: any, solves = 0 }
local function withWorkCapture(fn: () -> ())
	local real = solver.solve
	solver.solve = function(...)
		local r = real(...)
		capture.solves += 1
		capture.result = r
		capture.root = (select(1, ...))
		capture.viewport = (select(2, ...))
		capture.opts = (select(3, ...))
		return r
	end
	local ok, err = pcall(fn)
	solver.solve = real
	if not ok then
		capture.result = nil
		error(err, 0)
	end
end

local function drove(fn: () -> ()): string
	local before = capture.solves
	capture.result = nil
	fn()
	local n = capture.solves - before
	if n == 0 or capture.result == nil then
		return `solves={n}`
	end
	local w = capture.result.work
	return `solves={n} entries={w.arrangeEntries} skipped={w.placeSkipped} `
		.. `arranged={w.arranged} inserts={w.rectInserts} calls={w.measureCalls}`
end

local function px(n: number): any
	return { type = "fixed", px = n }
end

--[[ THE FIXTURE: one VStack, N boxes, and a signal on every input the replay's gate
	names. It is hand-built rather than an arm of `deep_stack_scene` because that scene
	exists to drive the MEASURE side — its rows are HStacks of two Texts, so a drive on
	one reaches three containers and the counters answer about all of them. Here every
	row is a LEAF, so one number is one claim about one stack.

	MAIN IS HEIGHT AND CROSS IS WIDTH, which is the whole reason the two drives below
	are different cases: `rowH` moves the cursor for every later row, `rowW` moves
	nothing but the row's own box. ]]
local function world(o: any): any
	o = o or {}
	local n = o.rows or 8
	local gate = o.gate or 3
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 400, h = 600 })
	local rowH: { any } = {}
	local rowW: { any } = {}
	local gap = core:signal(o.gap or 2)
	local align = core:signal(o.align)
	local distribute = core:signal(o.distribute)
	local axis = core:signal("y")
	local gateAlign = core:signal(o.gateAlign)
	local gateWeight = core:signal(o.gateWeight)
	local gatePriority = core:signal(o.gatePriority)
	-- the gate row's own margin, as a signal: a SPLIT change (left 11/right 7 becomes
	-- left 7/right 11) moves the child and moves no total, which is the one shape a
	-- margin-INCLUSIVE pair cannot see
	local gateMargin = core:signal(11)
	-- ...and a HEADER above the list, whose height moves the LIST's own origin with its
	-- size unchanged — the only drive here that moves `innerY` without moving `innerH`
	local headerH = core:signal(10)
	local rowText: { any } = {}
	local kids: { any } = {}
	for i = 1, n do
		rowText[i] = core:signal(`row {i}`)
		rowH[i] = core:signal(if o.tall and i == gate then 40 else 20)
		rowW[i] = core:signal(if o.wide and i == gate then 500 else 60)
		local isGate = i == gate
		--[[ ...OR A `text` ROW, which is the only shape a CALIBRATION case can be built
			on: a calibration change moves `ctx.measureStamp` and dirties NOTHING, so the
			children whose measurement it silently corrects are exactly the clean ones a
			replay would keep. ]]
		if o.nested and not isGate then
			-- a row that is itself a CONTAINER, so the arm is exercised on a stack whose
			-- children have subtrees rather than on eight leaves
			kids[i] = UI.VStack({
				id = `R{i}`,
				padding = 0,
				gap = 1,
				width = core:memo(function(use: any)
					return px(use(rowW[i]) :: number)
				end),
				height = { type = "content" },
				children = {
					UI.Box({ id = "a", width = px(10), height = px(4) }),
					UI.Box({ id = "b", width = px(14), height = px(4) }),
				},
			})
			continue
		end
		if o.aspect and isGate then
			-- an `aspect` child derives one axis from the other AT PLACEMENT, so its
			-- recorded pair is not the measurement that decided its rect
			kids[i] = UI.Box({
				id = `R{i}`,
				width = core:memo(function(use: any)
					return px(use(rowW[i]) :: number)
				end),
				height = { type = "aspect", ratio = 3 },
			})
			continue
		end
		if o.text then
			kids[i] = UI.Text({
				id = `R{i}`,
				textSize = 14,
				text = core:memo(function(use: any)
					return use(rowText[i]) :: string
				end),
			})
			continue
		end
		kids[i] = UI.Box({
			id = `R{i}`,
			width = core:memo(function(use: any)
				return px(use(rowW[i]) :: number)
			end),
			-- ...and the GATE row can be `fill` on the main axis instead, which is the
			-- shape the "measured-to-measured" case is about: its placed extent is its
			-- SHARE of what is left, and comparing a fresh measurement against THAT is
			-- the error the first prototype of this arm made
			height = if o.fill and isGate
				then { type = "fill", weight = 1 }
				else core:memo(function(use: any)
					return px(use(rowH[i]) :: number)
				end),
			--[[ ...and the CONTAINMENT shape, which is a MARGIN and not a width: a stack
				CLAMPS a child's cross extent to its box (`crossSize = min(desired, crossAvail)`),
				so a 500px row in a 300px stack is placed at 300 and contains fine. What
				lands outside is a margin wider than the box — `placement_audit.containment`'s
				own sentence says so — and that is the only shape this finding has. ]]
			--[[ ...and the NEGATIVE-margin shape (fix round 1, I-1), which is the only one
				that makes a child's OVERHANG a function of its own measured cross extent.
				A stack CLAMPS `crossSize` to `crossAvail`, so a plain wide row is placed
				at the box width and contains fine; `right = -200` widens `crossAvail` to
				500 against a 300px box, so the row is placed at its full measured width
				and hangs `w - 300` past the right edge. Driving `rowW[gate]` therefore
				moves the FINDING, which is what a chain of replays has to be asked about.
				A negative side is a schema-accepted `sides` value. TWO rows carry it (the
				gate row and `gate + 3`), because owed row 11's ORDER claim needs two
				findings to have an order at all. ]]
			margin = if o.negMargin and (isGate or i == gate + 3)
				then { right = -200 }
				elseif o.contain and isGate then { left = 340 }
				elseif o.margin and isGate then core:memo(function(use: any)
					local l = use(gateMargin) :: number
					return { top = 5, right = 18 - l, bottom = 3, left = l }
				end)
				else nil,
			lineAlign = if isGate
				then core:memo(function(use: any)
					return use(gateAlign) :: any
				end)
				else nil,
			shrinkWeight = if isGate
				then core:memo(function(use: any)
					return use(gateWeight) :: any
				end)
				else nil,
			layoutPriority = if isGate
				then core:memo(function(use: any)
					return use(gatePriority) :: any
				end)
				else nil,
		})
	end
	local listChildren: { any } = kids
	local list = if o.adaptive
		then UI.AdaptiveStack({
			id = "List",
			axis = core:memo(function(use: any)
				return use(axis) :: any
			end),
			padding = 0,
			gap = core:memo(function(use: any)
				return use(gap) :: number
			end),
			align = core:memo(function(use: any)
				return use(align) :: any
			end),
			width = px(o.listW or 300),
			height = px(o.listH or 560),
			children = listChildren,
		})
		else UI.VStack({
			id = "List",
			padding = 0,
			gap = core:memo(function(use: any)
				return use(gap) :: number
			end),
			align = core:memo(function(use: any)
				return use(align) :: any
			end),
			distribute = core:memo(function(use: any)
				return use(distribute) :: any
			end),
			width = px(o.listW or 300),
			height = px(o.listH or 560),
			children = listChildren,
		})
	--[[ ...AND THE HEADER ARM. `o.header` wraps the list in an outer VStack under a box
		whose height is a signal, so a drive can move the list's own ORIGIN while its size
		and every child inside it stand still. Nothing else in this fixture separates
		`innerY` from `innerH`. ]]
	local bp = if o.header
		then UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Root",
					padding = 0,
					gap = 0,
					width = px(o.listW or 300),
					height = px((o.listH or 560) + 60),
					children = {
						UI.Box({
							id = "Header",
							width = px(o.listW or 300),
							height = core:memo(function(use: any)
								return px(use(headerH) :: number)
							end),
						}),
						list,
					},
				}),
			},
		})
		else UI.Screen({ id = "S", children = { list } })
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new({})
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = o.incremental ~= false,
		measureReuse = o.measureReuse ~= false,
		layoutNodeReuse = true,
		commitScope = true,
		translateHosts = true,
	})
	controller.initialRender()
	local w: any = { core = core, env = env, adapter = adapter, controller = controller, rows = n, gate = gate }
	--[[ ...AND THE TWO-SIGNAL DRIVE, which is the only way to move a container's ORIGIN
		while something inside it is dirty. Set both, refresh ONCE: the header's height
		moves the list's `innerY`, and the row write is what puts a dirty child inside it
		so the arm is reached at all. ]]
	function w.headerAndRow(h: number, i: number, v: number)
		headerH:set(h)
		rowW[i]:set(v)
		controller.refresh()
	end
	function w.gateMargin(v: number)
		gateMargin:set(v)
		controller.refresh()
	end
	function w.text(i: number, v: string)
		rowText[i]:set(v)
		controller.refresh()
	end
	function w.height(i: number, v: number)
		rowH[i]:set(v)
		controller.refresh()
	end
	function w.width(i: number, v: number)
		rowW[i]:set(v)
		controller.refresh()
	end
	function w.gap(v: number)
		gap:set(v)
		controller.refresh()
	end
	function w.align(v: any)
		align:set(v)
		controller.refresh()
	end
	function w.distribute(v: any)
		distribute:set(v)
		controller.refresh()
	end
	function w.axis(v: string)
		axis:set(v)
		controller.refresh()
	end
	function w.gateAlign(v: any)
		gateAlign:set(v)
		controller.refresh()
	end
	function w.gateWeight(v: any)
		gateWeight:set(v)
		controller.refresh()
	end
	function w.gatePriority(v: any)
		gatePriority:set(v)
		controller.refresh()
	end
	function w.viewport(vw: number, vh: number)
		env:set("viewportRect", { x = 0, y = 0, w = vw, h = vh })
		controller.refresh()
	end
	function w.stats(): any
		return controller.stats()
	end
	--[[ EVERY LIVE NODE, and every per-path fact a reader can see — the same columns
		`deep_stack_scene.snapshot` uses and for the same reason: an oracle over this
		fixture asks exactly one question, did an optimisation that skips work change
		anything a reader can see. `pos == sro` is carried as an identity because the
		engine POSITION and the public screen rect are two different readers of one
		answer. ]]
	function w.snapshot(): string
		local out: { string } = {}
		for path, node in adapter.liveNodes() do
			local r, hit = node.storedRect, node.hitRect
			local pp = node.presentedPosition
			local sro = controller.screenRectOf(path)
			local function f(x: any): string
				return if x == nil then "-" else `{x.x},{x.y},{x.w},{x.h}`
			end
			table.insert(
				out,
				`{path}|{f(r)}|vis={tostring(node.visible)}|hit={f(hit)}`
					.. `|pos={if pp then `{pp.x},{pp.y}` else "-"}`
					.. `|ro={f(controller.rectOf(path))}|sro={f(sro)}`
			)
		end
		table.sort(out)
		table.insert(out, `diag={w.diagKey()}`)
		return table.concat(out, "\n")
	end
	local base = if o.header then "/S/Root/List" else "/S/List"
	function w.rects(): string
		local out: { string } = {}
		for i = 1, n do
			local r = controller.rectOf(`{base}/R{i}`)
			table.insert(out, if r == nil then `R{i}=-` else `R{i}={r.x},{r.y},{r.w},{r.h}`)
		end
		return table.concat(out, " ")
	end
	--[[ ...and the SAME findings UNSORTED, which is the only reader that can see the
		order the replay filed them in (fix round 1, minor 3). `diagKey` sorts, so the
		oracle compares the finding SET; owed row 11's claim is about the ORDER the
		placement loop and the replay file in, and it needs its own instrument. ]]
	function w.diagOrder(): string
		local out: { string } = {}
		for _, f in controller.diagnostics() do
			table.insert(out, f.node)
		end
		return table.concat(out, ",")
	end
	function w.diagKey(): string
		local keys: { string } = {}
		for _, f in controller.diagnostics() do
			table.insert(keys, `{f.node}::{string.sub(f.issue, 1, 90)}`)
		end
		table.sort(keys)
		return table.concat(keys, ";")
	end
	function w.dispose()
		controller.dispose()
		root.dispose()
	end
	return w
end

--[[ TWO ARMS OF THE SAME TREE, DRIVEN IDENTICALLY: the replaying one and a
	FULL-SOLVE control (`incrementalLayout = false`, where `ctx.reuse` is nil and the
	arm is structurally unreachable). Every case that claims the replay FIRED compares
	rects against this arm, because "it skipped the work" and "it kept the answer" are
	two different claims and only the second one matters. ]]
local function pair(o: any): (any, any)
	local live = table.clone(o or {})
	local ctrl = table.clone(o or {})
	ctrl.incremental = false
	ctrl.measureReuse = false
	return world(live), world(ctrl)
end

local function agree(a: any, c: any, step: string)
	if a.rects() ~= c.rects() then
		error(`{step}: rects diverged from a FULL solve\n  live {a.rects()}\n  ctrl {c.rects()}`, 0)
	end
	if a.diagKey() ~= c.diagKey() then
		error(`{step}: diagnostics diverged from a FULL solve\n  live {a.diagKey()}\n  ctrl {c.diagKey()}`, 0)
	end
end

-- ...and the WHOLE snapshot, which is what the oracle below compares
local function agreeAll(a: any, c: any, step: string)
	if a.snapshot() ~= c.snapshot() then
		error(`{step}: the snapshot diverged from a FULL solve`, 0)
	end
end

describe("T14: the counters — what falls, and the five that must not move", function()
	it("a text write on ONE leaf of a 1,000-row list: the placements fall", function()
		--[[ THE HEADLINE, ON THE SAME FIXTURE T13 AND T13b ARE PINNED ON, so the three
			levers' numbers are comparable. `entries` is `arrangeBody` ENTRIES and
			`skipped` is the per-child placement-loop iterations the replay did not
			spend — published as a PAIR because neither can carry the claim alone: an
			entry count cannot fall below the container count, and a skipped-placement
			count cannot say how many containers paid for it.

			`arranged` and `inserts` MUST NOT MOVE, and that is the acceptance test
			rather than a bonus: both bumps sit BELOW `arrangeBody`'s own early skip, so
			a clean child cost zero at HEAD too. If either fell, the arm would have
			removed a rect the commit still needs. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe("solves=1 entries=5 skipped=999 arranged=5 inserts=5 calls=8")
			s.dispose()
		end)
	end)

	it("...and THE BEFORE COLUMN is the MOUNT solve, measured on this build", function()
		--[[ THE ARM IS STRUCTURALLY UNREACHABLE ON A SOLVE WITH NO `reuse` TABLE, which
			is what the first solve of a mounted surface is — so the mount's own numbers
			are the pre-T14 branch's exactly: every container entered, nothing skipped,
			and `entries` equal to the layout-node count. A spec that only pinned the
			drive could not tell a working replay from a fixture that stopped having
			children.

			IT ALSO SAYS WHERE THE PAYLOAD COMES FROM. The mount RECORDS while it places,
			so the very next incremental solve can replay — which is why the "warm-up"
			tick below is already a replay and not a second full walk.

			── `calls` RE-RECORDED 2026-09-06 (Plan D, D5), 5,003 -> 4,003, and it is the
			only number here that moved. The arrange pass used to re-measure every child
			the measure pass had already answered at the same offer, because a full solve
			recorded no node slots to answer from; it records them now, so the second ask
			is SERVED and a served container never descends into the 1,000 children it
			would have re-measured. `entries`, `skipped`, `arranged` and `inserts` — the
			replay's own four — are untouched. ]]
		local mount = ""
		withWorkCapture(function()
			local s
			mount = drove(function()
				s = scene.new({ rows = ROWS })
			end)
			expect(drove(function()
				(s :: any).text(500, "warm")
			end)).toBe("solves=1 entries=5 skipped=999 arranged=5 inserts=5 calls=1007")
			expect(drove(function()
				(s :: any).text(500, "x")
			end)).toBe("solves=1 entries=5 skipped=999 arranged=5 inserts=5 calls=8");
			(s :: any).dispose()
		end)
		expect(mount).toBe("solves=1 entries=3002 skipped=0 arranged=3002 inserts=3002 calls=4003")
	end)

	it("the four commit-side counters and the solve census do not move", function()
		--[[ THE OTHER HALF OF THE ACCEPTANCE TEST, read off the CONTROLLER rather than
			off `work`: `lastArranged` + `lastTranslated` + `lastSolveSkipped` is still
			the whole layout-node count, so a child the replay did not place is counted
			as SKIPPED — exactly what it was at HEAD, where `arrangeBody` returned above
			every one of these counters. `rectWrites`/`propWrites` are the COMMIT's, and
			a lever that changed what the commit writes would be a different task. ]]
		local s = scene.new({ rows = ROWS })
		s.text(500, "warm")
		local before = s.stats()
		local baseRects, baseProps = before.rectWrites, before.propWrites
		s.text(500, "x")
		local st = s.stats()
		expect(
			`arranged={st.lastArranged} translated={st.lastTranslated} skipped={st.lastSolveSkipped} `
				.. `nodes={st.lastLayoutNodes} anchorSkipped={st.lastAnchorSkipped}`
		).toBe("arranged=5 translated=0 skipped=2997 nodes=3002 anchorSkipped=0")
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(st.lastLayoutNodes)
		expect(`rectWrites moved={st.rectWrites - baseRects} propWrites moved={st.propWrites - baseProps}`).toBe(
			"rectWrites moved=2 propWrites moved=1"
		)
		s.dispose()
	end)
end)

describe("T14: what the replay fires on", function()
	it("a CROSS-only change re-places that child and nothing else", function()
		--[[ THE CASE THE ARENA'S `updateItem-hp` CLASS IS. `rowW` is the cross extent of
			a VStack child: it moves that row's own box and no cursor. The row is
			re-placed with a fresh rect; its seven siblings are not placed at all. ]]
		local a, c = pair({ rows = 8 })
		a.height(4, 20)
		c.height(4, 20)
		agree(a, c, "warm")
		withWorkCapture(function()
			a.width(4, 140)
		end)
		c.width(4, 140)
		agree(a, c, "cross-only")
		local w = capture.result.work
		expect(`entries={w.arrangeEntries} skipped={w.placeSkipped} arranged={w.arranged}`).toBe(
			"entries=3 skipped=7 arranged=3"
		)
		a.dispose()
		c.dispose()
	end)

	it("a MARGINED child replays, because the recorded pair is margin-INCLUSIVE", function()
		--[[ REVIEW ROUND 2's §3.2 CASE. An earlier revision recorded the pair in the
			PLACEMENT loop from `mainSize`/`crossSize` — margin-EXCLUSIVE — and compared
			it against a freshly measured margin-inclusive number, so any child with a
			margin refused unconditionally and the arm was silently dead on real UI. The
			pair is now taken from `desired` plus `margins`, where the measurement is. ]]
		local a, c = pair({ rows = 8, margin = true })
		a.width(3, 70)
		c.width(3, 70)
		agree(a, c, "warm")
		withWorkCapture(function()
			a.width(3, 80)
		end)
		c.width(3, 80)
		agree(a, c, "margined replay")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=7")
		a.dispose()
		c.dispose()
	end)

	it("a FILL child is compared measured-to-measured, not against its placed rect", function()
		--[[ THE FIXTURE THAT BROKE THE CEILING PROTOTYPE. The gate row is `fill` on the
			main axis, so its PLACED extent is its share of what is left — a number no
			measurement ever produced. A dirty FIXED sibling whose size does not change
			must still let the replay fire, and it does: the fill child is CLEAN, so its
			measurement cannot have moved and `pFlag` never has to refuse it. ]]
		local a, c = pair({ rows = 8, fill = true })
		a.width(6, 70)
		c.width(6, 70)
		agree(a, c, "warm")
		withWorkCapture(function()
			a.width(6, 70)
			a.height(6, 20)
		end)
		c.width(6, 70)
		c.height(6, 20)
		agree(a, c, "fill sibling")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=7")
		a.dispose()
		c.dispose()
	end)

	it("a `distribute` stack whose contents did not move REPLAYS (ruling A-13)", function()
		--[[ `distributionOf` reads `remaining`, which is a function of `fixedMain` and
			the box — both gate terms — so a `spaceBetween` stack is not refused for
			being one. It is the mirror of the FLIP case below, and the pair is what
			makes each of them a witness. ]]
		local a, c = pair({ rows = 6, distribute = "spaceBetween" })
		a.width(2, 70)
		c.width(2, 70)
		agree(a, c, "warm")
		withWorkCapture(function()
			a.width(2, 90)
		end)
		c.width(2, 90)
		agree(a, c, "distribute replay")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=5")
		a.dispose()
		c.dispose()
	end)
end)

describe("T14: what the replay REFUSES, one case per gate term", function()
	local function refuses(o: any, drive: (any) -> (), label: string, entries: number)
		local a, c = pair(o)
		a.width(1, 61)
		c.width(1, 61)
		agree(a, c, `{label} warm`)
		withWorkCapture(function()
			drive(a)
		end)
		drive(c)
		agree(a, c, label)
		local w = capture.result.work
		expect(`{label}: entries={w.arrangeEntries} skipped={w.placeSkipped}`).toBe(
			`{label}: entries={entries} skipped=0`
		)
		a.dispose()
		c.dispose()
	end

	it("a dirty child whose MAIN extent CHANGED refuses — the whole of the amended scope", function()
		--[[ THE HONEST STATEMENT OF WHAT THIS LEVER IS NOT. The cursor is the sum of
			every earlier main extent, so one row growing 12px moves every later row.
			Shifting the suffix by that delta is the BOOKED prefix rebase, with the five
			terms named in this file's header; refusing is what ships. ]]
		refuses({ rows = 8 }, function(a)
			a.height(3, 32)
		end, "main extent", 10)
	end)

	it("a child whose resolved ALIGN changed refuses", function()
		-- `child.lineAlign or child.align or node.align` is read at placement and no
		-- measurement can see it: the row measures identically and lands somewhere else
		refuses({ rows = 8, gateAlign = "start" }, function(a)
			a.gateAlign("end")
		end, "child align", 10)
	end)

	it("a GAP change on the container refuses", function()
		-- `gap` is a PARAMETER of `stack.arrange`, not a node field: the replay compares
		-- the parameter it was handed
		refuses({ rows = 8 }, function(a)
			a.gap(9)
		end, "gap", 10)
	end)

	it("a CONTAINER align change refuses", function()
		refuses({ rows = 8, align = "start" }, function(a)
			a.align("center")
		end, "container align", 10)
	end)

	it("a `distribute` FLIP on the container refuses (ruling A-15)", function()
		--[[ THE MIRROR OF THE REPLAY CASE ABOVE, and the reason `pDistribute` is a gate
			term rather than an argument. Flipping `"start"` to `"spaceBetween"` dirties
			the CONTAINER and no child, so the scan finds nothing dirty and every child
			would keep its old cursor position while `lead`/`step` changed underneath. ]]
		refuses({ rows = 6, distribute = "start" }, function(a)
			a.distribute("spaceBetween")
		end, "distribute flip", 8)
	end)

	it("an AXIS flip refuses — `pMain` stops meaning the axis it was recorded on", function()
		--[[ THE DEFECT T13b FOUND IN T13'S OWN KEY, asked of this payload. `UI.AdaptiveStack`
			is ONE class whose reactive `axis` maps to two solver KINDS with the documented
			guarantee that the flip is a re-solve and never a remount — so every child keeps
			its identity and stays CLEAN, the box is the same box, and `pMain`/`pCross` are
			suddenly the wrong way round. `pKind` is the one term that catches it. ]]
		refuses({ rows = 6, adaptive = true }, function(a)
			a.axis("x")
		end, "axis flip", 8)
	end)

	it("a `shrinkWeight` write with no measurement change refuses (ruling A-15)", function()
		--[[ ON AN OVERFLOWING STACK, so the shrink pass is LIVE rather than merely
			declared: 8 rows of 40px in a 120px box. A weight ARRIVING on a dirty child
			changes every rect with no measurement change at all, and the term that
			catches it is not an array — it is `pShort` (this stack came out SHORT last
			pass) plus the child's CURRENT weight. A clean child's weight cannot have
			moved, and on a stack that was not short the pass cannot run. ]]
		refuses({ rows = 8, listH = 120, tall = true }, function(a)
			a.gateWeight(1)
		end, "shrinkWeight", 10)
	end)

	it("a `layoutPriority` write with no measurement change refuses (ruling A-15)", function()
		-- the shrink pass's ORDER, read inside `shrinkLib.stack`; same shape, same term
		refuses({ rows = 8, listH = 120, tall = true, gateWeight = 1 }, function(a)
			a.gatePriority(3)
		end, "layoutPriority", 10)
	end)

	it("a VIEWPORT change replays nothing — it is unreachable, not declined", function()
		--[[ A geometry write is a FULL solve with no `reuse` table, and the gate asks for
			it before anything else. This is the arm where the whole mechanism is
			structurally absent, and a fixture with no such drive cannot tell "refused"
			from "never asked". ]]
		local a, c = pair({ rows = 8 })
		a.width(1, 61)
		c.width(1, 61)
		withWorkCapture(function()
			a.viewport(500, 620)
		end)
		c.viewport(500, 620)
		agree(a, c, "viewport")
		expect(`entries={capture.result.work.arrangeEntries} skipped={capture.result.work.placeSkipped}`).toBe(
			"entries=10 skipped=0"
		)
		a.dispose()
		c.dispose()
	end)

	it("a `ForEach` sibling splice refuses even when NO child is dirty", function()
		--[[ THE BLOCKING FIXTURE (review round 2, §3.1). `mount` replaces a REGION's
			children, never the enclosing panel's, so the carrier gate's `prior.kids ==
			node.children` HOLDS across an insert into a spliced sibling while every
			later index shifts in the LAYOUT node's flat list. Measured on the arena,
			`battle_hud L removeItem-damage` reaches this arm with `dirty ~= nil`, ZERO
			dirty children and an unmoved box over 1,123 children — so without the id
			scan the arm returns having placed NOTHING while the splice moved every
			surviving row. Every rect is pinned against a full solve. ]]
		local a = scene.new({ rows = 12, foreach = true })
		local c = scene.new({ rows = 12, foreach = true, incremental = false, measureReuse = false })
		a.insertItem("warm")
		c.insertItem("warm")
		expect(a.snapshot()).toBe(c.snapshot())
		withWorkCapture(function()
			a.insertItem("spliced")
		end)
		c.insertItem("spliced")
		if a.snapshot() ~= c.snapshot() then
			error("the splice diverged from a FULL solve", 0)
		end
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=0")
		a.dispose()
		c.dispose()
	end)
end)

describe("T14: the two diagnostics a replay would have silenced", function()
	it("an OVERFLOWING stack keeps reporting its overflow, every replay, forever", function()
		--[[ REVIEW ROUND 3, MUST-FIX 3. `stack.luau`'s overflow finding is
			`{ node = node.id, issue = … }` with NO `filedBy`, so `solve`'s diagnostic
			replay keys it on the CONTAINER — which is walked on every solve that reaches
			this branch — and drops the previous copy, while the arm returns long before
			`availMain` is computed. The first version of the plan called this
			"STATED-UNREACHABLE"; it is the opposite, and an overflowing stack that
			stopped reporting from its first replay onward, silently and forever, is the
			worst outcome this task could have had.

			THE DRIVE IS A CROSS-ONLY CHANGE, so the replay FIRES on a stack whose 8
			forty-pixel rows do not fit its 120px box. Ten consecutive replays, and the
			finding is asked for after each. ]]
		local a, c = pair({ rows = 8, listH = 120, tall = true })
		a.width(2, 61)
		c.width(2, 61)
		agree(a, c, "overflow warm")
		expect(string.find(a.diagKey(), "content overflows", 1, true) ~= nil).toBe(true)
		for step = 1, 10 do
			withWorkCapture(function()
				a.width(2, 70 + step)
			end)
			c.width(2, 70 + step)
			agree(a, c, `overflow replay {step}`)
			expect(`step {step}: skipped={capture.result.work.placeSkipped}`).toBe(`step {step}: skipped=7`)
		end
		a.dispose()
		c.dispose()
	end)

	it("a CONTAINMENT finding about a CLEAN child survives a replay", function()
		--[[ REVIEW ROUND 3, MUST-FIX 2, and it is the finding the plan's owed row 2 had
			backwards. `placement_audit.containment` stamps `filedBy = parentId`, and
			`solve` carries a previous finding forward only when its FILER was not walked
			— the replaying container always is. So a finding about a child the replay
			did not place is dropped and cannot be restored. The arm re-files
			`noteContainment` for EVERY child, gated on `pNoted`.

			ROW 3 IS 500px WIDE IN A 300px BOX and is CLEAN on the drive; row 5 is the
			dirty one. Ten replays, and the finding must be there after each. ]]
		local a, c = pair({ rows = 8, contain = true })
		a.width(5, 61)
		c.width(5, 61)
		agree(a, c, "containment warm")
		expect(string.find(a.diagKey(), "/S/List/R3", 1, true) ~= nil).toBe(true)
		expect(string.find(a.diagKey(), "past the right edge", 1, true) ~= nil).toBe(true)
		for step = 1, 10 do
			withWorkCapture(function()
				a.width(5, 70 + step)
			end)
			c.width(5, 70 + step)
			agree(a, c, `containment replay {step}`)
			expect(`step {step}: skipped={capture.result.work.placeSkipped}`).toBe(`step {step}: skipped=7`)
		end
		a.dispose()
		c.dispose()
	end)

	it("...and a `distribute` CONFLICT finding survives one too", function()
		-- the container's OTHER own-finding: `distribute` with a `fill` child that
		-- already took the whole leftover. Same `filedBy`-less shape, same re-file
		local a, c = pair({ rows = 6, fill = true, distribute = "spaceBetween" })
		a.width(2, 61)
		c.width(2, 61)
		agree(a, c, "conflict warm")
		expect(string.find(a.diagKey(), "nothing to distribute", 1, true) ~= nil).toBe(true)
		for step = 1, 5 do
			withWorkCapture(function()
				a.width(2, 70 + step)
			end)
			c.width(2, 70 + step)
			agree(a, c, `conflict replay {step}`)
			expect(`step {step}: skipped={capture.result.work.placeSkipped}`).toBe(`step {step}: skipped=5`)
		end
		a.dispose()
		c.dispose()
	end)

	it("the entry of a child the replay did NOT place is the one the commit reads (owed row 1)", function()
		--[[ `out` IS `reuse.previous.rects`, so the rect map this solve hands back
			already holds every skipped child's entry — the same table the last commit
			saw. Read back through the PUBLIC readers rather than asserted about the map,
			because that is who the claim is for. ]]
		local a, c = pair({ rows = 8 })
		a.width(1, 61)
		c.width(1, 61)
		withWorkCapture(function()
			a.width(4, 90)
		end)
		c.width(4, 90)
		agree(a, c, "entries survive")
		local rects = capture.result.rects
		local present = 0
		for i = 1, 8 do
			local e = rects[`/S/List/R{i}`]
			if e ~= nil and e.rect ~= nil then
				present += 1
			end
		end
		expect(`entries present={present} of 8, skipped={capture.result.work.placeSkipped}`).toBe(
			"entries present=8 of 8, skipped=7"
		)
		a.dispose()
		c.dispose()
	end)
end)

describe("T14: the solve-wide inputs no child can see", function()
	it("a CALIBRATION change refuses, because it corrects the CLEAN children", function()
		--[[ REVIEW ROUND 3, MUST-FIX 1, and the shape is exact rather than illustrative.
			`text_metrics.calibrate` moves `calibEpoch`, which is still a `measureStamp`
			term after T18-A split the generation in two — and it dirties NOTHING. So
			every text child's measured width is silently corrected while `dirtyContains`
			names only whatever else the tick wrote. The container's box is FIXED here, so
			`pInnerW`/`pInnerH` cannot refuse for it; the dirty child's own extents are
			CHOSEN not to move (`row 1` -> `row 8`, the same glyph count under any
			calibration on this measurer), so the extent comparison cannot refuse either.
			`pStamp` is the only term left, and without it the seven clean rows keep
			widths measured under the old calibration — which is the text-settle "pop"
			class, one level up.

			THE WORD HALF OF THE GENERATION IS NOT HERE AND MUST NOT BE. T18-A took it
			OUT of the stamp and routes it as DIRT over the (font,size)'s actual users, so
			a learned word arrives at this arm as a dirty child, gets re-measured, and is
			compared like any other change. The two halves are two different mechanisms
			and this case is about the one that still rides the stamp. ]]
		local a, c = pair({ rows = 8, text = true })
		a.text(1, "row 2")
		c.text(1, "row 2")
		agree(a, c, "calibration warm")
		local ok, err = pcall(function()
			text_metrics.calibrate("BuilderSans", 0.33)
			withWorkCapture(function()
				a.text(1, "row 8")
			end)
			c.text(1, "row 8")
			agree(a, c, "calibration")
			expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=0")
		end)
		-- the calibration is GLOBAL and must be put back whatever happened above, or
		-- every later spec in the suite measures under it (`measure_reuse`'s own rule)
		text_metrics.resetCalibration()
		a.dispose()
		c.dispose()
		if not ok then
			error(err, 0)
		end
	end)

	it("...and the SAME drive with the calibration untouched REPLAYS — the non-vacuity half", function()
		--[[ WITHOUT THIS THE CASE ABOVE PROVES NOTHING: a refusal is only evidence if
			the identical drive fires the arm when the stamp does not move. Same tree,
			same write, no calibration. ]]
		local a, c = pair({ rows = 8, text = true })
		a.text(1, "row 2")
		c.text(1, "row 2")
		agree(a, c, "control warm")
		withWorkCapture(function()
			a.text(1, "row 8")
		end)
		c.text(1, "row 8")
		agree(a, c, "control")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=7")
		a.dispose()
		c.dispose()
	end)
end)

describe("T14 oracle: byte-equal to a full solve, every view, every drive kind", function()
	--[[ THE DIFFERENTIAL. Five shapes, nine device views, both arms driven identically
		— every drive kind the gate has a term for — comparing the WHOLE snapshot: every
		live node's stored rect, hit rect, visibility, engine position, `rectOf`,
		`screenRectOf` and the diagnostics list. Facet's only headless adapter is
		`tests/lib/fake_target` (the Roblox one cannot run under Lune), so "both
		adapters" is served by it plus the adapter-free direct-solve audit below — the
		same price T13 and T13b recorded. ]]
	local FIXTURES: { any } = {
		{ name = "plain", rows = 8 },
		{ name = "nested", rows = 8, nested = true },
		{ name = "fill", rows = 8, fill = true },
		{ name = "distribute", rows = 6, distribute = "spaceBetween" },
		{ name = "aspect", rows = 8, aspect = true },
		--[[ ...and a TEXT fixture (fix round 1, I-2), which is the only shape a
			replay -> settle -> replay chain can be driven on: a calibration change moves
			`ctx.measureStamp` and dirties nothing, so it is the solve-wide correction the
			replay must refuse BETWEEN two replays without leaving the payload describing
			a tree measured under the old calibration. ]]
		{ name = "text", rows = 8, text = true },
		--[[ ...and the OVERHANGING fixture, because Important 1 was a DIAGNOSTICS defect
			and every other fixture here files nothing. A negative right margin makes the
			gate row's overhang a function of its own measured width, so a chain of cross
			re-places moves a FINDING as well as a rect and the snapshot's `diag=` column
			has something to compare. ]]
		{ name = "overhang", rows = 8, negMargin = true, wide = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, hit rects and the public readers survive the replay`, function()
			for _, view in device_views.VIEWS do
				local o = table.clone(fixture)
				o.viewport = { x = 0, y = 0, w = view.w, h = view.h }
				local a, c = pair(o)
				local label = `{fixture.name}/{view.id}`
				agreeAll(a, c, `{label} mount`)
				--[[ THREE CONSECUTIVE CROSS DRIVES ON DIFFERENT ROWS, WITH NOTHING
					REFUSING BETWEEN THEM (fix round 1, I-2). The loop below interleaves a
					MAIN change after every cross change, and a MAIN change refuses and
					re-records — so before this block no case in this file chained two
					replays with DIFFERENT dirty children, which is exactly the shape
					Important 1's defect needed. The fourth drive repeats the SAME row,
					which is the other half: a payload that a replay wrote has to be
					readable by the replay after it. ]]
				for chain = 1, 3 do
					a.width(chain + 1, 44 + chain * 9)
					c.width(chain + 1, 44 + chain * 9)
					agreeAll(a, c, `{label} chain {chain}`)
				end
				a.width(2, 91)
				c.width(2, 91)
				agreeAll(a, c, `{label} chain repeat`)
				for step = 1, 3 do
					-- a CROSS-only change (the class the replay is for)
					a.width(step + 1, 50 + step * 7)
					c.width(step + 1, 50 + step * 7)
					agreeAll(a, c, `{label} cross {step}`)
					-- ...a MAIN change (the class it refuses)
					a.height(step + 1, 18 + step * 3)
					c.height(step + 1, 18 + step * 3)
					agreeAll(a, c, `{label} main {step}`)
					-- ...the container's own gate and align
					a.gap(step)
					c.gap(step)
					agreeAll(a, c, `{label} gap {step}`)
					a.align(if step % 2 == 0 then "center" else "end")
					c.align(if step % 2 == 0 then "center" else "end")
					agreeAll(a, c, `{label} align {step}`)
					-- ...and a viewport change, where the arm is unreachable
					a.viewport(view.w - step, view.h - step)
					c.viewport(view.w - step, view.h - step)
					agreeAll(a, c, `{label} viewport {step}`)
				end
				--[[ ...AND THE SECOND PASS, AUDITED (ruling A-12). The audit is a SOLVER
					opt, so a mounted arm cannot turn it on — but the solve an arm just ran
					can be REPLAYED with it. One more drive on arm `a` alone, captured, then
					re-solved with `stackReplayAudit = true`: the gate is still evaluated
					and the FULL placement loop still runs, asserting every rect the replay
					would have served against the one the loop just computed, inside the
					solve, at this fixture and this viewport.

					THE GUARD IS `replayChecks`, NOT A PROXY. It counts the comparisons
					themselves and is incremented only on the audit path, so every
					production solve reads 0 and a case where the audit asserted NOTHING
					cannot read as a case where it passed.

					AND IT PRICES ONE TICK ONLY (fix round 1, I-2). The audited pass does
					not re-record, so the payload it checks is the one the last REPLAY left
					— which is the state Important 1's defect lived in, and is why the
					audit could not see it before. What it still cannot say is "and it will
					hold after two more replays": that is the chained-replay drives above
					and the rotating-rows case, and the two are a pair rather than one
					covering the other. ]]
				--[[ ...AND A REPLAY -> SETTLE -> REPLAY CHAIN (fix round 1, I-2). A
					CALIBRATION change moves `ctx.measureStamp` and dirties nothing, so the
					replay must REFUSE across it — and the tick after it must not be reading
					a payload recorded under the old calibration. Global, so it is put back
					whatever happens, exactly as `measure_reuse.spec`'s own rule demands. ]]
				a.width(3, 47)
				c.width(3, 47)
				agreeAll(a, c, `{label} pre-settle replay`)
				local calOk, calErr = pcall(function()
					text_metrics.calibrate("BuilderSans", 0.33)
					a.width(4, 53)
					c.width(4, 53)
					agreeAll(a, c, `{label} settle tick`)
					a.width(5, 59)
					c.width(5, 59)
					agreeAll(a, c, `{label} post-settle replay`)
				end)
				text_metrics.resetCalibration()
				if not calOk then
					a.dispose()
					c.dispose()
					error(calErr, 0)
				end
				a.width(6, 61)
				c.width(6, 61)
				agreeAll(a, c, `{label} post-reset replay`)
				--[[ THE WARM-UP CROSS-RE-PLACES A **DIFFERENT** ROW FROM THE ONE THE
					AUDITED SOLVE DIRTIES (fix round 1, I-2). That is what puts a stale
					entry in front of the audit at all: row 3 is re-placed and then goes
					CLEAN, so the audited pass compares `pRect[3]` — the payload as the
					last REPLAY left it — against a freshly computed rect. With the
					warm-up on the same row as the drive (the first version of this block)
					the served value is always `hot[idx]`, no recorded entry is ever
					consulted, and the arm asserts only about the tick it is looking at. ]]
				a.width(3, 43)
				c.width(3, 43)
				agreeAll(a, c, `{label} audit warm-up`)
				withWorkCapture(function()
					a.width(2, 44)
				end)
				c.width(2, 44)
				agreeAll(a, c, `{label} audit drive`)
				local audited = table.clone(capture.opts)
				audited.stackReplayAudit = true
				local checked = solver.solve(capture.root, capture.viewport, audited)
				if checked.work.replayChecks < 1 then
					error(`{label}: the audited pass compared {checked.work.replayChecks} rects`, 0)
				end
				if checked.work.placeSkipped ~= 0 then
					error(`{label}: the audit did not disable the fast return`, 0)
				end
				a.dispose()
				c.dispose()
			end
		end)
	end
end)

describe("T14: the node-resident offer pair, and why T13/T13b's null is structural", function()
	it("its two readers and its one writer cannot meet — the finding, as a source pin", function()
		--[[ T13 AND T13b BOTH RECORDED `child.oMemo` AS A BEHAVIOURAL NULL and both
			named T14 as the task that would make it load-bearing: "the day you stop
			re-measuring, the node-resident pair becomes the sole writer of
			`offerW`/`offerH` for served children, and the anchor arms ARM a rect-serving
			skip on it". **T14 does not make it load-bearing, and the reason is
			structural rather than a fixture nobody found.**

			  * The FALLBACK is read in exactly one place — `arrangeBody`'s entry literal
			    — and only when `ctx.offers` missed for that node.
			  * Its only writer is `stack_measure`'s container walk, so the nodes that
			    carry a non-nil `oMemo` are the children of a STACK.
			  * `entry.offerW`/`offerH` have exactly TWO readers, both inside the ANCHOR
			    branch, and both ask about a child of an ANCHOR
			    (`prevAll[child.id]` / `prevOf[child.id]` for `child in node.children`).
			A node has one parent, so a node cannot be both. And under the replay a
			CLEAN child is not placed at all — no fresh entry literal is built for it, so
			its recorded `offerW`/`offerH` are the ones the previous solve filed, at the
			same `innerW`/`innerH`, both gate terms.

			SO THIS CASE IS THE ARGUMENT, MECHANISED, rather than a witness this task
			could not build: the counts below are what make the three bullets checkable
			after an edit that moves any of them. The behavioural half is a recorded
			MUTATION — poisoning `mOffW` in the fallback leaves the whole suite green —
			and it is reported as a NULL WITH A MECHANISM, which is the strongest form
			this channel has had. ]]
		local fs = require("@lune/fs")
		local function strip(path: string): string
			local body = fs.readFile(path)
			return (body:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
		end
		local solverBody = strip("src/layout/solver.luau")
		local measureBody = strip("src/layout/stack_measure.luau")
		local writes = 0
		for _ in string.gmatch(measureBody, "%.oMemo%s*=") do
			writes += 1
		end
		local otherWrites = 0
		for _ in string.gmatch(solverBody, "%.oMemo%s*=") do
			otherWrites += 1
		end
		local fallbackReads = 0
		for _ in string.gmatch(solverBody, "oMemo%.mOff[WH]") do
			fallbackReads += 1
		end
		local offerReads = 0
		for _ in string.gmatch(solverBody, "[%a_][%w_]*%.offer[WH]%s*==") do
			offerReads += 1
		end
		expect(
			`oMemo writes in stack_measure={writes} in solver={otherWrites} `
				.. `fallback reads={fallbackReads} entry-offer readers={offerReads}`
		).toBe("oMemo writes in stack_measure=1 in solver=0 fallback reads=2 entry-offer readers=4")
		-- ...and BOTH entry-offer readers sit inside the anchor branch, after the line
		-- that opens it. A reader that moved out of it would break the argument above,
		-- and this is the check that would say so.
		--[[ ...AND **BOTH** READERS, NOT THE FIRST (fix round 1, minor 5). A pin that
			only asked about the first would pass while a second reader migrated out of
			the anchor branch, which is the one edit that would break the argument above.
			The branch's own end is not greppable, so the check is "every `.offerW ==`
			and `.offerH ==` in the file sits after the line that opens it" — the
			conservative half, plus the exact count above, which is what stops a THIRD
			reader appearing anywhere. ]]
		local anchorAt = string.find(solverBody, 'node.kind == "anchor"', 1, true)
		expect(anchorAt ~= nil).toBe(true)
		local outside = 0
		local seen = 0
		for at in string.gmatch(solverBody, "()%.offer[WH]%s*==") do
			seen += 1
			if at < (anchorAt :: number) then
				outside += 1
			end
		end
		expect(`entry-offer reads={seen} outside the anchor branch={outside}`).toBe(
			"entry-offer reads=4 outside the anchor branch=0"
		)
		--[[ ...AND TASK 13b's SECOND DEMAND, which its review made and this file owes an
			answer to: "a case for the fallback's own failure mode — a container measured
			at TWO offers in one solve". That shape is real and this is it: a HUGGING list
			hands each row the screen's width in the measure pass and its own resolved
			width in the arrange pass, so `cmemo.mOffW` holds whichever was recorded LAST
			and a served child taking its offer from there could file a pair that no pass
			ever asked it. **The wrongness is unobservable**, and the count above is why:
			the pair reaches only a STACK child's entry and is read only about an ANCHOR
			child. What this case pins is the precondition and the actual outcome — every
			row's entry carries the ARRANGE offer, which is what `measure` wrote, not the
			memo's. If a later round gives `offerW` a third reader, this is the case that
			has to be re-argued. ]]
		local two = scene.new({ rows = 12, hug = true })
		two.text(4, "warm")
		withWorkCapture(function()
			two.text(4, "two-offer")
		end)
		local rects = capture.result.rects
		local list = rects["/S/List"]
		local sample = rects["/S/List/R7"]
		expect(
			`list innerW={if list ~= nil and list.rect ~= nil then list.rect.w else -1} `
				.. `row offerW={if sample ~= nil then tostring(sample.offerW) else "-"}`
		).toBe("list innerW=300 row offerW=300")
		two.dispose()
	end)

	it("a CLEAN child the replay skipped keeps the offer pair the last solve filed", function()
		--[[ THE POSITIVE HALF, on rects rather than on an argument: the entries of the
			children this arm did not place still carry the offer they were measured at,
			because nothing rebuilt them. If the arm had built fresh entry literals for
			skipped children — the shape that would have made the fallback load-bearing —
			this pair would read nil here. ]]
		local a, c = pair({ rows = 8 })
		a.width(1, 61)
		c.width(1, 61)
		withWorkCapture(function()
			a.width(4, 95)
		end)
		c.width(4, 95)
		agree(a, c, "offers")
		local rects = capture.result.rects
		local withOffer = 0
		for i = 1, 8 do
			local e = rects[`/S/List/R{i}`]
			if e ~= nil and e.offerW ~= nil and e.offerH ~= nil then
				withOffer += 1
			end
		end
		expect(`entries carrying an offer pair={withOffer} of 8`).toBe("entries carrying an offer pair=8 of 8")
		a.dispose()
		c.dispose()
	end)
end)

describe("T14: three terms whose witness took a shape of its own", function()
	it("a MARGIN SPLIT with the total unchanged refuses", function()
		--[[ THE PAIR IS MARGIN-INCLUSIVE, WHICH IS WHY THE MARGIN IS ITS OWN TERM. Left
			11 / right 7 becomes left 7 / right 11: the measured extent is the same, the
			margin-inclusive contribution is the same, and the child is 4px to the left of
			where it was. Nothing in `pMain`/`pCross` can see that, and the four-side
			comparison is asked of DIRTY children only — a clean child's margin cannot
			have moved, because a margin write is what makes a node dirty. ]]
		local a, c = pair({ rows = 8, margin = true })
		a.gateMargin(11)
		c.gateMargin(11)
		agree(a, c, "margin warm")
		withWorkCapture(function()
			a.gateMargin(7)
		end)
		c.gateMargin(7)
		agree(a, c, "margin split")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=0")
		a.dispose()
		c.dispose()
	end)

	it("the container's ORIGIN moving with its size unchanged refuses", function()
		--[[ `pInnerX`/`pInnerY` ARE NOT THE SAME TERM AS `pInnerW`/`pInnerH`, and no
			single-signal drive in this fixture can tell them apart. A header above the
			list, whose height is a signal, moves the list's `innerY` while its size and
			every child inside it stand still — and a row write in the SAME tick is what
			puts a dirty child inside it so the arm is reached at all. The rects this arm
			serves are ABSOLUTE, so an origin it did not check is every child in the wrong
			place. ]]
		local a, c = pair({ rows = 8, header = true })
		a.headerAndRow(10, 2, 61)
		c.headerAndRow(10, 2, 61)
		agree(a, c, "origin warm")
		withWorkCapture(function()
			a.headerAndRow(26, 2, 62)
		end)
		c.headerAndRow(26, 2, 62)
		agree(a, c, "origin moved")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=0")
		a.dispose()
		c.dispose()
	end)

	it("a CLEAN child whose INDEX moved under a two-region splice refuses", function()
		--[[ THE REVIEW'S BLOCKING FIXTURE, in the only shape that can actually reach it.
			`pN == #children` fixes the LENGTH of the spliced flat list, so a single
			region losing or gaining a row is refused by the count and every clean child
			keeps its index. What survives that term is a container holding TWO regions
			with plain rows between them: remove from the first and add to the second in
			ONE tick and the count is unchanged while every row between them shifts by
			one — and those rows are CLEAN, because `mount` pushes dirt for a region's own
			changed or reordered children and not for its siblings.

			THE ROWS ARE DELIBERATELY DIFFERENT HEIGHTS. With identical rows the recorded
			rect at index k is the right rect for whatever now sits at index k, and the
			fixture would be a witness to nothing. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		local left = core:signal({ { key = "L1" }, { key = "L2" } })
		local right = core:signal({ { key = "R1" } })
		local function region(id: string, items: any): any
			return UI.ForEach({
				id = id,
				items = items,
				key = function(item: any)
					return item.key
				end,
				row = function(item: any)
					return UI.Box({ id = "Item", width = px(24), height = px(8) })
				end,
			})
		end
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "List",
					padding = 0,
					gap = 0,
					width = px(300),
					height = px(560),
					children = {
						region("A", left),
						UI.Box({ id = "M1", width = px(30), height = px(11) }),
						UI.Box({ id = "M2", width = px(30), height = px(23) }),
						UI.Box({ id = "M3", width = px(30), height = px(37) }),
						region("B", right),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new({})
		local controller = renderer.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			incrementalLayout = true,
			measureReuse = true,
			layoutNodeReuse = true,
			commitScope = true,
			translateHosts = true,
		})
		controller.initialRender()
		local function mid(): string
			local out: { string } = {}
			for _, id in { "M1", "M2", "M3" } do
				local r = controller.rectOf(`/S/List/{id}`)
				table.insert(out, if r == nil then `{id}=-` else `{id}={r.x},{r.y},{r.w},{r.h}`)
			end
			return table.concat(out, " ")
		end
		local before = mid()
		expect(before).toBe("M1=0,16,30,11 M2=0,27,30,23 M3=0,50,30,37")
		-- ONE tick: the first region loses a row and the second gains one, so
		-- `#children` is 5 before and 5 after while M1..M3 each move up by 8px
		withWorkCapture(function()
			left:set({ { key = "L2" } })
			right:set({ { key = "R1" }, { key = "R2" } })
			controller.refresh()
		end)
		expect(mid()).toBe("M1=0,8,30,11 M2=0,19,30,23 M3=0,42,30,37")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=0")
		controller.dispose()
		root.dispose()
	end)
end)

describe("T14: a CHAIN of replays, which is where the payload has to keep up", function()
	--[[ FIX ROUND 1, IMPORTANT 1. The replay COMMITS rects it did not RECORD: a
		cross-only re-place writes `hot[idx]` and `place`s it while `cmemo.pRect`/`pCross`
		keep describing the last FULL pass, and `pNoted` is never raised. The RECTS
		survive that — `pRect` and `pCross` go stale TOGETHER, so the "nothing moved" copy
		is only ever taken when the fresh measurement matches the rect it was recorded
		with — but the DIAGNOSTICS do not, in both directions:

		  * a finding re-filed for a CLEAN child is re-filed from the rect that child had
		    two ticks ago, so an overhang that grew is reported at its old size;
		  * a finding CREATED by a cross re-place is lost on the next tick, because
		    `pNoted` still says this container filed nothing and no clean child is
		    re-noted — while `solve`'s diagnostic replay drops the previous copy, since
		    the container was walked.

		The second is the "silently, and forever" class MUST-FIX 3 was written to prevent,
		one lane over — and the lane is the one this task added beyond the plan.

		BOTH CASES CHAIN TWO REPLAYS WITH **DIFFERENT** DIRTY CHILDREN, which is the shape
		nothing in this file had: the two ten-step diagnostic loops above chain replays but
		always with the SAME dirty row, so the child whose payload goes stale is never the
		one that goes clean. ]]
	it("a finding about a CLEAN child is re-filed from THIS tick's rect, not from two ticks ago", function()
		local a, c = pair({ rows = 8, negMargin = true, wide = true })
		a.width(3, 400)
		c.width(3, 400)
		agree(a, c, "chain warm")
		expect(string.find(a.diagKey(), "100px past the right edge", 1, true) ~= nil).toBe(true)
		-- TICK A: the OVERHANGING row is the dirty one, so it is cross-re-placed and its
		-- finding is filed fresh at the new rect
		withWorkCapture(function()
			a.width(3, 460)
		end)
		c.width(3, 460)
		agree(a, c, "chain tick A")
		expect(`A: skipped={capture.result.work.placeSkipped}`).toBe("A: skipped=7")
		-- TICK B: a DIFFERENT row is dirty, so row 3 is CLEAN and is re-noted from the
		-- payload. Without the write-back that payload is the last FULL pass's rect and
		-- the finding reads 100px where the truth is 160px.
		withWorkCapture(function()
			a.width(5, 70)
		end)
		c.width(5, 70)
		agree(a, c, "chain tick B")
		expect(`B: skipped={capture.result.work.placeSkipped}`).toBe("B: skipped=7")
		expect(string.find(a.diagKey(), "160px past the right edge", 1, true) ~= nil).toBe(true)
		a.dispose()
		c.dispose()
	end)

	it("a finding CREATED by a cross re-place survives the NEXT replay", function()
		--[[ THE SHARPER OF THE TWO. The recording pass leaves `pNoted = false` because
			nothing overhangs; the cross re-place on tick A files the finding (a `hot`
			child is always re-noted); and on tick B `pNoted` is STILL false, so no clean
			child is re-noted and the previous copy is dropped by the solve-level replay.
			Live diagnostics: empty. Control: the finding. ]]
		local a, c = pair({ rows = 8, negMargin = true })
		a.width(3, 200)
		c.width(3, 200)
		agree(a, c, "loss warm")
		expect(a.diagKey()).toBe("")
		withWorkCapture(function()
			a.width(3, 460)
		end)
		c.width(3, 460)
		agree(a, c, "loss tick A")
		expect(`A: skipped={capture.result.work.placeSkipped}`).toBe("A: skipped=7")
		expect(string.find(a.diagKey(), "160px past the right edge", 1, true) ~= nil).toBe(true)
		withWorkCapture(function()
			a.width(5, 70)
		end)
		c.width(5, 70)
		agree(a, c, "loss tick B")
		expect(`B: skipped={capture.result.work.placeSkipped}`).toBe("B: skipped=7")
		expect(string.find(a.diagKey(), "160px past the right edge", 1, true) ~= nil).toBe(true)
		a.dispose()
		c.dispose()
	end)

	it("...and a chain of FIVE cross re-places on rotating rows tracks a full solve throughout", function()
		--[[ THE GENERAL SHAPE, because the two cases above each pin one direction. Five
			consecutive replays, a different row dirty each time and no refusing drive
			between them, with the whole snapshot compared against a forced full solve
			after every one. `placeSkipped=7` on each says every tick really was a replay
			— a chain that quietly started refusing would agree with the control for the
			wrong reason. ]]
		local a, c = pair({ rows = 8, negMargin = true, wide = true })
		a.width(3, 400)
		c.width(3, 400)
		agreeAll(a, c, "rotate warm")
		for step = 1, 5 do
			local row = 1 + (step % 8)
			withWorkCapture(function()
				a.width(row, 380 + step * 13)
			end)
			c.width(row, 380 + step * 13)
			agreeAll(a, c, `rotate {step} (row {row})`)
			expect(`step {step}: skipped={capture.result.work.placeSkipped}`).toBe(`step {step}: skipped=7`)
		end
		a.dispose()
		c.dispose()
	end)
end)

describe("T14: owed row 11 — the order the replay files in", function()
	it("the replay files its containment findings in DOCUMENT order, as the placement loop does", function()
		--[[ OWED ROW 11, PINNED RATHER THAN ASSERTED (fix round 1, minor 3). The row
			claims "document order UNCHANGED", and nothing in this file could see it: the
			oracle's `diagKey()` SORTS, so it compares the finding SET. `diagOrder()` is
			the unsorted reader, and two overhanging rows are what make an order exist at
			all.

			THE CLAIM IS ABOUT THIS ARM'S OWN FILING, AND THE ROW IS NARROWED TO IT. The
			SOLVE's final diagnostics LIST is not claimed to match a full solve's: the
			solve-level replay appends every carried-forward finding at the TAIL
			(`solver.luau`'s replay loop), which is a different position from where the
			walking pass would have filed it, and that is true at HEAD for every skipped
			subtree. What this arm owes is that IT does not reorder, and that is what is
			pinned here — including across a replay, where the re-file walks `children`
			and interleaves `noteContainment`/`place` exactly as the placement loop does. ]]
		local a, c = pair({ rows = 8, negMargin = true, wide = true })
		a.width(3, 400)
		c.width(3, 400)
		agree(a, c, "order warm")
		expect(c.diagOrder()).toBe("/S/List/R3")
		-- row 6 carries the same negative margin and is driven past the edge here, so the
		-- tick has TWO findings and they must come back in index order on both arms
		withWorkCapture(function()
			a.width(6, 480)
		end)
		c.width(6, 480)
		agree(a, c, "order two findings")
		expect(`skipped={capture.result.work.placeSkipped}`).toBe("skipped=7")
		expect(a.diagOrder()).toBe(c.diagOrder())
		expect(a.diagOrder()).toBe("/S/List/R3,/S/List/R6")
	end)
end)
