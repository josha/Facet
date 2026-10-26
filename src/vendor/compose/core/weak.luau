--!strict

local WEAK_KEYS = table.freeze { __mode = "k" }
local WEAK_VALUES = table.freeze { __mode = "v" }

local function keys<K, V>(made: { [K]: V })
	setmetatable(made, WEAK_KEYS)
end

local function values<K, V>(made: { [K]: V })
	setmetatable(made, WEAK_VALUES)
end

return {
	keys = keys,
	values = values,
}
