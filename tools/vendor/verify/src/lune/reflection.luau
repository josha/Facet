--!strict

local Environment = require "../roblox/environment"
local Adapter = require "../roblox/environment-engine"
local FixtureBridge = require "../roblox/fixture-bridge"
local Reflection = require "../roblox/reflection"
local UiFakes = require "../roblox/ui-fakes"

export type Native<V2, V3, C3, U1, U2, CF> = {
	getReflectionDatabase: () -> Reflection.Database,
	Vector2: { new: (number, number) -> V2 },
	Vector3: { new: (number, number, number) -> V3 },
	Color3: { new: (number, number, number) -> C3 },
	UDim: { new: (number, number) -> U1 },
	UDim2: { new: (number, number, number, number) -> U2 },
	CFrame: { new: (...number) -> CF },
}

export type Options = {
	ui: (UiFakes.Options | false)?,
	classes: { [string]: Environment.ClassSpec }?,
	referenceClass: ((className: string, property: string) -> string?)?,
	validateProperty: ((className: string, property: string, value: unknown, operation: "set" | "poke") -> ())?,
}

local load = require :: (string) -> unknown

local function enumType(value: unknown): string
	return tostring((value :: { EnumType: unknown }).EnumType)
end

local function createFrom<V2, V3, C3, U1, U2, CF>(native: Native<V2, V3, C3, U1, U2, CF>, options: Options?): FixtureBridge.Bridge
	local settings: Options = options or {}
	local library: Adapter.Library<V2, V3, C3, U1, U2, CF> = {
		typeName = function(value: unknown): string
			return typeof(value)
		end,
		datatypes = {
			Vector2 = native.Vector2,
			Vector3 = native.Vector3,
			Color3 = native.Color3,
			UDim = native.UDim,
			UDim2 = native.UDim2,
			CFrame = native.CFrame,
		},
	}
	return FixtureBridge.create {
		database = native.getReflectionDatabase(),
		typeName = function(value: unknown): string
			return typeof(value)
		end,
		enumType = enumType,
		library = library,
		classes = settings.classes,
		referenceClass = settings.referenceClass,
		validateProperty = settings.validateProperty,
		ui = settings.ui,
	}
end

local function create(options: Options?): FixtureBridge.Bridge
	local native = load "@lune/roblox" :: Native<unknown, unknown, unknown, unknown, unknown, unknown>
	return createFrom(native, options)
end

return {
	create = create,
	createFrom = createFrom,
}
