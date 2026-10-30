--!strict
--!native

local Types = require "./types"
local Weak = require "../weak"

type Node = Types.Node

export type Evaluation = { consumer: Node?, order: number }

local evaluations: { [thread]: Evaluation } = {}
Weak.keys(evaluations)
local active = 0
local order = 0
export type Cache = { thread: thread?, frame: Evaluation? }

local cache: Cache = { thread = nil, frame = nil }

local function context(): Node?
	local running = coroutine.running()
	if running == cache.thread then
		local cached = cache.frame
		if cached ~= nil and cached.order > 0 then
			return cached.consumer
		end
	end
	local own = evaluations[running]
	if own ~= nil and own.order > 0 then
		return own.consumer
	end
	if active == 0 then
		return nil
	end
	local inherited: Evaluation? = nil
	for thread, evaluation in evaluations do
		if
			evaluation.order > 0
			and coroutine.status(thread) == "normal"
			and (inherited == nil or evaluation.order > inherited.order)
		then
			inherited = evaluation
		end
	end
	return if inherited ~= nil then inherited.consumer else nil
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
	return current
end

local function enter(consumer: Node?): (Node?, number, Evaluation)
	local running = coroutine.running()
	local cached = if running == cache.thread then cache.frame else nil
	local current: Evaluation = if cached ~= nil then cached else frame()
	local previousConsumer, previousOrder = current.consumer, current.order
	if previousOrder == 0 then
		active += 1
	end
	order += 1
	current.consumer = consumer
	current.order = order
	return previousConsumer, previousOrder, current
end

local function snapshot(): (Node?, number)
	local cached = cache.frame
	local current: Evaluation = if cached ~= nil and coroutine.running() == cache.thread then cached else frame()
	return current.consumer, current.order
end

local function leave(previousConsumer: Node?, previousOrder: number, entered: Evaluation?)
	local current: Evaluation
	if entered ~= nil then
		current = entered
	else
		local running = coroutine.running()
		local cached = if running == cache.thread then cache.frame else nil
		current = if cached ~= nil then cached else frame()
	end
	current.consumer = previousConsumer
	current.order = previousOrder
	if previousOrder == 0 then
		active -= 1
	end
end

return {
	cache = cache,
	frame = frame,
	context = context,
	enter = enter,
	snapshot = snapshot,
	leave = leave,
}
