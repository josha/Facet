--!strict
local spatial = { RADIUS = 37, CENTER_Z = -36.3, HEIGHT = 7, STEP = math.rad(18) }

function spatial.pose(index: number, count: number): (number, number, number)
	local yaw = ((count + 1) / 2 - index) * spatial.STEP
	return spatial.RADIUS * math.sin(yaw), spatial.CENTER_Z + spatial.RADIUS * math.cos(yaw), yaw
end

function spatial.canvasSize(viewportWidth: number): (number, number)
	local width = math.min(920, math.max(1, math.floor(viewportWidth)))
	return width, math.floor(width * 640 / 920 + 0.5)
end

function spatial.contentHeight(viewportWidth: number, viewportHeight: number): number
	local _, canvasHeight = spatial.canvasSize(viewportWidth)
	return if viewportWidth < 700 then math.max(canvasHeight, viewportHeight) else canvasHeight
end

return spatial
