--!strict
--!nolint DeprecatedApi

local Compose = require "../core"
local Engine = require "./engine"
local PreferredInput = require "./preferred-input"

local function preferredInput(
	inputService: { PreferredInput: unknown }?,
	engine: Engine.Engine?
): Compose.Value<PreferredInput.Class>
	local resolvedEngine = if engine ~= nil then engine else Engine.ambient()
	local service: { PreferredInput: unknown }
	if inputService == nil then
		local globals = (
			getfenv and getfenv(0) or {}
		) :: { game: { GetService: (unknown, string) -> { PreferredInput: unknown } } }
		service = globals.game:GetService "UserInputService"
	else
		service = inputService
	end
	local initial: PreferredInput.Class = PreferredInput.specOf(service.PreferredInput).class
	local value: Compose.Value<PreferredInput.Class> = Compose.cell(initial)
	local connection = resolvedEngine.propertyChanged(service, "PreferredInput"):Connect(function()
		value:set(PreferredInput.specOf(service.PreferredInput).class)
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
