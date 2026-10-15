--!strict

local Files = require("./files")
local Markdown = require("./markdown")

export type Section = {
	file: string,
	level: number,
	title: string,
	anchor: string,
	line: number,
	body: string,
}

export type Match = { section: Section, score: number }

local DocsIndex = {}

local SOURCES = { "docs/reference/api.md", "docs/guide", "examples/blocks/README.md" }

local SKIPPED: { [string]: boolean } = {
	["11-device-verification.md"] = true,
	["12-performance-lab.md"] = true,
	["19-paired-performance.md"] = true,
	["appearance-verification-2026-09-28.md"] = true,
	["touch-outpost-verification-2026-09-30.md"] = true,
}

function DocsIndex.tokens(text: string): number
	return math.ceil(#text / 4)
end

function DocsIndex.consumerGuide(name: string): boolean
	return not SKIPPED[name]
end

function DocsIndex.parse(file: string, source: string): { Section }
	local sections: { Section } = {}
	local lines = string.split(string.gsub(source, "\r\n", "\n"), "\n")
	local fenced = false
	local seen: { [string]: number } = {}
	local open: { level: number, title: string, anchor: string, line: number }? = nil
	local body: { string } = {}
	local function close()
		local current = open
		if current ~= nil then
			table.insert(sections, {
				file = file,
				level = current.level,
				title = current.title,
				anchor = current.anchor,
				line = current.line,
				body = table.concat(body, "\n"),
			})
		end
		body = {}
	end
	for index, raw in lines do
		if string.match(raw, "^%s*```") ~= nil then
			fenced = not fenced
		end
		local hashes, title = string.match(raw, "^(#+)%s+(.-)%s*$")
		if not fenced and hashes ~= nil and title ~= nil then
			close()
			local slug = Markdown.slug(title)
			local count = seen[slug] or 0
			seen[slug] = count + 1
			open = {
				level = #hashes,
				title = title,
				anchor = if count == 0 then slug else ("%s-%d"):format(slug, count),
				line = index,
			}
		end
		table.insert(body, raw)
	end
	close()
	return sections
end

function DocsIndex.load(root: string): { Section }
	local sections: { Section } = {}
	local files: { string } = {}
	for _, source in SOURCES do
		local path = Files.join(root, source)
		if Files.isFile(path) then
			table.insert(files, source)
		elseif Files.isDirectory(path) then
			local names: { string } = {}
			for _, entry in Files.list(path) do
				if
					entry.type == "file"
					and string.sub(entry.name, -3) == ".md"
					and DocsIndex.consumerGuide(entry.name)
				then
					table.insert(names, entry.name)
				end
			end
			table.sort(names)
			for _, name in names do
				table.insert(files, source .. "/" .. name)
			end
		end
	end
	for _, file in files do
		for _, section in DocsIndex.parse(file, Files.read(Files.join(root, file))) do
			table.insert(sections, section)
		end
	end
	return sections
end

function DocsIndex.extent(sections: { Section }, chosen: Section): string
	local parts: { string } = {}
	local inside = false
	for _, section in sections do
		if section == chosen then
			inside = true
		elseif inside and (section.file ~= chosen.file or section.level <= chosen.level) then
			break
		end
		if inside then
			table.insert(parts, section.body)
		end
	end
	return (string.gsub(table.concat(parts, "\n"), "%s+$", ""))
end

local function normal(text: string): string
	return (string.gsub(string.lower(text), "[`%*]", ""))
end

function DocsIndex.find(sections: { Section }, query: string): { Match }
	local wanted = normal(query)
	local bare = string.gsub(wanted, "^ui%.", "")
	local matches: { Match } = {}
	for _, section in sections do
		local title = normal(section.title)
		local score = 0
		if title == wanted or title == bare or section.anchor == wanted then
			score = 100
		elseif string.find(" " .. title .. " ", "[^%w]" .. bare .. "[^%w]") ~= nil then
			score = 60
		elseif string.find(title, bare, 1, true) ~= nil then
			score = 40
		end
		if score > 0 then
			if section.file == "docs/reference/api.md" then
				score += 5
			end
			score -= section.level
			table.insert(matches, { section = section, score = score })
		end
	end
	table.sort(matches, function(left: Match, right: Match): boolean
		if left.score ~= right.score then
			return left.score > right.score
		end
		return left.section.line < right.section.line
	end)
	return matches
end

function DocsIndex.search(sections: { Section }, text: string, limit: number): { Match }
	local wanted = normal(text)
	local matches: { Match } = {}
	for _, section in sections do
		local body = normal(section.body)
		local count = 0
		local from = 1
		while true do
			local at = string.find(body, wanted, from, true)
			if at == nil then
				break
			end
			count += 1
			from = at + #wanted
		end
		if count > 0 then
			table.insert(matches, { section = section, score = count })
		end
	end
	table.sort(matches, function(left: Match, right: Match): boolean
		if left.score ~= right.score then
			return left.score > right.score
		end
		return left.section.line < right.section.line
	end)
	while #matches > limit do
		table.remove(matches)
	end
	return matches
end

return table.freeze(DocsIndex)
