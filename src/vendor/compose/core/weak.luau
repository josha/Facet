--!strict

local WEAK_KEYS = table.freeze { __mode = "k" }
local WEAK_VALUES = table.freeze { __mode = "v" }
local WEAK_ENTRIES = table.freeze { __mode = "kv" }

local function keys(made: {})
	setmetatable(made, WEAK_KEYS)
end

local function values(made: {})
	setmetatable(made, WEAK_VALUES)
end

local function entries(made: {})
	setmetatable(made, WEAK_ENTRIES)
end

return {
	keys = keys,
	values = values,
	entries = entries,
}
