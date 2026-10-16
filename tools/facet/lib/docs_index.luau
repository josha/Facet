--!strict
local Files = require("./files")
local Json = require("./json")
local Markdown = require("./markdown")

export type Node = {
	path: string,
	file: string,
	kind: string,
	summary: string,
	aliases: { string },
	children: { string },
	body: string,
}
export type Match = { node: Node, score: number }
local DocsIndex = {}
DocsIndex.budgets = table.freeze({ map = 2048, recipe = 2048, card = 1024, detail = 4096, index = 4096 })
DocsIndex.responseBudget = 4096

function DocsIndex.budget(kind: string): number?
	if kind == "map" then
		return DocsIndex.budgets.map
	end
	if kind == "recipe" then
		return DocsIndex.budgets.recipe
	end
	if kind == "card" then
		return DocsIndex.budgets.card
	end
	if kind == "detail" then
		return DocsIndex.budgets.detail
	end
	if kind == "index" then
		return DocsIndex.budgets.index
	end
	return nil
end

function DocsIndex.consumerGuide(name: string): boolean
	return name ~= "11-device-verification.md"
		and name ~= "12-performance-lab.md"
		and name ~= "19-paired-performance.md"
		and string.match(name, "%d%d%d%d%-%d%d%-%d%d") == nil
end

function DocsIndex.load(root: string): { Node }
	local manifest = Files.join(root, "docs/reference/index.json")
	local records = assert(Json.asArray(Json.decode(Files.read(manifest))), "documentation index must be an array")
	local nodes: { Node } = {}
	for _, record in records do
		local file = assert(Json.stringField(record, "file"), "node file is missing")
		table.insert(nodes, {
			path = assert(Json.stringField(record, "path"), "node path is missing"),
			file = file,
			kind = assert(Json.stringField(record, "kind"), "node kind is missing"),
			summary = assert(Json.stringField(record, "summary"), "node summary is missing"),
			aliases = assert(Json.strings(Json.field(record, "aliases")), "node aliases are missing"),
			children = assert(Json.strings(Json.field(record, "children")), "node children are missing"),
			body = (string.gsub(Files.read(Files.join(root, file)), "\r\n", "\n")),
		})
	end
	return nodes
end

local function normal(text: string): string
	return (string.gsub(string.lower(text), "^ui%.", ""))
end

function DocsIndex.find(nodes: { Node }, query: string): Node?
	local wanted = normal(query)
	for _, node in nodes do
		if normal(node.path) == wanted .. ".card" then
			return node
		end
	end
	for _, node in nodes do
		if normal(node.path) == wanted then
			return node
		end
	end
	for _, node in nodes do
		for _, alias in node.aliases do
			if normal(alias) == wanted then
				return node
			end
		end
	end
	return nil
end

function DocsIndex.search(nodes: { Node }, query: string, limit: number): { Match }
	local wanted = normal(query)
	local matches: { Match } = {}
	if wanted == "" then
		return matches
	end
	for _, node in nodes do
		local title = string.lower(node.path .. " " .. node.summary .. " " .. table.concat(node.aliases, " "))
		local score = if string.find(title, wanted, 1, true) then 10 else 0
		if string.find(string.lower(node.body), wanted, 1, true) then
			score += 1
		end
		if score > 0 then
			table.insert(matches, { node = node, score = score })
		end
	end
	table.sort(matches, function(a: Match, b: Match): boolean
		return if a.score == b.score then a.node.path < b.node.path else a.score > b.score
	end)
	while #matches > limit do
		table.remove(matches)
	end
	return matches
end

function DocsIndex.validate(nodes: { Node }): { string }
	local findings: { string } = {}
	local byPath: { [string]: Node } = {}
	local byFile: { [string]: Node } = {}
	for _, node in nodes do
		if byPath[node.path] then
			table.insert(findings, "duplicate node " .. node.path)
		end
		if byFile[node.file] then
			table.insert(findings, "duplicate file " .. node.file)
		end
		byPath[node.path] = node
		byFile[node.file] = node
		local budget = DocsIndex.budget(node.kind)
		if budget == nil then
			table.insert(findings, node.path .. ": unknown kind " .. node.kind)
		elseif #node.body > budget then
			table.insert(findings, node.path .. ": " .. #node.body .. " bytes exceeds " .. budget)
		end
		if #node.summary > 160 or string.find(node.summary, "\n", 1, true) then
			table.insert(findings, node.path .. ": summary must be one line of at most 160 bytes")
		end
	end
	local seen: { [string]: boolean } = {}
	local queue = { "Map" }
	while #queue > 0 do
		local path = table.remove(queue, 1) :: string
		if seen[path] then
			continue
		end
		seen[path] = true
		local node = byPath[path]
		if node == nil then
			table.insert(findings, "missing node " .. path)
			continue
		end
		local linked: { [string]: boolean } = {}
		for _, link in Markdown.links(node.body) do
			if not Markdown.isExternal(link.target) then
				local target = string.match(link.target, "^([^#]+)") or ""
				local file = Markdown.normalize(Files.parent(node.file) .. "/" .. target)
				local child = byFile[file]
				if child then
					linked[child.path] = true
					table.insert(queue, child.path)
				end
			end
		end
		for _, child in node.children do
			if not byPath[child] then
				table.insert(findings, path .. ": missing child " .. child)
			elseif not linked[child] then
				table.insert(findings, path .. ": child has no link " .. child)
			end
		end
	end
	for _, node in nodes do
		if not seen[node.path] then
			table.insert(findings, node.path .. ": unreachable from Map")
		end
	end
	return findings
end

return table.freeze(DocsIndex)
