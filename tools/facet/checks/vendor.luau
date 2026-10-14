--!strict

local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Rule = require("../lib/rule")
local Snapshot = require("../lib/snapshot")

local APPROVED: { [string]: { string } } = {
	["src/vendor"] = { "compose" },
	["tools/vendor"] = { "verify" },
}

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	local composeOk, composeMessage = Snapshot.check(context.root, "compose")
	if not composeOk then
		table.insert(findings, composeMessage)
	end
	local verifyOk, verifyMessage = Snapshot.check(context.root, "verify")
	if not verifyOk then
		table.insert(findings, verifyMessage)
	end
	for directory, allowed in APPROVED do
		for _, entry in Files.list(context.path(directory)) do
			if table.find(allowed, entry.name) == nil then
				table.insert(
					findings,
					("%s/%s: only the pinned %s dependency is approved"):format(
						directory,
						entry.name,
						table.concat(allowed, ", ")
					)
				)
			end
		end
	end
	table.sort(findings)
	return findings
end

local function pinned(files: { [string]: string }, docs: { [string]: string }): string
	local hashes = Json.object()
	for name, data in files do
		Json.set(hashes, name, Hash.sha256(data))
	end
	local guides = Json.object()
	for name, data in docs do
		Json.set(guides, name, Hash.sha256(data))
	end
	return Json.encode({
		repository = "https://github.com/voidmeld/fixture",
		commit = string.rep("c", 40),
		sha256 = hashes,
		docs = guides,
	})
end

local function tree(): { [string]: string }
	local composeFiles = { ["core/init.luau"] = "return {}\n", LICENSE = "MIT\n" }
	local verifyFiles = { ["src/core/init.luau"] = "return {}\n" }
	local verifyDocs = { ["SKILL.md"] = "Guide\n" }
	return {
		["src/vendor/compose/core/init.luau"] = composeFiles["core/init.luau"],
		["src/vendor/compose/LICENSE"] = composeFiles.LICENSE,
		["src/vendor/compose/UPSTREAM.lock"] = pinned(composeFiles, { ["SKILL.md"] = "Compose\n" }),
		["skills/compose/SKILL.md"] = "Compose\n",
		["tools/vendor/verify/src/core/init.luau"] = verifyFiles["src/core/init.luau"],
		["tools/vendor/verify/.agents/skills/verify/SKILL.md"] = verifyDocs["SKILL.md"],
		["tools/vendor/verify/UPSTREAM.lock"] = pinned(verifyFiles, verifyDocs),
	}
end

local function cases(): { Rule.Case }
	return {
		{
			name = "intact pinned snapshots pass",
			run = function()
				return Rule.within(tree(), function(context)
					local findings = check(context)
					return Rule.expect(#findings == 0, Rule.describe(findings))
				end)
			end,
		},
		{
			name = "a modified vendored file fails",
			run = function()
				return Rule.within(tree(), function(context)
					Files.write(context.path("src/vendor/compose/core/init.luau"), "return { changed = true }\n")
					return Rule.expect(
						Rule.contains(check(context), "Compose: missing or modified"),
						"the change passed"
					)
				end)
			end,
		},
		{
			name = "a modified nested guide fails",
			run = function()
				return Rule.within(tree(), function(context)
					Files.write(context.path("tools/vendor/verify/.agents/skills/verify/SKILL.md"), "Changed\n")
					return Rule.expect(
						Rule.contains(check(context), "Verify: missing or modified"),
						"the change passed"
					)
				end)
			end,
		},
		{
			name = "an unapproved vendor directory fails",
			run = function()
				local files = tree()
				files["src/vendor/other/init.luau"] = "return {}\n"
				return Rule.within(files, function(context)
					return Rule.expect(Rule.contains(check(context), "src/vendor/other"), "the extra vendor passed")
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "vendor",
	summary = "The vendored Compose and Verify snapshots match their pins, and no other vendor exists.",
	check = check,
	cases = cases,
}

return rule
