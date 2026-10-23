--!strict

local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Cell = require "../reactive/cell"
local Reactor = require "../reactive/reactor"

local sharedResource = require "../async/shared"

export type Options = { frame: boolean?, poll: boolean?, styled: boolean? }
type Entry = { live: boolean, read: () -> unknown, value: Types.Cell<unknown> }

return function(host: Host.Host, ownerOf: (string) -> Owner.Owner, reactor: Reactor.Reactor)
	local entries: { [Host.Node]: { [string]: sharedResource.Acquire<Types.Cell<unknown>> } } = {}
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
	local function schedule()
		if stop then
			return
		end
		local frames = assert(host.frames, "Compose frame observation requires host.frames")
		stop = frames.onFrame(function()
			local queued = pending
			pending = {}
			for entry in polling do
				queued[entry] = true
			end
			local snapshots: { { entry: Entry, value: unknown } } = {}
			local failures: { unknown } = {}
			for entry in queued do
				if entry.live then
					local ok, value = pcall(entry.read)
					if ok then
						table.insert(snapshots, { entry = entry, value = value })
					else
						table.insert(failures, value)
					end
				end
			end
			reactor:batch(function()
				for _, snapshot in snapshots do
					if snapshot.entry.live then
						snapshot.entry.value:set(snapshot.value)
					end
				end
			end)
			idle()
			Owner.raiseAll(failures)
		end)
	end
	return function(node: Host.Node, property: string, options: Options?): Types.Readable<unknown>
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
		local properties = entries[node]
		if properties == nil then
			properties = {}
			entries[node] = properties
		end
		local acquire: sharedResource.Acquire<Types.Cell<unknown>>? = properties[key]
		if acquire == nil then
			acquire = sharedResource(function(): (Types.Cell<unknown>, (() -> ())?)
				local owner = ownerOf "observe"
				owner.own(function()
					properties[key] = nil
					if next(properties) == nil then
						entries[node] = nil
					end
				end)
				local value = Cell.cell(read(node, property))
				if framed then
					local entry: Entry = {
						live = true,
						read = function()
							return read(node, property)
						end,
						value = value,
					}
					owner.own(function()
						entry.live = false
						pending[entry], polling[entry] = nil, nil
						idle()
					end)
					local release = subscribe(node, property, function()
						if entry.live then
							pending[entry] = true
							schedule()
						end
					end)
					owner.own(release)
					pending[entry] = true
					if poll then
						polling[entry] = true
					end
					schedule()
					return value, nil
				end
				return value, subscribe(node, property, function()
					value:set(read(node, property))
				end)
			end)
			properties[key] = assert(acquire)
		end
		return assert(acquire)()
	end
end
