--!strict

export type Stroke = { read closed: boolean, read points: { { number } } }

local function ring(cx: number, cy: number, radius: number, count: number): Stroke
	local points: { { number } } = {}
	for index = 0, count - 1 do
		local angle = (index / count) * math.pi * 2
		table.insert(points, { cx + radius * math.cos(angle), cy + radius * math.sin(angle) })
	end
	return table.freeze({ closed = true, points = table.freeze(points) })
end

local function open(points: { { number } }): Stroke
	return table.freeze({ closed = false, points = table.freeze(points) })
end

local function closed(points: { { number } }): Stroke
	return table.freeze({ closed = true, points = table.freeze(points) })
end

local function line(x0: number, y0: number, x1: number, y1: number): Stroke
	return open({ { x0, y0 }, { x1, y1 } })
end

local function dot(x: number, y: number): Stroke
	return line(x - 0.03, y, x + 0.03, y)
end

local function sweep(
	cx: number,
	cy: number,
	rx: number,
	ry: number,
	from: number,
	to: number,
	count: number
): { { number } }
	local points: { { number } } = {}
	for index = 0, count do
		local angle = math.rad(from + (to - from) * index / count)
		table.insert(points, { cx + rx * math.cos(angle), cy + ry * math.sin(angle) })
	end
	return points
end

local function arc(cx: number, cy: number, radius: number, from: number, to: number, count: number): Stroke
	return open(sweep(cx, cy, radius, radius, from, to, count))
end

local function oval(cx: number, cy: number, rx: number, ry: number, count: number): Stroke
	local points = sweep(cx, cy, rx, ry, 0, 360, count)
	table.remove(points)
	return closed(points)
end

local function join(...: { { number } }): { { number } }
	local points: { { number } } = {}
	for _, part in { ... } do
		for _, point in part do
			table.insert(points, point)
		end
	end
	return points
end

local function box(x0: number, y0: number, x1: number, y1: number, radius: number): Stroke
	if radius <= 0 then
		return closed({ { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } })
	end
	return closed(
		join(
			sweep(x0 + radius, y0 + radius, radius, radius, 180, 270, 3),
			sweep(x1 - radius, y0 + radius, radius, radius, 270, 360, 3),
			sweep(x1 - radius, y1 - radius, radius, radius, 0, 90, 3),
			sweep(x0 + radius, y1 - radius, radius, radius, 90, 180, 3)
		)
	)
end

local function flipped(strokes: { Stroke }): { Stroke }
	local result: { Stroke } = {}
	for _, stroke in strokes do
		local points: { { number } } = {}
		for _, point in stroke.points do
			table.insert(points, { point[1], 1 - point[2] })
		end
		table.insert(result, if stroke.closed then closed(points) else open(points))
	end
	return result
end

local function gear(teeth: number, root: number, tip: number, rootHalf: number, tipHalf: number): Stroke
	local points: { { number } } = {}
	local step = 360 / teeth
	for index = 0, teeth - 1 do
		local center = index * step - 90
		for _, pair in
			{
				{ root, center - rootHalf },
				{ tip, center - tipHalf },
				{ tip, center + tipHalf },
				{ root, center + rootHalf },
			}
		do
			local angle = math.rad(pair[2])
			table.insert(points, { 0.5 + pair[1] * math.cos(angle), 0.5 + pair[1] * math.sin(angle) })
		end
	end
	return closed(points)
end

local function star(): Stroke
	local points: { { number } } = {}
	for index = 0, 9 do
		local radius = if index % 2 == 0 then 0.36 else 0.17
		local angle = math.pi / 5 * index - math.pi / 2
		table.insert(points, { 0.5 + math.cos(angle) * radius, 0.54 + math.sin(angle) * radius })
	end
	return closed(points)
end

