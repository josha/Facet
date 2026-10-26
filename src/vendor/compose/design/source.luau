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
	if #keys == 0 then
		return "{}"
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

local WIDTH = 120

local function layoutHeader(header: Literal): string
	local function lay(current: Literal, depth: number, used: number): string
		if type(current) ~= "table" then
			return literal(current)
		end
		local keys: { string | number } = {}
		for key in current do
			table.insert(keys, key)
		end
		if #keys == 0 then
			return "{}"
		end
		table.sort(keys, before)
		local single = literal(current)
		if used + #single <= WIDTH then
			return single
		end
		local lines = { "{" }
		for index, key in keys do
			local prefix = if key == index
				then ""
				elseif type(key) == "string" and string.match(key, "^[%a_][%w_]*$") then key .. " = "
				else "[" .. literal(key) .. "] = "
			local width = (depth + 1) * 4 + #prefix + 1
			table.insert(lines, string.rep("\t", depth + 1) .. prefix .. lay(current[key], depth + 1, width) .. ",")
		end
		table.insert(lines, string.rep("\t", depth) .. "}")
		return table.concat(lines, "\n")
	end
	return lay(header, 0, 16)
end

local function datatypeLiteral(datatype: string, value: Literal): string
	if string.sub(datatype, 1, 5) == "Enum." then
		return `{datatype}.{tostring(value)}`
	end
	local parts: { string } = {}
	if type(value) == "table" then
		for _, component in value do
			table.insert(parts, literal(component))
		end
	end
	return `{datatype}.new({table.concat(parts, ", ")})`
end

