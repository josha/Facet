--!strict
-- Integer fill shares, identical in measurement and placement. Rounding every
-- share down is conservative for wrapped text but undermeasures aspect images.
local fillSpace = {}
function fillSpace.allocate(remaining: number, weightSum: number, shares: { any }): { [number]: number }
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
return fillSpace
