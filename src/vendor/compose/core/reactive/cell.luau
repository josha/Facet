--!strict
--!native

local Graph = require "./graph"
local NodeCast = require "./node"
local Reactor = require "./reactor"
local Types = require "./types"
local clock = require "./clock"
local clockState = clock.state
local stats = require "./stats"
local statsOn = stats.state
local userSpace = require "./userSpace"
local validationState = userSpace.state

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>
type Initial<T> = (() -> T) | T

local DIRTY = Graph.DIRTY
local CHECK = Graph.CHECK

local function onlyListeners(first: Node): boolean
	local reactor = first.reactor
	local edge: Node? = first[4]
	while edge ~= nil do
		if edge[2] ~= nil or edge.reactor ~= reactor then
			return false
		end
		edge = edge[4]
	end
	return true
end

local function suppress(self: Node)
	if statsOn.enabled then
		stats.bump "cellWritesSuppressed"
		statsOn.recorder.write(self, true)
	end
end

local function write(self: Node, incoming: unknown)
	self.value = incoming
	local version = clockState.now + 1
	clockState.now = version
	self.version = version
	local first = self.first
	if statsOn.enabled then
		stats.bump "cellWrites"
		Graph.countNotification(self)
		statsOn.recorder.write(self, false)
	elseif first == nil then
		return
	else
		local consumer = first[2]
		if consumer == nil then
			if first[4] == nil or onlyListeners(first) then
				local reactor = first.reactor
				if reactor ~= nil and reactor.batching then
					if not first.queued then
						first.queued = true
						local count = reactor.count + 1
						reactor.count = count
						reactor.queue[count] = first
					end
				else
					Reactor.runNow(first)
				end
				return
			end
		elseif first[4] == nil then
			local state = consumer.state
			if state == DIRTY and not consumer.retry then
				return
			elseif state == CHECK and not consumer.retry then
				consumer.state = DIRTY
				return
			elseif consumer.body == nil and consumer.run ~= nil then
				consumer.retry = false
				consumer.state = DIRTY
				local reactor = consumer.reactor
				if reactor ~= nil and reactor.batching then
					if not consumer.queued then
						consumer.queued = true
						local count = reactor.count + 1
						reactor.count = count
						reactor.queue[count] = consumer
					end
				else
					Reactor.enqueue(consumer)
					Graph.settleTouched()
				end
				return
			end
		end
	end
	if first == nil then
		return
	end
	Graph.markStale(self, DIRTY)
	Graph.settleTouched()
end

local function same(current: unknown, incoming: unknown): boolean
	return current == incoming
end

local CELL = {}
CELL.__index = CELL

local set: (Node, unknown) -> ()

local function coalesced(self: Node, incoming: unknown)
	if self.resume == nil then
		set(self, incoming)
	elseif self.value ~= incoming then
		self.value = incoming
	end
end

local function coalescedNumber(self: Node, incoming: unknown)
	if self.set ~= coalescedNumber then
		set(self, incoming)
		return
	end
	self.value = incoming
	if type(incoming) ~= "number" then
		self.set = coalesced
	end
end

function CELL.peek(self: Node): unknown
	return self.value
end

