--!strict

local Harness = require "./core/harness"
local Performance = require "./core/performance"

export type Unit = "seconds" | "milliseconds" | "microseconds"
export type Clock = () -> number
export type Metric = "p50" | "p95" | "p99" | "mean"

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
	value: number,
	tolerance: number,
}

export type Spec = {
	name: string,
	unit: Unit,
	workload: () -> (),
	warmup: number,
	samples: number,
	iterations: number?,
	budget: Budget,
	environment: { observed: string, accepted: { string }? },
	maxSpread: number?,
	yardstick: Yardstick?,
	baseline: Baseline?,
	acceptedBaselines: { string }?,
	deadlineSeconds: number?,
	clock: Clock?,
	signal: string?,
	tags: { string }?,
}

export type InvalidReason =
	"environment_mismatch"
	| "baseline_mismatch"
	| "unstable"
	| "yardstick_unstable"
	| "yardstick_drift"
	| "deadline_exceeded"

export type Invalid = { reason: InvalidReason, detail: string }

export type Comparison = {
	metric: Metric,
	observed: number,
	baseline: number,
	limit: number,
	regressed: boolean,
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
	failure: string?,
	elapsedSeconds: number,
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

local function check(spec: Spec)
	assert(type(spec.name) == "string" and string.find(spec.name, "%S") ~= nil, "benchmark needs a name")
	assert(SCALE[spec.unit] ~= nil, "benchmark unit must be seconds, milliseconds or microseconds")
	assert(type(spec.workload) == "function", "benchmark needs a workload function")
	assert(type(spec.warmup) == "number" and spec.warmup >= 0 and spec.warmup % 1 == 0, "warmup must be a whole count")
	positiveWhole(spec.samples, "samples")
	if spec.iterations ~= nil then
		positiveWhole(spec.iterations, "iterations")
	end
	local declared = 0
	local budget = spec.budget
	local limits: { { name: string, value: number? } } = {
		{ name = "p50", value = budget.p50 },
		{ name = "p95", value = budget.p95 },
		{ name = "p99", value = budget.p99 },
		{ name = "maximum", value = budget.maximum },
	}
	for _, limit in limits do
		if limit.value ~= nil then
			nonnegativeFinite(limit.value, "budget." .. limit.name)
			declared += 1
		end
	end
	assert(declared > 0, "benchmark needs at least one budget limit")
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
	local baseline = spec.baseline
	if baseline ~= nil then
		assert(SCALE[baseline.unit] ~= nil, "baseline unit must be seconds, milliseconds or microseconds")
		nonnegativeFinite(baseline.value, "baseline.value")
		nonnegativeFinite(baseline.tolerance, "baseline.tolerance")
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

local function run(spec: Spec): Result
	check(spec)
	local clock: Clock = spec.clock or os.clock
	local scale = SCALE[spec.unit]
	local iterations = spec.iterations or 1
	local started = clock()
	local samples: { number } = {}
	local yardstickBefore: { number } = {}
	local yardstickAfter: { number } = {}
	local invalid: { Invalid } = {}
	local failure: string? = nil
	local warmupRuns = 0

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
			failure = failure,
			elapsedSeconds = math.max(0, clock() - started),
		}
		local baseline = spec.baseline
		if baseline ~= nil and #samples > 0 then
			local recorded = baseline
			local value = metricValue(summary, recorded.metric)
			if value ~= nil and recorded.unit == spec.unit and recorded.environment == spec.environment.observed then
				local limit = recorded.value * (1 + recorded.tolerance)
				result.comparison = {
					metric = recorded.metric,
					observed = value,
					baseline = recorded.value,
					limit = limit,
					regressed = value > limit,
				}
			end
		end
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
		local yardstick = spec.yardstick
		if yardstick ~= nil and #yardstickBefore > 0 and #yardstickAfter > 0 then
			local combined = table.clone(yardstickBefore)
			for _, value in yardstickAfter do
				table.insert(combined, value)
			end
			local yardstickSpread = relativeSpread(combined)
			if yardstickSpread ~= nil and yardstickSpread > yardstick.maxSpread then
				table.insert(invalid, {
					reason = "yardstick_unstable",
					detail = ("yardstick spread was %.3f, above the allowed %.3f"):format(
						yardstickSpread,
						yardstick.maxSpread
					),
				})
			end
			local before = median(yardstickBefore)
			local after = median(yardstickAfter)
			local drift = if before == 0
				then (if after == 0 then 0 else math.huge)
				else math.abs(after - before) / before
			if drift > yardstick.maxDrift then
				table.insert(invalid, {
					reason = "yardstick_drift",
					detail = ("yardstick median moved %.3f between the start and end, above the allowed %.3f"):format(
						drift,
						yardstick.maxDrift
					),
				})
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
		local problems: { string } = {}
		if spec.acceptedBaselines ~= nil and not contains(spec.acceptedBaselines, baseline.identity) then
			table.insert(problems, ("baseline identity %q is not accepted"):format(baseline.identity))
		end
		if baseline.environment ~= spec.environment.observed then
			table.insert(
				problems,
				("baseline was recorded in %q, not the observed %q"):format(
					baseline.environment,
					spec.environment.observed
				)
			)
		end
		if baseline.unit ~= spec.unit then
			table.insert(problems, ("baseline unit %s differs from %s"):format(baseline.unit, spec.unit))
		end
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

	local function timeYardstick(into: { number }, tool: Yardstick): boolean
		for _ = 1, tool.samples do
			local before = clock()
			if not attempt(tool.run) then
				return false
			end
			local elapsed = clock() - before
			if elapsed ~= elapsed or elapsed < 0 or elapsed == math.huge then
				failure = "the clock produced an invalid yardstick duration"
				return false
			end
			table.insert(into, elapsed * scale)
		end
		return true
	end

	for _ = 1, spec.warmup do
		if not attempt(spec.workload) then
			return finish()
		end
		warmupRuns += 1
	end
	local tool = spec.yardstick
	if tool ~= nil and not timeYardstick(yardstickBefore, tool) then
		return finish()
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
	end
	if tool ~= nil and not timeYardstick(yardstickAfter, tool) then
		return finish()
	end
	return finish()
