--!strict
--!native

local ImageModule = require("./image")
local Numeric = require("./numeric")

type Image = ImageModule.Image

export type Ink = { number }

local f32 = Numeric.f32
local trunc = Numeric.trunc

local Draw = {}

local function hline(image: Image, x0: number, y: number, x1: number, ink: Ink)
	if y < 0 or y >= image.height then
		return
	end
	if x0 < 0 then
		x0 = 0
	elseif x0 >= image.width then
		return
	end
	if x1 < 0 then
		return
	elseif x1 >= image.width then
		x1 = image.width - 1
	end
	if x0 > x1 then
		return
	end
	local channels = image.channels
	local data = image.data
	local row = y * image.width
	if channels == 1 then
		buffer.fill(data, row + x0, ink[1], x1 - x0 + 1)
	else
		for x = x0, x1 do
			local offset = (row + x) * channels
			for channel = 0, channels - 1 do
				buffer.writeu8(data, offset + channel, ink[channel + 1])
			end
		end
	end
end

local function point(image: Image, x: number, y: number, ink: Ink)
	if x >= 0 and x < image.width and y >= 0 and y < image.height then
		local channels = image.channels
		local offset = (y * image.width + x) * channels
		for channel = 0, channels - 1 do
			buffer.writeu8(image.data, offset + channel, ink[channel + 1])
		end
	end
end

local function thinLine(image: Image, x0: number, y0: number, x1: number, y1: number, ink: Ink)
	local dx = x1 - x0
	local xs = 1
	if dx < 0 then
		dx = -dx
		xs = -1
	end
	local dy = y1 - y0
	local ys = 1
	if dy < 0 then
		dy = -dy
		ys = -1
	end
	if dx == 0 then
		for _ = 1, dy do
			point(image, x0, y0, ink)
			y0 += ys
		end
	elseif dy == 0 then
		for _ = 1, dx do
			point(image, x0, y0, ink)
			x0 += xs
		end
	elseif dx > dy then
		local n = dx
		dy += dy
		local e = dy - dx
		dx += dx
		for _ = 1, n do
			point(image, x0, y0, ink)
			if e >= 0 then
				y0 += ys
				e -= dx
			end
			e += dy
			x0 += xs
		end
	else
		local n = dy
		dx += dx
		local e = dx - dy
		dy += dy
		for _ = 1, n do
			point(image, x0, y0, ink)
			if e >= 0 then
				x0 += xs
				e -= dy
			end
			e += dx
			y0 += ys
		end
	end
end

type Edge = {
	x0: number,
	y0: number,
	xmin: number,
	ymin: number,
	xmax: number,
	ymax: number,
	dx: number,
}

local function newEdge(x0: number, y0: number, x1: number, y1: number): Edge
	local edge: Edge = {
		x0 = x0,
		y0 = y0,
		xmin = math.min(x0, x1),
		xmax = math.max(x0, x1),
		ymin = math.min(y0, y1),
		ymax = math.max(y0, y1),
		dx = 0,
	}
	if y0 ~= y1 then
		edge.dx = f32(f32(x1 - x0) / f32(y1 - y0))
	end
	return edge
end

local function edgeX(edge: Edge, y: number): number
	return f32(f32((y - edge.y0) * edge.dx) + edge.x0)
end

