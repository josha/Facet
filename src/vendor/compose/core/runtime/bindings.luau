--!strict
--!native

local Weak = require "../weak"
local Diagnostics = require "../diagnostics"
local Dynamic = require "../dynamic"
local Host = require "../host"
local Nodes = require "../ownership/nodes"
local cellModule = require "../reactive/cell"
local statsOn = require("../reactive/evaluation").stats.state
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local State = require "./props-state"
local mapped = State.mapped
local applying = State.applying
local UNWRITTEN = State.unwritten
type Node = Host.Node
local createWritten: (number, unknown?) -> { unknown } = table.create
local createPrevious: (number, Binding??) -> { Binding? } = table.create

local function readStatic(value: Host.PropValue): (unknown, boolean)
	if type(value) ~= "table" or Dynamic.raw(value, "composeValue") ~= "static" then
		return nil, false
	end
	return Dynamic.raw(value, "value"), true
end

type Binding = { remaining: number, active: boolean, dispose: (() -> ())?, pendingKey: string?, previous: Binding? }
type Bindings = { [string]: Binding? }
type Registry = { [Node]: Bindings }

type Clear = (node: Node, key: string) -> ()
type GroupBody = (use: Types.Use) -> ...unknown

local propertyBindings: Registry = {}

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

return {
	bind = bind,
	writeOnce = writeOnce,
	bindGroup = bindGroup,
	applyAttributes = applyAttributes,
	propertyTarget = propertyTarget,
}
