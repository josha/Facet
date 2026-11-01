--!strict
--!native
local Weak = require "../weak"

local createWritten: (number, unknown?) -> { unknown } = table.create
local createPrevious: (number, Binding??) -> { Binding? } = table.create

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

local function readStatic(value: Host.PropValue): (unknown, boolean)
	if type(value) ~= "table" or Dynamic.raw(value, "composeValue") ~= "static" then
		return nil, false
	end
	return Dynamic.raw(value, "value"), true
end

type Node = Host.Node

local UNWRITTEN = newproxy(false)

local applying: { key: string? } = { key = nil }

export type Props = { [unknown]: unknown }

type Binding = { remaining: number, active: boolean, dispose: (() -> ())?, pendingKey: string?, previous: Binding? }
type Bindings = { [string]: Binding? }
type Registry = { [Node]: Bindings }

type Clear = (node: Node, key: string) -> ()
type GroupBody = (use: Types.Use) -> ...unknown

local propertyBindings: Registry = {}

local fastEdges: { [Node]: Types.Node? } = {}

Weak.keys(fastEdges)

Weak.keys(propertyBindings)
local attributeBindings: Registry = {}
Weak.keys(attributeBindings)

local function retireBinding(binding: Binding?, key: string)
	if binding == nil then
		return
	end
	if binding.pendingKey == key then
		retireBinding(binding.previous, key)
		return
	end
	binding.remaining -= 1
	if binding.remaining == 0 then
		binding.active = false
		if binding.dispose ~= nil then
			binding.dispose()
		end
	end
end

local function replace(bindings: Bindings, key: string, binding: Binding?)
	local previous = bindings[key]
	bindings[key] = binding
	if binding ~= nil then
		binding.remaining += 1
		binding.active = true
	end
	retireBinding(previous, key)
end

local function beginWrite(
	registry: Registry,
	node: Node,
	bindings: Bindings,
	key: string,
	binding: Binding,
	previous: Binding?
): boolean
	if registry[node] ~= bindings or bindings[key] ~= previous then
		return false
	end
	binding.pendingKey = key
	binding.previous = previous
	bindings[key] = binding
	return true
end

local function finishWrite(bindings: Bindings, key: string, binding: Binding, succeeded: boolean)
	local previous = binding.previous
	binding.previous = nil
	binding.pendingKey = nil
	if bindings[key] ~= binding then
		return
	end
	if succeeded then
		binding.remaining += 1
		binding.active = true
		retireBinding(previous, key)
	else
		bindings[key] = if previous ~= nil and (previous.active or previous.pendingKey == key) then previous else nil
	end
end

local function bindingFor(registry: Registry, node: Node): (Bindings, Binding)
	local bindings = registry[node]
	if bindings == nil then
		bindings = {}
		registry[node] = bindings
	end
	return bindings, { remaining = 0, active = false }
end

local function retire(registry: Registry, node: Node, key: string)
	local bindings = registry[node]
	if bindings ~= nil then
		replace(bindings, key, nil)
		if next(bindings) == nil and registry[node] == bindings then
			registry[node] = nil
		end
	end
end

local function singleCleanup(
	registry: Registry,
	node: Node,
	bindings: Bindings,
	key: string,
	binding: Binding,
	clear: Clear
): () -> ()
	local borrowed = not Nodes.isDestructible(node)
	return function()
		binding.active = false
		if bindings[key] ~= binding then
			if next(bindings) == nil and registry[node] == bindings then
				registry[node] = nil
			end
			return
		end
		if binding.pendingKey == key then
			bindings[key] = binding.previous
			return
		end
		bindings[key] = nil
		binding.remaining = 0
		if next(bindings) == nil and registry[node] == bindings then
			registry[node] = nil
		end
		if borrowed then
			clear(node, key)
		end
	end
end

local function classify(host: Host.Host, node: Node, key: string): Host.KeyKind
	local events = host.events
	if events == nil then
		return "property"
	end
	local classifyKey = events.classifyKey
	if classifyKey == nil then
		return "property"
	end
	return classifyKey(node, key)
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
	local attach = events.attachEvent
	local callback = Dynamic.handler(handler)
	if fresh and attach ~= nil then
		attach(node, name, callback)
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

type Target = {
	registry: Registry,
	write: (Node, string, unknown) -> (),
	clear: Clear,
	host: Host.Host,
	prefix: string,
	deduplicate: boolean,
	attributeWrite: ((Node, string, unknown) -> (boolean, string?))?,
}

