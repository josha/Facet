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

local function copyValue(value: Value): Value
	local copied = table.clone(value)
	if type(copied.literal) == "table" then
		copied.literal = copyLiteral(copied.literal)
	end
	local args = copied.args
	if args then
		local arguments: { Literal } = {}
		for index, item in args do
			arguments[index] = copyLiteral(item)
		end
		copied.args = arguments
	end
	if copied.path then
		copied.path = table.clone(copied.path)
	end
	if copied.fields then
		copied.fields = table.clone(copied.fields)
	end
	if copied.nodes then
		copied.nodes = table.clone(copied.nodes)
	end
	return copied
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
	local variant: Types.RowVariant? = nil
	if node.rowVariant then
		local cases: { Types.VariantCase } = {}
		for _, alternative in node.rowVariant.cases do
			local wrapper = table.clone(node)
			wrapper.rowVariant = nil
			wrapper.props = alternative.props
			wrapper.children = alternative.children
			local copied = copyNode(wrapper)
			table.insert(
				cases,
				{ value = alternative.value, kind = alternative.kind, props = copied.props, children = copied.children }
			)
		end
		variant = { item = node.rowVariant.item, cases = cases }
	end
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
		rowVariant = variant,
		tagBinding = if node.tagBinding then copyValue(node.tagBinding) else nil,
		slot = node.slot,
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
			options = if field.options then table.clone(field.options) else nil,
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
			options = if input.options then table.clone(input.options) else nil,
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
	local variant = value.rootVariant
	local alternative: Types.RootVariant? = nil
	if variant then
		local props: { [string]: Value } = {}
		for key, property in variant.props do
			props[key] = copyValue(property)
		end
		local children: { Node }? = nil
		if variant.children then
			children = {}
			for _, child in variant.children do
				table.insert(children, copyNode(child))
			end
		end
		alternative =
			{ input = variant.input, value = variant.value, kind = variant.kind, props = props, children = children }
	end
	return {
		schema = "compose-design/1",
		name = value.name,
		library = value.library,
		nextId = value.nextId,
		contract = copyContract(value.contract),
		typeImports = if value.typeImports then table.clone(value.typeImports) else nil,
		state = copyState(value.state),
		sequences = copySequences(value.sequences),
		root = copyNode(value.root),
		rootVariant = alternative,
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
