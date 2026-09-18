--!strict

local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Keys = require "./keys"
local Nodes = require "../ownership/nodes"
local cellModule = require "../reactive/cell"
local profile = require "../reactive/profile"
local stats = require "../reactive/stats"
local statsOn = stats.state
local Owner = require "../ownership/owner"

type Node = Host.Node

local UNWRITTEN = newproxy(false)

export type Props = { [any]: any }

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

local function subscribe(host: Host.Host, node: Node, owner: Owner.Owner, name: string, handler: (...any) -> ())
	local events = host.events
	if events == nil then
		Diagnostics.raise("host/no-events", ("host %q cannot subscribe to events"):format(host.name), {
			event = name,
			node = Host.describeNode(host, node),
			contract = "subscribing requires the host events capability",
			fix = "implement host.events.connectEvent, or stop passing event keys to this host",
		})
	end
	owner.own((events :: Host.Events).connectEvent(node, name, handler))
end

local function refuseNodeValue(host: Host.Host, node: Node, key: string, value: unknown)
	if not Nodes.isDestructible(value :: any) then
		return
	end
	Diagnostics.raise("props/child-under-string-key", "a node was given as the value of a property", {
		key = key,
		node = Host.describeNode(host, node),
		actual = ("a node this runtime will destroy: %s"):format(Host.describeNode(host, value :: any)),
		expected = "a value the host can store in a property",
		contract = "a string key names a property to write; children live in the array part of the props table",
		fix = ("drop the key -- write the node as a positional child rather than as %s = ...; "):format(key)
			.. ("if this host really does take a node there, say so with %s = static(node)"):format(key),
	})
end

local function writeOnce(host: Host.Host, node: Node, owner: Owner.Owner, key: string, value: unknown)
	host.render.setProperty(node, key, value)
	if not Nodes.isDestructible(node) then
		owner.own(function()
			host.render.clearProperty(node, key)
		end)
	end
end

local function bind(host: Host.Host, node: Node, owner: Owner.Owner, key: string, source: any)
	local render = host.render
	local setProperty = render.setProperty
	if statsOn.enabled then
		profile.naming(("%s.%s"):format(Host.describeNode(host, node), key))
	end
	if cellModule.isReadable(source) then
		owner.watchStatic(source, function(value: unknown)
			setProperty(node, key, value)
			if statsOn.enabled then
				profile.hostWrite()
			end
		end)
	else
		owner.watchTerminal(function(use)
			setProperty(node, key, source(use))
			if statsOn.enabled then
				profile.hostWrite()
			end
		end)
	end
	if statsOn.enabled then
		profile.naming(nil)
	end
	if not Nodes.isDestructible(node) then
		owner.own(function()
			render.clearProperty(node, key)
		end)
	end
end

local function bindGroup(host: Host.Host, node: Node, owner: Owner.Owner, names: { string }, source: any)
	local render = host.render
	local count = #names
	for index = 1, count do
		local name = names[index]
		if classify(host, node, name) == "event" then
			Diagnostics.raise("props/group-names-an-event", "a group named a key the host classifies as an event", {
				event = name,
				node = Host.describeNode(host, node),
				contract = "a group writes properties; events are subscribed with event(name)",
				fix = ("move %q out of the group and onto its own [event(%q)] key"):format(name, name),
			})
		end
	end
	if type(source) ~= "function" then
		Diagnostics.raise("props/group-needs-a-body", "a group key was given something that is not a body", {
			properties = table.concat(names, ", "),
			node = Host.describeNode(host, node),
			actual = Diagnostics.describe(source),
			expected = "a function taking `use` and returning one value per name",
		})
	end

	local written = table.create(count, UNWRITTEN)
	if statsOn.enabled then
		profile.naming(("%s.{%s}"):format(Host.describeNode(host, node), table.concat(names, ",")))
	end
	owner.watch(function(use)
		local values = table.pack(source(use))
		if values.n ~= count then
			Diagnostics.raise("props/group-arity", "a group body returned the wrong number of values", {
				properties = table.concat(names, ", "),
				node = Host.describeNode(host, node),
				actual = ("%d value(s)"):format(values.n),
				expected = ("%d, one per name, in order"):format(count),
			})
		end
		for index = 1, count do
			local value = values[index]
			if value ~= written[index] then
				written[index] = value
				render.setProperty(node, names[index], value)
				if statsOn.enabled then
					profile.hostWrite()
				end
			end
		end
	end)
	if statsOn.enabled then
		profile.naming(nil)
	end
	if not Nodes.isDestructible(node) then
		owner.own(function()
			for index = 1, count do
				render.clearProperty(node, names[index])
			end
		end)
	end
end

local ATTRIBUTES = "Attributes"

type SetAttribute = (node: Node, name: string, value: unknown) -> (boolean, string?)

local function attributeWriter(host: Host.Host, node: Node): SetAttribute
	local setAttribute = host.render.setAttribute
	if setAttribute == nil then
		Diagnostics.raise("host/no-attributes", ("host %q cannot store attributes"):format(host.name), {
			key = ATTRIBUTES,
			node = Host.describeNode(host, node),
			contract = "an Attributes prop requires the render.setAttribute capability",
			fix = "implement host.render.setAttribute, or write the value under an ordinary property key",
		})
	end
	return setAttribute :: SetAttribute
end

local function writeAttribute(host: Host.Host, node: Node, write: SetAttribute, name: string, value: unknown)
	local accepted, reason = write(node, name, value)
	if accepted then
		return
	end
	Diagnostics.raise("props/attribute-value", "the host refused an attribute value", {
		key = ("%s.%s"):format(ATTRIBUTES, name),
		node = Host.describeNode(host, node),
		actual = Diagnostics.describe(value),
		expected = "a value this host stores as an attribute",
		detail = if reason ~= nil then reason else "the host gave no reason",
		contract = "an attribute value must be one the host's attribute store accepts; nil clears it",
		fix = ("write a value the host accepts, or move %q onto an ordinary property key"):format(name),
	})
