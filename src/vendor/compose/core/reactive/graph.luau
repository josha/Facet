--!strict
--!native

local Diagnostics = require "../diagnostics"
local Nodes = require "./node"
local Weak = require "../weak"
local Dynamic = require "../dynamic"
local Evaluation = require "./evaluation"
local stats = Evaluation.stats
local evaluationCache = Evaluation.cache
local Reactor = require "./reactor"
local Types = require "./types"
local statsOn = stats.state
local validationState = Evaluation.validation

type Node = Types.Node
type Dispose = Types.Dispose

local clock = { now = 0 }

local function nextVersion(): number
	local version = clock.now + 1
	clock.now = version
	return version
end

local CLEAN = 0
local CHECK = 1
local DIRTY = 2
local RETRY = 3

local detachers = Nodes.detachers
local nodeOf = Nodes.nodeOf
local identityKey = Nodes.identityKey

local invalidated: { Node } = {}

local observations: { [Node]: (boolean) -> () } = {}
Weak.keys(observations)
local observing = 0

local function observe(producer: Node, callback: ((boolean) -> ())?)
	local existing = observations[producer]
	if callback ~= nil and existing == nil then
		observing += 1
	elseif callback == nil and existing ~= nil then
		observing -= 1
	end
	if callback == nil then
		observations[producer] = nil
	else
		observations[producer] = callback
	end
end

local coalesced: { [Node]: boolean } = {}
Weak.keys(coalesced)

local function resumeSet(producer: Node)
	if producer.coalescing then
		local edge = producer.first
		if edge ~= nil then
			local consumer = edge[2]
			if consumer ~= nil then
				consumer.coalesced = false
			else
				local version = edge.version
				if version ~= nil and version < 0 then
					edge.version = -version - 1
				end
			end
		end
		producer.coalescing = nil
		Dynamic.write(producer, "set", nil)
		coalesced[producer] = nil
	end
end

statsOn.resume = function()
	for producer in coalesced do
		resumeSet(producer)
	end
end

local function coalesce(producer: Node, consumer: Node, set: (Node, unknown) -> ())
	if not producer.coalescing then
		producer.coalescing = 1
		Dynamic.write(producer, "set", set)
		if consumer.state == nil then
			consumer.version = -(consumer.version or 0) - 1
		else
			consumer.coalesced = producer
		end
		coalesced[producer] = true
	end
end

local function kindOf(producer: Node): string
	return if producer.state ~= nil and producer.refresh ~= nil then "formula" else "cell"
end

local function append(producer: Node, edge: Node)
	local first = producer.first
	if first == nil then
		producer.first = edge
		edge[3] = edge
		if observing > 0 then
			local observed = observations[producer]
			if observed then
				observed(true)
			end
		end
		return
	end
	if first.listenerGroup and (edge[2] ~= nil or edge.reactor ~= first.reactor) then
		first.listenerGroup = false
	end
	if producer.coalescing ~= nil then
		resumeSet(producer)
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
			if following[2] == nil then
				following.listenerGroup = edge.listenerGroup == true
			end
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
	if observing > 0 and producer.first == nil then
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
	local source: Node? = producer
	while source ~= nil do
		local from = source
		source = nil
		if statsOn.enabled then
			local kind = kindOf(from)
			local recorded = from.first
			while recorded ~= nil do
				statsOn.recorder.edge(from, kind, recorded[2] or recorded)
				recorded = recorded[4]
			end
		end

		local edge = from.first
		local scheduled: Types.Reactor? = nil
		local grouped: Types.Reactor? = nil
		while edge ~= nil do
			local consumer = edge[2]
			local following = edge[4]
			if consumer == nil then
				local reactor = edge.reactor
				if reactor ~= scheduled then
					scheduled = reactor
					Reactor.enqueue(edge)
				end
			else
				local current = consumer.state or CLEAN
				local kind = consumer.kind
				local retry = if kind == 1 or kind == 2 then current == RETRY else consumer.retry
				if current < state or retry then
					if retry and kind ~= 1 and kind ~= 2 then
						consumer.retry = false
					end
					consumer.state = state
					if current == CLEAN or retry then
						if kind == 1 then
							if following == nil then
								source = consumer
							else
								markStale(consumer, CHECK)
							end
						elseif kind == 2 then
							local cutoff = consumer.cutoff
							if cutoff ~= nil then
								cutoff(consumer)
							end
						elseif kind == nil then
							table.insert(invalidated, consumer)
						elseif state == DIRTY and kind == 4 then
							local reactor = consumer.reactor
							if consumer[2] ~= nil then
								Reactor.enqueue(consumer)
							elseif reactor ~= grouped then
								grouped = reactor
								consumer.source = from
								Reactor.enqueue(consumer)
							end
						else
							Reactor.enqueue(consumer)
						end
					end
				end
			end
			edge = following
		end
		state = CHECK
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
				local ok, failure: unknown = pcall(invalidate, node)
				if not ok then
					table.insert(failures, tostring(failure))
				end
			end
		end
	end
	local ok, failure: unknown = pcall(Reactor.settleTouched)
	if not ok then
		table.insert(failures, tostring(failure))
	end
	if #failures > 0 then
		error(table.concat(failures, "\n"), 0)
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

