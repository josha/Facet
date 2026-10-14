--!strict

local Cst = require("./cst")
local SourceMap = require("./source_map")
local Wire = require("./wire")

export type ValueKind =
	"string"
	| "number"
	| "boolean"
	| "nil"
	| "token"
	| "binding"
	| "datatype"
	| "enum"
	| "table"
	| "code"

export type Arg = number | string

export type Value = {
	kind: ValueKind,
	value: (string | number | boolean)?,
	cast: boolean?,
	set: string?,
	path: string?,
	source: ("model" | "item")?,
	form: ("use" | "direct")?,
	type: string?,
	constructor: string?,
	args: { Arg }?,
	enum: string?,
	item: string?,
	fields: { [string]: Value }?,
	items: { Value }?,
	text: string?,
}

export type Scope = { model: string?, item: string?, use: string? }

export type Style = {
	indent: string,
	unit: string,
	newline: string,
	cast: boolean,
	brackets: boolean,
	useAnnotation: string?,
	column: number,
	width: number,
}

local Values = {}

local KEYWORDS: { [string]: boolean } = {}
for _, word in
	{
		"and",
		"break",
		"do",
		"else",
		"elseif",
		"end",
		"false",
		"for",
		"function",
		"if",
		"in",
		"local",
		"nil",
		"not",
		"or",
		"repeat",
		"return",
		"then",
		"true",
		"until",
		"while",
		"continue",
		"export",
		"type",
		"typeof",
	}
do
	KEYWORDS[word] = true
end

local CONSTRUCTORS: { [string]: { [string]: { number } } } = {
	UDim2 = { new = { 4 }, fromScale = { 2 }, fromOffset = { 2 } },
	UDim = { new = { 2 } },
	Vector2 = { new = { 0, 2 } },
	Vector3 = { new = { 0, 3 } },
	Color3 = { new = { 0, 3 }, fromRGB = { 0, 3 }, fromHSV = { 3 }, fromHex = { 1 } },
	NumberRange = { new = { 1, 2 } },
	NumberSequence = { new = { 1, 2 } },
	Rect = { new = { 4 } },
	BrickColor = { new = { 1 } },
	Font = { new = { 1, 3 }, fromName = { 1, 3 } },
	TweenInfo = { new = { 0, 1, 2, 3, 4, 5, 6 } },
}

Values.CONSTRUCTORS = CONSTRUCTORS

function Values.isIdentifier(text: string): boolean
	return string.match(text, "^[%a_][%w_]*$") ~= nil and not KEYWORDS[text]
end

function Values.isLabel(text: string): boolean
	return string.match(text, "^[%a_][%w_]*$") ~= nil and #text <= 64
end

local SIMPLE_ESCAPES: { [string]: string } = {
	a = "\a",
	b = "\b",
	f = "\f",
	n = "\n",
	r = "\r",
	t = "\t",
	v = "\v",
	["\\"] = "\\",
	['"'] = '"',
	["'"] = "'",
	["\n"] = "\n",
	["`"] = "`",
	["{"] = "{",
}

local function hex(text: string): number?
	return tonumber(text, 16)
end

