--!strict
--!native

local sharedTails: { number } = {}
local sharedPrevious: { number } = {}

local function longestIncreasingSubsequence(values: { number }, countOf: number?): { [number]: true }
	local count = if countOf ~= nil then countOf else #values
	local result: { [number]: true } = {}
	if count == 0 then
		return result
	end

	local tails = sharedTails
	local previous = sharedPrevious
	local length = 0

	for index = 1, count do
		local value = values[index]

		local low, high = 1, length
		while low <= high do
			local middle = (low + high) // 2
			if values[tails[middle]] < value then
				low = middle + 1
			else
				high = middle - 1
			end
		end

		previous[index] = if low > 1 then tails[low - 1] else 0
		tails[low] = index
		if low > length then
			length = low
		end
	end

	local cursor = tails[length]
	while cursor ~= 0 and cursor ~= nil do
		result[cursor] = true
		cursor = previous[cursor]
	end
	return result
end

return longestIncreasingSubsequence
