--!strict

local Values = require("./values")
local Wire = require("./wire")

export type Kind = "string" | "integer" | "number" | "boolean" | "object" | "array" | "value" | "json" | "node"

export type Spec = {
	kind: Kind,
	description: string?,
	enum: { string }?,
	pattern: string?,
	minimum: number?,
	maximum: number?,
	maxLength: number?,
	fields: { [string]: Spec }?,
	required: { string }?,
	items: Spec?,
	maxItems: number?,
	minItems: number?,
	values: Spec?,
}

local Contract = {}

function Contract.string(
	description: string?,
	extra: { enum: { string }?, pattern: string?, maxLength: number? }?
): Spec
	local spec: Spec = { kind = "string", description = description }
	if extra then
		spec.enum = extra.enum
		spec.pattern = extra.pattern
		spec.maxLength = extra.maxLength
	end
	return spec
end

function Contract.integer(description: string?, minimum: number?, maximum: number?): Spec
	return { kind = "integer", description = description, minimum = minimum, maximum = maximum }
end

function Contract.boolean(description: string?): Spec
	return { kind = "boolean", description = description }
end

function Contract.value(description: string?): Spec
	return { kind = "value", description = description }
end

function Contract.json(description: string?): Spec
	return { kind = "json", description = description }
end

function Contract.node(description: string?): Spec
	return { kind = "node", description = description }
end

function Contract.array(items: Spec, description: string?, minItems: number?, maxItems: number?): Spec
	return { kind = "array", items = items, description = description, minItems = minItems, maxItems = maxItems }
end

function Contract.map(values: Spec, description: string?): Spec
	return { kind = "object", values = values, description = description }
end

function Contract.object(fields: { [string]: Spec }, required: { string }?, description: string?): Spec
	return { kind = "object", fields = fields, required = required or {}, description = description }
end

local NO_FIELDS: { [string]: Spec } = {}
local NO_NAMES: { string } = {}

local function fieldsOf(spec: Spec): { [string]: Spec }
	return spec.fields or NO_FIELDS
end

local function requiredOf(spec: Spec): { string }
	return spec.required or NO_NAMES
end

local function typeName(value: unknown): string
	if value == nil or value == Wire.null then
		return "null"
	elseif type(value) == "table" then
		return if Wire.isArray(value) and not Wire.isObject(value) then "array" else "object"
	end
	return type(value)
end

local nodeSpec: Spec

local function check(spec: Spec, value: unknown, path: string): string?
	local kind = spec.kind
	if kind == "json" then
		return nil
	elseif kind == "string" then
		if type(value) ~= "string" then
			return path .. " must be a string, not " .. typeName(value)
		end
		local text = value :: string
		local enum = spec.enum
		if enum and not table.find(enum, text) then
			return path .. " must be one of " .. table.concat(enum, ", ")
		end
		if spec.pattern and string.match(text, spec.pattern :: string) == nil then
			return path .. " has an invalid format: " .. text
		end
		if spec.maxLength and #text > (spec.maxLength :: number) then
			return path .. " must be at most " .. spec.maxLength .. " bytes"
		end
		return nil
	elseif kind == "integer" or kind == "number" then
		if type(value) ~= "number" or value ~= value then
			return path .. " must be a number, not " .. typeName(value)
		end
		local number = value :: number
		if kind == "integer" and number % 1 ~= 0 then
			return path .. " must be an integer"
		end
		if spec.minimum and number < (spec.minimum :: number) then
			return path .. " must be at least " .. spec.minimum
		end
		if spec.maximum and number > (spec.maximum :: number) then
			return path .. " must be at most " .. spec.maximum
		end
		return nil
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then
			return path .. " must be a boolean, not " .. typeName(value)
		end
		return nil
	elseif kind == "value" then
		local _, problem = Values.fromJson(value, path)
		return problem
	elseif kind == "node" then
		return check(nodeSpec, value, path)
	elseif kind == "array" then
		if type(value) ~= "table" or not Wire.isArray(value) then
			return path .. " must be an array, not " .. typeName(value)
		end
		local list = value :: { unknown }
		if spec.minItems and #list < (spec.minItems :: number) then
			return path .. " needs at least " .. spec.minItems .. " items"
		end
		if spec.maxItems and #list > (spec.maxItems :: number) then
			return path .. " allows at most " .. spec.maxItems .. " items"
		end
		local items = spec.items :: Spec
		for index, item in list do
			local problem = check(items, item, path .. "[" .. (index - 1) .. "]")
			if problem then
				return problem
			end
		end
		return nil
	end
	if type(value) ~= "table" or (Wire.isArray(value) and next(value :: { [unknown]: unknown }) ~= nil) then
		return path .. " must be an object, not " .. typeName(value)
	end
	local object = value :: { [unknown]: unknown }
	local values = spec.values
	if values then
		for key, item in object do
			if type(key) == "userdata" then
				continue
			end
			if type(key) ~= "string" then
				return path .. " must have string keys"
			end
			local problem = check(values, item, path .. "." .. key)
			if problem then
				return problem
			end
		end
		return nil
	end
	local fields = fieldsOf(spec)
	for key in object do
		if type(key) == "userdata" then
			continue
		end
		if type(key) ~= "string" or fields[key :: string] == nil then
			local names: { string } = {}
			for name in fields do
				table.insert(names, name)
			end
			table.sort(names)
			return path .. " has an unknown field " .. tostring(key) .. "; expected " .. table.concat(names, ", ")
		end
	end
	for _, name in requiredOf(spec) do
		if object[name] == nil or object[name] == Wire.null then
			return path .. "." .. name .. " is required"
		end
	end
	local names: { string } = {}
	for name in fields do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local item = object[name]
		if item ~= nil and item ~= Wire.null then
			local problem = check(fields[name], item, path .. "." .. name)
			if problem then
				return problem
			end
		end
	end
	return nil
