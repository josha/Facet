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

export type Recorder = {
	write: (cell: unknown, suppressed: boolean) -> (),
	wake: (producer: unknown, kind: string, count: number) -> (),
	edge: (producer: unknown, producerKind: string, consumer: unknown) -> (),
	recompute: (formula: unknown) -> (),
	suppressedRecompute: (formula: unknown) -> (),
	schedule: (watch: unknown, coalesced: boolean) -> (),
	enterRun: (watch: unknown) -> (),
	hostWrite: () -> (),
	drain: (runs: number, seconds: number) -> (),
	naming: (name: string?) -> (),
	born: (node: unknown, name: string?) -> (),
	nowOrNil: () -> number?,
}

local function ignore(...: unknown) end

local function never(): number?
	return nil
end

local idle: Recorder = {
	write = ignore,
	wake = ignore,
	edge = ignore,
	recompute = ignore,
	suppressedRecompute = ignore,
	schedule = ignore,
	enterRun = ignore,
	hostWrite = ignore,
	drain = ignore,
	naming = ignore,
	born = ignore,
	nowOrNil = never,
}

local counters: Record = zeroed()
local state: { enabled: boolean, resume: (() -> ())?, recorder: Recorder } =
	{ enabled = false, resume = nil, recorder = idle }

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
