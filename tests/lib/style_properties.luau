--!strict
local Theme = require("../../src/ui/theme_types")

return function(rule: StyleRule): Theme.RuleProperties
	local properties = rule:GetProperties() :: Theme.RuleProperties
	for property, value in properties do
		if type(value) == "string" and string.sub(value, 1, 12) == "$FacetColor_" then
			local sheet = rule.Parent
			properties[property] = if sheet then sheet:GetAttribute(string.sub(value, 2)) :: Theme.StyleValue? else nil
		end
	end
	return properties
end