local function writeOnce(target: Target, node: Node, owner: Owner.Owner, key: string, value: unknown)
	local registry, write, clear = target.registry, target.write, target.clear
	local before = registry[node]
	local previous = if before ~= nil then before[key] else nil
	write(node, key, value)
	local current = registry[node]
	if (if current ~= nil then current[key] else nil) ~= previous then
		return
	end
	if Nodes.isDestructible(node) then
		retire(registry, node, key)
		return
	end
	local bindings, binding = bindingFor(registry, node)
	local cleanup = singleCleanup(registry, node, bindings, key, binding, clear)
	replace(bindings, key, binding)
	binding.dispose = Owner.own(owner, cleanup)
end

type Mapping = { source: Types.ReadOnlyValue<unknown>, transform: (unknown) -> unknown }

local mapped: { [unknown]: Mapping } = {}

Weak.keys(mapped)

local function bind(target: Target, node: Node, owner: Owner.Owner, key: string, source: Host.PropValue)
	local readable = if type(source) == "table" then cellModule.asValue(source) else nil
	local registry, write, clear = target.registry, target.write, target.clear
	local deduplicate = target.deduplicate
	local bindings, binding = bindingFor(registry, node)
	local previous = bindings[key]
	local written: unknown = UNWRITTEN
	local function publish(value: unknown)
		if written == UNWRITTEN then
			if not beginWrite(registry, node, bindings, key, binding, previous) then
				written = value
				if binding.dispose then
					binding.dispose()
				end
				return
			end
			local ok, err: unknown = pcall(write, node, key, value)
			finishWrite(bindings, key, binding, ok)
			if not ok then
				error(err, 0)
			end
		elseif not binding.active or (deduplicate and value == written) then
			return
		else
			write(node, key, value)
		end
		written = value
		if statsOn.enabled then
			statsOn.recorder.hostWrite()
		end
	end
	local cleanup = singleCleanup(registry, node, bindings, key, binding, clear)
	if statsOn.enabled then
		statsOn.recorder.naming(("%s.%s%s"):format(Host.describeNode(target.host, node), target.prefix, key))
	end
	local dispose: () -> ()
	local mapping = mapped[source]
	if mapping ~= nil then
		dispose = Owner.watchStatic(owner, mapping.source, function(value)
			if written == UNWRITTEN or binding.active then
				publish(mapping.transform(value))
			end
		end, cleanup)
	elseif type(source) == "function" then
		dispose = Owner.watchTerminal(owner, function(use)
			if written == UNWRITTEN or binding.active then
				publish(source(use))
			end
		end, cleanup)
	else
		dispose = Owner.watchStatic(owner, assert(readable), publish, cleanup)
	end
	binding.dispose = dispose
	if statsOn.enabled then
		statsOn.recorder.naming(nil)
	end
	previous = nil
	if binding.remaining == 0 then
		dispose()
	end
end