local function fillEdges(image: Image, edges: { Edge }, ink: Ink)
	local count = #edges
	if count == 0 then
		return
	end
	local table_: { Edge } = {}
	local ymin = image.height - 1
	local ymax = 0
	for _, edge in edges do
		if ymin > edge.ymin then
			ymin = edge.ymin
		end
		if ymax < edge.ymax then
			ymax = edge.ymax
		end
		if edge.ymin == edge.ymax then
			hline(image, edge.xmin, edge.ymin, edge.xmax, ink)
		else
			table.insert(table_, edge)
		end
	end
	if ymin < 0 then
		ymin = 0
	end
	if ymax > image.height then
		ymax = image.height
	end
	local xs: { number } = {}
	for y = ymin, ymax do
		table.clear(xs)
		local j = 0
		for i, current in table_ do
			if y >= current.ymin and y <= current.ymax then
				j += 1
				xs[j] = edgeX(current, y)
				if y == current.ymax and y < ymax then
					j += 1
					xs[j] = xs[j - 1]
				elseif (y == current.ymin or y == current.ymax) and current.dx ~= 0 then
					for k = 1, i - 1 do
						local other = table_[k]
						if (y ~= other.ymin and y ~= other.ymax) or other.dx == 0 then
							continue
						end
						if Numeric.roundHalfAway(xs[j]) == Numeric.roundHalfAway(edgeX(other, y)) then
							local offset = if y == current.ymax then -1 else 1
							local adjacent = edgeX(current, y + offset)
							if y + offset >= other.ymin and y + offset <= other.ymax then
								local adjacentOther = edgeX(other, y + offset)
								if xs[j] > f32(adjacent + 1) and xs[j] > f32(adjacentOther + 1) then
									xs[j] = f32(Numeric.roundHalfAway(math.max(adjacent, adjacentOther)) + 1)
								elseif xs[j] < f32(adjacent - 1) and xs[j] < f32(adjacentOther - 1) then
									xs[j] = f32(Numeric.roundHalfAway(math.min(adjacent, adjacentOther)) - 1)
								end
								break
							end
						end
					end
				end
			end
		end
		if j > 1 then
			table.sort(xs)
		end
		for i = 2, j, 2 do
			hline(image, Numeric.roundUpF32(xs[i - 1]), y, Numeric.roundDownF32(xs[i]), ink)
		end
	end
end

local function wideLine(image: Image, x0: number, y0: number, x1: number, y1: number, ink: Ink, width: number)
	local dx = x1 - x0
	local dy = y1 - y0
	if dx == 0 and dy == 0 then
		point(image, x0, y0, ink)
		return
	end
	local big = math.sqrt(dx * dx + dy * dy)
	local small = (width - 1) / 2.0
	local ratioMax = Numeric.roundUp(small) / big
	local ratioMin = Numeric.roundDown(small) / big
	local dxmin = Numeric.roundDown(ratioMin * dy)
	local dxmax = Numeric.roundDown(ratioMax * dy)
	local dymin = Numeric.roundDown(ratioMin * dx)
	local dymax = Numeric.roundDown(ratioMax * dx)
	local ax, ay = x0 - dxmin, y0 + dymax
	local bx, by = x1 - dxmin, y1 + dymax
	local cx, cy = x1 + dxmax, y1 - dymin
	local ex, ey = x0 + dxmax, y0 - dymin
	fillEdges(image, {
		newEdge(ax, ay, bx, by),
		newEdge(bx, by, cx, cy),
		newEdge(cx, cy, ex, ey),
		newEdge(ex, ey, ax, ay),
	}, ink)
end

local function rectangle(
	image: Image,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	ink: Ink,
	fill: boolean,
	width: number
)
	if y0 > y1 then
		y0, y1 = y1, y0
	end
	if fill then
		if y0 < 0 then
			y0 = 0
		elseif y0 >= image.height then
			return
		end
		if y1 < 0 then
			return
		elseif y1 > image.height then
			y1 = image.height
		end
		for y = y0, y1 do
			hline(image, x0, y, x1, ink)
		end
	else
		if width == 0 then
			width = 1
		end
		for i = 0, width - 1 do
			hline(image, x0, y0 + i, x1, ink)
			hline(image, x0, y1 - i, x1, ink)
			thinLine(image, x1 - i, y0 + width, x1 - i, y1 - width + 1, ink)
			thinLine(image, x0 + i, y0 + width, x0 + i, y1 - width + 1, ink)
		end
	end
end

