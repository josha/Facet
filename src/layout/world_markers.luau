--!strict
local guard = require("../spec_guard")
local num = require("../num")
local rect = require("../rect")
local hud = require("./hud_insets")
local markers = {}
local KEYS = guard.keySet({ "bounds", "markers", "exclusions", "gap" })
local MARKER_KEYS = guard.keySet({ "id", "x", "y", "width", "height", "priority", "visible" })
local OFFSETS = { { 0, 0 }, { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 } }

function markers.solve(request: any): { any }
	guard.assertKnownKeys("layout.worldMarkers", request, KEYS, "request")
	local bounds, gap = request.bounds, request.gap or 8
	hud.validateRect(bounds)
	assert(num.isFinite(gap) and gap >= 0, "layout.worldMarkers.gap must be nonnegative pixels")
	assert(type(request.markers) == "table", "layout.worldMarkers.markers must be an array")
	assert(
		request.exclusions == nil or type(request.exclusions) == "table",
		"layout.worldMarkers.exclusions must be an array"
	)
	local ordered, seen, occupied = {}, {}, {}
	for _, exclusion in request.exclusions or {} do
		hud.validateRect(exclusion)
		table.insert(
			occupied,
			{ x = exclusion.x - gap / 2, y = exclusion.y - gap / 2, w = exclusion.w + gap, h = exclusion.h + gap }
		)
	end
	for index, marker in request.markers do
		guard.assertKnownKeys("layout.worldMarkers marker", marker, MARKER_KEYS, "spec")
		assert(
			type(marker.id) == "string" and #marker.id > 0 and not seen[marker.id],
			"World marker ids must be nonempty and unique"
		)
		seen[marker.id] = true
		assert(marker.visible == nil or type(marker.visible) == "boolean", "World marker visible must be boolean")
		assert(
			num.isFinite(marker.width) and marker.width > 0 and num.isFinite(marker.height) and marker.height > 0,
			"World marker dimensions must be positive pixels"
		)
		assert(marker.priority == nil or num.isFinite(marker.priority), "World marker priority must be finite")
		if marker.visible ~= false then
			assert(num.isFinite(marker.x) and num.isFinite(marker.y), "Visible world marker coordinates must be finite")
		end
		table.insert(ordered, { marker = marker, index = index })
	end
	table.sort(ordered, function(a, b)
		local ap, bp = a.marker.priority or 0, b.marker.priority or 0
		return if ap == bp then a.index < b.index else ap > bp
	end)
	local result = {}
	for _, entry in ordered do
		local m = entry.marker
		local row: any = { id = m.id, visible = false }
		if m.visible == false then
			row.reason = "unavailable"
		elseif m.width > bounds.w or m.height > bounds.h then
			row.reason = "tooLarge"
		else
			local cx, cy = rect.centre(bounds)
			local dx, dy = m.x - cx, m.y - cy
			local halfW, halfH = (bounds.w - m.width) / 2, (bounds.h - m.height) / 2
			local edge = math.abs(dx) > halfW or math.abs(dy) > halfH
			local scale = 1
			if edge then
				if dx ~= 0 then
					scale = math.min(scale, halfW / math.abs(dx))
				end
				if dy ~= 0 then
					scale = math.min(scale, halfH / math.abs(dy))
				end
			end
			local baseX, baseY = cx + dx * scale - m.width / 2, cy + dy * scale - m.height / 2
			row.edge, row.angle = edge, math.deg(math.atan2(dx, -dy)) % 360
			for _, offset in OFFSETS do
				local r = {
					x = math.clamp(baseX + offset[1] * (m.width + gap), bounds.x, bounds.x + bounds.w - m.width),
					y = math.clamp(baseY + offset[2] * (m.height + gap), bounds.y, bounds.y + bounds.h - m.height),
					w = m.width,
					h = m.height,
				}
				if
					edge
					and math.min(
							math.abs(r.x - bounds.x),
							math.abs(r.y - bounds.y),
							math.abs(r.x + r.w - bounds.x - bounds.w),
							math.abs(r.y + r.h - bounds.y - bounds.h)
						)
						> 0.01
				then
					continue
				end
				local padded = { x = r.x - gap / 2, y = r.y - gap / 2, w = r.w + gap, h = r.h + gap }
				local clear = true
				for _, other in occupied do
					if rect.overlaps(padded, other) then
						clear = false
						break
					end
				end
				if clear then
					row.rect, row.visible = r, true
					table.insert(occupied, padded)
					break
				end
			end
			if not row.visible then
				row.reason = "crowded"
			end
		end
		table.insert(result, row)
	end
	return result
end

return markers