function Values.decodeString(raw: string, style: string): string?
	if style == "block" then
		if string.sub(raw, 1, 2) == "\r\n" then
			return string.sub(raw, 3)
		elseif string.sub(raw, 1, 1) == "\n" then
			return string.sub(raw, 2)
		end
		return raw
	end
	local parts: { string } = {}
	local index = 1
	local length = #raw
	while index <= length do
		local character = string.sub(raw, index, index)
		if character ~= "\\" then
			local nextEscape = string.find(raw, "\\", index, true) or (length + 1)
			table.insert(parts, string.sub(raw, index, nextEscape - 1))
			index = nextEscape
			continue
		end
		local escape = string.sub(raw, index + 1, index + 1)
		local simple = SIMPLE_ESCAPES[escape]
		if simple then
			table.insert(parts, simple)
			index += 2
		elseif escape == "\r" then
			table.insert(parts, "\n")
			index += if string.sub(raw, index + 2, index + 2) == "\n" then 3 else 2
		elseif escape == "z" then
			index += 2
			while index <= length and string.find(string.sub(raw, index, index), "%s") do
				index += 1
			end
		elseif escape == "x" then
			local code = hex(string.sub(raw, index + 2, index + 3))
			if code == nil then
				return nil
			end
			table.insert(parts, string.char(code))
			index += 4
		elseif escape == "u" then
			local digits = string.match(raw, "^{(%x+)}", index + 2)
			if digits == nil then
				return nil
			end
			local code = hex(digits)
			if code == nil or code > 0x10FFFF then
				return nil
			end
			table.insert(parts, utf8.char(code))
			index += 4 + #digits
		elseif string.match(escape, "%d") then
			local digits = string.match(raw, "^%d%d?%d?", index + 1) :: string
			local code = tonumber(digits) :: number
			if code > 255 then
				return nil
			end
			table.insert(parts, string.char(code))
			index += 1 + #digits
		else
			return nil
		end
	end
	return table.concat(parts)
end

function Values.quote(text: string): string
	local escaped = string.gsub(text, '[%c"\\\128-\255]', function(character: string): string
		local byte = string.byte(character)
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
		elseif byte >= 128 then
			return character
		end
		return string.format("\\%d", byte)
	end)
	return '"' .. escaped .. '"'
end

function Values.number(value: number): string
	if value ~= value or value == math.huge or value == -math.huge then
		error("a design value must be a finite number", 0)
	end
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

local function stringValue(node: Cst.Expr): string?
	if node.tag == "string" then
		return Values.decodeString(node.value.text, node.quoteStyle)
	end
	return nil
end

local function numberValue(node: Cst.Expr): number?
	if node.tag == "number" then
		return node.value
	elseif node.tag == "integer" then
		return node.value
	elseif node.tag == "unary" and node.operator.text == "-" then
		local operand = node.operand
		if operand.tag == "number" then
			return -operand.value
		elseif operand.tag == "integer" then
			return -operand.value
		end
	end
	return nil
end

local function nameOf(node: Cst.Expr): string?
	if node.tag == "local" then
		return node.token.text
	elseif node.tag == "global" then
		return node.name.text
	end
	return nil
end

local function pathOf(node: Cst.Expr, root: string): string?
	local segments: { string } = {}
	local current = node
	while true do
		if current.tag == "indexname" and current.accessor.text == "." then
			table.insert(segments, 1, current.index.text)
			current = current.expression
		elseif current.tag == "index" and current.index.tag == "string" then
			local key = stringValue(current.index)
			if key == nil or string.find(key, ".", 1, true) then
				return nil
			end
			table.insert(segments, 1, key)
			current = current.expression
		elseif current.tag == "group" then
			current = current.expression
		else
			break
		end
	end
	if nameOf(current) ~= root then
		return nil
	end
	return table.concat(segments, ".")
end

local function singleReturn(fn: Cst.Function): Cst.Expr?
	local statements = fn.body.statements
	if #statements ~= 1 then
		return nil
	end
	local statement = statements[1]
	if statement.tag ~= "return" or #statement.expressions ~= 1 then
		return nil
	end
	return statement.expressions[1]
end

