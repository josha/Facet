--!strict
--!native

local Graph = require "./graph"
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

local function releaseIfEmpty(self: any, producer: any)
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

local function pass(self: any)
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
				local evicted = self.evicted
				if not evicted then
					evicted = {}
					self.evicted = evicted
				end
				table.insert(evicted :: { any }, member)
			end
		end
	end

	self.live = live
end

local function run(self: any)
	if self.released then
		return
	end

	local edge = self.edge
	local producer = edge[PRODUCER]
	if self.state == CHECK then
		local refresh = producer.refresh
		if refresh then
			refresh(producer)
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
		local ok, err: any = pcall(pass, self)
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
		self.evicted = false
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

local function enqueue(self: any)
	if self.released then
		return
	end
	self.reactor:__enqueue(self)
end

local function sinkFor(
	producer: any,
	reactor: any,
	report: (err: any, member: any) -> (),
	evict: (member: any) -> ()
): any
	local sinks = producer.sinks
	if sinks == nil then
		sinks = setmetatable({}, { __mode = "k" })
		producer.sinks = sinks
	end
	local existing = sinks[reactor]
	if existing ~= nil and not existing.released then
		return existing
	end

	local self = {
		state = Graph.CLEAN,
		dependencies = {},
		reads = 0,
		released = false,
		queued = false,
		reactor = reactor,
		members = {},

		at = 0,
		live = 0,
		evicted = false :: any,
		report = report,
		evict = evict,
		run = run,

		enqueue = reactor.__enqueueConsumer or enqueue,

		enqueueSettle = reactor.__enqueueSettleConsumer or false,
		edge = nil :: any,
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
