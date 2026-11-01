--!strict

local Compose = require "../core"
local Engine = require "./engine"

local function cleanupWith(nameOf: (value: unknown) -> string, value: unknown): Compose.Dispose
	local kind = nameOf(value)

	if kind == "RBXScriptConnection" then
		return Compose.cleanup(function()
			Engine.invoke(Engine.readMember, value, "Disconnect")
		end)
	end

	if type(value) == "thread" then
		local thread = value
		return Compose.cleanup(function()
			Engine.cancelThread(thread)
		end)
	end

	if kind == "Instance" then
		return Compose.cleanup(function()
			Engine.invoke(Engine.readMember, value, "Destroy")
		end)
	end

	if kind == "table" then
		local object = value
		if type(Engine.readMember(object, "Disconnect")) == "function" then
			return Compose.cleanup(function()
				Engine.invoke(Engine.readMember, object, "Disconnect")
			end)
		end
		if type(Engine.readMember(object, "disconnect")) == "function" then
			return Compose.cleanup(function()
				Engine.invoke(Engine.readMember, object, "disconnect")
			end)
		end
	end

	return Compose.cleanup(value)
end

local function createCleanup(typeName: ((value: unknown) -> string)?): (value: unknown) -> Compose.Dispose
	local nameOf: (value: unknown) -> string
	if typeName ~= nil then
		nameOf = typeName
	else
		nameOf = function(value: unknown): string
			return typeof(value)
		end
	end

	return function(value: unknown): Compose.Dispose
		return cleanupWith(nameOf, value)
	end
end

return {
	createCleanup = createCleanup,
	cleanup = createCleanup(nil),
}