set = function(self: Node, incoming: unknown)
	local current = self.value
	if if validationState.validating then userSpace.call(same, current, incoming) else current == incoming then
		if statsOn.enabled then
			suppress(self)
		end
		return
	end
	self.value = incoming
	local first = self.first
	local consumer = if first ~= nil then first[2] else nil
	local state = if consumer ~= nil then consumer.state else nil
	if
		state == DIRTY
		and consumer ~= nil
		and consumer.group
		and not statsOn.enabled
		and first ~= nil
		and first[4] == nil
		and not consumer.retry
	then
		if consumer[2] == nil and consumer.queued then
			Graph.coalesce(self, consumer, if type(incoming) == "number" then coalescedNumber else coalesced)
		end
		return
	end
	local version = clockState.now + 1
	clockState.now = version
	self.version = version
	if statsOn.enabled then
		stats.bump "cellWrites"
		Graph.countNotification(self)
		statsOn.recorder.write(self, false)
	elseif first == nil then
		return
	else
		if consumer == nil then
			if first[4] == nil or onlyListeners(first) then
				local reactor = first.reactor
				if reactor ~= nil and reactor.batching then
					if not first.queued then
						first.queued = true
						local count = reactor.count + 1
						reactor.count = count
						reactor.queue[count] = first
					elseif not validationState.validating then
						Graph.coalesce(self, first, if type(incoming) == "number" then coalescedNumber else coalesced)
					end
				else
					Reactor.runNow(first)
				end
				return
			end
		elseif first[4] == nil then
			if state == DIRTY and not consumer.retry then
				return
			elseif state == CHECK and not consumer.retry then
				consumer.state = DIRTY
				return
			elseif consumer.body == nil and consumer.run ~= nil then
				consumer.retry = false
				consumer.state = DIRTY
				local reactor = consumer.reactor
				if reactor ~= nil and reactor.batching then
					if not consumer.queued then
						consumer.queued = true
						local count = reactor.count + 1
						reactor.count = count
						reactor.queue[count] = consumer
					end
				else
					Reactor.runNow(consumer)
				end
				return
			end
		end
	end
	if first == nil then
		return
	end
	Graph.markStale(self, DIRTY)
	Graph.settleTouched()
end

CELL.set = set

function CELL.update(self: Node, change: (previous: unknown) -> unknown)
	CELL.set(self, userSpace.call(change, self.value))
end

function CELL.dispose(_self: Node) end

local EQUAL = {}
EQUAL.__index = EQUAL
EQUAL.peek = CELL.peek
EQUAL.dispose = CELL.dispose

function EQUAL.set(self: Node, incoming: unknown)
	local equals = self.equals or same
	if userSpace.call(equals, self.value, incoming) then
		suppress(self)
		return
	end
	write(self, incoming)
end

function EQUAL.update(self: Node, change: (previous: unknown) -> unknown)
	EQUAL.set(self, userSpace.call(change, self.value))
end

local function start(self: Node)
	local initializer = self.body
	self.body = nil
	self.refresh = nil
	local class = if self.equals ~= nil then EQUAL else CELL
	NodeCast.classify(self, class)
	self.set = class.set
	if initializer then
		self.value = userSpace.call(initializer, Graph.use)
	end
end

local LAZY = {}
LAZY.__index = LAZY
LAZY.refresh = start
LAZY.dispose = CELL.dispose

function LAZY.peek(self: Node): unknown
	start(self)
	return self.value
end

function LAZY.set(self: Node, incoming: unknown)
	start(self)
	local set = self.set
	if set then
		set(self, incoming)
	end
end

function LAZY.update(self: Node, change: (previous: unknown) -> unknown)
	start(self)
	local set = self.set
	if set then
		set(self, userSpace.call(change, self.value))
	end
end

NodeCast.adopt(CELL)
NodeCast.adopt(EQUAL)
NodeCast.adopt(LAZY)

local cellSet = CELL.set

local function cell<T>(initial: Initial<T>, equals: Equals<T>?): Value<T>
	local version = clockState.now + 1
	clockState.now = version
	if equals == nil and type(initial) ~= "function" then
		return (
			setmetatable({ version = version, value = initial, first = nil, set = cellSet }, CELL) :: unknown
		) :: Value<T>
	end
	local initializer, value = NodeCast.split(initial)
	local class = if initializer then LAZY elseif equals ~= nil then EQUAL else CELL
	local node: Node = { version = version, value = value, first = nil, set = class.set }
	if initializer then
		node.body = initializer
		node.refresh = start
	end
	if equals ~= nil then
		node.equals = NodeCast.eraseEquals(equals)
	end
	return NodeCast.make(node, class)
end

local isValue = NodeCast.isNode

return {
	cell = cell,
	isValue = isValue,
	defaultEquals = same,
}
