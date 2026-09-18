--!strict

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

local function zeroed(): Counters
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

local counters: Counters = zeroed()
local state = { enabled = false }

local function isEnabled(): boolean
	return state.enabled
end

local function setEnabled(value: boolean)
	state.enabled = value
end

local function read(): Counters
	return table.clone(counters)
end

local function reset()
	counters = zeroed()
end

local function bump(name: string, amount: number?)
	local record = counters :: { [string]: number }
	record[name] += if amount ~= nil then amount else 1
end

return {

	state = state,
	isEnabled = isEnabled,
	setEnabled = setEnabled,
	read = read,
	reset = reset,
	bump = bump,
	zeroed = zeroed,
}
