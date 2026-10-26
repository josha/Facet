--!strict
--!native

local Types = require "../reactive/types"
local Weak = require "../weak"
local Inspect = require "./inspect"
local Reactor = require "../reactive/reactor"
local watchModule = require "../reactive/watch"
local Evaluation = require "../reactive/evaluation"

type Dispose = Types.Dispose

export type Boundary = {
	report: (failure: unknown) -> (),
}

export type Entry = {
	release: Dispose | Owner | nil,
	after: Dispose?,
	previous: Entry?,
	following: Entry?,
}

export type Owner = {
	parent: Owner?,
	reactor: Reactor.Reactor,
	boundary: Boundary?,
	head: Entry?,
	count: number,
	disposed: boolean,
	attachment: Entry?,
}

local currentOwner: () -> Owner? = function(): Owner?
	return nil
end

local function new(inherited: Reactor.Reactor?, parent: Owner?): Owner
	return {
		parent = parent or currentOwner(),
		reactor = inherited or Reactor.create(),
		boundary = nil,
		head = nil,
		count = 0,
		disposed = false,
		attachment = nil,
	}
end

local function noop() end

local function raiseAll(failures: { unknown })
	local count = #failures
	if count == 0 then
		return
	end
	if count == 1 then
		error(failures[1], 0)
	end
	local parts = { ("Compose: %d errors while disposing an owner:"):format(count) }
	for index, failure in failures do
		table.insert(parts, ("  [%d] %s"):format(index, tostring(failure)))
	end
	error(table.concat(parts, "\n"), 0)
end

local disposeOwner: (owner: Owner) -> ()

local function release(target: Dispose | Owner | nil)
	if type(target) == "function" then
		target()
	elseif target ~= nil then
		disposeOwner(target)
	end
end

local function releaseEntry(entry: Entry, failures: { unknown })
	local target = entry.release
	entry.release = nil
	local after = entry.after
	if after == nil then
		release(target)
		return
	end
	entry.after = nil
	local ok, failure: unknown = pcall(release, target)
	if not ok then
		table.insert(failures, failure)
	end
	local settled, later: unknown = pcall(after)
	if not settled then
		table.insert(failures, later)
	end
end

local function unlink(owner: Owner, entry: Entry)
	local previous = entry.previous
	local following = entry.following
	if previous ~= nil then
		previous.following = following
	else
		owner.head = following
	end
	if following ~= nil then
		following.previous = previous
	end
	entry.previous = nil
	entry.following = nil
	owner.count -= 1
end

local function link(owner: Owner, target: Dispose | Owner, after: Dispose?): Entry
	local first = owner.head
	local entry: Entry = { release = target, previous = nil, following = first }
	if after ~= nil then
		entry.after = after
	end
	if first ~= nil then
		first.previous = entry
	end
	owner.head = entry
	owner.count += 1
	return entry
end

export type RunScope = { child: Owner?, base: number, inherited: Owner }

local runScopes: { [unknown]: RunScope } = {}
Weak.keys(runScopes)

local activationDepth: () -> number = function(): number
	return 0
end

local function installActivationDepth(depth: () -> number)
	activationDepth = depth
end

local function installCurrentOwner(current: () -> Owner?)
	currentOwner = current
end

local function runScopeOf(consumer: unknown): RunScope?
	return runScopes[consumer]
end

local function createOwner(inherited: Reactor.Reactor?, parent: Owner?): Owner
	return new(inherited, parent)
end

local function own(owner: Owner, dispose: Dispose, after: Dispose?): Dispose
	if owner.disposed then
		dispose()
		if after ~= nil then
			after()
		end
		return noop
	end
	local entry = link(owner, dispose, after)
	return function()
		if owner.disposed or entry.release == nil then
			return
		end
		unlink(owner, entry)
		if entry.after == nil then
			local target = entry.release
			entry.release = nil
			release(target)
			return
		end
		local failures: { unknown } = {}
		releaseEntry(entry, failures)
		raiseAll(failures)
	end
end

local function adopt(owner: Owner, dispose: Dispose)
	if owner.disposed then
		dispose()
		return
	end
	link(owner, dispose, nil)
end

local function checkpoint(owner: Owner): Entry?
	return owner.head
end

local function rollbackTo(owner: Owner, token: Entry?)
	local failures: { unknown } = {}
	local pending = owner.head

	local function releaseRest()
		while true do
			local entry = pending
			if entry == nil or entry == token then
				break
			end
			pending = entry.following
			unlink(owner, entry)
			releaseEntry(entry, failures)
		end
	end

	while pending ~= nil and pending ~= token do
		local ok, failure: unknown = pcall(releaseRest)
		if not ok then
			table.insert(failures, failure)
		end
	end
	raiseAll(failures)
end

disposeOwner = function(owner: Owner)
	if owner.disposed then
		return
	end
	owner.disposed = true

	local attachment = owner.attachment
	if attachment ~= nil then
		owner.attachment = nil
		local parent = owner.parent
		if parent ~= nil and not parent.disposed and attachment.release ~= nil then
			unlink(parent, attachment)
			attachment.release = nil
		end
	end
	owner.parent = nil

	local pending = owner.head
	owner.head = nil
	owner.count = 0
	if pending == nil then
		return
	end

	local failures: { unknown } = {}
	local function releaseRest()
		while pending ~= nil do
			local entry = pending
			pending = entry.following
			entry.previous = nil
			entry.following = nil
			releaseEntry(entry, failures)
		end
	end

	repeat
		local ok, failure: unknown = pcall(releaseRest)
		if not ok then
			table.insert(failures, failure)
		end
	until pending == nil
	raiseAll(failures)
