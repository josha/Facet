--!strict

local Harness = require "./core/harness"
local Performance = require "./core/performance"

export type Unit = "seconds" | "milliseconds" | "microseconds"
export type Clock = () -> number
export type Metric = "p50" | "p95" | "p99" | "mean"
export type HeapReading = { before: number, after: number, growth: number, unit: string }

export type Budget = {
	p50: number?,
	p95: number?,
	p99: number?,
	maximum: number?,
}

export type Yardstick = {
	run: () -> (),
	samples: number,
	maxSpread: number,
	maxDrift: number,
}

export type Baseline = {
	identity: string,
	environment: string,
	unit: Unit,
	metric: Metric,
	value: number?,
	samples: { number }?,
	tolerance: number,
	yardstick: number?,
}

export type Heap = {
	probe: () -> number?,
	unit: string,
	maximumGrowth: number?,
}

export type Judgment = {
	samples: { number },
	summary: Performance.Summary,
	unit: Unit,
	yardstickBefore: { number },
	yardstickAfter: { number },
	yardstickBeforeSummary: Performance.Summary,
	yardstickAfterSummary: Performance.Summary,
	heap: HeapReading?,
}

export type Spec = {
	name: string,
	unit: Unit,
	workload: () -> (),
	warmup: number,
	samples: number,
	iterations: number?,
	budget: Budget?,
	environment: { observed: string, accepted: { string }? },
	maxSpread: number?,
	yardstick: Yardstick?,
	baseline: Baseline?,
	acceptedBaselines: { string }?,
	deadlineSeconds: number?,
	clock: Clock?,
	signal: string?,
	tags: { string }?,
	setup: (() -> ())?,
	teardown: (() -> ())?,
	beforeSample: (() -> ())?,
	afterSample: (() -> ())?,
	heap: Heap?,
	judge: ((view: Judgment) -> string?)?,
}

export type Collection = {
	name: string,
	yardstick: Yardstick,
	benchmarks: { Spec },
	clock: Clock?,
}

export type InvalidReason =
	"environment_mismatch"
	| "baseline_mismatch"
	| "unstable"
	| "yardstick_unstable"
	| "yardstick_drift"
	| "heap_unsupported"
	| "deadline_exceeded"

export type Invalid = { reason: InvalidReason, detail: string }

export type Comparison = {
	metric: Metric,
	observed: number,
	baseline: number,
	limit: number,
	regressed: boolean,
	normalized: boolean,
}

export type Result = {
	name: string,
	unit: Unit,
	samples: { number },
	warmupRuns: number,
	iterations: number,
	yardstickBefore: { number },
	yardstickAfter: { number },
	summary: Performance.Summary,
	spread: number?,
	invalid: { Invalid },
	comparison: Comparison?,
	heap: HeapReading?,
	judgment: string?,
	failure: string?,
	elapsedSeconds: number,
}

export type CollectionResult = {
	name: string,
	results: { Result },
	yardstickBefore: { number },
	yardstickAfter: { number },
	invalid: { Invalid },
	failure: string?,
}

local SCALE: { [Unit]: number } = { seconds = 1, milliseconds = 1e3, microseconds = 1e6 }

local function positiveWhole(value: number, label: string)
	assert(
		type(value) == "number" and value >= 1 and value % 1 == 0 and value < math.huge,
		label .. " must be a positive whole number"
	)
end

local function positiveFinite(value: number, label: string)
	assert(type(value) == "number" and value > 0 and value < math.huge, label .. " must be positive and finite")
end

local function nonnegativeFinite(value: number, label: string)
	assert(type(value) == "number" and value >= 0 and value < math.huge, label .. " must be finite and nonnegative")
end

