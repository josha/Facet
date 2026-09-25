--!strict

local Compose = require "../core"
local Engine = require "./engine"

local function cleanupWith(nameOf: (value: unknown) -> string, value: unknown): Compose.Dispose
	local kind = nameOf(value)

	if kind == "RBXScriptConnection" then
		local connection = value :: Engine.Connection
		return Compose.cleanup(function()
			connection:Disconnect()
		end)
	end

	if kind == "thread" then
		local thread = value :: thread
		return Compose.cleanup(function()
			Engine.cancelThread(thread)
		end)
	end

	if kind == "Instance" then
		local object = value :: Engine.Destroyable
		return Compose.cleanup(function()
			object:Destroy()
		end)
	end

	if kind == "table" then
		local object = (value :: unknown) :: { Disconnect: unknown, disconnect: unknown }
		if type(object.Disconnect) == "function" then
			return Compose.cleanup(function()
				(object.Disconnect :: (unknown) -> ())(object)
			end)
		end
		if type(object.disconnect) == "function" then
			return Compose.cleanup(function()
				(object.disconnect :: (unknown) -> ())(object)
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
