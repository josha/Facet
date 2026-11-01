--!strict
local Compose = require("../vendor/compose/core")

local function peek<T>(source: Compose.ReadOnlyValue<T>): T
	return source:peek()
end

return function<T>(source: Compose.Source<T>, use: Compose.Use?): T
	if type(source) == "function" then
		return source(use or peek)
	end
	return if use then use(source) else source:peek()
end