local function bindGroup(host: Host.Host, node: Node, owner: Owner.Owner, names: { string }, source: Host.PropValue)
	local render = host.render
	local count = #names
	for index = 1, count do
		local name = names[index]
		if classify(host, node, name) == "event" then
			return Diagnostics.raise(
				"props/group-names-an-event",
				"a group named a key the host classifies as an event",
				{
					event = name,
					node = Host.describeNode(host, node),
					contract = "a group writes properties; events are subscribed with event(name)",
					fix = ("move %q out of the group and onto its own [event(%q)] key"):format(name, name),
				}
			)
		end
	end
	if type(source) ~= "function" then
		return Diagnostics.raise("props/group-needs-a-body", "a group key was given something that is not a body", {
			properties = table.concat(names, ", "),
			node = Host.describeNode(host, node),
			actual = Diagnostics.describe(source),
			expected = "a function taking `use` and returning one value per name",
		})
	end

	local body = source
	local written: { unknown } = createWritten(count, UNWRITTEN)
	local bindings, binding = bindingFor(propertyBindings, node)
	local previous: { Binding? } = createPrevious(count)
	for index, name in names do
		previous[index] = bindings[name]
	end
	local borrowed = not Nodes.isDestructible(node)
	local function cleanup()
		binding.active = false
		local failure: unknown = nil
		for _, name in names do
			if bindings[name] == binding then
				if binding.pendingKey == name then
					bindings[name] = binding.previous
					continue
				end
				bindings[name] = nil
				if borrowed then
					local ok, err: unknown = pcall(render.clearProperty, node, name)
					if not ok and failure == nil then
						failure = err
					end
				end
			end
		end
		binding.remaining = 0
		if next(bindings) == nil and propertyBindings[node] == bindings then
			propertyBindings[node] = nil
		end
		if failure ~= nil then
			error(failure, 0)
		end
	end
	if statsOn.enabled then
		statsOn.recorder.naming(("%s.{%s}"):format(Host.describeNode(host, node), table.concat(names, ",")))
	end
	local dispose = Owner.watch(owner, function(use)
		local values = table.pack(body(use))
		if values.n ~= count then
			return Diagnostics.raise("props/group-arity", "a group body returned the wrong number of values", {
				properties = table.concat(names, ", "),
				node = Host.describeNode(host, node),
				actual = ("%d value(s)"):format(values.n),
				expected = ("%d, one per name, in order"):format(count),
			})
		end
		for index = 1, count do
			local name = names[index]
			local initial = written[index] == UNWRITTEN
			local value = values[index]
			if initial then
				if not beginWrite(propertyBindings, node, bindings, name, binding, previous[index]) then
					written[index] = value
					continue
				end
				local ok, err: unknown = pcall(render.setProperty, node, name, value)
				finishWrite(bindings, name, binding, ok)
				if not ok then
					error(err, 0)
				end
			elseif bindings[name] == binding and value ~= written[index] then
				render.setProperty(node, name, value)
			else
				continue
			end
			written[index] = value
			if statsOn.enabled then
				statsOn.recorder.hostWrite()
			end
		end
		if binding.remaining == 0 and binding.dispose ~= nil then
			binding.dispose()
		end
	end, nil, cleanup)
	binding.dispose = dispose
	if statsOn.enabled then
		statsOn.recorder.naming(nil)
	end
	table.clear(previous)
	for index = 1, count do
		if written[index] == UNWRITTEN then
			written[index] = nil
		end
	end
	if binding.remaining == 0 then
		dispose()
	end
end

local ATTRIBUTES = "Attributes"

type SetAttribute = (node: Node, name: string, value: unknown) -> (boolean, string?)

local function attributeWriter(host: Host.Host, node: Node): SetAttribute
	local setAttribute = host.render.setAttribute
	if setAttribute == nil then
		return Diagnostics.raise("host/no-attributes", ("host %q cannot store attributes"):format(host.name), {
			key = ATTRIBUTES,
			node = Host.describeNode(host, node),
			contract = "an Attributes prop requires the render.setAttribute capability",
			fix = "implement host.render.setAttribute, or write the value under an ordinary property key",
		})
	end
	return setAttribute
end

local function writeAttribute(host: Host.Host, node: Node, write: SetAttribute, name: string, value: unknown)
	local accepted, reason = write(node, name, value)
	if accepted then
		return
	end
	return Diagnostics.raise("props/attribute-value", "the host refused an attribute value", {
		key = ("%s.%s"):format(ATTRIBUTES, name),
		node = Host.describeNode(host, node),
		actual = Diagnostics.describe(value),
		expected = "a value this host stores as an attribute",
		detail = if reason ~= nil then reason else "the host gave no reason",
		contract = "an attribute value must be one the host's attribute store accepts; nil clears it",
		fix = ("write a value the host accepts, or move %q onto an ordinary property key"):format(name),
	})
end

local attributeTargets: { [Host.Host]: Target } = {}

Weak.entries(attributeTargets)

local function attributeTarget(host: Host.Host, node: Node): Target
	local method = attributeWriter(host, node)
	local cached = attributeTargets[host]
	if cached ~= nil and cached.attributeWrite == method then
		return cached
	end
	local function write(target: Node, name: string, value: unknown)
		writeAttribute(host, target, method, name, value)
	end
	local target: Target = {
		registry = attributeBindings,
		write = write,
		clear = function(target: Node, name: string)
			method(target, name, nil)
		end,
		host = host,
		prefix = "Attributes.",
		deduplicate = true,
		attributeWrite = method,
	}
	attributeTargets[host] = target
	return target
end

local function refuseNodeAttribute(host: Host.Host, node: Node, name: string, value: unknown)
	if not Nodes.isDestructible(value) then
		return
	end
	return Diagnostics.raise("props/child-under-attribute", "a node was given as the value of an attribute", {
		key = ("%s.%s"):format(ATTRIBUTES, name),
		node = Host.describeNode(host, node),
		actual = ("a node this runtime will destroy: %s"):format(Host.describeNode(host, value)),
		expected = "a value the host can store in an attribute",
		contract = "an attribute holds data; children live in the array part of the props table",
		fix = ("drop the attribute -- write the node as a positional child rather than as %s.%s"):format(
			ATTRIBUTES,
			name
		),
	})
