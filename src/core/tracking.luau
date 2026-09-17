--!strict
-- A yielding user callback must never lend its dependency context to another task.
local contexts: { [thread]: any } = setmetatable({}, { __mode = "k" }) :: any
-- Luau weak-key tables are not ephemerons: a value that points back to its
-- key keeps the whole graph alive. These indexes borrow both halves. A getter
-- already closes over its source; the mounted owner holds its binding cache.
local tracking = { sources = setmetatable({}, { __mode = "kv" }) :: any }
function tracking.current(): any
	return contexts[coroutine.running()]
end
function tracking.run(scope: any, fn: any, ...: any): (boolean, any)
	local thread = coroutine.running()
	local previous = contexts[thread]
	contexts[thread] = scope
	local ok, result = pcall(fn, ...)
	contexts[thread] = previous
	return ok, result
end
-- Bindings are shared only within a mounted owner, never across mounts/cores.
local bindings: { [any]: { [any]: any } } = setmetatable({}, { __mode = "kv" }) :: any
local owners: { [any]: any } = setmetatable({}, { __mode = "kv" }) :: any
function tracking.inheritBindings(child: any, parent: any)
	owners[child] = owners[parent] or parent
end
function tracking.bind(core: any, scope: any, read: any): any
	local known = tracking.sources[read]
	if known then
		return known
	end
	local owner = owners[scope] or scope
	local cache = bindings[owner]
	if not cache then
		cache = {}
		bindings[owner] = cache
		owner:own(function()
			bindings[owner] = nil
			table.clear(cache)
		end)
	end
	if not cache[read] then
		cache[read] = owner:own(core:memo(function()
			return read(tracking.current())
		end))
	end
	return cache[read]
end
-- Internal update provenance keeps frame-driven presentation out of layout flights.
local origins: { [thread]: string } = setmetatable({}, { __mode = "k" }) :: any
function tracking.origin(): string?
	return origins[coroutine.running()]
end
function tracking.withOrigin(origin: string, run: () -> ())
	local thread = coroutine.running()
	local previous = origins[thread]
	origins[thread] = origin
	local ok, err = pcall(run :: any)
	origins[thread] = previous
	if not ok then
		error(err, 0)
	end
end
return tracking
