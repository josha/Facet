--!strict

local Prefix = require "./prefix"

export type Kind = "list" | "grid"

export type Placement = {
	index: number,
	row: number,
	column: number,
	offset: number,
	size: number,
	crossOffset: number,
	crossSize: number,
}

export type Geometry = {
	count: number,
	columns: number,
	rowCount: number,
	gap: number,
	crossSize: number,
	crossGap: number,
	rowSize: number,
	uniform: boolean,
	rows: Prefix.Prefix?,
	itemSizes: { number }?,
}

local function rowsFor(count: number, columns: number): number
	if count <= 0 then
		return 0
	end
	return math.ceil(count / columns)
end

export type Options = {
	count: number,
	columns: number,
	rowSize: number,
	gap: number,
	crossSize: number,
	crossGap: number,
}

local function create(options: Options): Geometry
	local columns = math.max(1, math.floor(options.columns))
	return {
		count = options.count,
		columns = columns,
		rowCount = rowsFor(options.count, columns),
		gap = options.gap,
		crossSize = options.crossSize,
		crossGap = options.crossGap,
		rowSize = options.rowSize,
		uniform = true,
		rows = nil,
		itemSizes = nil,
	}
end

local function materialise(self: Geometry)
	if self.rows ~= nil then
		return
	end
	self.rows = Prefix.create(self.rowCount, self.rowSize + self.gap)
	self.itemSizes = table.create(self.count, self.rowSize)
	self.uniform = false
end

local function totalExtent(self: Geometry): number
	if self.rowCount == 0 then
		return 0
	end
	if self.uniform then
		return self.rowCount * (self.rowSize + self.gap) - self.gap
	end

	return (self.rows :: Prefix.Prefix).sum - self.gap
end

local function setItemSize(self: Geometry, index: number, size: number): boolean
	if index < 1 or index > self.count then
		return false
	end
	if self.uniform then
		if size == self.rowSize then
			return false
		end
		materialise(self)
	end

	local itemSizes = self.itemSizes :: { number }
	if itemSizes[index] == size then
		return false
	end
	itemSizes[index] = size

	local columns = self.columns
	local row = math.ceil(index / columns)
	local rowSize: number
	if columns == 1 then
		rowSize = size
	else
		local first = (row - 1) * columns + 1
		local last = math.min(self.count, row * columns)
		rowSize = 0
		for at = first, last do
			local candidate = itemSizes[at]
			if candidate > rowSize then
				rowSize = candidate
			end
		end
	end

	return Prefix.set(self.rows :: Prefix.Prefix, row, rowSize + self.gap)
end

local function rowSpan(self: Geometry, row: number): (number, number)
	if self.uniform then
		return (row - 1) * (self.rowSize + self.gap), self.rowSize
	end
	local rows = self.rows :: Prefix.Prefix
	return Prefix.startOf(rows, row), Prefix.extentOf(rows, row) - self.gap
end

local function rowAt(self: Geometry, offset: number): number
	if self.rowCount == 0 then
		return 0
	end
	if self.uniform then
		local stride = self.rowSize + self.gap
		if stride <= 0 then
			return 1
		end
		return math.clamp(math.floor(offset / stride) + 1, 1, self.rowCount)
	end
	local row = Prefix.find(self.rows :: Prefix.Prefix, offset)
	return math.clamp(row, 1, self.rowCount)
end

local function placementOf(self: Geometry, index: number): Placement
	local columns = self.columns
	local row = math.ceil(index / columns)
	local column = index - (row - 1) * columns
	local offset, size = rowSpan(self, row)
	return {
		index = index,
		row = row,
		column = column,
		offset = offset,
		size = size,
		crossOffset = (column - 1) * (self.crossSize + self.crossGap),
		crossSize = self.crossSize,
	}
end

local function offsetOf(self: Geometry, index: number): number
	if self.count == 0 then
		return 0
	end
	local row = math.ceil(math.clamp(index, 1, self.count) / self.columns)
	local offset = rowSpan(self, row)
	return offset
end

export type Range = {

	first: number,
	last: number,
	firstRow: number,
	lastRow: number,
}

local function rangeFor(self: Geometry, offset: number, size: number, overscan: number): Range
	if self.rowCount == 0 then
		return { first = 1, last = 0, firstRow = 1, lastRow = 0 }
	end

	local firstRow = rowAt(self, math.max(0, offset))
	local lastRow: number
	if size <= 0 then
		lastRow = firstRow
	else
		lastRow = rowAt(self, math.max(0, offset) + size)

		local rowStart = rowSpan(self, lastRow)
		if lastRow > firstRow and rowStart >= offset + size then
			lastRow -= 1
		end
	end

	firstRow = math.max(1, firstRow - overscan)
	lastRow = math.min(self.rowCount, lastRow + overscan)

	local columns = self.columns
	return {
		first = (firstRow - 1) * columns + 1,
		last = math.min(self.count, lastRow * columns),
		firstRow = firstRow,
		lastRow = lastRow,
	}
end

return {
	create = create,
	rowsFor = rowsFor,
	totalExtent = totalExtent,
	setItemSize = setItemSize,
	placementOf = placementOf,
	offsetOf = offsetOf,
	rowAt = rowAt,
	rowSpan = rowSpan,
	rangeFor = rangeFor,
}
