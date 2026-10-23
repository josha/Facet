--!strict

local Compose = require "../core"
local Engine = require "./engine"

type Node = Compose.Node

type DefaultCache = { [string]: unknown }
type StyledNode = {
	GetStyled: (self: StyledNode, property: string) -> unknown,
	StyledPropertiesChanged: Engine.Signal<()>,
}
type Subscriber = { live: boolean, listener: () -> (), stopRaw: Compose.Unsubscribe? }
type StyledEntry = {
	live: boolean,
	subscribers: { [Subscriber]: boolean },
	stopStyled: Compose.Unsubscribe?,
}

local function raiseFailures(failures: { unknown })
	if #failures == 1 then
		error(failures[1], 0)
	elseif #failures > 1 then
		local messages: { string } = {}
		for _, failure in failures do
			table.insert(messages, tostring(failure))
		end
		error(table.concat(messages, "\n"), 0)
	end
end

local function attempt(callback: () -> ()): (boolean, unknown)
	local ok, failure = pcall(function(): unknown
		callback()
		return nil
	end)
	return ok, if not ok and failure == nil then "ComposeRoblox styled observation raised nil" else failure
end

local function connect<Args...>(signal: Engine.Signal<Args...>, handler: (Args...) -> ()): Compose.Unsubscribe
	local connection = signal:Connect(handler)
	local disconnected = false
	return function()
		if not disconnected then
			disconnected = true
			connection:Disconnect()
		end
	end
end

