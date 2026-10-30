--!strict

local ResourceTypes = require "./resource-types"
local Owners = require "./ownership/owner"
local Diagnostics = require "./diagnostics"
local cacheOptions = require "./ownership/cache-options"

export type Cache<K, T> = ResourceTypes.KeyedCache<K, T>

export type Options<K, T> = ResourceTypes.KeyedCacheOptions<K, T>

local function createKeyedCache<K, T>(options: Options<K, T>): Cache<K, T>
	local owner, maximum = cacheOptions.validate(options, "keyed-cache")
	local values: { [K]: T } = {}

	local order: { K } = {}
	local disposed = false

	local function unlink(key: K)
		local at = table.find(order, key)
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
		cacheOptions.destroyAll("keyed-cache", options.destroy, function(destroy)
			for _, key in table.clone(order) do
				local value = values[key]
				if value ~= nil then
					destroy(value)
				end
			end
			table.clear(values)
			table.clear(order)
		end)
	end
	Owners.own(owner, destroyAll)

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
