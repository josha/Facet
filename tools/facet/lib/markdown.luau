--!strict

export type Link = {
	start: number,
	line: number,
	label: string,
	target: string,
}

local Markdown = {}

function Markdown.slug(heading: string): string
	local slug = string.lower(heading)
	slug = string.gsub(slug, "[`*]", "")
	slug = string.gsub(slug, "[^%w%s_-]", "")
	slug = string.gsub(slug, "%s", "-")
	return slug
end

function Markdown.anchors(source: string): { [string]: boolean }
	local anchors: { [string]: boolean } = {}
	local seen: { [string]: number } = {}
	local fenced = false
	for _, raw in string.split(string.gsub(source, "\r\n", "\n"), "\n") do
		if string.match(raw, "^%s*```") ~= nil then
			fenced = not fenced
			continue
		end
		if fenced then
			continue
		end
		for name in string.gmatch(raw, '<a%s+id="([^"]+)"') do
			anchors[name] = true
		end
		for name in string.gmatch(raw, '<a%s+name="([^"]+)"') do
			anchors[name] = true
		end
		local heading = string.match(raw, "^#+%s+(.-)%s*$")
		if heading ~= nil then
			local slug = Markdown.slug(heading)
			local count = seen[slug] or 0
			anchors[if count == 0 then slug else ("%s-%d"):format(slug, count)] = true
			seen[slug] = count + 1
		end
	end
	return anchors
end

function Markdown.blankCode(source: string): string
	local blanked = string.gsub("\n" .. source, "\n```.-\n```", function(block: string): string
		local spaces = string.gsub(block, "[^\n]", " ")
		return spaces
	end)
	blanked = string.gsub(blanked, "`[^`\n]*`", function(span: string): string
		return string.rep(" ", #span)
	end)
	return string.sub(blanked, 2)
end

function Markdown.links(source: string): { Link }
	local prose = Markdown.blankCode(source)
	local found: { Link } = {}
	local line = 1
	local consumed = 1
	local cursor = 1
	while true do
		local start, finish, labelText, inside = string.find(prose, "%[([^%[%]]*)%]%(%s*([^)]*)%)", cursor)
		if start == nil or finish == nil or labelText == nil or inside == nil then
			break
		end
		cursor = finish + 1
		local _, breaks = string.gsub(string.sub(prose, consumed, start - 1), "\n", "")
		line += breaks
		consumed = start
		local target = string.match(inside, "^%S+")
		if target ~= nil then
			table.insert(found, {
				start = start,
				line = line,
				label = string.sub(source, start + 1, start + #labelText),
				target = target,
			})
		end
	end
	return found
end

function Markdown.isExternal(target: string): boolean
	return string.match(target, "^%a[%w+.-]*:") ~= nil
end

function Markdown.normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == "." then
			continue
		elseif part == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
		else
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

function Markdown.directoryOf(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

return table.freeze(Markdown)
