--!strict

local Types = require "./types"

local arity: { [string]: number } = { UDim2 = 4, UDim = 2, Vector2 = 2, Vector3 = 3, Rect = 4, NumberRange = 2 }

local function reference(component: Types.Literal, kind: string): string?
	if type(component) ~= "table" then
		return nil
	end
	local name = component[kind]
	if type(name) ~= "string" then
		return nil
	end
	for key in component do
		if key ~= kind then
			return nil
		end
	end
	return name
end

local function token(component: Types.Literal): string?
	return reference(component, "token")
end

local function input(component: Types.Literal): string?
	return reference(component, "input")
end

local function literal(components: { Types.DatatypeComponent }): Types.Literal
	local result: { [string | number]: Types.Literal } = {}
	for index, component in components do
		if type(component) == "number" then
			result[index] = component
		else
			local reference: { [string | number]: Types.Literal } = {}
			for key, value in component do
				reference[key] = value
			end
			result[index] = reference
		end
	end
	return result
end

return { arity = arity, token = token, input = input, literal = literal }
