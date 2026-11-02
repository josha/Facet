--!strict
local ComposeTypes = require("../vendor/compose/core")

export type Floor = { x: ComposeTypes.Value<number>, y: ComposeTypes.Value<number> }

local floors: { [Instance]: Floor } = setmetatable({}, { __mode = "k" })

local sizeFloor = {}

function sizeFloor.of(node: Instance, cell: typeof(ComposeTypes.cell)): Floor
	local floor = floors[node]
	if floor == nil then
		floor = { x = cell(0), y = cell(0) }
		floors[node] = floor
	end
	return floor
end

function sizeFloor.peek(node: Instance): Floor?
	return floors[node]
end

return sizeFloor
