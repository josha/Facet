--!strict
local ComposeTypes = require("../vendor/compose/core")
local Roblox = require("../vendor/compose/roblox")
local Shared = require("./types")

export type Level = Shared.MotionLevel

local RANK: { [string]: number } = { normal = 0, limited = 1, none = 2 }
local warned: { [string]: boolean } = {}
local PUBLISHED = {}

local function codecs(ctx: Shared.Context): Shared.MotionCodecs
	if ctx.motionCodecs ~= nil then
		return ctx.motionCodecs
	end
	local types = ctx.types
	local source = {
		datatypes = {
			Vector2 = types.Vector2.new,
			Vector3 = types.Vector3.new,
			Color3 = types.Color3.new,
			UDim = types.UDim.new,
			UDim2 = types.UDim2.new,
			CFrame = function(position: { X: number, Y: number, Z: number }, rotation: { number })
				return types.CFrame.new(
					position.X,
					position.Y,
					position.Z,
					rotation[1],
					rotation[2],
					rotation[3],
					rotation[4],
					rotation[5],
					rotation[6],
					rotation[7],
					rotation[8],
					rotation[9]
				)
			end,
		},
		readCFrame = function(value: CFrame)
			local parts = { value:GetComponents() }
			return parts[1],
				parts[2],
				parts[3],
				{
					parts[4],
					parts[5],
					parts[6],
					parts[7],
					parts[8],
					parts[9],
					parts[10],
					parts[11],
					parts[12],
				}
		end,
	}
	local native = (Roblox.codecs((source :: unknown) :: Roblox.CodecSource) :: unknown) :: Shared.MotionCodecs
	ctx.motionCodecs = native
	return native
end

local function forValue<T>(ctx: Shared.Context, value: T): ComposeTypes.Motion<T>
	if type(value) == "number" then
		return ctx.runtime.motion((ctx.Compose.numberCodec :: unknown) :: ComposeTypes.Codec<T>)
	end
	local native = codecs(ctx)
	local typeOf: (unknown) -> string = ctx.runtime.host.typeNameOf or typeof
	local kind = typeOf(value)
	local codec = if kind == "Vector2"
		then native.Vector2
		elseif kind == "Vector3" then native.Vector3
		elseif kind == "Color3" then native.Color3
		elseif kind == "UDim" then native.UDim
		elseif kind == "UDim2" then native.UDim2
		elseif kind == "CFrame" then native.CFrame
		else nil
	assert(codec ~= nil, "Facet motion requires a number or a supported Roblox datatype")
	return ctx.runtime.motion((codec :: unknown) :: ComposeTypes.Codec<T>)
end

local function check(value: unknown)
	if value ~= nil and value ~= "normal" and value ~= "limited" and value ~= "none" then
		error(`Facet motionLevel must be "normal", "limited" or "none", got {tostring(value)}`, 0)
	end
end

local function resolve(chosen: unknown, engineReduced: boolean): Level
	local device: Level = if engineReduced then "limited" else "normal"
	if chosen == nil then
		return device
	end
	if chosen ~= "normal" and chosen ~= "limited" and chosen ~= "none" then
		local key = tostring(chosen)
		if not warned[key] then
			warned[key] = true
			warn(`Facet motionLevel must be "normal", "limited" or "none", got {key}; following the device`)
		end
		return device
	end
	return if RANK[chosen] > RANK[device] then chosen else device
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
	local native = if gui then ctx.observe.ReducedMotionEnabled(gui) else nil
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
	forValue = forValue,
	level = level,
	reduced = reduced,
	resolve = resolve,
	check = check,
	publish = publish,
	published = publishedFor,
}
