--!strict

local stringext = require("@std/stringext")
local Allowlist = require("../lib/allowlist")
local Case = require("../lib/case")
local Files = require("../lib/files")
local Markdown = require("../lib/markdown")
local Rule = require("../lib/rule")

local ALLOWLIST = "tools/public_allowlist.txt"
local VENDOR = "tools/vendor/"
local REFERENCE = "docs/reference/"
local EM_DASH = "\u{2014}"

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

export type Counts = { documents: number, links: number, anchors: number }

local function isArchived(path: string): boolean
	if ARCHIVED_FILES[path] then
		return true
	end
	if stringext.hasPrefix(path, REFERENCE) and not PUBLIC_REFERENCE[path] then
		return true
	end
	for _, prefix in ARCHIVED_PREFIXES do
		if stringext.hasPrefix(path, prefix) then
			return true
		end
	end
	return false
end

local function documents(context: Rule.Context, list: Allowlist.Allowlist): { string }
	local seen: { [string]: boolean } = {}
	local found: { string } = {}
	local function consider(path: string)
		if seen[path] or isArchived(path) or not Allowlist.public(list, path) or stringext.hasPrefix(path, VENDOR) then
			return
		end
		seen[path] = true
		table.insert(found, path)
	end
	for _, pattern in list.allows do
		if string.sub(pattern, -1) == "/" then
			local directory = string.sub(pattern, 1, -2)
			for _, relative in Files.walk(context.path(directory)) do
				if string.sub(relative, -3) == ".md" then
					consider(directory .. "/" .. relative)
				end
			end
		elseif string.sub(pattern, -3) == ".md" and Files.isFile(context.path(pattern)) then
			consider(pattern)
		end
	end
	table.sort(found)
	return found
end

local function resolve(document: string, path: string): string
	if path == "" then
		return document
	elseif string.sub(path, 1, 1) == "/" then
		return Markdown.normalize(string.sub(path, 2))
	end
	return Markdown.normalize(Markdown.directoryOf(document) .. "/" .. path)
end

local function namesPart(label: string): boolean
	return string.match(label, "^`[^`]+`$") ~= nil
		and string.find(label, "/", 1, true) == nil
		and string.match(label, "%.md`$") == nil
		and string.match(label, "%.luau`$") == nil
		and string.match(label, "%.json`$") == nil
end

local function inspect(context: Rule.Context): ({ string }, Counts)
	local problems: { string } = {}
	local counts: Counts = { documents = 0, links = 0, anchors = 0 }
	local listPath = context.path(ALLOWLIST)
	if not Files.isFile(listPath) then
		return {
			("%s is missing, and it is what decides which documents ship %s this check cannot answer without it"):format(
				ALLOWLIST,
				EM_DASH
			),
		},
			counts
	end
	local list = Allowlist.parse(Files.text(listPath))
	local anchorCache: { [string]: { [string]: boolean } } = {}
	local function anchorsOf(path: string): { [string]: boolean }
		local cached = anchorCache[path]
		if cached == nil then
			cached = Markdown.anchors(Files.text(context.path(path)))
			anchorCache[path] = cached
		end
		return cached
	end
	local docs = documents(context, list)
	counts.documents = #docs
	for _, document in docs do
		for _, link in Markdown.links(Files.text(context.path(document))) do
			local target = link.target
			if Markdown.isExternal(target) then
				continue
			end
			counts.links += 1
			local path, fragment = string.match(target, "^([^#]*)#(.*)$")
			local resolved = resolve(document, path or target)
			if isArchived(resolved) then
				table.insert(
					problems,
					("%s:%d: links into material that is not published %s %s (resolves to %s). Make it plain text: the link label, the path in a code span, and `(archived privately)`."):format(
						document,
						link.line,
						EM_DASH,
						target,
						resolved
					)
				)
				continue
			end
			local absolute = context.path(resolved)
			if not Files.isFile(absolute) and not Files.isDirectory(absolute) then
				table.insert(
					problems,
					("%s:%d: dead link %s %s (resolves to %s, which does not exist)"):format(
						document,
						link.line,
						EM_DASH,
						target,
						resolved
					)
				)
				continue
			end
			local markdownTarget = string.sub(resolved, -3) == ".md"
			if (fragment == nil or fragment == "") and markdownTarget and namesPart(link.label) then
				table.insert(
					problems,
					("%s:%d: %s names a specific part of %s but links to the top of the page; add the heading anchor"):format(
						document,
						link.line,
						link.label,
						resolved
					)
				)
			end
			if fragment ~= nil and fragment ~= "" and markdownTarget and Files.isFile(absolute) then
				counts.anchors += 1
				if not anchorsOf(resolved)[fragment] then
					table.insert(
						problems,
						("%s:%d: no such heading %s %s (%s has no heading whose anchor is '#%s')"):format(
							document,
							link.line,
							EM_DASH,
							target,
							resolved,
							fragment
						)
					)
				end
			end
		end
	end
	return problems, counts
end

local function check(context: Rule.Context): { string }
	local problems = inspect(context)
	return problems
end

local ALLOWLIST_FIXTURE = "AGENTS.md\ndocs/guide/\ndocs/reference/api.md\ndocs/MAINTAINERS.md\n!docs/guide/secret.md\n"