local function polygonFill(image: Image, xy: { number }, ink: Ink)
	local count = #xy // 2
	if count <= 0 then
		return
	end
	local edges: { Edge } = {}
	local i = 0
	while i < count - 1 do
		local x0 = xy[i * 2 + 1]
		local y0 = xy[i * 2 + 2]
		local x1 = xy[i * 2 + 3]
		local y1 = xy[i * 2 + 4]
		local merged = false
		if y0 == y1 and i ~= 0 and y0 == xy[i * 2] then
			local last = edges[#edges]
			if x1 > x0 and x0 > xy[i * 2 - 1] then
				last.xmax = x1
				merged = true
			elseif x1 < x0 and x0 < xy[i * 2 - 1] then
				last.xmin = x1
				merged = true
			end
		end
		if not merged then
			table.insert(edges, newEdge(x0, y0, x1, y1))
		end
		i += 1
	end
	if xy[i * 2 + 1] ~= xy[1] or xy[i * 2 + 2] ~= xy[2] then
		table.insert(edges, newEdge(xy[i * 2 + 1], xy[i * 2 + 2], xy[1], xy[2]))
	end
	fillEdges(image, edges, ink)
end

type Quarter = {
	a: number,
	b: number,
	cx: number,
	cy: number,
	ex: number,
	ey: number,
	a2: number,
	b2: number,
	a2b2: number,
	finished: boolean,
}

local function quarterInit(a: number, b: number): Quarter
	if a < 0 or b < 0 then
		return { a = 0, b = 0, cx = 0, cy = 0, ex = 0, ey = 0, a2 = 0, b2 = 0, a2b2 = 0, finished = true }
	end
	return {
		a = a,
		b = b,
		cx = a,
		cy = b % 2,
		ex = a % 2,
		ey = b,
		a2 = a * a,
		b2 = b * b,
		a2b2 = a * a * b * b,
		finished = false,
	}
end

local function quarterDelta(state: Quarter, x: number, y: number): number
	return math.abs(state.a2 * y * y + state.b2 * x * x - state.a2b2)
end

local function quarterNext(state: Quarter): (boolean, number, number)
	if state.finished then
		return false, 0, 0
	end
	local x, y = state.cx, state.cy
	if state.cx == state.ex and state.cy == state.ey then
		state.finished = true
	else
		local nx = state.cx
		local ny = state.cy + 2
		local delta = quarterDelta(state, nx, ny)
		if nx > 1 then
			local candidate = quarterDelta(state, state.cx - 2, state.cy + 2)
			if delta > candidate then
				nx = state.cx - 2
				ny = state.cy + 2
				delta = candidate
			end
			candidate = quarterDelta(state, state.cx - 2, state.cy)
			if delta > candidate then
				nx = state.cx - 2
				ny = state.cy
			end
		end
		state.cx = nx
		state.cy = ny
	end
	return true, x, y
end

type EllipseState = {
	outer: Quarter,
	inner: Quarter,
	py: number,
	pl: number,
	pr: number,
	segments: { number },
	finished: boolean,
	leftmost: number,
}

local function ellipseInit(a: number, b: number, w: number): EllipseState
	local state: EllipseState = {
		outer = quarterInit(a, b),
		inner = quarterInit(0, 0),
		py = 0,
		pl = 0,
		pr = 0,
		segments = {},
		finished = false,
		leftmost = a % 2,
	}
	local ok, x, y = false, 0, 0
	if w >= 1 then
		ok, x, y = quarterNext(state.outer)
	end
	if w < 1 or not ok then
		state.finished = true
	else
		state.pr = x
		state.py = y
		state.inner = quarterInit(a - 2 * (w - 1), b - 2 * (w - 1))
		state.pl = state.leftmost
	end
	return state
end

local function ellipseNext(state: EllipseState): (boolean, number, number, number)
	local segments = state.segments
	if #segments == 0 then
		if state.finished then
			return false, 0, 0, 0
		end
		local y = state.py
		local l = state.pl
		local r = state.pr
		local cx, cy = 0, 0
		local ok
		repeat
			ok, cx, cy = quarterNext(state.outer)
		until not ok or cy > y
		if not ok then
			state.finished = true
		else
			state.pr = cx
			state.py = cy
		end
		while true do
			ok, cx, cy = quarterNext(state.inner)
			if not ok or cy > y then
				break
			end
			l = cx
		end
		state.pl = if not ok then state.leftmost else cx
		if (l > 0 or l < r) and y > 0 then
			table.insert(segments, if l == 0 then 2 else l)
			table.insert(segments, y)
			table.insert(segments, r)
		end
		if y > 0 then
			table.insert(segments, -r)
			table.insert(segments, y)
			table.insert(segments, -l)
		end
		if l > 0 or l < r then
			table.insert(segments, if l == 0 then 2 else l)
			table.insert(segments, -y)
			table.insert(segments, r)
		end
		table.insert(segments, -r)
		table.insert(segments, -y)
		table.insert(segments, -l)
	end
	local n = #segments
	local x0, y, x1 = segments[n - 2], segments[n - 1], segments[n]
	segments[n] = nil
	segments[n - 1] = nil
	segments[n - 2] = nil
	return true, x0, y, x1
end

type ClipNode = {
	kind: "and" | "or" | "clip",
	a: number,
	b: number,
	c: number,
	l: ClipNode?,
	r: ClipNode?,
}

local function clipNode(a: number, b: number, c: number): ClipNode
	return { kind = "clip", a = a, b = b, c = c }
end

local function combine(kind: "and" | "or", l: ClipNode, r: ClipNode): ClipNode
	return { kind = kind, a = 0, b = 0, c = 0, l = l, r = r }
end

local function transposeTree(root: ClipNode?)
	if root ~= nil then
		if root.kind == "clip" then
			root.a, root.b = root.b, root.a
		end
		transposeTree(root.l)
		transposeTree(root.r)
	end
end

local function clipSegment(root: ClipNode?, x0: number, y: number, x1: number): { number }
	if root == nil then
		return { x0, 1, x1, -1 }
	end
	if root.kind == "clip" then
		local eps = 1e-9
		local A, B, C = root.a, root.b, root.c
		if math.abs(A) < eps then
			if B * y + C < -eps then
				x0 = 1
				x1 = 0
			end
		else
			local ix = -(B * y + C) / A
			if A * x0 + B * y + C < eps then
				x0 = Numeric.roundHalfAway(math.max(x0, ix))
			end
			if A * x1 + B * y + C < eps then
				x1 = Numeric.roundHalfAway(math.min(x1, ix))
			end
		end
		if x0 <= x1 then
			return { x0, 1, x1, -1 }
		end
		return {}
	end
	local left = clipSegment(root.l, x0, y, x1)
	local right = clipSegment(root.r, x0, y, x1)
	local out: { number } = {}
	local i1, i2 = 1, 1
	local k1, k2 = 0, 0
	local tail = 0
	local isOr = root.kind == "or"
	while i1 <= #left or i2 <= #right do
		local x, kind
		if
			i2 > #right
			or (i1 <= #left and (left[i1] < right[i2] or (left[i1] == right[i2] and left[i1 + 1] > right[i2 + 1])))
		then
			x, kind = left[i1], left[i1 + 1]
			k1 += kind
			i1 += 2
		else
			x, kind = right[i2], right[i2 + 1]
			k2 += kind
			i2 += 2
		end
		local keep
		if isOr then
			keep = (kind == 1 and (tail == 0 or tail == -1)) or (kind == -1 and k1 == 0 and k2 == 0)
		else
			keep = (kind == 1 and (tail == 0 or tail == -1) and k1 > 0 and k2 > 0)
				or (kind == -1 and tail == 1 and (k1 == 0 or k2 == 0))
		end
		if keep then
			table.insert(out, x)
			table.insert(out, kind)
			tail = kind
		end
	end
	return out
end

local function normalizeAngles(al: number, ar: number): (number, number)
	if f32(ar - al) >= 360 then
		return 0, 360
	end
	local start = f32(math.fmod(if al < 0 then 360 - math.fmod(-al, 360) else al, 360))
	local span = if ar < start then 360 - math.fmod(f32(start - ar), 360) else f32(ar - start)
	return start, f32(start + math.fmod(span, 360))
end

local function arcTree(a: number, b: number, al: number, ar: number): ClipNode?
	if a < b then
		local root = arcTree(b, a, f32(90 - ar), f32(90 - al))
		transposeTree(root)
		return root
	end
	al, ar = normalizeAngles(al, ar)
	if ar == f32(al + 360) then
		return nil
	end
	local lc = clipNode(
		-a * math.sin(al * math.pi / 180.0),
		b * math.cos(al * math.pi / 180.0),
		(a * a - b * b) * math.sin(al * math.pi / 90.0) / 2.0
	)
	local rc = clipNode(
		a * math.sin(ar * math.pi / 180.0),
		-b * math.cos(ar * math.pi / 180.0),
		(b * b - a * a) * math.sin(ar * math.pi / 90.0) / 2.0
	)
	if math.fmod(al, 180) == 0 or math.fmod(ar, 180) == 0 then
		return combine(if f32(ar - al) < 180 then "and" else "or", lc, rc)
	end
	local halfL = trunc(f32(al / 180))
	local halfR = trunc(f32(ar / 180))
	if (halfL + halfR) % 2 == 1 then
		return combine(
			"or",
			combine("and", clipNode(0, if halfL % 2 == 0 then 1 else -1, 0), lc),
			combine("and", clipNode(0, if halfR % 2 == 0 then 1 else -1, 0), rc)
		)
	end
	local kind: "and" | "or" = if f32(ar - al) < 180 then "and" else "or"
	return combine(kind, combine(kind, lc, rc), clipNode(0, if ar < 180 or ar > 540 then 1 else -1, 0))
end

local function pieTree(a: number, b: number, al: number, ar: number): ClipNode
	local xl = a * math.cos(al * math.pi / 180.0)
	local xr = a * math.cos(ar * math.pi / 180.0)
	local yl = b * math.sin(al * math.pi / 180.0)
	local yr = b * math.sin(ar * math.pi / 180.0)
	local root = combine(if f32(ar - al) < 180 then "and" else "or", clipNode(-yl, xl, 0), clipNode(yr, -xr, 0))
	if f32(ar - al) < 90 then
		root = combine("and", root, clipNode((xl + xr) / 2.0, (yl + yr) / 2.0, 0))
	end
	return root
end

local function ellipseSpans(
	image: Image,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	ink: Ink,
	width: number,
	tree: ClipNode?,
	clipped: boolean
)
	local a = x1 - x0
	local b = y1 - y0
	if a < 0 or b < 0 then
		return
	end
	local state = ellipseInit(a, b, width)
	while true do
		local ok, sx0, sy, sx1 = ellipseNext(state)
		if not ok then
			break
		end
		if clipped then
			local events = clipSegment(tree, sx0, sy, sx1)
			for index = 1, #events, 4 do
				hline(image, x0 + (events[index] + a) // 2, y0 + (sy + b) // 2, x0 + (events[index + 2] + a) // 2, ink)
			end
		else
			hline(image, x0 + (sx0 + a) // 2, y0 + (sy + b) // 2, x0 + (sx1 + a) // 2, ink)
		end
	end
end

local function ellipse(
	image: Image,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	ink: Ink,
	fill: boolean,
	width: number
)
	local a = x1 - x0
	local b = y1 - y0
	if a < 0 or b < 0 then
		return
	end
	ellipseSpans(image, x0, y0, x1, y1, ink, if fill then a + b else width, nil, false)
end

local function arc(
	image: Image,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	startAngle: number,
	endAngle: number,
	ink: Ink,
	width: number
)
	local start, stop = normalizeAngles(f32(startAngle), f32(endAngle))
	if f32(start + 360) == stop then
		ellipse(image, x0, y0, x1, y1, ink, false, width)
		return
	end
	if start == stop then
		return
	end
	ellipseSpans(image, x0, y0, x1, y1, ink, width, arcTree(x1 - x0, y1 - y0, start, stop), true)
end

local function pieslice(
	image: Image,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	startAngle: number,
	endAngle: number,
	ink: Ink
)
	local start, stop = normalizeAngles(f32(startAngle), f32(endAngle))
	if f32(start + 360) == stop then
		ellipse(image, x0, y0, x1, y1, ink, true, 0)
		return
	end
	if start == stop then
		return
	end
	local a = x1 - x0
	local b = y1 - y0
	if a < 0 or b < 0 then
		return
	end
	ellipseSpans(image, x0, y0, x1, y1, ink, x1 + y1 - x0 - y0, pieTree(a, b, start, stop), true)
end

export type Box = { number }

local function box(xy: Box): (number, number, number, number)
	return trunc(xy[1]), trunc(xy[2]), trunc(xy[3]), trunc(xy[4])
end

local function distinct(outline: Ink, fill: Ink?): boolean
	if fill == nil then
		return true
	end
	if #outline ~= #fill then
		return true
	end
	for index, value in outline do
		if fill[index] ~= value then
			return true
		end
	end
	return false
end

function Draw.point(image: Image, x: number, y: number, ink: Ink)
	point(image, trunc(x), trunc(y), ink)
end

function Draw.rectangle(image: Image, xy: Box, fill: Ink?, outline: Ink?, width: number?)
	local x0, y0, x1, y1 = box(xy)
	if fill ~= nil then
		rectangle(image, x0, y0, x1, y1, fill, true, 0)
	end
	local strokeWidth = width or 1
	if outline ~= nil and strokeWidth ~= 0 and distinct(outline, fill) then
		rectangle(image, x0, y0, x1, y1, outline, false, strokeWidth)
	end
end

function Draw.ellipse(image: Image, xy: Box, fill: Ink?, outline: Ink?, width: number?)
	local x0, y0, x1, y1 = box(xy)
	if fill ~= nil then
		ellipse(image, x0, y0, x1, y1, fill, true, 1)
	end
	local strokeWidth = width or 1
	if outline ~= nil and strokeWidth ~= 0 and distinct(outline, fill) then
		ellipse(image, x0, y0, x1, y1, outline, false, strokeWidth)
	end
end

function Draw.pieslice(image: Image, xy: Box, startAngle: number, endAngle: number, fill: Ink)
	local x0, y0, x1, y1 = box(xy)
	pieslice(image, x0, y0, x1, y1, startAngle, endAngle, fill)
end

function Draw.arc(image: Image, xy: Box, startAngle: number, endAngle: number, ink: Ink, width: number?)
	local strokeWidth = width or 1
	if strokeWidth ~= 0 then
		local x0, y0, x1, y1 = box(xy)
		arc(image, x0, y0, x1, y1, startAngle, endAngle, ink, strokeWidth)
	end
end

function Draw.polygon(image: Image, xy: { number }, fill: Ink)
	local points = table.create(#xy, 0)
	for index, value in xy do
		points[index] = trunc(value)
	end
	polygonFill(image, points, fill)
end

local function drawLines(image: Image, xy: { number }, ink: Ink, width: number)
	local count = #xy // 2
	if width == 1 then
		local lastX, lastY = nil :: number?, nil :: number?
		for index = 0, count - 2 do
			local x0 = trunc(xy[index * 2 + 1])
			local y0 = trunc(xy[index * 2 + 2])
			local x1 = trunc(xy[index * 2 + 3])
			local y1 = trunc(xy[index * 2 + 4])
			thinLine(image, x0, y0, x1, y1, ink)
			lastX, lastY = x1, y1
		end
		if lastX ~= nil and lastY ~= nil then
			point(image, lastX, lastY, ink)
		end
	else
		for index = 0, count - 2 do
			wideLine(
				image,
				trunc(xy[index * 2 + 1]),
				trunc(xy[index * 2 + 2]),
				trunc(xy[index * 2 + 3]),
				trunc(xy[index * 2 + 4]),
				ink,
				width
			)
		end
	end
end

local RADIANS = math.pi / 180.0
local DEGREES = 180.0 / math.pi

function Draw.line(image: Image, xy: { number }, ink: Ink, width: number?, joint: "curve"?)
	local strokeWidth = width or 1
	if strokeWidth == 0 then
		return
	end
	drawLines(image, xy, ink, strokeWidth)
	if joint ~= "curve" or strokeWidth <= 4 then
		return
	end
	local count = #xy // 2
	for index = 1, count - 2 do
		local px, py = xy[index * 2 + 1], xy[index * 2 + 2]
		local ax, ay = xy[index * 2 - 1], xy[index * 2]
		local bx, by = xy[index * 2 + 3], xy[index * 2 + 4]
		local angle0 = Numeric.floorMod(math.atan2(px - ax, ay - py) * DEGREES, 360)
		local angle1 = Numeric.floorMod(math.atan2(bx - px, py - by) * DEGREES, 360)
		if angle0 == angle1 then
			continue
		end
		local flipped = (angle1 > angle0 and angle1 - 180 > angle0) or (angle1 < angle0 and angle1 + 180 > angle0)
		local half = strokeWidth / 2
		local coords = { px - half + 1, py - half + 1, px + half - 1, py + half - 1 }
		local start, stop
		if flipped then
			start, stop = angle1 + 90, angle0 + 90
		else
			start, stop = angle0 - 90, angle1 - 90
		end
		Draw.pieslice(image, coords, start - 90, stop - 90, ink)
		if strokeWidth > 8 then
			local distance = strokeWidth / 2 - 1
			local function at(angle: number): (number, number)
				local turned = angle - 90
				local ox = distance * math.cos(turned * RADIANS)
				local oy = distance * math.sin(turned * RADIANS)
				return px + (if ox > 0 then math.floor(ox) else math.ceil(ox)),
					py + (if oy > 0 then math.floor(oy) else math.ceil(oy))
			end
			local gx0, gy0, gx1, gy1
			if flipped then
				gx0, gy0 = at(angle0 + 90)
				gx1, gy1 = at(angle1 + 90)
			else
				gx0, gy0 = at(angle0 - 90)
				gx1, gy1 = at(angle1 - 90)
			end
			Draw.line(image, { gx0, gy0, px, py, gx1, gy1 }, ink, 3)
		end
	end
end

local function pyRound(value: number): number
	return Numeric.roundHalfEven(value)
end

function Draw.roundedRectangle(image: Image, xy: Box, radius: number, fill: Ink?, outline: Ink?, width: number?)
	local strokeWidth = width or 1
	local fx0, fy0, fx1, fy1 = xy[1], xy[2], xy[3], xy[4]
	local d = math.min(fx1 - fx0, fy1 - fy0, radius * 2)
	local x0 = pyRound(fx0)
	local y0 = pyRound(fy0)
	local x1 = pyRound(fx1)
	local y1 = pyRound(fy1)
	local fullX = d >= x1 - x0 - 1
	if fullX then
		d = x1 - x0
	end
	local fullY = d >= y1 - y0 - 1
	if fullY then
		d = y1 - y0
	end
	if fullX and fullY then
		Draw.ellipse(image, xy, fill, outline, strokeWidth)
		return
	end
	if d == 0 then
		Draw.rectangle(image, xy, fill, outline, strokeWidth)
		return
	end
	local r = trunc(d // 2)
	local function corners(callback: (Box, number, number) -> ())
		if fullX then
			callback({ x0, y0, x0 + d, y0 + d }, 180, 360)
			callback({ x0, y1 - d, x0 + d, y1 }, 0, 180)
		elseif fullY then
			callback({ x0, y0, x0 + d, y0 + d }, 90, 270)
			callback({ x1 - d, y0, x1, y0 + d }, 270, 90)
		else
			callback({ x0, y0, x0 + d, y0 + d }, 180, 270)
			callback({ x1 - d, y0, x1, y0 + d }, 270, 360)
			callback({ x1 - d, y1 - d, x1, y1 }, 0, 90)
			callback({ x0, y1 - d, x0 + d, y1 }, 90, 180)
		end
	end
	if fill ~= nil then
		corners(function(part: Box, startAngle: number, endAngle: number)
			Draw.pieslice(image, part, startAngle, endAngle, fill)
		end)
		if fullX then
			rectangle(image, x0, y0 + r + 1, x1, y1 - r - 1, fill, true, 0)
		elseif x1 - r - 1 >= x0 + r + 1 then
			rectangle(image, x0 + r + 1, y0, x1 - r - 1, y1, fill, true, 0)
		end
		if not fullX and not fullY then
			rectangle(image, x0, y0 + r + 1, x0 + r, y1 - r - 1, fill, true, 0)
			rectangle(image, x1 - r, y0 + r + 1, x1, y1 - r - 1, fill, true, 0)
		end
	end
	if outline ~= nil and strokeWidth ~= 0 and distinct(outline, fill) then
		corners(function(part: Box, startAngle: number, endAngle: number)
			Draw.arc(image, part, startAngle, endAngle, outline, strokeWidth)
		end)
		if not fullX then
			rectangle(image, x0 + r + 1, y0, x1 - r - 1, y0 + strokeWidth - 1, outline, true, 0)
			rectangle(image, x0 + r + 1, y1 - strokeWidth + 1, x1 - r - 1, y1, outline, true, 0)
		end
		if not fullY then
			rectangle(image, x0, y0 + r + 1, x0 + strokeWidth - 1, y1 - r - 1, outline, true, 0)
			rectangle(image, x1 - strokeWidth + 1, y0 + r + 1, x1, y1 - r - 1, outline, true, 0)
		end
	end
end

return table.freeze(Draw)
