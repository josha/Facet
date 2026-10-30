--!strict

local RuntimeTypes = require "./types"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Cell = require "../reactive/cell"
local Reactor = require "../reactive/reactor"

export type Options = RuntimeTypes.ObserveOptions

local SETTLE_FRAMES = 3
type Entry = { live: boolean, read: () -> unknown, value: Types.Value<unknown>, polls: boolean, quiet: number }
type Record = {
	node: Host.Node,
	key: string,
	properties: { [string]: Record },
	value: Types.Value<unknown>,
	references: number,
	unsubscribe: Host.Unsubscribe?,
	entry: Entry?,
}

return function(host: Host.Host, ownerOf: (string) -> Owner.Owner, reactor: Reactor.Reactor)
	local entries: { [Host.Node]: { [string]: Record } } = {}
	local pending: { [Entry]: boolean } = {}
	local polling: { [Entry]: boolean } = {}
	local stop: Host.Unsubscribe? = nil
	local function idle()
		if next(pending) == nil and next(polling) == nil and stop then
			local release = stop
			stop = nil
			release()
		end
	end
	local function releaseRecord(subject: unknown)
		local record = subject :: Record
		record.references -= 1
		if record.references > 0 then
			return
		end
		local properties = record.properties
		if properties[record.key] == record then
			properties[record.key] = nil
			if next(properties) == nil and entries[record.node] == properties then
				entries[record.node] = nil
			end
		end
		local entry = record.entry
		if entry ~= nil then
			entry.live = false
			pending[entry], polling[entry] = nil, nil
			idle()
		end
		local unsubscribe = record.unsubscribe
		record.unsubscribe = nil
		if unsubscribe ~= nil then
			unsubscribe()
		end
	end
	local spare: { [Entry]: boolean } = {}
	local changed: { Entry } = {}
	local readings: { unknown } = {}
	local published = 0
	local function publish()
		local count = published
		published = 0
		for index = 1, count do
			local entry = changed[index]
			if entry.live then
				entry.value:set(readings[index])
			end
		end
		table.clear(changed)
		table.clear(readings)
	end
	local function schedule()
		if stop then
			return
		end
		local frames = assert(host.frames, "Compose frame observation requires host.frames")
		stop = frames.onFrame(function()
			local queued = pending
			pending = spare
			for entry in polling do
				queued[entry] = true
			end
			local failures: { unknown }? = nil
			local count = 0
			for entry in queued do
				if entry.live then
					local ok, value = pcall(entry.read)
					if not ok then
						local collected = failures or {}
						failures = collected
						table.insert(collected, value)
					elseif value ~= entry.value:peek() then
						entry.quiet = 0
						count += 1
						changed[count] = entry
						readings[count] = value
					elseif polling[entry] then
						entry.quiet += 1
						if entry.quiet >= SETTLE_FRAMES then
							polling[entry] = nil
						end
					end
				end
			end
			table.clear(queued)
			spare = queued
			if count > 0 then
				published = count
				Reactor.batch(reactor, publish)
			end
			idle()
			if failures ~= nil then
				Owner.raiseAll(failures)
			end
		end)
	end
	return function(node: Host.Node, property: string, options: Options?): Types.ReadOnlyValue<unknown>
		ownerOf "observe"
		local observation = assert(host.observation, "Compose observe requires host.observation")
		local styled = options ~= nil and options.styled == true
		if styled then
			assert(
				observation.readStyledProperty,
				"Compose styled observation requires host.observation.readStyledProperty"
			)
		end
		local function read(target: Host.Node, key: string): unknown
			if styled then
				return assert(observation.readStyledProperty)(target, key)
			end
			return observation.readProperty(target, key)
		end
		local subscribe: (Host.Node, string, () -> ()) -> Host.Unsubscribe = if styled
			then assert(
				observation.observeStyledProperty,
				"Compose styled observation requires host.observation.observeStyledProperty"
			)
			else observation.observeProperty
		local framed = options ~= nil and options.frame == true
		local poll = options ~= nil and options.poll == true
		assert(not poll or framed, "Compose polling observation requires frame = true")
		assert(not framed or host.frames ~= nil, "Compose frame observation requires host.frames")
		local key = property
			.. (if styled then "\0styled" else "")
			.. (if poll then "\0poll" elseif framed then "\0frame" else "")
		local owner = ownerOf "observe"
		local properties = entries[node]
		if properties == nil then
			properties = {}
			entries[node] = properties
		end
		local record = properties[key]
		if record == nil then
			local value = Cell.cell(read(node, property))
			local created: Record = {
				node = node,
				key = key,
				properties = properties,
				value = value,
				references = 0,
				unsubscribe = nil,
				entry = nil,
			}
			if framed then
				local entry: Entry = {
					live = true,
					read = function()
						return read(node, property)
					end,
					value = value,
					polls = poll,
					quiet = 0,
				}
				created.entry = entry
				created.unsubscribe = subscribe(node, property, function()
					if entry.live then
						pending[entry] = true
						if entry.polls then
							entry.quiet = 0
							polling[entry] = true
						end
						schedule()
					end
				end)
				pending[entry] = true
				if poll then
					polling[entry] = true
				end
				schedule()
			else
				created.unsubscribe = subscribe(node, property, function()
					value:set(read(node, property))
				end)
			end
			properties[key] = created
			record = created
		end
		local held = assert(record)
		held.references += 1
		Owner.holdSubject(owner, releaseRecord, held)
		return held.value
	end
end
