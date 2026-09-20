--!strict

local Types = require "../reactive/types"
local Inspect = require "./inspect"
local Reactor = require "../reactive/reactor"
local watchModule = require "../reactive/watch"

type Dispose = Types.Dispose
type Scope = Types.Use

export type Boundary = {
	report: (failure: unknown) -> (),
}

export type Owner = {
	own: (dispose: Dispose) -> Dispose,
	watch: (body: (use: Types.Use) -> (), label: string?, afterDispose: Dispose?) -> Dispose,
	watchStatic: (producer: any, body: (value: any) -> (), afterDispose: Dispose?) -> Dispose,
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

local function raiseAll(errors: { string })
	if #errors == 0 then
		return
	end
	if #errors == 1 then
		error(errors[1], 0)
	end
	local parts = { ("Compose: %d errors while disposing an owner:"):format(#errors) }
	for index, message in errors do
		table.insert(parts, ("  [%d] %s"):format(index, message))
	end
	error(table.concat(parts, "\n"), 0)
end

local function releaseEntry(entry: Entry)
	entry[DISPOSE]()
	local afterDispose = entry[AFTER_DISPOSE]
	if afterDispose ~= nil then
		entry[AFTER_DISPOSE] = nil
		afterDispose()
	end
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
			releaseEntry(entry)
		end
	end

	local function checkpoint(): unknown
		return head
	end

	local function rollbackTo(token: unknown)
		local boundaryEntry = token :: Entry?
		local errors: { string } = {}
		local pending = head

		local function releaseRest()
			while pending ~= nil and pending ~= boundaryEntry do
				local entry = pending
				pending = entry[NEXT]
				unlink(entry)
				releaseEntry(entry)
			end
		end

		while pending ~= nil and pending ~= boundaryEntry do
			local ok, err: any = pcall(releaseRest)
			if not ok then
				table.insert(errors, tostring(err))
			end
		end
		raiseAll(errors)
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

		local errors: { string } = {}
		local function releaseRest()
			while pending ~= nil do
				local entry = pending
				pending = entry[NEXT]
				entry[PREVIOUS] = nil
				entry[NEXT] = nil
				entry[ATTACHED] = false
				releaseEntry(entry)
			end
		end

		repeat
			local ok, err: any = pcall(releaseRest)
			if not ok then
				table.insert(errors, tostring(err))
			end
		until pending == nil
		raiseAll(errors)
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

	local function startWatch(factory: any, first: any, second: any, afterDispose: Dispose?): Dispose
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

	local function ownedWatchStatic(producer: any, body: (value: any) -> (), afterDispose: Dispose?): Dispose
		if Inspect.isActive() then
			Inspect.watch(owner)
		end
		local boundary = owner.boundary
		if boundary == nil then
			return startWatch(watchModule.watchStatic, producer, body, afterDispose)
		end
		return startWatch(watchModule.watchStatic, producer, function(value: any)
			local ok, err: any = pcall(body, value)
			if not ok then
				boundary.report(err)
			end
		end, afterDispose)
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
			local ok, err: any = pcall(body, use)
			if not ok then
				boundary.report(err)
			end
		end, nil, afterDispose)
	end

	local function ownedWatch(body: (use: Types.Use) -> (), label: string?, afterDispose: Dispose?): Dispose
		if Inspect.isActive() then
			Inspect.watch(owner)
		end
		local boundary = owner.boundary
		if boundary == nil then
			return startWatch(watchModule.watch, body, label, afterDispose)
		end
		return startWatch(watchModule.watch, function(use: Types.Use)
			local ok, err: any = pcall(body, use)
			if not ok then
				boundary.report(err)
			end
		end, label, afterDispose)
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
		boundary = nil,
		guardWith = function(boundary: Boundary)
			owner.boundary = boundary
		end,
		__attachTo = function(detach: Dispose)
			detachFromParent = detach
		end,
	}

	return owner
end

return {
	createOwner = createOwner,
}
