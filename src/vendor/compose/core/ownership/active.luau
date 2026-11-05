--!strict
--!native

local Diagnostics = require "../diagnostics"
local Owner = require "./owner"
local Evaluation = require "../reactive/evaluation"
local Types = require "../reactive/types"

type Dispose = Types.Dispose

local owners: { Owner.Owner } = {}
local threads: { thread } = {}
local evaluations: { number } = {}

local function findOn(create: boolean, running: thread): Owner.Owner?
	local context, evaluation, evaluating = Evaluation.contextOn(running)
	local record = if context ~= nil then Owner.runScopeOf(context) else nil
	local last = #threads
	if threads[last] == running then
		if record == nil or evaluating ~= running or evaluations[last] == evaluation then
			return owners[last]
		end
	end
	local explicit: Owner.Owner? = nil
	local inherited: Owner.Owner? = nil
	local scoped: Owner.Owner? = nil
	local seen: { [thread]: boolean }? = nil
	local ambiguous = false
	local scopeAmbiguous = false
	for index = #threads, 1, -1 do
		local thread = threads[index]
		if thread == running then
			if record == nil or evaluating ~= running or evaluations[index] == evaluation then
				explicit = owners[index]
			end
			break
		else
			local status = coroutine.status(thread)
			if status == "normal" and (seen == nil or not seen[thread]) then
				local visited = seen or {}
				seen = visited
				visited[thread] = true
				if record ~= nil and evaluations[index] == evaluation then
					if scoped == nil then
						scoped = owners[index]
					elseif scoped ~= owners[index] then
						scopeAmbiguous = true
					end
				end
				if inherited == nil then
					inherited = owners[index]
				elseif inherited ~= owners[index] then
					ambiguous = true
				end
			elseif status == "dead" then
				table.remove(threads, index)
				table.remove(owners, index)
				table.remove(evaluations, index)
			end
		end
	end
	if record ~= nil and explicit == nil then
		if not scopeAmbiguous then
			return scoped or (if create then Owner.scopeOwner(record) else record.child or record.inherited)
		end
		ambiguous = true
	end
	if explicit == nil and ambiguous then
		return Diagnostics.raise("owner/no-active-owner", "resumer owners are ambiguous", {
			contract = "a callback cannot infer the order of distinct resumer owners",
			fix = "bind the child callback with Compose.bindOwner or activate its owner with Compose.withOwner",
		})
	end
	return explicit or inherited
end

local function current(): Owner.Owner?
	return findOn(true, coroutine.running())
end

local function nearest(): Owner.Owner?
	return findOn(false, coroutine.running())
end

local evaluationCache = Evaluation.cache

local function resolve(): (Owner.Owner?, boolean)
	local running = coroutine.running()
	local last = #threads
	if threads[last] == running then
		if evaluationCache.active == 0 then
			return owners[last], true
		end
		local frame = evaluationCache.frame
		if frame ~= nil and evaluationCache.thread == running and frame.order > 0 then
			local context = frame.consumer
			if context == nil or context.inherited == nil then
				return owners[last], true
			end
			if evaluations[last] == frame.order then
				return owners[last], true
			end
		end
	end
	local owner = findOn(true, running)
	last = #threads
	return owner, owner ~= nil and threads[last] == running and owners[last] == owner
end

local function push(owner: Owner.Owner): thread
	local running = coroutine.running()
	local index = #threads + 1
	threads[index] = running
	owners[index] = owner
	local _, evaluation = Evaluation.contextOn(running)
	evaluations[index] = evaluation
	return running
end

local function pop(owner: Owner.Owner, running: thread)
	local last = #threads
	if threads[last] == running and owners[last] == owner then
		threads[last] = nil
		owners[last] = nil
		evaluations[last] = nil
		return
	end
	for index = last, 1, -1 do
		if threads[index] == running and owners[index] == owner then
			table.remove(threads, index)
			table.remove(owners, index)
			table.remove(evaluations, index)
			return
		end
	end
end

local function release<T...>(owner: Owner.Owner, running: thread, ok: boolean, ...: T...): T...
	pop(owner, running)
	if not ok then
		error(select(1, ...), 0)
	end
	return ...
end

local function withOwner<T...>(owner: Owner.Owner, body: () -> T...): T...
	return release(owner, push(owner), pcall(body))
end

local function bind<Args..., Rets...>(owner: Owner.Owner, body: (Args...) -> Rets...): (Args...) -> Rets...
	return function(...: Args...): Rets...
		return release(owner, push(owner), pcall(body, ...))
	end
end

local function own(dispose: Dispose, operation: string): Dispose
	local owner = current()
	if owner == nil then
		return Diagnostics.raise("owner/no-active-owner", ("%s has no owner to register with"):format(operation), {
			contract = "resources must be created inside a mount, so something can release them",
			fix = "wrap the caller in runtime.mount(component, target), or pass an explicit owner",
		})
	end
	return Owner.own(owner, dispose)
end

local function runWith<A...>(owner: Owner.Owner, body: (A...) -> (), ...: A...)
	local running = push(owner)
	local ok, err: unknown = pcall(body, ...)
	pop(owner, running)
	if not ok then
		error(err, 0)
	end
end

Owner.installCurrentOwner(current)

local function resetForTests()
	table.clear(threads)
	table.clear(owners)
	table.clear(evaluations)
end

return {
	current = current,
	nearest = nearest,
	resolve = resolve,
	withOwner = withOwner,
	bind = bind,
	runWith = runWith,
	push = push,
	pop = pop,
	own = own,
	resetForTests = resetForTests,
}
