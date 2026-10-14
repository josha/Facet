--!strict

export type Value =
	{ kind: "null" }
	| { kind: "bool", value: boolean }
	| { kind: "int", value: number }
	| { kind: "float", value: number }
	| { kind: "string", value: string }
	| { kind: "array", items: { Value } }
	| { kind: "object", keys: { string }, map: { [string]: Value } }

export type Object = { kind: "object", keys: { string }, map: { [string]: Value } }

local OrderedJson = {}

local NULL: Value = { kind = "null" }
OrderedJson.null = table.freeze(NULL)

function OrderedJson.string(value: string): Value
	return { kind = "string", value = value }
end

function OrderedJson.int(value: number): Value
	return { kind = "int", value = value }
end

function OrderedJson.float(value: number): Value
	return { kind = "float", value = value }
end

function OrderedJson.bool(value: boolean): Value
	return { kind = "bool", value = value }
end

function OrderedJson.array(items: { Value }): Value
	return { kind = "array", items = items }
end

function OrderedJson.object(): Object
	return { kind = "object", keys = {}, map = {} }
end

function OrderedJson.set(object: Object, key: string, value: Value)
	if object.map[key] == nil then
		table.insert(object.keys, key)
	end
	object.map[key] = value
end

function OrderedJson.get(object: Object, key: string): Value?
	return object.map[key]
end

function OrderedJson.asObject(value: Value?): Object?
	if value ~= nil and value.kind == "object" then
		return value :: Object
	end
	return nil
end

function OrderedJson.asString(value: Value?): string?
	if value ~= nil and value.kind == "string" then
		return (value :: { kind: "string", value: string }).value
	end
	return nil
end

function OrderedJson.sorted(object: Object): Object
	local out = OrderedJson.object()
	local keys = table.clone(object.keys)
	table.sort(keys)
	for _, key in keys do
		OrderedJson.set(out, key, object.map[key])
	end
	return out
