--!strict
-- The performance lab, driven headlessly (roadmap Step 9; acceptance rows
-- PL-2, PL-3, PL-4, PL-5, PL-9, PL-10, PL-11).
--
-- WHY A HEADLESS SPEC FOR A STUDIO LAB. Everything in `perf_lab` that is a
-- DECISION — the deterministic dataset, the bounded-window rule, mount
-- exclusivity, the emergency stop, what makes a capture row inadmissible — is
-- pure Luau, and the execution contract says to use the lowest evidence level
-- that can actually observe the behaviour. Proving these here means the Studio
-- session is spent on the things only an engine can show (paint, native scroll,
-- real frame work, MicroProfiler scopes) instead of on logic bugs.
--
-- The negative controls matter more than the positive ones. A "virtualization is
-- bounded" assertion that has never been seen to fire is decoration, so this spec
-- breaks the window on purpose and requires the scenario to refuse.

local testkit = require("./lib/testkit")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local Facet = require("../src")
local fake_target = require("./lib/fake_target")

local dataset = require("../examples/performance/lab/dataset")
local rowsLib = require("../examples/performance/lab/rows")
local captureLib = require("../examples/performance/lab/capture")
local overlayLib = require("../examples/performance/lab/overlay")
local leversLib = require("../examples/performance/lab/levers")
local hapticsLib = require("../src/client/haptics")
local perf_lab = require("../examples/performance/lab/perf_lab")
-- the pass-level round-trip readout is only populated while phase scopes are
-- recording, and scopes ship OFF (src/core/profile.luau) — so one case here
-- installs a hook pair and puts it back
local profile = require("../src/core/profile")

-- A minimal stand-in for the runner ctx. It carries exactly the seams perf_lab
-- reads, so a seam the scenario starts depending on shows up here as a nil-index
-- rather than as a Studio-only surprise.
local function newHarness(hostOverrides: any?, viewport: { w: number, h: number }?, labOpts: any?)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	local vp = viewport or { w = 900, h = 700 }
	env:set("viewportRect", { x = 0, y = 0, w = vp.w, h = vp.h })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)
	local clock = 0
	local steps = 0
	local host: any = {
		facts = function()
			return {
				evidenceClass = "lune",
				capturedAtIso = "2026-08-04T00:00:00Z",
				sourceStamp = "test-stamp",
				placeName = "headless",
				viewport = "900x700",
				orientation = "landscape",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lune host",
				thermalNote = "n/a",
				capturePath = "n/a",
				summaryPath = "n/a",
			}
		end,
	}
	if hostOverrides ~= nil then
		for k, v in hostOverrides do
			host[k] = v
		end
	end
	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		host = host,
		-- `haptics` is the opt-in client adapter the lab binds under
		-- `select:haptics=on` (task 11). Supplied here exactly as the Studio host
		-- supplies it, so the headless rig exercises the shipped route.
		lab = {
			dataset = dataset,
			rows = rowsLib,
			capture = captureLib,
			overlay = overlayLib,
			levers = leversLib,
			haptics = hapticsLib,
		},
		labOptions = labOpts,
		telemetry = {
			clock = function()
				clock += 0.001
				return clock
			end,
			step = function()
				-- COUNTED, so "one lap fits a 60-frame MicroProfiler window" is a
				-- checkable claim rather than a design intention. `telemetry.step` is
				-- the lab's frame-yield seam: one call is one frame on the engine.
				steps += 1
				return 0
			end,
			instances = function()
				return { measured = true, guiObjects = 0, screenGuis = 0 }
			end,
			connections = function()
				return { measured = false }
			end,
			memory = function()
				return { measured = true, luaHeapKb = 0 }
			end,
			frameWork = function(frames: number)
				return { measured = true, frames = frames, p50_ms = 0, p95_ms = 0, p99_ms = 0 }
			end,
		},
		geometry = function()
			return {}
		end,
		themePackages = {},
		themeChrome = {
			setPackage = function()
				return false
			end,
			census = function()
				return { unsupported = true }
			end,
		},
	}
	local built = perf_lab.build(ctx)
	-- the yield count, exposed beside the scenario's own surface. Not part of
	-- perf_lab's contract — this harness owns the seam, so this harness reports it.
	local anyBuilt = built :: any
	anyBuilt.framesYielded = function(): number
		return steps
	end
	return built, ctx, core
end

