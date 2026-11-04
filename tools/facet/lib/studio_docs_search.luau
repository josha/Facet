--!strict
-- Search the Facet documents under ServerStorage.FacetDocs from Studio. The Studio
-- command thread cannot require modules in Edit, so this ships as text:
--   local search = loadstring(game.ServerStorage.FacetDocs["search.luau"].Value)()
--   return search("Sheet detents")                    -- best sections and other matching paths
--   return search.read("docs/reference/nodes/Sheet.props.md") -- one whole document

type Doc = { path: string, name: string, text: string }
type Section = { path: string, heading: string, text: string, score: number }

local root: Instance = game:GetService("ServerStorage"):WaitForChild("FacetDocs")
local loaded: { Doc }? = nil

local function documents(): { Doc }
	if loaded ~= nil then
		return loaded
	end
	local list: { Doc } = {}
	for _, item in root:GetDescendants() do
		if item:IsA("StringValue") and item.Name ~= "search.luau" then
			local parts: { string } = {}
			local node: Instance? = item
			while node ~= nil and node ~= root do
				table.insert(parts, 1, node.Name)
				node = node.Parent
			end
			table.insert(list, { path = table.concat(parts, "/"), name = string.lower(item.Name), text = item.Value })
		end
	end
	table.sort(list, function(a: Doc, b: Doc): boolean
		return a.path < b.path
	end)
	loaded = list
	return list
end

local function termsOf(query: string): { string }
	local terms: { string } = {}
	for word in string.gmatch(string.lower(query), "[%w_%-]+") do
		if #word > 1 then
			table.insert(terms, word)
		end
	end
	return terms
end

local function count(haystack: string, term: string): number
	local total, at = 0, 1
	while true do
		local first, last = string.find(haystack, term, at, true)
		if first == nil or last == nil then
			return total
		end
		total += 1
		at = last + 1
	end
end

local function sectionsOf(doc: Doc): { { heading: string, text: string } }
	local sections: { { heading: string, text: string } } = {}
	local heading, lines = doc.path, {} :: { string }
	local function flush()
		if #lines > 0 then
			table.insert(sections, { heading = heading, text = table.concat(lines, "\n") })
		end
	end
	for line in string.gmatch(doc.text .. "\n", "(.-)\n") do
		if string.match(line, "^#+%s") then
			flush()
			heading, lines = (string.gsub(line, "^#+%s*", "")), { line }
		else
			table.insert(lines, line)
		end
	end
	flush()
	return sections
end

local function find(query: string, budget: number?): string
	local terms = termsOf(query)
	assert(#terms > 0, "search needs at least one word")
	local limit = budget or 4000
	local ranked: { { doc: Doc, score: number } } = {}
	for _, doc in documents() do
		local lower = string.lower(doc.text)
		local score, matched = 0, 0
		for _, term in terms do
			local inName = string.find(doc.name, term, 1, true) ~= nil
			local hits = count(lower, term)
			if inName or hits > 0 then
				matched += 1
			end
			score += (if inName then 25 else 0) + math.min(hits, 10)
		end
		if matched == #terms then
			table.insert(ranked, { doc = doc, score = score })
		end
	end
	if #ranked == 0 then
		return ("No document mentions every word of %q. Try fewer or different words."):format(query)
	end
	table.sort(ranked, function(a, b): boolean
		return a.score > b.score or (a.score == b.score and #a.doc.text < #b.doc.text)
	end)
	local candidates: { Section } = {}
	for index = 1, math.min(#ranked, 6) do
		local doc = ranked[index].doc
		for _, section in sectionsOf(doc) do
			local lower = string.lower(section.text)
			local score = 0
			for _, term in terms do
				score += math.min(count(lower, term), 5)
			end
			if score > 0 then
				table.insert(candidates, {
					path = doc.path,
					heading = section.heading,
					text = section.text,
					score = score + ranked[index].score / 10,
				})
			end
		end
	end
	table.sort(candidates, function(a: Section, b: Section): boolean
		return a.score > b.score
	end)
	local out: { string } = {}
	local used = 0
	local shown: { [string]: boolean } = {}
	for _, section in candidates do
		local body = section.text
		if #body > 1500 then
			body = string.sub(body, 1, 1500) .. "\n…"
		end
		if used + #body > limit and used > 0 then
			break
		end
		table.insert(out, ("---- %s § %s\n%s"):format(section.path, section.heading, body))
		used += #body
		shown[section.path] = true
	end
	local others: { string } = {}
	for index = 1, math.min(#ranked, 12) do
		local path = ranked[index].doc.path
		if not shown[path] then
			table.insert(others, path)
		end
	end
	if #others > 0 then
		table.insert(out, "Other matches (search.read(path) for one): " .. table.concat(others, ", "))
	end
	return table.concat(out, "\n\n")
end

local function read(path: string): string
	local suffix = string.gsub(path, "%.txt$", "")
	for _, doc in documents() do
		if doc.path == suffix or string.sub(doc.path, -#suffix - 1) == "/" .. suffix then
			return doc.text
		end
	end
	error(("no document at %s; search for a word it contains instead"):format(path), 2)
end

return setmetatable({ read = read }, {
	__call = function(_: unknown, query: string, budget: number?): string
		return find(query, budget)
	end,
})
