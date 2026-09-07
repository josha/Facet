--!strict
--[[ T13 — A CONTAINER RE-ASKS ONLY ITS DIRTY CHILDREN.

	C2 (`tests/measure_serve.spec.luau`) made the ANSWER cheap: a clean node asked the
	question it answered last solve returns from two slots on itself in ~0.47 us. It
	could not make the PARENT STOP ASKING. On the arena's `battle_hud` workload at L a
	ONE-LEAF write measured 6 nodes and entered `measure` 2,221 times, 2,206 of which
	the serve answered — 1.038 ms of a 1.824 ms class, spent asking questions whose
	answers had not moved.

	SO THE PARENT KEEPS ITS CHILDREN'S ANSWERS. Four arrays indexed by child index —
	`mMain`, `mCross`, `mCuts`, `mIds` — plus a four-part key
	(`mStamp`, `mScope`, `mOffW`, `mOffH`), on a `cmemo` table whose home is the
	MOUNT-KEYED STORE ENTRY (`render/layout_node`'s `store.byNode`) and not the layout
	node. That is not a detail: a container holding one dirty child has its layout node
	REBUILT every tick, so a memo living there would be nil on exactly the ticks this
	lever is for.

	NOTHING IS AGGREGATED AND NOTHING IS PATCHED. `mainSum` is re-summed from `mMain`
	exactly as the loop always summed it, so the memo cannot drift from a base PASS 1.5
	moved. What the skip removes is the `measure` CALL — the WHOLE call, because the arm
	`continue`s before `measure` is entered, so nothing is routed through C2's serve and
	this branch owes every channel that call would have published.

	── THE OWED LIST ────────────────────────────────────────────────────────────────
	C2's table asked "may this CHILD be served". This one asks "may this PARENT skip
	asking", which is a different question with a different answer per channel.

	 #  channel                          verdict
	 1  `ctx.offers[wKey]`/`[hKey]`      SERVED. The skip writes the RAW offer pair,
	    (`solver.luau`, and the rect     which is what the serve one level down writes
	    entry that reads it back)        too. A nil there disarms BOTH anchor arms for
	                                     the life of the surface (T7 finding 2), so
	                                     this is not optional. Case: "the offer channel
	                                     survives a skipped child"
	 2  `ctx.textStates`/`compact`/      GATED PER CHILD, and per child ONLY. A `text`
	    `textFacts` (`record`'s          or `composition` DIRECT child is never
	    `publishes` predicate)           skipped, so `record` publishes exactly what it
	                                     publishes today. Killing the whole container
	                                     at the first such child was measured at 1.4 %
	                                     of `battle_hud L`'s calls where the per-child
	                                     refusal reaches 96.8 %: a real flat list
	                                     splices labels into its own flow. Case: "a
	                                     container with a `text` child still memoises
	                                     its other children"
	 3  `ctx.fitCuts +=`                 SERVED from `mCuts[idx]`, recorded as the
	                                     `ctx.fitCuts` delta across that child's own
	                                     call — which is exactly what `record`
	                                     subtracts to get a node's `cuts`. ▲ IT IS THE
	                                     ONE SERVED NUMBER WITH NO GEOMETRIC SHADOW,
	                                     so a rect differential cannot witness it and
	                                     the first version of this file did not: the
	                                     case is "a memoising stack inside a
	                                     `ViewThatFits` candidate", and the audit arm
	                                     now compares `mCuts` as well
	 4  `shrinkBasis[idx]`               GATED: a `shrinkWeight > 0` child sets
	                                     `memoable = false`, so nothing is recorded and
	                                     the key is dropped. ▲ IT DOES NOT CLEAR `hit`:
	                                     on the tick a weight ARRIVES the key still
	                                     matches, so PASS 1.5 runs over a partly
	                                     memo-served `mainSum`. That is EXACT — a served
	                                     number is the number this loop would have
	                                     produced for that index — and it is the case
	                                     "a shrinkWeight ARRIVING on a container that
	                                     already memoised"
	 5  the fill pass's re-measure       NOT SKIPPED, EVER. `crossOf`/`marginMain` are
	                                     freshly allocated and a fill index is never
	                                     written in PASS 1, so the fill pass re-measures
	                                     every fill child on every tick. Case: "a `fill`
	                                     child is re-measured on EVERY tick"
	 6  `ctx.compositions`/`hasScroll`/  GATED by C2's own gate asked of the CHILD
	    the container arm/`boundary`     (`subtreeHasScroll`, `subtreeHasComposition`,
	                                     `containerRelativeInside`) plus `ctx.analyze`
	                                     and `ctx.measureQuiet` on the container
	 7  `ctx.mdepth`/`deepNesting`       BALANCED BY CONSTRUCTION: the child is not
	                                     entered, so nothing is pushed and nothing owed
	 8  `ctx.measureCalls`/`Served`      MOVES BY DESIGN. Both fall, both re-recorded in
	                                     this commit — Facet and Rascal Rally
	 9  the index -> child binding       GATED BY AN ID KEY. See below
	10  the O(n) residual                NOT SERVED, BOOKED. Three passes over the child
	                                     array survive; only the work INSIDE them became
	                                     O(dirty). `lastChildVisits` counts CALLS, never
	                                     iterations, and this task does not claim the
	                                     iteration count
	11  `record`'s slot maintenance      SERVED, and ▲ THE REASON WAS RESTATED (review
	    (`node.mStamp`, `mA*`/`mB*`)     round 1, M-1). The first version said "a
	                                     skipped child is a node-store HIT, so its
	                                     layout node is the SAME TABLE and its slots
	                                     survive" — which is FALSE for an
	                                     arrange-dirty, measure-clean child:
	                                     `layout_node.build`'s `store.dirty` is the
	                                     renderer's `nodeDirty`, every dirty path of
	                                     EVERY class plus prefixes, which is strictly
	                                     wider than `measureContains`, so such a child
	                                     IS rebuilt (fresh node, `mStamp = nil`) while
	                                     the memo still skips it. The verdict survives
	                                     on a tighter argument: a skipped child is
	                                     measure-clean at an unchanged `measureStamp`,
	                                     which is C2's OWN serve gate — so without the
	                                     memo `measure` would have taken the serve and
	                                     returned THROUGH `record`, where the matching
	                                     slot's `mAW == w and mAH == h and mACuts ==
	                                     cuts` is an unconditional early return with
	                                     zero writes. `record` under a serve is a
	                                     no-op, so the memo owes it nothing.
	                                     `lastMeasured` UNMOVED is a consistent
	                                     witness, not a sufficient one — and if it
	                                     moves, the skip served a child this build
	                                     actually re-measures, which is a finding

	── RE-RECORDED 2026-09-05 (Plan C, T14), AND THE MOVEMENT IS THE POINT ──────────
	Every `calls`/`served` number in this file fell, and one `measured` moved by one.
	The cause is one line of arithmetic: at HEAD a stack child was measured TWICE per
	solve — once by its parent's MEASURE pass (`contentSize`, what this file is about)
	and once by its parent's ARRANGE pass (`stack.arrange`'s PASS 1, which measured
	every child in order to build a `childRect` for it). T14 deletes the second one on
	every stack where nothing moved, so the arrange half of `lastMeasureCalls`
	disappears and the calls that used to be ANSWERED by C2's node-resident serve
	disappear with it — which is why `served` falls hardest of all.

	WHAT DID NOT MOVE IS THE CLAIM THIS FILE MAKES. `visits` (the `measure` calls a
	stack's MEASURE branch makes) and `measured` (uncached measures) are this lever's
	numbers, and they are unchanged on every steady-state case. The one exception is
	the `containerRelative`-ARRIVAL tick, which is re-recorded with its reason at the
	case: the arrange pass used to refresh each child's SECOND measure slot at the
	arrange offer, and a tick that now finds that slot cold pays one more uncached
	measure and one more visit. Every rect on that tick still agrees with a full solve,
	which is the case's own oracle and is unchanged.

	── WHY THE ID KEY, AND WHAT IT IS NOT ───────────────────────────────────────────
	The carrier gate compares the MOUNT node's `node.children` by identity. The array
	the memo indexes is the LAYOUT node's SPLICED FLAT LIST, and the two are not the
	same list: `mount` replaces a `UI.ForEach` REGION's children, never its parent's, so
	an insert shifts every later index while the carrier gate still holds. Measured, an
	index-keyed gate reads 98 % skippable on a remove where every index moved — and
	every one of those serves would be a number belonging to a different node. So the
	memo carries `mIds` and the skip's own term is `mIds[idx] == child.id`.

	`child.id` IS THE MOUNT PATH (`render/layout_node`'s `id = node.path`): stable
	across a rebuild of the child, unique among siblings because paths are — and NOT AN
	IDENTITY. A region that re-creates DIFFERENT content under the SAME path is a
	structural change, and what refuses it is one level up. ▲ NAMED PRECISELY (review
	round 1, M-2): it is **`structural_scope.widen(structural.contains,
	nodeStore.builtIds)`** (`renderer.luau:2014`), which mutates in place the very
	table `measureContains` points at — NOT the `measureContains = dirtyContains`
	assignment three hundred lines below it, which alone would not cover this, because
	the re-created path is a DESCENDANT of the dirty region path and both
	`dirty_closure.of` and `structural_scope.plan` close over ANCESTORS. The re-created
	node is a new mount node, so `layout_node.build` constructs it and its path lands
	in `builtIds`; the widen puts it in the measure-dirty set and the skip arm never
	fires for it. The case "the SAME PATH with different content" drives exactly that
	and pins the geometry; the id key cannot see it and does not claim to.

	── WHAT THE COUNTER COUNTS ──────────────────────────────────────────────────────
	`lastChildVisits` is `measure` calls made by PASS 1 of a stack's measure branch —
	the calls the memo can remove — and nothing else. The fill pass's re-measure and
	PASS 1.5's re-measure at the reduced offer are NOT counted, because the memo never
	removes them and a counter that swept them in would report a win this task does not
	have. On this file's fixture the memoising containers are the Screen (one child) and
	`List` (a thousand), and a row's own content size is never computed at all — every
	row declares a fixed width and height. That last fact was learned from the run: the
	first version of the `fill` and `shrinkWeight` arms put those props on a box INSIDE
	a row, where no memoising loop ever reaches them, and the counters came back
	byte-identical to the plain arm.

	Every count pin below carries `solves=N`, because a drive that solves ZERO times
	silently re-asserts the previous solve's counters. Every number was read off the run
	at this commit with the warm-up drive discarded. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/deep_stack_scene")
local nameplates = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")
local solver = require("../src/layout/solver")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local ROWS = 1000
local GATE_ROW = scene.GATE_ROW

--[[ ONE DRIVE, AND WHAT IT COST, in the shape `measure_serve` and `anchor_arrange`
	established. `visits` is this task's own counter; `calls`/`served`/`measured` are
	C2's, carried in the same string because the claim is about how the three move
	TOGETHER — `visits` and `calls` fall, `measured` does not move at all. ]]
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
	return `solves={n} calls={w.measureCalls} served={w.measureServed} measured={w.measured} visits={w.childVisits}`
end

--[[ THE LADDER FIXTURE, local to the one case that needs it (owed row 3). It is not an
	arm of `deep_stack_scene` because nothing else in this file is a `ViewThatFits`, and
	the shape is load-bearing in a way a shared opt would hide: the rich rung is a
	MEASURE-DIRTY VStack (so C2's serve refuses it and `contentSize` is entered at all),
	its row 1 carries the dirt, and its row 2 holds ONE UNBROKEN WORD wider than the
	40px offer — a phrase would wrap, and wrapping is fitting. The honest rung is no
	TALLER than the cut one, because a taller honest rung loses the ladder's undercut
	rule and the case would pass for the wrong reason. ]]
local function fitsScene(opts: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	local rowWidth = core:signal(20)
	local rows: { any } = {}
	for i = 1, 6 do
		rows[i] = UI.HStack({
			id = `Row{i}`,
			padding = 0,
			gap = 0,
			width = { type = "content" },
			height = { type = "content" },
			children = {
				if i == 2
					then UI.Text({ id = "Long", text = "Reconfiguration" })
					elseif i == 1 then UI.Box({
						id = "B",
						width = core:memo(function(use: any)
							return { type = "fixed", px = use(rowWidth) :: number }
						end),
						height = { type = "fixed", px = 10 },
					})
					else UI.Box({
						id = "B",
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 10 },
					}),
			},
		})
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.VStack({
				id = "Root",
				padding = 0,
				gap = 0,
				width = { type = "fill", weight = 1 },
				height = { type = "content" },
				children = {
					UI.ViewThatFits({
						id = "Fits",
						width = { type = "fixed", px = 40 },
						children = {
							UI.VStack({
								id = "Rich",
								padding = 0,
								gap = 0,
								width = { type = "content" },
								height = { type = "content" },
								children = rows,
							}),
							UI.Box({
								id = "Plain",
								width = { type = "fixed", px = 20 },
								height = { type = "fixed", px = 20 },
							}),
							UI.Box({
								id = "Fallback",
								width = { type = "fixed", px = 20 },
								height = { type = "fixed", px = 10 },
							}),
						},
					}),
				},
			}),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new({})
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = opts.incremental ~= false,
		measureReuse = opts.measureReuse ~= false,
		layoutNodeReuse = true,
		commitScope = true,
		translateHosts = true,
	})
	controller.initialRender()
	local w: any = {}
	function w.driveRow(value: number)
		rowWidth:set(value)
		controller.refresh()
	end
	-- WHICH RUNG WON, read the way `tests/adaptive.spec.luau` reads it: the rungs the
	-- ladder did not choose are arranged at zero width
	function w.chosen(): string
		local out = {}
		for _, id in { "Rich", "Plain", "Fallback" } do
			local n = adapter.node(`/S/Root/Fits/{id}`)
			table.insert(out, `{id}={if n ~= nil and n.rect ~= nil then n.rect.w else -1}`)
		end
		return table.concat(out, " ")
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

describe("T13: one changed row does not make 999 parents ask again", function()
	it("a text write on ONE leaf: the calls fall, and `measured` does not move", function()
		--[[ THE HEADLINE, and the two numbers that carry it. `visits` is 1,001 on the
			warm-up (the first reuse solve after a full one records and can serve nothing,
			exactly as `record` does) and 2 on the drive: `List` asks about the one dirty
			row, the Screen asks about `List`, and the other 999 rows are answered from
			the memo. `calls` falls 2,005 -> 1,006 with it — the 999 asks that stopped
			being made.

			`measured=5` IS THE ROW-11 WITNESS AND IT IS THE MOST IMPORTANT NUMBER HERE.
			It is 5 at HEAD and 5 with the memo. A skipped child never runs `record`, so
			its stamp and slots are not refreshed; they survive because a skipped child is
			also a node-store HIT and its layout node is the same table. If this number
			moved, the memo would have skipped a child this build actually re-measures. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe("solves=1 calls=8 served=1 measured=5 visits=2")
			s.dispose()
		end)
	end)

	it("...and the WARM-UP is the full walk, which is what says the drive was memo work", function()
		--[[ THE BEFORE COLUMN, measured on THIS build rather than remembered. The first
			reuse solve after a full one has an EMPTY memo, so it walks all 1,000 children
			and records — `visits=1001`, `calls=2005`, which are HEAD's numbers exactly.
			A spec that only pinned the drive could not tell a working memo from a fixture
			that stopped having children.

			── RE-RECORDED 2026-09-06 (Plan D, D5), AND THE CASE'S OWN NUMBERS ARE THE ONES
			THAT DID NOT MOVE. `visits` — the container memo's walk, which is what this case
			is about — still reads 1,001, the full walk, and so does `calls`. What moved is
			`measured` 1,005 -> 5 with `served` 0 -> 1,000: D5 lets a FULL solve record the
			node-resident slots, so the mount leaves 3,002 of them behind and this walk's
			1,000 questions are answered from a tuple instead of re-measured. That is
			exactly the cost `record`'s old gate carried in its own words — "the first
			reuse solve after a full one records and serves nothing" — and it is gone. The
			memo's before-column is untouched by it, which is why this case still says what
			it said. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			expect(drove(function()
				s.text(500, "warm")
			end)).toBe("solves=1 calls=1007 served=1000 measured=5 visits=1001")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe("solves=1 calls=8 served=1 measured=5 visits=2")
			s.dispose()
		end)
	end)

	it("a VIEWPORT change memoises nothing, and what it serves is its OWN first answers", function()
		--[[ A geometry write is a FULL solve with no reuse table, and the CONTAINER memo's
			gate asks for `ctx.reuse` before anything else. So this is the arm where THAT
			mechanism is structurally absent: nothing is memoised, and `visits` is every
			child of every container, asked.

			── RE-RECORDED 2026-09-06 (Plan D, D5), TITLE INCLUDED. It read "serves
			nothing", which was true of both serves until D5 gave the node-resident one a
			WITHIN-solve arm: a full solve now records a slot the first time it measures a
			node and answers the second ask of the same node at the same offer from it. So
			`measured` is one per layout node exactly (3,002 of 3,002) where it was 5,003,
			`served` is 1,001, and `visits` falls 2,001 -> 1,001 because a container the
			arrange pass re-asks is served WITHOUT descending into the children it would
			have re-measured. The CROSS-solve arm is still structurally unreachable here,
			which is what this case is for: `node.mSolve` is written only where
			`ctx.reuse == nil`, so nothing this solve did not itself measure can be
			served. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			s.text(500, "x")
			expect(drove(function()
				s.viewport(900, 640)
			end)).toBe("solves=1 calls=4003 served=1001 measured=3002 visits=1001")
			--[[ ...AND THE SOLVE AFTER IT NO LONGER PAYS THE OLD ONE-SOLVE COST. It read
				`calls=1005 served=0 measured=1004`: the full solve above recorded nothing,
				so every clean row was re-measured once more before the steady state came
				back. It records now, so this is an ordinary tick. ]]
			expect(drove(function()
				s.text(500, "y")
			end)).toBe("solves=1 calls=1005 served=999 measured=5 visits=1001")
			s.dispose()
		end)
	end)

	it("a WIDTH write on the CONTAINER refills the memo at the new offer", function()
		--[[ THE KEY MOVED, NOT THE DIRT — and no other drive in this fixture can say so.
			`List`'s own width is what its thousand children are measured against; a write
			to it leaves every child clean and every recorded answer measured against a
			width that no longer exists. The memo's `mOffW` term is the only thing
			standing between those children and a stale size, and the tick reads as a FULL
			walk (`visits=1001`) followed by a memoised one (`visits=2`) — refused, then
			refilled at the new offer, rather than refused forever. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, listWidth = true })
			s.text(500, "warm")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe("solves=1 calls=8 served=1 measured=5 visits=2")
			expect(drove(function()
				s.listWidth(880)
			end)).toBe("solves=1 calls=2003 served=1000 measured=1002 visits=1001")
			expect(drove(function()
				s.text(500, "y")
			end)).toBe("solves=1 calls=6 served=0 measured=5 visits=2")
			s.dispose()
		end)
	end)
end)

describe("T13: the gate, one case per owed row", function()
	local function gateDrive(opts: any): string
		local out
		withWorkCapture(function()
			local s = scene.new(opts)
			s.text(500, "warm")
			out = drove(function()
				s.text(500, "x")
			end)
			s.dispose()
		end)
		return out :: string
	end

	local PLAIN = "solves=1 calls=8 served=1 measured=5 visits=2"

	it("a `text` DIRECT child is refused, and its 999 siblings still memoise (row 2)", function()
		--[[ THE RE-AMENDED ROW 2, and the measurement behind it. A `text` child publishes
			three verdict channels no cached number can carry back, so it is refused — but
			PER CHILD. Revision 2 of the plan killed the whole container at the first such
			child, and on `battle_hud L` that reaches 1.4 % of this loop's calls where the
			per-child form reaches 96.8 %, because a real flat list splices its labels
			straight into its own flow.

			`visits=3` against the plain arm's 2 is that difference, said as a number: the
			label is asked on every tick, forever, and the thousand boxes beside it are
			not. A container-level refusal would read 1,002 here. ]]
		expect(gateDrive({ rows = ROWS })).toBe(PLAIN)
		expect(gateDrive({ rows = ROWS, label = true })).toBe("solves=1 calls=9 served=2 measured=5 visits=3")
	end)

	it("a `shrinkWeight > 0` child takes the whole container out of the memo (row 4)", function()
		--[[ PASS 1.5 rebases `mainSum` by what the shrink absorbed and re-measures at the
			reduced offer — numbers this memo does not hold. So a container ANY of whose
			children declares a weight above zero records nothing, and the counter says so
			at the full walk: `visits=1001` on every tick, forever, against the plain arm's
			2. The weight rides the ROW rather than a box inside it because `List` is the
			container the memo is about, and `List` overflows its 720px by an order of
			magnitude, so the pass is LIVE rather than merely declared. ]]
		expect(gateDrive({ rows = ROWS, shrink = true })).toBe("solves=1 calls=1008 served=1001 measured=5 visits=1001")
	end)

	it("a `fill` child is re-measured on EVERY tick, memo or no memo (row 5)", function()
		--[[ THE PASS THE MEMO MUST NOT SWALLOW. A fill child's index is never written in
			PASS 1 — it goes to `fillWeightSum` — and `crossOf` is freshly allocated every
			call, so the fill pass's `continue` scan finds it missing and re-measures it at
			its weighted share of what PASS 1 left. `remaining` depends on `mainSum`, so it
			must.

			The witness is `calls`, not `visits`: the fill pass's measure is deliberately
			NOT counted by this task's counter (the memo never removes it), so the arm
			reads `visits=2` like the plain one and TWO MORE CALLS — the fill row asked
			again, every tick. ]]
		expect(gateDrive({ rows = ROWS, fill = true })).toBe("solves=1 calls=9 served=2 measured=5 visits=2")
	end)

	it("a ScrollView, a Composition and a `containerRelative` subtree are each refused (row 6)", function()
		--[[ C2'S OWN THREE GATES, ASKED OF THE CHILD. Each is a channel whose owner is a
			node inside the subtree the skip would jump over — `ctx.hasScroll` is published
			by the scroll node itself, `ctx.compositions` by the composition, and the
			container arm of the cache key by whatever reads the container — and no cached
			number carries any of them back. All three read the same way: one extra call,
			one fewer serve, two more uncached measures and `visits=3`. ]]
		expect(gateDrive({ rows = ROWS, scroll = true })).toBe("solves=1 calls=9 served=1 measured=6 visits=3")
		expect(gateDrive({ rows = ROWS, composition = true })).toBe("solves=1 calls=9 served=1 measured=6 visits=3")
		expect(gateDrive({ rows = ROWS, crel = true })).toBe("solves=1 calls=9 served=1 measured=6 visits=3")
	end)

	it("...and `compositionAt` still answers for the refused row, which a rect cannot say", function()
		-- the one gated channel with a PUBLIC reader: a served composition would leave
		-- `ctx.compositions` empty and this dump would be nil, with every rect identical
		local key
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, composition = true })
			s.text(500, "warm")
			s.text(500, "x")
			key = s.compositionKey(`/S/List/R{GATE_ROW}/Comp`)
			s.dispose()
		end)
		expect(key).toBe("column|/S/List/R3/Comp/Reg:0,0,60,10:main")
	end)

	it("an ANALYZE solve and a non-QUIET solve memoise nothing (row 6, the two ctx gates)", function()
		--[[ `ctx.analyze` writes the boundary map inside `measureUncached`, and
			`measureQuiet` is false for a whole solve whose predecessor filed a
			measure-time finding — a finding filed about a node in the subtree the skip
			jumps over, which no number can carry back. Both are terms in the memo's gate
			for the same reason they are terms in the serve's.

			The analyze arm is driven by re-running the CAPTURED solve with one option
			changed, because `controller.analyzeBoundaries` clears `reuse` itself and would
			prove the FIRST gate while leaving this one untested. ]]
		expect(gateDrive({ rows = ROWS, unquiet = true })).toBe(
			"solves=1 calls=2005 served=0 measured=2003 visits=1001"
		)
		local shipped, analyzed
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			s.text(500, "x")
			s.dispose()
		end)
		local root, viewport, opts = capture.root, capture.viewport, capture.opts
		local plain = solver.solve(root, viewport, opts)
		shipped = `visits={plain.work.childVisits}`
		local o2 = table.clone(opts)
		o2.analyzeBoundaries = true
		local report = solver.solve(root, viewport, o2)
		analyzed = `visits={report.work.childVisits}`
		--[[ 1,001 rather than 2,001, and the difference is worth stating because it is
			the two-offer fact C2's second slot exists for. An ANALYZE solve keeps the
			per-solve memo and the cross-solve store — only the serve and this memo are
			gated on `ctx.analyze` — so the arrange pass's second ask about `List` is
			answered without re-entering this loop, and the loop runs once over 1,000
			children plus the Screen's one. A FULL solve has neither, enters the loop
			TWICE at two different offers, and reads 2,001 (the viewport case above).
			Measured with a temporary per-edge census, both arms, and discarded. ]]
		expect(`{shipped} / {analyzed}`).toBe("visits=2 / visits=1001")
	end)
end)

describe("T13: the channels a skipped child owes", function()
	it("the offer channel survives a skipped child (row 1)", function()
		--[[ T7 FINDING 2, AS A PIN. A child that is ARRANGE-dirty but MEASURE-clean has
			its rect entry REBUILT, and that literal reads `ctx.offers` for its
			`offerW`/`offerH`. A nil there disarms both anchor arms for the life of the
			surface — not for a tick — so the skip writes the raw offer pair itself.

			The drive is the gate row's HEIGHT on the `coupled` arm: every row below it
			moves, so ~500 rows are arrange-dirty and measure-clean at once, and the memo
			skips every one of them. The pin reads the offers back out of the solve's own
			rect map, which is the exact table the next solve's anchor arm reads. ]]
		local out = {}
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, coupled = true })
			s.text(500, "warm")
			s.text(500, "x")
			s.height(GATE_ROW, 40)
			local rects = capture.result.rects
			for _, path in { "/S/List/R4", "/S/List/R500", "/S/List/R900" } do
				local e = rects[path]
				table.insert(out, `{path}={tostring(e ~= nil and e.offerW)}/{tostring(e ~= nil and e.offerH)}`)
			end
			s.dispose()
		end)
		expect(table.concat(out, " ")).toBe("/S/List/R4=1280/20020 /S/List/R500=1280/20020 /S/List/R900=1280/20020")
	end)

	it("...and the anchor arm downstream of it still skips 249 of 250 plates", function()
		--[[ THE SAME CHANNEL, ONE LEVEL FURTHER ON, and on the fixture the anchor arm was
			built for. `nameplates_scene` memoises too — an hp write leaves `visits=1` —
			and the anchor's own skip count is unmoved at its C3 value. Those two numbers
			in one block are the claim: the memo removed measure work inside the plates
			and did not cost the anchor a single skip. ]]
		local s = nameplates.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		s.hp(7, 0.4)
		s.hp(7, 0.5)
		local st = s.stats()
		expect(`visits={st.lastChildVisits} anchorSkipped={st.lastAnchorSkipped} measured={st.lastMeasured}`).toBe(
			"visits=1 anchorSkipped=249 measured=5"
		)
		s.dispose()
	end)

	it("a memoising stack inside a `ViewThatFits` candidate replays its CUTS (row 3)", function()
		--[[ THE ONE SERVED NUMBER WITH NO GEOMETRIC SHADOW, and the case the first
			version of this file did not have (review round 1, I-2). `mCuts[idx]` is the
			`ctx.fitCuts` delta a child's own measure produced. Nothing downstream reads
			it as geometry — it reaches the world through ONE test, `chosenCandidate`'s
			`local uncut = ctx.fitCuts == cutsBefore`, which asks whether a candidate
			would paint an ellipsis. Under-count it and a candidate that WILL be cut
			looks honest and wins.

			THE SHAPE IS WHAT MAKES IT REACHABLE, and two earlier attempts were vacuous.
			The candidate must be MEASURE-DIRTY so C2's node-resident serve refuses it
			and `contentSize` is actually entered (a clean candidate is served whole from
			its own two slots, and then C2 — not this memo — replays the cuts). Its
			CUTTING child must be clean, and it must be a CONTAINER rather than a `text`,
			because a `text` child is never skipped. So: a ladder whose rich rung is a
			VStack of rows, row 1 driven by a signal (the dirt), row 2 holding one
			unbroken word the 40px offer cannot hold (the clamp — a phrase would WRAP,
			which is not a cut). Row 2 is skipped on every tick after the first, and its
			cut has to come back from `mCuts`.

			Measured: with `ctx.fitCuts += 0` in the skip arm the ladder picks the CUT
			rung (`Rich=40 Plain=0`) on two of the four drives while a full solve keeps
			`Plain`. Every drive is compared against that full-solve arm. ]]
		withWorkCapture(function()
			local a = fitsScene({})
			local c = fitsScene({ incremental = false, measureReuse = false })
			expect(`{a.chosen()} | {c.chosen()}`).toBe("Rich=0 Plain=20 Fallback=0 | Rich=0 Plain=20 Fallback=0")
			for step = 1, 4 do
				local solves = capture.solves
				-- the ground-truth arm is driven FIRST so the captured solve is arm `a`'s:
				-- the audited replay below re-solves it, and arm `c`'s opts carry no
				-- `reuse` at all, so replaying THAT would compare nothing and say so
				c.driveRow(20 + step)
				a.driveRow(20 + step)
				expect(`step {step}: solves={capture.solves - solves} {a.chosen()} | {c.chosen()}`).toBe(
					`step {step}: solves=2 Rich=0 Plain=20 Fallback=0 | Rich=0 Plain=20 Fallback=0`
				)
			end
			--[[ ...AND THE MEMO REALLY IS LIVE ON THE LADDER'S RUNG, which is what stops
				this being a case about `ViewThatFits` alone: after the first drive the rich
				rung's own loop asks about the ONE dirty row, where the full walk is six
				rows plus the ladder's own child. ]]
			expect(`visits={a.stats().lastChildVisits}`).toBe("visits=5")
			--[[ ...AND THE AUDIT ARM IS ASKED THE SAME QUESTION HERE, which is the only
				place in this file it can be asked at all: `mCuts` is the one recorded
				number with no geometric shadow, and the nine-view audited replay runs on
				fixtures where nothing truncates, so every `mCuts` there is legitimately
				zero and a corrupted recording is indistinguishable. This tree cuts. With
				the memo's cuts recorded as 0 the assert fires here — measured — and
				without the `mCuts` term in it, it does not. ]]
			local audited = table.clone(capture.opts)
			audited.containerMemoAudit = true
			local checked = solver.solve(capture.root, capture.viewport, audited)
			if checked.work.memoChecks < 1 then
				error(`the ladder's audited replay compared {checked.work.memoChecks} memo entries`, 0)
			end
			a.dispose()
			c.dispose()
		end)
	end)

	it("a `shrinkWeight` ARRIVING on a container that already memoised (row 4, restated)", function()
		--[[ REVIEW ROUND 3, SHOULD-FIX 3. `memoable = false` does NOT clear `hit`: on the
			tick the weight arrives the key still matches, so the memo IS hit and PASS 1.5
			runs over a partly memo-served `mainSum`. That is exact — a served number is
			the number this loop would have produced for that index — and the tick reads
			`visits=2`: the row whose weight changed is measure-dirty and asked, the other
			999 are served, and the shrink pass then rebases the sum they contributed.

			What makes the NEXT tick safe is the tail that drops the key: `visits=1001`
			from then on, forever, because a container with a live weight can never record
			again. Without that line the memo would hit on numbers PASS 1.5 has rebased —
			which is mutation 4. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, shrinkLater = true })
			s.text(500, "warm")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe("solves=1 calls=9 served=2 measured=5 visits=3")
			expect(drove(function()
				s.shrinkOn(1)
				--[[ RE-RECORDED 2026-09-06 (Plan D, D5): `served` 999 -> 1,001, `measured` 8 -> 6.
				Two of the nodes this tick re-measured were a container the arrange pass
				re-asked at the offer its own measure pass had just answered, which is what
				the within-solve arm now serves. `visits=2` — the claim of the case — is
				unmoved, and so is the tail below. ]]
			end)).toBe("solves=1 calls=1008 served=1001 measured=6 visits=2")
			expect(drove(function()
				s.text(500, "z")
			end)).toBe("solves=1 calls=1007 served=1001 measured=5 visits=1001")
			s.dispose()
		end)
	end)
