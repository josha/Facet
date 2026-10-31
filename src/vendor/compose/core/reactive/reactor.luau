--!strict
--!native

local Evaluation = require "./evaluation"
local evaluationCache = Evaluation.cache
local Types = require "./types"
local stats = require "./stats"
local statsOn = stats.state

type Node = Types.Node
export type Reactor = Types.Reactor

local MAX_RUNS_PER_DRAIN = 1_000_000

local caught = ""

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function catch(message: unknown)
	caught = traceback(message)
end

local function describeErrors(errors: { string }): string
	if #errors == 1 then
		return errors[1]
	end
	local parts = { ("Compose: %d errors while running watches:"):format(#errors) }
	for index, message in errors do
		table.insert(parts, ("  [%d] %s"):format(index, message))
	end
	return table.concat(parts, "\n")
end

local function create(): Reactor
	return { queue = {}, count = 0, cursor = 0, batching = false, errors = nil, abandoned = false }
end

local touched: { Reactor } = {}
local touchedCount = 0

local function touch(reactor: Reactor)
	for index = 1, touchedCount do
		if touched[index] == reactor then
			return
		end
	end
	touchedCount += 1
	touched[touchedCount] = reactor
end

local function enqueue(node: Node)
	local reactor = node.reactor
	if reactor == nil then
		return
	end
	if node.queued then
		if statsOn.enabled then
			stats.bump "watchSchedulesCoalesced"
			statsOn.recorder.schedule(node, true)
		end
		return
	end
	node.queued = true
	local count = reactor.count + 1
	reactor.count = count
	reactor.queue[count] = node
	if statsOn.enabled then
		stats.bump "watchSchedules"
		statsOn.recorder.schedule(node, false)
	end
	if not reactor.batching then
		touch(reactor)
	end
end

local function rearm(node: Node)
	if node.released or node.retry then
		return
	end
	node.retry = true
	for index = 1, #node do
		local edge = node[index]
		local producer = if edge ~= nil then edge[1] else nil
		if producer ~= nil and producer.state ~= nil then
			rearm(producer)
		end
	end
end

local function fail(reactor: Reactor, message: string)
	local errors = reactor.errors or {}
	reactor.errors = errors
	table.insert(errors, message)
end

local function runRest(reactor: Reactor)
	local queue = reactor.queue
	while reactor.cursor < reactor.count do
		local limit = math.min(reactor.count, MAX_RUNS_PER_DRAIN)
		while reactor.cursor < limit do
			local cursor = reactor.cursor + 1
			reactor.cursor = cursor
			local node = queue[cursor]
			node.queued = false
			local run = node.run
			if run then
				run(node)
			end
		end
		if reactor.cursor >= MAX_RUNS_PER_DRAIN then
			fail(
				reactor,
				(
					"Compose: watch cascade did not settle after %d runs. A watch is very likely "
					.. "writing to a cell it also reads; break the loop, or write inside a batch "
					.. "that ends."
				):format(MAX_RUNS_PER_DRAIN)
			)
			reactor.abandoned = true
			return
		end
	end
end

local function runInRest(reactor: Reactor)
	local queue = reactor.queue
	local frame, previousConsumer, previousOrder = Evaluation.enterFrame(nil)
	while reactor.cursor < reactor.count do
		local limit = math.min(reactor.count, MAX_RUNS_PER_DRAIN)
		while reactor.cursor < limit do
			local cursor = reactor.cursor + 1
			reactor.cursor = cursor
			local node = queue[cursor]
			node.queued = false
			local runIn =
				rawget((node :: unknown) :: { [string]: unknown }, "runIn") :: ((Evaluation.Evaluation, Node) -> ())?
			if runIn ~= nil then
				runIn(frame, node)
			else
				frame.consumer = previousConsumer
				local run = node.run
				if run then
					run(node)
				end
			end
		end
		if reactor.cursor >= MAX_RUNS_PER_DRAIN then
			fail(
				reactor,
				(
					"Compose: watch cascade did not settle after %d runs. A watch is very likely "
					.. "writing to a cell it also reads; break the loop, or write inside a batch "
					.. "that ends."
				):format(MAX_RUNS_PER_DRAIN)
			)
			reactor.abandoned = true
			Evaluation.leaveFrame(frame, previousConsumer, previousOrder)
			return
		end
	end
	Evaluation.leaveFrame(frame, previousConsumer, previousOrder)
end

local function drain(reactor: Reactor): { string }?
	reactor.errors = nil
	reactor.abandoned = false
	if reactor.count == 0 and not statsOn.enabled then
		reactor.cursor = 0
		return nil
	end
	local openedAt = if statsOn.enabled then statsOn.recorder.nowOrNil() else nil

	local consumer: Types.Node?, at: number
	local cached = evaluationCache.frame
	if cached ~= nil and evaluationCache.thread == coroutine.running() then
		consumer, at = cached.consumer, cached.order
	else
		consumer, at = Evaluation.snapshot()
	end
	repeat
		local first = reactor.queue[reactor.cursor + 1]
		local run = if first ~= nil and rawget((first :: unknown) :: { [string]: unknown }, "runIn") ~= nil
			then runInRest
			else runRest
		if not xpcall(run, catch, reactor) then
			Evaluation.leave(consumer, at)
			fail(reactor, caught)
		end
	until reactor.abandoned or reactor.cursor >= reactor.count

	local cursor = reactor.cursor
	if statsOn.enabled then
		stats.bump("continuationPasses", cursor)
		if openedAt ~= nil then
			local closedAt = statsOn.recorder.nowOrNil()
			statsOn.recorder.drain(cursor, if closedAt ~= nil then closedAt - openedAt else 0)
		end
	end

	local queue = reactor.queue
	if reactor.abandoned then
		local resume = statsOn.resume
		if resume ~= nil then
			resume()
		end
		for index = cursor + 1, reactor.count do
			rearm(queue[index])
		end
		for index = reactor.count, 1, -1 do
			queue[index].queued = false
			queue[index] = nil
		end
	else
		local count = reactor.count
		if count <= 16 then
			for index = 1, count do
				queue[index] = nil
			end
		else
			table.clear(queue)
		end
	end
	reactor.count = 0
	reactor.cursor = 0
	return reactor.errors
end

local function finishBatch<T...>(reactor: Reactor, ok: boolean, ...: T...): T...
	local errors = drain(reactor)
	reactor.batching = false
	if not ok then
		error(select(1, ...), 0)
	end
	if errors ~= nil then
		error(describeErrors(errors), 0)
	end
	return ...
end

local function batch<T...>(reactor: Reactor, body: () -> T...): T...
	if reactor.batching then
		return body()
	end
	reactor.batching = true
	if statsOn.enabled then
		stats.bump "drains"
	end
	return finishBatch(reactor, xpcall(body, traceback))
end

local function batchMethod(reactor: Reactor): <T...>(self: unknown, body: () -> T...) -> T...
	return function<T...>(_self: unknown, body: () -> T...): T...
		if reactor.batching then
			return body()
		end
		reactor.batching = true
		if statsOn.enabled then
			stats.bump "drains"
		end
		return finishBatch(reactor, xpcall(body, traceback))
	end
end

local function settle(reactor: Reactor)
	if reactor.batching or reactor.count == 0 then
		return
	end
	reactor.batching = true
	if statsOn.enabled then
		stats.bump "drains"
	end
	local errors = drain(reactor)
	reactor.batching = false
	if errors ~= nil then
		error(describeErrors(errors), 0)
	end
end

local function settleTouched()
	if touchedCount == 0 then
		return
	end
	local count = touchedCount
	touchedCount = 0

	if count == 1 then
		local only = touched[1]
		touched[1] = nil
		settle(only)
		return
	end

	local pending = touched
	touched = {}
	local errors: { string } = {}
	for index = 1, count do
		local reactor = pending[index]
		pending[index] = nil
		local ok, err: unknown = pcall(settle, reactor)
		if not ok then
			table.insert(errors, tostring(err))
		end
	end
	if #errors == 0 then
		return
	end
	if #errors == 1 then
		error(errors[1], 0)
	end
	local parts = { ("Compose: %d scheduling domains failed while settling one write:"):format(#errors) }
	for index, message in errors do
		table.insert(parts, ("  [%d] %s"):format(index, message))
	end
	error(table.concat(parts, "\n"), 0)
end

local function runNow(node: Node)
	local reactor = node.reactor
	local run = node.run
	if reactor == nil or run == nil then
		return
	end
	if reactor.batching or reactor.count > 0 then
		if not node.queued then
			node.queued = true
			local count = reactor.count + 1
			reactor.count = count
			reactor.queue[count] = node
		end
		return
	end
	reactor.batching = true
	local listener = node.listener
	local producer = node[1]
	local direct = listener ~= nil
		and producer ~= nil
		and rawget((producer :: unknown) :: { [string]: unknown }, "refresh") == nil
		and producer.first == node
		and node[4] == nil
		and not statsOn.enabled
	local consumer: Node? = nil
	local at = 0
	local ok: boolean
	if direct and listener ~= nil and producer ~= nil then
		node.version = producer.version
		ok = xpcall(listener, catch, producer.value)
	else
		consumer, at = Evaluation.snapshot()
		ok = xpcall(run, catch, node)
	end
	if not ok and not direct then
		Evaluation.leave(consumer, at)
	end
	local errors: { string }? = nil
	if reactor.count > 0 then
		errors = drain(reactor)
	end
	reactor.batching = false
	if not ok then
		if errors == nil then
			errors = { caught }
		else
			table.insert(errors, 1, caught)
		end
	end
	if errors ~= nil then
		error(describeErrors(errors), 0)
	end
end

local function pending(reactor: Reactor): number
	return reactor.count - reactor.cursor
end

local function reset(reactor: Reactor)
	local resume = statsOn.resume
	if resume ~= nil then
		resume()
	end
	local queue = reactor.queue
	for index = reactor.count, 1, -1 do
		queue[index].queued = false
		queue[index] = nil
	end
	reactor.count = 0
	reactor.cursor = 0
	reactor.batching = false
end

return {
	create = create,
	enqueue = enqueue,
	runNow = runNow,
	batch = batch,
	batchMethod = batchMethod,
	settle = settle,
	settleTouched = settleTouched,
	pending = pending,
	reset = reset,
	rearm = rearm,
	touch = touch,
	MAX_RUNS_PER_DRAIN = MAX_RUNS_PER_DRAIN,
}
