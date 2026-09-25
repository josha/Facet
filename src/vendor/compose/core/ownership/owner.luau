--!strict

local Types = require "../reactive/types"
local Inspect = require "./inspect"
local Reactor = require "../reactive/reactor"
local watchModule = require "../reactive/watch"
local Graph = require "../reactive/graph"

type Dispose = Types.Dispose
type Scope = Types.Use

export type Boundary = {
	report: (failure: unknown) -> (),
}

export type Owner = {
	own: (dispose: Dispose, afterDispose: Dispose?) -> Dispose,
	watch: (body: (use: Types.Use) -> (), label: string?, afterDispose: Dispose?) -> Dispose,
	watchStatic: <T>(producer: Types.Readable<T>, body: (value: T) -> (), afterDispose: Dispose?) -> Dispose,
	watchTerminal: (body: (use: Types.Use) -> (), afterDispose: Dispose?) -> Dispose,
	reactor: Reactor.Reactor,
	createChild: () -> Owner,

	dispose: Dispose,
	isDisposed: () -> boolean,
	size: () -> number,
	checkpoint: () -> unknown,
	rollbackTo: (token: unknown) -> (),

	boundary: Boundary?,
	guardWith: (boundary: Boundary) -> (),

	__attachTo: (detach: Dispose) -> (),
}

local DISPOSE, PREVIOUS, NEXT, ATTACHED, AFTER_DISPOSE = 1, 2, 3, 4, 5

type Entry = { any }

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

local function releaseEntry(entry: Entry, failures: { unknown })
	local afterDispose = entry[AFTER_DISPOSE]
	if afterDispose == nil then
		entry[DISPOSE]()
		return
	end
	entry[AFTER_DISPOSE] = nil
	local ok, failure: unknown = pcall(entry[DISPOSE])
	if not ok then
		table.insert(failures, failure)
	end
	local settled, later: unknown = pcall(afterDispose)
	if not settled then
		table.insert(failures, later)
	end
end

export type RunScope = { scope: Owner, base: number }

local runScopes: { [unknown]: RunScope } = setmetatable({}, { __mode = "k" }) :: any
local activationDepth: () -> number = function(): number
	return 0
end

local function installActivationDepth(depth: () -> number)
	activationDepth = depth
end

local function runScopeOf(consumer: unknown): RunScope?
	return runScopes[consumer]
end

