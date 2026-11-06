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

local checkmark = { open({ { 0.22, 0.52 }, { 0.42, 0.72 }, { 0.78, 0.3 } }) }

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
}) :: { [string]: { Stroke } }
