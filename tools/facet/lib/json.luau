--!strict

export type Object = { [string]: unknown }
export type Array = { unknown }

export type EncodeOptions = {
	indent: number?,
	sortKeys: boolean?,
	compact: boolean?,
	ascii: boolean?,
}

local Json = {}

local NULL = table.freeze({})
type Orders = { [unknown]: { string } }
type Kinds = { [unknown]: "array" | "object" }

local orders: Orders = {}
local kinds: Kinds = {}
setmetatable(orders, { __mode = "k" })
setmetatable(kinds, { __mode = "k" })

Json.null = NULL

function Json.isNull(value: unknown): boolean
	return value == NULL
end

function Json.object(): Object
	local object: Object = {}
	kinds[object] = "object"
	orders[object] = {}
	return object
end

function Json.array(items: { unknown }?): Array
	local array: Array = items or {}
	kinds[array] = "array"
	return array
end

function Json.set(object: Object, key: string, value: unknown)
	if object[key] == nil then
		local order = orders[object]
		if order == nil then
			order = {}
			orders[object] = order
			kinds[object] = "object"
		end
		if table.find(order, key) == nil then
			table.insert(order, key)
		end
	end
	object[key] = value
end

function Json.keys(object: Object): { string }
	local order = orders[object]
	local seen: { [string]: boolean } = {}
	local keys: { string } = {}
	if order ~= nil then
		for _, key in order do
			if object[key] ~= nil and not seen[key] then
				seen[key] = true
				table.insert(keys, key)
			end
		end
	end
	local rest: { string } = {}
	for key in object do
		if type(key) == "string" and not seen[key] then
			table.insert(rest, key)
		end
	end
	table.sort(rest)
	for _, key in rest do
		table.insert(keys, key)
	end
	return keys
end

local function isArray(value: { [unknown]: unknown }): boolean
	local kind = kinds[value]
	if kind ~= nil then
		return kind == "array"
	end
	local count = 0
	for key in value do
		if type(key) ~= "number" then
			return false
		end
		count += 1
	end
	return count == #value
end

function Json.asObject(value: unknown): Object?
	if type(value) ~= "table" or value == NULL then
		return nil
	end
	local candidate = value :: { [unknown]: unknown }
	if kinds[candidate] == "array" then
		return nil
	end
	if kinds[candidate] == nil and next(candidate) ~= nil and isArray(candidate) then
		return nil
	end
	return candidate :: Object
end

function Json.asArray(value: unknown): Array?
	if type(value) ~= "table" or value == NULL then
		return nil
	end
	local candidate = value :: { [unknown]: unknown }
	if kinds[candidate] == "object" then
		return nil
	end
	if not isArray(candidate) then
		return nil
	end
	return candidate :: Array
end

function Json.asString(value: unknown): string?
	return if type(value) == "string" then value else nil
end

function Json.asNumber(value: unknown): number?
	return if type(value) == "number" then value else nil
end

function Json.asBoolean(value: unknown): boolean?
	return if type(value) == "boolean" then value else nil
end

function Json.field(value: unknown, key: string): unknown
	local object = Json.asObject(value)
	if object == nil then
		return nil
	end
	local found = object[key]
	if found == NULL then
		return nil
	end
	return found
end

function Json.stringField(value: unknown, key: string): string?
	return Json.asString(Json.field(value, key))
end

function Json.numberField(value: unknown, key: string): number?
	return Json.asNumber(Json.field(value, key))
end

function Json.objectField(value: unknown, key: string): Object?
	return Json.asObject(Json.field(value, key))
end

function Json.arrayField(value: unknown, key: string): Array?
	return Json.asArray(Json.field(value, key))
end

function Json.strings(value: unknown): { string }?
	local array = Json.asArray(value)
	if array == nil then
		return nil
	end
	local strings: { string } = {}
	for _, item in array do
		if type(item) ~= "string" then
			return nil
		end
		table.insert(strings, item)
	end
	return strings
end

type Reader = { text: string, index: number }

local function fail(reader: Reader, message: string): never
	local before = string.sub(reader.text, 1, reader.index - 1)
	local _, newlines = string.gsub(before, "\n", "")
	local column = reader.index - (string.match(before, ".*()\n") or 0)
	error(("%s at line %d column %d"):format(message, newlines + 1, column), 0)
end

local function skip(reader: Reader)
	local _, finish = string.find(reader.text, "^[ \t\r\n]*", reader.index)
	reader.index = (finish or reader.index - 1) + 1
end

local decodeValue: (Reader) -> unknown

