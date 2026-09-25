--!strict
--!native

local Graph = require "./graph"
local Weak = require "../weak"
local Types = require "./types"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local runTracked = Graph.runTracked
local PRODUCER = Graph.PRODUCER
local OBSERVED = Graph.OBSERVED
local CLEAN = Graph.CLEAN
local CHECK = Graph.CHECK

type Dispose = Types.Dispose
type Edge = Graph.Edge
type Consumer = Graph.Consumer
type Reactor = Graph.Reactor
type Scheduled = Graph.Scheduled
type Tracked = Graph.Tracked

export type Member = Tracked

export type Sink = {
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
	members: { Member },
	at: number,
	live: number,
	evicted: { Member }?,
	report: (err: unknown, member: Member) -> (),
	evict: (member: Member) -> (),
	edge: Edge,
	running: boolean?,
	membersChanged: boolean?,
}

export type Host = Graph.Producer & {
	sinks: { [Reactor]: Sink }?,
}

local UNATTACHED: Edge = {}

local function releaseIfEmpty(self: Sink, producer: Host)
	if self.released or #self.members > 0 then
		return
	end
	self.queued = false
	Graph.release(self)
	local sinks = producer.sinks
	if sinks ~= nil then
		sinks[self.reactor] = nil
	end
end

local function pass(self: Sink)
	local members = self.members
	local producer = self.edge[PRODUCER]
	local live = self.live

	for index = self.at + 1, #members do
		self.at = index
		local member = members[index]
		if not member.released then
			live += 1
			member.state = CLEAN
			if statsOn.enabled then
				stats.bump "watchRuns"
				profile.enterRun(member)
			end

			runTracked(member)

			if not member.released and (member.reads ~= 1 or member.dependencies[1][PRODUCER] ~= producer) then
				local evicted = self.evicted or {}
				self.evicted = evicted
				table.insert(evicted, member)
			end
		end
	end

	self.live = live
end

local function run(scheduled: Scheduled)
	local self = scheduled :: Sink
	if self.released then
		return
	end

	local edge = self.edge
	local producer: Host = edge[PRODUCER]
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

	local members = self.members
	local failures: { string }? = nil

	local context = Graph.evaluationContext()

	self.running = true
	self.at = 0
	self.live = 0
	while true do
		local ok, err: unknown = pcall(pass, self)
		if ok then
			break
		end
		Graph.restoreEvaluationContext(context)

		failures = failures or {}
		table.insert(failures :: { string }, tostring(err))
		if self.at >= #members then
			break
		end
	end

	self.running = false
	if self.live ~= #members or self.membersChanged then
		self.membersChanged = false
		local kept = 0
		for index = 1, #members do
			local member = members[index]
			if not member.released then
				kept += 1
				members[kept] = member
			end
		end
		for index = #members, kept + 1, -1 do
			members[index] = nil
		end
	end

	local evicted = self.evicted
	if evicted then
		self.evicted = nil
		for _, member in evicted do
			self.evict(member)
		end
	end

	releaseIfEmpty(self, producer)

	if failures ~= nil then
		local collected = failures :: { string }
		if #collected == 1 then
			error(collected[1], 0)
		end
		error(("Compose: %d fused bindings failed:\n  %s"):format(#collected, table.concat(collected, "\n  ")), 0)
	end
end

local function enqueue(consumer: Consumer)
	local self = consumer :: Sink
	if self.released then
		return
	end
	self.reactor:__enqueue(self)
end

local function sinkFor(
	producer: Host,
	reactor: Reactor,
	report: (err: unknown, member: Member) -> (),
	evict: (member: Member) -> ()
): Sink
	local sinks = producer.sinks or Weak.keys() :: { [Reactor]: Sink }
	producer.sinks = sinks
	local existing = sinks[reactor]
	if existing ~= nil and not existing.released then
		return existing
	end

	local self: Sink = {
		state = Graph.CLEAN,
		dependencies = {},
		reads = 0,
		released = false,
		queued = false,
		reactor = reactor,
		members = {},

		at = 0,
		live = 0,
		evicted = nil,
		report = report,
		evict = evict,
		run = run,

		enqueue = reactor.__enqueueConsumer or enqueue,

		enqueueSettle = reactor.__enqueueSettleConsumer or false,
		edge = UNATTACHED,
	}
	self.edge = Graph.attach(producer, self)
	self.dependencies[1] = self.edge
	sinks[reactor] = self
	return self
end

return {
	sinkFor = sinkFor,
	releaseIfEmpty = releaseIfEmpty,
}
