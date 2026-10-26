--!strict

local Active = require "../ownership/active"
local Diagnostics = require "../diagnostics"
local Owner = require "../ownership/owner"

export type Factory<T> = () -> (T, (() -> ())?)

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

	local references = 0
	local value: T? = nil

	local lifetime: Owner.Owner? = nil
	local built = false

	local function release()
		references -= 1
		if references > 0 then
			return
		end

		local scope = lifetime
		built = false
		lifetime = nil
		value = nil

		if scope ~= nil then
			Owner.dispose(scope)
		end
	end

	local function take(): (T, () -> ())
		if not built then
			local scope = Owner.createOwner()
			local ok, result, dispose = pcall(Active.withOwner, scope, factory)
			if not ok then
				Owner.dispose(scope)
				error(result, 0)
			end
			if dispose ~= nil then
				Owner.own(scope, dispose)
			end
			value = result
			lifetime = scope
			built = true
		end

		references += 1

		local released = false
		return value :: T, function()
			if released then
				return
			end
			released = true
			release()
		end
	end

	local function acquireOwned(): T
		local owner = Active.current()
		if owner == nil then
			error(
				Diagnostics.format(
					"async/shared-no-owner",
					"a shared resource was acquired with no owner to release it",
					{
						contract = "a reference is released when the owner that took it is disposed",
						fix = "acquire it inside a component, inside Compose.withOwner(owner, ...), or use its `detached` form and release it yourself",
					}
				),
				0
			)
		end
		local result, release_ = take()
		Owner.own(owner, release_)
		return result
	end

	local acquire = setmetatable({
		detached = function(): (T, () -> ())
			return take()
		end,
	}, {
		__call = function(_: unknown): T
			return acquireOwned()
		end,
	})

	return acquire
end

export type Acquire<T> = typeof(createSharedResource(function(): (T, (() -> ())?)
	error("unreachable", 0)
end))

return createSharedResource
