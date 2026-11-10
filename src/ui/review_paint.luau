--!strict
local Rules = require("./review_rules")

type Rect = Rules.ReviewRect
export type Box = { x0: number, y0: number, x1: number, y1: number, width: number, height: number }
export type Slice = { x0: number, y0: number, x1: number, y1: number, scale: number }

local PAINT_ALPHA = 26

local function measure(pixels: buffer, width: number, height: number): Box
	local x0: number, y0: number, x1: number, y1: number = width, height, 0, 0
	for y = 0, height - 1 do
		local alpha = y * width * 4 + 3
		for x = 0, width - 1 do
			if buffer.readu8(pixels, alpha) >= PAINT_ALPHA then
				if x < x0 then
					x0 = x
				end
				if x >= x1 then
					x1 = x + 1
				end
				if y < y0 then
					y0 = y
				end
				y1 = y + 1
			end
			alpha += 4
		end
	end
	if x1 <= x0 or y1 <= y0 then
		x0, y0, x1, y1 = 0, 0, 0, 0
	end
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, width = width, height = height }
end

local function sliced(point: number, size: number, low: number, high: number, scale: number, length: number): number
	local borders = low + size - high
	local unit = if borders > 0 and borders * scale > length then length / borders else scale
	if point <= low then
		return point * unit
	elseif point >= high then
		return length - (size - point) * unit
	end
	return low * unit + (point - low) / (high - low) * (length - borders * unit)
end

local function place(rect: Rect, box: Box, mode: string, slice: Slice?, quarter: number): Rect
	local centerX, centerY = rect.x + rect.width / 2, rect.y + rect.height / 2
	if box.x1 <= box.x0 or box.y1 <= box.y0 or box.width <= 0 or box.height <= 0 then
		return { x = centerX, y = centerY, width = 0, height = 0 }
	end
	local left, top, right, bottom = 0, 0, rect.width, rect.height
	if mode == "Slice" and slice ~= nil and slice.x1 > slice.x0 and slice.y1 > slice.y0 then
		left = sliced(box.x0, box.width, slice.x0, slice.x1, slice.scale, rect.width)
		right = sliced(box.x1, box.width, slice.x0, slice.x1, slice.scale, rect.width)
		top = sliced(box.y0, box.height, slice.y0, slice.y1, slice.scale, rect.height)
		bottom = sliced(box.y1, box.height, slice.y0, slice.y1, slice.scale, rect.height)
	elseif mode ~= "Tile" then
		local across, down = rect.width / box.width, rect.height / box.height
		if mode == "Fit" then
			across = math.min(across, down)
			down = across
		elseif mode == "Crop" then
			across = math.max(across, down)
			down = across
		end
		local originX = (rect.width - box.width * across) / 2
		local originY = (rect.height - box.height * down) / 2
		left = math.max(0, originX + box.x0 * across)
		right = math.min(rect.width, originX + box.x1 * across)
		top = math.max(0, originY + box.y0 * down)
		bottom = math.min(rect.height, originY + box.y1 * down)
	end
	local x0, x1 = left - rect.width / 2, right - rect.width / 2
	local y0, y1 = top - rect.height / 2, bottom - rect.height / 2
	for _ = 1, quarter % 4 do
		x0, x1, y0, y1 = -y1, -y0, x0, x1
	end
	return { x = centerX + x0, y = centerY + y0, width = math.max(0, x1 - x0), height = math.max(0, y1 - y0) }
end

return table.freeze({ measure = measure, place = place })
