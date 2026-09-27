--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type Acquire = () -> ComposeTypes.Cell<boolean>

return function(ctx: Shared.Context): (ComposeTypes.Use?) -> boolean
	local config = ctx.config
	local gui = config.guiService
	local native: ComposeTypes.Cell<boolean>? = nil
	if gui then
		local acquire: Acquire = (ctx.reducedMotion :: Acquire?)
			or ctx.Compose.createSharedResource(function(): (ComposeTypes.Cell<boolean>, (() -> ())?)
				return ctx.observe.ReducedMotionEnabled(gui), nil
			end)
		ctx.reducedMotion = acquire
		native = acquire()
	end
	return function(use: ComposeTypes.Use?): boolean
		if ctx.read(config.reducedMotion, use) == true then
			return true
		end
		if native == nil then
			return false
		end
		return (if use then use(native) else native:peek()) == true
	end
end
