--!strict
local Files = require("./files")
local Markdown = require("./markdown")

export type Node = {
	path: string,
	file: string,
	kind: string,
	summary: string,
	aliases: { string },
	children: { string },
	body: string,
	bytes: number?,
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

local function kind(path: string, body: string): string
	local marker = string.match(body, "\n<!%-%- kind: ([%w]+) %-%->\n")
	if marker then
		return marker
	elseif path == "Map" then
		return "map"
	elseif
		path == "Controls"
		or path == "Tasks"
		or path == "Reference"
		or string.match(path, "^Controls%.%d+$")
		or string.match(path, "%.index$")
		or string.match(path, "^Themes%.[%w_]+%.tokens$")
	then
		return "index"
	elseif string.match(path, "^Tasks%.[%w_-]+$") then
		return "recipe"
	elseif string.match(path, "^[%w_-]+%.card$") then
		return "card"
	elseif string.match(path, "^[%a][%w_.-]*$") then
		return "detail"
	end
	return "unknown"
end

function DocsIndex.load(root: string): { Node }
	local nodes: { Node } = {}
	local directory = "docs/reference/nodes"
	for _, relative in Files.walk(Files.join(root, directory)) do
		if Files.extension(relative) ~= ".md" then
			continue
		end
		local file = Files.join(directory, relative)
		local path = Files.stem(relative)
		local source = Files.text(Files.join(root, file))
		local aliases: { string } = {}
		local aliasLine = string.match(source, "\n<!%-%- aliases: ([^\n]-) %-%->\n")
		if aliasLine then
			aliases = string.split(aliasLine, " | ")
		elseif string.match(path, "^[%w_-]+%.card$") then
			local control = string.sub(path, 1, -6)
			aliases = { control, "UI." .. control }
		end
		local body = string.gsub(source, "<!%-%- aliases: [^\n]- %-%->\n\n?", "")
		body = string.gsub(body, "<!%-%- kind: [^\n]- %-%->\n\n?", "")
		local prose = string.match(body, "^#+ [^\n]+\n%s*(.*)$") or ""
		local paragraph = string.match(prose, "^(.-)\n\n") or prose
		paragraph = string.gsub(paragraph, "%s+", " ")
		local summary = string.match(paragraph, "^(.-[.!?])%s") or paragraph
		table.insert(nodes, {
			path = path,
			file = file,
			kind = kind(path, source),
			summary = summary,
			aliases = aliases,
			children = {},
			body = body,
			bytes = #source,
		})
	end
	for _, node in nodes do
		for _, link in Markdown.links(node.body) do
			if not Markdown.isExternal(link.target) then
				local target = string.match(link.target, "^([^#]+)") or ""
				local file = Markdown.normalize(Files.parent(node.file) .. "/" .. target)
				if Files.parent(file) == directory and Files.extension(file) == ".md" then
					table.insert(node.children, Files.stem(file))
				end
			end
		end
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
	local aliased: Node? = nil
	for _, node in nodes do
		for _, alias in node.aliases do
			if normal(alias) == wanted then
				if aliased == nil or #node.path < #aliased.path then
					aliased = node
				end
			end
		end
	end
	return aliased
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
		if not string.match(node.body, "^#+ [^\n]+\n") then
			table.insert(findings, node.path .. ": missing title")
		end
		local budget = DocsIndex.budget(node.kind)
		local bytes = node.bytes or #node.body
		if budget == nil then
			table.insert(findings, node.path .. ": unknown kind " .. node.kind)
		elseif bytes > budget then
			table.insert(findings, node.path .. ": " .. bytes .. " bytes exceeds " .. budget)
		end
		if node.summary == "" or #node.summary > 160 or string.find(node.summary, "\n", 1, true) then
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
