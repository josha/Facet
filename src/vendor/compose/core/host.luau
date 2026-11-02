--!strict

local Diagnostics = require "./diagnostics"
local Types = require "./reactive/types"

local function nodeReference(value: unknown)
	if type(value) == "table" or type(value) == "userdata" then
		return value
	end
	error "a host node must be a table or userdata"
end

export type Node = typeof(nodeReference(nil))

local function plainReference(value: unknown)
	if type(value) == "table" or type(value) == "function" then
		error "a plain value is neither a table nor a function"
	end
	return value
end

export type Plain = typeof(plainReference(nil))

export type EventKey = {
	composeKey: "event",
	name: string,
}

export type PropertyKey = {
	composeKey: "property",
	name: string,
}

export type GroupKey = {
	composeKey: "group",
	names: { string },
}

export type StaticValue = {
	composeValue: "static",
	value: unknown,
}

export type PropFunction = (use: Types.Use) -> ...unknown

export type PropMarker = { names: { string }? }

export type PropValue = StaticValue | Types.ReadOnlyValue<unknown> | PropFunction | Plain

export type PropKey = string | number | PropMarker

export type PropTable = { [PropKey]: PropValue }

export type Unsubscribe = () -> ()

export type KeyKind = "property" | "event"

export type Renderer = {
	createNode: (kind: string) -> Node,
	setProperty: (node: Node, key: string, value: unknown) -> (),
	clearProperty: (node: Node, key: string) -> (),

	setAttribute: ((node: Node, name: string, value: unknown) -> (boolean, string?))?,

	insertChild: (parent: Node, child: Node, position: number?) -> (),

	moveChild: ((parent: Node, child: Node, position: number) -> ())?,

	removeChild: (parent: Node, child: Node) -> (),

	destroyNode: (node: Node) -> (),
}

export type Events = {
	connectEvent: <Args...>(node: Node, event: string, handler: (Args...) -> ()) -> Unsubscribe,
	attachEvent: (<Args...>(node: Node, event: string, handler: (Args...) -> ()) -> ())?,

	classifyKey: ((node: Node, key: string) -> KeyKind)?,
}

export type Observation = {
	readProperty: (node: Node, key: string) -> unknown,
	observeProperty: (node: Node, key: string, listener: () -> ()) -> Unsubscribe,
	readStyledProperty: ((node: Node, key: string) -> unknown)?,
	observeStyledProperty: ((node: Node, key: string, listener: () -> ()) -> Unsubscribe)?,
}

export type Naming = {

	setName: (node: Node, label: string) -> (),
}

export type Frames = {
	onFrame: (listener: (delta: number) -> ()) -> Unsubscribe,
	now: () -> number,
}

export type Host = {
	name: string,
	render: Renderer,
	events: Events?,
	observation: Observation?,
	frames: Frames?,
	naming: Naming?,
	describeNode: ((node: Node) -> string)?,
	typeNameOf: ((value: unknown) -> string)?,
}

export type MountPoint = {
	parent: Node,
	insert: (node: Node, at: number?) -> (),
	moveTo: (node: Node, at: number) -> (),

	ordersChildren: boolean,
	remove: (node: Node) -> (),
	count: () -> number,
	host: Host,
}

export type Directive = (MountPoint) -> ()

export type Child = Node | Directive

type LooseHost = {
	name: unknown,
	render: { [string]: unknown }?,
	events: { [string]: unknown }?,
	observation: { [string]: unknown }?,
	frames: { [string]: unknown }?,
	naming: { [string]: unknown }?,
}

local REQUIRED_RENDERER = {
	"createNode",
	"setProperty",
	"clearProperty",
	"insertChild",
	"removeChild",
	"destroyNode",
}

local function validate(host: Host)
	if type(host) ~= "table" then
		return Diagnostics.raise("host/not-a-host", "createRuntime expects a host table", {
			actual = Diagnostics.describe(host),
			contract = "a host implements the protocol in src/core/host.luau",
		})
	end
	if type(host.name) ~= "string" or host.name == "" then
		return Diagnostics.raise("host/unnamed", "a host must name itself", {
			contract = "host.name appears in every diagnostic Compose raises about this host",
			fix = 'set host.name, e.g. "roblox"',
		})
	end

	local loose = host

	if type(loose.render) ~= "table" then
		return Diagnostics.raise("host/no-renderer", ("host %q has no render capability"):format(host.name), {
			contract = "render is the one required capability",
		})
	end
	local renderer = loose.render
	local methods: { [string]: unknown } = {
		createNode = renderer.createNode,
		setProperty = renderer.setProperty,
		clearProperty = renderer.clearProperty,
		insertChild = renderer.insertChild,
		removeChild = renderer.removeChild,
		destroyNode = renderer.destroyNode,
	}
	for _, method in REQUIRED_RENDERER do
		if type(methods[method]) ~= "function" then
			return Diagnostics.raise(
				"host/incomplete-renderer",
				("host %q is missing render.%s"):format(host.name, method),
				{
					expected = "a function",
					actual = Diagnostics.describe(methods[method]),
					contract = "every method in Renderer is required",
				}
			)
		end
	end

	local events = loose.events
	if events ~= nil and type(events.connectEvent) ~= "function" then
		return Diagnostics.raise(
			"host/incomplete-events",
			("host %q declares events without connectEvent"):format(host.name),
			{
				contract = "a declared capability must be complete",
				fix = "either implement connectEvent or omit host.events entirely",
			}
		)
	end

	local observation = loose.observation
	if observation ~= nil then
		if type(observation.readProperty) ~= "function" or type(observation.observeProperty) ~= "function" then
			return Diagnostics.raise(
				"host/incomplete-observation",
				("host %q declares observation but does not implement it"):format(host.name),
				{
					contract = "observation requires both readProperty and observeProperty",
					fix = "either implement both or omit host.observation entirely",
				}
			)
		end
		if observation.readStyledProperty ~= nil or observation.observeStyledProperty ~= nil then
			if
				type(observation.readStyledProperty) ~= "function"
				or type(observation.observeStyledProperty) ~= "function"
			then
				return Diagnostics.raise(
					"host/incomplete-styled-observation",
					"styled observation requires both host methods",
					{
						contract = "readStyledProperty and observeStyledProperty must be supplied together",
					}
				)
			end
		end
	end

	local naming = loose.naming
	if naming ~= nil then
		if type(naming.setName) ~= "function" then
			return Diagnostics.raise(
				"host/incomplete-naming",
				("host %q declares naming but does not implement it"):format(host.name),
				{
					contract = "naming requires setName",
					fix = "either implement setName or omit host.naming entirely",
				}
			)
		end
	end

	local frames = loose.frames
	if frames ~= nil then
		if type(frames.onFrame) ~= "function" or type(frames.now) ~= "function" then
			return Diagnostics.raise(
				"host/incomplete-frames",
				("host %q declares frames but does not implement it"):format(host.name),
				{
					contract = "frames requires both onFrame and now",
					fix = "either implement both or omit host.frames entirely",
				}
			)
		end
	end
end

local function typeNameOf(host: Host, value: unknown): string
	local name = host.typeNameOf
	if name ~= nil then
		return name(value)
	end
	return typeof(value)
end

local function describeNode(host: Host, node: unknown): string
	local describe = host.describeNode
	if describe ~= nil and (type(node) == "table" or type(node) == "userdata") then
		local ok, label = pcall(describe, node)
		if ok and type(label) == "string" then
			return label
		end
	end
	return tostring(node)
end

return {
	validate = validate,
	describeNode = describeNode,
	typeNameOf = typeNameOf,
}
