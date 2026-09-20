--!strict

local Active = require "../ownership/active"
local Diagnostics = require "../diagnostics"
local Owner = require "../ownership/owner"

export type Factory<T> = () -> (T, (() -> ())?)

export type Acquire<T> = (() -> T) & { detached: () -> (T, () -> ()) }

local function createSharedResource<T>(factory: Factory<T>): Acquire<T>
	if type(factory) ~= "function" then
		Diagnostics.raise("async/shared-needs-a-factory", "createSharedResource expects a factory function", {
			actual = Diagnostics.describe(factory),
			expected = "function() return value, teardown end",
		})
	end

	local references = 0
	local value: T

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
		value = nil :: any

		if scope ~= nil then
			scope.dispose()
		end
	end

	local function take(): (T, () -> ())
		if not built then
			local scope = Owner.createOwner()
			local ok, result, dispose = pcall(Active.withOwner, scope, factory)
			if not ok then
				scope.dispose()
				error(result, 0)
			end
			if dispose ~= nil then
				scope.own(dispose)
			end
			value = result :: T
			lifetime = scope
			built = true
		end

		references += 1

		local released = false
		return value, function()
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
			Diagnostics.raise("async/shared-no-owner", "a shared resource was acquired with no owner to release it", {
				contract = "a reference is released when the owner that took it is disposed",
				fix = "acquire it inside a component, inside Compose.withOwner(owner, ...), or use its `detached` form and release it yourself",
			})
		end
		local result, release_ = take();
		(owner :: any).own(release_)
		return result
	end

	local acquire = setmetatable({
		detached = function(): (T, () -> ())
			return take()
		end,
	}, {
		__call = function(): T
			return acquireOwned()
		end,
	})

	return (acquire :: any) :: Acquire<T>
end

return createSharedResource