local function check(spec: Spec, owned: boolean?)
	assert(type(spec.name) == "string" and string.find(spec.name, "%S") ~= nil, "benchmark needs a name")
	assert(SCALE[spec.unit] ~= nil, "benchmark unit must be seconds, milliseconds or microseconds")
	assert(type(spec.workload) == "function", "benchmark needs a workload function")
	assert(type(spec.warmup) == "number" and spec.warmup >= 0 and spec.warmup % 1 == 0, "warmup must be a whole count")
	positiveWhole(spec.samples, "samples")
	if spec.iterations ~= nil then
		positiveWhole(spec.iterations, "iterations")
	end
	local budget: Budget = if spec.budget ~= nil then spec.budget else {}
	local limits: { { name: string, value: number? } } = {
		{ name = "p50", value = budget.p50 },
		{ name = "p95", value = budget.p95 },
		{ name = "p99", value = budget.p99 },
		{ name = "maximum", value = budget.maximum },
	}
	for _, limit in limits do
		if limit.value ~= nil then
			nonnegativeFinite(limit.value, "budget." .. limit.name)
		end
	end
	assert(
		type(spec.environment) == "table"
			and type(spec.environment.observed) == "string"
			and string.find(spec.environment.observed, "%S") ~= nil,
		"benchmark must name the observed environment identity"
	)
	if spec.maxSpread ~= nil then
		nonnegativeFinite(spec.maxSpread, "maxSpread")
	end
	if spec.deadlineSeconds ~= nil then
		positiveFinite(spec.deadlineSeconds, "deadlineSeconds")
	end
	local yardstick = spec.yardstick
	if yardstick ~= nil then
		assert(type(yardstick.run) == "function", "yardstick needs a run function")
		positiveWhole(yardstick.samples, "yardstick.samples")
		nonnegativeFinite(yardstick.maxSpread, "yardstick.maxSpread")
		nonnegativeFinite(yardstick.maxDrift, "yardstick.maxDrift")
	end
	local hooks: { [string]: unknown } = {
		setup = spec.setup,
		teardown = spec.teardown,
		beforeSample = spec.beforeSample,
		afterSample = spec.afterSample,
		judge = spec.judge,
	}
	for name, value in hooks do
		assert(type(value) == "function", name .. " must be a function")
	end
	if spec.heap ~= nil then
		assert(type(spec.heap.probe) == "function", "heap needs a probe function")
		assert(type(spec.heap.unit) == "string" and spec.heap.unit ~= "", "heap needs a unit")
		if spec.heap.maximumGrowth ~= nil then
			nonnegativeFinite(spec.heap.maximumGrowth, "heap.maximumGrowth")
		end
	end
	local baseline = spec.baseline
	if baseline ~= nil then
		assert(SCALE[baseline.unit] ~= nil, "baseline unit must be seconds, milliseconds or microseconds")
		assert(
			(baseline.value == nil) ~= (baseline.samples == nil),
			"a baseline holds either a value or recorded samples"
		)
		if baseline.value ~= nil then
			nonnegativeFinite(baseline.value, "baseline.value")
		end
		if baseline.samples ~= nil then
			assert(#baseline.samples > 0, "baseline samples must not be empty")
			for _, sample in baseline.samples do
				nonnegativeFinite(sample, "baseline sample")
			end
		end
		nonnegativeFinite(baseline.tolerance, "baseline.tolerance")
		if baseline.yardstick ~= nil then
			positiveFinite(baseline.yardstick, "baseline.yardstick")
			assert(
				spec.yardstick ~= nil or owned == true,
				"a yardstick-normalized baseline needs the benchmark to declare a yardstick"
			)
		end
		assert(
			baseline.identity ~= "" and baseline.environment ~= "",
			"baseline must name its identity and environment"
		)
	end
end

local function contains(values: { string }?, value: string): boolean
	return values ~= nil and table.find(values, value) ~= nil
end

local function relativeSpread(samples: { number }): number?
	if #samples == 0 then
		return nil
	end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local median = sorted[math.max(1, math.ceil(#sorted * 0.5))]
	local high = sorted[math.max(1, math.ceil(#sorted * 0.95))]
	if median == 0 then
		return if high == 0 then 0 else math.huge
	end
	return (high - median) / median
end

local function median(samples: { number }): number
	local sorted = table.clone(samples)
	table.sort(sorted)
	return sorted[math.max(1, math.ceil(#sorted * 0.5))]
end

local function metricValue(summary: Performance.Summary, metric: Metric): number?
	if metric == "mean" then
		return summary.mean
	elseif metric == "p50" then
		return summary.p50
	elseif metric == "p95" then
		return summary.p95
	end
	return summary.p99
end

local function summaryOf(spec: Spec, samples: { number }): Performance.Summary
	return Performance.summarize {
		samples = samples,
		unit = spec.unit,
		context = {
			environment = spec.environment.observed,
			signal = spec.signal or spec.name,
			timing = "observed",
		},
	}
end

local function baselineValue(spec: Spec, baseline: Baseline): number?
	if baseline.value ~= nil then
		return baseline.value
	end
	return metricValue(summaryOf(spec, baseline.samples :: { number }), baseline.metric)
end

local function yardstickIssues(tool: Yardstick, before: { number }, after: { number }): { Invalid }
	local issues: { Invalid } = {}
	if #before == 0 or #after == 0 then
		return issues
	end
	local combined = table.clone(before)
	for _, value in after do
		table.insert(combined, value)
	end
	local spread = relativeSpread(combined)
	if spread ~= nil and spread > tool.maxSpread then
		table.insert(issues, {
			reason = "yardstick_unstable",
			detail = ("yardstick spread was %.3f, above the allowed %.3f"):format(spread, tool.maxSpread),
		})
	end
	local first = median(before)
	local last = median(after)
	local drift = if first == 0 then (if last == 0 then 0 else math.huge) else math.abs(last - first) / first
	if drift > tool.maxDrift then
		table.insert(issues, {
			reason = "yardstick_drift",
			detail = ("yardstick median moved %.3f between the start and end, above the allowed %.3f"):format(
				drift,
				tool.maxDrift
			),
		})
	end
	return issues
end

local function timeYardstick(clock: Clock, scale: number, tool: Yardstick, into: { number }): string?
	for _ = 1, tool.samples do
		local before = clock()
		local ok, thrown: unknown = pcall(tool.run)
		if not ok then
			return "workload raised: " .. tostring(thrown)
		end
		local elapsed = clock() - before
		if elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge then
			return "the clock produced an invalid yardstick duration"
		end
		table.insert(into, elapsed * scale)
	end
	return nil
end

local function readHeap(heap: Heap): number?
	local ok, value: unknown = pcall(heap.probe)
	if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then
		return value
	end
	return nil
end

local function comparisonOf(
	spec: Spec,
	summary: Performance.Summary,
	samples: { number },
	before: { number },
	after: { number }
): Comparison?
	local baseline = spec.baseline
	local recorded = if baseline ~= nil then baselineValue(spec, baseline) else nil
	if baseline == nil or recorded == nil or #samples == 0 or baseline.unit ~= spec.unit then
		return nil
	end
	local value = metricValue(summary, baseline.metric)
	if value == nil then
		return nil
	end
	if baseline.yardstick ~= nil then
		if #before == 0 or #after == 0 then
			return nil
		end
		local combined = table.clone(before)
		for _, entry in after do
			table.insert(combined, entry)
		end
		local current = median(combined)
		if current <= 0 then
			return nil
		end
		local reference = recorded / baseline.yardstick
		local observed = value / current
		local limit = reference * (1 + baseline.tolerance)
		return {
			metric = baseline.metric,
			observed = observed,
			baseline = reference,
			limit = limit,
			regressed = observed > limit,
			normalized = true,
		}
	end
	if baseline.environment ~= spec.environment.observed then
		return nil
	end
	local limit = recorded * (1 + baseline.tolerance)
	return {
		metric = baseline.metric,
		observed = value,
		baseline = recorded,
		limit = limit,
		regressed = value > limit,
		normalized = false,
	}
end

local function baselineProblems(spec: Spec, baseline: Baseline): { string }
	local problems: { string } = {}
	if spec.acceptedBaselines ~= nil and not contains(spec.acceptedBaselines, baseline.identity) then
		table.insert(problems, ("baseline identity %q is not accepted"):format(baseline.identity))
	end
	if baseline.yardstick == nil and baseline.environment ~= spec.environment.observed then
		table.insert(
			problems,
			("baseline was recorded in %q, not the observed %q"):format(baseline.environment, spec.environment.observed)
		)
	end
	if baseline.unit ~= spec.unit then
		table.insert(problems, ("baseline unit %s differs from %s"):format(baseline.unit, spec.unit))
	end
	return problems
end

local function judgeResult(spec: Spec, result: Result)
	local judge = spec.judge
	if judge == nil or result.failure ~= nil or #result.invalid > 0 or #result.samples ~= spec.samples then
		return
	end
	local ok, verdict: unknown = pcall(judge, {
		samples = table.clone(result.samples),
		summary = result.summary,
		unit = spec.unit,
		yardstickBefore = table.clone(result.yardstickBefore),
		yardstickAfter = table.clone(result.yardstickAfter),
		yardstickBeforeSummary = summaryOf(spec, result.yardstickBefore),
		yardstickAfterSummary = summaryOf(spec, result.yardstickAfter),
		heap = result.heap,
	})
	if not ok then
		result.failure = "judge raised: " .. tostring(verdict)
	elseif verdict ~= nil then
		result.judgment = tostring(verdict)
	end
end

local function measure(spec: Spec, clock: Clock, started: number): Result
	local scale = SCALE[spec.unit]
	local iterations = spec.iterations or 1
	local samples: { number } = {}
	local yardstickBefore: { number } = {}
	local yardstickAfter: { number } = {}
	local invalid: { Invalid } = {}
	local failure: string? = nil
	local warmupRuns = 0
	local heapBefore: number? = nil

	local function finish(): Result
		local summary = summaryOf(spec, samples)
		local result: Result = {
			name = spec.name,
			unit = spec.unit,
			samples = samples,
			warmupRuns = warmupRuns,
			iterations = iterations,
			yardstickBefore = yardstickBefore,
			yardstickAfter = yardstickAfter,
			summary = summary,
			spread = relativeSpread(samples),
			invalid = invalid,
			comparison = nil,
			heap = nil,
			judgment = nil,
			failure = failure,
			elapsedSeconds = math.max(0, clock() - started),
		}
		result.comparison = comparisonOf(spec, summary, samples, yardstickBefore, yardstickAfter)
		if spec.maxSpread ~= nil and #samples > 0 then
			local spread = result.spread
			if spread ~= nil and spread > spec.maxSpread then
				table.insert(invalid, {
					reason = "unstable",
					detail = ("relative spread (p95-p50)/p50 was %.3f, above the allowed %.3f"):format(
						spread,
						spec.maxSpread
					),
				})
			end
		end
		local tool = spec.yardstick
		if tool ~= nil then
			for _, issue in yardstickIssues(tool, yardstickBefore, yardstickAfter) do
				table.insert(invalid, issue)
			end
		end
		return result
	end

	local accepted = spec.environment.accepted
	if accepted ~= nil and not contains(accepted, spec.environment.observed) then
		table.insert(invalid, {
			reason = "environment_mismatch",
			detail = ("observed environment %q is not among the accepted %s"):format(
				spec.environment.observed,
				table.concat(accepted, ", ")
			),
		})
	end
	local baseline = spec.baseline
	if baseline ~= nil then
		local problems = baselineProblems(spec, baseline)
		if #problems > 0 then
			table.insert(invalid, { reason = "baseline_mismatch", detail = table.concat(problems, "; ") })
		end
	end
	if #invalid > 0 then
		return finish()
	end

	local function attempt(work: () -> ()): boolean
		local ok, thrown: unknown = pcall(work)
		if not ok then
			failure = "workload raised: " .. tostring(thrown)
			return false
		end
		return true
	end

	local function expired(): boolean
		return spec.deadlineSeconds ~= nil and clock() - started >= spec.deadlineSeconds
	end

	local heap = spec.heap
	local function heapReading(): HeapReading?
		if heap == nil or heapBefore == nil then
			return nil
		end
		local after = readHeap(heap)
		if after == nil then
			return nil
		end
		return { before = heapBefore, after = after, growth = after - heapBefore, unit = heap.unit }
	end
	local function finishWithHeap(): Result
		local result = finish()
		if heap ~= nil and failure == nil and #samples == spec.samples then
			result.heap = heapReading()
			if result.heap == nil then
				table.insert(result.invalid, {
					reason = "heap_unsupported",
					detail = "the heap probe did not return a finite non-negative reading",
				})
			end
		end
		return result
	end

	for _ = 1, spec.warmup do
		if not attempt(spec.workload) then
			return finish()
		end
		warmupRuns += 1
	end
	if heap ~= nil then
		heapBefore = readHeap(heap)
		if heapBefore == nil then
			table.insert(invalid, {
				reason = "heap_unsupported",
				detail = "the heap probe did not return a finite non-negative reading",
			})
			return finish()
		end
	end
	local tool = spec.yardstick
	if tool ~= nil then
		failure = timeYardstick(clock, scale, tool, yardstickBefore)
		if failure ~= nil then
			return finish()
		end
	end
	for _ = 1, spec.samples do
		if expired() then
			table.insert(invalid, {
				reason = "deadline_exceeded",
				detail = ("the %s second deadline elapsed after %d of %d samples"):format(
					tostring(spec.deadlineSeconds),
					#samples,
					spec.samples
				),
			})
			return finish()
		end
		if spec.beforeSample ~= nil and not attempt(spec.beforeSample) then
			return finish()
		end
		local before = clock()
		for _ = 1, iterations do
			if not attempt(spec.workload) then
				return finish()
			end
		end
		local elapsed = clock() - before
		if elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge then
			failure = "the clock produced an invalid sample duration"
			return finish()
		end
		table.insert(samples, elapsed / iterations * scale)
		if spec.afterSample ~= nil and not attempt(spec.afterSample) then
			return finish()
		end
	end
	if tool ~= nil then
		failure = timeYardstick(clock, scale, tool, yardstickAfter)
		if failure ~= nil then
			return finish()
		end
	end
	return finishWithHeap()
end

local function run(spec: Spec): Result
	check(spec)
	local clock: Clock = spec.clock or os.clock
	local started = clock()
	local setupFailure: string? = nil
	if spec.setup ~= nil then
		local ok, thrown: unknown = pcall(spec.setup)
		if not ok then
			setupFailure = "setup raised: " .. tostring(thrown)
		end
	end
	local result: Result
	if setupFailure ~= nil then
		result = {
			name = spec.name,
			unit = spec.unit,
			samples = {},
			warmupRuns = 0,
			iterations = spec.iterations or 1,
			yardstickBefore = {},
			yardstickAfter = {},
			summary = summaryOf(spec, {}),
			spread = nil,
			invalid = {},
			comparison = nil,
			heap = nil,
			judgment = nil,
			failure = setupFailure,
			elapsedSeconds = 0,
		}
	else
		result = measure(spec, clock, started)
	end
	if spec.teardown ~= nil then
		local ok, thrown: unknown = pcall(spec.teardown)
		if not ok and result.failure == nil then
			result.failure = "teardown raised: " .. tostring(thrown)
		end
	end
	judgeResult(spec, result)
	result.elapsedSeconds = math.max(0, clock() - started)
	return result
end

local function collect(collection: Collection): CollectionResult
	assert(type(collection.name) == "string" and string.find(collection.name, "%S") ~= nil, "collection needs a name")
	assert(#collection.benchmarks > 0, "collection needs at least one benchmark")
	local tool = collection.yardstick
	assert(type(tool.run) == "function", "yardstick needs a run function")
	positiveWhole(tool.samples, "yardstick.samples")
	nonnegativeFinite(tool.maxSpread, "yardstick.maxSpread")
	nonnegativeFinite(tool.maxDrift, "yardstick.maxDrift")
	local clock: Clock = collection.clock or os.clock
	local unit: Unit = collection.benchmarks[1].unit
	local scale = SCALE[unit]
	local before: { number } = {}
	local after: { number } = {}
	local results: { Result } = {}
	local invalid: { Invalid } = {}
	local failure = timeYardstick(clock, scale, tool, before)
	if failure == nil then
		for _, member in collection.benchmarks do
			check(member, true)
			assert(member.yardstick == nil, "a collection owns the yardstick; a member declares none")
			assert(member.unit == unit, "every member of a collection shares one unit")
			local copy = table.clone(member)
			copy.clock = member.clock or clock
			copy.baseline = nil
			copy.judge = nil
			table.insert(results, run(copy))
		end
		failure = timeYardstick(clock, scale, tool, after)
		if failure == nil then
			invalid = yardstickIssues(tool, before, after)
			for index, result in results do
				local member = collection.benchmarks[index]
				result.yardstickBefore = table.clone(before)
				result.yardstickAfter = table.clone(after)
				local baseline = member.baseline
				if baseline ~= nil then
					local problems = baselineProblems(member, baseline)
					if #problems > 0 then
						table.insert(
							result.invalid,
							{ reason = "baseline_mismatch", detail = table.concat(problems, "; ") }
						)
					end
					result.comparison = comparisonOf(member, result.summary, result.samples, before, after)
				end
				if #invalid == 0 then
					judgeResult(member, result)
				end
			end
		end
	end
	return {
		name = collection.name,
		results = results,
		yardstickBefore = before,
		yardstickAfter = after,
		invalid = invalid,
		failure = failure,
	}
end

local function limitsOf(spec: Spec): Performance.Limits
	local budget: Budget = if spec.budget ~= nil then spec.budget else {}
	return {
		unit = spec.unit,
		minimumSamples = spec.samples,
		p50 = budget.p50,
		p95 = budget.p95,
		p99 = budget.p99,
		maximum = budget.maximum,
		measureOnly = budget.p50 == nil and budget.p95 == nil and budget.p99 == nil and budget.maximum == nil,
	}
end

local function inputOf(spec: Spec, result: Result): Performance.Input
	return {
		samples = result.samples,
		unit = spec.unit,
		context = result.summary.context,
	}
end

local function report(context: Harness.Context, spec: Spec, result: Result)
	if #result.samples > 0 then
		local measured, thrown: unknown =
			pcall(context.measure, context, "benchmark", spec.name, inputOf(spec, result), limitsOf(spec))
		if not measured and type(thrown) ~= "table" then
			error(thrown, 0)
		end
	end
	local heap = result.heap
	if heap ~= nil then
		context:step(
			("heap %s: %.4g -> %.4g %s (growth %.4g)"):format(
				spec.name,
				heap.before,
				heap.after,
				heap.unit,
				heap.growth
			),
			function() end
		)
		local limit = if spec.heap ~= nil then spec.heap.maximumGrowth else nil
		if limit ~= nil and heap.growth > limit then
			error(("%s heap grew %.4g %s, above the allowed %.4g"):format(spec.name, heap.growth, heap.unit, limit), 0)
		end
	end
	local comparison = result.comparison
	if comparison ~= nil and comparison.regressed then
		error(
			("%s %s %.4g exceeds the %sbaseline %.4g plus tolerance (limit %.4g)"):format(
				spec.name,
				comparison.metric,
				comparison.observed,
				if comparison.normalized then "yardstick-normalized " else "",
				comparison.baseline,
				comparison.limit
			),
			0
		)
	end
	if result.judgment ~= nil then
		error(("%s was refused by its judge: %s"):format(spec.name, result.judgment), 0)
	end
	if result.failure ~= nil then
		error(result.failure :: string, 0)
	end
	for _, entry in result.invalid do
		pcall(context.step, context, ("benchmark invalid: %s (%s)"):format(entry.reason, entry.detail), function()
			context:unsupported("measurement:" .. entry.reason)
		end)
	end
end

local function case(spec: Spec): Harness.CaseOptions
	check(spec)
	return {
		timeoutSeconds = if spec.deadlineSeconds ~= nil then spec.deadlineSeconds + 5 else nil,
		tags = spec.tags,
		limitations = if limitsOf(spec).measureOnly == true then { "measured only: no budget declared" } else nil,
		run = function(context: Harness.Context)
			report(context, spec, run(spec))
		end,
	}
end

local function collectionCase(collection: Collection): Harness.CaseOptions
	for _, member in collection.benchmarks do
		check(member, true)
	end
	return {
		run = function(context: Harness.Context)
			local collected = collect(collection)
			local firstFailure: unknown = nil
			for index, result in collected.results do
				local reported, thrown: unknown = pcall(report, context, collection.benchmarks[index], result)
				if not reported and firstFailure == nil and type(thrown) ~= "table" then
					firstFailure = thrown
				end
			end
			if collected.failure ~= nil then
				error(collected.failure :: string, 0)
			end
			if firstFailure ~= nil then
				error(firstFailure, 0)
			end
			for _, entry in collected.invalid do
				pcall(
					context.step,
					context,
					("collection invalid: %s (%s)"):format(entry.reason, entry.detail),
					function()
						context:unsupported("measurement:" .. entry.reason)
					end
				)
			end
		end,
	}
end

local luauHeap: Heap = {
	unit = "kilobytes",
	probe = function(): number?
		local compiled = if loadstring ~= nil then loadstring "return collectgarbage('count')" else nil
		if compiled == nil then
			return nil
		end
		local ok, value: unknown = pcall(compiled)
		return if ok and type(value) == "number" then value else nil
	end,
}

return {
	check = check,
	run = run,
	case = case,
	collect = collect,
	collection = collectionCase,
	luauHeap = luauHeap,
	limits = limitsOf,
}
