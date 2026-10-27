--!strict

local Core = require "../core"
local Types = require "./types"
local Document = require "./document"
local Datatype = require "./datatype"

type ReadOnlyValue<T> = Core.ReadOnlyValue<T>
type Use = Core.Use
type Literal = Types.Literal
type Row = Types.Row
type Resolved = Types.Resolved

export type Context = Types.RenderContext

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
	local bindings: { [string]: Resolved } = if context and context.bindings then context.bindings else {}
	local live = context ~= nil and context.bindings ~= nil
	local outputs: { [string]: (args: { Literal }) -> () } = if context and context.outputs then context.outputs else {}
	local slots: { [string]: () -> unknown } = if context and context.slots then context.slots else {}
	local token = if context then context.token else nil
	local resolveToken = if context then context.resolveToken else nil
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
	local players: { [string]: Types.Player } = {}
	local sequences, sequencing = value.sequences, library.sequence
	local playing = if sequencing then sequencing.build else nil
	if sequences ~= nil and playing ~= nil then
		local called: { [string]: () -> () } = {}
		for _, output in value.contract.outputs do
			called[output.id] = function()
				local handler = outputs[output.id]
				if handler then
					handler {}
				end
			end
		end
		for _, sequence in sequences do
			players[sequence.id] = playing(sequence, states, called)
		end
	end
	local shared = if context then context.players else nil
	if shared then
		shared(players)
	end
	local function inputValue(id: string, use: Use?): Literal?
		local binding = bindings[id]
		if binding ~= nil then
			local readable = binding.readable
			if readable ~= nil then
				return if use then use(readable) else readable:peek()
			end
			return binding.literal
		end
		return inputs[id]
	end
	local function truthy(id: string, item: ReadOnlyValue<Row>?, use: Use?): boolean
		local row = if item then (if use then use(item) else item:peek()) else nil
		if Document.input(value, id) == nil and row ~= nil and row[id] ~= nil then
			return row[id] == true
		end
		local held = states[id]
		if held ~= nil then
			return (if use then use(held) else held:peek()) == true
		end
		return inputValue(id, use) == true
	end
	local function listFrom(from: string, item: ReadOnlyValue<Row>?, use: Use?): { Row }
		local binding = bindings[from]
		local rows = if binding then binding.rows else nil
		if rows ~= nil then
			return if use then use(rows) else rows:peek()
		end
		if Document.input(value, from) == nil and item ~= nil then
			return rowsOf((if use then use(item) else item:peek())[from])
		end
		return rowsOf(inputValue(from, use))
	end
	local references: { [string]: Core.Value<unknown> } = {}
	local names: { [string]: string } = {}
	local function collect(node: Types.Node)
		names[node.id] = node.name
		for _, property in node.props do
			local target = property.node
			if target ~= nil and references[target] == nil then
				references[target] = Core.cell(nil :: unknown)
			end
			local candidates = property.nodes
			if candidates then
				for _, candidate in candidates do
					if references[candidate] == nil then
						references[candidate] = Core.cell(nil :: unknown)
					end
				end
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
		if current["$output"] ~= nil or current["$template"] ~= nil then
			return true
		end
		for _, item in current do
			if carriesOutput(item) then
				return true
			end
		end
		return false
	end
	local build: (node: Types.Node, item: ReadOnlyValue<Row>?) -> unknown
	local function withCallbacks(current: Literal, row: ReadOnlyValue<Row>?, owner: Types.Node): unknown
		if type(current) ~= "table" then
			return current
		end
		local template = current["$template"]
		if type(template) == "string" then
			local found = Document.find(owner, template)
			local cell = assert(found, `{owner.name} renders unknown cell {template}`)
			local repeated = owner.bind ~= nil
			return function(each: ReadOnlyValue<Row>?): unknown
				return build(cell, if repeated then each else row)
			end
		end
		local output = current["$output"]
		if type(output) == "string" then
			local passesRow = current["$row"] == true
			return function(...: Literal)
				local handler = outputs[output]
				if handler then
					handler(if passesRow then { assert(row, "Row outputs need a row"):peek() } else { ... })
				end
			end
		end
		local copied: { [string | number]: unknown } = {}
		for key, item in current do
			copied[key] = withCallbacks(item, row, owner)
		end
		return copied
	end
	local function resolve(
		property: Types.Value,
		item: ReadOnlyValue<Row>?,
		owner: Types.Node,
		definition: Types.Field?
	): Resolved
		local current, input, field, output, name =
			property.literal, property.input, property.item, property.output, property.token
		local target = property.node
		if target ~= nil then
			return { node = references[target] }
		end
		local source = property.nodeFrom
		if source ~= nil then
			local byName: { [string]: Core.Value<unknown> } = {}
			local candidates = property.nodes
			if candidates then
				for _, candidate in candidates do
					byName[names[candidate]] = references[candidate]
				end
			end
			local held = states[source]
			return {
				node = Core.formula(function(use: Use): unknown
					local chosen = if held ~= nil then use(held) else inputValue(source, use)
					local cell = if type(chosen) == "string" then byName[chosen] else nil
					return if cell then use(cell) else nil
				end),
			}
		end
		local stateId = property.state
		if stateId ~= nil then
			return { readable = states[stateId] }
		end
		local played = property.play
		if played ~= nil then
			return {
				callback = function()
					local player = players[played]
					if player then
						player.play()
					end
				end,
			}
		end
		if current ~= nil then
			if definition ~= nil and definition.type == "datatype" and type(current) == "table" then
				local components: { [number]: Resolved } = {}
				local reactive = false
				for index, component in current do
					local tokenName = Datatype.token(component)
					if tokenName ~= nil and type(index) == "number" then
						local resolver = resolveToken
						local resolved: Resolved = if resolver
							then resolver(tokenName)
							else {
								literal = assert(token, "This design reads theme tokens; supply a token resolver")(
									tokenName
								),
							}
						components[index] = resolved
						reactive = reactive or resolved.readable ~= nil
					end
				end
				if next(components) == nil then
					if definition.perRow then
						local literal = current
						return {
							literal = current,
							value = function(each: ReadOnlyValue<Row>): unknown
								return withCallbacks(literal, each, owner)
							end,
						}
					end
					return { literal = current }
				end
				local function numeric(use: Use?): Literal
					local result: { [string | number]: Literal } = table.clone(current)
					for index, resolved in components do
						local readable = resolved.readable
						local number = if readable
							then (if use then use(readable) else readable:peek())
							else if resolved.value ~= nil then resolved.value else resolved.literal
						assert(type(number) == "number", `Datatype component {index} needs a numeric token`)
						result[index] = number
					end
					return result
				end
				return if reactive
					then { readable = Core.formula(function(use: Use): Literal?
						return numeric(use)
					end) }
					else { literal = numeric(nil) }
			end
			if definition ~= nil and definition.perRow then
				local literal = current
				return {
					literal = current,
					value = function(each: ReadOnlyValue<Row>): unknown
						return withCallbacks(literal, each, owner)
					end,
				}
			end
			if carriesOutput(current) then
				return { literal = current, value = withCallbacks(current, item, owner) }
			end
			return { literal = current }
		elseif input then
			local binding = bindings[input]
			if binding ~= nil then
				return table.clone(binding)
			end
			local slot = slots[input]
			if slot then
				return { slot = slot }
			end
			return { literal = inputs[input] }
		elseif field then
			local row = assert(item, "Item bindings need a template")
			if definition ~= nil and definition.type == "string" then
				return {
					readable = Core.formula(function(use: Use): Literal?
						local current = use(row)[field]
						return if current == nil or type(current) == "string" then current else tostring(current)
					end),
				}
			end
			return { readable = itemField(row, field) }
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
			local resolved = if context then context.resolveToken else nil
			if resolved then
				return table.clone(resolved(name))
			end
			local resolver = assert(token, "This design reads theme tokens; supply a token resolver")
			return { literal = resolver(name) }
		end
		return {}
	end
	build = function(node: Types.Node, item: ReadOnlyValue<Row>?): unknown
		local kind = assert(library.kinds[node.kind], `Unknown {library.name} kind {node.kind}`)
		local props: { [string]: Resolved } = {}
		local cells: { [string]: true } = {}
		for key, property in node.props do
			local resolved = resolve(property, item, node, kind.fields[key])
			local role, readable = property.motion, resolved.readable
			local animate = if library.motion then library.motion.animate else nil
			if role ~= nil and readable ~= nil and animate ~= nil then
				resolved.readable = animate(readable, role)
			end
			props[key] = resolved
			local literal = property.literal
			if literal ~= nil then
				Document.cellsOf(literal, cells)
			end
		end
		local content: { Types.Node } = {}
		for _, child in node.children do
			if not cells[child.id] then
				table.insert(content, child)
			end
		end
		local children: { unknown } = {}
		local function append(child: Types.Node)
			local condition = child.when
			if condition ~= nil and live then
				table.insert(
					children,
					Core.show(function(use: Use): boolean
						return truthy(condition, item, use)
					end, function(): unknown
						return build(child, item)
					end)
				)
			elseif condition == nil or truthy(condition, item, nil) then
				table.insert(children, build(child, item))
			end
		end
		local bind, template = node.bind, content[1]
		if kind.children == "slot" then
			if template then
				props[assert(kind.slot, `{node.kind} names no content property`)] = {
					slot = function(): unknown
						return build(template, item)
					end,
				}
			end
		elseif kind.children == "template" then
			if bind then
				local rows: ReadOnlyValue<{ Row }> = if live
					then Core.formula(function(use: Use): { Row }
						return listFrom(bind.from, item, use)
					end)
					else Core.cell(listFrom(bind.from, item, nil))
				props[assert(kind.source, `{node.kind} names no list property`)] = { rows = rows, key = bind.key }
			end
			if kind.template == nil then
				for _, child in content do
					append(child)
				end
			elseif bind and template then
				local rowId = bind.row or template.id
				local rowNode = template
				for _, child in content do
					if child.id == rowId then
						rowNode = child
					else
						append(child)
					end
				end
				props[assert(kind.template)] = {
					template = function(row: ReadOnlyValue<Row>): unknown
						return build(rowNode, row)
					end,
				}
			end
		elseif bind and template then
			local rowId = bind.row or template.id
			for _, child in content do
				if child.id == rowId then
					if live then
						table.insert(
							children,
							Core.keyed {
								from = function(use: Use): { Row }
									return listFrom(bind.from, item, use)
								end,
								key = function(row: Row): Literal
									local key = row[bind.key]
									assert(key ~= nil, `A row needs key {bind.key}`)
									return key
								end,
								render = function(row: ReadOnlyValue<Row>): unknown
									return build(child, row)
								end,
							}
						)
					else
						for _, row in listFrom(bind.from, item, nil) do
							table.insert(children, build(child, Core.cell(row)))
						end
					end
				else
					append(child)
				end
			end
		else
			for _, child in content do
				append(child)
			end
		end
		local named = node.name
		local nameInput = node.nameInput
		if nameInput ~= nil then
			local supplied = inputValue(nameInput, nil)
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
		local tags, tagging = node.tags, library.tags
		if tags ~= nil and tagging ~= nil then
			tagging.apply(built, tags)
		end
		local captured = references[node.id]
		if captured ~= nil then
			captured:set(built)
		end
		if decorate then
			decorate(node, built)
		end
		return built
	end
	local root = build(value.root, nil)
	if sequences ~= nil then
		for _, sequence in sequences do
			local player = players[sequence.id]
			if sequence.autoplay and player then
				player.play()
			end
		end
	end
	return root
end
