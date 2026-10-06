--!strict

local Diagnostics = require "../diagnostics"
local Owner = require "./owner"
local Graph = require "../reactive/graph"
local Types = require "../reactive/types"

type Dispose = Types.Dispose

type Activation = { owner: Owner.Owner, thread: thread }

local activations: { Activation } = {}

local function depth(): number
	local running = coroutine.running()
	local count = 0
	for _, activation in activations do
		if activation.thread == running or coroutine.status(activation.thread) == "normal" then
			count += 1
		end
	end
	return count
end

local function current(): Owner.Owner?
	local running = coroutine.running()
	local explicit: Owner.Owner? = nil
	local inherited: Owner.Owner? = nil
	local seen: { [thread]: boolean } = {}
	local ambiguous = false
	for index = #activations, 1, -1 do
		local activation = activations[index]
		if activation.thread == running then
			if explicit == nil then
				explicit = activation.owner
			end
		else
			local status = coroutine.status(activation.thread)
			if status == "normal" and not seen[activation.thread] then
				seen[activation.thread] = true
				if inherited == nil then
					inherited = activation.owner
				elseif inherited ~= activation.owner then
					ambiguous = true
				end
			elseif status == "dead" then
				table.remove(activations, index)
			end
		end
	end
	if explicit == nil and ambiguous then
		Diagnostics.raise("owner/no-active-owner", "resumer owners are ambiguous", {
			contract = "a callback cannot infer the order of distinct resumer owners",
			fix = "bind the child callback with Compose.bindOwner or activate its owner with Compose.withOwner",
		})
	end
	local context = Graph.evaluationContext()
	if context ~= nil then
		local record = Owner.runScopeOf(context)
		if record ~= nil and depth() <= record.base then
			return record.scope
		end
	end
	return explicit or inherited
end

local function push(owner: Owner.Owner): Activation
	local activation: Activation = { owner = owner, thread = coroutine.running() }
	table.insert(activations, activation)
	return activation
end

local function pop(activation: Activation)
	local last = #activations
	if activations[last] == activation then
		activations[last] = nil
		return
	end
	local index = table.find(activations, activation)
	if index ~= nil then
		table.remove(activations, index)
	end
end

local function release<T...>(activation: Activation, ok: boolean, ...: T...): T...
	pop(activation)
	if not ok then
		error(select(1, ...), 0)
	end
	return ...
end

local function withOwner<T...>(owner: Owner.Owner, body: () -> T...): T...
	local activation = push(owner)
	return release(activation, pcall(body))
end

local function bind<Args..., Rets...>(owner: Owner.Owner, body: (Args...) -> Rets...): (Args...) -> Rets...
	return function(...: Args...): Rets...
		local activation = push(owner)
		return release(activation, pcall(body, ...))
	end
end

local function own(dispose: Dispose, operation: string): Dispose
	local owner = current()
	if owner == nil then
		Diagnostics.raise("owner/no-active-owner", ("%s has no owner to register with"):format(operation), {
			contract = "resources must be created inside a mount, so something can release them",
			fix = "wrap the caller in runtime.mount(component, target), or pass an explicit owner",
		})
	end
	return (owner :: Owner.Owner).own(dispose)
end

local function runWith<A...>(owner: Owner.Owner, body: (A...) -> (), ...: A...)
	local activation = push(owner)
	local ok, err: unknown = pcall(body, ...)
	pop(activation)
	if not ok then
		error(err, 0)
	end
end

local function runWith1<T>(owner: Owner.Owner, body: () -> T): T
	local activation = push(owner)
	local ok, result = pcall(body)
	pop(activation)
	if not ok then
		error(result, 0)
	end
	return result
end

Owner.installActivationDepth(depth)

local function resetForTests()
	table.clear(activations)
end

return {
	current = current,
	depth = depth,
	withOwner = withOwner,
	bind = bind,
	runWith = runWith,
	runWith1 = runWith1,
	own = own,
	resetForTests = resetForTests,
}
