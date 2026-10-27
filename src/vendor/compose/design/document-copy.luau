--!strict

local Types = require "./types"
type Document = Types.Document
type Node = Types.Node
type Value = Types.Value
type Literal = Types.Literal

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
		hidden = node.hidden,
		locked = node.locked,
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

return {
	literal = copyLiteral,
	value = copyValue,
	node = copyNode,
	contract = copyContract,
	state = copyState,
	sequences = copySequences,
	document = copyDocument,
}