local function noEvaluation()
	return Diagnostics.raise("reactive/no-evaluation", "use() was called outside a reactive body", {
		contract = "use reads a cell or formula and records a dependency, which only means "
			.. "something while a formula, watch, or bound property is evaluating",
		fix = "read it with :peek() outside a reactive body, or move the read inside one",
	})
end

local function use<T>(value: Types.ReadOnlyValue<T>): T
	local frame = evaluationCache.frame
	local consumer = if frame ~= nil
			and frame.order > 0
			and evaluationCache.thread == coroutine.running()
		then frame.consumer
		else Evaluation.context()
	if consumer == nil then
		if type(value) ~= "table" or nodeOf(value).version == nil then
			return notANode("use", value)
		end
		noEvaluation()
		return Nodes.readCached(value)
	end
	local node: Node = value
	local at = consumer.reads
	if at == nil then
		if type(value) ~= "table" or node.version == nil then
			return notANode("use", value)
		end
		local update = node.refresh
		if update then
			update(node)
		end
		return Nodes.readCached(value)
	end
	local following = at + 1
	local edge = consumer[following]
	if edge ~= nil and rawequal(edge[1], value) then
		consumer.reads = following
	else
		edge = consumer[at]
		if edge == nil or not rawequal(edge[1], value) then
			if type(value) ~= "table" or node.version == nil then
				return notANode("use", value)
			end
			consumer.reads = following
			trim(consumer, following)
			local attached = attach(node, consumer)
			consumer[following] = attached
			edge = attached
		end
	end
	local update = if node.state ~= CLEAN then node.refresh else nil
	if update ~= nil then
		update(node)
	end
	if edge ~= nil then
		edge.version = node.version
	end
	local cached = value.cache
	if cached == nil then
		return Nodes.readCached(value)
	end
	return cached.value
end

local function dependenciesMoved(consumer: Node): boolean
	for index = 1, #consumer do
		local edge = consumer[index]
		if edge ~= nil then
			local producer = edge[1]
			if producer ~= nil then
				local update = if producer.state ~= CLEAN then producer.refresh else nil
				if update ~= nil then
					update(producer)
				end
				if producer.version ~= edge.version then
					return true
				end
			end
		end
	end
	return false
end

