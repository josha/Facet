--!strict

local Contract = require("./contract")
local Document = require("./document")
local Edit = require("./edit")
local Schema = require("../lib/schema")
local SourceMap = require("./source_map")
local Values = require("./values")
local Wire = require("./wire")

type Document = Document.Document
type Node = Document.Node
type Value = Values.Value
type Spec = Contract.Spec

export type Input = { [string]: unknown }
export type Result = { [string]: unknown }
export type Remap = { from: string, to: string }

export type Context = {
	doc: Document,
	schema: Schema.Schema?,
	inverse: { Edit.Restore },
	remap: { Remap },
	touched: { string },
}

export type Mutation = "none" | "document" | "comments"
export type Capability = "read" | "edit" | "comment"

export type Definition = {
	name: string,
	summary: string,
	input: Spec,
	mutation: Mutation,
	capability: Capability,
	internal: boolean?,
	run: (Context, Input) -> Result,
}

export type BatchResult = {
	doc: Document,
	inverse: { Edit.Restore },
	remap: { Remap },
	results: { Result },
	touched: { string },
}

local Operations = {}

local fail = Edit.fail

local NODE = Contract.string("Node id (label path such as Screen/Panel/Title) or a unique label.", { maxLength = 512 })
local PROP = Contract.string("Property name.", { pattern = "^[%a_][%w_]*$", maxLength = 64 })
local POSITION: { [string]: Spec } = {
	index = Contract.integer("Zero-based child position.", 0, 10000),
	before = Contract.string("Insert before this sibling id.", { maxLength = 512 }),
	after = Contract.string("Insert after this sibling id.", { maxLength = 512 }),
}

local function withPosition(fields: { [string]: Spec }): { [string]: Spec }
	local merged = table.clone(fields)
	for name, spec in POSITION do
		merged[name] = spec
	end
	return merged
end

local function text(input: Input, name: string): string?
	local value = input[name]
	return if type(value) == "string" then value else nil
end

local function required(input: Input, name: string): string
	local value = input[name]
	if type(value) ~= "string" then
		fail(name .. " is required")
	end
	return value :: string
end

local function integer(input: Input, name: string): number?
	local value = input[name]
	return if type(value) == "number" then value else nil
end

local function styleFor(doc: Document, indent: string, column: number): Values.Style
	return {
		indent = indent,
		unit = doc.style.unit,
		newline = doc.style.newline,
		cast = doc.style.cast,
		brackets = doc.style.brackets,
		useAnnotation = doc.style.useAnnotation,
		column = column,
		width = doc.style.width,
	}
end

local function resolve(ctx: Context, reference: string): Node
	local doc = ctx.doc
	if doc.root == nil then
		fail("the file is not a view module: " .. table.concat(doc.problems, "; "))
	end
	local exact = doc.nodes[reference]
	if exact then
		return exact
	end
	local matches: { Node } = {}
	for _, node in doc.order do
		if node.label == reference then
			table.insert(matches, node)
		end
	end
	if #matches == 1 then
		return matches[1]
	elseif #matches > 1 then
		local ids: { string } = {}
		for _, node in matches do
			table.insert(ids, node.id)
		end
		fail("label " .. reference .. " is not unique; use one of " .. table.concat(ids, ", "))
	end
	return fail("no node " .. reference)
end

local function controlNode(node: Node): Node
	if node.type ~= "control" then
		fail("node " .. node.id .. " is " .. node.type .. ", not a control")
	end
	return node
end

local function schemaControl(ctx: Context, node: Node): Schema.Control?
	local schema = ctx.schema
	if schema == nil or node.namespace ~= "UI" or node.kind == nil then
		return nil
	end
	return schema.controls[node.kind :: string]
end

local function suggestions(control: Schema.Control, name: string): string
	local close: { string } = {}
	local lower = string.lower(name)
	for _, field in control.props do
		local candidate = string.lower(field.name)
		if
			field.origin ~= "engine_types"
			and (string.find(candidate, lower, 1, true) or string.find(lower, candidate, 1, true))
		then
			table.insert(close, field.name)
		end
	end
	if #close == 0 then
		for _, field in control.props do
			if field.origin ~= "engine_types" and #close < 8 then
				table.insert(close, field.name)
			end
		end
	end
	return table.concat(close, ", ")
end

local function describeShape(shape: Schema.Shape): string
	local described = Schema.describe(shape)
	local tokens = Schema.tokenSets(shape)
	for set, values in tokens do
		described ..= " (" .. set .. " tokens: " .. table.concat(values, ", ") .. ")"
	end
	return described
end

local NO_VALUES: { Value } = {}
local NO_FIELDS: { [string]: Value } = {}
local NO_SCHEMA_FIELDS: { Schema.Field } = {}

local function itemsOf(value: Value): { Value }
	return value.items or NO_VALUES
end

local function fieldsOf(value: Value): { [string]: Value }
	return value.fields or NO_FIELDS
end

local function shapeFields(shape: Schema.Shape): { Schema.Field }
	return shape.fields or NO_SCHEMA_FIELDS
end

