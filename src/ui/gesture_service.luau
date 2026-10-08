--!strict
local Types = require("./types")
local arbitration = require("./gesture_arbitration")
local services = setmetatable({} :: { [UserInputService]: arbitration.Arbiter }, { __mode = "k" })
local fallbacks = setmetatable({} :: { [Types.Context]: arbitration.Arbiter }, { __mode = "k" })

return function(ctx: Types.Context): arbitration.Arbiter
	local input = ctx.config.userInputService
	if input then
		if not services[input] then
			services[input] = arbitration.new()
		end
		return services[input]
	end
	if not fallbacks[ctx] then
		fallbacks[ctx] = arbitration.new()
	end
	return fallbacks[ctx]
end
