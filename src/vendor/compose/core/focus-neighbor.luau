--!strict

local FocusScope = require "./focus-scope"
local Diagnostics = require "./diagnostics"

export type FocusRect = { x: number, y: number, width: number, height: number }

local function focusNeighbor(from: FocusRect, candidates: { FocusRect }, direction: FocusScope.Direction): number?
	if direction ~= "left" and direction ~= "right" and direction ~= "up" and direction ~= "down" then
		Diagnostics.raise("focus-neighbor/unknown-direction", "focusNeighbor needs a known direction", {
			expected = '"left", "right", "up", or "down"',
		})
	end
	local vertical = direction == "up" or direction == "down"
	local forward = direction == "down" or direction == "right"
	local bestTier, bestPrimary, bestAcross, found = math.huge, math.huge, math.huge, nil
	for index, candidate in candidates do
		local gap, along, across, overlap, extent, reach
		if vertical then
			local edge = if forward then from.y + from.height else from.y
			extent = from.height
			reach = if forward then candidate.y + candidate.height - edge else edge - candidate.y
			gap = if forward then candidate.y - edge else edge - (candidate.y + candidate.height)
			along = (candidate.y + candidate.height / 2 - edge) * (if forward then 1 else -1)
			across = math.abs(candidate.x + candidate.width / 2 - (from.x + from.width / 2))
			overlap = candidate.x < from.x + from.width and from.x < candidate.x + candidate.width
		else
			local edge = if forward then from.x + from.width else from.x
			extent = from.width
			reach = if forward then candidate.x + candidate.width - edge else edge - candidate.x
			gap = if forward then candidate.x - edge else edge - (candidate.x + candidate.width)
			along = (candidate.x + candidate.width / 2 - edge) * (if forward then 1 else -1)
			across = math.abs(candidate.y + candidate.height / 2 - (from.y + from.height / 2))
			overlap = candidate.y < from.y + from.height and from.y < candidate.y + candidate.height
		end
		if gap > -extent / 2 and (overlap or reach > 0) then
			local tier, primary
			if overlap then
				tier, primary = 0, gap
			elseif across < along then
				tier, primary = 1, across + along * 0.028
			else
				tier, primary = 2, across / math.max(along, 1) ^ 0.15
			end
			if
				tier < bestTier
				or (tier == bestTier and (primary < bestPrimary or (primary == bestPrimary and across < bestAcross)))
			then
				bestTier, bestPrimary, bestAcross, found = tier, primary, across, index
			end
		end
	end
	return found
end

return focusNeighbor
