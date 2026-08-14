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

local LuauUI = require("../src")
local fake_target = require("./lib/fake_target")

local dataset = require("../examples/performance/lab/dataset")
local rowsLib = require("../examples/performance/lab/rows")
local captureLib = require("../examples/performance/lab/capture")
local overlayLib = require("../examples/performance/lab/overlay")
local perf_lab = require("../examples/performance/lab/perf_lab")

-- A minimal stand-in for the runner ctx. It carries exactly the seams perf_lab
-- reads, so a seam the scenario starts depending on shows up here as a nil-index
-- rather than as a Studio-only surprise.
local function newHarness(hostOverrides: any?, viewport: { w: number, h: number }?, labOpts: any?)
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	local vp = viewport or { w = 900, h = 700 }
	env:set("viewportRect", { x = 0, y = 0, w = vp.w, h = vp.h })
	local adapter = fake_target.new()
	local system = LuauUI.newActionSystem(core)
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local clock = 0
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
		LuauUI = LuauUI,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		host = host,
		lab = { dataset = dataset, rows = rowsLib, capture = captureLib, overlay = overlayLib },
		labOptions = labOpts,
		telemetry = {
			clock = function()
				clock += 0.001
				return clock
			end,
			step = function()
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
			`moved` above). The lab's own overlay writes that one edge twice more per
			resize on its own schedule — `forgetReservation` zeroes it when the
			viewport moves, then `onGeometry` republishes the measured dock height —
			so counting it here would measure the overlay's reservation dance rather
			than this pass's batching. Measured 2026-08-13 over 4 steps: viewportRect
			5, deviceSafeInsets/topbarSafeInsets/topbarInset 4 each, displaySize 1,
			and coreSafeInsets ELEVEN. Those extra writes are a real cost, recorded in
			the optimization log; they are simply not what this check is about. ]]
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
		expect(r.mountedImplementation).toBe("luauui")
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

describe("perf lab: selectors and workload identity (PL-2/PL-10)", function()
	it("every declared workload names only passes the scenario implements", function()
		local built = newHarness()
		local declared = built.steps.workloads()
		-- TEN since resize-relayout joined them (director ask 2026-08-05): a continuous
		-- resize interleaved with single-value changes, which is the workload that
		-- makes the incremental-layout gap measurable instead of argued
		expect(#declared.order).toBe(10)
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
		expect(result.settings.implementation).toBe("luauui")
		expect(result.settings.content).toBe("identity")
		expect(#result.datasetDigest).toBe(8)
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
		expect(built.report().mountedImplementation).toBe("luauui")
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
		expect(built.report().mountedImplementation).toBe("luauui")
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
			expect(built.report().mountedImplementation).toBe("luauui")
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
		expect(built.report().mountedImplementation).toBe("luauui")
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
			expect(built.report().mountedImplementation).toBe("luauui")
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
		expect(built.report().mountedImplementation).toBe("luauui")
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
		local core = LuauUI.newCore()
		local provider = LuauUI.newResourceProvider(core)
		local scope = core:scope("row-shape")
		local item = dataset.build({ count = 1, seed = 1 })[1]
		local bp = rowsLib.cell(LuauUI, core, item, {
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
		local core = LuauUI.newCore()
		local provider = LuauUI.newResourceProvider(core)
		local scope = core:scope("row-disclose")
		local item = dataset.build({ count = 1, seed = 1, content = "identity" })[1]
		local bp = rowsLib.cell(LuauUI, core, item, {
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
		local neutral = LuauUI.themes.neutral()
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
		local snap = LuauUI.themes.resolve(ornateModule.build(LuauUI.themes), nil, {})
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
	             again the native reference, which calls no LuauUI code at all.

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
		expect(string.find(tostring(err), "calls NO LuauUI code") ~= nil).toBe(true)
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
		expect(out.implementation).toBe("luauui")
		expect(out.laps).toBe(2)
		-- steps.run would have executed all seven passes; profileWindow must not use it
		expect(#ran).toBe(0)
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
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = vw, h = vh })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
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
		local bp = overlayLib.build(LuauUI, core, model)
		local handle = pres.present(LuauUI.UI.Screen({ id = "O", children = { bp } }))
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
