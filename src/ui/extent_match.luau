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
export type State = { entries: { [unknown]: Entry }, waited: number }

local extentMatch = {}

function extentMatch.new(): State
	local entries: { [unknown]: Entry } = setmetatable({}, { __mode = "k" })
	return { entries = entries, waited = 0 }
end

function extentMatch.forget(state: State, key: unknown)
	state.entries[key] = nil
end

local QUIET = 2
local PATIENCE = 8

local function close(a: number?, b: number?): boolean
	return a ~= nil and b ~= nil and math.abs(a - b) < 0.5
end

function extentMatch.step(
	state: State,
	members: { read [number]: unknown },
	measured: { [unknown]: number },
	content: { [unknown]: number },
	quiet: number?
): ({ [unknown]: number }, boolean)
	local needed = if quiet == nil then QUIET else quiet
	local entries = state.entries
	local settled = true
	local natural: { [unknown]: number } = {}
	for _, key in members do
		local entry = entries[key]
		if entry == nil then
			local created: Entry = {
				min = 0,
				offset = nil,
				bias = 0,
				lastSize = nil,
				lastMin = nil,
				lastContent = nil,
				quiet = 0,
				corrected = false,
			}
			entries[key] = created
			entry = created
		end
		local size, own = measured[key] or 0, content[key] or 0
		local stable = close(size, entry.lastSize) and close(entry.min, entry.lastMin) and close(own, entry.lastContent)
		entry.quiet = if stable then entry.quiet + 1 else 0
		if entry.quiet < needed then
			settled = false
		end
		entry.lastSize, entry.lastMin, entry.lastContent = size, entry.min, own
	end
	if not settled and state.waited < PATIENCE then
		state.waited += 1
		local held: { [unknown]: number } = {}
		for _, key in members do
			held[key] = entries[key].min
		end
		return held, false
	end
	state.waited = 0
	for _, key in members do
		local entry = entries[key]
		local size, own = measured[key] or 0, content[key] or 0
		if entry.quiet >= needed then
			if entry.min <= 0 then
				entry.bias = size - own
			elseif own + entry.bias < size - 0.5 then
				entry.offset = size - entry.min
			end
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
	local goal = if widest == nil then 0 elseif entries[widest].min > 0 then largest else measured[widest] or largest
	for _, key in members do
		local entry = entries[key]
		local outgrown = entry.min > 0 and entry.corrected and (measured[key] or 0) > goal + 0.5
		if outgrown then
			entry.offset = nil
		end
		local value = if #members < 2
				or key == widest
				or outgrown
				or natural[key] >= goal - 0.5
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
