--!strict

local stringext = require("@std/stringext")
local luau = require("@lute/luau")
local net = require("@std/net")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local time = require("@std/time")
local Analyzer = require("../lib/analyzer")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Generator = require("../lib/engine_generator")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Run = require("../lib/run")

local USAGE = [[usage: lute run tools/facet types [--solver old|new|both] [--flag KEY=VALUE]... [--source-only]
       lute run tools/facet types [--solver ...] --files FILE [FILE...]
       lute run tools/facet types selftest [--solver old|new|both]
       lute run tools/facet types engine [--check] [--definitions PATH] [--creator-docs PATH]
       lute run tools/facet types --selftest

The complete check type checks every tracked and untracked Luau file that Git does not
ignore, in each Rojo project context, in the Designer plugin context and in the Lute
context (tools/facet, tests/tools, tools/lute and the vendored Verify Lute runtime). It
requires strict directives, zero blocking diagnostics and the rejection of every public
negative probe. Every selected solver must pass.

--files checks only the named targets and records dependency diagnostics separately.
--source-only checks Facet-owned source without the public probes.
selftest runs the checker cases, then proves that the analyzer accepts a native UDim2
and a Lute standard library type and rejects an incompatible scalar in each context.
engine checks or regenerates src/ui/engine_types.luau from the pinned declarations
and tools/typecheck/engine_members.json; --creator-docs refreshes that metadata.
--selftest runs only the checker cases.]]

local ARTIFACTS = "artifacts/verify/types"
local LOCK = "tools/typecheck/roblox.lock.json"
local PLUGIN_LOCK = "tools/typecheck/roblox-plugin.lock.json"
local DEFAULT_FLAGS = { "LuauTarjanChildLimit=100000" }
local SOLVER_FLAGS: { [string]: { string } } = { old = {}, new = { "LuauSolverV2=true" } }
local ANALYZER_TIMEOUT = 600
local ARGUMENT_BUDGET = if system.win32 then 24000 else 1000000
local INVENTORY = { "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.luau" }
local PROJECTS = { "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*project.json" }

type Context = {
	run: Analyzer.Run,
	classified: Analyzer.Classified,
	log: string,
}

type Options = {
	solver: string,
	files: { string }?,
	flags: { string },
	sourceOnly: boolean,
}

type Probes = {
	count: number,
	missed: { string },
	unexpected: { Analyzer.Diagnostic },
	log: string,
}

type Report = {
	ok: boolean,
	owned: { Analyzer.Diagnostic },
	external: { Analyzer.Diagnostic },
	document: Json.Object,
}

type LuteTypes = { version: string, pin: string, typedefs: string }

local function fail(message: string): never
	error(message, 0)
end

local function home(): string
	return Files.normalize(path.format(process.homedir()))
end

local function decodeFile(file: string): Json.Object
	local value, problem = Json.tryDecode(Files.read(file))
	local object = Json.asObject(value)
	if problem ~= nil or object == nil then
		fail(("%s is not a JSON object: %s"):format(file, problem or "wrong shape"))
	end
	return object :: Json.Object
end

local function record(fields: { { string | unknown } }): Json.Object
	local object = Json.object()
	for _, pair in fields do
		Json.set(object, pair[1] :: string, if pair[2] == nil then Json.null else pair[2])
	end
	return object
end

local function encodeDiagnostic(diagnostic: Analyzer.Diagnostic): Json.Object
	return record({
		{ "file", diagnostic.file },
		{ "line", diagnostic.line },
		{ "column", diagnostic.column },
		{ "kind", diagnostic.kind },
		{ "message", diagnostic.message },
	})
end

local function encodeDiagnostics(list: { Analyzer.Diagnostic }): Json.Array
	local encoded = Json.array()
	for _, diagnostic in list do
		table.insert(encoded, encodeDiagnostic(diagnostic))
	end
	return encoded
end

