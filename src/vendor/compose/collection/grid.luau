--!strict

local LIMIT = 65536
local SPAN = LIMIT * 2

export type Grid = {
	cellSize: number,
	buckets: { [number]: { number } },
	activeKeys: { number },
	pool: { { number } },
	lengths: { [number]: number },
	count: number,
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	minZ: number,
	maxZ: number,
}

local function cellOf(value: number, cellSize: number): number
	return math.clamp(math.floor(value / cellSize), -LIMIT, LIMIT - 1)
end

local function keyOf(cx: number, cy: number, cz: number): number
	return ((cx + LIMIT) * SPAN + (cy + LIMIT)) * SPAN + (cz + LIMIT)
end

local function create(cellSize: number): Grid
	return {
		cellSize = if cellSize > 0 then cellSize else 1,
		buckets = {},
		activeKeys = {},
		pool = {},
		lengths = {},
		count = 0,
		minX = 0,
		maxX = -1,
		minY = 0,
		maxY = -1,
		minZ = 0,
		maxZ = -1,
	}
end

local function build<V>(self: Grid, list: { V }, positionOf: (value: V) -> (number, number, number))
	local buckets = self.buckets
	local lengths = self.lengths
	local activeKeys = self.activeKeys
	local pool = self.pool

	for _, key in activeKeys do
		local bucket = buckets[key]
		buckets[key] = nil
		lengths[key] = nil
		pool[#pool + 1] = bucket
	end
	table.clear(activeKeys)

	local cellSize = self.cellSize
	local total = #list
	self.count = total

	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for index = 1, total do
		local x, y, z = positionOf(list[index])
		local cx, cy, cz = cellOf(x, cellSize), cellOf(y, cellSize), cellOf(z or 0, cellSize)
		if cx < minX then
			minX = cx
		end
		if cx > maxX then
			maxX = cx
		end
		if cy < minY then
			minY = cy
		end
		if cy > maxY then
			maxY = cy
		end
		if cz < minZ then
			minZ = cz
		end
		if cz > maxZ then
			maxZ = cz
		end
		local key = keyOf(cx, cy, cz)
		local bucket = buckets[key]
		if bucket == nil then
			bucket = table.remove(pool) or {}
			buckets[key] = bucket
			lengths[key] = 0
			activeKeys[#activeKeys + 1] = key
		end
		local at = (lengths[key] :: number) + 1
		lengths[key] = at
		bucket[at] = index
	end

	if total > 0 then
		self.minX, self.maxX = minX, maxX
		self.minY, self.maxY = minY, maxY
		self.minZ, self.maxZ = minZ, maxZ
	else
		self.minX, self.maxX = 0, -1
		self.minY, self.maxY = 0, -1
		self.minZ, self.maxZ = 0, -1
	end
end

local function query(self: Grid, x: number, y: number, z: number, radius: number, visit: (index: number) -> ()): number
	local cellSize = self.cellSize
	local buckets = self.buckets
	local minX = math.max(cellOf(x - radius, cellSize), self.minX)
	local maxX = math.min(cellOf(x + radius, cellSize), self.maxX)
	local minY = math.max(cellOf(y - radius, cellSize), self.minY)
	local maxY = math.min(cellOf(y + radius, cellSize), self.maxY)
	local minZ = math.max(cellOf(z - radius, cellSize), self.minZ)
	local maxZ = math.min(cellOf(z + radius, cellSize), self.maxZ)

	local visited = 0
	for cx = minX, maxX do
		for cy = minY, maxY do
			for cz = minZ, maxZ do
				visited += 1
				local key = keyOf(cx, cy, cz)
				local live = self.lengths[key]
				if live ~= nil and live > 0 then
					local bucket = buckets[key]
					for at = 1, live do
						visit(bucket[at])
					end
				end
			end
		end
	end
	return visited
end

return {
	create = create,
	build = build,
	query = query,
	cellOf = cellOf,
	keyOf = keyOf,
}