local function staticAccepts(shape: Schema.Shape, value: Value): (boolean, string?)
	local options = Schema.options(shape)
	local function has(kind: Schema.ShapeKind, name: string?): boolean
		for _, option in options do
			if option.kind == "unknown" or option.kind == "opaque" then
				return true
			end
			if option.kind == kind and (name == nil or option.name == name) then
				return true
			end
		end
		return false
	end
	local kind = value.kind
	if kind == "string" or kind == "token" then
		if has("string") then
			return true, nil
		end
		for _, literal in Schema.literals(shape) do
			if literal == value.value then
				return true, nil
			end
		end
		return false, nil
	elseif kind == "number" then
		return has("number"), nil
	elseif kind == "boolean" then
		if has("boolean") then
			return true, nil
		end
		for _, literal in Schema.literals(shape) do
			if literal == value.value then
				return true, nil
			end
		end
		return false, nil
	elseif kind == "nil" then
		return has("nil"), nil
	elseif kind == "datatype" then
		return has("roblox", value.type), nil
	elseif kind == "enum" then
		return has("enum", value.enum) or has("roblox", "EnumItem"), nil
	elseif kind == "table" then
		for _, option in options do
			if option.kind == "unknown" or option.kind == "opaque" then
				return true, nil
			end
			if option.kind == "array" and value.fields == nil then
				local element = option.element
				for _, item in itemsOf(value) do
					if element then
						local ok = staticAccepts(element, item)
						if not ok then
							return false, "an item does not match " .. Schema.describe(element)
						end
					end
				end
				return true, nil
			end
			if option.kind == "table" and value.items == nil then
				local known: { [string]: Schema.Field } = {}
				for _, field in shapeFields(option) do
					known[field.name] = field
				end
				local valid = true
				local problem: string? = nil
				for key, inner in fieldsOf(value) do
					local field = known[key]
					if field == nil then
						valid = false
						problem = "unknown field " .. key
						break
					end
					local ok = staticAccepts(field.shape, inner)
					if not ok then
						valid = false
						problem = "field " .. key .. " takes " .. describeShape(field.shape)
						break
					end
				end
				if valid then
					for _, field in shapeFields(option) do
						if not field.optional and fieldsOf(value)[field.name] == nil then
							valid = false
							problem = "field " .. field.name .. " is required"
						end
					end
				end
				if valid then
					return true, nil
				end
				if problem then
					return false, problem
				end
			end
		end
		return false, nil
	end
	return false, nil
end

local function checkKind(ctx: Context, namespace: string?, kind: string?, name: string, value: Value): Value
	local schema = ctx.schema
	if schema == nil or namespace ~= "UI" or kind == nil then
		return value
	end
	local control = schema.controls[kind :: string]
	if control == nil then
		return value
	end
	local field = Schema.field(control, name)
	if field == nil then
		fail(
			(kind :: string)
				.. " has no property "
				.. name
				.. "; known properties include "
				.. suggestions(control, name)
		)
	end
	local shape = (field :: Schema.Field).shape
	local label = (kind :: string) .. "." .. name
	if value.kind == "binding" then
		local readable = Schema.accepts(shape, "readable")
		local cell = Schema.accepts(shape, "cell")
		if not readable and not cell then
			fail(label .. " cannot take a binding; it takes " .. describeShape(shape))
		end
		if value.form == "use" and not readable then
			fail(label .. " needs a cell; bind it with form direct")
		end
		return value
	end
	local ok, problem = staticAccepts(shape, value)
	if not ok then
		fail(label .. " takes " .. describeShape(shape) .. (if problem then "; " .. problem else ""))
	end
	if (value.kind == "string" or value.kind == "token") and value.cast == nil then
		local casted = table.clone(value)
		casted.cast = ctx.doc.style.cast and not Schema.accepts(shape, "string") and #Schema.literals(shape) > 0
		if value.kind == "string" then
			for set, members in Schema.tokenSets(shape) do
				if table.find(members, value.value :: string) then
					casted.kind = "token"
					casted.set = set
				end
			end
		end
		return casted
	end
	return value
end

local function checkValue(ctx: Context, node: Node, name: string, value: Value): Value
	return checkKind(ctx, node.namespace, node.kind, name, value)
end

local function keyText(doc: Document, name: string): string
	if Values.isIdentifier(name) then
		return name
	end
	return "[" .. Values.quote(name) .. "]"
end

local function commit(ctx: Context, change: Edit.Change): Document
	local source = Edit.apply(ctx.doc.source, change.splice)
	local doc = Document.parse(source, ctx.schema)
	if doc.error then
		fail("the edit produced invalid Luau: " .. (doc.error :: string))
	end
	if doc.root == nil then
		fail("the edit broke the view module: " .. table.concat(doc.problems, "; "))
	end
	local anchor = doc.byStart[change.anchor]
	if anchor == nil then
		fail("the edit lost its node; the batch was not applied")
	end
	local inverse = table.clone(change.inverse)
	inverse.node = anchor.id
	table.insert(ctx.inverse, inverse)
	table.insert(ctx.touched, anchor.id)
	ctx.doc = doc
	return doc
end

local function mapOffset(offset: number, splice: Edit.Splice): number
	if offset >= splice.finish then
		return offset + #splice.text - (splice.finish - splice.start)
	end
	return offset
end

local NO_NODES: { Node } = {}

local function siblingLabels(parent: Node, except: { Node }?): { [string]: boolean }
	local taken: { [string]: boolean } = {}
	for _, child in parent.children do
		local skip = false
		for _, excluded in except or NO_NODES do
			if excluded == child then
				skip = true
			end
		end
		if not skip and child.label then
			taken[child.label :: string] = true
		end
	end
	return taken
