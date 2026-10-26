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
	local function resolve(property: Types.Value, item: ReadOnlyValue<Row>?): Resolved
		local current, input, field, output, name =
			property.literal, property.input, property.item, property.output, property.token
		if current ~= nil then
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
		else
			for _, child in node.children do
				table.insert(children, build(child, item))
			end
		end
		local built = kind.build(props, children)
		if decorate then
			decorate(node, built)
		end
		return built
	end
	return build(value.root, nil)
end
