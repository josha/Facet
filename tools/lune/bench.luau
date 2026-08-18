--!strict
-- Facet bench (design §16.1, §14.3): runs named scenarios from
-- bench/scenarios.luau, records p50/p95/p99 wall time plus a heap net and the
-- collector SWING around it (never a retention figure — see `measure`), writes
-- artifacts/bench.json, compares against bench/baseline.json when present.
-- Headless Lune numbers are trend screening only — device measurements stay
-- authoritative (§14.3). Exits nonzero on empty registry, error, or regression.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local artifact = require("./artifact")

local scenarios = require("../../bench/scenarios")

local WARMUP = 50
--[[ 1500, NOT 300 (measured 2026-08-16).

	The gated value is a p95 — an ORDER STATISTIC — and at 300 samples it was not
	a stable one. On an allocation-heavy scene a collector pause is a discrete
	event that either does or does not land inside the top 5% of a given run, so
	the same source produced a bimodal p95: `textinput-typing-storm` read
	0.518 0.529 0.544 0.560 0.561 | 0.640 0.842 0.948 1.072 normalized over nine
	runs at FIXED source, while its p50 never left 0.108-0.114ms. That is an A/A
	control spread of 2.07x against a REGRESSION_FACTOR of 1.5 — the gate could
	not distinguish a real 1.5x regression from its own noise, which is why this
	scene has been carried on prior-gate allow-lists as an "instrument" failure.

	Raising the sample count fixes it at the root, because it lets the pause rate
	be SAMPLED rather than caught or missed. Measured A/A over the scenes that
	are actually gate-eligible (median p95 above REGRESSION_FLOOR_MS):

	    worst spread @300  = 2.07x  (textinput-typing-storm)  -> un-adjudicable
	    worst spread @1500 = 1.22x  (billboard-nameplate-storm)

	Taking the median of several 300-sample runs does NOT substitute: measured
	median-of-3 = 1.79x and median-of-5 = 1.55x, both still above the factor.
	Cost is 2.5s -> 10.4s for the whole bench, which a gate can afford.
	Changing this REQUIRES re-freezing bench/baseline.json — p95 rises when the
	tail is properly represented rather than intermittently missed. ]]
local SAMPLES = 1500
local REGRESSION_FACTOR = 1.5 -- normalized p95 vs baseline
-- below this, p95 differences are OS-scheduler jitter, not regressions:
-- a 1.5x factor on a ~2 microsecond scenario flip-flops run to run
-- (2026-07-19 phase-gate verifier finding 1)
local REGRESSION_FLOOR_MS = 0.05

-- THE YARDSTICK (2026-07-28). Raw milliseconds are not a stable instrument on a
-- developer laptop: the SAME source measured a gated scene at 1.29x quiet,
-- 1.40x mid gate-batch and 1.54x with Roblox Studio open, and the gate went red
-- for none of those reasons. Raising REGRESSION_FACTOR would only trade false
-- alarms for a real 2x slipping through.
--
-- So each scene is divided by a Facet-free CPU workload measured in the same
-- run on the same machine (bench/scenarios.luau "zz-yardstick-cpu"), and the
-- RATIO is what gets compared. A slow day lifts both and the ratio holds still.
--
-- It is measured TWICE, once before the scenes and once after, and averaged:
-- one reading taken at the end alone would miss load that arrived mid-run.
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

local results = {}
local failed = false

