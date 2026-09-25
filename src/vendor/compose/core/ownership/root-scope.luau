--!strict

local Active = require "./active"
local Diagnostics = require "../diagnostics"
local Owner = require "./owner"
local Reactor = require "../reactive/reactor"
local Types = require "../reactive/types"

type Dispose = Types.Dispose

export type RootScope = {
	owner: Owner.Owner,

	dispose: Dispose,
}

local function requireBody(body: unknown, operation: string)
	if type(body) ~= "function" then
		Diagnostics.raise(
			"owner/root-body-not-a-function",
			("%s expects a function to run in the root scope"):format(operation),
			{
				actual = Diagnostics.describe(body),
				expected = "a function taking the root owner",
				contract = "a root scope exists to give one body an owner; there is nothing else to run",
			}
		)
	end
end

local function unwind(owner: Owner.Owner, failure: unknown): never
	local ok, disposeError: unknown = pcall(owner.dispose)
	if ok then
		return error(failure, 0) :: never
	end
	return error(
		("%s\nCompose: the root scope also raised while unwinding it:\n%s"):format(
			tostring(failure),
			tostring(disposeError)
		),
		0
	) :: never
end

local function settle<T...>(owner: Owner.Owner, ok: boolean, ...: T...): T...
	if not ok then
		unwind(owner, (select(1, ...)))
	end
	owner.dispose()
	return ...
end

local function withRootOwner<T...>(body: (owner: Owner.Owner) -> T..., reactor: Reactor.Reactor?): T...
	requireBody(body, "withRootOwner")
	local owner = Owner.createOwner(reactor)
	return settle(
		owner,
		pcall(Active.withOwner, owner, function(): T...
			return body(owner)
		end)
	)
end

local function createRootOwner(body: (owner: Owner.Owner) -> (), reactor: Reactor.Reactor?): RootScope
	requireBody(body, "createRootOwner")
	local owner = Owner.createOwner(reactor)
	local ok, err: unknown = pcall(Active.runWith, owner, body, owner)
	if not ok then
		unwind(owner, err)
	end
	return {
		owner = owner,
		dispose = owner.dispose,
	}
end

return {
	withRootOwner = withRootOwner,
	createRootOwner = createRootOwner,
}
