--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local artifact = require("./artifact")
local Benchmark = require("../vendor/verify/src/benchmark")
local Verify = require("../vendor/verify/src/core")

if not process.exec("python3", { "tools/sync_compose.py", "--check" }, { stdio = "inherit" }).ok then
	process.exit(1)
end

local scenarios = require("../../bench/scenarios")

local WARMUP = 50

local SAMPLES = 1500
local REGRESSION_FACTOR = 1.5

local REGRESSION_FLOOR_MS = 0.05

local YARDSTICK = "zz-yardstick-cpu"

local UNGATED = 1e12

if #scenarios == 0 then
	print("bench: FAIL - no scenarios registered in bench/scenarios.luau (hint: land the core bake-off scenarios)")
	process.exit(1)
end

local baseline: any = nil
if fs.isFile("bench/baseline.json") then
	baseline = serde.decode("json", fs.readFile("bench/baseline.json"))
end

local fidelity = serde.decode("json", fs.readFile("bench/workload_fidelity.json"))
assert(fidelity.status == "verified", "microbenchmark workload fidelity audit is incomplete")
local results = {}
local failed = false
local errored = false

local yardstickScenario: any = nil
local subjects = {}
for _, s in scenarios do
	if s.name == YARDSTICK then
		yardstickScenario = s
	else
		table.insert(subjects, s)
	end
end
if yardstickScenario == nil then
	print(`bench: FAIL - the yardstick scenario '{YARDSTICK}' is not registered in bench/scenarios.luau`)
	process.exit(1)
end

local baselineHasNorm = false
local baselineRows: { [string]: any } = {}
if baseline ~= nil then
	for _, b in baseline.results or {} do
		baselineRows[b.name] = b
		if b.p95_norm ~= nil then
			baselineHasNorm = true
		end
	end
end

local function baselineOf(row: any): Benchmark.Baseline?
	if row == nil then
		return nil
	end
	local floor = { limit = REGRESSION_FLOOR_MS, metric = "p95" :: "p95", recorded = row.p95_ms }
	if not baselineHasNorm or row.p95_norm == nil then
		return {
			identity = "bench/baseline.json",
			environment = "facet-lune",
			unit = "milliseconds",
			metric = "p95",
			value = row.p95_ms,
			tolerance = REGRESSION_FACTOR - 1,
			floor = floor,
		}
	end
	local gated = row.gateChannel == "p50_norm" and row.p50_norm ~= nil
	return {
		identity = "bench/baseline.json",
		environment = "facet-lune",
		unit = "milliseconds",
		metric = if gated then "p50" else "p95",
		value = if gated then row.p50_ms else row.p95_ms,
		tolerance = REGRESSION_FACTOR - 1,
		yardstick = if gated then row.p50_ms / row.p50_norm else row.p95_ms / row.p95_norm,
		yardstickStatistic = "p95",
		floor = floor,
	}
end

type Member = { spec: Benchmark.Spec, scenario: any, heap: () -> (number, number) }

