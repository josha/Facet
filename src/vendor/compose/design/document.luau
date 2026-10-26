--!strict

local Types = require "./types"

type Document = Types.Document
type Node = Types.Node
type Library = Types.Library
type Value = Types.Value
type Literal = Types.Literal

local MAX_NODES = 500
local MAX_DEPTH = 32
local IDENTIFIER = "^%l[%w]*$"
local OUTPUT = "^on%u[%w]*$"
local TOKEN = "^%a[%w]*$"
local DATATYPE_ARITY: { [string]: number } =
	{ UDim2 = 4, UDim = 2, Vector2 = 2, Vector3 = 3, Rect = 4, NumberRange = 2 }

local document = {}

local function copyLiteral(value: Literal): Literal
	if type(value) == "table" then
		local copied: { [string | number]: Literal } = {}
		for key, item in value do
			copied[key] = copyLiteral(item)
		end
		return copied
	end
	return value
end
document.copyLiteral = copyLiteral

local function copyArgs(args: { Literal }?): { Literal }?
	if args == nil then
		return nil
	end
	local copied: { Literal } = {}
	for index, item in args do
		copied[index] = copyLiteral(item)
	end
	return copied
end

local function copyValue(value: Value): Value
	local current = value.literal
	return {
		literal = if current ~= nil then copyLiteral(current) else nil,
		input = value.input,
		item = value.item,
		output = value.output,
		args = copyArgs(value.args),
		fields = if value.fields then table.clone(value.fields) else nil,
		node = value.node,
		nodeFrom = value.nodeFrom,
		nodes = if value.nodes then table.clone(value.nodes) else nil,
		token = value.token,
		state = value.state,
		motion = value.motion,
		play = value.play,
	}
end
document.copyValue = copyValue

local function copyNode(node: Node): Node
	local props: { [string]: Value } = {}
	for key, value in node.props do
		props[key] = copyValue(value)
	end
	local children: { Node } = {}
	for index, child in node.children do
		children[index] = copyNode(child)
	end
	local bind = node.bind
	return {
		id = node.id,
		kind = node.kind,
		name = node.name,
		props = props,
		children = children,
		bind = if bind then { from = bind.from, key = bind.key, row = bind.row } else nil,
		nameField = node.nameField,
		nameInput = node.nameInput,
		when = node.when,
		tags = if node.tags then table.clone(node.tags) else nil,
	}
end

local function copyFields(source: { Types.ItemField }): { Types.ItemField }
	local list: { Types.ItemField } = {}
	for at, field in source do
		local nested = field.fields
		list[at] = {
			id = field.id,
			type = field.type,
			fields = if nested then copyFields(nested) else nil,
			luauType = field.luauType,
		}
	end
	return list
end

local function copyContract(contract: Types.Contract): Types.Contract
	local inputs: { Types.Input } = {}
	for index, input in contract.inputs do
		local source = input.fields
		local fields: { Types.ItemField }? = if source then copyFields(source) else nil
		local preview = input.preview
		inputs[index] = {
			id = input.id,
			kind = input.kind,
			type = input.type,
			preview = if preview ~= nil then copyLiteral(preview) else nil,
			fields = fields,
			required = input.required,
			luauType = input.luauType,
		}
	end
	local outputs: { Types.Output } = {}
	for index, output in contract.outputs do
		local args = output.args
		outputs[index] = { id = output.id, args = if args then table.clone(args) else nil, row = output.row }
	end
	return { inputs = inputs, outputs = outputs }
end

local function copyState(state: { Types.State }?): { Types.State }?
	if state == nil then
		return nil
	end
	local copied: { Types.State } = {}
	for index, entry in state do
		copied[index] = { id = entry.id, type = entry.type, initial = copyLiteral(entry.initial) }
	end
	return copied
end

local function copySequences(sequences: { Types.Sequence }?): { Types.Sequence }?
	if sequences == nil then
		return nil
	end
	local copied: { Types.Sequence } = {}
	for index, sequence in sequences do
		local steps: { Types.SequenceStep } = {}
		for at, step in sequence.steps do
			local target = step.to
			steps[at] = {
				delay = step.delay,
				duration = step.duration,
				easing = step.easing,
				state = step.state,
				to = if target ~= nil then copyLiteral(target) else nil,
				output = step.output,
			}
		end
		copied[index] = { id = sequence.id, autoplay = sequence.autoplay, steps = steps }
	end
	return copied
