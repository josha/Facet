--!strict
local freeze = require("./freeze")
local placement = {}

export type Rect = { x: number, y: number, w: number, h: number }
export type Request = {
	source: Rect,
	size: { w: number, h: number },
	safe: Rect,
	edge: string?,
	align: string?,
	gap: number?,
	crossOffset: number?,
	tail: number?,
	tailInset: number?,
	overflow: string?,
}
export type Placement = {
	x: number,
	y: number,
	w: number,
	h: number,
	edge: string,
	flipped: boolean,
	shift: number,
	fits: boolean,
	tailX: number?,
	tailY: number?,
	tailSuppressed: boolean,
}

local EDGES: { [string]: boolean } = freeze({ top = true, bottom = true, leading = true, trailing = true })
local ALIGNS: { [string]: boolean } = freeze({ start = true, center = true, ["end"] = true })
local OPPOSITE: { [string]: string } = freeze({ top = "bottom", bottom = "top", left = "right", right = "left" })

function placement.assertEdge(edge: unknown, where: string)
	if edge ~= nil and (type(edge) ~= "string" or not EDGES[edge]) then
		error(`Facet {where}: edge must be top, bottom, leading or trailing (got {tostring(edge)})`, 0)
	end
end

function placement.assertAlign(align: unknown, where: string)
	if align ~= nil and (type(align) ~= "string" or not ALIGNS[align]) then
		error(`Facet {where}: align must be start, center or end (got {tostring(align)})`, 0)
	end
end

function placement.assertCrossOffset(offset: unknown, where: string)
	if offset ~= nil and (type(offset) ~= "number" or offset ~= offset or math.abs(offset :: number) == math.huge) then
		error(`Facet {where}: crossOffset must be a finite number of pixels (got {tostring(offset)})`, 0)
	end
end

local function resolveEdge(edge: string): string
	return if edge == "leading" then "left" elseif edge == "trailing" then "right" else edge
end

local function vertical(edge: string): boolean
	return edge == "top" or edge == "bottom"
end

function placement.solve(request: Request): Placement
	placement.assertEdge(request.edge, "placement")
	placement.assertAlign(request.align, "placement")
	placement.assertCrossOffset(request.crossOffset, "placement")
	local source, size, safe = request.source, request.size, request.safe
	local gap = request.gap or 0
	local tail = math.max(request.tail or 0, 0)
	local tailInset = math.max(request.tailInset or 0, 0)
	local align = request.align or "center"
	local preferred = resolveEdge(request.edge or "bottom")
	local function mainFor(edge: string): number
		if edge == "bottom" then
			return source.y + source.h + gap
		elseif edge == "top" then
			return source.y - gap - size.h
		elseif edge == "right" then
			return source.x + source.w + gap
		end
		return source.x - gap - size.w
	end
	local function fitsOn(edge: string): boolean
		local m = mainFor(edge)
		if vertical(edge) then
			return m >= safe.y and m + size.h <= safe.y + safe.h
		end
		return m >= safe.x and m + size.w <= safe.x + safe.w
	end
	local resolved, flipped = preferred, false
	if not fitsOn(preferred) then
		local other = OPPOSITE[preferred]
		if fitsOn(other) then
			resolved, flipped = other, true
		else
			local sides: { string } = if vertical(preferred) then { "right", "left" } else { "bottom", "top" }
			for _, side in sides do
				local across = if vertical(side) then size.w <= safe.w else size.h <= safe.h
				if across and fitsOn(side) then
					resolved, flipped = side, true
					break
				end
			end
		end
	end
	local isVertical = vertical(resolved)
	local edgePosition = mainFor(resolved)
	local mainExtent = if isVertical then size.h else size.w
	local mainLow = if isVertical then safe.y else safe.x
	local mainHigh = mainLow + (if isVertical then safe.h else safe.w) - mainExtent
	local main = edgePosition
	if request.overflow ~= "keep" then
		main = math.clamp(main, mainLow, math.max(mainLow, mainHigh))
	end
	local alongExtent = if isVertical then size.w else size.h
	local sourceLow = if isVertical then source.x else source.y
	local sourceExtent = if isVertical then source.w else source.h
	local aligned = if align == "start"
		then sourceLow
		elseif align == "end" then sourceLow + sourceExtent - alongExtent
		else sourceLow + sourceExtent / 2 - alongExtent / 2
	aligned += request.crossOffset or 0
	local alongLow = if isVertical then safe.x else safe.y
	local alongHigh = alongLow + (if isVertical then safe.w else safe.h) - alongExtent
	local along = math.clamp(aligned, alongLow, math.max(alongLow, alongHigh))
	local rect = if isVertical
		then { x = along, y = main, w = size.w, h = size.h }
		else { x = main, y = along, w = size.w, h = size.h }
	local fits = rect.x >= safe.x
		and rect.y >= safe.y
		and rect.x + rect.w <= safe.x + safe.w
		and rect.y + rect.h <= safe.y + safe.h
	local tailX: number?, tailY: number? = nil, nil
	local suppressed = true
	if tail > 0 then
		local half = tail / 2
		local low, high = along + tailInset + half, along + alongExtent - tailInset - half
		if high >= low then
			local centre = math.clamp(sourceLow + sourceExtent / 2, low, high)
			suppressed = main ~= edgePosition or centre < sourceLow or centre > sourceLow + sourceExtent
			if isVertical then
				tailX, tailY = centre, if resolved == "bottom" then rect.y else rect.y + rect.h
			else
				tailX, tailY = if resolved == "right" then rect.x else rect.x + rect.w, centre
			end
		end
	end
	return {
		x = rect.x,
		y = rect.y,
		w = rect.w,
		h = rect.h,
		edge = resolved,
		flipped = flipped,
		shift = along - aligned,
		fits = fits,
		tailX = tailX,
		tailY = tailY,
		tailSuppressed = suppressed,
	}
end

return placement
