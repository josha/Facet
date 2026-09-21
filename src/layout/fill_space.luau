--!strict
-- Integer fill shares, identical in measurement and placement. Rounding every
-- share down is conservative for wrapped text but undermeasures aspect images.
local fillSpace = {}
local function rounded(remaining: number, weightSum: number, shares: { any }): { [number]: number }
	local pixels = {}
	local acc = 0
	for _, share in shares do
		local exact = remaining * share.weight / weightSum
		share.floor = math.floor(exact)
		share.rem = exact - share.floor
		acc += share.floor
	end
	table.sort(shares, function(a, b)
		return if a.rem ~= b.rem then a.rem > b.rem else a.i < b.i
	end)
	local leftover = remaining - acc
	for rank, share in shares do
		pixels[share.i] = share.floor + (if rank <= leftover then 1 else 0)
	end
	return pixels
end
-- Optional fill minima clamp only deficient shares. Unconstrained weights keep
-- the established largest-remainder result; Spacer bases are reserved by callers.
function fillSpace.allocate(remaining: number, weightSum: number, shares: { any }): { [number]: number }
	local constrained = false
	for _, share in shares do
		constrained = constrained or (share.min or 0) > 0
	end
	if not constrained then
		return rounded(remaining, weightSum, shares)
	end
	local pending = shares
	local fixed = {}
	while #pending > 0 do
		local pixels = rounded(math.max(0, remaining), weightSum, pending)
		local nextPending = {}
		local clamped = false
		for _, share in pending do
			local minimum = math.ceil(share.min or 0)
			if pixels[share.i] < minimum then
				fixed[share.i] = minimum
				remaining -= minimum
				weightSum -= share.weight
				clamped = true
			else
				table.insert(nextPending, share)
			end
		end
		if not clamped then
			for i, value in pixels do
				fixed[i] = value
			end
			return fixed
		end
		pending = nextPending
	end
	return fixed
end

-- Dimensions arrive normalized by layout_node; only fill has this offer floor.
function fillSpace.extent(dim: any, offer: number): number
	return if dim.type == "fill" and dim.min ~= nil then math.max(offer, dim.min) else offer
end

return fillSpace