local function evaluate<A, T>(consumer: Node, body: (A) -> T, argument: A): T
	local running = coroutine.running()
	local cached = if running == evaluationCache.thread then evaluationCache.frame else nil
	local current: Evaluation.Evaluation = if cached ~= nil then cached else Evaluation.frame()
	local previousConsumer, previousOrder = current.consumer, current.order
	if previousOrder == 0 then
		evaluationCache.active += 1
	end
	local order = evaluationCache.order + 1
	evaluationCache.order = order
	current.consumer = consumer
	current.order = order
	consumer.reads = 0

	local ok, result
	if validationState.validating then
		ok, result = pcall(Evaluation.call, body, argument)
	else
		ok, result = pcall(body, argument)
	end

	current.consumer = previousConsumer
	current.order = previousOrder
	if previousOrder == 0 then
		evaluationCache.active -= 1
	end
	evaluationCache.thread = running
	evaluationCache.frame = current
	if not ok then
		if consumer.run == nil then
			consumer.state = DIRTY
			consumer.retry = true
		end
		error(result, 0)
	end

	local reads = consumer.reads or 0
	if #consumer > reads then
		trim(consumer, reads + 1)
	end
	return result
end

local function runEffect(consumer: Node)
	local producer = consumer.coalesced
	if type(producer) == "table" then
		resumeSet(producer)
	end
	local frame, previousConsumer, previousOrder = Evaluation.enterFrame(consumer)
	consumer.reads = 0
	local effect = consumer.effect
	if effect then
		if validationState.validating then
			Evaluation.call(effect, use)
		else
			effect(use)
		end
	end
	Evaluation.leaveFrame(frame, previousConsumer, previousOrder)
	local reads = consumer.reads or 0
	if #consumer > reads then
		trim(consumer, reads + 1)
	end
end

local function runEffectIn(frame: Evaluation.Evaluation, consumer: Node)
	local producer = consumer.coalesced
	if type(producer) == "table" then
		resumeSet(producer)
	end
	frame.consumer = consumer
	consumer.reads = 0
	local effect = consumer.effect
	if effect then
		if validationState.validating then
			Evaluation.call(effect, use)
		else
			effect(use)
		end
	end
	local reads = consumer.reads or 0
	if #consumer > reads then
		trim(consumer, reads + 1)
	end
end

local function release(consumer: Node)
	if consumer.released then
		return
	end
	consumer.released = true
	consumer.reads = nil
	trim(consumer, 1)
	consumer.state = DIRTY
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
	local frame, previousConsumer, previousOrder = Evaluation.enterFrame(nil)
	local ok, result = pcall(body)
	Evaluation.leaveFrame(frame, previousConsumer, previousOrder)
	if not ok then
		error(result, 0)
	end
	return result
end

local function countNotification(producer: Node)
	if statsOn.enabled then
		local count = subscriberCount(producer)
		stats.bump("notifications", count)
		statsOn.recorder.wake(producer, kindOf(producer), count)
	end
end

local LISTENER = {}
LISTENER.__index = LISTENER
LISTENER.listenerGroup = true
Nodes.adopt(LISTENER)

local resume: Node? = nil

local function sweep(producer: Node, reactor: Types.Reactor?, version: number?, from: Node?)
	local edge = from
	while edge ~= nil do
		local following = edge[4]
		resume = following
		if rawget(edge, 2) == nil and edge.reactor == reactor then
			local listener = edge.listener
			if listener ~= nil and edge.version ~= version then
				edge.version = version
				if statsOn.enabled then
					stats.bump "watchRuns"
					statsOn.recorder.enterRun(edge)
				end
				if edge.subject ~= nil then
					listener(producer.value, edge)
				else
					listener(producer.value)
				end
			end
		end
		edge = following
	end
end

