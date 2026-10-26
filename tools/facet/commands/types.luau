--!strict
local Gate = require("../lib/gate")
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local luau = require("@lute/luau")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")
local time = require("@std/time")
local Analyzer = require("../lib/analyzer")
local Cli = require("../lib/cli")
local ControlProps = require("../lib/control_props")
local Definitions = require("../lib/definitions")
local Files = require("../lib/files")
local Generator = require("../lib/engine_generator")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Run = require("../lib/run")

local USAGE = [[usage: lute run tools/facet types [--solver old|new|both] [--flag KEY=VALUE]... [--source-only]
       lute run tools/facet types prepare
       lute run tools/facet types [--solver ...] --files FILE [FILE...]
       lute run tools/facet types selftest [--solver old|new|both]
       lute run tools/facet types engine [--check] [--definitions PATH] [--creator-docs PATH]
       lute run tools/facet types props [--check]
       lute run tools/facet types --selftest

The complete check type checks every tracked and untracked Luau file that Git does not
ignore, in each Rojo project context, in the Designer plugin context and in the Lute
context (tools/facet, tests/tools, tools/lute and the vendored Verify Lute runtime). It
requires strict directives, zero blocking diagnostics and the rejection of every public
negative probe. Every selected solver must pass.

--files checks only the named targets and records dependency diagnostics separately.
--source-only checks Facet-owned source without the public probes.
selftest selects the checker cases, then proves that the analyzer accepts a native UDim2
and a Lute standard library type and rejects an incompatible scalar in each context.
engine checks or regenerates src/ui/engine_types.luau from the pinned declarations
and tools/typecheck/engine_members.json; --creator-docs refreshes that metadata.
props checks or regenerates the flat control property types in src/ui/*_props.luau
from the option tables in src/ui/*_types.luau.
--selftest selects all checker and analyzer cases.]]

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
	local file = Files.join(ARTIFACTS, if lockFile == PLUGIN_LOCK then "roblox-plugin.d.luau" else "roblox.d.luau")
	return Definitions.resolve(lockFile, file)
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
		if project ~= "" and not seen[project] and Files.isFile(project) then
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
	{ "Menu command callback", 'local item: Facet.MenuCommand = { label = "Open", onSelect = 42 }' },
	{
		"Radial command callback",
		'local item: Facet.RadialAction<string> = { id = "open", label = "Open", onSelect = 42 }',
	},
	{ "Button native size", 'UI.Button({ label = "Save", Size = "large" })' },
	{ "Button native visibility", 'UI.Button({ label = "Save", Visible = "yes" })' },
	{ "Button nullable label", "UI.Button({ label = nullableText })" },
	{ "Button callback", 'UI.Button({ label = "Save", onActivate = "save" })' },
	{ "Button size rung", 'UI.Button({ label = "Save", controlSize = "tiny" })' },
	{ "Button native return", 'local wrong: number = UI.Button({ label = "Save" })' },
	{ "Button shortcut hint action", 'UI.Button({ label = "Boost", shortcutHint = "Boost" })' },
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
	{ "Card badge status", 'UI.Card({ title = "Kart", image = "a", badges = { leading = { status = "busy" } } })' },
	{ "Badge label", "UI.Badge({ label = false })" },
	{ "Avatar presence", 'UI.Avatar({ name = "Alder", presence = "unknown" })' },
	{ "Status status", 'UI.StatusIndicator({ status = "busy" })' },
	{ "Badged status", 'UI.badged(UI.Button { label = "Inbox" }, true, { status = "busy" })' },
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
	{
		"Toggle controlled callback",
		"local source: Facet.ReadOnlyValue<boolean> = Facet.Compose.formula(function() return false end); UI.Toggle({value=source})",
	},
	{ "TextInput numeric model", 'UI.TextInput({value=Facet.Compose.cell("1"),presentation="number"})' },
	{
		"TextInput controlled callback",
		'local source: Facet.ReadOnlyValue<string> = Facet.Compose.formula(function() return "" end); UI.TextInput({value=source})',
	},
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
	{ "HStack corners", 'UI.HStack({ surface = "panel", corners = "round" })' },
	{ "VStack width", 'UI.VStack({ width = "stretch" })' },
	{ "VStack native size", "UI.VStack({ Size = 42 })" },
	{ "Screen gap", "UI.Screen({ gap = false })" },
	{ "Screen surface", 'UI.Screen({ surface = "card" })' },
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
	'local Facet = require("@repo/src")',
	"local runtime = Facet.Roblox.createRuntime()",
	"local UI = Facet.controls(runtime)",
	"local nullableText: Facet.Value<string?> = Facet.Compose.cell(nil :: string?)",
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
	local file = Files.join(ARTIFACTS, uniqueName("_negative_") .. ".luau")
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

local function props(invocation: Cli.Invocation): number
	local stale, texts = ControlProps.stale(ARTIFACTS)
	if Cli.switch(invocation, "check") then
		if #stale > 0 then
			print(("control props differ; run lute run tools/facet types props: %s"):format(table.concat(stale, ", ")))
			return 1
		end
		print(("%d generated props modules match their option types"):format(#ControlProps.FAMILIES))
		return 0
	end
	while #stale > 0 do
		for _, output in stale do
			Files.write(output, texts[output])
			print(("wrote %s"):format(output))
		end
		stale, texts = ControlProps.stale(ARTIFACTS)
	end
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

local function prepare(capture: typeof(Run.capture)?)
	local execute = capture or Run.capture
	local rokit = Files.read("rokit.toml")
	for _, tool in { "rojo", "stylua" } do
		local pin = assert(string.match(rokit, "\n" .. tool .. '%s*=%s*"[^"@]*@([^"]+)"'))
		local result = execute({ tool, "--version" })
		local version = string.match(result.stdout, "%d+%.%d+%.%d+")
		if not result.ok or version ~= pin then
			fail(`{tool} {tostring(version)} differs from pin {pin}; run rokit install`)
		end
		print(stringext.trim(result.stdout))
	end
	for _, tool in { "git", "bash" } do
		local result = execute({ tool, "--version" })
		if not result.ok then
			fail(`{tool} is missing from PATH: {result.stderr}`)
		end
	end
	analyzerVersion()
	prepareLuteTypes()
	definitions(LOCK)
	definitions(PLUGIN_LOCK)
	print("preflight: pinned tools, Lute typedefs and both Roblox definition locks are ready")
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
		Files.join(ARTIFACTS, uniqueName("_checker_") .. ".luau"),
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

local register: (Verify.Harness, string) -> ()

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
	local code = Gate.selftest("tools/commands", "tools/commands::types::checker::")
	if code ~= 0 then
		return code
	end
	for _, solver in solversOf(options) do
		code = math.max(code, Gate.selftest("tools/commands", "tools/commands::types::analyzer " .. solver .. "::"))
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
		local stale = ControlProps.stale(ARTIFACTS)
		if #stale > 0 then
			fail(("Control props differ: %s; run lute run tools/facet types props"):format(table.concat(stale, ", ")))
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
		if subcommand == "prepare" then
			if #invocation.positional ~= 1 or next(invocation.flags) ~= nil then
				print(USAGE)
				return 2
			end
			prepare()
			return 0
		end
		if subcommand == "engine" then
			return engine(invocation)
		end
		if subcommand == "props" then
			return props(invocation)
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

register = function(harness: Verify.Harness, prefix: string): ()
	local idPrefix = prefix
	prefix ..= "checker::"
	harness:case(prefix .. "control option origins retain native hooks, binding variants and aliases", {
		id = idPrefix .. "control option origins retain native hooks, binding variants and aliases",
		run = function(test: Verify.Context): ()
			local origins = ControlProps.optionOrigins(".")
			Verify.expect(origins.ButtonProps.ref):toBe("TextButtonProps")
			Verify.expect(origins.ToggleCellProps.value):toBe("CellBinding")
			Verify.expect(origins.ToggleRequestProps.value):toBe("RequestBinding")
			Verify.expect(origins.SliderCellProps.range):toBe("SliderCellBinding")
			Verify.expect(origins.SliderRangeProps.range):toBe("SliderRangeBinding")
			Verify.expect(origins.CollectionSpec.from):toBe(origins.KeyedCollectionSpec.from)
			Verify.expect(origins.KeyedCollectionSpec.rowActions):toBe(nil)
		end,
	})
	harness:case(prefix .. "inventory includes each repository area and untracked files", {
		id = idPrefix .. "inventory includes each repository area and untracked files",
		run = function(test: Verify.Context): ()
			local existing: { [string]: boolean } = {}
			for _, file in FIXTURE_FILES do
				existing[file] = true
			end
			existing["examples/new.luau"] = true
			local listing = table.concat(FIXTURE_FILES, "\0") .. "\0examples/new.luau\0src/deleted.luau\0src/a.luau\0"
			local expected = table.clone(FIXTURE_FILES)
			table.insert(expected, "examples/new.luau")
			table.sort(expected)
			Verify.expect(Analyzer.inventory(listing, function(file: string): boolean
				return existing[file] == true
			end)):toEqual(expected)
			Verify.expect(table.find(INVENTORY, "--others") ~= nil):toBeTrueWith("the inventory omits untracked files")
			Verify.expect(table.find(INVENTORY, "--cached") ~= nil):toBeTrueWith("the inventory omits tracked files")
		end,
	})
	harness:case(prefix .. "complete check blocks dependency errors", {
		id = idPrefix .. "complete check blocks dependency errors",
		run = function(test: Verify.Context): ()
			local report = fixtureReport({ diagnostic("src/vendor/dependency.luau") })
			Verify.expect(report.ok):toBe(false)
			Verify.expect(fileList(report.owned)):toEqual({ "src/vendor/dependency.luau:2" })
			Verify.expect(fileList(report.external)):toEqual({})
			Verify.expect(Json.strings(report.document.targets) or {}):toEqual(FIXTURE_FILES)
			Verify.expect(Json.field(report.document, "mode")):toBe("full")
		end,
	})
	harness:case(prefix .. "analyzer report keeps the type mismatch details", {
		id = idPrefix .. "analyzer report keeps the type mismatch details",
		run = function(test: Verify.Context): ()
			local output =
				"tests/a.luau(2,1): TypeError: Expected this to be\n\t'string'\nbut got\n\t'number'\ntests/a.luau(3,1): SyntaxError: missing end\n"
			local diagnostics = Analyzer.parse(output, "/repo")
			Verify.expect(#diagnostics):toBe(2)
			Verify.expect(
				diagnostics[1] ~= nil and string.find(diagnostics[1].message, "but got\n\t'number'", 1, true) ~= nil
			)
				:toBeTrueWith("the first message lost its detail")
			Verify.expect(diagnostics[2] and diagnostics[2].message):toBe("missing end")
			Verify.expect(diagnostics[1] and diagnostics[1].file):toBe("tests/a.luau")
		end,
	})
	harness:case(prefix .. "focused check records dependencies separately", {
		id = idPrefix .. "focused check records dependencies separately",
		run = function(test: Verify.Context): ()
			local report = fixtureReport({ diagnostic("src/vendor/dependency.luau") }, { "src/a.luau" })
			Verify.expect(report.ok):toBe(true)
			Verify.expect(fileList(report.external)):toEqual({ "src/vendor/dependency.luau:2" })
			Verify.expect(Json.field(report.document, "mode")):toBe("focused")
			Verify.expect(Json.isNull(report.document.publicProbes)):toBe(true)
		end,
	})
	harness:case(prefix .. "strict cannot be disabled later in a file", {
		id = idPrefix .. "strict cannot be disabled later in a file",
		run = function(test: Verify.Context): ()
			local report = fixtureReport({}, nil, nil, { "bench/a.luau" })
			Verify.expect(Analyzer.missingStrict("--!strict\n--!nocheck\nreturn {}\n")):toBe(true)
			Verify.expect(Analyzer.missingStrict("--!strict\n--!nonstrict\nreturn {}\n")):toBe(true)
			Verify.expect(Analyzer.missingStrict("--!nonstrict\nreturn {}\n")):toBe(true)
			Verify.expect(Analyzer.missingStrict("--!strict\r\nreturn {}\r\n")):toBe(false)
			Verify.expect(Analyzer.missingStrict("--!strict\n--!nocheckers\nreturn {}\n")):toBe(false)
			Verify.expect(Analyzer.missingStrict("--!strict")):toBe(true)
			Verify.expect(report.ok):toBe(false)
			Verify.expect(Json.strings(report.document.missingStrict) or {}):toEqual({ "bench/a.luau" })
		end,
	})
	harness:case(prefix .. "new solver has no diagnostic allowance", {
		id = idPrefix .. "new solver has no diagnostic allowance",
		run = function(test: Verify.Context): ()
			local report = fixtureReport({ diagnostic("tests/a.luau") }, nil, "new")
			Verify.expect(report.ok):toBe(false)
			Verify.expect(Json.strings(report.document.flags) or {}):toEqual({
				"LuauTarjanChildLimit=100000",
				"LuauSolverV2=true",
			})
		end,
	})
	harness:case(prefix .. "projects cover mapped and unmapped files in both security contexts", {
		id = idPrefix .. "projects cover mapped and unmapped files in both security contexts",
		run = function(test: Verify.Context): ()
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
			Verify.expect(covered):toEqual(expected)
			Verify.expect(contexts):toEqual({ "default.project.json/game", "default.project.json/plugin", "nil/game" })
			Verify.expect(runs[1] and runs[1].extra[1])
				:toBe("--sourcemap=artifacts/verify/types/project-abc.sourcemap.json")
		end,
	})
	harness:case(prefix .. "Lute runtime files are analyzed in their own context", {
		id = idPrefix .. "Lute runtime files are analyzed in their own context",
		run = function(test: Verify.Context): ()
			local roblox, lute = Analyzer.partition({
				"src/a.luau",
				"tools/facet/init.luau",
				"tests/lute/worker.luau",
				"tests/a.verify.luau",
				"tools/facet/commands/studio.luau",
				"bench/perf_runner.luau",
				"tools/vendor/verify/src/lute/host.luau",
				"tools/vendor/verify/src/core/init.luau",
				"tools/vendor/verify/tools/studio-worker.luau",
			})
			Verify.expect(roblox):toEqual({
				"src/a.luau",
				"tests/a.verify.luau",
				"bench/perf_runner.luau",
				"tools/vendor/verify/src/core/init.luau",
			})
			Verify.expect(lute):toEqual({
				"tools/facet/init.luau",
				"tests/lute/worker.luau",
				"tools/facet/commands/studio.luau",
				"tools/vendor/verify/src/lute/host.luau",
				"tools/vendor/verify/tools/studio-worker.luau",
			})
		end,
	})
	harness:case(prefix .. "the Lute context blocks only first-party diagnostics", {
		id = idPrefix .. "the Lute context blocks only first-party diagnostics",
		run = function(test: Verify.Context): ()
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
			Verify.expect(fileList(public.owned)):toEqual({ "tools/facet/init.luau:2" })
			Verify.expect(#public.external):toBe(4)
			Verify.expect(fileList(focused.owned)):toEqual({ "tools/vendor/verify/src/lute/host.luau:2" })
			Verify.expect(#robloxPublic.owned):toBe(1)
			Verify.expect(#robloxPublic.external):toBe(1)
		end,
	})
	harness:case(prefix .. "a diagnostic owned in one context is not also a dependency diagnostic", {
		id = idPrefix .. "a diagnostic owned in one context is not also a dependency diagnostic",
		run = function(test: Verify.Context): ()
			local shared = diagnostic("tools/vendor/verify/src/core/execution.luau")
			local merged = Analyzer.merge({
				{ owned = {}, external = { shared, diagnostic("C:/x.luau") } },
				{ owned = { shared, shared }, external = {} },
			})
			Verify.expect(fileList(merged.owned)):toEqual({ "tools/vendor/verify/src/core/execution.luau:2" })
			Verify.expect(fileList(merged.external)):toEqual({ "C:/x.luau:2" })
		end,
	})
	harness:case(prefix .. "analyzer paths normalize to repository-relative forward slashes", {
		id = idPrefix .. "analyzer paths normalize to repository-relative forward slashes",
		run = function(test: Verify.Context): ()
			local root = "C:/git/Facet/worktree"
			Verify.expect(Analyzer.relative("tools\\facet\\init.luau", root)):toBe("tools/facet/init.luau")
			Verify.expect(Analyzer.relative("c:\\git\\Facet\\worktree\\src\\a.luau", root)):toBe("src/a.luau")
			Verify.expect(Analyzer.relative("\\\\?\\C:\\git\\Facet\\worktree\\src\\a.luau", root)):toBe("src/a.luau")
			Verify.expect(Analyzer.relative("../../../Users/bacon/.lute/typedefs/1.0.1/std/fs.luau", root))
				:toBe("C:/Users/bacon/.lute/typedefs/1.0.1/std/fs.luau")
			Verify.expect(Analyzer.relative("../../../../t:/fixture/samples/a.luau", root))
				:toBe("t:/fixture/samples/a.luau")
			Verify.expect(Analyzer.relative("/repo/src/a.luau", "/repo")):toBe("src/a.luau")
			Verify.expect(Analyzer.relative("/Repo/src/a.luau", "/repo")):toBe("/Repo/src/a.luau")
			Verify.expect(Analyzer.withoutVerbatimPrefix("\\\\?\\C:\\repo\\src\\init.luau"))
				:toBe("C:\\repo\\src\\init.luau")
			Verify.expect(Analyzer.withoutVerbatimPrefix("/repo/src/init.luau")):toBe("/repo/src/init.luau")
			Verify.expect(Analyzer.isFirstParty("C:/Users/bacon/x.luau")):toBe(false)
			Verify.expect(Analyzer.isFirstParty("tools/facet/x.luau")):toBe(true)
		end,
	})
	harness:case(prefix .. "analyzer output with CRLF, log lines, project labels and lint kinds parses", {
		id = idPrefix .. "analyzer output with CRLF, log lines, project labels and lint kinds parses",
		run = function(test: Verify.Context): ()
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
			Verify.expect(fileList(diagnostics)):toEqual({ "tools/facet/a.luau:4", "src/b.luau:7", "src/d.lua:9" })
			Verify.expect(diagnostics[1] and diagnostics[1].message)
				:toBe("Expected this to be\n\t'string'\nbut got 'number'")
			Verify.expect(diagnostics[2] and diagnostics[2].kind):toBe("SyntaxError")
			Verify.expect(diagnostics[2] and diagnostics[2].column):toBe(3)
		end,
	})
	harness:case(prefix .. "long target lists split under the argument budget", {
		id = idPrefix .. "long target lists split under the argument budget",
		run = function(test: Verify.Context): ()
			local chunks = Analyzer.chunks({ "aaaa", "bbbb", "cccc", "dddd", "e" }, 15)
			local shapes: { string } = {}
			for _, chunk in chunks do
				table.insert(shapes, table.concat(chunk, ","))
			end
			Verify.expect(shapes):toEqual({ "aaaa,bbbb", "cccc,dddd", "e" })
			Verify.expect(#Analyzer.chunks({}, 10)):toBe(0)
			Verify.expect(Analyzer.chunks({ string.rep("x", 40) }, 10)[1]):toEqual({ string.rep("x", 40) })
		end,
	})
	harness:case(prefix .. "public probes cover every exported control in both constructor forms", {
		id = idPrefix .. "public probes cover every exported control in both constructor forms",
		run = function(test: Verify.Context): ()
			local names = Analyzer.publicNames(
				"UI.Button = make\nlocal UI = {}\nUI.Badge=1\nXUI.Hidden = 1\nUI.helper = 2\nUI.Button = again\nif UI.Label == nil then end"
			)
			local source, expected, count = probeSource({ "Badge", "Button", "helper" })
			local lines = string.split(source, "\n")
			Verify.expect(names):toEqual({ "Badge", "Button", "Label", "helper" })
			Verify.expect(lines[6]):toBe("UI.Badge(42)")
			Verify.expect(expected[6]):toBe("Badge: table required")
			Verify.expect(expected[7]):toBe("Button: table required")
			Verify.expect(lines[8]):toBe("UI.Button({ label = 42 })")
			Verify.expect(count):toBe(#lines - 6)
			Verify.expect(Analyzer.named('local wrong: number = UI.Button({ label = "Save" })'))
				:toBe('local wrong: number = UI.Button("Typed")({ label = "Save" })')
			Verify.expect(string.find(source, 'UI.ThisControlDoesNotExist("Typed")', 1, true) == nil)
				:toBeTrueWith("the unknown control gained a named form")
			Verify.expect(string.find(source, 'UI.Badge("Typed")', 1, true) ~= nil)
				:toBeTrueWith("Badge has no named form")
		end,
	})
	harness:case(prefix .. "preflight rejects missing tools and mismatched pins before expensive checks", {
		id = idPrefix .. "preflight rejects missing tools and mismatched pins before expensive checks",
		run = function(test: Verify.Context): ()
			for _, broken in { "rojo", "stylua", "git", "bash", "wrong-version" } do
				local ok, problem = pcall(function(): boolean
					prepare(function(argv: { string }, _: Run.Options?): Run.Result
						return {
							ok = argv[1] ~= broken,
							code = if argv[1] == broken then 127 else 0,
							stdout = if broken == "wrong-version"
								then "0.0.0"
								elseif argv[1] == "rojo" then "Rojo 7.7.0"
								else "stylua 2.5.2",
							stderr = "missing fixture tool",
							timedOut = false,
						}
					end)
					return true
				end)
				local expected = if broken == "wrong-version" then "differs from pin" else broken
				if ok or not string.find(tostring(problem), expected, 1, true) then
					error(`preflight accepted {broken}: {tostring(problem)}`, 0)
				end
			end
		end,
	})
	harness:case(prefix .. "Lute accepts the pinned nightly and base version reports", {
		id = idPrefix .. "Lute accepts the pinned nightly and base version reports",
		run = function(test: Verify.Context): ()
			local pin, base = "1.0.1-nightly.20261006", "1.0.1"
			Verify.expect(matchesLutePin(pin, pin, base)):toBeTrueWith("the pinned nightly was refused")
			Verify.expect(matchesLutePin(base, pin, base)):toBeTrueWith("the base version was refused")
			Verify.expect(not matchesLutePin("1.0.0", pin, base)):toBeTrueWith("a different base version was accepted")
			Verify.expect(not matchesLutePin("1.0.1-nightly.20261007", pin, base))
				:toBeTrueWith("a different nightly was accepted")
		end,
	})
	harness:case(prefix .. "the Lute typedef pin follows rokit.toml and .luaurc", {
		id = idPrefix .. "the Lute typedef pin follows rokit.toml and .luaurc",
		run = function(test: Verify.Context): ()
			local pin, base =
				lutePin('[tools]\nrojo = "rojo-rbx/rojo@7.7.0"\nlute = "luau-lang/lute@1.0.1-nightly.20261006"\n')
			Verify.expect(pin):toBe("1.0.1-nightly.20261006")
			Verify.expect(base):toBe("1.0.1")
			Verify.expect(
				aliasProblem(
					Json.decode(
						'{"aliases": {"std": "~/.lute/typedefs/1.0.1/std", "lute": "~/.lute/typedefs/1.0.1/lute"}}'
					),
					"1.0.1"
				)
			):toBe(nil)
			Verify.expect(
				aliasProblem(Json.decode('{"aliases": {"std": "~/.lute/typedefs/1.0.0/std"}}'), "1.0.1") ~= nil
			)
				:toBeTrueWith("a stale alias was accepted")
		end,
	})
	harness:case(prefix .. "engine types map Enum, ContentId and any", {
		id = idPrefix .. "engine types map Enum, ContentId and any",
		run = function(test: Verify.Context): ()
			Verify.expect(Generator.nativeType("EnumFont")):toBe("Enum.Font")
			Verify.expect(Generator.nativeType("EnumItem")):toBe("EnumItem")
			Verify.expect(Generator.nativeType("{ EnumKeyCode }?")):toBe("{ Enum.KeyCode }?")
			Verify.expect(Generator.nativeType("ContentId | any")):toBe("string | unknown")
			Verify.expect(Generator.nativeType("anything | Enumerate")):toBe("anything | Enumerate")
		end,
	})
	harness:case(prefix .. "engine types generate props, signals, aliases, observers and the host", {
		id = idPrefix .. "engine types generate props, signals, aliases, observers and the host",
		run = function(test: Verify.Context): ()
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
			local function has(line: string): ()
				Verify.expect(table.find(lines, line) ~= nil):toBeTrueWith("missing line: " .. line)
			end
			Verify.expect(ordered):toEqual({ "Instance", "GuiObject", "Frame" })
			has("export type ValueBoolean = Input<boolean>")
			has("export type ValueInstanceOptional = Input<Instance?>")
			has("export type ValueEnumFrameStyle = Input<Enum.FrameStyle>")
			has("\tParent: (ValueInstanceOptional | StaticValue)?,")
			has("\tChanged: ((string) -> ())?,")
			has("\tInputBegan: ((InputObject, Enum.UserInputState, unknown) -> ())?,")
			has("\tAttributes: Attributes?,")
			has("\tref: ((Frame) -> ())?,")
			has("\tFrame: Constructor<FrameNativeProps, Frame>,")
			has("\tAbsoluteSize: ((GuiObject) -> Compose.Value<Vector2>),")
			has("\tParent: ((Instance) -> Compose.Value<Instance?>),")
			Verify.expect(table.find(lines, "export type InstanceNativeProps = {") == nil)
				:toBeTrueWith("an unselected class was exported")
			Verify.expect(table.find(lines, "\tGuiObject: Constructor<GuiObjectNativeProps, GuiObject>,") == nil)
				:toBeTrueWith("the abstract GuiObject gained a constructor")
			Verify.expect(lines[#lines - 1]):toBe("return {}")
		end,
	})
	harness:case(prefix .. "creator-docs metadata keeps writable, non-read-only properties", {
		id = idPrefix .. "creator-docs metadata keeps writable, non-read-only properties",
		run = function(test: Verify.Context): ()
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
				error(tostring(metadata), 0)
			end
			local frame = Json.field(metadata, "Frame")
			Verify.expect(Json.strings(Json.field(frame, "writable")) or {}):toEqual({ "Alpha", "Style" })
			Verify.expect(Json.stringField(frame, "sha256")):toBe(Hash.sha256(yaml))
		end,
	})
end

local command: Cli.Command = {
	name = "types",
	summary = "Type check every Luau context with the pinned analyzer, or check the engine type generation.",
	usage = USAGE,
	values = { "solver", "files", "flag", "definitions", "creator-docs" },
	register = function(harness: Verify.Harness, prefix: string)
		register(harness, prefix)
		local name = "the analyzers accept native and Lute types and reject planted scalar faults"
		for _, solver in { "old", "new" } do
			harness:case(prefix .. "analyzer " .. solver .. "::" .. name, {
				id = prefix .. name .. (if solver == "old" then "" else " (new solver)"),
				run = function()
					prepare()
					Verify.expect(liveSelftest(flagsFor(solver, {}))):toBe(0)
				end,
			})
		end
	end,
	run = run,
}

return command
