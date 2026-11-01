--!strict
local Verify = require("../../vendor/verify/src/core")

local json = require("@std/json")
local Analyzer = require("../lib/analyzer")
local Cli = require("../lib/cli")
local ConsumerTypes = require("../lib/consumer_types")
local Files = require("../lib/files")
local Encoding = require("../lib/encoding")
local Json = require("../lib/json")
local Run = require("../lib/run")
local UsageLint = require("../lib/usage_lint")
local Static = require("../lib/static_findings")

local USAGE =
	[[usage: lute run tools/facet lint [paths...] [--types] [--verbose] [--project FILE] [--solver new] [--rules] [--usage] [--json]

Checks interface code for Facet usage problems: any casts, reserved keys,
deprecated schedulers, dot calls of cell methods, Instance.new for interface
objects, literal paint, fonts and motion, device branches and raw input. Each
finding names the rule, the line and the fix.

  paths           Luau files or directories. The default is src/client.
  --types         Also type-check the paths with luau-lsp in strict Roblox mode.
                  It makes a Rojo sourcemap of --project and uses the Roblox
                  definitions in tools/typecheck/roblox.d.luau, or downloads
                  and checks the pinned definitions into artifacts/verify/types.
  --project FILE  The Rojo project for --types. The default is default.project.json.
  --solver NAME   The Luau type solver for --types: new.
  --rules         Lists the rules and exits.
  --verbose       Print source lines, repeated rule advice and full type errors.
                  The default shortens long type errors
                  and groups repeated findings. artifacts/facet-lint/report.txt keeps every finding.
  --usage         Lists the Facet controls and helpers that the paths use, with
                  counts, read from the source. It does not run the code.

The exit code is 1 when there is an error, and 0 when there are only warnings.]]

local function sources(paths: { string }): { string }
	local found: { string } = {}
	for _, given in paths do
		if Files.isFile(given) then
			table.insert(found, given)
		elseif Files.isDirectory(given) then
			for _, file in Files.walk(given) do
				if string.sub(file, -5) == ".luau" or string.sub(file, -4) == ".lua" then
					table.insert(found, Files.join(given, file))
				end
			end
		end
	end
	table.sort(found)
	return found
end

local SPEC_TYPES = { "CollectionSpec", "OutlineSpec", "TableSpec" }

local function hint(message: string): string?
	if string.find(message, "ThemeDefinition", 1, true) ~= nil then
		return "give the definition a Facet.ThemeDefinition type. Put palette lists in style.themes and type roles in metrics.typography. Read docs Tasks.theme."
	end
	if string.find(message, "Cannot add indexer to table", 1, true) ~= nil then
		return 'this table has fixed fields. Narrow the key to a literal branch, for example if key == "Credits" then value.Credits else value.Tokens. For an open map you own, type the initial value as { [string]: number } before Compose.cell; do not cast a server record.'
	end
	if string.find(message, "Unknown type 'Facet.Use'", 1, true) ~= nil then
		return "require the Facet root into local Facet in this module; Facet.Use is an exported type. Do not require a Use submodule or read Facet.Use as a value."
	end
	if string.find(message, "(InputObject?, number?) -> ()", 1, true) ~= nil then
		return "type a callback that you pass to onActivate as Facet.Activate, for example local function action(onActivate: Facet.Activate). Read docs Button.props."
	end
	if string.find(message, "Sides", 1, true) ~= nil then
		return 'give a padding table a type on a local, for example local inset: Facet.Sides = { top = "xl" }, and pass padding = inset. A literal inside the options does not check, because padding also takes a readable. Read docs Layout-options.'
	end
	if
		string.find(message, "ReadOnlyValue", 1, true) ~= nil
		or (string.find(message, "read cache:", 1, true) ~= nil and string.find(message, "read peek:", 1, true) ~= nil)
	then
		return "check the source value type, annotate reactive callbacks with function(use: Facet.Use), and type option lists before passing them. Read docs Types.reactive."
	end
	if string.find(message, "not valid UTF-8", 1, true) ~= nil or string.find(message, "U+feff", 1, true) ~= nil then
		return "save the file as UTF-8 without a byte order mark. In Windows PowerShell 5.1, Set-Content and Out-File use the system code page, and -Encoding utf8 adds a byte order mark; use [System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding $false))."
	end
	if string.find(message, "Available overloads", 1, true) ~= nil then
		for _, name in SPEC_TYPES do
			if string.find(message, name, 1, true) ~= nil then
				return 'give the spec a type on a local, for example local spec: Facet.KeyedCollectionSpec<Item, string> = { ... }, and pass it: UI.VirtualList(spec, "Items"). The checker then names the wrong entry. See docs "Typed collections".'
			end
		end
	end
	local option = string.match(message, "^Expected this to be 'number', but got '\"([^\"]+)\"'")
	if option ~= nil then
		return Static.layoutHint(option)
			or ("%s is not an option of this control. Run lute run tools/facet docs <Control>.props for typed options."):format(
				option
			)
	end
	return nil
