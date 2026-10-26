--!strict
local Compose = require("../vendor/compose/core")
local Types = require("./control_types")

type Environment = { [Types.Runtime]: Types.Controls }
local contexts: { [Types.ComposeModule]: Compose.Context<Environment> } = {}
setmetatable(contexts, { __mode = "k" })

return function(core: Types.ComposeModule): Compose.Context<Environment>
	local context = contexts[core]
	if context == nil then
		local default: Environment = {}
		context = core.createContext(default)
		contexts[core] = context
	end
	return context
end
