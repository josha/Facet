--!strict

local Files = require("../lib/files")
local Luau = require("../lib/luau")
local Rule = require("../lib/rule")
local Run = require("../lib/run")

local EXTERNAL = { "@lune/", "@std/", "@lute/" }
local SCANNED = { "src", "examples", "bench" }
local PUBLIC = { "examples", "bench" }
local DEPENDENCY_ROOTS = { "src", "examples", "bench", "tests", "tools" }
local REMOVED_API: { [string]: boolean } = {
	["Facet.new"] = true,
	["Facet.createHost"] = true,
	["Facet.newPresenter"] = true,
	["Facet.newActionSystem"] = true,
	["Facet.newFocusGraph"] = true,
}
local REMOVED_FILES = {
	"src/client/application.luau",
	"src/render/compose_scene.luau",
	"src/render/renderer.luau",
	"src/core/services.luau",
}
local FORBIDDEN_DEPENDENCIES = {
	{ name = "Fusion", needle = "fusion", reason = "Fusion is retired; Compose is the only reactive runtime" },
}
local APPROVED_VENDORS: { [string]: boolean } = { ["src/vendor"] = true, ["tools/vendor"] = true }
local SKIPPED_DIRECTORIES: { [string]: boolean } = {
	[".git"] = true,
	[".claude"] = true,
	node_modules = true,
	__pycache__ = true,
	build = true,
	[".venv"] = true,
}

export type Resolution = "external" | "missing" | "resolved"

type Source = {
	parsed: Luau.Parsed?,
	problem: string?,
	text: string,
}

type Scan = {
	context: Rule.Context,
	sources: { [string]: Source },
	imports: { [string]: { string } },
	resolutions: { [string]: { resolution: Resolution, resolved: string? } },
}

local function source(scan: Scan, relative: string): Source
	local cached = scan.sources[relative]
	if cached ~= nil then
		return cached
	end
	local text = Files.text(scan.context.path(relative))
	local parsed, problem = Luau.parse(text)
	local entry: Source = { parsed = parsed, problem = problem, text = text }
	scan.sources[relative] = entry
	return entry
end

local function imports(scan: Scan, relative: string): { string }
	local cached = scan.imports[relative]
	if cached ~= nil then
		return cached
	end
	local entry = source(scan, relative)
	local found: { string } = {}
	if entry.parsed ~= nil then
		for _, request in Luau.requires(entry.parsed) do
			table.insert(found, (if request.dynamic then "dynamic:" else "") .. request.path)
		end
	end
	scan.imports[relative] = found
	return found
end

