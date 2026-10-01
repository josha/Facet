--!strict

local document = require("./document")

local savedLibrary = {}

local function cleanDocument(value: any): document.Document
	local valid = document.validate(value)
	local function node(source: document.Node): document.Node
		local children = {}
		for _, child in source.children do
			table.insert(children, node(child))
		end
		return {
			id = source.id,
			kind = source.kind,
			name = source.name,
			props = document.copy(source.props),
			children = children,
		}
	end
	return { schema = valid.schema, name = valid.name, nextId = valid.nextId, root = node(valid.root) }
end

function savedLibrary.validate(value: any): any
	assert(type(value) == "table", "Invalid design library")
	local clean: any = { designs = {}, archived = {} }
	if value.draft ~= nil then
		clean.draft = cleanDocument(value.draft)
	end
	assert(value.designs == nil or type(value.designs) == "table", "Invalid saved designs")
	local count = 0
	for name, design in value.designs or {} do
		count += 1
		assert(count <= 40, "A library supports at most 40 saved designs")
		assert(type(name) == "string" and #name > 0 and #name <= 120, "Invalid saved design name")
		clean.designs[name] = cleanDocument(design)
	end
	assert(value.archived == nil or type(value.archived) == "table", "Invalid removed designs")
	local archived = 0
	for name, design in value.archived or {} do
		archived += 1
		assert(archived <= 40, "Restore removed designs before removing more")
		assert(type(name) == "string" and #name > 0 and #name <= 120, "Invalid removed design name")
		clean.archived[name] = cleanDocument(design)
	end
	return clean
end

function savedLibrary.replace(previous: any, revision: number, value: any): any
	local current = if previous then previous.revision else 0
	assert(current == revision, "Your library changed in another session. Rejoin to load the latest designs")
	return { revision = revision + 1, library = savedLibrary.validate(value) }
end

return savedLibrary
