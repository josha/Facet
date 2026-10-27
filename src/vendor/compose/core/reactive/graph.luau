--!strict
--!native

local Diagnostics = require "../diagnostics"
local Evaluation = require "./evaluation"
local evaluationCache = Evaluation.cache
local NodeCast = require "./node"
local Reactor = require "./reactor"
local Types = require "./types"
local Weak = require "../weak"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local userSpace = require "./userSpace"
local validationState = userSpace.state

type Node = Types.Node
type Value<T> = Types.Value<T>
type Dispose = Types.Dispose

local CLEAN = 0
local CHECK = 1
local DIRTY = 2

local invalidated: { Node } = {}

local observations: { [Node]: (boolean) -> () } = {}
Weak.keys(observations)

local coalesced: { [Node]: boolean } = {}
Weak.keys(coalesced)

local function resumeSet(producer: Node)
	local set = producer.resume
	if set ~= nil then
		local edge = producer.first
		local consumer = if edge ~= nil then edge[2] else nil
		if consumer ~= nil then
			consumer.coalesced = nil
		end
		producer.resume = nil
		producer.set = set
		coalesced[producer] = nil
	end
end

statsOn.resume = function()
	for producer in coalesced do
		resumeSet(producer)
	end
end

local function coalesce(producer: Node, consumer: Node, set: (Node, unknown) -> ())
	if producer.resume == nil then
		producer.resume = producer.set
		producer.set = set
		consumer.coalesced = producer
		coalesced[producer] = true
	end
end

local function kindOf(producer: Node): string
	return if producer.state ~= nil then "formula" else "cell"
end

local function append(producer: Node, edge: Node)
	resumeSet(producer)
	local first = producer.first
	if first == nil then
		producer.first = edge
		edge[3] = edge
		local observed = observations[producer]
		if observed then
			observed(true)
		end
		return
	end
	local last = first[3]
	if last ~= nil then
		last[4] = edge
	end
	edge[3] = last
	first[3] = edge
end

local function attach(producer: Node, consumer: Node): Node
	local edge: Node = { producer, consumer, nil, nil, version = producer.version }
	append(producer, edge)
	return edge
end

local function detach(edge: Node)
	local producer = edge[1]
	if producer == nil then
		return
	end
	resumeSet(producer)
	local first = producer.first
	local previous = edge[3]
	local following = edge[4]
	if edge == first then
		producer.first = following
		if following ~= nil then
			following[3] = previous
		end
	else
		if previous ~= nil then
			previous[4] = following
		end
		if following ~= nil then
			following[3] = previous
		elseif first ~= nil then
			first[3] = previous
		end
	end
	edge[3] = nil
	edge[4] = nil
	if producer.first == nil then
		local observed = observations[producer]
		if observed then
			observed(false)
		end
	end
end

local function trim(consumer: Node, from: number)
	for index = #consumer, from, -1 do
		local edge = consumer[index]
		if edge ~= nil then
			detach(edge)
		end
		consumer[index] = nil
	end
end

local function markStale(producer: Node, state: number)
	if statsOn.enabled then
		local kind = kindOf(producer)
		local recorded = producer.first
		while recorded ~= nil do
			profile.edge(producer, kind, recorded[2] or recorded)
			recorded = recorded[4]
		end
	end

	local edge = producer.first
	local scheduled: Types.Reactor? = nil
	local grouped: Types.Reactor? = nil
	while edge ~= nil do
		local consumer = edge[2]
		if consumer == nil then
			local reactor = edge.reactor
			if reactor ~= scheduled then
				scheduled = reactor
				Reactor.enqueue(edge)
			end
		else
			local current = consumer.state or CLEAN
			local retry = consumer.retry
			if current < state or retry then
				if retry then
					consumer.retry = false
				end
				consumer.state = state
				if current == CLEAN or retry then
					if consumer.invalidate ~= nil then
						consumer.announced = consumer.version
						table.insert(invalidated, consumer)
					elseif consumer.run == nil then
						markStale(consumer, CHECK)
					elseif state == DIRTY and consumer.group then
						local reactor = consumer.reactor
						if consumer[2] ~= nil then
							Reactor.enqueue(consumer)
						elseif reactor ~= grouped then
							grouped = reactor
							consumer.source = producer
							Reactor.enqueue(consumer)
						end
					else
						Reactor.enqueue(consumer)
					end
				end
			end
		end
		edge = edge[4]
	end
end

