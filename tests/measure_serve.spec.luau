--!strict
--[[ C2 — A CLEAN NODE ANSWERS FROM ITS OWN LAST ANSWER, AND NEVER REACHES THE MEMO.

	`measure`'s per-solve memo is cheap but it is not free: a hit costs a
	`{maxW}|{maxH}|{scopeKey}` string, a `measureReuse.adopt` (a slate lookup and, on
	a refusal, a fresh table), and a hash probe into the per-node slate. On a dirty
	path every CLEAN SIBLING pays that bill to be told the answer it gave last solve.
	The serve is the shortest path through `measure`: a node with nothing
	MEASURE-classed dirty inside it, asked the same question it answered last time
	against the same scope, answers from numbers on itself and returns before the
	memo exists.

	THE FIXTURE IS A STACK, NOT AN ANCHOR, AND THAT IS THE POINT.
	`tests/lib/nameplates_scene` is one `anchor` with 250 children, whose
	per-sibling bill the anchor arrange arm already serves from each child's previous
	RECT. A `vstack` can have no such arm: a stack child's rect is a function of every
	sibling's measured extent (`fixedMain`, `fillWeightSum`, then the cursor), so the
	only thing that can be served on a stack path is the MEASURE, one node at a time.
	`tests/lib/deep_stack_scene` is 1,000 rows under one stack for exactly that
	reason.

	TWO SLOTS PER NODE, AND THE ONE-SLOT VERSION WAS BUILT, MEASURED AND REJECTED.
	The plan specified a single last-answer tuple. Almost every node in a real tree
	is measured at TWO offers per solve — the measure pass hands a container's own
	offer down, the arrange pass hands the RESOLVED inner box down, and they differ
	whenever a container does not fill what it was offered, which is most of them — so
	one slot thrashes between the two and answers neither. Measured on FacetBench at
	L, with the whole mechanism otherwise identical:

	  | workload             | served / calls, one slot | two slots      | class p50 |
	  |----------------------|--------------------------|----------------|-----------|
	  | `battle_hud`         | 0 / 2,257                | 2,246 / 2,249  | +5 % -> -7 % |
	  | `war_room_inventory` | 0 / 2,951                | 2,940 / 2,955  | +5 % -> -4 % |
	  | `killfeed_nameplates`| 0 / 667 (99 over a run)  | 664 / 667      | +5 % -> -4 % |

	The one-slot build was a 5-8 % REGRESSION on all three, and it was green on every
	count pin in this file, because this file's own fixture is one of the few shapes
	where a node IS asked at one offer: `List` is `fill`-width, so its inner width
	equals its offer. A fixture chosen to demonstrate a mechanism cannot also be the
	evidence that the mechanism pays, and the arena workloads are what said so.

	A THIRD SLOT IS NOT INDICATED: two buys 98.6-99.0 %, and the probe that measured
	it (a two-entry LRU over `{maxW}|{heightKey}|{scopeKey}`) is the shape that
	shipped.

	"THE SAME QUESTION" IS NOT "THE SAME TWO NUMBERS". A stack offers each child the
	height REMAINING after its siblings during the measure pass and the RESOLVED
	content height during the arrange pass, so a row on this fixture is asked at 720,
	then at 158, then at 720 again: an offer test that compared both numbers served 1
	call out of 45 (measured on the pre-fix build). The serve asks `memoPlan` the same
	question the memo's cache key asks — can this node's answer READ the offered
	height? — and drops `maxH` from the key when it cannot. One classification with
	one rule, not a second predicate beside it.

	WHAT THE SLOTS COST IN MEMORY, MEASURED. Twenty-one `m*` fields land in a layout
	node's hash part, and only for nodes a reuse solve actually measures. On this
	file's 1,000-row fixture (3,002 layout nodes, ~2,000 of them text), mount plus
	three drives, `collectgarbage("count")` read at the end — Lune 0.10.4 has no
	`"collect"`, so this is an ALLOCATION snapshot including garbage rather than a
	retention figure, and the median of three runs is what is quoted:

	  | build | heap delta |
	  |---|---:|
	  | pre-task `d4316f53` | 35,583 KB |
	  | with the two slots   | **34,457 KB (−3.2 %)** |

	It is NEGATIVE — the measures the serve does not run allocate more than the
	fields cost. The one thing that is genuinely RETAINED is the pair of
	`m*TextFacts`/`m*TextState` references on each TEXT node: two slots x two
	references x ~2,000 text nodes here. They are references to tables the measure
	store's own slate already holds, so they extend a lifetime rather than duplicate
	a payload, and a rebuilt node drops both.

	=====================================================================
	THE PUBLISH TABLE — every channel `measure` publishes, with its verdict
	=====================================================================

	The serve republishes THREE of them and REFUSES to run whenever any of the eight
	it cannot carry could be live. Six more are named because they are reachable from
	`measure` and an omitted channel is exactly the enumeration failure this table
	exists to prevent. The campaign's copy of it is the SDD ledger, under
	"### Task 6 — the owed list".

	  1  `ctx.offers[wKey]`/`[hKey]`            SERVED — from the offer in hand
	  2  `ctx.textStates`/`compact`/`textFacts` SERVED — from the node's own tuple
	  3  `ctx.fitCuts +=`                       SERVED — the slot's cut delta
	  4  `ctx.compositions[node.id]`            GATED  — `subtreeHasComposition`; it
	                                                     feeds the PUBLIC
	                                                     `controller.compositionAt`
	  5  `ctx.hasScroll`                        GATED  — `subtreeHasScroll`
	  6  `armContainer` -> `ctx.scopeKey`       GATED  — the two booleans plus
	                                                     `containerRelativeInside`
	  7  `ctx.boundary[node.id]`                GATED  — `ctx.analyze`
	  8  the diagnostics replay, and every      GATED  — `ctx.measureQuiet`, the
	     measure-time finding the served                 anchor arm's fourth gate,
	     SUBTREE would file                               for the same reason
	  9  `measureReuse.note`                    NOT SERVED — a store HIT COUNTER; a
	                                                     served call is not a hit
	 10  `ctx.measureCache[node]`               NOT SERVED — a per-solve convenience
	 11  `ctx.mdepth` / `ctx.deepNesting`       BALANCED BY CONSTRUCTION — the serve
	                                                     returns before both
	 12  `ctx.memoPlans[node]`                  WRITTEN BY THE SERVE — `heightFree`
	                                                     asks `memoPlan`, the ONE
	                                                     classification of "can this
	                                                     answer read the offered
	                                                     height", memoised per node
	                                                     per solve. The serve needs
	                                                     the same answer the memo's
	                                                     own cache key needs
	 13  `ctx.flowLines` / `ctx.gridPlan`       NOT SERVED, SELF-HEALING — keyed by
	                                                     the BOX and derived by
	                                                     whichever pass misses
	 14  `measureReuse.adopt`'s slate reset     NOT REACHED — the serve's gate is a
	                                                     superset of `reusable`, so
	                                                     `adopt` would have written
	                                                     nothing anyway
	 15  `ctx.measured`                         NOT INCREMENTED, by design
	 16  `ctx.scopeKey`'s three non-argument    SERVED BY KEY — the slot's `mScope`
	     inputs (`hiddenDepth`, the container,
	     `fitProbe`)
	 17  `candidate.choose`'s `ctx.fitCuts =`   INSIDE ROW 3 — it is a SET, and
	                                                     `record` stores a DELTA

	ROW 16 IS NOT IN THE PLAN'S TABLE AND IT IS THE ROW THAT MAKES THE SERVE CORRECT
	RATHER THAN NEARLY CORRECT. A `ViewThatFits` fit probe measures the same node at
	the same `(maxW, maxH)` with the measure-side shrink pass SUPPRESSED
	(`solver.setFitProbe`, ruling 2) — a different answer under an identical
	argument list. Without the scope in the key, the probe's answer would be served
	to the winner's real measure one call later, INSIDE the same solve. `hiddenDepth`
	and the container ride the same string for the same reason the memo's own key
	carries all three.

	ROWS 4 AND 5 ARE SELF-INCLUSIVE BOOLEANS, and that is an argument rather than a
	convenience: `ctx.hasScroll` is set for the scroll node ITSELF and
	`ctx.compositions[node.id]` is written for the composition node itself, so a
	child-only OR would leave the OWNER of each channel ungated and a served
	ScrollView would drop its own publish.

	AND THE ANCHOR BRANCH'S `anchorReused` ARM STAYS AS IT IS. It is now a special
	case of this serve — an anchor CHILD served from the parent's previous rect,
	gated on the same `measureContains` + same-offer + `measureQuiet` conditions —
	but it serves from `reuse.previous.rects` rather than from the node, fires one
	frame up the stack (the parent never calls `measure` for that child at all) and
	is pinned by `tests/anchor_arrange.spec.luau`, `tests/translate_arm.spec.luau`
	and RascalRally's own contract. Deleting it would be a second measurement, not a
	simplification. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")
local scene = require("./lib/deep_stack_scene")
local device_views = require("./lib/device_views")
local solver = require("../src/layout/solver")
local layout_node = require("../src/render/layout_node")
local themeSnapshot = require("../src/themes/snapshot")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local customFactory = require("../src/core/custom")
local text_metrics = require("../src/layout/text_metrics")

local ROWS = 1000
local GATE_ROW = scene.GATE_ROW

--[[ ONE DRIVE, AND WHAT IT COST — the whole assertion in one string, in the shape
	`tests/anchor_arrange.spec.luau` established and for the reason its header gives:
	a drive that solves ZERO times silently re-asserts the previous solve's counters,
	so `solves=N` is part of every pin rather than a side condition. The wrapper also
	keeps the OPTIONS, because `opts.reuse == nil` is the difference between "the
	serve declined" and "there was no serve to decline", and the two produce the
	identical `served=0`. ]]
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
	return `solves={n} calls={w.measureCalls} served={w.measureServed} measured={w.measured}`
end

local function lastSolveWasIncremental(): string
	local opts = capture.opts
	return `reuse={tostring(opts ~= nil and (opts :: any).reuse ~= nil)}`
end

describe("C2: one changed row does not re-measure 999 clean siblings", function()
	it("a text write on ONE leaf serves every clean row from its own tuple", function()
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			-- one warm-up drive is discarded: the FIRST refresh after `initialRender`
			-- has no tuples to serve from, because nothing has recorded one yet
			s.text(500, "warm")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe(`solves=1 calls=2005 served=1999 measured=5`)
			s.dispose()
		end)
	end)

	it("...and the SERVE is what removes the calls: with it disarmed the same drive walks the tree", function()
		--[[ THE BEFORE COLUMN, measured on THIS build rather than remembered from the
			last one. `measureQuiet` is the cheapest honest disarm: it is one of the
			serve's own gates, it is read once per solve, and it disarms nothing else in
			the solver — the anchor arm has no anchor on this fixture.

			THE TWO ARMS DIFFER BY ONE LEAF (`R1/Bad`, the aspect-on-both-axes box that
			makes the finding), so the number carrying the claim is `measured`: 5 with
			the serve, 2,003 without it. Every one of those 2,003 is a row or a label
			re-measured to be told the size it gave last solve — and 1,000 of them are
			`PLAN_SKIP` boxes, which never consult the memo at all and are therefore
			calls no cache in this file could ever have removed. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, unquiet = true })
			s.text(500, "warm")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe(`solves=1 calls=2005 served=0 measured=2003`)
			s.dispose()
		end)
	end)

	it("a WIDTH write on one row excludes that row, its ancestors AND its two children", function()
		--[[ the second of the serve's two same-question gates, and the one the dirty
			closure cannot state. A row's `width` moves the OFFER it makes to its
			children; the children are not in `measureContains` and are refused by
			the slot's own offer instead. A serve that only asked the dirt set
			would hand back a size measured against a width that no longer exists. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.width(500, 260)
			expect(drove(function()
				s.width(500, 240)
			end)).toBe(`solves=1 calls=2005 served=1998 measured=6`)
			s.dispose()
		end)
	end)

	it("the FIRST reuse solve after a full one records and serves nothing; the next one serves", function()
		--[[ THE TUPLE IS WRITTEN ONLY ON A SOLVE THAT COULD SPEND IT, which is the
			solver's purity contract and not an economy — see `record`. So this pair is
			the whole cost of that decision, said as a number.

			AND IT SHOWS THE SERVE HAS TWO HALVES, which no single-drive pin can. The
			first reuse solve after a full one has no tuples at entry and still serves
			999: those are the INTRA-SOLVE re-asks, where a stack's arrange pass asks
			for a size its own measure pass computed two frames of the recursion ago.
			The second solve serves 1,999 — the same 999 plus the cross-solve half.
			Halving the first number and near-eliminating the second is what the two
			mechanisms are worth separately. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			expect(drove(function()
				s.text(500, "first")
			end)).toBe(`solves=1 calls=2005 served=999 measured=1005`)
			expect(drove(function()
				s.text(500, "second")
			end)).toBe(`solves=1 calls=2005 served=1999 measured=5`)
			s.dispose()
		end)
	end)

	it("...and a FROZEN node tree still solves, which is what that decision protects", function()
		--[[ `solver.luau`'s first line promises a solve "over an immutable snapshot",
			and `tests/layout.spec.luau`'s purity case hands it a `table.freeze`d tree.
			A recorder that wrote unconditionally turned that promise into a hard error
			for every direct caller with one — `dump.fromSolve`, the layout fuzzer, a
			hand-built tree in a spec. It is pinned HERE as well as there, because the
			line that keeps it true lives in this task's own function. ]]
		local function deepFreeze(node: any): any
			for _, child in node.children or {} do
				deepFreeze(child)
			end
			return table.freeze(node)
		end
		local root = deepFreeze({
			kind = "vstack",
			id = "root",
			gap = 4,
			children = {
				{ kind = "text", id = "t", text = "hello", textSize = 16 },
				{ kind = "box", id = "b", width = { type = "fixed", px = 40 }, height = { type = "fixed", px = 20 } },
			},
		}) :: any
		local ok, err = pcall(function()
			return solver.solve(root, { w = 300, h = 200 }, { rootPolicy = "edgeToEdge" })
		end)
		expect(`ok={ok} err={if ok then "-" else tostring(err)}`).toBe("ok=true err=-")
	end)

	it("a TEXT-METRICS SETTLE disarms the serve for one solve — axis 3, the one no node can see", function()
		--[[ THE DEFECT THIS FIXES, and it is not hypothetical: the Roblox adapter
			answers the same measurement batch twice, up to ~12 s apart, and the second
			answer CORRECTS the first — same font, same size, same word, a different
			width. `measure_reuse`'s store reads that through its axis-3 stamp and
			clears. The node tuple OUTLIVES that clear, because the layout nodes are
			rebuilt only when the metrics or the two text scales move, and neither does
			here: a served label would keep the width it had before the correction, at
			an unchanged offer, under an unchanged theme, with a green suite. So the
			renderer threads the SAME string it re-stamps the store with, and the slot
			answers axis 3 the same way the slate does.

			Driven through `setMeasured` with a probe word no fixture in this suite
			measures, so the epoch moves and no geometry does — the counts below are
			the ordinary drive's, with the CROSS-SOLVE half of `served` gone: 1,999 ->
			999, exactly the intra-solve re-asks, which are recorded at the new stamp
			inside this very solve and are therefore not stale. A serve that answered
			axis 3 by disarming wholesale would read 0 here and be paying for the
			settle twice. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			s.text(500, "warmer")
			text_metrics.setMeasured("BuilderSans", 21, "facet-t6-serve-probe", 41)
			expect(drove(function()
				s.text(500, "x")
			end)).toBe(`solves=1 calls=2005 served=999 measured=1005`)
			-- ...and the solve after it, at the settled epoch, serves the other half too
			expect(drove(function()
				s.text(500, "y")
			end)).toBe(`solves=1 calls=2005 served=1999 measured=5`)
			s.dispose()
		end)
	end)

	it("A HUGGING list asks every row TWO offers, and the SECOND SLOT is what answers", function()
		--[[ THE CASE THAT SAYS THE SECOND SLOT EXISTS, and the one whose absence let a
			one-slot build ship green through every other pin in this file. A `fill` list
			hands each row the same width in both passes — the default arm above — so it
			cannot tell one slot from two. A HUGGING list hands the screen's 1,280 down
			in the measure pass and its own resolved 300 in the arrange pass, which is the
			ordinary shape of real UI: on FacetBench's `battle_hud L` and
			`war_room_inventory L` the one-slot build served ZERO of 2,257 and 2,951 calls
			a frame and cost 5-8 %.

			Driven here rather than left to the arena: with the eviction pinned to one
			slot this reads `served=1 measured=2003`, and with two it reads the numbers
			below. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, hug = true })
			s.text(500, "warm")
			s.text(500, "warmer")
			expect(drove(function()
				s.text(500, "x")
			end)).toBe(`solves=1 calls=2005 served=1999 measured=5`)
			s.dispose()
		end)
	end)

	it("a clean node whose answer READS the offered height is refused when that offer moves", function()
		--[[ THE OTHER HALF OF THE OFFER TEST, as geometry rather than as a count. The
			gate row's wrapping VStack is `PLAN_KEYED` — a wrap's measured WIDTH is a
			function of the height it was offered — and moving the ROW's height dirties
			the row, never the child. So the child is clean, at a scope that has not
			moved, and only `node.lastOfferH == maxH` stands between it and a stale
			width. Four 20x10 boxes: one column at 46px of height, four at 18px. ]]
		local s = scene.new({ rows = 24, coupled = true })
		local function hc(): string
			local r = s.controller.rectOf(`/S/List/R{GATE_ROW}/HC`)
			return if r == nil then "-" else `{r.w}x{r.h}`
		end
		expect(hc()).toBe("80x18")
		s.height(GATE_ROW, 46)
		expect(hc()).toBe("20x46")
		s.height(GATE_ROW, 18)
		expect(hc()).toBe("80x18")
		s.dispose()
	end)

	it("a `containerRelative` node under a scroller is refused when its CONTAINER moves (row 6)", function()
		--[[ THE GATE `mAScope`/`mBScope` CANNOT COVER, and it is the one shape in this file
			that needs its own world. A `containerRelative` dimension resolves against the
			nearest scroll VIEWPORT, and the container joins `ctx.scopeKey` only once one
			has actually been MEASURED (`armContainer` arms late on purpose — arming up
			front kills the memo). A chain of serves is a chain of measures that never
			happen, so the arm never fires, the scope key stays the unarmed `"0"` on both
			solves and MATCHES — while the container underneath the node has moved.

			The drive is exact for that: the scroller's own height is a dynamic prop, so
			the scroller is measure-dirty and the node beneath it is not; and a y-scroller
			offers its children `math.huge` on the scroll axis in BOTH passes, so the
			offer test cannot see the change either, and `measure_reuse.adopt`'s axis 4 is
			the same question one layer down.

			WHAT ACTUALLY REFUSES IT IS THE SLOT'S SCOPE KEY, AND THE NULL RESULT IS
			RECORDED HERE RATHER THAN SMOOTHED OVER: deleting the serve's
			`containerRelativeInside` term leaves this case — and the whole suite —
			green, because `hasContainerRelative` is a per-solve LATCH armed inside
			`measureUncached`, so a node whose subtree arms it records an armed key and
			can never match the unarmed `"0"` a fresh solve starts from. The term is kept
			anyway: that equivalence holds only while the arm stays late, and
			`rebuildScopeKey`'s header calls arming late the difference between a live
			memo and a dead one — a thing a later round changes for reasons unrelated to
			this line. The case is the behaviour either way. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		local scrollH = core:signal(200)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "SV",
						axis = "y",
						width = { type = "fixed", px = 100 },
						height = core:memo(function(use: any)
							return { type = "fixed", px = use(scrollH) :: number }
						end),
						children = {
							UI.VStack({
								id = "Inner",
								children = {
									UI.Box({
										id = "CR",
										width = { type = "fixed", px = 20 },
										height = { type = "containerRelative", fraction = 0.5, axis = "h" },
									}),
								},
							}),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			incrementalLayout = true,
			measureReuse = true,
			layoutNodeReuse = true,
			commitScope = true,
		})
		controller.initialRender()
		local function crH(): string
			local r = controller.rectOf("/S/SV/Inner/CR")
			return if r == nil then "-" else tostring(r.h)
		end
		expect(crH()).toBe("100")
		scrollH:set(120)
		controller.refresh()
		expect(crH()).toBe("60")
		scrollH:set(300)
		controller.refresh()
		expect(crH()).toBe("150")
		controller.dispose()
		root.dispose()
	end)

	it("a `ViewThatFits` PROBE and the real measure of the same node get SEPARATE slots (row 16)", function()
		--[[ ROW 16, ISOLATED. `candidate.choose` measures a candidate with
			`ctx.fitProbe` on, which SUPPRESSES every squeezing mechanism — the `hug`
			cap here, and the measure-side shrink pass — so the same node at the same
			`(maxW, maxH)` answers differently inside the probe and outside it. That
			difference is not in the argument list: it rides `ctx.scopeKey`, exactly as
			it rides the memo's own cache key, and the slot key carries it for the same
			reason.

			THE SHAPE, and it took three attempts to find one that reaches this at all.
			The CHOSEN candidate cannot be the node: a candidate that wins is one whose
			ideal FITS, so nothing squeezes it and its two answers are equal. The
			fallback cannot be either — `candidate.choose`'s loop stops one short of it,
			so it is never probed. The node that is both probed and measured for real
			with two different answers is a DESCENDANT of a winning candidate: `Rich`
			is `fixed(400)` and fits, and its `hug`-width child `Inner` wants 900 and is
			capped to 400 outside the probe.

			WHAT THIS PINS IS THE SLOTS, not a rect, and that is deliberate. Under the
			mutation "drop the scope term from the slot key" the probe's 900 IS served
			to the real measure — the leak is real and reproducible — but every arranger
			downstream re-clamps a `hug` child to its box, so the painted tree is
			identical and arm `c` agrees. A pin on the rect would be a check that cannot
			fail. The slot state is where the claim lives, so that is what is read: two
			slots, ONE offer, TWO scopes, TWO answers. ]]
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 400 })
		local fitsH = core:signal(60)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.ViewThatFits({
						id = "Fits",
						width = { type = "fixed", px = 400 },
						-- the drive: it dirties `Fits` and NOTHING below it, so the
						-- candidate ladder re-runs over a clean subtree
						height = core:memo(function(use: any)
							return { type = "fixed", px = use(fitsH) :: number }
						end),
						children = {
							UI.VStack({
								id = "Rich",
								width = { type = "fixed", px = 400 },
								height = { type = "content" },
								padding = 0,
								gap = 0,
								children = {
									UI.HStack({
										id = "Inner",
										width = { type = "hug" },
										height = { type = "fixed", px = 40 },
										padding = 0,
										gap = 0,
										children = {
											UI.Box({
												id = "Big",
												width = { type = "fixed", px = 900 },
												height = { type = "fixed", px = 40 },
											}),
										},
									}),
								},
							}),
							-- the declared fallback, so `Rich` is a PROBED candidate
							UI.Box({
								id = "Plain",
								width = { type = "fixed", px = 50 },
								height = { type = "fixed", px = 20 },
							}),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, {
			rootPolicy = "edgeToEdge",
			incrementalLayout = true,
			measureReuse = true,
			layoutNodeReuse = true,
			commitScope = true,
		})
		controller.initialRender()
		local function innerNode(): any
			local found: any = nil
			local function walk(n: any)
				if n.id == "/S/Fits/Rich/Inner" then
					found = n
				end
				for _, c in n.children or {} do
					walk(c)
				end
			end
			walk(capture.root)
			return found
		end
		withWorkCapture(function()
			fitsH:set(61) -- warm: records both slots
			controller.refresh()
			expect(drove(function()
				fitsH:set(62)
				controller.refresh()
			end)).toBe("solves=1 calls=5 served=2 measured=3")
		end)
		local n = innerNode()
		assert(n ~= nil, "no `/S/Fits/Rich/Inner` layout node in the captured tree")
		--[[ ONE OFFER, TWO SCOPES, TWO ANSWERS. `0|fit` is `rebuildScopeKey`'s probe
			segment; the ideal 900 is what the `hug` cap is suppressed for, and 400 is
			the same node at the same offer with the cap in force. ]]
		expect(
			`A[{tostring(n.mAOfferW)},{tostring(n.mAScope)}]={tostring(n.mAW)}`
				.. ` B[{tostring(n.mBOfferW)},{tostring(n.mBScope)}]={tostring(n.mBW)}`
		).toBe("A[400,0|fit]=900 B[400,0]=400")
		-- ...and the painted answer is the capped one, which is what the two slots buy
		expect(`inner={(controller.rectOf("/S/Fits/Rich/Inner") :: any).w}`).toBe("inner=400")
		controller.dispose()
		root.dispose()
	end)

	it("a VIEWPORT change serves NOTHING, and it is unreachable rather than declined", function()
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			expect(drove(function()
				s.viewport(900, 640)
			end)).toBe(`solves=1 calls=5003 served=0 measured=5003`)
			expect(lastSolveWasIncremental()).toBe("reuse=false")
			s.dispose()
		end)
	end)
end)

describe("C2: the gate is what makes the serve legal", function()
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

	it("a ScrollView inside a clean row keeps that row off the serve (row 5)", function()
		expect(gateDrive({ rows = ROWS })).toBe(`solves=1 calls=2005 served=1999 measured=5`)
		expect(gateDrive({ rows = ROWS, scroll = true })).toBe(`solves=1 calls=2005 served=1997 measured=7`)
	end)

	it("a Composition inside a clean row does the same, and `compositionAt` still answers (row 4)", function()
		local out, key
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, composition = true })
			s.text(500, "warm")
			out = drove(function()
				s.text(500, "x")
			end)
			key = s.compositionKey(`/S/List/R{GATE_ROW}/Comp`)
			s.dispose()
		end)
		expect(out).toBe(`solves=1 calls=2005 served=1997 measured=7`)
		expect(key).toBe("column|/S/List/R3/Comp/Reg:0,0,60,10:main")
	end)

	it("an ANALYZE solve serves nothing — the boundary map is written in `measureUncached` (row 7)", function()
		--[[ driven by re-running the CAPTURED solve twice from the same inputs, once
			as it shipped and once with `analyzeBoundaries` on. `controller.analyzeBoundaries`
			clears `reuse` itself, so going through it would prove the FIRST gate and
			leave this one untested; the two arms below differ in exactly one option. ]]
		local shipped, analyzed
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			s.text(500, "x")
			s.dispose()
		end)
		local root, viewport, opts = capture.root, capture.viewport, capture.opts
		local plain = solver.solve(root, viewport, opts)
		shipped = `served={plain.work.measureServed}`
		local o2 = table.clone(opts)
		o2.analyzeBoundaries = true
		local report = solver.solve(root, viewport, o2)
		analyzed = `served={report.work.measureServed}`
		expect(`{shipped} / {analyzed}`).toBe("served=1999 / served=0")
	end)

	it("a solve whose PREDECESSOR filed a measure-time finding serves nothing (row 8)", function()
		expect(gateDrive({ rows = ROWS, unquiet = true })).toBe(`solves=1 calls=2005 served=0 measured=2003`)
	end)
end)

