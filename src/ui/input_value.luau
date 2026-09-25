--!strict
local Shared = require("./types")
export type Options = {
	min: number?,
	max: number?,
	step: Shared.Value<number>?,
	format: ((number) -> string)?,
}
export type Model = {
	min: number,
	max: number,
	quantize: (number) -> number,
	format: (number) -> string,
	fraction: (number) -> number,
	fromFraction: (number) -> number,
	stepped: (number, number) -> number,
}
export type Read = Shared.Read
local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function defaultFormat(value: number): string
	if value == 0 then
		return "0"
	end
	if value % 1 == 0 then
		return string.format("%d", value)
	end
	local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
	return if text == "-0" then "0" else text
end

return function(spec: Options, read: Read): Model
	local minimum, maximum = spec.min or 0, spec.max or 1
	assert(
		finite(minimum) and finite(maximum) and maximum > minimum,
		"Facet value control: finite min must be below max"
	)
	local function step(): number?
		local value = read(spec.step)
		assert(value == nil or (finite(value) and value > 0), "Facet value control: step must be positive and finite")
		return value
	end
	step()
	local function clamp(value: number): number
		return if finite(value) then math.clamp(value, minimum, maximum) else minimum
	end
	local function quantize(value: number): number
		local clamped, increment = clamp(value), step()
		return if increment
			then clamp(minimum + math.floor((clamped - minimum) / increment + 0.5) * increment)
			else clamped
	end
	local function format(value: number): string
		if spec.format then
			local ok, formatted = pcall(spec.format, clamp(value))
			if ok and type(formatted) == "string" then
				return formatted
			end
		end
		return defaultFormat(clamp(value))
	end
	return {
		min = minimum,
		max = maximum,
		quantize = quantize,
		format = format,
		fraction = function(value: number): number
			return (clamp(value) - minimum) / (maximum - minimum)
		end,
		fromFraction = function(fraction: number): number
			return quantize(minimum + math.clamp(fraction, 0, 1) * (maximum - minimum))
		end,
		stepped = function(value: number, direction: number): number
			local increment = step()
			local delta = (increment or (maximum - minimum) / 100) * (if direction < 0 then -1 else 1)
			local nextValue = quantize(clamp(value) + delta)
			return if increment and nextValue == quantize(value) then clamp(nextValue + delta) else nextValue
		end,
	}
end