local function startsWith(value: string, prefix: string): boolean
	return string.sub(value, 1, #prefix) == prefix
end

local function isInit(relative: string): boolean
	return Files.name(relative) == "init.luau"
end

local function resolveUncached(scan: Scan, relative: string, requested: string): (Resolution, string?)
	local dynamic = startsWith(requested, "dynamic:")
	local target = if dynamic then string.sub(requested, 9) else requested
	for _, prefix in EXTERNAL do
		if startsWith(target, prefix) then
			return "external", nil
		end
	end
	local base: string
	if startsWith(target, "@self/") then
		local rest = string.sub(target, 7)
		local anchor = if isInit(relative) then Files.parent(relative) else string.gsub(relative, "%.luau?$", "")
		base = Files.collapse(anchor .. "/" .. rest)
	elseif startsWith(target, ".") then
		local directory = Files.parent(relative)
		local anchor = if isInit(relative) then Files.parent(directory) else directory
		base = Files.collapse(anchor .. "/" .. target)
	else
		return "missing", nil
	end
	local context = scan.context
	if dynamic then
		if Files.isDirectory(context.path(base)) then
			return "external", nil
		end
		local prefix = Files.name(base)
		for _, entry in Files.list(context.path(Files.parent(base))) do
			if startsWith(entry.name, prefix) and string.sub(entry.name, -5) == ".luau" then
				return "external", nil
			end
		end
	end
	if string.sub(target, -1) == "/" and Files.isDirectory(context.path(base)) then
		return "external", nil
	end
	for _, candidate in { base .. ".luau", base .. ".lua", base .. "/init.luau" } do
		if Files.isFile(context.path(candidate)) then
			return "resolved", Files.collapse(candidate)
		end
	end
	return "missing", nil
end

local function resolve(scan: Scan, relative: string, requested: string): (Resolution, string?)
	local key = relative .. "|" .. requested
	local cached = scan.resolutions[key]
	if cached == nil then
		local resolution: Resolution, resolved: string? = resolveUncached(scan, relative, requested)
		local entry: { resolution: Resolution, resolved: string? } = { resolution = resolution, resolved = resolved }
		scan.resolutions[key] = entry
		return resolution, resolved
	end
	return cached.resolution, cached.resolved
end

local function missingDependencies(
	scan: Scan,
	relative: string,
	visited: { [string]: boolean },
	missing: { [string]: boolean }
)
	if visited[relative] then
		return
	end
	visited[relative] = true
	local entry = source(scan, relative)
	if entry.parsed == nil then
		missing[("%s: cannot parse: %s"):format(relative, entry.problem or "")] = true
		return
	end
	for _, requested in imports(scan, relative) do
		local resolution, resolved = resolve(scan, relative, requested)
		if resolution == "missing" then
			missing[("%s: %s"):format(relative, requested)] = true
		elseif resolved ~= nil and string.find(resolved, "vendor/compose", 1, true) == nil then
			missingDependencies(scan, resolved, visited, missing)
		end
	end
end

local function luauFiles(context: Rule.Context, folder: string): { string }
	local found: { string } = {}
	for _, relative in Files.walk(context.path(folder)) do
		if string.sub(relative, -5) == ".luau" then
			table.insert(found, folder .. "/" .. relative)
		end
	end
	return found
end

local function vendored(relative: string): boolean
	for _, part in string.split(relative, "/") do
		if part == "vendor" then
			return true
		end
	end
	return false
end

local function constructorAlias(entry: Source): number?
	local parsed = entry.parsed
	if parsed == nil then
		return nil
	end
	local lines = Files.lines(entry.text)
	local found: number? = nil
	Luau.walk(parsed.root, function(node)
		if found == nil and Luau.kind(node) == "stat" and Luau.tag(node) == "local" then
			for _, variable in Luau.items(node, "variables") do
				if Luau.tokenText(variable, "name") == "H" then
					local line = Luau.line(node)
					local text = lines[line] or ""
					local after = string.match(text, "=(.*)$") or ""
					if string.find(after, "constructors", 1, true) ~= nil then
						found = line
					end
				end
			end
		end
		return found == nil
	end)
	return found
end

local function removedCalls(entry: Source): { number }
	local lines: { number } = {}
	if entry.parsed == nil then
		return lines
	end
	for _, call in Luau.calls(entry.parsed) do
		if call.callee ~= nil and REMOVED_API[call.callee] then
			table.insert(lines, call.line)
		end
	end
	return lines
end

local function forbiddenDependencies(entry: Source, relative: string, findings: { [string]: boolean })
	local parsed = entry.parsed
	if parsed == nil then
		return
	end
	for _, dependency in FORBIDDEN_DEPENDENCIES do
		for _, request in Luau.requires(parsed) do
			if string.find(string.lower(request.path), dependency.needle, 1, true) ~= nil then
				findings[("%s:%d: requires %s (%s)"):format(relative, request.line, request.path, dependency.reason)] =
					true
			end
		end
		Luau.walk(parsed.root, function(node)
			local tag = Luau.tag(node)
			local name = if Luau.kind(node) == "expr" and tag == "global"
				then Luau.tokenText(node, "name")
				elseif Luau.kind(node) == "local" then Luau.tokenText(node, "name")
				else nil
			if name == dependency.name then
				findings[("%s:%d: names %s (%s)"):format(relative, Luau.line(node), dependency.name, dependency.reason)] =
					true
			end
			return true
		end)
	end
end

local function trackedDirectories(context: Rule.Context): { string }?
	local listed = Run.git({ "ls-files", "-z", "--cached", "--others", "--exclude-standard" }, context.root)
	if not listed.ok or Run.gitOutput({ "rev-parse", "--show-prefix" }, context.root) ~= "" then
		return nil
	end
	local directories: { [string]: boolean } = {}
	for _, path in string.split(listed.stdout, string.char(0)) do
		local current = Files.normalize(path)
		while true do
			local parent = string.match(current, "^(.*)/[^/]*$")
			if parent == nil or parent == "" or directories[parent] then
				break
			end
			directories[parent] = true
			current = parent
		end
	end
	local sorted: { string } = {}
	for directory in directories do
		table.insert(sorted, directory)
	end
	table.sort(sorted)
	return sorted
end

local function vendorDirectories(context: Rule.Context): { string }
	local candidates = trackedDirectories(context)
		or Files.walk(context.root, {
			directories = true,
			skip = SKIPPED_DIRECTORIES,
			prune = function(path: string): boolean
				return path == "artifacts/verify/tmp"
			end,
		})
	local found: { string } = {}
	for _, relative in candidates do
		if Files.name(relative) == "vendor" and not APPROVED_VENDORS[relative] then
			local inside = false
			for approved in APPROVED_VENDORS do
				if Files.within(relative, approved) then
					inside = true
				end
			end
			if not inside then
				table.insert(found, relative)
			end
		end
	end
	return found
end

local function check(context: Rule.Context): { string }
	local scan: Scan = { context = context, sources = {}, imports = {}, resolutions = {} }
	local failures: { [string]: boolean } = {}
	for _, folder in SCANNED do
		for _, relative in luauFiles(context, folder) do
			if string.find(relative, "vendor/compose", 1, true) ~= nil then
				continue
			end
			local missing: { [string]: boolean } = {}
			missingDependencies(scan, relative, {}, missing)
			for finding in missing do
				failures[finding] = true
			end
			local entry = source(scan, relative)
			if #removedCalls(entry) > 0 then
				failures[relative .. ": removed Facet scaffolding API"] = true
			end
			if constructorAlias(entry) ~= nil then
				failures[relative .. ": use Host for Roblox constructors"] = true
			end
		end
	end
	for _, folder in PUBLIC do
		for _, relative in luauFiles(context, folder) do
			for _, requested in imports(scan, relative) do
				local resolution, resolved = resolve(scan, relative, requested)
				if
					resolution == "resolved"
					and resolved ~= nil
					and startsWith(resolved, "src/")
					and resolved ~= "src/init.luau"
				then
					failures[("%s: requires private Facet module %s"):format(relative, resolved)] = true
				end
			end
		end
	end
	for _, entry in Files.list(context.path("src/vendor")) do
		if entry.name ~= "compose" then
			failures[("src/vendor/%s: unapproved vendor"):format(entry.name)] = true
		end
	end
	for _, removed in REMOVED_FILES do
		if Files.exists(context.path(removed)) then
			failures[removed .. ": removed architecture still exists"] = true
		end
	end
	for _, folder in DEPENDENCY_ROOTS do
		for _, relative in luauFiles(context, folder) do
			if not vendored(relative) then
				forbiddenDependencies(source(scan, relative), relative, failures)
			end
		end
	end
	for _, directory in vendorDirectories(context) do
		failures[directory .. ": unexpected vendor directory"] = true
	end
	local sorted: { string } = {}
	for finding in failures do
		table.insert(sorted, finding)
	end
	table.sort(sorted)
	return sorted
end

local BASE: { [string]: string } = {
	["tests/.keep"] = "",
	["src/ui/.keep"] = "",
	["examples/.keep"] = "",
	["bench/.keep"] = "",
	["tools/lune/.keep"] = "",
}

local function tree(files: { [string]: string }): { [string]: string }
	local merged = table.clone(BASE)
	for path, contents in files do
		merged[path] = contents
	end
	return merged
end

local function dependencies(context: Rule.Context, relative: string): { string }
	local missing: { [string]: boolean } = {}
	missingDependencies({ context = context, sources = {}, imports = {}, resolutions = {} }, relative, {}, missing)
	local sorted: { string } = {}
	for finding in missing do
		table.insert(sorted, finding)
	end
	table.sort(sorted)
	return sorted
end

local function importList(context: Rule.Context, relative: string): string
	return table.concat(imports({ context = context, sources = {}, imports = {}, resolutions = {} }, relative), ", ")
end

local function cases(): { Rule.Case }
	return {
		{
			name = "init self aliases resolve and a missing import is rejected",
			run = function()
				return Rule.within(
					tree({
						["src/init.luau"] = 'return require("@self/ui")',
						["src/ui/init.luau"] = 'return require("@self/control")',
						["src/ui/control.luau"] = "return {}",
					}),
					function(context)
						if #dependencies(context, "src/init.luau") ~= 0 then
							return "clean imports: " .. Rule.describe(dependencies(context, "src/init.luau"))
						end
						Files.write(context.path("src/ui/control.luau"), 'return require("./gone")')
						return Rule.expect(
							Rule.contains(dependencies(context, "src/init.luau"), "./gone"),
							"the missing import was not reported"
						)
					end
				)
			end,
		},
		{
			name = "a dynamic data prefix that exists passes and a missing prefix fails",
			run = function()
				return Rule.within(
					tree({
						["tests/data.spec.luau"] = 'return require("../examples/words/len" .. tostring(5))',
						["examples/words/len5.luau"] = "return {}",
					}),
					function(context)
						if #dependencies(context, "tests/data.spec.luau") ~= 0 then
							return "an existing prefix failed"
						end
						Files.write(
							context.path("tests/data.spec.luau"),
							'return require("../examples/missing/len" .. tostring(5))'
						)
						return Rule.expect(
							#dependencies(context, "tests/data.spec.luau") > 0,
							"a missing prefix passed"
						)
					end
				)
			end,
		},
		{
			name = "require text in comments and literals is not a dependency",
			run = function()
				return Rule.within(
					tree({
						["tests/probe.spec.luau"] = table.concat({
							'-- require("./removed")',
							"local example = 'require(\"./removed\")'",
							'local text = `example require("./removed"): {require("./actual")}`',
							'return require("./actual")',
						}, "\n"),
						["tests/actual.luau"] = "return {}",
					}),
					function(context)
						local listed = importList(context, "tests/probe.spec.luau")
						if listed ~= "./actual, ./actual" then
							return "imports: " .. listed
						end
						return Rule.expect(
							#dependencies(context, "tests/probe.spec.luau") == 0,
							"a literal was resolved"
						)
					end
				)
			end,
		},
		{
			name = "typeof type imports are erased and runtime imports stay checked",
			run = function()
				return Rule.within(
					tree({
						["tests/probe.spec.luau"] = table.concat({
							'type Props = typeof(require("@repo/missing")("("))',
							'local value: typeof(require("./missing")) = nil :: never',
							'local text = "typeof(require(\\"./missing\\"))"',
							'local runtimeKind = typeof(require("./actual"))',
							'return typeof(require("./actual"))',
						}, "\n"),
						["tests/actual.luau"] = "return {}",
					}),
					function(context)
						local listed = importList(context, "tests/probe.spec.luau")
						if listed ~= "./actual, ./actual" then
							return "imports: " .. listed
						end
						if #dependencies(context, "tests/probe.spec.luau") ~= 0 then
							return "an erased type import was checked"
						end
						Files.write(context.path("tests/probe.spec.luau"), 'return require("@repo/missing")')
						return Rule.expect(
							#dependencies(context, "tests/probe.spec.luau") > 0,
							"a runtime alias passed"
						)
					end
				)
			end,
		},
		{
			name = "a typed require alias keeps dynamic dependency checks",
			run = function()
				return Rule.within(
					tree({
						["tests/probe.spec.luau"] = 'local requireDynamic = require :: (unknown) -> unknown\nreturn requireDynamic("../examples/words/len" .. tostring(5))',
						["examples/words/len5.luau"] = "return {}",
					}),
					function(context)
						local listed = importList(context, "tests/probe.spec.luau")
						if listed ~= "dynamic:../examples/words/len" then
							return "imports: " .. listed
						end
						if #dependencies(context, "tests/probe.spec.luau") ~= 0 then
							return "an existing dynamic prefix failed"
						end
						Files.write(
							context.path("tests/probe.spec.luau"),
							'local load = require :: (unknown) -> unknown; return load("./missing")'
						)
						return Rule.expect(
							#dependencies(context, "tests/probe.spec.luau") > 0,
							"a missing alias import passed"
						)
					end
				)
			end,
		},
		{
			name = "examples cannot import private modules and extra vendors are rejected",
			run = function()
				return Rule.within(
					tree({
						["src/ui/private.luau"] = "return {}",
						["examples/screen.luau"] = 'return require("../src/ui/private")',
						["src/vendor/other/init.luau"] = "return {}",
					}),
					function(context)
						local findings = check(context)
						if not Rule.contains(findings, "private Facet module") then
							return "the private import passed: " .. Rule.describe(findings)
						end
						return Rule.expect(Rule.contains(findings, "unapproved vendor"), Rule.describe(findings))
					end
				)
			end,
		},
		{
			name = "the old API and the abandoned renderer are rejected",
			run = function()
				return Rule.within(
					tree({
						["src/render/renderer.luau"] = "return {}",
						["examples/screen.luau"] = "local app = Facet.new()",
					}),
					function(context)
						local findings = check(context)
						if not Rule.contains(findings, "renderer.luau") then
							return "the renderer passed: " .. Rule.describe(findings)
						end
						return Rule.expect(
							Rule.contains(findings, "removed Facet scaffolding API"),
							Rule.describe(findings)
						)
					end
				)
			end,
		},
		{
			name = "a short constructor alias is rejected and Host passes",
			run = function()
				return Rule.within(
					tree({
						["examples/bad.luau"] = "local H = runtime.constructors\nreturn H",
						["examples/good.luau"] = "local Host = runtime.constructors\nreturn Host",
					}),
					function(context)
						local findings = check(context)
						if not Rule.contains(findings, "examples/bad.luau: use Host") then
							return "the short alias passed: " .. Rule.describe(findings)
						end
						return Rule.expect(not Rule.contains(findings, "examples/good.luau"), Rule.describe(findings))
					end
				)
			end,
		},
		{
			name = "a Fusion dependency is forbidden and the word confusion is not",
			run = function()
				return Rule.within(
					tree({
						["tests/vendored.luau"] = 'local F = require("../../vendor/Fusion")\nreturn F',
						["tools/lune/shim.luau"] = 'local shim = require("../lib/fusion_shim")\nreturn shim',
						["examples/value.luau"] = "local value = Fusion.Value(0)\nreturn value",
						["examples/clean.luau"] = '-- the confusion this fixture does not report\nlocal text = "Fusion"\nreturn text',
					}),
					function(context)
						local findings = check(context)
						for _, expected in
							{
								"tests/vendored.luau:1: requires ../../vendor/Fusion",
								"tools/lune/shim.luau:1: requires ../lib/fusion_shim",
								"examples/value.luau:1: names Fusion",
							}
						do
							if not Rule.contains(findings, expected) then
								return "missing " .. expected .. ": " .. Rule.describe(findings)
							end
						end
						return Rule.expect(not Rule.contains(findings, "examples/clean.luau:"), Rule.describe(findings))
					end
				)
			end,
		},
		{
			name = "a vendor directory is found by name outside the approved pins",
			run = function()
				return Rule.within(
					tree({
						["nested/vendor/x.luau"] = "return {}",
						["artifacts/verify/tmp/case/src/vendor/x.luau"] = "return {}",
						["artifacts/shipped/vendor/x.luau"] = "return {}",
						["tools/vendor/verify/x.luau"] = "return {}",
					}),
					function(context)
						local findings = check(context)
						if
							not Rule.contains(findings, "nested/vendor: unexpected")
							or not Rule.contains(findings, "artifacts/shipped/vendor: unexpected")
						then
							return Rule.describe(findings)
						end
						return Rule.expect(
							not Rule.contains(findings, "artifacts/verify/tmp")
								and not Rule.contains(findings, "tools/vendor:"),
							Rule.describe(findings)
						)
					end
				)
			end,
		},
		{
			name = "an unparsable source is a finding",
			run = function()
				return Rule.within(tree({ ["src/broken.luau"] = "local x = 'unfinished" }), function(context)
					return Rule.expect(Rule.contains(check(context), "src/broken.luau: cannot parse"), "parsed")
				end)
			end,
		},
	}
end

local rule: Rule.Rule = {
	name = "architecture",
	summary = "Imports resolve, examples use only the public root, and no removed API, renderer, Fusion or extra vendor exists.",
	check = check,
	cases = cases,
}

return rule
