--!strict
--!native

local Evaluation = require "./evaluation"
local Graph = require "./graph"
local NodeCast = require "./node"
local Types = require "./types"
local stats = require "./stats"
local statsOn = stats.state

type Body = (use: Types.Use) -> ()
type Node = Types.Node
type Reactor = Types.Reactor
type Dispose = Types.Dispose

local enterScope: (Node) -> () = function(_node: Node) end
local leaveScope: (Node) -> () = function(_node: Node) end

local function installScope(enter: (Node) -> (), leave: (Node) -> ())
	enterScope, leaveScope = enter, leave
end

local function rerun(node: Node)
	if statsOn.enabled then
		stats.bump "watchRuns"
		statsOn.recorder.enterRun(node)
	end
	node.state = Graph.CLEAN
	if node.inherited ~= nil then
		enterScope(node)
	end
	Graph.runEffect(node)
end

local function moved(node: Node): boolean
	node.retry = true
	local result = Graph.dependenciesMoved(node)
	node.retry = false
	return result
end

local function guardedMoved(node: Node): boolean
	local checked, result = pcall(Graph.dependenciesMoved, node)
	return not checked or result
end

local WATCH = {}
WATCH.__index = WATCH

function WATCH.run(node: Node)
	if node.released then
		return
	end
	if node.state == Graph.CHECK and not moved(node) then
		node.state = Graph.CLEAN
		return
	end
	rerun(node)
end

local TERMINAL = {}
TERMINAL.__index = TERMINAL
TERMINAL.group = true

local resume: Node? = nil

local function sweep(leader: Node, producer: Node, from: Node?)
	local reactor = leader.reactor
	local frame = Evaluation.frame()
	local previousConsumer, previousOrder = Evaluation.enter(leader)
	local edge = from
	while edge ~= nil do
		local following = edge[4]
		resume = following
		local consumer = edge[2]
		if
			consumer ~= nil
			and consumer ~= leader
			and consumer[2] == nil
			and consumer.state == Graph.DIRTY
			and consumer.reactor == reactor
			and not consumer.queued
			and not consumer.released
			and consumer.group
		then
			if statsOn.enabled then
				stats.bump "watchRuns"
				statsOn.recorder.enterRun(consumer)
			end
			consumer.state = Graph.CLEAN
			Graph.runEffectIn(frame, consumer)
		end
		edge = following
	end
	Evaluation.leave(previousConsumer, previousOrder)
end

function TERMINAL.run(leader: Node)
	local producer = leader.source
	leader.source = nil
	if not leader.released then
		if leader.state == Graph.CHECK and not moved(leader) then
			leader.state = Graph.CLEAN
		else
			rerun(leader)
		end
	end
	if producer == nil then
		return
	end
	local first = producer.first
	if first ~= nil and first[4] == nil then
		return
	end
	local consumer, at = Evaluation.snapshot()
	local from = producer.first
	local failures: { string }? = nil
	while from ~= nil do
		resume = nil
		local ok, err: unknown = pcall(sweep, leader, producer, from)
		if ok then
			break
		end
		Evaluation.leave(consumer, at)
		local collected = failures or {}
		failures = collected
		table.insert(collected, tostring(err))
		from = resume
	end
	if failures ~= nil then
		if #failures == 1 then
			error(failures[1], 0)
		end
		error(("Compose: %d fused bindings failed:\n  %s"):format(#failures, table.concat(failures, "\n  ")), 0)
	end
end

function TERMINAL.runIn(frame: Evaluation.Evaluation, node: Node)
	if node.source ~= nil or node.state == Graph.CHECK then
		TERMINAL.run(node)
		return
	end
	if node.released then
		return
	end
	if statsOn.enabled then
		stats.bump "watchRuns"
		statsOn.recorder.enterRun(node)
	end
	node.state = Graph.CLEAN
	Graph.runEffectIn(frame, node)
end

local GUARDED = {}
GUARDED.__index = GUARDED

function GUARDED.run(node: Node)
	if node.released then
		return
	end
	if node.state == Graph.CHECK and not guardedMoved(node) then
		node.state = Graph.CLEAN
		return
	end
	rerun(node)
end

local function begin(reactor: Reactor, body: Body, class: {}, label: string?, scope: unknown?): Node
	local node: Node = {
		state = Graph.DIRTY,
		reactor = reactor,
		effect = body,
		released = false,
		queued = false,
		inherited = scope,
		child = nil,
		base = nil,
	}
	NodeCast.classify(node, class)
	if statsOn.enabled then
		statsOn.recorder.born(node, label)
	end
	local consumer, at = Evaluation.snapshot()
	local ok, err: unknown = pcall(rerun, node)
	if not ok then
		Evaluation.leave(consumer, at)
		Graph.release(node)
		if node.child ~= nil then
			leaveScope(node)
		end
		error(err, 0)
	end
	return node
end

local function releaseHeld(subject: unknown)
	local node = NodeCast.heldEdge(subject)
	if node.listener ~= nil then
		Graph.unlisten(node)
	elseif not node.released and node.effect ~= nil then
		Graph.release(node)
		node.queued = false
	end
end

local function start(reactor: Reactor, body: Body, class: {}, label: string?, scope: unknown?): Dispose
	local node = begin(reactor, body, class, label, scope)
	return function()
		if node.released then
			return
		end
		Graph.release(node)
		node.queued = false
		if node.child ~= nil then
			leaveScope(node)
		end
	end
end

local function watch(reactor: Reactor, body: Body, label: string?): Dispose
	return start(reactor, body, WATCH, label)
end

local function watchGuarded(reactor: Reactor, body: Body, label: string?): Dispose
	return start(reactor, body, GUARDED, label)
end

local function watchScoped(reactor: Reactor, body: Body, label: string?, scope: unknown, guarded: boolean): Dispose
	return start(reactor, body, if guarded then GUARDED else WATCH, label, scope)
end

local function watchTerminal(reactor: Reactor, body: Body): Dispose
	return start(reactor, body, TERMINAL, nil)
end

local function terminalNode(reactor: Reactor, body: Body): Node
	return begin(reactor, body, TERMINAL, nil)
end

local function watchStatic<T>(reactor: Reactor, value: Types.ReadOnlyValue<T>, body: (value: T) -> ()): Dispose
	return Graph.listen(reactor, NodeCast.nodeOf(value), NodeCast.eraseListener(body))
end

local function listenEdge<T>(reactor: Reactor, value: Types.ReadOnlyValue<T>, body: (value: T) -> ()): Node
	return Graph.listenEdge(reactor, NodeCast.nodeOf(value), NodeCast.eraseListener(body))
end

local function sample<T>(body: () -> T): T
	return Graph.untracked(body)
end

return {
	watch = watch,
	watchGuarded = watchGuarded,
	watchScoped = watchScoped,
	installScope = installScope,
	watchStatic = watchStatic,
	listenEdge = listenEdge,
	unlisten = Graph.unlisten,
	terminalNode = terminalNode,
	releaseHeld = releaseHeld,
	watchTerminal = watchTerminal,
	sample = sample,
}
