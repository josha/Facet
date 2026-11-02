--!strict

local YIELDED = "Compose: reactive code yielded. Computeds and effects must complete "
	.. "without yielding; use an async resource for work that waits."

type Completion = { done: boolean }

local function finish<R...>(completion: Completion, ...: R...): R...
	completion.done = true
	return ...
end

local function check<R...>(completion: Completion, ...: R...): R...
	if not completion.done then
		error(YIELDED, 4)
	end
	return ...
end

return function<A..., R...>(fn: (A...) -> R..., ...: A...): R...
	local completion: Completion = { done = false }
	local wrapped = coroutine.wrap(function(...: A...): R...
		return finish(completion, fn(...))
	end)
	return check(completion, wrapped(...))
end
