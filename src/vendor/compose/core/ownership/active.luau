--!strict
--!native

local Diagnostics = require "../diagnostics"
local Owner = require "./owner"
local Evaluation = require "../reactive/evaluation"
local Types = require "../reactive/types"

type Dispose = Types.Dispose

local owners: { Owner.Owner } = {}
local threads: { thread } = {}
local stacked: { [thread]: number? } = {}

local function unstack(thread: thread)
	local remaining = (stacked[thread] or 1) - 1
	stacked[thread] = if remaining > 0 then remaining else nil
end

local function depth(): number
	local running = coroutine.running()
	local own = stacked[running] or 0
	if own == #threads then
		return own
	end
	local count = 0
	for _, thread in threads do
		if thread == running or coroutine.status(thread) == "normal" then
			count += 1
		end
	end
	return count
end

local function find(create: boolean): Owner.Owner?
	local running = coroutine.running()
	local context = Evaluation.context()
	local last = #threads
	if context == nil and threads[last] == running then
		return owners[last]
	end
	local explicit: Owner.Owner? = nil
	local inherited: Owner.Owner? = nil
	local seen: { [thread]: boolean }? = nil
	local ambiguous = false
	for index = #threads, 1, -1 do
		local thread = threads[index]
		if thread == running then
			explicit = owners[index]
			break
		else
			local status = coroutine.status(thread)
			if status == "normal" and (seen == nil or not seen[thread]) then
				local visited = seen or {}
				seen = visited
				visited[thread] = true
				if inherited == nil then
					inherited = owners[index]
				elseif inherited ~= owners[index] then
					ambiguous = true
				end
			elseif status == "dead" then
				unstack(thread)
				table.remove(threads, index)
				table.remove(owners, index)
			end
		end
	end
	if context ~= nil then
		local record = Owner.runScopeOf(context)
		if record ~= nil and depth() <= (record.base or 0) then
			return if create then Owner.scopeOwner(record) else record.child or record.inherited
		end
	end
	if explicit == nil and ambiguous then
		error(
			Diagnostics.format("owner/no-active-owner", "resumer owners are ambiguous", {
				contract = "a callback cannot infer the order of distinct resumer owners",
				fix = "bind the child callback with Compose.bindOwner or activate its owner with Compose.withOwner",
			}),
			0
		)
	end
	return explicit or inherited
end

local function current(): Owner.Owner?
	return find(true)
end

local function nearest(): Owner.Owner?
	return find(false)
end

local function isCurrent(owner: Owner.Owner): boolean
	local last = #threads
	return threads[last] == coroutine.running() and owners[last] == owner
end

local function push(owner: Owner.Owner): thread
	local running = coroutine.running()
	local index = #threads + 1
	threads[index] = running
	owners[index] = owner
	stacked[running] = (stacked[running] or 0) + 1
	return running
end

local function pop(owner: Owner.Owner, running: thread)
	local last = #threads
	if threads[last] == running and owners[last] == owner then
		threads[last] = nil
		owners[last] = nil
		unstack(running)
		return
	end
	for index = last, 1, -1 do
		if threads[index] == running and owners[index] == owner then
			unstack(running)
			table.remove(threads, index)
			table.remove(owners, index)
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
		error(
			Diagnostics.format("owner/no-active-owner", ("%s has no owner to register with"):format(operation), {
				contract = "resources must be created inside a mount, so something can release them",
				fix = "wrap the caller in runtime.mount(component, target), or pass an explicit owner",
			}),
			0
		)
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

local function runWith1<T>(owner: Owner.Owner, body: () -> T): T
	local running = push(owner)
	local ok, result = pcall(body)
	pop(owner, running)
	if not ok then
		error(result, 0)
	end
	return result
end

Owner.installActivationDepth(depth)
Owner.installCurrentOwner(current)

local function resetForTests()
	table.clear(threads)
	table.clear(owners)
	table.clear(stacked)
end

return {
	current = current,
	nearest = nearest,
	isCurrent = isCurrent,
	depth = depth,
	withOwner = withOwner,
	bind = bind,
	runWith = runWith,
	runWith1 = runWith1,
	push = push,
	pop = pop,
	own = own,
	resetForTests = resetForTests,
}
