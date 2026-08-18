--!strict
-- TIER 1 (headless Lune = REGRESSION SIGNAL ONLY, never a device claim) readout of
-- the two named levers of `artifacts/performance-stress-places/device-capture-
-- 2026-08-15.md` §7: `arrange-shapes` (which tree shape makes arrange expensive)
-- and `edit-locality` (does incremental layout bite on a collection edit).
--
-- It prints every arm's own numbers AND the per-lap scope deltas `profileWindow`
-- writes to the phone's status line, so the aim of each arm is checkable before a
-- capture is ever spent on it.
--
-- A REAL CLOCK, unlike `_probe_profile_aim`: the suite harness fakes `clock()` with
-- a 1 ms-per-call counter, which is correct for counting and useless for timing.
-- Usage: lune run tools/lune/_probe_levers

local process = require("@lune/process")
local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local profile = require("../../src/core/profile") :: any
local perf_lab = require("../../examples/performance/lab/perf_lab") :: any
local dataset = require("../../examples/performance/lab/dataset")
local rowsLib = require("../../examples/performance/lab/rows")
local captureLib = require("../../examples/performance/lab/capture")
local overlayLib = require("../../examples/performance/lab/overlay")
local leversLib = require("../../examples/performance/lab/levers")

local REPS = tonumber((process :: any).args[1] or "") or 120
local SCOPES = { "arrange", "measure", "mount", "react", "commit", "resource", "reset" }

local function newHarness(): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)
	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		host = { profile = profile },
		lab = { dataset = dataset, rows = rowsLib, capture = captureLib, overlay = overlayLib, levers = leversLib },
		telemetry = {
			clock = os.clock,
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
	return perf_lab.build(ctx)
end

local function counts(): { [string]: number }
	local ok, c = pcall(profile.counters)
	local out: { [string]: number } = {}
	if not ok or c == nil or c.byScope == nil then
		return out
	end
	for _, k in SCOPES do
		out[k] = (c.byScope :: any)[k] or 0
	end
	return out
end

local function f(n: any, places: number?): string
	if type(n) ~= "number" then
		return tostring(n)
	end
	return string.format(`%.{places or 3}f`, n)
end

profile.setEnabled(true)
profile.setHooks(function() end, function() end)

local PLAN = {
	{ "arrange-shapes", leversLib.SHAPE_ARMS },
	{ "edit-locality", leversLib.EDIT_ARMS },
}

for _, spec in PLAN do
	local workload = spec[1] :: string
	print(`\n=== {workload}`)
	for _, passName in spec[2] :: { string } do
		local built = newHarness()
		local ok, err = pcall(function()
			built.steps.select(nil, `scenario={workload}`)
			built.steps.mount()
			profile.resetCounters()
			local before = counts()
			local record = built.steps.pass(nil, `{passName}=60/{REPS}`)
			local after = counts()
			local lap = {}
			for _, k in SCOPES do
				table.insert(lap, `{k}={(after[k] or 0) - (before[k] or 0)}`)
			end
			local d = record.detail
			if workload == "arrange-shapes" then
				print(
					`  {passName}: p50={f(d.solveMs.p50_ms)}ms p95={f(d.solveMs.p95_ms)}ms `
						.. `arranged={d.arrangedNodes} measured={d.measuredNodes} `
						.. `us/arrNode={f(d.usPerArrangedNode)} us/measNode={f(d.usPerMeasuredNode)} `
						.. `meas/arr={f(d.measuresPerArrangedNode, 2)} `
						.. `partial={d.partialSolves}`
				)
			else
				print(
					`  {passName}: p50={f(d.editMs.p50_ms)}ms p95={f(d.editMs.p95_ms)}ms `
						.. `arrange/edit={f(d.arrangePerEdit, 2)} mount/edit={f(d.mountPerEdit, 2)} `
						.. `partial/edit={f(d.partialSolvesPerEdit, 2)} skipped={d.lastSkipped} `
						.. `arranged={d.arrangedNodes} window={d.mountedRows}`
				)
			end
			print(`      lapWork: {table.concat(lap, " ")}`)
		end)
		if not ok then
			print(`  {passName}: ERROR {tostring(err)}`)
		end
		pcall(built.dispose)
	end
end

profile.setHooks(nil, nil)
profile.setEnabled(false)
