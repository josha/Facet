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
		token = value.token,
		state = value.state,
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
		bind = if bind then { from = bind.from, key = bind.key } else nil,
		nameField = node.nameField,
		nameInput = node.nameInput,
		when = node.when,
	}
end

local function copyContract(contract: Types.Contract): Types.Contract
	local inputs: { Types.Input } = {}
	for index, input in contract.inputs do
		local fields: { Types.ItemField }? = nil
		local source = input.fields
		if source then
			local list: { Types.ItemField } = {}
			for at, field in source do
				list[at] = { id = field.id, type = field.type }
			end
			fields = list
		end
		local preview = input.preview
		inputs[index] = {
			id = input.id,
			kind = input.kind,
			type = input.type,
			preview = if preview ~= nil then copyLiteral(preview) else nil,
			fields = fields,
			required = input.required,
		}
	end
	local outputs: { Types.Output } = {}
	for index, output in contract.outputs do
		local args = output.args
		outputs[index] = { id = output.id, args = if args then table.clone(args) else nil }
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

local function copyDocument(value: Document): Document
	return {
		schema = "compose-design/1",
		name = value.name,
		library = value.library,
		nextId = value.nextId,
		contract = copyContract(value.contract),
		state = copyState(value.state),
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
	if value.state ~= nil then
		count += 1
	end
	return count
end

local function checkContract(contract: Types.Contract)
	local seen: { [string]: true } = {}
	for _, input in contract.inputs do
		assert(string.match(input.id, IDENTIFIER) ~= nil, "Input ids are lower camel case")
		assert(not seen[input.id], `Duplicate contract id {input.id}`)
		seen[input.id] = true
		local preview = input.preview
		assert(preview == nil or plain(preview, 0), `Preview for {input.id} must be plain data`)
		assert(input.type ~= "slot" or input.kind == "value", `Slot input {input.id} must be a value`)
	end
	for _, output in contract.outputs do
		assert(string.match(output.id, OUTPUT) ~= nil, "Outputs are named onSomething")
		assert(not seen[output.id], `Duplicate contract id {output.id}`)
		seen[output.id] = true
	end
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

local function checkValue(value: Document, field: Types.Field, property: Value, collection: Types.Input?, key: string)
	assert(present(property) == 1, `{key} holds exactly one literal or binding`)
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
	assert(field.type ~= "node", `{key} references another node`)
	if current ~= nil then
		assert(plain(current, 0), `{key} must be plain data`)
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
	local seen: { [string]: true } = {}
	local count, highest = 0, 0
	local references: { [string]: string } = {}
	local function visit(node: Node, depth: number, collection: Types.Input?)
		assert(depth <= MAX_DEPTH, "Designs nest at most 32 levels")
		count += 1
		assert(count <= MAX_NODES, "A design holds at most 500 nodes")
		local number = tonumber(string.match(node.id, "^n(%d+)$"))
		assert(number ~= nil and not seen[node.id], "Node ids must be unique")
		seen[node.id] = true
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
			assert(typed == "boolean", `{node.name} is shown by {condition}, which is not a true or false input`)
		end
		for key, property in node.props do
			local field = assert(kind.fields[key], `{node.kind} has no property {key}`)
			checkValue(value, field, property, collection, key)
			local target = property.node
			if target ~= nil then
				references[target] = key
			end
		end
		local nested = collection
		if kind.children == "none" then
			assert(#node.children == 0 and node.bind == nil, `{node.kind} holds no children`)
		elseif kind.children == "slot" then
			assert(#node.children <= 1 and node.bind == nil, `{node.kind} holds one content node`)
			assert(kind.slot ~= nil, `{node.kind} names no content property`)
		elseif kind.children == "template" then
			assert(#node.children <= 1, `{node.kind} holds one row template`)
			local bind = node.bind
			if bind then
				local list = assert(inputOf(value, bind.from), `{node.kind} binds unknown input {bind.from}`)
				assert(list.type == "list", `{node.kind} binds {bind.from}, which is not a list`)
				assert(#bind.key > 0, `{node.kind} needs an item key`)
				nested = list
			else
				assert(#node.children == 0, `{node.kind} needs a list input for its template`)
			end
		else
			local bind = node.bind
			if bind then
				assert(library.keyed ~= nil, `{library.name} cannot repeat children`)
				local list = assert(inputOf(value, bind.from), `{node.kind} binds unknown input {bind.from}`)
				assert(list.type == "list", `{node.kind} binds {bind.from}, which is not a list`)
				assert(#bind.key > 0, `{node.kind} needs an item key`)
				assert(#node.children == 1, `{node.kind} repeats exactly one row template`)
				nested = list
			end
		end
		for _, child in node.children do
			assert(
				child.when == nil or (kind.children == "list" and node.bind == nil),
				`{child.name} is shown conditionally only inside an unbound list container`
			)
			visit(child, depth + 1, nested)
		end
	end
	visit(value.root, 0, nil)
	assert(value.nextId > highest, "Next node id must exceed every node id")
	for target, key in references do
		assert(seen[target], `{key} references unknown node {target}`)
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
			or ((container.children == "template" or container.children == "slot") and #parent.children == 0),
		`{parent.kind} cannot take this node`
	)
	local kind = assert(library.kinds[kindName], `Unknown {library.name} kind {kindName}`)
	local id = `n{nextValue.nextId}`
	nextValue.nextId += 1
	local node: Node = { id = id, kind = kindName, name = kindName, props = defaults(kind), children = {} }
	table.insert(parent.children, math.clamp(at or #parent.children + 1, 1, #parent.children + 1), node)
	return document.validate(nextValue, library), id
end

function document.change(value: Document, library: Library, id: string, key: string, property: Value?): Document
	local nextValue = copyDocument(value)
	local node = assert(document.find(nextValue.root, id), "Choose a node")
	if property then
		node.props[key] = copyValue(property)
	else
		node.props[key] = nil
	end
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
	node.bind = if bind then { from = bind.from, key = bind.key } else nil
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

function document.setState(value: Document, library: Library, state: { Types.State }?): Document
	local nextValue = copyDocument(value)
	nextValue.state = copyState(state)
	return document.validate(nextValue, library)
end

return document