describe("C2: the two bottom-up booleans are SELF-INCLUSIVE", function()
	local function built(bp: any): { [string]: any }
		local core = customFactory.new()
		local root = mountLib.mount(core, bp)
		local store = layout_node.newStore(true, nil)
		local tree = layout_node.build(store, root.node, themeSnapshot.neutral(), 1, 0, nil)
		local byId: { [string]: any } = {}
		local function walk(n: any)
			byId[n.id] = n
			for _, c in n.children or {} do
				walk(c)
			end
		end
		walk(tree)
		root.dispose()
		return byId
	end

	local function flags(n: any): string
		return `scroll={tostring(n.subtreeHasScroll)} comp={tostring(n.subtreeHasComposition)}`
	end

	it("a `scroll` node reports the boolean about ITSELF, and so does every ancestor", function()
		local byId = built(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "L",
					children = {
						UI.ScrollView({ id = "SV", children = { UI.Box({ id = "In" }) } }),
						UI.Box({ id = "Sib" }),
					},
				}),
			},
		}))
		expect(flags(byId["/S/L/SV"])).toBe("scroll=true comp=nil")
		expect(flags(byId["/S/L"])).toBe("scroll=true comp=nil")
		expect(flags(byId["/S"])).toBe("scroll=true comp=nil")
		-- ...and the two nodes it must NOT reach: a sibling, and the scroller's child
		expect(flags(byId["/S/L/Sib"])).toBe("scroll=nil comp=nil")
		expect(flags(byId["/S/L/SV/In"])).toBe("scroll=nil comp=nil")
	end)

	it("...and a `composition` node reports its own, on the same walk", function()
		local byId = built(UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "L",
					children = {
						UI.Composition({
							id = "C",
							arrangements = { "column" },
							groups = { { id = "main", lane = "main", sizing = "fill" } },
							children = {
								UI.Region({ id = "R", group = "main", rank = 1, children = { UI.Box({ id = "In" }) } }),
							},
						}),
						UI.Box({ id = "Sib" }),
					},
				}),
			},
		}))
		expect(flags(byId["/S/L/C"])).toBe("scroll=nil comp=true")
		expect(flags(byId["/S/L"])).toBe("scroll=nil comp=true")
		expect(flags(byId["/S"])).toBe("scroll=nil comp=true")
		expect(flags(byId["/S/L/Sib"])).toBe("scroll=nil comp=nil")
	end)
