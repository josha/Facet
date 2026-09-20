--!strict
-- Stroke icons drawn with `UI.Path`. Each icon is one polyline in a unit
-- square, so it scales to any size and takes its colour from a theme role.
local icons = {}

local function arc(cx: number, cy: number, r: number, from: number, to: number, steps: number): { any }
	local points = {}
	for step = 0, steps do
		local angle = math.rad(from + (to - from) * step / steps)
		table.insert(points, { x = cx + math.cos(angle) * r, y = cy + math.sin(angle) * r })
	end
	return points
end

local function join(...: { any }): { any }
	local out = {}
	for _, part in { ... } do
		for _, point in part do
			table.insert(out, point)
		end
	end
	return out
end

local function heart(): { any }
	local points = {}
	for step = 0, 32 do
		local t = math.rad(step / 32 * 360)
		local x = 16 * math.sin(t) ^ 3
		local y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
		table.insert(points, { x = 0.5 + x / 36, y = 0.47 - y / 36 })
	end
	return points
end

local function star(): { any }
	local points = {}
	for corner = 0, 10 do
		local radius = if corner % 2 == 0 then 0.46 else 0.19
		local angle = math.rad(-90 + corner * 36)
		table.insert(points, { x = 0.5 + math.cos(angle) * radius, y = 0.52 + math.sin(angle) * radius })
	end
	return points
end

local function sparkle(): { any }
	local points = {}
	for corner = 0, 8 do
		local radius = if corner % 2 == 0 then 0.46 else 0.12
		local angle = math.rad(-90 + corner * 45)
		table.insert(points, { x = 0.5 + math.cos(angle) * radius, y = 0.5 + math.sin(angle) * radius })
	end
	return points
end

local SHAPES: { [string]: { any } } = {
	heart = heart(),
	star = star(),
	sparkle = sparkle(),
	-- A lens, then the handle drawn from the point the circle closes on.
	search = join(arc(0.43, 0.43, 0.3, 45, 405, 20), { { x = 0.92, y = 0.92 } }),
	send = {
		{ x = 0.06, y = 0.5 },
		{ x = 0.94, y = 0.08 },
		{ x = 0.62, y = 0.94 },
		{ x = 0.46, y = 0.58 },
		{ x = 0.06, y = 0.5 },
		{ x = 0.46, y = 0.58 },
		{ x = 0.94, y = 0.08 },
	},
	-- Three quarters of a turn, ending in an arrow head.
	rotate = join(
		arc(0.5, 0.5, 0.36, -40, 250, 18),
		{ { x = 0.18, y = 0.62 }, { x = 0.38, y = 0.84 }, { x = 0.42, y = 0.6 } }
	),
}
for _, shape in SHAPES do
	table.freeze(shape)
end

-- `role` is a theme colour role such as "accent" or "secondary".
function icons.draw(UI: any, name: string, size: number, role: string?, thickness: number?): any
	local shape = assert(SHAPES[name], `Virtual Monitors has no icon named '{name}'`)
	return UI.Path({
		points = shape,
		thickness = thickness or math.max(2, math.floor(size / 10)),
		role = role or "content",
		width = { type = "fixed", px = size },
		height = { type = "fixed", px = size },
	})
end

return icons
