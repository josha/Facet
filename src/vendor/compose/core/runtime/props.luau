--!strict
--!native

local createWritten: (number, unknown?) -> { unknown } = table.create
local createPrevious: (number, Binding??) -> { Binding? } = table.create

local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Keys = require "./keys"
local Nodes = require "../ownership/nodes"
local cellModule = require "../reactive/cell"
local profile = require "../reactive/profile"
local stats = require "../reactive/stats"
local statsOn = stats.state
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Watch = require "../reactive/watch"
local Weak = require "../weak"

type Node = Host.Node

local UNWRITTEN = newproxy(false)

export type Props = { [unknown]: unknown }

type Binding = { remaining: number, active: boolean, dispose: (() -> ())?, pendingKey: string?, previous: Binding? }
type Bindings = { [string]: Binding? }
type Registry = { [Node]: Bindings }

type Clear = (node: Node, key: string, value: nil) -> ...unknown
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
			clear(node, key, nil)
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
	handler: (...unknown) -> (),
	fresh: boolean?
)
	local events = host.events
	if events == nil then
		error(
			Diagnostics.format("host/no-events", ("host %q cannot subscribe to events"):format(host.name), {
				event = name,
				node = Host.describeNode(host, node),
				contract = "subscribing requires the host events capability",
				fix = "implement host.events.connectEvent, or stop passing event keys to this host",
			}),
			0
		)
	end
	local attach = events.attachEvent
	if fresh and attach ~= nil then
		attach(node, name, handler)
		return
	end
	Owner.adopt(owner, (events).connectEvent(node, name, handler))
end

local function refuseNodeValue(host: Host.Host, node: Node, key: string, value: unknown)
	if not Nodes.isDestructible(value) then
		return
	end
	error(
		Diagnostics.format("props/child-under-string-key", "a node was given as the value of a property", {
			key = key,
			node = Host.describeNode(host, node),
			actual = ("a node this runtime will destroy: %s"):format(Host.describeNode(host, value)),
			expected = "a value the host can store in a property",
			contract = "a string key names a property to write; children live in the array part of the props table",
			fix = ("drop the key -- write the node as a positional child rather than as %s = ...; "):format(key)
				.. ("if this host really does take a node there, say so with %s = static(node)"):format(key),
		}),
		0
	)
end

