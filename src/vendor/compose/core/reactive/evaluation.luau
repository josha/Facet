--!strict
--!native

local Types = require "./types"
local Weak = require "../weak"

type Node = Types.Node

export type Evaluation = { consumer: Node?, order: number }

local evaluations: { [thread]: Evaluation } = {}
Weak.keys(evaluations)
export type Cache = { thread: thread?, frame: Evaluation?, active: number, order: number }

local cache: Cache = { thread = nil, frame = nil, active = 0, order = 0 }

local function contextOn(running: thread): Node?
	if cache.active == 0 then
		return nil
	end
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
	if cache.active == 0 then
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

local function context(): Node?
	return contextOn(coroutine.running())
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

local function enter(consumer: Node?): (Node?, number)
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
	return previousConsumer, previousOrder
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
	return current, previousConsumer, previousOrder
end

local function leaveFrame(current: Evaluation, previousConsumer: Node?, previousOrder: number)
	current.consumer = previousConsumer
	current.order = previousOrder
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
	current.consumer = previousConsumer
	current.order = previousOrder
	if previousOrder == 0 then
		cache.active -= 1
	end
end

return {
	cache = cache,
	frame = frame,
	context = context,
	contextOn = contextOn,
	enter = enter,
	enterFrame = enterFrame,
	leaveFrame = leaveFrame,
	snapshot = snapshot,
	leave = leave,
}
