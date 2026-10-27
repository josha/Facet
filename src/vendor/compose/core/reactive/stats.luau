--!strict
--!native

export type Counters = {
	cellWrites: number,
	cellWritesSuppressed: number,
	notifications: number,
	formulaRecomputations: number,
	formulaRecomputationsSuppressed: number,
	watchRuns: number,
	watchSchedules: number,
	watchSchedulesCoalesced: number,
	drains: number,
	continuationPasses: number,
}

type Record = Counters & { [string]: number }

local function zeroed(): Record
	return {
		cellWrites = 0,
		cellWritesSuppressed = 0,
		notifications = 0,
		formulaRecomputations = 0,
		formulaRecomputationsSuppressed = 0,
		watchRuns = 0,
		watchSchedules = 0,
		watchSchedulesCoalesced = 0,
		drains = 0,
		continuationPasses = 0,
	}
end

local counters: Record = zeroed()
local state: { enabled: boolean, resume: (() -> ())? } = { enabled = false, resume = nil }

local function setEnabled(value: boolean)
	local resume = state.resume
	if value and resume ~= nil then
		resume()
	end
	state.enabled = value
end

local function read(): Counters
	return table.clone(counters)
end

local function reset()
	counters = zeroed()
end

local function bump(name: string, amount: number?)
	local record = counters
	record[name] += if amount ~= nil then amount else 1
end

return {

	state = state,
	setEnabled = setEnabled,
	read = read,
	reset = reset,
	bump = bump,
	zeroed = zeroed,
}
