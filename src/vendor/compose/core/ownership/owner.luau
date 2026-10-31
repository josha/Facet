--!strict
--!native

local Types = require "../reactive/types"
local Inspect = require "./inspect"
local Reactor = require "../reactive/reactor"
local watchModule = require "../reactive/watch"
local Graph = require "../reactive/graph"

local inspecting = Inspect.flag

type Dispose = Types.Dispose

export type Boundary = {
	report: (failure: unknown) -> (),
}

export type Owner = {
	parent: Owner?,
	reactor: Reactor.Reactor?,
	boundary: Boundary?,
	head: Owner?,
	disposed: boolean?,
	previous: Owner?,
	following: Owner?,
	release: Dispose?,
	after: Dispose?,
	batchRelease: ((subject: unknown) -> ())?,
	[number]: unknown,
}

export type Entry = Owner

local currentOwner: () -> Owner? = function(): Owner?
	return nil
end

local function new(inherited: Reactor.Reactor?, parent: Owner?): Owner
	return {
		parent = parent or currentOwner(),
		reactor = inherited or Reactor.create(),
	}
end

local detached: Reactor.Reactor? = nil
local releaseHeld = watchModule.releaseHeld

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

local function reactorOf(owner: Owner): Reactor.Reactor
	local current: Owner? = owner
	while current ~= nil do
		local reactor = current.reactor
		if reactor ~= nil then
			return reactor
		end
		current = current.parent
	end
	local fallback = detached or Reactor.create()
	detached = fallback
	return fallback
end

local function isOwner(candidate: unknown): boolean
	if type(candidate) ~= "table" then
		return false
	end
	local owner = candidate :: Owner
	return owner.release == nil
		and owner[1] == nil
		and (owner.reactor ~= nil or owner.parent ~= nil or owner.disposed ~= nil)
end

local function heldSize(entry: Entry): number
	return if entry.batchRelease ~= nil then #entry else #entry // 2
end

local cursor = 0

local function releaseSingles(batch: Entry, release: (subject: unknown) -> (), keep: number)
	local index = cursor
	while index > keep do
		local subject = batch[index]
		batch[index] = nil
		index -= 1
		cursor = index
		release(subject)
	end
end

local function releasePairs(batch: Entry, keep: number)
	local index = cursor
	local floor = keep * 2 + 1
	while index >= floor do
		local releaseSubject, subject = batch[index], batch[index + 1]
		batch[index] = nil
		batch[index + 1] = nil
		index -= 2
		cursor = index
		if type(releaseSubject) == "function" then
			((releaseSubject :: unknown) :: (subject: unknown) -> ())(subject)
		end
	end
end

local function releaseBatch(batch: Entry, keep: number, failures: { unknown })
	local outer = cursor
	local release = batch.batchRelease
	if release ~= nil then
		cursor = #batch
		while true do
			local ok, failure: unknown = pcall(releaseSingles, batch, release, keep)
			if ok then
				break
			end
			table.insert(failures, failure)
		end
		cursor = outer
		if keep == 0 then
			batch.batchRelease = nil
		end
		return
	end
	cursor = #batch - 1
	while true do
		local ok, failure: unknown = pcall(releasePairs, batch, keep)
		if ok then
			break
		end
		table.insert(failures, failure)
	end
	cursor = outer
end

local function releaseEntry(entry: Entry, failures: { unknown })
	local release = entry.release
	if release == nil then
		if entry[1] ~= nil then
			releaseBatch(entry, 0, failures)
			return
		end
		disposeOwner(entry)
		return
	end
	entry.release = nil
	local after = entry.after
	if after == nil then
		release()
		return
	end
	entry.after = nil
	local ok, failure: unknown = pcall(release)
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
end

local function attach(owner: Owner, entry: Entry)
	local first = owner.head
	entry.following = first
	if first ~= nil then
		first.previous = entry
	end
	owner.head = entry
end

local function link(owner: Owner, release: Dispose, after: Dispose?): Entry
	local entry: Entry = { release = release, previous = nil, following = nil }
	if after ~= nil then
		entry.after = after
	end
	attach(owner, entry)
	return entry
end

export type RunScope = { child: Owner?, base: number?, inherited: Owner? }

local activationDepth: () -> number = function(): number
	return 0
end

local function installActivationDepth(depth: () -> number)
	activationDepth = depth
end

local function installCurrentOwner(current: () -> Owner?)
	currentOwner = current
end

local function runScopeOf(consumer: Types.Node): RunScope?
	if consumer.inherited ~= nil then
		return (consumer :: unknown) :: RunScope
	end
	return nil
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
			if target ~= nil then
				target()
			end
			return
		end
		local failures: { unknown } = {}
		releaseEntry(entry, failures)
		raiseAll(failures)
	end
end

