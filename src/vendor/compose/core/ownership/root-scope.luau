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

local function unwind(owner: Owner.Owner, failure: any): never
	local ok, disposeError: any = pcall(owner.dispose)
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

local function withRootOwnerImpl(body: any, reactor: Reactor.Reactor?): ...any
	requireBody(body, "withRootOwner")
	local owner = Owner.createOwner(reactor)
	local results = table.pack(pcall(Active.withOwner, owner, function(): ...any
		return body(owner)
	end))
	if not results[1] then
		unwind(owner, results[2])
	end
	owner.dispose()
	return table.unpack(results, 2, results.n)
end

local withRootOwner = (withRootOwnerImpl :: any) :: <T...>(
	body: (owner: Owner.Owner) -> T...,
	reactor: Reactor.Reactor?
) -> T...

local function createRootOwner(body: (owner: Owner.Owner) -> (), reactor: Reactor.Reactor?): RootScope
	requireBody(body, "createRootOwner")
	local owner = Owner.createOwner(reactor)
	local ok, err: any = pcall(Active.withOwner, owner, function()
		body(owner)
	end)
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
