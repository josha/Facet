--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

type Pointer = {
	allowed: (ComposeTypes.Use) -> boolean,
	preferred: ComposeTypes.Readable<Enum.PreferredInput?>,
}
local resources = (setmetatable({}, { __mode = "k" }) :: unknown) :: {
	[Types.Context]: ComposeTypes.AcquireSharedResource<Pointer>,
}

return function(ctx: Types.Context): ((ComposeTypes.Use) -> boolean, ComposeTypes.Readable<Enum.PreferredInput?>)
	local acquire = resources[ctx]
	if not acquire then
		acquire = ctx.Compose.createSharedResource(function(): (Pointer, (() -> ())?)
			local Compose, E = ctx.Compose, ctx.types.Enum
			local input = ctx.config.userInputService or ctx.config.services.UserInputService
			local preferred = if input
				then ctx.observe.PreferredInput(input) :: ComposeTypes.Readable<Enum.PreferredInput?>
				else Compose.cell(nil :: Enum.PreferredInput?)
			local last = Compose.cell(nil :: Enum.UserInputType?)
			local changed: RBXScriptConnection? = nil
			if input and input.GetLastInputType then
				last:set(input:GetLastInputType())
				changed = input.LastInputTypeChanged:Connect(function(kind: Enum.UserInputType)
					last:set(kind)
				end)
			end
			return {
				preferred = preferred,
				allowed = function(use: ComposeTypes.Use): boolean
					return use(preferred) ~= E.PreferredInput.Gamepad and use(last) ~= E.UserInputType.Keyboard
				end,
			}, function()
				if changed then
					changed:Disconnect()
				end
				resources[ctx] = nil
			end
		end)
		resources[ctx] = acquire
	end
	local pointer = assert(acquire)()
	return pointer.allowed, pointer.preferred
end