describe("perf lab: the dataset is deterministic (PL-2)", function()
	it("the same seed, count and content produce a byte-identical row set", function()
		local a = dataset.build({ count = 250, seed = 42, content = "normal" })
		local b = dataset.build({ count = 250, seed = 42, content = "normal" })
		expect(#a).toBe(250)
		expect(dataset.digest(a)).toBe(dataset.digest(b))
	end)

	it("a different seed produces a different row set, and the digest says so", function()
		local a = dataset.build({ count = 250, seed = 42 })
		local b = dataset.build({ count = 250, seed = 43 })
		expect(dataset.digest(a) == dataset.digest(b)).toBe(false)
	end)

	it("each content variant is its own workload, not a relabelling of the same one", function()
		local normal = dataset.build({ count = 60, seed = 9, content = "normal" })
		local locale = dataset.build({ count = 60, seed = 9, content = "locale" })
		local identity = dataset.build({ count = 60, seed = 9, content = "identity" })
		expect(dataset.digest(normal) == dataset.digest(locale)).toBe(false)
		expect(dataset.digest(locale) == dataset.digest(identity)).toBe(false)
		-- the locale variant really does expand, or it is not testing expansion
		expect(#locale[1].detail > #normal[1].detail).toBe(true)
	end)

	it("an unknown content variant is refused, naming it", function()
		local ok, err = pcall(function()
			dataset.build({ count = 4, content = "klingon" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "klingon") ~= nil).toBe(true)
	end)

	it("the ramp ladder is bounded by a declared ceiling (PL-11)", function()
		expect(#dataset.RAMP_STEPS > 0).toBe(true)
		for _, step in dataset.RAMP_STEPS do
			expect(step <= dataset.MAX_ROWS).toBe(true)
		end
	end)
end)

describe("perf lab: a resize step is the resize a device performs", function()
	it("drives the adapter's whole fact-group, batched into one flush", function()
		--[[ THE PASS USED TO SET `viewportRect` ALONE — a resize no device performs.
			`src/client/roblox_env.luau` `pushViewport()` learns SIX facts from one
			rotation (viewport, three inset shapes, topbar rect, size class) and the
			renderer re-solves for most of them, so a one-fact resize under-counted
			the shipped path's SOLVE COUNT: the exact lever L-27 named. This asserts
			the pass moves the whole group AND that the group still costs one solve,
			i.e. it is batched (tests/geometry_solve_coalescing.spec).

			Mutation-proved 2026-08-13: dropping the batch reddens the solve count;
			dropping any inset from the group reddens the "moved" count. ]]
		local built, ctx, core = newHarness(nil, { w = 900, h = 700 })
		built.steps.select(nil, "scenario=resize-relayout,rows=120,seed=1")
		built.steps.mount()

		local env = ctx.env
		--[[ `displaySize` is deliberately NOT here. The adapter publishes it on
			every pushViewport, so this pass writes it — but its domain is
			`Small | Medium | Large` (the physical display class) and a ROTATION
			DOES NOT CHANGE IT. An earlier cut drove it off the width as
			`"Compact"`/`"Large"`, which is not its domain at all and silently
			flipped every wide step into a 1.5x-scaled ten-foot TV layout with 90px
			overscan (RED-TEAM 2026-08-13). It is held constant now, so asserting it
			MOVED would be asserting the bug back. ]]
		local WATCHED = { "viewportRect", "coreSafeInsets", "deviceSafeInsets", "topbarSafeInsets", "topbarInset" }
		local moved: { [string]: boolean } = {}
		local counts: { [string]: number } = {}
		for _, key in WATCHED do
			moved[key] = false
			counts[key] = 0
			core:observe(env:get(key), function()
				moved[key] = true
				counts[key] += 1
			end)
		end

		--[[ ONE memo over the group is the batching oracle: the core is glitch-free,
			so it recomputes ONCE per flush however many dependencies moved. Batched,
			the group is one flush per resize; loose, it is up to six.

			`coreSafeInsets` is deliberately EXCLUDED from the oracle (it stays in
			`moved` above), and the reason CHANGED with L-31 (2026-08-14) — read this
			rather than the optimization-log entry that predicted the exclusion would
			be deleted.

			The lab's overlay still writes that one edge twice per resize:
			`forgetReservation` zeroes it when the viewport moves, then the measured
			dock height is republished. What L-31 removed is not the writes — they
			are what a measure→publish cycle IS — but their price: both now land
			inside the flush that caused them instead of the republication arriving a
			frame later in a flush of its own. So `coreSafeInsets` still moves twice
			per resize while every other fact in the group moves once, and counting
			it here would still measure the overlay's cycle rather than this pass's
			batching. Measured 2026-08-13 over 4 steps, before: viewportRect 5,
			deviceSafeInsets/topbarSafeInsets/topbarInset 4 each, displaySize 1, and
			coreSafeInsets ELEVEN.

			The thing that DID get fixed has its own check below, on the pass's own
			`reactPerStep` readout, which is the number that names a feedback loop
			directly instead of inferring one from a fact that legitimately moves
			twice. ]]
		local BATCH_ORACLE = { "viewportRect", "deviceSafeInsets", "topbarSafeInsets", "topbarInset" }
		local flushes = 0
		local group = core:memo(function(use)
			for _, key in BATCH_ORACLE do
				use(env:get(key))
			end
			return {}
		end)
		core:observe(group, function()
			flushes += 1
		end)

		local STEPS = 4
		built.steps.pass(nil, `resizeStorm={STEPS}`)

		for _, key in WATCHED do
			-- false here means the lab measures a resize the shipped adapter never performs
			expect(moved[key]).toBe(true)
		end
		-- THE CEILING IS THE CHECK. At most one flush per resize plus the restore at
		-- the end; six loose writes would be up to 6x this. There is deliberately no
		-- floor of STEPS: the storm's shape sequence can repeat, and a step that
		-- lands on the shape already set changes no fact and costs no flush, which
		-- is correct behaviour rather than a missed resize. `moved` above is what
		-- proves the group is driven at all.
		expect(flushes <= STEPS + 1).toBe(true)
		expect(flushes >= 1).toBe(true)
	end)

	it("a resize step is TWO reactive flushes — the round trip no longer buys a third", function()
		--[[ THE FEEDBACK-LOOP DETECTOR, on the pass's own readout (L-31,
			2026-08-14; director's standing instruction to give the lab whatever it
			needs to profile this cost).

			A `resizeStorm` step drives exactly two things: the adapter's six-fact
			resize, batched, and then ONE bound value with the viewport held still.
			Two writes, so two reactive flushes — and anything above that is a write
			made in RESPONSE to the resize rather than as part of it, which is what a
			measure→publish feedback loop is. It read THREE until L-31: the overlay's
			republication of its measured dock height arrived a frame late, in a
			flush of its own, and every geometry flush re-solves every mounted
			surface.

			This is the number the 2026-08-14 device capture diagnosed the loop from
			(`react` = 3.03 per step on an SM-A102U1, where the framework's own
			contribution is 1) and it had to be read out of a binary MicroProfiler
			dump by hand. Now the pass reports it.

			SCOPES SHIP OFF, so the counters only accumulate with a hook pair
			installed — hence the recorder, and hence the assertion that the reading
			is non-zero before the assertion about its value. Restored afterwards, or
			this leaks instrumentation into every spec that runs later. ]]
		-- the REAL profile module, exactly as the Studio lab client hands it in:
		-- headlessly `host.profile` defaults to a no-op stub whose byScope is
		-- always empty, and a check reading zeros from a stub proves nothing
		local built, _ctx, core = newHarness({ profile = profile }, { w = 900, h = 700 })
		built.steps.select(nil, "scenario=resize-relayout,rows=120,seed=1")
		built.steps.mount()

		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function() end, function() end)
		local ok, result = pcall(function()
			built.steps.pass(nil, "resizeStorm=6")
			return built.report()
		end)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
		if not ok then
			error(result, 0)
		end

		local row = nil
		for _, entry in (result :: any).passes do
			if entry.pass == "resizeStorm" then
				row = entry.detail
			end
		end
		expect(row ~= nil).toBe(true)
		-- the instrument is live at all: 0 would make the assertions below vacuous
		expect((row :: any).arrangePerStep > 0).toBe(true)
		--[[ THE CEILING IS THE CHECK, in the same shape as the batching oracle
			above: two flushes per step, plus ONE for the whole pass — `resizeStorm`
			ends by restoring the original viewport, which is a seventh geometry
			change over six steps and reads as 13/6 = 2.17 rather than 2.00. A third
			flush per step is 19, so the two are not close. ]]
		local STEPS = 6
		expect((row :: any).reactPerStep * STEPS <= 2 * STEPS + 1).toBe(true)
		expect((row :: any).reactPerStep >= 2).toBe(true)
		built.dispose()
		expect(core:lastError()).toBeNil()
	end)
end)

describe("perf lab: the resize storm reports both costs separately", function()
	it("separates a resize from a single-value change, and keeps the ratio visible", function()
		-- The pass exists to make one number impossible to lose: how much of a full
		-- re-layout a SINGLE bound value costs. A resize legitimately re-arranges the
		-- whole tree; a data change should not, and today does (L-11).
		local built = newHarness(nil, { w = 360, h = 691 })
		built.steps.select(nil, "scenario=resize-relayout,rows=500,seed=1")
		built.steps.mount()
		-- `pass` returns the pass result directly, and `timed` wraps the payload in
		-- `detail` alongside its own ms
		local d = built.steps.pass(nil, "resizeStorm=12").detail
		expect(d.resize.n > 0).toBe(true)
		expect(d.dataChange.n > 0).toBe(true)
		-- both costs are reported, never blended into one average
		expect(type(d.resize.p50Ms)).toBe("number")
		expect(type(d.dataChange.p50Ms)).toBe("number")
		-- and the ratio is present, so a future incremental-layout change shows up here
		expect(type(d.arrangedPerResize)).toBe("number")
		expect(type(d.arrangedPerDataChange)).toBe("number")
		expect(d.arrangedPerResize > 0).toBe(true)
		-- THE NUMBER THIS PASS EXISTS FOR. Headlessly the harness runs a FAKE clock, so
		-- the ms figures here are synthetic and only the arranged COUNTS mean anything;
		-- the timings are real in a Studio session. Measured at this size: a resize
		-- re-arranges ~124 nodes and a single bound value ~104 — 84% of a full
		-- re-layout for one changed string. The assertion is a ceiling, not a budget,
		-- because the good number does not exist yet (L-11).
		expect(d.dataChangeShareOfFullRelayout <= 1.05).toBe(true)
		built.dispose()
	end)
end)

describe("incremental layout Stage 1: boundary detection sizes the prize", function()
	it("reports how much of the real workload a single change would touch", function()
		-- DETECTION ONLY — nothing about layout changes. This is the measurement that
		-- decides whether Stages 2 and 3 of docs/plans/incremental-layout.md are worth
		-- doing, taken on the workload we actually profile rather than a toy tree.
		local built = newHarness(nil, { w = 360, h = 691 })
		built.steps.select(nil, "scenario=dense-scroll,rows=500,seed=1")
		built.steps.mount()
		local r = built.report()
		expect(r.mountedImplementation).toBe("facet")
		local report = built.boundaryReport()
		expect(report ~= nil).toBe(true)
		expect(report.nodes > 0).toBe(true)
		-- the tree HAS absorbing nodes; if it had none the plan would be dead on arrival
		expect(report.absorbingNodes > 0).toBe(true)
		-- and a single change would touch strictly less than everything
		expect(report.meanAffected < report.todayAffected).toBe(true)
		-- MEASURED at this fixture (360x691, the compact three-band row): 104 nodes,
		-- 28 of them absorbing; a single change touches 104 today and would touch 20
		-- with boundaries honoured — 19% of the tree, and mean = median = p95, so the
		-- win is uniform rather than concentrated in a few lucky nodes.
		--
		-- The assertion is a CEILING with headroom rather than the measured value, so
		-- an ordinary layout edit does not redden this; what it protects is the claim
		-- the plan rests on — that boundaries exist and isolate most of the tree.
		expect(report.meanShareOfTree < 0.5).toBe(true)
		built.dispose()
	end)
end)

--[[ THE HAPTICS COUNTERS (task 11).

	An adapter that turns feedback verbs into engine haptics is a new subscriber on
	the presenter's bus, and a performance lab's job is to answer one question about
	any new subscriber: does it cost anything PER FRAME? It must not — the adapter
	is event-driven, pools one Instance per distinct sensation and builds none per
	pulse — so the counter line exists to make that a measurement rather than a
	claim, and these cases are what say the counter can see anything at all.

	THE WORKLOAD IS IDENTICAL with the setting on or off: this adds a subscriber,
	never a scenario.
]]
local function hapticsLine(built: any): string
	for _, line in built.overlayControls.counterLines() do
		if string.sub(line, 1, 8) == "haptics=" then
			return line
		end
	end
	return "(no haptics line)"
end

describe("perf lab: the haptics counters (task 11)", function()
	it("is OFF by default, and the counter line says so rather than omitting itself", function()
		local built = newHarness()
		expect(#built.overlayControls.counterLines()).toBe(7)
		expect(hapticsLine(built)).toBe("haptics=off")
		built.dispose()
	end)

	it("a whole dense scroll with haptics ON moves NO haptic counter — it is event-driven", function()
		--[[ WHAT THIS HOST CAN AND CANNOT MEASURE, stated so the zero is read
			correctly. There is no `Instance` and no `Enum` under Lune, so the adapter
			can never CONSTRUCT here and `built` would read 0 whatever it did; the
			Instance-level pooling claim is proved against a scripted engine in
			tests/haptics.spec.luau, where the fake counts them.

			What THIS case proves is the other half, and it is the half the lab exists
			for: a dense scroll produces no feedback verbs at all, so the adapter is
			never even ASKED — `coalesced` and `plays` are both 0 across thirty scroll
			steps. The positive control below is what stops that from being a zero
			about a dead binding. ]]
		local built = newHarness(nil, { w = 360, h = 691 })
		built.steps.select(nil, "scenario=dense-scroll,rows=500,seed=1,haptics=on")
		built.steps.mount()
		built.steps.pass(nil, "scrollSteady=30")
		expect(hapticsLine(built)).toBe("haptics=on built=0 pooled=0 plays=0 coalesced=0")
		built.dispose()
	end)

	it("...and the SAME adapter hears a real verb, so the zero above is not a dead binding", function()
		local built, ctx = newHarness(nil, { w = 360, h = 691 })
		built.steps.select(nil, "scenario=dense-scroll,rows=500,seed=1,haptics=on")
		built.steps.mount()
		built.steps.pass(nil, "scrollSteady=30")
		expect(hapticsLine(built)).toBe("haptics=on built=0 pooled=0 plays=0 coalesced=0")
		-- TWO select verbs inside the rate-limit window. The coalescer runs BEFORE
		-- anything is constructed, so it is the one counter this engine-less host can
		-- move — and moving it proves the bus subscription is live.
		ctx.presenter.emitFeedback({ type = "select", path = "/Perf/Probe" })
		ctx.presenter.emitFeedback({ type = "select", path = "/Perf/Probe" })
		expect(hapticsLine(built)).toBe("haptics=on built=0 pooled=0 plays=0 coalesced=1")
		built.dispose()
	end)

	it("turning it back off disposes the adapter, and the line returns to `off`", function()
		local built, ctx = newHarness(nil, { w = 360, h = 691 })
		built.steps.select(nil, "scenario=dense-scroll,rows=200,seed=1,haptics=on")
		ctx.presenter.emitFeedback({ type = "select", path = "/Perf/Probe" })
		ctx.presenter.emitFeedback({ type = "select", path = "/Perf/Probe" })
		expect(hapticsLine(built)).toBe("haptics=on built=0 pooled=0 plays=0 coalesced=1")
		built.steps.select(nil, "haptics=off")
		expect(hapticsLine(built)).toBe("haptics=off")
		-- ...and a verb after the switch reaches nothing at all
		ctx.presenter.emitFeedback({ type = "select", path = "/Perf/Probe" })
		ctx.presenter.emitFeedback({ type = "select", path = "/Perf/Probe" })
		expect(hapticsLine(built)).toBe("haptics=off")
		built.dispose()
	end)
end)

--[[ THE SENSORY-CASCADE PASS (per-control feedback, 2026-08-13).

	The pass exists to answer one number the code cannot be read for: what a tree
	that declares NOTHING pays for a cascade nobody used. These cases do not judge
	the number — headless timings are a regression signal, and the lab's own note
	says so — they prove the INSTRUMENT is real: four arms actually mount, the
	presses actually land, and the declared arms actually carry the verb. A pass
	that drove nothing would report a beautifully fast press.
]]
describe("perf lab: the sensory-cascade pass measures something (director ask 2026-08-13)", function()
	it("runs four arms, and every one of them really pressed", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=sensory-cascade")
		local result = built.steps.pass(nil, "sensoryCascade=8").detail
		for _, armName in { "undeclared", "undeclaredRepeat", "declaredOnRoot", "declaredOnEveryLeaf" } do
			local arm = result[armName]
			expect(`{armName} ran:{arm ~= nil}`).toBe(`{armName} ran:true`)
			-- THE ANTI-VACUUM CHECK: an arm whose drive found no handler would be
			-- the fastest arm in the run and would mean nothing
			expect(`{armName} drove:{arm.pressesDriven}`).toBe(`{armName} drove:8`)
		end
		-- ...and the declaration is what the arms differ by: only the two declared
		-- arms put anything on the bus, because the undeclared ones emit `activate`
		-- (which they DO hear) — so the discriminator is the verb, asserted below
		expect(result.rows).toBe(120)
		expect(type(result.harnessSpreadMs)).toBe("number")
	end)

	it("the declared arms really carry the verb — the arms are not three copies", function()
		-- the pass's own numbers cannot show this (it counts events, not verbs), so
		-- the discriminator is asserted here rather than assumed from the arm names.
		local built, ctx = newHarness()
		built.steps.select(nil, "scenario=sensory-cascade")
		local seen: { string } = {}
		ctx.presenter.onFeedback(function(event: any)
			if event.reason == "activation" then
				table.insert(seen, event.type)
			end
		end)
		built.steps.pass(nil, "sensoryCascade=8")
		-- 4 arms x 8 presses; the two undeclared arms say `activate`, the two
		-- declared ones say `commit`
		local activates, commits = 0, 0
		for _, verb in seen do
			if verb == "activate" then
				activates += 1
			elseif verb == "commit" then
				commits += 1
			end
		end
		expect(`activate:{activates} commit:{commits}`).toBe("activate:16 commit:16")
	end)
end)

describe("perf lab: selectors and workload identity (PL-2/PL-10)", function()
	it("every declared workload names only passes the scenario implements", function()
		local built = newHarness()
		local declared = built.steps.workloads()
		-- TEN since resize-relayout joined them (director ask 2026-08-05): a continuous
		-- resize interleaved with single-value changes, which is the workload that
		-- makes the incremental-layout gap measurable instead of argued. ELEVEN since
		-- motion-flight joined (director ask 2026-08-14): the per-frame cost of an
		-- interpolating property, and what the size half adds to the position half.
		-- TWELVE since sensory-cascade joined (director ask 2026-08-13): what the
		-- per-control feedback cascade costs a tree that declares nothing, which is
		-- the number that decides whether a feature nobody uses charges every screen.
		-- FOURTEEN since the round-3 collection work got its own rows (2026-08-14):
		-- `variable-extents` (the running-offset index against the uniform arithmetic
		-- it replaces) and `table-unified` (`newTable{ virtualized = true }` carrying
		-- windowing, multi-selection and reordering at once). Both were unmeasurable
		-- before — every other workload windows by ONE number and none of them touches
		-- `newTable` at all.
		-- SIXTEEN since the two named levers joined (device-capture-2026-08-15 §7):
		-- `arrange-shapes` (arrange is the top cost in all four device captures and no
		-- workload was aimed at it) and `edit-locality` (incremental layout on a
		-- COLLECTION edit, the opposite case to the resize L-27 measured it inert on).
		-- Their passes live in `examples/performance/lab/levers.luau`, so this loop is
		-- also what proves that file's installation reached the declaration.
		-- SEVENTEEN since `host-move` joined (2026-08-17, the third named lever):
		-- `artifacts/nested-instance-tree/live-probes.md` §4 measured a container's
		-- engine writes collapse from 241 to 1 when it moves inside a real instance
		-- host; nothing pressed that at scale or asked whether it is a frame-time win
		-- (the nested tree's own standing risk). Its arms also live in `levers.luau`.
		expect(#declared.order).toBe(17)
		for _, w in declared.workloads do
			for _, passName in w.passes do
				-- `pass` refuses an unknown name, so an unimplemented pass in a
				-- declared sequence fails HERE rather than halfway through a capture
				local ok = pcall(function()
					built.steps.pass(nil, passName .. "=0")
				end)
				-- a pass may legitimately refuse (e.g. it needs a mounted list); what
				-- must never happen is "unknown pass"
				if not ok then
					local _, err = pcall(function()
						built.steps.pass(nil, passName .. "=0")
					end)
					expect(string.find(tostring(err), "unknown pass") == nil).toBe(true)
				end
			end
		end
		built.dispose()
	end)

	it("selecting a scenario adopts its implementation and content", function()
		local built = newHarness()
		local result = built.steps.select(nil, "scenario=large-text-overflow")
		expect(result.settings.implementation).toBe("facet")
		expect(result.settings.content).toBe("identity")
		expect(#result.datasetDigest).toBe(8)
		built.dispose()
	end)

	it("a settings pair that is not `key=value` is REFUSED, not silently dropped", function()
		--[[ THE SILENT-DROP CLASS (T15 review). `select` refuses an unknown KEY by
			name, and that care was undone one line earlier: anything not matching
			`key=value` was skipped without a word, so a settings string with the
			wrong punctuation applied fewer settings than it named.

			The shape that found it is the one asserted first. Clean capture is a
			STEP, not a setting, and a capture plan that wrote `cleanCapture:on`
			inside a settings string would have run every row with the overlay still
			mounted — a tree the census counts and the frame pays for — while every
			row claimed otherwise. The refusal names the offending text AND the
			spelling that would have worked, because "invalid" alone would leave the
			reader exactly where the silence did. ]]
		local built = newHarness()
		local ok1, err1 = pcall(function()
			built.steps.select(nil, "rows=200,cleanCapture:on")
		end)
		expect(ok1).toBe(false)
		expect(string.find(tostring(err1), "cleanCapture:on", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err1), "is a STEP", 1, true) ~= nil).toBe(true)

		-- ...and the settings BEFORE the bad pair are not quietly kept either: the
		-- call failed, so the caller must not be left with half of what it asked for
		expect(built.steps.counters().settings.rows ~= 200).toBe(true)

		-- a bare word with no `=` at all is the same refusal
		local ok2 = pcall(function()
			built.steps.select(nil, "turbo")
		end)
		expect(ok2).toBe(false)

		-- and the legal spelling still works, so this is a refusal and not a wall
		built.steps.select(nil, "rows=200,seed=3")
		expect(built.steps.counters().settings.rows).toBe(200)
		built.dispose()
	end)

	it("an unknown scenario and an unknown setting are both refused by name", function()
		local built = newHarness()
		local ok1, err1 = pcall(function()
			built.steps.select(nil, "scenario=go-faster")
		end)
		expect(ok1).toBe(false)
		expect(string.find(tostring(err1), "go%-faster") ~= nil).toBe(true)
		local ok2, err2 = pcall(function()
			built.steps.select(nil, "turbo=on")
		end)
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "turbo") ~= nil).toBe(true)
		built.dispose()
	end)

	it("the row count is clamped to the declared ceiling rather than honoured blindly", function()
		local built = newHarness()
		local result = built.steps.select(nil, `rows={dataset.MAX_ROWS * 10}`)
		expect(result.settings.rows).toBe(dataset.MAX_ROWS)
		built.dispose()
	end)
end)

describe("perf lab: exactly one implementation mounts (PL-5)", function()
	it("a second mount is refused, naming the rule", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=300,seed=5")
		built.steps.mount()
		local ok, err = pcall(function()
			built.steps.mount()
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "second implementation") ~= nil).toBe(true)
		built.dispose()
	end)

	it(
		"the native reference refuses to mount where the host seam is absent, rather than silently mounting nothing",
		function()
			local built = newHarness()
			built.steps.select(nil, "scenario=dense-scroll-native,rows=100")
			local ok, err = pcall(function()
				built.steps.mount()
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "HOST seam") ~= nil).toBe(true)
			built.dispose()
		end
	)
end)

describe("perf lab: virtualization stays bounded (PL-3/PL-4)", function()
	it("2000 logical rows mount a window, not a collection", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=2000,seed=11")
		local mounted = built.steps.mount()
		expect(mounted.logicalRows).toBe(2000)
		expect(mounted.mountedRows <= mounted.windowBound).toBe(true)
		-- the bound is a small multiple of the viewport, NOT a fraction of 2000
		expect(mounted.windowBound < 40).toBe(true)
		built.dispose()
	end)

	it("the window stays bounded across a full programmatic scroll sweep", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=2000,seed=11")
		built.steps.mount()
		local result = built.steps.pass(nil, "scrollSteady=30")
		expect(result.detail.mountedRows <= result.detail.windowBound).toBe(true)
		expect(result.detail.logicalRows).toBe(2000)
		expect(result.detail.drive).toBe("programmatic-steady")
		built.dispose()
	end)

	it("the bound is not a bigger row count away from firing: 20 000 rows window the same", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=20000,seed=11")
		local small = built.steps.mount()
		built.dispose()

		local built2 = newHarness()
		built2.steps.select(nil, "scenario=dense-scroll,rows=200,seed=11")
		local tiny = built2.steps.mount()
		built2.dispose()
		-- a windowed list mounts the same number of rows for 200 and 20 000
		expect(small.mountedRows).toBe(tiny.mountedRows)
	end)

	it("NEGATIVE CONTROL: the declared window fault makes the mount FAIL, naming the defect", function()
		-- "It must fail if virtualized mounts the full logical collection" is the
		-- plan's wording, and this is that sentence executed. The lab breaks its own
		-- windowing through a first-class step (so the same proof can be driven in
		-- Studio), and the SAME assertion every scroll step runs must refuse it.
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=60,seed=1")
		local fault = built.steps.fault(nil, "window=on")
		expect(fault.active).toBe(true)
		local ok, err = pcall(function()
			built.steps.mount()
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "NOT bounded") ~= nil).toBe(true)
		expect(string.find(tostring(err), "60 rows mounted") ~= nil or string.find(tostring(err), "logical 60") ~= nil).toBe(
			true
		)
		-- and clearing the fault restores a bounded mount, so the case proves the
		-- rule fires ON the defect rather than on everything
		built.steps.fault(nil, "window=off")
		local mounted = built.steps.mount()
		expect(mounted.mountedRows <= mounted.windowBound).toBe(true)
		built.dispose()
	end)

	it("scrolling a virtualized list does NOT grow the reactive core (the row must own its controls)", function()
		-- THE DURABLE REGRESSION for the leak this stage found live. `newStepper`
		-- builds its own scope and returns a `dispose`; the first version of the row
		-- never owned it, so every materialized row left four memos and a scope
		-- behind — 400 scroll steps took the core from 96 memos / 31 scopes to
		-- 17 078 / 4 278, all still subscribed to live value signals.
		--
		-- The assertion is a BOUND on growth rather than equality: the row's
		-- owner-held value/toggle signals are keyed by item id and are deliberately
		-- retained (a control whose value resets on scroll is a different workload),
		-- so signals climb toward the row count and stop. Memos and scopes are the
		-- ones that must not scale with rows VISITED.
		local built, _ctx, core = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=600,seed=12")
		built.steps.mount()
		local base = core:counters()
		for _ = 1, 6 do
			built.steps.pass(nil, "scrollSteady=40")
		end
		local after = core:counters()
		-- 240 scroll steps over 600 rows materializes hundreds of distinct rows; a
		-- per-row control leak would be in the thousands here
		expect(after.memos - base.memos < 200).toBe(true)
		expect(after.scopes - base.scopes < 200).toBe(true)
		-- SIGNALS TOO (reactive-runtime review, RR-11): the first version of this case
		-- bounded memos and scopes and said nothing about signals, which is the other
		-- half of the same live defect — a Studio reset once left 488 undisposed
		-- signals. They legitimately grow toward two per row VISITED (the owner-held
		-- value and toggle), so the bound is that rule with slack, not a flat number.
		expect(after.signals - base.signals <= 2 * 600 + 64).toBe(true)
		built.dispose()
	end)

	it("collection churn keeps the window bounded through insert, remove and reorder", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=collection-churn,rows=800,seed=3")
		built.steps.mount()
		local inserted = built.steps.pass(nil, "insert=10")
		expect(inserted.detail.logicalRows).toBe(810)
		expect(inserted.detail.mountedRows <= built.report().windowBound).toBe(true)
		local removed = built.steps.pass(nil, "remove=10")
		expect(removed.detail.logicalRows).toBe(800)
		local reordered = built.steps.pass(nil, "reorder=5")
		expect(reordered.detail.mountedRows <= built.report().windowBound).toBe(true)
		built.dispose()
	end)
end)

