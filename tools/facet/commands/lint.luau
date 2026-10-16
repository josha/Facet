--!strict

local json = require("@std/json")
local Analyzer = require("../lib/analyzer")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local ConsumerTypes = require("../lib/consumer_types")
local Files = require("../lib/files")
local Encoding = require("../lib/encoding")
local Json = require("../lib/json")
local Run = require("../lib/run")
local UsageLint = require("../lib/usage_lint")

local USAGE =
	[[usage: lute run tools/facet lint [paths...] [--types] [--verbose] [--project FILE] [--solver new|old] [--rules] [--usage] [--json]

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
  --solver NAME   The Luau type solver for --types: new (the default, as in
                  Studio) or old.
  --rules         Lists the rules and exits.
  --verbose       Print source lines, repeated rule advice and full type errors.
                  The default shortens long type errors
                  and saves their full text to artifacts/facet-lint/types.txt.
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
	if string.find(message, "Readable", 1, true) ~= nil then
		return "annotate reactive callbacks with function(use: Facet.Use) and type option lists before passing them. Read docs Types.reactive."
	end
	if string.find(message, "not valid UTF-8", 1, true) ~= nil or string.find(message, "U+feff", 1, true) ~= nil then
		return "save the file as UTF-8 without a byte order mark. In Windows PowerShell 5.1, Set-Content and Out-File use the system code page, and -Encoding utf8 adds a byte order mark; use [System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding $false))."
	end
	if string.find(message, "Available overloads", 1, true) ~= nil then
		for _, name in SPEC_TYPES do
			if string.find(message, name, 1, true) ~= nil then
				return 'give the spec a type on a local, for example local spec: Facet.KeyedCollectionSpec<Item, string> = { ... }, and pass it: UI.VirtualList "Items" (spec). The checker then names the wrong entry. See docs "Typed collections".'
			end
		end
	end
	local option = string.match(message, "^Expected this to be 'EventKey | number', but got '\"([^\"]+)\"'")
	if option ~= nil then
		return ("%s is not an option of this control. Run docs <Control> for its options."):format(option)
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
	local unknown = Cli.unknownFlags(invocation, { "types", "verbose", "project", "solver", "rules", "usage" })
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
	local rules: { [string]: boolean } = {}
	for _, finding in findings do
		if finding.severity == "error" then
			errors += 1
		end
		local label = ("%s:%d: %s [%s]"):format(finding.file, finding.line, finding.severity, finding.rule)
		if not rules[finding.rule] or Cli.switch(invocation, "verbose") then
			label ..= " " .. finding.message
		end
		if Cli.switch(invocation, "verbose") then
			label ..= "\n    " .. finding.text
		end
		rules[finding.rule] = true
		table.insert(lines, label)
	end
	local details: { string } = {}
	local hints: { [string]: boolean } = {}
	local shortened = false
	for _, diagnostic in diagnostics do
		errors += 1
		local full = ("%s:%d:%d: error [types] %s"):format(
			diagnostic.file,
			diagnostic.line,
			diagnostic.column,
			diagnostic.message
		)
		table.insert(details, full)
		if #diagnostic.message > 600 and not Cli.switch(invocation, "verbose") then
			local prefix = string.sub(diagnostic.message, 1, 400)
			table.insert(lines, string.sub(full, 1, #full - #diagnostic.message) .. prefix .. " ... [shortened]")
			shortened = true
		else
			table.insert(lines, full)
		end
		local fix = hint(diagnostic.message)
		if fix ~= nil and not hints[fix] then
			table.insert(lines, "    hint: " .. fix)
			hints[fix] = true
		end
	end
	if shortened then
		Files.write("artifacts/facet-lint/types.txt", table.concat(details, "\n"))
		table.insert(lines, "Full type errors: artifacts/facet-lint/types.txt (or run lint --types --verbose).")
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

local GOOD = [[--!strict
local Facet = require(game:GetService("ReplicatedStorage").Packages.Facet)
local app = Facet.app({ name = "Shop" })
local UI = app.UI
local count = Facet.Compose.cell(0)
app.mount(function()
	return UI.Screen "Shop" {
		UI.Button "Buy" { label = "Buy", onActivate = function() count:update(function(n) return n + 1 end) end },
		UI.Text "Note" { text = "wait(1) and Color3.new in a string are fine", textRole = "caption" },
	}
end)
-- Instance.new("Frame") in a comment is fine
]]

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

local function cases(): { Case.Case }
	return {
		{
			name = "clean Facet code has no findings, and strings and comments do not count",
			run = function()
				local findings = UsageLint.check("good.luau", GOOD)
				return Case.equal(#findings, 0, "findings: " .. (if findings[1] then findings[1].rule else ""))
			end,
		},
		{
			name = "each rule finds its planted fault on the right line",
			run = function()
				local seen = rulesOf(UsageLint.check("bad.luau", BAD))
				return Case.first(
					Case.equal(seen.strict, 1, "strict"),
					Case.equal(seen["native-gui-object"], 3, "native-gui-object"),
					Case.equal(seen["literal-paint"], 4, "literal-paint"),
					Case.equal(seen["any-cast"], 5, "any-cast"),
					Case.equal(seen["literal-font"], 5, "literal-font"),
					Case.equal(seen["dot-cell-method"], 7, "dot-cell-method"),
					Case.equal(seen["deprecated-scheduler"], 8, "deprecated-scheduler"),
					Case.equal(seen["device-branch"], 9, "device-branch"),
					Case.equal(seen["raw-input"], 10, "raw-input"),
					Case.equal(seen["reserved-key"], 11, "reserved-key"),
					Case.equal(seen["literal-motion"], 13, "literal-motion")
				)
			end,
		},
		{
			name = "a second app or a second mounted root is a warning, and one of each is not",
			run = function()
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
				return Case.first(
					Case.equal(#single, 0, "findings for one app"),
					Case.equal(double["one-runtime"], 2, "second app"),
					Case.equal(mounts["one-root"], 4, "second mount"),
					Case.equal(mounts["one-runtime"], nil, "one app in one file")
				)
			end,
		},
		{
			name = "type errors that hide their cause get a hint, and other errors do not",
			run = function()
				local overload = hint(
					"Available overloads: <V, K>(KeyedCollectionSpec<V, K>) -> ScrollingFrame; and <V, _K>(IdentityCollectionSpec<V>) -> ScrollingFrame"
				)
				local option = hint("Expected this to be 'EventKey | number', but got '\"width\"'")
				local record = hint("Cannot add indexer to table 'Record'")
				local publicUse = hint("Unknown type 'Facet.Use'")
				local encoding = hint("rojo sourcemap failed: [ERROR rojo] File was not valid UTF-8: src/a.luau")
				return Case.first(
					Case.expect(
						overload ~= nil and string.find(overload, "KeyedCollectionSpec", 1, true) ~= nil,
						"no spec hint"
					),
					Case.expect(option ~= nil and string.find(option, "width", 1, true) == 1, "no option hint"),
					Case.expect(
						record ~= nil and string.find(record, "Narrow the key", 1, true) ~= nil,
						"no record hint"
					),
					Case.expect(
						publicUse ~= nil and string.find(publicUse, "local Facet", 1, true) ~= nil,
						"no Use hint"
					),
					Case.expect(
						encoding ~= nil and string.find(encoding, "without a byte order mark", 1, true) ~= nil,
						"no encoding hint"
					),
					Case.expect(
						hint("Expected identifier when parsing expression, got Unicode character U+feff") ~= nil,
						"no byte order mark hint"
					),
					Case.equal(hint("Type 'unknown' does not have key 'id'"), nil, "plain error")
				)
			end,
		},
		{
			name = "usage counts the controls and helpers through an alias, and skips strings and comments",
			run = function()
				local counts = UsageLint.usage({
					{
						file = "a.luau",
						source = [[--!strict
local app = Facet.app({ name = "Game" })
local Kit = app.UI
local label = Kit.Text "Coins" { text = Facet.format.compact(1200) }
-- UI.Sheet in a comment
local note = "UI.Toast in a string"
local steps = UI.sequence({})
]],
					},
				})
				local names = UsageLint.controls(Files.read("src/ui/control_types.luau"))
				return Case.first(
					Case.equal(counts["UI.Text"], 1, "Text through an alias"),
					Case.equal(counts["Facet.format.compact"], 1, "format"),
					Case.equal(counts["Facet.app"], 1, "app"),
					Case.equal(counts["UI.sequence"], 1, "sequence"),
					Case.equal(counts["UI.Sheet"], nil, "comment"),
					Case.equal(counts["UI.Toast"], nil, "string"),
					Case.expect(table.find(names, "UI.Typewriter") ~= nil and #names > 40, "the Controls type list")
				)
			end,
		},
		{
			name = "Facet-only rules stay quiet in code that does not use Facet",
			run = function()
				local plain =
					'--!strict\nlocal frame = Instance.new("Frame")\nframe.BackgroundColor3 = Color3.new(1, 1, 1)\n'
				return Case.equal(#UsageLint.check("plain.luau", plain), 0, "findings")
			end,
		},
		{
			name = "the consumer example passes the lint",
			run = function()
				for _, file in sources({ "examples/consumer/src" }) do
					for _, finding in UsageLint.check(file, Files.read(file)) do
						if finding.severity == "error" then
							return `{file}:{finding.line} {finding.rule}`
						end
					end
				end
				return nil
			end,
		},
	}
end

local command: Cli.Command = {
	name = "lint",
	summary = "Check interface code for Facet usage problems, and optionally strict types.",
	usage = USAGE,
	values = { "project", "solver" },
	cases = cases,
	run = run,
}

return command
