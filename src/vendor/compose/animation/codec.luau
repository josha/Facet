--!strict

local Diagnostics = require "../diagnostics"

export type Codec<T> = {
	arity: number,

	encode: (value: T, out: { number }) -> (),
	decode: (components: { number }) -> T,

	normalise: ((components: { number }) -> ())?,
}

local registry: { [string]: Codec<any> } = {}

local function register<T>(typeName: string, codec: Codec<T>)
	if type(typeName) ~= "string" or typeName == "" then
		Diagnostics.raise("animation/codec-unnamed", "registerCodec expects a type name", {
			actual = Diagnostics.describe(typeName),
			expected = "the string typeof() returns for the values this codec handles",
		})
	end
	if type(codec) ~= "table" or type(codec.arity) ~= "number" or codec.arity < 1 then
		Diagnostics.raise("animation/codec-invalid", ("the codec for %s is not usable"):format(typeName), {
			contract = "a codec needs a positive arity, an encode, and a decode",
		})
	end
	if type(codec.encode) ~= "function" or type(codec.decode) ~= "function" then
		Diagnostics.raise("animation/codec-invalid", ("the codec for %s is not usable"):format(typeName), {
			contract = "a codec needs a positive arity, an encode, and a decode",
		})
	end
	registry[typeName] = codec
end

local function codecFor(typeName: string): Codec<any>
	local codec = registry[typeName]
	if codec == nil then
		Diagnostics.raise("animation/no-codec", ("nothing knows how to animate a %s"):format(typeName), {
			actual = typeName,
			contract = "animating a value requires a registered codec",
			fix = ("call Compose.registerCodec(%q, ...), or animate the numbers inside it"):format(typeName),
		})
	end
	return codec :: Codec<any>
end

local function isAnimatable(typeName: string): boolean
	return registry[typeName] ~= nil
end

local function registered(): { string }
	local names: { string } = {}
	for name in registry do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

register("number", {
	arity = 1,
	encode = function(value: number, out: { number })
		out[1] = value
	end,
	decode = function(components: { number }): number
		return components[1]
	end,
})

return {
	register = register,
	codecFor = codecFor,
	isAnimatable = isAnimatable,
	registered = registered,
}
