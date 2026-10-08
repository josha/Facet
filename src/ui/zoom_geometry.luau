--!strict
local Types = require("./zoom_travel_types")

local geometry = {}

function geometry.fit(width: number, height: number, contentWidth: number, contentHeight: number): number
	return math.min(width / contentWidth, height / contentHeight)
end

function geometry.axis(window: number, content: number, scale: number, point: number, screen: number): (number, number)
	local extent = content * scale
	local inset = math.max(0, (window - extent) / 2)
	return math.clamp(point * scale + inset - screen, 0, math.max(0, extent - window)), inset
end

function geometry.point(scale: number, offset: number, inset: number, screen: number): number
	return (screen + offset - inset) / scale
end

function geometry.rectangle(windowWidth: number, windowHeight: number, rect: Types.Rect): number
	assert(
		rect.w > 0 and rect.h > 0 and rect.w < math.huge and rect.h < math.huge,
		"ZoomView rectangle must have positive finite dimensions"
	)
	assert(
		rect.x == rect.x and rect.y == rect.y and math.abs(rect.x) < math.huge and math.abs(rect.y) < math.huge,
		"ZoomView rectangle must have finite coordinates"
	)
	return math.min(windowWidth / rect.w, windowHeight / rect.h)
end

return geometry
