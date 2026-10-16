--!strict

local json = require("@std/json")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local DocsIndex = require("../lib/docs_index")
local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Run = require("../lib/run")
local Lute = require("../../vendor/verify/src/lute")

local USAGE = [[usage: lute run tools/facet kit --out DIR [--force] [--json]

Writes the Facet author kit into a game project, so that an author or a coding
agent can run the author commands there:

  Packages/Facet/                  the library, from src/
  docs/, examples/blocks/          the API reference, consumer guides and starter blocks
  tools/facet/                     the author commands: info, docs, lint, preview and audit,
                                   and kit.json with the source commit of the kit
  tools/play/                      the Studio play host that preview and audit use
  tools/vendor/verify/             Verify (MIT), which the play host and audit use
  tools/typecheck/roblox.d.luau    the pinned Roblox definitions for lint --types
  .agents/skills/                  the use-facet and compose skills

Map Packages to ReplicatedStorage.Packages in the Rojo project. The kit refuses
to replace a path that exists in DIR unless you give --force. The Roblox
definitions come from the cache that lute run tools/facet types writes.]]

local AUTHOR_COMMANDS = { "info", "docs", "project", "lint", "preview", "audit", "verify" }
local DEFINITIONS_LOCK = "tools/typecheck/roblox.lock.json"
local DEFINITIONS_CACHE = "artifacts/verify/types/roblox.d.luau"
local OWNED = {
	"examples/themes",
	"Packages/Facet",
	"docs",
	"tools/facet",
	"tools/play",
	"tools/studio/live/frame_stability.luau",
	"tools/vendor/verify",
	"tools/typecheck",
	".agents/skills/use-facet",
	".agents/skills/compose",
}

export type Plan = { copies: { [string]: string }, writes: { [string]: string }, problems: { string } }

local function tree(plan: Plan, source: string, target: string, keep: ((string) -> boolean)?)
	if not Files.isDirectory(source) then
		table.insert(plan.problems, source .. " is missing")
		return
	end
	for _, relative in Files.walk(source) do
		if keep == nil or keep(relative) then
			plan.copies[Files.join(target, relative)] = Files.join(source, relative)
		end
	end
end

local function resolve(from: string, request: string): string?
	local directory = Files.parent(from)
	local base: string
	if string.sub(request, 1, 6) == "@self/" then
		local selfRoot = if Files.name(from) == "init.luau" then directory else directory
		base = Files.join(selfRoot, string.sub(request, 7))
	elseif string.sub(request, 1, 1) == "." then
		local parent = if Files.name(from) == "init.luau" then Files.parent(directory) else directory
		base = Files.collapse(Files.join(parent, request))
	else
		return nil
	end
	for _, candidate in { base, base .. ".luau", base .. "/init.luau" } do
		if Files.isFile(candidate) then
			return Files.collapse(candidate)
		end
	end
	return nil
end

local function closure(roots: { string }): ({ string }, { string })
	local seen: { [string]: boolean } = {}
	local order: { string } = {}
	local missing: { string } = {}
	local queue = table.clone(roots)
	while #queue > 0 do
		local file = table.remove(queue, 1) :: string
		if seen[file] or file == "tools/facet/commands/init.luau" then
			continue
		end
		seen[file] = true
		table.insert(order, file)
		local source = Files.read(file)
		for request in string.gmatch(source, 'require%(%s*"([^"]+)"%s*%)') do
			if string.sub(request, 1, 1) == "@" and string.sub(request, 1, 6) ~= "@self/" then
				continue
			end
			local found = resolve(file, request)
			if found == nil then
				table.insert(missing, ("%s requires %s"):format(file, request))
			elseif not seen[found] then
				table.insert(queue, found)
			end
		end
	end
	table.sort(order)
	return order, missing
end

local function commandsInit(names: { string }): string
	local lines = { "--!strict", "", 'local Cli = require("./lib/cli")', "", "local commands: { Cli.Command } = {" }
	for _, name in names do
		table.insert(lines, ('\trequire("@self/%s"),'):format(name))
	end
	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, "return table.freeze(commands)")
	return table.concat(lines, "\n") .. "\n"
end

local function definitions(plan: Plan)
	local lock = Json.decode(Files.read(DEFINITIONS_LOCK))
	local digest = Json.stringField(lock, "sha256")
	if not Files.isFile(DEFINITIONS_CACHE) or Hash.sha256(Files.read(DEFINITIONS_CACHE)) ~= digest then
		table.insert(plan.problems, "the Roblox definitions are not cached; run lute run tools/facet types once")
		return
	end
	plan.copies["tools/typecheck/roblox.d.luau"] = DEFINITIONS_CACHE
	plan.copies["tools/typecheck/roblox.lock.json"] = DEFINITIONS_LOCK
