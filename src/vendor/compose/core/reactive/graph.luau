--!strict
--!native

local Diagnostics = require "../diagnostics"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local userSpace = require "./userSpace"
local validationState = userSpace.state

local CLEAN = 0
local CHECK = 1
local DIRTY = 2

export type Producer = {

	version: number,

	subscribers: Edge?,
	lastSubscriber: Edge?,

	refresh: ((Producer) -> ()) | false,

	derived: boolean,
}

export type Consumer = {
	state: number,

	dependencies: { Edge },
	reads: number,
	enqueue: ((Consumer) -> ())?,
	released: boolean,
	retry: boolean?,
}

local PRODUCER, CONSUMER, OBSERVED, PREVIOUS, NEXT = 1, 2, 3, 4, 5

export type Edge = { any }

local evaluating: Consumer? = nil

local touched: { any } = {}
local touchedCount = 0

local function attach(producer: Producer, consumer: Consumer): Edge
	local tail = producer.lastSubscriber
	local edge: Edge = { producer, consumer, producer.version, tail, nil }
	if tail ~= nil then
		tail[NEXT] = edge
	else
		producer.subscribers = edge
	end
	producer.lastSubscriber = edge
	return edge
end

local function detach(edge: Edge)
	local previous = edge[PREVIOUS]
	local following = edge[NEXT]
	local producer = edge[PRODUCER]
	if previous ~= nil then
		previous[NEXT] = following
	else
		producer.subscribers = following
	end
	if following ~= nil then
		following[PREVIOUS] = previous
	else
		producer.lastSubscriber = previous
	end
	edge[PREVIOUS] = nil
	edge[NEXT] = nil
end

local function trim(consumer: Consumer, from: number)
	local dependencies = consumer.dependencies
	for index = #dependencies, from, -1 do
		detach(dependencies[index])
		dependencies[index] = nil
	end
end

local function markStale(producer: Producer, state: number)
	if statsOn.enabled then
		local kind = if (producer :: any).derived then "formula" else "cell"
		local recorded = producer.subscribers
		while recorded ~= nil do
			profile.edge(producer, kind, recorded[CONSUMER])
			recorded = recorded[NEXT]
		end
	end

	local edge = producer.subscribers
	while edge ~= nil do
		local consumer = edge[CONSUMER]
		if consumer.state < state or consumer.retry then
			local wasClean = consumer.state == CLEAN or consumer.retry
			consumer.retry = false
			consumer.state = state
			if wasClean then
				if (consumer :: any).derived then
					markStale((consumer :: any) :: Producer, CHECK)
				end
				local enqueue = consumer.enqueue

				if enqueue then
					enqueue(consumer)
				end
			end
		end
		edge = edge[NEXT]
	end
end

