--!strict
--!native

local state = { now = 0 }

local function next(): number
	local value = state.now + 1
	state.now = value
	return value
end

local function current(): number
	return state.now
end

local function reset()
	state.now = 0
end

return {
	next = next,
	current = current,
	reset = reset,
	state = state,
}
