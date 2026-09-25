--!strict

local Active = require "./ownership/active"
local Diagnostics = require "./diagnostics"
local Owner = require "./ownership/owner"

export type Cache<K, T> = {
	get: (key: K) -> T,
	peek: (key: K) -> T?,
	evict: (key: K) -> (),
	size: () -> number,

	keys: () -> { K },
}

export type Options<K, T> = {
	build: (key: K) -> T,
	destroy: (value: T) -> (),
	maxRetained: number,

	touch: ((key: K, value: T) -> ())?,
}

local KNOWN_FIELDS: { [string]: true } = {
	build = true,
	destroy = true,
	maxRetained = true,
	touch = true,
}

local function createKeyedCache<K, T>(options: Options<K, T>): Cache<K, T>
	if type(options) ~= "table" or type(options.build) ~= "function" or type(options.destroy) ~= "function" then
		Diagnostics.raise("keyed-cache/invalid-options", "createKeyedCache needs build and destroy functions", {
			expected = "{ build = function, destroy = function, maxRetained = finite number, touch? = function }",
		})
	end
	for field in (options :: unknown) :: { [string]: unknown } do
		if KNOWN_FIELDS[field] == nil then
			Diagnostics.raise("keyed-cache/unknown-option", "createKeyedCache was given an option it does not have", {
				option = tostring(field),
				expected = "build, destroy, maxRetained, touch",
			})
		end
	end
	if options.touch ~= nil and type(options.touch) ~= "function" then
		Diagnostics.raise("keyed-cache/invalid-touch", "createKeyedCache.touch must be a function", {
			actual = Diagnostics.describe(options.touch),
		})
	end
	local owner = Active.current()
	if owner == nil then
		Diagnostics.raise("keyed-cache/no-active-owner", "createKeyedCache ran outside an owner", {
			contract = "a cache cannot outlive the owner responsible for its resources",
			fix = "create it inside a component or Compose.withOwner(owner, ...)",
		})
	end
	if
		type(options.maxRetained) ~= "number"
		or options.maxRetained ~= options.maxRetained
		or options.maxRetained < 0
		or math.abs(options.maxRetained) == math.huge
	then
		Diagnostics.raise(
			"keyed-cache/invalid-limit",
			"createKeyedCache.maxRetained must be a finite non-negative number",
			{
				actual = Diagnostics.describe(options.maxRetained),
				contract = "a cache always has an explicit retained-entry bound",
			}
		)
	end
	local maximum = math.floor(options.maxRetained)

	local values: { [K]: T } = {}

	local order: { K } = {}
	local disposed = false

	local function indexOf(key: K): number?
		for index, candidate in order do
			if candidate == key then
				return index
			end
		end
		return nil
	end

	local function unlink(key: K)
		local at = indexOf(key)
		if at ~= nil then
			table.remove(order, at)
		end
	end

	local function destroyEntry(key: K)
		local value = values[key]
		values[key] = nil
		unlink(key)
		if value ~= nil then
			options.destroy(value)
		end
	end

	local function destroyAll()
		disposed = true
		local errors: { string } = {}
		for _, key in table.clone(order) do
			local value = values[key]
			if value ~= nil then
				local ok, err = pcall(function(): unknown?
					options.destroy(value)
					return nil
				end)
				if not ok then
					errors[#errors + 1] = tostring(err)
				end
			end
		end
		table.clear(values)
		table.clear(order)
		if #errors > 0 then
			error(
				("Compose: %d keyed-cache resource destroy failures: %s"):format(#errors, table.concat(errors, "; ")),
				0
			)
		end
	end
	(owner :: Owner.Owner).own(destroyAll)

	local function get(key: K): T
		if disposed then
			Diagnostics.raise("keyed-cache/disposed", "a disposed cache cannot build or return entries", {
				contract = "the cache shares its owner's lifetime",
			})
		end

		local value = values[key]
		if value ~= nil then
			unlink(key)
			order[#order + 1] = key
			if options.touch ~= nil then
				options.touch(key, value)
			end
			return value
		end

		while #order > 0 and #order >= maximum do
			destroyEntry(order[1])
		end

		value = options.build(key)
		values[key] = value
		order[#order + 1] = key

		if options.touch ~= nil then
			options.touch(key, value)
		end
		return value
	end

	local function peek(key: K): T?
		return values[key]
	end

	local function evict(key: K)
		if disposed or values[key] == nil then
			return
		end
		destroyEntry(key)
	end

	local function size(): number
		return #order
	end

	local function keys(): { K }
		return table.clone(order)
	end

	return {
		get = get,
		peek = peek,
		evict = evict,
		size = size,
		keys = keys,
	}
end

return createKeyedCache