local function flagsFor(solver: string, overrides: { string }): { string }
	local flags = table.clone(DEFAULT_FLAGS)
	table.move(SOLVER_FLAGS[solver], 1, #SOLVER_FLAGS[solver], #flags + 1, flags)
	table.move(overrides, 1, #overrides, #flags + 1, flags)
	return flags
end

local function isNewSolver(flags: { string }): boolean
	return table.find(flags, "LuauSolverV2=true") ~= nil
end

local function suffix(flags: { string }): string
	return if isNewSolver(flags) then "-v2" else ""
end

local function uniqueName(prefix: string): string
	return ("%s%d_%d"):format(prefix, process.pid(), math.random(1, 1000000000))
end

local function repositoryFiles(): { string }
	local listed = Run.git(INVENTORY)
	if not listed.ok then
		fail("git ls-files failed: " .. stringext.trim(listed.stderr))
	end
	return Analyzer.inventory(listed.stdout, Files.isFile)
end

local function scratchDirectory(): string
	local directory = Files.join(ARTIFACTS, uniqueName("setup-"))
	Files.makeDirectory(directory)
	return directory
end

local function lutePin(rokit: string): (string?, string?)
	local pin = string.match(rokit, '\nlute%s*=%s*"[^"@]*@([^"]+)"')
	if pin == nil then
		return nil, nil
	end
	return pin, string.match(pin, "^(%d+%.%d+%.%d+)")
end

local function matchesLutePin(version: string, pin: string, base: string): boolean
	return version == pin or version == base
end

local function aliasProblem(luaurc: unknown, base: string): string?
	local aliases = Json.objectField(luaurc, "aliases")
	for _, alias in { "std", "lute" } do
		local value = Json.stringField(aliases, alias)
		local expected = ("/.lute/typedefs/%s/%s"):format(base, alias)
		if value == nil or string.sub(Files.normalize(value), -#expected) ~= expected then
			return (".luaurc aliases @%s to %s; expected ~%s"):format(alias, tostring(value), expected)
		end
	end
	return nil
end

local function prepareLuteTypes(): LuteTypes
	local pin, base = lutePin(Files.text("rokit.toml"))
	if pin == nil or base == nil then
		fail("rokit.toml does not pin lute")
	end
	local reported = Run.capture({ Run.lute(), "--version" })
	local version = stringext.trim(reported.stdout)
	if not reported.ok or not matchesLutePin(version, pin :: string, base :: string) then
		fail(("Lute %s differs from the rokit.toml pin %s; run rokit install"):format(version, tostring(pin)))
	end
	local problem = aliasProblem(Json.decode(Files.read(".luaurc")), base :: string)
	if problem ~= nil then
		fail(problem)
	end
	local scratch = scratchDirectory()
	local setup = Run.capture({ Run.lute(), "setup" }, { cwd = scratch, timeout = 120 })
	Files.remove(scratch)
	if not setup.ok then
		fail("lute setup failed: " .. stringext.trim(setup.stdout .. setup.stderr))
	end
	local typedefs = Files.join(home(), ".lute/typedefs", base :: string)
	for _, library in { "std", "lute" } do
		if not Files.isDirectory(Files.join(typedefs, library)) then
			fail(("lute setup did not write %s/%s"):format(typedefs, library))
		end
	end
	return { version = version, pin = pin :: string, typedefs = "~/.lute/typedefs/" .. (base :: string) }
end

local function definitions(lockFile: string): string
	local lock = decodeFile(lockFile)
	local digest = Json.stringField(lock, "sha256") or fail(lockFile .. " has no sha256")
	local url = Json.stringField(lock, "url") or fail(lockFile .. " has no url")
	local file = Files.join(ARTIFACTS, if lockFile == PLUGIN_LOCK then "roblox-plugin.d.luau" else "roblox.d.luau")
	if Files.isFile(file) and Hash.sha256(Files.read(file)) == digest then
		return file
	end
	local fetched, response = pcall(function(): net.Response
		return net.request(url)
	end)
	if not fetched then
		fail(("could not download the Roblox definitions from %s: %s"):format(url, tostring(response)))
	end
	local answer = response :: net.Response
	if not answer.ok then
		fail(("could not download the Roblox definitions from %s: HTTP %d"):format(url, answer.status))
	end
	if Hash.sha256(answer.body) ~= digest then
		fail("Roblox definitions differ from their pinned SHA-256")
	end
	Files.write(file, answer.body)
	return file
end

local function analyze(
	files: { string },
	name: string,
	extra: { string },
	platform: Analyzer.Platform,
	lockFile: string,
	flags: { string }
): ({ Analyzer.Diagnostic }, string)
	local base: { string } = { "luau-lsp", "analyze" }
	if platform == "roblox" then
		table.insert(base, "--platform")
		table.insert(base, "roblox")
		table.insert(base, "--definitions=" .. definitions(lockFile))
	else
		table.insert(base, "--platform=standard")
		table.insert(base, "--base-luaurc=.luaurc")
	end
	table.move(extra, 1, #extra, #base + 1, base)
	for _, flag in flags do
		table.insert(base, "--flag:" .. flag)
	end
	local fixed = 0
	for _, argument in base do
		fixed += #argument + 3
	end
	local log = Files.join(ARTIFACTS, name .. suffix(flags) .. ".log")
	local outputs: { string } = {}
	local diagnostics: { Analyzer.Diagnostic } = {}
	local root = Files.cwd()
	for _, chunk in Analyzer.chunks(files, ARGUMENT_BUDGET - fixed) do
		local argv = table.clone(base)
		table.move(chunk, 1, #chunk, #argv + 1, argv)
		local result = Run.capture(argv, { timeout = ANALYZER_TIMEOUT })
		local output = string.gsub(result.stdout .. result.stderr, "\r\n", "\n")
		table.insert(outputs, output)
		local found = Analyzer.parse(output, root)
		if result.timedOut then
			Files.write(log, table.concat(outputs))
			fail(("Analyzer timed out after %ds; see %s"):format(ANALYZER_TIMEOUT, log))
		end
		if (result.code ~= 0 and result.code ~= 1) or (result.code ~= 0 and #found == 0) then
			Files.write(log, table.concat(outputs))
			fail(
				("Analyzer failed without usable diagnostics (exit code %d, %d targets); see %s"):format(
					result.code,
					#chunk,
					log
				)
			)
		end
		table.move(found, 1, #found, #diagnostics + 1, diagnostics)
	end
	Files.write(log, table.concat(outputs))
	return Analyzer.dedupe(diagnostics), log
end

local function projects(): { Analyzer.Project }
	local listed = Run.git(PROJECTS)
	if not listed.ok then
		fail("git ls-files failed: " .. stringext.trim(listed.stderr))
	end
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, project in string.split(listed.stdout, "\0") do
		if project ~= "" and not seen[project] then
			seen[project] = true
			table.insert(names, project)
		end
	end
	table.sort(names)
	local root = Files.cwd()
	local list: { Analyzer.Project } = {}
	for _, project in names do
		local name = "project-" .. string.sub(Hash.sha256(project), 1, 12)
		local sourcemap = Files.join(ARTIFACTS, name .. ".sourcemap.json")
		local built = Run.capture({ "rojo", "sourcemap", project, "--absolute", "-o", sourcemap }, { timeout = 300 })
		if not built.ok then
			fail(("rojo sourcemap %s failed: %s"):format(project, stringext.trim(built.stderr)))
		end
		local mapped: { string } = {}
		local verbatim = false
		local function visit(node: unknown)
			local filePaths: Json.Array = Json.arrayField(node, "filePaths") or {}
			for index, file in filePaths do
				if type(file) ~= "string" then
					continue
				end
				local plain = Analyzer.withoutVerbatimPrefix(file)
				if plain ~= file then
					filePaths[index] = plain
					verbatim = true
				end
				if string.sub(plain, -5) == ".luau" then
					table.insert(mapped, Analyzer.relative(plain, root))
				end
			end
			local children: Json.Array = Json.arrayField(node, "children") or {}
			for _, child in children do
				visit(child)
			end
		end
		local tree = Json.decode(Files.read(sourcemap))
		visit(tree)
		if verbatim then
			Files.write(sourcemap, Json.encode(tree))
		end
		table.insert(list, { project = project, name = name, sourcemap = sourcemap, mapped = mapped })
	end
	return list
end

local function luteRun(files: { string }): Analyzer.Run
	return {
		targets = files,
		name = "lute",
		extra = {},
		platform = "standard",
		plugin = false,
		project = nil,
	}
end

local NEGATIVE_PROBES: { { string } } = {
	{ "Button label", "UI.Button({ label = 42 })" },
	{ "Button native size", 'UI.Button({ label = "Save", Size = "large" })' },
	{ "Button native visibility", 'UI.Button({ label = "Save", Visible = "yes" })' },
	{ "Button nullable label", "UI.Button({ label = nullableText })" },
	{ "Button callback", 'UI.Button({ label = "Save", onActivate = "save" })' },
	{ "Button size rung", 'UI.Button({ label = "Save", controlSize = "tiny" })' },
	{ "Button native return", 'local wrong: number = UI.Button({ label = "Save" })' },
	{ "Toggle cell value", 'UI.Toggle({ value = Facet.Compose.cell("on") })' },
	{
		"Toggle callback value",
		"UI.Toggle({ value = Facet.Compose.cell(false), onChange = function(value: string) end })",
	},
	{ "TextInput cell value", "UI.TextInput({ value = Facet.Compose.cell(42) })" },
	{
		"TextInput callback value",
		'UI.TextInput({ value = Facet.Compose.cell(""), onChange = function(value: number) end })',
	},
	{ "Slider cell value", 'UI.Slider({ value = Facet.Compose.cell("loud") })' },
	{
		"Slider callback value",
		"UI.Slider({ value = Facet.Compose.cell(0.5), onChange = function(value: string) end })",
	},
	{ "Stepper numeric maximum", 'UI.Stepper({ value = Facet.Compose.cell(1), max = "ten" })' },
	{ "Progress numeric value", 'UI.ProgressView({ value = "half" })' },
	{ "Badge label", "UI.Badge({ label = false })" },
	{ "Avatar presence", 'UI.Avatar({ name = "Alder", presence = "unknown" })' },
	{ "Status status", 'UI.StatusIndicator({ status = "busy" })' },
	{ "Sheet writable presentation", 'UI.Sheet({ isPresented = "yes", detent = Facet.Compose.cell("large") })' },
	{ "Radial native hold action", 'UI.RadialMenu({ items = {}, holdAction = "Interact" })' },
	{
		"Radial selected value",
		'UI.RadialMenu({ items = {{id="choice", label="Choice", selected=Facet.Compose.cell("a"), value=42}} })',
	},
	{
		"Radial selected callback",
		'UI.RadialMenu({ items = {{id="choice", label="Choice", selected=Facet.Compose.cell("a"), value="a", onChange=function(value: number) end}} })',
	},
	{
		"Radial checked callback",
		'UI.RadialMenu({ items = {{id="choice", label="Choice", checked=Facet.Compose.cell(false), onChange=function(value: string) end}} })',
	},
	{ "Radial geometry", 'UI.RadialMenu({ items={}, preset="triangle" })' },
	{ "Slider controlled callback", "UI.Slider({value=0.5})" },
	{ "Toggle controlled callback", "UI.Toggle({value=Facet.Compose.formula(function() return false end)})" },
	{ "TextInput numeric model", 'UI.TextInput({value=Facet.Compose.cell("1"),presentation="number"})' },
	{ "TextInput controlled callback", 'UI.TextInput({value=Facet.Compose.formula(function() return "" end)})' },
	{ "NumberInput numeric model", 'UI.NumberInput({value=Facet.Compose.cell("1")})' },
	{ "Civil date parse", 'local civilDay: number = Facet.civilDate.parse("09/03/2026")' },
	{ "Shortcut neither source", "UI.ShortcutHint({})" },
	{ "Shortcut both sources", 'UI.ShortcutHint({keys={{"Ctrl","K"}},action=Instance.new("InputAction")})' },
	{ "Progress presentation", 'UI.ProgressView({presentation="pie"})' },
	{ "Image resource value", 'UI.AsyncImage({resource=function() return {value=12,state="ready"} end})' },
	{ "Image loader source", "UI.AsyncImage({loader=function(source:number) end})" },
	{ "Stage world model", "UI.Stage({content=function(runtime:Facet.Runtime, world:Frame) end})" },
	{ "Theme numeric metric", 'Facet.themes.define({metrics={controlSizes={regular={height="tall"}}}})' },
	{ "VStack spacing type", "UI.VStack({ gap = true })" },
	{ "HStack padding side", "UI.HStack({ padding = { left = true } })" },
	{ "VStack padding side name", "UI.VStack({ padding = { start = 4 } })" },
	{ "HStack align", 'UI.HStack({ align = "middle" })' },
	{ "VStack distribute", 'UI.VStack({ distribute = "around" })' },
	{ "VStack maximum width", 'UI.VStack({ maxWidth = "fill" })' },
	{ "VStack width", 'UI.VStack({ width = "stretch" })' },
	{ "VStack native size", "UI.VStack({ Size = 42 })" },
	{ "Screen gap", "UI.Screen({ gap = false })" },
	{ "ZStack alignment", 'UI.ZStack({ alignH = "stretch" })' },
	{ "ScrollView axis", 'UI.ScrollView({ axis = "z" })' },
	{ "ScrollView native canvas", "UI.ScrollView({ CanvasSize = 3 })" },
	{ "ScrollView native return", "local wrong: Frame = UI.ScrollView({})" },
	{ "Grid columns required", 'UI.Grid({ gap = "s" })' },
	{ "Grid columns type", 'UI.Grid({ columns = "two" })' },
	{ "Grid alignment", 'UI.Grid({ columns = 2, align = "stretch" })' },
	{ "Fill weight", 'UI.fill("wide")' },
	{ "Fill return", "local wrong: Frame = UI.fill()" },
	{ "Unknown control", "UI.ThisControlDoesNotExist({})" },
	{ "App parent", "Facet.app({ parent = 42 })" },
	{ "App theme", 'Facet.app({ theme = "dark" })' },
	{ "App component", "Facet.app().mount(42)" },
	{
		"App mount return",
		'local wrong: number = Facet.app().mount(function() return UI.Label({ text = "Hi" }) end)',
	},
	{ "App screen property", 'Facet.app({ screen = { DisplayOrder = "top" } })' },
	{ "App sheet option", 'Facet.app({ sheet = { transition = "slow" } })' },
	{ "App dispose argument", "local wrong: string = Facet.app().dispose()" },
}

local PROBE_HEADER = {
	"--!strict",
	'local Facet = require("../../src")',
	"local runtime = Facet.Roblox.createRuntime()",
	"local UI = Facet.controls(runtime)",
	"local nullableText: Facet.Cell<string?> = Facet.Compose.cell(nil :: string?)",
}

local function probeSource(names: { string }): (string, { [number]: string }, number)
	local probes: { { string } } = {}
	for _, name in names do
		if string.match(name, "^%u") ~= nil then
			table.insert(probes, { name .. ": table required", ("UI.%s(42)"):format(name) })
		end
	end
	for _, probe in NEGATIVE_PROBES do
		table.insert(probes, probe)
	end
	local named: { { string } } = {}
	for _, probe in probes do
		local label, code = probe[1], probe[2]
		if
			string.find(code, "({", 1, true) ~= nil
			and string.find(code, "UI.", 1, true) ~= nil
			and string.sub(label, 1, 7) ~= "Unknown"
		then
			table.insert(named, { label .. " named", Analyzer.named(code) })
		end
	end
	table.move(named, 1, #named, #probes + 1, probes)
	local lines = table.clone(PROBE_HEADER)
	local expected: { [number]: string } = {}
	local count = 0
	for _, probe in probes do
		table.insert(lines, probe[2])
		expected[#lines] = probe[1]
		count += 1
	end
	return table.concat(lines, "\n") .. "\n", expected, count
end

local function publicSource(): string
	local parts: { string } = {}
	for _, entry in Files.list("src/ui") do
		if entry.type == "file" and string.sub(entry.name, -5) == ".luau" then
			table.insert(parts, Files.text(Files.join("src/ui", entry.name)))
		end
	end
	return table.concat(parts, "\n")
end

local function withProbe<T>(file: string, contents: string, body: () -> T): T
	Files.write(file, contents)
	local ok, result = pcall(body)
	Files.remove(file)
	if not ok then
		error(result, 0)
	end
	return result
end

local function negativeProbes(flags: { string }): Probes
	local source, expected, count = probeSource(Analyzer.publicNames(publicSource()))
	local file = Files.join("tests/types", uniqueName("_negative_") .. ".luau")
	return withProbe(file, source, function(): Probes
		local diagnostics, log = analyze({ file }, "negative", {}, "roblox", LOCK, flags)
		local rejected: { [number]: boolean } = {}
		local unexpected: { Analyzer.Diagnostic } = {}
		for _, diagnostic in diagnostics do
			if diagnostic.file == file then
				rejected[diagnostic.line] = true
				if expected[diagnostic.line] == nil then
					table.insert(unexpected, diagnostic)
				end
			end
		end
		local lines: { number } = {}
		for line in expected do
			table.insert(lines, line)
		end
		table.sort(lines)
		local missed: { string } = {}
		for _, line in lines do
			if not rejected[line] then
				table.insert(missed, expected[line])
			end
		end
		return { count = count, missed = missed, unexpected = unexpected, log = log }
	end)
end

local function encodeProbes(probes: Probes?): unknown
	if probes == nil then
		return Json.null
	end
	return record({
		{ "count", probes.count },
		{ "missed", Json.array(probes.missed) },
		{ "unexpected", encodeDiagnostics(probes.unexpected) },
		{ "log", probes.log },
	})
end

local function modeOf(options: Options): string
	return if options.files ~= nil then "focused" elseif options.sourceOnly then "owned-source" else "full"
end

local function assemble(
	options: Options,
	targets: { string },
	flags: { string },
	missingStrict: { string },
	contexts: { Context },
	probes: Probes?,
	locks: { [string]: unknown }
): Report
	local classified: { Analyzer.Classified } = {}
	local encodedContexts = Json.array()
	for _, context in contexts do
		table.insert(classified, context.classified)
		local security: unknown = Json.null
		if context.run.platform == "roblox" then
			local lock = locks[if context.run.plugin then "plugin" else "game"]
			security = Json.field(lock, "security")
		end
		table.insert(
			encodedContexts,
			record({
				{ "project", context.run.project },
				{ "platform", context.run.platform },
				{ "security", security },
				{ "targets", Json.array(context.run.targets) },
				{ "log", context.log },
			})
		)
	end
	local merged = Analyzer.merge(classified)
	local ok = #merged.owned == 0
		and #missingStrict == 0
		and (probes == nil or (#probes.missed == 0 and #probes.unexpected == 0))
	local document = record({
		{ "ok", ok },
		{ "solver", options.solver },
		{ "mode", modeOf(options) },
		{ "targets", Json.array(targets) },
		{ "flags", Json.array(flags) },
		{ "missingStrict", Json.array(missingStrict) },
		{ "diagnostics", encodeDiagnostics(merged.owned) },
		{ "dependencyDiagnostics", encodeDiagnostics(merged.external) },
		{ "publicProbes", encodeProbes(probes) },
		{ "contexts", encodedContexts },
		{ "definitions", locks.game },
		{ "pluginDefinitions", locks.plugin },
		{ "luteDefinitions", locks.lute },
	})
	return { ok = ok, owned = merged.owned, external = merged.external, document = document }
end

local function normalizeTargets(files: { string }): { string }
	local root = Files.cwd()
	local list: { string } = {}
	for _, file in files do
		table.insert(list, Analyzer.relative(file, root))
	end
	return list
end

local function selectTargets(options: Options): { string }
	local files: { string } = if options.files ~= nil then normalizeTargets(options.files) else repositoryFiles()
	if options.sourceOnly then
		local owned: { string } = {}
		for _, file in files do
			if Analyzer.isOwnedSource(file) then
				table.insert(owned, file)
			end
		end
		files = owned
	end
	return files
end

local function loadLocks(lute: LuteTypes?): { [string]: unknown }
	return {
		game = decodeFile(LOCK),
		plugin = decodeFile(PLUGIN_LOCK),
		lute = if lute ~= nil
			then record({ { "version", lute.version }, { "pin", lute.pin }, { "typedefs", lute.typedefs } })
			else Json.null,
	}
end

local function check(
	options: Options,
	targets: { string },
	projectList: { Analyzer.Project }?,
	lute: LuteTypes?
): boolean
	local flags = flagsFor(options.solver, options.flags)
	local public = options.files == nil and not options.sourceOnly
	local missing: { string } = {}
	for _, file in targets do
		if not Files.isFile(file) then
			table.insert(missing, file)
		end
	end
	if #missing > 0 then
		fail("Missing type targets: " .. table.concat(missing, ", "))
	end
	local missingStrict: { string } = {}
	for _, file in targets do
		if Analyzer.missingStrict(Files.read(file)) then
			table.insert(missingStrict, file)
		end
	end
	local name = if options.files ~= nil
		then "focused-" .. string.sub(
			Hash.sha256(table.concat(flags, "\n") .. "\n" .. table.concat(targets, "\n")),
			1,
			10
		)
		elseif options.sourceOnly then "source"
		else "repository"
	local started = time.now()
	local roblox, luteFiles = Analyzer.partition(targets)
	local runs: { Analyzer.Run } = if projectList ~= nil
		then Analyzer.plan(roblox, projectList)
		else {
			{
				targets = roblox,
				name = name,
				extra = {},
				platform = "roblox",
				plugin = false,
				project = nil,
			},
		}
	if #luteFiles > 0 then
		table.insert(runs, luteRun(luteFiles))
	end
	local targetSet: { [string]: boolean } = {}
	for _, file in targets do
		targetSet[file] = true
	end
	local contexts: { Context } = {}
	for _, run in runs do
		if #run.targets == 0 then
			continue
		end
		local diagnostics, log =
			analyze(run.targets, run.name, run.extra, run.platform, if run.plugin then PLUGIN_LOCK else LOCK, flags)
		table.insert(contexts, {
			run = run,
			classified = Analyzer.classify(run, diagnostics, public, targetSet),
			log = log,
		})
	end
	local probes = if public then negativeProbes(flags) else nil
	local report = assemble(options, targets, flags, missingStrict, contexts, probes, loadLocks(lute))
	local reportPath = Files.join(ARTIFACTS, name .. suffix(flags) .. ".json")
	Files.write(reportPath, Json.pretty(report.document))
	print(
		("types (%s solver): %s; %d targets, %d blocking diagnostics, %d dependency diagnostics; %.1fs analyzer wall time"):format(
			options.solver,
			if report.ok then "PASS" else "FAIL",
			#targets,
			#report.owned,
			#report.external,
			time.since(started)
		)
	)
	for index = 1, math.min(#report.owned, 35) do
		local diagnostic = report.owned[index]
		print(
			("%s:%d:%d: %s"):format(
				diagnostic.file,
				diagnostic.line,
				diagnostic.column,
				Analyzer.truncate(diagnostic.message, 320)
			)
		)
	end
	for _, file in missingStrict do
		print("missing strict directive: " .. file)
	end
	if probes ~= nil then
		print(("public negative probes: %d/%d rejected"):format(probes.count - #probes.missed, probes.count))
		for _, label in probes.missed do
			print("missed: " .. label)
		end
		for _, diagnostic in probes.unexpected do
			print("probe setup error: " .. Analyzer.truncate(diagnostic.message, 320))
		end
	end
	print(("report: %s; %d analysis contexts; raw logs are listed in the report"):format(reportPath, #contexts))
	return report.ok
end

local function compileLute(files: { string }): { string }
	local problems: { string } = {}
	for _, file in files do
		local ok, problem = pcall(function()
			luau.load(luau.compile(Files.read(file)), file)
		end)
		if not ok then
			table.insert(problems, ("%s: %s"):format(file, tostring(problem)))
		end
	end
	return problems
end

local function compile(files: { string })
	local roblox, luteFiles = Analyzer.partition(files)
	local outputs: { string } = {}
	local failed = false
	local luteProblems = compileLute(roblox)
	for _, problem in compileLute(luteFiles) do
		table.insert(luteProblems, problem)
	end
	if #luteProblems > 0 then
		table.insert(outputs, table.concat(luteProblems, "\n") .. "\n")
		failed = true
	end
	local log = Files.join(ARTIFACTS, "syntax.log")
	Files.write(log, table.concat(outputs))
	if failed then
		fail(("Pinned runtime compilation failed; see %s"):format(log))
	end
end

local function engineCheck(definitionsPath: string): (boolean, string)
	local source = Files.text(definitionsPath)
	local schema = Generator.schema(Json.decode(Files.read(Generator.SCHEMA)))
	local text = Generator.generate(source, schema)
	local formatted = Generator.format(text, Files.join(ARTIFACTS, uniqueName("engine_types_") .. ".luau"))
	return Files.text(Generator.OUTPUT) == formatted, formatted
end

local function engine(invocation: Cli.Invocation): number
	local definitionsPath = Cli.flag(invocation, "definitions") or definitions(LOCK)
	local creatorDocs = Cli.flag(invocation, "creator-docs")
	if creatorDocs ~= nil then
		local closure = Generator.closure(Generator.records(Files.text(definitionsPath)), Generator.CLASSES)
		Files.write(Generator.SCHEMA, Json.pretty(Generator.metadata(creatorDocs, closure)))
	end
	local matches, formatted = engineCheck(definitionsPath)
	if Cli.switch(invocation, "check") then
		if not matches then
			print("engine_types.luau differs; run lute run tools/facet types engine")
			return 1
		end
		print("native engine types match pinned declarations and writable metadata")
		return 0
	end
	Files.write(Generator.OUTPUT, formatted)
	print(("wrote %s"):format(Generator.OUTPUT))
	return 0
end

local function analyzerVersion()
	local reported = Run.capture({ "luau-lsp", "--version" })
	if not reported.ok then
		fail("Pinned luau-lsp is missing; run rokit install")
	end
	local expected = Json.stringField(decodeFile(LOCK), "analyzerVersion")
	if stringext.trim(reported.stdout) ~= expected then
		fail(
			("Analyzer %s differs from the pinned toolchain; run rokit install"):format(stringext.trim(reported.stdout))
		)
	end
end

local function probeContext(
	file: string,
	contents: string,
	name: string,
	platform: Analyzer.Platform,
	flags: { string },
	line: number
): (boolean, string)
	local outcome = withProbe(file, contents, function(): { ok: boolean, log: string }
		local diagnostics, log = analyze({ file }, name, {}, platform, LOCK, flags)
		local own: { Analyzer.Diagnostic } = {}
		for _, diagnostic in diagnostics do
			if diagnostic.file == file then
				table.insert(own, diagnostic)
			end
		end
		return { ok = #own == 1 and own[1].line == line, log = log }
	end)
	return outcome.ok, outcome.log
end

local function liveSelftest(flags: { string }): number
	local solver = if isNewSolver(flags) then "new" else "old"
	local robloxOk, robloxLog = probeContext(
		Files.join("tests/types", uniqueName("_checker_") .. ".luau"),
		"--!strict\nlocal valid: UDim2 = UDim2.fromOffset(24, 24)\nlocal invalid: string = 42\nreturn valid, invalid\n",
		"selftest",
		"roblox",
		flags,
		3
	)
	print(
		("types selftest (%s solver): %s; valid native type accepted, wrong scalar rejected; %s"):format(
			solver,
			if robloxOk then "PASS" else "FAIL",
			robloxLog
		)
	)
	local luteOk, luteLog = probeContext(
		Files.join(ARTIFACTS, uniqueName("_checker_lute_") .. ".luau"),
		'--!strict\nlocal process = require("@std/process")\nlocal valid: { string } = process.args\nlocal invalid: string = 42\nreturn valid, invalid\n',
		"selftest-lute",
		"standard",
		flags,
		4
	)
	print(
		("types selftest lute (%s solver): %s; Lute standard library type accepted, wrong scalar rejected; %s"):format(
			solver,
			if luteOk then "PASS" else "FAIL",
			luteLog
		)
	)
	return if robloxOk and luteOk then 0 else 1
end

local cases: () -> { Case.Case }

local function parseOptions(invocation: Cli.Invocation, offset: number): (Options?, string?)
	local solver: string = Cli.flag(invocation, "solver") or "old"
	if solver ~= "old" and solver ~= "new" and solver ~= "both" then
		return nil, ("unknown solver '%s'"):format(solver)
	end
	local files: { string } = {}
	local given: { string } = invocation.repeated.files or {}
	for _, file in given do
		table.insert(files, file)
	end
	for index = offset, #invocation.positional do
		table.insert(files, invocation.positional[index])
	end
	if Cli.switch(invocation, "files") and #files == 0 then
		return nil, "--files needs at least one file"
	end
	local overrides: { string } = invocation.repeated.flag or {}
	local options: Options = {
		solver = solver :: string,
		files = if #files > 0 then files else nil,
		flags = table.clone(overrides),
		sourceOnly = Cli.switch(invocation, "source-only"),
	}
	return options, nil
end

local function solversOf(options: Options): { string }
	return if options.solver == "both" then { "old", "new" } else { options.solver }
end

local function selftest(options: Options): number
	local code = Case.report("types", cases)
	if code ~= 0 then
		return code
	end
	analyzerVersion()
	prepareLuteTypes()
	for _, solver in solversOf(options) do
		code = math.max(code, liveSelftest(flagsFor(solver, options.flags)))
	end
	return code
end

local function full(options: Options): number
	analyzerVersion()
	if options.files == nil then
		local matches = engineCheck(definitions(LOCK))
		if not matches then
			fail(
				"Native engine type generation differs: engine_types.luau differs; run lute run tools/facet types engine"
			)
		end
	end
	local targets = selectTargets(options)
	compile(targets)
	local _, luteFiles = Analyzer.partition(targets)
	local lute = if #luteFiles > 0 then prepareLuteTypes() else nil
	local projectList = if options.sourceOnly then nil else projects()
	local passed = true
	for _, solver in solversOf(options) do
		local selected = table.clone(options)
		selected.solver = solver
		if not check(selected, targets, projectList, lute) then
			passed = false
		end
	end
	return if passed then 0 else 1
end

local KNOWN = { "solver", "files", "flag", "source-only", "selftest", "check", "definitions", "creator-docs" }

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, KNOWN)
	if unknown ~= nil then
		print(("facet types: unknown option %s\n\n%s"):format(unknown, USAGE))
		return 2
	end
	local subcommand = invocation.positional[1]
	Files.makeDirectory(ARTIFACTS)
	local ok, code = pcall(function(): number
		if subcommand == "engine" then
			return engine(invocation)
		end
		local offset = if subcommand == "selftest" then 2 else 1
		local options, problem = parseOptions(invocation, offset)
		if options == nil then
			print(("facet types: %s\n\n%s"):format(problem or "invalid options", USAGE))
			return 2
		end
		if subcommand == "selftest" or Cli.switch(invocation, "selftest") then
			if options.files ~= nil then
				print(("facet types: selftest takes no files\n\n%s"):format(USAGE))
				return 2
			end
			return selftest(options)
		end
		return full(options)
	end)
	if not ok then
		print(("types: FAIL; %s"):format(tostring(code)))
		return 1
	end
	return code :: number
end

local function diagnostic(file: string, line: number?): Analyzer.Diagnostic
	return { file = file, line = line or 2, column = 1, kind = "TypeError", message = "wrong value" }
end

local FIXTURE_FILES = {
	"src/a.luau",
	"src/vendor/dependency.luau",
	"tests/a.luau",
	"examples/a.luau",
	"bench/a.luau",
	"tools/designer/a.luau",
}

local FIXTURE_LOCKS: { [string]: unknown } = {
	game = record({ { "security", "None" } }),
	plugin = record({ { "security", "PluginSecurity" } }),
	lute = Json.null,
}

local function robloxRun(targets: { string }): Analyzer.Run
	return { targets = targets, name = "all", extra = {}, platform = "roblox", plugin = false, project = nil }
end

local function fixtureReport(
	diagnostics: { Analyzer.Diagnostic },
	files: { string }?,
	solver: string?,
	missingStrict: { string }?
): Report
	local options: Options = { solver = solver or "old", files = files, flags = {}, sourceOnly = false }
	local targets: { string } = files or FIXTURE_FILES
	local targetSet: { [string]: boolean } = {}
	for _, file in targets do
		targetSet[file] = true
	end
	local run = robloxRun(FIXTURE_FILES)
	local public = files == nil
	local context: Context = {
		run = run,
		classified = Analyzer.classify(run, diagnostics, public, targetSet),
		log = "all.log",
	}
	local probes: Probes? = if public then { count = 1, missed = {}, unexpected = {}, log = "negative.log" } else nil
	return assemble(
		options,
		targets,
		flagsFor(options.solver, {}),
		missingStrict or {},
		{ context },
		probes,
		FIXTURE_LOCKS
	)
end

local function fileList(diagnostics: { Analyzer.Diagnostic }): { string }
	local list: { string } = {}
	for _, item in diagnostics do
		table.insert(list, ("%s:%d"):format(item.file, item.line))
	end
	return list
end

cases = function(): { Case.Case }
	return {
		{
			name = "inventory includes each repository area and untracked files",
			run = function(): string?
				local existing: { [string]: boolean } = {}
				for _, file in FIXTURE_FILES do
					existing[file] = true
				end
				existing["examples/new.luau"] = true
				local listing = table.concat(FIXTURE_FILES, "\0")
					.. "\0examples/new.luau\0src/deleted.luau\0src/a.luau\0"
				local expected = table.clone(FIXTURE_FILES)
				table.insert(expected, "examples/new.luau")
				table.sort(expected)
				return Case.first(
					Case.same(
						Analyzer.inventory(listing, function(file: string): boolean
							return existing[file] == true
						end),
						expected,
						"inventory"
					),
					Case.expect(table.find(INVENTORY, "--others") ~= nil, "the inventory omits untracked files"),
					Case.expect(table.find(INVENTORY, "--cached") ~= nil, "the inventory omits tracked files")
				)
			end,
		},
		{
			name = "complete check blocks dependency errors",
			run = function(): string?
				local report = fixtureReport({ diagnostic("src/vendor/dependency.luau") })
				return Case.first(
					Case.equal(report.ok, false, "ok"),
					Case.same(fileList(report.owned), { "src/vendor/dependency.luau:2" }, "diagnostics"),
					Case.same(fileList(report.external), {}, "dependency diagnostics"),
					Case.same(Json.strings(report.document.targets) or {}, FIXTURE_FILES, "targets"),
					Case.equal(Json.field(report.document, "mode"), "full", "mode")
				)
			end,
		},
		{
			name = "analyzer report keeps the type mismatch details",
			run = function(): string?
				local output =
					"tests/a.luau(2,1): TypeError: Expected this to be\n\t'string'\nbut got\n\t'number'\ntests/a.luau(3,1): SyntaxError: missing end\n"
				local diagnostics = Analyzer.parse(output, "/repo")
				return Case.first(
					Case.equal(#diagnostics, 2, "count"),
					Case.expect(
						diagnostics[1] ~= nil
							and string.find(diagnostics[1].message, "but got\n\t'number'", 1, true) ~= nil,
						"the first message lost its detail"
					),
					Case.equal(diagnostics[2] and diagnostics[2].message, "missing end", "second message"),
					Case.equal(diagnostics[1] and diagnostics[1].file, "tests/a.luau", "file")
				)
			end,
		},
		{
			name = "focused check records dependencies separately",
			run = function(): string?
				local report = fixtureReport({ diagnostic("src/vendor/dependency.luau") }, { "src/a.luau" })
				return Case.first(
					Case.equal(report.ok, true, "ok"),
					Case.same(fileList(report.external), { "src/vendor/dependency.luau:2" }, "dependency diagnostics"),
					Case.equal(Json.field(report.document, "mode"), "focused", "mode"),
					Case.equal(Json.isNull(report.document.publicProbes), true, "focused runs have no probes")
				)
			end,
		},
		{
			name = "strict cannot be disabled later in a file",
			run = function(): string?
				local report = fixtureReport({}, nil, nil, { "bench/a.luau" })
				return Case.first(
					Case.equal(Analyzer.missingStrict("--!strict\n--!nocheck\nreturn {}\n"), true, "nocheck"),
					Case.equal(Analyzer.missingStrict("--!strict\n--!nonstrict\nreturn {}\n"), true, "nonstrict"),
					Case.equal(Analyzer.missingStrict("--!nonstrict\nreturn {}\n"), true, "first line"),
					Case.equal(Analyzer.missingStrict("--!strict\r\nreturn {}\r\n"), false, "CRLF"),
					Case.equal(Analyzer.missingStrict("--!strict\n--!nocheckers\nreturn {}\n"), false, "word boundary"),
					Case.equal(Analyzer.missingStrict("--!strict"), true, "no newline"),
					Case.equal(report.ok, false, "ok"),
					Case.same(Json.strings(report.document.missingStrict) or {}, { "bench/a.luau" }, "missingStrict")
				)
			end,
		},
		{
			name = "new solver has no diagnostic allowance",
			run = function(): string?
				local report = fixtureReport({ diagnostic("tests/a.luau") }, nil, "new")
				return Case.first(
					Case.equal(report.ok, false, "ok"),
					Case.same(Json.strings(report.document.flags) or {}, {
						"LuauTarjanChildLimit=100000",
						"LuauSolverV2=true",
					}, "flags")
				)
			end,
		},
		{
			name = "projects cover mapped and unmapped files in both security contexts",
			run = function(): string?
				local runs = Analyzer.plan(FIXTURE_FILES, {
					{
						project = "default.project.json",
						name = "project-abc",
						sourcemap = "artifacts/verify/types/project-abc.sourcemap.json",
						mapped = { "src/a.luau", "tools/designer/a.luau", "elsewhere/b.luau" },
					},
				})
				local covered: { string } = {}
				local contexts: { string } = {}
				for _, planned in runs do
					table.move(planned.targets, 1, #planned.targets, #covered + 1, covered)
					table.insert(
						contexts,
						("%s/%s"):format(tostring(planned.project), if planned.plugin then "plugin" else "game")
					)
				end
				table.sort(covered)
				local expected = table.clone(FIXTURE_FILES)
				table.sort(expected)
				return Case.first(
					Case.same(covered, expected, "covered"),
					Case.same(
						contexts,
						{ "default.project.json/game", "default.project.json/plugin", "nil/game" },
						"contexts"
					),
					Case.equal(
						runs[1] and runs[1].extra[1],
						"--sourcemap=artifacts/verify/types/project-abc.sourcemap.json"
					)
				)
			end,
		},
		{
			name = "Lute runtime files are analyzed in their own context",
			run = function(): string?
				local roblox, lute = Analyzer.partition({
					"src/a.luau",
					"tools/facet/init.luau",
					"tests/lute/worker.luau",
					"tests/a.verify.luau",
					"tools/lute/studio_live.luau",
					"bench/perf_runner.luau",
					"tools/vendor/verify/src/lute/host.luau",
					"tools/vendor/verify/src/core/init.luau",
					"tools/vendor/verify/tools/studio-worker.luau",
				})
				return Case.first(
					Case.same(roblox, {
						"src/a.luau",
						"tests/a.verify.luau",
						"bench/perf_runner.luau",
						"tools/vendor/verify/src/core/init.luau",
					}, "roblox"),
					Case.same(lute, {
						"tools/facet/init.luau",
						"tests/lute/worker.luau",
						"tools/lute/studio_live.luau",
						"tools/vendor/verify/src/lute/host.luau",
						"tools/vendor/verify/tools/studio-worker.luau",
					}, "lute")
				)
			end,
		},
		{
			name = "the Lute context blocks only first-party diagnostics",
			run = function(): string?
				local lute = luteRun({ "tools/facet/init.luau", "tools/vendor/verify/src/lute/host.luau" })
				local diagnostics = {
					diagnostic("tools/facet/init.luau"),
					diagnostic("tools/vendor/verify/src/lute/host.luau"),
					diagnostic("tools/vendor/verify/src/core/execution.luau"),
					diagnostic("C:/Users/someone/.lute/typedefs/1.0.1/std/path/win32/init.luau"),
					diagnostic("/home/runner/.lute/typedefs/1.0.1/lute/time.luau"),
				}
				local public = Analyzer.classify(lute, diagnostics, true, {})
				local focused =
					Analyzer.classify(lute, diagnostics, false, { ["tools/vendor/verify/src/lute/host.luau"] = true })
				local robloxPublic = Analyzer.classify(robloxRun({}), {
					diagnostic("src/vendor/x.luau"),
					diagnostic("C:/Users/someone/.lute/typedefs/1.0.1/std/path/win32/init.luau"),
				}, true, {})
				return Case.first(
					Case.same(fileList(public.owned), { "tools/facet/init.luau:2" }, "public owned"),
					Case.equal(#public.external, 4, "public external"),
					Case.same(fileList(focused.owned), { "tools/vendor/verify/src/lute/host.luau:2" }, "focused owned"),
					Case.equal(#robloxPublic.owned, 1, "the Roblox contexts keep the complete policy"),
					Case.equal(#robloxPublic.external, 1, "the Roblox contexts do not block the Lute declarations")
				)
			end,
		},
		{
			name = "a diagnostic owned in one context is not also a dependency diagnostic",
			run = function(): string?
				local shared = diagnostic("tools/vendor/verify/src/core/execution.luau")
				local merged = Analyzer.merge({
					{ owned = {}, external = { shared, diagnostic("C:/x.luau") } },
					{ owned = { shared, shared }, external = {} },
				})
				return Case.first(
					Case.same(fileList(merged.owned), { "tools/vendor/verify/src/core/execution.luau:2" }, "owned"),
					Case.same(fileList(merged.external), { "C:/x.luau:2" }, "external")
				)
			end,
		},
		{
			name = "analyzer paths normalize to repository-relative forward slashes",
			run = function(): string?
				local root = "C:/git/Facet/worktree"
				return Case.first(
					Case.equal(
						Analyzer.relative("tools\\facet\\init.luau", root),
						"tools/facet/init.luau",
						"backslashes"
					),
					Case.equal(
						Analyzer.relative("c:\\git\\Facet\\worktree\\src\\a.luau", root),
						"src/a.luau",
						"drive case"
					),
					Case.equal(
						Analyzer.relative("\\\\?\\C:\\git\\Facet\\worktree\\src\\a.luau", root),
						"src/a.luau",
						"verbatim"
					),
					Case.equal(
						Analyzer.relative("../../../Users/bacon/.lute/typedefs/1.0.1/std/fs.luau", root),
						"C:/Users/bacon/.lute/typedefs/1.0.1/std/fs.luau",
						"outside"
					),
					Case.equal(Analyzer.relative("/repo/src/a.luau", "/repo"), "src/a.luau", "posix"),
					Case.equal(
						Analyzer.relative("/Repo/src/a.luau", "/repo"),
						"/Repo/src/a.luau",
						"posix is case sensitive"
					),
					Case.equal(
						Analyzer.withoutVerbatimPrefix("\\\\?\\C:\\repo\\src\\init.luau"),
						"C:\\repo\\src\\init.luau",
						"rojo verbatim path"
					),
					Case.equal(
						Analyzer.withoutVerbatimPrefix("/repo/src/init.luau"),
						"/repo/src/init.luau",
						"posix path"
					),
					Case.equal(Analyzer.isFirstParty("C:/Users/bacon/x.luau"), false, "absolute"),
					Case.equal(Analyzer.isFirstParty("tools/facet/x.luau"), true, "first party")
				)
			end,
		},
		{
			name = "analyzer output with CRLF, log lines, project labels and lint kinds parses",
			run = function(): string?
				local output = table.concat({
					"[WARN] No definitions file provided by client",
					"tools/facet/a.luau(4,2): TypeError: Expected this to be",
					"\t'string'",
					"[INFO] Loading Luau configuration from c:\\repo\\.luaurc",
					"but got 'number'",
					"src/b.luau [game](7,3): SyntaxError: Expected identifier",
					"src/c.luau(1,1): LocalUnused: Variable 'x' is never used",
					"\tdetail",
					"src/d.lua(9,9): TypeError: legacy extension",
					"src/d.lua(9,9): TypeError: legacy extension",
					"",
				}, "\r\n")
				local diagnostics = Analyzer.parse(output, "/repo")
				return Case.first(
					Case.same(fileList(diagnostics), { "tools/facet/a.luau:4", "src/b.luau:7", "src/d.lua:9" }, "files"),
					Case.equal(
						diagnostics[1] and diagnostics[1].message,
						"Expected this to be\n\t'string'\nbut got 'number'",
						"message"
					),
					Case.equal(diagnostics[2] and diagnostics[2].kind, "SyntaxError", "kind"),
					Case.equal(diagnostics[2] and diagnostics[2].column, 3, "column")
				)
			end,
		},
		{
			name = "long target lists split under the argument budget",
			run = function(): string?
				local chunks = Analyzer.chunks({ "aaaa", "bbbb", "cccc", "dddd", "e" }, 15)
				local shapes: { string } = {}
				for _, chunk in chunks do
					table.insert(shapes, table.concat(chunk, ","))
				end
				return Case.first(
					Case.same(shapes, { "aaaa,bbbb", "cccc,dddd", "e" }, "chunks"),
					Case.equal(#Analyzer.chunks({}, 10), 0, "empty"),
					Case.same(Analyzer.chunks({ string.rep("x", 40) }, 10)[1], { string.rep("x", 40) }, "oversized")
				)
			end,
		},
		{
			name = "public probes cover every exported control in both constructor forms",
			run = function(): string?
				local names = Analyzer.publicNames(
					"UI.Button = make\nlocal UI = {}\nUI.Badge=1\nXUI.Hidden = 1\nUI.helper = 2\nUI.Button = again\nif UI.Label == nil then end"
				)
				local source, expected, count = probeSource({ "Badge", "Button", "helper" })
				local lines = string.split(source, "\n")
				return Case.first(
					Case.same(names, { "Badge", "Button", "Label", "helper" }, "names"),
					Case.equal(lines[6], "UI.Badge(42)", "first probe"),
					Case.equal(expected[6], "Badge: table required", "first label"),
					Case.equal(expected[7], "Button: table required", "second label"),
					Case.equal(lines[8], "UI.Button({ label = 42 })", "listed probe"),
					Case.equal(count, #lines - 6, "count"),
					Case.equal(
						Analyzer.named('local wrong: number = UI.Button({ label = "Save" })'),
						'local wrong: number = UI.Button("Typed")({ label = "Save" })',
						"named"
					),
					Case.expect(
						string.find(source, 'UI.ThisControlDoesNotExist("Typed")', 1, true) == nil,
						"the unknown control gained a named form"
					),
					Case.expect(string.find(source, 'UI.Badge("Typed")', 1, true) ~= nil, "Badge has no named form")
				)
			end,
		},
		{
			name = "Lute accepts the pinned nightly and base version reports",
			run = function(): string?
				local pin, base = "1.0.1-nightly.20261006", "1.0.1"
				return Case.first(
					Case.expect(matchesLutePin(pin, pin, base), "the pinned nightly was refused"),
					Case.expect(matchesLutePin(base, pin, base), "the base version was refused"),
					Case.expect(not matchesLutePin("1.0.0", pin, base), "a different base version was accepted"),
					Case.expect(
						not matchesLutePin("1.0.1-nightly.20261007", pin, base),
						"a different nightly was accepted"
					)
				)
			end,
		},
		{
			name = "the Lute typedef pin follows rokit.toml and .luaurc",
			run = function(): string?
				local pin, base =
					lutePin('[tools]\nrojo = "rojo-rbx/rojo@7.7.0"\nlute = "luau-lang/lute@1.0.1-nightly.20261006"\n')
				return Case.first(
					Case.equal(pin, "1.0.1-nightly.20261006", "pin"),
					Case.equal(base, "1.0.1", "base"),
					Case.equal(
						aliasProblem(
							Json.decode(
								'{"aliases": {"std": "~/.lute/typedefs/1.0.1/std", "lute": "~/.lute/typedefs/1.0.1/lute"}}'
							),
							"1.0.1"
						),
						nil,
						"aliases"
					),
					Case.expect(
						aliasProblem(Json.decode('{"aliases": {"std": "~/.lute/typedefs/1.0.0/std"}}'), "1.0.1") ~= nil,
						"a stale alias was accepted"
					)
				)
			end,
		},
		{
			name = "engine types map Enum, ContentId and any",
			run = function(): string?
				return Case.first(
					Case.equal(Generator.nativeType("EnumFont"), "Enum.Font", "enum"),
					Case.equal(Generator.nativeType("EnumItem"), "EnumItem", "EnumItem"),
					Case.equal(Generator.nativeType("{ EnumKeyCode }?"), "{ Enum.KeyCode }?", "nested"),
					Case.equal(Generator.nativeType("ContentId | any"), "string | unknown", "content and any"),
					Case.equal(Generator.nativeType("anything | Enumerate"), "anything | Enumerate", "word boundaries")
				)
			end,
		},
		{
			name = "engine types generate props, signals, aliases, observers and the host",
			run = function(): string?
				local definitions = table.concat({
					"declare extern type Instance with",
					"\tName: string",
					"\tParent: Instance?",
					"\tChanged: RBXScriptSignal<(string)>",
					"end",
					"declare extern type GuiObject extends Instance with",
					"\tVisible: boolean",
					"\tSize: UDim2",
					"\tSize: UDim2",
					"\tAbsoluteSize: Vector2",
					"\tInputBegan: RBXScriptSignal<(InputObject, EnumUserInputState, any)>",
					"end",
					"declare extern type Frame extends GuiObject with",
					"\tStyle: EnumFrameStyle",
					"end",
					"",
				}, "\n")
				local schema: Generator.Schema = {
					Instance = { writable = { "Name", "Parent" } },
					GuiObject = { writable = { "Visible", "Size" } },
					Frame = { writable = { "Style" } },
				}
				local text, ordered = Generator.generate(definitions, schema, { "Frame", "GuiObject" })
				local lines = string.split(text, "\n")
				local function has(line: string): string?
					return Case.expect(table.find(lines, line) ~= nil, "missing line: " .. line)
				end
				return Case.first(
					Case.same(ordered, { "Instance", "GuiObject", "Frame" }, "order"),
					has("export type ValueBoolean = Value<boolean>"),
					has("export type ValueInstanceOptional = Value<Instance?>"),
					has("export type ValueEnumFrameStyle = Value<Enum.FrameStyle>"),
					has("\tParent: (ValueInstanceOptional | StaticValue)?,"),
					has("\tChanged: ((string) -> ())?,"),
					has("\tInputBegan: ((InputObject, Enum.UserInputState, unknown) -> ())?,"),
					has("\tAttributes: Attributes?,"),
					has("\tref: ((Frame) -> ())?,"),
					has("\tFrame: Constructor<FrameNativeProps, Frame>,"),
					has("\tAbsoluteSize: ((GuiObject) -> Compose.Cell<Vector2>),"),
					has("\tParent: ((Instance) -> Compose.Cell<Instance?>),"),
					Case.expect(
						table.find(lines, "export type InstanceNativeProps = {") == nil,
						"an unselected class was exported"
					),
					Case.expect(
						table.find(lines, "\tGuiObject: Constructor<GuiObjectNativeProps, GuiObject>,") == nil,
						"the abstract GuiObject gained a constructor"
					),
					Case.equal(lines[#lines - 1], "return {}", "tail")
				)
			end,
		},
		{
			name = "creator-docs metadata keeps writable, non-read-only properties",
			run = function(): string?
				local yaml = table.concat({
					"name: Frame",
					"properties:",
					"  - name: Frame.Style",
					"    security:",
					"      read: None",
					"      write: None",
					"",
					"  - name: Frame.Locked",
					"    security:",
					"      write: PluginSecurity",
					"  - name: Frame.Absolute",
					"    tags:",
					"      - ReadOnly",
					"    security:",
					"      write: None",
					"  - name: Frame.Alpha  ",
					"      write: None",
					"methods:",
					"  - name: Frame.Later",
					"      write: None",
					"",
				}, "\r\n")
				local directory = Files.join(ARTIFACTS, uniqueName("creator-docs-"))
				local file = Files.join(directory, "content/en-us/reference/engine/classes/Frame.yaml")
				Files.write(file, yaml)
				local ok, metadata = pcall(Generator.metadata, directory, { "Frame" })
				Files.remove(directory)
				if not ok then
					return tostring(metadata)
				end
				local frame = Json.field(metadata, "Frame")
				return Case.first(
					Case.same(Json.strings(Json.field(frame, "writable")) or {}, { "Alpha", "Style" }, "writable"),
					Case.equal(Json.stringField(frame, "sha256"), Hash.sha256(yaml), "sha256")
				)
			end,
		},
	}
end

local command: Cli.Command = {
	name = "types",
	summary = "Type check every Luau context with the pinned analyzer, or check the engine type generation.",
	usage = USAGE,
	values = { "solver", "files", "flag", "definitions", "creator-docs" },
	cases = function(): { Case.Case }
		return cases()
	end,
	run = run,
}

return command