-- one timing pass over a scenario; returns the entry or nil on error
local function measure(scenario: any): any?
	local entry: any = nil
	local ok, err = pcall(function()
		local state = scenario.setup()
		for _ = 1, WARMUP do
			scenario.run(state)
		end
		local samples = table.create(SAMPLES, 0)
		--[[ HEAP: SAMPLED, AND PUBLISHED WITH ITS SWING (measured 2026-08-16).

			This used to be one `gcinfo()` at each end, reported as `heapDeltaKb`.
			Lune's `collectgarbage` accepts only "count" — there is NO forced
			collection on this host — so that difference could never be retention.
			It is where the collector happened to be at two instants, and it reads
			like retention, which is exactly how it got read: a +2659KB reading on
			billboard-nameplate-storm was investigated as 2.6MB of retained memory.

			What that scene actually does, measured: thirty consecutive identical
			300-sample windows read +1281, +678, -2050, +2163, -2397, +1942 ... KB
			— sign flipping, swinging ±3.7MB — while the mean was 144KB/window
			(151KB on the repeat) and the adapter's node count never moved off 3.
			The single-window number overstated the truth ~17x and its SIGN was
			noise. The same source read +2714KB in one checkout and -580KB in
			another, differing only by directory path.

			So the net is still published, but never alone: `heapSwingKb` is the
			peak-to-trough excursion across the checkpoints, and when it dwarfs the
			net (the note below) the net is inside the collector's cycle and means
			nothing on its own. Compare NETS ACROSS RUNS; never read one sign. ]]
		local CHECKPOINTS = 10
		local every = SAMPLES // CHECKPOINTS
		local heapFirst = gcinfo()
		local heapLast, heapMin, heapMax = heapFirst, heapFirst, heapFirst
		for i = 1, SAMPLES do
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
			samples = SAMPLES,
			warmup = WARMUP,
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

-- split the yardstick out: it is the divisor, not a measured subject
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

-- before ... scenes ... after, then average: a single reading taken at the end
-- would miss load that arrived mid-run
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
-- how much the machine moved DURING the run. A large drift means the ratios are
-- being taken against a moving divisor and deserve less trust; it is reported
-- rather than silently absorbed.
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
	if baseline ~= nil then
		for _, b in baseline.results or {} do
			if b.name == entry.name then
				-- the floor still applies to RAW milliseconds: a scene of a few
				-- microseconds is scheduler jitter whatever you divide it by
				local aboveFloor = entry.p95_ms > REGRESSION_FLOOR_MS or b.p95_ms > REGRESSION_FLOOR_MS
				if baselineHasNorm and b.p95_norm ~= nil then
					entry.baseline_p95_norm = b.p95_norm
					entry.ratio = entry.p95_norm / b.p95_norm
					if entry.ratio > REGRESSION_FACTOR and aboveFloor then
						entry.regression = true
						failed = true
					end
				elseif entry.p95_ms > b.p95_ms * REGRESSION_FACTOR and aboveFloor then
					-- legacy baseline (raw ms only): the old, load-sensitive rule
					entry.regression = true
					failed = true
				end
			end
		end
	end
	print(
		`  {entry.name}: p50={string.format("%.4f", entry.p50_ms)}ms p95={string.format("%.4f", entry.p95_ms)}ms`
			.. ` norm={string.format("%.3f", entry.p95_norm)}`
			.. (if entry.ratio ~= nil then ` vs-base={string.format("%.2f", entry.ratio)}x` else "")
			.. ` heapNet={entry.heapNetKb}KB(swing {entry.heapSwingKb}KB){entry.regression and "  REGRESSION" or ""}`
	)
end

-- A heap net smaller than the collector's own excursion is not a measurement of
-- the scene. Said here, in the output, because the output is where it was misread.
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

-- the yardstick is reported so a reader can see the machine, but it is never a
-- regression subject: normalized against itself it is 1.000 by construction
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

-- A divisor that moved a lot DURING the run cannot cancel what it did not hold
-- still for. Normalizing shrinks the excursion (measured: a scene that ran 4.2x
-- raw under a 20-spinner load reported 1.55x normalized) but does not remove it,
-- so a high-drift run still produces untrustworthy ratios in BOTH directions.
--
-- This warns and does NOT suppress the failure. Suppressing would hand anyone a
-- way to launder a real regression by running the bench on a busy machine, which
-- is the exact defect class this repo keeps finding.
local DRIFT_WARN_PCT = 15
if yardstickDriftPct > DRIFT_WARN_PCT then
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
	status = if failed then "FAIL" else "PASS",
	environment = "lune-headless (trend screening only; device authoritative per design §14.3)",
	warmup = WARMUP,
	samples = SAMPLES,
	regressionFactorP95 = REGRESSION_FACTOR,
	normalizedBy = YARDSTICK,
	yardstickP95Ms = yardstickP95,
	yardstickDriftPct = yardstickDriftPct,
	comparisonMode = if baselineHasNorm then "normalized" else "raw-legacy",
	results = results,
})
print(`bench: {failed and "FAIL" or "PASS"} (artifacts/bench.json)`)
process.exit(if failed then 1 else 0)