end)

describe("T13: the container's own offer is half the key", function()
	it("the container's vertical PADDING moves what its clean children are offered (`mOffH`)", function()
		--[[ THE HEIGHT HALF OF THE OFFER KEY, WITNESSED (review round 1, M-5). The first
			version of this task recorded `mOffH` as an unreachable null: inside
			`contentSize` the offered height is the PARENT's, never narrowed by the node's
			own height the way `innerMaxW` is by its own width, so no drive in the repo
			moved it without a full solve.

			A CONTAINER'S OWN VERTICAL PADDING DOES. `innerMaxH` is `maxH - pt - pb`, and
			padding is measure-classed dirt on the container ALONE — so every child stays
			clean while the question they were recorded under changes. The gate row is a
			vertically-wrapping stack, whose measured WIDTH is a function of the offered
			HEIGHT: without a child that READS the offer, serving a stale answer produces
			the same number and the term is unfalsifiable.

			Measured with the term dropped: the snapshot diverges from a full solve at
			pads 350 and 355 — the offer crosses the point where the four boxes stop
			fitting in one column — and `visits` reads 1 where the shipped key reads 13. ]]
		local a = scene.new({ rows = 12, listPad = true, coupledRow = true })
		local c = scene.new({ rows = 12, listPad = true, coupledRow = true, incremental = false, measureReuse = false })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the incremental arm diverged from a FULL solve`, 0)
			end
		end
		a.text(5, "warm")
		c.text(5, "warm")
		a.text(5, "x")
		c.text(5, "x")
		agree("text")
		expect(`visits={a.stats().lastChildVisits}`).toBe("visits=2")
		for _, pad in { 340, 350, 355, 300 } do
			a.listPad(pad)
			c.listPad(pad)
			agree(`pad {pad}`)
			-- the memo REFUSED at the new offer and refilled: a full walk of the twelve
			-- rows plus the Screen's one child, every tick the offer moves
			expect(`pad {pad}: visits={a.stats().lastChildVisits}`).toBe(`pad {pad}: visits=13`)
		end
		a.dispose()
		c.dispose()
	end)
end)

describe("T13: the index is not the identity", function()
	--[[ OWED ROW 9. Both cases below compare against a FULL-SOLVE arm driven in
		lockstep, because the question is not "did the counters move" — it is "did any
		rect change", and only a ground-truth arm can answer that. `scene.snapshot()` is
		every live node's stored rect, hit rect, scroll region, visibility, adapter
		props, both public readers and `controller.diagnostics()`. ]]
	local function pair(opts: any): (any, any)
		local a = scene.new(opts)
		local c = table.clone(opts)
		c.measureReuse = false
		c.incremental = false
		return a, scene.new(c)
	end

	it("a ForEach sibling insert shifts every later index and the memo refuses", function()
		--[[ THE FIXTURE THE ID KEY EXISTS FOR. The region is `List`'s FIRST child, so an
			insert into it shifts every row's index in the layout node's spliced flat list
			— while `List`'s own MOUNT children table, the one the carrier gate compares by
			identity, is untouched. `prior.kids == node.children` HOLDS throughout, which
			is the point: an index-keyed memo would pass its own gate and serve a number
			belonging to a different node.

			The counters say the memo refused (a full walk on the insert and on the remove,
			1,004 and 1,003 — the extra visits are the region's own items), and the
			snapshot says nothing moved. ]]
		local a, c = pair({ rows = ROWS, foreach = true })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the incremental arm diverged from a FULL solve`, 0)
			end
		end
		a.text(500, "warm")
		c.text(500, "warm")
		agree("warm")
		a.text(500, "x")
		c.text(500, "x")
		agree("text")
		expect(`visits={a.stats().lastChildVisits}`).toBe("visits=2")
		a.insertItem("i0")
		c.insertItem("i0")
		agree("insert")
		expect(`visits={a.stats().lastChildVisits}`).toBe("visits=1004")
		a.text(500, "y")
		c.text(500, "y")
		agree("text after insert")
		expect(`visits={a.stats().lastChildVisits}`).toBe("visits=2")
		a.removeItem("i0")
		c.removeItem("i0")
		agree("remove")
		expect(`visits={a.stats().lastChildVisits}`).toBe("visits=1003")
		a.dispose()
		c.dispose()
	end)

	it("the SAME PATH with different content is refused one level up, not by the key", function()
		--[[ WHAT `child.id` IS NOT. It is `node.path`: stable across a rebuild and unique
			among siblings, but not an identity — remove a keyed row and re-add it in
			another form and the reconciler destroys and re-creates at the identical path,
			with a genuinely different measured size (a 24x8 box becomes a text). The
			memo's key cannot tell those apart and does not try.

			WHAT REFUSES IT is that both ticks are STRUCTURAL, and a structural solve
			widens `measureContains` to the whole `dirtyContains` set, so the re-created
			child is measure-dirty and the skip arm never fires for it. This case is that
			claim under a full-solve oracle: if the widening ever narrowed, the box's old
			extent would be served for the text and the snapshot would say so. ]]
		local a, c = pair({ rows = 24, foreach = true })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the incremental arm diverged from a FULL solve`, 0)
			end
		end
		a.text(5, "warm")
		c.text(5, "warm")
		agree("warm")
		a.removeItem("i1")
		c.removeItem("i1")
		agree("removed")
		a.insertItemKind("i1", "text")
		c.insertItemKind("i1", "text")
		agree("re-created at the same path, as a different kind")
		-- ...and it really is a different measured extent, so the case is not vacuous
		expect(string.find(a.snapshot(), "/S/List/F/[i1]/Item|0,0,15,15", 1, true) ~= nil).toBe(true)
		a.dispose()
		c.dispose()
	end)
end)

--[[ THE ORACLE'S ARMS, and they are `measure_serve`'s: `a` is the shipped
	configuration, `b` throws the cross-solve measure SLATES away and keeps the
	incremental arrange — the arm where the container memo is the only cross-solve
	measure mechanism left, and therefore the arm a wrong skip shows up in first — and
	`c` forces a FULL solve every refresh, where `ctx.reuse` is nil and the memo is
	structurally unreachable. `c` is the ground truth. ]]
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

--[[ ORACLE_ROWS, and the reasoning is `measure_serve`'s: the tree SHAPE is what the
	memo's correctness depends on — one stack, N identical rows, one of them carrying
	the gate shape — and that shape is per-row identical, so a small N exercises every
	branch a thousand does while a snapshot of 3,002 nodes across 3 arms x 9 views x 6
	fixtures is a suite this repository would stop running. The COUNT pins above run at
	the full 1,000, which is where a per-row cost would show. ]]
local ORACLE_ROWS = 12

describe("T13 oracle: byte-equal to a full solve, every view, every drive kind", function()
	local FIXTURES: { any } = {
		{ name = "plain", rows = ORACLE_ROWS },
		{ name = "nested", rows = ORACLE_ROWS, nested = true },
		{ name = "fill", rows = ORACLE_ROWS, fill = true },
		{ name = "shrink", rows = ORACLE_ROWS, shrink = true },
		{ name = "label", rows = ORACLE_ROWS, label = true },
		{ name = "foreach", rows = ORACLE_ROWS, foreach = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects and the public readers survive the memo`, function()
			for _, view in device_views.VIEWS do
				--[[ THE CAPTURE IS ARMED FOR THE WHOLE VIEW, so the audited replay below
					replays arm `a`'s LAST solve — the one the final `agree` just checked.
					Arms `b` and `c` solve inside the same window and would overwrite it,
					so the three arms are driven in a fixed order and `a` is driven last
					on the final step. ]]
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
					a.text(step + 1, `t{step}`)
					b.text(step + 1, `t{step}`)
					c.text(step + 1, `t{step}`)
					agree(`text {step}`)
					a.width(step + 1, 200 + step * 20)
					b.width(step + 1, 200 + step * 20)
					c.width(step + 1, 200 + step * 20)
					agree(`width {step}`)
					-- the gate row itself, so every arm drives the node its shape hangs on
					a.text(GATE_ROW, `g{step}`)
					b.text(GATE_ROW, `g{step}`)
					c.text(GATE_ROW, `g{step}`)
					agree(`gate-row text {step}`)
					a.viewport(view.w - step, view.h - step)
					b.viewport(view.w - step, view.h - step)
					c.viewport(view.w - step, view.h - step)
					agree(`viewport {step}`)
				end
				--[[ ...AND THE SECOND PASS, AUDITED (the brief's step 6; review round 1's
					M-3 recorded its absence as a scope deviation). The audit is a SOLVER
					opt (ruling L-4), so a mounted arm cannot turn it on — but the solve an
					arm just ran can be REPLAYED with it. One more drive on arm `a` alone,
					captured, then re-solved with `containerMemoAudit = true`: that forces
					the full walk and makes every container compare its memoised numbers —
					`mMain`, `mCross` and `mCuts` — against the real ones, inside the
					solve, at this fixture and this viewport. `b` and `c` take the same
					drive afterwards (outside the capture window, so the captured solve
					stays arm `a`'s) and the snapshot is compared again. The guard is the
					`childVisits` pair: equal numbers would mean the replay asserted
					nothing. ]]
				a.text(2, "audit-warm")
				b.text(2, "audit-warm")
				c.text(2, "audit-warm")
				agree("audit warm-up")
				withWorkCapture(function()
					a.text(2, "audit")
				end)
				b.text(2, "audit")
				c.text(2, "audit")
				agree("audit drive")
				local audited = table.clone(capture.opts)
				audited.containerMemoAudit = true
				local checked = solver.solve(capture.root, capture.viewport, audited)
				--[[ THE GUARD IS THE AUDIT'S OWN COUNTER, NOT A PROXY. `childVisits` was
					tried and is unsound here: a REPLAY is a second solve over the same
					tree, so C2's node slots are warm and the audited pass can enter FEWER
					containers than the plain one — the guard read "asserted nothing" on
					two fixtures where the audit was in fact running. `memoChecks` counts
					the comparisons themselves. A shape that records nothing (the `shrink`
					fixture, whose weight takes its container out of the memo) legitimately
					reads zero, which is why the minimum is asked per fixture. ]]
				local floor = if fixture.name == "shrink" then 0 else 1
				if checked.work.memoChecks < floor then
					error(
						`{label}: the audited pass compared {checked.work.memoChecks} memo entries, `
							.. `expected at least {floor}`,
						0
					)
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)

describe("T13 oracle: the memo checks its own arithmetic on EVERY container", function()
	--[[ THE FORCED-ON ARM (ruling A-12 as routed by ruling L-4). The differential above
		compares OUTPUT, so it can only catch a wrong number that reaches a rect — and a
		memo's whole purpose is to be invisible. This arm makes the memo compute its
		answer AND the real one and assert they are equal, on every container it touches,
		with no gate weakened.

		ITS ROUTE IS THE SOLVER'S OWN OPTS, NEVER AN ATTACH OPT. `containerMemoAudit`
		reaches `ctx.memoAudit` through `solve_ctx.new` exactly as `analyzeBoundaries`
		does; `renderer`'s `ATTACH_OPTS_KEYS` and its public `MountOpts` are untouched,
		which is what keeps a test-only switch off the public surface. The price, stated:
		this arm drives hand-captured solves rather than the 9-view mount fuzz, so its
		trees are the ones the capture below reaches.

		NON-VACUITY IS THE `visits` PAIR. With the audit ON the skip never fires, so the
		audited solve walks every child (2,001) where the plain one walks 2 — and every
		one of those forced walks whose child WOULD have been skipped runs the assert.
		Equal numbers here would mean the arm asserted nothing. ]]
	it("re-solving the same inputs with the audit ON asserts every skip it would have taken", function()
		for _, view in device_views.VIEWS do
			withWorkCapture(function()
				local s = scene.new({
					rows = ROWS,
					viewport = { x = 0, y = 0, w = view.w, h = view.h },
				})
				s.text(500, "warm")
				s.text(500, "x")
				s.dispose()
			end)
			local root, viewport, opts = capture.root, capture.viewport, capture.opts
			local plain = solver.solve(root, viewport, opts)
			local audited = table.clone(opts)
			audited.containerMemoAudit = true
			local checked = solver.solve(root, viewport, audited)
			--[[ NON-VACUITY, ASKED OF THE AUDIT ITSELF (review round 1, I-3):
				`memoChecks` counts the comparisons the audit made. The `childVisits` pair
				beside it is the second half of the same statement — the plain replay
				serves where the audited one walks — and is kept because it is what says
				the memo was LIVE on this tree rather than merely present. ]]
			if checked.work.memoChecks < 900 then
				error(`{view.id}: the audit compared only {checked.work.memoChecks} memo entries`, 0)
			end
			if plain.work.childVisits >= checked.work.childVisits then
				error(
					`{view.id}: the audit arm asserted nothing — plain={plain.work.childVisits} `
						.. `audited={checked.work.childVisits}`,
					0
				)
			end
			-- ...and the two solves agree on every rect, which is the audit's own claim
			-- read from the outside
			for id, entry in plain.rects do
				local other = (checked.rects :: any)[id]
				local r, o = entry.rect, if other ~= nil then other.rect else nil
				if o == nil or r.x ~= o.x or r.y ~= o.y or r.w ~= o.w or r.h ~= o.h then
					error(`{view.id}: {id} moved between the plain and audited solves`, 0)
				end
			end
		end
	end)

	it("...and the audit arm reaches every gate shape, with a ground truth per shape", function()
		--[[ REWRITTEN (review round 1, I-3). The first version asserted
			`expect("visits>0").toBe("visits>0")` — a literal compared with itself, the
			"check that proves nothing" class — and `childVisits < 100`, which 120 rows
			satisfy whether the memo was ever armed. It carried no plain-vs-audited pair
			and compared no rects, so an edit that broke the arithmetic on exactly the
			four shapes it exists to cover would pass it silently.

			IT NOW ASKS THREE THINGS PER SHAPE. (1) The plain replay really is memoising:
			`plain.childVisits` is far below the audited walk, which is the non-vacuity
			guard the case above uses and this one lacked. (2) The audited replay walks
			every child, which is what makes the per-container assert run at all. (3) A
			GROUND TRUTH: a third solve with `reuse` and `measures` removed, where both
			the memo and C2's serve are structurally unreachable, compared rect by rect
			against the memoised one. That is the arm `c` of this file's mount-level
			oracle, taken at the direct-solve level so it can be asked of a captured solve
			the audit is also asked of. ]]
		for _, opts in
			{
				{ rows = 120, fill = true },
				{ rows = 120, shrink = true },
				{ rows = 120, nested = true },
				{ rows = 120, foreach = true },
			}
		do
			local label = if opts.fill
				then "fill"
				elseif opts.shrink then "shrink"
				elseif opts.nested then "nested"
				else "foreach"
			withWorkCapture(function()
				local s = scene.new(opts)
				s.text(50, "warm")
				s.text(50, "x")
				s.dispose()
			end)
			local root, viewport = capture.root, capture.viewport
			local plain = solver.solve(root, viewport, capture.opts)
			local audited = table.clone(capture.opts)
			audited.containerMemoAudit = true
			local checked = solver.solve(root, viewport, audited)
			--[[ NON-VACUITY PER SHAPE, and the `shrink` row is the one that made a
				`childVisits` guard unusable: a `shrinkWeight > 0` child takes its whole
				container out of the memo, so that shape records nothing, compares nothing
				and legitimately walks the same children twice. Its claim is the
				ground-truth compare below; the other three must actually have compared. ]]
			local floor = if opts.shrink then 0 else 1
			if checked.work.memoChecks < floor then
				error(
					`{label}: the audit compared {checked.work.memoChecks} memo entries, `
						.. `expected at least {floor}`,
					0
				)
			end
			--[[ ...AND THE GROUND TRUTH. `reuse` nil is the whole mechanism gone: no
				memo (its gate asks for `ctx.reuse` first), no node-resident serve, no
				cross-solve store. Every rect the memoised solve produced has to be this
				solve's rect. ]]
			local truth = table.clone(capture.opts)
			truth.reuse = nil
			truth.measures = nil
			local c = solver.solve(root, viewport, truth)
			local compared = 0
			for id, entry in c.rects do
				local other = (plain.rects :: any)[id]
				local r, o = entry.rect, if other ~= nil then other.rect else nil
				if o == nil or r.x ~= o.x or r.y ~= o.y or r.w ~= o.w or r.h ~= o.h then
					error(`{label}: {id} differs from a solve with no reuse at all`, 0)
				end
				compared += 1
			end
			if compared < 100 then
				error(`{label}: the ground-truth compare only saw {compared} rects`, 0)
			end
		end
	end)
end)