end

local function copyDocument(value: Document): Document
	return {
		schema = "compose-design/1",
		name = value.name,
		library = value.library,
		nextId = value.nextId,
		contract = copyContract(value.contract),
		state = copyState(value.state),
		sequences = copySequences(value.sequences),
		root = copyNode(value.root),
	}
end
document.copy = copyDocument

local function plain(value: Literal, depth: number): boolean
	if type(value) == "string" then
		return #value <= 10000
	elseif type(value) == "number" then
		return value == value and math.abs(value) < 1e9
	elseif type(value) == "table" then
		if depth >= 8 then
			return false
		end
		local count = 0
		for _, item in value do
			count += 1
			if count > 500 or not plain(item, depth + 1) then
				return false
			end
		end
	end
	return true
end
document.plain = plain

local function inputOf(value: Document, id: string): Types.Input?
	for _, input in value.contract.inputs do
		if input.id == id then
			return input
		end
	end
	return nil
end
document.input = inputOf

local function hasOutput(value: Document, id: string): boolean
	for _, output in value.contract.outputs do
		if output.id == id then
			return true
		end
	end
	return false
end

local function present(value: Value): number
	local count = 0
	if value.literal ~= nil then
		count += 1
	end
	if value.input ~= nil then
		count += 1
	end
	if value.item ~= nil then
		count += 1
	end
	if value.output ~= nil then
		count += 1
	end
	if value.token ~= nil then
		count += 1
	end
	if value.node ~= nil then
		count += 1
	end
	if value.nodeFrom ~= nil then
		count += 1
	end
	if value.state ~= nil then
		count += 1
	end
	if value.play ~= nil then
		count += 1
	end
	return count
end

local function checkTypeName(name: string?)
	if name == nil then
		return
	end
	assert(string.match(name, "^[%a_][%w_%.]*$") ~= nil, "A Luau type names a type or a qualified type")
	assert(
		string.sub(name, -1) ~= "." and not string.find(name, "..", 1, true),
		"A Luau type has no empty path segments"
	)
	for segment in string.gmatch(name, "[^%.]+") do
		assert(string.match(segment, "^[%a_][%w_]*$") ~= nil, "A Luau type has identifier path segments")
	end
end

local function checkFields(fields: { Types.ItemField }?)
	if fields == nil then
		return
	end
	for _, field in fields do
		checkTypeName(field.luauType)
		checkFields(field.fields)
	end
end

local function checkContract(contract: Types.Contract)
	local seen: { [string]: true } = {}
	for _, input in contract.inputs do
		assert(string.match(input.id, IDENTIFIER) ~= nil, "Input ids are lower camel case")
		assert(not seen[input.id], `Duplicate contract id {input.id}`)
		seen[input.id] = true
		checkTypeName(input.luauType)
		checkFields(input.fields)
		assert(input.type ~= "slot" or input.luauType == nil, `Slot input {input.id} uses the library return type`)
		local preview = input.preview
		assert(preview == nil or plain(preview, 0), `Preview for {input.id} must be plain data`)
		assert(input.type ~= "slot" or input.kind == "value", `Slot input {input.id} must be a value`)
	end
	for _, output in contract.outputs do
		assert(string.match(output.id, OUTPUT) ~= nil, "Outputs are named onSomething")
		assert(not seen[output.id], `Duplicate contract id {output.id}`)
		seen[output.id] = true
		local row = output.row
		if row ~= nil then
			local found = false
			for _, input in contract.inputs do
				found = found or (input.id == row and input.type == "list" and input.fields ~= nil)
			end
			assert(found, `{output.id} carries a row of {row}, which is not a list input with fields`)
		end
	end
end

