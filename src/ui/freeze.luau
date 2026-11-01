--!strict
local freeze: <T>(T & {}) -> T = table.freeze
return freeze