local function bindingOf(node: Cst.Expr, scope: Scope): Value?
	if scope.model then
		local path = pathOf(node, scope.model :: string)
		if path and path ~= "" then
			return { kind = "binding", path = path, source = "model", form = "direct" }
		end
	end
	if scope.item then
		local path = pathOf(node, scope.item :: string)
		if path then
			return { kind = "binding", path = path, source = "item", form = "direct" }
		end
	end
	if node.tag ~= "function" or #node.parameters ~= 1 or node.hasVararg then
		return nil
	end
	local useName = node.parameters[1].name.text
	local returned = singleReturn(node)
	if returned == nil then
		return nil
	end
	local call: Cst.Expr = returned
	local suffix = ""
	if call.tag ~= "call" then
		local outer = returned
		local segments: { string } = {}
		while outer.tag == "indexname" and outer.accessor.text == "." do
			table.insert(segments, 1, outer.index.text)
			outer = outer.expression
		end
		if outer.tag ~= "call" or #segments == 0 then
			return nil
		end
		call = outer
		suffix = table.concat(segments, ".")
	end
	if call.tag ~= "call" or call.self or #call.arguments ~= 1 or nameOf(call.func) ~= useName then
		return nil
	end
	local argument = call.arguments[1]
	if scope.model then
		local path = pathOf(argument, scope.model :: string)
		if path and path ~= "" and suffix == "" then
			return { kind = "binding", path = path, source = "model", form = "use" }
		end
	end
	if scope.item then
		local path = pathOf(argument, scope.item :: string)
		if path then
			local full = if path == "" then suffix elseif suffix == "" then path else path .. "." .. suffix
			return { kind = "binding", path = full, source = "item", form = "use" }
		end
	end
	return nil
end

