--!strict
export type Entry = {
	min: number,
	offset: number?,
	bias: number,
	lastSize: number?,
	lastMin: number?,
	lastContent: number?,
	quiet: number,
	corrected: boolean,
}
export type State = { [unknown]: Entry }

local extentMatch = {}

function extentMatch.new(): State
	return (setmetatable({}, { __mode = "k" }) :: unknown) :: State
end

local QUIET = 2

local function close(a: number?, b: number?): boolean
	return a ~= nil and b ~= nil and math.abs(a - b) < 0.5
end

function extentMatch.step(
	state: State,
	members: { unknown },
	measured: { [unknown]: number },
	content: { [unknown]: number },
	quiet: number?
): ({ [unknown]: number }, boolean)
	local needed = if quiet == nil then QUIET else quiet
	local settled = true
	local natural: { [unknown]: number } = {}
	for _, key in members do
		local entry = state[key]
		if entry == nil then
			entry = {
				min = 0,
				offset = nil,
				bias = 0,
				lastSize = nil,
				lastMin = nil,
				lastContent = nil,
				quiet = 0,
				corrected = false,
			}
			state[key] = entry
		end
		local size, own = measured[key] or 0, content[key] or 0
		local stable = close(size, entry.lastSize)
			and close(entry.min, entry.lastMin)
			and close(own, entry.lastContent)
		entry.quiet = if stable then entry.quiet + 1 else 0
		if entry.quiet < needed then
			settled = false
		end
		entry.lastSize, entry.lastMin, entry.lastContent = size, entry.min, own
	end
	if not settled then
		local held: { [unknown]: number } = {}
		for _, key in members do
			held[key] = state[key].min
		end
		return held, false
	end
	for _, key in members do
		local entry = state[key]
		local size, own = measured[key] or 0, content[key] or 0
		if entry.min <= 0 then
			entry.bias = size - own
		elseif own + entry.bias < size - 0.5 then
			entry.offset = size - entry.min
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
	local goal = if widest == nil
		then 0
		elseif state[widest].min > 0 then largest
		else measured[widest] or largest
	for _, key in members do
		local entry = state[key]
		local outgrown = entry.min > 0 and entry.corrected and (measured[key] or 0) > goal + 0.5
		if outgrown then
			entry.offset = nil
		end
		local value = if #members < 2 or key == widest or outgrown or natural[key] >= goal - 0.5
			then 0
			else math.max(0.5, goal - (entry.offset or 0))
		entry.corrected = value > 0 and entry.offset ~= nil
		if not close(value, entry.min) then
			settled = false
		end
		entry.min = value
		mins[key] = value
	end
	return mins, settled
end

return extentMatch