local function turned(points: { { number } }, degrees: number): { { number } }
	local angle = math.rad(degrees)
	local cos, sin = math.cos(angle), math.sin(angle)
	local result: { { number } } = {}
	for _, point in points do
		local x, y = point[1] - 0.5, point[2] - 0.5
		table.insert(result, { 0.5 + x * cos - y * sin, 0.5 + x * sin + y * cos })
	end
	return result
end

local function wrench(): Stroke
	local radius, slot, handle = 0.17, 0.09, 0.06
	local jaw = math.deg(math.atan2(math.sqrt(radius ^ 2 - slot ^ 2), slot))
	local neck = math.deg(math.atan2(math.sqrt(radius ^ 2 - handle ^ 2), handle))
	return closed(
		turned(
			join(
				{ { 0.5 - slot, 0.31 } },
				sweep(0.5, 0.33, radius, radius, 180 + jaw, 180 - neck, 8),
				sweep(0.5, 0.78, handle, handle, 180, 0, 4),
				sweep(0.5, 0.33, radius, radius, neck, -jaw, 8),
				{ { 0.5 + slot, 0.31 } }
			),
			45
		)
	)
end

local checkmark = { open({ { 0.22, 0.52 }, { 0.42, 0.72 }, { 0.78, 0.3 } }) }

local thumb = {
	box(0.16, 0.46, 0.28, 0.82, 0),
	closed({
		{ 0.38, 0.46 },
		{ 0.48, 0.2 },
		{ 0.56, 0.2 },
		{ 0.6, 0.26 },
		{ 0.56, 0.42 },
		{ 0.78, 0.42 },
		{ 0.84, 0.48 },
		{ 0.8, 0.76 },
		{ 0.74, 0.82 },
		{ 0.38, 0.82 },
	}),
}

