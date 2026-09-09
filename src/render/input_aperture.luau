--!strict
-- Four ordinary native input rectangles around a transparent rectangular aperture.
-- Shared by a control's capture plane and the presenter's outside-tap catcher.
local aperture = {}
function aperture.contains(r: any, x: any, y: any): boolean
	return r ~= nil
		and type(x) == "number"
		and type(y) == "number"
		and x >= r.x
		and y >= r.y
		and x < r.x + r.w
		and y < r.y + r.h
end
function aperture.rects(outer: any, hole: any): { any }
	if not hole then
		return { { id = "all", x = outer.x, y = outer.y, w = outer.w, h = outer.h } }
	end
	local x1 = math.clamp(hole.x, outer.x, outer.x + outer.w)
	local x2 = math.clamp(hole.x + hole.w, x1, outer.x + outer.w)
	local y1 = math.clamp(hole.y, outer.y, outer.y + outer.h)
	local y2 = math.clamp(hole.y + hole.h, y1, outer.y + outer.h)
	return {
		{ id = "top", x = outer.x, y = outer.y, w = outer.w, h = y1 - outer.y },
		{ id = "bottom", x = outer.x, y = y2, w = outer.w, h = outer.y + outer.h - y2 },
		{ id = "left", x = outer.x, y = y1, w = x1 - outer.x, h = y2 - y1 },
		{ id = "right", x = x2, y = y1, w = outer.x + outer.w - x2, h = y2 - y1 },
	}
end
return aperture
