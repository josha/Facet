--!strict

local library = require("./library")

export type Node = { id: string, kind: string, name: string, props: { [string]: any }, children: { Node } }
export type Document = { schema: string, name: string, nextId: number, root: Node }

local document = {}

function document.copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copied = {}
	for key, item in value do
		copied[key] = document.copy(item)
	end
	return copied
end

function document.validate(value: any): Document
	assert(type(value) == "table" and value.schema == "facet-designer/1", "Unsupported design format")
	assert(
		type(value.name) == "string" and #value.name > 0 and #value.name <= 120,
		"A design needs a name of 1 to 120 bytes"
	)
	assert(type(value.nextId) == "number" and value.nextId % 1 == 0 and value.nextId >= 1, "Invalid next node ID")
	local seen, visiting, count, maximum = {}, {}, 0, 0
	local function visit(node: any, depth: number)
		assert(
			depth <= 32 and type(node) == "table" and not visiting[node],
			"Design nesting exceeds 32 levels or contains a cycle"
		)
		visiting[node] = true
		count += 1
		assert(count <= 500, "A design supports at most 500 controls")
		assert(
			type(node.id) == "string" and string.match(node.id, "^n%d+$") and not seen[node.id],
			"Node IDs must be unique"
		)
		maximum = math.max(maximum, assert(tonumber(string.sub(node.id, 2))))
		seen[node.id] = true
		local definition = assert(library.definitions[node.kind], `Unsupported control: {tostring(node.kind)}`)
		assert(type(node.name) == "string" and #node.name > 0 and #node.name <= 120, "A control needs a name")
		assert(
			type(node.props) == "table" and type(node.children) == "table",
			"A control needs properties and children"
		)
		for key, property in node.props do
			local descriptor =
				assert(library.descriptor(node.kind, key), `Unsupported {node.kind} property: {tostring(key)}`)
			assert(library.parse(descriptor, property) == property, "Properties must use their normalized types")
		end
		assert(definition.container or #node.children == 0, `{node.kind} cannot contain controls`)
		for _, child in ipairs(node.children) do
			visit(child, depth + 1)
		end
		for key in node.children do
			assert(
				type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #node.children,
				"Children must be a dense array"
			)
		end
		visiting[node] = nil
	end
	visit(value.root, 1)
	assert(value.root.kind == "Screen", "A design must start with Screen")
	assert(value.nextId > maximum, "Next node ID must exceed every existing ID")
	return value
end

function document.find(root: Node, id: string): (Node?, Node?, number?)
	if root.id == id then
		return root
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
	return nil
end

function document.rows(root: Node): { any }
	local rows = {}
	local function visit(node: Node, depth: number)
		table.insert(rows, { id = node.id, name = node.name, kind = node.kind, depth = depth })
		for _, child in node.children do
			visit(child, depth + 1)
		end
	end
	visit(root, 0)
	return rows
end

function document.new(name: string?): Document
	return {
		schema = "facet-designer/1",
		name = name or "Untitled design",
		nextId = 2,
		root = { id = "n1", name = "Screen", kind = "Screen" :: "Screen", props = { gap = "m" }, children = {} },
	}
end

function document.insert(value: Document, selected: string, kind: string): (Document, string)
	local nextValue = document.copy(value)
	local node, parent = document.find(nextValue.root, selected)
	assert(node, "Select a control first")
	local destination = if library.definitions[node.kind].container then node else parent
	assert(destination, "Select a container")
	local definition = assert(library.definitions[kind], "Unknown control")
	assert(kind ~= "Screen", "Only the root can be a Screen")
	local id = `n{nextValue.nextId}`
	nextValue.nextId += 1
	table.insert(
		destination.children,
		{ id = id, kind = kind, name = kind, props = document.copy(definition.defaults), children = {} }
	)
	local inserted = assert(document.find(nextValue.root, id))
	local function seed(children: any, target: Node)
		for _, item in children or {} do
			local child = {
				id = `n{nextValue.nextId}`,
				kind = item.kind,
				name = item.kind,
				props = document.copy(item.props or {}),
				children = {},
			}
			nextValue.nextId += 1
			table.insert(target.children, child)
			seed(item.children, child)
		end
	end
	seed(definition.seeds, inserted)
	return document.validate(nextValue), id
end

function document.change(value: Document, selected: string, key: string, property: any): Document
	local nextValue = document.copy(value)
	local node = assert(document.find(nextValue.root, selected))
	if key == "name" then
		assert(type(property) == "string" and property ~= "", "Enter a control name")
		node.name = property
	elseif property == nil then
		node.props[key] = nil
	else
		node.props[key] = library.parse(assert(library.descriptor(node.kind, key)), property)
		if node.kind == "Toggle" and key == "mixed" then
			node.props.presentation = "checkbox" :: "checkbox"
		elseif node.kind == "Toggle" and key == "presentation" and property ~= "checkbox" then
			node.props.mixed = nil
		end
		if node.kind == "Text" and key == "truncate" and property == "middle" then
			node.props.wrap = false
			node.props.lines = nil
		elseif
			node.kind == "Text"
			and ((key == "wrap" and property == true) or (key == "lines" and property ~= 1))
			and node.props.truncate == "middle"
		then
			node.props.truncate = "end"
		end
		if node.kind == "DateTimePicker" and key == "time" and property == true then
			local civil = document.copy(node.props.value or library.definitions.DateTimePicker.defaults.value)
			civil.hour, civil.minute = civil.hour or 0, civil.minute or 0
			node.props.value = civil
		end
	end
	if node.kind == "Image" then
		if key == "tileSize" then
			node.props.scaleMode = "tile" :: "tile"
		elseif key == "sliceCenter" or key == "sliceScale" then
			node.props.scaleMode = "slice" :: "slice"
		end
		local mode = node.props.scaleMode or library.definitions.Image.defaults.scaleMode
		if mode == "tile" and node.props.tileSize == nil then
			node.props.tileSize = { width = 32, height = 32 }
		end
		if mode == "slice" and node.props.sliceCenter == nil then
			node.props.sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 }
		end
		if mode ~= "tile" then
			node.props.tileSize = nil
		end
		if mode ~= "slice" then
			node.props.sliceCenter, node.props.sliceScale = nil, nil
		end
	elseif node.kind == "Picker" then
		if key == "indicatorPosition" and property ~= nil then
			node.props.style = "radioGroup" :: "radioGroup"
		end
		if key == "maxHeight" and property ~= nil then
			node.props.style = "menu" :: "menu"
		end
		local style = node.props.style or library.definitions.Picker.defaults.style
		if style ~= "radioGroup" then
			node.props.indicatorPosition = nil
		end
		if not table.find({ "automatic", "menu", "navigationLink" }, style) then
			node.props.maxHeight = nil
		end
		if node.props.iconOnly == true then
			local options = document.copy(node.props.options or library.definitions.Picker.defaults.options)
			for _, option in options do
				option.icon = option.icon or "settings"
			end
			node.props.options = options
		end
	elseif node.kind == "Sheet" then
		if key == "edge" and property ~= nil and node.props.placement ~= "adaptive" then
			node.props.placement = "side" :: "side"
		end
		if not table.find({ "side", "adaptive" }, node.props.placement) then
			node.props.edge = nil
		end
	elseif node.kind == "Toggle" and node.props.presentation ~= "checkbox" then
		node.props.mixed = nil
	elseif node.kind == "Text" and node.props.truncate == "middle" then
		if node.props.wrap ~= false then
			node.props.truncate = "end"
		end
	end
	return document.validate(nextValue)
end

function document.remove(value: Document, selected: string): (Document, string)
	local nextValue = document.copy(value)
	local _, parent, index = document.find(nextValue.root, selected)
	assert(parent and index, "The root Screen cannot be deleted")
	table.remove(parent.children, index)
	return document.validate(nextValue), parent.id
end

function document.duplicate(value: Document, selected: string): (Document, string)
	local nextValue = document.copy(value)
	local node, parent, index = document.find(nextValue.root, selected)
	assert(node and parent and index, "The root Screen cannot be duplicated")
	local copy = document.copy(node)
	local function assign(item: Node)
		item.id = `n{nextValue.nextId}`
		nextValue.nextId += 1
		for _, child in item.children do
			assign(child)
		end
	end
	assign(copy)
	copy.name ..= " copy"
	table.insert(parent.children, index + 1, copy)
	return document.validate(nextValue), copy.id
end

function document.move(value: Document, selected: string, destination: string, before: number?): Document
	local nextValue = document.copy(value)
	local node, parent, index = document.find(nextValue.root, selected)
	local target = assert(document.find(nextValue.root, destination), "Destination does not exist")
	assert(node and parent and index, "The root Screen cannot be moved")
	assert(
		library.definitions[target.kind].container and not document.find(node, destination),
		"Move into a container outside this subtree"
	)
	table.remove(parent.children, index)
	table.insert(target.children, math.clamp(before or (#target.children + 1), 1, #target.children + 1), node)
	return document.validate(nextValue)
end

function document.reorder(value: Document, selected: string, insertionSlot: number): Document
	local node, parent, index = document.find(value.root, selected)
	assert(node and parent and index, "The root Screen cannot be moved")
	local remaining = {}
	for _, row in document.rows(value.root) do
		if row.id ~= selected then
			table.insert(remaining, row)
		end
	end
	local anchor = remaining[insertionSlot + 1]
	if not anchor then
		return document.move(value, selected, parent.id)
	end
	if document.find(node, anchor.id) then
		return value
	end
	local _, destination, before = document.find(value.root, anchor.id)
	assert(destination and before, "Drop a layer below the root Screen")
	if destination.id == parent.id and index < before then
		before -= 1
	end
	return document.move(value, selected, destination.id, before)
end

return document
