--!strict

local Cst = require("./cst")
local Schema = require("../lib/schema")
local SourceMap = require("./source_map")
local Values = require("./values")

export type Span = SourceMap.Span
export type Value = Values.Value

export type Prop = {
	name: string,
	value: Value,
	item: Cst.TableItem,
	entry: number,
	opaque: boolean,
}

export type NodeType = "control" | "keyed" | "code"
export type Slot = "entry" | "root" | "template"

export type Node = {
	id: string,
	segment: string,
	type: NodeType,
	namespace: string?,
	kind: string?,
	label: string?,
	parent: Node?,
	index: number,
	entry: number?,
	slot: Slot,
	props: { Prop },
	children: { Node },
	expr: Cst.Expr,
	call: Cst.Call?,
	head: Cst.Expr?,
	labelString: Cst.String?,
	table: Cst.Table?,
	render: Cst.Function?,
	keyField: string?,
	scope: Values.Scope,
	span: Span,
}

export type View = {
	func: Cst.Function,
	ui: string,
	model: string?,
	compose: string?,
	host: string?,
	rootExpr: Cst.Expr,
}

export type Style = {
	unit: string,
	newline: string,
	cast: boolean,
	brackets: boolean,
	useAnnotation: string?,
	width: number,
}

export type Document = {
	source: string,
	map: SourceMap.SourceMap?,
	error: string?,
	view: View?,
	root: Node?,
	nodes: { [string]: Node },
	order: { Node },
	byStart: { [number]: Node },
	style: Style,
	problems: { string },
	schema: Schema.Schema?,
}

local Document = {}

local function unwrapGroup(node: Cst.Expr): Cst.Expr
	local current = node
	while current.tag == "group" do
		current = current.expression
	end
	return current
end

local function nameOf(node: Cst.Expr): string?
	if node.tag == "local" then
		return node.token.text
	elseif node.tag == "global" then
		return node.name.text
	end
	return nil
end

local function detectStyle(source: string): Style
	local unit = "\t"
	local smallest: number? = nil
	for line in string.gmatch(source, "[^\n]+") do
		local leading = string.match(line, "^([ \t]+)%S")
		if leading then
			if string.sub(leading, 1, 1) == "\t" then
				smallest = nil
				unit = "\t"
				break
			end
			if smallest == nil or #leading < (smallest :: number) then
				smallest = #leading
			end
		end
	end
	if smallest then
		unit = string.rep(" ", smallest :: number)
	end
	local annotation = string.match(source, "function%(%s*use%s*(:%s*[%w_%.]+)%s*%)")
	return {
		unit = unit,
		newline = if string.find(source, "\r\n", 1, true) then "\r\n" else "\n",
		cast = true,
		brackets = string.find(source, '%[%s*"[%a_][%w_]*"%s*%]%s*=') ~= nil,
		useAnnotation = if annotation then (string.gsub(annotation, "^:%s*", ": ")) else nil,
		width = 120,
	}
end