end

function Contract.check(spec: Spec, value: unknown, path: string?): string?
	return check(spec, value, path or "input")
end

local NODE_KIND = Contract.string("Control name, for example Text or VStack.", { pattern = "^%u[%w_]*$" })
local LABEL = Contract.string("Unique label among siblings.", { pattern = "^[%a_][%w_]*$", maxLength = 64 })

nodeSpec = Contract.object({
	kind = NODE_KIND,
	label = LABEL,
	props = Contract.map(Contract.value(), "Property values by name."),
	children = Contract.array(Contract.node(), "Child nodes in order.", 0, 200),
	keyed = Contract.object({
		from = Contract.string("Model path of the list, for example inventory.items.", { pattern = "^[%a_][%w_%.]*$" }),
		key = Contract.string("Item field that identifies each item.", { pattern = "^[%a_][%w_]*$" }),
		item = Contract.string("Parameter name for the item.", { pattern = "^[%a_][%w_]*$" }),
		template = Contract.node("The control that renders one item."),
	}, { "from", "template" }, "A keyed collection over a model list."),
}, {}, "A new node: a control (kind) or a keyed collection (keyed).")

Contract.NODE = nodeSpec
Contract.LABEL = LABEL
Contract.KIND = NODE_KIND

local VALUE_SCHEMA: { [string]: unknown } = {
	description = "A design value: a string, number or boolean, or an object with kind token, binding, datatype, enum or table.",
	anyOf = {
		{ type = "string" },
		{ type = "number" },
		{ type = "boolean" },
		{
			type = "object",
			properties = {
				kind = {
					type = "string",
					enum = { "string", "number", "boolean", "token", "binding", "datatype", "enum", "table" },
				},
			},
			required = { "kind" },
		},
	},
}

local function jsonSchema(spec: Spec, depth: number): { [string]: unknown }
	local result: { [string]: unknown } = {}
	local kind = spec.kind
	if kind == "value" then
		result = table.clone(VALUE_SCHEMA)
	elseif kind == "json" then
		result = {}
	elseif kind == "node" then
		if depth > 2 then
			result = { type = "object", description = "A nested node with the same fields." }
		else
			result = jsonSchema(nodeSpec, depth + 1)
		end
	elseif kind == "string" then
		result.type = "string"
		if spec.enum then
			result.enum = spec.enum
		end
		if spec.maxLength then
			result.maxLength = spec.maxLength
		end
	elseif kind == "integer" or kind == "number" then
		result.type = kind
		if spec.minimum then
			result.minimum = spec.minimum
		end
		if spec.maximum then
			result.maximum = spec.maximum
		end
	elseif kind == "boolean" then
		result.type = "boolean"
	elseif kind == "array" then
		result.type = "array"
		result.items = jsonSchema(spec.items :: Spec, depth)
		if spec.minItems then
			result.minItems = spec.minItems
		end
		if spec.maxItems then
			result.maxItems = spec.maxItems
		end
	else
		result.type = "object"
		if spec.values then
			result.additionalProperties = jsonSchema(spec.values :: Spec, depth)
		else
			local properties: { [string]: unknown } = {}
			for name, field in fieldsOf(spec) do
				properties[name] = jsonSchema(field, depth)
			end
			result.properties = Wire.object(properties :: { [string]: Wire.Value })
			result.additionalProperties = false
			if spec.required and #(spec.required :: { string }) > 0 then
				result.required = spec.required
			end
		end
	end
	if spec.description and result.description == nil then
		result.description = spec.description
	end
	return result
end

function Contract.jsonSchema(spec: Spec): { [string]: unknown }
	return jsonSchema(spec, 0)
end

function Contract.extend(spec: Spec, fields: { [string]: Spec }, required: { string }?): Spec
	local merged: { [string]: Spec } = table.clone(fieldsOf(spec))
	for name, field in fields do
		merged[name] = field
	end
	local names = table.clone(requiredOf(spec))
	for _, name in required or NO_NAMES do
		table.insert(names, name)
	end
	return { kind = "object", fields = merged, required = names, description = spec.description }
end

return table.freeze(Contract)
