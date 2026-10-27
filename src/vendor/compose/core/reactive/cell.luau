--!strict
--!native

local Graph = require "./graph"
local NodeCast = require "./node"
local Reactor = require "./reactor"
local Types = require "./types"
local clock = require "./clock"
local clockState = clock.state
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local userSpace = require "./userSpace"
local validationState = userSpace.state

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>
type Initial<T> = (() -> T) | T

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
		profile.write(self, true)
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
		profile.write(self, false)
	elseif first == nil then
		return
	else
		local consumer = first[2]
		if consumer == nil then
			if first[4] == nil or onlyListeners(first) then
				Reactor.runNow(first)
				return
			end
		elseif first[4] == nil then
			local state = consumer.state
			if state == Graph.DIRTY and not consumer.retry then
				return
			elseif state == Graph.CHECK and not consumer.retry then
				consumer.state = Graph.DIRTY
				return
			elseif consumer.run ~= nil then
				consumer.retry = false
				consumer.state = Graph.DIRTY
				Reactor.enqueue(consumer)
				Graph.settleTouched()
				return
			end
		end
	end
	if first == nil then
		return
	end
	Graph.markStale(self, Graph.DIRTY)
	Graph.settleTouched()
end

local function same(current: unknown, incoming: unknown): boolean
	return current == incoming
end

local CELL = {}
CELL.__index = CELL

function CELL.peek(self: Node): unknown
	return self.value
end

function CELL.set(self: Node, incoming: unknown)
	local current = self.value
	if if validationState.validating then userSpace.call(same, current, incoming) else current == incoming then
		if statsOn.enabled then
			suppress(self)
		end
		return
	end
	self.value = incoming
	local version = clockState.now + 1
	clockState.now = version
	self.version = version
	local first = self.first
	if statsOn.enabled then
		stats.bump "cellWrites"
		Graph.countNotification(self)
		profile.write(self, false)
	elseif first == nil then
		return
	else
		local consumer = first[2]
		if consumer == nil then
			if first[4] == nil or onlyListeners(first) then
				Reactor.runNow(first)
				return
			end
		elseif first[4] == nil then
			local state = consumer.state
			if state == Graph.DIRTY and not consumer.retry then
				return
			elseif state == Graph.CHECK and not consumer.retry then
				consumer.state = Graph.DIRTY
				return
			elseif consumer.run ~= nil then
				consumer.retry = false
				consumer.state = Graph.DIRTY
				Reactor.enqueue(consumer)
				Graph.settleTouched()
				return
			end
		end
	end
	if first == nil then
		return
	end
	Graph.markStale(self, Graph.DIRTY)
	Graph.settleTouched()
end

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

local function cell<T>(initial: Initial<T>, equals: Equals<T>?): Value<T>
	local initializer, value = NodeCast.split(initial)
	local class = if initializer then LAZY elseif equals ~= nil then EQUAL else CELL
	local node: Node = { version = clock.next(), value = value, first = nil, set = class.set }
	if initializer then
		node.body = initializer
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