type Target = {
	registry: Registry,
	write: (Node, string, unknown) -> (),
	clear: Clear,
	host: Host.Host,
	prefix: string,
	deduplicate: boolean,
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

local function bind(target: Target, node: Node, owner: Owner.Owner, key: string, source: Types.Source<unknown>)
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
			profile.hostWrite()
		end
	end
	local cleanup = singleCleanup(registry, node, bindings, key, binding, clear)
	if statsOn.enabled then
		profile.naming(("%s.%s%s"):format(Host.describeNode(target.host, node), target.prefix, key))
	end
	local dispose: () -> ()
	if type(source) == "function" then
		dispose = Owner.watchTerminal(owner, function(use)
			if written == UNWRITTEN or binding.active then
				publish(source(use))
			end
		end, cleanup)
	else
		dispose = Owner.watchStatic(owner, source, publish, cleanup)
	end
	binding.dispose = dispose
	if statsOn.enabled then
		profile.naming(nil)
	end
	previous = nil
	if binding.remaining == 0 then
		dispose()
	end
end

local function bindGroup(host: Host.Host, node: Node, owner: Owner.Owner, names: { string }, source: unknown)
	local render = host.render
	local count = #names
	for index = 1, count do
		local name = names[index]
		if classify(host, node, name) == "event" then
			error(
				Diagnostics.format(
					"props/group-names-an-event",
					"a group named a key the host classifies as an event",
					{
						event = name,
						node = Host.describeNode(host, node),
						contract = "a group writes properties; events are subscribed with event(name)",
						fix = ("move %q out of the group and onto its own [event(%q)] key"):format(name, name),
					}
				),
				0
			)
		end
	end
	if type(source) ~= "function" then
		error(
			Diagnostics.format("props/group-needs-a-body", "a group key was given something that is not a body", {
				properties = table.concat(names, ", "),
				node = Host.describeNode(host, node),
				actual = Diagnostics.describe(source),
				expected = "a function taking `use` and returning one value per name",
			}),
			0
		)
	end

	local body = source :: GroupBody
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
		profile.naming(("%s.{%s}"):format(Host.describeNode(host, node), table.concat(names, ",")))
	end
	local dispose = Owner.watch(owner, function(use)
		local values = table.pack(body(use))
		if values.n ~= count then
			error(
				Diagnostics.format("props/group-arity", "a group body returned the wrong number of values", {
					properties = table.concat(names, ", "),
					node = Host.describeNode(host, node),
					actual = ("%d value(s)"):format(values.n),
					expected = ("%d, one per name, in order"):format(count),
				}),
				0
			)
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
				profile.hostWrite()
			end
		end
		if binding.remaining == 0 and binding.dispose ~= nil then
			binding.dispose()
		end
	end, nil, cleanup)
	binding.dispose = dispose
	if statsOn.enabled then
		profile.naming(nil)
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
		error(
			Diagnostics.format("host/no-attributes", ("host %q cannot store attributes"):format(host.name), {
				key = ATTRIBUTES,
				node = Host.describeNode(host, node),
				contract = "an Attributes prop requires the render.setAttribute capability",
				fix = "implement host.render.setAttribute, or write the value under an ordinary property key",
			}),
			0
		)
	end
	return setAttribute
end

local function writeAttribute(host: Host.Host, node: Node, write: SetAttribute, name: string, value: unknown)
	local accepted, reason = write(node, name, value)
	if accepted then
		return
	end
	error(
		Diagnostics.format("props/attribute-value", "the host refused an attribute value", {
			key = ("%s.%s"):format(ATTRIBUTES, name),
			node = Host.describeNode(host, node),
			actual = Diagnostics.describe(value),
			expected = "a value this host stores as an attribute",
			detail = if reason ~= nil then reason else "the host gave no reason",
			contract = "an attribute value must be one the host's attribute store accepts; nil clears it",
			fix = ("write a value the host accepts, or move %q onto an ordinary property key"):format(name),
		}),
		0
	)
end

local function refuseNodeAttribute(host: Host.Host, node: Node, name: string, value: unknown)
	if not Nodes.isDestructible(value) then
		return
	end
	error(
		Diagnostics.format("props/child-under-attribute", "a node was given as the value of an attribute", {
			key = ("%s.%s"):format(ATTRIBUTES, name),
			node = Host.describeNode(host, node),
			actual = ("a node this runtime will destroy: %s"):format(Host.describeNode(host, value)),
			expected = "a value the host can store in an attribute",
			contract = "an attribute holds data; children live in the array part of the props table",
			fix = ("drop the attribute -- write the node as a positional child rather than as %s.%s"):format(
				ATTRIBUTES,
				name
			),
		}),
		0
	)
end

local function applyAttributes(host: Host.Host, node: Node, owner: Owner.Owner, source: unknown, onKey: (string) -> ())
	if type(source) ~= "table" then
		error(
			Diagnostics.format(
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
			),
			0
		)
	end

	local table_ = source :: { [unknown]: unknown }
	local names: { string } = {}
	for name in table_ do
		if type(name) ~= "string" or name == "" then
			error(
				Diagnostics.format("props/attribute-name", "an attribute name is not a non-empty string", {
					key = ATTRIBUTES,
					node = Host.describeNode(host, node),
					actual = Diagnostics.describe(name),
					expected = "a non-empty string",
					contract = "every key of an Attributes table names one attribute",
					fix = "give the attribute a name the host can address",
				}),
				0
			)
		end
		table.insert(names, name)
	end

	table.sort(names)

	local rawWrite = attributeWriter(host, node)
	local function write(target: Node, name: string, value: unknown)
		writeAttribute(host, target, rawWrite, name, value)
	end
	local target: Target = {
		registry = attributeBindings,
		write = write,
		clear = rawWrite,
		host = host,
		prefix = "Attributes.",
		deduplicate = true,
	}
	for _, name in names do
		onKey(("%s.%s"):format(ATTRIBUTES, name))
		local value = table_[name]

		local literal, isStatic = Keys.readStatic(value)
		if isStatic then
			writeOnce(target, node, owner, name, literal)
			continue
		end

		if cellModule.isValue(value) or type(value) == "function" then
			bind(target, node, owner, name, value :: Types.Source<unknown>)
			continue
		end

		refuseNodeAttribute(host, node, name, value)
		writeOnce(target, node, owner, name, value)
	end
end

type Connect = (Owner.Owner, (unknown) -> ()) -> Types.Node

local mapped: { [unknown]: Connect } = {}

Weak.keys(mapped)

local function map<T, R>(source: Types.ReadOnlyValue<T>, transform: (T) -> R): Types.Body<R>
	local function body(use: Types.Use): R
		return transform(use(source))
	end
	mapped[body] = function(owner: Owner.Owner, sink: (unknown) -> ()): Types.Node
		return Owner.listenHeld(owner, source, function(current: T)
			sink(transform(current))
		end)
	end
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
		clear = render.clearProperty :: Clear,
		host = host,
		prefix = "",
		deduplicate = false,
	}
	propertyTargets[host] = target
	return target
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
			Watch.releaseHeld(edge)
		else
			previous = edge
		end
		edge = following
	end
