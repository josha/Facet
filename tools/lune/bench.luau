--!strict

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local artifact = require("./artifact")

local scenarios = require("../../bench/scenarios")

local WARMUP = 50

local SAMPLES = 1500
local REGRESSION_FACTOR = 1.5

local REGRESSION_FLOOR_MS = 0.05

local YARDSTICK = "zz-yardstick-cpu"

if #scenarios == 0 then
	print("bench: FAIL - no scenarios registered in bench/scenarios.luau (hint: land the core bake-off scenarios)")
	process.exit(1)
end

local function percentile(sorted: { number }, p: number): number
	local idx = math.max(1, math.ceil(p * #sorted))
	return sorted[idx]
end

local baseline: any = nil
if fs.isFile("bench/baseline.json") then
	baseline = serde.decode("json", fs.readFile("bench/baseline.json"))
end

local fidelity = serde.decode("json", fs.readFile("bench/workload_fidelity.json"))
assert(fidelity.status == "verified", "microbenchmark workload fidelity audit is incomplete")
local results = {}
local failed = false

local function measure(scenario: any): any?
	local entry: any = nil
	local ok, err = pcall(function()
		local sampleCount: number = scenario.samples or SAMPLES
		local warmupCount: number = scenario.warmup or WARMUP
		local state = scenario.setup()
		for _ = 1, warmupCount do
			scenario.run(state)
		end
		local samples = table.create(sampleCount, 0)

		local CHECKPOINTS = 10
		local every = math.max(1, sampleCount // CHECKPOINTS)
		local heapFirst = gcinfo()
		local heapLast, heapMin, heapMax = heapFirst, heapFirst, heapFirst
		for i = 1, sampleCount do
			local t0 = os.clock()
			scenario.run(state)
			samples[i] = (os.clock() - t0) * 1000
			if i % every == 0 then
				heapLast = gcinfo()
				heapMin = math.min(heapMin, heapLast)
				heapMax = math.max(heapMax, heapLast)
			end
		end
		if scenario.teardown then
			scenario.teardown(state)
		end
		table.sort(samples)
		entry = {
			name = scenario.name,
			requirement = scenario.requirement,
			samples = sampleCount,
			warmup = warmupCount,
			p50_ms = percentile(samples, 0.50),
			p95_ms = percentile(samples, 0.95),
			p99_ms = percentile(samples, 0.99),
			heapNetKb = heapLast - heapFirst,
			heapSwingKb = heapMax - heapMin,
			regression = false,
		}
	end)
	if not ok then
		print(`  {scenario.name}: ERROR {err}`)
		failed = true
		return nil
	end
	return entry
end

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

local yardBefore = measure(yardstickScenario)
for _, scenario in subjects do
	local entry = measure(scenario)
	if entry ~= nil then
		table.insert(results, entry)
	end
end
local yardAfter = measure(yardstickScenario)

if yardBefore == nil or yardAfter == nil then
	print("bench: FAIL - the yardstick did not measure; every ratio would be meaningless")
	process.exit(1)
end
local yardstickP95 = (yardBefore.p95_ms + yardAfter.p95_ms) / 2
if not (yardstickP95 > 0) then
	print("bench: FAIL - the yardstick measured zero; refusing to divide by it")
	process.exit(1)
end

local yardstickDriftPct = math.abs(yardAfter.p95_ms - yardBefore.p95_ms) / yardstickP95 * 100

local baselineHasNorm = false
if baseline ~= nil then
	for _, b in baseline.results or {} do
		if b.p95_norm ~= nil then
			baselineHasNorm = true
			break
		end
	end
end

for _, entry in results do
	entry.p95_norm = entry.p95_ms / yardstickP95
	entry.p50_norm = entry.p50_ms / yardstickP95
	if baseline ~= nil then
		for _, b in baseline.results or {} do
			if b.name == entry.name then
				local aboveFloor = entry.p95_ms > REGRESSION_FLOOR_MS or b.p95_ms > REGRESSION_FLOOR_MS
				if baselineHasNorm and b.p95_norm ~= nil then
					entry.baseline_p95_norm = b.p95_norm

					if b.gateChannel == "p50_norm" and b.p50_norm ~= nil and entry.p50_norm ~= nil then
						entry.gateChannel = "p50_norm"
						entry.ratio = entry.p50_norm / b.p50_norm
					else
						entry.ratio = entry.p95_norm / b.p95_norm
					end
					if entry.ratio > REGRESSION_FACTOR and aboveFloor then
						entry.regression = true
						failed = true
					end
				elseif entry.p95_ms > b.p95_ms * REGRESSION_FACTOR and aboveFloor then
					entry.regression = true
					failed = true
				end
			end
		end
	end
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
yardBefore.name = `{YARDSTICK}-before`
yardAfter.name = `{YARDSTICK}-after`
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
	status = if failed then "FAIL" else "PASS",
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
print(`bench: {failed and "FAIL" or "PASS"} (artifacts/bench.json)`)
process.exit(if failed then 1 else 0)
