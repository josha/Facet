--!strict

local state = { validating = false }

local YIELDED = "Compose: reactive code yielded. Computeds and effects must complete "
	.. "without yielding; use an async resource for work that waits."

local function raise(co: thread, cause: unknown): never
	if type(cause) == "string" then
		error(debug.traceback(co, cause), 2)
	end
	error(cause, 2)
end

local function settle(co: thread, ok: boolean, ...: any): ...any
	if ok and coroutine.status(co) == "dead" then
		return ...
	end
	if ok then
		return raise(co, YIELDED)
	end
	return raise(co, (...))
end

local function guarded(fn: any, ...: any): ...any
	local co = coroutine.create(fn)
	return settle(co, coroutine.resume(co, ...))
end

local checked = (guarded :: any) :: <Args..., Rets...>(fn: (Args...) -> Rets..., Args...) -> Rets...

local function call<Args..., Rets...>(fn: (Args...) -> Rets..., ...: Args...): Rets...
	if state.validating then
		return checked(fn, ...)
	end
	return fn(...)
end

local function setValidating(value: boolean)
	state.validating = value
end

return {
	call = call,

	state = state,
	setValidating = setValidating,
}
