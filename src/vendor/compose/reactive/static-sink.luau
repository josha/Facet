--!strict
--!native

local Graph = require "./graph"
local profile = require "./profile"
local stats = require "./stats"
local statsOn = stats.state
local OBSERVED = Graph.OBSERVED
local CLEAN = Graph.CLEAN
local CHECK = Graph.CHECK

local function releaseIfEmpty(self: any)
	if self.released or self.live > 0 then
		return
	end
	self.queued = false
	self.only = false
	Graph.release(self)
	local sinks = self.producer.staticSinks
	if sinks ~= nil then
		sinks[self.reactor] = nil
	end
	table.clear(self.members)
end

local function runMembers(self: any, producer: any)
	local members = self.members

	local failures: { string }? = nil
	local write = 0
	for read = 1, #members do
		local member = members[read]
		if not member.released then
			write += 1
			members[write] = member
			if statsOn.enabled then
				stats.bump "watchRuns"
				profile.enterRun(member)
			end
			local ok, err: any = pcall(member.body, producer.value)
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

local function run(self: any)
	if self.released then
		return
	end

	local producer = self.producer
	local edge = self.edge
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

local function runOnCell(self: any)
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

local function enqueue(self: any)
	if not self.released then
		self.reactor:__enqueue(self)
	end
end

local function sinkFor(producer: any, reactor: any): any
	local refresh = producer.refresh
	if refresh then
		refresh(producer)
	end
	local sinks = producer.staticSinks
	if sinks == nil then
		sinks = setmetatable({}, { __mode = "k" })
		producer.staticSinks = sinks
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
		producer = producer,
		members = {},
		live = 0,
		only = false :: any,

		run = if producer.derived == false then runOnCell else run,

		enqueue = reactor.__enqueueConsumer or enqueue,

		enqueueSettle = reactor.__enqueueSettleConsumer or false,
		edge = nil :: any,
	}
	self.edge = Graph.attach(producer, self)
	self.dependencies[1] = self.edge
	sinks[reactor] = self
	return self
end

local function recount(sink: any)
	if sink.live == 1 then
		for _, member in sink.members do
			if not member.released then
				sink.only = member
				return
			end
		end
	end
	sink.only = false
end

local function add(producer: any, reactor: any, body: (value: any) -> ()): any
	local sink = sinkFor(producer, reactor)
	local member = { released = false, body = body, sink = sink }
	table.insert(sink.members, member)
	sink.live += 1
	sink.only = if sink.live == 1 then member else false

	if statsOn.enabled then
		profile.born(member)
		stats.bump "watchRuns"
		profile.enterRun(member)
	end
	local ok, err: any = pcall(body, producer.value)
	if not ok then
		member.released = true
		sink.live -= 1
		recount(sink)
		releaseIfEmpty(sink)
		error(err, 0)
	end
	return member
end

local function release(member: any)
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