local function datatypeOf(node: Cst.Expr): Value?
	if node.tag ~= "call" or node.self then
		return nil
	end
	local callee = node.func
	if callee.tag ~= "indexname" or callee.accessor.text ~= "." or callee.expression.tag ~= "global" then
		return nil
	end
	local typeName = callee.expression.name.text
	local constructorName = callee.index.text
	local family = CONSTRUCTORS[typeName]
	if family == nil or family[constructorName] == nil then
		return nil
	end
	local args: { Arg } = {}
	for index = 1, #node.arguments do
		local argument = node.arguments[index]
		local numeric = numberValue(argument)
		if numeric ~= nil then
			table.insert(args, numeric)
		else
			local text = stringValue(argument)
			if text == nil then
				return nil
			end
			table.insert(args, text)
		end
	end
	if not table.find(family[constructorName], #args) then
		return nil
	end
	return { kind = "datatype", type = typeName, constructor = constructorName, args = args }
end

local function enumOf(node: Cst.Expr): Value?
	if node.tag ~= "indexname" or node.accessor.text ~= "." then
		return nil
	end
	local middle = node.expression
	if middle.tag ~= "indexname" or middle.accessor.text ~= "." then
		return nil
	end
	local root = middle.expression
	if root.tag ~= "global" or root.name.text ~= "Enum" then
		return nil
	end
	return { kind = "enum", enum = middle.index.text, item = node.index.text }
end

local function literal(kind: ValueKind, value: (string | number | boolean)?): Value
	return { kind = kind, value = value }
end

function Values.read(map: SourceMap.SourceMap, node: Cst.Expr, scope: Scope): Value
	local text = SourceMap.slice(map, SourceMap.expr(map, node))
	local result: Value? = nil
	if node.tag == "string" then
		local decoded = stringValue(node)
		if decoded ~= nil then
			result = literal("string", decoded)
		end
	elseif node.tag == "number" or node.tag == "integer" or node.tag == "unary" then
		local numeric = numberValue(node)
		if numeric ~= nil then
			result = literal("number", numeric)
		end
	elseif node.tag == "boolean" then
		result = literal("boolean", node.value)
	elseif node.tag == "nil" then
		result = literal("nil", nil)
	elseif node.tag == "cast" then
		local operand = node.operand
		local annotation = node.annotation
		if operand.tag == "string" and annotation.tag == "string" then
			local decoded = stringValue(operand)
			if decoded ~= nil and decoded == annotation.value.text then
				local casted = literal("string", decoded)
				casted.cast = true
				result = casted
			end
		end
	elseif node.tag == "table" then
		local fields: { [string]: Value } = {}
		local items: { Value } = {}
		local valid = true
		local named = 0
		for _, entry in node.entries do
			local key: string? = nil
			if entry.kind == "record" then
				key = entry.key.text
			elseif entry.kind == "general" then
				key = stringValue(entry.key)
				if key == nil then
					valid = false
					break
				end
			end
			local inner = Values.read(map, entry.value, scope)
			if inner.kind == "code" or inner.kind == "binding" then
				valid = false
				break
			end
			if key then
				fields[key :: string] = inner
				named += 1
			else
				table.insert(items, inner)
			end
		end
		if valid and (named == 0 or #items == 0) then
			local tableValue = literal("table", nil)
			tableValue.fields = if named > 0 then fields else nil
			tableValue.items = if #items > 0 then items else nil
			result = tableValue
		end
	end
	if result == nil then
		result = bindingOf(node, scope) or datatypeOf(node) or enumOf(node)
	end
	local fallback: Value = { kind = "code" }
	local value: Value = if result then result else fallback
	value.text = text
	return value
end

function Values.keyField(node: Cst.Expr): string?
	if node.tag ~= "function" or #node.parameters < 1 then
		return nil
	end
	local returned = singleReturn(node)
	if returned == nil then
		return nil
	end
	local path = pathOf(returned, node.parameters[1].name.text)
	if path and path ~= "" and not string.find(path, ".", 1, true) then
		return path
	end
	return nil
end

local function visualWidth(text: string): number
	local width = 0
	for _, code in utf8.codes(text) do
		width += if code == 9 then 4 else 1
	end
	return width
end

Values.visualWidth = visualWidth

local NO_ARGS: { Arg } = {}
local NO_VALUES: { Value } = {}

local function argsOf(value: Value): { Arg }
	return value.args or NO_ARGS
end

local function itemsOf(value: Value): { Value }
	return value.items or NO_VALUES
end

local function accessPath(root: string, path: string): string
	local parts = { root }
	for segment in string.gmatch(path, "[^%.]+") do
		if Values.isIdentifier(segment) then
			table.insert(parts, "." .. segment)
		else
			table.insert(parts, "[" .. Values.quote(segment) .. "]")
		end
	end
	return table.concat(parts)
end

local function keyText(key: string, style: Style): string
	if Values.isIdentifier(key) and not style.brackets then
		return key
	end
	return "[" .. Values.quote(key) .. "]"
end

local function sortedKeys(fields: { [string]: Value }): { string }
	local keys: { string } = {}
	for key in fields do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function Values.print(value: Value, style: Style, scope: Scope): string
	local kind = value.kind
	if kind == "string" or kind == "token" then
		local text = Values.quote(value.value :: string)
		if value.cast or (value.cast == nil and kind == "token" and style.cast) then
			return text .. " :: " .. text
		end
		return text
	elseif kind == "number" then
		return Values.number(value.value :: number)
	elseif kind == "boolean" then
		return if value.value then "true" else "false"
	elseif kind == "nil" then
		return "nil"
	elseif kind == "enum" then
		return "Enum." .. (value.enum :: string) .. "." .. (value.item :: string)
	elseif kind == "datatype" then
		local args: { string } = {}
		for _, argument in argsOf(value) do
			table.insert(args, if type(argument) == "number" then Values.number(argument) else Values.quote(argument))
		end
		return (value.type :: string) .. "." .. (value.constructor :: string) .. "(" .. table.concat(args, ", ") .. ")"
	elseif kind == "binding" then
		local root = if value.source == "item" then scope.item else scope.model
		if root == nil then
			error(
				if value.source == "item"
					then "an item binding needs a collection template"
					else "a model binding needs a view with a model parameter",
				0
			)
		end
		local path = value.path or ""
		if value.form == "direct" then
			return accessPath(root :: string, path)
		end
		local useName = scope.use or "use"
		local inner: string
		if value.source == "item" then
			inner = useName .. "(" .. (root :: string) .. ")"
			if path ~= "" then
				inner = accessPath(inner, path)
			end
		else
			inner = useName .. "(" .. accessPath(root :: string, path) .. ")"
		end
		local annotation = style.useAnnotation or ""
		return "function("
			.. useName
			.. annotation
			.. ")"
			.. style.newline
			.. style.indent
			.. style.unit
			.. "return "
			.. inner
			.. style.newline
			.. style.indent
			.. "end"
	elseif kind == "table" then
		local nested: Style = table.clone(style)
		nested.indent = style.indent .. style.unit
		local parts: { string } = {}
		local fields = value.fields
		if fields then
			for _, key in sortedKeys(fields) do
				table.insert(parts, keyText(key, style) .. " = " .. Values.print(fields[key], nested, scope))
			end
		end
		for _, item in itemsOf(value) do
			table.insert(parts, Values.print(item, nested, scope))
		end
		if #parts == 0 then
			return "{}"
		end
		local inline = "{ " .. table.concat(parts, ", ") .. " }"
		if not string.find(inline, "\n", 1, true) and style.column + visualWidth(inline) + 1 <= style.width then
			return inline
		end
		local lines = { "{" }
		for _, part in parts do
			table.insert(lines, nested.indent .. part .. ",")
		end
		table.insert(lines, style.indent .. "}")
		return table.concat(lines, style.newline)
	elseif kind == "code" then
		return value.text or "nil"
	end
	error("cannot print a value of kind " .. tostring(kind), 0)
end

function Values.json(value: Value): { [string]: unknown }
	local result: { [string]: unknown } = { kind = value.kind }
	for _, key in { "value", "cast", "set", "path", "source", "form", "type", "constructor", "enum", "item", "text" } do
		local field = ((value :: unknown) :: { [string]: unknown })[key]
		if field ~= nil then
			result[key] = field
		end
	end
	if value.args then
		result.args = table.clone(value.args)
	end
	if value.fields then
		local fields: { [string]: unknown } = {}
		for key, inner in value.fields do
			fields[key] = Values.json(inner)
		end
		result.fields = Wire.object(fields :: { [string]: Wire.Value })
	end
	if value.items then
		local items: { unknown } = {}
		for _, inner in value.items do
			table.insert(items, Values.json(inner))
		end
		result.items = items
	end
	return result
end

local INPUT_KINDS: { [string]: boolean } = {
	string = true,
	number = true,
	boolean = true,
	token = true,
	binding = true,
	datatype = true,
	enum = true,
	table = true,
}

function Values.fromJson(input: unknown, at: string?): (Value?, string?)
	local where = at or "value"
	if type(input) == "string" then
		return { kind = "string", value = input }, nil
	elseif type(input) == "number" then
		if input ~= input or input == math.huge or input == -math.huge then
			return nil, where .. " must be a finite number"
		end
		return { kind = "number", value = input }, nil
	elseif type(input) == "boolean" then
		return { kind = "boolean", value = input }, nil
	elseif type(input) ~= "table" then
		return nil, where .. " must be a string, number, boolean or value object"
	end
	local kind = Wire.text(input, "kind")
	if kind == nil or not INPUT_KINDS[kind] then
		return nil, where .. ".kind must be one of string, number, boolean, token, binding, datatype, enum or table"
	end
	local raw = Wire.field(input, "value")
	if kind == "string" or kind == "token" then
		if type(raw) ~= "string" then
			return nil, where .. ".value must be a string"
		end
		local cast = Wire.field(input, "cast")
		if cast ~= nil and type(cast) ~= "boolean" then
			return nil, where .. ".cast must be a boolean"
		end
		return { kind = kind :: ValueKind, value = raw, cast = cast :: boolean? }, nil
	elseif kind == "number" then
		if type(raw) ~= "number" then
			return nil, where .. ".value must be a number"
		end
		return Values.fromJson(raw, where)
	elseif kind == "boolean" then
		if type(raw) ~= "boolean" then
			return nil, where .. ".value must be a boolean"
		end
		return { kind = "boolean", value = raw }, nil
	elseif kind == "binding" then
		local path = Wire.text(input, "path")
		local source = Wire.text(input, "source") or "model"
		local form = Wire.text(input, "form") or "use"
		if path == nil or not string.match(path, "^[%w_]*[%w_%.]*$") or string.find(path, "%.%.") then
			return nil, where .. ".path must be a dotted model path such as stats.coins"
		end
		if path == "" and source == "model" then
			return nil, where .. ".path must name a model field"
		end
		if source ~= "model" and source ~= "item" then
			return nil, where .. '.source must be "model" or "item"'
		end
		if form ~= "use" and form ~= "direct" then
			return nil, where .. '.form must be "use" or "direct"'
		end
		local binding: Value = {
			kind = "binding",
			path = path,
			source = source :: "model" | "item",
			form = form :: "use" | "direct",
		}
		return binding, nil
	elseif kind == "datatype" then
		local typeName = Wire.text(input, "type")
		local constructorName = Wire.text(input, "constructor") or "new"
		local family = if typeName then CONSTRUCTORS[typeName] else nil
		if family == nil then
			local names: { string } = {}
			for name in CONSTRUCTORS do
				table.insert(names, name)
			end
			table.sort(names)
			return nil, where .. ".type must be one of " .. table.concat(names, ", ")
		end
		local arities = family[constructorName]
		if arities == nil then
			return nil, where .. ".constructor is not a supported " .. (typeName :: string) .. " constructor"
		end
		local args: { Arg } = {}
		for index, argument in Wire.list(Wire.field(input, "args")) do
			if type(argument) == "number" then
				if argument ~= argument or argument == math.huge or argument == -math.huge then
					return nil, where .. ".args[" .. index .. "] must be finite"
				end
				table.insert(args, argument)
			elseif type(argument) == "string" then
				table.insert(args, argument)
			else
				return nil, where .. ".args[" .. index .. "] must be a number or a string"
			end
		end
		if not table.find(arities, #args) then
			return nil,
				where
					.. ".args has the wrong number of arguments for "
					.. (typeName :: string)
					.. "."
					.. constructorName
		end
		return { kind = "datatype", type = typeName, constructor = constructorName, args = args }, nil
	elseif kind == "enum" then
		local enumName = Wire.text(input, "enum")
		local item = Wire.text(input, "item")
		if enumName == nil or item == nil or not Values.isIdentifier(enumName) or not Values.isIdentifier(item) then
			return nil, where .. " needs enum and item names, for example SortOrder and LayoutOrder"
		end
		return { kind = "enum", enum = enumName, item = item }, nil
	end
	local fieldsInput = Wire.field(input, "fields")
	local itemsInput = Wire.field(input, "items")
	local fields: { [string]: Value }? = nil
	local items: { Value }? = nil
	if fieldsInput ~= nil then
		if type(fieldsInput) ~= "table" then
			return nil, where .. ".fields must be an object"
		end
		local collected: { [string]: Value } = {}
		for key, inner in fieldsInput :: { [unknown]: unknown } do
			if type(key) == "userdata" then
				continue
			end
			if type(key) ~= "string" then
				return nil, where .. ".fields must be an object"
			end
			local parsed, problem = Values.fromJson(inner, where .. ".fields." .. key)
			if parsed == nil then
				return nil, problem
			end
			if parsed.kind == "binding" then
				return nil, where .. ".fields." .. key .. " cannot be a binding"
			end
			collected[key] = parsed
		end
		fields = collected
	end
	if itemsInput ~= nil then
		local collected: { Value } = {}
		for index, inner in Wire.list(itemsInput) do
			local parsed, problem = Values.fromJson(inner, where .. ".items[" .. index .. "]")
			if parsed == nil then
				return nil, problem
			end
			table.insert(collected, parsed)
		end
		items = collected
	end
	if fields and items and next(fields) ~= nil and #items > 0 then
		return nil, where .. " cannot mix fields and items"
	end
	return { kind = "table", fields = fields, items = items }, nil
end

return table.freeze(Values)