end

local function plan(): Plan
	local result: Plan = { copies = {}, writes = {}, problems = {} }
	tree(result, "src", "Packages/Facet", function(relative: string): boolean
		return string.find(relative, "%.verify%.luau$") == nil
	end)
	tree(result, "docs/reference", "docs/reference")
	tree(result, "examples/themes", "examples/themes")
	tree(result, "docs/guide", "docs/guide", DocsIndex.consumerGuide)
	if Files.isDirectory("examples/blocks") then
		tree(result, "examples/blocks", "examples/blocks")
		for _, file in Files.walk("examples/blocks") do
			if Files.extension(file) == ".luau" then
				local target = Files.join("examples/blocks", file)
				local source = Files.read(target)
				source = string.gsub(
					source,
					'require%("../../src"%)',
					'require(game:GetService("ReplicatedStorage").Packages.Facet)'
				)
				result.copies[target] = nil
				result.writes[target] = source
			end
		end
	end
	local roots: { string } = { "tools/facet/init.luau", "tools/play/engine/probe.luau" }
	local present: { string } = {}
	for _, name in AUTHOR_COMMANDS do
		local path = ("tools/facet/commands/%s.luau"):format(name)
		if Files.isFile(path) then
			table.insert(roots, path)
			table.insert(present, name)
		else
			table.insert(result.problems, path .. " is missing")
		end
	end
	local files, missing = closure(roots)
	for _, problem in missing do
		table.insert(result.problems, problem)
	end
	for _, file in files do
		if string.sub(file, 1, 20) ~= "tools/vendor/verify/" and string.sub(file, 1, 4) ~= "src/" then
			result.copies[file] = file
		end
	end
	result.writes["tools/facet/commands/init.luau"] = commandsInit(present)
	result.writes["tools/facet/README.md"] = [[# Facet author tools

Start with `lute run tools/facet docs` for the map. Open one task recipe,
then a card or option node only for a missing detail. Do not reread a node.
Use `lute run tools/facet project [directory]` to find application files.
These commands need neither rg nor a Git checkout.
Run `lute run tools/facet verify --tap TEXT...` for types, lint, build,
audit and screenshot paths. Use `--static` when Studio is unavailable.
]]
	local head = Run.capture({ "git", "rev-parse", "HEAD" })
	local status = Run.capture({ "git", "status", "--porcelain", "--untracked-files=no" })
	local stamp: json.Value = {
		commit = if head.ok then (string.gsub(head.stdout, "%s+$", "")) else "unknown",
		changed = not status.ok or status.stdout ~= "",
	}
	result.writes["tools/facet/kit.json"] = json.serialize(stamp, true) .. "\n"
	if Files.isDirectory("tools/play") then
		tree(result, "tools/play", "tools/play")
	end
	tree(result, "tools/vendor/verify/src", "tools/vendor/verify/src")
	result.copies["tools/vendor/verify/LICENSE"] = "tools/vendor/verify/LICENSE"
	definitions(result)
	result.copies[".agents/skills/use-facet/SKILL.md"] = "skills/use-facet/SKILL.md"
	tree(result, "skills/compose", ".agents/skills/compose")
	return result
end

local function write(out: string, chosen: Plan, force: boolean): (boolean, { string })
	if #chosen.problems > 0 then
		return false, chosen.problems
	end
	local present: { string } = {}
	for _, owned in OWNED do
		if Files.exists(Files.join(out, owned)) then
			table.insert(present, owned)
		end
	end
	if #present > 0 and not force then
		return false, { "the kit paths exist in " .. out .. ": " .. table.concat(present, ", ") .. "; give --force" }
	end
	for _, owned in present do
		Files.remove(Files.join(out, owned))
	end
	local count = 0
	for target, source in chosen.copies do
		Files.copy(source, Files.join(out, target))
		count += 1
	end
	for target, contents in chosen.writes do
		Files.write(Files.join(out, target), contents)
		count += 1
	end
	return true, { ("facet kit: wrote %d file(s) into %s"):format(count, out) }
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "out", "force" })
	local out = Cli.flag(invocation, "out")
	if unknown ~= nil or out == nil or #invocation.positional > 0 then
		if unknown ~= nil then
			print("facet kit: unknown flags " .. unknown)
		end
		print(USAGE)
		return 2
	end
	local chosen = plan()
	local ok, lines = write(out :: string, chosen, Cli.switch(invocation, "force"))
	local value: json.Value = { ok = ok, lines = lines }
	Cli.emit(invocation, value, table.concat(lines, "\n"))
	return if ok then 0 else 1