end

local function applyAttributes(host: Host.Host, node: Node, owner: Owner.Owner, source: unknown)
	if type(source) ~= "table" then
		return Diagnostics.raise(
			"props/attributes-not-a-table",
			"the Attributes key was given something that is not a table",
			{
				key = ATTRIBUTES,
				node = Host.describeNode(host, node),
				actual = Diagnostics.describe(source),
				expected = "a table of attribute name to value",
				contract = "Attributes is a reserved key naming a table of attributes to write",
				fix = 'write Attributes = { Tier = 3 }, or [Compose.property "Attributes"] = value for a real property',
			}
		)
	end

	local table_: { [string]: Host.PropValue } = {}
	local names: { string } = {}
	for name, value in Dynamic.props(source) do
		if type(name) ~= "string" or name == "" then
			return Diagnostics.raise("props/attribute-name", "an attribute name is not a non-empty string", {
				key = ATTRIBUTES,
				node = Host.describeNode(host, node),
				actual = Diagnostics.describe(name),
				expected = "a non-empty string",
				contract = "every key of an Attributes table names one attribute",
				fix = "give the attribute a name the host can address",
			})
		end
		table_[name] = value
		table.insert(names, name)
	end

	table.sort(names)

	local target = attributeTarget(host, node)
	for _, name in names do
		applying.key = ("%s.%s"):format(ATTRIBUTES, name)
		local value = table_[name]

		local literal, isStatic = readStatic(value)
		if isStatic then
			writeOnce(target, node, owner, name, literal)
			continue
		end

		if cellModule.isValue(value) or type(value) == "function" then
			bind(target, node, owner, name, value)
			continue
		end

		refuseNodeAttribute(host, node, name, value)
		writeOnce(target, node, owner, name, value)
	end
end

local function map<T, R>(source: Types.ReadOnlyValue<T>, transform: (T) -> R): Types.Body<R>
	local function body(use: Types.Use): R
		return transform(use(source))
	end
	mapped[body] = {
		source = source,
		transform = function(_value: unknown): unknown
			return transform(source:peek())
		end,
	}
	return body
end

local propertyTargets: { [Host.Host]: Target } = {}

Weak.entries(propertyTargets)

local function propertyTarget(host: Host.Host): Target
	local render = host.render
	local cached = propertyTargets[host]
	if cached ~= nil and cached.write == render.setProperty and cached.clear == render.clearProperty then
		return cached
	end
	local target: Target = {
		registry = propertyBindings,
		write = render.setProperty,
		clear = render.clearProperty,
		host = host,
		prefix = "",
		deduplicate = false,
	}
	propertyTargets[host] = target
	return target
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

local function retireFast(node: Node, key: string)
	local edge = fastEdges[node]
	local previous: Types.Node? = nil
	while edge ~= nil do
		local following = edge.fastNext
		if edge.fastKey == key then
			if previous == nil then
				fastEdges[node] = following
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
					bindGroup(host, node, owner, assert(markerNames), value)
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
					subscribe(host, node, owner, markerName, value, fresh)
				elseif type(value) == "function" or cellModule.isValue(value) then
					bind(propertyTarget(host), node, owner, markerName, value)
				else
					refuseNodeValue(host, node, markerName, value)
					writeOnce(propertyTarget(host), node, owner, markerName, value)
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
			applyAttributes(host, node, owner, value)
			continue
		end

		applying.key = name

		if type(value) == "table" then
			if Dynamic.raw(value, "composeValue") == "static" then
				local literal = Dynamic.raw(value, "value")
				if fresh then
					write(node, name, literal)
				else
					writeOnce(propertyTarget(host), node, owner, name, literal)
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
					bind(propertyTarget(host), node, owner, name, value)
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
				bind(propertyTarget(host), node, owner, name, value)
			end
			continue
		elseif type(value) == "userdata" then
			refuseNodeValue(host, node, name, value)
		end

		if fresh then
			write(node, name, value)
		else
			writeOnce(propertyTarget(host), node, owner, name, value)
		end
	end
end

local function forget(node: Node)
	fastEdges[node] = nil
end

return {
	event = event,
	group = group,
	property = property,
	static = static,
	applying = applying,
	apply = apply,
	forget = forget,
	map = map,
}
