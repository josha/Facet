--!strict

local Diagnostics = require "../diagnostics"

export type Codec<T> = {
	arity: number,

	encode: (value: T, out: { number }) -> (),
	decode: (components: { number }) -> T,

	normalise: ((components: { number }) -> ())?,
}

local numberCodec: Codec<number> = {
	arity = 1,
	encode = function(value: number, out: { number })
		if type(value) ~= "number" then
			return Diagnostics.raise("animation/no-codec", "numeric motion requires a number", {
				actual = Diagnostics.describe(value),
				fix = "select runtime.motion(codec) for another value type",
			})
		end
		out[1] = value
	end,
	decode = function(components: { number }): number
		return components[1]
	end,
}

local function validate<T>(codec: Codec<T>)
	if type(codec) ~= "table" or type(codec.arity) ~= "number" or codec.arity < 1 or codec.arity % 1 ~= 0 then
		return Diagnostics.raise("animation/codec-invalid", "the motion codec is not usable", {
			contract = "a codec needs a positive integer arity, an encode, and a decode",
		})
	end
	if type(codec.encode) ~= "function" or type(codec.decode) ~= "function" then
		return Diagnostics.raise("animation/codec-invalid", "the motion codec is not usable", {
			contract = "a codec needs a positive integer arity, an encode, and a decode",
		})
	end
end

return {
	number = numberCodec,
	validate = validate,
}