local function holdSubject(owner: Owner, releaseSubject: (subject: unknown) -> (), subject: unknown)
	if owner.disposed then
		releaseSubject(subject)
		return
	end
	local head = owner.head
	if head == nil or head[1] == nil then
		attach(owner, { subject, batchRelease = releaseSubject })
		return
	end
	local release = head.batchRelease
	if release == releaseSubject then
		head[#head + 1] = subject
		return
	elseif release ~= nil then
		for index = #head, 1, -1 do
			head[index * 2] = head[index]
			head[index * 2 - 1] = release
		end
		head.batchRelease = nil
	end
	local size = #head
	head[size + 1] = releaseSubject
	head[size + 2] = subject
end

local function heldCount(owner: Owner): number
	local head = owner.head
	return if head == nil then 0 else heldSize(head)
end

local function rollbackHeld(owner: Owner, keep: number)
	local head = owner.head
	if head == nil then
		return
	end
	local held = heldSize(head)
	if held <= keep then
		return
	end
	local failures: { unknown } = {}
	releaseBatch(head, keep, failures)
	raiseAll(failures)
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

local function takeOwner(owner: Owner): Entry?
	owner.disposed = true
	local parent = owner.parent
	if parent ~= nil and not parent.disposed and (owner.previous ~= nil or parent.head == owner) then
		unlink(parent, owner)
	end
	owner.parent = nil

	local pending = owner.head
	owner.head = nil
	return pending
end

local function releaseTree(following: { Entry? }, marks: { number }, failures: { unknown })
	while #marks > 0 do
		local depth = #marks
		local entry = following[depth]
		if entry ~= nil then
			following[depth] = entry.following
			entry.previous = nil
			entry.following = nil
			if entry.release == nil and entry[1] == nil then
				if not entry.disposed then
					marks[depth + 1] = #failures
					following[depth + 1] = takeOwner(entry)
				end
			else
				releaseEntry(entry, failures)
			end
		else
			local mark = marks[depth]
			if depth > 1 and #failures - mark > 1 then
				local nested: { unknown } = {}
				for index = mark + 1, #failures do
					table.insert(nested, failures[index])
					failures[index] = nil
				end
				local ok, failure: unknown = pcall(raiseAll, nested)
				if not ok then
					table.insert(failures, failure)
				end
			end
			marks[depth] = nil
			following[depth] = nil
		end
	end
end

disposeOwner = function(owner: Owner)
	if owner.disposed then
		return
	end
	local pending = takeOwner(owner)
	if pending == nil then
		return
	end
	local failures: { unknown } = {}
	if pending.following == nil and pending[1] ~= nil then
		releaseBatch(pending, 0, failures)
	else
		local following: { Entry? } = { pending }
		local marks: { number } = { 0 }
		repeat
			local ok, failure: unknown = pcall(releaseTree, following, marks, failures)
			if not ok then
				table.insert(failures, failure)
			end
		until #marks == 0
	end
	raiseAll(failures)
end

local function isDisposed(owner: Owner): boolean
	return owner.disposed == true
end

local function size(owner: Owner): number
	local total = 0
	local entry = owner.head
	while entry ~= nil do
		local held = heldSize(entry)
		total += if held > 0 then held else 1
		entry = entry.following
	end
	return total
end

local function guardWith(owner: Owner, boundary: Boundary)
	owner.boundary = boundary
end

local function createChild(owner: Owner): Owner
	local child: Owner = { parent = owner }
	if owner.disposed then
		disposeOwner(child)
	else
		attach(owner, child)
	end
	if inspecting.active then
		Inspect.child(owner, child)
	end
	local boundary = owner.boundary
	if boundary ~= nil then
		child.boundary = boundary
	end
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
		return own(owner, factory(reactorOf(owner), first, second))
	end
	local ok, dispose = pcall(factory, reactorOf(owner), first, second)
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
	if inspecting.active then
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

local function listenHeld<T>(owner: Owner, producer: Types.ReadOnlyValue<T>, body: (value: T) -> ()): Types.Node
	if inspecting.active then
		Inspect.watch(owner)
	end
	local edge = Graph.listenEdge(
		reactorOf(owner),
		(producer :: unknown) :: Types.Node,
		(body :: unknown) :: (value: unknown) -> ()
	)
	holdSubject(owner, releaseHeld, edge)
	return edge
end

local function effectHeld(owner: Owner, body: (use: Types.Use) -> ()): Types.Node
	if inspecting.active then
		Inspect.watch(owner)
	end
	local node = watchModule.terminalNode(reactorOf(owner), body)
	holdSubject(owner, releaseHeld, node)
	return node
end

local function watchTerminal(owner: Owner, body: (use: Types.Use) -> (), after: Dispose?): Dispose
	if inspecting.active then
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

local function releaseScope(node: Types.Node)
	local child = node.child
	if child ~= nil then
		node.child = nil
		disposeOwner(child :: Owner)
	end
end

watchModule.installScope(function(node: Types.Node)
	releaseScope(node)
	node.base = activationDepth()
end, releaseScope)

local function watch(owner: Owner, body: (use: Types.Use) -> (), label: string?, after: Dispose?): Dispose
	if inspecting.active then
		Inspect.watch(owner)
	end
	local boundary = owner.boundary
	local run = if boundary == nil
		then body
		else function(use: Types.Use)
			local ok, err: unknown = pcall(body, use)
			if not ok then
				boundary.report(err)
			end
		end
	if after == nil then
		return own(owner, watchModule.watchScoped(reactorOf(owner), run, label, owner, boundary ~= nil))
	end
	local ok, dispose = pcall(watchModule.watchScoped, reactorOf(owner), run, label, owner, boundary ~= nil)
	if not ok then
		after()
		error(dispose, 0)
	end
	return own(owner, dispose, after)
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
	local created = createChild(assert(record.inherited))
	record.child = created
	return created
end

return {
	createOwner = createOwner,
	reactorOf = reactorOf,
	isOwner = isOwner,
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
	holdSubject = holdSubject,
	listenHeld = listenHeld,
	effectHeld = effectHeld,
	heldCount = heldCount,
	rollbackHeld = rollbackHeld,
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
