--!strict

export type Prefix = {
	count: number,

	tree: { number },
	extents: { number },
	sum: number,
}

local function create(count: number, extent: number): Prefix
	local tree = table.create(count + 1, 0)
	local extents = table.create(count, extent)

	for index = 1, count do
		tree[index] += extent
		local parent = index + bit32.band(index, -index)
		if parent <= count then
			tree[parent] += tree[index]
		end
	end

	return {
		count = count,
		tree = tree,
		extents = extents,
		sum = extent * count,
	}
end

local function extentOf(self: Prefix, index: number): number
	return self.extents[index]
end

local function set(self: Prefix, index: number, extent: number): boolean
	local current = self.extents[index]
	local delta = extent - current
	if delta == 0 then
		return false
	end
	self.extents[index] = extent
	self.sum += delta

	local tree = self.tree
	local count = self.count
	local at = index
	while at <= count do
		tree[at] += delta
		at += bit32.band(at, -at)
	end
	return true
end

local function startOf(self: Prefix, index: number): number
	local tree = self.tree
	local total = 0
	local at = index - 1
	while at > 0 do
		total += tree[at]
		at -= bit32.band(at, -at)
	end
	return total
end

local function find(self: Prefix, offset: number): (number, number)
	local count = self.count
	if count == 0 then
		return 0, 0
	end
	if offset <= 0 then
		return 1, 0
	end

	local tree = self.tree
	local index = 0
	local remaining = offset
	local step = 1
	while step * 2 <= count do
		step *= 2
	end
	while step > 0 do
		local next = index + step
		if next <= count and tree[next] <= remaining then
			index = next
			remaining -= tree[next]
		end
		step //= 2
	end

	local row = index + 1
	if row > count then
		return count, self.sum - self.extents[count]
	end
	return row, offset - remaining
end

return {
	create = create,
	set = set,
	startOf = startOf,
	extentOf = extentOf,
	find = find,
}
