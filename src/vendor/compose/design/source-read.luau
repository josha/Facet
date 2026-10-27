--!strict

local Types = require "./types"
local Datatype = require "./datatype"
local Document = require "./document"

type Node = Types.Node
type Literal = Types.Literal
type Library = Types.Library
type Value = Types.Value
type Record = { [string | number]: Literal }

local source = {}

type Token = { kind: "name" | "string" | "number" | "symbol", text: string }

local function tokenize(code: string): { Token }
	local tokens: { Token } = {}
	local function push(kind: "name" | "string" | "number" | "symbol", text: string)
		table.insert(tokens, { kind = kind, text = text })
	end
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
			push("string", string.sub(code, at, stop))
			at = stop + 1
		elseif string.match(character, "[%a_]") then
			local word = assert(string.match(code, "^[%w_]+", at))
			push("name", word)
			at += #word
		elseif string.match(code, "^%-?%d", at) then
			local number = assert(string.match(code, "^%-?[%d%.eE]+", at))
			push("number", number)
			at += #number
		elseif string.sub(code, at, at + 2) == "..." then
			push("symbol", "...")
			at += 3
		else
			push("symbol", character)
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

local function readLiteral(
	tokens: { Token },
	start: number,
	callback: ((at: number) -> (Literal, number))?
): (Literal, number)
	local at = start
	local function peek(offset: number?): string
		local token = tokens[at + (offset or 0)]
		return if token then token.text else ""
	end
	local function take(expected: string?): Token
		local token = assert(tokens[at], "The value ended early")
		assert(expected == nil or token.text == expected, `Expected {expected or ""} but found {token.text}`)
		at += 1
		return token
	end
	local function read(): Literal
		local ahead = tokens[at]
		local named = ahead ~= nil and ahead.kind == "name" and ahead.text ~= "true" and ahead.text ~= "false"
		if callback ~= nil and (peek() == "function" or named) then
			local marker, after = callback(at)
			at = after
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
				local raw = read()
				if type(raw) == "string" or type(raw) == "number" then
					key = raw
				else
					error "Table keys are text or numbers"
				end
				take "]"
				take "="
			elseif tokens[at] and tokens[at].kind == "name" and peek(1) == "=" then
				key = take().text
				take "="
			else
				index += 1
				key = index
			end
			result[key] = read()
			if peek() == "," then
				take ","
			end
		end
		take "}"
		return result
	end
	local value = read()
	return value, at
end

