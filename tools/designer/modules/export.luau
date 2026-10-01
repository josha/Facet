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
		"return function(UI: Facet.Controls): GuiObject",
	}
	for _, row in document.rows(value.root) do
		local node = assert(document.find(value.root, row.id))
		for _, key in adapter.stateKeys(library.definitions[node.kind]) do
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
		if library.definitions[node.kind].anchor then
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
		local keys, body = {}, {}
		for key in props do
			table.insert(keys, key)
		end
		table.sort(keys)
		table.insert(body, indent .. "UI." .. node.kind .. " " .. literal(node.name) .. " {")
		for _, key in keys do
			table.insert(body, indent .. "\t" .. key .. " = " .. adapter.emit(props[key], emit, depth + 1) .. ",")
		end
		if
			not definition.content
			and node.kind ~= "ErrorBoundary"
			and node.kind ~= "TabView"
			and node.kind ~= "PageView"
			and node.kind ~= "NavigationStack"
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
	table.insert(lines, "\treturn " .. string.sub(emit(value.root, 1), 2))
	table.insert(lines, "end")
	return table.concat(lines, "\n") .. "\n"
end

function export.preview(componentName: string, designName: string): string
	return table.concat({
		"--!strict",
		"",
		`local component = require(script.Parent[{literal(componentName)}])`,
		"",
		"return {",
		`\tname = {literal(designName)},`,
		"\tpreviews = {",
		'\t\t{ name = "Design", render = function(ctx) return component(ctx.UI) end },',
		"\t},",
		"}",
		"",
	}, "\n")
end

return export
