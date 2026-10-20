--!strict
local Spatial = require("./spatial_grid_types")

local function integer(value: number): boolean
	return value > 0 and value < math.huge and value % 1 == 0
end
local function inside(at: Spatial.Placement, columns: number, rows: number): boolean
	return integer(at.column)
		and integer(at.row)
		and integer(at.width)
		and integer(at.height)
		and at.column + at.width - 1 <= columns
		and at.row + at.height - 1 <= rows
end
local function overlaps(a: Spatial.Placement, b: Spatial.Placement): boolean
	return a.column < b.column + b.width
		and b.column < a.column + a.width
		and a.row < b.row + b.height
		and b.row < a.row + a.height
end
return { integer = integer, inside = inside, overlaps = overlaps }
