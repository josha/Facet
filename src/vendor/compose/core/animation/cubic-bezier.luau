--!strict
--!native

local Easing = require "./easing"

local function sample(t: number, first: number, second: number): number
	local remaining = 1 - t
	return 3 * remaining * remaining * t * first + 3 * remaining * t * t * second + t * t * t
end

return function(x1: number, y1: number, x2: number, y2: number): Easing.Easing
	for _, point in { x1, y1, x2, y2 } do
		assert(point == point and math.abs(point) < math.huge, "Compose cubicBezier needs finite control points")
	end
	assert(x1 >= 0 and x1 <= 1 and x2 >= 0 and x2 <= 1, "Compose cubicBezier x control points must be in [0, 1]")
	return function(progress: number): number
		if progress <= 0 then
			return 0
		elseif progress >= 1 then
			return 1
		end
		local low, high = 0, 1
		for _ = 1, 40 do
			local middle = (low + high) / 2
			local x = sample(middle, x1, x2)
			if x == progress then
				return sample(middle, y1, y2)
			elseif x < progress then
				low = middle
			else
				high = middle
			end
		end
		return sample((low + high) / 2, y1, y2)
	end
end