local function touch(reactor: any)
	for index = 1, touchedCount do
		if touched[index] == reactor then
			return
		end
	end
	touchedCount += 1
	touched[touchedCount] = reactor
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
		only:settle()
		return
	end

	local errors: { string }? = nil
	for index = 1, count do
		local reactor = touched[index]
		touched[index] = nil
		local ok, err: any = pcall(reactor.settle, reactor)
		if not ok then
			if errors == nil then
				errors = {}
			end
			table.insert(errors :: { string }, tostring(err))
		end
	end

	local failures = errors
	if failures == nil then
		return
	end
	if #failures == 1 then
		error(failures[1], 0)
	end
	local parts = { ("Compose: %d scheduling domains failed while settling one write:"):format(#failures) }
	for index, message in failures do
		table.insert(parts, ("  [%d] %s"):format(index, message))
	end
	error(table.concat(parts, "\n"), 0)
end

local function observe(producer: Producer)
	local consumer = evaluating
	if consumer == nil then
		Diagnostics.raise("reactive/no-evaluation", "use() was called outside a reactive body", {
			contract = "use reads a cell or formula and records a dependency, which only means "
				.. "something while a formula, watch, or bound property is evaluating",
			fix = "read it with :peek() outside a reactive body, or move the read inside one",
		})
		return
	end

	local refresh = producer.refresh
	if refresh then
		(refresh :: (Producer) -> ())(producer)
	end

	if consumer.released then
		return
	end

	local at = consumer.reads + 1
	consumer.reads = at
	local dependencies = consumer.dependencies
	local existing = dependencies[at]
	if existing ~= nil and existing[PRODUCER] == producer then
		existing[OBSERVED] = producer.version
		return
	end

	trim(consumer, at)
	dependencies[at] = attach(producer, consumer)
end

local function dependenciesMoved(consumer: Consumer): boolean
	local dependencies = consumer.dependencies
	for index = 1, #dependencies do
		local edge = dependencies[index]
		local producer = edge[PRODUCER]
		local refresh = producer.refresh
		if refresh then
			refresh(producer)
		end
		if producer.version ~= edge[OBSERVED] then
			return true
		end
	end
	return false
end

local function evaluate<A, T>(consumer: Consumer, body: (A) -> T, argument: A): T
	local previous = evaluating
	evaluating = consumer
	consumer.reads = 0

	local ok, result
	if validationState.validating then
		ok, result = pcall(userSpace.call, body, argument)
	else
		ok, result = pcall(body, argument)
	end

	evaluating = previous
	if not ok then
		error(result, 0)
	end

	trim(consumer, consumer.reads + 1)
	return result :: T
end

local function beginEvaluation(consumer: Consumer): Consumer?
	local previous = evaluating
	evaluating = consumer
	consumer.reads = 0
	return previous
end

local function finishEvaluation(consumer: Consumer, previous: Consumer?)
	evaluating = previous
	local dependencies = consumer.dependencies
	local from = consumer.reads + 1
	for index = #dependencies, from, -1 do
		detach(dependencies[index])
		dependencies[index] = nil
	end
end

local function evaluationContext(): Consumer?
	return evaluating
end

local function restoreEvaluationContext(previous: Consumer?)
	evaluating = previous
end

local function release(consumer: Consumer)
	if consumer.released then
		return
	end
	consumer.released = true
	trim(consumer, 1)
	consumer.state = CLEAN
end

local function rearm(consumer: Consumer)
	if consumer.released or consumer.retry then
		return
	end
	consumer.retry = true
	for _, edge in consumer.dependencies do
		local producer = edge[PRODUCER]
		if producer.derived then
			rearm(producer)
		end
	end
end

local function subscriberCount(producer: Producer): number
	local total = 0
	local edge = producer.subscribers
	while edge ~= nil do
		total += 1
		edge = edge[NEXT]
	end
	return total
end

local function untracked<T>(body: () -> T): T
	local previous = evaluating
	evaluating = nil
	local ok, result = pcall(body)
	evaluating = previous
	if not ok then
		error(result, 0)
	end
	return result :: T
end

local function notANode(api: string, value: any): never
	local actual = Diagnostics.describe(value)
	Diagnostics.raise(
		"reactive/not-a-node",
		("%s was given a %s where a cell or formula was expected"):format(api, actual),
		{
			actual = actual,
			expected = "a cell or a formula",
			contract = ("%s records a dependency on a node the graph owns, and only a cell or a formula is one"):format(
				api
			),
			fix = "a body is called, not read: write source(use) rather than use(source), or wrap it once with Compose.formula(source)",
		}
	)
	error("unreachable", 0)
end

local function use<T>(producer: any): T
	if type(producer) ~= "table" or getmetatable(producer :: any) == nil then
		notANode("use", producer)
	end
	local consumer = evaluating
	if consumer == nil then
		observe(producer)
		return producer.value
	end

	local refresh = producer.refresh
	if refresh then
		(refresh :: (Producer) -> ())(producer)
	end

	if consumer.released then
		return producer.value
	end

	local at = consumer.reads + 1
	consumer.reads = at
	local dependencies = consumer.dependencies
	local existing = dependencies[at]
	if existing ~= nil and existing[PRODUCER] == producer then
		existing[OBSERVED] = producer.version
		return producer.value
	end

	trim(consumer, at)
	dependencies[at] = attach(producer, consumer)
	return producer.value
end

local function runTracked(consumer: any)
	local previous = evaluating
	evaluating = consumer
	consumer.reads = 0

	if validationState.validating then
		userSpace.call(consumer.body, use)
	else
		consumer.body(use)
	end

	evaluating = previous
	local dependencies = consumer.dependencies
	for index = #dependencies, consumer.reads + 1, -1 do
		detach(dependencies[index])
		dependencies[index] = nil
	end
end

local function countNotification(producer: Producer)
	if statsOn.enabled then
		local count = subscriberCount(producer)
		stats.bump("notifications", count)
		profile.wake(producer, if (producer :: any).derived then "formula" else "cell", count)
	end
end

return {
	PRODUCER = PRODUCER,
	CONSUMER = CONSUMER,
	OBSERVED = OBSERVED,
	PREVIOUS = PREVIOUS,
	NEXT = NEXT,
	CLEAN = CLEAN,
	CHECK = CHECK,
	DIRTY = DIRTY,
	attach = attach,
	detach = detach,
	trim = trim,
	markStale = markStale,
	notANode = notANode,
	observe = observe,
	dependenciesMoved = dependenciesMoved,
	evaluate = evaluate,
	beginEvaluation = beginEvaluation,
	finishEvaluation = finishEvaluation,
	evaluationContext = evaluationContext,
	restoreEvaluationContext = restoreEvaluationContext,
	runTracked = runTracked,
	release = release,
	rearm = rearm,
	subscriberCount = subscriberCount,
	untracked = untracked,
	use = use,
	touch = touch,
	settleTouched = settleTouched,
	countNotification = countNotification,
}
