--!strict
local spatial = { RADIUS = 37, CENTER_Z = -36.3, HEIGHT = 7, STEP = math.rad(18) }

function spatial.pose(index: number, count: number): (number, number, number)
	local yaw = ((count + 1) / 2 - index) * spatial.STEP
	return spatial.RADIUS * math.sin(yaw), spatial.CENTER_Z + spatial.RADIUS * math.cos(yaw), yaw
end

return spatial
