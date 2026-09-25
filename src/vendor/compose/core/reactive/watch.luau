--!strict
--!native

local Graph = require "./graph"
local Sink = require "./sink"
local StaticSink = require "./static-sink"
local Types = require "./types"
local profile = require "./profile"
local stats = require "./stats"
local userSpace = require "./userSpace"
local validationState = userSpace.state
local statsOn = stats.state
local beginEvaluation = Graph.beginEvaluation
local finishEvaluation = Graph.finishEvaluation
local use = Graph.use

type Body = (use: Types.Use) -> ()
type Edge = Graph.Edge
type Consumer = Graph.Consumer
type Reactor = Graph.Reactor
type Scheduled = Graph.Scheduled

type Watch = {
	state: number,
	dependencies: { Edge },
	reads: number,
	enqueue: ((Consumer) -> ()) | false | nil,
	enqueueSettle: ((Consumer) -> ()) | false | nil,
	released: boolean,
	retry: boolean?,
	derived: boolean?,
	queued: boolean,
	guarded: boolean,
	run: (self: Scheduled) -> ...unknown,

	reactor: Reactor,
	body: Body,
	sink: Sink.Sink | false,
}

local WATCH = {}
WATCH.__index = WATCH

WATCH.derived = false

WATCH.sink = false

WATCH.enqueueSettle = false

WATCH.guarded = false

local FUSE_AT = 8
type Dispose = Types.Dispose

local function invoke(self: Watch): nil
	self.body(Graph.use)
	return nil
end

local function evaluate(self: Watch)
	if statsOn.enabled then
		stats.bump "watchRuns"
		profile.enterRun(self)
	end

	self.state = Graph.CLEAN
	Graph.evaluate(self, invoke, self)
end

local function evaluateQueued(self: Watch)
	if statsOn.enabled then
		stats.bump "watchRuns"
		profile.enterRun(self)
	end
	self.state = Graph.CLEAN
	local previous = beginEvaluation(self)
	if validationState.validating then
		userSpace.call(self.body, use)
	else
		self.body(use)
	end
	finishEvaluation(self, previous)
end

local function run(scheduled: Scheduled)
	local self = scheduled :: Watch
	if self.released then
		return
	end
	if self.state == Graph.CHECK then
		if self.guarded then
			local checked, moved = pcall(Graph.dependenciesMoved, self)
			if checked and not moved then
				self.state = Graph.CLEAN
				return
			end
		else
			self.retry = true
			local moved = Graph.dependenciesMoved(self)
			self.retry = false
			if not moved then
				self.state = Graph.CLEAN
				return
			end
		end
	end
	evaluateQueued(self)
end

local function enqueue(consumer: Consumer)
	local self = consumer :: Watch
	self.reactor.__enqueueConsumer(self)
end

local function create(reactor: Reactor, body: Body): Watch
	return setmetatable({
		state = Graph.DIRTY,
		dependencies = {},
		reads = 0,
		reactor = reactor,
		body = body,
		queued = false,
		released = false,
	}, WATCH) :: any
end

local function start(self: Watch, label: string?): Dispose
	if statsOn.enabled then
		profile.born(self, label)
	end

	local ok, err: unknown = pcall(evaluate, self)
	if not ok then
		Graph.release(self)
		error(err, 0)
	end

	return function()
		if self.released then
			return
		end
		Graph.release(self)
		self.queued = false
	end
end

local function watch(reactor: Reactor, body: Body, label: string?): Dispose
	return start(create(reactor, body), label)
end

local function watchGuarded(reactor: Reactor, body: Body, label: string?): Dispose
	local self = create(reactor, body)
	self.guarded = true
	return start(self, label)
end

local function watchStatic<T>(reactor: Reactor, producer: Types.Readable<T>, body: (value: T) -> ()): Dispose
	local member = StaticSink.add((producer :: any) :: StaticSink.Host, reactor, body)
	return function()
		StaticSink.release(member)
	end
end

local function unfuse(member: Sink.Member)
	local self = member :: Watch
	local fused = self.sink
	if not fused then
		return
	end
	local sink = fused :: Sink.Sink
	local members = sink.members
	if sink.running then
		sink.membersChanged = true
	else
		for index = 1, #members do
			if members[index] == self then
				table.remove(members, index)
				break
			end
		end
	end
	local producer = sink.edge[Graph.PRODUCER]
	Sink.releaseIfEmpty(sink, producer)
	self.sink = false

	self.enqueue = nil
end

local function report(err: unknown, _member: Sink.Member): ()
	error(err, 0)
end

local function fuseIfTerminal(self: Watch)
	if self.released or self.sink then
		return
	end
	local dependencies = self.dependencies
	if #dependencies ~= 1 then
		return
	end
	local producer: Sink.Host = dependencies[1][Graph.PRODUCER]

	if producer.derived then
		return
	end
	if Graph.subscriberCount(producer) < FUSE_AT then
		return
	end
	local sink = Sink.sinkFor(producer, self.reactor, report, unfuse)
	self.sink = sink
	table.insert(sink.members, self)

	self.enqueue = false
end

local function watchTerminal(reactor: Reactor, body: Body): Dispose
	local self = create(reactor, body)

	if statsOn.enabled then
		profile.born(self)
	end

	local ok, err: unknown = pcall(evaluate, self)
	if not ok then
		Graph.release(self)
		error(err, 0)
	end
	fuseIfTerminal(self)

	return function()
		if self.released then
			return
		end
		unfuse(self)
		Graph.release(self)
		self.queued = false
	end
end

WATCH.run = run
WATCH.enqueue = enqueue

local function sample<T>(body: () -> T): T
	return Graph.untracked(body)
end

return {
	watch = watch,
	watchGuarded = watchGuarded,
	watchStatic = watchStatic,
	watchTerminal = watchTerminal,
	sample = sample,
}
