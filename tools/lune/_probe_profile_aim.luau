--!strict
-- Device-capture 2026-08-15 probe: what does ONE lap of a `profileWindow` pass
-- actually provoke? The device capture of `async-image-churn` contained 29
-- byte-identical frames, zero `Facet/mount` and zero `Facet/resource` — the
-- looped pass was `passes[1]` = `imagesCold`, which sets a flag and refreshes.
-- This prints the per-lap scope deltas for every pass of the workloads the
-- director captured, so the claim is a table rather than a reading of the source.
-- Usage: lune run tools/lune/_probe_profile_aim

local Facet = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local profile = require("../../src/core/profile") :: any
local perf_lab = require("../../examples/performance/lab/perf_lab") :: any
local dataset = require("../../examples/performance/lab/dataset")
local rowsLib = require("../../examples/performance/lab/rows")
local captureLib = require("../../examples/performance/lab/capture")
local overlayLib = require("../../examples/performance/lab/overlay")
local leversLib = require("../../examples/performance/lab/levers")

local SCOPES = { "arrange", "measure", "mount", "react", "commit", "resource", "reset", "present" }

local function newHarness(): any
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)
	local clock = 0
	local host: any = { profile = profile }
	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		host = host,
		lab = { dataset = dataset, rows = rowsLib, capture = captureLib, overlay = overlayLib, levers = leversLib },
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

profile.setEnabled(true)
profile.setHooks(function() end, function() end)

local PLAN = {
	{ "async-image-churn", { "imagesCold", "imagesWarm", "imagesFail", "imagesReuse" } },
	{ "collection-churn", { "insert", "remove", "reorder", "selectRow", "scrollSteady" } },
}

for _, spec in PLAN do
	local workload = spec[1] :: string
	print(`\n=== {workload}`)
	for _, passName in spec[2] :: { string } do
		local built = newHarness()
		local ok, err = pcall(function()
			built.steps.select(nil, `scenario={workload},rows=400,seed=1`)
			built.steps.mount()
			profile.resetCounters()
			local before = counts()
			built.steps.pass(nil, passName)
			local after = counts()
			local parts = {}
			for _, k in SCOPES do
				table.insert(parts, `{k}={(after[k] or 0) - (before[k] or 0)}`)
			end
			print(`  {passName}: {table.concat(parts, " ")}`)
		end)
		if not ok then
			print(`  {passName}: ERROR {tostring(err)}`)
		end
		pcall(built.dispose)
	end
end

profile.setHooks(nil, nil)
profile.setEnabled(false)
