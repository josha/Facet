--!strict
local ComposeTypes = require("../vendor/compose/core")
local Shared = require("./types")

type Acquire = () -> ComposeTypes.Cell<boolean>
export type Level = Shared.MotionLevel

local RANK = { normal = 0, limited = 1, none = 2 }
local warned: { [string]: boolean } = {}
local PUBLISHED = {}

local function check(value: unknown)
	if value ~= nil and (type(value) ~= "string" or RANK[value :: string] == nil) then
		error(`Facet motionLevel must be "normal", "limited" or "none", got {tostring(value)}`, 0)
	end
end

local function resolve(chosen: unknown, engineReduced: boolean): Level
	local device: Level = if engineReduced then "limited" else "normal"
	if chosen == nil then
		return device
	end
	if type(chosen) ~= "string" or RANK[chosen :: string] == nil then
		local key = tostring(chosen)
		if not warned[key] then
			warned[key] = true
			warn(`Facet motionLevel must be "normal", "limited" or "none", got {key}; following the device`)
		end
		return device
	end
	return if RANK[chosen :: string] > RANK[device] then chosen :: Level else device
end

local function publish(Compose: typeof(ComposeTypes), runtime: unknown, value: unknown)
	if value == nil then
		return
	end
	local owner = runtime :: { [unknown]: { unknown }? }
	local list = owner[PUBLISHED] or {}
	owner[PUBLISHED] = list
	local entry = { value }
	table.insert(list, entry)
	if Compose.currentOwner() ~= nil then
		Compose.cleanup(function()
			local at = table.find(list, entry)
			if at then
				table.remove(list, at)
			end
		end)
	end
end

local function publishedFor(runtime: unknown): { unknown }
	local out = {}
	local list: { { unknown } } = (runtime :: { [unknown]: { { unknown } }? })[PUBLISHED] or {}
	for _, entry in list do
		table.insert(out, entry[1])
	end
	return out
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
		return resolve(
			ctx.read(config.motionLevel, use),
			native ~= nil and (if use then use(native) else native:peek()) == true
		)
	end
end

local function reduced(ctx: Shared.Context): (ComposeTypes.Use?) -> boolean
	local current = level(ctx)
	return function(use: ComposeTypes.Use?): boolean
		return current(use) ~= "normal"
	end
end

return {
	level = level,
	reduced = reduced,
	resolve = resolve,
	check = check,
	publish = publish,
	published = publishedFor,
}
