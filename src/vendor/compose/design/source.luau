--!strict

local Types = require "./types"
local Document = require "./document"
local Read = require "./source-read"
local Datatype = require "./datatype"

type Node = Types.Node
type Literal = Types.Literal
type Library = Types.Library
type Value = Types.Value
type Record = { [string | number]: Literal }

local source = { parse = Read.parse, parseLiteral = Read.parseLiteral }

local function before(a: string | number, b: string | number): boolean
	if type(a) == "number" and type(b) == "number" then
		return a < b
	elseif type(a) == "string" and type(b) == "string" then
		return a < b
	end
	return type(a) == "number"
end

local function keysOf(value: Record): { string | number }
	local keys: { string | number } = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, before)
	return keys
end

local function prefix(key: string | number, index: number): string
	if key == index then
		return ""
	elseif type(key) == "string" and string.match(key, "^[%a_][%w_]*$") then
		return key .. " = "
	end
	local text = if type(key) == "string" then string.format("%q", key) else tostring(key)
	return "[" .. text .. "] = "
end

local function literal(value: Literal): string
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "number" or type(value) == "boolean" then
		return tostring(value)
	end
	local keys = keysOf(value)
	if #keys == 0 then
		return "{}"
	end
	local pieces: { string } = {}
	for index, key in keys do
		table.insert(pieces, prefix(key, index) .. literal(value[key]))
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
		local keys = keysOf(current)
		if #keys == 0 then
			return "{}"
		end
		local single = literal(current)
		if used + #single <= WIDTH then
			return single
		end
		local lines = { "{" }
		for index, key in keys do
			local prefix = prefix(key, index)
			local width = (depth + 1) * 4 + #prefix + 1
			table.insert(lines, string.rep("\t", depth + 1) .. prefix .. lay(current[key], depth + 1, width) .. ",")
		end
		table.insert(lines, string.rep("\t", depth) .. "}")
		return table.concat(lines, "\n")
	end
	return lay(header, 0, 16)
end

local function tokenExpression(library: Library, token: string): string
	local call = assert(library.token, `{library.name} has no theme tokens`)
	return if string.sub(call, -1) == "." then call .. token else `{call} {literal(token)}`
end

local function datatypeLiteral(library: Library, datatype: string, value: Literal): string
	if string.sub(datatype, 1, 5) == "Enum." then
		return `{datatype}.{tostring(value)}`
	end
	if datatype == "Color3" and type(value) == "string" then
		return `Color3.fromHex {literal((string.gsub(value, "^#", "")))}`
	end
	local parts: { string } = {}
	if type(value) == "table" then
		for _, component in value do
			local token = Datatype.token(component)
			table.insert(parts, if token then tokenExpression(library, token) else literal(component))
		end
		if datatype == "UDim2" then
			if value[1] == 0 and value[3] == 0 then
				return `UDim2.fromOffset({parts[2]}, {parts[4]})`
			elseif value[2] == 0 and value[4] == 0 then
				return `UDim2.fromScale({parts[1]}, {parts[3]})`
			end
		elseif datatype == "Vector2" or datatype == "Vector3" then
			for _, constant in { "zero", "one" } do
				local same = true
				for _, component in value do
					same = same and component == (if constant == "zero" then 0 else 1)
				end
				if same then
					return `{datatype}.{constant}`
				end
			end
		end
	end
	return `{datatype}.new({table.concat(parts, ", ")})`
end

