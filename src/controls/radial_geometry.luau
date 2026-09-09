--!strict
-- Clockwise degrees from north. Paint and selection share these sectors;
-- image alpha and rectangular label boxes never participate in selection.
local geometry = {}
local pathShapes = require("./path_shapes")
local slots = { N = 0, NE = 45, E = 90, SE = 135, S = 180, SW = 225, W = 270, NW = 315 }
function geometry.arc(preset: string): (number, number)
	local corners = { ["top-left"] = 90, ["top-right"] = 180, ["bottom-right"] = 270, ["bottom-left"] = 0 }
	return corners[preset] or 0, if corners[preset] then 90 else 360
end
function geometry.delta(a: number, b: number): number
	return (a - b + 180) % 360 - 180
end
function geometry.sectors(
	items: { any },
	start: number,
	sweep: number,
	distribution: string,
	inner: number,
	outer: number
): { any }
	local result, used = {}, {}
	for i, item in items do
		local angle, span
		if distribution == "compass" then
			angle = slots[item.slot]
			assert(angle ~= nil, "RadialMenu: compass items require slot N, NE, E, SE, S, SW, W, or NW")
			assert(not used[angle], "RadialMenu: conflicting compass slot " .. tostring(item.slot))
			used[angle] = true
			span = 45
			if sweep < 360 then
				local distance = (angle - start) % 360
				span = math.min(span, 2 * distance, 2 * (sweep - distance))
				assert(span > 0, "RadialMenu: corner compass slots must be inside the arc, not on its edge")
			end
		else
			span = sweep / #items
			angle = if sweep == 360 then start + (i - 1) * span else start + (i - 0.5) * span
		end
		assert(sweep == 360 or ((angle - start) % 360 <= sweep), "RadialMenu: compass slot is outside the corner arc")
		local radius = (inner + outer) / 2
		table.insert(result, {
			id = item.id,
			item = item,
			angle = angle,
			span = span,
			inner = inner,
			outer = outer,
			x = math.sin(math.rad(angle)) * radius,
			y = -math.cos(math.rad(angle)) * radius,
			size = math.min(outer - inner, 2 * radius * math.sin(math.rad(math.min(span, 180) / 2)) * 0.86),
		})
	end
	return result
end
-- Largest upright label rectangle of the requested height inside the painted
-- sector. Test the inner edge as well as the corners: a rectangle must never
-- bridge the transparent center. Padding leaves breathing room at the seams.
function geometry.labelBounds(s: any, height: number): any
	local function fits(width: number): boolean
		local hx, hy = width / 2 + 3, height / 2 + 3
		local nearX, nearY = math.max(0, math.abs(s.x) - hx), math.max(0, math.abs(s.y) - hy)
		if nearX * nearX + nearY * nearY < s.inner * s.inner then
			return false
		end
		for _, dx in { -hx, hx } do
			for _, dy in { -hy, hy } do
				local x, y = s.x + dx, s.y + dy
				if x * x + y * y > s.outer * s.outer then
					return false
				end
				if math.abs(geometry.delta(math.deg(math.atan2(x, -y)), s.angle)) > s.span / 2 - 2 then
					return false
				end
			end
		end
		return true
	end
	local lo, hi = 0, math.min(160, s.outer * 2)
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		if fits(mid) then
			lo = mid
		else
			hi = mid
		end
	end
	return { w = lo, h = height }
end
-- Fit only the paint to an upright content rectangle. Logical selection sectors
-- retain their minimum targets and stable compass directions.
function geometry.fitContent(s: any, width: number, height: number, padding: number, mode: string): any
	local fitted = table.clone(s)
	if mode == "none" then
		return fitted
	end
	local hx, hy = width / 2 + padding, height / 2 + padding
	local nx, ny = math.max(0, math.abs(s.x) - hx), math.max(0, math.abs(s.y) - hy)
	local near, far, halfAngle = math.sqrt(nx * nx + ny * ny), 0, 0
	for _, dx in { -hx, hx } do
		for _, dy in { -hy, hy } do
			local x, y = s.x + dx, s.y + dy
			far = math.max(far, math.sqrt(x * x + y * y))
			halfAngle = math.max(halfAngle, math.abs(geometry.delta(math.deg(math.atan2(x, -y)), s.angle)))
		end
	end
	if mode ~= "angular" then
		fitted.inner, fitted.outer = math.max(s.inner, near), math.min(s.outer, far)
	end
	if mode ~= "radial" then
		fitted.span = math.min(s.span, halfAngle * 2 + math.deg((s.gap or 2) / math.max(1, fitted.inner)))
	end
	return fitted
