--!strict
--!native

local stats = require "./stats"

local state = { validating = false }

local YIELDED = "Compose: reactive code yielded. Computeds and effects must complete "
	.. "without yielding; use an async resource for work that waits."

type Completion = { done: boolean }

local function finish<R...>(completion: Completion, ...: R...): R...
	completion.done = true
	return ...
end

local function check<R...>(completion: Completion, ...: R...): R...
	if not completion.done then
		error(YIELDED, 3)
	end
	return ...
end

local function call<A..., R...>(fn: (A...) -> R..., ...: A...): R...
	if not state.validating then
		return fn(...)
	end
	local completion: Completion = { done = false }
	local wrapped = coroutine.wrap(function(...: A...): R...
		return finish(completion, fn(...))
	end)
	return check(completion, wrapped(...))
end

local function setValidating(value: boolean)
	local resume = stats.state.resume
	if value and resume ~= nil then
		resume()
	end
	state.validating = value
end

return {
	call = call,
	state = state,
	setValidating = setValidating,
}
