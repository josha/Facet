--!strict
local release = {}

release.PROJECTION_S = 0.15
release.DISMISS_FRACTION = 0.7

export type Stop = { id: string, height: number, index: number }

local function band(over: number, limit: number): number
	if limit <= 0 then
		return 0
	end
	return limit * over / (over + limit)
end

function release.choose(
	stops: { Stop },
	released: number,
	velocity: number,
	current: string,
	canDismiss: boolean
): string
	local projected = released + velocity * release.PROJECTION_S
	local threshold = stops[1].height * release.DISMISS_FRACTION
	if canDismiss and released < threshold and projected < threshold then
		return "dismiss"
	end
	local best: Stop? = nil
	local bestGap = math.huge
	for _, stop in stops do
		local gap = math.abs(stop.height - projected)
		local better = gap < bestGap
			or (
				gap == bestGap
				and best ~= nil
				and best.id ~= current
				and (stop.id == current or stop.index < best.index)
			)
		if better then
			best, bestGap = stop, gap
		end
	end
	return (best :: Stop).id
end

function release.resist(
	raw: number,
	lowest: number,
	highest: number,
	room: number,
	canDismiss: boolean,
	limit: number
): number
	if raw > highest then
		return math.min(room, highest + band(raw - highest, math.max(0, room - highest)))
	end
	if raw < lowest then
		if canDismiss then
			return math.max(1, raw)
		end
		return lowest - band(lowest - raw, limit)
	end
	return raw
end

return release
