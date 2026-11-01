--!strict

local Active = require "../ownership/active"
local Diagnostics = require "../diagnostics"
local Owner = require "../ownership/owner"
local CoreTypes = require "../types"

export type Factory<T> = () -> (T, (() -> ())?)

export type Acquire<T> = CoreTypes.AcquireSharedResource<T>

type State<T> = {
	factory: Factory<T>,
	references: number,
	value: { value: T }?,
	lifetime: Owner.Owner?,
}

local function release<T>(state: State<T>)
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

local function take<T>(state: State<T>): T
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
		state.value = { value = result }
		state.lifetime = scope
	end
	state.references += 1
	return assert(state.value).value
end

local function acquireOwned<T>(state: State<T>, releaseHeld: (unknown) -> ()): T
	local owner = Active.current()
	if owner == nil then
		return Diagnostics.raise(
			"async/shared-no-owner",
			"a shared resource was acquired with no owner to release it",
			{
				contract = "a reference is released when the owner that took it is disposed",
				fix = "acquire it inside a component, inside Compose.withOwner(owner, ...), or use its `detached` form and release it yourself",
			}
		)
	end
	local result = take(state)
	Owner.holdSubject(owner, releaseHeld, state)
	return result
end

local function createSharedResource<T>(factory: Factory<T>): Acquire<T>
	if type(factory) ~= "function" then
		return Diagnostics.raise("async/shared-needs-a-factory", "createSharedResource expects a factory function", {
			actual = Diagnostics.describe(factory),
			expected = "function() return value, teardown end",
		})
	end
	local state: State<T> = {
		factory = factory,
		references = 0,
		value = nil,
		lifetime = nil,
	}
	local function releaseHeld(_subject: unknown)
		release(state)
	end
	local acquire = setmetatable({
		state = state,
		detached = function(): (T, () -> ())
			local value = take(state)
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
	}, {
		__call = function(_self: unknown): T
			return acquireOwned(state, releaseHeld)
		end,
	})
	return acquire
end

return createSharedResource