end
function geometry.hit(
	sectors: { any },
	x: number,
	y: number,
	appearance: string,
	overshoot: number?,
	previous: any?
): any
	local radius = math.sqrt(x * x + y * y)
	local angle = math.deg(math.atan2(x, -y)) % 360
	local function contains(s: any, hysteresis: number): boolean
		if radius < s.inner or radius > s.outer + (overshoot or 0) then
			return false
		end
		if appearance == "buttons" and overshoot == nil then
			return (x - s.x) ^ 2 + (y - s.y) ^ 2 <= (s.size / 2) ^ 2
		end
		return math.abs(geometry.delta(angle, s.angle)) < s.span / 2 + hysteresis
	end
	-- Never bridge an empty compass slot: hysteresis only stabilizes two assigned sectors.
	local candidate
	for i = #sectors, 1, -1 do
		local s = sectors[i]
		if contains(s, 0) then
			candidate = s
			break
		end
	end
	if candidate and previous and contains(previous, 3) then
		return previous
	end
	return candidate
end
-- Tight paint bounds let corner sectors stay inside their offered rectangle.
function geometry.paint(s: any): any
	-- Parallel butt caps, inset in pixels along the boundary tangent. Angular
	-- trimming alone makes gaps widen toward the outside of a thick ring.
	local halfGap = math.min((s.gap or 2) / 2, (s.inner + s.outer) / 2 * math.sin(math.rad(s.span / 4)))
	local trim = math.deg(math.asin(halfGap / ((s.inner + s.outer) / 2)))
	local start, span = s.angle - s.span / 2 + trim, s.span - 2 * trim
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local angles = { start, start + span }
	for angle = 0, 720, 90 do
		if (angle - start) % 360 <= span then
			table.insert(angles, angle)
		end
	end
	for _, angle in angles do
		for _, radius in { s.inner, s.outer } do
			local x, y = math.sin(math.rad(angle)) * radius, -math.cos(math.rad(angle)) * radius
			minX = math.min(minX, x)
			maxX = math.max(maxX, x)
			minY = math.min(minY, y)
			maxY = math.max(maxY, y)
		end
	end
	-- Include the corrected end-cap corners in the solved paint bounds.
	for _, edge in { -1, 1 } do
		local a = math.rad(s.angle + edge * s.span / 2)
		for _, r in { s.inner, s.outer } do
			local x = math.sin(a) * r - edge * halfGap * math.cos(a)
			local y = -math.cos(a) * r - edge * halfGap * math.sin(a)
			minX, maxX = math.min(minX, x), math.max(maxX, x)
			minY, maxY = math.min(minY, y), math.max(maxY, y)
		end
	end
	local w, h = math.max(1, maxX - minX), math.max(1, maxY - minY)
	local points = pathShapes.arc(start, span, { radius = (s.inner + s.outer) / (s.outer * 2) })
	for _, endpoint in { { 1, -1 }, { #points, 1 } } do
		local p, edge = points[endpoint[1]], endpoint[2]
		local a = math.rad(s.angle + edge * s.span / 2)
		local r = (s.inner + s.outer) / 2
		p.x = 0.5 + (math.sin(a) * r - edge * halfGap * math.cos(a)) / (2 * s.outer)
		p.y = 0.5 + (-math.cos(a) * r - edge * halfGap * math.sin(a)) / (2 * s.outer)
		local length = math.sqrt(p.outX ^ 2 + p.outY ^ 2)
		p.outX, p.outY = math.cos(a) * length, math.sin(a) * length
		p.inX, p.inY = -p.outX, -p.outY
	end
	-- Trace the entire perimeter, including the two straight butt caps. A wider
	-- copy of the center stroke only outlines the circular sides.
	local outline = {}
	for _, radius in { s.outer, s.inner } do
		local arc = pathShapes.arc(start, span, { radius = radius / s.outer })
		for _, endpoint in { { 1, -1 }, { #arc, 1 } } do
			local p, edge = arc[endpoint[1]], endpoint[2]
			local a = math.rad(s.angle + edge * s.span / 2)
			p.x = 0.5 + (math.sin(a) * radius - edge * halfGap * math.cos(a)) / (2 * s.outer)
			p.y = 0.5 + (-math.cos(a) * radius - edge * halfGap * math.sin(a)) / (2 * s.outer)
		end
		if radius == s.inner then
			local reversed = {}
			for i = #arc, 1, -1 do
				local p = arc[i]
				p.inX, p.outX = p.outX, p.inX
				p.inY, p.outY = p.outY, p.inY
				table.insert(reversed, p)
			end
			arc = reversed
		end
		arc[1].inX, arc[1].inY = 0, 0
		arc[#arc].outX, arc[#arc].outY = 0, 0
		for _, p in arc do
			table.insert(outline, p)
		end
	end
	for _, curve in { points, outline } do
		for _, p in curve do
			p.x = (p.x * 2 * s.outer - s.outer - minX) / w
			p.y = (p.y * 2 * s.outer - s.outer - minY) / h
			p.inX *= 2 * s.outer / w
			p.outX *= 2 * s.outer / w
			p.inY *= 2 * s.outer / h
			p.outY *= 2 * s.outer / h
		end
	end
	return { x = minX, y = minY, w = w, h = h, points = points, outline = outline }
end
return geometry
