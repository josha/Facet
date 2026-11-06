--!strict
--!native
local Weak = require "../weak"

local Diagnostics = require "../diagnostics"
local Dynamic = require "../dynamic"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local ReactiveNodes = require "../reactive/node"
local cellModule = require "../reactive/cell"
local stats = require("../reactive/evaluation").stats
local statsOn = stats.state
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Watch = require "../reactive/watch"

local freeze: ({}) -> {} = table.freeze

local createCopied: (number, string?) -> { string } = table.create

export type EventKey = Host.EventKey

export type PropertyKey = Host.PropertyKey

export type GroupKey = Host.GroupKey

export type StaticValue = Host.StaticValue

local eventKeys: { [string]: EventKey } = {}
local propertyKeys: { [string]: PropertyKey } = {}

local function event(name: string): EventKey
	local existing = eventKeys[name]
	if existing ~= nil then
		return existing
	end
	local created: EventKey = { composeKey = "event", name = name }
	freeze(created)
	eventKeys[name] = created
	return created
end

local function property(name: string): PropertyKey
	local existing = propertyKeys[name]
	if existing ~= nil then
		return existing
	end
	local created: PropertyKey = { composeKey = "property", name = name }
	freeze(created)
	propertyKeys[name] = created
	return created
end

local function group(names: { string }): GroupKey
	if #names == 0 then
		error("group needs at least one property name", 2)
	end
	local copied: { string } = createCopied(#names)
	for index, name in names do
		if type(name) ~= "string" then
			error(("group names must be strings; entry %d is %s"):format(index, typeof(name)), 2)
		end
		copied[index] = name
	end
	freeze(copied)
	local created: GroupKey = { composeKey = "group", names = copied }
	freeze(created)
	return created
end

local function static(value: unknown): StaticValue
	local created: StaticValue = { composeValue = "static", value = value }
	freeze(created)
	return created
end

export type MarkerKind = "event" | "property" | "group"

local function readKey(key: Host.PropKey): (MarkerKind?, string, { string }?)
	if type(key) ~= "table" then
		return nil, "", nil
	end
	local kind = Dynamic.raw(key, "composeKey")
	if kind == "event" then
		return "event", tostring(Dynamic.raw(key, "name")), nil
	elseif kind == "property" then
		return "property", tostring(Dynamic.raw(key, "name")), nil
	elseif kind == "group" then
		local names = key.names
		if names ~= nil then
			return "group", table.concat(names, "+"), names
		end
	end
	return nil, "", nil
end

type Node = Host.Node

local State = require "./props-state"
local UNWRITTEN = State.unwritten
local mapped = State.mapped
local bindingsModule: typeof(require "./bindings")? = nil
local fastEdges: { [Node]: Types.Node? } = {}
local fastCount = 0
local fastPeak = 0
Weak.keys(fastEdges)

local attached: { [Node]: unknown } = {}
local attachedMany: { [Node]: { unknown } } = {}
Weak.keys(attached)
Weak.keys(attachedMany)
local ATTRIBUTES = "Attributes"

local applying = State.applying

export type Props = { [unknown]: unknown }

local classify = Host.classifyKey

local function remember(node: Node, connection: unknown)
	local many = attachedMany[node]
	if many ~= nil then
		table.insert(many, connection)
		return
	end
	local single = attached[node]
	if single == nil then
		attached[node] = connection
		return
	end
	attached[node] = nil
	attachedMany[node] = { single, connection }
end

local function detach(host: Host.Host, node: Node)
	local single, many = attached[node], attachedMany[node]
	if single == nil and many == nil then
		return
	end
	attached[node] = nil
	attachedMany[node] = nil
	local events = host.events
	local release = if events ~= nil then events.detachEvent else nil
	if release == nil then
		return
	end
	if single ~= nil then
		release(single)
	end
	if many ~= nil then
		for _, connection in many do
			release(connection)
		end
	end
end

local function subscribe(
	host: Host.Host,
	node: Node,
	owner: Owner.Owner,
	name: string,
	handler: Host.PropFunction,
	fresh: boolean?
)
	local events = host.events
	if events == nil then
		return Diagnostics.raise("host/no-events", ("host %q cannot subscribe to events"):format(host.name), {
			event = name,
			node = Host.describeNode(host, node),
			contract = "subscribing requires the host events capability",
			fix = "implement host.events.connectEvent, or stop passing event keys to this host",
		})
	end
	local callback = Dynamic.handler(handler)
	local attach = events.attachEvent
	if fresh and attach ~= nil and events.detachEvent ~= nil then
		remember(node, attach(node, name, callback))
		return
	end
	Owner.adopt(owner, events.connectEvent(node, name, callback))
end

local function refuseNodeValue(host: Host.Host, node: Node, key: string, value: unknown)
	if not Nodes.isDestructible(value) then
		return
	end
	return Diagnostics.raise("props/child-under-string-key", "a node was given as the value of a property", {
		key = key,
		node = Host.describeNode(host, node),
		actual = ("a node this runtime will destroy: %s"):format(Host.describeNode(host, value)),
		expected = "a value the host can store in a property",
		contract = "a string key names a property to write; children live in the array part of the props table",
		fix = ("drop the key -- write the node as a positional child rather than as %s = ...; "):format(key)
			.. ("if this host really does take a node there, say so with %s = static(node)"):format(key),
	})
end

local function map<T, R>(source: Types.ReadOnlyValue<T>, transform: (T) -> R): Types.Body<R>
	local function body(use: Types.Use): R
		return transform(use(source))
	end
	mapped[body] = {
		source = source,
		transform = function(_value: unknown): unknown
			local cached = source.cache
			return transform(if cached ~= nil then cached.value else source:peek())
		end,
	}
	return body
end

type Listener = (value: unknown, edge: Types.Node?) -> ()

local propertyListeners: { [(Node, string, unknown) -> ()]: Listener } = {}

Weak.entries(propertyListeners)

local function propertyListener(write: (Node, string, unknown) -> ()): Listener
	local cached = propertyListeners[write]
	if cached ~= nil then
		return cached
	end
	local function listener(value: unknown, edge: Types.Node?)
		if edge == nil then
			return
		end
		local subject, key = edge.subject, edge.fastKey
		if subject ~= nil and key ~= nil then
			write(subject, key, value)
		end
	end
	propertyListeners[write] = listener
	return listener
end

local mappedListeners: { [(Node, string, unknown) -> ()]: Listener } = {}

Weak.entries(mappedListeners)

local mappedReads: { [Listener]: ((Node, string) -> unknown)? } = {}

Weak.keys(mappedReads)

local function mappedListener(write: (Node, string, unknown) -> (), liveRead: ((Node, string) -> unknown)?): Listener
	local cached = mappedListeners[write]
	if cached ~= nil and mappedReads[cached] == liveRead then
		return cached
	end
	local function listener(raw: unknown, edge: Types.Node?)
		if edge == nil then
			return
		end
		local node, name, transform = edge.subject, edge.fastKey, edge.transform
		if node == nil or name == nil or transform == nil then
			return
		end
		local current = transform(raw)
		local written = edge.written
		if written ~= UNWRITTEN and current == written and liveRead ~= nil then
			local read, live = pcall(liveRead, node, name)
			if read and live == current then
				return
			end
		end
		edge.written = current
		write(node, name, current)
	end
	mappedListeners[write] = listener
	mappedReads[listener] = liveRead
	return listener
end

local function forget(node: Node)
	attached[node] = nil
	attachedMany[node] = nil
	if fastEdges[node] ~= nil then
		fastEdges[node] = nil
		fastCount -= 1
		if fastCount * 4 <= fastPeak then
			local compacted: { [Node]: Types.Node? } = {}
			for target, edge in fastEdges do
				compacted[target] = edge
			end
			Weak.keys(compacted)
			fastEdges = compacted
			fastPeak = fastCount
		end
	end
end

local function retireFast(node: Node, key: string)
	local edge = fastEdges[node]
	local previous: Types.Node? = nil
	while edge ~= nil do
		local following = edge.fastNext
		if edge.fastKey == key then
			if previous == nil then
				if following == nil then
					forget(node)
				else
					fastEdges[node] = following
				end
			else
				previous.fastNext = following
			end
			Watch.releaseEdge(edge)
		else
			previous = edge
		end
		edge = following
	end
end

local function appendFast(node: Node, edge: Types.Node)
	local previous = fastEdges[node]
	if previous ~= nil then
		edge.fastNext = previous
	else
		fastCount += 1
		fastPeak = math.max(fastPeak, fastCount)
	end
	fastEdges[node] = edge
end

local function bindFunction(
	host: Host.Host,
	node: Node,
	owner: Owner.Owner,
	name: string,
	value: Host.PropValue,
	write: (Node, string, unknown) -> ()
)
	local observation = host.observation
	local liveRead = if observation then observation.readProperty else nil
	local mapping = mapped[value]
	if mapping ~= nil and owner.boundary == nil then
		local edge = Owner.listenHeld(
			owner,
			mapping.source,
			mappedListener(write, liveRead),
			node,
			name,
			mapping.transform,
			UNWRITTEN
		)
		appendFast(node, edge)
		return
	end
	local readable = if type(value) == "table" then cellModule.asValue(value) else nil
	local source: Host.PropFunction
	if readable ~= nil then
		function source(use: Types.Use): unknown
			return use(readable)
		end
	elseif type(value) == "function" then
		source = value
	else
		return
	end
	local written: unknown = UNWRITTEN
	local watcher = Owner.effectHeld(owner, function(use: Types.Use)
		local current = source(use)
		if written ~= UNWRITTEN and current == written and liveRead ~= nil then
			local read, live = pcall(liveRead, node, name)
			if read and live == current then
				return
			end
		end
		written = current
		write(node, name, current)
	end)
	if watcher == nil then
		return
	end
	watcher.fastKey = name
	appendFast(node, watcher)
end

local function apply(host: Host.Host, node: Node, source: unknown, owner: Owner.Owner, created: boolean?)
	assert(type(source) == "table")
	local props = Dynamic.props(source)
	local fresh = created == true and not statsOn.enabled and not owner.disposed
	local write = host.render.setProperty
	local replacing = not fresh and fastEdges[node] ~= nil
	local length = #props

	for key, value in props do
		if type(key) ~= "string" then
			if type(key) == "number" and key >= 1 and key <= length and key % 1 == 0 then
				continue
			end

			local markerKind, markerName, markerNames = readKey(key)
			if markerKind ~= nil then
				applying.key = markerName
				if replacing then
					if markerKind == "group" then
						for _, name in assert(markerNames) do
							retireFast(node, name)
						end
					else
						retireFast(node, markerName)
					end
				end
				if markerKind == "group" then
					local loaded = bindingsModule or require "./bindings"
					bindingsModule = loaded
					loaded.bindGroup(host, node, owner, assert(markerNames), value)
				elseif markerKind == "event" then
					if type(value) ~= "function" then
						return Diagnostics.raise(
							"props/event-needs-handler",
							"an event key was given something that is not a handler",
							{
								event = markerName,
								node = Host.describeNode(host, node),
								actual = Diagnostics.describe(value),
								expected = "a function",
							}
						)
					end
					subscribe(host, node, owner, markerName, value)
				elseif type(value) == "function" or cellModule.isValue(value) then
					local loaded = bindingsModule or require "./bindings"
					bindingsModule = loaded
					loaded.bind(loaded.propertyTarget(host), node, owner, markerName, value)
				else
					refuseNodeValue(host, node, markerName, value)
					local loaded = bindingsModule or require "./bindings"
					bindingsModule = loaded
					loaded.writeOnce(loaded.propertyTarget(host), node, owner, markerName, value)
				end
				continue
			end

			return Diagnostics.raise("props/unsupported-key", "a props key is neither a string nor a wrapped key", {
				actual = Diagnostics.describe(key),
				expected = 'a string, event("Name"), or property("Name")',
				contract = "props keys name properties and events; array entries are children",
			})
		end
		local name = key
		if replacing then
			retireFast(node, name)
		end

		if name == ATTRIBUTES then
			applying.key = ATTRIBUTES
			local loaded = bindingsModule or require "./bindings"
			bindingsModule = loaded
			loaded.applyAttributes(host, node, owner, value)
			continue
		end

		applying.key = name

		if type(value) == "table" then
			if Dynamic.raw(value, "composeValue") == "static" then
				local literal = Dynamic.raw(value, "value")
				if fresh then
					write(node, name, literal)
				else
					local loaded = bindingsModule or require "./bindings"
					bindingsModule = loaded
					loaded.writeOnce(loaded.propertyTarget(host), node, owner, name, literal)
				end
				continue
			end
			local producer = ReactiveNodes.asValueNode(value)
			if producer ~= nil then
				if fresh and owner.boundary ~= nil then
					bindFunction(host, node, owner, name, value, write)
				elseif fresh then
					local edge = Owner.listenHeld(owner, producer, propertyListener(write), node, name)
					appendFast(node, edge)
				else
					local loaded = bindingsModule or require "./bindings"
					bindingsModule = loaded
					loaded.bind(loaded.propertyTarget(host), node, owner, name, value)
				end
				continue
			end
			refuseNodeValue(host, node, name, value)
		elseif type(value) == "function" then
			if classify(host, node, name) == "event" then
				subscribe(host, node, owner, name, value, fresh)
			elseif fresh then
				bindFunction(host, node, owner, name, value, write)
			else
				local loaded = bindingsModule or require "./bindings"
				bindingsModule = loaded
				loaded.bind(loaded.propertyTarget(host), node, owner, name, value)
			end
			continue
		elseif type(value) == "userdata" then
			refuseNodeValue(host, node, name, value)
		end

		if fresh then
			write(node, name, value)
		else
			local loaded = bindingsModule or require "./bindings"
			bindingsModule = loaded
			loaded.writeOnce(loaded.propertyTarget(host), node, owner, name, value)
		end
	end
end

return {
	event = event,
	group = group,
	property = property,
	static = static,
	applying = applying,
	apply = apply,
	forget = forget,
	detach = detach,
	map = map,
}
