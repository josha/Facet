--!strict
--!native

local Dynamic = require "../dynamic"
local Evaluation = require "./evaluation"
local Graph = require "./graph"
local Nodes = require "./node"
local Reactor = require "./reactor"
local Types = require "./types"
local clockState = Graph.clock
local stats = Evaluation.stats
local statsOn = stats.state
local validationState = Evaluation.validation

type Node = Types.Node
type Value<T> = Types.Value<T>
type Equals<T> = Types.Equals<T>

local DIRTY = Graph.DIRTY
local CHECK = Graph.CHECK

local function suppress(self: Node)
	if statsOn.enabled then
		stats.bump "cellWritesSuppressed"
		statsOn.recorder.write(self, true)
	end
end

local function write(self: Node)
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
		local consumer: Node? = first[2]
		if consumer == nil then
			if rawget(first, 4) == nil or first.listenerGroup then
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
		elseif rawget(first, 4) == nil then
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

local function compare(equals: unknown, current: unknown, incoming: unknown): boolean
	local result = Dynamic.invoke(equals, current, incoming)
	assert(type(result) == "boolean", "Compose equality must return a boolean")
	return result
end

local CELL = {}
CELL.__index = CELL
CELL.version = 0

function CELL.peek<T>(self: Types.Cache<T>): T
	local cached = self.cache
	if cached == nil then
		return Nodes.readCached(self)
	end
	return cached.value
end

local function plainSet(self: Node, incoming: unknown)
	CELL.set(self, incoming)
end

local function coalesced(self: Node, incoming: unknown)
	if self.coalescing == nil then
		plainSet(self, incoming)
	elseif self.value ~= incoming then
		self.value = incoming
	end
end

local function coalescedNumber(self: Node, incoming: unknown)
	if self.set ~= coalescedNumber then
		plainSet(self, incoming)
		return
	end
	self.value = incoming
	if type(incoming) ~= "number" then
		Dynamic.write(self, "set", coalesced)
	end
end

function CELL.set<T>(self: Value<T>, incoming: T)
	local node: Node = self
	local current = node.value
	local unchanged = if validationState.validating
		then Evaluation.call(same, current, incoming)
		else current == incoming
	if unchanged then
		if statsOn.enabled then
			suppress(node)
		end
		return
	end
	node.value = incoming
	if node.first == nil and not statsOn.enabled then
		local version = clockState.now + 1
		clockState.now = version
		node.version = version
		return
	end
	local first = node.first
	local consumer: Node? = if first ~= nil then first[2] else nil
	local state = if consumer ~= nil then consumer.state else nil
	if
		state == DIRTY
		and consumer ~= nil
		and consumer.group
		and not statsOn.enabled
		and first ~= nil
		and rawget(first, 4) == nil
		and not consumer.retry
	then
		if consumer[2] == nil and consumer.queued then
			Graph.coalesce(node, consumer, if type(incoming) == "number" then coalescedNumber else coalesced)
		end
		return
	end
	local version = clockState.now + 1
	clockState.now = version
	node.version = version
	if statsOn.enabled then
		stats.bump "cellWrites"
		Graph.countNotification(node)
		statsOn.recorder.write(node, false)
	elseif first == nil then
		return
	else
		if consumer == nil then
			if rawget(first, 4) == nil or first.listenerGroup then
				local reactor = first.reactor
				if reactor ~= nil and reactor.batching then
					if not first.queued then
						first.queued = true
						local count = reactor.count + 1
						reactor.count = count
						reactor.queue[count] = first
					elseif not validationState.validating then
						Graph.coalesce(node, first, if type(incoming) == "number" then coalescedNumber else coalesced)
					end
				else
					Reactor.runNow(first)
				end
				return
			end
		elseif rawget(first, 4) == nil then
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
	Graph.markStale(node, DIRTY)
	Graph.settleTouched()
end

local EQUAL = {}
EQUAL.__index = EQUAL
EQUAL.version = 0

function EQUAL.set<T>(self: Value<T>, incoming: T)
	local node: Node = self
	if Evaluation.call(compare, node.equals, node.value, incoming) then
		if statsOn.enabled then
			suppress(node)
		end
		return
	end
	node.value = incoming
	if node.first == nil and not statsOn.enabled then
		local version = clockState.now + 1
		clockState.now = version
		node.version = version
		return
	end
	write(node)
end

function CELL.update<T>(self: Value<T>, change: (previous: T) -> T)
	self:set(Evaluation.call(change, self:peek()))
end

function CELL.dispose<T>(_self: Value<T>) end

EQUAL.peek = CELL.peek
EQUAL.update = CELL.update
EQUAL.dispose = CELL.dispose

local LAZY = {}
LAZY.__index = LAZY
LAZY.version = 0
LAZY.update = CELL.update
LAZY.dispose = CELL.dispose

local function establish(node: Node)
	if node.cache == nil then
		Dynamic.cache(node, Evaluation.call(assert(node.initial)))
		node.initial = nil
	end
	node.refresh = nil
	setmetatable(node, if node.equals ~= nil then EQUAL else CELL)
end

function LAZY.peek<T>(self: Types.Cache<T>): T
	establish(self)
	return Nodes.readCached(self)
end

function LAZY.set<T>(self: Value<T>, incoming: T)
	establish(self)
	self:set(incoming)
end

Nodes.adopt(CELL)
Nodes.adopt(EQUAL)
Nodes.adopt(LAZY)

type CellData<T> = { value: T, cache: { read value: T }?, equals: Equals<T>? }

local function cell<T>(initial: T, equals: Equals<T>?): Value<T>
	local node: CellData<T> = { value = initial, cache = nil }
	node.cache = node
	if equals ~= nil then
		node.equals = equals
		return setmetatable(node, EQUAL)
	end
	return setmetatable(node, CELL)
end

local function lazyCell<T>(initial: () -> T, equals: Equals<T>?): Value<T>
	return setmetatable({ initial = initial, refresh = establish, equals = equals }, LAZY)
end

return {
	cell = cell,
	lazyCell = lazyCell,
	isValue = Nodes.isNode,
	asValue = Nodes.asValue,
	defaultEquals = same,
	compare = compare,
}
