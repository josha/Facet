--!strict

local Active = require "../ownership/active"
local Diagnostics = require "../diagnostics"
local Owner = require "../ownership/owner"

export type Factory<T> = () -> (T, (() -> ())?)

type State = {
	factory: Factory<unknown>,
	references: number,
	value: unknown,
	lifetime: Owner.Owner?,
}

local function release(state: State)
	state.references -= 1
	if state.references > 0 then
		return
	end
	local scope = state.lifetime
	state.lifetime = nil
	state.value = nil
	if scope ~= nil then
		Owner.dispose(scope)
	end
end

local function releaseHeld(subject: unknown)
	release(subject :: State)
end

local function take(state: State): unknown
	if state.lifetime == nil then
		local scope = Owner.createOwner()
		local ok, result, dispose = pcall(Active.withOwner, scope, state.factory)
		if not ok then
			Owner.dispose(scope)
			error(result, 0)
		end
		if dispose ~= nil then
			Owner.own(scope, dispose)
		end
		state.value = result
		state.lifetime = scope
	end
	state.references += 1
	return state.value
end

local function acquireOwned(state: State): unknown
	local owner = Active.current()
	if owner == nil then
		error(
			Diagnostics.format("async/shared-no-owner", "a shared resource was acquired with no owner to release it", {
				contract = "a reference is released when the owner that took it is disposed",
				fix = "acquire it inside a component, inside Compose.withOwner(owner, ...), or use its `detached` form and release it yourself",
			}),
			0
		)
	end
	local result = take(state)
	Owner.holdSubject(owner, releaseHeld, state)
	return result
end

local Acquire = {
	__call = function(self: unknown): unknown
		return acquireOwned((self :: { state: State }).state)
	end,
}

local function createSharedResource<T>(factory: Factory<T>)
	if type(factory) ~= "function" then
		error(
			Diagnostics.format("async/shared-needs-a-factory", "createSharedResource expects a factory function", {
				actual = Diagnostics.describe(factory),
				expected = "function() return value, teardown end",
			}),
			0
		)
	end
	local state: State = {
		factory = (factory :: unknown) :: Factory<unknown>,
		references = 0,
		value = nil,
		lifetime = nil,
	}
	local acquire = setmetatable({
		state = state,
		detached = function(): (T, () -> ())
			local value = take(state) :: T
			local released = false
			return value,
				function()
					if released then
						return
					end
					released = true
					release(state)
				end
		end,
	}, (Acquire :: unknown) :: { __call: (unknown) -> T })
	return acquire
end

export type Acquire<T> = typeof(createSharedResource(function(): (T, (() -> ())?)
	error("unreachable", 0)
end))

return createSharedResource