return table.freeze({
	close = { line(0.26, 0.26, 0.74, 0.74), line(0.74, 0.26, 0.26, 0.74) },
	checkmark = checkmark,
	check = checkmark,
	["chevron.leading"] = { open({ { 0.6, 0.22 }, { 0.34, 0.5 }, { 0.6, 0.78 } }) },
	["chevron.trailing"] = { open({ { 0.4, 0.22 }, { 0.66, 0.5 }, { 0.4, 0.78 } }) },
	["chevron.up"] = { open({ { 0.22, 0.6 }, { 0.5, 0.34 }, { 0.78, 0.6 } }) },
	["chevron.down"] = { open({ { 0.22, 0.4 }, { 0.5, 0.66 }, { 0.78, 0.4 } }) },
	["chevron.first"] = { open({ { 0.64, 0.22 }, { 0.4, 0.5 }, { 0.64, 0.78 } }), line(0.3, 0.22, 0.3, 0.78) },
	["chevron.last"] = { open({ { 0.36, 0.22 }, { 0.6, 0.5 }, { 0.36, 0.78 } }), line(0.7, 0.22, 0.7, 0.78) },
	["chevron.up.chevron.down"] = {
		open({ { 0.3, 0.4 }, { 0.5, 0.2 }, { 0.7, 0.4 } }),
		open({ { 0.3, 0.6 }, { 0.5, 0.8 }, { 0.7, 0.6 } }),
	},
	increment = { line(0.5, 0.22, 0.5, 0.78), line(0.22, 0.5, 0.78, 0.5) },
	decrement = { line(0.22, 0.5, 0.78, 0.5) },
	menu = { line(0.2, 0.3, 0.8, 0.3), line(0.2, 0.5, 0.8, 0.5), line(0.2, 0.7, 0.8, 0.7) },
	more = { dot(0.25, 0.5), dot(0.5, 0.5), dot(0.75, 0.5) },
	["facet:search"] = { ring(0.44, 0.44, 0.22, 16), line(0.6, 0.6, 0.8, 0.8) },
	["status.info"] = { ring(0.5, 0.5, 0.36, 20), line(0.5, 0.46, 0.5, 0.68), dot(0.5, 0.34) },
	["status.success"] = { ring(0.5, 0.5, 0.36, 20), open({ { 0.34, 0.52 }, { 0.46, 0.64 }, { 0.66, 0.4 } }) },
	["status.warning"] = {
		closed({ { 0.5, 0.16 }, { 0.86, 0.8 }, { 0.14, 0.8 } }),
		line(0.5, 0.4, 0.5, 0.6),
		dot(0.5, 0.7),
	},
	["status.error"] = { ring(0.5, 0.5, 0.36, 20), line(0.38, 0.38, 0.62, 0.62), line(0.62, 0.38, 0.38, 0.62) },
	["facet:selection.radio.off"] = { ring(0.5, 0.5, 0.32, 20) },
	["facet:selection.radio.on"] = { ring(0.5, 0.5, 0.32, 20), ring(0.5, 0.5, 0.12, 10) },
	["facet:selection.check.off"] = { closed({ { 0.22, 0.22 }, { 0.78, 0.22 }, { 0.78, 0.78 }, { 0.22, 0.78 } }) },
	clock = { ring(0.5, 0.5, 0.34, 20), open({ { 0.5, 0.3 }, { 0.5, 0.5 }, { 0.64, 0.6 } }) },
	calendar = {
		closed({ { 0.2, 0.26 }, { 0.8, 0.26 }, { 0.8, 0.8 }, { 0.2, 0.8 } }),
		line(0.2, 0.42, 0.8, 0.42),
		line(0.36, 0.16, 0.36, 0.3),
		line(0.64, 0.16, 0.64, 0.3),
	},
	["view.grid"] = {
		box(0.18, 0.18, 0.42, 0.42, 0.04),
		box(0.58, 0.18, 0.82, 0.42, 0.04),
		box(0.18, 0.58, 0.42, 0.82, 0.04),
		box(0.58, 0.58, 0.82, 0.82, 0.04),
	},
	["view.list"] = {
		dot(0.22, 0.26),
		dot(0.22, 0.5),
		dot(0.22, 0.74),
		line(0.38, 0.26, 0.8, 0.26),
		line(0.38, 0.5, 0.8, 0.5),
		line(0.38, 0.74, 0.8, 0.74),
	},
	["view.table"] = {
		box(0.16, 0.18, 0.84, 0.82, 0.04),
		line(0.16, 0.39, 0.84, 0.39),
		line(0.16, 0.61, 0.84, 0.61),
		line(0.4, 0.18, 0.4, 0.82),
	},
	settings = { gear(8, 0.27, 0.37, 13, 9), ring(0.5, 0.5, 0.1, 12) },
	edit = {
		closed({ { 0.2, 0.8 }, { 0.26, 0.58 }, { 0.62, 0.22 }, { 0.78, 0.38 }, { 0.42, 0.74 } }),
		line(0.26, 0.58, 0.42, 0.74),
		line(0.53, 0.31, 0.69, 0.47),
	},
	trash = {
		open({ { 0.42, 0.31 }, { 0.42, 0.2 }, { 0.58, 0.2 }, { 0.58, 0.31 } }),
		line(0.2, 0.31, 0.8, 0.31),
		open({ { 0.28, 0.31 }, { 0.33, 0.8 }, { 0.67, 0.8 }, { 0.72, 0.31 } }),
	},
	flag = { line(0.27, 0.2, 0.27, 0.8), closed({ { 0.27, 0.23 }, { 0.77, 0.36 }, { 0.27, 0.5 } }) },
	["vote.up"] = thumb,
	["vote.down"] = flipped(thumb),
	person = { ring(0.5, 0.31, 0.12, 16), closed(sweep(0.5, 0.84, 0.28, 0.28, 180, 360, 12)) },
	star = { star() },
	heart = {
		closed(
			join(
				{ { 0.5, 0.8 } },
				sweep(0.355, 0.4, 0.155, 0.155, 135, 339, 10),
				sweep(0.645, 0.4, 0.155, 0.155, 201, 405, 10)
			)
		),
	},
	chat = {
		closed(
			join(
				sweep(0.3, 0.32, 0.12, 0.12, 180, 270, 3),
				sweep(0.7, 0.32, 0.12, 0.12, 270, 360, 3),
				sweep(0.7, 0.56, 0.12, 0.12, 0, 90, 3),
				{ { 0.44, 0.68 }, { 0.28, 0.82 } },
				sweep(0.3, 0.56, 0.12, 0.12, 90, 180, 3)
			)
		),
	},
	gift = {
		closed({ { 0.5, 0.38 }, { 0.36, 0.2 }, { 0.27, 0.3 } }),
		closed({ { 0.5, 0.38 }, { 0.64, 0.2 }, { 0.73, 0.3 } }),
		box(0.16, 0.38, 0.84, 0.52, 0),
		box(0.22, 0.52, 0.78, 0.82, 0),
		line(0.5, 0.38, 0.5, 0.82),
	},
	coin = {
		oval(0.5, 0.4, 0.34, 0.22, 20),
		open(sweep(0.5, 0.56, 0.34, 0.22, 0, 180, 10)),
		line(0.16, 0.4, 0.16, 0.56),
		line(0.84, 0.4, 0.84, 0.56),
	},
	gem = {
		closed({ { 0.3, 0.2 }, { 0.7, 0.2 }, { 0.86, 0.4 }, { 0.5, 0.82 }, { 0.14, 0.4 } }),
		line(0.14, 0.4, 0.86, 0.4),
	},
	bag = {
		arc(0.5, 0.38, 0.14, 180, 360, 8),
		box(0.2, 0.38, 0.8, 0.82, 0.08),
		arc(0.5, 0.52, 0.1, 0, 180, 8),
	},
	trophy = {
		closed(join({ { 0.28, 0.18 }, { 0.72, 0.18 } }, sweep(0.5, 0.36, 0.22, 0.22, 0, 180, 10))),
		arc(0.28, 0.3, 0.1, 90, 270, 8),
		arc(0.72, 0.3, 0.1, 270, 450, 8),
		line(0.5, 0.58, 0.5, 0.78),
		line(0.32, 0.8, 0.68, 0.8),
	},
	crown = {
		closed({
			{ 0.17, 0.32 },
			{ 0.34, 0.54 },
			{ 0.5, 0.24 },
			{ 0.66, 0.54 },
			{ 0.83, 0.32 },
			{ 0.77, 0.78 },
			{ 0.23, 0.78 },
		}),
	},
	lock = {
		open(join({ { 0.35, 0.46 } }, sweep(0.5, 0.34, 0.15, 0.15, 180, 360, 8), { { 0.65, 0.46 } })),
		box(0.2, 0.46, 0.8, 0.82, 0.06),
		line(0.5, 0.6, 0.5, 0.68),
	},
	bolt = {
		closed({
			{ 0.46, 0.19 },
			{ 0.68, 0.19 },
			{ 0.57, 0.43 },
			{ 0.73, 0.43 },
			{ 0.41, 0.81 },
			{ 0.48, 0.55 },
			{ 0.28, 0.55 },
		}),
	},
	wrench = { wrench() },
	timer = {
		ring(0.5, 0.56, 0.28, 20),
		line(0.42, 0.16, 0.58, 0.16),
		line(0.5, 0.16, 0.5, 0.28),
		line(0.72, 0.3, 0.76, 0.26),
		line(0.5, 0.56, 0.6, 0.42),
	},
	car = {
		open({
			{ 0.22, 0.68 },
			{ 0.16, 0.68 },
			{ 0.16, 0.5 },
			{ 0.26, 0.46 },
			{ 0.36, 0.26 },
			{ 0.64, 0.26 },
			{ 0.76, 0.46 },
			{ 0.84, 0.5 },
			{ 0.84, 0.68 },
			{ 0.78, 0.68 },
		}),
		line(0.42, 0.68, 0.58, 0.68),
		ring(0.32, 0.7, 0.08, 12),
		ring(0.68, 0.7, 0.08, 12),
	},
}) :: { [string]: { Stroke } }
