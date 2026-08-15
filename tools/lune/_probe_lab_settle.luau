--!strict
-- L-31 probe: drive the REAL performance lab headlessly and account for every
-- solve and every reactive flush in one `resizeStorm` step, so the device's
-- 7.12 arranges/step and 3.03 react/step are explained by name rather than by
-- a decomposition. Usage: lune run tools/lune/_probe_lab_settle

local LuauUI = require("../../src") :: any
local fake_target = require("../../tests/lib/fake_target")
local profile = require("../../src/core/profile")

local dataset = require("../../examples/performance/lab/dataset")
local rowsLib = require("../../examples/performance/lab/rows")
local captureLib = require("../../examples/performance/lab/capture")
local overlayLib = require("../../examples/performance/lab/overlay")
local leversLib = require("../../examples/performance/lab/levers")
local perf_lab = require("../../examples/performance/lab/perf_lab")

local spans: { [string]: number } = {}
local trace: { string } = {}
local tracing = false
profile.setEnabled(true)
profile.setHooks(function(label: string)
	spans[label] = (spans[label] or 0) + 1
	if tracing and (label == "LuauUI/react" or label == "LuauUI/arrange" or label == "LuauUI/mount") then
		table.insert(trace, (label:gsub("LuauUI/", "")))
	end
end, function() end)

local core = LuauUI.newCore()
local env = LuauUI.newEnvironment(core)
env:set("viewportRect", { x = 0, y = 0, w = 360, h = 691 })
local adapter = fake_target.new()
local system = LuauUI.newActionSystem(core)
local pres = LuauUI.newPresenter(core, env, adapter, system)
local clock = 0
local ctx: any = {
	LuauUI = LuauUI,
	core = core,
	env = env,
	adapter = adapter,
	presenter = pres,
	actionSystem = system,
	host = {
		facts = function()
			return {
				evidenceClass = "lune",
				capturedAtIso = "2026-08-14T00:00:00Z",
				sourceStamp = "probe",
				placeName = "headless",
				viewport = "360x691",
				orientation = "portrait",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lune host",
				thermalNote = "n/a",
				capturePath = "n/a",
				summaryPath = "n/a",
			}
		end,
	},
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

local built = perf_lab.build(ctx)
built.steps.select(nil, "scenario=resize-relayout,rows=500,seed=1")
built.steps.mount()

-- markers: what the LAB does, interleaved with what the FRAMEWORK does
local realRefresh = pres.refresh
pres.refresh = function(...)
	if tracing then
		table.insert(trace, "|refresh")
	end
	return realRefresh(...)
end
for _, key in { "viewportRect", "coreSafeInsets" } do
	core:observe(env:get(key), function()
		if tracing then
			table.insert(trace, `|{key}`)
		end
	end)
end

local STEPS = 3
local before = {
	react = spans["LuauUI/react"] or 0,
	arrange = spans["LuauUI/arrange"] or 0,
	mount = spans["LuauUI/mount"] or 0,
	commit = spans["LuauUI/commit"] or 0,
	measure = spans["LuauUI/measure"] or 0,
	present = spans["LuauUI/present"] or 0,
}
tracing = true
built.steps.pass(nil, `resizeStorm={STEPS}`)
tracing = false

local function per(key: string): string
	local d = (spans[`LuauUI/{key}`] or 0) - (before :: any)[key]
	return `{key}={d} ({string.format("%.2f", d / STEPS)}/step)`
end

print(`over {STEPS} resizeStorm steps:`)
print("  " .. per("react"))
print("  " .. per("arrange"))
print("  " .. per("measure"))
print("  " .. per("mount"))
print("  " .. per("commit"))
print("  " .. per("present"))
print(`trace = {table.concat(trace, " ")}`)
print(`lastError = {tostring(core:lastError())}`)
