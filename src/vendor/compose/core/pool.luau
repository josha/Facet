--!strict

local Diagnostics = require "./diagnostics"
local cacheOptions = require "./ownership/cache-options"

export type Lease<T> = {
	value: T,
	release: () -> (),
}

export type Pool<T> = {
	acquire: () -> Lease<T>,
	idle: () -> number,
	active: () -> number,
}

export type Options<T> = {
	create: () -> T,
	destroy: (value: T) -> (),
	reset: ((value: T) -> ())?,
	maxRetained: number,
}

local function createPool<T>(options: Options<T>): Pool<T>
	local owner, maximum = cacheOptions.validate(options, "pool")
	local idle: { T } = {}
	local active: { [Lease<T>]: T } = {}
	local disposed = false

	local function destroyAll()
		disposed = true
		cacheOptions.destroyAll("pool", options.destroy, function(destroy)
			for _, value in idle do
				destroy(value)
			end
			for _, value in active do
				destroy(value)
			end
			table.clear(idle)
			table.clear(active)
		end)
	end
	owner.own(destroyAll)

	local function acquire(): Lease<T>
		if disposed then
			Diagnostics.raise("pool/disposed", "a disposed pool cannot acquire resources", {
				contract = "the pool shares its owner's lifetime",
			})
		end
		local value: T
		if #idle > 0 then
			value = table.remove(idle) :: T
		else
			value = options.create()
		end
		local lease: Lease<T>
		local released = false
		local function release()
			if released then
				return
			end
			released = true
			active[lease] = nil
			if disposed then
				return
			end
			if options.reset ~= nil then
				local ok, err: unknown = pcall(options.reset :: (T) -> (), value)
				if not ok then
					options.destroy(value)
					error(err, 0)
				end
			end
			if #idle < maximum then
				idle[#idle + 1] = value
			else
				options.destroy(value)
			end
		end
		lease = { value = value, release = release }
		active[lease] = value
		return lease
	end

	return {
		acquire = acquire,
		idle = function()
			return #idle
		end,
		active = function()
			local count = 0
			for _ in active do
				count += 1
			end
			return count
		end,
	}
end

return createPool
