--!strict

local Files = require("./files")
local Json = require("./json")
local Run = require("./run")
local Benchmark = require("../../vendor/verify/src/benchmark")
local Verify = require("../../vendor/verify/src/core")
local Loader = require("../../../tests/lib/loader")

type Scenario = {
	name: string,
	requirement: string,
	samples: number?,
	warmup: number?,
	setup: () -> unknown,
	run: (unknown) -> (),
	teardown: ((unknown) -> ())?,
}
type BaselineRow = {
	name: string,
	p50_ms: number,
	p95_ms: number,
	p50_norm: number?,
	p95_norm: number?,
	gateChannel: string?,
}
type Entry = {
	name: string,
	requirement: string,
	samples: number,
	warmup: number,
	p50_ms: number,
	p95_ms: number,
	p99_ms: number,
	heapNetKb: number?,
	heapSwingKb: number?,
	regression: boolean,
	p95_norm: number?,
	p50_norm: number?,
	baseline_p95_norm: number?,
	gateChannel: string?,
	ratio: number?,
}
type Member = { spec: Benchmark.Spec, scenario: Scenario, heap: () -> (number, number) }

local WARMUP = 50
local SAMPLES = 1500
local REGRESSION_FACTOR = 1.5
local REGRESSION_FLOOR_MS = 0.05
local YARDSTICK = "zz-yardstick-cpu"
local YARDSTICK_ITERATIONS = 20
local YARDSTICK_SAMPLES = 100
local YARDSTICK_WARMUP = 25
local UNGATED = 1e12
local DRIFT_LIMIT = 0.25
local ENVIRONMENT = "facet-lute"
local BASELINE = "bench/baseline.json"
local ARTIFACT = "artifacts/bench.json"

