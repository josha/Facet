--!strict
--[[ Where a released Sheet goes, and how far a drag may pull past its limits.
	Pure: heights in, an id (or "dismiss") out, so every sign and tie is
	testable without a mounted sheet.

	RELEASE. The projected height is the released height plus the height
	velocity times PROJECTION_S (a downward flick is a negative height
	velocity). The nearest detent to that projection wins; an exact tie keeps
	the current id, then the authored order. Dismissal is decided by where the
	sheet ACTUALLY is: below DISMISS_FRACTION of the lowest detent, and not being
	flicked back above it. Velocity alone never dismisses a barely moved sheet.

	RESISTANCE. Between the lowest and highest detents the drag is 1:1. Past the
	highest it approaches the safe room and never exceeds it; below the lowest
	it is free when dismissal is allowed, and otherwise approaches `limit` px
	under the lowest. Both bands have slope 1 at the edge, so there is no jump. ]]
local sheet_release = {}

sheet_release.PROJECTION_S = 0.15
sheet_release.DISMISS_FRACTION = 0.7

export type Stop = { id: string, height: number, index: number }

-- a band that starts at slope 1 and approaches `limit`
local function band(over: number, limit: number): number
	if limit <= 0 then
		return 0
	end
	return limit * over / (over + limit)
end

-- `stops` sorted by height (ties in authored order)
function sheet_release.choose(
	stops: { Stop },
	released: number,
	velocity: number,
	current: string,
	canDismiss: boolean
): string
	local projected = released + velocity * sheet_release.PROJECTION_S
	local threshold = stops[1].height * sheet_release.DISMISS_FRACTION
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

function sheet_release.resist(
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

return sheet_release
