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
type Edge = Graph.Edge
type Consumer = Graph.Consumer
type Producer = Graph.Producer

type CellNode = {
	version: number,
	subscribers: Edge?,
	lastSubscriber: Edge?,
	refresh: ((Producer) -> ()) | false,
	derived: boolean?,
	value: unknown,
	initial: Initial<unknown>?,
	compare: Equals<unknown> | false,
}

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
	local self: CellNode = setmetatable({
		version = 0,
		subscribers = false,
		lastSubscriber = false,
		refresh = CELL.refresh,
		set = CELL.set,
		value = UNSET,
		initial = initial,
		compare = equals or false,
	}, CELL) :: any

	self.subscribers = nil
	self.lastSubscriber = nil
	return (self :: any) :: Cell<T>
end

local function start(self: CellNode)
	local initial = self.initial
	self.initial = nil
	self.value = if type(initial) == "function" then userSpace.call(initial :: () -> unknown) else initial
	self.version = clock.next()

	self.refresh = false
end

function CELL.refresh(producer: Producer)
	local self = producer :: CellNode
	if self.value == UNSET then
		start(self)
	end
end

function CELL.peek(self: CellNode): unknown
	if self.value == UNSET then
		start(self)
	end
	return self.value
end

function CELL.set(self: CellNode, incoming: unknown)
	local current = self.value
	if current == UNSET then
		start(self)
		current = self.value
	end

	local compare = self.compare
	local unchanged = if not compare and not validationState.validating
		then current == incoming
		else userSpace.call((compare or defaultEquals) :: Equals<unknown>, current, incoming)

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
		local node = edge[EDGE_CONSUMER]
		local consumer: Consumer = node
		local state = consumer.state
		if state == CLEAN or consumer.retry then
			consumer.retry = false
			consumer.state = DIRTY

			local settleQueue = consumer.enqueueSettle
			if settleQueue then
				(settleQueue :: (Consumer) -> ())(consumer)
				return
			end
			if consumer.derived then
				markStale(node, CHECK)
			end

			local enqueue = consumer.enqueue
			if enqueue then
				(enqueue :: (Consumer) -> ())(consumer)
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

function CELL.update(self: CellNode, change: (unknown) -> unknown)
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
	return meta ~= nil and rawget(meta, "__isComposeReadable") == true
end

return {
	cell = cell,
	sharedCell = sharedCell,
	defaultEquals = defaultEquals,
	isReadable = isReadable,
	READABLE = READABLE,
}