local function fixture(extra: { [string]: string }): { [string]: string }
	local files: { [string]: string } = {
		[ALLOWLIST] = ALLOWLIST_FIXTURE,
		["AGENTS.md"] = "# Agents\n\nRead [the guide](docs/guide/intro.md#first-steps).\n",
		["docs/MAINTAINERS.md"] = "# Maintainers\n\nSee [the reference](reference/api.md#facetbind).\n",
		["docs/reference/api.md"] = "# API\n\n## `Facet.bind`\n\n## Notes\n\n## Notes\n",
		["docs/guide/intro.md"] = "# Intro\n\n## First steps\n",
	}
	for path, contents in extra do
		files[path] = contents
	end
	return files
end

local function expectFindings(extra: { [string]: string }, fragments: { string }): string?
	return Rule.within(fixture(extra), function(context)
		local findings = check(context)
		for _, fragment in fragments do
			if not Rule.contains(findings, fragment) then
				return ("expected a finding with '%s', got %s"):format(fragment, Rule.describe(findings))
			end
		end
		return nil
	end)
end

local function expectClean(extra: { [string]: string }): string?
	return Rule.within(fixture(extra), function(context)
		return Case.same(check(context), {})
	end)
end

local function cases(): { Rule.Case }
	return {
		{
			name = "a clean fixture passes and counts its links",
			run = function()
				return Rule.within(fixture({}), function(context)
					local problems, counts = inspect(context)
					return Case.first(
						Case.same(problems, {}),
						Case.equal(counts.documents, 4, "documents"),
						Case.equal(counts.links, 2, "links"),
						Case.equal(counts.anchors, 2, "anchors")
					)
				end)
			end,
		},
		{
			name = "a dead link is reported on its own line",
			run = function()
				return expectFindings({
					["AGENTS.md"] = "# Agents\n\n[a file that is not there](docs/guide/00-does-not-exist.md)\n",
				}, { "AGENTS.md:3: dead link " .. EM_DASH .. " docs/guide/00-does-not-exist.md" })
			end,
		},
		{
			name = "a link into archived material is reported, with or without a title",
			run = function()
				return expectFindings({
					["AGENTS.md"] = '[the plan](docs/plans/distribution-readiness.md)\n[the handoff](docs/handoff/a-handoff.md "why it exists")\n[old](docs/reference/retired.md)\n',
				}, {
					"AGENTS.md:1: links into material that is not published "
						.. EM_DASH
						.. " docs/plans/distribution-readiness.md",
					"AGENTS.md:2: links into material that is not published "
						.. EM_DASH
						.. " docs/handoff/a-handoff.md",
					"resolves to docs/reference/retired.md",
				})
			end,
		},
		{
			name = "a code-name link without a heading anchor is reported",
			run = function()
				return expectFindings(
					{ ["AGENTS.md"] = "[`Facet.bind`](docs/reference/api.md)\n" },
					{ "`Facet.bind` names a specific part of docs/reference/api.md" }
				)
			end,
		},
		{
			name = "a code-name label that names a file may link to the top of the page",
			run = function()
				return expectClean({ ["AGENTS.md"] = "[`docs/reference/api.md`](docs/reference/api.md)\n" })
			end,
		},
		{
			name = "a missing heading anchor is reported and a repeated heading gets a numbered anchor",
			run = function()
				return Case.first(
					expectFindings(
						{ ["AGENTS.md"] = "[x](docs/reference/api.md#nowhere)\n" },
						{ "no such heading " .. EM_DASH .. " docs/reference/api.md#nowhere" }
					),
					expectClean({ ["AGENTS.md"] = "[x](docs/reference/api.md#notes-1)\n" })
				)
			end,
		},
		{
			name = "a dead link in a document widened by the allowlist is reported",
			run = function()
				return expectFindings(
					{ ["docs/MAINTAINERS.md"] = "# Maintainers\n\n[a page](guide/00-no-such-chapter.md)\n" },
					{ "docs/MAINTAINERS.md:3: dead link " .. EM_DASH .. " guide/00-no-such-chapter.md" }
				)
			end,
		},
		{
			name = "links in code, external links and denied documents are not checked",
			run = function()
				return expectClean({
					["AGENTS.md"] = "```md\n[x](docs/nowhere.md)\n```\n\n`[y](docs/nowhere.md)`\n\n[z](https://example.com/nowhere.md)\n",
					["docs/guide/secret.md"] = "[x](docs/nowhere.md)\n",
				})
			end,
		},
		{
			name = "CRLF line endings report the same lines as LF",
			run = function()
				return expectFindings(
					{ ["AGENTS.md"] = "# Agents\r\n\r\n[dead](docs/nowhere.md)\r\n" },
					{ "AGENTS.md:3: dead link" }
				)
			end,
		},
		{
			name = "a missing allowlist is reported",
			run = function()
				return Rule.within({ ["AGENTS.md"] = "# Agents\n" }, function(context)
					local findings = check(context)
					return Case.expect(
						#findings == 1 and Rule.contains(findings, ALLOWLIST .. " is missing"),
						"expected one missing-allowlist finding, got " .. Rule.describe(findings)
					)
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "links",
	summary = "Every relative link in a published document resolves, and every heading anchor exists.",
	check = check,
	cases = cases,
}

return rule
