--!strict

local Core = require "../core"
local Types = require "./types"

type ReadOnlyValue<T> = Core.Value<T>
type Use = Core.Use
type Literal = Types.Literal
type Row = Types.Row
type Resolved = Types.Resolved

export type Context = {
	inputs: { [string]: Literal }?,
	outputs: { [string]: (args: { Literal }) -> () }?,
	slots: { [string]: () -> unknown }?,
	token: ((name: string) -> Literal)?,
	decorate: ((node: Types.Node, built: unknown) -> ())?,
}

local function itemField(current: ReadOnlyValue<Row>, field: string): ReadOnlyValue<Literal?>
	return Core.formula(function(use: Use): Literal?
		return use(current)[field]
	end)
end

local function rowsOf(value: Literal?): { Row }
	local rows: { Row } = {}
	if type(value) == "table" then
		for _, item in value do
			if type(item) == "table" then
				table.insert(rows, item)
			end
		end
	end
	return rows
end

return function(value: Types.Document, library: Types.Library, context: Context?): unknown
	local supplied: { [string]: Literal } = if context and context.inputs then context.inputs else {}
	local outputs: { [string]: (args: { Literal }) -> () } = if context and context.outputs then context.outputs else {}
	local slots: { [string]: () -> unknown } = if context and context.slots then context.slots else {}
	local token = if context then context.token else nil
	local decorate = if context then context.decorate else nil
	local inputs: { [string]: Literal } = {}
	for _, input in value.contract.inputs do
		local override = supplied[input.id]
		local preview = input.preview
		if override ~= nil then
			inputs[input.id] = override
		elseif preview ~= nil then
			inputs[input.id] = preview
		end
	end
	local states: { [string]: Core.Value<Literal?> } = {}
	local declared = value.state
	if declared then
		for _, entry in declared do
			states[entry.id] = Core.cell(entry.initial :: Literal?)
		end
	end
	local function truthy(id: string): boolean
		local held = states[id]
		if held ~= nil then
			return held:peek() == true
		end
		return inputs[id] == true
	end
	local references: { [string]: Core.Value<unknown> } = {}
	local function collect(node: Types.Node)
		for _, property in node.props do
			local target = property.node
			if target ~= nil and references[target] == nil then
				references[target] = Core.cell(nil :: unknown)
			end
		end
		for _, child in node.children do
			collect(child)
		end
	end
	collect(value.root)
	local function carriesOutput(current: Literal): boolean
		if type(current) ~= "table" then
			return false
		end
		if current["$output"] ~= nil then
			return true
		end
		for _, item in current do
			if carriesOutput(item) then
				return true
			end
		end
		return false
	end
	local function withCallbacks(current: Literal): unknown
		if type(current) ~= "table" then
			return current
		end
		local output = current["$output"]
		if type(output) == "string" then
			return function(...: Literal)
				local handler = outputs[output]
				if handler then
					handler { ... }
				end
			end
		end
		local copied: { [string | number]: unknown } = {}
		for key, item in current do
			copied[key] = withCallbacks(item)
		end
		return copied
	end
	local function resolve(property: Types.Value, item: ReadOnlyValue<Row>?): Resolved
		local current, input, field, output, name =
			property.literal, property.input, property.item, property.output, property.token
		local target = property.node
		if target ~= nil then
			return { node = references[target] }
		end
		local stateId = property.state
		if stateId ~= nil then
			return { readable = states[stateId] }
		end
		if current ~= nil then
			if carriesOutput(current) then
				return { literal = current, value = withCallbacks(current) }
			end
			return { literal = current }
		elseif input then
			local slot = slots[input]
			if slot then
				return { slot = slot }
			end
			return { literal = inputs[input] }
		elseif field then
			return { readable = itemField(assert(item, "Item bindings need a template"), field) }
		elseif output then
			local passed = property.fields
			if passed then
				local row = assert(item, "Item fields need a template")
				local fixedArgs = property.args
				return {
					callback = function()
						local handler = outputs[output]
						if handler then
							local args: { Literal } = if fixedArgs then table.clone(fixedArgs) else {}
							local current = row:peek()
							for _, name in passed do
								local fieldValue = current[name]
								if fieldValue ~= nil then
									table.insert(args, fieldValue)
								end
							end
							handler(args)
						end
					end,
				}
			end
			local fixed = property.args
			return {
				callback = function(...: Literal)
					local handler = outputs[output]
					if handler then
						handler(if fixed then fixed else { ... })
					end
				end,
			}
		elseif name then
			local resolver = assert(token, "This design reads theme tokens; supply a token resolver")
			return { literal = resolver(name) }
		end
		return {}
	end
	local function build(node: Types.Node, item: ReadOnlyValue<Row>?): unknown
		local kind = assert(library.kinds[node.kind], `Unknown {library.name} kind {node.kind}`)
		local props: { [string]: Resolved } = {}
		for key, property in node.props do
			props[key] = resolve(property, item)
		end
		local children: { unknown } = {}
		local bind, template = node.bind, node.children[1]
		if kind.children == "slot" then
			if template then
				props[assert(kind.slot, `{node.kind} names no content property`)] = {
					slot = function(): unknown
						return build(template, item)
					end,
				}
			end
		elseif kind.children == "template" then
			if bind and template then
				local rows: ReadOnlyValue<{ Row }> = Core.cell(rowsOf(inputs[bind.from]))
				props[assert(kind.source, `{node.kind} names no list property`)] = { rows = rows, key = bind.key }
				props[assert(kind.template, `{node.kind} names no template property`)] = {
					template = function(row: ReadOnlyValue<Row>): unknown
						return build(template, row)
					end,
				}
			end
		elseif bind and template then
			local rowId = bind.row or template.id
			for _, child in node.children do
				if child.id == rowId then
					for _, row in rowsOf(inputs[bind.from]) do
						table.insert(children, build(child, Core.cell(row)))
					end
				elseif child.when == nil or truthy(child.when) then
					table.insert(children, build(child, item))
				end
			end
		else
			for _, child in node.children do
				local condition = child.when
				if condition == nil or truthy(condition) then
					table.insert(children, build(child, item))
				end
			end
		end
		local named = node.name
		local nameInput = node.nameInput
		if nameInput ~= nil then
			local supplied = inputs[nameInput]
			if type(supplied) == "string" and supplied ~= "" then
				named = supplied
			end
		end
		local nameField = node.nameField
		if nameField ~= nil and item ~= nil then
			local field = item:peek()[nameField]
			if field ~= nil then
				named = tostring(field)
			end
		end
		local built = kind.build(props, children, named)
		local captured = references[node.id]
		if captured ~= nil then
			captured:set(built)
		end
		if decorate then
			decorate(node, built)
		end
		return built
	end
	return build(value.root, nil)
end