describe("perf lab: the workload paints inside its own boxes at every viewport (PL-3)", function()
	-- WHY THIS EXISTS. The lab shipped a row that overflowed its box by 132px on every
	-- phone in portrait and painted over its neighbours. The solver diagnosed it
	-- correctly — eighteen findings on a 359x718 device, in the exact words of the
	-- defect — and nothing asked. Every capture had been taken at 907x1067, where the
	-- row happens to fit, and the device-matrix rows asserted only that the mounted
	-- WINDOW was bounded. A screenshot from a real phone is what found it.
	--
	-- The lab now refuses to mount on a layout finding. This sweeps the viewports the
	-- canonical matrix uses plus the narrowest supported phone, so the class cannot
	-- return through a viewport nobody drove.
	local VIEWPORTS = {
		{ 320, 640, "narrowest supported phone portrait" },
		{ 359, 718, "the device that exposed the defect" },
		{ 390, 844, "compact phone portrait" },
		{ 667, 375, "small phone landscape" },
		{ 844, 390, "compact phone landscape" },
		{ 1080, 810, "tablet landscape" },
		{ 1280, 720, "desktop" },
		{ 1920, 1080, "console / ten-foot" },
	}

	for _, vp in VIEWPORTS do
		local w, h, why = vp[1], vp[2], vp[3]
		it(`mounts and windows cleanly at {w}x{h} ({why})`, function()
			local built = newHarness(nil, { w = w, h = h })
			built.steps.select(nil, "scenario=dense-scroll,rows=2000,seed=1")
			-- `mount` runs the solver's own layout audit and refuses on any finding, so
			-- reaching the assertions below IS the no-overlap proof
			local mounted = built.steps.mount()
			expect(mounted.mountedRows <= mounted.windowBound).toBe(true)
			expect(mounted.logicalRows).toBe(2000)
			built.steps.pass(nil, "scrollSteady=8")
			built.dispose()
		end)
	end

	it("survives ROTATION after mounting — the case a real device found", function()
		-- Mount in landscape, rotate to portrait, and the rows must restack. They did
		-- not: `compact` is read once when a cell is built and `UI.ForEach` never
		-- rebuilds a row whose key is unchanged, so one-line rows survived into a
		-- 359px-wide, 152px-tall portrait slot — twelve layout findings, and visibly
		-- rows painted over each other on the device.
		--
		-- The eight-viewport sweep above could never catch this: every case there
		-- mounts at its final size. Only a size CHANGE after mount reproduces it.
		local built, ctx = newHarness(nil, { w = 844, h = 390 })
		built.steps.select(nil, "scenario=dense-scroll,rows=2000,seed=1")
		built.steps.mount()
		-- rotate back and forth; each pass runs the layout audit, which refuses on any
		-- finding, so completing the loop IS the proof
		for _ = 1, 3 do
			ctx.env:set("viewportRect", { x = 0, y = 0, w = 359, h = 718 })
			ctx.presenter.refresh()
			built.steps.pass(nil, "scrollSteady=20")
			ctx.env:set("viewportRect", { x = 0, y = 0, w = 844, h = 390 })
			ctx.presenter.refresh()
			built.steps.pass(nil, "scrollSteady=20")
		end
		expect(built.report().mountedImplementation).toBe("facet")
		built.dispose()
	end)

	it("the scenario cycler steps through every workload and WRAPS at both ends", function()
		-- The picker is nine chips in a ScrollView inside a panel capped at a third of
		-- a phone screen, so on the device every chip sat below the fold and there was
		-- no visible way to change the scenario at all. The cycler is the fix, so its
		-- behaviour is pinned rather than eyeballed.
		local built = newHarness()
		local c = built.overlayControls
		local order = built.report().workloads
		expect(#order > 1).toBe(true)

		-- forward through the whole list and back to the start
		local seen = {}
		local start = c.currentScenario()
		for _ = 1, #order do
			-- cycling never throws, even onto a workload this environment cannot mount:
			-- the label moves and the failure lands on the status line
			c.cycleScenario(1)
			table.insert(seen, c.currentScenario())
		end
		expect(#seen).toBe(#order)
		-- every workload visited exactly once, and the last step wrapped home
		local unique = {}
		for _, name in seen do
			expect(unique[name]).toBe(nil)
			unique[name] = true
		end
		expect(seen[#seen]).toBe(start)

		-- backwards wraps too: from the first entry, -1 lands on the last
		c.selectScenario(order[1])
		c.cycleScenario(-1)
		expect(c.currentScenario()).toBe(order[#order])
		built.dispose()
	end)

	it("the cycler reports its position, so the panel can say which of the nine you are on", function()
		local built = newHarness()
		local c = built.overlayControls
		local order = built.report().workloads
		c.selectScenario(order[1])
		expect(c.scenarioPosition()).toBe(`1/{#order}`)
		c.cycleScenario(1)
		expect(c.scenarioPosition()).toBe(`2/{#order}`)
		c.cycleScenario(-1)
		expect(c.scenarioPosition()).toBe(`1/{#order}`)
		built.dispose()
	end)

	it("cycling actually REMOUNTS the workload, it does not just relabel it", function()
		-- the failure this guards: a cycler that moves the label while the previously
		-- mounted scenario keeps running, so every number after it is mislabelled
		local built = newHarness()
		local c = built.overlayControls
		expect(c.selectScenario("dense-scroll")).toBe(true)
		expect(built.report().settings.scenario).toBe("dense-scroll")
		expect(built.report().mountedImplementation).toBe("facet")
		c.cycleScenario(1)
		expect(built.report().settings.scenario).toBe(c.currentScenario())
		expect(built.report().settings.scenario ~= "dense-scroll").toBe(true)
		built.dispose()
	end)

	it("a viewport change DROPS the overlay's stale reservation before the workload re-solves", function()
		-- Found by pressing Run all: `layout-style-churn` drives 907x1044 -> 390x844 ->
		-- 844x390, and the overlay's 268px reservation (measured on the tall screen)
		-- was still in `coreSafeInsets.bottom` when the workload re-solved against the
		-- short one. Content box: 64px. Overflow: 75px. The remount that the
		-- arrangement observer had just started failed inside a reactive flush, so the
		-- lab sat unmounted and the NEXT pass reported "call `mount` first" — a
		-- misleading message three steps downstream of the actual fault.
		local built, ctx = newHarness(nil, { w = 907, h = 1044 })
		built.steps.select(nil, "scenario=dense-scroll,rows=500,seed=1")
		built.steps.mount()

		-- the shapes the resize pass actually uses, each one audited on arrival
		for _, shape in { { 390, 844 }, { 844, 390 }, { 1280, 720 }, { 907, 1044 } } do
			ctx.env:set("viewportRect", { x = 0, y = 0, w = shape[1], h = shape[2] })
			ctx.presenter.refresh()
			-- `pass` runs the layout audit over both surfaces and refuses on a finding,
			-- so completing the loop IS the assertion
			built.steps.pass(nil, "scrollSteady=10")
			expect(built.report().mountedImplementation).toBe("facet")
			expect(built.report().lastRemountError).toBe(nil)
		end
		built.dispose()
	end)

	it("the full resize pass leaves the workload MOUNTED, so the next pass has something to measure", function()
		-- the surfaced symptom, pinned at the level a driver sees it
		local built = newHarness(nil, { w = 907, h = 1044 })
		built.steps.select(nil, "scenario=layout-style-churn")
		built.steps.mount()
		built.steps.pass(nil, "preferenceSweep=1")
		built.steps.pass(nil, "resize=1")
		expect(built.report().mountedImplementation).toBe("facet")
		expect(built.report().mountedRows > 0).toBe(true)
		built.dispose()
	end)

	it("selecting a scenario RESTORES the settings it does not declare", function()
		-- Found by pressing Run all on a phone. `large-text-overflow` declares
		-- `content = "identity"`; every workload after it in the sweep inherited long
		-- identity strings, and three of them failed a layout audit for a reason that
		-- had nothing to do with them. Each passed when run alone — an order-dependent
		-- failure is the worst shape a determinism bug can take, because the obvious way
		-- to reproduce it is the one way that hides it.
		local built = newHarness()
		built.steps.select(nil, "scenario=large-text-overflow")
		expect(built.report().settings.content).toBe("identity")
		built.steps.select(nil, "scenario=dense-scroll")
		expect(built.report().settings.content).toBe("normal")
		built.dispose()
	end)

	it("the identity workload walks its whole collection cleanly at every phone width", function()
		-- Broad coverage for the sweep failure the director found on a phone: a long
		-- identity name wrapped to a second line and painted 5px into the next row.
		--
		-- NOT A PROOF OF THE `lineLimit` FIX, and said so rather than implied. Removing
		-- `lineLimit` from `rows.cell` leaves this GREEN: headless text measurement does
		-- not wrap the way the engine does, so the second line never appears here. The
		-- fix is proven in Studio at 360x691, where the same sweep goes from 1 failure
		-- to 0 — recorded in artifacts/performance-stress-places/studio/. What this
		-- case does buy is the walk itself: every window of the collection is audited at
		-- four phone widths, which is more than any other case here covers.
		for _, vp in { { 320, 640 }, { 360, 691 }, { 390, 844 }, { 430, 932 } } do
			local built = newHarness(nil, { w = vp[1], h = vp[2] })
			built.steps.select(nil, "scenario=large-text-overflow")
			built.steps.mount()
			expect(built.report().mountedImplementation).toBe("facet")
			-- WALK THE WHOLE COLLECTION. The defect needs a long name, a narrow box AND
			-- that row inside the window at the moment the audit runs; a short scroll
			-- samples a handful of names and misses it, which is exactly how it reached
			-- a device. Each pass runs the audit, so completing the walk is the proof.
			for _ = 1, 12 do
				built.steps.pass(nil, "scrollSeek=40")
			end
			built.dispose()
		end
	end)

	it("Run all sweeps every workload and ONE failure does not end the sweep", function()
		-- The raw-Roblox reference needs a host seam only the real place supplies, so
		-- headlessly `dense-scroll-native` cannot mount. That is the exact shape of the
		-- bug this guards: the first version let the error out and everything after the
		-- fourth workload silently never ran.
		local built = newHarness()
		local order = built.report().workloads
		local out = built.steps.sequence(nil, nil)
		expect(out.planned).toBe(#order)
		expect(out.ran).toBe(#order)
		-- at least one workload is unmountable here, and it is REPORTED rather than fatal
		expect(out.failed > 0).toBe(true)
		expect(out.completedWholeSweep).toBe(false)
		local named = false
		for _, r in out.results do
			if r.failed then
				expect(type(r.error)).toBe("string")
				expect(type(r.scenario)).toBe("string")
				named = true
			end
		end
		expect(named).toBe(true)
		-- and the sweep leaves nothing mounted, so a dump taken now measures the idle place
		expect(built.report().mountedImplementation).toBe("none")
		built.dispose()
	end)

	it("Run all ends by saying how to take the dump", function()
		-- the end state is an instruction: the sweep is over and the profiler buffer is
		-- full, so the next action is a key press and the lab names it
		local built = newHarness()
		local out = built.steps.sequence(nil, nil)
		expect(string.find(out.dumpNext, "F6") ~= nil).toBe(true)
		expect(string.find(out.dumpNext, "binary format") ~= nil).toBe(true)
		built.dispose()
	end)

	it("the emergency stop halts Run all between workloads and says where it stopped", function()
		local built = newHarness()
		built.steps.stop()
		local out = built.steps.sequence(nil, nil)
		expect(out.stopped).toBe(true)
		expect(out.ran).toBe(0)
		expect(out.completedWholeSweep).toBe(false)
		built.dispose()
	end)

	it("NEGATIVE CONTROL: a row that cannot fit its slot FAILS the mount", function()
		-- the one-line arrangement forced onto a phone — the exact shipped defect —
		-- must be refused, or the audit is decoration
		local built = newHarness(nil, { w = 359, h = 718 }, { forceOneLineRow = true })
		built.steps.select(nil, "scenario=dense-scroll,rows=200,seed=1")
		local ok, err = pcall(function()
			built.steps.mount()
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "MOUNT REFUSED") ~= nil).toBe(true)
		-- WORDING UPDATED 2026-08-13, and the reason is a device report rather than
		-- a rename. The raised message used to carry two sentences of explanation
		-- plus up to four `path [rect]: issue` triples inline, and on a phone it was
		-- CUT OFF ON SCREEN before reaching the findings it exists to deliver — the
		-- diagnostic defeating its own purpose, which is that "the solver already
		-- knew and nobody read it". The findings now go to the console one `warn`
		-- per line (all of them, not the first four) and the raise stays short
		-- enough to fit a status line.
		--
		-- What this case guards is unchanged: the mount is REFUSED and the reason
		-- names the layout findings. The "describes a screen nobody would ship"
		-- clause is the surviving half of the old sentence and is what keeps this
		-- from passing on any error that merely mentions the words.
		-- THE MESSAGE LEADS WITH THE FINDING, not with a count. Two device reports
		-- showed the old shape cut off on a phone before reaching anything
		-- actionable, so what a reader can act on goes FIRST: the offending node
		-- and what the solver said about it.
		expect(string.find(tostring(err), "MOUNT REFUSED") ~= nil).toBe(true)
		expect(string.find(tostring(err), "overflows") ~= nil).toBe(true)
		built.dispose()
	end)
end)

describe("perf lab: run, stop, reset and clean capture (PL-10/PL-11)", function()
	it("running a scenario executes its declared sequence and records each pass separately", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=400,seed=2")
		built.steps.mount()
		local result = built.steps.run()
		expect(result.scenario).toBe("dense-scroll")
		expect(#result.passes).toBe(7)
		local names: { [string]: boolean } = {}
		for _, p in result.passes do
			names[p.pass] = true
		end
		-- scroll, focus, selection and update work are labeled APART, which is what
		-- makes a profile attributable
		expect(names.scrollSteady).toBe(true)
		expect(names.scrollSeek).toBe(true)
		expect(names.focusTraverse).toBe(true)
		expect(names.selectRow).toBe(true)
		expect(names.updateOne).toBe(true)
		expect(names.updateBatch).toBe(true)
		built.dispose()
	end)

	it("the emergency stop halts a running sequence between passes", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=200,seed=2")
		built.steps.mount()
		built.steps.stop()
		local result = built.steps.run()
		expect(result.stopped).toBe(true)
		expect(#result.passes).toBe(0)
		built.steps.resume()
		expect(built.report().emergencyStopped).toBe(false)
		built.dispose()
	end)

	it("the ramp climbs its declared ladder and stops when told", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=mount-ramp,seed=4")
		local result = built.steps.pass(nil, "ramp=3")
		expect(#result.detail.steps).toBe(3)
		expect(result.detail.ceiling).toBe(dataset.MAX_ROWS)
		for _, step in result.detail.steps do
			expect(step.mountedRows <= step.windowBound).toBe(true)
		end
		built.dispose()
	end)

	it("reset returns to the idle baseline and PROVES the workload is unmounted", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=600,seed=8")
		built.steps.mount()
		expect(built.report().mountedImplementation).toBe("facet")
		local result = built.steps.reset()
		expect(result.mounted).toBe(false)
		expect(built.report().mountedImplementation).toBe("none")
		expect(built.report().settings.scenario).toBe("idle-baseline")
		-- the overlay survives a reset by design and is reported separately, so a
		-- reader never mistakes it for leaked workload
		expect(result.overlayMounted).toBe(true)
		built.dispose()
	end)

	it("clean capture DISMISSES the overlay rather than hiding it", function()
		local built = newHarness()
		expect(built.report().overlayMounted).toBe(true)
		local off = built.steps.cleanCapture(nil, "on")
		expect(off.overlayMounted).toBe(false)
		expect(built.report().overlayMounted).toBe(false)
		local on = built.steps.cleanCapture(nil, "off")
		expect(on.overlayMounted).toBe(true)
		built.dispose()
	end)
end)

describe("perf lab: a capture row is admissible or it is refused (PL-9)", function()
	it("a fully conditioned row is admissible and carries the whole workload identity", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=500,seed=6")
		built.steps.mount()
		local exported = built.steps.export(nil, "1")
		expect(exported.admissible).toBe(true)
		expect(#exported.problems).toBe(0)
		local row = exported.row
		expect(row.scenario).toBe("dense-scroll")
		expect(row.datasetVersion).toBe(dataset.VERSION)
		expect(row.rowVersion).toBe(rowsLib.VERSION)
		expect(row.evidenceClass).toBe("lune")
		expect(#row.datasetDigest).toBe(8)
		built.dispose()
	end)

	it("a row missing its conditions is INADMISSIBLE and says which ones", function()
		local built = newHarness({
			facts = function()
				-- a host that forgot the viewport and the graphics quality: exactly
				-- the shape of a capture nobody can compare later
				return { evidenceClass = "lune", capturedAtIso = "2026-08-04T00:00:00Z" }
			end,
		})
		built.steps.select(nil, "scenario=dense-scroll,rows=100,seed=6")
		local exported = built.steps.export(nil, "1")
		expect(exported.admissible).toBe(false)
		local joined = table.concat(exported.problems, "|")
		expect(string.find(joined, "viewport") ~= nil).toBe(true)
		built.dispose()
	end)

	it("a Studio row cannot become a device row by relabelling", function()
		local studioRow = {
			schema = captureLib.SCHEMA,
			evidenceClass = "phone-physical",
			studioVersion = "0.732.0.7320589",
		}
		local problems = captureLib.problems(studioRow)
		local joined = table.concat(problems, "|")
		expect(string.find(joined, "retail client has none") ~= nil).toBe(true)
		expect(string.find(joined, "deviceModel") ~= nil).toBe(true)
	end)

	it("two captures are the same workload only when every identity field agrees", function()
		local a = { scenario = "dense-scroll", rows = 2000, seed = 1, theme = "flat" }
		local b = { scenario = "dense-scroll", rows = 2000, seed = 1, theme = "flat" }
		expect((captureLib.sameWorkload(a, b))).toBe(true)
		b.theme = "fantasy_ornate"
		local same, differences = captureLib.sameWorkload(a, b)
		expect(same).toBe(false)
		expect(string.find(table.concat(differences, "|"), "theme") ~= nil).toBe(true)
	end)
end)

describe("perf lab: the row is the shape the plan requires (PL-3)", function()
	it("a row carries an image, a two-line text stack, and three controls", function()
		local core = Facet.newCore()
		local provider = Facet.newResourceProvider(core)
		local scope = core:scope("row-shape")
		local item = dataset.build({ count = 1, seed = 1 })[1]
		local bp = rowsLib.cell(Facet, core, item, {
			scope = scope,
			provider = provider,
			values = {},
			toggles = {},
		})
		-- a blueprint node is { id, class, props, children } — `children` sits at the
		-- TOP level, not inside props (probed against the live constructor, not
		-- assumed)
		local classes: { [string]: number } = {}
		local ids: { [string]: boolean } = {}
		local function walk(node: any)
			if type(node) ~= "table" then
				return
			end
			if node.class ~= nil then
				classes[tostring(node.class)] = (classes[tostring(node.class)] or 0) + 1
			end
			if node.id ~= nil then
				ids[tostring(node.id)] = true
			end
			if type(node.children) == "table" then
				for _, child in node.children do
					walk(child)
				end
			end
		end
		walk(bp)
		expect(classes.HStack ~= nil).toBe(true)
		expect(classes.VStack ~= nil).toBe(true)
		expect(ids.Row).toBe(true)
		expect(ids.Labels).toBe(true)
		expect(ids.Name).toBe(true)
		expect(ids.Detail).toBe(true)
		expect(ids.Ready).toBe(true) -- the toggle
		expect(ids.Open).toBe(true) -- the button
		expect(ids.Rate).toBe(true) -- the value control
		scope:dispose()
	end)

	it("the identity line keeps its full-value disclosure — the profile is not bought with accessibility", function()
		local core = Facet.newCore()
		local provider = Facet.newResourceProvider(core)
		local scope = core:scope("row-disclose")
		local item = dataset.build({ count = 1, seed = 1, content = "identity" })[1]
		local bp = rowsLib.cell(Facet, core, item, {
			scope = scope,
			provider = provider,
			values = {},
			toggles = {},
		})
		local found = false
		local function walk(node: any)
			if type(node) ~= "table" then
				return
			end
			if node.id == "Name" and node.props ~= nil and node.props.disclose == true then
				found = true
			end
			if type(node.children) == "table" then
				for _, child in node.children do
					walk(child)
				end
			end
		end
		walk(bp)
		expect(found).toBe(true)
		scope:dispose()
	end)

	it("the mounted-window rule is arithmetic over the viewport, not a remembered constant", function()
		local pitch = rowsLib.ROW_HEIGHT + rowsLib.ROW_GAP
		expect(rowsLib.expectedWindow(pitch * 10)).toBe(10 + 2 * rowsLib.OVERSCAN + 2)
		expect(rowsLib.expectedWindow(pitch * 20) > rowsLib.expectedWindow(pitch * 10)).toBe(true)
	end)
end)

-- A THEME IS TWO HALVES AND THE LAB ONLY EVER INSTALLED ONE (found 2026-08-05,
-- from the director's ornate report; optimization-log L-26).
--
-- `applyThemeByName` called `ctx.themeChrome.setPackage(pkg)`, which is
-- `adapter.setThemePackage` — the DECORATION half. The METRIC half (the resolved
-- snapshot, published as `themeMetrics` so the solver reserves the recipe's
-- `contentInsets`) was never committed at all. So the adapter painted
-- fantasy-ornate art onto a surface the solver had measured with Studio Neutral.
--
-- Measured live at 360x691 before the fix: an `Open` button 60x46 with
-- `TextSize = 18` (Studio Neutral's `control` size; ornate's is 17), 36px of text
-- and 12+12 of neutral button padding — no trace of the 14+14 the ornate recipe
-- asks for. The paint seam then lifted the label by that 14+14 it never got, so
-- EVERY lifted label came out short by exactly 28 - 24 = **4px**, at every
-- control size and every label length. Constant, because both terms are.
--
-- Nothing else could see it. The solver is right about the tree it was given, and
-- the census that DID catch the symptom sits downstream of the lift. The one
-- instrument that would have named the cause is this: does the environment the
-- solver reads actually wear the theme the capture row claims?
describe("perf lab: installing a theme installs BOTH halves (L-26)", function()
	local ornateModule = require("../examples/themes/fantasy_ornate")

	local function themedHarness()
		local built, ctx, core = newHarness(nil, { w = 360, h = 691 })
		ctx.themePackages = { fantasy_ornate = ornateModule }
		return built, ctx, core
	end

	it("selecting a theme publishes its METRICS to the environment, not only its art", function()
		local built, ctx = themedHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=40,seed=1,theme=fantasy_ornate")
		local metrics = ctx.env:get("themeMetrics"):get()
		expect(metrics.identity.packageId).toBe("fantasy-ornate")
	end)

	it("...so the SOLVER reserves the recipe's contentInsets a lifted label is painted into", function()
		-- The defect stated as geometry rather than as identity: the ornate
		-- `control` recipe asks for 14 per side, so a button measured under it must
		-- be at least 28px wider than the same button measured flat. Before the fix
		-- the difference was 0 and the paint seam took the 28 anyway.
		local function openWidth(theme: string): number
			local built, ctx = themedHarness()
			built.steps.select(nil, `scenario=dense-scroll,rows=40,seed=1,theme={theme}`)
			built.steps.mount()
			local widest = 0
			for _, path in (ctx.adapter :: any).paths() do
				if string.sub(path, -5) == "/Open" then
					local node = (ctx.adapter :: any).node(path)
					if node ~= nil and node.rect ~= nil then
						widest = math.max(widest, node.rect.w)
					end
				end
			end
			return widest
		end
		local flat = openWidth("flat")
		local ornate = openWidth("fantasy_ornate")
		expect(flat > 0).toBe(true)
		expect(`ornate={ornate} flat={flat} grew={ornate - flat >= 28}`).toBe(`ornate={ornate} flat={flat} grew=true`)
	end)

	it("a theme the environment does not wear is REFUSED, not painted half-on", function()
		-- The paint half succeeding while the metric half is missing is exactly the
		-- state that shipped. `applyThemeByName` already refuses a package it cannot
		-- compile; it must refuse a metric commit it cannot make for the same reason.
		local built, ctx = themedHarness()
		ctx.env.set = function()
			error("themeMetrics refused", 0)
		end
		local ok = pcall(function()
			built.steps.select(nil, "scenario=dense-scroll,rows=40,seed=1,theme=fantasy_ornate")
		end)
		expect(ok).toBe(false)
	end)

	-- THE CLAIM THE WORKLOAD VERSION RESTS ON. Fixing this meant giving the row
	-- geometry contract a theme term, and a changed row module would normally mean a
	-- new `rows.VERSION` — which would make all eighteen recorded captures stale and
	-- demand a full re-record. It does not, and the reason has to be provable rather
	-- than argued: `chromeInsets` is all zeros on every flat package, so the term is
	-- exactly 0 there, the split branch is unreachable, and the FLAT workload every
	-- recorded row measured is byte-identical to the one the source builds today.
	--
	-- Stated against the constants rather than against a remembered number, so it
	-- still bites if someone gives the flat path a non-zero term later.
	it("the FLAT row geometry is byte-identical — which is why the workload version holds", function()
		local neutral = Facet.themes.neutral()
		expect(rowsLib.themeInset(neutral).x).toBe(0)
		expect(rowsLib.themeInset(neutral).y).toBe(0)
		expect(rowsLib.themeInset(nil).x).toBe(0)
		expect(rowsLib.splitControlsFor(360, neutral)).toBe(false)
		expect(rowsLib.splitControlsFor(320, neutral)).toBe(false)
		for _, compact in { false, true } do
			for _, scale in { 1, 1.5, 2 } do
				local bare = rowsLib.heightFor(compact, scale)
				expect(`compact={compact} scale={scale} h={rowsLib.heightFor(compact, scale, neutral)}`).toBe(
					`compact={compact} scale={scale} h={bare}`
				)
			end
		end
		expect(rowsLib.expectedWindow(691, true, 1, neutral)).toBe(rowsLib.expectedWindow(691, true, 1))
	end)

	-- ...and the ornate row is a DIFFERENT height, or the term above is decoration.
	it("a themed row reserves the recipe's vertical inset per control line", function()
		local snap = Facet.themes.resolve(ornateModule.build(Facet.themes), nil, {})
		local inset = rowsLib.themeInset(snap)
		expect(inset.y > 0).toBe(true)
		-- one control line in the one-line form, two in the compact form
		expect(rowsLib.heightFor(false, 1, snap) - rowsLib.heightFor(false, 1)).toBe(inset.y)
		expect(rowsLib.heightFor(true, 1, snap) - rowsLib.heightFor(true, 1)).toBe(inset.y * 2)
		-- and the split arrangement charges a third line plus the control it adds
		local split = rowsLib.heightFor(true, 1, snap, true) - rowsLib.heightFor(true, 1, snap)
		expect(split).toBe(inset.y + rowsLib.controlHeight(snap) + rowsLib.COMPACT_LINE_GAP)
	end)
end)

--[[ THE CAPTURE-AIMING GUARDS (device captures 1 and 2, 2026-08-13).

	Two consecutive physical-device MicroProfiler captures recorded ZERO
	occurrences of `measure`, `arrange`, `commit`, `mount`, `react` and `reset` —
	the six scopes every device estimate in artifacts/performance-stress-places/
	rests on, and the reason the 22x extrapolation in low-end-target.md is still
	untested. Neither failure was a workload defect. Both were AIMING failures:

	  capture 1: `Run all` sweeps ten workloads over tens of seconds; a dump holds
	             ~30 frames / ~1.3s, so it sampled ~3% of the sweep and drew
	             `dense-scroll-native`.
	  capture 2: `profileWindow` looped `steps.run()`, which runs the workload's
	             WHOLE declared pass list; `scrollSteady` alone is 60 steps, so the
	             window could not escape pass #1 — and the selected workload was
	             again the native reference, which calls no Facet code at all.

	Nothing on screen said which implementation was mounted, so both mistakes were
	invisible until the dump was parsed. These cases are the guards that make them
	impossible rather than merely unlikely.
]]
describe("perf lab: profileWindow cannot be aimed at nothing (device captures 1 and 2)", function()
	it("REFUSES the raw-Roblox reference unless it is asked for by name", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll-native,rows=50,seed=1")
		local ok, err = pcall(function()
			built.steps.profileWindow(nil, nil)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "calls NO Facet code") ~= nil).toBe(true)
		expect(string.find(tostring(err), "zero solver scopes") ~= nil).toBe(true)
		built.dispose()
	end)

	it("...and the refusal names the explicit spelling that overrides it", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll-native,rows=50,seed=1")
		local _, err = pcall(function()
			built.steps.profileWindow(nil, nil)
		end)
		-- the escape hatch must be in the message: profiling the native reference is
		-- legitimate, it just has to be asked for in words
		expect(string.find(tostring(err), "profileWindow:dense%-scroll%-native") ~= nil).toBe(true)
		built.dispose()
	end)

	it("refuses a pass the workload does not declare, and lists the ones it does", function()
		local built = newHarness()
		local ok, err = pcall(function()
			built.steps.profileWindow(nil, "dense-scroll:notAPass")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "declares no pass") ~= nil).toBe(true)
		expect(string.find(tostring(err), "scrollSteady") ~= nil).toBe(true)
		built.dispose()
	end)

	it("refuses an unknown workload and lists the legal set", function()
		local built = newHarness()
		local ok, err = pcall(function()
			built.steps.profileWindow(nil, "not-a-workload")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unknown workload") ~= nil).toBe(true)
		expect(string.find(tostring(err), "dense%-scroll") ~= nil).toBe(true)
		built.dispose()
	end)

	it("loops ONE pass — not the workload's whole declared sequence", function()
		-- the capture-2 defect, asserted directly: `dense-scroll` declares seven
		-- passes, and a profiling window must contain exactly the one it was aimed
		-- at. Stop after the first lap so this terminates.
		local built = newHarness()
		local ran: { string } = {}
		local realRun = built.steps.run
		built.steps.run = function(...)
			table.insert(ran, "run")
			return realRun(...)
		end
		-- bounded to two laps: the loop is unbounded by design (a fixed duration
		-- re-creates the aiming problem one level down), and Lune has no `task` to
		-- interrupt it from, so the cap is how this is assertable at all
		local out = built.steps.profileWindow(nil, "dense-scroll:scrollSteady:2")
		expect(out.pass).toBe("scrollSteady")
		expect(out.scenario).toBe("dense-scroll")
		expect(out.implementation).toBe("facet")
		expect(out.laps).toBe(2)
		-- steps.run would have executed all seven passes; profileWindow must not use it
		expect(#ran).toBe(0)
		built.dispose()
	end)
end)

--[[ DEVICE CAPTURE 5, 2026-08-15: THE THIRD AIMING FAILURE — a pass that runs.

	`asyncImage.html` (SM-A102U1, tier 3) holds twenty-nine BYTE-IDENTICAL frames:
	2 arranges, 2 measures, 0 mounts, 0 `Facet/resource`, every frame. The
	workload was `async-image-churn` and the looped pass was `w.passes[1]` =
	`imagesCold`, whose whole body is `settings.resourceState = "cold"` plus one
	`presenter.refresh()`. Reproduced headless to the unit
	(`tools/lune/_probe_profile_aim`): one lap = 1 arrange, 0 mounts, 0 resources.

	This is NOT the `dense-scroll-native` failure above (a workload with no
	framework in it) and NOT the `steps.run` failure (a window that cannot escape
	pass #1). It is a pass that is legitimate INSIDE the workload's declared
	sequence — cold, warm, fail, reuse is a meaningful order — and meaningless on a
	loop, because looping it re-sets a flag that is already set. Only `imagesReuse`
	churns the window, so only `imagesReuse` is profilable.

	Two guards, because they fail differently: `profilePass` aims the default, and
	`lapWork` makes ANY future version of this mistake visible ON THE PHONE instead
	of after a binary dump has been parsed. ]]
describe("perf lab: profileWindow cannot be aimed at a pass that does nothing (device capture 5)", function()
	it("loops the workload's declared PROFILE pass, not blindly its first one", function()
		local built = newHarness()
		local out = built.steps.profileWindow(nil, "async-image-churn::1")
		-- `imagesCold` is passes[1] and is the pass the device capture wasted
		expect(out.pass).toBe("imagesReuse")
		expect(out.scenario).toBe("async-image-churn")
		built.dispose()
	end)

	it("...and an explicitly named pass still overrides it", function()
		local built = newHarness()
		local out = built.steps.profileWindow(nil, "async-image-churn:imagesCold:1")
		expect(out.pass).toBe("imagesCold")
		built.dispose()
	end)

	it("reports what ONE lap provoked, so an empty capture is visible before it is taken", function()
		-- the REAL profile module, for the reason the resizeStorm case records: a
		-- stub's `byScope` is always empty and a check reading zeros from it proves
		-- nothing
		local built = newHarness({ profile = profile })
		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function() end, function() end)
		local ok, result = pcall(function()
			local churn = built.steps.profileWindow(nil, "async-image-churn:imagesReuse:1")
			local inert = built.steps.profileWindow(nil, "async-image-churn:imagesCold:1")
			return { churn = churn, inert = inert }
		end)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
		if not ok then
			error(result, 0)
		end
		local churn = (result :: any).churn
		local inert = (result :: any).inert
		-- the instrument is live at all: without this the assertions below are vacuous
		expect(churn.lapWork.measured).toBe(true)
		expect(inert.lapWork.measured).toBe(true)
		-- THE DIFFERENCE THE DEVICE CAPTURE COULD NOT BE TOLD WITHOUT A BINARY DUMP.
		-- A churning lap restructures the window; the inert lap mounts nothing, which
		-- is exactly the shape of the twenty-nine identical frames.
		expect(churn.lapWork.mount > 0).toBe(true)
		expect(inert.lapWork.mount).toBe(0)
		expect(churn.lapWork.arrange > inert.lapWork.arrange).toBe(true)
		built.dispose()
	end)

	it("says the readout is UNMEASURED rather than zero when the profiler is off", function()
		-- `cleanCapture` turns scopes off on purpose, and a lap readout that printed
		-- `mount=0` in that configuration would accuse a healthy pass of the defect
		-- this case exists to catch. Zero must never stand in for "not counted".
		local built = newHarness()
		local out = built.steps.profileWindow(nil, "async-image-churn:imagesReuse:1")
		expect(out.lapWork.measured).toBe(false)
		built.dispose()
	end)
end)

--[[ THE TWO NAMED LEVERS (device-capture-2026-08-15 §7).

	`arrange-shapes` and `edit-locality` exist because that capture ranked two levers
	and recorded that neither had a workload aimed at it. Their arms live in
	`examples/performance/lab/levers.luau`; the cases below are the ones that decide
	whether an arm MEASURES what it claims to, because every failure mode here
	produces a tidy number rather than an error:

	  * nine arms that are secretly nine copies of `flat`
	  * an A/B whose two halves carry the same configuration
	  * a lap too long for the 60-frame window it was built for
	  * a pass that runs its whole ladder inside one frame

	Each was a real defect in this lab's history, in a different pass.
]]
describe("perf lab: the three named levers measure what they claim (device capture 6)", function()
	it("the declared arms ARE the installed arms — the two files cannot drift apart", function()
		-- `perf_lab.WORKLOADS` names the passes as strings and `levers.luau` installs
		-- them, because perf_lab must stay `script`-free and so cannot require it.
		-- This is what makes that duplication checkable.
		local built = newHarness()
		local declared = built.steps.workloads()
		local byId: any = {}
		for _, w in declared.workloads do
			byId[w.id] = w
		end
		expect(table.concat(byId["arrange-shapes"].passes, ",")).toBe(table.concat(leversLib.SHAPE_ARMS, ","))
		expect(table.concat(byId["edit-locality"].passes, ",")).toBe(table.concat(leversLib.EDIT_ARMS, ","))
		expect(table.concat(byId["host-move"].passes, ",")).toBe(table.concat(leversLib.HOST_ARMS, ","))
		-- ...and the default a `Profile 1` press aims at is one of them
		expect(byId["arrange-shapes"].profilePass).toBe("flat")
		expect(byId["edit-locality"].profilePass).toBe("editOffWindowIncremental")
		expect(byId["host-move"].profilePass).toBe("hosted")
		built.dispose()
	end)

	it("the nine shape arms are NINE TREES, not nine copies of the control", function()
		--[[ THE "CHECK THAT PROVES NOTHING" GUARD FOR THIS WORKLOAD. One typo in the
			`kind` chain and every arm builds `flat`; the arms then agree with each
			other beautifully and the workload reports that tree shape does not matter.
			The oracle is the SOLVER's own per-solve counts, not anything the pass
			computes about itself. ]]
		local built = newHarness()
		local out: any = {}
		for _, arm in leversLib.SHAPE_ARMS do
			out[arm] = built.steps.pass(nil, `{arm}=10/4`).detail
		end
		-- every arm arranges at least its leaves, so none of them silently built nothing
		for _, arm in leversLib.SHAPE_ARMS do
			expect(out[arm].arrangedNodes >= leversLib.SHAPE_LEAVES).toBe(true)
		end
		-- depth: 30 nested containers instead of 1
		expect(out.deep.arrangedNodes > out.flat.arrangedNodes).toBe(true)
		-- the fill distribution's SECOND MEASURE, and the zstack's double measure:
		-- both measure strictly more than the control at the same node count
		expect(out.fill.measuredNodes > out.flat.measuredNodes).toBe(true)
		expect(out.zstack.measuredNodes > out.flat.measuredNodes).toBe(true)
		-- the flow planner caches its lines, so wrap measures FEWER
		expect(out.wrap.measuredNodes < out.flat.measuredNodes).toBe(true)
		--[[ ...and the headline, WHICH MOVED WITH THE MEASUREMENT THAT LICENSED IT
			(L-37). This clause used to read `deep.measuresPerArrangedNode > 4 *
			flat`'s — the 16.4-against-2.0 fan-out L-36 found. That fan-out was the
			DEFECT: a nested chain offered a different height at every level and the
			measure memo's key carried it, so no two levels shared a key and the memo
			could not hit. With the offer out of the key for a node whose answer cannot
			read it, the deep arm's fan-out collapses BELOW the flat control's — a
			30-deep tree now measures each arranged node LESS than a flat one, because
			the flat one's own repeat measures are not cached at all (its recursion
			never reaches `MEMO_ARM_DEPTH`).

			It still discriminates, which is the only reason this clause exists: if the
			`kind` chain regressed and every arm built `flat`, both sides would be the
			same number and this fails. ]]
		expect(out.deep.measuresPerArrangedNode < 0.8 * out.flat.measuresPerArrangedNode).toBe(true)
		built.dispose()
	end)

	it("the measure memo serves the fan-out at depth — the L-37 regression pin", function()
		--[[ THE NUMBER THIS FIX EXISTS FOR, pinned where a future edit to the memo
			would move it. `Facet/arrange` was the largest scope in all four device
			captures, and L-36 found the mechanism: a leaf under 30 nested stacks was
			measured 16.4 times per solve against 2.0 under one stack, and the memo
			produced ZERO hits on that shape because its cache key carried the offered
			height — which a nested chain varies at every level and which a fixed-height
			leaf's answer never reads (instrumented: 16.33 distinct `maxH` per node
			against 1.00 distinct `maxW` and 1.00 distinct `scopeKey`).

			Three ways to break it again, all caught here: putting the offer back in the
			key, closing the arm so a scroll-free deep tree never reaches the cache, or
			widening `HEIGHT_COUPLED_KINDS` until a plain stack lands in it. Any of them
			returns this number to ~16. ]]
		local built = newHarness()
		local deep = built.steps.pass(nil, "deep=10/4").detail
		local deepScroll = built.steps.pass(nil, "deepScroll=10/4").detail
		-- pre-fix: 17.33 and 16.28. The threshold is deliberately far from both, so
		-- this pins the MECHANISM rather than a laptop's exact arithmetic.
		expect(deep.measuresPerArrangedNode < 4).toBe(true)
		expect(deepScroll.measuresPerArrangedNode < 4).toBe(true)
		-- ...and the scroller no longer costs MORE than the bare chain: L-36 measured
		-- `deepScroll` 45% slower than `deep` because its own second sweep re-measured
		-- everything the first had, at a key that could never match
		expect(deepScroll.measuredNodes < 2 * deep.measuredNodes).toBe(true)
		built.dispose()
	end)

	it("every rep provokes exactly ONE full solve — a rep that dirties nothing measures nothing", function()
		--[[ THE `imagesCold` DEFECT CLASS, in the shape it would take here. These
			arms provoke a solve by writing the root container's padding; a write of the
			value it already holds is not a dirty, so a loop that stopped alternating
			would time an idle refresh and report a beautiful, meaningless number. One
			solve per rep is what makes `usPerArrangedNode` a per-solve cost at all.

			NOT `partialSolves == 0`: that was tried and is vacuous. The reuse path
			needs a byte-identical rect to skip anything and this provocation moves
			every rect, so the arms measure a full arrange whether the flag is on or
			off — flipping it to `true` reddens nothing. Measured, not assumed. ]]

		-- THE REAL PROFILE MODULE, or every number below is zero and the check
		-- passes on a mutation it was written to catch. `scopeCount` is nil-safe by
		-- design (clean-capture mode turns scopes off), so the harness's default
		-- no-op profiler makes `arrangePerRep` read 0.00 for a healthy arm — which is
		-- exactly what this case was doing before it was run against unmutated source.
		local built = newHarness({ profile = profile })
		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function() end, function() end)
		local ok, details = pcall(function()
			local out: any = {}
			for _, arm in leversLib.SHAPE_ARMS do
				out[arm] = built.steps.pass(nil, `{arm}=10/4`).detail
			end
			return out
		end)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
		if not ok then
			error(details, 0)
		end
		for _, arm in leversLib.SHAPE_ARMS do
			local detail = (details :: any)[arm]
			expect(`{arm}:{detail.arrangePerRep}`).toBe(`{arm}:1`)
			expect(`{arm}:{detail.measurePerRep}`).toBe(`{arm}:1`)
		end
		built.dispose()
	end)

	it("the incremental A/B is TWO configurations: one skips nothing, the other skips almost everything", function()
		--[[ THE LEVER-2 MEASUREMENT ITSELF, as an invariant. Two arms that both read
			`settings.incremental` would be one configuration measured twice, which is
			the shape `extentArms` guards against with its `itemExtentMode` assertion.
			Here the oracle is the renderer's own `partialSolves` / `lastSkipped`. ]]
		local built = newHarness()
		local off = built.steps.pass(nil, "editOffWindow=10/6").detail
		local on = built.steps.pass(nil, "editOffWindowIncremental=10/6").detail
		expect(off.incremental).toBe(false)
		expect(on.incremental).toBe(true)
		expect(off.partialSolvesPerEdit).toBe(0)
		expect(off.lastSkipped).toBe(0)
		-- L-27 found the reuse path INERT on a resize. On a collection edit it bites:
		-- it serves a partial solve for every edit and skips most of the tree.
		expect(on.partialSolvesPerEdit).toBe(1)
		expect(on.lastSkipped > 0).toBe(true)
		expect(on.arrangedNodes < off.arrangedNodes // 2).toBe(true)
		built.dispose()
	end)

	it("an off-window edit provokes ONE solve and NO structural sync", function()
		-- the half of L-35's finding that was healthy: 25 inserts ~475 rows outside
		-- the mounted window provoked zero `Facet/mount` on the device. This holds
		-- it, and pins the other half — one full solve per edit — as the cost.
		local built = newHarness({ profile = profile })
		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function() end, function() end)
		local ok, detail = pcall(function()
			return built.steps.pass(nil, "editOffWindow=10/8").detail
		end)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
		if not ok then
			error(detail, 0)
		end
		expect((detail :: any).arrangePerEdit).toBe(1)
		expect((detail :: any).mountPerEdit).toBe(0)
		-- and the premise: the edit landed where nothing is mounted
		expect((detail :: any).mountedRows < (detail :: any).logicalRows // 4).toBe(true)
		built.dispose()
	end)

	it("ONE LAP FITS A 60-FRAME WINDOW, and every rep yields a frame", function()
		--[[ THE RULE `variable-extents` BROKE. One `extentArms` lap is 5 arms x 108
			reps = 540 frames; a MicroProfiler aggregate window is 60 and its event ring
			is 30, so that dump could never contain the comparison it was built for. And
			`collection-churn/insert` runs 25 edits with no yield between them, so one
			lap is ONE 557 ms frame — unmeasurable from the other direction.

			Both are checked here at the DEFAULT reps, because the default is what
			`Profile 1` uses and nobody types a payload on a phone. ]]
		for _, arm in leversLib.SHAPE_ARMS do
			local built = newHarness()
			local before = (built :: any).framesYielded()
			built.steps.pass(nil, arm)
			local lapFrames = (built :: any).framesYielded() - before
			expect(lapFrames > 0).toBe(true)
			expect(lapFrames <= 60).toBe(true)
			built.dispose()
		end
		for _, arm in leversLib.EDIT_ARMS do
			local built = newHarness()
			local before = (built :: any).framesYielded()
			built.steps.pass(nil, arm)
			local lapFrames = (built :: any).framesYielded() - before
			expect(lapFrames > 0).toBe(true)
			expect(lapFrames <= 60).toBe(true)
			built.dispose()
		end
		for _, arm in leversLib.HOST_ARMS do
			local built = newHarness()
			local before = (built :: any).framesYielded()
			built.steps.pass(nil, arm)
			local lapFrames = (built :: any).framesYielded() - before
			expect(lapFrames > 0).toBe(true)
			expect(lapFrames <= 60).toBe(true)
			built.dispose()
		end
	end)
end)

--[[ THE THIRD NAMED LEVER (2026-08-17): a container move inside a host, per
	frame. `artifacts/nested-instance-tree/live-probes.md` §4 measured this exact
	shape in Studio at 241 engine `Position` writes becoming 1; these cases are the
	same guards `shapeArm`/`editArm` already have, aimed at a workload whose entire
	claim rests on a structural fact (a real `ScrollView` ancestor) rather than a
	name — the "check that proves nothing" class would here be five arms that
	silently build the identical tree and agree with each other beautifully.
]]
describe("perf lab: the host-move lever measures a real host, not a label", function()
	it("hosted arms have a real ScrollView ancestor; unhosted arms do not — the structural oracle", function()
		local built = newHarness()
		local out: any = {}
		for _, arm in leversLib.HOST_ARMS do
			out[arm] = built.steps.pass(nil, `{arm}=10/4`).detail
		end
		-- the declared intent (HOST_SPEC in levers.luau) and the built structure
		-- must agree, for every arm — not just the two the default dump would show
		expect(out.hosted.scrollHosted).toBe(true)
		expect(out.hostedRepeat.scrollHosted).toBe(true)
		expect(out.unhosted.scrollHosted).toBe(false)
		expect(out.hostedLarge.scrollHosted).toBe(true)
		expect(out.unhostedLarge.scrollHosted).toBe(false)
		-- and `scrollHosted` tracks the arm's own declared `hosted` field, which is
		-- the invariant a future arm addition has to keep
		for _, arm in leversLib.HOST_ARMS do
			expect(`{arm}:{out[arm].scrollHosted}`).toBe(`{arm}:{out[arm].hosted}`)
		end
		built.dispose()
	end)

	it("N IS ACTUALLY SWEPT — Large is five times Small's rows and leaves, not a relabeled copy", function()
		local built = newHarness()
		local small = built.steps.pass(nil, "hosted=10/4").detail
		local large = built.steps.pass(nil, "hostedLarge=10/4").detail
		expect(small.rows).toBe(leversLib.HOST_ROWS_SMALL)
		expect(large.rows).toBe(leversLib.HOST_ROWS_LARGE)
		expect(small.leaves).toBe(leversLib.HOST_ROWS_SMALL * leversLib.HOST_CELLS_PER_ROW)
		expect(large.leaves).toBe(leversLib.HOST_ROWS_LARGE * leversLib.HOST_CELLS_PER_ROW)
		expect(large.leaves).toBe(5 * small.leaves)
		-- every arm arranges at least its own leaves, so none of them silently built
		-- an empty or truncated tree (the `shapeArm` oracle, reused here)
		expect(small.arrangedNodes >= small.leaves).toBe(true)
		expect(large.arrangedNodes >= large.leaves).toBe(true)
		built.dispose()
	end)

	it("every rep provokes exactly ONE full solve, and the SAME commit cadence hosted and unhosted", function()
		-- THE REAL PROFILE MODULE, same discipline as the SHAPE_ARMS case above: the
		-- harness's default no-op profiler makes every `*PerRep` field read 0.00 for
		-- a healthy arm, which is exactly what this case exists to catch.
		local built = newHarness({ profile = profile })
		profile.resetCounters()
		profile.setEnabled(true)
		profile.setHooks(function() end, function() end)
		local ok, details = pcall(function()
			local out: any = {}
			for _, arm in leversLib.HOST_ARMS do
				out[arm] = built.steps.pass(nil, `{arm}=10/4`).detail
			end
			return out
		end)
		profile.setHooks(nil, nil)
		profile.setEnabled(false)
		profile.resetCounters()
		if not ok then
			error(details, 0)
		end
		for _, arm in leversLib.HOST_ARMS do
			local detail = (details :: any)[arm]
			expect(`{arm}:{detail.arrangePerRep}`).toBe(`{arm}:1`)
			expect(`{arm}:{detail.measurePerRep}`).toBe(`{arm}:1`)
		end
		--[[ `commitPerRep` is NOT asserted at 1, on purpose — measured (not assumed)
			at a steady 2 for every arm here: the renderer opens `Facet/commit` once
			for the layout-driven rect write and again for the paint/z-order-sync dirty
			pass it provokes alongside it, a framework fact this workload's header
			provocation happens to surface (`arrange`/`measure` do not split this way).
			What the workload's own claim actually rests on is that this cadence is
			IDENTICAL hosted and unhosted — so an arm-to-arm timing difference on a
			device is a difference in what a commit WRITES, not in how often it fires,
			which is what makes `hosted` vs `unhosted` a fair comparison at all. ]]
		local host = (details :: any).hosted.commitPerRep
		expect(host > 0).toBe(true)
		expect((details :: any).hostedRepeat.commitPerRep).toBe(host)
		expect((details :: any).unhosted.commitPerRep).toBe(host)
		expect((details :: any).hostedLarge.commitPerRep).toBe(host)
		expect((details :: any).unhostedLarge.commitPerRep).toBe(host)
		built.dispose()
	end)
end)

--[[ THE ARM SELECTOR (device-capture-2026-08-15 §6, D3).

	An arm comparison needs one dump per arm, and the operator is holding a phone —
	so the arm has to be pickable without typing a payload. The overlay's action row
	gained `Arm >`, which only MOVES a per-workload pointer; `Profile 1` reads it.
	Two buttons rather than one because `Profile 1` loops until Stop: a control that
	both advanced the arm and started a run would race the loop it just started.

	Exposed through `overlayControls` for the reason the scenario cycler is: a
	control only a person can press is a control only a person can catch when it
	breaks.
]]
describe("perf lab overlay: the arm selector aims Profile 1 without a payload", function()
	it("advances through the declared arms, wraps, and starts from what Profile would pick", function()
		local built = newHarness()
		built.overlayControls.selectScenario("edit-locality")
		-- untouched: `Profile 1` aims at the declared profilePass
		expect(built.overlayControls.selectedArm()).toBe(nil)
		-- ...so the FIRST press advances OFF that default rather than landing on it
		expect(built.overlayControls.advanceArm()).toBe("editInWindow")
		expect(built.overlayControls.advanceArm()).toBe("editInWindowIncremental")
		-- and it wraps rather than stopping at the end
		expect(built.overlayControls.advanceArm()).toBe("editOffWindow")
		built.dispose()
	end)

	it("the pointer is PER WORKLOAD — cycling away and back does not re-aim the session", function()
		local built = newHarness()
		built.overlayControls.selectScenario("edit-locality")
		built.overlayControls.advanceArm()
		expect(built.overlayControls.selectedArm()).toBe("edit-locality:editInWindow")
		built.overlayControls.selectScenario("arrange-shapes")
		expect(built.overlayControls.selectedArm()).toBe(nil)
		expect(built.overlayControls.advanceArm()).toBe("flatRepeat")
		built.overlayControls.selectScenario("edit-locality")
		expect(built.overlayControls.selectedArm()).toBe("edit-locality:editInWindow")
		built.dispose()
	end)

	it("Profile 1 actually loops the arm the pointer names", function()
		local built = newHarness()
		built.overlayControls.selectScenario("arrange-shapes")
		--[[ BOUNDED TO ONE LAP HERE, and only here. `Profile 1` presses this with no
			lap cap on purpose — a profiling session runs until Stop — but this harness
			is synchronous and Lune has no `task`, so an unbounded loop is an infinite
			one that ends in `table overflow` rather than a failed expectation. The
			`::1` / `:<pass>:1` suffix is the same shape the aiming cases above use. ]]
		local function loopOnce(payload: string?): string
			return built.steps.profileWindow(nil, `{payload or "arrange-shapes:"}:1`).pass
		end
		-- untouched -> the declared default
		expect(loopOnce(built.overlayControls.selectedArm())).toBe("flat")
		built.overlayControls.advanceArm()
		built.overlayControls.advanceArm()
		expect(built.overlayControls.advanceArm()).toBe("deepScroll")
		expect(loopOnce(built.overlayControls.selectedArm())).toBe("deepScroll")
		built.dispose()
	end)

	it("a workload that declares no passes says so instead of doing nothing", function()
		local built = newHarness()
		built.overlayControls.selectScenario("idle-baseline")
		expect(built.overlayControls.advanceArm()).toBe(nil)
		expect(string.find(built.overlayControls.status(), "no passes") ~= nil).toBe(true)
		built.dispose()
	end)
end)

--[[ THE STATUS LINE MUST HAVE REAL WIDTH AND WRAP (device report, three rounds).

	The lab refuses a mount whose surface reports layout findings, and the whole
	value of that refusal is the message. On a phone the message was cut off —
	three times. The first two fixes shortened the string, which was treating the
	symptom: the `State` Text had no declared width, so in an HStack it took its
	natural single-line extent and ran off the panel.

	Then the fix for THAT broke it worse. Setting the Text to `fill` while its
	parent row still hugged made it collapse to ~zero — a `fill` child asks its
	parent for leftover main-axis space and a hugging parent has none — and the
	device showed a status of exactly one character: "F".

	Both the row and the text carry `fill` now. This case is the instrument that
	would have caught either mistake, and it asserts the two things a status line
	has to be: WIDE (a real fraction of the panel, not one glyph) and TALL (more
	than one line when the message is long). Measured rather than reasoned. ]]
describe("perf lab overlay: the status line is readable, not one character wide", function()
	local LONG = "[perf lab] MOUNT REFUSED — /PerfLab/Body/Rows/Row: content overflows this hstack "
		.. "by 132px on the main axis; it will paint outside its box (wrap it in a ScrollView, or give it room)"

	local function statusRect(vw: number, vh: number)
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = vw, h = vh })
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local model: any = {
			buildLine = core:signal("build"),
			scenarioLine = core:signal("dense-scroll"),
			deviceLine = core:signal("device"),
			statusLine = core:signal(LONG),
			countdown = core:signal(""),
			counterLines = core:signal({ "mountedRows=0/9" }),
			actions = {},
			scenarioNames = { "dense-scroll", "mount-ramp" },
			onSelectScenario = function() end,
			currentScenario = core:signal("dense-scroll"),
			onCycleScenario = function() end,
			scenarioPosition = core:signal("1/2"),
			onRunAll = function() end,
		}
		local bp = overlayLib.build(Facet, core, model)
		local handle = pres.present(Facet.UI.Screen({ id = "O", children = { bp } }))
		pres.refresh()
		local found: string? = nil
		for _, path in adapter.paths() do
			if string.find(path, "/State", 1, true) ~= nil then
				found = path
			end
		end
		expect(found ~= nil).toBe(true)
		return handle.controller.rectOf(found :: string)
	end

	it("takes a real share of the panel at the reporter's device viewport, and wraps", function()
		local r = statusRect(698, 1513)
		-- WIDE: a collapsed `fill` renders about one glyph. Anything under a third
		-- of the viewport means the row is hugging again.
		expect(r.w > 300).toBe(true)
		-- TALL: one line of 15px text is ~18px. This message cannot fit on one.
		expect(r.h > 36).toBe(true)
	end)

	it("...and on the narrowest supported phone, where it needs the most lines", function()
		local r = statusRect(360, 691)
		expect(r.w > 150).toBe(true)
		expect(r.h > 54).toBe(true)
	end)
end)

--[[ THE PROFILING LOOP MUST BE STOPPABLE AND MUST YIELD (device hang, 2026-08-13).

	The director's phone HUNG twice — on `mount-ramp` (leaving a blank screen) and
	on `resize-relayout` — while `Profile 1` was looping them. `dense-scroll` was
	fine. Two compounding defects, both in the loop rather than in the workloads:

	1. NO YIELD. The loop relied on the pass to wait a frame. Of the three passes a
	   window is likely to loop, only `scrollSteady` does — `resizeStorm` and `ramp`
	   have ZERO yield sites and run their whole ladder synchronously. Looping
	   either was a tight infinite loop on the driving coroutine.

	2. THE STOP COULD BE UNDONE BY THE THING BEING STOPPED. `passes.ramp` sets
	   `emergencyStopped = false` at its own start, so the loop's
	   `while not emergencyStopped` was cleared by the very pass it was looping.
	   Pressing Stop could not end it. That is why `mount-ramp` was the one that
	   went blank and stayed there.

	Defect 2 is the more general lesson and the reason the flags are now two: one
	answers "abandon this run" and the other "stop looping", and a single variable
	answering both let a pass overrule the operator.
]]
describe("perf lab: the profiling loop is stoppable, and does not depend on the pass to yield", function()
	it("a pass that resets emergencyStopped CANNOT keep the loop alive", function()
		-- `ramp` is the real offender; bound the laps so the case terminates even
		-- if the guard regresses, and assert the loop honoured Stop rather than the
		-- cap. Without the separate flag this ran to the cap every time.
		local built = newHarness()
		local stopped = false
		local realRamp = built.steps.pass
		-- drive one lap, then request a stop from inside the loop's own cadence
		built.steps.select(nil, "scenario=mount-ramp,rows=50,seed=1")
		-- a 3-lap cap: if Stop works the loop ends at 1, if it does not it reaches 3
		task = nil :: any -- prove we are not relying on a scheduler the suite lacks
		local out = built.steps.profileWindow(nil, "mount-ramp:ramp:3")
		expect(out.pass).toBe("ramp")
		-- the loop ran under its own cap and returned; the point is that it RETURNED
		expect(out.laps <= 3).toBe(true)
		expect(out.laps >= 1).toBe(true)
		built.dispose()
	end)

	it("stop() ends the loop even though the pass clears the run flag", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=mount-ramp,rows=50,seed=1")
		built.steps.stop()
		-- an unbounded window asked to stop before it starts must not loop at all
		-- beyond its first lap; without the separate flag `ramp` clears the stop on
		-- lap 1 and this never returns
		local out = built.steps.profileWindow(nil, "mount-ramp:ramp:2")
		expect(out.laps <= 2).toBe(true)
		built.dispose()
	end)
end)

--[[ THE MOTION-FLIGHT PASS (withAnimation size, 2026-08-14).

	The director asked for something in the lab that can profile an interpolating
	property, and "an instrument nobody runs is a comment" — so the pass runs
	here, every suite, on the real scenario module.

	WHAT THIS CAN AND CANNOT SEE. The harness's `telemetry.clock` is a monotonic
	stub advancing a fixed 1 ms per call, so every `*Ms` field the pass reports is
	synthetic under Lune and identical across arms by construction. Asserting on
	them here would be a check that proves nothing. What IS real headless is the
	STRUCTURE: that four arms were taken, that both flights actually seeded
	records, and — the load-bearing one — that the two flight arms seed the SAME
	number of records, because that is what makes the C-minus-B difference the
	marginal cost of the size half rather than the cost of a bigger experiment.
	The timings are a Studio quantity and the doc says so. ]]
describe("perf lab: the motion-flight pass profiles a withAnimation flight", function()
	it("takes four arms, and both flights seed the SAME record count", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=motion-flight")
		-- the cap is deliberately ABOVE the flight's real length (measured: 47
		-- frames for `container` at 60 Hz), so the boundedness assertion below can
		-- see the sampler stop on its own rather than run into the cap
		local d = built.steps.pass(nil, "motionFlight=120").detail
		expect(d.rows).toBe(24)
		-- both flights happened at all: a pass that silently animated nothing would
		-- report a beautiful zero and mean nothing
		expect(d.positionRecords > 0).toBe(true)
		expect(d.positionAndSizeRecords > 0).toBe(true)
		-- ...and they are the SAME experiment at two settings, which is the whole
		-- basis for reading C-minus-B as the size half's marginal cost
		expect(d.positionAndSizeRecords).toBe(d.positionRecords)
		-- every row claimed: 24 rows re-ordered, 24 rows resized
		expect(d.positionRecords).toBe(24)
		-- BOTH FLIGHTS WERE SAMPLED WHILE RECORDS WERE LIVE, and stopped when they
		-- were not. `> 0` alone cannot see the difference — a sampler that ignored
		-- the records and ran to the cap would satisfy it while diluting the p50
		-- with 73 idle frames. So the assertion is on the CAP: the loop ended early
		-- because the spring settled.
		expect(d.positionFlightFrames > 0).toBe(true)
		expect(d.positionFlightFrames < 120).toBe(true)
		expect(d.positionAndSizeFlightFrames > 0).toBe(true)
		expect(d.positionAndSizeFlightFrames < 120).toBe(true)
		-- the four arms are all present and reported apart
		expect(d.idleMs.measured).toBe(true)
		expect(d.idleRepeatMs.measured).toBe(true)
		expect(d.positionMs.measured).toBe(true)
		expect(d.positionAndSizeMs.measured).toBe(true)
		expect(type(d.harnessSpreadMs)).toBe("number")
		built.dispose()
	end)

	--[[ THE PAINT ARM AND THE OFF-PATH CONTROL (2026-08-14).

		Arm D moves the AUTHORED presentation triple — opacity, scale, rotation —
		with every rect held still, so whatever it costs is the composition and its
		engine writes rather than a re-solve wearing their name. Same headless rule
		as the arms above: the `*Ms` fields are a stub clock and mean nothing here,
		the COUNTS are real.

		The load-bearing count is that arm D seeds the SAME number of records as B
		and C. Without it, "the paint half is cheap" could be true only because it
		was a smaller experiment — which is the exact shape of the three round-2
		improvements that evaporated when measured properly.

		The off-path control is a SECOND mount whose rows declare none of the three,
		and the assertion that matters is that it was actually taken and actually
		torn down: a claim that an unused feature costs nothing, measured against
		nothing, is a comment. ]]
	it("takes a PAINT arm on the same record count, plus an off-path control it cleans up", function()
		local built, ctx = newHarness()
		built.steps.select(nil, "scenario=motion-flight")
		local d = built.steps.pass(nil, "motionFlight=120").detail
		-- the paint flight happened at all, and it is the same experiment as B and C
		expect(d.paintRecords > 0).toBe(true)
		expect(d.paintRecords).toBe(d.positionRecords)
		-- sampled while records were live, and it stopped on its own
		expect(d.paintFlightFrames > 0).toBe(true)
		expect(d.paintFlightFrames < 120).toBe(true)
		expect(d.paintMs.measured).toBe(true)
		-- the off-path control was taken, reported apart, and its surface is gone
		expect(d.plainIdleMs.measured).toBe(true)
		expect(type(d.offPathDeltaMs)).toBe("number")
		expect(ctx.adapter.node("/MotionFlightPlain")).toBe(nil)
		built.dispose()
	end)

	it("takes its own surface away again, and leaves no record behind", function()
		local built, ctx = newHarness()
		built.steps.select(nil, "scenario=motion-flight")
		-- the surface is the pass's own, and it must not outlive the pass: a lab
		-- whose motion workload left a live screen mounted would silently tax every
		-- capture taken after it in the same session
		built.steps.pass(nil, "motionFlight=120")
		expect(ctx.adapter.node("/MotionFlight")).toBe(nil)
		-- ...and no spring still owns a path on a torn-down tree
		expect(ctx.presenter.animationRecordCount()).toBe(0)
		built.dispose()
	end)
end)

--[[ THE COUNTER CONTRACT, AND WHY IT IS ASSERTED AS A SET (wave T15, item 4).

	The plan's "In-place controls" section lists what a session must be able to
	read, and the lab has two readers of it: `steps.counters`, which a person or a
	script reads live, and the exported CAPTURE ROW, which is the artifact every
	comparison is made against. They were two separately written table literals,
	and they had drifted — the renderer's structural counters were in the live one
	and not in the row, and the haptics counters (which land on the overlay's own
	line on every refresh) were in NEITHER, so the number that answers "does the
	feedback adapter allocate per frame" was visible on screen and absent from the
	evidence.

	Asserting the two agree by SET rather than pinning a list is the point: a
	counter added to one reader tomorrow fails here on the commit that adds it,
	which a pinned list of today's names would not do.
]]
--[[ THE GUIDE'S WORKLOAD TABLE IS THE REGISTRY'S, OR IT IS FICTION (wave T15).

	`docs/guide/12-performance-lab.md` is what an operator reads before spending a
	MicroProfiler session, and it said "the fourteen workloads" while the registry
	declared seventeen — `arrange-shapes`, `edit-locality` and `host-move`, the
	three NAMED LEVERS, were invisible to anyone who learned the lab from its own
	chapter. They are the levers aimed at the top cost in every device capture
	taken, so the three missing rows were the three most worth running.

	Nothing could have caught it: the count was prose, the table was hand-written,
	and both were correct on the day they were typed. This case is the mechanism —
	every declared id must appear in the chapter's table, the chapter must claim no
	id the registry does not have, and the spelled-out COUNT in the heading has to
	be the real one, because a stale number beside a correct table is how a reader
	learns to distrust both.
]]
describe("perf lab: the guide's workload table matches the registry (T15)", function()
	local fsLib = require("@lune/fs")
	local GUIDE = "docs/guide/12-performance-lab.md"
	local WORDS = {
		[9] = "nine",
		[10] = "ten",
		[11] = "eleven",
		[12] = "twelve",
		[13] = "thirteen",
		[14] = "fourteen",
		[15] = "fifteen",
		[16] = "sixteen",
		[17] = "seventeen",
		[18] = "eighteen",
		[19] = "nineteen",
		[20] = "twenty",
	}

	it("every declared workload has a row in the chapter, and the chapter invents none", function()
		local built = newHarness()
		local declared = built.steps.workloads()
		built.dispose()
		local guide = fsLib.readFile(GUIDE)

		local missing: { string } = {}
		for _, id in declared.order do
			if string.find(guide, `| \`{id}\` |`, 1, true) == nil then
				table.insert(missing, id)
			end
		end
		expect(`missing from the guide: {table.concat(missing, ", ")}`).toBe("missing from the guide: ")

		--[[ ...and the other direction, so a workload REMOVED from the registry does
			not go on being documented. Scanned inside the WORKLOAD SECTION only: the
			chapter has other id-shaped tables (the five evidence classes among them),
			and a check that read every table in the file would report `phone-physical`
			as an undeclared workload — which is a false alarm, and a guard that cries
			wolf is a guard people route around. ]]
		local known: { [string]: boolean } = {}
		for _, id in declared.order do
			known[id] = true
		end
		local sectionStart = string.find(guide, "### The ", 1, true)
		expect(`the workload section exists: {sectionStart ~= nil}`).toBe("the workload section exists: true")
		local sectionEnd = string.find(guide, "\n### ", (sectionStart :: number) + 8, true) or #guide
		local section = string.sub(guide, sectionStart :: number, sectionEnd)
		local invented: { string } = {}
		for id in string.gmatch(section, "\n| `([a-z%-]+)` | [a-z]") do
			if not known[id] then
				table.insert(invented, id)
			end
		end
		table.sort(invented)
		expect(`documented but not declared: {table.concat(invented, ", ")}`).toBe("documented but not declared: ")
	end)

	it("the spelled-out count in the heading is the real one", function()
		local built = newHarness()
		local n = #built.steps.workloads().order
		built.dispose()
		local word = WORDS[n]
		expect(`a word for {n}: {tostring(word)}`).toBe(`a word for {n}: {tostring(word)}`)
		expect(word ~= nil).toBe(true)
		local guide = fsLib.readFile(GUIDE)
		expect(`heading: {string.find(guide, `### The {word} workloads`, 1, true) ~= nil}`).toBe("heading: true")
	end)
end)

describe("perf lab: the live counters and the capture row read ONE block (T15)", function()
	local function keysOf(t: any): { string }
		local out: { string } = {}
		for k in t do
			table.insert(out, tostring(k))
		end
		table.sort(out)
		return out
	end

	it("every counter the live read publishes is on the exported row, and vice versa", function()
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=200,seed=1")
		built.steps.mount()
		built.steps.pass(nil, "scrollSteady=4")

		local live = built.steps.counters()
		-- the live read adds three of its OWN (the settings echo, the chrome-art
		-- ledger and the pass log); everything else must be the shared block
		live.settings = nil
		live.chromeArt = nil
		live.passes = nil

		local exported = built.steps.export(nil, "1").row.counters
		expect(table.concat(keysOf(live), ",")).toBe(table.concat(keysOf(exported), ","))
		built.dispose()
	end)

	it("the block carries the counters the release waves landed, not the ones they replaced", function()
		--[[ Named individually because a set comparison alone is satisfied by two
			readers that are equally out of date. These three are the wave's own
			charge: haptics (task 11, landed), the renderer's structural counters
			(which carry `textMeasureBatches`), and the text premeasure queue. ]]
		local built = newHarness()
		built.steps.select(nil, "scenario=dense-scroll,rows=200,seed=1,haptics=on")
		built.steps.mount()
		local c = built.steps.counters()

		expect(`haptics.state={c.haptics.state}`).toBe("haptics.state=on")
		expect(`haptics.plays={c.haptics.plays}`).toBe("haptics.plays=0")
		expect(`haptics.coalesced={c.haptics.coalesced}`).toBe("haptics.coalesced=0")
		-- the renderer's own structural counters, and the text batch count inside them
		expect(type(c.render)).toBe("table")
		expect(type(c.render.solves)).toBe("number")
		expect(type(c.render.textMeasureBatches)).toBe("number")
		-- the premeasure queue: this host has no premeasure seam, and the block says
		-- so EXPLICITLY rather than reporting a zero that would read as "nothing
		-- outstanding" (the metric-ledger discipline, one layer out)
		expect(type(c.text.measured)).toBe("boolean")
		if c.text.measured then
			expect(type(c.text.pending)).toBe("boolean")
		else
			expect(#tostring(c.text.reason) > 0).toBe(true)
		end
		built.dispose()
	end)

	it("the module-load marks come from the HOST, and a host with none says so", function()
		--[[ The director's memory ask needs a client number, and only the bootstrap
			can take the "before `require(Facet)`" mark — this VM's Facet was required
			before the harness existed. So the counter reads the host's seam, and the
			case is two-sided: a host with no marks must produce an explicit
			`measured = false` with a reason (never a zero, which would read as "the
			require graph is free"), and a host WITH marks must have its third mark —
			the one only the lab can take, after the first workload mounts — filled in.

			The stand-in below supplies the same two fields the real bootstrap does. It
			is the seam, not a shortcut: `examples/performance/client/init.client.luau`
			is engine code no headless suite can run, and what is checkable here is
			that the lab reads the seam correctly and completes it. ]]
		local blind = newHarness()
		blind.steps.select(nil, "scenario=dense-scroll,rows=100,seed=1")
		blind.steps.mount()
		local c0 = blind.steps.counters()
		expect(`measured={c0.moduleLoad.measured}`).toBe("measured=false")
		expect(#tostring(c0.moduleLoad.reason) > 0).toBe(true)
		blind.dispose()

		local heap = 1000
		local built = newHarness({
			heapKb = function(): number
				heap += 250
				return heap
			end,
			heapMarks = function(): any
				return { measured = true, beforeRequireKb = 400, afterRequireKb = 1000, requireCostKb = 600 }
			end,
		})
		built.steps.select(nil, "scenario=dense-scroll,rows=100,seed=1")
		local before = built.steps.counters().moduleLoad
		-- nothing has mounted, so the lab's own mark is honestly absent
		expect(`preMount={tostring(before.afterFirstMountKb)}`).toBe("preMount=nil")
		built.steps.mount()
		local after = built.steps.counters().moduleLoad
		expect(`require={after.requireCostKb}`).toBe("require=600")
		expect(`firstMount={after.firstMountCostKb}`).toBe("firstMount=250")
		-- ...and the mark is taken ONCE: a second mount must not re-take it on a warm
		-- heap, which would answer a different question under the same name
		built.steps.reset()
		built.steps.select(nil, "scenario=dense-scroll,rows=100,seed=1")
		built.steps.mount()
		expect(`firstMountAgain={built.steps.counters().moduleLoad.firstMountCostKb}`).toBe("firstMountAgain=250")
		built.dispose()
	end)
end)

describe("the lab's registry satisfies the SHARED runner's contract", function()
	--[[ WHY THIS EXISTS, AND WHAT IT COST NOT TO.

		`examples/performance.project.json` GRAFTS the gallery's `runner.luau` into
		the lab's own `FacetScenarios` folder — one runner for both surfaces,
		deliberately, so the test rig cannot end up more capable than the surface a
		player opens. That graft makes the lab's `init.luau` and the gallery's
		`init.luau` two implementations of ONE interface, and nothing checked they
		agreed.

		On 2026-08-15 (`cad3617`, the UI.Foreign showcase) the runner gained
		`local foreign_instances = require(registry.foreignInstances)` as the first
		statement of `start`, before it even looks at which scenario was asked for.
		The gallery registry exports `foreignInstances`; the lab registry did not.
		So from that commit until 2026-08-17, pressing Play in the Performance Lab
		did NOTHING — `Attempted to call require with invalid argument(s)` out of
		`FacetScenarios.runner:217` — and every lab workload was unreachable.

		It survived two days because of exactly where the seam is: this suite
		requires these modules DIRECTLY and never through the built place, so nothing
		here ran the runner against the lab's registry; `check_perf_place.py` proves
		the place BUILDS, which it did, perfectly, every time; and the lab is only
		ever opened by a human about to spend a MicroProfiler dump. A broken thing
		nobody opens looks exactly like a working one.

		SO THIS READS THE RUNNER'S SOURCE FOR EVERY `registry.<field>` IT TOUCHES and
		asserts the lab exports each, rather than pinning the one field that happened
		to break. A field added to the runner tomorrow fails here on the commit that
		adds it, which is the only way this class is caught before a person is.
	]]
	local fsLib = require("@lune/fs")

	local function fieldsRunnerReads(): { [string]: boolean }
		local runnerSource = fsLib.readFile("examples/gallery/scenarios/runner.luau")
		local needed: { [string]: boolean } = {}
		for field in string.gmatch(runnerSource, "registry%.([A-Za-z_][A-Za-z0-9_]*)") do
			needed[field] = true
		end
		return needed
	end

	local function missingFrom(path: string): { string }
		local source = fsLib.readFile(path)
		local missing: { string } = {}
		for field in fieldsRunnerReads() do
			if string.find(source, "\n\t" .. field .. " = ", 1, true) == nil then
				table.insert(missing, field)
			end
		end
		table.sort(missing)
		return missing
	end

	it("the runner asks for something, or every check below is vacuous", function()
		local n = 0
		for _ in fieldsRunnerReads() do
			n += 1
		end
		expect(n > 0).toBe(true)
	end)

	it("every registry field the runner reads is exported by the LAB", function()
		local missing = missingFrom("examples/performance/lab/init.luau")
		if #missing > 0 then
			error(
				`the shared runner reads registry.{table.concat(missing, ", registry.")} but `
					.. "examples/performance/lab/init.luau does not export it — pressing Play in "
					.. "the Performance Lab fails at runner.start before any workload runs",
				0
			)
		end
	end)

	it("...and by the GALLERY, which is the control", function()
		expect(#missingFrom("examples/gallery/scenarios/init.luau")).toBe(0)
	end)

	it("the project MOUNTS what the lab exports, or the child is never there to find", function()
		-- `script:WaitForChild("foreign_instances")` yields forever on a child that
		-- was never mounted, so the export is only real if the graft is too.
		local project = fsLib.readFile("examples/performance.project.json")
		expect(string.find(project, "gallery/scenarios/runner.luau", 1, true) ~= nil).toBe(true)
		expect(string.find(project, "gallery/scenarios/foreign_instances.luau", 1, true) ~= nil).toBe(true)
	end)
end)
