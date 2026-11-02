--!strict

local Types = require "./reactive/types"

export type Node = typeof((function(value: unknown)
	if type(value) == "table" or type(value) == "userdata" then
		return value
	end
	error "a host node must be a table or userdata"
end)(nil))

export type Plain = typeof((function(value: unknown)
	if type(value) == "table" or type(value) == "function" then
		error "a plain value is neither a table nor a function"
	end
	return value
end)(nil))

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

local errorsModule: typeof(require "./host-validation")? = nil

local function fail(code: string, name: string?, actual: unknown?, method: string?)
	local loaded = errorsModule or require "./host-validation"
	errorsModule = loaded
	return loaded(code, name, actual, method)
end

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
		return fail("not-a-host", nil, host)
	end
	if type(host.name) ~= "string" or host.name == "" then
		return fail "unnamed"
	end

	if type(host.render) ~= "table" then
		return fail("no-renderer", host.name)
	end
	local renderer = host.render
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
			return fail("incomplete-renderer", host.name, methods[method], method)
		end
	end

	local events = host.events
	if events ~= nil and type(events.connectEvent) ~= "function" then
		return fail("incomplete-events", host.name)
	end

	local observation = host.observation
	if observation ~= nil then
		if type(observation.readProperty) ~= "function" or type(observation.observeProperty) ~= "function" then
			return fail("incomplete-observation", host.name)
		end
		if observation.readStyledProperty ~= nil or observation.observeStyledProperty ~= nil then
			if
				type(observation.readStyledProperty) ~= "function"
				or type(observation.observeStyledProperty) ~= "function"
			then
				return fail "incomplete-styled-observation"
			end
		end
	end

	local naming = host.naming
	if naming ~= nil then
		if type(naming.setName) ~= "function" then
			return fail("incomplete-naming", host.name)
		end
	end

	local frames = host.frames
	if frames ~= nil then
		if type(frames.onFrame) ~= "function" or type(frames.now) ~= "function" then
			return fail("incomplete-frames", host.name)
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