end

local function apply(
	host: Host.Host,
	node: Node,
	props: Props,
	owner: Owner.Owner,
	onKey: (string) -> (),
	created: boolean?
)
	local fresh = created == true and not statsOn.enabled and owner.boundary == nil and not owner.disposed
	local write = host.render.setProperty
	local replacing = not fresh and fastEdges[node] ~= nil
	local length = #props

	for key, value in props do
		if type(key) ~= "string" then
			if type(key) == "number" and key >= 1 and key <= length and key % 1 == 0 then
				continue
			end

			local marker = Keys.readKey(key)
			if marker ~= nil then
				onKey(marker.name)
				if replacing then
					retireFast(node, marker.name)
				end
				if marker.kind == "group" then
					bindGroup(host, node, owner, marker.names, value)
				elseif marker.kind == "event" then
					if type(value) ~= "function" then
						error(
							Diagnostics.format(
								"props/event-needs-handler",
								"an event key was given something that is not a handler",
								{
									event = marker.name,
									node = Host.describeNode(host, node),
									actual = Diagnostics.describe(value),
									expected = "a function",
								}
							),
							0
						)
					end
					subscribe(host, node, owner, marker.name, value :: (...unknown) -> (), fresh)
				elseif type(value) == "function" or cellModule.isValue(value) then
					bind(propertyTarget(host), node, owner, marker.name, value :: Types.Source<unknown>)
				else
					refuseNodeValue(host, node, marker.name, value)
					writeOnce(propertyTarget(host), node, owner, marker.name, value)
				end
				continue
			end

			error(
				Diagnostics.format("props/unsupported-key", "a props key is neither a string nor a wrapped key", {
					actual = Diagnostics.describe(key),
					expected = 'a string, event("Name"), or property("Name")',
					contract = "props keys name properties and events; array entries are children",
				}),
				0
			)
		end
		local name = key
		if replacing then
			retireFast(node, name)
		end

		if name == ATTRIBUTES then
			onKey(ATTRIBUTES)
			applyAttributes(host, node, owner, value, onKey)
			continue
		end

		onKey(name)

		local kind = type(value)
		if kind == "string" or kind == "boolean" then
			if fresh then
				write(node, name, value)
			else
				writeOnce(propertyTarget(host), node, owner, name, value)
			end
			continue
		end

		local literal, isStatic = Keys.readStatic(value)
		if isStatic then
			if fresh then
				write(node, name, literal)
			else
				writeOnce(propertyTarget(host), node, owner, name, literal)
			end
			continue
		end

		if cellModule.isValue(value) then
			if fresh then
				local edge = Owner.listenHeld(owner, value :: Types.ReadOnlyValue<unknown>, function(current: unknown)
					write(node, name, current)
				end)
				edge.fastKey = name
				edge.fastNext = fastEdges[node]
				fastEdges[node] = edge
			else
				bind(propertyTarget(host), node, owner, name, value :: Types.Source<unknown>)
			end
			continue
		end

		if type(value) == "function" then
			if classify(host, node, name) == "event" then
				subscribe(host, node, owner, name, value :: (...unknown) -> (), fresh)
			elseif fresh then
				local connect = mapped[value]
				local watcher: Types.Node
				if connect ~= nil then
					watcher = connect(owner, function(current: unknown)
						write(node, name, current)
					end)
				else
					local source = value :: Types.Body<unknown>
					watcher = Owner.effectHeld(owner, function(use: Types.Use)
						write(node, name, source(use))
					end)
				end
				watcher.fastKey = name
				watcher.fastNext = fastEdges[node]
				fastEdges[node] = watcher
			else
				bind(propertyTarget(host), node, owner, name, value :: Types.Source<unknown>)
			end
			continue
		end

		refuseNodeValue(host, node, name, value)
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
	apply = apply,
	forget = forget,
	map = map,
}