end

local function withHint(line: string, message: string): string
	local found = hint(message)
	return if found ~= nil then line .. "\n    hint: " .. found else line
end

local CONTROL_TYPES = { "Packages/Facet/ui/control_types.luau", "src/ui/control_types.luau" }

local function usageReport(invocation: Cli.Invocation, sources: { { file: string, source: string } }): number
	local counts = UsageLint.usage(sources)
	local names: { string } = {}
	for name in counts do
		table.insert(names, name)
	end
	table.sort(names, function(left: string, right: string): boolean
		if counts[left] ~= counts[right] then
			return counts[left] > counts[right]
		end
		return left < right
	end)
	local lines: { string } = {}
	for _, name in names do
		table.insert(lines, ("%-28s %d"):format(name, counts[name]))
	end
	local known: { string } = {}
	for _, candidate in CONTROL_TYPES do
		if Files.isFile(candidate) then
			known = UsageLint.controls(Files.read(candidate))
			break
		end
	end
	local used = 0
	for _, name in known do
		if counts[name] ~= nil then
			used += 1
		end
	end
	if #known > 0 then
		table.insert(lines, ("facet lint: %d file(s) use %d of %d UI members"):format(#sources, used, #known))
	else
		table.insert(lines, ("facet lint: %d file(s)"):format(#sources))
	end
	local value: json.Value = { files = #sources, usage = counts, used = used, members = #known }
	Cli.emit(invocation, value, table.concat(lines, "\n"))
	return 0
end

local function run(invocation: Cli.Invocation): number
	local unknown =
		Cli.unknownFlags(invocation, { "types", "verbose", "project", "solver", "rules", "usage", "warning-counts" })
	if unknown ~= nil then
		print("facet lint: unknown flags " .. unknown)
		print(USAGE)
		return 2
	end
	if Cli.switch(invocation, "rules") then
		for _, rule in UsageLint.rules() do
			print(("%-22s %-8s %s"):format(rule.id, rule.severity, rule.message))
		end
		return 0
	end
	local paths = if #invocation.positional > 0 then invocation.positional else { "src/client" }
	Encoding.normalize(paths)
	local files = sources(paths)
	if #files == 0 then
		print(("facet lint: no Luau files under %s"):format(table.concat(paths, ", ")))
		print(USAGE)
		return 2
	end
	local findings: { UsageLint.Finding } = {}
	local sources: { { file: string, source: string } } = {}
	for _, file in files do
		local source = Files.read(file)
		table.insert(sources, { file = file, source = source })
		for _, finding in UsageLint.check(file, source) do
			table.insert(findings, finding)
		end
	end
	if Cli.switch(invocation, "usage") then
		return usageReport(invocation, sources)
	end
	for _, finding in UsageLint.project(sources) do
		table.insert(findings, finding)
	end
	local diagnostics: { Analyzer.Diagnostic } = {}
	local problem: string? = nil
	if Cli.switch(invocation, "types") then
		local checked, failure = ConsumerTypes.check(
			paths,
			Cli.flag(invocation, "project") or "default.project.json",
			Cli.flag(invocation, "solver") or "new"
		)
		diagnostics = checked or {}
		problem = failure
	end
	local errors = 0
	local lines: { string } = {}
	local grouped: { Static.Finding } = {}
	local details: { string } = {}
	local sourceByFile: { [string]: string } = {}
	for _, source in sources do
		sourceByFile[source.file] = source.source
	end
	local hidden = Static.cascades(diagnostics, sourceByFile)
	for _, finding in findings do
		if finding.severity == "error" then
			errors += 1
		end
		local location = ("%s:%d"):format(finding.file, finding.line)
		local full = location
			.. ": "
			.. finding.severity
			.. " ["
			.. finding.rule
			.. "] "
			.. finding.message
			.. "\n    "
			.. finding.text
		table.insert(details, full)
		table.insert(
			grouped,
			{ rule = finding.rule, severity = finding.severity, message = finding.message, location = location }
		)
	end
	for index, diagnostic in diagnostics do
		errors += 1
		local location = ("%s:%d:%d"):format(diagnostic.file, diagnostic.line, diagnostic.column)
		local full = location .. ": error [types] " .. diagnostic.message
		table.insert(details, withHint(full, diagnostic.message))
		if not hidden[index] then
			local finding: Static.Finding = {
				rule = "types",
				severity = "error",
				message = diagnostic.message,
				hint = hint(diagnostic.message),
				location = location,
			}
			table.insert(grouped, finding)
		end
	end
	Files.write("artifacts/facet-lint/report.txt", table.concat(details, "\n") .. "\n")
	lines = if Cli.switch(invocation, "verbose")
		then table.clone(details)
		else Static.render(grouped, Cli.switch(invocation, "warning-counts"))
	if #details > 0 then
		table.insert(lines, "Full static findings: artifacts/facet-lint/report.txt")
	end
	if problem ~= nil then
		errors += 1
		table.insert(lines, withHint("error [types] " .. (problem :: string), problem :: string))
	end
	table.insert(
		lines,
		("facet lint: %d file(s), %d finding(s), %d error(s)"):format(#files, #findings + #diagnostics, errors)
	)
	local value: json.Value = { files = #files, findings = #findings, diagnostics = #diagnostics, errors = errors }
	Cli.emit(invocation, value, table.concat(lines, "\n"))
	return if errors > 0 then 1 else 0
end

local GOOD = [=[--!strict
local Facet = require(game:GetService("ReplicatedStorage").Packages.Facet)
local app = Facet.app({ name = "Shop" })
local UI = app.UI
local count = Facet.Compose.cell(0)
app.mount(function()
	return UI.Screen({
		UI.Button({ label = "Buy", onActivate = function() count:update(function(n) return n + 1 end) end }, "Buy"),
		UI.Text({ text = "wait(1) and Color3.new in a string are fine", textRole = "caption" }, "Note"),
	}, "Shop")
end)
-- Instance.new("Frame") in a comment is fine
]=]

local BAD = [[local Facet = require(game:GetService("ReplicatedStorage").Packages.Facet)
local UserInputService = game:GetService("UserInputService")
local frame = Instance.new("Frame")
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
local label = Facet.app().UI.Text { text = "x", TextScaled = true } :: any
local count = Facet.Compose.cell(0)
count.set(2)
wait(1)
if UserInputService.TouchEnabled then end
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape then end
end)
local info = TweenInfo.new(0.3)
]]

local function rulesOf(findings: { UsageLint.Finding }): { [string]: number }
	local seen: { [string]: number } = {}
	for _, finding in findings do
		seen[finding.rule] = finding.line
	end
	return seen
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "clean Facet code has no findings, and strings and comments do not count", {
		id = prefix .. "clean Facet code has no findings, and strings and comments do not count",
		run = function(test: Verify.Context)
			local findings = UsageLint.check("good.luau", GOOD)
			Verify.expect(#findings):toBe(0)
		end,
	})
	harness:case(prefix .. "each rule finds its planted fault on the right line", {
		id = prefix .. "each rule finds its planted fault on the right line",
		run = function(test: Verify.Context)
			local seen = rulesOf(UsageLint.check("bad.luau", BAD))
			Verify.expect(seen.strict):toBe(1)
			Verify.expect(seen["native-gui-object"]):toBe(3)
			Verify.expect(seen["literal-paint"]):toBe(4)
			Verify.expect(seen["any-cast"]):toBe(5)
			Verify.expect(seen["literal-font"]):toBe(5)
			Verify.expect(seen["dot-cell-method"]):toBe(7)
			Verify.expect(seen["deprecated-scheduler"]):toBe(8)
			Verify.expect(seen["device-branch"]):toBe(9)
			Verify.expect(seen["raw-input"]):toBe(10)
			Verify.expect(seen["reserved-key"]):toBe(11)
			Verify.expect(seen["literal-motion"]):toBe(13)
		end,
	})
	harness:case(prefix .. "a second app or a second mounted root is a warning, and one of each is not", {
		id = prefix .. "a second app or a second mounted root is a warning, and one of each is not",
		run = function(test: Verify.Context)
			local one = [[--!strict
local app = Facet.app({ name = "Game" })
app.mount(function() return UI.Screen {} end)
]]
			local two = [[--!strict
local shop = Facet.app({ name = "Shop" })
shop.mount(function() return UI.Screen {} end)
]]
			local again = [[--!strict
local app = Facet.app({ name = "Game" })
app.mount(build)
app.mount(other)
Interface.mount(context)
]]
			local single = UsageLint.project({ { file = "a.luau", source = one } })
			local double =
				rulesOf(UsageLint.project({ { file = "a.luau", source = one }, { file = "b.luau", source = two } }))
			local mounts = rulesOf(UsageLint.project({ { file = "c.luau", source = again } }))
			Verify.expect(#single):toBe(0)
			Verify.expect(double["one-runtime"]):toBe(2)
			Verify.expect(mounts["one-root"]):toBe(4)
			Verify.expect(mounts["one-runtime"]):toBe(nil)
		end,
	})
	harness:case(prefix .. "type errors that hide their cause get a hint, and other errors do not", {
		id = prefix .. "type errors that hide their cause get a hint, and other errors do not",
		run = function(test: Verify.Context)
			local overload = hint(
				"Available overloads: <V, K>(KeyedCollectionSpec<V, K>) -> ScrollingFrame; and <V, _K>(IdentityCollectionSpec<V>) -> ScrollingFrame"
			)
			local option = hint("Expected this to be 'number', but got '\"width\"'")
			local record = hint("Cannot add indexer to table 'Record'")
			local publicUse = hint("Unknown type 'Facet.Use'")
			local reactive =
				hint("Expected Cache<Entry> & { read cache: { read value: Entry }?, read peek: <T>(Cache<T>) -> T }")
			local encoding = hint("rojo sourcemap failed: [ERROR rojo] File was not valid UTF-8: src/a.luau")
			Verify.expect(overload ~= nil and string.find(overload, "KeyedCollectionSpec", 1, true) ~= nil)
				:toBeTrueWith("no spec hint")
			Verify.expect(option ~= nil and string.find(option, "width", 1, true) == 1):toBeTrueWith("no option hint")
			Verify.expect(record ~= nil and string.find(record, "Narrow the key", 1, true) ~= nil)
				:toBeTrueWith("no record hint")
			Verify.expect(publicUse ~= nil and string.find(publicUse, "local Facet", 1, true) ~= nil)
				:toBeTrueWith("no Use hint")
			Verify.expect(reactive ~= nil and string.find(reactive, "source value type", 1, true) ~= nil)
				:toBeTrueWith("no reactive source hint")
			Verify.expect(encoding ~= nil and string.find(encoding, "without a byte order mark", 1, true) ~= nil)
				:toBeTrueWith("no encoding hint")
			Verify.expect(hint("Expected identifier when parsing expression, got Unicode character U+feff") ~= nil)
				:toBeTrueWith("no byte order mark hint")
			Verify.expect(hint("Type 'unknown' does not have key 'id'")):toBe(nil)
		end,
	})
	harness:case(prefix .. "usage counts the controls and helpers through an alias, and skips strings and comments", {
		id = prefix .. "usage counts the controls and helpers through an alias, and skips strings and comments",
		run = function(test: Verify.Context)
			local counts = UsageLint.usage({
				{
					file = "a.luau",
					source = [=[--!strict
local app = Facet.app({ name = "Game" })
local Kit = app.UI
local label = Kit.Text({ text = Facet.format.compact(1200) }, "Coins")
-- UI.Sheet in a comment
local note = "UI.Toast in a string"
local steps = UI.sequence({})
]=],
				},
			})
			local names = UsageLint.controls(Files.read("src/ui/control_types.luau"))
			Verify.expect(counts["UI.Text"]):toBe(1)
			Verify.expect(counts["Facet.format.compact"]):toBe(1)
			Verify.expect(counts["Facet.app"]):toBe(1)
			Verify.expect(counts["UI.sequence"]):toBe(1)
			Verify.expect(counts["UI.Sheet"]):toBe(nil)
			Verify.expect(counts["UI.Toast"]):toBe(nil)
			Verify.expect(table.find(names, "UI.Typewriter") ~= nil and #names > 40)
				:toBeTrueWith("the Controls type list")
		end,
	})
	harness:case(prefix .. "Facet-only rules stay quiet in code that does not use Facet", {
		id = prefix .. "Facet-only rules stay quiet in code that does not use Facet",
		run = function(test: Verify.Context)
			local plain =
				'--!strict\nlocal frame = Instance.new("Frame")\nframe.BackgroundColor3 = Color3.new(1, 1, 1)\n'
			Verify.expect(#UsageLint.check("plain.luau", plain)):toBe(0)
		end,
	})
	harness:case(prefix .. "the consumer example passes the lint", {
		id = prefix .. "the consumer example passes the lint",
		run = function(test: Verify.Context)
			for _, file in sources({ "examples/consumer/src" }) do
				for _, finding in UsageLint.check(file, Files.read(file)) do
					if finding.severity == "error" then
						error(`{file}:{finding.line} {finding.rule}`, 0)
					end
				end
			end
		end,
	})
end

local command: Cli.Command = {
	name = "lint",
	summary = "Check interface code for Facet usage problems, and optionally strict types.",
	usage = USAGE,
	values = { "project", "solver" },
	register = register,
	run = run,
}

return command