local function createOwner(inherited: Reactor.Reactor?): Owner
	local reactor = inherited or Reactor.create()
	local head: Entry? = nil
	local count = 0
	local disposed = false
	local detachFromParent: Dispose? = nil

	local function unlink(entry: Entry)
		local previous = entry[PREVIOUS]
		local following = entry[NEXT]
		if previous ~= nil then
			previous[NEXT] = following
		else
			head = following
		end
		if following ~= nil then
			following[PREVIOUS] = previous
		end
		entry[PREVIOUS] = nil
		entry[NEXT] = nil
		entry[ATTACHED] = false
		count -= 1
	end

	local function own(dispose: Dispose, afterDispose: Dispose?): Dispose
		if disposed then
			dispose()
			if afterDispose ~= nil then
				afterDispose()
			end
			return noop
		end

		local first = head
		local entry: Entry = { dispose, nil, first, true, afterDispose }
		if first ~= nil then
			first[PREVIOUS] = entry
		end
		head = entry
		count += 1

		return function()
			if disposed or not entry[ATTACHED] then
				return
			end
			unlink(entry)
			if entry[AFTER_DISPOSE] == nil then
				entry[DISPOSE]()
				return
			end
			local failures: { unknown } = {}
			releaseEntry(entry, failures)
			raiseAll(failures)
		end
	end

	local function checkpoint(): unknown
		return head
	end

	local function rollbackTo(token: unknown)
		local boundaryEntry = token :: Entry?
		local failures: { unknown } = {}
		local pending = head

		local function releaseRest()
			while true do
				local entry = pending
				if entry == nil or entry == boundaryEntry then
					break
				end
				pending = entry[NEXT]
				unlink(entry)
				releaseEntry(entry, failures)
			end
		end

		while pending ~= nil and pending ~= boundaryEntry do
			local ok, failure: unknown = pcall(releaseRest)
			if not ok then
				table.insert(failures, failure)
			end
		end
		raiseAll(failures)
	end

	local function disposeOwner()
		if disposed then
			return
		end

		local detach = detachFromParent
		if detach ~= nil then
			detachFromParent = nil
			detach()
			if disposed then
				return
			end
		end

		disposed = true

		local pending = head
		head = nil
		count = 0

		if pending == nil then
			return
		end

		local failures: { unknown } = {}
		local function releaseRest()
			while pending ~= nil do
				local entry = pending
				pending = entry[NEXT]
				entry[PREVIOUS] = nil
				entry[NEXT] = nil
				entry[ATTACHED] = false
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

	local owner: Owner

	local function createChild(): Owner
		local child = createOwner(reactor)
		child.__attachTo(own(child.dispose))
		if Inspect.isActive() then
			Inspect.child(owner, child)
		end
		if owner.boundary ~= nil then
			child.guardWith(owner.boundary :: Boundary)
		end
		return child
	end

	local function startWatch<A, B>(
		factory: (reactor: Reactor.Reactor, first: A, second: B) -> Dispose,
		first: A,
		second: B,
		afterDispose: Dispose?
	): Dispose
		if afterDispose == nil then
			return own(factory(reactor, first, second))
		end
		local ok, dispose = pcall(factory, reactor, first, second)
		if not ok then
			afterDispose()
			error(dispose, 0)
		end
		return own(dispose, afterDispose)
	end

	local function ownedWatchStatic<T>(
		producer: Types.Readable<T>,
		body: (value: T) -> (),
		afterDispose: Dispose?
	): Dispose
		if Inspect.isActive() then
			Inspect.watch(owner)
		end
		local boundary = owner.boundary
		if boundary == nil then
			return startWatch(watchModule.watchStatic, producer, body, afterDispose)
		end
		return startWatch(watchModule.watchGuarded, function(use: Types.Use)
			local ok, err: unknown = pcall(function()
				body(use(producer))
			end)
			if not ok then
				boundary.report(err)
			end
		end, nil, afterDispose)
	end

	local function ownedWatchTerminal(body: (use: Types.Use) -> (), afterDispose: Dispose?): Dispose
		if Inspect.isActive() then
			Inspect.watch(owner)
		end
		local boundary = owner.boundary
		if boundary == nil then
			return startWatch(watchModule.watchTerminal, body, nil, afterDispose)
		end
		return startWatch(watchModule.watchTerminal, function(use: Types.Use)
			local ok, err: unknown = pcall(body, use)
			if not ok then
				boundary.report(err)
			end
		end, nil, afterDispose)
	end

	local function scopedRuns(body: (use: Types.Use) -> (), afterDispose: Dispose?): ((use: Types.Use) -> (), Dispose)
		local run: Owner? = nil
		local scope = setmetatable({}, {
			__index = function(_: unknown, key: string): unknown
				local current = run
				if current == nil then
					current = createChild()
					run = current
				end
				return ((current :: any) :: { [string]: unknown })[key]
			end,
		}) :: any
		local function release()
			local current = run
			if current ~= nil then
				run = nil
				current.dispose()
			end
		end
		local record: RunScope = { scope = scope :: Owner, base = 0 }
		local registered = false
		local function scoped(use: Types.Use)
			if run ~= nil then
				release()
			end
			if not registered then
				local consumer = Graph.evaluationContext()
				if consumer ~= nil then
					runScopes[consumer] = record
					registered = true
				end
			end
			record.base = activationDepth()
			body(use)
		end
		local function released()
			release()
			if afterDispose ~= nil then
				afterDispose()
			end
		end
		return scoped, released
	end

	local function ownedWatch(body: (use: Types.Use) -> (), label: string?, afterDispose: Dispose?): Dispose
		if Inspect.isActive() then
			Inspect.watch(owner)
		end
		local scoped, released = scopedRuns(body, afterDispose)
		local boundary = owner.boundary
		if boundary == nil then
			return startWatch(watchModule.watch, scoped, label, released)
		end
		return startWatch(watchModule.watchGuarded, function(use: Types.Use)
			local ok, err: unknown = pcall(scoped, use)
			if not ok then
				boundary.report(err)
			end
		end, label, released)
	end

	owner = {
		own = own,
		watch = ownedWatch,
		watchStatic = ownedWatchStatic,
		watchTerminal = ownedWatchTerminal,
		reactor = reactor,
		createChild = createChild,
		dispose = disposeOwner,
		isDisposed = function(): boolean
			return disposed
		end,
		size = function(): number
			return count
		end,
		checkpoint = checkpoint,
		rollbackTo = rollbackTo,
		boundary = nil :: Boundary?,
		guardWith = function(boundary: Boundary): ()
			owner.boundary = boundary
		end,
		__attachTo = function(detach: Dispose): ()
			detachFromParent = detach
		end,
	}

	return owner
end

return {
	createOwner = createOwner,
	installActivationDepth = installActivationDepth,
	runScopeOf = runScopeOf,
}