end)

describe("C2: the slot lives on the layout node, and a rebuilt node has none", function()
	it("a node in `store.dirty` is a FRESH literal; a warm hit is the same table, tuple intact", function()
		--[[ THE WHOLE INVALIDATION ARGUMENT, in one drive. The serve reads
			`node.mAOfferW`/`mAW`/... off the layout node, so what makes a stale
			answer impossible is not a version stamp but the fact that a node whose props
			moved is a NEW TABLE — `toLayoutNode`'s literal, with every `m*` field
			absent. Anything less than a fresh table here and the serve would need an
			epoch of its own. ]]
		local core = customFactory.new()
		local width = core:signal({ type = "fixed", px = 40 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = { UI.VStack({ id = "L", children = { UI.Box({ id = "B", width = width }) } }) },
			})
		)
		local store = layout_node.newStore(true, nil)
		local metrics = themeSnapshot.neutral()
		local first = layout_node.build(store, root.node, metrics, 1, 0, nil)
		local function nodeOf(tree: any, id: string): any
			if tree.id == id then
				return tree
			end
			for _, c in tree.children or {} do
				local hit = nodeOf(c, id)
				if hit ~= nil then
					return hit
				end
			end
			return nil
		end
		local b1 = nodeOf(first, "/S/L/B")
		b1.mAOfferW, b1.mAW, b1.mAScope, b1.mStamp = 40, 40, "0", "stamp"
		-- nothing dirty: the store's warm-hit path returns `hit.built`, the SAME table
		local warm = layout_node.build(store, root.node, metrics, 1, 0, {})
		local b2 = nodeOf(warm, "/S/L/B")
		expect(`same={b2 == b1} offer={tostring(b2.mAOfferW)} scope={tostring(b2.mAScope)} stamp={tostring(b2.mStamp)}`).toBe(
			"same=true offer=40 scope=0 stamp=stamp"
		)
		--[[ ...and the node named in `dirty` is rebuilt, tuple and all. THE SET IS
			CLOSED OVER ANCESTORS, which is not tidiness: the store's warm-hit path
			returns `hit.built` for the whole subtree without descending, so a dirty
			leaf named alone is never REACHED. The renderer closes the set for exactly
			this reason (`render/dirty_closure`); a test that passed the leaf alone
			would be asserting the store's behaviour on an input it never receives, and
			it reads as a passing rebuild check while rebuilding nothing. ]]
		local rebuilt =
			layout_node.build(store, root.node, metrics, 1, 0, { ["/S"] = true, ["/S/L"] = true, ["/S/L/B"] = true })
		local b3 = nodeOf(rebuilt, "/S/L/B")
		expect(`same={b3 == b1} offer={tostring(b3.mAOfferW)} scope={tostring(b3.mAScope)} stamp={tostring(b3.mStamp)}`).toBe(
			"same=false offer=nil scope=nil stamp=nil"
		)
		root.dispose()
	end)
