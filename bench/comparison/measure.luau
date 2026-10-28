--!strict

local Benchmark = require("../../tools/vendor/verify/src/benchmark")
local Lute = require("../../tools/vendor/verify/src/lute")
local Verify = require("../../tools/vendor/verify/src/core")
local Roblox = require("../../tools/vendor/verify/src/roblox")
local NativeApp = require("../native_app")
local Types = require("./types")
local Report = require("../../tools/facet/lib/bench_compare_report")
local Scenarios = require("../scenarios")

export type Evidence = {
	problem: string?,
	timing: Benchmark.CollectionResult,
	memory: { [string]: { Lute.MemoryResult } },
	rows: { Report.Row },
	work: { [string]: { properties: { [string]: number }, classes: { [string]: number } } },
}
type Sample = { world: Types.World, scene: Types.Scene }

local function prepare(workload: Types.Workload, lane: Types.Lane): Sample
	local world = NativeApp({ textService = true })
	return { world = world, scene = workload.prepare(world, lane) }
end

local function exercise(workload: Types.Workload, sample: Sample)
	for index = 1, workload.iterations do
		sample.scene.step(index)
	end
end

local function release(sample: Sample)
	sample.scene.stop()
	sample.world.dispose()
end

local function median(values: { number }): number
	return assert(Verify.performance.summarize({
		samples = values,
		unit = "KiB",
		context = { environment = "facet-lute", signal = "retained-heap", timing = "observed" },
	}).p50)
end

return function(workload: Types.Workload, position: number): Evidence
	local lanes: { Types.Lane } = if position % 2 == 1 then { "plain", "facet" } else { "facet", "plain" }
	local specs: { Benchmark.Spec } = {}
	for _, lane in lanes do
		assert(lane == "plain" or lane == "facet")
		local current: Sample? = nil
		local spec: Benchmark.Spec = {
			name = tostring(lane),
			unit = "microseconds",
			samples = 9,
			warmup = 2,
			warmupScope = "sample",
			iterations = 1,
			environment = { observed = "facet-lute" },
			deadlineSeconds = 300,
			beforeSample = function()
				current = prepare(workload, lane)
			end,
			workload = function()
				exercise(workload, assert(current))
			end,
			afterSample = function()
				release(assert(current))
				current = nil
			end,
		}
		table.insert(specs, spec)
	end
	local reference: Scenarios.Scenario? = nil
	for _, scenario in Scenarios do
		if scenario.name == "zz-yardstick-cpu" then
			reference = scenario
			break
		end
	end
	local cpu = assert(reference)
	local referenceState = cpu.setup()
	local timing = Benchmark.collect({
		name = workload.id,
		benchmarks = specs,
		calibrationAttempts = 3,
		yardstick = {
			run = function()
				cpu.run(referenceState)
			end,
			samples = 32,
			warmup = 16,
			iterations = 20,
			maxSpread = 4,
			maxDrift = 0.25,
			driftBase = "mean",
		},
	})
	if cpu.teardown then
		cpu.teardown(referenceState)
	end
	local memory: { [string]: { Lute.MemoryResult } } = {}
	local rows: { Report.Row } = {}
	local work: { [string]: { properties: { [string]: number }, classes: { [string]: number } } } = {}
	if timing.failure ~= nil or #timing.invalid > 0 then
		return {
			timing = timing,
			memory = memory,
			rows = rows,
			work = work,
			problem = timing.failure or Lute.encode(timing.invalid),
		}
	end
	for _, lane in { "plain", "facet" } do
		assert(lane == "plain" or lane == "facet")
		local result: Benchmark.Result? = nil
		for _, candidate in timing.results do
			if candidate.name == lane then
				result = candidate
				break
			end
		end
		if not result or result.failure ~= nil or #result.invalid > 0 or #result.samples ~= 9 then
			return { timing = timing, memory = memory, rows = rows, work = work, problem = Lute.encode(result) }
		end
		local mounted, teardown = {}, {}
		memory[lane] = {}
		for _ = 1, 3 do
			local world = NativeApp({ textService = true })
			local retained = Lute.memory.measure({
				setup = function()
					return { world = world, scene = workload.prepare(world, lane) }
				end,
				run = function(sample: Sample)
					exercise(workload, sample)
				end,
				teardown = function(sample: Sample)
					sample.scene.stop()
				end,
				iterations = 1,
			}, { cycles = 8, maxAllocations = 2500000, deadlineSeconds = 30 })
			world.dispose()
			table.insert(memory[lane], retained)
			table.insert(mounted, retained.mountedRetainedKb)
			table.insert(teardown, retained.teardownRetainedKb)
		end
		local sample = prepare(workload, lane)
		local writes, created = 0, 0
		local properties: { [string]: number } = {}
		local classes: { [string]: number } = {}
		local observer = sample.world.engine.environment.observe(function(event: Roblox.EnvironmentEvent)
			if event.operation == "setProperty" then
				writes += 1
				local key = event.object.ClassName .. "." .. assert(event.member)
				properties[key] = (properties[key] or 0) + 1
			elseif event.operation == "create" then
				created += 1
				local key = event.object.ClassName
				classes[key] = (classes[key] or 0) + 1
			end
		end)
		exercise(workload, sample)
		observer:Disconnect()
		work[lane] = { properties = properties, classes = classes }
		release(sample)
		table.insert(rows, {
			workload = workload.id,
			iterations = workload.iterations,
			lane = tostring(lane),
			microseconds = assert(result.summary.p50),
			mountedKb = median(mounted),
			teardownKb = median(teardown),
			writes = writes,
			created = created,
		})
	end
	return { timing = timing, memory = memory, rows = rows, work = work }
end
