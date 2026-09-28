--!strict
export type Rect = { x: number, y: number, width: number, height: number }
export type Direction = "up" | "down" | "left" | "right"

local function neighbor(from: Rect, candidates: { Rect }, direction: Direction): number?
	local vertical = direction == "up" or direction == "down"
	local forward = direction == "down" or direction == "right"
	local bestRank, bestPrimary, bestAcross, found = math.huge, math.huge, math.huge, nil
	for index, candidate in candidates do
		local gap, across, overlap
		if vertical then
			gap = if forward then candidate.y - (from.y + from.height) else from.y - (candidate.y + candidate.height)
			across = math.abs(candidate.x + candidate.width / 2 - (from.x + from.width / 2))
			overlap = candidate.x < from.x + from.width and from.x < candidate.x + candidate.width
		else
			gap = if forward then candidate.x - (from.x + from.width) else from.x - (candidate.x + candidate.width)
			across = math.abs(candidate.y + candidate.height / 2 - (from.y + from.height / 2))
			overlap = candidate.y < from.y + from.height and from.y < candidate.y + candidate.height
		end
		if gap >= -1 then
			local rank = if overlap then 0 else 1
			local primary = if overlap then gap else gap + 2 * across
			if
				rank < bestRank
				or (rank == bestRank and (primary < bestPrimary or (primary == bestPrimary and across < bestAcross)))
			then
				bestRank, bestPrimary, bestAcross, found = rank, primary, across, index
			end
		end
	end
	return found
end

return table.freeze({ neighbor = neighbor })