local ESCAPES: { [string]: string } = {
	['"'] = '"',
	["\\"] = "\\",
	["/"] = "/",
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
}

local function decodeString(reader: Reader): string
	local text = reader.text
	local index = reader.index + 1
	local parts: { string } = {}
	while true do
		local start, finish = string.find(text, '^[^"\\%c]+', index)
		if start ~= nil and finish ~= nil then
			table.insert(parts, string.sub(text, start, finish))
			index = finish + 1
		end
		local char = string.sub(text, index, index)
		if char == '"' then
			reader.index = index + 1
			return table.concat(parts)
		elseif char == "\\" then
			local escape = string.sub(text, index + 1, index + 1)
			if escape == "u" then
				local hexits = string.sub(text, index + 2, index + 5)
				if not string.match(hexits, "^%x%x%x%x$") then
					reader.index = index
					fail(reader, "invalid unicode escape")
				end
				local code = tonumber(hexits, 16) :: number
				index += 6
				if code >= 0xD800 and code <= 0xDBFF and string.sub(text, index, index + 1) == "\\u" then
					local low = tonumber(string.sub(text, index + 2, index + 5), 16)
					if low ~= nil and low >= 0xDC00 and low <= 0xDFFF then
						code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
						index += 6
					end
				end
				table.insert(parts, utf8.char(code))
			else
				local replacement = ESCAPES[escape]
				if replacement == nil then
					reader.index = index
					fail(reader, "invalid escape")
				end
				table.insert(parts, replacement)
				index += 2
			end
		elseif char == "" then
			reader.index = index
			fail(reader, "unterminated string")
		else
			reader.index = index
			fail(reader, "control character in string")
		end
	end
end

local function decodeArray(reader: Reader): Array
	local array = Json.array()
	reader.index += 1
	skip(reader)
	if string.sub(reader.text, reader.index, reader.index) == "]" then
		reader.index += 1
		return array
	end
	while true do
		table.insert(array, decodeValue(reader))
		skip(reader)
		local char = string.sub(reader.text, reader.index, reader.index)
		reader.index += 1
		if char == "]" then
			return array
		elseif char ~= "," then
			reader.index -= 1
			fail(reader, "expected ',' or ']'")
		end
	end
end

local function decodeObject(reader: Reader): Object
	local object = Json.object()
	reader.index += 1
	skip(reader)
	if string.sub(reader.text, reader.index, reader.index) == "}" then
		reader.index += 1
		return object
	end
	while true do
		skip(reader)
		if string.sub(reader.text, reader.index, reader.index) ~= '"' then
			fail(reader, "expected a string key")
		end
		local key = decodeString(reader)
		skip(reader)
		if string.sub(reader.text, reader.index, reader.index) ~= ":" then
			fail(reader, "expected ':'")
		end
		reader.index += 1
		local value = decodeValue(reader)
		Json.set(object, key, value)
		skip(reader)
		local char = string.sub(reader.text, reader.index, reader.index)
		reader.index += 1
		if char == "}" then
			return object
		elseif char ~= "," then
			reader.index -= 1
			fail(reader, "expected ',' or '}'")
		end
	end
end