function source.parseLiteral(code: string): Literal
	local tokens = tokenize(code)
	local value, after = readLiteral(tokens, 1)
	assert(after > #tokens, "Unexpected text after the value")
	return value
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

local function sequencesFrom(header: Record): { Types.Sequence }?
	if header.sequences == nil then
		return nil
	end
	local sequences: { Types.Sequence } = {}
	for _, entry in list(header, "sequences") do
		local steps: { Types.SequenceStep } = {}
		for _, step in list(entry, "steps") do
			local function token(key: string): string?
				local found = step[key]
				return if type(found) == "string" then found else nil
			end
			table.insert(steps, {
				delay = token "delay",
				duration = token "duration",
				easing = token "easing",
				state = token "state",
				to = step.to,
				output = token "output",
			})
		end
		table.insert(
			sequences,
			{ id = text(entry, "id"), autoplay = if entry.autoplay == true then true else nil, steps = steps }
		)
	end
	return sequences
end

local function fieldsFrom(entry: Record): { Types.ItemField }
	local declared: { Types.ItemField } = {}
	for _, field in list(entry, "fields") do
		table.insert(declared, {
			id = text(field, "id"),
			type = inputType(text(field, "type")),
			luauType = if field.luauType ~= nil then text(field, "luauType") else nil,
			fields = if field.fields ~= nil then fieldsFrom(field) else nil,
		})
	end
	return declared
end

local function contractOf(header: Record): Types.Contract
	local found = header.contract
	assert(type(found) == "table", "The design header needs a contract")
	local inputs: { Types.Input } = {}
	for _, entry in list(found, "inputs") do
		local fields: { Types.ItemField }? = if entry.fields ~= nil then fieldsFrom(entry) else nil
		table.insert(inputs, {
			id = text(entry, "id"),
			kind = inputKind(text(entry, "kind")),
			luauType = if entry.luauType ~= nil then text(entry, "luauType") else nil,
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
		local row = entry.row
		table.insert(outputs, { id = text(entry, "id"), args = args, row = if type(row) == "string" then row else nil })
	end
	return { inputs = inputs, outputs = outputs }
end

local function editorNodes(node: Node, path: string, visit: (Node, string) -> ())
	visit(node, path)
	local content: { [string]: string } = {}
	local function templates(value: Literal, at: string)
		if type(value) ~= "table" then
			return
		end
		local id = value["$template"]
		if type(id) == "string" and (content[id] == nil or at < content[id]) then
			content[id] = at
		end
		for key, child in value do
			templates(child, `{at}/{tostring(key)}`)
		end
	end
	for key, property in node.props do
		if property.literal ~= nil then
			templates(property.literal, tostring(key))
		end
	end
	local index = 0
	for _, child in node.children do
		local slot = content[child.id]
		if slot then
			editorNodes(child, `{path}/content/{slot}`, visit)
		else
			index += 1
			editorNodes(child, `{path}/{index}`, visit)
		end
	end
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
	local function annotation()
		if peek() == ":" then
			while peek() ~= ")" do
				take()
			end
		end
	end
	local function returnAnnotation()
		if peek() == ":" then
			while peek() ~= "return" do
				take()
			end
		end
	end
	local calls: { [string]: string } = {}
	for kindName, kind in library.kinds do
		calls[kind.call] = kindName
	end
	local rows: { [string]: Node } = {}
	local typedLiterals: { [string]: Literal } = {}
	local typedCells: { [string]: { Node } } = {}
	local namedRefs: { [string]: string } = {}
	local node: () -> Node
	local pendingCells: { Node } = {}
	local function plain(): Literal
		local value, after = readLiteral(tokens, at, function(position: number): (Literal, number)
			at = position
			if peek() ~= "function" then
				local rowName = name()
				local cell = assert(rows[rowName], `{rowName} is not a row function`)
				table.insert(pendingCells, cell)
				local reference: Record = { ["$template"] = cell.id }
				return reference, at
			end
			take "function"
			take "("
			if peek() == "current" or peek() == ")" then
				if peek() == "current" then
					take "current"
					annotation()
				end
				take ")"
				returnAnnotation()
				take "return"
				local cell = node()
				take "end"
				table.insert(pendingCells, cell)
				local reference: Record = { ["$template"] = cell.id }
				return reference, at
			end
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
			local marker: Record = { ["$output"] = output }
			if peek() == "current" then
				take "current"
				take ":"
				take "peek"
				take "("
				take ")"
				marker["$row"] = true
			else
				take "..."
			end
			take ")"
			take "end"
			take "end"
			return marker, at
		end)
		at = after
		return value
	end
	local nextId = 1
	local function dotted(): string
		local path = name()
		while peek() == "." do
			take "."
			path ..= "." .. name()
		end
		return path
	end
	local function token(): string?
		local call = library.token
		if call == nil or tokens[at] == nil or tokens[at].kind ~= "name" then
			return nil
		end
		local start = at
		local path = dotted()
		if string.sub(call, -1) == "." and string.sub(path, 1, #call) == call then
			return string.sub(path, #call + 1)
		elseif path == call then
			local wrapped = peek() == "("
			if wrapped then
				take "("
			end
			local name = plain()
			if wrapped then
				take ")"
			end
			assert(type(name) == "string", "Token names are text")
			return name
		end
		at = start
		return nil
	end
	local function startsCall(path: string): boolean
		local offset = 0
		for index, part in string.split(path, ".") do
			if index > 1 then
				if peek(offset) ~= "." then
					return false
				end
				offset += 1
			end
			if peek(offset) ~= part then
				return false
			end
			offset += 1
		end
		return peek(offset) == "("
	end
	local function value(): (Value?, Node?)
		local motion = library.motion
		if motion ~= nil and startsCall(motion.call) then
			dotted()
			take "("
			local moving = assert(value(), `{motion.call} moves an input, state or item`)
			take ","
			moving.motion = unquote(take().text)
			take ")"
			return moving, nil
		end
		local bare = tokens[at]
		if bare and bare.kind == "name" and rows[bare.text] ~= nil and (peek(1) == "," or peek(1) == "}") then
			take()
			return nil, rows[bare.text]
		end
		if bare and bare.kind == "name" and typedLiterals[bare.text] ~= nil and (peek(1) == "," or peek(1) == "}") then
			take()
			local carried: { Node } = typedCells[bare.text] or {}
			for _, cell in carried do
				table.insert(pendingCells, cell)
			end
			return { literal = typedLiterals[bare.text] }, nil
		end
		if peek() == "sequences" and peek(1) == "." then
			take "sequences"
			take "."
			local played = name()
			take "."
			take "play"
			return { play = played }, nil
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
			if peek() == "use" and peek(2) == "local" then
				take "use"
				take ")"
				take "local"
				take "chosen"
				take "="
				take "named"
				take "["
				local wrapped = peek() == "use"
				if wrapped then
					take "use"
					take "("
				end
				local holder = name()
				take "."
				local source = name()
				if wrapped then
					take ")"
				end
				assert(holder == "props" or holder == "state", "A chosen node follows an input or state")
				take "]"
				take "return"
				take "if"
				take "chosen"
				take "then"
				take "use"
				take "("
				take "chosen"
				take ")"
				take "else"
				take "nil"
				take "end"
				local candidates: { string } = {}
				for _, id in namedRefs do
					table.insert(candidates, id)
				end
				table.sort(candidates)
				return { nodeFrom = source, nodes = candidates }, nil
			elseif peek() == "use" then
				take "use"
				take ")"
				take "return"
				local converted = peek() == "tostring"
				if converted then
					take "tostring"
					take "("
				end
				take "use"
				take "("
				take "current"
				take ")"
				take "."
				local field = name()
				if converted then
					take ")"
				end
				take "end"
				return { item = field }, nil
			elseif peek() == "current" or peek() == ")" then
				if peek() == "current" then
					take "current"
					annotation()
				end
				take ")"
				returnAnnotation()
				take "return"
				local next = tokens[at]
				if next ~= nil and (next.text == "{" or next.kind == "string" or next.kind == "number") then
					local perRow = plain()
					take "end"
					return { literal = perRow }, nil
				end
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
			elseif path == "Color3.fromHex" then
				local wrapped = peek() == "("
				if wrapped then
					take "("
				end
				local hex = plain()
				if wrapped then
					take ")"
				end
				assert(type(hex) == "string", "Color3.fromHex takes text")
				return { literal = "#" .. hex }, nil
			elseif
				path == "Vector2.one"
				or path == "Vector2.zero"
				or path == "Vector3.one"
				or path == "Vector3.zero"
			then
				local datatype, constant = string.match(path, "^(%w+)%.(%w+)$")
				local components: Record = {}
				for index = 1, assert(Datatype.arity[assert(datatype)]) do
					components[index] = if constant == "one" then 1 else 0
				end
				return { literal = components }, nil
			elseif
				(string.match(path, "^[%w_]+%.new$") or path == "UDim2.fromOffset" or path == "UDim2.fromScale")
				and peek() == "("
			then
				take "("
				local components: { Types.DatatypeComponent } = {}
				while peek() ~= ")" do
					local name = token()
					if name then
						components[#components + 1] = { token = name }
					else
						local number = plain()
						assert(type(number) == "number", "Datatype constructors take numeric or token components")
						components[#components + 1] = number
					end
					if peek() == "," then
						take ","
					end
				end
				take ")"
				if path == "UDim2.fromOffset" or path == "UDim2.fromScale" then
					assert(#components == 2, `{path} takes two components`)
					local expanded: { Types.DatatypeComponent } = if path == "UDim2.fromOffset"
						then { 0, components[1], 0, components[2] }
						else { components[1], 0, components[2], 0 }
					components = expanded
				end
				return { literal = Datatype.literal(components) }, nil
			end
			at = start
		end
		local name = token()
		if name then
			return { token = name }, nil
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
		local tagging = library.tags
		if tagging ~= nil and call == tagging.call and peek() == "(" then
			take "("
			local inner = node()
			take ","
			local raw = plain()
			take ")"
			local tags: { string } = {}
			if type(raw) == "table" then
				for _, tag in raw do
					if type(tag) == "string" then
						table.insert(tags, tag)
					end
				end
			end
			inner.tags = tags
			return inner
		end
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
		local outerCells = pendingCells
		pendingCells = {}
		take "{"
		local from: string?, key: string? = nil, nil
		local rowId: string? = nil
		while peek() ~= "}" do
			if tokens[at] and tokens[at].kind == "name" and peek(1) == "=" then
				local prop = name()
				take "="
				local property, template = value()
				local contentField = kind.fields[prop]
				if template and contentField and contentField.type == "content" then
					local marker: Record = { ["$template"] = template.id }
					result.props[prop] = { literal = marker }
					table.insert(pendingCells, template)
				elseif template then
					assert(
						prop == (if kind.children == "slot" then kind.slot else kind.template),
						`{prop} cannot hold a template`
					)
					if templated then
						rowId = template.id
					end
					table.insert(result.children, template)
				elseif property and templated and prop == kind.source then
					from = assert(property.input or property.item, `{prop} must read a list input or item field`)
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
					if peek() == "function" and peek(2) == "use" then
						take "function"
						take "("
						take "use"
						take ")"
						take "return"
						take "use"
						take "("
						take "current"
						take ")"
						take "."
						condition = name()
						take "="
						take "="
						take "true"
						take "end"
					elseif peek() == "function" then
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
					local listValue = assert(value(), "A keyed list reads a list")
					local list =
						assert(listValue.input or listValue.item, "A keyed list reads a list input or item field")
					take ","
					take "key"
					take "="
					take "function"
					take "("
					take "row"
					annotation()
					take ")"
					returnAnnotation()
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
						annotation()
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
		local listed = #result.children
		for _, cell in pendingCells do
			table.insert(result.children, cell)
		end
		pendingCells = outerCells
		if from then
			local row = if rowId ~= nil and listed > 1 then rowId else nil
			local keyProp = kind.key
			local field = if keyProp then kind.fields[keyProp] else nil
			local default = if field then field.default else nil
			result.bind = { from = from, key = key or (if type(default) == "string" then default else "id"), row = row }
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
		if peek() == "local" and peek(1) == "named" and peek(2) == "=" then
			take "local"
			take "named"
			take "="
			take "{"
			while peek() ~= "}" do
				local chosenName = name()
				take "="
				take "refs"
				take "."
				namedRefs[chosenName] = name()
				if peek() == "," then
					take ","
				end
			end
			take "}"
		elseif peek() == "local" and tokens[at + 1] and tokens[at + 1].kind == "name" and peek(2) == ":" then
			take "local"
			local literalName = name()
			take ":"
			while peek() ~= "=" do
				take()
			end
			take "="
			local outerCells = pendingCells
			pendingCells = {}
			typedLiterals[literalName] = plain()
			typedCells[literalName] = pendingCells
			pendingCells = outerCells
		elseif peek() == "local" and peek(1) == "function" and peek(2) ~= "capture" then
			take "local"
			take "function"
			local rowName = name()
			take "("
			take "current"
			annotation()
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
			local candidates = property.nodes
			if candidates then
				local remapped: { string } = {}
				for _, candidate in candidates do
					local mapped: string = assert(captured[candidate], `refs.{candidate} names no captured node`)
					table.insert(remapped, mapped)
				end
				property.nodes = remapped
			end
		end
		for _, child in current.children do
			remap(child)
		end
	end
	remap(root)
	local editor = header.editor
	if editor ~= nil then
		assert(type(editor) == "table", "The editor header is a table")
		editorNodes(root, "root", function(node: Node, path: string)
			local flags = editor[path]
			if flags ~= nil then
				assert(type(flags) == "table", "Editor flags are a table")
				assert(flags.hidden == nil or type(flags.hidden) == "boolean", "Hidden is a boolean")
				assert(flags.locked == nil or type(flags.locked) == "boolean", "Locked is a boolean")
				node.hidden = if flags.hidden == true then true else nil
				node.locked = if flags.locked == true then true else nil
			end
		end)
	end
	return Document.validate({
		schema = "compose-design/1",
		name = text(header, "name"),
		library = library.name,
		nextId = nextId,
		contract = contractOf(header),
		state = stateFrom(header),
		sequences = sequencesFrom(header),
		root = root,
	}, library)
end

source.editorNodes = editorNodes

return source
