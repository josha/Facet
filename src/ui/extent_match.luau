--!strict
export type Entry = { min: number, offset: number?, bias: number }
export type State = { [unknown]: Entry }

local extentMatch = {}

function extentMatch.new(): State
	return (setmetatable({}, { __mode = "k" }) :: unknown) :: State
end

function extentMatch.step(
	state: State,
	members: { unknown },
	measured: { [unknown]: number },
	content: { [unknown]: number }
): { [unknown]: number }
	local natural: { [unknown]: number } = {}
	for _, key in members do
		local entry = state[key]
		if entry == nil then
			entry = { min = 0, offset = nil, bias = 0 }
			state[key] = entry
		end
		local size, own = measured[key] or 0, content[key] or 0
		if entry.min <= 0 then
			entry.bias = size - own
		end
		natural[key] = own + entry.bias
	end
	local widest: unknown = nil
	local largest = -math.huge
	for _, key in members do
		if natural[key] > largest then
			widest, largest = key, natural[key]
		end
	end
	local mins: { [unknown]: number } = {}
	if widest == nil or #members < 2 then
		for _, key in members do
			state[key].min = 0
			mins[key] = 0
		end
		return mins
	end
	local goal = if state[widest].min > 0 then largest else measured[widest] or largest
	for _, key in members do
		local entry = state[key]
		local own, size = natural[key], measured[key] or 0
		if key == widest or own >= goal - 0.5 then
			entry.min = 0
			mins[key] = 0
		else
			if entry.min > 0 and size >= entry.min - 0.5 and own < size - 0.5 then
				entry.offset = size - entry.min
			end
			entry.min = math.max(0.5, goal - (entry.offset or 0))
			mins[key] = entry.min
		end
	end
	return mins
end

return extentMatch
