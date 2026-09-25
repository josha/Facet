--!strict

local fs = require("@lune/fs")

local check_links = {}

local ALLOWLIST = "tools/public_allowlist.txt"

local ARCHIVED_PREFIXES = {
	"docs/adr/",
	"docs/lessons/",
	"docs/plans/",
	"docs/handoff/",
	"docs/research/",
	"artifacts/",
	".superpowers/",
	"vendor/",
}
local ARCHIVED_FILES: { [string]: boolean } = {
	["docs/INVENTORY.md"] = true,
	["ui_todo.md"] = true,
	["sweep.luau"] = true,
}

local PUBLIC_REFERENCE: { [string]: boolean } = {
	["docs/reference/api.md"] = true,
	["docs/reference/constitution.md"] = true,
}

export type Opts = {
	fileOverrides: { [string]: string }?,
}

local function normalize(path: string): string
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

local function dirOf(path: string): string
	local dir = string.match(path, "^(.*)/[^/]*$")
	return dir or ""
end

local function isArchived(repoPath: string): boolean
	if ARCHIVED_FILES[repoPath] then
		return true
	end
	if string.sub(repoPath, 1, 15) == "docs/reference/" and not PUBLIC_REFERENCE[repoPath] then
		return true
	end
	for _, prefix in ARCHIVED_PREFIXES do
		if string.sub(repoPath, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function blankCode(source: string): string
	local out = string.gsub("\n" .. source, "\n```.-\n```", function(block: string): string
		return (string.gsub(block, "[^\n]", " "))
	end)
	out = string.gsub(out, "`[^`\n]*`", function(span: string): string
		return string.rep(" ", #span)
	end)
	return out
end

local function anchorsOf(source: string): { [string]: boolean }
	local anchors: { [string]: boolean } = {}
	local seen: { [string]: number } = {}
	local inFence = false
	for line in string.gmatch("\n" .. source, "\n([^\n]*)") do
		if string.match(line, "^%s*```") ~= nil then
			inFence = not inFence
			continue
		end
		if inFence then
			continue
		end

		for id in string.gmatch(line, '<a%s+id="([^"]+)"') do
			anchors[id] = true
		end
		for id in string.gmatch(line, '<a%s+name="([^"]+)"') do
			anchors[id] = true
		end
		local heading = string.match(line, "^#+%s+(.-)%s*$")
		if heading ~= nil then
			local slug = string.lower(heading)
			slug = string.gsub(slug, "[`*]", "")
			slug = string.gsub(slug, "[^%w%s_-]", "")
			slug = string.gsub(slug, "%s", "-")
			local count = seen[slug] or 0
			anchors[if count == 0 then slug else `{slug}-{count}`] = true
			seen[slug] = count + 1
		end
	end
	return anchors
end

local function isExternal(target: string): boolean
	return string.match(target, "^%a[%w+.-]*:") ~= nil
end

local patternCache: { [string]: string } = {}
local function globPattern(glob: string): string
	local cached = patternCache[glob]
	if cached ~= nil then
		return cached
	end
	local out: { string } = { "^" }
	for i = 1, #glob do
		local c = string.sub(glob, i, i)
		if c == "*" then
			table.insert(out, ".*")
		elseif c == "?" then
			table.insert(out, ".")
		elseif string.match(c, "[%w_/-]") ~= nil then
			table.insert(out, c)
		else
			table.insert(out, "%" .. c)
		end
	end
	table.insert(out, "$")
	local pattern = table.concat(out)
	patternCache[glob] = pattern
	return pattern
end

local function matchesPattern(path: string, pattern: string): boolean
	if string.sub(pattern, -1) == "/" then
		return string.sub(path, 1, #pattern) == pattern
	end
	if path == pattern then
		return true
	end
	return string.match(path, globPattern(pattern)) ~= nil
end

type Allowlist = { allows: { string }, denies: { string } }

local function readAllowlist(): Allowlist?
	if not fs.isFile(ALLOWLIST) then
		return nil
	end
	local allows: { string } = {}
	local denies: { string } = {}
	for raw in string.gmatch(fs.readFile(ALLOWLIST), "[^\n]+") do
		local line = string.match(raw, "^%s*(.-)%s*$") :: string
		if line == "" or string.sub(line, 1, 1) == "#" then
			continue
		end
		if string.sub(line, 1, 1) == "!" then
			table.insert(denies, string.sub(line, 2))
		else
			table.insert(allows, line)
		end
	end
	return { allows = allows, denies = denies }
end

local function isPublic(path: string, list: Allowlist): boolean
	local allowed = false
	for _, pattern in list.allows do
		if matchesPattern(path, pattern) then
			allowed = true
			break
		end
	end
	if not allowed then
		return false
	end
	for _, pattern in list.denies do
		if matchesPattern(path, pattern) then
			return false
		end
	end
	return true
end

local function documents(list: Allowlist): { string }
	local seen: { [string]: boolean } = {}
	local found: { string } = {}
	local function consider(path: string)
		if seen[path] or isArchived(path) or not isPublic(path, list) then
			return
		end
		seen[path] = true
		table.insert(found, path)
	end
	local function walk(dir: string)
		if not fs.isDir(dir) then
			return
		end
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			local path = `{dir}/{entry}`
			if fs.isDir(path) then
				walk(path)
			elseif string.match(entry, "%.md$") ~= nil then
				consider(path)
			end
		end
	end
	for _, pattern in list.allows do
		if string.sub(pattern, -1) == "/" then
			walk(string.sub(pattern, 1, -2))
		elseif string.match(pattern, "%.md$") ~= nil and fs.isFile(pattern) then
			consider(pattern)
		end
	end
	table.sort(found)
	return found
end

function check_links.check(opts: Opts?): { ok: boolean, problems: { string }, counts: { [string]: number } }
	local overrides = (opts and opts.fileOverrides) or {}
	local problems: { string } = {}
	local linksChecked = 0
	local anchorsChecked = 0
	local anchorCache: { [string]: { [string]: boolean } } = {}

	local function sourceOf(path: string): string?
		if overrides[path] ~= nil then
			return overrides[path]
		end
		if not fs.isFile(path) then
			return nil
		end
		return fs.readFile(path)
	end

	local function anchorSetOf(path: string): { [string]: boolean }?
		if anchorCache[path] == nil then
			local source = sourceOf(path)
			if source == nil then
				return nil
			end
			anchorCache[path] = anchorsOf(source)
		end
		return anchorCache[path]
	end

	local list = readAllowlist()
	if list == nil then
		return {
			ok = false,
			problems = {
				`{ALLOWLIST} is missing, and it is what decides which documents ship — `
					.. "this check cannot answer without it",
			},
			counts = { documents = 0, links = 0, anchors = 0, problems = 1 },
		}
	end

	local docs = documents(list :: Allowlist)
	for _, doc in docs do
		local raw = sourceOf(doc)
		if raw == nil then
			continue
		end
		local prose = blankCode(raw :: string)
		local line = 1
		local consumed = 1

		for start, labelText, inside in string.gmatch(prose, "()%[([^%[%]]*)%]%(%s*([^)]*)%)") do
			local label = string.sub(raw :: string, start, start + #labelText - 1)
			local _, breaks = string.gsub(string.sub(prose, consumed, start), "\n", "")
			line += breaks
			consumed = start

			local found = string.match(inside, "^%S+")
			if found == nil then
				continue
			end
			local target = found :: string
			if isExternal(target) then
				continue
			end
			linksChecked += 1

			local path, fragment = string.match(target, "^([^#]*)#(.*)$")
			if path == nil then
				path = target
				fragment = nil
			end

			local targetDoc: string
			if path == "" then
				targetDoc = doc
			elseif string.sub(path :: string, 1, 1) == "/" then
				targetDoc = normalize(string.sub(path :: string, 2))
			else
				targetDoc = normalize(`{dirOf(doc)}/{path}`)
			end

			if isArchived(targetDoc) then
				table.insert(
					problems,
					`{doc}:{line}: links into material that is not published — {target} `
						.. `(resolves to {targetDoc}). Make it plain text: the link label, the path in a `
						.. "code span, and `(archived privately)`."
				)
				continue
			end

			local exists = overrides[targetDoc] ~= nil or fs.isFile(targetDoc) or fs.isDir(targetDoc)
			if not exists then
				table.insert(
					problems,
					`{doc}:{line}: dead link — {target} (resolves to {targetDoc}, which does not exist)`
				)
				continue
			end

			if
				(fragment == nil or fragment == "")
				and string.match(targetDoc, "%.md$") ~= nil
				and string.match(label, "^`[^`]+`$") ~= nil
				and string.find(label, "/", 1, true) == nil
				and string.match(label, "%.md`$") == nil
				and string.match(label, "%.luau`$") == nil
				and string.match(label, "%.json`$") == nil
			then
				table.insert(
					problems,
					`{doc}:{line}: {label} names a specific part of {targetDoc} but links to the top of the `
						.. "page; add the heading anchor"
				)
			end

			if fragment ~= nil and fragment ~= "" and string.match(targetDoc, "%.md$") ~= nil then
				local anchors = anchorSetOf(targetDoc)
				if anchors ~= nil then
					anchorsChecked += 1
					if not anchors[fragment :: string] then
						table.insert(
							problems,
							`{doc}:{line}: no such heading — {target} ({targetDoc} has no heading whose `
								.. `anchor is '#{fragment}')`
						)
					end
				end
			end
		end
	end

	return {
		ok = #problems == 0,
		problems = problems,
		counts = {
			documents = #docs,
			links = linksChecked,
			anchors = anchorsChecked,
			problems = #problems,
		},
	}
end

function check_links.selftest(): { ok: boolean, problems: { string } }
	local problems: { string } = {}
	local victim = "AGENTS.md"
	if not fs.isFile(victim) then
		return { ok = false, problems = { `selftest needs {victim} and it is missing` } }
	end

	local planted = fs.readFile(victim)
		.. "\n\n[a file that is not there](docs/guide/00-does-not-exist.md)\n"
		.. "\n[the internal plan](docs/plans/distribution-readiness.md)\n"
		.. '\n[the internal plan](docs/handoff/a-handoff.md "why it exists")\n'
		.. "\n[`Facet.bind`](docs/reference/api.md)\n"

	local widened = "docs/MAINTAINERS.md"
	if not fs.isFile(widened) then
		return { ok = false, problems = { `selftest needs {widened} and it is missing` } }
	end
	local plantedWide = fs.readFile(widened) .. "\n\n[a page that is not there](guide/00-no-such-chapter.md)\n"

	local result = check_links.check({
		fileOverrides = { [victim] = planted, [widened] = plantedWide },
	})

	local sawDead = false
	local sawArchived = false
	local sawTitled = false
	for _, problem in result.problems do
		if string.find(problem, "00-does-not-exist.md", 1, true) ~= nil then
			sawDead = true
		end
		if string.find(problem, "docs/plans/distribution-readiness.md", 1, true) ~= nil then
			sawArchived = true
		end
		if string.find(problem, "docs/handoff/a-handoff.md", 1, true) ~= nil then
			sawTitled = true
		end
	end
	if not sawDead then
		table.insert(problems, "a planted dead link was not reported")
	end
	if not sawArchived then
		table.insert(problems, "a planted link into archived material was not reported")
	end
	if not sawTitled then
		table.insert(problems, "a planted TITLED link into archived material was not reported")
	end
	local sawBare = false
	for _, problem in result.problems do
		if string.find(problem, "`Facet.bind` names a specific part", 1, true) ~= nil then
			sawBare = true
		end
	end
	if not sawBare then
		table.insert(problems, "a planted code-name link without a heading anchor was not reported")
	end
	local sawWidened = false
	for _, problem in result.problems do
		if string.find(problem, "00-no-such-chapter.md", 1, true) ~= nil then
			sawWidened = true
		end
	end
	if not sawWidened then
		table.insert(problems, `a planted dead link in {widened} was not reported — the scanned set is too narrow`)
	end

	local clean = check_links.check()
	if not clean.ok then
		table.insert(problems, `the tree itself does not pass: {#clean.problems} problem(s)`)
	end

	return { ok = #problems == 0, problems = problems }
end

return check_links
