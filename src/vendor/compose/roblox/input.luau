--!strict

local Compose = require "../core"
local Engine = require "./engine"
local PreferredInput = require "./preferred-input"

local function preferredInput(inputService: unknown, engine: Engine.Engine?): Compose.Value<PreferredInput.Class>
	local resolvedEngine = if engine ~= nil then engine else Engine.ambient()
	local service = if inputService ~= nil then inputService else Engine.service "UserInputService"
	local initial: PreferredInput.Class = PreferredInput.specOf(Engine.readMember(service, "PreferredInput")).class
	local value: Compose.Value<PreferredInput.Class> = Compose.cell(initial)
	local connection = resolvedEngine.propertyChanged(service, "PreferredInput"):Connect(function()
		value:set(PreferredInput.specOf(Engine.readMember(service, "PreferredInput")).class)
	end)
	Compose.cleanup(function()
		connection:Disconnect()
	end)
	return value
end

return {
	preferredInput = preferredInput,
	preferredInputSpec = PreferredInput.specOf,
}
