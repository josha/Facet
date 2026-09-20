--!strict

local Compose = require "../core"
local Engine = require "./engine"

type Node = Compose.Node

type DefaultCache = { [string]: any }

local function createHost(engine: Engine.Engine): Compose.Host
	local defaults: DefaultCache = {}
	local unsampleable: { [string]: true } = {}

	local classified: { [string]: { [string]: Compose.KeyKind } } = {}

	local function readClassName(node: Node): string
		return (node :: any).ClassName
	end

	local function readMember(node: Node, key: string): any
		return (node :: any)[key]
	end

	local function hasConnectMethod(value: any): boolean
		return type(value.Connect) == "function"
	end

	local function classNameOf(node: Node): string
		local ok, name = pcall(readClassName, node)
		if ok and type(name) == "string" then
			return name
		end
		return "<unknown class>"
	end

	local function defaultFor(node: Node, key: string): any
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
		(node :: any)[key] = value
	end

	local function writeAttribute(node: Node, name: string, value: unknown): boolean
		(node :: any):SetAttribute(name, value)
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
		(node :: any)[key] = default
	end

	local function insertChild(parent: Node, child: Node, _position: number?)
		(child :: any).Parent = parent
	end

	local function removeChild(_parent: Node, child: Node)
		(child :: any).Parent = nil
	end

	local function destroyNode(node: Node)
		engine.destroy(node)
	end

	local function connectEvent(node: Node, event: string, handler: (...any) -> ()): Compose.Unsubscribe
		local signal = (node :: any)[event]
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

		local connection = signal:Connect(handler)
		local disconnected = false
		return function()
			if disconnected then
				return
			end
			disconnected = true
			connection:Disconnect()
		end
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

	local function readProperty(node: Node, key: string): unknown
		return (node :: any)[key]
	end

	local function observeProperty(node: Node, key: string, listener: () -> ()): Compose.Unsubscribe
		local connection = engine.propertyChanged(node, key):Connect(listener)
		local disconnected = false
		return function()
			if disconnected then
				return
			end
			disconnected = true
			connection:Disconnect()
		end
	end

	local function onFrame(listener: (delta: number) -> ()): Compose.Unsubscribe
		local connection = engine.heartbeat:Connect(listener)
		local disconnected = false
		return function()
			if disconnected then
				return
			end
			disconnected = true
			connection:Disconnect()
		end
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
			readProperty = readProperty,
			observeProperty = observeProperty,
		},
		naming = {
			setName = function(node: Node, label: string)
				(node :: any).Name = label
			end,
		},
		frames = {
			onFrame = onFrame,
			now = engine.clock,
		},
		describeNode = function(node: Node): string
			local ok, name = pcall(function()
				return ("%s %q"):format((node :: any).ClassName, (node :: any).Name)
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
