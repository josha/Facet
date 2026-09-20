--!strict
--!nolint DeprecatedApi

local Compose = require "../core"
local Engine = require "./engine"
local PreferredInput = require "./preferred-input"

local function preferredInput(inputService: any?, engine: Engine.Engine?): Compose.Cell<PreferredInput.Class>
	local resolvedEngine = if engine ~= nil then engine else Engine.ambient()
	local resolvedService = inputService
	if resolvedService == nil then
		local globals = (getfenv and getfenv(0) or {}) :: { [string]: any }
		resolvedService = globals.game:GetService "UserInputService"
	end
	local value = (Compose.cell(PreferredInput.specOf(resolvedService.PreferredInput).class) :: any) :: Compose.Cell<
		PreferredInput.Class
	>
	local connection = resolvedEngine.propertyChanged(resolvedService, "PreferredInput"):Connect(function()
		value:set(PreferredInput.specOf(resolvedService.PreferredInput).class)
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