end

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function quote(text: string): string
	local parts: { string } = { '"' }
	for _, codepoint in utf8.codes(text) do
		local character = utf8.char(codepoint)
		local escape = ESCAPES[character]
		if escape ~= nil then
			table.insert(parts, escape)
		elseif codepoint < 0x20 then
			table.insert(parts, ("\\u%04x"):format(codepoint))
		elseif codepoint < 0x80 then
			table.insert(parts, character)
		elseif codepoint < 0x10000 then
			table.insert(parts, ("\\u%04x"):format(codepoint))
		else
			local offset = codepoint - 0x10000
			table.insert(parts, ("\\u%04x\\u%04x"):format(0xD800 + offset // 0x400, 0xDC00 + offset % 0x400))
		end
	end
	table.insert(parts, '"')
	return table.concat(parts)
end

function OrderedJson.floatRepr(value: number): string
	if value ~= value then
		return "NaN"
	elseif value == math.huge then
		return "Infinity"
	elseif value == -math.huge then
		return "-Infinity"
	elseif value == 0 then
		return if 1 / value < 0 then "-0.0" else "0.0"
	end
	local mantissa, exponent = "", 0
	for precision = 1, 17 do
		local text = string.format("%." .. (precision - 1) .. "e", value)
		if tonumber(text) == value then
			local digits, power = string.match(text, "^(-?[%d%.]+)e([-+]%d+)$")
			mantissa = string.gsub(digits :: string, "%.", "")
			exponent = tonumber(power) :: number
			break
		end
	end
	local negative = string.sub(mantissa, 1, 1) == "-"
	if negative then
		mantissa = string.sub(mantissa, 2)
	end
	mantissa = string.gsub(mantissa, "0+$", "")
	if mantissa == "" then
		mantissa = "0"
	end
	local text
	if exponent >= -4 and exponent < 16 then
		if exponent >= 0 then
			local whole = if #mantissa > exponent + 1
				then string.sub(mantissa, 1, exponent + 1)
				else mantissa .. string.rep("0", exponent + 1 - #mantissa)
			local fraction = string.sub(mantissa, exponent + 2)
			text = whole .. "." .. (if fraction == "" then "0" else fraction)
		else
			text = "0." .. string.rep("0", -exponent - 1) .. mantissa
		end
	else
		local head = string.sub(mantissa, 1, 1)
		local tail = string.sub(mantissa, 2)
		text = head
			.. (if tail == "" then "" else "." .. tail)
			.. ("e%s%02d"):format(if exponent < 0 then "-" else "+", math.abs(exponent))
	end
	return if negative then "-" .. text else text
end

local function encode(value: Value, indent: number?, depth: number, sortKeys: boolean, parts: { string })
	local function opening(level: number): string
		if indent == nil then
			return ""
		end
		return "\n" .. string.rep(" ", indent * level)
	end
	local separator = if indent == nil then ", " else ","
	if value.kind == "null" then
		table.insert(parts, "null")
	elseif value.kind == "bool" then
		table.insert(parts, if value.value then "true" else "false")
	elseif value.kind == "int" then
		table.insert(parts, ("%d"):format(value.value))
	elseif value.kind == "float" then
		table.insert(parts, OrderedJson.floatRepr(value.value))
	elseif value.kind == "string" then
		table.insert(parts, quote(value.value))
	elseif value.kind == "array" then
		if #value.items == 0 then
			table.insert(parts, "[]")
			return
		end
		local inner = opening(depth + 1)
		table.insert(parts, "[")
		for index, item in value.items do
			table.insert(parts, if index == 1 then inner else separator .. inner)
			encode(item, indent, depth + 1, sortKeys, parts)
		end
		table.insert(parts, opening(depth) .. "]")
	else
		local keys: { string } = if sortKeys then table.clone(value.keys) else value.keys
		if sortKeys then
			table.sort(keys)
		end
		if #keys == 0 then
			table.insert(parts, "{}")
			return
		end
		local inner = opening(depth + 1)
		table.insert(parts, "{")
		for index, key in keys do
			table.insert(parts, if index == 1 then inner else separator .. inner)
			table.insert(parts, quote(key))
			table.insert(parts, ": ")
			encode(value.map[key], indent, depth + 1, sortKeys, parts)
		end
		table.insert(parts, opening(depth) .. "}")
	end
end

function OrderedJson.dumps(value: Value, sortKeys: boolean?): string
	local parts: { string } = {}
	encode(value, 2, 0, sortKeys == true, parts)
	return table.concat(parts)
end

function OrderedJson.compact(value: Value, sortKeys: boolean?): string
	local parts: { string } = {}
	encode(value, nil, 0, sortKeys == true, parts)
	return table.concat(parts)
end

type Parser = { text: string, position: number }

local function fail(parser: Parser, message: string): never
	error(("json: %s at byte %d"):format(message, parser.position), 0)
end

local function present<T>(value: T?, parser: Parser, message: string): T
	if value == nil then
		fail(parser, message)
	end
	return value :: T
end

local function skip(parser: Parser)
	local _, stop = string.find(parser.text, "^[ \t\r\n]*", parser.position)
	parser.position = (stop :: number) + 1
end

local parseValue: (Parser) -> Value

local function parseString(parser: Parser): string
	local text = parser.text
	local position = parser.position + 1
	local parts: { string } = {}
	while true do
		local character = string.sub(text, position, position)
		if character == "" then
			parser.position = position
			fail(parser, "unterminated string")
		elseif character == '"' then
			parser.position = position + 1
			return table.concat(parts)
		elseif character == "\\" then
			local escape = string.sub(text, position + 1, position + 1)
			if escape == "u" then
				parser.position = position
				local code = present(
					tonumber(string.sub(text, position + 2, position + 5), 16),
					parser,
					"invalid unicode escape"
				)
				position += 6
				if code >= 0xD800 and code <= 0xDBFF and string.sub(text, position, position + 1) == "\\u" then
					local low = tonumber(string.sub(text, position + 2, position + 5), 16)
					if low ~= nil and low >= 0xDC00 and low <= 0xDFFF then
						code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
						position += 6
					end
				end
				table.insert(parts, utf8.char(code))
			else
				local map: { [string]: string } =
					{ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				parser.position = position
				table.insert(parts, present(map[escape], parser, "invalid escape"))
				position += 2
			end
		else
			parser.position = position
			local stop: number = present(string.find(text, '["\\]', position), parser, "unterminated string")
			table.insert(parts, string.sub(text, position, stop - 1))
			position = stop
		end
	end
end

parseValue = function(parser: Parser): Value
	skip(parser)
	local text = parser.text
	local character = string.sub(text, parser.position, parser.position)
	if character == "{" then
		parser.position += 1
		local object = OrderedJson.object()
		skip(parser)
		if string.sub(text, parser.position, parser.position) == "}" then
			parser.position += 1
			return object
		end
		while true do
			skip(parser)
			if string.sub(text, parser.position, parser.position) ~= '"' then
				fail(parser, "expected an object key")
			end
			local key = parseString(parser)
			skip(parser)
			if string.sub(text, parser.position, parser.position) ~= ":" then
				fail(parser, "expected ':'")
			end
			parser.position += 1
			OrderedJson.set(object, key, parseValue(parser))
			skip(parser)
			local separator = string.sub(text, parser.position, parser.position)
			parser.position += 1
			if separator == "}" then
				return object
			elseif separator ~= "," then
				fail(parser, "expected ',' or '}'")
			end
		end
	elseif character == "[" then
		parser.position += 1
		local items: { Value } = {}
		skip(parser)
		if string.sub(text, parser.position, parser.position) == "]" then
			parser.position += 1
			return OrderedJson.array(items)
		end
		while true do
			table.insert(items, parseValue(parser))
			skip(parser)
			local separator = string.sub(text, parser.position, parser.position)
			parser.position += 1
			if separator == "]" then
				return OrderedJson.array(items)
			elseif separator ~= "," then
				fail(parser, "expected ',' or ']'")
			end
		end
	elseif character == '"' then
		return OrderedJson.string(parseString(parser))
	elseif string.sub(text, parser.position, parser.position + 3) == "true" then
		parser.position += 4
		return OrderedJson.bool(true)
	elseif string.sub(text, parser.position, parser.position + 4) == "false" then
		parser.position += 5
		return OrderedJson.bool(false)
	elseif string.sub(text, parser.position, parser.position + 3) == "null" then
		parser.position += 4
		return OrderedJson.null
	end
	local literal =
		present(string.match(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", parser.position), parser, "unexpected character")
	if literal == "" then
		fail(parser, "unexpected character")
	end
	parser.position += #literal
	local number = present(tonumber(literal), parser, "invalid number")
	if string.find(literal, "[%.eE]") then
		return OrderedJson.float(number)
	end
	return OrderedJson.int(number)
end

function OrderedJson.parse(text: string): Value
	local parser: Parser = { text = text, position = 1 }
	local value = parseValue(parser)
	skip(parser)
	if parser.position <= #text then
		fail(parser, "trailing characters")
	end
	return value
end

return table.freeze(OrderedJson)