return function(shard: { index: number, count: number }?): number
	local synced = Run.inherit({ Run.lute(), "run", "tools/facet", "sync", "compose", "--check" })
	if not synced.ok then
		return 1
	end

	local scenarios = Loader.new().require("bench/scenarios.luau") :: { Scenario }
	if #scenarios == 0 then
		print("bench: FAIL - no scenarios registered in bench/scenarios.luau (hint: land the core bake-off scenarios)")
		return 1
	end

	local yardstickScenario: Scenario? = nil
	local subjects: { Scenario } = {}
	for _, s in scenarios do
		if s.name == YARDSTICK then
			yardstickScenario = s
		else
			table.insert(subjects, s)
		end
	end
	if shard then
		table.sort(subjects, function(left: Scenario, right: Scenario): boolean
			return left.name < right.name
		end)
		local share: { Scenario } = {}
		for position, scenario in subjects do
			if (position - 1) % shard.count == shard.index - 1 then
				table.insert(share, scenario)
			end
		end
		subjects = share
	end
	if yardstickScenario == nil then
		print(`bench: FAIL - the yardstick scenario '{YARDSTICK}' is not registered in bench/scenarios.luau`)
		return 1
	end
	local yardstick = yardstickScenario :: Scenario

	local baselineHasNorm = false
	local baselineRows: { [string]: BaselineRow } = {}
	if Files.isFile(BASELINE) then
		local baseline = Json.decode(Files.read(BASELINE)) :: { results: { BaselineRow }? }
		local results: { BaselineRow } = baseline.results or {}
		for _, b in results do
			baselineRows[b.name] = b
			if b.p95_norm ~= nil then
				baselineHasNorm = true
			end
		end
	end

	local function baselineOf(row: BaselineRow?): Benchmark.Baseline?
		if row == nil then
			return nil
		end
		local floor: Benchmark.Floor = { limit = REGRESSION_FLOOR_MS, metric = "p95", recorded = row.p95_ms }
		if not baselineHasNorm or row.p95_norm == nil then
			return {
				identity = BASELINE,
				environment = ENVIRONMENT,
				unit = "milliseconds",
				metric = "p95",
				value = row.p95_ms,
				tolerance = REGRESSION_FACTOR - 1,
				floor = floor,
			}
		end
		local gated = row.gateChannel == "p50_norm" and row.p50_norm ~= nil
		return {
			identity = BASELINE,
			environment = ENVIRONMENT,
			unit = "milliseconds",
			metric = if gated then "p50" else "p95",
			value = if gated then row.p50_ms else row.p95_ms,
			tolerance = REGRESSION_FACTOR - 1,
			yardstick = if gated then row.p50_ms / (row.p50_norm :: number) else row.p95_ms / (row.p95_norm :: number),
			yardstickStatistic = "p95",
			floor = floor,
		}
	end

	local function member(scenario: Scenario): Member
		local sampleCount: number = scenario.samples or SAMPLES
		local warmupCount: number = scenario.warmup or WARMUP
		local every = math.max(1, sampleCount // 10)
		local state: unknown = nil
		local taken = 0
		local heapFirst, heapLast, heapMin, heapMax = 0, 0, 0, 0
		local spec: Benchmark.Spec = {
			name = scenario.name,
			unit = "milliseconds",
			warmup = warmupCount,
			samples = sampleCount,
			environment = { observed = ENVIRONMENT },
			baseline = baselineOf(baselineRows[scenario.name]),
			setup = function()
				state = scenario.setup()
			end,
			workload = function()
				scenario.run(state)
			end,
			beforeSample = function()
				if taken == 0 then
					heapFirst = gcinfo()
					heapLast, heapMin, heapMax = heapFirst, heapFirst, heapFirst
				end
			end,
			afterSample = function()
				taken += 1
				if taken % every == 0 then
					heapLast = gcinfo()
					heapMin = math.min(heapMin, heapLast)
					heapMax = math.max(heapMax, heapLast)
				end
			end,
			teardown = function()
				if scenario.teardown then
					scenario.teardown(state)
				end
			end,
		}
		return {
			spec = spec,
			scenario = scenario,
			heap = function()
				return heapLast - heapFirst, heapMax - heapMin
			end,
		}
	end

	local members: { Member } = {}
	local specs: { Benchmark.Spec } = {}
	for _, scenario in subjects do
		local entry = member(scenario)
		table.insert(members, entry)
		table.insert(specs, entry.spec)
	end
	local yardstickState = yardstick.setup()
	local collected = Benchmark.collect({
		name = "facet-bench",
		benchmarks = specs,
		yardstick = {
			run = function()
				yardstick.run(yardstickState)
			end,
			samples = YARDSTICK_SAMPLES,
			iterations = YARDSTICK_ITERATIONS,
			warmup = YARDSTICK_WARMUP,
			maxSpread = UNGATED,
			maxDrift = DRIFT_LIMIT,
			driftStatistic = "median",
			driftBase = "mean",
		},
	})
	if yardstick.teardown then
		yardstick.teardown(yardstickState)
	end
	if collected.failure ~= nil then
		print(`bench: FAIL - the yardstick did not measure; every ratio would be meaningless ({collected.failure})`)
		return 1
	end

	local function yardstickEntry(samples: { number }, suffix: string): Entry
		local summary = Verify.performance.summarize({
			samples = samples,
			unit = "ms",
			context = { environment = ENVIRONMENT, signal = YARDSTICK, timing = "observed" },
		})
		return {
			name = `{YARDSTICK}-{suffix}`,
			requirement = yardstick.requirement,
			samples = #samples,
			warmup = YARDSTICK_WARMUP,
			p50_ms = assert(summary.p50),
			p95_ms = assert(summary.p95),
			p99_ms = assert(summary.p99),
			regression = false,
		}
	end
	local yardBefore = yardstickEntry(collected.yardstickBefore, "before")
	local yardAfter = yardstickEntry(collected.yardstickAfter, "after")
	local yardstickP95 = (yardBefore.p95_ms + yardAfter.p95_ms) / 2
	if not (yardstickP95 > 0) then
		print("bench: FAIL - the yardstick measured zero; refusing to divide by it")
		return 1
	end
	local yardstickDriftPct = math.abs(yardAfter.p95_ms - yardBefore.p95_ms) / yardstickP95 * 100
	local yardstickMedian = (yardBefore.p50_ms + yardAfter.p50_ms) / 2
	local yardstickMedianDriftPct = math.abs(yardAfter.p50_ms - yardBefore.p50_ms) / yardstickMedian * 100

	local results: { Entry } = {}
	local failed = false
	local errored = false
	for index, result in collected.results do
		if result.failure ~= nil then
			print(`  {result.name}: ERROR {result.failure}`)
			errored = true
			continue
		end
		local scenario = members[index].scenario
		local heapNet, heapSwing = members[index].heap()
		local summary = assert(result.summary)
		local entry: Entry = {
			name = scenario.name,
			requirement = scenario.requirement,
			samples = scenario.samples or SAMPLES,
			warmup = scenario.warmup or WARMUP,
			p50_ms = assert(summary.p50),
			p95_ms = assert(summary.p95),
			p99_ms = assert(summary.p99),
			heapNetKb = heapNet,
			heapSwingKb = heapSwing,
			regression = false,
		}
		entry.p95_norm = entry.p95_ms / yardstickP95
		entry.p50_norm = entry.p50_ms / yardstickP95
		local comparison = result.comparison
		local row = baselineRows[entry.name]
		if comparison ~= nil and row ~= nil then
			if comparison.normalized then
				entry.baseline_p95_norm = row.p95_norm
				entry.gateChannel = if comparison.metric == "p50" then "p50_norm" else nil
				entry.ratio = comparison.observed / comparison.baseline
			end
			entry.regression = comparison.regressed
		end
		failed = failed or entry.regression
		table.insert(results, entry)
	end
	for _, entry in results do
		print(
			`  {entry.name}: p50={string.format("%.4f", entry.p50_ms)}ms p95={string.format("%.4f", entry.p95_ms)}ms`
				.. ` norm={string.format("%.3f", entry.p95_norm or 0)}`
				.. (if entry.ratio ~= nil
					then ` vs-base={string.format("%.2f", entry.ratio)}x{if entry.gateChannel == "p50_norm"
						then " (p50 gate)"
						else ""}`
					else "")
				.. ` heapNet={entry.heapNetKb}KB(swing {entry.heapSwingKb}KB){if entry.regression
					then "  REGRESSION"
					else ""}`
		)
	end

	local phaseDominated = 0
	for _, entry in results do
		local swing, net = entry.heapSwingKb, entry.heapNetKb
		if swing ~= nil and net ~= nil and swing > math.abs(net) then
			phaseDominated += 1
		end
	end
	if phaseDominated > 0 then
		print(`  NOTE: on {phaseDominated}/{#results} scenes the heap SWING exceeds the heap NET. This host`)
		print("        cannot force a collection, so a heap number is allocation churn plus")
		print("        collector phase — not retention. Compare nets across runs; never read one sign.")
	end

	yardBefore.p95_norm = yardBefore.p95_ms / yardstickP95
	yardAfter.p95_norm = yardAfter.p95_ms / yardstickP95
	table.insert(results, yardBefore)
	table.insert(results, yardAfter)
	print(
		`  {YARDSTICK}: {string.format("%.4f", yardstickP95)}ms (before {string.format("%.4f", yardBefore.p95_ms)}, `
			.. `after {string.format("%.4f", yardAfter.p95_ms)}, p95 drift {string.format("%.1f", yardstickDriftPct)}%, `
			.. `CPU median drift {string.format("%.1f", yardstickMedianDriftPct)}%)`
	)
	if not baselineHasNorm then
		print("  NOTE: bench/baseline.json has no normalized values — falling back to the")
		print("        old raw-millisecond rule, which is load-sensitive. Re-freeze the")
		print("        baseline to get load-independent comparisons.")
	end

	local drifted = false
	for _, entry in collected.invalid do
		drifted = drifted or entry.reason == "yardstick_drift"
	end
	if drifted then
		failed = true
		print("")
		print(
			`  ⚠ UNTRUSTWORTHY RUN: the yardstick median moved {string.format("%.1f", yardstickMedianDriftPct)}% between the`
		)
		print(`    before and after readings (warn above {DRIFT_LIMIT * 100}%), so the machine was changing`)
		print("    speed while the scenes were measured. Ratios from this run are noise in")
		print("    both directions — a regression reported here may be load, and a real one")
		print("    may be hidden. Re-run on a quiet machine before believing either.")
		print("    Common cause: Roblox Studio open, or a gate batch running concurrently.")
		print("")
	end

	Files.write(ARTIFACT, Json.encode({
		schema = "facet-bench/1",
		status = if errored or failed then "FAIL" else "PASS",
		failureKind = if errored
			then "execution"
			elseif drifted then "calibration"
			elseif failed then "regression"
			else nil,
		expectedMeasurements = #subjects + 2,
		environment = "lute-headless (trend screening only; device authoritative per design §14.3)",
		warmup = WARMUP,
		samples = SAMPLES,
		regressionFactorP95 = REGRESSION_FACTOR,
		normalizedBy = YARDSTICK,
		yardstickP95Ms = yardstickP95,
		yardstickDriftPct = yardstickDriftPct,
		yardstickMedianDriftPct = yardstickMedianDriftPct,
		yardstickIterations = YARDSTICK_ITERATIONS,
		yardstickWarmupBatches = YARDSTICK_WARMUP,
		yardstickBefore = collected.yardstickBefore,
		yardstickAfter = collected.yardstickAfter,
		proofStatus = if drifted then "unstable-cpu-rate" else "stable-cpu-rate-trend",
		comparisonMode = if baselineHasNorm then "normalized" else "raw-legacy",
		results = results,
	}, { indent = 2, sortKeys = true, ascii = false }) .. "\n")
	if errored then
		print(`bench: FAIL - a scenario raised an error ({ARTIFACT})`)
		return 1
	end
	if failed then
		print(`bench: FAIL_ENVIRONMENT - a host timing comparison failed; see the rows above ({ARTIFACT})`)
		return 2
	end
	print(`bench: PASS ({ARTIFACT})`)
	return 0
end
