--!strict
local harness = require("./lib/harness")
-- DOES MOUNT/UNMOUNT RATCHET? The soak invariant: N mount/unmount cycles must
-- return to the starting instance count.
--
-- WHY THIS SPEC EXISTS, AND WHY IT DOES NOT COUNT `liveCount`. A physical-device
-- MicroProfiler read suggested Facet was accumulating Instances across mounts.
-- The obvious instrument — the adapter's live-node count, and its Studio
-- equivalent `instances.guiObjects` (which walks PlayerGui) — is STRUCTURALLY
-- BLIND to the one mechanism that can actually do it:
--
--   `park` takes a dying node out of the live `nodes` map WITHOUT destroying it
--   and hands it to the renderer's recycle pool. `destroyRoot` frees a surface by
--   walking that same `nodes` map — so a parked node is unreachable from teardown
--   and is freed by exactly one call, `drainRecyclePool()`. Delete that call and
--   every unmount strands up to RECYCLE_POOL_CAP (64) live objects while
--   `liveCount` reads perfectly flat.
--
-- So this spec censuses every handle the adapter ever created and counts the ones
-- still holding an object (alive OR parked). That is the only number that can see
-- a pool teardown forgot to drain. Mutation-proven: removing `drainRecyclePool()`
-- from the renderer's teardown ratchets `parked` 18 -> 36 -> 54 across three laps
-- while the live count sits at a constant 44.

local testkit = require("./lib/testkit")
local describe, it, expect = testkit.describe, testkit.it, testkit.expect

local Facet = require("../src")
local fake_target = require("./lib/fake_target")

local dataset = require("../examples/performance/lab/dataset")
local rowsLib = require("../examples/performance/lab/rows")
local captureLib = require("../examples/performance/lab/capture")
local overlayLib = require("../examples/performance/lab/overlay")
local leversLib = require("../examples/performance/lab/levers")
local navigationInventory = require("../examples/performance/lab/navigation_inventory")
local transientSurfaces = require("../examples/performance/lab/transient_surfaces")
local perf_lab = require("../examples/performance/lab/perf_lab")

local function newHarness()
	local core = harness.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = harness.newPresenter(core, env, adapter, system)
	-- `app.controls` in Studio (runner.luau's `ctx.UI`): the shorthand-capable
	-- constructor table, per `tests/perf_lab.spec.luau`'s `newHarness`.
	local controlsApi = harness.libraryOf(core)
	local clock = 0
	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		UI = controlsApi,
		Compose = Facet.Compose,
		host = {
			facts = function()
				return {
					evidenceClass = "lune",
					capturedAtIso = "2026-08-13T00:00:00Z",
					sourceStamp = "test-stamp",
					placeName = "headless",
				}
			end,
		},
		lab = {
			dataset = dataset,
			rows = rowsLib,
			capture = captureLib,
			overlay = overlayLib,
			levers = leversLib,
			navigationInventory = navigationInventory,
			transientSurfaces = transientSurfaces,
		},
		telemetry = {
			clock = function()
				clock += 0.001
				return clock
			end,
			step = function()
				return 0
			end,
			instances = function()
				return { measured = true, guiObjects = adapter.liveCount(), screenGuis = 0 }
			end,
			connections = function()
				return { measured = true, total = adapter.handlerCount() }
			end,
			memory = function()
				return { measured = true, luaHeapKb = 0 }
			end,
			frameWork = function(frames: number)
				return { measured = true, frames = frames, p50_ms = 0 }
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
	-- In Studio, every call into a mounted scenario runs with the scenario's
	-- owner already active, re-entered by the framework's own dispatch — see
	-- `tests/perf_lab.spec.luau`'s `newHarness` for the full story. `deepOwn`
	-- closes that gap for this harness's own direct calls into `built`.
	local function deepOwn(t: any): any
		for k, v in t do
			if type(v) == "function" then
				t[k] = function(...)
					local args = table.pack(...)
					return harness.owned(function()
						return v(table.unpack(args, 1, args.n))
					end)
				end
			elseif type(v) == "table" then
				deepOwn(v)
			end
		end
		return t
	end
	local built = deepOwn(harness.owned(function()
		return perf_lab.build(ctx)
	end))

	-- the pool-aware census: wrap `create` and keep every handle ever made
	local everCreated: { any } = {}
	local rawCreate = adapter.create
	adapter.create = function(...)
		local handle = rawCreate(...)
		if handle ~= nil then
			table.insert(everCreated, handle)
		end
		return handle
	end
	local function census(): { outstanding: number, parked: number, live: number }
		local live, parked = 0, 0
		for _, h in everCreated do
			if h.parked == true then
				parked += 1
			elseif h.alive == true then
				live += 1
			end
		end
		return { outstanding = live + parked, parked = parked, live = live }
	end
	return built, census, adapter
end

describe("mount/unmount soak: the instance count returns to its starting level", function()
	it("five mount/unmount laps leave the outstanding-instance count flat", function()
		local built, census = newHarness()
		built.steps.select(nil, "scenario=mount-ramp,rows=200,seed=1")

		built.steps.mount()
		built.steps.unmount()
		-- the settled floor AFTER one full cycle: the lab's overlay stays mounted by
		-- design, so the baseline is "one cycle done", not "never mounted"
		local floor = census().outstanding

		for lap = 1, 5 do
			built.steps.mount()
			built.steps.unmount()
			local c = census()
			expect(c.outstanding).toBe(floor)
			expect(c.parked).toBe(0)
		end
	end)

	it(
		"a SCROLLED surface — which actually fills the recycle pool — still returns to the floor, and the pool is drained",
		function()
			local built, census = newHarness()
			built.steps.select(nil, "scenario=mount-ramp,rows=200,seed=1")

			built.steps.mount()
			built.steps.pass(nil, "scrollSteady")
			built.steps.unmount()
			local floor = census().outstanding

			-- THE ANTI-VACUITY GUARD. A soak that never parks anything proves nothing
			-- about the pool, and `parked == 0` after every unmount would then be true
			-- for the wrong reason. Each lap asserts the pool was genuinely loaded
			-- BEFORE teardown, so the drain has something to drain.
			local peakParked = 0
			for _ = 1, 3 do
				built.steps.mount()
				built.steps.pass(nil, "scrollSteady")
				local loaded = census()
				peakParked = math.max(peakParked, loaded.parked)

				built.steps.unmount()
				local c = census()
				expect(c.outstanding).toBe(floor)
				-- the pool is empty after teardown: `drainRecyclePool` ran
				expect(c.parked).toBe(0)
			end
			-- scrolling must have parked something, or this case is decoration
			expect(peakParked > 0).toBe(true)
		end
	)

	it("three full ramp laps (5 rungs each, up to the declared ceiling) leave the count flat", function()
		local built, census = newHarness()
		built.steps.select(nil, "scenario=mount-ramp,rows=200,seed=1")

		built.steps.pass(nil, "ramp")
		built.steps.unmount()
		local floor = census().outstanding

		for _ = 1, 3 do
			built.steps.pass(nil, "ramp")
			built.steps.unmount()
			local c = census()
			expect(c.outstanding).toBe(floor)
			expect(c.parked).toBe(0)
		end
	end)
end)
