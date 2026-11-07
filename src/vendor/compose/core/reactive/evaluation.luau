--!strict
--!native
local Weak = require "../weak"

local Types = require "./types"

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
	edge: (producer: unknown, producerKind: string, consumer: Types.Node) -> (),
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

local stats = {
	state = state,
	setEnabled = setEnabled,
	read = read,
	reset = reset,
	bump = bump,
}

type Node = Types.Node

export type Evaluation = { consumer: Node?, order: number }

local evaluations: { [thread]: Evaluation } = {}
Weak.keys(evaluations)
export type Cache = { thread: thread?, frame: Evaluation?, consumer: Node?, active: number, order: number }

local cache: Cache = { thread = nil, frame = nil, consumer = nil, active = 0, order = 0 }

local function contextOn(running: thread): (Node?, number, thread?)
	if cache.active == 0 then
		return nil, 0, nil
	end
	if running == cache.thread then
		local cached = cache.frame
		if cached ~= nil and cached.order > 0 then
			return cached.consumer, cached.order, running
		end
	end
	local own = evaluations[running]
	if own ~= nil and own.order > 0 then
		return own.consumer, own.order, running
	end
	local inherited: Evaluation? = nil
	local resumer: thread? = nil
	for thread, evaluation in evaluations do
		if
			evaluation.order > 0
			and coroutine.status(thread) == "normal"
			and (inherited == nil or evaluation.order > inherited.order)
		then
			inherited = evaluation
			resumer = thread
		end
	end
	if inherited ~= nil then
		return inherited.consumer, inherited.order, resumer
	end
	return nil, 0, nil
end

local function context(): Node?
	local consumer = contextOn(coroutine.running())
	return consumer
end

local function frame(): Evaluation
	local running = coroutine.running()
	local cached = cache.frame
	if running == cache.thread and cached ~= nil then
		return cached
	end
	local found = evaluations[running]
	local current: Evaluation
	if found ~= nil then
		current = found
	else
		local previous = cache.thread
		if cached ~= nil and cached.order == 0 and previous ~= nil then
			evaluations[previous] = nil
			current = cached
		else
			local made: Evaluation = { consumer = nil, order = 0 }
			current = made
		end
		evaluations[running] = current
	end
	cache.thread = running
	cache.frame = current
	cache.consumer = if current.order > 0 then current.consumer else nil
	return current
end

local function enterFrame(consumer: Node?): (Evaluation, Node?, number)
	local running = coroutine.running()
	local cached = if running == cache.thread then cache.frame else nil
	local current: Evaluation = if cached ~= nil then cached else frame()
	local previousConsumer, previousOrder = current.consumer, current.order
	if previousOrder == 0 then
		cache.active += 1
	end
	local order = cache.order + 1
	cache.order = order
	current.consumer = consumer
	current.order = order
	cache.consumer = consumer
	return current, previousConsumer, previousOrder
end

local function leaveFrame(current: Evaluation, previousConsumer: Node?, previousOrder: number)
	current.consumer = previousConsumer
	current.order = previousOrder
	if cache.frame == current then
		cache.consumer = if previousOrder > 0 then previousConsumer else nil
	end
	if previousOrder == 0 then
		cache.active -= 1
	end
end

local function snapshot(): (Node?, number)
	local cached = cache.frame
	local current: Evaluation = if cached ~= nil and coroutine.running() == cache.thread then cached else frame()
	return current.consumer, current.order
end

local function leave(previousConsumer: Node?, previousOrder: number)
	local running = coroutine.running()
	local cached = if running == cache.thread then cache.frame else nil
	local current: Evaluation = if cached ~= nil then cached else frame()
	if previousOrder == 0 and current.order > 0 then
		cache.active -= 1
	end
	current.consumer = previousConsumer
	current.order = previousOrder
	cache.consumer = if previousOrder > 0 then previousConsumer else nil
end

local validation = { validating = false }

local yieldCheck: typeof(require "./yield-check")? = nil

local function call<A..., R...>(fn: (A...) -> R..., ...: A...): R...
	if not validation.validating then
		return fn(...)
	end
	local loaded = yieldCheck or require "./yield-check"
	yieldCheck = loaded
	return loaded(fn, ...)
end

local function setValidating(value: boolean)
	local resume = stats.state.resume
	if value and resume ~= nil then
		resume()
	end
	validation.validating = value
end

return {
	stats = stats,
	call = call,
	validation = validation,
	setValidating = setValidating,
	cache = cache,
	frame = frame,
	context = context,
	contextOn = contextOn,
	enterFrame = enterFrame,
	leaveFrame = leaveFrame,
	snapshot = snapshot,
	leave = leave,
}
