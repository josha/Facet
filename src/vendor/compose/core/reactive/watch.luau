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

local WATCH = {}
WATCH.__index = WATCH

WATCH.derived = false

WATCH.sink = false

WATCH.enqueueSettle = false

local FUSE_AT = 8
type Dispose = Types.Dispose

local function invoke(self: any): nil
	self.body(Graph.use)
	return nil
end

local function evaluate(self: any)
	if statsOn.enabled then
		stats.bump "watchRuns"
		profile.enterRun(self)
	end

	self.state = Graph.CLEAN
	Graph.evaluate(self, invoke, self)
end

local function evaluateQueued(self: any)
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

local function run(self: any)
	if self.released then
		return
	end
	if self.state == Graph.CHECK and not Graph.dependenciesMoved(self) then
		self.state = Graph.CLEAN
		return
	end
	evaluateQueued(self)
end

local function enqueue(self: any)
	self.reactor.__enqueueConsumer(self)
end

local function watch(reactor: any, body: Body, label: string?): Dispose
	local self = setmetatable({
		state = Graph.DIRTY,
		dependencies = {},
		reads = 0,
		reactor = reactor,
		body = body,
		queued = false,
		released = false,
	}, WATCH)

	if statsOn.enabled then
		profile.born(self, label)
	end

	local ok, err = pcall(evaluate :: any, self)
	if not ok then
		Graph.release(self :: any)
		error(err, 0)
	end

	return function()
		if self.released then
			return
		end
		Graph.release(self :: any)
		self.queued = false
	end
end

local function watchStatic(reactor: any, producer: any, body: (value: any) -> ()): Dispose
	local member = StaticSink.add(producer, reactor, body)
	return function()
		StaticSink.release(member)
	end
end

local function unfuse(self: any)
	local sink = self.sink
	if not sink then
		return
	end
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

local function report(err: any)
	error(err, 0)
end

local function fuseIfTerminal(self: any)
	if self.released or self.sink then
		return
	end
	local dependencies = self.dependencies
	if #dependencies ~= 1 then
		return
	end
	local producer = dependencies[1][Graph.PRODUCER]

	if (producer :: any).derived then
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

local function watchTerminal(reactor: any, body: Body): Dispose
	local self: any = setmetatable({
		state = Graph.DIRTY,
		dependencies = {},
		reads = 0,
		reactor = reactor,
		body = body,
		queued = false,
		released = false,
	}, WATCH)

	if statsOn.enabled then
		profile.born(self)
	end

	local ok, err = pcall(evaluate :: any, self)
	if not ok then
		Graph.release(self :: any)
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
	watchStatic = watchStatic,
	watchTerminal = watchTerminal,
	sample = sample,
}
