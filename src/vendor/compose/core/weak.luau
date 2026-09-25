--!strict

local WEAK_KEYS = table.freeze { __mode = "k" }
local WEAK_VALUES = table.freeze { __mode = "v" }

local function keys<K, V>(): { [K]: V }
	return setmetatable({}, WEAK_KEYS) :: any
end

local function values<K, V>(): { [K]: V }
	return setmetatable({}, WEAK_VALUES) :: any
end

return {
	keys = keys,
	values = values,
}