end)

describe("C2: what the solver writes onto a layout node is a CLOSED set of outputs", function()
	it("every `node.<field> =` in the solver is one of the enumerated memo fields", function()
		--[[ THE LICENCE FOR THE P3 NODE STORE USED TO BE "the solver never writes into a
			layout node" (`render/layout_node.luau`, the audit at the head of
			`toLayoutNode`). C2 made that false, and the replacement licence is three
			claims: the written fields are OUTPUTS — the last answers this node gave —
			never inputs the BUILD reads; a node whose props moved is a fresh literal; and
			the set is CLOSED. This case is the third claim, and it is the one a comment
			cannot make: a new `node.<field> =` in `solver.luau` that is not on this list
			is a fact the store would forward across solves without any axis invalidating
			it, and it reddens here rather than being discovered by a stale rect.

			The scan takes only ASSIGNMENT TARGETS — the comma-separated left-hand side at
			bracket depth zero — because `ctx.offers[node.wKey or (node.id .. "|w")] = maxW`
			has `node.wKey` and `node.id` on the left of an `=` while writing neither. A
			scan that missed that reported six fields where there are none. ]]
		local source = fs.readFile("src/layout/solver.luau")
		local stripped = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
		stripped = string.gsub(stripped, "\n[ \t]*%-%-[^\n]*", "\n")
		local function assignmentTargets(line: string): { string }
			-- the first `=` that is not part of `==`, `~=`, `<=` or `>=`
			local eq: number? = nil
			local i = 1
			while i <= #line do
				local ch = string.sub(line, i, i)
				if ch == "=" then
					local prev = string.sub(line, i - 1, i - 1)
					local next_ = string.sub(line, i + 1, i + 1)
					if next_ ~= "=" and prev ~= "=" and prev ~= "~" and prev ~= "<" and prev ~= ">" then
						eq = i
						break
					end
					i += 1
				end
				i += 1
			end
			if eq == nil then
				return {}
			end
			local out: { string } = {}
			local depth, cur = 0, ""
			for k = 1, (eq :: number) - 1 do
				local ch = string.sub(line, k, k)
				if ch == "(" or ch == "[" or ch == "{" then
					depth += 1
				elseif ch == ")" or ch == "]" or ch == "}" then
					depth -= 1
				end
				if ch == "," and depth == 0 then
					table.insert(out, cur)
					cur = ""
				else
					cur ..= ch
				end
			end
			table.insert(out, cur)
			return out
		end
		local written: { [string]: boolean } = {}
		for line in string.gmatch(stripped, "([^\n]*)") do
			for _, target in assignmentTargets(line) do
				local field = string.match(target, "^%s*node%.([%a_][%w_]*)%s*$")
				if field ~= nil then
					written[field] = true
				end
			end
		end
		local out: { string } = {}
		for field in written do
			table.insert(out, field)
		end
		table.sort(out)
		--[[ TWENTY-ONE, and every one is an OUTPUT: the two slots' keys and answers,
			the shared axis-3 stamp, the eviction toggle, and the cached `memoPlan`
			verdict. None is a field `layout_node.toLayoutNode` reads to BUILD a node,
			which is what keeps the P3 store's four axes complete. ]]
		expect(out).toEqual({
			"mACompact",
			"mACuts",
			"mAH",
			"mAOfferH",
			"mAOfferW",
			"mAScope",
			"mATextFacts",
			"mATextState",
			"mAW",
			"mBCompact",
			"mBCuts",
			"mBH",
			"mBOfferH",
			"mBOfferW",
			"mBScope",
			"mBTextFacts",
			"mBTextState",
			"mBW",
			"mFillB",
			"mHeightFree",
			"mStamp",
		})
		-- NEGATIVE CONTROL: the scan really does see a write, really does see a
		-- multiple assignment, and really does IGNORE a `node.` inside an index on the
		-- left of an `=`
		local fake = "\n\tnode.newThing = 1\n\tnode.a, node.b = 1, 2\n\tctx.offers[node.wKey or node.id] = maxW\n"
		local seen: { [string]: boolean } = {}
		for line in string.gmatch(fake, "([^\n]*)") do
			for _, target in assignmentTargets(line) do
				local field = string.match(target, "^%s*node%.([%a_][%w_]*)%s*$")
				if field ~= nil then
					seen[field] = true
				end
			end
		end
		local control: { string } = {}
		for field in seen do
			table.insert(control, field)
		end
		table.sort(control)
		expect(control).toEqual({ "a", "b", "newThing" })
	end)
end)

describe("C2: the recorder is called at EVERY return of `measure`", function()
	it("`#returns == #record( calls`, by source scan, with no stated exception", function()
		--[[ A NEW RETURN ADDED WITHOUT A RECORD IS A STALE TUPLE — the node would
			answer its NEXT caller with the answer before last. There is no way to check
			that behaviourally without knowing which return was added, so the rule is
			pinned on the source instead, as a plain equality: the serve's own return
			goes through `record` too (idempotently — it rewrites the same tuple), so
			there is no exception to remember and no `== n + 1` for a later edit to
			satisfy by adding another exception. ]]
		local source = fs.readFile("src/layout/solver.luau")
		local stripped = string.gsub("\n" .. source, "%-%-%[%[.-%]%]", " ")
		stripped = string.gsub(stripped, "\n[ \t]*%-%-[^\n]*", "\n")
		local body = string.match(stripped, "\nmeasure = function%(ctx: Ctx.-\nend\n")
		assert(body ~= nil, "could not isolate `measure`'s body")
		local returns, records = 0, 0
		for _ in string.gmatch(body :: string, "%f[%w]return%f[%W]") do
			returns += 1
		end
		for _ in string.gmatch(body :: string, "record%(") do
			records += 1
		end
		expect(`returns={returns} records={records}`).toBe("returns=7 records=7")
		-- NEGATIVE CONTROL: both scans really read what they claim to
		local fake = "\nmeasure = function(ctx: Ctx)\n\tif a then\n\t\treturn 1\n\tend\n\treturn record(x)\nend\n"
		local fakeBody = string.match(fake, "\nmeasure = function%(ctx: Ctx.-\nend\n") :: string
		local fr, fc = 0, 0
		for _ in string.gmatch(fakeBody, "%f[%w]return%f[%W]") do
			fr += 1
		end
		for _ in string.gmatch(fakeBody, "record%(") do
			fc += 1
		end
		expect(`returns={fr} records={fc}`).toBe("returns=2 records=1")
	end)
end)

--[[ THE ORACLE'S ARMS. `a` is the shipped configuration, `b` throws the cross-solve
	measure slates away but keeps the incremental arrange — the arm where the node
	tuple is the ONLY cross-solve measure mechanism left, and therefore the arm a
	wrong serve shows up in first — and `c` forces a FULL solve every refresh, where
	`ctx.reuse` is nil and the serve is structurally unreachable. `c` is the ground
	truth. The channel compared is `scene.snapshot()`: every live node's stored rect,
	hit rect, scroll region, visibility, adapter props, the two PUBLIC readers and
	the `pos == sro` identity, plus `controller.diagnostics()` as one key. ]]
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

--[[ ORACLE_ROWS, and the reasoning is `tests/measure_split.spec.luau`'s: the tree
	SHAPE is what the serve's correctness depends on — one stack, N identical rows,
	one of them carrying the gate shape — and that shape is per-row identical, so a
	small N exercises every branch 1,000 does while a snapshot of 3,002 nodes across
	3 arms x 9 views x 4 drive kinds is a suite this repo would stop running. The
	COUNT pins above run at the full 1,000, which is where a per-row cost would show
	up; this half of the file is about equality. ]]
local ORACLE_ROWS = 12

describe("C2 oracle: byte-equal to a full solve, every view, every drive kind", function()
	local FIXTURES: { any } = {
		{ name = "plain", rows = ORACLE_ROWS },
		{ name = "scroll", rows = ORACLE_ROWS, scroll = true },
		{ name = "composition", rows = ORACLE_ROWS, composition = true },
		{ name = "unquiet", rows = ORACLE_ROWS, unquiet = true },
		{ name = "coupled", rows = ORACLE_ROWS, coupled = true },
		{ name = "hug", rows = ORACLE_ROWS, hug = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, verdicts and the public readers survive the serve`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				local compKey = `/S/List/R{GATE_ROW}/Comp`
				local function agree(step: string)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {step} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= b.snapshot() then
						error(`{label}: {step} diverged from the slate-less solve`, 0)
					end
					--[[ ...AND THE PUBLIC COMPOSITION READ, which is row 4 of the publish
						table and the only gated channel with a public reader. A rect
						comparison cannot see it: `compositionAt` answers off
						`ctx.compositions`, which a served composition would simply leave
						empty. ]]
					if a.compositionKey(compKey) ~= c.compositionKey(compKey) then
						error(`{label}: {step} moved controller.compositionAt`, 0)
					end
				end
				agree("mount")
				for step = 1, 3 do
					a.text(step + 1, `t{step}`)
					b.text(step + 1, `t{step}`)
					c.text(step + 1, `t{step}`)
					agree(`text {step}`)
					-- the gate row itself, so the scroll/composition arms drive the node
					-- the boolean is about rather than only its neighbours
					a.text(GATE_ROW, `g{step}`)
					b.text(GATE_ROW, `g{step}`)
					c.text(GATE_ROW, `g{step}`)
					agree(`gate-row text {step}`)
					a.width(step + 1, 200 + step * 20)
					b.width(step + 1, 200 + step * 20)
					c.width(step + 1, 200 + step * 20)
					agree(`width {step}`)
					--[[ ...and the drive that moves a CLEAN node's offered HEIGHT. It is
						the only drive here that can catch the serve dropping `maxH` from
						its offer test for a node whose answer genuinely reads it, and it
						is a no-op on every arm but `coupled` (the signal is bound to
						nothing there, so the refresh solves nothing). ]]
					a.height(GATE_ROW, 18 + step * 14)
					b.height(GATE_ROW, 18 + step * 14)
					c.height(GATE_ROW, 18 + step * 14)
					agree(`row height {step}`)
					a.viewport(view.w - step, view.h - step)
					b.viewport(view.w - step, view.h - step)
					c.viewport(view.w - step, view.h - step)
					agree(`viewport {step}`)
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)