local function member(scenario: any): Member
	local sampleCount: number = scenario.samples or SAMPLES
	local warmupCount: number = scenario.warmup or WARMUP
	local every = math.max(1, sampleCount // 10)
	local state: any = nil
	local taken = 0
	local heapFirst, heapLast, heapMin, heapMax = 0, 0, 0, 0
	local spec: Benchmark.Spec = {
		name = scenario.name,
		unit = "milliseconds",
		warmup = warmupCount,
		samples = sampleCount,
		environment = { observed = "facet-lune" },
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
local yardstickState = yardstickScenario.setup()
for _ = 1, yardstickScenario.warmup or WARMUP do
	yardstickScenario.run(yardstickState)
end
local collected = Benchmark.collect({
	name = "facet-bench",
	benchmarks = specs,
	yardstick = {
		run = function()
			yardstickScenario.run(yardstickState)
		end,
		samples = yardstickScenario.samples or SAMPLES,
		maxSpread = UNGATED,
		maxDrift = UNGATED,
	},
})
if yardstickScenario.teardown then
	yardstickScenario.teardown(yardstickState)
end
if collected.failure ~= nil then
	print(`bench: FAIL - the yardstick did not measure; every ratio would be meaningless ({collected.failure})`)
	process.exit(1)
end

local function yardstickEntry(samples: { number }, suffix: string): any
	local summary = Verify.performance.summarize({
		samples = samples,
		unit = "ms",
		context = { environment = "facet-lune", signal = YARDSTICK, timing = "observed" },
	})
	return {
		name = `{YARDSTICK}-{suffix}`,
		requirement = yardstickScenario.requirement,
		samples = #samples,
		warmup = yardstickScenario.warmup or WARMUP,
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
	process.exit(1)
end
local yardstickDriftPct = math.abs(yardAfter.p95_ms - yardBefore.p95_ms) / yardstickP95 * 100

for index, result in collected.results do
	if result.failure ~= nil then
		print(`  {result.name}: ERROR {result.failure}`)
		errored = true
		continue
	end
	local scenario = members[index].scenario
	local heapNet, heapSwing = members[index].heap()
	local entry: any = {
		name = scenario.name,
		requirement = scenario.requirement,
		samples = scenario.samples or SAMPLES,
		warmup = scenario.warmup or WARMUP,
		p50_ms = assert(result.summary.p50),
		p95_ms = assert(result.summary.p95),
		p99_ms = assert(result.summary.p99),
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
			.. ` norm={string.format("%.3f", entry.p95_norm)}`
			.. (if entry.ratio ~= nil
				then ` vs-base={string.format("%.2f", entry.ratio)}x{entry.gateChannel == "p50_norm" and " (p50 gate)" or ""}`
				else "")
			.. ` heapNet={entry.heapNetKb}KB(swing {entry.heapSwingKb}KB){entry.regression and "  REGRESSION" or ""}`
	)
end

local phaseDominated = 0
for _, entry in results do
	if entry.heapSwingKb ~= nil and entry.heapSwingKb > math.abs(entry.heapNetKb) then
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
		.. `after {string.format("%.4f", yardAfter.p95_ms)}, drift {string.format("%.1f", yardstickDriftPct)}%)`
)
if not baselineHasNorm then
	print("  NOTE: bench/baseline.json has no normalized values — falling back to the")
	print("        old raw-millisecond rule, which is load-sensitive. Re-freeze the")
	print("        baseline to get load-independent comparisons.")
end

local DRIFT_WARN_PCT = 15
if yardstickDriftPct > DRIFT_WARN_PCT then
	failed = true
	print("")
	print(`  ⚠ UNTRUSTWORTHY RUN: the yardstick moved {string.format("%.1f", yardstickDriftPct)}% between the`)
	print(`    before and after readings (warn above {DRIFT_WARN_PCT}%), so the machine was changing`)
	print("    speed while the scenes were measured. Ratios from this run are noise in")
	print("    both directions — a regression reported here may be load, and a real one")
	print("    may be hidden. Re-run on a quiet machine before believing either.")
	print("    Common cause: Roblox Studio open, or a gate batch running concurrently.")
	print("")
end

artifact.writeJson("artifacts/bench.json", {
	schema = "facet-bench/1",
	workloadFidelity = fidelity,
	status = if errored or failed then "FAIL" else "PASS",
	environment = "lune-headless (trend screening only; device authoritative per design §14.3)",
	warmup = WARMUP,
	samples = SAMPLES,
	regressionFactorP95 = REGRESSION_FACTOR,
	normalizedBy = YARDSTICK,
	yardstickP95Ms = yardstickP95,
	yardstickDriftPct = yardstickDriftPct,
	proofStatus = if yardstickDriftPct > DRIFT_WARN_PCT then "unstable-host" else "stable-host-trend",
	comparisonMode = if baselineHasNorm then "normalized" else "raw-legacy",
	results = results,
})
if errored then
	print("bench: FAIL - a scenario raised an error (artifacts/bench.json)")
	process.exit(1)
end
if failed then
	print("bench: FAIL_ENVIRONMENT - a host timing comparison failed; see the rows above (artifacts/bench.json)")
	process.exit(2)
end
print("bench: PASS (artifacts/bench.json)")
process.exit(0)
