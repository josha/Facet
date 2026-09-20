--!strict
--!native

export type Easing = (t: number) -> number

local function linear(t: number): number
	return t
end

local function flip(ease: Easing): Easing
	return function(t: number): number
		return 1 - ease(1 - t)
	end
end

local function mirror(ease: Easing): Easing
	return function(t: number): number
		if t < 0.5 then
			return ease(t * 2) / 2
		end
		return 1 - ease((1 - t) * 2) / 2
	end
end

local function power(exponent: number): Easing
	return function(t: number): number
		return t ^ exponent
	end
end

local function inSine(t: number): number
	return 1 - math.cos((t * math.pi) / 2)
end

local function inExpo(t: number): number
	if t <= 0 then
		return 0
	end
	return 2 ^ (10 * (t - 1))
end

local function inCirc(t: number): number
	return 1 - math.sqrt(math.max(0, 1 - t * t))
end

local function inBack(t: number): number
	local overshoot = 1.70158
	return t * t * ((overshoot + 1) * t - overshoot)
end

local function inElastic(t: number): number
	if t <= 0 then
		return 0
	end
	if t >= 1 then
		return 1
	end
	return -(2 ^ (10 * (t - 1))) * math.sin(((t - 1) * 10 - 0.75) * ((2 * math.pi) / 3))
end

local function outBounce(t: number): number
	local n, d = 7.5625, 2.75
	if t < 1 / d then
		return n * t * t
	elseif t < 2 / d then
		local shifted = t - 1.5 / d
		return n * shifted * shifted + 0.75
	elseif t < 2.5 / d then
		local shifted = t - 2.25 / d
		return n * shifted * shifted + 0.9375
	end
	local shifted = t - 2.625 / d
	return n * shifted * shifted + 0.984375
end

local inQuad, inCubic, inQuart, inQuint = power(2), power(3), power(4), power(5)
local inBounce = flip(outBounce)

local easing = table.freeze {
	linear = linear,

	inQuad = inQuad,
	outQuad = flip(inQuad),
	inOutQuad = mirror(inQuad),

	inCubic = inCubic,
	outCubic = flip(inCubic),
	inOutCubic = mirror(inCubic),

	inQuart = inQuart,
	outQuart = flip(inQuart),
	inOutQuart = mirror(inQuart),

	inQuint = inQuint,
	outQuint = flip(inQuint),
	inOutQuint = mirror(inQuint),

	inSine = inSine,
	outSine = flip(inSine),
	inOutSine = mirror(inSine),

	inExpo = inExpo,
	outExpo = flip(inExpo),
	inOutExpo = mirror(inExpo),

	inCirc = inCirc,
	outCirc = flip(inCirc),
	inOutCirc = mirror(inCirc),

	inBack = inBack,
	outBack = flip(inBack),
	inOutBack = mirror(inBack),

	inElastic = inElastic,
	outElastic = flip(inElastic),
	inOutElastic = mirror(inElastic),

	inBounce = inBounce,
	outBounce = outBounce,
	inOutBounce = mirror(inBounce),
}

return easing