local function runListeners(leader: Node, producer: Node)
	local version = producer.version
	local from = producer.first
	if from == leader and rawget(leader, 4) == nil then
		local listener = leader.listener
		if listener ~= nil and leader.version ~= version then
			leader.version = version
			if statsOn.enabled then
				stats.bump "watchRuns"
				statsOn.recorder.enterRun(leader)
			end
			if leader.subject ~= nil then
				listener(producer.value, leader)
			else
				listener(producer.value)
			end
		end
		return
	end
	local reactor = leader.reactor
	local failures: { string }? = nil
	while from ~= nil do
		local previous = resume
		resume = nil
		local ok, err: unknown = pcall(sweep, producer, reactor, version, from)
		local following = resume
		resume = previous
		if ok then
			break
		end
		local collected = failures or {}
		failures = collected
		table.insert(collected, tostring(err))
		from = following
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
	if (leader.version or 0) < 0 then
		resumeSet(producer)
	end
	local update = producer.refresh
	if update then
		update(producer)
	end
	if producer.first == leader and rawget(leader, 4) == nil and not statsOn.enabled then
		local listener = leader.listener
		local version = producer.version
		if listener ~= nil and leader.version ~= version then
			leader.version = version
			if leader.subject ~= nil then
				listener(producer.value, leader)
			else
				listener(producer.value)
			end
		end
		return
	end
	runListeners(leader, producer)
end

local CELL_LISTENER = {}
CELL_LISTENER.__index = CELL_LISTENER
CELL_LISTENER.listenerGroup = true
Nodes.adopt(CELL_LISTENER)

function CELL_LISTENER.run(leader: Node)
	local producer = leader[1]
	if producer == nil then
		return
	end
	if (leader.version or 0) < 0 then
		resumeSet(producer)
	end
	if producer.first == leader and rawget(leader, 4) == nil and not statsOn.enabled then
		local listener = leader.listener
		local version = producer.version
		if listener ~= nil and leader.version ~= version then
			leader.version = version
			if leader.subject ~= nil then
				listener(producer.value, leader)
			else
				listener(producer.value)
			end
		end
		return
	end
	runListeners(leader, producer)
end

local function makeListener(reactor: Types.Reactor, producer: Node): Node
	local update = producer.refresh
	if update then
		update(producer)
	end
	local class = if update ~= nil and producer.refresh ~= nil then LISTENER else CELL_LISTENER
	local edge: Node = { producer, nil, nil, nil, version = producer.version, reactor = reactor }
	Nodes.classify(edge, class)
	return edge
end

local function startListener(edge: Node)
	local producer, listener = edge[1], edge.listener
	if producer == nil or listener == nil then
		return
	end
	if statsOn.enabled then
		statsOn.recorder.born(edge)
		stats.bump "watchRuns"
		statsOn.recorder.enterRun(edge)
	end
	if edge.subject ~= nil then
		listener(producer.value, edge)
	else
		listener(producer.value)
	end
	append(producer, edge)
end

local function listenEdge(
	reactor: Types.Reactor,
	producer: Node,
	listener: (value: unknown, edge: Node?) -> (),
	subject: {},
	key: string,
	transform: ((unknown) -> unknown)?,
	written: unknown
): Node
	local edge = makeListener(reactor, producer)
	edge.listener = listener
	edge.subject = subject
	edge.fastKey = key
	if transform ~= nil then
		edge.transform = transform
		edge.written = written
	end
	startListener(edge)
	return edge
end

local function unlisten(edge: Node)
	if edge.listener ~= nil then
		edge.listener = nil
		detach(edge)
	end
end

local function listen(reactor: Types.Reactor, producer: Node, listener: (unknown) -> ()): Dispose
	local edge = makeListener(reactor, producer)
	edge.listener = listener
	startListener(edge)
	return function()
		unlisten(edge)
	end
end

return {
	detachers = detachers,
	nodeOf = nodeOf,
	identityKey = identityKey,
	clock = clock,
	nextVersion = nextVersion,
	CLEAN = CLEAN,
	coalesce = coalesce,
	CHECK = CHECK,
	DIRTY = DIRTY,
	RETRY = RETRY,
	observe = observe,
	trim = trim,
	markStale = markStale,
	settleTouched = settleTouched,
	notANode = notANode,
	use = use,
	runEffect = runEffect,
	runEffectIn = runEffectIn,
	dependenciesMoved = dependenciesMoved,
	evaluate = evaluate,
	release = release,
	untracked = untracked,
	countNotification = countNotification,
	listen = listen,
	listenEdge = listenEdge,
	unlisten = unlisten,
}