end

local function refuseNodeAttribute(host: Host.Host, node: Node, name: string, value: unknown)
	if not Nodes.isDestructible(value :: any) then
		return
	end
	Diagnostics.raise("props/child-under-attribute", "a node was given as the value of an attribute", {
		key = ("%s.%s"):format(ATTRIBUTES, name),
		node = Host.describeNode(host, node),
		actual = ("a node this runtime will destroy: %s"):format(Host.describeNode(host, value :: any)),
		expected = "a value the host can store in an attribute",
		contract = "an attribute holds data; children live in the array part of the props table",
		fix = ("drop the attribute -- write the node as a positional child rather than as %s.%s"):format(
			ATTRIBUTES,
			name
		),
	})
end

local function writeAttributeOnce(
	host: Host.Host,
	node: Node,
	owner: Owner.Owner,
	write: SetAttribute,
	name: string,
	value: unknown
)
	writeAttribute(host, node, write, name, value)
	if not Nodes.isDestructible(node) then
		owner.own(function()
			write(node, name, nil)
		end)
	end
end

local function bindAttribute(
	host: Host.Host,
	node: Node,
	owner: Owner.Owner,
	write: SetAttribute,
	name: string,
	source: any
)
	local written: unknown = UNWRITTEN
	local function publish(value: unknown)
		if value == written then
			return
		end
		written = value
		writeAttribute(host, node, write, name, value)
		if statsOn.enabled then
			profile.hostWrite()
		end
	end

	if statsOn.enabled then
		profile.naming(("%s.%s.%s"):format(Host.describeNode(host, node), ATTRIBUTES, name))
	end
	if cellModule.isReadable(source) then
		owner.watchStatic(source, publish)
	else
		owner.watchTerminal(function(use)
			publish(source(use))
		end)
	end
	if statsOn.enabled then
		profile.naming(nil)
	end

	if not Nodes.isDestructible(node) then
		owner.own(function()
			write(node, name, nil)
		end)
	end
end

local function applyAttributes(host: Host.Host, node: Node, owner: Owner.Owner, source: unknown, onKey: (string) -> ())
	if type(source) ~= "table" then
		Diagnostics.raise(
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

	local table_ = (source :: any) :: { [unknown]: unknown }
	local names: { string } = {}
	for name in table_ do
		if type(name) ~= "string" or name == "" then
			Diagnostics.raise("props/attribute-name", "an attribute name is not a non-empty string", {
				key = ATTRIBUTES,
				node = Host.describeNode(host, node),
				actual = Diagnostics.describe(name),
				expected = "a non-empty string",
				contract = "every key of an Attributes table names one attribute",
				fix = "give the attribute a name the host can address",
			})
		end
		table.insert(names, name :: string)
	end

	table.sort(names)

	local write = attributeWriter(host, node)
	for _, name in names do
		onKey(("%s.%s"):format(ATTRIBUTES, name))
		local value = table_[name]

		local literal, isStatic = Keys.readStatic(value)
		if isStatic then
			writeAttributeOnce(host, node, owner, write, name, literal)
			continue
		end

		if cellModule.isReadable(value) or type(value) == "function" then
			bindAttribute(host, node, owner, write, name, value)
			continue
		end

		refuseNodeAttribute(host, node, name, value)
		writeAttributeOnce(host, node, owner, write, name, value)
	end
end

local function apply(host: Host.Host, node: Node, props: Props, owner: Owner.Owner, onKey: (string) -> ())
	local length = #props

	for key, value in props do
		if type(key) == "number" and key >= 1 and key <= length and key % 1 == 0 then
			continue
		end

		local marker = Keys.readKey(key)
		if marker ~= nil then
			onKey(marker.name)
			if marker.kind == "group" then
				bindGroup(host, node, owner, marker.names :: { string }, value)
			elseif marker.kind == "event" then
				if type(value) ~= "function" then
					Diagnostics.raise(
						"props/event-needs-handler",
						"an event key was given something that is not a handler",
						{
							event = marker.name,
							node = Host.describeNode(host, node),
							actual = Diagnostics.describe(value),
							expected = "a function",
						}
					)
				end
				subscribe(host, node, owner, marker.name, value)
			elseif type(value) == "function" or cellModule.isReadable(value) then
				bind(host, node, owner, marker.name, value)
			else
				refuseNodeValue(host, node, marker.name, value)
				writeOnce(host, node, owner, marker.name, value)
			end
			continue
		end

		if type(key) ~= "string" then
			Diagnostics.raise("props/unsupported-key", "a props key is neither a string nor a wrapped key", {
				actual = Diagnostics.describe(key),
				expected = 'a string, event("Name"), or property("Name")',
				contract = "props keys name properties and events; array entries are children",
			})
		end
		local name = key :: string

		if name == ATTRIBUTES then
			onKey(ATTRIBUTES)
			applyAttributes(host, node, owner, value, onKey)
			continue
		end

		onKey(name)

		local literal, isStatic = Keys.readStatic(value)
		if isStatic then
			writeOnce(host, node, owner, name, literal)
			continue
		end

		if cellModule.isReadable(value) then
			bind(host, node, owner, name, value)
			continue
		end

		if type(value) == "function" then
			if classify(host, node, name) == "event" then
				subscribe(host, node, owner, name, value)
			else
				bind(host, node, owner, name, value)
			end
			continue
		end

		refuseNodeValue(host, node, name, value)
		writeOnce(host, node, owner, name, value)
	end
end

return {
	apply = apply,
}
