--!strict
--[[ THE CONTAINER STOPS WALKING THE CHILDREN IT DID NOT RE-MEASURE (Plan C, T13b —
	rulings L-7 and L-8). `tests/container_memo.spec.luau` is the sibling of this file
	and the two claims are deliberately different: T13 made the WORK inside
	`contentSize`'s loops O(dirty) and left the LOOPS at O(children), and its own report
	booked that residual as "the dominant term in this branch now". Measured at
	`66ccc867` with three `os.clock()` brackets, on the arena's `battle_hud L
	updateItem-hp`: PASS 1's walk 0.207 ms of a 1.802 ms class, the fill scan 0.005, the
	`crossMax` fold 0.004 — 12.0 % of the class, of which PASS 1 is 96 %.

	SO THE DIRTY CHILDREN ARE ENUMERATED INSTEAD OF FOUND, and the fold is left alone on
	a measurement rather than a habit (1.9 % of the three passes, with a rescan needed on
	0.09-14.8 % of hit folds if it were patched).

	THE ACCEPTANCE EVIDENCE IS AN UNMOVED COUNTER, which is the reverse of T13's.
	`lastChildVisits` counts CALLS and already reads "dirty + always-visit"; this task
	removes ITERATIONS, so the same children must still be measured and that counter
	must not move. The red is `lastChildIterations`.

	── THE OWED LIST ─────────────────────────────────────────────────────────────────
	What the skipped LOOP published per child that an O(dirty) pass no longer touches.
	T13's list asked "may this parent skip ASKING"; this one asks "may it skip LOOKING",
	which is strictly larger: a child the loop never reaches is a child whose `id`,
	`kind` and `dim` were never read. Every row names the case that holds it.

	A1  `ctx.offers[child.wKey]`/`[child.hKey]` for an unvisited child — SERVED by a
	    gated node-resident fallback. `child.oMemo` points at the container's memo, whose
	    key IS the offer, and `solver`'s entry literal reads it only when `ctx.offers`
	    misses AND the memo carries this solve's token. A nil offer disarms both anchor
	    arms, so "drop it" was never on the table.  ["a served child still files the
	    offer it was measured at"]
	A2  the index -> `child.id` binding of every UNVISITED index — REFUSED on the one
	    tick class where it can move (`cmemo.struct`, `cmemo.mN == n`), and `struct` is
	    cleared by every completed full pass so it cannot be sticky-true.  ["a structural
	    splice refuses the aggregate", "...and the tick AFTER the splice"]
	A3  which indices are `fill` — SERVED from `mFill`/`mIsFill`, with a valve in BOTH
	    directions decided in the pre-pass, before anything is written.  ["a child that
	    becomes fill re-runs the full pass"]
	A4  `marginMain[idx]` for a FILL child — SERVED by an O(#fill) pre-pass. The plan
	    said PASS 2 supplies it; PASS 2 only READS it.  [the fill oracle rows]
	A5  `crossOf[idx]` completeness for the fold — SERVED BY ALIASING, and the full pass
	    now records its OWN complete `crossOf` rather than the record block's subset.
	A6  `mainSum` — PATCHED (`mSum + new - mMain[idx]`), with `mMain` complete at every
	    index and `mSum` captured BEFORE PASS 1.5 can rebase it.  ["two consecutive
	    aggregate ticks"]
	A7  `ctx.fitCuts` for unvisited children — PATCHED from `mCutsSum`, written back on
	    every aggregate tick.  [the audited oracle's channel 3]
	A8  `fillWeightSum` — RE-ACCUMULATED in the same pre-pass as A4. Without it the share
	    is `math.huge` and every fill child measures at an unbounded main extent.
	A9  DOCUMENT ORDER — the dirty set is a HASH. The visit list is sorted ascending and
	    deduplicated.  ["two dirty siblings publish in document order"]
	A10 the walk's own bound — a probe budget of `math.max(4, n // 4)`; the floor exists
	    because a bare `n // 4` is 0 below four children.  `lastAggregateFallbacks`
	    counts STARTED-THEN-BAILED only.
	A11 `lastChildVisits`, `lastMeasureCalls`, `lastMeasureServed`, `lastMeasured` — NONE
	    MOVE, and that is the acceptance evidence.  ["the counters that must not move"]
	A12 PASS 1.5's `shrinkBasis` — the visit loop builds it exactly as PASS 1 does, so a
	    weight ARRIVING on an aggregating container shrinks on the arrival tick and the
	    tail drops the key.  ["a shrinkWeight arriving on an aggregating container"]
	A13 the five always-visit predicates plus the declared shrink weight — recorded ONCE
	    and never re-checked on an unvisited index. A flip of any of them makes the child
	    DIRTY (a `kind` change is a remount; the three subtree booleans and
	    `containerRelativeInside` are functions of the subtree, so a flip means a
	    descendant changed and the ancestor closure carries it; `shrinkWeight` is a prop
	    on the child).  [one case per class]

	AND ONE DEFECT THIS TASK FOUND IN T13'S OWN KEY, which is not an owed row: the memo
	was keyed on the offer pair but not on the AXIS. `UI.AdaptiveStack` flips `kind`
	between `vstack` and `hstack` through a reactive prop with no remount, and `mMain` is
	a MAIN-axis contribution — so the memo served heights as widths. `cmemo.mKind` closes
	it and the last case in this file drives it. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/deep_stack_scene")
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

--[[ ONE DRIVE, AND WHAT IT COST. `iters` is this task's own counter and the only one
	that is allowed to move; the other four are T13's headline and A11's promise, carried
	in the SAME string so a change to either is one diff. `solves=N` on every pin, per the
	standing rule that a pin which cannot see how many solves ran is pinning an average. ]]
local function drove(fn: () -> ()): string
	local before = capture.solves
	capture.result = nil
	fn()
	local n = capture.solves - before
	if n == 0 or capture.result == nil then
		return `solves={n}`
	end
	local w = capture.result.work
	return `solves={n} iters={w.childIterations} fallbacks={w.aggregateFallbacks} `
		.. `calls={w.measureCalls} served={w.measureServed} measured={w.measured} visits={w.childVisits}`
end

local function pair(opts: any): (any, any)
	local a = scene.new(opts)
	local c = table.clone(opts)
	c.measureReuse = false
	c.incremental = false
	return a, scene.new(c)
end

--[[ THE LOCAL FIXTURE, for the three shapes `deep_stack_scene` cannot carry: a stack
	whose AXIS is a reactive prop (`UI.AdaptiveStack` — one class, two solver kinds, and
	the flip is a re-solve rather than a remount, which is exactly what makes it a hazard
	for an index-keyed memo), a child whose main DIM changes type under it, and a pair of
	siblings dirtied in the SAME tick with fractional extents. `List` wants content on
	both axes, so its own offer is the screen's and does not move when the axis flips —
	which is the whole point: every other term in the memo's key still holds. ]]
local function flexScene(opts: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	local n = opts.rows or 8
	local axis = core:signal(opts.axis or "y")
	local fillOn = core:signal(false)
	local extra = core:signal(false)
	local heights: { any } = {}
	local kids: { any } = {}
	for i = 1, n do
		heights[i] = core:signal(if opts.fractional then 10 + i / 8 else 10 + i)
		local idx = i
		kids[i] = UI.Box({
			id = `B{idx}`,
			width = { type = "fixed", px = 20 },
			height = core:memo(function(use: any)
				if idx == 2 and (use(fillOn) :: boolean) then
					return { type = "fill", weight = 1 }
				end
				return { type = "fixed", px = use(heights[idx]) :: number }
			end),
		})
	end
	local bp = UI.Screen({
		id = "S",
		children = {
			UI.AdaptiveStack({
				id = "List",
				axis = core:memo(function(use: any)
					return use(axis) :: string
				end),
				gap = 0,
				padding = 0,
				width = { type = "content" },
				height = { type = "content" },
				children = {
					UI.When({
						id = "W",
						condition = core:memo(function(use: any)
							return use(extra) :: boolean
						end),
						thenView = function()
							return UI.Box({
								id = "X",
								width = { type = "fixed", px = 5 },
								height = { type = "fixed", px = 5 },
							})
						end,
					}),
					table.unpack(kids),
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
	local w: any = { controller = controller }
	function w.height(i: number, v: number)
		heights[i]:set(v)
		controller.refresh()
	end
	function w.heights(a: number, av: number, b: number, bv: number)
		heights[a]:set(av)
		heights[b]:set(bv)
		controller.refresh()
	end
	function w.axis(v: string)
		axis:set(v)
		controller.refresh()
	end
	function w.fill(v: boolean)
		fillOn:set(v)
		controller.refresh()
	end
	function w.extra(v: boolean)
		extra:set(v)
		controller.refresh()
	end
	function w.stats(): any
		return controller.stats()
	end
	function w.snapshot(): string
		local out: { string } = {}
		for path, node in adapter.liveNodes() do
			local r = node.storedRect
			table.insert(out, `{path}|{if r == nil then "-" else `{r.x},{r.y},{r.w},{r.h}`}`)
		end
		table.sort(out)
		return table.concat(out, "\n")
	end
	function w.dispose()
		controller.dispose()
		root.dispose()
	end
	return w
end

--[[ THE LADDER, ported from `tests/container_memo.spec.luau` for owed row A7 — the
	CUTS channel, which is the one served number with no geometric shadow. Three
	properties of the shape are load-bearing and two earlier attempts (T13's) were
	vacuous without them: the candidate must be MEASURE-DIRTY so C2's node-resident
	serve refuses it and `contentSize` is entered at all; the CUTTING child must be a
	container rather than a `text`, because a `text` child is never served; and the
	label must be ONE UNBROKEN WORD wider than the offer, because a phrase WRAPS and
	wrapping is fitting, not cutting. ]]
local function fitsScene(opts: any): any
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	local rowWidth = core:signal(20)
	--[[ ...AND A `ScrollView` THAT ARRIVES STRUCTURALLY INSIDE THE TRUNCATING ROW (fix
		round 1, I-2). `UI.When`'s every arm ends in `pushDirty(path, "structure")`, so
		flipping it is the one refresh class on which `hit` can be TRUE while the
		aggregate refuses: the memo's key still matches (the offer, the stamp, the scope
		and the kind are all unchanged), so the full pass runs with `mIds` as the SAME
		TABLE it recorded last epoch — and row 2 leaves the record set on that pass,
		because `subtreeHasScroll` makes it always-visit. Whether its `mIds` entry is
		retracted on the way out is what this fixture exists to see. ]]
	local scrollOn = core:signal(false)
	local rows: { any } = {}
	--[[ FORTY ROWS, NOT SIX, AND THE RUN IS WHAT SAID SO. The probe budget is
		`math.max(4, n // 4)`, and this drive's `reuse.measureContains` holds six entries
		(the dirty leaf plus its ancestor chain) — so on T13's six-row rung the aggregate
		STARTED, spent its budget on the closure and fell back to the walk every tick,
		and the cuts mutation below could not bite because the arithmetic it corrupts
		never ran. Forty rows puts the budget at ten, which is the shape a real list has
		and the shape this case is about. ]]
	for i = 1, 40 do
		rows[i] = UI.HStack({
			id = `Row{i}`,
			padding = 0,
			gap = 0,
			width = { type = "content" },
			height = { type = "content" },
			children = {
				if i == 2
					then UI.HStack({
						id = "L2",
						padding = 0,
						gap = 0,
						width = { type = "content" },
						height = { type = "content" },
						children = {
							UI.Text({ id = "Long", text = "Reconfiguration" }),
							UI.When({
								id = "W",
								condition = core:memo(function(use: any)
									return use(scrollOn) :: boolean
								end),
								thenView = function()
									return UI.ScrollView({
										id = "Sc",
										axis = "y",
										width = { type = "fixed", px = 6 },
										height = { type = "fixed", px = 6 },
										children = {
											UI.Box({
												id = "In",
												width = { type = "fixed", px = 4 },
												height = { type = "fixed", px = 20 },
											}),
										},
									})
								end,
							}),
						},
					})
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
	-- the STRUCTURAL arrival of `subtreeHasScroll` on the row that truncates
	function w.scroll(value: boolean)
		scrollOn:set(value)
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

local function flexPair(opts: any): (any, any)
	local a = flexScene(opts)
	local c = table.clone(opts)
	c.measureReuse = false
	c.incremental = false
	return a, flexScene(c)
end

describe("T13b: the counter that moves, and the four that must not", function()
	it("the counters that must not move (owed row A11), at base and after", function()
		--[[ THE REVERSE OF T13'S STEP 1(a), AND DELIBERATELY SO. T13's red was
			`lastChildVisits` falling; T13b's whole claim is that it does not, because the
			aggregate measures exactly the children the walk would have. If it fell, the
			aggregate skipped a child HEAD measured — a finding, not a win. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			expect(drove(function()
				s.text(500, "warm")
			end)).toBe("solves=1 iters=1001 fallbacks=0 calls=2005 served=999 measured=1005 visits=1001")
			--[[ THE FIRST AGGREGATING TICK PAYS FOR THE REVERSE MAP, once per full-pass
				epoch, and it is pinned rather than amortised away: `iters=1011` is the
				1,000-child walk that builds `id -> index` plus the ten the aggregate
				itself spends. The full pass used to build it and the arena said no —
				+0.3 ms on a STRUCTURAL class that never aggregates. ]]
			expect(drove(function()
				s.text(500, "x")
			end)).toBe("solves=1 iters=1011 fallbacks=0 calls=1006 served=1000 measured=5 visits=2")
			-- ...AND THE STEADY STATE, which is what the arena measures: the map is warm
			-- and the tick is five probes, two visits and the Screen's own container
			expect(drove(function()
				s.text(500, "y")
			end)).toBe("solves=1 iters=10 fallbacks=0 calls=1006 served=1000 measured=5 visits=2")
			s.dispose()
		end)
	end)

	it("...and the ITERATIONS are the red: 2,002 positions become 10", function()
		--[[ THE BEFORE COLUMN IS THE WARM-UP AND THE MUTATION, not a memory. The warm-up
			above reads 1,001 — PASS 1's walk of the 1,000-row `List` plus the Screen's own
			single child — and HEAD reads 2,002 for the same tick, because HEAD's fill pass
			re-walked the array to find the indices whose `crossOf` was still nil. That
			scan is gone in both arms: PASS 1 records the fill list, which the aggregate
			needs anyway (the sentinel cannot survive a persisted `crossOf`).

			ON THE DRIVE the aggregate reads 10 against HEAD's 2,002: five probes of
			`reuse.measureContains`, two visits, and the Screen's own container walking its
			one child twice. The measured arena numbers are in `docs/studio-runs`. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			s.text(500, "x")
			s.text(500, "y")
			local st = s.stats() :: any
			expect(`iters={st.lastChildIterations} visits={st.lastChildVisits}`).toBe("iters=10 visits=2")
			s.dispose()
		end)
	end)

	it("a viewport change aggregates nothing — it is unreachable, not declined", function()
		--[[ A geometry write is a FULL solve with no reuse table, so `hit` is false before
			the aggregate's own gate is reached and `lastAggregateFallbacks` must be 0: a
			tick the aggregate never ENTERED is not a fallback (that is the whole of the
			counter's definition, and the plan had it pinned at the container count on a
			tick where the aggregate never starts). ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			expect(drove(function()
				s.viewport(1000, 800)
			end)).toBe("solves=1 iters=2001 fallbacks=0 calls=5003 served=0 measured=5003 visits=2001")
			s.dispose()
		end)
	end)
end)

describe("T13b: the aggregate agrees with a full solve, tick after tick", function()
	it("two consecutive aggregate ticks, and a third (owed row A6)", function()
		--[[ THE ONLY WITNESS FOR THE WRITE-BACK, and the plan review is what asked for it:
			the first draft read `cmemo.mSum`/`mCutsSum` and never wrote them, so tick 2 was
			exact and tick 3 computed `mSum - mMain[idx]_from_tick_2 + new_3` where the
			truth is `mSum - mMain[idx]_original + new_3`, with the error accumulating. A
			spec that drives ONE tick after a warm-up cannot see it, and every case in the
			plan's own list was that shape. ]]
		local a, c = pair({ rows = 200 })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.text(50, "warm")
		c.text(50, "warm")
		agree("warm")
		for i, value in { "x", "yy", "zzz", "wwww", "v" } do
			a.text(50, value)
			c.text(50, value)
			agree(`tick {i}`)
			expect(`tick{i} visits={a.stats().lastChildVisits}`).toBe(`tick{i} visits=2`)
		end
		-- ...and the drives really did change the measured extent, or the case is a
		-- comparison of two unchanged trees
		expect(string.find(a.snapshot(), "/S/List/R50/A|", 1, true) ~= nil).toBe(true)
		a.dispose()
		c.dispose()
	end)

	it("a structural splice refuses the aggregate, and so does the tick AFTER it", function()
		--[[ OWED ROW A2, BOTH HALVES. The splice is what `cmemo.struct` is for: a
			`UI.ForEach` region spliced BEFORE the rows shifts every row's index in the
			layout node's flat list while `List`'s own mount children table stays the same
			OBJECT, so the carrier keeps the memo and an index-keyed pass would resolve
			every dirty id to the wrong child.

			THE TICK AFTER IT IS THE OTHER HALF and is the case the plan stopped one short
			of: on that tick `struct` is false again, so the aggregate runs — and it runs on
			the payload the splice tick RECORDED, which is why the tail re-records after
			every completed full pass and not only on a miss. Without that, a REORDER (same
			child count, so `mN` holds) would leak a stale `mIdx` into a tick the aggregate
			accepts. ]]
		local a, c = pair({ rows = 200, foreach = true })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.text(50, "warm")
		c.text(50, "warm")
		agree("warm")
		a.text(50, "x")
		c.text(50, "x")
		agree("plain")
		a.text(50, "x2")
		c.text(50, "x2")
		agree("second plain, the steady state")
		expect(`iters={a.stats().lastChildIterations}`).toBe("iters=10")
		a.insertItem("i0")
		c.insertItem("i0")
		agree("splice")
		-- the aggregate never STARTED (`struct` is true), so this is a full walk and not
		-- a fallback
		expect(`iters={a.stats().lastChildIterations} fallbacks={a.stats().lastAggregateFallbacks}`).toBe(
			"iters=204 fallbacks=0"
		)
		a.text(50, "y")
		c.text(50, "y")
		agree("plain tick AFTER the splice")
		a.text(50, "z2")
		c.text(50, "z2")
		agree("second plain tick after the splice")
		--[[ ...AND THE AGGREGATE IS BACK ON, which is the OTHER half of `cmemo.struct`
			(plan review, S5). The flag is written on every rebuild and a container that is
			NOT rebuilt on a later non-structural tick keeps the old value — so unless a
			completed full pass clears it, one structural tick disables the aggregate for
			that container indefinitely and no counter shows it. This number is the one
			that would show it. ]]
		expect(`iters={a.stats().lastChildIterations}`).toBe("iters=10")
		a.text(50, "z")
		c.text(50, "z")
		agree("second plain tick after the splice")
		a.removeItem("i0")
		c.removeItem("i0")
		agree("remove")
		a.text(50, "w")
		c.text(50, "w")
		agree("plain tick after the remove")
		a.dispose()
		c.dispose()
	end)

	it("a child that becomes `fill` re-runs the full pass (owed row A3)", function()
		--[[ THE VALVE, AND IT IS DECIDED BEFORE ANYTHING IS WRITTEN. A child whose main
			dim changed type is a prop change on that child, so it is dirty and therefore
			visited — but the aggregate has already classified it as non-fill and excluded
			it from the fill list, so the two halves would disagree. The pre-pass asks
			`dim` for every index it is about to visit and for every index in the recorded
			fill list, calls no `measure` and writes no solve-visible number, so a refusal
			leaves HEAD's pass running on exactly the fresh state it expects. ]]
		local a, c = flexPair({ rows = 8 })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.height(4, 30)
		c.height(4, 30)
		agree("warm")
		a.height(4, 31)
		c.height(4, 31)
		agree("plain")
		a.fill(true)
		c.fill(true)
		agree("B2 becomes fill")
		expect(`fallbacks={a.stats().lastAggregateFallbacks}`).toBe("fallbacks=1")
		a.height(4, 32)
		c.height(4, 32)
		agree("a plain tick with a fill child present")
		a.fill(false)
		c.fill(false)
		agree("B2 stops being fill")
		expect(`fallbacks={a.stats().lastAggregateFallbacks}`).toBe("fallbacks=1")
		a.dispose()
		c.dispose()
	end)

	it("a container whose child count changed refuses (`mN`)", function()
		--[[ THE `mN` TERM ALONE. A `UI.When` flipping adds or removes a child of `List`,
			which changes `#children` — and a count change is ALWAYS structural, so this
			term is a second lock on the door `cmemo.struct` already holds. It is kept
			because the two answer different questions (`struct` is a fact about the BUILD,
			`mN` a fact about the array the payload was recorded against) and because the
			payload's own arrays are indexed by a position `mN` bounds. The mutation table
			in the report records what removing it does. ]]
		local a, c = flexPair({ rows = 8 })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.height(4, 30)
		c.height(4, 30)
		agree("warm")
		a.extra(true)
		c.extra(true)
		agree("a child appears")
		a.height(4, 31)
		c.height(4, 31)
		agree("plain tick at the new count")
		a.extra(false)
		c.extra(false)
		agree("the child leaves")
		a.height(4, 32)
		c.height(4, 32)
		agree("plain tick back at the old count")
		a.dispose()
		c.dispose()
	end)

	it("a child in BOTH lists is measured ONCE, which is what the sort buys (owed row A9)", function()
		--[[ THE SORT'S WITNESS, and the first round could not build one. `table.sort(list)`
			was recorded as a NULL: every last-write-wins verdict channel is keyed by node
			id, two siblings cannot share one, and float reassociation moved no rect. The
			review asked for a bite or a deletion, and the bite is not about ORDER at all —
			it is about the DEDUPE the sort makes possible.

			The visit list is `mAlways` plus whatever the dirty set resolves to, and a child
			can be in both. The dedupe is a one-element compare against the previous entry,
			which is exactly what a SORTED list needs and nothing more — so with the sort
			removed, `always = {3, 4}` and a dirty index of 3 gives `{3, 4, 3}`, the
			duplicate is not adjacent, and index 3 is measured TWICE. `mainSum` survives it
			(the second patch subtracts the value the first just wrote, so the delta is
			zero) but `ctx.childVisits` does not — and that counter moving is owed row A11's
			whole claim.

			THE SHAPE: the gate row carries `containerRelativeInside` (always-visit at its
			index) and a `text` label sits at the index above it (always-visit too), and the
			drive dirties the GATE ROW ITSELF. Nothing else in this fixture puts a child in
			both lists with a second always-visit child above it. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = 60, crelLater = true, crelStart = true, label = true })
			s.text(30, "warm")
			s.text(30, "a")
			expect(drove(function()
				s.width(GATE_ROW, 301)
			end)).toBe("solves=1 iters=10 fallbacks=0 calls=70 served=61 measured=8 visits=4")
			s.dispose()
		end)
	end)

	it("two dirty siblings publish in document order (owed row A9)", function()
		--[[ THE DIRTY SET IS A HASH. `for id in dirty` gives an arbitrary order, and PASS
			1.5's own comment states the rule this pass inherits: last-write-wins verdict
			channels must publish deterministically. The visit list is therefore sorted and
			deduplicated (a child in the always list AND in the dirty set appears twice,
			and measuring it twice would patch `mainSum` twice).

			FRACTIONAL EXTENTS, on purpose: `mainSum` is a float accumulation and float
			addition is not associative, so a reordered visit list is the one thing that
			can make two arithmetically identical sums differ in their low bits. The report
			records whether that is enough to move a rect on this tree. ]]
		local a, c = flexPair({ rows = 8, fractional = true })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.height(4, 30.125)
		c.height(4, 30.125)
		agree("warm")
		a.heights(3, 7.375, 6, 21.625)
		c.heights(3, 7.375, 6, 21.625)
		agree("two siblings dirty in one tick")
		expect(`visits={a.stats().lastChildVisits}`).toBe("visits=3")
		a.heights(6, 4.0625, 3, 19.9375)
		c.heights(6, 4.0625, 3, 19.9375)
		agree("...and again, the other way round")
		a.dispose()
		c.dispose()
	end)

	it("the memo is keyed on the AXIS, or a vstack serves heights as widths", function()
		--[[ NOT AN OWED ROW — A DEFECT IN T13'S KEY, found while proving owed row A2 and
			fixed in the same commit. `UI.AdaptiveStack` is ONE public class with a reactive
			`axis` prop, and `render/layout_node` maps it to two solver KINDS with the
			documented guarantee that "the flip is a re-solve, never a remount, so children
			keep their identity". `mMain[idx]` is the child's MAIN-axis contribution; which
			axis that is depends on the kind. A container that wants content on both axes is
			offered the same `innerMaxW`/`innerMaxH` before and after the flip, its children
			are all clean, and the stamp and scope are unchanged — so every term in T13's key
			held and the memo served the wrong axis's numbers. `cmemo.mKind` is the term. ]]
		local a, c = flexPair({ rows = 8 })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.height(4, 30)
		c.height(4, 30)
		agree("warm")
		a.axis("x")
		c.axis("x")
		agree("the axis flips to x")
		a.height(4, 31)
		c.height(4, 31)
		agree("a plain tick as an hstack")
		a.axis("y")
		c.axis("y")
		agree("...and back to y")
		a.dispose()
		c.dispose()
	end)
end)

describe("T13b: one case per always-visit class (owed row A13)", function()
	--[[ Each arm puts one of the six shapes on `List`'s own direct child and asks two
		things of the same drive: that the shaped child IS still measured every tick
		(`visits` at its T13 value — the aggregate visits exactly the set the walk would
		have), and that the other rows are NOT walked (`iters` in single digits, where a
		walk is 1,001). The pair is what separates "the class is in the always list" from
		"the container refused wholesale". ]]
	local function gateDrive(opts: any): string
		local out
		withWorkCapture(function()
			local s = scene.new(opts)
			s.text(500, "warm")
			-- twice: the first aggregating tick pays for the container's reverse map, and
			-- what these arms are about is the steady state around a refused child
			s.text(500, "x")
			out = drove(function()
				s.text(500, "y")
			end)
			s.dispose()
		end)
		return out :: string
	end

	it("a `text` direct child", function()
		expect(gateDrive({ rows = ROWS, label = true })).toBe(
			"solves=1 iters=11 fallbacks=0 calls=1008 served=1002 measured=5 visits=3"
		)
	end)

	it("a `composition` subtree", function()
		expect(gateDrive({ rows = ROWS, composition = true })).toBe(
			"solves=1 iters=11 fallbacks=0 calls=1007 served=999 measured=7 visits=3"
		)
	end)

	it("a `ScrollView` subtree", function()
		expect(gateDrive({ rows = ROWS, scroll = true })).toBe(
			"solves=1 iters=11 fallbacks=0 calls=1007 served=999 measured=7 visits=3"
		)
	end)

	it("a `containerRelative` subtree", function()
		expect(gateDrive({ rows = ROWS, crel = true })).toBe(
			"solves=1 iters=11 fallbacks=0 calls=1007 served=999 measured=7 visits=3"
		)
	end)

	it("a DECLARED `shrinkWeight = 0`, which is the documented `never shrinks`", function()
		--[[ THE SHAPE THE PLAN REVIEW'S ALTERNATIVE WOULD HAVE COST. Its M4 proposed
			refusing the aggregate whenever a visited child carries `shrinkWeight ~= nil`;
			a declared ZERO is a legal authored value meaning "never shrinks" (Roblox's
			`UIFlexMode.None`), it never builds a shrink basis, and refusing on it would
			disable the aggregate for that container forever. It is an always-visit child
			instead, and the container keeps aggregating around it. ]]
		expect(gateDrive({ rows = ROWS, shrinkLater = true })).toBe(
			"solves=1 iters=11 fallbacks=0 calls=1007 served=1001 measured=5 visits=3"
		)
	end)

	it("a `fill` child is measured on EVERY tick, and the fill pass is O(#fill)", function()
		expect(gateDrive({ rows = ROWS, fill = true })).toBe(
			"solves=1 iters=12 fallbacks=0 calls=1008 served=1002 measured=5 visits=2"
		)
	end)
end)

describe("T13b: an always-visit predicate that ARRIVES after mount (fix round 1, I-1)", function()
	--[[ OWED ROW A13'S ARGUMENT WAS HALF AN ARGUMENT. It said a flip of any of the
		seven predicates cannot reach an UNVISITED index, and that is true — the flip
		makes the child dirty and a dirty child is visited. What it did not say is what
		happens to the classification the flip tick produced: `mAlways` is recorded only
		by a COMPLETED FULL PASS, so an aggregate tick measured the child correctly and
		threw the classification away. From the next tick the child was neither in
		`mAlways` nor dirty — so it was SERVED, a serve HEAD's own PASS 1 refuses by this
		very predicate, and `lastChildVisits` fell BELOW the walk's.

		`containerRelativeInside` is the reachable vector because it is the only one of
		the seven that is a pure function of a DESCENDANT's dim TYPE — no remount, no
		structural refresh, just a reactive measure-classed `width` two levels down.

		THE CASE IS A PAIR OF IDENTICALLY-SHAPED TREES, which is what makes it a witness
		rather than a number: one DECLARES the mark at construction, one has it ARRIVE at
		tick 3, and at the same steady state they must agree. ]]
	local function steady(opts: any, flip: (any) -> ()): string
		local out
		withWorkCapture(function()
			local s = scene.new(opts)
			s.text(500, "warm")
			s.text(500, "a")
			flip(s)
			s.text(500, "b")
			out = drove(function()
				s.text(500, "c")
			end)
			s.dispose()
		end)
		return out :: string
	end

	it("the ARRIVING mark is visited on every tick after it, exactly as a DECLARED one is", function()
		local declared = steady({ rows = ROWS, crelLater = true, crelStart = true }, function() end)
		local arrived = steady({ rows = ROWS, crelLater = true }, function(s)
			s.crelOn(true)
		end)
		expect(`arrived: {arrived}`).toBe(`arrived: {declared}`)
		-- ...and the shared number is the WALK's, not a serve: three children measured
		-- (the dirty row, the gate row, and `List` itself asked by the Screen)
		expect(declared).toBe("solves=1 iters=11 fallbacks=0 calls=1007 served=999 measured=7 visits=3")
	end)

	it("...and a mark that DEPARTS stops being visited, rather than being walked forever", function()
		--[[ THE MIRROR, and the review called it benign: a child that stops being
			always-visit stays in `mAlways` and is over-visited for the life of the
			surface. Benign is not correct — the valve catches both directions, because
			it compares the predicate's answer against the RECORDED classification rather
			than testing it one way. ]]
		local plain = steady({ rows = ROWS, crelLater = true }, function() end)
		local departed = steady({ rows = ROWS, crelLater = true, crelStart = true }, function(s)
			s.crelOn(false)
		end)
		expect(`departed: {departed}`).toBe(`departed: {plain}`)
		expect(plain).toBe("solves=1 iters=10 fallbacks=0 calls=1006 served=1000 measured=5 visits=2")
	end)

	it("...and the flip tick itself is a REFUSAL, which is where the re-record comes from", function()
		--[[ The valve is in the pre-pass, so it costs nothing and writes nothing: it
			reads `dim`, the predicate and the memo, refuses, and HEAD's pass runs on the
			fresh state it expects and re-records `mAlways` correctly. `fallbacks=1` is
			that refusal — a STARTED-then-bailed tick, which is the only thing that
			counter means. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS, crelLater = true })
			s.text(500, "warm")
			s.text(500, "a")
			expect(drove(function()
				s.crelOn(true)
			end)).toBe("solves=1 iters=1012 fallbacks=2 calls=1009 served=999 measured=9 visits=3")
			s.dispose()
		end)
	end)

	it("...and every rect agrees with a full solve across the flip, both ways", function()
		local a, c = pair({ rows = 200, crelLater = true })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.text(50, "warm")
		c.text(50, "warm")
		agree("warm")
		a.text(50, "a")
		c.text(50, "a")
		agree("plain")
		a.crelOn(true)
		c.crelOn(true)
		agree("the mark ARRIVES")
		a.text(50, "b")
		c.text(50, "b")
		agree("the tick after the arrival")
		a.text(50, "c")
		c.text(50, "c")
		agree("and the one after that")
		a.crelOn(false)
		c.crelOn(false)
		agree("the mark DEPARTS")
		a.text(50, "d")
		c.text(50, "d")
		agree("the tick after the departure")
		a.dispose()
		c.dispose()
	end)
end)

describe("T13b: a shrinkWeight arriving on an aggregating container (owed row A12)", function()
	it("the arrival tick shrinks, the key is dropped, and the next tick is a full pass", function()
		--[[ `memoable = false` DOES NOT CLEAR `hit`, so a weight that arrives on a
			container which has already memoised at this offer leaves the key matching and
			the aggregate can run on the very tick the weight appears. The visit loop
			therefore builds `shrinkBasis` exactly as PASS 1 does — the arriving child is
			dirty, so it is visited; every child that ALREADY had a weight is in the always
			list, so the basis is complete — and PASS 1.5 runs over a `mainSum` that is
			exact, because a served number is the number the walk would have produced for
			that index and the capture the memo keeps is taken before the shrink rebases
			it. Then the tail drops the key and the next tick walks. ]]
		local a, c = pair({ rows = 200, shrinkLater = true })
		local function agree(step: string)
			if a.snapshot() ~= c.snapshot() then
				error(`{step}: the aggregating arm diverged from a FULL solve`, 0)
			end
		end
		a.text(50, "warm")
		c.text(50, "warm")
		agree("warm")
		a.text(50, "x")
		c.text(50, "x")
		agree("plain, aggregating")
		a.text(50, "x2")
		c.text(50, "x2")
		agree("second plain, the steady state")
		expect(`iters={a.stats().lastChildIterations}`).toBe("iters=11")
		a.shrinkOn(1)
		c.shrinkOn(1)
		agree("the weight ARRIVES")
		a.text(50, "y")
		c.text(50, "y")
		agree("the tick after the arrival, which must be a full pass")
		expect(`iters={a.stats().lastChildIterations}`).toBe("iters=205")
		a.dispose()
		c.dispose()
	end)
end)

describe("T13b: the offer a SERVED child was measured at (owed row A1)", function()
	--[[ THE CHANNEL, AND THE NULL IT STILL SITS IN — stated first, because a case that
		reads as a witness and is not one is worse than no case.

		T13's skip arm writes `ctx.offers` for every child it skips; the aggregate never
		reaches those children at all. The entry literal reads that pair to file
		`offerW`/`offerH`, and BOTH anchor arms test it — a nil there disarms them (T7,
		finding 2). So the pair moved onto the memo it was already the KEY of:
		`child.oMemo` points at the container's own memo, and `solver`'s entry literal
		reads `mOffW`/`mOffH` from it when `ctx.offers` misses AND the memo carries this
		solve's token. The stamp is what makes it sound rather than a stale value arming a
		rect-serving skip on a false match: the aggregate fires only when the memo's key
		EQUALS this tick's offer.

		AND IT IS STILL BEHAVIOURALLY INVISIBLE, exactly as T13 recorded of its own two
		writes. `stack.arrange`'s pass 1 measures EVERY child of every stack it arranges
		(`src/layout/stack.luau`, the `deps.measure(ctx, child, innerW, innerH)` in the
		first loop and the `hugLater` loop under it), and `measure` writes `ctx.offers`
		itself — so by the time an entry literal is built, the pair is never nil. Measured
		here: deleting the fallback entirely leaves 20/20 green, and so does transposing
		its two halves. T14's replay is what deletes that re-measure, and the day it does,
		this fallback is the only writer for a served child.

		SO THE CASES BELOW ARE WHAT IS HONESTLY AVAILABLE: the VALUE the entry files, and
		the MECHANISM on the node. Neither claims to be the behavioural witness the
		channel is still owed. ]]
	it("a child the aggregate served files the offer its container measured it at", function()
		withWorkCapture(function()
			local s = scene.new({ rows = 200 })
			s.text(50, "warm")
			s.text(50, "x")
			s.text(50, "y")
			local result = capture.result
			expect(`visits={result.work.childVisits} iters={result.work.childIterations}`).toBe("visits=2 iters=10")
			-- a row the aggregate SERVED (not the dirty one, not the first)
			local entry = (result.rects :: any)["/S/List/R120"]
			expect(entry ~= nil).toBe(true)
			--[[ ...and the VALUE, not merely non-nil. `List` is a `fill`-width child of the
				screen, so the offer every row is measured against is the list's own inner
				width. A pair that is merely non-nil could be anything. ]]
			local list = (result.rects :: any)["/S/List"]
			expect(`w={entry.offerW == list.rect.w} h={entry.offerH ~= nil}`).toBe("w=true h=true")
			s.dispose()
		end)
	end)

	it("...and the pointer the fallback follows is on the node, pointing at the right memo", function()
		--[[ THE MECHANISM PIN, which is what is left once the channel's behaviour is a
			null. It walks the layout tree the solve was handed and asks the two things the
			entry literal asks: that a SERVED child carries `oMemo`, and that the memo it
			points at holds the offer that container is measuring at right now. If the
			record's `child.oMemo = cmemo` is dropped, or the memo's offer key drifts from
			what the aggregate compares against, this reddens where the rect differential
			cannot. ]]
		withWorkCapture(function()
			local s = scene.new({ rows = 200 })
			s.text(50, "warm")
			s.text(50, "x")
			local root = capture.root
			local function find(node: any, id: string): any
				if node.id == id then
					return node
				end
				for _, child in node.children or {} do
					local hit = find(child, id)
					if hit ~= nil then
						return hit
					end
				end
				return nil
			end
			local list = find(root, "/S/List")
			local row = find(root, "/S/List/R120")
			expect(`list={list ~= nil} row={row ~= nil}`).toBe("list=true row=true")
			local memo = row.oMemo
			expect(`pointsAtItsContainer={memo ~= nil and memo == list.cmemo}`).toBe("pointsAtItsContainer=true")
			local rect = (capture.result.rects :: any)["/S/List"]
			expect(`offerIsTheContainers={memo.mOffW == rect.rect.w}`).toBe("offerIsTheContainers=true")
			s.dispose()
		end)
	end)
end)

describe("T13b: an aggregating stack replays the cuts of the children it did not visit", function()
	it("...inside a `ViewThatFits`, where a lost cut changes which rung paints", function()
		--[[ OWED ROW A7, AND IT IS THE ONE CHANNEL THE RECT DIFFERENTIAL CANNOT SEE.
			`ctx.fitCuts` reaches the world through exactly one test —
			`chosenCandidate`'s `local uncut = ctx.fitCuts == cutsBefore` — which asks
			whether a candidate would paint an ellipsis. The aggregate never visits the
			cutting row, so its cuts have to come back from `mCutsSum`, patched by
			subtracting the visited children's own recorded deltas.

			UNDER-COUNT IT AND A CANDIDATE THAT WILL BE CUT LOOKS HONEST AND WINS. That is
			the mutation (`cutsOwed = 0`) and its bite is recorded in the report; the
			nine-view oracle cannot catch it, because the fixtures it runs on do not
			truncate and every `mCuts` there is legitimately zero.

			THE AGGREGATE MUST BE LIVE ON THE RUNG, or this is a case about `ViewThatFits`.
			`iters` says so: the rich rung has six rows and one of them is dirty. ]]
		withWorkCapture(function()
			local a = fitsScene({})
			local c = fitsScene({ incremental = false, measureReuse = false })
			expect(`{a.chosen()} | {c.chosen()}`).toBe("Rich=0 Plain=20 Fallback=0 | Rich=0 Plain=20 Fallback=0")
			for step = 1, 4 do
				c.driveRow(20 + step)
				a.driveRow(20 + step)
				expect(`step {step}: {a.chosen()} | {c.chosen()}`).toBe(
					`step {step}: Rich=0 Plain=20 Fallback=0 | Rich=0 Plain=20 Fallback=0`
				)
			end
			--[[ ...AND THE RUNG'S OWN LOOP REALLY IS AGGREGATING, which is what separates
				this from T13's version of the same fixture: `visits` is unmoved at 5 (the
				memo's number) while `iters` is far below the full walk of six rows plus the
				ladder's own children. ]]
			local st = a.stats() :: any
			expect(`visits={st.lastChildVisits} iters={st.lastChildIterations}`).toBe("visits=5 iters=21")
			a.dispose()
			c.dispose()
		end)
	end)
end)

--[[ THE FORCED-ON ORACLE (ruling L-4, and the plan review's M5). The plan asked the full
	pass to "compare its own answers against the aggregate's" — but with the audit on the
	aggregate never ran, so there was nothing on the other side of the equals:
	`cmemo.mSum` is the value the PREVIOUS full pass recorded, which legitimately differs
	from this tick's whenever anything changed. T13's audit works because its memo holds a
	per-index would-have-served answer; a container-level SUM has no such twin.

	SO THE ANSWER IS COMPUTED. `contentSize` snapshots the payload as the aggregate would
	have found it, runs the full walk, and then derives the four channels arithmetically —
	no extra `measure` call, no gate weakened — and asserts each against its own numbers
	BEFORE the record at the tail replaces them:

	  1. THE VISIT SET — the indices the aggregate would have measured, in the order it
	     would have measured them, against the ones the walk actually did. This is owed
	     rows A2, A3 and A13 in one equality.
	  2. `mainSum` — `mSum + sum(new - old)` over that set, against PASS 1's own total
	     (owed row A6, and the pre-shrink capture of amendment A-4's first reason).
	  3. THE CUTS AN UNVISITED CHILD OWES — `mCutsSum - sum(old cuts over the visited
	     recorded indices)`, against what the walk's skip arm actually served (owed row
	     A7, the one number with no geometric shadow).
	  4. `fillWeightSum` AND `marginMain` over the fill indices — the pair PASS 2 reads
	     and never writes (owed rows A4 and A8).

	NON-VACUITY IS `ctx.aggregateChecks`, which counts the containers actually compared;
	every case below pins a floor on it. The plan's proposed witness — that the two
	`lastChildIterations` differ — is satisfied by the audit flag alone and proves only
	that the flag works. ]]
local ORACLE_ROWS = 12

describe("T13b: a child that LEAVES the record set retracts it (fix round 1, I-2)", function()
	it("...or the aggregate subtracts cuts from a total that never held them", function()
		--[[ `mIds[idx]` HAD ONE WRITER AND NO ERASER. On a HIT the array IS `cmemo.mIds`,
			so a full pass that runs on a hit inherits the previous epoch's entries and only
			ADDS — and the one refresh class where `hit` is true while the aggregate refuses
			is the STRUCTURAL one (`hit` is computed before the `struct` term). A `UI.When`
			flip is exactly that: every arm of `setBranch` ends in `pushDirty(path,
			"structure")`.

			So row 2 — which TRUNCATES, and therefore is the only child here with a non-zero
			`mCuts` — gains a `ScrollView` and leaves the record set on that pass, while
			`cutsSum` correctly drops it. Without the retraction its `mIds` entry survives,
			and the next aggregate tick reads `mIdsA[idx] ~= nil` as "this index is
			RECORDED" and runs `cutsOwed -= mCuts[idx]` against a `cutsOwed` seeded from an
			`mCutsSum` that never contained it. `ctx.fitCuts` is short by that child's cuts
			on that tick and every one after — and under-counting is the direction that
			makes a candidate which WILL paint an ellipsis look honest.

			THE LADDER IS THE INSTRUMENT because `ctx.fitCuts` has exactly one reader:
			`chosenCandidate`'s `uncut = ctx.fitCuts == cutsBefore`. Every step is compared
			against a full-solve arm, and the audited replay runs channel 3 (`mCutsSum`
			against what the walk actually served) on the tick after the flip. ]]
		withWorkCapture(function()
			local a = fitsScene({})
			local c = fitsScene({ incremental = false, measureReuse = false })
			local function agree(step: string)
				if a.chosen() ~= c.chosen() then
					error(`{step}: {a.chosen()} vs a FULL solve's {c.chosen()}`, 0)
				end
			end
			c.driveRow(21)
			a.driveRow(21)
			agree("warm")
			c.driveRow(22)
			a.driveRow(22)
			agree("aggregating")
			-- the STRUCTURAL arrival: `hit` is true, the aggregate refuses, the full pass
			-- runs in place on the memo's own arrays and row 2 leaves the record set
			c.scroll(true)
			a.scroll(true)
			agree("the ScrollView arrives")
			for step = 1, 3 do
				c.driveRow(22 + step)
				a.driveRow(22 + step)
				agree(`aggregate tick {step} after the arrival`)
			end
			--[[ ...AND THE AUDITED REPLAY, which is where channel 3 asks the question a
				rung verdict cannot: `mCutsSum` must equal the sum of `mCuts` over the
				indices the walk actually served. A stale `mIds` entry breaks that equality
				directly, whether or not the rung it belongs to happens to flip. ]]
			local audited = table.clone(capture.opts)
			audited.containerAggregateAudit = true
			local checked = solver.solve(capture.root, capture.viewport, audited)
			if checked.work.aggregateChecks < 1 then
				error(`the ladder's audited replay compared {checked.work.aggregateChecks} containers`, 0)
			end
			a.dispose()
			c.dispose()
		end)
	end)
end)

describe("T13b oracle: the aggregate's own answer, computed and asserted", function()
	it("every gate shape, at every one of the nine device views", function()
		for _, fixture in
			{
				{ name = "plain", rows = ORACLE_ROWS },
				{ name = "nested", rows = ORACLE_ROWS, nested = true },
				{ name = "fill", rows = ORACLE_ROWS, fill = true },
				{ name = "label", rows = ORACLE_ROWS, label = true },
				{ name = "foreach", rows = ORACLE_ROWS, foreach = true },
				{ name = "crel", rows = ORACLE_ROWS, crel = true },
				--[[ ...and the ARRIVAL (fix round 1, I-1). Every other fixture here
					DECLARES its gate shape at construction, so channel 1 — the visit set —
					never had a tree where the classification could move under it. This one
					flips it mid-drive, and channel 1 fires on it without the pre-pass
					valve: `container aggregate visit-set mismatch at /S/List`. ]]
				{ name = "crelLater", rows = ORACLE_ROWS, crelLater = true, flip = true },
			}
		do
			local checks = 0
			for _, view in device_views.VIEWS do
				local opts = table.clone(fixture)
				opts.name = nil
				opts.flip = nil
				opts.viewport = { x = 0, y = 0, w = view.w, h = view.h }
				withWorkCapture(function()
					local s = scene.new(opts)
					s.text(5, "warm")
					s.text(5, "x")
					if fixture.flip then
						s.crelOn(true)
						s.text(5, "y")
						s.text(5, "z")
					end
					s.dispose()
				end)
				local root, viewport = capture.root, capture.viewport
				local plain = solver.solve(root, viewport, capture.opts)
				local audited = table.clone(capture.opts)
				audited.containerAggregateAudit = true
				local checked = solver.solve(root, viewport, audited)
				--[[ NON-VACUITY PER VIEW, not per fixture (review MINOR). The floor used to
					be one comparison across all nine, so a fixture where eight views
					silently stopped comparing still passed. Read off the run. ]]
				if checked.work.aggregateChecks < 1 then
					error(`{fixture.name}/{view.id}: the audit compared {checked.work.aggregateChecks} containers`, 0)
				end
				checks += checked.work.aggregateChecks
				--[[ ...AND THE RECT DIFFERENTIAL BESIDE IT, over the four channels the
					mount-level snapshot names: `rectOf`, `screenRectOf`, the hit rect and
					the engine `Position`. At the direct-solve level all four are functions
					of the entry, so the entry is what is compared — every field of it, not
					only the rect, so the offer pair and the verdict channels are in the
					comparison too. ]]
				for id, entry in plain.rects do
					local other = (checked.rects :: any)[id]
					if other == nil then
						error(`{fixture.name}/{view.id}: {id} vanished under the audit`, 0)
					end
					local r, o = entry.rect, other.rect
					if r.x ~= o.x or r.y ~= o.y or r.w ~= o.w or r.h ~= o.h then
						error(`{fixture.name}/{view.id}: {id} moved under the audit`, 0)
					end
					if entry.offerW ~= other.offerW or entry.offerH ~= other.offerH then
						error(`{fixture.name}/{view.id}: {id} filed a different offer`, 0)
					end
					if entry.compact ~= other.compact or entry.textState ~= other.textState then
						error(`{fixture.name}/{view.id}: {id} published a different verdict`, 0)
					end
				end
			end
			if checks < 1 then
				error(`{fixture.name}: the audit compared {checks} containers across nine views`, 0)
			end
		end
	end)

	it("...and at the full 1,000 rows, where a per-index error has room to show", function()
		withWorkCapture(function()
			local s = scene.new({ rows = ROWS })
			s.text(500, "warm")
			s.text(500, "x")
			s.dispose()
		end)
		local root, viewport = capture.root, capture.viewport
		local plain = solver.solve(root, viewport, capture.opts)
		local audited = table.clone(capture.opts)
		audited.containerAggregateAudit = true
		local checked = solver.solve(root, viewport, audited)
		if checked.work.aggregateChecks < 1 then
			error(`the audit compared {checked.work.aggregateChecks} containers`, 0)
		end
		--[[ ...AND THE GROUND TRUTH, the third arm T13's own audit case learned to carry:
			a solve with `reuse` and `measures` removed, where the memo, the aggregate and
			C2's node-resident serve are all structurally unreachable. Every rect the
			aggregating solve produced has to be this solve's rect. ]]
		local truth = table.clone(capture.opts)
		truth.reuse = nil
		truth.measures = nil
		local c = solver.solve(root, viewport, truth)
		local compared = 0
		for id, entry in c.rects do
			local other = (plain.rects :: any)[id]
			local r, o = entry.rect, if other ~= nil then other.rect else nil
			if o == nil or r.x ~= o.x or r.y ~= o.y or r.w ~= o.w or r.h ~= o.h then
				error(`{id} differs from a solve with no reuse at all`, 0)
			end
			compared += 1
		end
		if compared < 2000 then
			error(`the ground-truth compare only saw {compared} rects`, 0)
		end
	end)
end)
