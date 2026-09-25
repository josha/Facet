--!strict
--!native

local Graph = require "./graph"
local Weak = require "../weak"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local OBSERVED = Graph.OBSERVED
local CLEAN = Graph.CLEAN
local CHECK = Graph.CHECK

type Edge = Graph.Edge
type Consumer = Graph.Consumer
type Reactor = Graph.Reactor
type Scheduled = Graph.Scheduled

export type Member = {
	released: boolean,
	body: (value: unknown) -> (),
	sink: StaticSink,
}

export type Host = {
	version: number,
	subscribers: Edge?,
	lastSubscriber: Edge?,
	refresh: ((Graph.Producer) -> ()) | false,
	derived: boolean?,
	value: unknown,
	staticSinks: { [Reactor]: StaticSink }?,
}

export type StaticSink = {
	state: number,
	dependencies: { Edge },
	reads: number,
	enqueue: ((Consumer) -> ()) | false | nil,
	enqueueSettle: ((Consumer) -> ()) | false | nil,
	released: boolean,
	retry: boolean?,
	derived: boolean?,
	queued: boolean,
	run: (self: Scheduled) -> ...unknown,

	reactor: Reactor,
	producer: Host,
	members: { Member },
	live: number,
	only: Member?,
	edge: Edge,
}

local UNATTACHED: Edge = {}

local function releaseIfEmpty(self: StaticSink)
	if self.released or self.live > 0 then
		return
	end
	self.queued = false
	self.only = nil
	Graph.release(self)
	local sinks = self.producer.staticSinks
	if sinks ~= nil then
		sinks[self.reactor] = nil
	end
	table.clear(self.members)
end

local function runMembers(self: StaticSink, producer: Host)
	local members = self.members

	local failures: { string }? = nil
	local write = 0
	for read = 1, #members do
		if self.released then
			break
		end
		local member = members[read]
		if not member.released then
			write += 1
			members[write] = member
			if statsOn.enabled then
				stats.bump "watchRuns"
				profile.enterRun(member)
			end
			local ok, err: unknown = pcall(member.body, producer.value)
			if not ok then
				failures = failures or {}
				table.insert(failures :: { string }, tostring(err))
			end
		end
	end
	for index = #members, write + 1, -1 do
		members[index] = nil
	end

	if failures ~= nil then
		local collected = failures :: { string }
		if #collected == 1 then
			error(collected[1], 0)
		end
		error(("Compose: %d direct bindings failed:\n  %s"):format(#collected, table.concat(collected, "\n  ")), 0)
	end
end

local function run(scheduled: Scheduled)
	local self = scheduled :: StaticSink
	if self.released then
		return
	end

	local producer = self.producer
	local edge = self.edge
	if self.state == CHECK then
		local refresh = producer.refresh
		if refresh then
			self.retry = true
			(refresh :: (Graph.Producer) -> ())(producer)
			self.retry = false
		end
		if producer.version == edge[OBSERVED] then
			self.state = CLEAN
			return
		end
	end
	self.state = CLEAN
	edge[OBSERVED] = producer.version

	local single = self.only
	if single then
		if statsOn.enabled then
			stats.bump "watchRuns"
			profile.enterRun(single)
		end
		single.body(producer.value)
		return
	end

	runMembers(self, producer)
end

local function runOnCell(scheduled: Scheduled)
	local self = scheduled :: StaticSink
	if self.released then
		return
	end
	self.state = CLEAN

	local producer = self.producer
	local single = self.only
	if single then
		if statsOn.enabled then
			stats.bump "watchRuns"
			profile.enterRun(single)
		end
		single.body(producer.value)
		return
	end

	runMembers(self, producer)
end

local function enqueue(consumer: Consumer)
	local self = consumer :: StaticSink
	if not self.released then
		self.reactor:__enqueue(self)
	end
end

local function sinkFor(producer: Host, reactor: Reactor): StaticSink
	local refresh = producer.refresh
	if refresh then
		(refresh :: (Graph.Producer) -> ())(producer)
	end
	local sinks = producer.staticSinks or Weak.keys() :: { [Reactor]: StaticSink }
	producer.staticSinks = sinks
	local existing = sinks[reactor]
	if existing ~= nil and not existing.released then
		return existing
	end

	local self: StaticSink = {
		state = Graph.CLEAN,
		dependencies = {},
		reads = 0,
		released = false,
		queued = false,
		reactor = reactor,
		producer = producer,
		members = {},
		live = 0,
		only = nil,

		run = if producer.derived == false then runOnCell else run,

		enqueue = reactor.__enqueueConsumer or enqueue,

		enqueueSettle = reactor.__enqueueSettleConsumer or false,
		edge = UNATTACHED,
	}
	self.edge = Graph.attach(producer, self)
	self.dependencies[1] = self.edge
	sinks[reactor] = self
	return self
end

local function recount(sink: StaticSink)
	if sink.live == 1 then
		local members = sink.members
		for index = 1, #members do
			local member = members[index]
			if not member.released then
				sink.only = member
				return
			end
		end
	end
	sink.only = nil
end

local function add<T>(producer: Host, reactor: Reactor, body: (value: T) -> ()): Member
	local sink = sinkFor(producer, reactor)
	local member: Member = { released = false, body = body :: (value: unknown) -> (), sink = sink }
	table.insert(sink.members, member)
	sink.live += 1
	sink.only = if sink.live == 1 then member else nil

	if statsOn.enabled then
		profile.born(member)
		stats.bump "watchRuns"
		profile.enterRun(member)
	end
	local ok, err: unknown = pcall(member.body, producer.value)
	if not ok then
		member.released = true
		sink.live -= 1
		recount(sink)
		releaseIfEmpty(sink)
		error(err, 0)
	end
	return member
end

local function release(member: Member)
	if member.released then
		return
	end
	member.released = true
	local sink = member.sink
	sink.live -= 1
	recount(sink)
	releaseIfEmpty(sink)
end

return {
	add = add,
	release = release,
}
