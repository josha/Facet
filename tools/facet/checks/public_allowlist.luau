--!strict
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local fs = require("@std/fs")
local Allowlist = require("../lib/allowlist")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Rule = require("../lib/rule")
local Run = require("../lib/run")

local LIST = "tools/public_allowlist.txt"
local PRIVATE = { "docs/plans/", "docs/superpowers/", "artifacts/distribution-readiness/" }
local REPORT_LIMIT = 12

local function private(path: string): boolean
	for _, prefix in PRIVATE do
		if stringext.hasPrefix(path, prefix) then
			return true
		end
	end
	return false
end

local function strays(paths: { string }, list: Allowlist.Allowlist): { string }
	local found: { string } = {}
	for _, path in paths do
		if not Allowlist.allowed(list, path) or Allowlist.denied(list, path) or private(path) then
			table.insert(found, path)
		end
	end
	return found
end

local function present(path: string): boolean
	if Files.kind(path) ~= "missing" then
		return true
	end
	local name = Files.name(path)
	for _, entry in Files.list(Files.parent(path)) do
		if entry.name == name then
			return true
		end
	end
	return false
end

local function workingPaths(context: Rule.Context, paths: { string }): { string }
	local found: { string } = {}
	for _, path in paths do
		if present(context.path(path)) then
			table.insert(found, path)
		end
	end
	return found
end

local function tracked(context: Rule.Context): ({ string }?, string?)
	local result = Run.git({ "ls-files", "-z" }, context.root)
	if not result.ok then
		return nil, ("git ls-files failed in %s: %s"):format(context.root, result.stderr)
	end
	local paths: { string } = {}
	for _, path in string.split(result.stdout, "\0") do
		if path ~= "" then
			table.insert(paths, path)
		end
	end
	return workingPaths(context, paths), nil
end

local function inspect(context: Rule.Context): ({ string }?, string?)
	local listPath = context.path(LIST)
	if not Files.isFile(listPath) then
		return nil, ("%s is missing"):format(LIST)
	end
	local paths, problem = tracked(context)
	if paths == nil then
		return nil, problem
	end
	return strays(paths, Allowlist.parse(Files.text(listPath))), nil
end

local function check(context: Rule.Context): { string }
	local found, problem = inspect(context)
	if found == nil then
		return { problem or "cannot list the tracked paths" }
	end
	local findings: { string } = {}
	for _, path in found do
		table.insert(
			findings,
			("not allowed on the public tip: %s (archive it or extend %s with a reason)"):format(path, LIST)
		)
	end
	return findings
end

local function report(context: Rule.Context, _invocation: Cli.Invocation): number
	local found, problem = inspect(context)
	if found == nil then
		print("public-allowlist: " .. (problem or "cannot list the tracked paths"))
		return 1
	end
	local groups: { [string]: { string } } = {}
	local tops: { string } = {}
	for _, path in found do
		local top = string.match(path, "^([^/]*)") or path
		local group = groups[top]
		if group == nil then
			group = {}
			groups[top] = group
			table.insert(tops, top)
		end
		table.insert(group, path)
	end
	table.sort(tops)
	for _, top in tops do
		local items = groups[top]
		print(("%s: %d path(s)"):format(top, #items))
		for index = 1, math.min(#items, REPORT_LIMIT) do
			print("  " .. items[index])
		end
		if #items > REPORT_LIMIT then
			print(("  \u{2026} %d more"):format(#items - REPORT_LIMIT))
		end
	end
	print(("strays: %d"):format(#found))
	return 0
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "allowed paths pass and denied or unlisted paths are strays", {
		id = prefix .. "allowed paths pass and denied or unlisted paths are strays",
		run = function(test: Verify.Context)
			local list = Allowlist.parse("src/\nREADME.md\n!src/core/fusion_adapter.luau\n")
			local clean = { "src/init.luau", "README.md", "src/core/services.luau" }
			local planted = table.clone(clean)
			table.insert(planted, "docs/plans/secret-plan.md")
			table.insert(planted, "src/core/fusion_adapter.luau")
			Verify.expect(strays(clean, list)):toEqual({})
			Verify.expect(strays(planted, list))
				:toEqual({ "docs/plans/secret-plan.md", "src/core/fusion_adapter.luau" })
		end,
	})
	harness:case(prefix .. "private trees are strays even when a broad line allows them", {
		id = prefix .. "private trees are strays even when a broad line allows them",
		run = function(test: Verify.Context)
			local broad = Allowlist.parse("docs/\nartifacts/\n")
			local privatePaths =
				{ "docs/plans/goal.md", "docs/superpowers/specs/x.md", "artifacts/distribution-readiness/owner.md" }
			local candidates = table.clone(privatePaths)
			table.insert(candidates, "docs/guide/a.md")
			Verify.expect(strays(candidates, broad)):toEqual(privatePaths)
		end,
	})
	harness:case(prefix .. "glob, character set and negated patterns match like fnmatch", {
		id = prefix .. "glob, character set and negated patterns match like fnmatch",
		run = function(test: Verify.Context)
			local list = Allowlist.parse(
				"# comment\r\n  tools/  \r\n*.md\r\n!*.env\r\n!!tools/secret_[0-9].txt\r\n!tools/[!a-m]*.key\r\n"
			)
			Verify.expect(strays({
				"tools/run.luau",
				"docs/guide/deep/page.md",
				"tools/config/.env",
				"tools/secret_7.txt",
				"tools/secret_x.txt",
				"tools/zeta.key",
				"tools/alpha.key",
				"bench/x.luau",
			}, list)):toEqual({ "tools/config/.env", "tools/secret_7.txt", "tools/zeta.key", "bench/x.luau" })
		end,
	})
	harness:case(prefix .. "deleted paths are not working paths and present files are", {
		id = prefix .. "deleted paths are not working paths and present files are",
		run = function(test: Verify.Context)
			Rule.within(test, { ["docs/plans/present.md"] = "private" }, function(context)
				local broad = Allowlist.parse("docs/\n")
				local candidates = { "docs/plans/deleted.md", "docs/plans/present.md" }
				local linked = false
				local made = pcall(fs.symbolicLink, context.path("missing.md"), context.path("docs/plans/dangling.md"))
				if made then
					linked = true
					table.insert(candidates, "docs/plans/dangling.md")
				end
				local expected = { "docs/plans/present.md" }
				if linked then
					table.insert(expected, "docs/plans/dangling.md")
				end
				Verify.expect(strays(workingPaths(context, candidates), broad)):toEqual(expected)
			end)
		end,
	})
	harness:case(prefix .. "a missing allowlist is reported", {
		id = prefix .. "a missing allowlist is reported",
		run = function(test: Verify.Context)
			Rule.within(test, { ["README.md"] = "" }, function(context)
				Verify.expect(check(context)):toEqual({ LIST .. " is missing" })
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "public-allowlist",
	summary = "Every tracked path is allowed on the public tip by tools/public_allowlist.txt.",
	check = check,
	register = register,
	actions = {
		report = {
			summary = "Print the stray paths grouped by top-level directory, and exit 0.",
			run = report,
		},
	},
}

return rule
