--!strict

local Active = require "./ownership/active"
local Diagnostics = require "./diagnostics"

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

local KNOWN_FIELDS: { [string]: true } = {
	create = true,
	destroy = true,
	reset = true,
	maxRetained = true,
}

local function createPool<T>(options: Options<T>): Pool<T>
	if type(options) ~= "table" or type(options.create) ~= "function" or type(options.destroy) ~= "function" then
		Diagnostics.raise("pool/invalid-options", "createPool needs create and destroy functions", {
			expected = "{ create = function, destroy = function, maxRetained = finite number, reset? = function }",
		})
	end
	for field in options :: any do
		if KNOWN_FIELDS[field] == nil then
			Diagnostics.raise("pool/unknown-option", "createPool was given an option it does not have", {
				option = tostring(field),
				expected = "create, destroy, maxRetained, reset",
			})
		end
	end
	if options.reset ~= nil and type(options.reset) ~= "function" then
		Diagnostics.raise("pool/invalid-reset", "createPool.reset must be a function", {
			actual = Diagnostics.describe(options.reset),
		})
	end
	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("pool/no-active-owner", "createPool ran outside an owner", {
			contract = "a pool cannot outlive the owner responsible for its resources",
			fix = "create it inside a component or Compose.withOwner(owner, ...)",
		})
	end
	if
		type(options.maxRetained) ~= "number"
		or options.maxRetained ~= options.maxRetained
		or options.maxRetained < 0
		or math.abs(options.maxRetained) == math.huge
	then
		Diagnostics.raise("pool/invalid-limit", "createPool.maxRetained must be a finite non-negative number", {
			actual = Diagnostics.describe(options.maxRetained),
			contract = "a pool always has an explicit retained-memory bound",
		})
	end
	local maximum = math.floor(options.maxRetained)
	local idle: { T } = {}
	local active: { [Lease<T>]: T } = {}
	local disposed = false

	local function destroyAll()
		disposed = true
		local errors: { string } = {}
		for _, value in idle do
			local ok, err = pcall(function(): unknown?
				options.destroy(value)
				return nil
			end)
			if not ok then
				errors[#errors + 1] = tostring(err)
			end
		end
		for _, value in active do
			local ok, err = pcall(function(): unknown?
				options.destroy(value)
				return nil
			end)
			if not ok then
				errors[#errors + 1] = tostring(err)
			end
		end
		table.clear(idle)
		table.clear(active)
		if #errors > 0 then
			error(("Compose: %d pool resource destroy failures: %s"):format(#errors, table.concat(errors, "; ")), 0)
		end
	end
	(owner :: any).own(destroyAll)

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
				local ok, err = pcall(function(): unknown?
					(options.reset :: (T) -> ())(value)
					return nil
				end)
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
