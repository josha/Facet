--!strict

local Json = require("./json")
local Lute = require("../../vendor/verify/src/lute")

export type Reading = { mounted: number, teardown: number }
export type Comparison = {
	metric: string,
	first: number,
	second: number,
	deltaKb: number,
	ratio: number?,
	regressed: boolean,
}

local Retained = { RATIO = 1.05, MINIMUM_KB = 64, CYCLES = 8 }

local function finite(value: number?): boolean
	return value ~= nil and value >= 0 and value < math.huge
end

function Retained.read(value: unknown): (Reading?, string?)
	if
		Json.stringField(value, "method") ~= Lute.memory.METHOD
		or Json.numberField(value, "cycles") ~= Retained.CYCLES
	then
		return nil, "retained memory needs the declared collection method and eight completed witness cycles"
	end
	for _, name in { "baselineAllocations", "mountedAllocations", "teardownAllocations" } do
		local count = Json.numberField(value, name)
		if count == nil or count < 1 or count > 1000000 or count % 1 ~= 0 then
			return nil, "retained memory needs bounded collection progress for " .. name
		end
	end
	local baseline, mounted, teardown =
		Json.numberField(value, "baselineKb"),
		Json.numberField(value, "mountedKb"),
		Json.numberField(value, "teardownKb")
	local mountedRetained, teardownRetained =
		Json.numberField(value, "mountedRetainedKb"), Json.numberField(value, "teardownRetainedKb")
	if
		not finite(baseline)
		or not finite(mounted)
		or not finite(teardown)
		or not finite(mountedRetained)
		or not finite(teardownRetained)
	then
		return nil, "retained memory readings must be finite and nonnegative"
	end
	local before, during, after = assert(baseline), assert(mounted), assert(teardown)
	local live, released = assert(mountedRetained), assert(teardownRetained)
	if live ~= math.max(0, during - before) or released ~= math.max(0, after - before) then
		return nil, "retained memory deltas do not match their raw heap readings"
	end
	return { mounted = live, teardown = released }, nil
end

local function median(values: { number }): number
	local ordered = table.clone(values)
	table.sort(ordered)
	local middle = math.floor(#ordered / 2)
	return if #ordered % 2 == 0 then (ordered[middle] + ordered[middle + 1]) / 2 else ordered[middle + 1]
end

local function exceeds(first: number, second: number): boolean
	return second > first * Retained.RATIO and second - first > Retained.MINIMUM_KB
end

function Retained.compare(first: { Reading }, second: { Reading }): { Comparison }
	assert(#first > 0 and #first == #second, "retained memory needs matching nonempty paired rounds")
	local result: { Comparison } = {}
	for _, metric in { "mounted", "teardown" } do
		local left, right = {}, {}
		local consistent = true
		for round, reading in first do
			local a = if metric == "mounted" then reading.mounted else reading.teardown
			local b = if metric == "mounted" then second[round].mounted else second[round].teardown
			table.insert(left, a)
			table.insert(right, b)
			consistent = consistent and exceeds(a, b)
		end
		local a, b = median(left), median(right)
		table.insert(result, {
			metric = metric,
			first = a,
			second = b,
			deltaKb = b - a,
			ratio = if a > 0 then b / a else nil,
			regressed = consistent and exceeds(a, b),
		})
	end
	return result
end

return table.freeze(Retained)