local function listOf(value: Document, from: string, collection: Types.Input?): Types.Input?
	local declared = inputOf(value, from)
	if declared ~= nil then
		return declared
	end
	local fields = if collection then collection.fields else nil
	if fields ~= nil then
		for _, field in fields do
			if field.id == from and field.type == "list" then
				return { id = from, kind = "readable", type = "list", fields = field.fields }
			end
		end
	end
	return nil
end

local function stateOf(value: Document, id: string): Types.State?
	local state = value.state
	if state then
		for _, entry in state do
			if entry.id == id then
				return entry
			end
		end
	end
	return nil
end
document.stateOf = stateOf

local function sequenceOf(value: Document, id: string): Types.Sequence?
	local sequences = value.sequences
	if sequences then
		for _, sequence in sequences do
			if sequence.id == id then
				return sequence
			end
		end
	end
	return nil
end
document.sequenceOf = sequenceOf

local function cellsOf(current: Literal, found: { [string]: true }): { [string]: true }
	if type(current) == "table" then
		local template = current["$template"]
		if type(template) == "string" then
			found[template] = true
		else
			for _, item in current do
				cellsOf(item, found)
			end
		end
	end
	return found
end
document.cellsOf = cellsOf

local function checkOutputs(value: Document, current: Literal, key: string, collection: Types.Input?)
	if type(current) ~= "table" then
		return
	end
	local output = current["$output"]
	if output ~= nil then
		assert(type(output) == "string" and hasOutput(value, output), `{key} calls unknown output {tostring(output)}`)
		assert(current["$row"] == nil or collection ~= nil, `{key} passes a row outside a collection`)
		return
	end
	if current["$template"] ~= nil then
		assert(collection ~= nil, `{key} renders a cell outside a collection`)
		return
	end
	for _, item in current do
		checkOutputs(value, item, key, collection)
	end
end