local function settleTouched()
	if #invalidated == 0 then
		Reactor.settleTouched()
		return
	end
	local failures: { string } = {}
	while #invalidated > 0 do
		local pending = invalidated
		invalidated = {}
		for _, node in pending do
			local invalidate = node.invalidate
			if invalidate ~= nil and not node.released then
				local ok, failure: unknown = pcall(function(): unknown
					invalidate(node)
					return nil
				end)
				if not ok then
					table.insert(failures, tostring(failure))
				end
			end
		end
	end
	local ok, failure: unknown = pcall(function(): unknown
		Reactor.settleTouched()
		return nil
	end)
	if not ok then
		table.insert(failures, tostring(failure))
	end
	if #failures > 0 then
		error(table.concat(failures, "\n"), 0)
	end
end

local function refresh(producer: Node)
	local update = producer.refresh
	if update then
		update(producer)
	end
end

local function notANode(api: string, candidate: unknown): never
	local actual = Diagnostics.describe(candidate)
	return Diagnostics.raise(
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
end

local function observe(node: Node, value: unknown)
	if type(value) ~= "table" or node.version == nil then
		notANode("use", value)
	end
	local frame = evaluationCache.frame
	local consumer = if frame ~= nil
			and frame.order > 0
			and evaluationCache.thread == coroutine.running()
		then frame.consumer
		else Evaluation.context()
	if consumer == nil then
		Diagnostics.raise("reactive/no-evaluation", "use() was called outside a reactive body", {
			contract = "use reads a cell or formula and records a dependency, which only means "
				.. "something while a formula, watch, or bound property is evaluating",
			fix = "read it with :peek() outside a reactive body, or move the read inside one",
		})
		return
	end
	if consumer.released then
		refresh(node)
		return
	end
	local at = consumer.reads
	if at == nil then
		refresh(node)
		return
	end
	local edge = consumer[at]
	if edge == nil or edge[1] ~= node then
		at += 1
		consumer.reads = at
		edge = consumer[at]
		if edge == nil or edge[1] ~= node then
			trim(consumer, at)
			local attached = attach(node, consumer)
			consumer[at] = attached
			edge = attached
		end
	end
	local update = node.refresh
	if update then
		update(node)
	end
	if edge ~= nil then
		edge.version = node.version
	end
end

NodeCast.setObserver(observe)

local use = NodeCast.use

local function dependenciesMoved(consumer: Node): boolean
	for index = 1, #consumer do
		local edge = consumer[index]
		if edge ~= nil then
			local producer = edge[1]
			if producer ~= nil then
				refresh(producer)
				if producer.version ~= edge.version then
					return true
				end
			end
		end
	end
	return false
end

local function evaluate<A, T>(consumer: Node, body: (A) -> T, argument: A): T
	local previousConsumer, previousOrder = Evaluation.enter(consumer)
	consumer.reads = 0

	local ok, result
	if validationState.validating then
		ok, result = pcall(userSpace.call, body, argument)
	else
		ok, result = pcall(body, argument)
	end

	Evaluation.leave(previousConsumer, previousOrder)
	if not ok then
		if consumer.run == nil then
			consumer.state = DIRTY
			consumer.retry = true
		end
		error(result, 0)
	end

	trim(consumer, (consumer.reads or 0) + 1)
	return result
end

local function runEffect(consumer: Node)
	local producer = consumer.coalesced
	if producer ~= nil then
		resumeSet(producer)
	end
	local previousConsumer, previousOrder = Evaluation.enter(consumer)
	consumer.reads = 0
	local effect = consumer.effect
	if effect then
		if validationState.validating then
			userSpace.call(effect, use)
		else
			effect(use)
		end
	end
	Evaluation.leave(previousConsumer, previousOrder)
	trim(consumer, (consumer.reads or 0) + 1)
end

local function runEffectIn(frame: Evaluation.Evaluation, consumer: Node)
	local producer = consumer.coalesced
	if producer ~= nil then
		resumeSet(producer)
	end
	frame.consumer = consumer
	consumer.reads = 0
	local effect = consumer.effect
	if effect then
		if validationState.validating then
			userSpace.call(effect, use)
		else
			effect(use)
		end
	end
	trim(consumer, (consumer.reads or 0) + 1)
end

local function track(consumer: Node, invoke: (Node) -> ())
	local previousConsumer, previousOrder = Evaluation.enter(consumer)
	consumer.reads = 0
	invoke(consumer)
	Evaluation.leave(previousConsumer, previousOrder)
	trim(consumer, (consumer.reads or 0) + 1)
end

local function release(consumer: Node)
	if consumer.released then
		return
	end
	consumer.released = true
	trim(consumer, 1)
	consumer.state = CLEAN
end

local function subscriberCount(producer: Node): number
	local total = 0
	local edge = producer.first
	while edge ~= nil do
		total += 1
		edge = edge[4]
	end
	return total
end

local function untracked<T>(body: () -> T): T
	local previousConsumer, previousOrder = Evaluation.enter(nil)
	local ok, result = pcall(body)
	Evaluation.leave(previousConsumer, previousOrder)
	if not ok then
		error(result, 0)
	end
	return result
end

local function countNotification(producer: Node)
	if statsOn.enabled then
		local count = subscriberCount(producer)
		stats.bump("notifications", count)
		profile.wake(producer, kindOf(producer), count)
	end
end

local LISTENER = {}
LISTENER.__index = LISTENER

local resume: Node? = nil

local function sweep(producer: Node, reactor: Types.Reactor?, version: number?, from: Node?)
	local edge = from
	while edge ~= nil do
		local following = edge[4]
		resume = following
		if edge[2] == nil and edge.reactor == reactor then
			local listener = edge.listener
			if listener ~= nil and edge.version ~= version then
				edge.version = version
				if statsOn.enabled then
					stats.bump "watchRuns"
					profile.enterRun(edge)
				end
				listener(producer.value)
			end
		end
		edge = following
	end
end

local function runListeners(leader: Node, producer: Node)
	local version = producer.version
	local from = producer.first
	if from == leader and leader[4] == nil then
		local listener = leader.listener
		if listener ~= nil and leader.version ~= version then
			leader.version = version
			if statsOn.enabled then
				stats.bump "watchRuns"
				profile.enterRun(leader)
			end
			listener(producer.value)
		end
		return
	end
	local reactor = leader.reactor
	local failures: { string }? = nil
	while from ~= nil do
		resume = nil
		local ok, err: unknown = pcall(sweep, producer, reactor, version, from)
		if ok then
			break
		end
		local collected = failures or {}
		failures = collected
		table.insert(collected, tostring(err))
		from = resume
	end
	if failures ~= nil then
		if #failures == 1 then
			error(failures[1], 0)
		end
		error(("Compose: %d direct bindings failed:\n  %s"):format(#failures, table.concat(failures, "\n  ")), 0)
	end
end

function LISTENER.run(leader: Node)
	local producer = leader[1]
	if producer == nil or producer.released then
		return
	end
	local update = producer.refresh
	if update then
		update(producer)
	end
	if producer.first == leader and leader[4] == nil and not statsOn.enabled then
		local listener = leader.listener
		local version = producer.version
		if listener ~= nil and leader.version ~= version then
			leader.version = version
			listener(producer.value)
		end
		return
	end
	runListeners(leader, producer)
end

local CELL_LISTENER = {}
CELL_LISTENER.__index = CELL_LISTENER

function CELL_LISTENER.run(leader: Node)
	local producer = leader[1]
	if producer == nil then
		return
	end
	if producer.first == leader and leader[4] == nil and not statsOn.enabled then
		local listener = leader.listener
		local version = producer.version
		if listener ~= nil and leader.version ~= version then
			leader.version = version
			listener(producer.value)
		end
		return
	end
	runListeners(leader, producer)
end

local function listenEdge(reactor: Types.Reactor, producer: Node, listener: (value: unknown) -> ()): Node
	refresh(producer)
	local edge: Node =
		{ producer, nil, nil, nil, version = producer.version, reactor = reactor, queued = false, listener = listener }
	NodeCast.classify(edge, if producer.refresh ~= nil then LISTENER else CELL_LISTENER)
	if statsOn.enabled then
		profile.born(edge)
		stats.bump "watchRuns"
		profile.enterRun(edge)
	end
	listener(producer.value)
	append(producer, edge)
	return edge
end

local function unlisten(subject: unknown)
	local edge = NodeCast.heldEdge(subject)
	if edge.listener ~= nil then
		edge.listener = nil
		detach(edge)
	end
end

local function listen(reactor: Types.Reactor, producer: Node, listener: (value: unknown) -> ()): Dispose
	refresh(producer)
	local edge: Node =
		{ producer, nil, nil, nil, version = producer.version, reactor = reactor, queued = false, listener = listener }
	NodeCast.classify(edge, if producer.refresh ~= nil then LISTENER else CELL_LISTENER)
	if statsOn.enabled then
		profile.born(edge)
		stats.bump "watchRuns"
		profile.enterRun(edge)
	end
	listener(producer.value)
	append(producer, edge)
	return function()
		if edge.listener ~= nil then
			edge.listener = nil
			detach(edge)
		end
	end
end

return {
	CLEAN = CLEAN,
	coalesce = coalesce,
	CHECK = CHECK,
	DIRTY = DIRTY,
	observations = observations,
	attach = attach,
	detach = detach,
	trim = trim,
	markStale = markStale,
	settleTouched = settleTouched,
	refresh = refresh,
	notANode = notANode,
	use = use,
	runEffect = runEffect,
	runEffectIn = runEffectIn,
	dependenciesMoved = dependenciesMoved,
	evaluate = evaluate,
	track = track,
	release = release,
	subscriberCount = subscriberCount,
	untracked = untracked,
	countNotification = countNotification,
	listen = listen,
	listenEdge = listenEdge,
	unlisten = unlisten,
}
