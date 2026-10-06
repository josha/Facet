--!strict
--!nolint DeprecatedApi

local Compose = require "../core"
local Engine = require "./engine"
local PreferredInput = require "./preferred-input"

local function preferredInput(
	inputService: { PreferredInput: unknown }?,
	engine: Engine.Engine?
): Compose.Cell<PreferredInput.Class>
	local resolvedEngine = if engine ~= nil then engine else Engine.ambient()
	local resolvedService = inputService
	if resolvedService == nil then
		local globals = (
			getfenv and getfenv(0) or {}
		) :: { game: { GetService: (unknown, string) -> { PreferredInput: unknown } } }
		resolvedService = globals.game:GetService "UserInputService"
	end
	local service = resolvedService :: { PreferredInput: unknown }
	local initial: PreferredInput.Class = PreferredInput.specOf(service.PreferredInput).class
	local value: Compose.Cell<PreferredInput.Class> = Compose.cell(initial)
	local connection = resolvedEngine.propertyChanged(resolvedService, "PreferredInput"):Connect(function()
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
