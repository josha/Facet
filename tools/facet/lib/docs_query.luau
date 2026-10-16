--!strict
local Cli = require("./cli")
local DocsIndex = require("./docs_index")

local DocsQuery = {}

local function discovery(nodes: { DocsIndex.Node }, names: { string }, reserved: number?): string
	local lines = { "Open one path with: lute run tools/facet docs <path>" }
	local size = #lines[1] + 1
	for _, name in names do
		local found = DocsIndex.find(nodes, name)
		local line = if found then found.path .. " - " .. found.summary else name .. " - no exact node; use --search"
		if size + #line + 1 + (reserved or 0) > DocsIndex.responseBudget then
			break
		end
		table.insert(lines, line)
		size += #line + 1
	end
	return table.concat(lines, "\n")
end

function DocsQuery.response(nodes: { DocsIndex.Node }, invocation: Cli.Invocation): string
	local query = Cli.flag(invocation, "search")
	if query ~= nil then
		local names: { string } = {}
		for _, match in DocsIndex.search(nodes, query, 15) do
			table.insert(names, match.node.path)
		end
		return discovery(nodes, names)
	end
	if Cli.switch(invocation, "list") then
		return discovery(nodes, { "Tasks", "Controls", "Reference", "Themes.index" })
	end
	if #invocation.positional > 1 then
		return discovery(nodes, invocation.positional)
	end
	local name = invocation.positional[1] or "Map"
	local node = DocsIndex.find(nodes, name)
	local resolved = node ~= nil and string.lower(node.path) ~= string.lower(name)
	if node ~= nil and node.kind == "card" then
		local control = string.lower(string.sub(node.path, 1, -6))
		if string.lower(name) == control or string.lower(name) == "ui." .. control then
			resolved = false
		end
	end
	if node == nil then
		node = DocsIndex.nearest(nodes, name)
		resolved = node ~= nil
	end
	if node == nil then
		local matches = DocsIndex.search(nodes, name, 2)
		if #matches == 1 or (#matches == 2 and matches[1].score > matches[2].score) then
			node = matches[1].node
			resolved = true
		end
	end
	if node == nil then
		local names: { string } = {}
		for _, match in DocsIndex.search(nodes, name, 5) do
			table.insert(names, match.node.path)
		end
		return `No documentation node '{name}'.\n` .. discovery(nodes, names)
	end
	local prefix = if resolved then `Resolved '{name}' to {node.path}.\n` else ""
	if #prefix + #node.body + 1 > DocsIndex.responseBudget or Cli.switch(invocation, "outline") then
		return prefix .. discovery(nodes, node.children, #prefix)
	end
	return prefix .. (string.gsub(node.body, "%s+$", ""))
end

return table.freeze(DocsQuery)
