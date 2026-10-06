--!strict

local WEAK_KEYS = table.freeze { __mode = "k" }
local WEAK_VALUES = table.freeze { __mode = "v" }

local function keys<K, V>(): { [K]: V }
	return (setmetatable({} :: { [K]: V }, WEAK_KEYS) :: unknown) :: { [K]: V }
end

local function values<K, V>(): { [K]: V }
	return (setmetatable({} :: { [K]: V }, WEAK_VALUES) :: unknown) :: { [K]: V }
end

return {
	keys = keys,
	values = values,
}