local function fieldsLiteral(fields: { Types.ItemField }): Record
	local list: Record = {}
	for _, field in fields do
		local item: Record = { id = field.id, type = field.type }
		if field.luauType ~= nil then
			item.luauType = field.luauType
		end
		local nested = field.fields
		if nested then
			item.fields = fieldsLiteral(nested)
		end
		list[#list + 1] = item
	end
	return list
end

local function contractLiteral(contract: Types.Contract): Literal
	local inputs: Record = {}
	for _, input in contract.inputs do
		local entry: Record = { id = input.id, kind = input.kind, type = input.type }
		if input.luauType ~= nil then
			entry.luauType = input.luauType
		end
		local preview = input.preview
		if preview ~= nil then
			entry.preview = preview
		end
		if input.required then
			entry.required = true
		end
		local fields = input.fields
		if fields then
			entry.fields = fieldsLiteral(fields)
		end
		inputs[#inputs + 1] = entry
	end
	local outputs: Record = {}
	for _, output in contract.outputs do
		local item: Record = { id = output.id }
		local row = output.row
		if row ~= nil then
			item.row = row
		end
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

local function sequencesLiteral(sequences: { Types.Sequence }): Literal
	local entries: Record = {}
	for index, sequence in sequences do
		local steps: Record = {}
		for at, step in sequence.steps do
			local entry: Record = {}
			local function put(key: string, found: string?)
				if found ~= nil then
					entry[key] = found
				end
			end
			put("delay", step.delay)
			put("duration", step.duration)
			put("easing", step.easing)
			put("state", step.state)
			put("output", step.output)
			local to = step.to
			if to ~= nil then
				entry.to = to
			end
			steps[at] = entry
		end
		local record: Record = { id = sequence.id, steps = steps }
		if sequence.autoplay then
			record.autoplay = true
		end
		entries[index] = record
	end
	return entries
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
		local shape = field.luauType
		local nested = field.fields
		if shape == nil and nested ~= nil and #nested > 0 then
			local child = rowType(library, nested)
			shape = if field.type == "list" then "{ " .. child .. " }" else child
		end
		table.insert(pieces, `{field.id}: {shape or scalar(library, field.type)}`)
	end
	return "{ " .. table.concat(pieces, ", ") .. " }"
end

local function listItemName(input: Types.Input): string
	return string.upper(string.sub(input.id, 1, 1)) .. string.sub(input.id, 2) .. "Item"
end

local function base(library: Library, input: Types.Input): string
	if input.luauType ~= nil then
		return input.luauType
	end
	local fields = input.fields
	if fields and #fields > 0 then
		if input.type == "list" then
			return "{ " .. listItemName(input) .. " }"
		elseif input.type == "record" then
			return rowType(library, fields)
		end
	end
	return scalar(library, input.type)
end

local function outputType(library: Library, output: Types.Output, contract: Types.Contract): string
	local row = output.row
	if row ~= nil then
		for _, input in contract.inputs do
			if input.id == row then
				return `({listItemName(input)}) -> ()`
			end
		end
	end
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

export type EmitOptions = Types.EmitOptions

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
	local localControls = options ~= nil and options.localControls == true
	if controls ~= nil and not localControls then
		table.insert(lines, controls)
	end
	table.insert(lines, "")
	if propsType == nil and #value.contract.inputs == 0 and #value.contract.outputs == 0 then
		table.insert(lines, "export type Props = {}")
		table.insert(lines, "")
	elseif propsType == nil then
		for _, input in value.contract.inputs do
			local fields = input.fields
			if input.type == "list" and fields and #fields > 0 then
				table.insert(lines, `export type {listItemName(input)} = {rowType(library, fields)}`)
				table.insert(lines, "")
			end
		end
		table.insert(lines, "export type Props = {")
		for _, input in value.contract.inputs do
			local optional = if input.required then "" else "?"
			table.insert(lines, `\t{input.id}: {fieldType(library, input)}{optional},`)
		end
		for _, output in value.contract.outputs do
			table.insert(lines, `\t{output.id}: ({outputType(library, output, value.contract)})?,`)
		end
		table.insert(lines, "}")
		table.insert(lines, "")
	end
	local rowTypesAt = #lines + 1
	local header: Record = { name = value.name, contract = contractLiteral(value.contract) }
	local state = value.state
	if state and #state > 0 then
		header.state = stateLiteral(state)
	end
	local sequences = value.sequences
	if sequences and #sequences > 0 then
		header.sequences = sequencesLiteral(sequences)
	end
	table.insert(lines, "local _design = " .. layoutHeader(header))
	table.insert(lines, "")
	local referenced: { [string]: boolean } = {}
	local referencedIds: { string } = {}
	local chosenNames: { [string]: string } = {}
	local nodeNames: { [string]: string } = {}
	local function nameNodes(node: Node)
		nodeNames[node.id] = node.name
		for _, child in node.children do
			nameNodes(child)
		end
	end
	nameNodes(value.root)
	local function collect(node: Node)
		for _, property in node.props do
			local target = property.node
			if target ~= nil and not referenced[target] then
				referenced[target] = true
				table.insert(referencedIds, target)
			end
			local candidates = property.nodes
			if candidates then
				for _, candidate in candidates do
					chosenNames[nodeNames[candidate]] = candidate
					if not referenced[candidate] then
						referenced[candidate] = true
						table.insert(referencedIds, candidate)
					end
				end
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
	local function returning(params: string, body: string, depth: number, returnType: string?): string
		local annotated = if returnType then `: {returnType}` else ""
		return `function({params}){annotated}\n{tabs(depth + 1)}return {body}\n{tabs(depth)}end`
	end
	local rowTypeLines: { string } = {}
	local rowItemTypes: { [string]: string } = {}
	local function rowBase(template: Node): string
		local base = string.gsub(template.name, "[^%w_]", "")
		if not string.match(base, "^%u") then
			base = "Row" .. base
		elseif not string.match(base, "Row$") then
			base ..= "Row"
		end
		return base
	end
	local function unique(base: string): string
		local name = base
		local suffix = 1
		while rowNames[name] do
			suffix += 1
			name = base .. tostring(suffix)
		end
		rowNames[name] = true
		return name
	end
	local scopes: { { fields: { Types.ItemField }? } } = {}
	local function fieldsOf(from: string): { Types.ItemField }?
		local declared = Document.input(value, from)
		if declared ~= nil then
			return declared.fields
		end
		local enclosing = scopes[#scopes]
		local around = if enclosing then enclosing.fields else nil
		if around ~= nil then
			for _, field in around do
				if field.id == from then
					return field.fields
				end
			end
		end
		return nil
	end
	local function sourceOf(from: string, depth: number): string
		if Document.input(value, from) ~= nil then
			return `props.{from}`
		end
		return returning("use", `use(current).{from}`, depth)
	end
	local listItemTypes: { [string]: string } = {}
	if propsType == nil then
		for _, input in value.contract.inputs do
			local fields = input.fields
			if input.type == "list" and fields and #fields > 0 then
				listItemTypes[input.id] = listItemName(input)
				rowNames[listItemName(input)] = true
			end
		end
	end
	local function itemType(template: Node, from: string): string?
		local known = rowItemTypes[template.id] or listItemTypes[from]
		if known ~= nil then
			rowItemTypes[template.id] = known
			return known
		end
		local fields = fieldsOf(from)
		if fields == nil or #fields == 0 then
			return nil
		end
		local name = unique(rowBase(template) .. "Item")
		rowItemTypes[template.id] = name
		listItemTypes[from] = name
		table.insert(rowTypeLines, `type {name} = {rowType(library, fields)}`)
		return name
	end
	local function keyFunction(template: Node, bind: Types.Bind, depth: number): string
		local typed = itemType(template, bind.from)
		if typed == nil then
			return returning("row", "row." .. bind.key, depth)
		end
		local keyType = "string"
		local fields = fieldsOf(bind.from)
		if fields then
			for _, field in fields do
				if field.id == bind.key then
					keyType = scalar(library, field.type)
				end
			end
		end
		return `function(row: {typed}): {keyType}\n{tabs(depth + 1)}return row.{bind.key}\n{tabs(depth)}end`
	end
	local function rowFunction(template: Node, depth: number, from: string): string
		local typed = itemType(template, from)
		local parameter = if typed then `current: {library.readable}<{typed}>` else "current"
		table.insert(scopes, { fields = fieldsOf(from) })
		local written
		if not rowFunctions then
			written = returning(parameter, emit(template, depth + 1), depth)
		else
			local name = unique(rowBase(template))
			table.insert(rowDefinitions, `\tlocal function {name}({parameter})\n\t\treturn {emit(template, 2)}\n\tend`)
			written = name
		end
		table.remove(scopes)
		return written
	end
	local cellOwner: Node? = nil
	local function layout(current: Literal, depth: number, used: number): string
		if type(current) ~= "table" then
			return literal(current)
		end
		local output = current["$output"]
		if type(output) == "string" then
			return callback(output, if current["$row"] == true then "current:peek()" else "...", depth)
		end
		local template = current["$template"]
		if type(template) == "string" then
			local owner = assert(cellOwner, "A cell template needs its node")
			local found = Document.find(owner, template)
			local cell = assert(found, "A cell template names a child")
			local bound = owner.bind
			if bound == nil then
				return returning("", emit(cell, depth + 1), depth)
			end
			return rowFunction(cell, depth, bound.from)
		end
		local keys = keysOf(current)
		if #keys == 0 then
			return "{}"
		end
		local prefixes: { string } = {}
		for index, key in keys do
			prefixes[index] = prefix(key, index)
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
	local hoisted: { string } = {}
	local function carriesRow(current: Literal): boolean
		if type(current) ~= "table" then
			return false
		end
		if current["$row"] ~= nil then
			return true
		end
		for _, item in current do
			if carriesRow(item) then
				return true
			end
		end
		return false
	end
	local lateHoisted: { string } = {}
	local function hoist(node: Node, key: string, luauType: string, current: Literal): string
		local base = string.gsub(node.name, "[^%w_]", "")
		base = string.lower(string.sub(base, 1, 1)) .. string.sub(base, 2)
		if not string.match(base, "^%a") then
			base = "value"
		end
		base ..= string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
		local name = base
		local suffix = 1
		while rowNames[name] do
			suffix += 1
			name = base .. tostring(suffix)
		end
		rowNames[name] = true
		local typed = luauType
		local bound = node.bind
		if bound ~= nil then
			local keyType = "unknown"
			local fields: { Types.ItemField } = fieldsOf(bound.from) or {}
			for _, field in fields do
				if field.id == bound.key then
					keyType = scalar(library, field.type)
				end
			end
			local itemName = itemType(node, bound.from) or "unknown"
			typed = (string.gsub(typed, "%$Item", itemName))
			typed = (string.gsub(typed, "%$Key", keyType))
		end
		local prefix = `\tlocal {name}: {typed} = `
		local late = next(Document.cellsOf(current, {})) ~= nil
		table.insert(if late then lateHoisted else hoisted, prefix .. layout(current, 1, #prefix + 3))
		return name
	end
	local function expression(property: Value, depth: number, used: number): string
		local role = property.motion
		if role ~= nil then
			local motion = assert(library.motion, `{library.name} has no motion roles`)
			local still = table.clone(property)
			still.motion = nil
			return `{motion.call}({expression(still, depth, used)}, {literal(role)})`
		end
		local target = property.node
		if target ~= nil then
			return `refs.{target}`
		end
		local stateId = property.state
		if stateId ~= nil then
			return `state.{stateId}`
		end
		local played = property.play
		if played ~= nil then
			return `sequences.{played}.play`
		end
		local source = property.nodeFrom
		if source ~= nil then
			local read
			if Document.stateOf(value, source) ~= nil then
				read = `use(state.{source})`
			elseif assert(Document.input(value, source)).kind == "value" then
				read = `props.{source}`
			else
				read = `use(props.{source})`
			end
			return `function(use)\n{tabs(depth + 1)}local chosen = named[{read}]\n`
				.. `{tabs(depth + 1)}return if chosen then use(chosen) else nil\n{tabs(depth)}end`
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
		return tokenExpression(library, assert(token))
	end
	local function tagged(node: Node, depth: number): string
		local tags, tagging = node.tags, library.tags
		if tags == nil or tagging == nil then
			return emitNode(node, depth)
		end
		local inner = tabs(depth + 1)
		local quoted: { string } = {}
		for _, tag in tags do
			table.insert(quoted, string.format("%q", tag))
		end
		local list = "{ " .. table.concat(quoted, ", ") .. " }"
		return `{tagging.call}(\n{inner}{emitNode(node, depth + 1)},\n{inner}{list}\n{tabs(depth)})`
	end
	emit = function(node: Node, depth: number): string
		if referenced[node.id] then
			local inner = tabs(depth + 1)
			return `capture(\n{inner}"{node.id}",\n{inner}{tagged(node, depth + 1)}\n{tabs(depth)})`
		end
		return tagged(node, depth)
	end
	emitNode = function(node: Node, depth: number): string
		local kind = assert(library.kinds[node.kind])
		local inner = tabs(depth + 1)
		local nameField, nameInput = node.nameField, node.nameInput
		local opening
		if nameField ~= nil then
			opening = `{kind.call}(tostring(current:peek().{nameField})) `
		elseif nameInput ~= nil then
			opening = `{kind.call}(props.{nameInput} or {literal(node.name)}) `
		else
			opening = `{kind.call} {literal(node.name)} `
		end
		local body: { string } = {}
		local keys: { string } = {}
		local boundTemplate = kind.children == "template" and node.bind ~= nil
		for key in node.props do
			local current = node.props[key].literal
			local declared = kind.fields[key]
			local default = if declared then declared.default else nil
			if
				not (boundTemplate and (key == kind.source or key == kind.key))
				and not (current ~= nil and default ~= nil and literal(current) == literal(default))
			then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local cells: { [string]: true } = {}
		local outerOwner = cellOwner
		cellOwner = node
		for _, key in keys do
			local property = node.props[key]
			local field = kind.fields[key]
			local current = property.literal
			if current ~= nil then
				Document.cellsOf(current, cells)
			end
			local datatype: string? = if field then field.datatype else nil
			local written = expression(property, depth + 1, (depth + 1) * 4 + #key + 4)
			local luauType: string? = if field then field.luauType else nil
			local bound = node.bind
			local itemName = property.item
			if itemName ~= nil and field ~= nil and field.type == "string" then
				local enclosing = scopes[#scopes]
				local around: { Types.ItemField } = if enclosing and enclosing.fields then enclosing.fields else {}
				local textual = true
				for _, entry in around do
					if entry.id == itemName and entry.type ~= "string" then
						textual = false
					end
				end
				if not textual then
					written = returning("use", `tostring(use(current).{itemName})`, depth + 1)
				end
			end
			if current ~= nil and field ~= nil and field.perRow and bound ~= nil then
				local typed = itemType(node, bound.from)
				local parameter = if typed then `current: {library.readable}<{typed}>` else "current"
				table.insert(scopes, { fields = fieldsOf(bound.from) })
				written = returning(parameter, layout(current, depth + 2, 0), depth + 1, luauType)
				table.remove(scopes)
			elseif current ~= nil and datatype ~= nil then
				written = datatypeLiteral(library, datatype, current)
			elseif current ~= nil and type(current) == "table" and luauType and not carriesRow(current) then
				local typeName: string = luauType
				written = hoist(node, key, typeName, current)
			end
			table.insert(body, `{inner}{key} = {written},`)
		end
		cellOwner = outerOwner
		local content: { Node } = {}
		for _, child in node.children do
			if not cells[child.id] then
				table.insert(content, child)
			end
		end
		local bind, template = node.bind, content[1]
		if kind.children == "slot" then
			if template then
				table.insert(
					body,
					`{inner}{assert(kind.slot)} = {returning("", emit(template, depth + 2), depth + 1)},`
				)
			end
		elseif kind.children == "template" then
			if bind then
				table.insert(body, `{inner}{assert(kind.source)} = {sourceOf(bind.from, depth + 1)},`)
				local keyProp = kind.key
				if keyProp then
					local field = kind.fields[keyProp]
					local default = if field then field.default else nil
					if default ~= bind.key then
						table.insert(body, `{inner}{keyProp} = {literal(bind.key)},`)
					end
				end
			end
			local templateProp = kind.template
			if templateProp == nil then
				for _, child in content do
					table.insert(body, `{inner}{emit(child, depth + 1)},`)
				end
			elseif bind and template then
				local rowId = bind.row or template.id
				local rowNode = template
				for _, child in content do
					if child.id == rowId then
						rowNode = child
					end
				end
				table.insert(body, `{inner}{templateProp} = {rowFunction(rowNode, depth + 1, bind.from)},`)
				for _, child in content do
					if child ~= rowNode then
						table.insert(body, `{inner}{emit(child, depth + 1)},`)
					end
				end
			end
		else
			local rowId = if bind then bind.row or (if template then template.id else nil) else nil
			for _, child in content do
				local condition = child.when
				if bind and child.id == rowId then
					local keyedCall = assert(library.keyed)
					local field = tabs(depth + 2)
					table.insert(body, `{inner}{keyedCall} ` .. "{")
					table.insert(body, `{field}from = {sourceOf(bind.from, depth + 2)},`)
					table.insert(body, `{field}key = {keyFunction(child, bind, depth + 2)},`)
					table.insert(body, `{field}render = {rowFunction(child, depth + 2, bind.from)},`)
					table.insert(body, `{inner}},`)
				elseif condition == nil then
					table.insert(body, `{inner}{emit(child, depth + 1)},`)
				else
					local showCall = assert(library.show)
					local source
					if Document.stateOf(value, condition) ~= nil then
						source = `state.{condition}`
					elseif Document.input(value, condition) == nil then
						source = returning("use", `use(current).{condition} == true`, depth + 1)
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
	if controls ~= nil and localControls then
		table.insert(lines, "\t" .. controls)
	end
	local rootSource = emit(value.root, 1)
	for index, line in rowTypeLines do
		table.insert(lines, rowTypesAt + 2 * index - 2, line)
		table.insert(lines, rowTypesAt + 2 * index - 1, "")
	end
	for _, definition in hoisted do
		table.insert(lines, definition)
	end
	local readsState = string.find(rootSource, "state.", 1, true) ~= nil
	for _, definition in lateHoisted do
		readsState = readsState or string.find(definition, "state.", 1, true) ~= nil
	end
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
		local chosen: { string } = {}
		for name in chosenNames do
			table.insert(chosen, name)
		end
		table.sort(chosen)
		if #chosen > 0 then
			local entries: { string } = {}
			for _, name in chosen do
				table.insert(entries, `{name} = refs.{chosenNames[name]}`)
			end
			table.insert(lines, "\tlocal named = { " .. table.concat(entries, ", ") .. " }")
		end
	end
	local sequenceLines: { string } = {}
	if sequences and #sequences > 0 then
		local sequencing = assert(library.sequence, `{library.name} cannot play sequences`)
		table.insert(sequenceLines, "\tlocal sequences = {")
		for _, sequence in sequences do
			table.insert(sequenceLines, "\t\t" .. sequence.id .. " = " .. sequencing.call .. " {")
			table.insert(sequenceLines, "\t\t\tsteps = {")
			for _, step in sequence.steps do
				local parts: { string } = {}
				local function timed(key: string, token: string?)
					if token ~= nil then
						table.insert(parts, `{key} = {literal(token)}`)
					end
				end
				timed("delay", step.delay)
				timed("duration", step.duration)
				timed("easing", step.easing)
				local target, to = step.state, step.to
				if target ~= nil and to ~= nil then
					table.insert(
						parts,
						if type(to) == "number"
							then `sample = {sequencing.toward}(state.{target}, {literal(to)})`
							else `onStart = function() state.{target}:set({literal(to)}) end`
					)
					readsState = true
				end
				local output = step.output
				if output ~= nil then
					table.insert(parts, `onEnd = props.{output}`)
				end
				table.insert(sequenceLines, "\t\t\t\t{ " .. table.concat(parts, ", ") .. " },")
			end
			table.insert(sequenceLines, "\t\t\t},")
			table.insert(sequenceLines, "\t\t},")
		end
		table.insert(sequenceLines, "\t}")
		for _, sequence in sequences do
			if sequence.autoplay then
				table.insert(sequenceLines, `\tsequences.{sequence.id}.play()`)
			end
		end
	end
	if state and #state > 0 and readsState then
		local newCell = assert(library.newCell, `{library.name} cannot hold state; it names no cell constructor`)
		local cells: { string } = {}
		for _, entry in state do
			local initial = entry.initial
			local argument = literal(initial)
			table.insert(
				cells,
				if type(initial) == "string" or type(initial) == "table"
					then `{entry.id} = {newCell} {argument}`
					else `{entry.id} = {newCell}({argument})`
			)
		end
		table.insert(lines, "\tlocal state = { " .. table.concat(cells, ", ") .. " }")
	end
	for _, line in sequenceLines do
		table.insert(lines, line)
	end
	for _, definition in rowDefinitions do
		table.insert(lines, definition)
	end
	for _, definition in lateHoisted do
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

return source