end

local function limitsOf(spec: Spec): Performance.Limits
	return {
		unit = spec.unit,
		minimumSamples = spec.samples,
		p50 = spec.budget.p50,
		p95 = spec.budget.p95,
		p99 = spec.budget.p99,
		maximum = spec.budget.maximum,
	}
end

local function inputOf(spec: Spec, result: Result): Performance.Input
	return {
		samples = result.samples,
		unit = spec.unit,
		context = result.summary.context,
	}
end

local function case(spec: Spec): Harness.CaseOptions
	check(spec)
	return {
		timeoutSeconds = if spec.deadlineSeconds ~= nil then spec.deadlineSeconds + 5 else nil,
		tags = spec.tags,
		run = function(context: Harness.Context)
			local result = run(spec)
			if #result.samples > 0 then
				local measured, thrown: unknown =
					pcall(context.measure, context, "benchmark", spec.name, inputOf(spec, result), limitsOf(spec))
				if not measured and type(thrown) ~= "table" then
					error(thrown, 0)
				end
			end
			local comparison = result.comparison
			if comparison ~= nil and comparison.regressed then
				error(
					("%s %s %.4g exceeds the baseline %.4g plus tolerance (limit %.4g)"):format(
						spec.name,
						comparison.metric,
						comparison.observed,
						comparison.baseline,
						comparison.limit
					),
					0
				)
			end
			if result.failure ~= nil then
				error(result.failure :: string, 0)
			end
			for _, entry in result.invalid do
				pcall(
					context.step,
					context,
					("benchmark invalid: %s (%s)"):format(entry.reason, entry.detail),
					function()
						context:unsupported("measurement:" .. entry.reason)
					end
				)
			end
		end,
	}
end

return {
	check = check,
	run = run,
	case = case,
	limits = limitsOf,
}
