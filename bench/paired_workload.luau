--!strict

local json = require("@std/json")
local process = require("@std/process")
local Lute = require("../tools/vendor/verify/src/lute")
local Json = require("../tools/facet/lib/json")
local Retained = require("../tools/facet/lib/perf_retained")
local perf_runner = require("./perf_runner")
local perf_scenes = require("./perf_scenes")
local perf_profiles = require("./perf_profiles")
local nativeApp = require("./native_app")

type Scene = {
	name: string,
	samples: number,
	warmup: number,
	timing: () -> unknown,
	setup: (profile: perf_profiles.Profile) -> nativeApp.State,
	run: (state: perf_scenes.SceneState) -> unknown,
	afterRun: (state: perf_scenes.SceneState) -> (),
	teardown: (state: perf_scenes.SceneState) -> (),
}
type MemoryState = { world: nativeApp.State, fixture: perf_scenes.SceneState }

local function emit(fields: { [string]: json.Value })
	print("@@" .. json.serialize(fields))
end

local name = assert(process.args[2], "a paired scene name is required")
local memoryOnly = process.args[3] == "--memory-only"
local plantedBytes = tonumber(process.args[4] or "0")
assert(plantedBytes ~= nil and plantedBytes >= 0 and plantedBytes <= 16 * 1024 * 1024 and plantedBytes % 1 == 0)
assert(memoryOnly or plantedBytes == 0, "retained allocation controls require the memory-only diagnostic")

local function findScene(sceneName: string, profile: perf_profiles.Profile): Scene?
	for _, candidate in perf_scenes do
		if candidate.name == sceneName then
			local source: unknown = candidate
			local samples, warmup = candidate.samples, candidate.warmup
			assert(
				type(samples) == "number" and type(warmup) == "number",
				"a paired scene needs declared sampling counts"
			)
			return {
				name = candidate.name,
				samples = samples,
				warmup = warmup,
				timing = function(): unknown
					return perf_runner.runScene(source, profile)
				end,
				setup = candidate.setup,
				run = candidate.run,
				afterRun = candidate.afterRun,
				teardown = candidate.teardown,
			}
		end
	end
	return nil
end
local profile = perf_profiles.get(perf_profiles.REFERENCE)
local scene = findScene(name, profile)
if scene == nil then
	emit({ scene = name, status = "missing" })
	process.exit(0)
end
assert(scene ~= nil)
local chosen: Scene = scene
local fields: { [string]: json.Value } = { scene = name, status = "ok", profile = profile.name }

local ok, problem = pcall(function()
	local record = chosen.timing()
	local total = Json.field(Json.field(record, "phases"), "total")
	fields.p50 = assert(Json.numberField(total, "p50_ms"))
	fields.p95 = assert(Json.numberField(total, "p95_ms"))
	fields.p99 = assert(Json.numberField(total, "p99_ms"))
	fields.samples = assert(Json.numberField(total, "samples"))
	local retained: buffer? = nil
	local memory = Lute.memory.measure({
		setup = function()
			local state = chosen.setup(profile)
			if plantedBytes > 0 then
				retained = buffer.create(plantedBytes)
			end
			local fixture: perf_scenes.SceneState =
				{ workload = state.workload, target = state.target, dispose = state.dispose }
			return { world = state, fixture = fixture }
		end,
		run = function(state: MemoryState)
			chosen.run(state.fixture)
		end,
		afterRun = function(state: MemoryState)
			chosen.afterRun(state.fixture)
		end,
		teardown = function(state: MemoryState)
			chosen.teardown(state.fixture)
		end,
		warmup = chosen.warmup,
		iterations = chosen.samples,
	}, { cycles = Retained.CYCLES })
	if retained ~= nil then
		assert(buffer.len(retained) == plantedBytes)
	end
	fields.memory = {
		method = memory.method,
		cycles = memory.baseline.cycles,
		baselineKb = memory.baseline.heapKb,
		mountedKb = memory.mounted.heapKb,
		teardownKb = memory.teardown.heapKb,
		mountedRetainedKb = memory.mountedRetainedKb,
		teardownRetainedKb = memory.teardownRetainedKb,
		baselineAllocations = memory.baseline.allocations,
		mountedAllocations = memory.mounted.allocations,
		teardownAllocations = memory.teardown.allocations,
	}
	return true
end)
if not ok then
	emit({ scene = name, status = "failed", error = string.sub(tostring(problem), 1, 1000) })
	process.exit(0)
end
emit(fields)
process.exit(0)