local function createHost(engine: Engine.Engine): Compose.Host
	local defaults: DefaultCache = {}
	local unsampleable: { [string]: true } = {}
	local styledEntries: { [Node]: StyledEntry } = {}

	local classified: { [string]: { [string]: Compose.KeyKind } } = {}

	local function readClassName(node: Node): string
		return (node :: Engine.Instance).ClassName
	end

	local function readMember(node: Node, key: string): unknown
		return (node :: { [string]: unknown })[key]
	end

	local function hasConnectMethod(value: unknown): boolean
		return type((value :: { Connect: unknown }).Connect) == "function"
	end

	local function classNameOf(node: Node): string
		local ok, name = pcall(readClassName, node)
		if ok and type(name) == "string" then
			return name
		end
		return "<unknown class>"
	end

	local function defaultFor(node: Node, key: string): unknown
		local class = classNameOf(node)
		local cacheKey = class .. "." .. key
		local cached = defaults[cacheKey]
		if cached ~= nil then
			return cached
		end
		if unsampleable[class] then
			return nil
		end

		local ok, sample = pcall(engine.new, class)
		if not ok then
			unsampleable[class] = true
			return nil
		end
		local readOk, value = pcall(readMember, sample, key)
		pcall(engine.destroy, sample)
		if not readOk then
			return nil
		end
		defaults[cacheKey] = value
		return value
	end

	local function createNode(kind: string): Node
		return engine.new(kind)
	end

	local function setProperty(node: Node, key: string, value: unknown)
		(node :: { [string]: unknown })[key] = value
	end

	local function writeAttribute(node: Node, name: string, value: unknown): boolean
		(node :: Engine.Instance):SetAttribute(name, value)
		return true
	end

	local function setAttribute(node: Node, name: string, value: unknown): (boolean, string?)
		local ok, result = pcall(writeAttribute, node, name, value)
		if ok then
			return true, nil
		end
		return false, tostring(result)
	end

	local function clearProperty(node: Node, key: string)
		local default = defaultFor(node, key)
		if default == nil then
			return
		end
		(node :: { [string]: unknown })[key] = default
	end

	local function insertChild(parent: Node, child: Node, _position: number?)
		(child :: Engine.Instance).Parent = parent
	end

	local function removeChild(_parent: Node, child: Node)
		if (child :: Engine.Instance).Parent ~= nil then
			(child :: Engine.Instance).Parent = nil
		end
	end

	local function destroyNode(node: Node)
		engine.destroy(node)
	end

	local function connectEvent<Args...>(node: Node, event: string, handler: (Args...) -> ()): Compose.Unsubscribe
		local read, found = pcall(function(): unknown
			return (node :: { [string]: unknown })[event]
		end)
		local signal = (if read then found else nil) :: Engine.Signal<Args...>?
		if signal == nil or type(signal.Connect) ~= "function" then
			error(
				Compose.formatDiagnostic(
					"host/not-an-event",
					("%s has no event named %s"):format(classNameOf(node), event),
					{
						event = event,
						node = classNameOf(node),
						contract = "an event key must name something the object can be subscribed to",
						fix = "check the spelling, or use Compose.property(name) if it is a property",
					}
				),
				0
			)
		end

		return connect(signal, handler)
	end

	local function classifyKey(node: Node, key: string): Compose.KeyKind
		local class = classNameOf(node)
		local byKey = classified[class]
		if byKey ~= nil then
			local known = byKey[key]
			if known ~= nil then
				return known :: Compose.KeyKind
			end
		end

		local kind: Compose.KeyKind = "property"
		local ok, value = pcall(readMember, node, key)
		if ok and value ~= nil then
			local connectOk, hasConnect = pcall(hasConnectMethod, value)
			if connectOk and hasConnect then
				kind = "event"
			end
		end

		if class ~= "<unknown class>" then
			if byKey == nil then
				local created: { [string]: Compose.KeyKind } = {}
				classified[class] = created
				byKey = created
			end
			byKey[key] = kind
		end
		return kind
	end

	local function observeProperty(node: Node, key: string, listener: () -> ()): Compose.Unsubscribe
		return connect(engine.propertyChanged(node, key), listener)
	end

	local function publish(entry: StyledEntry)
		if not entry.live then
			return
		end
		local queued: { Subscriber } = {}
		for subscriber in entry.subscribers do
			table.insert(queued, subscriber)
		end
		local failures: { unknown } = {}
		for _, subscriber in queued do
			if subscriber.live then
				local ok, failure = attempt(subscriber.listener)
				if not ok then
					table.insert(failures, failure)
				end
			end
		end
		raiseFailures(failures)
	end

	local function closeStyled(node: Node, entry: StyledEntry)
		entry.live = false
		styledEntries[node] = nil
		local stop = entry.stopStyled
		entry.stopStyled = nil
		if stop then
			stop()
		end
	end

	local function observeStyledProperty(node: Node, key: string, listener: () -> ()): Compose.Unsubscribe
		local native = node :: StyledNode
		local entry = styledEntries[node]
		if entry == nil then
			local created: StyledEntry = { live = true, subscribers = {} }
			styledEntries[node] = created
			local ok, failure = attempt(function()
				created.stopStyled = connect(native.StyledPropertiesChanged, function()
					publish(created)
				end)
			end)
			if not ok then
				local failures = { failure }
				local closed, cleanupFailure = attempt(function()
					closeStyled(node, created)
				end)
				if not closed then
					table.insert(failures, cleanupFailure)
				end
				raiseFailures(failures)
			end
			entry = created
		end
		local current = entry :: StyledEntry
		local subscriber: Subscriber = { live = true, listener = listener }
		current.subscribers[subscriber] = true
		local function release()
			if not subscriber.live then
				return
			end
			subscriber.live = false
			current.subscribers[subscriber] = nil
			local failures: { unknown } = {}
			if subscriber.stopRaw then
				local ok, failure = attempt(subscriber.stopRaw)
				if not ok then
					table.insert(failures, failure)
				end
				subscriber.stopRaw = nil
			end
			if next(current.subscribers) == nil then
				local ok, failure = attempt(function()
					closeStyled(node, current)
				end)
				if not ok then
					table.insert(failures, failure)
				end
			end
			raiseFailures(failures)
		end
		do
			local ok, failure = attempt(function()
				subscriber.stopRaw = observeProperty(node, key, function()
					if subscriber.live then
						listener()
					end
				end)
			end)
			if not ok then
				local failures = { failure }
				local closed, cleanupFailure = attempt(release)
				if not closed then
					table.insert(failures, cleanupFailure)
				end
				raiseFailures(failures)
			end
		end
		return release
	end

	local function onFrame(listener: (delta: number) -> ()): Compose.Unsubscribe
		return connect(engine.heartbeat, listener)
	end

	return {
		name = "roblox",
		render = {
			createNode = createNode,
			setProperty = setProperty,
			setAttribute = setAttribute,
			clearProperty = clearProperty,
			insertChild = insertChild,
			removeChild = removeChild,
			destroyNode = destroyNode,
		},
		events = {
			connectEvent = connectEvent,
			classifyKey = classifyKey,
		},
		observation = {
			readProperty = readMember,
			observeProperty = observeProperty,
			readStyledProperty = function(node: Node, key: string): unknown
				return (node :: StyledNode):GetStyled(key)
			end,
			observeStyledProperty = observeStyledProperty,
		},
		naming = {
			setName = function(node: Node, label: string)
				(node :: Engine.Instance).Name = label
			end,
		},
		frames = {
			onFrame = onFrame,
			now = engine.clock,
		},
		describeNode = function(node: Node): string
			local ok, name = pcall(function()
				return ("%s %q"):format((node :: Engine.Instance).ClassName, (node :: Engine.Instance).Name)
			end)
			return if ok then name else tostring(node)
		end,
		typeNameOf = function(value: unknown): string
			return engine.typeName(value)
		end,
	}
end

return {
	createHost = createHost,
}
