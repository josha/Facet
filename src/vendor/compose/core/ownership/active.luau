--!strict

local Diagnostics = require "../diagnostics"
local Owner = require "./owner"
local Types = require "../reactive/types"

type Dispose = Types.Dispose

type Activation = { owner: Owner.Owner, thread: thread }

local activations: { Activation } = {}

local function current(): Owner.Owner?
	local running = coroutine.running()
	local inherited: Owner.Owner? = nil
	for index = #activations, 1, -1 do
		local activation = activations[index]
		if activation.thread == running then
			return activation.owner
		end
		local status = coroutine.status(activation.thread)
		if status == "normal" then
			if inherited == nil then
				inherited = activation.owner
			end
		elseif status == "dead" then
			table.remove(activations, index)
		end
	end
	return inherited
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

local function depth(): number
	return #activations
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
