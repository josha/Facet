--!strict
--!native

local Graph = require "./graph"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state

export type Reactor = {

	batch: <T...>(self: Reactor, body: () -> T...) -> T...,

	settle: (self: Reactor) -> (),
	pending: (self: Reactor) -> number,
	__enqueue: (self: Reactor, consumer: any) -> (),

	__reset: (self: Reactor) -> (),
}

local MAX_RUNS_PER_DRAIN = 1_000_000

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
	local queue: { any } = {}
	local queueCount = 0
	local cursor = 0
	local batching = false
	local reactor: Reactor

	local drainErrors: { string }? = nil
	local drainAbandoned = false

	local function runRest()
		while cursor < queueCount do
			local limit = queueCount
			if limit > MAX_RUNS_PER_DRAIN then
				limit = MAX_RUNS_PER_DRAIN
			end
			while cursor < limit do
				cursor += 1
				local watch = queue[cursor]
				watch.queued = false
				watch.run(watch)
			end
			if cursor >= MAX_RUNS_PER_DRAIN then
				local errors: { string } = drainErrors or {}
				drainErrors = errors
				table.insert(
					errors,
					(
						"Compose: watch cascade did not settle after %d runs. A watch is very likely "
						.. "writing to a cell it also reads; break the loop, or write inside a batch "
						.. "that ends."
					):format(MAX_RUNS_PER_DRAIN)
				)
				drainAbandoned = true
				return
			end
		end
	end

	local function drain(): { string }?
		drainErrors = nil
		drainAbandoned = false
		local openedAt = if statsOn.enabled then profile.nowOrNil() else nil

		local context = Graph.evaluationContext()
		repeat
			local ok, err: any = xpcall(runRest, debug.traceback)
			if not ok then
				Graph.restoreEvaluationContext(context)
				local errors: { string } = drainErrors or {}
				drainErrors = errors
				table.insert(errors, tostring(err))
			end
		until drainAbandoned or cursor >= queueCount

		if statsOn.enabled then
			stats.bump("continuationPasses", cursor)
			if openedAt ~= nil then
				local closedAt = profile.nowOrNil()
				profile.drain(cursor, if closedAt ~= nil then closedAt - openedAt else 0)
			end
		end

		if drainAbandoned then
			for index = queueCount, 1, -1 do
				queue[index].queued = false
				queue[index] = nil
			end
		else
			table.clear(queue)
		end
		queueCount = 0
		cursor = 0
		return drainErrors
	end

	local function batch<T...>(_self: Reactor, body: () -> T...): T...
		if batching then
			return body()
		end

		batching = true
		if statsOn.enabled then
			stats.bump "drains"
		end

		local outcome = table.pack(xpcall(body, debug.traceback))
		local errors = drain()
		batching = false

		if not outcome[1] then
			error(outcome[2], 0)
		end
		if errors ~= nil then
			error(describeErrors(errors), 0)
		end
		return (table.unpack :: any)(outcome, 2, outcome.n)
	end

	local function settle(_self: Reactor)
		if batching or queueCount == 0 then
			return
		end

		batching = true
		if statsOn.enabled then
			stats.bump "drains"
		end
		local errors = drain()
		batching = false

		if errors ~= nil then
			error(describeErrors(errors), 0)
		end
	end

	local function pending(_self: Reactor): number
		return queueCount - cursor
	end

	local function enqueueConsumer(watch: any)
		if watch.queued then
			if statsOn.enabled then
				stats.bump "watchSchedulesCoalesced"
				profile.schedule(watch, true)
			end
			return
		end
		watch.queued = true
		queueCount += 1
		queue[queueCount] = watch
		if statsOn.enabled then
			stats.bump "watchSchedules"
			profile.schedule(watch, false)
		end

		if not batching then
			Graph.touch(reactor)
		end
	end

	local function enqueue(_self: Reactor, watch: any)
		enqueueConsumer(watch)
	end

	local function enqueueSettleConsumer(watch: any)
		if batching or queueCount > 0 then
			if not watch.queued then
				watch.queued = true
				queueCount += 1
				queue[queueCount] = watch
			end
			return
		end

		batching = true
		local context = Graph.evaluationContext()
		local ok, err: any = xpcall(watch.run, debug.traceback, watch)
		if not ok then
			Graph.restoreEvaluationContext(context)
		end
		local errors: { string }? = nil
		if queueCount > 0 then
			errors = drain()
		end
		batching = false
		if not ok then
			if errors == nil then
				errors = { tostring(err) }
			else
				table.insert(errors, 1, tostring(err))
			end
		end
		if errors ~= nil then
			error(describeErrors(errors), 0)
		end
	end

	local function reset(_self: Reactor)
		for index = queueCount, 1, -1 do
			queue[index].queued = false
			queue[index] = nil
		end
		queueCount = 0
		cursor = 0
		batching = false
	end

	reactor = {
		batch = batch,
		settle = settle,
		pending = pending,
		__enqueue = enqueue,
		__reset = reset,
	}

	(reactor :: any).__enqueueConsumer = enqueueConsumer;
	(reactor :: any).__enqueueSettleConsumer = enqueueSettleConsumer
	return reactor
end

return {
	create = create,
	MAX_RUNS_PER_DRAIN = MAX_RUNS_PER_DRAIN,
}
