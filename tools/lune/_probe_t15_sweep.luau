--!strict
-- T15 probe: boot EVERY declared perf-lab workload headlessly, run its passes,
-- reset, and re-run with the same seed. Throwaway measurement instrument.
local fs = require("@lune/fs")
local Facet = require("../../src")
local fake_target = require("../../tests/lib/fake_target")
local dataset = require("../../examples/performance/lab/dataset")
local rowsLib = require("../../examples/performance/lab/rows")
local captureLib = require("../../examples/performance/lab/capture")
local overlayLib = require("../../examples/performance/lab/overlay")
local leversLib = require("../../examples/performance/lab/levers")
local hapticsLib = require("../../src/client/haptics")
local perf_lab = require("../../examples/performance/lab/perf_lab")

local function newHarness()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 700 })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)
	local clock = 0
	local host: any = {
		facts = function()
			return {
				evidenceClass = "lune",
				capturedAtIso = "2026-08-21T00:00:00Z",
				sourceStamp = "t15",
				placeName = "headless",
				viewport = "900x700",
				orientation = "landscape",
				graphicsQualityLevel = "n/a",
				frameTarget = "n/a",
				studioVersion = "n/a",
				deviceLabel = "lune",
				thermalNote = "n/a",
				capturePath = "n/a",
				summaryPath = "n/a",
			}
		end,
	}
	local ctx: any = {
		Facet = Facet,
		core = core,
		env = env,
		adapter = adapter,
		presenter = pres,
		actionSystem = system,
		host = host,
		lab = {
			dataset = dataset,
			rows = rowsLib,
			capture = captureLib,
			overlay = overlayLib,
			levers = leversLib,
			haptics = hapticsLib,
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
	return perf_lab.build(ctx), ctx
end

local built0 = newHarness()
local declared = built0.steps.workloads()
print(`registry: {#declared.order} workloads, version {declared.scenarioVersion}`)
built0.dispose()

local rows = {}
local fails = 0
for _, w in declared.workloads do
	local built = newHarness()
	local okSelect, selErr = pcall(function()
		return built.steps.select(nil, `scenario={w.id},rows=200,seed=7`)
	end)
	local digestA, mountErr, passLog = "-", "-", {}
	if okSelect then
		local sel = built.steps.select(nil, `scenario={w.id},rows=200,seed=7`)
		digestA = tostring(sel.datasetDigest)
		local okMount, mErr = pcall(function()
			built.steps.mount()
		end)
		if not okMount then
			mountErr = tostring(mErr)
		end
		for _, passName in w.passes do
			local okPass, pErr = pcall(function()
				built.steps.pass(nil, passName .. "=2")
			end)
			if okPass then
				table.insert(passLog, `{passName}:ok`)
			else
				local msg = tostring(pErr)
				if string.find(msg, "unknown pass") then
					fails += 1
				end
				table.insert(passLog, `{passName}:REFUSED({string.sub(msg, 1, 60)})`)
			end
		end
	else
		fails += 1
		mountErr = tostring(selErr)
	end
	-- reset + reseed reproduction
	local digestB = "-"
	local okReset, rErr = pcall(function()
		built.steps.reset()
	end)
	if okReset then
		local sel2 = built.steps.select(nil, `scenario={w.id},rows=200,seed=7`)
		digestB = tostring(sel2.datasetDigest)
	else
		mountErr = mountErr .. " | reset:" .. tostring(rErr)
	end
	table.insert(rows, {
		id = w.id,
		digestA = digestA,
		digestB = digestB,
		reproduces = digestA == digestB,
		mountErr = mountErr,
		passes = table.concat(passLog, " "),
	})
	built.dispose()
end

for _, r in rows do
	print(`{r.id}\tdigest={r.digestA}\treproduces={r.reproduces}\tmount={r.mountErr}`)
	print(`    passes: {r.passes}`)
end
print(`HARD FAILS: {fails}`)
fs.writeFile("artifacts/release-candidate-review/perf/_sweep.json", require("@lune/serde").encode("json", rows, true))