end

local function uniqueLabel(taken: { [string]: boolean }, base: string): string
	local clean = string.gsub(base, "[^%w_]", "")
	if clean == "" or string.match(clean, "^%d") then
		clean = "Node" .. clean
	end
	if not taken[clean] then
		return clean
	end
	local index = 2
	while taken[clean .. index] do
		index += 1
	end
	return clean .. index
end

local function checkLabel(label: string)
	if not Values.isLabel(label) then
		fail("label " .. label .. " must be an identifier of at most 64 characters")
	end
end

local function propEntry(node: Node, name: string): number
	local props: { Document.Prop } = {}
	for _, prop in node.props do
		if not prop.opaque then
			table.insert(props, prop)
		end
	end
	if #props == 0 then
		return 1
	end
	local sorted = true
	for index = 2, #props do
		if props[index - 1].name > props[index].name then
			sorted = false
		end
	end
	if sorted then
		for _, prop in props do
			if prop.name > name then
				return prop.entry
			end
		end
	end
	return props[#props].entry + 1
end

local function childEntry(ctx: Context, parent: Node, input: Input, moving: Node?): number
	local children = parent.children
	local position = #children + 1
	local index = integer(input, "index")
	local before = text(input, "before")
	local after = text(input, "after")
	local given = (if index then 1 else 0) + (if before then 1 else 0) + (if after then 1 else 0)
	if given > 1 then
		fail("use at most one of index, before and after")
	end
	if index then
		position = math.clamp((index :: number) + 1, 1, #children + 1)
	elseif before or after then
		local sibling = resolve(ctx, (before or after) :: string)
		if sibling.parent ~= parent then
			fail("node " .. sibling.id .. " is not a child of " .. parent.id)
		end
		position = sibling.index + (if after then 1 else 0)
	end
	if moving and moving.parent == parent and moving.index < position then
		position -= 1
	end
	return position
end

local function entryForPosition(parent: Node, position: number): number
	local child = parent.children[position]
	if child and child.entry then
		return child.entry :: number
	end
	local tableExpr = parent.table
	return if tableExpr then #tableExpr.entries + 1 else 1
end

local Printer = {}

local function printProps(
	ctx: Context,
	holder: Node?,
	kind: string,
	props: { [string]: unknown },
	indent: string,
	scope: Values.Scope
): { string }
	local schema = ctx.schema
	local control = if schema then schema.controls[kind] else nil
	local names: { string } = {}
	for name in props do
		if type(name) == "string" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local lines: { string } = {}
	for _, name in names do
		if not Values.isIdentifier(name) then
			fail("property " .. name .. " must be an identifier")
		end
		local parsed, problem = Values.fromJson(props[name], name)
		if parsed == nil then
			fail(problem or ("invalid value for " .. name))
		end
		local value = parsed :: Value
		value = checkKind(ctx, "UI", kind, name, value)
		local prefix = keyText(ctx.doc, name) .. " = "
		local printed = Values.print(value, styleFor(ctx.doc, indent, Values.visualWidth(indent .. prefix)), scope)
		table.insert(lines, indent .. prefix .. printed .. ",")
	end
	if control then
		for _, field in control.props do
			if not field.optional and props[field.name] == nil then
				fail(kind .. " needs " .. field.name .. " (" .. describeShape(field.shape) .. ")")
			end
		end
	end
	return lines
end

function Printer.node(
	ctx: Context,
	spec: Input,
	indent: string,
	scope: Values.Scope,
	taken: { [string]: boolean }
): (string, string)
	local doc = ctx.doc
	local view = doc.view :: Document.View
	local newline = doc.style.newline
	local unit = doc.style.unit
	local inner = indent .. unit
	local keyed = spec.keyed
	if type(keyed) == "table" then
		local options = keyed :: Input
		if view.compose == nil then
			fail("a keyed collection needs local Compose = Facet.Compose in the view module")
		end
		if scope.model == nil then
			fail("a keyed collection needs a view function with a model parameter")
		end
		local itemName = text(options, "item") or "item"
		local template = options.template
		if type(template) ~= "table" then
			fail("keyed.template is required")
		end
		local from = required(options, "from")
		local key = text(options, "key")
		local templateScope: Values.Scope = { model = scope.model, item = itemName, use = scope.use }
		local deeper = inner .. unit
		local templateCore, templateLabel = Printer.node(ctx, template :: Input, deeper, templateScope, {})
		local lines = {
			(view.compose :: string) .. ".keyed({",
			inner .. "from = " .. Values.print(
				{ kind = "binding", path = from, source = "model", form = "direct" },
				styleFor(doc, inner, 0),
				scope
			) .. ",",
		}
		if key then
			table.insert(lines, inner .. "key = function(" .. itemName .. ")")
			table.insert(lines, deeper .. "return " .. itemName .. "." .. (key :: string))
			table.insert(lines, inner .. "end,")
		end
		table.insert(lines, inner .. "render = function(" .. itemName .. ")")
		table.insert(lines, deeper .. "return " .. templateCore)
		table.insert(lines, inner .. "end,")
		table.insert(lines, indent .. "})")
		return table.concat(lines, newline), templateLabel .. "[]"
	end
	local kind = text(spec, "kind")
	if kind == nil then
		fail("a node needs kind or keyed")
	end
	local schema = ctx.schema
	if schema and schema.controls[kind :: string] == nil then
		local names = table.concat(schema.order, ", ")
		fail("unknown control " .. (kind :: string) .. "; controls are " .. names)
	end
	local label = text(spec, "label")
	if label then
		checkLabel(label :: string)
		if taken[label :: string] then
			fail("label " .. (label :: string) .. " is already used by a sibling")
		end
	else
		label = uniqueLabel(taken, kind :: string)
	end
	taken[label :: string] = true
	local props = spec.props
	local lines = printProps(
		ctx,
		nil,
		kind :: string,
		if type(props) == "table" then props :: { [string]: unknown } else {},
		inner,
		scope
	)
	local childTaken: { [string]: boolean } = {}
	for _, child in Wire.list(spec.children) do
		if type(child) ~= "table" then
			fail("children must be node objects")
		end
		local core = Printer.node(ctx, child :: Input, inner, scope, childTaken)
		table.insert(lines, inner .. core .. ",")
	end
	local head = view.ui .. "." .. (kind :: string) .. " " .. Values.quote(label :: string)
	if #lines == 0 then
		return head .. " {}", label :: string
	end
	return head .. " {" .. newline .. table.concat(lines, newline) .. newline .. indent .. "}", label :: string
end

local function childAt(doc: Document, parentStart: number, position: number): string
	local parent = doc.byStart[parentStart]
	if parent == nil or parent.children[position] == nil then
		fail("the edited node could not be found after the edit")
	end
	return (parent :: Node).children[position].id
end

local function setValue(ctx: Context, node: Node, name: string, value: Value): Result
	local doc = ctx.doc
	local checked = checkValue(ctx, node, name, value)
	local prop = Document.prop(node, name)
	local map = doc.map :: SourceMap.SourceMap
	if prop then
		local span = SourceMap.expr(map, prop.item.value)
		local indent = Edit.indentAt(doc.source, SourceMap.item(map, prop.item).start)
		local lineStart = Edit.lineStart(doc.source, span.start)
		local column = Values.visualWidth(string.sub(doc.source, lineStart + 1, span.start))
		local printed = Values.print(checked, styleFor(doc, indent, column), node.scope)
		if printed == Document.text(doc, span) then
			return { node = node.id, changed = false }
		end
		commit(ctx, Edit.value(doc, node, prop, printed))
		return { node = node.id, changed = true }
	end
	if node.table == nil then
		fail("node " .. node.id .. " has no property table")
	end
	local indent = Edit.childIndent(doc, node)
	local prefix = keyText(doc, name) .. " = "
	local printed = Values.print(checked, styleFor(doc, indent, Values.visualWidth(indent .. prefix)), node.scope)
	commit(ctx, Edit.entries(doc, node, propEntry(node, name), 0, { Edit.newBlock(prefix .. printed, indent) }))
	return { node = node.id, changed = true }
end

local function unsetValue(ctx: Context, node: Node, name: string): Result
	local prop = Document.prop(node, name)
	if prop == nil then
		fail("node " .. node.id .. " does not set " .. name)
	end
	local control = schemaControl(ctx, node)
	if control then
		local field = Schema.field(control, name)
		if field and not field.optional then
			fail((node.kind :: string) .. " requires " .. name)
		end
	end
	commit(ctx, Edit.entries(ctx.doc, node, (prop :: Document.Prop).entry, 1, {}))
	return { node = node.id }
end

local function remapIds(ctx: Context, from: string, to: string)
	if from ~= to then
		table.insert(ctx.remap, { from = from, to = to })
	end
end

local definitions: { Definition } = {}

local function define(definition: Definition)
	table.insert(definitions, definition)
end

define({
	name = "query_tree",
	summary = "Return the node tree of the view: ids, control kinds, labels, properties and children.",
	input = Contract.object({
		node = Contract.string("Return only this subtree.", { maxLength = 512 }),
		depth = Contract.integer("Levels of children to include.", 0, 64),
	}),
	mutation = "none",
	capability = "read",
	run = function(ctx: Context, input: Input): Result
		local depth = integer(input, "depth")
		local reference = text(input, "node")
		if reference then
			local node = resolve(ctx, reference :: string)
			return { node = Document.nodeJson(ctx.doc, node, depth) }
		end
		return Document.json(ctx.doc, depth)
	end,
})

define({
	name = "get_node",
	summary = "Return one node with its properties and the schema of its control.",
	input = Contract.object({
		node = NODE,
		native = Contract.boolean("Include native Instance properties in the schema."),
	}, { "node" }),
	mutation = "none",
	capability = "read",
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		local result: Result = { node = Document.nodeJson(ctx.doc, node, 1) }
		local control = schemaControl(ctx, node)
		if control then
			result.schema = Schema.controlJson(control, input.native == true)
		end
		return result
	end,
})

define({
	name = "set_prop",
	summary = "Set a property of a control to a literal, token, binding, datatype, enum or table value.",
	input = Contract.object({
		node = NODE,
		prop = PROP,
		value = Contract.value("The new value."),
	}, { "node", "prop", "value" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = controlNode(resolve(ctx, required(input, "node")))
		local value, problem = Values.fromJson(input.value)
		if value == nil then
			fail(problem or "invalid value")
		end
		return setValue(ctx, node, required(input, "prop"), value :: Value)
	end,
})

define({
	name = "unset_prop",
	summary = "Remove a property from a control so the control uses its default.",
	input = Contract.object({ node = NODE, prop = PROP }, { "node", "prop" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = controlNode(resolve(ctx, required(input, "node")))
		return unsetValue(ctx, node, required(input, "prop"))
	end,
})

define({
	name = "insert",
	summary = "Insert a new control or keyed collection under a parent control.",
	input = Contract.object(
		withPosition({
			parent = Contract.string("Parent node id.", { maxLength = 512 }),
			node = Contract.node("The node to insert."),
		}),
		{ "parent", "node" }
	),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local parent = controlNode(resolve(ctx, required(input, "parent")))
		if parent.table == nil then
			fail("node " .. parent.id .. " cannot hold children")
		end
		local doc = ctx.doc
		local position = childEntry(ctx, parent, input, nil)
		local indent = Edit.childIndent(doc, parent)
		local core = Printer.node(ctx, input.node :: Input, indent, parent.scope, siblingLabels(parent))
		local parentStart = parent.span.start
		commit(ctx, Edit.entries(doc, parent, entryForPosition(parent, position), 0, { Edit.newBlock(core, indent) }))
		return { node = childAt(ctx.doc, parentStart, position) }
	end,
})

define({
	name = "remove",
	summary = "Remove a node and its subtree.",
	input = Contract.object({ node = NODE }, { "node" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		local parent = node.parent
		if node.slot ~= "entry" or parent == nil or node.entry == nil then
			fail("node " .. node.id .. " is the root or a collection template and cannot be removed")
		end
		local id = node.id
		commit(ctx, Edit.entries(ctx.doc, parent :: Node, node.entry :: number, 1, {}))
		return { removed = id }
	end,
})

define({
	name = "move",
	summary = "Move a node to another parent or another position under the same parent.",
	input = Contract.object(
		withPosition({
			node = NODE,
			parent = Contract.string("New parent node id.", { maxLength = 512 }),
		}),
		{ "node", "parent" }
	),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local doc = ctx.doc
		local node = resolve(ctx, required(input, "node"))
		local target = controlNode(resolve(ctx, required(input, "parent")))
		local parent = node.parent
		if node.slot ~= "entry" or parent == nil or node.entry == nil then
			fail("node " .. node.id .. " is the root or a collection template and cannot move")
		end
		if Document.isAncestor(node, target) then
			fail("node " .. node.id .. " cannot move inside itself")
		end
		if target.table == nil then
			fail("node " .. target.id .. " cannot hold children")
		end
		if target ~= parent and node.label and siblingLabels(target)[node.label :: string] then
			fail("label " .. (node.label :: string) .. " is already used under " .. target.id)
		end
		local position = childEntry(ctx, target, input, node)
		local oldId = node.id
		local block = Edit.nodeBlock(doc, node)
		local targetStart = target.span.start
		local removal = Edit.entries(doc, parent :: Node, node.entry :: number, 1, {})
		local afterRemoval = commit(ctx, removal)
		local moved = afterRemoval.byStart[mapOffset(targetStart, removal.splice)]
		if moved == nil then
			fail("the target parent changed during the move")
		end
		local destination = moved :: Node
		local destinationStart = destination.span.start
		commit(ctx, Edit.entries(afterRemoval, destination, entryForPosition(destination, position), 0, { block }))
		local newId = childAt(ctx.doc, destinationStart, position)
		remapIds(ctx, oldId, newId)
		return { node = newId }
	end,
})

define({
	name = "wrap",
	summary = "Wrap one node, or adjacent sibling nodes, in a new container control.",
	input = Contract.object({
		nodes = Contract.array(NODE, "Adjacent sibling ids in order.", 1, 200),
		node = NODE,
		kind = Contract.KIND,
		label = Contract.LABEL,
		props = Contract.map(Contract.value(), "Properties of the container."),
	}, { "kind" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local doc = ctx.doc
		local references: { string } = {}
		for _, item in Wire.list(input.nodes) do
			table.insert(references, item :: string)
		end
		local single = text(input, "node")
		if single then
			table.insert(references, single :: string)
		end
		if #references == 0 then
			fail("wrap needs node or nodes")
		end
		local nodes: { Node } = {}
		for _, reference in references do
			table.insert(nodes, resolve(ctx, reference))
		end
		table.sort(nodes, function(left: Node, right: Node): boolean
			return left.index < right.index
		end)
		local first = nodes[1]
		local parent = first.parent
		for position, node in nodes do
			if node.parent ~= parent then
				fail("wrapped nodes must share one parent")
			end
			if position > 1 then
				local previous = nodes[position - 1]
				if node.slot ~= "entry" or (node.entry :: number) ~= (previous.entry :: number) + 1 then
					fail("wrapped nodes must be adjacent entries")
				end
			end
		end
		local kind = required(input, "kind")
		local view = doc.view :: Document.View
		local taken = if parent then siblingLabels(parent :: Node, nodes) else {}
		local label = text(input, "label")
		if label then
			checkLabel(label :: string)
			if taken[label :: string] then
				fail("label " .. (label :: string) .. " is already used by a sibling")
			end
		else
			label = uniqueLabel(taken, kind)
		end
		local schema = ctx.schema
		if schema and schema.controls[kind] == nil then
			fail("unknown control " .. kind)
		end
		local indent: string
		if first.slot == "entry" and parent then
			indent = Edit.childIndent(doc, parent :: Node)
		else
			if #nodes > 1 then
				fail("only one node can be wrapped at the root or in a collection template")
			end
			indent = Edit.indentAt(doc.source, first.span.start)
		end
		local inner = indent .. doc.style.unit
		local props = input.props
		local lines = printProps(
			ctx,
			nil,
			kind,
			if type(props) == "table" then props :: { [string]: unknown } else {},
			inner,
			first.scope
		)
		local newline = doc.style.newline
		local body = table.concat(lines, newline)
		local blockText = ""
		for _, node in nodes do
			blockText ..= Edit.formatBlock(Edit.nodeBlock(doc, node), inner, newline)
		end
		local core = view.ui
			.. "."
			.. kind
			.. " "
			.. Values.quote(label :: string)
			.. " {"
			.. newline
			.. (if body ~= "" then body .. newline else "")
			.. blockText
			.. indent
			.. "}"
		local oldIds: { { id: string, segment: string } } = {}
		for _, node in nodes do
			table.insert(oldIds, { id = node.id, segment = node.segment })
		end
		local wrapperId: string
		if first.slot == "entry" and parent then
			local parentStart = (parent :: Node).span.start
			local position = first.index
			commit(
				ctx,
				Edit.entries(doc, parent :: Node, first.entry :: number, #nodes, { Edit.newBlock(core, indent) })
			)
			wrapperId = childAt(ctx.doc, parentStart, position)
		else
			local wrapStart = first.span.start
			commit(ctx, Edit.expr(doc, first, core))
			wrapperId = (ctx.doc.byStart[wrapStart] :: Node).id
		end
		for _, old in oldIds do
			remapIds(ctx, old.id, wrapperId .. "/" .. old.segment)
		end
		return { node = wrapperId }
	end,
})

define({
	name = "unwrap",
	summary = "Replace a container with its children. The container properties are removed.",
	input = Contract.object({ node = NODE }, { "node" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local doc = ctx.doc
		local node = controlNode(resolve(ctx, required(input, "node")))
		local parent = node.parent
		local oldId = node.id
		if node.slot == "entry" and parent and node.entry then
			local taken = siblingLabels(parent :: Node, { node })
			for _, child in node.children do
				if child.label and taken[child.label :: string] then
					fail("label " .. (child.label :: string) .. " is already used under " .. (parent :: Node).id)
				end
			end
			local blocks: { Edit.Block } = {}
			for _, child in node.children do
				table.insert(blocks, Edit.nodeBlock(doc, child))
			end
			local own = Edit.nodeBlock(doc, node)
			if #blocks > 0 and own.lead ~= "" then
				local firstBlock = table.clone(blocks[1])
				firstBlock.lead = Edit.reindent(own.lead, own.leadFixed, own.base, firstBlock.base, false)
					.. firstBlock.lead
				blocks[1] = firstBlock
			end
			local parentId = (parent :: Node).id
			local segments: { string } = {}
			for _, child in node.children do
				table.insert(segments, child.segment)
			end
			commit(ctx, Edit.entries(doc, parent :: Node, node.entry :: number, 1, blocks))
			for _, segment in segments do
				remapIds(ctx, oldId .. "/" .. segment, parentId .. "/" .. segment)
			end
			return { parent = parentId }
		end
		if #node.children ~= 1 or node.children[1].type ~= "control" then
			fail("the root or a template can be unwrapped only when it has exactly one child control")
		end
		local child = node.children[1]
		local block = Edit.nodeBlock(doc, child)
		local indent = Edit.indentAt(doc.source, node.span.start)
		local core = Edit.reindent(block.core, block.coreFixed, block.base, indent, true)
		local start = node.span.start
		local segment = child.segment
		commit(ctx, Edit.expr(doc, node, core))
		local newRoot = ctx.doc.byStart[start] :: Node
		remapIds(ctx, oldId .. "/" .. segment, newRoot.id)
		return { node = newRoot.id }
	end,
})

define({
	name = "rename",
	summary = "Change the label of a control. The label is the last segment of its id.",
	input = Contract.object({ node = NODE, label = Contract.LABEL }, { "node", "label" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = controlNode(resolve(ctx, required(input, "node")))
		local label = required(input, "label")
		checkLabel(label)
		if node.label == label then
			return { node = node.id, changed = false }
		end
		local parent = node.parent
		if parent and node.slot == "entry" and siblingLabels(parent :: Node, { node })[label] then
			fail("label " .. label .. " is already used by a sibling")
		end
		local oldId = node.id
		local start = node.span.start
		commit(ctx, Edit.label(ctx.doc, node, label))
		local renamed = ctx.doc.byStart[start] :: Node
		remapIds(ctx, oldId, renamed.id)
		return { node = renamed.id, changed = true }
	end,
})

define({
	name = "bind",
	summary = "Bind a property to a model path, or to an item field inside a collection template.",
	input = Contract.object({
		node = NODE,
		prop = PROP,
		path = Contract.string("Dotted path such as stats.coins.", { pattern = "^[%w_%.]*$", maxLength = 256 }),
		source = Contract.string("model or item.", { enum = { "model", "item" } }),
		form = Contract.string(
			"use makes function(use) return use(model.path) end; direct passes the readable itself.",
			{ enum = { "use", "direct" } }
		),
	}, { "node", "prop", "path" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		local name = required(input, "prop")
		local source = text(input, "source") or "model"
		local form = text(input, "form")
		if node.type == "keyed" then
			if name ~= "from" then
				fail("a collection binds only its from property")
			end
			form = "direct"
		else
			controlNode(node)
		end
		if form == nil then
			form = "use"
			local control = schemaControl(ctx, node)
			local field = if control then Schema.field(control, name) else nil
			if field and not Schema.accepts(field.shape, "readable") and Schema.accepts(field.shape, "cell") then
				form = "direct"
			end
		end
		local value, problem = Values.fromJson({
			kind = "binding",
			path = required(input, "path"),
			source = source,
			form = form,
		})
		if value == nil then
			fail(problem or "invalid binding")
		end
		if node.type == "keyed" then
			local prop = Document.prop(node, "from")
			if prop == nil then
				fail("the collection has no from property")
			end
			local printed = Values.print(value :: Value, styleFor(ctx.doc, "", 0), node.scope)
			commit(ctx, Edit.value(ctx.doc, node, prop :: Document.Prop, printed))
			return { node = node.id }
		end
		return setValue(ctx, node, name, value :: Value)
	end,
})

define({
	name = "unbind",
	summary = "Replace a bound property with a literal value, or remove it.",
	input = Contract.object({ node = NODE, prop = PROP, value = Contract.value("A literal to use instead.") }, {
		"node",
		"prop",
	}),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = controlNode(resolve(ctx, required(input, "node")))
		local name = required(input, "prop")
		local prop = Document.prop(node, name)
		if prop == nil or prop.value.kind ~= "binding" then
			fail("node " .. node.id .. " has no binding for " .. name)
		end
		if input.value ~= nil then
			local value, problem = Values.fromJson(input.value)
			if value == nil then
				fail(problem or "invalid value")
			end
			if (value :: Value).kind == "binding" then
				fail("unbind needs a literal value")
			end
			return setValue(ctx, node, name, value :: Value)
		end
		return unsetValue(ctx, node, name)
	end,
})

define({
	name = "set_token",
	summary = "Set a property to a theme token, such as a space step or a text role.",
	input = Contract.object({
		node = NODE,
		prop = PROP,
		token = Contract.string("Token name, for example m or title.", { pattern = "^[%a][%w_]*$", maxLength = 64 }),
	}, { "node", "prop", "token" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local node = controlNode(resolve(ctx, required(input, "node")))
		local name = required(input, "prop")
		local token = required(input, "token")
		local control = schemaControl(ctx, node)
		local set: string? = nil
		if control then
			local field = Schema.field(control, name)
			if field == nil then
				fail((node.kind :: string) .. " has no property " .. name)
			end
			local sets = Schema.tokenSets((field :: Schema.Field).shape)
			local available: { string } = {}
			for setName, members in sets do
				for _, member in members do
					table.insert(available, member)
				end
				if table.find(members, token) then
					set = setName
				end
			end
			if #available == 0 then
				fail((node.kind :: string) .. "." .. name .. " takes no theme tokens")
			end
			if set == nil then
				table.sort(available)
				fail(
					token
						.. " is not a token of "
						.. (node.kind :: string)
						.. "."
						.. name
						.. "; use "
						.. table.concat(available, ", ")
				)
			end
		end
		return setValue(ctx, node, name, { kind = "token", value = token, set = set })
	end,
})

define({
	name = "duplicate",
	summary = "Insert a copy of a control right after it, with a unique label.",
	input = Contract.object({ node = NODE, label = Contract.LABEL }, { "node" }),
	mutation = "document",
	capability = "edit",
	run = function(ctx: Context, input: Input): Result
		local doc = ctx.doc
		local node = controlNode(resolve(ctx, required(input, "node")))
		local parent = node.parent
		if node.slot ~= "entry" or parent == nil or node.entry == nil then
			fail("node " .. node.id .. " is the root or a collection template and cannot be duplicated")
		end
		local taken = siblingLabels(parent :: Node)
		local label = text(input, "label")
		if label then
			checkLabel(label :: string)
			if taken[label :: string] then
				fail("label " .. (label :: string) .. " is already used by a sibling")
			end
		else
			label = uniqueLabel(taken, node.label or (node.kind :: string))
		end
		local block = Edit.nodeBlock(doc, node)
		local copy = Edit.relabel(doc, node, block, label :: string)
		copy.lead = ""
		copy.trail = ""
		local parentStart = (parent :: Node).span.start
		local position = node.index + 1
		commit(ctx, Edit.entries(doc, parent :: Node, (node.entry :: number) + 1, 0, { copy }))
		return { node = childAt(ctx.doc, parentStart, position) }
	end,
})

local RESTORE_FIELDS = {
	node = NODE,
	text = Contract.string("Exact source text to restore."),
	expect = Contract.string("Exact source text that must be present now."),
}

local function restoreSpec(extra: { [string]: Spec }): Spec
	local fields = table.clone(RESTORE_FIELDS)
	for name, spec in extra do
		fields[name] = spec
	end
	return Contract.object(fields, { "node", "text", "expect" })
end

define({
	name = "restore_entries",
	summary = "Restore exact table entries recorded by the history.",
	input = restoreSpec({
		start = Contract.integer(nil, 1, 100000),
		count = Contract.integer(nil, 0, 100000),
		whole = Contract.boolean(),
	}),
	mutation = "document",
	capability = "edit",
	internal = true,
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		local whole = input.whole == true
		commit(
			ctx,
			Edit.restoreEntries(
				ctx.doc,
				node,
				integer(input, "start") or 1,
				integer(input, "count") or 0,
				whole,
				required(input, "text"),
				required(input, "expect")
			)
		)
		return { node = node.id }
	end,
})

define({
	name = "restore_value",
	summary = "Restore an exact property value recorded by the history.",
	input = restoreSpec({ prop = Contract.string() }),
	mutation = "document",
	capability = "edit",
	internal = true,
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		local prop = Document.prop(node, required(input, "prop"))
		if prop == nil then
			fail("node " .. node.id .. " changed after this edit")
		end
		commit(
			ctx,
			Edit.restoreValue(ctx.doc, node, prop :: Document.Prop, required(input, "text"), required(input, "expect"))
		)
		return { node = node.id }
	end,
})

define({
	name = "restore_label",
	summary = "Restore an exact label recorded by the history.",
	input = restoreSpec({}),
	mutation = "document",
	capability = "edit",
	internal = true,
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		commit(ctx, Edit.restoreLabel(ctx.doc, node, required(input, "text"), required(input, "expect")))
		return { node = node.id }
	end,
})

define({
	name = "restore_expr",
	summary = "Restore an exact node expression recorded by the history.",
	input = restoreSpec({}),
	mutation = "document",
	capability = "edit",
	internal = true,
	run = function(ctx: Context, input: Input): Result
		local node = resolve(ctx, required(input, "node"))
		commit(ctx, Edit.restoreExpr(ctx.doc, node, required(input, "text"), required(input, "expect")))
		return { node = node.id }
	end,
})

local byName: { [string]: Definition } = {}
for _, definition in definitions do
	byName[definition.name] = definition
end

Operations.definitions = definitions
Operations.byName = byName
Operations.MAX_BATCH = 200

function Operations.get(name: string): Definition?
	return byName[name]
end

function Operations.validate(ops: unknown, allowInternal: boolean?): (boolean, string?)
	if type(ops) ~= "table" or not Wire.isArray(ops) then
		return false, "a batch must be a JSON array of operations"
	end
	local list = ops :: { unknown }
	if #list == 0 then
		return false, "a batch needs at least one operation"
	end
	if #list > Operations.MAX_BATCH then
		return false, "a batch allows at most " .. Operations.MAX_BATCH .. " operations"
	end
	for index, op in list do
		local where = "operation " .. index
		if type(op) ~= "table" then
			return false, where .. " must be an object"
		end
		local name = (op :: { [string]: unknown }).op
		if type(name) ~= "string" then
			return false, where .. " needs an op name"
		end
		local definition = byName[name :: string]
		if definition == nil or definition.mutation ~= "document" or (definition.internal and not allowInternal) then
			return false, where .. ": " .. tostring(name) .. " is not a document operation"
		end
		local input = table.clone(op :: { [string]: unknown })
		input.op = nil
		local problem = Contract.check(definition.input, input, where .. " (" .. (name :: string) .. ")")
		if problem then
			return false, problem
		end
	end
	return true, nil
end

function Operations.run(doc: Document, schema: Schema.Schema?, name: string, input: Input): (Result?, string?)
	local definition = byName[name]
	if definition == nil then
		return nil, "unknown operation " .. name
	end
	local problem = Contract.check(definition.input, input, name)
	if problem then
		return nil, problem
	end
	local ctx: Context = { doc = doc, schema = schema, inverse = {}, remap = {}, touched = {} }
	local ok, result = pcall(definition.run, ctx, input)
	if not ok then
		return nil, tostring(result)
	end
	return result :: Result, nil
end

function Operations.apply(
	doc: Document,
	schema: Schema.Schema?,
	ops: unknown,
	allowInternal: boolean?
): (BatchResult?, string?)
	if doc.error then
		return nil, "the file does not parse: " .. (doc.error :: string)
	end
	if doc.root == nil then
		return nil, "the file is not a view module: " .. table.concat(doc.problems, "; ")
	end
	local valid, problem = Operations.validate(ops, allowInternal)
	if not valid then
		return nil, problem
	end
	local ctx: Context = { doc = doc, schema = schema, inverse = {}, remap = {}, touched = {} }
	local results: { Result } = {}
	for index, op in ops :: { unknown } do
		local input = table.clone(op :: { [string]: unknown })
		local name = input.op :: string
		input.op = nil
		local ok, result = pcall((byName[name] :: Definition).run, ctx, input)
		if not ok then
			return nil, "operation " .. index .. " (" .. name .. "): " .. tostring(result)
		end
		table.insert(results, result :: Result)
	end
	local inverse: { Edit.Restore } = {}
	for index = #ctx.inverse, 1, -1 do
		table.insert(inverse, ctx.inverse[index])
	end
	return {
		doc = ctx.doc,
		inverse = inverse,
		remap = ctx.remap,
		results = results,
		touched = ctx.touched,
	},
		nil
end

function Operations.restoreOps(inverse: { Edit.Restore }): { { [string]: unknown } }
	local ops: { { [string]: unknown } } = {}
	for _, restore in inverse do
		local op: { [string]: unknown } = {}
		for key, value in (restore :: unknown) :: { [string]: unknown } do
			op[key] = value
		end
		table.insert(ops, op)
	end
	return ops
end

return table.freeze(Operations)
