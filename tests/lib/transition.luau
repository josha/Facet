--!strict
return function(rule: any, property: string): any
	local value = rule:GetPropertyTransitions()[property]
	if type(value) ~= "string" then
		return value
	end
	local name = string.sub(value, 2)
	local at = rule.Parent
	while at do
		local found = at:GetAttribute(name)
		if found ~= nil then
			return found
		end
		at = at.Parent
	end
	return nil
end
