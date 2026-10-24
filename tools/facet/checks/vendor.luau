--!strict
local Verify = require("../../vendor/verify/src/core")

local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Rule = require("../lib/rule")
local Snapshot = require("../lib/snapshot")

local APPROVED: { [string]: { string } } = {
	["src/vendor"] = { "compose" },
	["tools/vendor"] = { "verify" },
}

local LOCKS: { [string]: string } = {
	compose = "src/vendor/compose/UPSTREAM.lock",
	verify = "tools/vendor/verify/UPSTREAM.lock",
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
	local notices = if Files.exists(context.path("THIRD_PARTY_NOTICES.md"))
		then Files.read(context.path("THIRD_PARTY_NOTICES.md"))
		else ""
	for name, lock in LOCKS do
		local commit = if Files.exists(context.path(lock))
			then Json.stringField(Json.decode(Files.read(context.path(lock))), "commit")
			else nil
		if commit ~= nil and string.find(notices, commit, 1, true) == nil then
			table.insert(findings, ("THIRD_PARTY_NOTICES.md: name the pinned %s commit %s"):format(name, commit))
		end
		if name == "compose" and commit ~= nil and Files.exists(context.path("src/init.luau")) then
			if
				string.find(Files.read(context.path("src/init.luau")), `COMPOSE_COMMIT = "{commit}"`, 1, true) == nil
			then
				table.insert(findings, ("src/init.luau: COMPOSE_COMMIT must be the pinned commit %s"):format(commit))
			end
		end
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
		["THIRD_PARTY_NOTICES.md"] = ("Compose and Verify at commit `%s`.\n"):format(string.rep("c", 40)),
		["src/init.luau"] = ('local COMPOSE_COMMIT = "%s"\n'):format(string.rep("c", 40)),
	}
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a notice or COMPOSE_COMMIT that differs from the pin fails", {
		id = prefix .. "a notice or COMPOSE_COMMIT that differs from the pin fails",
		run = function(test: Verify.Context)
			local files = tree()
			files["THIRD_PARTY_NOTICES.md"] = "Compose and Verify at an older commit.\n"
			files["src/init.luau"] = 'local COMPOSE_COMMIT = "old"\n'
			Rule.within(test, files, function(context)
				local findings = table.concat(check(context), "\n")
				for _, expected in
					{ "name the pinned compose commit", "name the pinned verify commit", "COMPOSE_COMMIT must be" }
				do
					if string.find(findings, expected, 1, true) == nil then
						error("missing finding: " .. expected, 0)
					end
				end
				return
			end)
		end,
	})
	harness:case(prefix .. "intact pinned snapshots pass", {
		id = prefix .. "intact pinned snapshots pass",
		run = function(test: Verify.Context)
			Rule.within(test, tree(), function(context)
				local findings = check(context)
				Verify.expect(#findings == 0):toBeTrueWith(Rule.describe(findings))
			end)
		end,
	})
	harness:case(prefix .. "a modified vendored file fails", {
		id = prefix .. "a modified vendored file fails",
		run = function(test: Verify.Context)
			Rule.within(test, tree(), function(context)
				Files.write(context.path("src/vendor/compose/core/init.luau"), "return { changed = true }\n")
				Verify.expect(Rule.contains(check(context), "Compose: missing or modified"))
					:toBeTrueWith("the change passed")
			end)
		end,
	})
	harness:case(prefix .. "a modified nested guide fails", {
		id = prefix .. "a modified nested guide fails",
		run = function(test: Verify.Context)
			Rule.within(test, tree(), function(context)
				Files.write(context.path("tools/vendor/verify/.agents/skills/verify/SKILL.md"), "Changed\n")
				Verify.expect(Rule.contains(check(context), "Verify: missing or modified"))
					:toBeTrueWith("the change passed")
			end)
		end,
	})
	harness:case(prefix .. "an unapproved vendor directory fails", {
		id = prefix .. "an unapproved vendor directory fails",
		run = function(test: Verify.Context)
			local files = tree()
			files["src/vendor/other/init.luau"] = "return {}\n"
			Rule.within(test, files, function(context)
				Verify.expect(Rule.contains(check(context), "src/vendor/other")):toBeTrueWith("the extra vendor passed")
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "vendor",
	summary = "The vendored Compose and Verify snapshots match their pins, and no other vendor exists.",
	check = check,
	register = register,
}

return rule
