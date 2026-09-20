--!strict
--!native

local Graph = require "./graph"
local Types = require "./types"
local clock = require "./clock"
local stats = require "./stats"
local statsOn = stats.state
local EDGE_CONSUMER = Graph.CONSUMER
local EDGE_NEXT = Graph.NEXT
local CLEAN = Graph.CLEAN
local CHECK = Graph.CHECK
local DIRTY = Graph.DIRTY
local markStale = Graph.markStale
local settleTouched = Graph.settleTouched
local clockState = clock.state
local profile = require "./profile"
local userSpace = require "./userSpace"

type Cell<T> = Types.Cell<T>
type Equals<T> = Types.Equals<T>
type Initial<T> = Types.Initial<T>

local function defaultEquals<T>(current: T, incoming: T): boolean
	return current == incoming
end

local CELL = {}
CELL.__index = CELL
CELL.derived = false

local READABLE = CELL

local UNSET = newproxy(false)

local validationState = userSpace.state

local function cell<T>(initial: Initial<T>, equals: Equals<T>?): Cell<T>
	local self = setmetatable({
		version = 0,
		subscribers = false :: any,
		lastSubscriber = false :: any,
		refresh = CELL.refresh :: any,
		set = CELL.set,
		value = UNSET :: any,
		initial = initial,
		compare = (equals or false) :: any,
	}, CELL)

	self.subscribers = nil
	self.lastSubscriber = nil
	return (self :: any) :: Cell<T>
end

local function start(self: any)
	local initial = self.initial
	self.initial = nil
	self.value = if type(initial) == "function" then userSpace.call(initial) else initial
	self.version = clock.next()

	self.refresh = false
end

function CELL.refresh(self: any)
	if self.value == UNSET then
		start(self)
	end
end

function CELL.peek(self: any): any
	if self.value == UNSET then
		start(self)
	end
	return self.value
end

function CELL.set(self: any, incoming: any)
	local current = self.value
	if current == UNSET then
		start(self)
		current = self.value
	end

	local compare = self.compare
	local unchanged = if not compare and not validationState.validating
		then current == incoming
		else userSpace.call(compare or defaultEquals, current, incoming)

	local statsEnabled = statsOn.enabled
	if unchanged then
		if statsEnabled then
			stats.bump "cellWritesSuppressed"
			profile.write(self, true)
		end
		return
	end

	self.value = incoming
	local version = clockState.now + 1
	clockState.now = version
	self.version = version
	if statsEnabled then
		stats.bump "cellWrites"
		Graph.countNotification(self)
		profile.write(self, false)
	end

	local edge = self.subscribers
	if edge == nil then
		return
	end

	if edge[EDGE_NEXT] == nil and not statsEnabled then
		local consumer = edge[EDGE_CONSUMER]
		local state = consumer.state
		if state == CLEAN or consumer.retry then
			consumer.retry = false
			consumer.state = DIRTY

			local settleQueue = consumer.enqueueSettle
			if settleQueue then
				settleQueue(consumer)
				return
			end
			if consumer.derived then
				markStale(consumer :: any, CHECK)
			end

			local enqueue = consumer.enqueue
			if enqueue then
				enqueue(consumer)
			end
			settleTouched()
		elseif state == CHECK then
			consumer.state = DIRTY
		end
		return
	end

	Graph.markStale(self, Graph.DIRTY)
	Graph.settleTouched()
end

function CELL.update(self: any, change: (any) -> any)
	if self.value == UNSET then
		start(self)
	end
	CELL.set(self, userSpace.call(change, self.value))
end

CELL.__isComposeReadable = true

local SHARED = table.clone(CELL)
SHARED.__index = SHARED
SHARED.shared = true

local function sharedCell<T>(initial: Initial<T>, equals: Equals<T>?): Cell<T>
	local self = cell(initial, equals)
	setmetatable(self :: any, SHARED)
	return self
end

local function isReadable(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local meta = getmetatable(value :: any)
	return meta ~= nil and rawget(meta :: any, "__isComposeReadable") == true
end

return {
	cell = cell,
	sharedCell = sharedCell,
	defaultEquals = defaultEquals,
	isReadable = isReadable,
	READABLE = READABLE,
}
