--!strict

local json = require("@std/json")

export type Value = json.Value
export type Object = { [string]: Value }
export type Array = { Value }

local Wire = {}

local EMPTY_OBJECT = json.object({})

Wire.null = json.null

function Wire.object(fields: { [string]: Value }?): Object
	return json.object(fields or {})
end

function Wire.emptyObject(): Object
	return EMPTY_OBJECT
end

function Wire.isObject(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	local fields = value :: { [unknown]: unknown }
	if json.asObject(value :: Value) ~= nil then
		return true
	end
	if #(fields :: { unknown }) > 0 then
		return false
	end
	return next(fields) ~= nil
end

function Wire.isArray(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	if json.asObject(value :: Value) ~= nil then
		return false
	end
	local fields = value :: { [unknown]: unknown }
	local count = #(fields :: { unknown })
	for key in fields do
		if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
			return false
		end
	end
	return true
end

local function escape(text: string): string
	local escaped = string.gsub(text, '[%c"\\]', function(character: string): string
		if character == '"' then
			return '\\"'
		elseif character == "\\" then
			return "\\\\"
		elseif character == "\n" then
			return "\\n"
		elseif character == "\r" then
			return "\\r"
		elseif character == "\t" then
			return "\\t"
		end
		return string.format("\\u%04x", string.byte(character))
	end)
	return '"' .. escaped .. '"'
end

local function number(value: number): string
	assert(value == value and value ~= math.huge and value ~= -math.huge, "JSON cannot encode a non-finite number")
	if value % 1 == 0 and math.abs(value) < 2 ^ 53 then
		return string.format("%d", value)
	end
	for precision = 1, 17 do
		local text = string.format("%." .. precision .. "g", value)
		if tonumber(text) == value then
			return text
		end
	end
	return string.format("%.17g", value)
end

local function encodeInto(parts: { string }, value: unknown, pretty: boolean, depth: number)
	if value == nil or value == json.null then
		table.insert(parts, "null")
		return
	end
	local kind = type(value)
	if kind == "boolean" then
		table.insert(parts, if value then "true" else "false")
	elseif kind == "number" then
		table.insert(parts, number(value :: number))
	elseif kind == "string" then
		table.insert(parts, escape(value :: string))
	elseif kind == "table" then
		local indent = if pretty then "\n" .. string.rep("  ", depth + 1) else ""
		local closing = if pretty then "\n" .. string.rep("  ", depth) else ""
		local separator = if pretty then ": " else ":"
		if Wire.isArray(value) and not Wire.isObject(value) then
			local items = value :: { unknown }
			if #items == 0 then
				table.insert(parts, "[]")
				return
			end
			table.insert(parts, "[")
			for index, item in items do
				if index > 1 then
					table.insert(parts, ",")
				end
				table.insert(parts, indent)
				encodeInto(parts, item, pretty, depth + 1)
			end
			table.insert(parts, closing .. "]")
			return
		end
		local fields = value :: { [unknown]: unknown }
		local keys: { string } = {}
		for key in fields do
			if type(key) == "string" then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		if #keys == 0 then
			table.insert(parts, "{}")
			return
		end
		table.insert(parts, "{")
		for index, key in keys do
			if index > 1 then
				table.insert(parts, ",")
			end
			table.insert(parts, indent .. escape(key) .. separator)
			encodeInto(parts, fields[key], pretty, depth + 1)
		end
		table.insert(parts, closing .. "}")
	else
		error("JSON cannot encode a " .. kind, 2)
	end
end

function Wire.encode(value: unknown, pretty: boolean?): string
	local parts: { string } = {}
	encodeInto(parts, value, pretty == true, 0)
	return table.concat(parts)
end

function Wire.decode(text: string): (boolean, unknown)
	local ok, result = pcall(json.deserialize, text)
	if not ok then
		return false, tostring(result)
	end
	return true, result
end

function Wire.field(value: unknown, name: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	local found = (value :: { [string]: unknown })[name]
	if found == json.null then
		return nil
	end
	return found
end

function Wire.text(value: unknown, name: string): string?
	local found = Wire.field(value, name)
	return if type(found) == "string" then found else nil
end

function Wire.list(value: unknown): { unknown }
	if type(value) == "table" and Wire.isArray(value) then
		return value :: { unknown }
	end
	return {}
end

return table.freeze(Wire)