end

local function cases(): { Case.Case }
	return {
		{
			name = "the plan holds the library, the author commands and their libraries, and no maintainer command",
			run = function()
				local chosen = plan()
				local init = chosen.writes["tools/facet/commands/init.luau"]
				local block = chosen.writes["examples/blocks/item_store.luau"] or ""
				return Case.first(
					Case.expect(string.find(block, "@repo", 1, true) == nil, "a block needs private type aliases"),
					Case.expect(
						string.find(block, "FacetTypes.Use", 1, true) ~= nil,
						"the block has no public Use type"
					),
					Case.expect(
						chosen.copies["Packages/Facet/init.luau"] == "src/init.luau",
						"the library entry is missing"
					),
					Case.expect(chosen.copies["tools/facet/commands/docs.luau"] ~= nil, "the docs command is missing"),
					Case.expect(chosen.copies["tools/facet/lib/docs_index.luau"] ~= nil, "a command library is missing"),
					Case.expect(chosen.copies["docs/reference/nodes/Map.md"] ~= nil, "the documentation map is missing"),
					Case.expect(
						chosen.copies["tools/facet/lib/markdown.luau"] ~= nil,
						"the node link parser is missing"
					),
					Case.expect(
						chosen.copies["docs/reference/nodes/Sheet.detents.md"] ~= nil,
						"an option node is missing"
					),
					Case.expect(chosen.copies["docs/reference/nodes/Tasks.shop.md"] ~= nil, "a task recipe is missing"),
					Case.expect(
						chosen.copies["tools/facet/commands/gate.luau"] == nil,
						"a maintainer command leaked in"
					),
					Case.expect(string.find(init, '"@self/lint"', 1, true) ~= nil, "lint is not registered"),
					Case.expect(string.find(init, '"@self/gate"', 1, true) == nil, "gate is registered"),
					Case.expect(chosen.copies[".agents/skills/use-facet/SKILL.md"] ~= nil, "the skill is missing"),
					Case.expect(
						string.find(chosen.writes["tools/facet/kit.json"] or "", "commit", 1, true) ~= nil,
						"the kit has no source stamp"
					)
				)
			end,
		},
		{
			name = "a relative require from an init module resolves from its parent directory",
			run = function()
				return Case.first(
					Case.equal(
						resolve("tools/facet/commands/init.luau", "./lib/cli"),
						"tools/facet/lib/cli.luau",
						"init"
					),
					Case.equal(
						resolve("tools/facet/commands/docs.luau", "../lib/cli"),
						"tools/facet/lib/cli.luau",
						"leaf"
					),
					Case.equal(
						resolve("tools/facet/init.luau", "@self/commands"),
						"tools/facet/commands/init.luau",
						"self"
					)
				)
			end,
		},
		{
			name = "a written kit runs the author commands on its own and refuses a second write without --force",
			run = function()
				local out = Files.temporaryDirectory("facet-kit")
				local chosen = plan()
				chosen.problems = {}
				local ok, lines = write(out, chosen, false)
				if not ok then
					Files.remove(out)
					return "the kit was not written: " .. table.concat(lines, "; ")
				end
				local docs = Run.capture(
					{ Run.lute(), "run", "tools/facet", "docs", "Button" },
					{ cwd = out, timeout = 120 }
				)
				local help = Run.capture({ Run.lute(), "run", "tools/facet", "help" }, { cwd = out, timeout = 120 })
				local probeOk, probeProblem = pcall(function(): boolean
					Lute.place.build({
						output = Files.join(out, "probe.rbxlx"),
						roots = {},
						modules = { Files.join(out, "tools/play/engine/probe.luau") },
					})
					return true
				end)
				local again = write(out, plan(), false)
				Files.remove(out)
				return Case.first(
					Case.expect(docs.ok, "docs failed in the kit: " .. docs.stderr .. docs.stdout),
					Case.expect(probeOk, "the standalone kit cannot bundle its play probe: " .. tostring(probeProblem)),
					Case.expect(
						string.find(docs.stdout, "# Button.card", 1, true) ~= nil,
						"docs did not print the Button card"
					),
					Case.expect(string.find(help.stdout, "lint", 1, true) ~= nil, "help does not list lint"),
					Case.expect(string.find(help.stdout, "gate", 1, true) == nil, "help lists a maintainer command"),
					Case.expect(not again, "a second write replaced the kit without --force")
				)
			end,
		},
	}
end

local command: Cli.Command = {
	name = "kit",
	summary = "Write the Facet author kit (library, author commands, docs, skills) into a game project.",
	usage = USAGE,
	values = { "out" },
	cases = cases,
	run = run,
}

return command
