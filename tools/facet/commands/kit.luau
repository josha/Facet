--!strict
local Verify = require("../../vendor/verify/src/core")

local json = require("@std/json")
local Cli = require("../lib/cli")
local DocsIndex = require("../lib/docs_index")
local Props = require("../lib/docs_props")
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
  examples/themes/                optional theme source for adaptation
  tools/facet/                     the author commands: info, docs, lint, preview, audit and critique,
                                   and kit.json with the source commit of the kit
  tools/play/                      the Studio play host that preview and audit use
  tools/vendor/verify/             Verify (MIT), which the play host and audit use
  tools/typecheck/roblox.d.luau    the pinned Roblox definitions for lint --types
  .agents/skills/                  the use-facet, compose and critique-ui skills
  StudioDocs/                      the documentation and skill source as native StringValues

Map Packages to ReplicatedStorage.Packages in the Rojo project. For Studio-only
authoring, map StudioDocs to ServerStorage.FacetDocs. Its folders follow the
source paths; read a document's Value through Studio MCP in Edit mode.
The kit refuses
to replace a path that exists in DIR unless you give --force. The Roblox
definitions come from the cache that lute run tools/facet types writes.]]

local AUTHOR_COMMANDS = { "info", "docs", "project", "lint", "preview", "audit", "critique", "verify" }
local DEFINITIONS_LOCK = "tools/typecheck/roblox.lock.json"
local DEFINITIONS_CACHE = "artifacts/verify/types/roblox.d.luau"
local OWNED = {
	"StudioDocs",
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
	".agents/skills/critique-ui",
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
	local reviewTool = "tools/facet/lib/design_review.luau"
	if result.copies[reviewTool] ~= nil then
		result.copies[reviewTool] = nil
		result.writes[reviewTool] = (
			string.gsub(
				Files.text(reviewTool),
				'require%("%.%./%.%./%.%./src/ui/review_rules"%)',
				'require("../../../Packages/Facet/ui/review_rules")'
			)
		)
	end
	result.writes["tools/facet/commands/init.luau"] = commandsInit(present)
	result.writes["tools/facet/README.md"] = [[# Facet author tools

Start with `.agents/skills/use-facet/SKILL.md`. Choose one complete task and give
it the game's visual identity. Retrieve a card or option node only for a missing contract.
In Studio, read the same skill and example source under `ServerStorage.FacetDocs`.
Theme builders are optional references to adapt to the game's existing app.
Do not reread a node.
Use `lute run tools/facet project [directory]` to find application files.
These commands need neither rg nor a Git checkout.
Run `lute run tools/facet verify --tap TEXT...` for types, lint, build,
audit and screenshot paths. Use `--static` when Studio is unavailable.
Run `lute run tools/facet critique` with `.agents/skills/critique-ui/SKILL.md`
to have a fresh reviewer judge how a screen looks.
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
	tree(result, "skills/use-facet", ".agents/skills/use-facet")
	tree(result, "skills/compose", ".agents/skills/compose")
	tree(result, "skills/critique-ui", ".agents/skills/critique-ui")
	for _, source in result.copies do
		local extension = Files.extension(source)
		if
			(extension == ".md" and (string.sub(source, 1, 5) == "docs/" or string.sub(source, 1, 7) == "skills/"))
			or (
				extension == ".luau"
				and (
					string.sub(source, 1, #"skills/use-facet/") == "skills/use-facet/"
					or string.sub(source, 1, #"examples/themes/") == "examples/themes/"
				)
			)
		then
			result.writes[Files.join("StudioDocs", source .. ".txt")] = Files.text(source)
		end
	end
	for name, options in Props.load(".") do
		result.writes["StudioDocs/docs/reference/nodes/" .. name .. ".props.md.txt"] = Props.render(name, options)
	end
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

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(
		prefix .. "the plan holds the library, the author commands and their libraries, and no maintainer command",
		{
			id = prefix
				.. "the plan holds the library, the author commands and their libraries, and no maintainer command",
			run = function(test: Verify.Context)
				local chosen = plan()
				local init = chosen.writes["tools/facet/commands/init.luau"]
				local block = chosen.writes["examples/blocks/item_store.luau"] or ""
				Verify.expect(string.find(block, "@repo", 1, true) == nil)
					:toBeTrueWith("a block needs private type aliases")
				Verify.expect(string.find(block, "FacetTypes.Use", 1, true) ~= nil)
					:toBeTrueWith("the block has no public Use type")
				Verify.expect(chosen.copies["Packages/Facet/init.luau"] == "src/init.luau")
					:toBeTrueWith("the library entry is missing")
				Verify.expect(chosen.copies["tools/facet/commands/docs.luau"] ~= nil)
					:toBeTrueWith("the docs command is missing")
				Verify.expect(chosen.copies["tools/facet/lib/docs_index.luau"] ~= nil)
					:toBeTrueWith("a command library is missing")
				Verify.expect(chosen.copies["docs/reference/nodes/Map.md"] ~= nil)
					:toBeTrueWith("the documentation map is missing")
				Verify.expect(chosen.copies["tools/facet/lib/markdown.luau"] ~= nil)
					:toBeTrueWith("the node link parser is missing")
				Verify.expect(chosen.copies["docs/reference/nodes/Sheet.detents.md"] ~= nil)
					:toBeTrueWith("an option node is missing")
				Verify.expect(chosen.copies["docs/reference/nodes/Tasks.collection-detail.md"] ~= nil)
					:toBeTrueWith("a task recipe is missing")
				Verify.expect(chosen.copies["tools/facet/commands/gate.luau"] == nil)
					:toBeTrueWith("a maintainer command leaked in")
				Verify.expect(string.find(init, '"@self/lint"', 1, true) ~= nil):toBeTrueWith("lint is not registered")
				Verify.expect(string.find(init, '"@self/gate"', 1, true) == nil):toBeTrueWith("gate is registered")
				Verify.expect(chosen.copies[".agents/skills/use-facet/SKILL.md"] ~= nil)
					:toBeTrueWith("the skill is missing")
				Verify.expect(chosen.copies[".agents/skills/critique-ui/SKILL.md"] ~= nil)
					:toBeTrueWith("the critique-ui skill is missing")
				Verify.expect(chosen.writes["StudioDocs/skills/critique-ui/references/rubric.md.txt"] ~= nil)
					:toBeTrueWith("the rubric is missing from StudioDocs")
				Verify.expect(string.find(init, '"@self/critique"', 1, true) ~= nil)
					:toBeTrueWith("critique is not registered")
				Verify.expect(
					string.find(
						chosen.writes["tools/facet/lib/design_review.luau"] or "",
						"Packages/Facet/ui/review_rules",
						1,
						true
					) ~= nil
				):toBeTrueWith("the kit design review does not load the packaged rules")
				Verify.expect(string.find(chosen.writes["tools/facet/kit.json"] or "", "commit", 1, true) ~= nil)
					:toBeTrueWith("the kit has no source stamp")
			end,
		}
	)
	harness:case(prefix .. "a relative require from an init module resolves from its parent directory", {
		id = prefix .. "a relative require from an init module resolves from its parent directory",
		run = function(test: Verify.Context)
			Verify.expect(resolve("tools/facet/commands/init.luau", "./lib/cli")):toBe("tools/facet/lib/cli.luau")
			Verify.expect(resolve("tools/facet/commands/docs.luau", "../lib/cli")):toBe("tools/facet/lib/cli.luau")
			Verify.expect(resolve("tools/facet/init.luau", "@self/commands")):toBe("tools/facet/commands/init.luau")
		end,
	})
	harness:case(
		prefix .. "a written kit runs the author commands on its own and refuses a second write without --force",
		{
			id = prefix
				.. "a written kit runs the author commands on its own and refuses a second write without --force",
			run = function(test: Verify.Context)
				local out = Files.temporaryDirectory("facet-kit")
				test:defer(function()
					Files.remove(out)
				end)
				local chosen = plan()
				chosen.problems = {}
				local ok, lines = write(out, chosen, false)
				if not ok then
					Files.remove(out)
					error("the kit was not written: " .. table.concat(lines, "; "), 0)
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
				local missingReferences: { string } = {}
				Files.write(
					Files.join(out, "docs.project.json"),
					Json.pretty({
						name = "KitDocs",
						tree = {
							["$className"] = "DataModel",
							ServerStorage = { FacetDocs = { ["$path"] = "StudioDocs" } },
						},
					})
				)
				local docsBuild = Run.capture({
					"rojo",
					"build",
					Files.join(out, "docs.project.json"),
					"-o",
					Files.join(out, "docs.rbxlx"),
				})
				Verify.expect(docsBuild.ok):toBeTrueWith(docsBuild.stderr .. docsBuild.stdout)
				local installed = Lute.model.read(Files.read(Files.join(out, "docs.rbxlx")))
				for target, contents in chosen.writes do
					if string.sub(target, 1, #"StudioDocs/") == "StudioDocs/" then
						local path = "ServerStorage/FacetDocs/" .. string.sub(target, #"StudioDocs/" + 1, -5)
						local node = Lute.model.find(installed, path)
						if
							node == nil
							or node.className ~= "StringValue"
							or node.properties.Value.value ~= contents
						then
							table.insert(missingReferences, path)
						end
					end
				end
				for _, source in
					{
						"skills/use-facet/SKILL.md",
						"skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md",
						"docs/reference/nodes/Map.md",
						"docs/reference/nodes/Tasks.hud.md",
					}
				do
					local target = Files.join(out, "StudioDocs", source .. ".txt")
					if not Files.isFile(target) or Files.text(target) ~= Files.text(source) then
						table.insert(missingReferences, "StudioDocs/" .. source)
					end
				end
				for name, options in Props.load(".") do
					local target = Files.join(out, "StudioDocs/docs/reference/nodes/" .. name .. ".props.md.txt")
					if not Files.isFile(target) or Files.text(target) ~= Props.render(name, options) then
						table.insert(missingReferences, name .. ".props")
					end
				end
				local icons = Files.join(out, "StudioDocs/docs/reference/nodes/Icons.names.md.txt")
				if not Files.isFile(icons) or Files.text(icons) ~= Props.icons(".") then
					table.insert(missingReferences, "Icons.names")
				end
				for _, relative in Files.walk("skills/use-facet/references") do
					local source = Files.join("skills/use-facet/references", relative)
					local target = Files.join(out, ".agents/skills/use-facet/references", relative)
					if not Files.isFile(target) or Files.read(target) ~= Files.read(source) then
						table.insert(missingReferences, relative)
					end
				end
				for _, relative in Files.walk("skills/use-facet") do
					if Files.extension(relative) == ".md" or Files.extension(relative) == ".luau" then
						local source = Files.join("skills/use-facet", relative)
						local target = Files.join(out, "StudioDocs", source .. ".txt")
						if not Files.isFile(target) or Files.read(target) ~= Files.text(source) then
							table.insert(missingReferences, "StudioDocs/" .. source)
						end
					end
				end
				for _, relative in Files.walk("examples/themes") do
					if Files.extension(relative) == ".luau" then
						local source = Files.join("examples/themes", relative)
						local target = Files.join(out, "StudioDocs", source .. ".txt")
						if not Files.isFile(target) or Files.read(target) ~= Files.text(source) then
							table.insert(missingReferences, "StudioDocs/" .. source)
						end
					end
				end
				Files.remove(out)
				Verify.expect(#missingReferences == 0)
					:toBeTrueWith("skill references missing or changed: " .. table.concat(missingReferences, ", "))
				Verify.expect(docs.ok):toBeTrueWith("docs failed in the kit: " .. docs.stderr .. docs.stdout)
				Verify.expect(probeOk)
					:toBeTrueWith("the standalone kit cannot bundle its play probe: " .. tostring(probeProblem))
				Verify.expect(string.find(docs.stdout, "# Button.card", 1, true) ~= nil)
					:toBeTrueWith("docs did not print the Button card")
				Verify.expect(string.find(help.stdout, "lint", 1, true) ~= nil):toBeTrueWith("help does not list lint")
				Verify.expect(string.find(help.stdout, "gate", 1, true) == nil)
					:toBeTrueWith("help lists a maintainer command")
				Verify.expect(not again):toBeTrueWith("a second write replaced the kit without --force")
			end,
		}
	)
end

local command: Cli.Command = {
	name = "kit",
	summary = "Write the Facet author kit (library, author commands, docs, skills) into a game project.",
	usage = USAGE,
	values = { "out" },
	register = register,
	run = run,
}

return command
