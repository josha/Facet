--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type Acquire = () -> ComposeTypes.Cell<boolean>
export type Level = Shared.MotionLevel

local LEVELS = { normal = true, limited = true, none = true }

local function resolve(chosen: unknown, engineReduced: boolean): Level
	if chosen == nil then
		return if engineReduced then "limited" else "normal"
	end
	if type(chosen) ~= "string" or not LEVELS[chosen :: string] then
		error(`Facet motionLevel must be "normal", "limited" or "none", got {tostring(chosen)}`, 0)
	end
	return chosen :: Level
end

local function level(ctx: Shared.Context): (ComposeTypes.Use?) -> Level
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
	return function(use: ComposeTypes.Use?): Level
		local chosen = ctx.read(config.motionLevel, use)
		if chosen ~= nil then
			return resolve(chosen, false)
		end
		return resolve(nil, native ~= nil and (if use then use(native) else native:peek()) == true)
	end
end

local function reduced(ctx: Shared.Context): (ComposeTypes.Use?) -> boolean
	local current = level(ctx)
	return function(use: ComposeTypes.Use?): boolean
		return current(use) ~= "normal"
	end
end

return { level = level, reduced = reduced, resolve = resolve }
