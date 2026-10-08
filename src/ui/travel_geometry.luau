--!strict
local geometry = {}

function geometry.point(from: number, to: number, progress: number): number
	return from + (to - from) * progress
end

function geometry.arc(progress: number, height: number): number
	return -4 * height * progress * (1 - progress)
end

return geometry
