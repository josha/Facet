--!strict

local Types = require "./types"

local arity: { [string]: number } = { UDim2 = 4, UDim = 2, Vector2 = 2, Vector3 = 3, Rect = 4, NumberRange = 2 }

local function token(component: Types.Literal): string?
	if type(component) ~= "table" then
		return nil
	end
	local name = component.token
	if type(name) ~= "string" then
		return nil
	end
	for key in component do
		if key ~= "token" then
			return nil
		end
	end
	return name
end

local function literal(components: { Types.DatatypeComponent }): Types.Literal
	local result: { [string | number]: Types.Literal } = {}
	for index, component in components do
		if type(component) == "number" then
			result[index] = component
		else
			local reference: { [string | number]: Types.Literal } = { token = component.token }
			result[index] = reference
		end
	end
	return result
end

return { arity = arity, token = token, literal = literal }
