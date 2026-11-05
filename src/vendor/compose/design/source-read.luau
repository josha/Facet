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
	local at = 1
	while at <= #code do
		local character = string.sub(code, at, at)
		local _, space = string.find(code, "^%s+", at)
		if space then
			at = space + 1
		elseif string.sub(code, at, at + 1) == "--" then
			local stop = string.find(code, "\n", at, true)
			at = if stop then stop + 1 else #code + 1
		elseif character == '"' then
			local stop = at + 1
			while stop <= #code and string.sub(code, stop, stop) ~= '"' do
				stop += if string.sub(code, stop, stop) == "\\" then 2 else 1
			end
			tokens[#tokens + 1] = { kind = "string", text = string.sub(code, at, stop) }
			at = stop + 1
		elseif string.match(character, "[%a_]") then
			local word = assert(string.match(code, "^[%w_]+", at))
			tokens[#tokens + 1] = { kind = "name", text = word }
			at += #word
		elseif string.match(code, "^%-?%d", at) then
			local number = string.match(code, "^%-?%d+%.?%d*[eE][%+%-]?%d+", at)
				or assert(string.match(code, "^%-?%d+%.?%d*", at))
			tokens[#tokens + 1] = { kind = "number", text = number }
			at += #number
		elseif string.sub(code, at, at + 2) == "..." then
			tokens[#tokens + 1] = { kind = "symbol", text = "..." }
			at += 3
		else
			tokens[#tokens + 1] = { kind = "symbol", text = character }
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
	if name == "value" or name == "readable" or name == "cell" then
		return name
	end
	error(`Unknown input kind {name}`, 0)
end

local function inputType(name: string): Types.InputType
	if
		name == "string"
		or name == "number"
		or name == "boolean"
		or name == "color"
		or name == "image"
		or name == "vector3"
		or name == "list"
		or name == "record"
		or name == "slot"
	then
		return name
	end
	error(`Unknown input type {name}`, 0)
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
		local options: { string }? = nil
		if type(field.options) == "table" then
			options = {}
			for _, option in field.options do
				assert(type(option) == "string", "Item options are text")
				table.insert(options, option)
			end
		end
		table.insert(declared, {
			id = text(field, "id"),
			type = inputType(text(field, "type")),
			luauType = if field.luauType ~= nil then text(field, "luauType") else nil,
			fields = if field.fields ~= nil then fieldsFrom(field) else nil,
			options = options,
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
		local options: { string }? = nil
		if entry.options ~= nil then
			assert(type(entry.options) == "table", "Input options are a list")
			local choices: { string } = {}
			for _, option in entry.options do
				assert(type(option) == "string", "Input options are text")
				table.insert(choices, option)
			end
			options = choices
		end
		table.insert(inputs, {
			id = text(entry, "id"),
			kind = inputKind(text(entry, "kind")),
			luauType = if entry.luauType ~= nil then text(entry, "luauType") else nil,
			type = inputType(text(entry, "type")),
			preview = entry.preview,
			fields = fields,
			required = if entry.required == true then true else nil,
			options = options,
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
	if node.rowVariant then
		for _, case in node.rowVariant.cases do
			local wrapper = table.clone(node)
			wrapper.rowVariant = nil
			wrapper.props, wrapper.children = case.props, case.children
			editorNodes(wrapper, `{path}/variant/{case.value}`, visit)
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
	local function annotation(stop: string)
		if peek() == ":" then
			while peek() ~= stop do
				take()
			end
		end
	end
	local function rowAlias()
		if peek() == "local" and string.match(peek(1), "^row_[%w]+$") then
			take "local"
			take()
			take "="
			take "current"
		end
	end
	local function referenceMessage()
		take ","
		local message = take()
		assert(
			message.kind == "string" and unquote(message.text) == "Node reference is not captured",
			"Node references assert their capture"
		)
		take ")"
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
	local function rowBody(): Node
		local cases: { Types.VariantCase } = {}
		local alternatives: { Node } = {}
		local item: string? = nil
		while peek() == "if" do
			take "if"
			take "current"
			take ":"
			take "peek"
			take "("
			take ")"
			take "."
			local field = name()
			assert(item == nil or item == field, "Row variants read one enum field")
			item = field
			take "="
			take "="
			local selected = take()
			assert(selected.kind == "string", "Row variants select text enum options")
			take "then"
			take "return"
			local alternative = node()
			table.insert(alternatives, alternative)
			table.insert(cases, {
				value = unquote(selected.text),
				kind = alternative.kind,
				props = alternative.props,
				children = alternative.children,
			})
			take "end"
		end
		take "return"
		local root = node()
		if item then
			for _, alternative in alternatives do
				assert(
					(root.nameInput ~= nil or root.nameField ~= nil or alternative.name == root.name)
						and alternative.nameInput == root.nameInput
						and alternative.nameField == root.nameField,
					"Row variants keep one direct root name"
				)
			end
			root.rowVariant = { item = item, cases = cases }
		end
		return root
	end
	local pendingCells: { Node } = {}
	local function plain(): Literal
		local value, after = readLiteral(tokens, at, function(position: number): (Literal, number)
			at = position
			if peek() == "props" then
				take "props"
				take "."
				return { ["$input"] = name() }, at
			end
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
					annotation ")"
				end
				take ")"
				annotation "return"
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
	local motion = library.motion
	local motionTokens = if motion then tokenize(motion.call .. "(") else {}
	local function startsMotion(): boolean
		for index, part in motionTokens do
			if peek(index - 1) ~= part.text then
				return false
			end
		end
		return true
	end
	local function value(): (Value?, Node?)
		if motion ~= nil and startsMotion() then
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
			local input = name()
			local path: { string } = {}
			while peek() == "." do
				take "."
				table.insert(path, name())
			end
			return { input = input, path = if #path > 0 then path else nil }, nil
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
				local captured = peek() == "assert"
				if captured then
					take "assert"
					take "("
				end
				take "if"
				take "chosen"
				take "then"
				take "use"
				take "("
				take "chosen"
				take ")"
				take "else"
				take "nil"
				if captured then
					referenceMessage()
				end
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
				if peek() == "assert" then
					take "assert"
					take "("
					take "use"
					take "("
					take "refs"
					take "."
					local target = name()
					take ")"
					referenceMessage()
					take "end"
					return { node = target }, nil
				end
				if peek() ~= "use" and peek() ~= "tostring" then
					local datatype = assert(value(), "A datatype formula returns a constructor")
					assert(type(datatype.literal) == "table", "A datatype formula returns components")
					take "end"
					return datatype, nil
				end
				local converted = peek() == "tostring"
				if converted then
					take "tostring"
					take "("
				end
				take "use"
				take "("
				local row = name()
				assert(
					row == "current" or string.match(row, "^row_[%w]+$") ~= nil,
					"Item bindings read the current row"
				)
				take ")"
				take "."
				local field = name()
				if converted then
					take ")"
				end
				take "end"
				local qualifier = string.match(row, "^row_([%w]+)$")
				return { item = if qualifier then qualifier .. "." .. field else field }, nil
			elseif string.match(peek(), "^event%d+$") or (peek() == ")" and peek(1) == "if") then
				local parameters: { [string]: number } = {}
				local count = 0
				while peek() ~= ")" do
					count += 1
					local parameter = name()
					assert(parameter == `event{count}`, "Action parameters use ordered event positions")
					parameters[parameter] = count
					take ":"
					local depth = 0
					repeat
						local text = take().text
						if text == "(" or text == "{" or text == "[" or text == "<" then
							depth += 1
						elseif text == ")" or text == "}" or text == "]" or text == ">" then
							depth -= 1
						end
					until depth == 0 and (peek() == "," or peek() == ")")
					if peek() == "," then
						take ","
					end
				end
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
				local arguments: { Types.ActionArgument } = {}
				while peek() ~= ")" do
					if peek() == "current" then
						take "current"
						take ":"
						take "peek"
						take "("
						take ")"
						take "."
						table.insert(arguments, { item = name() })
					else
						table.insert(arguments, { event = assert(parameters[name()], "Unknown action event argument") })
					end
					if peek() == "," then
						take ","
					end
				end
				take ")"
				take "end"
				take "end"
				return { output = id, arguments = arguments }, nil
			elseif peek() == "current" or peek() == ")" then
				if peek() == "current" then
					take "current"
					annotation ")"
				end
				take ")"
				annotation "return"
				rowAlias()
				if peek() == "if" then
					local child = rowBody()
					take "end"
					return nil, child
				end
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
					elseif peek() == "props" or peek() == "use" then
						local live = peek() == "use"
						if live then
							take "use"
							take "("
						end
						take "props"
						take "."
						local id = take()
						assert(id.kind == "name", "A datatype component names an input")
						if live then
							take ")"
						end
						components[#components + 1] = { input = id.text }
					else
						local number = plain()
						assert(
							type(number) == "number",
							"Datatype constructors take numeric, token or input components"
						)
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
	local sharedContent: Node? = nil
	node = function(): Node
		if peek() == "props" or peek() == "if" then
			local optional = peek() == "if"
			local condition: string? = nil
			if optional then
				take "if"
				take "props"
				take "."
				condition = name()
				take "then"
			end
			take "props"
			take "."
			local input = name()
			take "("
			take ")"
			if optional then
				assert(condition == input, "Optional slot children test their own factory")
				take "else"
				take "nil"
			end
			local child: Node =
				{ id = `n{nextId}`, kind = "$slot", name = input, slot = input, props = {}, children = {} }
			nextId += 1
			return child
		end
		if peek() == "rootContent" then
			take "rootContent"
			take "("
			take ")"
			local content = assert(sharedContent, "Root content needs its shared function")
			return content
		end
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
			local binding = assert(value(), "Tags need a value")
			take ")"
			if binding.input or binding.item then
				inner.tagBinding = binding
				return inner
			end
			local raw = binding.literal
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
		if kind.design then
			take "("
			take(library.parameter)
			take ","
			take "{"
			take(kind.design.nameInput)
			take "="
		end
		local nodeName = take()
		local nameField: string? = nil
		local nodeTitle: string
		local nameInput: string? = nil
		if (nodeName.text == "(" and peek() == "props") or (kind.design and nodeName.text == "props") then
			if nodeName.text == "(" then
				take "props"
			end
			take "."
			nameInput = name()
			nodeTitle = kindName
			if peek() == "or" then
				take "or"
				local fallback = take()
				assert(fallback.kind == "string", "A named node falls back to text")
				nodeTitle = unquote(fallback.text)
			end
			if nodeName.text == "(" then
				take ")"
			end
		elseif nodeName.text == "(" or (kind.design and nodeName.text == "tostring") then
			if nodeName.text == "(" then
				take "tostring"
			end
			take "("
			take "current"
			take ":"
			take "peek"
			take "("
			take ")"
			take "."
			nameField = name()
			take ")"
			if nodeName.text == "(" then
				take ")"
			end
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
		take(if kind.design then "," else "{")
		local from: string?, key: string? = nil, nil
		local rowId: string? = nil
		while peek() ~= "}" do
			if tokens[at] and tokens[at].kind == "name" and peek(1) == "=" then
				local prop = name()
				take "="
				local contentField = kind.fields[prop]
				local start = at
				local lead = if tokens[at] and tokens[at].kind == "name" then dotted() else ""
				at = start
				local direct = contentField
					and contentField.type == "value"
					and not contentField.perRow
					and (calls[lead] ~= nil or lead == "capture" or (library.tags and lead == library.tags.call))
				local property: Value? = nil
				local template: Node? = nil
				if direct then
					template = node()
				else
					property, template = value()
				end
				if template and contentField and (direct or contentField.type == "content") and prop ~= kind.slot then
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
					if peek() == "function" then
						take "function"
						take "("
						local item = peek() == "use"
						if item then
							take "use"
						end
						take ")"
						if item then
							rowAlias()
						end
						take "return"
						if item then
							take "use"
							take "("
							take "current"
							take ")"
						else
							take "props"
						end
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
					annotation ")"
					take ")"
					annotation "return"
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
						annotation ")"
						take ")"
						row = rowBody()
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
		if kind.design then
			take ")"
		end
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
	local variant: Types.RootVariant? = nil
	local alternative: Node? = nil
	while not (peek() == "return" and peek(1) ~= "node") do
		if peek() == "if" and peek(1) == "props" then
			take "if"
			take "props"
			take "."
			local input = name()
			take "="
			take "="
			local selected = plain()
			assert(type(selected) == "string", "A root variant selects an enum option")
			take "then"
			take "return"
			alternative = node()
			local found: Types.RootVariant =
				{ input = input, value = selected, kind = alternative.kind, props = alternative.props }
			variant = found
			take "end"
		elseif peek() == "local" and peek(1) == "function" and peek(2) == "rootContent" then
			take "local"
			take "function"
			take "rootContent"
			take "("
			take ")"
			annotation "return"
			take "return"
			sharedContent = node()
			take "end"
		elseif peek() == "local" and peek(1) == "named" then
			take "local"
			take "named"
			while peek() ~= "=" do
				take()
			end
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
		elseif
			peek() == "local"
			and tokens[at + 1]
			and tokens[at + 1].kind == "name"
			and peek(1) ~= "refs"
			and peek(2) == ":"
		then
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
			annotation ")"
			take ")"
			rowAlias()
			rows[rowName] = rowBody()
			take "end"
		else
			take()
		end
	end
	take "return"
	local root = node()
	if alternative and variant then
		assert(
			(root.nameInput ~= nil or alternative.name == root.name)
				and alternative.nameInput == root.nameInput
				and alternative.nameField == root.nameField,
			"Root variants keep one direct root name"
		)
		if sharedContent then
			assert(
				#root.children == 1
					and root.children[1] == sharedContent
					and #alternative.children == 1
					and alternative.children[1] == sharedContent,
				"Root variants share their content"
			)
		else
			variant.children = alternative.children
		end
	end
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
		if current.rowVariant then
			for _, case in current.rowVariant.cases do
				local wrapper = table.clone(current)
				wrapper.rowVariant = nil
				wrapper.props, wrapper.children = case.props, case.children
				remap(wrapper)
			end
		end
	end
	remap(root)
	if alternative then
		local wrapper = table.clone(alternative)
		wrapper.children = if sharedContent then {} else alternative.children
		remap(wrapper)
	end
	do
		local ids: { [string]: string } = {}
		nextId = 1
		local function renumber(current: Node)
			local id = `n{nextId}`
			nextId += 1
			ids[current.id] = id
			current.id = id
			for _, child in current.children do
				renumber(child)
			end
			if current.rowVariant then
				for _, case in current.rowVariant.cases do
					for _, child in case.children do
						renumber(child)
					end
				end
			end
		end
		renumber(root)
		if variant and variant.children then
			for _, child in variant.children do
				renumber(child)
			end
		end
		local function markers(current: Literal)
			if type(current) ~= "table" then
				return
			end
			local template = current["$template"]
			if type(template) == "string" then
				current["$template"] = ids[template]
			end
			for _, item in current do
				markers(item)
			end
		end
		local function bindings(current: Node)
			for _, property in current.props do
				if property.node then
					property.node = ids[property.node]
				end
				if property.nodes then
					for index, id in property.nodes do
						property.nodes[index] = ids[id]
					end
				end
				if property.literal ~= nil then
					markers(property.literal)
				end
			end
			if current.bind and current.bind.row then
				current.bind.row = ids[current.bind.row]
			end
			for _, child in current.children do
				bindings(child)
			end
			if current.rowVariant then
				for _, case in current.rowVariant.cases do
					local wrapper = table.clone(current)
					wrapper.rowVariant = nil
					wrapper.props, wrapper.children = case.props, case.children
					bindings(wrapper)
				end
			end
		end
		bindings(root)
		if variant then
			local wrapper = table.clone(root)
			wrapper.rowVariant = nil
			wrapper.props = variant.props
			wrapper.children = variant.children or {}
			bindings(wrapper)
		end
	end
	local editor = header.editor
	if editor ~= nil then
		assert(type(editor) == "table", "The editor header is a table")
		local function restore(node: Node, path: string)
			local flags = editor[path]
			if flags ~= nil then
				assert(type(flags) == "table", "Editor flags are a table")
				assert(flags.hidden == nil or type(flags.hidden) == "boolean", "Hidden is a boolean")
				assert(flags.locked == nil or type(flags.locked) == "boolean", "Locked is a boolean")
				if flags.name ~= nil then
					node.name = text(flags, "name")
				end
				node.hidden = if flags.hidden == true then true else nil
				node.locked = if flags.locked == true then true else nil
			end
		end
		editorNodes(root, "root", restore)
		if variant and variant.children then
			local wrapper = table.clone(root)
			wrapper.rowVariant = nil
			wrapper.props, wrapper.children = variant.props, variant.children
			editorNodes(wrapper, "alternative", restore)
		end
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
		rootVariant = variant,
	}, library)
end

source.editorNodes = editorNodes

return source
