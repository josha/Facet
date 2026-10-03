--!strict

local document = require("./document")
local library = require("./library")

local export = {}

local adapter = require("./adapter")
local values = require("./value")
local literal = values.literal

function export.component(value: document.Document): string
	document.validate(value)
	local lines = {
		"--!strict",
		"",
		"local Facet = require(game.ReplicatedStorage.Facet)",
		"local Compose = Facet.Compose",
		"",
		"return function(UI: Facet.Controls, data: {[string]: any}?): GuiObject",
	}
	for _, row in document.rows(value.root) do
		local node = assert(document.find(value.root, row.id))
		local keys: { string } = if document.collection(value, node.id)
			then {}
			else adapter.stateKeys(library.definitions[node.kind])
		for _, key in keys do
			table.insert(
				lines,
				"\tlocal "
					.. adapter.stateName(node, key)
					.. " = Compose.cell("
					.. adapter.emit(adapter.initial(node, key), nil)
					.. ")"
			)
		end
	end
	for _, row in document.rows(value.root) do
		local node = assert(document.find(value.root, row.id))
		if library.definitions[node.kind].anchor and not document.collection(value, node.id) then
			table.insert(
				lines,
				"\tlocal anchor_"
					.. node.id
					.. " = UI.Button "
					.. literal(node.name .. "Anchor")
					.. " { label = "
					.. literal(node.props.anchorLabel or library.definitions[node.kind].defaults.anchorLabel)
					.. ", onActivate = function(value) "
					.. adapter.stateName(node, "isPresented")
					.. ":set(true) end }"
			)
		end
	end
	local emit
	emit = function(node: document.Node, depth: number): string
		local indent = string.rep("\t", depth)
		local definition = library.definitions[node.kind]
		local props = adapter.properties(node)
		if node.kind == "Table" then
			props.columns = adapter.expression("variable", { name = "columns_" .. node.id })
		end
		local keys, body = {}, {}
		for key in props do
			table.insert(keys, key)
		end
		table.sort(keys)
		table.insert(body, indent .. "UI." .. node.kind .. " " .. literal(node.name) .. " {")
		for _, key in keys do
			local expression = adapter.emit(props[key], emit, depth + 1)
			for _, descriptor in definition.fields do
				if
					descriptor.key == key
					and type(props[key]) == "string"
					and table.find({ "choice", "extent", "space", "padding" }, descriptor.kind)
				then
					expression ..= " :: " .. literal(props[key])
				end
			end
			table.insert(body, indent .. "\t" .. key .. " = " .. expression .. ",")
		end
		if
			not definition.content
			and node.kind ~= "ErrorBoundary"
			and node.kind ~= "TabView"
			and node.kind ~= "PageView"
			and node.kind ~= "NavigationStack"
			and not table.find({ "Table", "VirtualList", "VirtualGrid" }, node.kind)
		then
			for _, child in node.children do
				table.insert(body, emit(child, depth + 1) .. ",")
			end
		end
		table.insert(body, indent .. "}")
		local result = table.concat(body, "\n")
		if definition.anchor then
			return indent
				.. 'UI.VStack "__FacetDesignHost_'
				.. node.id
				.. '" { gap = "s", anchor_'
				.. node.id
				.. ",\n"
				.. result
				.. "\n"
				.. indent
				.. "}"
		end
		return result
	end
	for _, row in document.rows(value.root) do
		local node = assert(document.find(value.root, row.id))
		if node.kind == "Table" and not document.collection(value, node.id) then
			table.insert(
				lines,
				"\tlocal columns_"
					.. node.id
					.. ": {Facet.TableColumn<any, any>} = "
					.. adapter.emit(adapter.properties(node).columns, emit, 1)
			)
		end
	end
	table.insert(lines, "\treturn " .. string.sub(emit(value.root, 1), 2))
	table.insert(lines, "end")
	return table.concat(lines, "\n") .. "\n"
end

function export.preview(componentName: string, designName: string): string
	return table.concat({
		"--!strict",
		"",
		"local Facet = require(game.ReplicatedStorage.Facet)",
		`local component = require(script.Parent:WaitForChild({literal(componentName)}))`,
		"",
		"return {",
		`\tname = {literal(designName)},`,
		"\tpreviews = {",
		'\t\t{ name = "Design", render = function(ctx: { UI: Facet.Controls }) return component(ctx.UI) end },',
		"\t},",
		"}",
		"",
	}, "\n")
end

return export
