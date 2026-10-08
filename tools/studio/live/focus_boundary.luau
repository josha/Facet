--!strict

return function(minimum: unknown, maximum: unknown, before: unknown, after: unknown): number
	if
		type(minimum) ~= "number"
		or type(maximum) ~= "number"
		or type(before) ~= "number"
		or type(after) ~= "number"
	then
		return 128
	end
	local span = maximum - minimum
	local change = math.abs(after - before)
	if span <= 0 or span >= math.huge or change <= 0 or change >= math.huge or span ~= span or change ~= change then
		return 128
	end
	return math.max(128, math.ceil(span / change) + 2)
end
