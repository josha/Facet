--!strict
local Verify = require("@verify/src/core")

local Files = require("../lib/files")
local Packages = require("../lib/packages")
local Rule = require("../lib/rule")
local Snapshot = require("../lib/snapshot")

local APPROVED: { [string]: { string } } = {
	["src/vendor"] = { "compose" },
}

local PINNED = { "compose", "verify" }

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	local composeOk, composeMessage = Snapshot.check(context.root, "compose")
	if not composeOk then
		table.insert(findings, composeMessage)
	end
	local notices = if Files.exists(context.path("THIRD_PARTY_NOTICES.md"))
		then Files.read(context.path("THIRD_PARTY_NOTICES.md"))
		else ""
	for _, name in PINNED do
		local locked, problem = Packages.locked(context.root, name)
		if locked == nil then
			table.insert(findings, problem or ("pkg.lock.luau does not pin %s"):format(name))
			continue
		end
		local commit = locked.rev
		if string.find(notices, commit, 1, true) == nil then
			table.insert(findings, ("THIRD_PARTY_NOTICES.md: name the pinned %s commit %s"):format(name, commit))
		end
		if name == "compose" and Files.exists(context.path("src/init.luau")) then
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
	if Files.exists(context.path("tools/vendor")) then
		table.insert(findings, "tools/vendor: development dependencies come from lute pkg, not a vendored copy")
	end
	table.sort(findings)
	return findings
end

local COMPOSE = string.rep("c", 40)
local VERIFY = string.rep("d", 40)

local function lock(): string
	local function entry(name: string, commit: string): string
		return ('["%s@%s"] = { name = "%s", rev = "%s", source = "https://github.com/voidmeld/%s", sourceKind = "github", installPath = "@pkg/fixture-%s/.", dependencies = {} }'):format(
			name,
			commit,
			name,
			commit,
			name,
			name
		)
	end
	return ('return { version = 5, dependencies = {}, devDependencies = { compose = "compose@%s", verify = "verify@%s" }, packages = { %s, %s } }\n'):format(
		COMPOSE,
		VERIFY,
		entry("compose", COMPOSE),
		entry("verify", VERIFY)
	)
end

local function tree(): { [string]: string }
	local installed = ".lpm/compose@" .. COMPOSE .. "/"
	local files: { [string]: string } = {
		["pkg.lock.luau"] = lock(),
		["THIRD_PARTY_NOTICES.md"] = ("Compose at commit `%s` and Verify at commit `%s`.\n"):format(COMPOSE, VERIFY),
		["src/init.luau"] = ('local COMPOSE_COMMIT = "%s"\n'):format(COMPOSE),
		["skills/compose/SKILL.md"] = "Compose\n",
		["src/vendor/compose/LICENSE"] = "MIT\n",
		["src/vendor/compose/license.luau"] = "--!strict\nreturn [=[\nMIT\n\n]=]\n",
		["src/vendor/compose/README.md"] = "Generated.\n",
		[installed .. "LICENSE"] = "MIT\n",
		[installed .. ".agents/skills/compose/SKILL.md"] = "Compose\n",
		[".lpm/verify@" .. VERIFY .. "/src/core/init.luau"] = "return {}\n",
	}
	for _, member in { "core", "roblox", "design", "design-editor" } do
		files[installed .. "src/" .. member .. "/init.luau"] = "return {}\n"
		files["src/vendor/compose/" .. member .. "/init.luau"] = "return {}\n"
	end
	return files
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a notice or COMPOSE_COMMIT that differs from the lock fails", {
		id = prefix .. "a notice or COMPOSE_COMMIT that differs from the lock fails",
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
	harness:case(prefix .. "a copy that matches the installed package passes", {
		id = prefix .. "a copy that matches the installed package passes",
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
				Verify.expect(Rule.contains(check(context), "Compose: src/vendor/compose/core/init.luau differs"))
					:toBeTrueWith("the change passed")
			end)
		end,
	})
	harness:case(prefix .. "a modified copied guide fails", {
		id = prefix .. "a modified copied guide fails",
		run = function(test: Verify.Context)
			Rule.within(test, tree(), function(context)
				Files.write(context.path("skills/compose/SKILL.md"), "Changed\n")
				Verify.expect(Rule.contains(check(context), "Compose: skills/compose/SKILL.md differs"))
					:toBeTrueWith("the change passed")
			end)
		end,
	})
	harness:case(prefix .. "an unapproved vendor directory fails", {
		id = prefix .. "an unapproved vendor directory fails",
		run = function(test: Verify.Context)
			local files = tree()
			files["src/vendor/other/init.luau"] = "return {}\n"
			files["tools/vendor/verify/src/core/init.luau"] = "return {}\n"
			Rule.within(test, files, function(context)
				local findings = check(context)
				Verify.expect(Rule.contains(findings, "src/vendor/other")):toBeTrueWith("the extra vendor passed")
				Verify.expect(Rule.contains(findings, "tools/vendor:")):toBeTrueWith("a vendored Verify passed")
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "vendor",
	summary = "The Compose copy matches the package lute pkg installed, the notices name the locked commits, and no other vendor exists.",
	check = check,
	register = register,
}

return rule