decodeValue = function(reader: Reader): unknown
	skip(reader)
	local text = reader.text
	local char = string.sub(text, reader.index, reader.index)
	if char == "{" then
		return decodeObject(reader)
	elseif char == "[" then
		return decodeArray(reader)
	elseif char == '"' then
		return decodeString(reader)
	elseif string.sub(text, reader.index, reader.index + 3) == "true" then
		reader.index += 4
		return true
	elseif string.sub(text, reader.index, reader.index + 4) == "false" then
		reader.index += 5
		return false
	elseif string.sub(text, reader.index, reader.index + 3) == "null" then
		reader.index += 4
		return NULL
	end
	local start, finish = string.find(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", reader.index)
	if start ~= nil and finish ~= nil then
		local number = tonumber(string.sub(text, start, finish))
		if number ~= nil then
			reader.index = finish + 1
			return number
		end
	end
	if char == "" then
		return fail(reader, "unexpected end of input")
	end
	return fail(reader, "unexpected character '" .. char .. "'")
end

function Json.decode(text: string): unknown
	local reader: Reader = { text = text, index = 1 }
	if string.sub(text, 1, 3) == "\239\187\191" then
		reader.index = 4
	end
	local value = decodeValue(reader)
	skip(reader)
	if reader.index <= #text then
		fail(reader, "trailing data")
	end
	return value
end

function Json.tryDecode(text: string): (unknown, string?)
	local ok, value = pcall(Json.decode, text)
	if not ok then
		return nil, tostring(value)
	end
	return value, nil
end

local SIMPLE_ESCAPES: { [number]: string } = {
	[0x22] = '\\"',
	[0x5C] = "\\\\",
	[0x08] = "\\b",
	[0x0C] = "\\f",
	[0x0A] = "\\n",
	[0x0D] = "\\r",
	[0x09] = "\\t",
}

local function encodeString(value: string, ascii: boolean): string
	local parts: { string } = { '"' }
	local valid = utf8.len(value) ~= nil
	if not valid then
		for index = 1, #value do
			local byte = string.byte(value, index)
			local escape = SIMPLE_ESCAPES[byte]
			if escape then
				table.insert(parts, escape)
			elseif byte < 0x20 or (ascii and byte >= 0x80) then
				table.insert(parts, ("\\u%04x"):format(byte))
			else
				table.insert(parts, string.char(byte))
			end
		end
	else
		for _, code in utf8.codes(value) do
			local escape = SIMPLE_ESCAPES[code]
			if escape then
				table.insert(parts, escape)
			elseif code < 0x20 then
				table.insert(parts, ("\\u%04x"):format(code))
			elseif code >= 0x80 and ascii then
				if code >= 0x10000 then
					local offset = code - 0x10000
					table.insert(
						parts,
						("\\u%04x\\u%04x"):format(0xD800 + bit32.rshift(offset, 10), 0xDC00 + bit32.band(offset, 0x3FF))
					)
				else
					table.insert(parts, ("\\u%04x"):format(code))
				end
			else
				table.insert(parts, utf8.char(code))
			end
		end
	end
	table.insert(parts, '"')
	return table.concat(parts)
end

local function encodeNumber(value: number): string
	if value ~= value then
		return "NaN"
	elseif value == math.huge then
		return "Infinity"
	elseif value == -math.huge then
		return "-Infinity"
	elseif value == math.floor(value) and math.abs(value) < 2 ^ 53 then
		return ("%d"):format(value)
	end
	return tostring(value)
end

local function encodeValue(value: unknown, options: EncodeOptions, depth: number, out: { string })
	local indent = options.indent
	local ascii = options.ascii ~= false
	local itemSeparator = if options.compact then "," elseif indent then "," else ", "
	local keySeparator = if options.compact then ":" else ": "
	if value == nil or value == NULL then
		table.insert(out, "null")
	elseif type(value) == "boolean" then
		table.insert(out, if value then "true" else "false")
	elseif type(value) == "number" then
		table.insert(out, encodeNumber(value))
	elseif type(value) == "string" then
		table.insert(out, encodeString(value, ascii))
	elseif type(value) == "table" then
		local tableValue = value :: { [unknown]: unknown }
		local newline = if indent then "\n" .. string.rep(" ", indent * (depth + 1)) else ""
		local closing = if indent then "\n" .. string.rep(" ", indent * depth) else ""
		if isArray(tableValue) and not (next(tableValue) == nil and kinds[tableValue] == "object") then
			local array = tableValue :: { unknown }
			if #array == 0 then
				table.insert(out, "[]")
				return
			end
			table.insert(out, "[")
			for index, item in array do
				if index > 1 then
					table.insert(out, itemSeparator)
				end
				table.insert(out, newline)
				encodeValue(item, options, depth + 1, out)
			end
			table.insert(out, closing)
			table.insert(out, "]")
		else
			local object = tableValue :: Object
			local keys = Json.keys(object)
			for key in tableValue do
				if type(key) == "number" then
					table.insert(keys, tostring(key))
				end
			end
			if options.sortKeys then
				table.sort(keys)
			end
			if #keys == 0 then
				table.insert(out, "{}")
				return
			end
			table.insert(out, "{")
			for index, key in keys do
				if index > 1 then
					table.insert(out, itemSeparator)
				end
				table.insert(out, newline)
				table.insert(out, encodeString(key, ascii))
				table.insert(out, keySeparator)
				local item = object[key]
				if item == nil then
					item = tableValue[tonumber(key)]
				end
				encodeValue(item, options, depth + 1, out)
			end
			table.insert(out, closing)
			table.insert(out, "}")
		end
	else
		error("cannot encode a " .. type(value) .. " as JSON", 0)
	end
end

function Json.encode(value: unknown, options: EncodeOptions?): string
	local out: { string } = {}
	encodeValue(value, options or {}, 0, out)
	return table.concat(out)
end

function Json.pretty(value: unknown): string
	return Json.encode(value, { indent = 2 }) .. "\n"
end

function Json.canonical(value: unknown): string
	return Json.encode(value, { sortKeys = true, compact = true })
end

return table.freeze(Json)
