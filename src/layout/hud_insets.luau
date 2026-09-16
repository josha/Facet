--!strict
local guard = require("../spec_guard")
local rect = require("../rect")
local num = require("../num")
local hud = {}
local KEYS = guard.keySet({ "bounds", "reservations" })

function hud.validateRect(r: any)
	assert(type(r) == "table", "HUD rectangle must be { x, y, w, h }")
	for _, key in { "x", "y", "w", "h" } do
		assert(num.isFinite(r[key]), `HUD rectangle.{key} must be finite`)
	end
	assert(r.w >= 0 and r.h >= 0, "HUD rectangle dimensions must be nonnegative")
end

function hud.solve(request: any): any
	guard.assertKnownKeys("layout.hudInsets", request, KEYS, "request")
	local box = request.bounds
	hud.validateRect(box)
	assert(type(request.reservations) == "table", "layout.hudInsets.reservations must be an array")
	local out = { top = 0, bottom = 0, left = 0, right = 0 }
	for _, entry in request.reservations do
		assert(out[entry.edge] ~= nil, "HUD reservation edge must be top, bottom, left, or right")
		local r = entry.rect
		hud.validateRect(r)
		if not rect.overlaps(box, r) then
			continue
		end
		local depth = if entry.edge == "top"
			then r.y + r.h - box.y
			elseif entry.edge == "bottom" then box.y + box.h - r.y
			elseif entry.edge == "left" then r.x + r.w - box.x
			else box.x + box.w - r.x
		local extent = if entry.edge == "left" or entry.edge == "right" then box.w else box.h
		out[entry.edge] = math.max(out[entry.edge], math.clamp(depth, 0, extent))
	end
	-- Opposing reservations can exhaust a box; never create negative geometry.
	out.bottom = math.min(out.bottom, box.h - out.top)
	out.right = math.min(out.right, box.w - out.left)
	return out
end

return hud