end

local function isDisposed(owner: Owner): boolean
	return owner.disposed
end

local function size(owner: Owner): number
	return owner.count
end

local function guardWith(owner: Owner, boundary: Boundary)
	owner.boundary = boundary
end

local function createChild(owner: Owner): Owner
	local child = new(owner.reactor, owner)
	if owner.disposed then
		disposeOwner(child)
	else
		child.attachment = link(owner, child, nil)
	end
	if Inspect.isActive() then
		Inspect.child(owner, child)
	end
	child.boundary = owner.boundary
	return child
end

local function startWatch<A, B>(
	owner: Owner,
	factory: (reactor: Reactor.Reactor, first: A, second: B) -> Dispose,
	first: A,
	second: B,
	after: Dispose?
): Dispose
	if after == nil then
		return own(owner, factory(owner.reactor, first, second))
	end
	local ok, dispose = pcall(factory, owner.reactor, first, second)
	if not ok then
		after()
		error(dispose, 0)
	end
	return own(owner, dispose, after)
end

local function watchStatic<T>(
	owner: Owner,
	producer: Types.ReadOnlyValue<T>,
	body: (value: T) -> (),
	after: Dispose?
): Dispose
	if Inspect.isActive() then
		Inspect.watch(owner)
	end
	local boundary = owner.boundary
	if boundary == nil then
		return startWatch(owner, watchModule.watchStatic, producer, body, after)
	end
	return startWatch(owner, watchModule.watchGuarded, function(use: Types.Use)
		local ok, err: unknown = pcall(function()
			body(use(producer))
		end)
		if not ok then
			boundary.report(err)
		end
	end, nil, after)
end

local function watchTerminal(owner: Owner, body: (use: Types.Use) -> (), after: Dispose?): Dispose
	if Inspect.isActive() then
		Inspect.watch(owner)
	end
	local boundary = owner.boundary
	if boundary == nil then
		return startWatch(owner, watchModule.watchTerminal, body, nil, after)
	end
	return startWatch(owner, watchModule.watchTerminal, function(use: Types.Use)
		local ok, err: unknown = pcall(body, use)
		if not ok then
			boundary.report(err)
		end
	end, nil, after)
end

local function scopedRuns(
	owner: Owner,
	body: (use: Types.Use) -> (),
	after: Dispose?
): ((use: Types.Use) -> (), Dispose)
	local record: RunScope = { child = nil, base = 0, inherited = owner }
	local function releaseChild()
		local current = record.child
		if current then
			record.child = nil
			disposeOwner(current)
		end
	end
	local registered = false
	local function scoped(use: Types.Use)
		if record.child ~= nil then
			releaseChild()
		end
		if not registered then
			local consumer = Evaluation.context()
			if consumer ~= nil then
				runScopes[consumer] = record
				registered = true
			end
		end
		record.base = activationDepth()
		body(use)
	end
	local function released()
		releaseChild()
		if after ~= nil then
			after()
		end
	end
	return scoped, released
end

local function watch(owner: Owner, body: (use: Types.Use) -> (), label: string?, after: Dispose?): Dispose
	if Inspect.isActive() then
		Inspect.watch(owner)
	end
	local scoped, released = scopedRuns(owner, body, after)
	local boundary = owner.boundary
	if boundary == nil then
		return startWatch(owner, watchModule.watch, scoped, label, released)
	end
	return startWatch(owner, watchModule.watchGuarded, function(use: Types.Use)
		local ok, err: unknown = pcall(scoped, use)
		if not ok then
			boundary.report(err)
		end
	end, label, released)
end

local function disposer(owner: Owner): Dispose
	return function()
		disposeOwner(owner)
	end
end

local function scopeOwner(record: RunScope): Owner
	local child = record.child
	if child then
		return child
	end
	local created = createChild(record.inherited)
	record.child = created
	return created
end

return {
	createOwner = createOwner,
	raiseAll = raiseAll,
	installActivationDepth = installActivationDepth,
	installCurrentOwner = installCurrentOwner,
	runScopeOf = runScopeOf,
	scopeOwner = scopeOwner,
	disposer = disposer,
	api = {
		own = own,
		adopt = adopt,
		watch = watch,
		watchStatic = watchStatic,
		watchTerminal = watchTerminal,
		createChild = createChild,
		dispose = disposeOwner,
		isDisposed = isDisposed,
		size = size,
		checkpoint = checkpoint,
		rollbackTo = rollbackTo,
		guardWith = guardWith,
	},
	own = own,
	adopt = adopt,
	watch = watch,
	watchStatic = watchStatic,
	watchTerminal = watchTerminal,
	createChild = createChild,
	dispose = disposeOwner,
	isDisposed = isDisposed,
	size = size,
	checkpoint = checkpoint,
	rollbackTo = rollbackTo,
	guardWith = guardWith,
}
