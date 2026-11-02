--!strict
local ComposeTypes = require("../vendor/compose/core")

local function peek<T>(source: ComposeTypes.ReadOnlyValue<T>): T
	return source:peek()
end

return function(isValue: typeof(ComposeTypes.isValue))
	return function<T>(value: T | ComposeTypes.Source<T>, use: ComposeTypes.Use?): T
		local kind = type(value)
		if kind == "table" and isValue(value) then
			local source = value :: ComposeTypes.ReadOnlyValue<T>
			return if use then use(source) else source:peek()
		elseif kind == "function" then
			local body = value :: ComposeTypes.Body<T>
			return body(use or peek)
		end
		return value :: T
	end
end