local function checkValue(value: Document, field: Types.Field, property: Value, collection: Types.Input?, key: string)
	assert(present(property) == 1, `{key} holds exactly one literal or binding`)
	local played = property.play
	if played ~= nil then
		assert(sequenceOf(value, played) ~= nil, `{key} plays unknown sequence {played}`)
		assert(field.type == "event", `{key} cannot play a sequence`)
		return
	end
	local stateId = property.state
	if stateId ~= nil then
		assert(stateOf(value, stateId) ~= nil, `{key} reads unknown state {stateId}`)
		assert(field.type ~= "event" and field.type ~= "content" and field.type ~= "node", `{key} cannot hold state`)
		return
	end
	local current = property.literal
	local input, item, output = property.input, property.item, property.output
	if property.node ~= nil then
		assert(field.type == "node", `{key} cannot reference a node`)
		return
	end
	local source = property.nodeFrom
	if source ~= nil then
		assert(field.type == "node", `{key} cannot reference a node`)
		local declared = inputOf(value, source)
		local held = stateOf(value, source)
		local typed = if declared then declared.type elseif held then held.type else nil
		assert(typed == "string", `{key} follows {source}, which is not a text input or state`)
		local candidates = property.nodes
		assert(candidates ~= nil and #candidates > 0, `{key} names no candidate nodes`)
		return
	end
	assert(field.type ~= "node", `{key} references another node`)
	local holdsContent = field.type == "content"
	if current ~= nil and holdsContent then
		assert(
			type(current) == "table" and type(current["$template"]) == "string",
			`{key} holds a slot input or a content node`
		)
		return
	end
	if current ~= nil then
		assert(plain(current, 0), `{key} must be plain data`)
		checkOutputs(value, current, key, collection)
		local also = field.also
		if also ~= nil and table.find(also, type(current)) ~= nil then
			return
		end
		if field.type == "choice" then
			local options = field.options or {}
			assert(
				type(current) == "string" and table.find(options, current) ~= nil,
				`{key} must be one of its options`
			)
		elseif field.type == "number" then
			assert(type(current) == "number", `{key} must be a number`)
		elseif field.type == "boolean" then
			assert(type(current) == "boolean", `{key} must be true or false`)
		elseif field.type == "string" or field.type == "color" then
			assert(type(current) == "string", `{key} must be text`)
		elseif field.type == "vector3" then
			assert(
				type(current) == "table"
					and #current == 3
					and type(current[1]) == "number"
					and type(current[2]) == "number"
					and type(current[3]) == "number",
				`{key} must be three numbers`
			)
		elseif field.type == "datatype" then
			local datatype = assert(field.datatype, `{key} names no datatype`)
			if string.sub(datatype, 1, 5) == "Enum." then
				assert(type(current) == "string", `{key} must name an item of {datatype}`)
			else
				local arity = DATATYPE_ARITY[datatype]
				local valid = type(current) == "table" and (arity == nil or #current == arity)
				if valid and type(current) == "table" then
					for _, component in current do
						valid = valid and type(component) == "number"
					end
				end
				assert(valid, `{key} must be {arity or "some"} numbers for {datatype}`)
			end
		else
			assert(field.type == "value", `{key} must be bound`)
		end
	elseif input then
		local declared = assert(inputOf(value, input), `{key} reads unknown input {input}`)
		assert((field.type == "content") == (declared.type == "slot"), `{key} and input {input} do not match`)
		assert(field.type ~= "event", `{key} needs an output`)
	elseif item then
		local list = assert(collection, `{key} reads an item outside a collection template`)
		local fields = list.fields
		if fields then
			local found = false
			for _, entry in fields do
				found = found or entry.id == item
			end
			assert(found, `{key} reads unknown item field {item}`)
		end
	elseif output then
		assert(field.type == "event", `{key} cannot call an output`)
		assert(hasOutput(value, output), `{key} calls unknown output {output}`)
		local args = property.args
		if args then
			for _, argument in args do
				assert(plain(argument, 0), `{key} output arguments must be plain data`)
			end
		end
		local passed = property.fields
		if passed then
			local list = assert(collection, `{key} passes item fields outside a collection template`)
			local declared = list.fields
			if declared then
				for _, name in passed do
					local found = false
					for _, entry in declared do
						found = found or entry.id == name
					end
					assert(found, `{key} passes unknown item field {name}`)
				end
			end
		end
	else
		assert(field.tokens == true, `{key} does not take theme tokens`)
	end
end

function document.validate(value: Document, library: Library): Document
	assert(value.schema == "compose-design/1", "Unsupported design format")
	assert(value.library == library.name, `This design uses the {value.library} library`)
	assert(#value.name > 0 and #value.name <= 120, "A design needs a name")
	assert(value.nextId % 1 == 0 and value.nextId >= 1, "Invalid next node id")
	checkContract(value.contract)
	local state = value.state
	if state then
		for _, entry in state do
			assert(string.match(entry.id, IDENTIFIER) ~= nil, "State ids are lower camel case")
			assert(inputOf(value, entry.id) == nil and not hasOutput(value, entry.id), `Duplicate id {entry.id}`)
			assert(stateOf(value, entry.id) == entry, `Duplicate state id {entry.id}`)
			assert(entry.type ~= "slot", `State {entry.id} cannot be a slot`)
			assert(plain(entry.initial, 0), `State {entry.id} starts with plain data`)
		end
	end
	local sequences = value.sequences
	if sequences then
		assert(library.sequence ~= nil, `{library.name} cannot play sequences`)
		for _, sequence in sequences do
			local id = sequence.id
			assert(string.match(id, IDENTIFIER) ~= nil, "Sequence ids are lower camel case")
			assert(
				inputOf(value, id) == nil and not hasOutput(value, id) and stateOf(value, id) == nil,
				`Duplicate id {id}`
			)
			assert(sequenceOf(value, id) == sequence, `Duplicate sequence id {id}`)
			assert(#sequence.steps > 0 and #sequence.steps <= 32, `Sequence {id} holds 1 to 32 steps`)
			for _, step in sequence.steps do
				for _, token in { step.delay, step.duration, step.easing } do
					assert(
						type(token) == "string" and string.match(token, TOKEN) ~= nil,
						`Sequence {id} times steps with token names`
					)
				end
				local target = step.state
				assert((target == nil) == (step.to == nil), `Sequence {id} moves a state to a value`)
				assert(target == nil or stateOf(value, target) ~= nil, `Sequence {id} moves unknown state {target}`)
				local to = step.to
				assert(to == nil or plain(to, 0), `Sequence {id} moves state to plain data`)
				local output = step.output
				assert(output == nil or hasOutput(value, output), `Sequence {id} calls unknown output {output}`)
			end
		end
	end
	local seen: { [string]: true } = {}
	local count, highest = 0, 0
	local references: { [string]: string } = {}
	local liveCandidates: { string } = {}
	local nodeNames: { [string]: string } = {}
	local function visit(node: Node, depth: number, collection: Types.Input?)
		assert(depth <= MAX_DEPTH, "Designs nest at most 32 levels")
		count += 1
		assert(count <= MAX_NODES, "A design holds at most 500 nodes")
		local number = tonumber(string.match(node.id, "^n(%d+)$"))
		assert(number ~= nil and not seen[node.id], "Node ids must be unique")
		seen[node.id] = true
		nodeNames[node.id] = node.name
		highest = math.max(highest, number)
		local kind = assert(library.kinds[node.kind], `Unknown {library.name} kind {node.kind}`)
		assert(#node.name > 0 and #node.name <= 120, "A node needs a name")
		local nameField = node.nameField
		if nameField ~= nil then
			local list = assert(collection, `{node.name} takes its name from an item outside a collection template`)
			local declared = list.fields
			if declared then
				local found = false
				for _, entry in declared do
					found = found or entry.id == nameField
				end
				assert(found, `{node.name} takes its name from unknown item field {nameField}`)
			end
		end
		local nameInput = node.nameInput
		if nameInput ~= nil then
			assert(nameField == nil, `{node.name} takes its name from one source`)
			local declared =
				assert(inputOf(value, nameInput), `{node.name} takes its name from unknown input {nameInput}`)
			assert(
				declared.type == "string" and declared.kind == "value",
				`{node.name} takes its name from {nameInput}, which is not a text value`
			)
		end
		local condition = node.when
		if condition ~= nil then
			assert(library.show ~= nil, `{library.name} cannot show nodes conditionally`)
			assert(node ~= value.root, "The root is always shown")
			local declared = inputOf(value, condition)
			local held = stateOf(value, condition)
			local typed = if declared then declared.type elseif held then held.type else nil
			local itemFields = if collection then collection.fields else nil
			if typed == nil and itemFields ~= nil then
				for _, field in itemFields do
					if field.id == condition then
						typed = field.type
					end
				end
			end
			assert(typed == "boolean", `{node.name} is shown by {condition}, which is not a true or false input`)
		end
		local ownBind = node.bind
		local own = if ownBind then listOf(value, ownBind.from, collection) else nil
		local cells: { [string]: true } = {}
		for key, property in node.props do
			local field = assert(kind.fields[key], `{node.kind} has no property {key}`)
			local literal = property.literal
			assert(not field.perRow or own ~= nil, `{key} needs the node to repeat a list`)
			checkValue(value, field, property, if literal ~= nil and own ~= nil then own else collection, key)
			local role = property.motion
			if role ~= nil then
				local motion = assert(library.motion, `{library.name} has no motion roles`)
				assert(table.find(motion.roles, role) ~= nil, `{key} moves with unknown motion role {role}`)
				assert(
					property.input ~= nil or property.state ~= nil or property.item ~= nil,
					`{key} moves only when it follows an input, state or item`
				)
				assert(field.type ~= "event" and field.type ~= "content" and field.type ~= "node", `{key} cannot move`)
			end
			if literal ~= nil then
				cellsOf(literal, cells)
			end
			local target = property.node
			if target ~= nil then
				references[target] = key
			end
			local candidates = property.nodes
			if candidates then
				for _, candidate in candidates do
					references[candidate] = key
					table.insert(liveCandidates, candidate)
				end
			end
		end
		local nested = collection
		local rowCollection: Types.Input? = nil
		local rowId: string? = nil
		local ordinary = 0
		for _, child in node.children do
			if not cells[child.id] then
				ordinary += 1
			end
		end
		if kind.children == "none" then
			assert(ordinary == 0 and node.bind == nil, `{node.kind} holds no children`)
		elseif kind.children == "slot" then
			assert(ordinary <= 1 and node.bind == nil, `{node.kind} holds one content node`)
			assert(kind.slot ~= nil, `{node.kind} names no content property`)
		elseif kind.children == "template" then
			local bind = node.bind
			local rows = 0
			for _, child in node.children do
				if not cells[child.id] then
					rows += 1
				end
			end
			assert(
				rows <= 1 or kind.template == nil or (bind ~= nil and bind.row ~= nil),
				`{node.kind} holds one row template`
			)
			if bind then
				local list = assert(listOf(value, bind.from, collection), `{node.kind} binds unknown input {bind.from}`)
				assert(list.type == "list", `{node.kind} binds {bind.from}, which is not a list`)
				assert(#bind.key > 0, `{node.kind} needs an item key`)
				local row = bind.row
				if row ~= nil then
					local found = false
					for _, child in node.children do
						found = found or child.id == row
					end
					assert(found, `{node.kind} repeats unknown row {row}`)
					rowCollection = list
					rowId = row
				else
					nested = list
				end
			else
				assert(#node.children == 0, `{node.kind} needs a list input for its template`)
			end
		else
			local bind = node.bind
			if bind then
				assert(library.keyed ~= nil, `{library.name} cannot repeat children`)
				local list = assert(listOf(value, bind.from, collection), `{node.kind} binds unknown input {bind.from}`)
				assert(list.type == "list", `{node.kind} binds {bind.from}, which is not a list`)
				assert(#bind.key > 0, `{node.kind} needs an item key`)
				local row = bind.row
				if row == nil then
					local rows = 0
					for _, child in node.children do
						if not cells[child.id] then
							rows += 1
						end
					end
					assert(rows == 1, `{node.kind} repeats exactly one row template`)
				else
					local found = false
					for _, child in node.children do
						found = found or child.id == row
					end
					assert(found, `{node.kind} repeats unknown row {row}`)
				end
				rowCollection = list
				local first: string? = nil
				for _, child in node.children do
					if first == nil and not cells[child.id] then
						first = child.id
					end
				end
				rowId = row or first
			end
		end
		for id in cells do
			local found = false
			for _, child in node.children do
				found = found or child.id == id
			end
			assert(found, `{node.name} renders unknown cell {id}`)
		end
		for _, child in node.children do
			if cells[child.id] then
				visit(child, depth + 1, own or collection)
				continue
			end
			local isRow = rowCollection ~= nil and child.id == rowId
			assert(
				child.when == nil or (kind.children == "list" and not isRow),
				`{child.name} is shown conditionally only inside a list container, outside its row`
			)
			visit(child, depth + 1, if isRow then rowCollection else nested)
		end
	end
	visit(value.root, 0, nil)
	assert(value.nextId > highest, "Next node id must exceed every node id")
	for target, key in references do
		assert(seen[target], `{key} references unknown node {target}`)
	end
	local names: { [string]: string } = {}
	for _, candidate in liveCandidates do
		local name = assert(nodeNames[candidate])
		assert(string.match(name, "^[%a_][%w_]*$") ~= nil, `{name} must be a Luau name to be chosen by a reference`)
		assert(names[name] == nil or names[name] == candidate, `Two chosen nodes share the name {name}`)
		names[name] = candidate
	end
	return value
end

local function defaults(kind: Types.Kind): { [string]: Value }
	local props: { [string]: Value } = {}
	local source = kind.defaults
	if source then
		for key, item in source do
			props[key] = { literal = copyLiteral(item) }
		end
	end
	return props
end

function document.new(name: string, library: Library, rootKind: string): Document
	local kind = assert(library.kinds[rootKind], `Unknown {library.name} kind {rootKind}`)
	return {
		schema = "compose-design/1",
		name = name,
		library = library.name,
		nextId = 2,
		contract = { inputs = {}, outputs = {} },
		root = { id = "n1", kind = rootKind, name = rootKind, props = defaults(kind), children = {} },
	}
end

function document.find(root: Node, id: string): (Node?, Node?, number?)
	if root.id == id then
		return root, nil, nil
	end
	for index, child in root.children do
		if child.id == id then
			return child, root, index
		end
		local found, parent, at = document.find(child, id)
		if found then
			return found, parent, at
		end
	end
	return nil, nil, nil
end

export type Row = { node: Node, depth: number }

function document.nodes(root: Node): { Row }
	local rows: { Row } = {}
	local function visit(node: Node, depth: number)
		table.insert(rows, { node = node, depth = depth })
		for _, child in node.children do
			visit(child, depth + 1)
		end
	end
	visit(root, 0)
	return rows
end

function document.nameFrom(value: Document, library: Library, id: string, field: string?): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	node.nameField = field
	return document.validate(nextValue, library)
end

function document.insert(
	value: Document,
	library: Library,
	parentId: string,
	kindName: string,
	at: number?
): (Document, string)
	local nextValue = copyDocument(value)
	local parent = assert(document.find(nextValue.root, parentId), "Choose a container")
	local container = assert(library.kinds[parent.kind])
	assert(
		container.children == "list"
			or ((container.children == "template" or container.children == "slot") and #parent.children == 0)
			or (container.children == "template" and container.template == nil)
			or (container.children == "template" and parent.bind ~= nil and parent.bind.row ~= nil),
		`{parent.kind} cannot take this node`
	)
	local function create(seed: Types.Seed): Node
		local kind = assert(library.kinds[seed.kind], `Unknown {library.name} kind {seed.kind}`)
		local created: Node = {
			id = `n{nextValue.nextId}`,
			kind = seed.kind,
			name = seed.kind,
			props = defaults(kind),
			children = {},
		}
		nextValue.nextId += 1
		local literals = seed.props
		if literals then
			for key, item in literals do
				created.props[key] = { literal = copyLiteral(item) }
			end
		end
		local nested: { Types.Seed }? = seed.children or kind.seeds
		if nested then
			for _, child in nested do
				table.insert(created.children, create(child))
			end
		end
		return created
	end
	local node = create { kind = kindName }
	table.insert(parent.children, math.clamp(at or #parent.children + 1, 1, #parent.children + 1), node)
	return document.validate(nextValue, library), node.id
end

function document.applies(node: Node, kind: Types.Kind, key: string): boolean
	local field = kind.fields[key]
	local requires = if field then field.requires else nil
	if requires == nil then
		return true
	end
	for other, allowed in requires do
		local property = node.props[other]
		local defaults = kind.defaults
		local sibling = kind.fields[other]
		local current: Literal? = if property
			then property.literal
			elseif defaults and defaults[other] ~= nil then defaults[other]
			elseif sibling then sibling.default
			else nil
		if property ~= nil and current == nil then
			continue
		end
		if current == nil or (#allowed > 0 and table.find(allowed, current) == nil) then
			return false
		end
	end
	return true
end

function document.content(
	value: Document,
	library: Library,
	id: string,
	key: string,
	kindName: string
): (Document, string)
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	local kind = assert(library.kinds[node.kind])
	local field = assert(kind.fields[key], `{node.kind} has no property {key}`)
	assert(field.type == "content", `{key} does not hold content`)
	local child = assert(library.kinds[kindName], `Unknown {library.name} kind {kindName}`)
	local childId = `n{nextValue.nextId}`
	nextValue.nextId += 1
	table.insert(node.children, {
		id = childId,
		kind = kindName,
		name = kindName,
		props = defaults(child),
		children = {},
	})
	local marker: Types.Row = { ["$template"] = childId }
	node.props[key] = { literal = marker }
	return document.validate(nextValue, library), childId
end

function document.change(value: Document, library: Library, id: string, key: string, property: Value?): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	local previous = node.props[key]
	local before = if previous and previous.literal ~= nil then cellsOf(previous.literal, {}) else {}
	if property then
		node.props[key] = copyValue(property)
	else
		node.props[key] = nil
	end
	if next(before) ~= nil then
		local kept: { [string]: true } = {}
		for _, other in node.props do
			if other.literal ~= nil then
				cellsOf(other.literal, kept)
			end
		end
		for index = #node.children, 1, -1 do
			local childId = node.children[index].id
			if before[childId] and not kept[childId] then
				table.remove(node.children, index)
			end
		end
	end
	local kind = library.kinds[node.kind]
	if kind then
		local requires = if kind.fields[key] then kind.fields[key].requires else nil
		if property and requires and not document.applies(node, kind, key) then
			local needs: { string } = {}
			for other, allowed in requires do
				local listed: { string } = {}
				for _, item in allowed do
					table.insert(listed, tostring(item))
				end
				table.insert(
					needs,
					if #listed > 0 then `{other} is {table.concat(listed, " or ")}` else `{other} is set`
				)
			end
			table.sort(needs)
			error(`{key} applies only when {table.concat(needs, " and ")}`, 0)
		end
		local pruned = true
		while pruned do
			pruned = false
			for other in node.props do
				if not document.applies(node, kind, other) then
					node.props[other] = nil
					pruned = true
				end
			end
		end
	end
	return document.validate(nextValue, library)
end

function document.tag(value: Document, library: Library, id: string, tags: { string }?): Document
	assert(tags == nil or library.tags ~= nil, `{library.name} has no tags`)
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	if tags ~= nil then
		for _, tag in tags do
			assert(type(tag) == "string" and string.match(tag, "^[%w_%-]+$"), "A tag is letters, digits, - and _")
		end
	end
	node.tags = if tags ~= nil and #tags > 0 then table.clone(tags) else nil
	return document.validate(nextValue, library)
end

function document.rename(value: Document, library: Library, id: string, name: string): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	node.name = name
	return document.validate(nextValue, library)
end

function document.bind(value: Document, library: Library, id: string, bind: Types.Bind?): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	node.bind = if bind then { from = bind.from, key = bind.key, row = bind.row } else nil
	return document.validate(nextValue, library)
end

function document.remove(value: Document, library: Library, id: string): Document
	local nextValue = copyDocument(value)
	local _, parent, index = document.find(nextValue.root, id)
	assert(parent and index, "The root cannot be removed")
	table.remove(parent.children, index)
	return document.validate(nextValue, library)
end

function document.move(value: Document, library: Library, id: string, destination: string, before: number?): Document
	local nextValue = copyDocument(value)
	local node, parent, index = document.find(nextValue.root, id)
	assert(node and parent and index, "The root cannot move")
	assert(document.find(node, destination) == nil, "A node cannot move into itself")
	local target = assert(document.find(nextValue.root, destination), "Choose a container")
	table.remove(parent.children, index)
	table.insert(target.children, math.clamp(before or #target.children + 1, 1, #target.children + 1), node)
	return document.validate(nextValue, library)
end

function document.duplicate(value: Document, library: Library, id: string): (Document, string)
	local nextValue = copyDocument(value)
	local node, parent, index = document.find(nextValue.root, id)
	assert(node and parent and index, "The root cannot be duplicated")
	local twin = copyNode(node)
	for _, row in document.nodes(twin) do
		row.node.id = `n{nextValue.nextId}`
		nextValue.nextId += 1
	end
	table.insert(parent.children, index + 1, twin)
	return document.validate(nextValue, library), twin.id
end

function document.setContract(value: Document, library: Library, contract: Types.Contract): Document
	local nextValue = copyDocument(value)
	nextValue.contract = copyContract(contract)
	return document.validate(nextValue, library)
end

function document.nameFromInput(value: Document, library: Library, id: string, input: string?): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	node.nameInput = input
	return document.validate(nextValue, library)
end

function document.showWhen(value: Document, library: Library, id: string, condition: string?): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	node.when = condition
	return document.validate(nextValue, library)
end

function document.setSequences(value: Document, library: Library, sequences: { Types.Sequence }?): Document
	local nextValue = copyDocument(value)
	nextValue.sequences = if sequences ~= nil and #sequences > 0 then copySequences(sequences) else nil
	return document.validate(nextValue, library)
end

function document.setState(value: Document, library: Library, state: { Types.State }?): Document
	local nextValue = copyDocument(value)
	nextValue.state = copyState(state)
	return document.validate(nextValue, library)
end

return document
