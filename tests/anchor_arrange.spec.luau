--!strict
--[[ N2 — THE SINGLE-UPDATE FLOOR IS THE CONTAINER, NOT THE CHANGE.

	There is no "list" layout node: `ForEach` splices its children into the parent
	(`layout_node.luau`'s ForEach region), so the canvas is ONE `anchor` with 250
	direct children and the solver's anchor arrange branch re-offers and re-places
	every one of them to settle a single dirty child. Per child, unconditionally: one
	`measure()`, one rect table, two `dim()` and two `offsetPx()` calls — and the same
	floor sits under every add, every remove and every tick.

	THE COST OF THAT `measure()` IS CPU, NOT GARBAGE, and the task brief said the
	opposite. Its 125 KB was attributed to the 250 memo-HIT `measure()` calls; measured
	six ways in one session (the CEILING case below carries the table), removing 249 of
	them moves the heap by 0.08 KB, because the interpolated `{maxW}|{maxH}|{scopeKey}`
	cacheKey is IDENTICAL for all 250 children and Luau interns it. What the arm is
	worth is on the clock and on the arena: FacetBench `nameplates L`, tick p50 -4.2 %,
	add -16.3 %, remove -18.2 %, every step's ABBA arms disjoint.

	WHY A PER-CHILD SKIP IS SOUND HERE AND NOWHERE ELSE: an anchor child's rect is a
	pure function of (innerX, innerY, innerW, innerH, child.anchor, child.offsetX/Y,
	measure(child, innerW, innerH)) — NO SIBLING APPEARS IN IT. A stack's does (every
	child feeds `fixedMain` / `fillWeightSum` and then the cursor, now
	`src/layout/stack.luau`), which is why this task touches the anchor branch only.

	AND THE COUNTER HAD TO BE A NEW ONE, which is the correction this file carries
	against the task brief. The brief expected `lastMeasured` to show the 250 and it
	CANNOT: `ctx.measured` is incremented inside `measureUncached`, and a sibling's
	re-offer is a memo HIT that returns before reaching it. Measured at the base of
	this task, an `hp` step on 250 plates read `arranged=4 measured=7` ALREADY — the
	dirty chain and nothing else — while the anchor branch was calling `measure` 250
	times. A demonstrator built on `measured` would
	have been green before the change and green after it, which is the "check that
	proves nothing" class this repository has a gate for. `work.anchorOffered` /
	`work.anchorReused` are the two halves of the loop this task changes and their sum
	is every child of every anchor the solve arranged, so a regression cannot hide in
	the split. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local solver = require("../src/layout/solver")
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local customFactory = require("../src/core/custom")
local fake_target = require("./lib/fake_target")

local PLATES = scene.PLATES -- 250

--[[ THE VIEWPORT STEP THE FIXTURE HAS NO VERB FOR. `nameplates_scene` drives
	signals (`tick`, `hp`, `add`, `remove`) and the viewport is not one — it is an
	ENV fact, set at construction. Driving it is `env:set` + `controller.refresh()`,
	the idiom `tests/adaptive_defaults.spec.luau` uses on its own scene, reaching for
	the two handles the fixture already publishes rather than growing a verb on a
	shared fixture for one spec's sake. ]]
local function resize(w: any, width: number, height: number)
	w.env:set("viewportRect", { x = 0, y = 0, w = width, h = height })
	w.controller.refresh()
end

--[[ READ OFF THE RUN (2026-09-02, at the T6 base `93fcd06e`), both of them, with
	the node names beside them. They are NOT knowable on paper, and the protocol here
	is the round's: correct the EXPRESSION and this comment, never the assertion.

	`arranged = 4` — the dirty chain is Screen + Canvas + Plate + Hp. The Canvas is in
	`dirtyContains` (a prefix of the Hp write) so it arranges; the plate's Row and
	Cast do not, because the plate's content height did not move when Hp's width
	changed, so both land on the rect they already had and take the skip.

	`measured = 7` — bucketed by node id with a temporary counter inside
	`measureUncached` (reverted before commit): `/S` x1 and `/S/Canvas` x1 and the
	plate root x1, all three slate refusals because they are dirty, plus `Hp` x2 and
	`Cast` x2 — both are fixed x fixed, hence PLAN_SKIP, hence counted on EVERY touch
	with no memo, and the plate's vstack touches them once in its measure pass and
	once in its arrange pass. 3 + 2 + 2 = 7.

	NEITHER MOVES IN THIS TASK, and that is stated here rather than discovered by the
	next reader: both are already the dirty chain alone. They are pinned as the
	INVARIANT half — the thing the anchor arm must not break — while
	`anchorReused`/`anchorOffered` and the KB are the half that moves. ]]
local ARRANGED_HP = 4 -- Screen + Canvas + Plate + Hp
local MEASURED_HP = 7 -- (Screen + Canvas + Plate) + Hp x2 + Cast x2, all PLAN_SKIP or dirty

--[[ ...AND THE HALF THAT MOVES, read off the run for every step kind the fixture
	drives. Before this task every one of them was `reused = 0, offered = 250`.

	THE GATE IS THE *MEASURE* HALF OF THE DIRT, not the whole closure, and these
	numbers are what that decision is worth. The arm reuses one thing — the child's
	SIZE — so the question is the one `measure`'s own cross-solve adopt gate asks: did
	anything change inside this subtree that a MEASUREMENT could read? A `tick` writes
	`offsetX`/`offsetY` on all 250 plates, which is ARRANGE-classed dirt: every plate
	is in `dirtyContains` and none of them is in `measureContains`, so the arm serves
	all 250 and `offered` is ZERO. On `dirtyContains` it would have been the reverse,
	and the same reversal was measured on Rascal Rally's shipped minimap, where a
	one-dot move re-runs every dot's family-hue memo (see
	`RascalRally/code/tests/facet_anchor_arrange.spec.luau`).

	`tickWithCasts` IS THE NEGATIVE CONTROL, and it is a real one rather than a
	drill: it moves every plate AND advances the Cast bar of the deterministic
	one-in-five subset with `{ type = "fixed", px = cast * 100 }` — a MEASURE-class
	write. Exactly those 50 plate roots go to `measure` and exactly the other 200 do
	not, so a gate that had collapsed to "always reuse" reads 250/0 here and fails. ]]
local REUSED_HP = PLATES - 1 -- 249: every plate but the one whose Hp width changed
local OFFERED_HP = 1 -- the dirty plate root alone
local CASTERS = PLATES // scene.CASTER_EVERY -- 50

--[[ The solver's `work` block is not on the controller's public surface and this
	task adds nothing to it, so the counters are read the way
	`tests/translate_arm.spec.luau` reads the entry map: wrap the module function for
	the duration of one case and put it back. `renderer.luau` calls `solver.solve(...)`
	as a field lookup, so the wrapper is on the shipped path; it is restored even when
	the body throws. ]]
--[[ THE INSTRUMENT, AND WHAT IT HAD TO GROW (T6 review, I2). The solver's `work`
	block is not on the controller's public surface and this task adds nothing to it,
	so the counters are read the way `tests/translate_arm.spec.luau` reads the entry
	map: wrap the module function for the duration of one case and put it back.
	`renderer.luau` calls `solver.solve(...)` as a field lookup, so the wrapper is on
	the shipped path; it is restored even when the body throws.

	THE FIRST VERSION KEPT ONLY THE LAST SOLVE, AND THAT IS THE "CHECK THAT PROVES
	NOTHING" CLASS. A drive that solves ZERO times — a `refresh()` with no dirt, which
	is exactly what follows an `env:set` of a geometry fact — silently re-asserted the
	previous solve's counters, and a drive that solved twice reported only the second.
	It is what hid the fact that both "a viewport change falls through" cases were
	measuring a full solve rather than the offer comparison.

	So the wrapper COUNTS INVOCATIONS and every pin carries the count: `solves=1` is
	part of the asserted string, not a side condition, and a step that caused no solve
	reports `solves=0` and no counters at all rather than a stale pair. It also keeps
	the OPTIONS the solve was called with, because `opts.reuse` is the difference
	between "the arm declined" and "there was no arm to decline" — see
	`geometryIsAFullSolve` below. ]]
local capture = { result = nil :: any, opts = nil :: any, solves = 0 }
local function withWorkCapture(fn: () -> ())
	local real = solver.solve
	solver.solve = function(...)
		local r = real(...)
		capture.solves += 1
		capture.result = r
		capture.opts = (select(3, ...))
		return r
	end
	local ok, err = pcall(fn)
	solver.solve = real
	if not ok then
		capture.result = nil
		capture.opts = nil
		error(err, 0)
	end
end

--[[ ONE DRIVE, AND WHAT IT COST — the whole assertion, in one string. `solves=N`
	first so a zero reads as a zero rather than as the last step's numbers, and the
	counters omitted entirely when there was no solve to read them from. ]]
local function drove(fn: () -> ()): string
	local before = capture.solves
	capture.result = nil
	fn()
	local n = capture.solves - before
	if n == 0 or capture.result == nil then
		return `solves={n}`
	end
	local w = capture.result.work
	return `solves={n} reused={w.anchorReused} offered={w.anchorOffered}`
end

-- ...and whether the LAST captured solve was handed a reuse table at all. `reuse`
-- is nil on a full solve, and `prevOf == nil` then makes the arm structurally
-- unreachable — a different mechanism from the arm declining, and the two produce
-- the same counters.
local function lastSolveWasIncremental(): string
	local opts = capture.opts
	return `reuse={tostring(opts ~= nil and (opts :: any).reuse ~= nil)}`
end

describe("N2: one changed plate does not re-offer 250 siblings", function()
	it("an hp step re-offers ONE anchor child and serves the other 249 from their own rect", function()
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			--[[ The two halves sum to every child of the one anchor this fixture has, so
				a "win" that simply stopped visiting children shows up here as a sum that
				is no longer 250 rather than as a smaller `offered`. ]]
			expect(drove(function()
				s.hp(7, 0.9)
			end)).toBe(`solves=1 reused={REUSED_HP} offered={OFFERED_HP}`)
			local w = capture.result.work
			expect(w.anchorReused + w.anchorOffered).toBe(PLATES)
			s.dispose()
		end)
	end)

	it("...and an ADD offers only the new plate, a REMOVE none at all", function()
		--[[ THE STRUCTURAL STEPS, which is where the arena measures the win (see the
			allocation case below). A structural solve rebuilds the ForEach's children,
			so the anchor re-offers all 251 — but only the NEW plate is dirty, so 250
			take the arm and one goes to `measure`. A REMOVE adds no node at all, so it
			offers NOTHING and every surviving sibling is served from its own rect. ]]
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			expect(drove(function()
				s.add(9001)
			end)).toBe(`solves=1 reused={PLATES} offered=1`)
			expect(drove(function()
				s.remove(1)
			end)).toBe(`solves=1 reused={PLATES} offered=0`)
			s.dispose()
		end)
	end)

	it("...and a TICK, which moves all 250 and resizes none, offers NOTHING", function()
		--[[ THE HEADLINE STEP. `offsetX`/`offsetY` are arrange-classed, so a tick puts
			every plate in `dirtyContains` and NONE of them in `measureContains` — their
			sizes cannot have moved. The anchor therefore re-places all 250 and measures
			none of them. This is the case the `measureContains` gate exists for. ]]
		withWorkCapture(function()
			local s = scene.new()
			expect(drove(function()
				s.tick(3, 2)
			end)).toBe(`solves=1 reused={PLATES} offered=0`)
			expect(drove(function()
				s.tick(3, 2)
			end)).toBe(`solves=1 reused={PLATES} offered=0`)
			s.dispose()
		end)
	end)

	it("NEGATIVE CONTROL: a caster tick resizes 50 plates, and exactly those 50 are measured", function()
		--[[ THE ARM IS NOT A BLANKET SKIP, and this is the case that says so with a
			number that is neither 0 nor 250. `tickWithCasts` moves every plate and
			advances the Cast bar of the one-in-five subset — a `{ type = "fixed", px =
			cast * 100 }` write, which IS measure-classed — so the 50 caster roots are in
			`measureContains` and go to `measure`, and the other 200 do not. A gate that
			collapsed to "always reuse" would serve a stale size to a plate that really
			did resize; it reads 250/0 here and this fails. ]]
		withWorkCapture(function()
			local s = scene.new()
			s.tick(3, 2)
			expect(drove(function()
				s.tickWithCasts(3, 2)
			end)).toBe(`solves=1 reused={PLATES - CASTERS} offered={CASTERS}`)
			expect(drove(function()
				s.tickWithCasts(3, 2)
			end)).toBe(`solves=1 reused={PLATES - CASTERS} offered={CASTERS}`)
			s.dispose()
		end)
	end)

	it("...and the dirty chain is untouched: the same arranged and measured as before", function()
		local s = scene.new()
		s.tick(3, 2)
		s.hp(7, 0.9)
		local st = s.stats()
		-- the dirty chain, and nothing else. What makes this a real assertion is the
		-- number's SIZE, not its exact value: 250 re-offered siblings cannot fit in it
		-- under any reading.
		expect(`arranged={st.lastArranged} measured={st.lastMeasured}`).toBe(
			`arranged={ARRANGED_HP} measured={MEASURED_HP}`
		)
		expect(`arrangedUnder10={st.lastArranged < 10} measuredUnder10={st.lastMeasured < 10}`).toBe(
			"arrangedUnder10=true measuredUnder10=true"
		)
		s.dispose()
	end)

	it("THE ALLOCATION CEILING, and the record of what the brief got backwards", function()
		--[[ THIS CASE IS A CEILING AND A RECORD, NOT A DEMONSTRATOR — said in its own
			name (T6 review, M6) because a reader skimming for "the allocation test" would
			otherwise find one that cannot fail for this arm. It stayed GREEN under the
			mutation that disables the arm entirely. The claims of this task are the
			counter cases above; this one keeps a number honest and writes down why it is
			not the number the task brief predicted.

			THE HEAP IS READ, NEVER COLLECTED. `collectgarbage("collect")` is not available
			under Lune 0.10.4 (it raises "collectgarbage called with invalid option");
			`"count"` is. So a window is a plain delta over ten identical steps after a
			warm-up, which measures ALLOCATION RATE rather than retention, and a collection
			landing inside a window can only make the number SMALLER — which is why every
			assertion here is a ceiling and the median of five windows is what is read.

			ONLY THE hp WINDOW IS PINNED. The structural window allocates ~3 MB and the
			collector reliably runs inside it: interleaved BASE/T6/T6/BASE through an
			earlier draft of this case, the add+remove medians read -38.68, 202.16, 285.00
			and 326.27 — a BASE arm produced the SMALLEST of the four, so a ceiling on it
			would have been a false green on the code it was written to reject. The hp
			window does not trip a collection and its arms are cleanly split. A pin is only
			worth having where the instrument separates the arms, so the structural claim
			is the counter case above and the arena row in FacetBench's ledger.

			THE SIX-ARM ATTRIBUTION, re-measured in ONE session on 2026-09-03 (T6 review,
			M3 — two earlier records disagreed by more than the effect they attributed,
			because they mixed a git parent with a feature-flagged build). Medians of five
			windows, one process per arm, same fixture, same drive:

			  | # | arm                                          | hp KB/step |
			  | 6 | the PARENT COMMIT `93fcd06e` — the honest before |     146.33 |
			  | 5 | this build, BOTH features off                |     143.58 |
			  | 4 | + the arm on, no new offer writes anywhere   |     143.66 |
			  | 3 | + the arm's own offer writes                 |     159.16 |
			  | 2 | the memo-hit offer write only, arm off       |     159.16 |
			  | 1 | SHIPPED (arm + memo-hit offer write)         |     159.16 |

			WHAT IT SAYS, and none of it is what the brief predicted:

			* A1 (`wKey`/`hKey`) IS THE ONLY ALLOCATION SAVING ON THIS STEP — rows 6 -> 5,
			  -2.75 KB, the four original `ctx.offers` indexes no longer concatenating.
			* THE ARM SAVES NOTHING HERE — rows 5 -> 4, +0.08 KB, i.e. nil. The brief's
			  125 KB was the 250 memo-HIT `measure()` calls the arm removes; the
			  interpolated cacheKey is IDENTICAL for all 250 children (same offer, same
			  scope) and Luau interns it, so 250 builds are one allocation. THIS IS ALSO
			  THE STEP-4 BOUND: rows 4 vs 5 remove 249 cacheKey builds OUTRIGHT for
			  |delta| <= 0.1 KB against a 143.6 floor — 0.07 % — so a three-level numeric
			  memo key (arm B) cannot reach the brief's 15 % threshold and arm A is kept.
			* THE OFFER CHANNEL COSTS +15.5 KB, and it is the CHANNEL rather than either
			  writer: rows 3 and 2 reach the same 159.16 from opposite sides, because
			  `ctx.offers` is fresh per solve and either writer alone fills it with two
			  entries per child — ~500 hash slots at 32 bytes is 16 KB, which is the
			  number. The arm needs that channel to be reachable at all (see
			  `tests/translate_arm.spec.luau`), so the hp step ends up 12.8 KB worse than
			  the parent commit on THIS fixture. Written down rather than netted away.
			* THE ARENA GOES THE OTHER WAY on the same channel, paid over far more nodes:
			  FacetBench `nameplates L`, ABBA n=4 per arm, arms disjoint on every step —
			  tick p50 -4.2 % and gcKb -6.3 %, add p50 -16.3 % and gcKb -21.9 %, remove
			  p50 -18.2 % and gcKb -24.9 %. The gate is worth most of that: the same ABBA
			  against a build that gated on `dirtyContains` read the tick p50 UNMOVED.

			The ceiling below is loose on purpose: 159 measured, a doubling caught, a 10 %
			machine difference tolerated. ]]
		local vals: { number } = {}
		for _ = 1, 5 do
			local s = scene.new()
			s.tick(3, 2)
			for i = 1, 4 do
				s.hp(7, 0.3 + i * 0.01)
			end
			local k0 = collectgarbage("count") :: number
			for i = 1, 10 do
				s.hp(7, 0.5 + i * 0.01)
			end
			local k1 = collectgarbage("count") :: number
			table.insert(vals, (k1 - k0) / 10)
			s.dispose()
		end
		table.sort(vals)
		local hpKb = vals[3]
		print(`anchor_arrange hp kbPerStep={string.format("%.2f", hpKb)}`)
		expect(`hpKb<250(CEILING)={tostring(hpKb < 250)}`).toBe("hpKb<250(CEILING)=true")
	end)

	it("...at every device view", function()
		withWorkCapture(function()
			for _, view in device_views.VIEWS do
				local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
				s.tick(3, 2)
				expect(`{view.id}:{drove(function()
					s.hp(7, 0.9)
				end)}:{s.stats().lastArranged}`).toBe(
					`{view.id}:solves=1 reused={REUSED_HP} offered={OFFERED_HP}:{ARRANGED_HP}`
				)
				s.dispose()
			end
		end)
	end)

	it("A GEOMETRY FACT IS A FULL SOLVE, so the arm is unreachable rather than declining", function()
		--[[ RE-TITLED AND RE-COMMENTED (T6 review, I1): this case was advertised as
			proving the arm's exact-offer precondition and it proves something else, which
			is worth having but is not that.

			`viewportRect` is a GEOMETRY key (`env/geometry_facts.luau`), and the
			renderer's geometry memo defers to `core:settle`, which calls `solveAndApply()`
			from OUTSIDE `refresh` — where the controller-level `dirtyContains` is still
			nil, so `solveOpts.reuse` is never set. The `env:set` therefore solves the
			surface itself, as a FULL solve, and the `refresh()` after it has no dirt and
			does not solve at all. The 250 that go to `measure` here do so because
			`prevOf == nil` at the top of the anchor branch, NOT because
			`prev.offerW ~= innerW`.

			THAT INVARIANT IS LOAD-BEARING FOR THE ARM AND IS ASSERTED NOWHERE ELSE. The
			gate is `measureContains`, so anything that changes a child's measured size
			without entering the measure dirt set would be served a stale rect — and the
			whole family of such things (the typography scale, the preferred-text offset,
			the theme metrics, the font-metric flip, the viewport, the safe insets) is the
			geometry-fact family. They are safe for exactly one reason: a geometry fact
			moving is always a full solve with no `reuse` table, so the arm cannot fire on
			the solve that first sees the new value. `reuse=false` below is that reason,
			pinned. The counters alone could not carry it — `reused=0 offered=250` is what
			BOTH mechanisms produce, which is why `solves=` and `reuse=` are in the
			asserted strings.

			The offer comparison itself is proved by "AN ANCESTOR'S PROP MOVES THE INNER
			BOX" below, which is the only shape that changes `innerW` while the solve
			stays incremental. ]]
		withWorkCapture(function()
			local s = scene.new({ viewport = { x = 0, y = 0, w = 1280, h = 720 } })
			s.tick(3, 2)
			expect(drove(function()
				s.hp(7, 0.9)
			end)).toBe(`solves=1 reused={REUSED_HP} offered={OFFERED_HP}`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			-- the `env:set` solves; the `refresh` after it finds no dirt, which is why
			-- the count is one and not two
			expect(drove(function()
				resize(s, 1000, 700)
			end)).toBe(`solves=1 reused=0 offered={PLATES}`)
			expect(lastSolveWasIncremental()).toBe("reuse=false")
			-- ...and the very next step at the SETTLED viewport is incremental again and
			-- arms again, so the full solve is the geometry fact's and not a latch
			expect(drove(function()
				s.hp(7, 0.4)
			end)).toBe(`solves=1 reused={REUSED_HP} offered={OFFERED_HP}`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			s.dispose()
		end)
	end)
end)

--[[ THE ONLY SHAPE THAT MOVES AN ANCHOR'S INNER BOX ON AN *INCREMENTAL* SOLVE
	(T6 review, I1), and therefore the only shape that can exercise the arm's
	exact-offer precondition at all.

	WHY THE 250-PLATE FIXTURE CANNOT DO IT: its anchor is the canvas root, so the only
	thing that changes `innerW`/`innerH` there is the viewport — and the viewport is a
	geometry fact, which is always a FULL solve with no `reuse` table (the case above
	pins that). `prevOf == nil` then makes the arm structurally unreachable, so the
	250 that go to `measure` on a resize say nothing about the offer comparison.
	Deleting both comparisons from the solver reddened NOTHING in either repository
	before this fixture existed.

	SO THE ANCHOR IS NESTED and its box is moved by a PROP write on its parent. The
	dirty closure runs UPWARD — a node is in it if it is dirty or CONTAINS a dirty node
	— so a `padding` write on the wrapper puts the wrapper and the Screen in the sets
	and leaves every anchor child out of both. The solve stays incremental (`reuse` is
	present, pinned below), the anchor's rect changes, `innerW` changes with it, and
	the offer comparison is the one and only thing standing between each child and a
	stale size.

	AND THE STALENESS IS REAL RATHER THAN THEORETICAL, which is why a third of the
	children are wrapping `UI.Text`: their measured HEIGHT is a function of the width
	they are offered. A child served its previous rect at a new offer keeps the box of
	a wrap that is not going to happen — so the differential half of this case is not a
	formality, it is where a wrong answer would show up as pixels. ]]
local NESTED_KIDS = 12

local function nestedAnchorWorld(incremental: boolean, view: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = view.w, h = view.h })
	local pad = core:signal(0)
	local nudge = core:signal(0)
	local kids = {}
	for i = 1, NESTED_KIDS do
		if i % 3 == 0 then
			table.insert(
				kids,
				UI.Text({
					id = `T{i}`,
					text = "a wrapping label whose measured height depends on the width it is offered, repeatedly",
					anchor = "topLeft",
					-- ONE child carries the reactive placement prop, so a `nudge` step is
					-- arrange-classed dirt on one child and nothing else: the step that
					-- must find the offers unchanged and take the arm
					offsetX = if i == 3 then nudge else 0,
					offsetY = i * 3,
				})
			)
		else
			table.insert(
				kids,
				UI.Box({
					id = `B{i}`,
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 20 },
					anchor = "topLeft",
					offsetY = i * 3,
				})
			)
		end
	end
	local root = mountLib.mount(
		core,
		UI.Screen({
			id = "S",
			children = {
				UI.VStack({
					id = "Wrap",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					-- the lever: a MEASURE-classed prop on the anchor's PARENT
					padding = pad,
					children = {
						UI.Anchor({
							id = "A",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = kids,
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
	return {
		controller = controller,
		pad = function(v: number)
			pad:set(v)
			controller.refresh()
		end,
		nudge = function(v: number)
			nudge:set(v)
			controller.refresh()
		end,
		dump = function(): string
			local out = {}
			for path, node in adapter.liveNodes() do
				local r = node.rect
				table.insert(out, `{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|vis={tostring(node.visible)}`)
			end
			table.sort(out)
			return table.concat(out, "\n")
		end,
		dispose = function()
			controller.dispose()
			root.dispose()
		end,
	}
end

describe("N2: the exact-offer precondition, on the only shape that can reach it", function()
	it("AN ANCESTOR'S PROP MOVES THE INNER BOX: every child falls through, on an INCREMENTAL solve", function()
		withWorkCapture(function()
			local w = nestedAnchorWorld(true, { w = 800, h = 600 })
			-- warm: `initialRender` is not a reuse solve, so the drive after it is the
			-- fill pass
			w.nudge(1)
			--[[ ARRANGE-CLASSED DIRT ON ONE CHILD, offers unchanged: the arm serves all
				twelve. This is the control — without it, the padding row below could be
				green because the arm never fires on this fixture at all. ]]
			expect(drove(function()
				w.nudge(2)
			end)).toBe(`solves=1 reused={NESTED_KIDS} offered=0`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			--[[ THE CASE THE GUARD EXISTS FOR. `padding` on the wrapper moves the
				anchor's inner box; the closure runs upward so no child is in either dirt
				set; the solve is still incremental (`reuse=true`, asserted — this is what
				separates it from the viewport case); and all twelve go to `measure`
				BECAUSE `prev.offerW ~= innerW`. Deleting the two comparisons at the arm's
				`if` makes this row read `reused=12 offered=0` — measured, not asserted. ]]
			expect(drove(function()
				w.pad(10)
			end)).toBe(`solves=1 reused=0 offered={NESTED_KIDS}`)
			expect(lastSolveWasIncremental()).toBe("reuse=true")
			-- ...and it re-arms at the settled box, so the fall-through is the offer's
			-- and not a latch
			expect(drove(function()
				w.nudge(3)
			end)).toBe(`solves=1 reused={NESTED_KIDS} offered=0`)
			-- ...and a SECOND move of the same box falls through again
			expect(drove(function()
				w.pad(24)
			end)).toBe(`solves=1 reused=0 offered={NESTED_KIDS}`)
			w.dispose()
		end)
	end)

	it("...and the geometry it produces is byte-equal to a forced FULL solve", function()
		--[[ THE COUNTER SAYS THE ARM DECLINED; THIS SAYS THE ANSWER IS RIGHT. A third of
			these children are wrapping text, so a child served its previous rect at a new
			offer would keep the height of a wrap it is not going to get — a wrong box,
			not a slow one. `b` re-solves in full on every refresh and is the ground
			truth. ]]
		local a = nestedAnchorWorld(true, { w = 800, h = 600 })
		local b = nestedAnchorWorld(false, { w = 800, h = 600 })
		local function step(what: string, drive: (any) -> ())
			drive(a)
			drive(b)
			if a.dump() ~= b.dump() then
				error(`{what}: the incremental arm diverged from a FULL solve`, 0)
			end
		end
		if a.dump() ~= b.dump() then
			error("mount: the incremental arm diverged from a FULL solve", 0)
		end
		for round = 1, 3 do
			step(`nudge {round}`, function(w)
				w.nudge(round)
			end)
			step(`pad in {round}`, function(w)
				w.pad(round * 9)
			end)
			step(`nudge under pad {round}`, function(w)
				w.nudge(round + 10)
			end)
			step(`pad out {round}`, function(w)
				w.pad(round * 3)
			end)
			step(`pad zero {round}`, function(w)
				w.pad(0)
			end)
		end
		a.dispose()
		b.dispose()
	end)
end)

--[[ THE ORACLE — the same three arms `tests/translate_arm.spec.luau` and
	`tests/measure_split.spec.luau` use, because the risk of a per-child skip is
	exactly the risk of a per-subtree one: an arm that serves a stale size produces a
	green counter and a wrong screen. `a` is the shipped configuration, `b` keeps
	incremental arrange but throws the measure slates away, and `c` forces a FULL
	solve every refresh and is the ground truth. The channel is `scene.snapshot()` —
	every live node's rect, hit rect, scroll region, visibility and adapter props,
	sorted — plus the diagnostics.

	THE OVERFLOW FIXTURE MATTERS MOST HERE: a plate 2,000px wide changes what the
	anchor's own hug path would compute, and the arm must not serve a stale size to
	it. ]]
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
-- is per-plate identical, so 20 plates exercises every branch 250 does. The COUNT
-- pins above run at the full 250.
local ORACLE_PLATES = 20

local function diagKey(w: any): string
	local out = {}
	for _, d in w.controller.diagnostics() do
		table.insert(out, `{d.node}|{string.sub(d.issue, 1, 32)}`)
	end
	table.sort(out)
	return `{#out}: ` .. table.concat(out, " ")
end

describe("N2 oracle: byte-equal to a full solve, every view, every step kind", function()
	local FIXTURES: { any } = {
		{ name = "plain", plates = ORACLE_PLATES },
		{ name = "overflow", plates = ORACLE_PLATES, overflow = true },
		{ name = "fractional", plates = ORACLE_PLATES, fractional = true },
	}
	for _, fixture in FIXTURES do
		it(`{fixture.name}: rects, visibility, hit rects, scroll regions and findings survive`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				local function step(what: string, compareB: boolean, drive: (any) -> ())
					drive(a)
					drive(b)
					drive(c)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: {what} diverged from a FULL solve`, 0)
					end
					if compareB and a.snapshot() ~= b.snapshot() then
						error(`{label}: {what} diverged from the memo-less solve`, 0)
					end
					if diagKey(a) ~= diagKey(c) then
						error(`{label}: {what} diagnostics diverged from a FULL solve`, 0)
					end
				end
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
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
					step(`add {round}`, false, function(w)
						w.add(round)
					end)
					step(`tick-after-add {round}`, false, function(w)
						w.tick(dx, dy)
					end)
					step(`remove {round}`, false, function(w)
						w.remove(round)
					end)
					--[[ ...AND THE THREE DRIVES THE SIBLING ORACLES DO NOT TAKE, added
						because the `measureContains` gate widened what this arm serves:
						`hide` is arrange-classed (the plate keeps its size), `align` is a
						container-level word this anchor's children carry, and `nudgeLabel`
						rewrites a plate's NAME — a text write, the measure-classed dirt the
						gate must let through. A child served a stale size after any of the
						three would show up here as a rect diverging from a full solve. ]]
					step(`hide {round}`, false, function(w)
						w.hide(2, round % 2 == 1)
					end)
					step(`align {round}`, false, function(w)
						w.align(if round % 2 == 1 then "center" else "start")
					end)
					step(`nudgeLabel {round}`, false, function(w)
						w.nudgeLabel(4, `Renamed {round}`)
					end)
					--[[ ...AND A VIEWPORT CHANGE, which is the step the other two oracles
						in this repository do not take and the one this arm is most exposed
						to: it changes `innerW`/`innerH`, so every recorded offer stops
						matching and the arm must fall through for all of them. A stale
						`prev.rect` served here is a wrong screen. ]]
					step(`resize {round}`, false, function(w)
						resize(w, view.w - round, view.h - round)
					end)
					step(`resize-back {round}`, false, function(w)
						resize(w, view.w, view.h)
					end)
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)