local function findView(map: SourceMap.SourceMap): (View?, string?)
	local statements = map.result.root.statements
	local compose: string? = nil
	local host: string? = nil
	for _, statement in statements do
		if statement.tag == "local" then
			for index = 1, #statement.variables do
				local name = statement.variables[index].name.text
				if name == "Compose" then
					compose = name
				elseif name == "Host" then
					host = name
				end
			end
		end
	end
	local last = statements[#statements]
	if last == nil or last.tag ~= "return" or #last.expressions ~= 1 then
		return nil, "the module does not end with return function(UI, model) ... end"
	end
	local func = unwrapGroup(last.expressions[1])
	if func.tag ~= "function" then
		return nil, "the module does not return a view function"
	end
	if #func.parameters < 1 then
		return nil, "the view function has no UI parameter"
	end
	local ui = func.parameters[1].name.text
	local model = if #func.parameters >= 2 then func.parameters[2].name.text else nil
	for _, statement in func.body.statements do
		if statement.tag == "local" then
			for index = 1, #statement.variables do
				local name = statement.variables[index].name.text
				if name == "Compose" then
					compose = name
				elseif name == "Host" then
					host = name
				end
			end
		end
	end
	local body = func.body.statements
	local final = body[#body]
	if final == nil or final.tag ~= "return" or #final.expressions ~= 1 then
		return nil, "the view function does not end with return <control>"
	end
	return {
		func = func,
		ui = ui,
		model = model,
		compose = compose,
		host = host,
		rootExpr = final.expressions[1],
	},
		nil
end

type Recognized = {
	namespace: string,
	kind: string,
	call: Cst.Call,
	head: Cst.Expr,
	labelString: Cst.String?,
	table: Cst.Table,
}

local function recognizeControl(node: Cst.Expr, view: View): Recognized?
	if node.tag ~= "call" or node.self or #node.arguments ~= 1 then
		return nil
	end
	local argument = node.arguments[1]
	if argument.tag ~= "table" then
		return nil
	end
	local callee = node.func
	local labelString: Cst.String? = nil
	if callee.tag == "call" then
		if callee.self or #callee.arguments ~= 1 then
			return nil
		end
		local label = callee.arguments[1]
		if label.tag ~= "string" or label.quoteStyle == "interp" then
			return nil
		end
		labelString = label
		callee = callee.func
	end
	if callee.tag ~= "indexname" or callee.accessor.text ~= "." then
		return nil
	end
	local namespaceName = nameOf(callee.expression)
	local namespace: string? = nil
	if namespaceName == view.ui then
		namespace = "UI"
	elseif namespaceName ~= nil and namespaceName == view.host then
		namespace = "Host"
	end
	local kind = callee.index.text
	if namespace == nil or string.match(kind, "^%u") == nil then
		return nil
	end
	return {
		namespace = namespace :: string,
		kind = kind,
		call = node,
		head = callee,
		labelString = labelString,
		table = argument,
	}
end

local function recognizeKeyed(node: Cst.Expr, view: View): (Cst.Call?, Cst.Table?)
	if view.compose == nil or node.tag ~= "call" or node.self or #node.arguments ~= 1 then
		return nil, nil
	end
	local callee = node.func
	if callee.tag ~= "indexname" or callee.index.text ~= "keyed" or nameOf(callee.expression) ~= view.compose then
		return nil, nil
	end
	local argument = node.arguments[1]
	if argument.tag ~= "table" then
		return nil, nil
	end
	for _, entry in argument.entries do
		if entry.kind == "record" and entry.key.text == "render" then
			local render = entry.value
			if render.tag == "function" then
				return node, argument
			end
		end
	end
	return nil, nil
end

local function propKey(map: SourceMap.SourceMap, item: Cst.TableItem): (string?, boolean)
	if item.kind == "record" then
		return item.key.text, false
	elseif item.kind == "general" then
		local key = item.key
		if key.tag == "string" then
			local decoded = Values.decodeString(key.value.text, key.quoteStyle)
			if decoded then
				return decoded, false
			end
		end
		return "[" .. SourceMap.slice(map, SourceMap.expr(map, key)) .. "]", true
	end
	return nil, false
end

type Builder = {
	doc: Document,
	map: SourceMap.SourceMap,
	view: View,
}

local Build = {}

local function newNode(
	builder: Builder,
	expr: Cst.Expr,
	parent: Node?,
	slot: Slot,
	entry: number?,
	scope: Values.Scope,
	nodeType: NodeType
): Node
	return {
		id = "",
		segment = "",
		type = nodeType,
		parent = parent,
		index = 0,
		entry = entry,
		slot = slot,
		props = {},
		children = {},
		expr = expr,
		scope = scope,
		span = SourceMap.expr(builder.map, expr),
	}
end

local function readEntries(builder: Builder, node: Node, tableExpr: Cst.Table, scope: Values.Scope, children: boolean)
	for index, item in tableExpr.entries do
		if item.kind == "list" then
			if children then
				table.insert(node.children, Build.node(builder, item.value, node, "entry", index, scope))
			end
		else
			local name, opaque = propKey(builder.map, item)
			if name then
				table.insert(node.props, {
					name = name,
					value = Values.read(builder.map, item.value, scope),
					item = item,
					entry = index,
					opaque = opaque,
				})
			end
		end
	end
end

function Build.node(
	builder: Builder,
	expr: Cst.Expr,
	parent: Node?,
	slot: Slot,
	entry: number?,
	scope: Values.Scope
): Node
	local inner = expr
	if inner.tag == "cast" and slot == "entry" then
		inner = inner.operand
	end
	inner = unwrapGroup(inner)
	local control = recognizeControl(inner, builder.view)
	if control then
		local node = newNode(builder, expr, parent, slot, entry, scope, "control")
		node.namespace = control.namespace
		node.kind = control.kind
		node.call = control.call
		node.head = control.head
		node.labelString = control.labelString
		node.table = control.table
		local labelString = control.labelString
		if labelString then
			node.label = Values.decodeString(labelString.value.text, labelString.quoteStyle)
		end
		readEntries(builder, node, control.table, scope, true)
		return node
	end
	local keyedCall, options = recognizeKeyed(inner, builder.view)
	if keyedCall and options then
		local node = newNode(builder, expr, parent, slot, entry, scope, "keyed")
		node.kind = "keyed"
		node.call = keyedCall
		node.table = options
		readEntries(builder, node, options, scope, false)
		for _, item in options.entries do
			if item.kind == "record" and item.key.text == "render" then
				local render = item.value
				if render.tag == "function" then
					node.render = render
					local itemName = if #render.parameters >= 1 then render.parameters[1].name.text else nil
					local statements = render.body.statements
					local final = statements[#statements]
					if final and final.tag == "return" and #final.expressions == 1 then
						local templateScope: Values.Scope = { model = scope.model, item = itemName, use = scope.use }
						local template = Build.node(builder, final.expressions[1], node, "template", nil, templateScope)
						table.insert(node.children, template)
					end
				end
			elseif item.kind == "record" and item.key.text == "key" then
				node.keyField = Values.keyField(item.value)
			end
		end
		return node
	end
	return newNode(builder, expr, parent, slot, entry, scope, "code")
end

local function escapeSegment(text: string): string
	return (
		string.gsub(text, "[%%/%[%]#~]", function(character: string): string
			return string.format("%%%02X", string.byte(character))
		end)
	)
end

local function baseSegment(node: Node): string
	if node.type == "control" then
		if node.label and node.label ~= "" then
			return escapeSegment(node.label :: string)
		end
		return "#" .. (node.kind :: string)
	elseif node.type == "keyed" then
		local template = node.children[1]
		if template then
			return baseSegment(template) .. "[]"
		end
		return "#keyed"
	end
	return "#code"
end

local function assignIds(doc: Document, node: Node, prefix: string, segment: string)
	node.segment = segment
	node.id = if prefix == "" then segment else prefix .. "/" .. segment
	doc.nodes[node.id] = node
	table.insert(doc.order, node)
	doc.byStart[node.span.start] = node
	local counts: { [string]: number } = {}
	local labeled: { [string]: boolean } = {}
	for index, child in node.children do
		child.index = index
		local base = baseSegment(child)
		local positional = string.sub(base, 1, 1) == "#"
		counts[base] = (counts[base] or 0) + 1
		local childSegment = base
		if positional then
			childSegment = base .. tostring(counts[base])
		elseif counts[base] > 1 then
			childSegment = base .. "~" .. tostring(counts[base])
			if not labeled[base] then
				labeled[base] = true
				table.insert(doc.problems, "duplicate label " .. base .. " under " .. node.id)
			end
		end
		assignIds(doc, child, node.id, childSegment)
	end
end

local function classifyTokens(doc: Document)
	local schema = doc.schema
	if schema == nil then
		return
	end
	local casted = 0
	local uncasted = 0
	for _, node in doc.order do
		if node.type ~= "control" or node.namespace ~= "UI" then
			continue
		end
		local control = schema.controls[node.kind :: string]
		if control == nil then
			continue
		end
		for _, prop in node.props do
			local field = control.byName[prop.name]
			if field == nil or prop.value.kind ~= "string" then
				continue
			end
			local text = prop.value.value :: string
			for set, members in Schema.tokenSets(field.shape) do
				if table.find(members, text) then
					prop.value.kind = "token"
					prop.value.set = set
					break
				end
			end
			if not Schema.accepts(field.shape, "string") then
				if prop.value.cast then
					casted += 1
				else
					uncasted += 1
				end
			end
		end
	end
	doc.style.cast = casted >= uncasted
end

function Document.parse(source: string, schema: Schema.Schema?): Document
	local doc: Document = {
		source = source,
		nodes = {},
		order = {},
		byStart = {},
		style = detectStyle(source),
		problems = {},
		schema = schema,
	}
	local map, problem = SourceMap.parse(source)
	if map == nil then
		doc.error = problem or "the source does not parse"
		return doc
	end
	doc.map = map
	local view, viewProblem = findView(map)
	if view == nil then
		table.insert(doc.problems, viewProblem or "not a view module")
		return doc
	end
	doc.view = view
	local builder: Builder = { doc = doc, map = map, view = view }
	local scope: Values.Scope = { model = view.model, use = nil }
	local root = Build.node(builder, view.rootExpr, nil, "root", nil, scope)
	doc.root = root
	assignIds(doc, root, "", baseSegment(root) .. (if string.sub(baseSegment(root), 1, 1) == "#" then "1" else ""))
	classifyTokens(doc)
	return doc
end

function Document.find(doc: Document, id: string): Node?
	return doc.nodes[id]
end

function Document.prop(node: Node, name: string): Prop?
	for _, prop in node.props do
		if prop.name == name and not prop.opaque then
			return prop
		end
	end
	return nil
end

function Document.isAncestor(ancestor: Node, node: Node): boolean
	local current: Node? = node
	while current do
		if current == ancestor then
			return true
		end
		current = current.parent
	end
	return false
end

function Document.text(doc: Document, span: Span): string
	return string.sub(doc.source, span.start + 1, span.finish)
end

local function spanJson(doc: Document, span: Span): { [string]: unknown }
	local map = doc.map :: SourceMap.SourceMap
	local line, column = SourceMap.line(map, span.start)
	local endLine, endColumn = SourceMap.line(map, span.finish)
	return {
		start = span.start,
		finish = span.finish,
		line = line,
		column = column,
		endLine = endLine,
		endColumn = endColumn,
	}
end

function Document.nodeJson(doc: Document, node: Node, depth: number?): { [string]: unknown }
	local result: { [string]: unknown } = {
		id = node.id,
		type = node.type,
		span = spanJson(doc, node.span),
	}
	if node.kind then
		result.kind = node.kind
	end
	if node.namespace then
		result.namespace = node.namespace
	end
	if node.label then
		result.label = node.label
	end
	if node.type == "code" then
		result.text = Document.text(doc, node.span)
	end
	if node.type ~= "code" then
		local props: { unknown } = {}
		for _, prop in node.props do
			local entry: { [string]: unknown } = { name = prop.name, value = Values.json(prop.value) }
			if prop.opaque then
				entry.opaque = true
			end
			table.insert(props, entry)
		end
		result.props = props
	end
	if node.type == "keyed" then
		local template = node.children[1]
		result.item = if template then template.scope.item else nil
		result.key = node.keyField
	end
	local limit = depth or math.huge
	if limit > 0 then
		local children: { unknown } = {}
		for _, child in node.children do
			table.insert(children, Document.nodeJson(doc, child, limit - 1))
		end
		result.children = children
	elseif #node.children > 0 then
		result.childCount = #node.children
	end
	return result
end

function Document.json(doc: Document, depth: number?): { [string]: unknown }
	local result: { [string]: unknown } = {
		ok = doc.error == nil and doc.root ~= nil,
		problems = doc.problems,
	}
	if doc.error then
		result.error = doc.error
	end
	local view = doc.view
	if view then
		result.view = { ui = view.ui, model = view.model }
	end
	if doc.root then
		result.root = Document.nodeJson(doc, doc.root :: Node, depth)
	end
	return result
end

return table.freeze(Document)