local function contractLiteral(contract: Types.Contract): Literal
	local inputs: Record = {}
	for _, input in contract.inputs do
		local entry: Record = { id = input.id, kind = input.kind, type = input.type }
		local preview = input.preview
		if preview ~= nil then
			entry.preview = preview
		end
		if input.required then
			entry.required = true
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
		local args = output.args
		if args then
			local list: Record = {}
			for index, argument in args do
				list[index] = argument
			end
			item.args = list
		end
		outputs[#outputs + 1] = item
	end
	local result: Record = { inputs = inputs, outputs = outputs }
	return result
end

local function stateLiteral(state: { Types.State }): Literal
	local list: Record = {}
	for index, entry in state do
		local item: Record = { id = entry.id, type = entry.type, initial = entry.initial }
		list[index] = item
	end
	return list
end

local function scalar(library: Library, kind: string): string
	if kind == "number" then
		return "number"
	elseif kind == "boolean" then
		return "boolean"
	elseif kind == "list" then
		return "{ { [string]: unknown } }"
	elseif kind == "record" then
		return "{ [string]: unknown }"
	elseif kind == "slot" then
		return `() -> {library.returnType}`
	end
	return "string"
end

local function rowType(library: Library, fields: { Types.ItemField }): string
	local pieces: { string } = {}
	for _, field in fields do
		table.insert(pieces, `{field.id}: {scalar(library, field.type)}`)
	end
	return "{ " .. table.concat(pieces, ", ") .. " }"
end

local function base(library: Library, input: Types.Input): string
	local fields = input.fields
	if fields and #fields > 0 then
		if input.type == "list" then
			return "{ " .. rowType(library, fields) .. " }"
		elseif input.type == "record" then
			return rowType(library, fields)
		end
	end
	return scalar(library, input.type)
end

local function outputType(library: Library, output: Types.Output): string
	local args = output.args
	if args == nil then
		return "(...unknown) -> ()"
	end
	local pieces: { string } = {}
	for _, argument in args do
		table.insert(pieces, scalar(library, argument))
	end
	return "(" .. table.concat(pieces, ", ") .. ") -> ()"
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

export type EmitOptions = {
	name: string?,
	rowFunctions: boolean?,
	controls: string?,
	propsType: string?,
	prelude: { string }?,
}

function source.emit(value: Types.Document, library: Library, options: EmitOptions?): string
	local exported = if options then options.name else nil
	if exported ~= nil then
		assert(string.match(exported, "^[%a_][%w_]*$") ~= nil, "A component name is a Luau identifier")
	end
	Document.validate(value, library)
	local controls = if options then options.controls else nil
	local propsType = if options then options.propsType else nil
	local lines: { string } = { "--!strict", "" }
	for _, line in library.prelude do
		table.insert(lines, line)
	end
	local extra = if options then options.prelude else nil
	if extra then
		for _, line in extra do
			table.insert(lines, line)
		end
	end
	if controls ~= nil then
		table.insert(lines, controls)
	end
	table.insert(lines, "")
	if propsType == nil and #value.contract.inputs == 0 and #value.contract.outputs == 0 then
		table.insert(lines, "export type Props = {}")
		table.insert(lines, "")
	elseif propsType == nil then
		table.insert(lines, "export type Props = {")
		for _, input in value.contract.inputs do
			local optional = if input.required then "" else "?"
			table.insert(lines, `\t{input.id}: {fieldType(library, input)}{optional},`)
		end
		for _, output in value.contract.outputs do
			table.insert(lines, `\t{output.id}: ({outputType(library, output)})?,`)
		end
		table.insert(lines, "}")
		table.insert(lines, "")
	end
	local header: Record = { name = value.name, contract = contractLiteral(value.contract) }
	local state = value.state
	if state and #state > 0 then
		header.state = stateLiteral(state)
	end
	table.insert(lines, "local _design = " .. layoutHeader(header))
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
	local rowFunctions = options ~= nil and options.rowFunctions == true
	local rowDefinitions: { string } = {}
	local rowNames: { [string]: boolean } = { props = true, state = true, refs = true, capture = true }
	rowNames[library.parameter] = true
	local emitNode: (node: Node, depth: number) -> string
	local emit: (node: Node, depth: number) -> string
	local function tabs(depth: number): string
		return string.rep("\t", depth)
	end
	local function callback(output: string, list: string, depth: number): string
		return `function(...)\n{tabs(depth + 1)}if props.{output} then\n{tabs(depth + 2)}props.{output}({list})\n`
			.. `{tabs(depth + 1)}end\n{tabs(depth)}end`
	end
	local function returning(params: string, body: string, depth: number): string
		return `function({params})\n{tabs(depth + 1)}return {body}\n{tabs(depth)}end`
	end
	local function rowFunction(template: Node, depth: number): string
		if not rowFunctions then
			return returning("current", emit(template, depth + 1), depth)
		end
		local base = string.gsub(template.name, "[^%w_]", "")
		if not string.match(base, "^%u") then
			base = "Row" .. base
		elseif not string.match(base, "Row$") then
			base ..= "Row"
		end
		local name = base
		local suffix = 1
		while rowNames[name] do
			suffix += 1
			name = base .. tostring(suffix)
		end
		rowNames[name] = true
		table.insert(rowDefinitions, `\tlocal function {name}(current)\n\t\treturn {emit(template, 2)}\n\tend`)
		return name
	end
	local function layout(current: Literal, depth: number, used: number): string
		if type(current) ~= "table" then
			return literal(current)
		end
		local output = current["$output"]
		if type(output) == "string" then
			return callback(output, "...", depth)
		end
		local keys: { string | number } = {}
		for key in current do
			table.insert(keys, key)
		end
		if #keys == 0 then
			return "{}"
		end
		table.sort(keys, before)
		local prefixes: { string } = {}
		for index, key in keys do
			if key == index then
				prefixes[index] = ""
			elseif type(key) == "string" and string.match(key, "^[%a_][%w_]*$") then
				prefixes[index] = key .. " = "
			else
				prefixes[index] = "[" .. literal(key) .. "] = "
			end
		end
		local flat: { string } = {}
		local fits = true
		for index, key in keys do
			local piece = layout(current[key], depth, 0)
			if string.find(piece, "\n", 1, true) then
				fits = false
				break
			end
			flat[index] = prefixes[index] .. piece
		end
		if fits then
			local single = "{ " .. table.concat(flat, ", ") .. " }"
			if used + #single <= WIDTH then
				return single
			end
		end
		local lines = { "{" }
		for index, key in keys do
			local prefix = prefixes[index]
			local width = (depth + 1) * 4 + #prefix + 1
			table.insert(lines, `{tabs(depth + 1)}{prefix}{layout(current[key], depth + 1, width)},`)
		end
		table.insert(lines, tabs(depth) .. "}")
		return table.concat(lines, "\n")
	end
	local function expression(property: Value, depth: number, used: number): string
		local target = property.node
		if target ~= nil then
			return `refs.{target}`
		end
		local stateId = property.state
		if stateId ~= nil then
			return `state.{stateId}`
		end
		local current, input, item, output, token =
			property.literal, property.input, property.item, property.output, property.token
		if current ~= nil then
			return layout(current, depth, used)
		elseif input then
			return `props.{input}`
		elseif item then
			return returning("use", `use(current).{item}`, depth)
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
			return callback(output, list, depth)
		end
		local call = assert(library.token, `{library.name} has no theme tokens`)
		return `{call} {literal(assert(token))}`
	end
	emit = function(node: Node, depth: number): string
		if referenced[node.id] then
			local inner = tabs(depth + 1)
			return `capture(\n{inner}"{node.id}",\n{inner}{emitNode(node, depth + 1)}\n{tabs(depth)})`
		end
		return emitNode(node, depth)
	end
	emitNode = function(node: Node, depth: number): string
		local kind = assert(library.kinds[node.kind])
		local inner = tabs(depth + 1)
		local nameField, nameInput = node.nameField, node.nameInput
		local opening
		if nameField ~= nil then
			opening = `{kind.call}(tostring(current:peek().{nameField})) `
		elseif nameInput ~= nil then
			local declared = assert(Document.input(value, nameInput))
			opening = if declared.required
				then `{kind.call}(props.{nameInput}) `
				else `{kind.call}(props.{nameInput} or {literal(node.name)}) `
		else
			opening = `{kind.call} {literal(node.name)} `
		end
		local body: { string } = {}
		local keys: { string } = {}
		for key in node.props do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			local property = node.props[key]
			local field = kind.fields[key]
			local current = property.literal
			local datatype: string? = if field then field.datatype else nil
			local written = expression(property, depth + 1, (depth + 1) * 4 + #key + 4)
			if current ~= nil and datatype ~= nil then
				written = datatypeLiteral(datatype, current)
			end
			table.insert(body, `{inner}{key} = {written},`)
		end
		local bind, template = node.bind, node.children[1]
		if kind.children == "slot" then
			if template then
				table.insert(
					body,
					`{inner}{assert(kind.slot)} = {returning("", emit(template, depth + 2), depth + 1)},`
				)
			end
		elseif kind.children == "template" then
			if bind and template then
				table.insert(body, `{inner}{assert(kind.source)} = props.{bind.from},`)
				local keyProp = kind.key
				if keyProp then
					table.insert(body, `{inner}{keyProp} = {literal(bind.key)},`)
				end
				table.insert(body, `{inner}{assert(kind.template)} = {rowFunction(template, depth + 1)},`)
			end
		else
			local rowId = if bind then bind.row or (if template then template.id else nil) else nil
			for _, child in node.children do
				local condition = child.when
				if bind and child.id == rowId then
					local keyedCall = assert(library.keyed)
					local field = tabs(depth + 2)
					table.insert(body, `{inner}{keyedCall} ` .. "{")
					table.insert(body, `{field}from = props.{bind.from},`)
					table.insert(body, `{field}key = {returning("row", "row." .. bind.key, depth + 2)},`)
					table.insert(body, `{field}render = {rowFunction(child, depth + 2)},`)
					table.insert(body, `{inner}},`)
				elseif condition == nil then
					table.insert(body, `{inner}{emit(child, depth + 1)},`)
				else
					local showCall = assert(library.show)
					local source
					if Document.stateOf(value, condition) ~= nil then
						source = `state.{condition}`
					elseif assert(Document.input(value, condition)).kind == "value" then
						source = returning("", `props.{condition} == true`, depth + 1)
					else
						source = `props.{condition}`
					end
					local shown = returning("", emit(child, depth + 2), depth + 1)
					table.insert(body, `{inner}{showCall}({source}, {shown}),`)
				end
			end
		end
		if #body == 0 then
			return opening .. "{}"
		end
		return opening .. "{\n" .. table.concat(body, "\n") .. "\n" .. tabs(depth) .. "}"
	end
	local propsName = propsType or "Props"
	local signature = if controls ~= nil
		then `(props: {propsName}): {library.returnType}`
		else `({library.parameter}: {library.parameterType}, props: {propsName}): {library.returnType}`
	table.insert(lines, if exported then `local function {exported}{signature}` else `return function{signature}`)
	local rootSource = emit(value.root, 1)
	local readsState = string.find(rootSource, "state.", 1, true) ~= nil
	for _, definition in rowDefinitions do
		readsState = readsState or string.find(definition, "state.", 1, true) ~= nil
	end
	if #referencedIds > 0 then
		local newCell = assert(library.newCell, `{library.name} cannot reference nodes; it names no cell constructor`)
		local cells: { string } = {}
		for _, id in referencedIds do
			table.insert(cells, `{id} = {newCell}(nil)`)
		end
		table.insert(lines, "\tlocal refs = { " .. table.concat(cells, ", ") .. " }")
		table.insert(lines, "\tlocal function capture(id, node)")
		table.insert(lines, "\t\trefs[id]:set(node)")
		table.insert(lines, "\t\treturn node")
		table.insert(lines, "\tend")
	end
	if state and #state > 0 and readsState then
		local newCell = assert(library.newCell, `{library.name} cannot hold state; it names no cell constructor`)
		local cells: { string } = {}
		for _, entry in state do
			table.insert(cells, `{entry.id} = {newCell}({literal(entry.initial)})`)
		end
		table.insert(lines, "\tlocal state = { " .. table.concat(cells, ", ") .. " }")
	end
	for _, definition in rowDefinitions do
		table.insert(lines, definition)
	end
	table.insert(lines, `\treturn {rootSource}`)
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

local function stateFrom(header: Record): { Types.State }?
	if header.state == nil then
		return nil
	end
	local state: { Types.State } = {}
	for _, entry in list(header, "state") do
		local initial = entry.initial
		assert(initial ~= nil, "State needs an initial value")
		table.insert(state, { id = text(entry, "id"), type = inputType(text(entry, "type")), initial = initial })
	end
	return state
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
			required = if entry.required == true then true else nil,
		})
	end
	local outputs: { Types.Output } = {}
	for _, entry in list(found, "outputs") do
		local args: { Types.InputType }? = nil
		local declared = entry.args
		if declared ~= nil then
			assert(type(declared) == "table", "Output arguments are a list")
			local typed: { Types.InputType } = {}
			for _, argument in declared do
				assert(type(argument) == "string", "Output arguments name input types")
				table.insert(typed, inputType(argument))
			end
			args = typed
		end
		table.insert(outputs, { id = text(entry, "id"), args = args })
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
	local rows: { [string]: Node } = {}
	local function plain(): Literal
		if peek() == "function" then
			take "function"
			take "("
			take "..."
			take ")"
			take "if"
			take "props"
			take "."
			local output = name()
			take "then"
			take "props"
			take "."
			take(output)
			take "("
			take "..."
			take ")"
			take "end"
			take "end"
			local marker: Record = { ["$output"] = output }
			return marker
		end
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
		local bare = tokens[at]
		if bare and bare.kind == "name" and rows[bare.text] ~= nil and (peek(1) == "," or peek(1) == "}") then
			take()
			return nil, rows[bare.text]
		end
		if peek() == "state" and peek(1) == "." then
			take "state"
			take "."
			return { state = name() }, nil
		elseif peek() == "refs" then
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
		if tokens[at] and tokens[at].kind == "name" and peek(1) == "." then
			local start = at
			local path = dotted()
			local item = string.match(path, "^Enum%.[%w_]+%.([%w_]+)$")
			if item ~= nil then
				return { literal = item }, nil
			elseif string.match(path, "^[%w_]+%.new$") and peek() == "(" then
				take "("
				local components: Record = {}
				while peek() ~= ")" do
					components[#components + 1] = plain()
					if peek() == "," then
						take ","
					end
				end
				take ")"
				return { literal = components }, nil
			end
			at = start
		end
		local tokenCall = library.token
		if tokenCall and tokens[at] and tokens[at].kind == "name" then
			local start = at
			if dotted() == tokenCall then
				local wrapped = peek() == "("
				if wrapped then
					take "("
				end
				local tokenName = plain()
				if wrapped then
					take ")"
				end
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
		local nameInput: string? = nil
		if nodeName.kind == "symbol" and nodeName.text == "(" and peek() == "props" then
			take "props"
			take "."
			nameInput = name()
			nodeTitle = kindName
			if peek() == "or" then
				take "or"
				local fallback = take()
				assert(fallback.kind == "string", "A named node falls back to text")
				nodeTitle = unquote(fallback.text)
			end
			take ")"
		elseif nodeName.kind == "symbol" and nodeName.text == "(" then
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
			nameInput = nameInput,
			props = {},
			children = {},
		}
		nextId += 1
		take "{"
		local from: string?, key: string? = nil, nil
		local rowId: string? = nil
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
				local start = at
				local lead = if tokens[at] and tokens[at].kind == "name" then dotted() else ""
				if library.show ~= nil and lead == library.show then
					take "("
					local condition: string
					if peek() == "function" then
						take "function"
						take "("
						take ")"
						take "return"
						take "props"
						take "."
						condition = name()
						take "="
						take "="
						take "true"
						take "end"
					else
						local holder = name()
						assert(holder == "props" or holder == "state", "A shown node reads an input or state")
						take "."
						condition = name()
					end
					take ","
					take "function"
					take "("
					take ")"
					take "return"
					local shown = node()
					take "end"
					take ")"
					shown.when = condition
					table.insert(result.children, shown)
				elseif library.keyed ~= nil and lead == library.keyed then
					take "{"
					take "from"
					take "="
					take "props"
					take "."
					local list = name()
					take ","
					take "key"
					take "="
					take "function"
					take "("
					take "row"
					take ")"
					take "return"
					take "row"
					take "."
					local itemKey = name()
					take "end"
					take ","
					take "render"
					take "="
					local row: Node
					if peek() == "function" then
						take "function"
						take "("
						take "current"
						take ")"
						take "return"
						row = node()
						take "end"
					else
						local rowName = name()
						row = assert(rows[rowName], `{rowName} is not a row function`)
					end
					if peek() == "," then
						take ","
					end
					take "}"
					from, key, rowId = list, itemKey, row.id
					table.insert(result.children, row)
				else
					at = start
					table.insert(result.children, node())
				end
			end
			if peek() == "," then
				take ","
			end
		end
		take "}"
		if from then
			local row = if rowId ~= nil and #result.children > 1 then rowId else nil
			result.bind = { from = from, key = key or "id", row = row }
		end
		return result
	end
	while not (peek() == "local" and (peek(1) == "design" or peek(1) == "_design")) do
		take()
	end
	take "local"
	take()
	take "="
	local header = plain()
	assert(type(header) == "table", "The design header is a table")
	while not ((peek() == "return" or peek() == "local") and peek(1) == "function") do
		take()
	end
	take()
	take "function"
	while not (peek() == "return" and peek(1) ~= "node") do
		if peek() == "local" and peek(1) == "function" and peek(2) ~= "capture" then
			take "local"
			take "function"
			local rowName = name()
			take "("
			take "current"
			take ")"
			take "return"
			rows[rowName] = node()
			take "end"
		else
			take()
		end
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
		state = stateFrom(header),
		root = root,
	}, library)
end

return source
