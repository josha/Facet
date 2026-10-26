--!strict

local Types = require "./types"
local Document = require "./document"

type Node = Types.Node
type Literal = Types.Literal
type Library = Types.Library
type Value = Types.Value
type Record = { [string | number]: Literal }

local source = {}

local function before(a: string | number, b: string | number): boolean
	if type(a) == "number" and type(b) == "number" then
		return a < b
	elseif type(a) == "string" and type(b) == "string" then
		return a < b
	end
	return type(a) == "number"
end

local function literal(value: Literal): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "number" or type(value) == "boolean" then
		return tostring(value)
	end
	local keys: { string | number } = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, before)
	local pieces: { string } = {}
	for index, key in keys do
		local item = value[key]
		if key == index then
			table.insert(pieces, literal(item))
		elseif type(key) == "string" and string.match(key, "^[%a_][%w_]*$") then
			table.insert(pieces, key .. " = " .. literal(item))
		else
			table.insert(pieces, "[" .. literal(key) .. "] = " .. literal(item))
		end
	end
	return "{ " .. table.concat(pieces, ", ") .. " }"
end
source.literal = literal

local function contractLiteral(contract: Types.Contract): Literal
	local inputs: Record = {}
	for _, input in contract.inputs do
		local entry: Record = { id = input.id, kind = input.kind, type = input.type }
		local preview = input.preview
		if preview ~= nil then
			entry.preview = preview
		end
		local fields = input.fields
		if fields then
			local list: Record = {}
			for _, field in fields do
				local item: Record = { id = field.id, type = field.type }
				list[#list + 1] = item
			end
			entry.fields = list
		end
		inputs[#inputs + 1] = entry
	end
	local outputs: Record = {}
	for _, output in contract.outputs do
		local item: Record = { id = output.id }
		outputs[#outputs + 1] = item
	end
	local result: Record = { inputs = inputs, outputs = outputs }
	return result
end

local function base(library: Library, input: Types.Input): string
	if input.type == "number" then
		return "number"
	elseif input.type == "boolean" then
		return "boolean"
	elseif input.type == "list" then
		return "{ { [string]: unknown } }"
	elseif input.type == "record" then
		return "{ [string]: unknown }"
	elseif input.type == "slot" then
		return `() -> {library.returnType}`
	end
	return "string"
end

local function fieldType(library: Library, input: Types.Input): string
	local shape = base(library, input)
	if input.kind == "readable" then
		return `{library.readable}<{shape}>`
	elseif input.kind == "cell" then
		return `{library.cell}<{shape}>`
	end
	return if input.type == "slot" then `({shape})` else shape
end

export type EmitOptions = { name: string? }

function source.emit(value: Types.Document, library: Library, options: EmitOptions?): string
	local exported = if options then options.name else nil
	if exported ~= nil then
		assert(string.match(exported, "^[%a_][%w_]*$") ~= nil, "A component name is a Luau identifier")
	end
	Document.validate(value, library)
	local lines: { string } = { "--!strict", "" }
	for _, line in library.prelude do
		table.insert(lines, line)
	end
	table.insert(lines, "")
	table.insert(lines, "export type Props = {")
	for _, input in value.contract.inputs do
		table.insert(lines, `\t{input.id}: {fieldType(library, input)}?,`)
	end
	for _, output in value.contract.outputs do
		table.insert(lines, `\t{output.id}: ((...unknown) -> ())?,`)
	end
	table.insert(lines, "}")
	table.insert(lines, "")
	local header: Record = { name = value.name, contract = contractLiteral(value.contract) }
	table.insert(lines, "local design = " .. literal(header))
	table.insert(lines, "")
	local referenced: { [string]: boolean } = {}
	local referencedIds: { string } = {}
	local function collect(node: Node)
		for _, property in node.props do
			local target = property.node
			if target ~= nil and not referenced[target] then
				referenced[target] = true
				table.insert(referencedIds, target)
			end
		end
		for _, child in node.children do
			collect(child)
		end
	end
	collect(value.root)
	table.sort(referencedIds)
	local function expression(property: Value): string
		local target = property.node
		if target ~= nil then
			return `refs.{target}`
		end
		local current, input, item, output, token =
			property.literal, property.input, property.item, property.output, property.token
		if current ~= nil then
			return literal(current)
		elseif input then
			return `props.{input}`
		elseif item then
			return `function(use) return use(current).{item} end`
		elseif output then
			local args = property.args
			local passed = property.fields
			local packed: Record = {}
			if args then
				for index, argument in args do
					packed[index] = argument
				end
			end
			local list = if args then string.sub(literal(packed), 3, -3) else if passed then "" else "..."
			if passed then
				local reads: { string } = {}
				for _, name in passed do
					table.insert(reads, `current:peek().{name}`)
				end
				list = if list == "" then table.concat(reads, ", ") else `{list}, {table.concat(reads, ", ")}`
			end
			return `function(...) if props.{output} then props.{output}({list}) end end`
		end
		local call = assert(library.token, `{library.name} has no theme tokens`)
		return `{call}({literal(assert(token))})`
	end
	local emitNode: (node: Node, depth: number) -> string
	local function emit(node: Node, depth: number): string
		local built = emitNode(node, depth)
		if referenced[node.id] then
			return `capture("{node.id}", {built})`
		end
		return built
	end
	emitNode = function(node: Node, depth: number): string
		local kind = assert(library.kinds[node.kind])
		local indent = string.rep("\t", depth)
		local nameField = node.nameField
		local body = {
			if nameField ~= nil
				then `{kind.call}(tostring(current:peek().{nameField})) ` .. "{"
				else `{kind.call} {literal(node.name)} ` .. "{",
		}
		local keys: { string } = {}
		for key in node.props do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			table.insert(body, `{indent}\t{key} = {expression(node.props[key])},`)
		end
		local bind, template = node.bind, node.children[1]
		if kind.children == "slot" then
			if template then
				table.insert(body, `{indent}\t{assert(kind.slot)} = function() return {emit(template, depth + 1)} end,`)
			end
		elseif kind.children == "template" then
			if bind and template then
				table.insert(body, `{indent}\t{assert(kind.source)} = props.{bind.from},`)
				local keyProp = kind.key
				if keyProp then
					table.insert(body, `{indent}\t{keyProp} = {literal(bind.key)},`)
				end
				table.insert(
					body,
					`{indent}\t{assert(kind.template)} = function(current) return {emit(template, depth + 1)} end,`
				)
			end
		else
			for _, child in node.children do
				table.insert(body, `{indent}\t{emit(child, depth + 1)},`)
			end
		end
		table.insert(body, indent .. "}")
		return table.concat(body, "\n")
	end
	local signature = `({library.parameter}: {library.parameterType}, props: Props): {library.returnType}`
	table.insert(lines, if exported then `local function {exported}{signature}` else `return function{signature}`)
	if #referencedIds > 0 then
		local newCell = assert(library.newCell, `{library.name} cannot reference nodes; it names no cell constructor`)
		local cells: { string } = {}
		for _, id in referencedIds do
			table.insert(cells, `{id} = {newCell}(nil)`)
		end
		table.insert(lines, "\tlocal refs = { " .. table.concat(cells, ", ") .. " }")
		table.insert(lines, "\tlocal function capture(id, node) refs[id]:set(node) return node end")
	end
	table.insert(lines, `\treturn {emit(value.root, 1)}`)
	table.insert(lines, "end")
	if exported then
		table.insert(lines, "")
		table.insert(lines, `return {exported}`)
	end
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

type Token = { kind: "name" | "string" | "number" | "symbol", text: string }

local function tokenize(code: string): { Token }
	local tokens: { Token } = {}
	local at = 1
	while at <= #code do
		local character = string.sub(code, at, at)
		if string.match(character, "%s") then
			at += 1
		elseif string.sub(code, at, at + 1) == "--" then
			local stop = string.find(code, "\n", at, true)
			at = if stop then stop + 1 else #code + 1
		elseif character == '"' then
			local stop = at + 1
			while stop <= #code and string.sub(code, stop, stop) ~= '"' do
				stop += if string.sub(code, stop, stop) == "\\" then 2 else 1
			end
			do
				local token: Token = { kind = "string", text = string.sub(code, at, stop) }
				table.insert(tokens, token)
			end
			at = stop + 1
		elseif string.match(character, "[%a_]") then
			local word = assert(string.match(code, "^[%w_]+", at))
			do
				local token: Token = { kind = "name", text = word }
				table.insert(tokens, token)
			end
			at += #word
		elseif string.match(code, "^%-?%d", at) then
			local number = assert(string.match(code, "^%-?[%d%.eE]+", at))
			do
				local token: Token = { kind = "number", text = number }
				table.insert(tokens, token)
			end
			at += #number
		elseif string.sub(code, at, at + 2) == "..." then
			do
				local token: Token = { kind = "symbol", text = "..." }
				table.insert(tokens, token)
			end
			at += 3
		else
			do
				local token: Token = { kind = "symbol", text = character }
				table.insert(tokens, token)
			end
			at += 1
		end
	end
	return tokens
end

local function unquote(text: string): string
	local inner = string.sub(text, 2, -2)
	return (
		string.gsub(inner, "\\(.)", function(escaped: string): string
			return if escaped == "n" then "\n" elseif escaped == "t" then "\t" else escaped
		end)
	)
end

local function text(record: Record, key: string): string
	local found = record[key]
	assert(type(found) == "string", `The design header needs text at {key}`)
	return found
end

local function list(record: Record, key: string): { Record }
	local found = record[key]
	local result: { Record } = {}
	if found == nil then
		return result
	end
	assert(type(found) == "table", `The design header needs a list at {key}`)
	for _, entry in found do
		assert(type(entry) == "table", `The design header list {key} holds records`)
		table.insert(result, entry)
	end
	return result
end

local function inputKind(name: string): Types.InputKind
	if name == "readable" then
		return "readable"
	elseif name == "cell" then
		return "cell"
	end
	assert(name == "value", `Unknown input kind {name}`)
	return "value"
end

local function inputType(name: string): Types.InputType
	if name == "number" then
		return "number"
	elseif name == "boolean" then
		return "boolean"
	elseif name == "color" then
		return "color"
	elseif name == "image" then
		return "image"
	elseif name == "list" then
		return "list"
	elseif name == "record" then
		return "record"
	elseif name == "slot" then
		return "slot"
	end
	assert(name == "string", `Unknown input type {name}`)
	return "string"
end

local function contractOf(header: Record): Types.Contract
	local found = header.contract
	assert(type(found) == "table", "The design header needs a contract")
	local inputs: { Types.Input } = {}
	for _, entry in list(found, "inputs") do
		local fields: { Types.ItemField }? = nil
		if entry.fields ~= nil then
			local declared: { Types.ItemField } = {}
			for _, field in list(entry, "fields") do
				table.insert(declared, { id = text(field, "id"), type = inputType(text(field, "type")) })
			end
			fields = declared
		end
		table.insert(inputs, {
			id = text(entry, "id"),
			kind = inputKind(text(entry, "kind")),
			type = inputType(text(entry, "type")),
			preview = entry.preview,
			fields = fields,
		})
	end
	local outputs: { Types.Output } = {}
	for _, entry in list(found, "outputs") do
		table.insert(outputs, { id = text(entry, "id") })
	end
	return { inputs = inputs, outputs = outputs }
end

function source.parse(code: string, library: Library): Types.Document
	local tokens = tokenize(code)
	local at = 1
	local function peek(offset: number?): string
		local token = tokens[at + (offset or 0)]
		return if token then token.text else ""
	end
	local function take(expected: string?): Token
		local token = assert(tokens[at], "The design source ended early")
		assert(expected == nil or token.text == expected, `Expected {expected or ""} but found {token.text}`)
		at += 1
		return token
	end
	local function name(): string
		local token = take()
		assert(token.kind == "name", `Expected a name but found {token.text}`)
		return token.text
	end
	local calls: { [string]: string } = {}
	for kindName, kind in library.kinds do
		calls[kind.call] = kindName
	end
	local function plain(): Literal
		local token = take()
		if token.kind == "string" then
			return unquote(token.text)
		elseif token.kind == "number" then
			return assert(tonumber(token.text), "Invalid number")
		elseif token.text == "true" or token.text == "false" then
			return token.text == "true"
		end
		assert(token.text == "{", `Unexpected {token.text}`)
		local result: Record = {}
		local index = 0
		while peek() ~= "}" do
			local key: string | number
			if peek() == "[" then
				take "["
				local raw = plain()
				if type(raw) == "string" or type(raw) == "number" then
					key = raw
				else
					error "Table keys are text or numbers"
				end
				take "]"
				take "="
			elseif tokens[at] and tokens[at].kind == "name" and peek(1) == "=" then
				key = name()
				take "="
			else
				index += 1
				key = index
			end
			result[key] = plain()
			if peek() == "," then
				take ","
			end
		end
		take "}"
		return result
	end
	local nextId = 1
	local node: () -> Node
	local function dotted(): string
		local path = name()
		while peek() == "." do
			take "."
			path ..= "." .. name()
		end
		return path
	end
	local function value(): (Value?, Node?)
		if peek() == "refs" then
			take "refs"
			take "."
			return { node = name() }, nil
		elseif peek() == "props" then
			take "props"
			take "."
			return { input = name() }, nil
		elseif peek() == "function" then
			take "function"
			take "("
			if peek() == "use" then
				take "use"
				take ")"
				take "return"
				take "use"
				take "("
				take "current"
				take ")"
				take "."
				local field = name()
				take "end"
				return { item = field }, nil
			elseif peek() == "current" or peek() == ")" then
				if peek() == "current" then
					take "current"
				end
				take ")"
				take "return"
				local child = node()
				take "end"
				return nil, child
			end
			take "..."
			take ")"
			take "if"
			take "props"
			take "."
			local id = name()
			take "then"
			take "props"
			take "."
			take(id)
			take "("
			local args: { Literal }? = nil
			local passed: { string }? = nil
			if peek() == "..." then
				take "..."
			else
				local supplied: { Literal } = {}
				local fields: { string } = {}
				while peek() ~= ")" do
					if peek() == "current" then
						take "current"
						take ":"
						take "peek"
						take "("
						take ")"
						take "."
						table.insert(fields, name())
					else
						table.insert(supplied, plain())
					end
					if peek() == "," then
						take ","
					end
				end
				if #supplied > 0 or #fields == 0 then
					args = supplied
				end
				if #fields > 0 then
					passed = fields
				end
			end
			take ")"
			take "end"
			take "end"
			return { output = id, args = args, fields = passed }, nil
		end
		local tokenCall = library.token
		if tokenCall and tokens[at] and tokens[at].kind == "name" then
			local start = at
			if dotted() == tokenCall then
				take "("
				local tokenName = plain()
				take ")"
				assert(type(tokenName) == "string", "Token names are text")
				return { token = tokenName }, nil
			end
			at = start
		end
		return { literal = plain() }, nil
	end
	local captured: { [string]: string } = {}
	node = function(): Node
		if peek() == "capture" then
			take "capture"
			take "("
			local source = take()
			assert(source.kind == "string", "A captured node names its id")
			take ","
			local inner = node()
			take ")"
			captured[unquote(source.text)] = inner.id
			return inner
		end
		local call = dotted()
		local kindName = assert(calls[call], `{call} is not a {library.name} kind`)
		local kind = library.kinds[kindName]
		local templated = kind.children == "template"
		local nodeName = take()
		local nameField: string? = nil
		local nodeTitle: string
		if nodeName.kind == "symbol" and nodeName.text == "(" then
			take "tostring"
			take "("
			take "current"
			take ":"
			take "peek"
			take "("
			take ")"
			take "."
			nameField = name()
			take ")"
			take ")"
			nodeTitle = kindName
		else
			assert(nodeName.kind == "string", "Every node needs a name")
			nodeTitle = unquote(nodeName.text)
		end
		local result: Node = {
			id = `n{nextId}`,
			kind = kindName,
			name = nodeTitle,
			nameField = nameField,
			props = {},
			children = {},
		}
		nextId += 1
		take "{"
		local from: string?, key: string? = nil, nil
		while peek() ~= "}" do
			if tokens[at] and tokens[at].kind == "name" and peek(1) == "=" then
				local prop = name()
				take "="
				local property, template = value()
				if template then
					assert(
						prop == (if kind.children == "slot" then kind.slot else kind.template),
						`{prop} cannot hold a template`
					)
					table.insert(result.children, template)
				elseif property and templated and prop == kind.source then
					from = assert(property.input, `{prop} must read a list input`)
				elseif property and templated and prop == kind.key then
					local current = property.literal
					assert(type(current) == "string", "Item keys are text")
					key = current
				elseif property then
					result.props[prop] = property
				end
			else
				table.insert(result.children, node())
			end
			if peek() == "," then
				take ","
			end
		end
		take "}"
		if from then
			result.bind = { from = from, key = key or "id" }
		end
		return result
	end
	while not (peek() == "local" and peek(1) == "design") do
		take()
	end
	take "local"
	take "design"
	take "="
	local header = plain()
	assert(type(header) == "table", "The design header is a table")
	while not ((peek() == "return" or peek() == "local") and peek(1) == "function") do
		take()
	end
	take()
	take "function"
	while not (peek() == "return" and peek(1) ~= "node") do
		take()
	end
	take "return"
	local root = node()
	take "end"
	local function remap(current: Node)
		for _, property in current.props do
			local target = property.node
			if target ~= nil then
				property.node = assert(captured[target], `refs.{target} names no captured node`)
			end
		end
		for _, child in current.children do
			remap(child)
		end
	end
	remap(root)
	return Document.validate({
		schema = "compose-design/1",
		name = text(header, "name"),
		library = library.name,
		nextId = nextId,
		contract = contractOf(header),
		root = root,
	}, library)
end

return source
