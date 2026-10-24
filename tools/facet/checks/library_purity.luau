--!strict
local Verify = require("../../vendor/verify/src/core")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Luau = require("../lib/luau")
local Model = require("../lib/model")
local Rule = require("../lib/rule")

type Theme = { module: string, names: { string } }

type Pattern = { module: string, name: string, bounded: boolean }

type Inspection = {
	root: string,
	source: string?,
	themes: string,
	model: string?,
	build: boolean,
}

local NEUTRAL_ID = "facet-neutral"
local EXAMPLE_PATHS: { string } = { "examples/themes", "examples/gallery", "examples/performance" }
local MODEL_LABEL = "build/Facet.rbxm"
local PLANT_TARGET = "ui/themes.luau"
local FULL: { string } = { "tier:full" }

local stripped: { [string]: string } = {}

local function code(source: string): (string?, string?)
	local cached = stripped[source]
	if cached ~= nil then
		return cached, nil
	end
	local parsed, problem = Luau.parse(source)
	if parsed == nil then
		return nil, problem or "the source does not parse"
	end
	local result = Luau.code(source, parsed)
	stripped[source] = result
	return result, nil
end

local function vocabulary(themes: string): { Theme }
	local found: { Theme } = {}
	for _, entry in Files.list(themes) do
		if string.sub(entry.name, -5) ~= ".luau" or not Files.isFile(Files.join(themes, entry.name)) then
			continue
		end
		local module = string.sub(entry.name, 1, -6)
		local source = Files.read(Files.join(themes, entry.name))
		local unique: { [string]: boolean } = { [module] = true }
		for _, pattern in { '%.id%s*=%s*"([^"]+)"', '%.displayName%s*=%s*"([^"]+)"' } do
			local name = string.match(source, pattern)
			if name ~= nil then
				unique[name] = true
			end
		end
		local names: { string } = {}
		for name in unique do
			table.insert(names, name)
		end
		table.sort(names)
		table.insert(found, { module = module, names = names })
	end
	return found
end

local function patternsFor(themes: { Theme }): { Pattern }
	local patterns: { Pattern } = {}
	for _, theme in themes do
		for _, name in theme.names do
			table.insert(patterns, { module = theme.module, name = name, bounded = true })
		end
	end
	for _, path in EXAMPLE_PATHS do
		table.insert(patterns, { module = path, name = path, bounded = false })
	end
	return patterns
end

local function wordByte(byte: number?): boolean
	if byte == nil then
		return false
	end
	return (byte >= 48 and byte <= 57)
		or (byte >= 65 and byte <= 90)
		or (byte >= 97 and byte <= 122)
		or byte == 95
		or byte == 45
end

local function hits(text: string, pattern: Pattern): { number }
	local found: { number } = {}
	local init = 1
	while true do
		local start, finish = string.find(text, pattern.name, init, true)
		if start == nil or finish == nil then
			break
		end
		local bounded = not pattern.bounded
			or (not wordByte(string.byte(text, start - 1)) and not wordByte(string.byte(text, finish + 1)))
		if bounded then
			table.insert(found, start)
			init = finish + 1
		else
			init = start + 1
		end
	end
	return found
end

local function scanText(label: string, source: string, patterns: { Pattern }, problems: { string })
	local text, problem = code(source)
	if text == nil then
		table.insert(problems, ("%s: cannot separate code from comments: %s"):format(label, problem or "unknown"))
		return
	end
	for _, pattern in patterns do
		for _, start in hits(text, pattern) do
			table.insert(
				problems,
				("%s:%d: the shipped library names '%s' in CODE. The library is facet-neutral and '%s' is an optional artifact a consumer may never have installed — say what the rule IS, or move the mention into a comment, where a measured story belongs"):format(
					label,
					Luau.lineOf(text, start),
					pattern.name,
					pattern.module
				)
			)
		end
	end
end

local function scanSources(root: string, patterns: { Pattern }, problems: { string })
	local prefix = Files.name((string.gsub(Files.normalize(root), "/+$", "")))
	for _, relative in Files.walk(root) do
		if string.sub(relative, -5) == ".luau" then
			scanText(prefix .. "/" .. relative, Files.read(Files.join(root, relative)), patterns, problems)
		end
	end
end

local function packageStamps(text: string): { [string]: boolean }
	local found: { [string]: boolean } = {}
	for id in string.gmatch(text, '%f[%w_]identity%.id%s*=%s*"([^"]+)"') do
		found[id] = true
	end
	local init = 1
	local length = #text
	while true do
		local start, finish = string.find(text, "%f[%w_]identity%s*=%s*{", init)
		if start == nil or finish == nil then
			break
		end
		local depth = 0
		local index = finish
		while index <= length do
			local byte = string.byte(text, index)
			if byte == 123 then
				depth += 1
			elseif byte == 125 then
				depth -= 1
				if depth == 0 then
					break
				end
			end
			index += 1
		end
		local region = string.sub(text, finish + 1, math.min(index, length))
		local field = string.match(region, '%f[%w_]id%s*=%s*"([^"]+)"')
		if field ~= nil then
			found[field] = true
		end
		init = finish + 1
	end
	return found
end

local function scanModel(text: string, patterns: { Pattern }, problems: { string })
	local stamps: { [string]: boolean } = {}
	local scripts = Model.scripts(text)
	for _, script in scripts do
		scanText(MODEL_LABEL .. ":" .. script.name, script.source, patterns, problems)
		local stripped = code(script.source)
		if stripped ~= nil then
			for stamp in packageStamps(stripped) do
				stamps[stamp] = true
			end
		end
	end
	local extra: { string } = {}
	for stamp in stamps do
		if stamp ~= NEUTRAL_ID then
			table.insert(extra, stamp)
		end
	end
	table.sort(extra)
	if not stamps[NEUTRAL_ID] then
		table.insert(
			problems,
			("%s: the model carries no '%s' package stamp at all — either the neutral package left the library or this check is looking at the wrong artifact"):format(
				MODEL_LABEL,
				NEUTRAL_ID
			)
		)
	end
	for _, slug in extra do
		table.insert(
			problems,
			("%s: the model stamps a second package, '%s'. Facet Neutral is the only theme the library ships; every other package is its own artifact under build/themes/"):format(
				MODEL_LABEL,
				slug
			)
		)
	end
end

local function inspect(options: Inspection): { string }
	local problems: { string } = {}
	if not Files.isDirectory(options.themes) then
		table.insert(
			problems,
			("%s is missing, so the reference package vocabulary cannot be derived"):format(options.themes)
		)
		return problems
	end
	local patterns = patternsFor(vocabulary(options.themes))
	local source = options.source
	if source ~= nil then
		scanSources(source, patterns, problems)
	end
	local model = options.model
	if model ~= nil then
		scanModel(model, patterns, problems)
	elseif options.build then
		local work = Files.temporaryDirectory("facet-purity-")
		local output = Files.join(work, "Facet.rbxmx")
		local built, message = Model.build({ output = output, root = options.root })
		if built then
			scanModel(Files.read(output), patterns, problems)
		else
			table.insert(problems, "the model build failed: " .. message)
		end
		Files.remove(work)
	end
	return problems
end

local function inspection(context: Rule.Context, build: boolean): Inspection
	return {
		root = context.root,
		source = context.path("src"),
		themes = context.path("examples/themes"),
		build = build,
	}
end

local function printVocabulary(context: Rule.Context): number
	local themes = context.path("examples/themes")
	if not Files.isDirectory(themes) then
		print(("library-purity: %s is missing"):format(themes))
		return 1
	end
	print("library-purity forbids these identifiers in the library's CODE (comments exempt):")
	for _, theme in vocabulary(themes) do
		print(("  %s: %s"):format(theme.module, table.concat(theme.names, ", ")))
	end
	print("  plus any of: " .. table.concat(EXAMPLE_PATHS, ", "))
	print(("  ...and the only package stamp the model may carry is '%s'."):format(NEUTRAL_ID))
	return 0
end

local function cdata(text: string): string
	local escaped = string.gsub(text, "%]%]>", "]]]]><![CDATA[>")
	return "<![CDATA[" .. escaped .. "]]>"
end

local function syntheticModel(themesSource: string, stamp: boolean): string
	local neutral = if stamp then themesSource else 'return { name = "plain" }\n'
	return table.concat({
		'<roblox version="4">',
		'  <Item class="ModuleScript" referent="RBX0">',
		"    <Properties>",
		'      <string name="Name">Facet</string>',
		'      <string name="Source">' .. cdata("--!strict\nreturn {}\n") .. "</string>",
		"    </Properties>",
		'    <Item class="Folder" referent="RBX1">',
		"      <Properties>",
		'        <string name="Name">ui</string>',
		"      </Properties>",
		'      <Item class="ModuleScript" referent="RBX2">',
		"        <Properties>",
		'          <string name="Name">themes</string>',
		'          <string name="Source">' .. cdata(neutral) .. "</string>",
		"        </Properties>",
		"      </Item>",
		"    </Item>",
		"  </Item>",
		"</roblox>",
		"",
	}, "\n")
end

local function withSourceCopy(test: Verify.Context, plant: (string) -> string, body: ({ string }) -> ())
	local work = Files.temporaryDirectory("facet-purity-selftest-")
	test:defer(function()
		Files.remove(work)
	end)
	local copy = Files.join(work, "src")
	Files.copyTree("src", copy)
	local target = Files.join(copy, PLANT_TARGET)
	Verify.expect(Files.isFile(target)):toBeTrueWith("the plant target src/" .. PLANT_TARGET .. " does not exist")
	Files.write(target, plant(Files.read(target)))
	body(inspect({ root = ".", source = copy, themes = "examples/themes", build = false }))
end

local function matching(problems: { string }, fragment: string): { string }
	local found: { string } = {}
	for _, problem in problems do
		if string.find(problem, fragment, 1, true) ~= nil then
			table.insert(found, problem)
		end
	end
	return found
end

local function bites(problems: { string }, fragment: string)
	Verify.expect(table.concat(problems, "\n")):toContain(fragment)
end

local function exempt(problems: { string }, fragment: string)
	Verify.expect(matching(problems, fragment)):toEqual({})
end

local function afterFirstLine(source: string, line: string): string
	local newline = string.find(source, "\n", 1, true)
	if newline == nil then
		return line .. "\n" .. source
	end
	return string.sub(source, 1, newline) .. line .. "\n" .. string.sub(source, newline + 1)
end

local function themesText(): string
	return Files.text(Files.join("src", PLANT_TARGET))
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the library sources are clean", {
		id = prefix .. "the library sources are clean",
		run = function(test: Verify.Context): ()
			local problems = inspect({ root = ".", source = "src", themes = "examples/themes", build = false })
			Verify.expect(#problems == 0):toBeTrueWith("src/ is already red: " .. Rule.describe(problems))
		end,
		tags = FULL,
	})
	harness:case(prefix .. "a require of a reference package in src/ bites", {
		id = prefix .. "a require of a reference package in src/ bites",
		run = function(test: Verify.Context): ()
			withSourceCopy(test, function(source: string): string
				return 'local ornate = require("../../examples/themes/fantasy_ornate")\n' .. source
			end, function(problems: { string }): ()
				bites(problems, "names 'fantasy_ornate' in CODE")
				return
			end)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "a package id inside a diagnostic string bites", {
		id = prefix .. "a package id inside a diagnostic string bites",
		run = function(test: Verify.Context): ()
			withSourceCopy(test, function(source: string): string
				return afterFirstLine(source, 'local HINT = "copy the pixel-quest package and edit it"')
			end, function(problems: { string }): ()
				bites(problems, "names 'pixel-quest' in CODE")
				return
			end)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "a package id inside a comment is exempt", {
		id = prefix .. "a package id inside a comment is exempt",
		run = function(test: Verify.Context): ()
			withSourceCopy(test, function(source: string): string
				return "-- measured live under fantasy-ornate at 1.5x: the frame did not move\n" .. source
			end, function(problems: { string }): ()
				exempt(problems, "fantasy-ornate")
				return
			end)
		end,
		tags = FULL,
	})
	harness:case(prefix .. "the pristine model carries only the neutral stamp", {
		id = prefix .. "the pristine model carries only the neutral stamp",
		run = function(test: Verify.Context): ()
			local problems = inspect({
				root = ".",
				themes = "examples/themes",
				model = syntheticModel(themesText(), true),
				build = false,
			})
			Verify.expect(#problems == 0):toBeTrueWith("the pristine model is red: " .. Rule.describe(problems))
		end,
	})
	harness:case(prefix .. "a second package stamp in the built model bites", {
		id = prefix .. "a second package stamp in the built model bites",
		run = function(test: Verify.Context): ()
			local model = syntheticModel(themesText(), true)
			local anchor = '<string name="Source">'
			local start, finish = string.find(model, anchor, 1, true)
			if start == nil or finish == nil then
				error("the synthetic model has no Source property", 0)
			end
			local planted = string.sub(model, 1, finish)
				.. 'local bundled = { identity = { id = "another-shipped-theme" } }\n'
				.. string.sub(model, finish + 1)
			local problems = inspect({
				root = ".",
				themes = "examples/themes",
				model = planted,
				build = false,
			})
			bites(problems, "stamps a second package, 'another-shipped-theme'")
		end,
	})
	harness:case(prefix .. "a model without the neutral stamp is refused", {
		id = prefix .. "a model without the neutral stamp is refused",
		run = function(test: Verify.Context): ()
			local problems = inspect({
				root = ".",
				themes = "examples/themes",
				model = syntheticModel("", false),
				build = false,
			})
			bites(problems, "carries no 'facet-neutral' package stamp")
		end,
	})
	harness:case(prefix .. "the vocabulary is each module with its id and display name", {
		id = prefix .. "the vocabulary is each module with its id and display name",
		run = function(test: Verify.Context): ()
			Rule.within(test, {
				["examples/themes/sample_theme.luau"] = 'local package = {}\npackage.id = "sample-theme"\npackage.displayName = "Sample Theme"\nreturn package\n',
				["examples/themes/notes.md"] = "sample_theme\n",
				["src/init.luau"] = 'local label = "Sample Theme"\n-- sample-theme in a comment\nreturn label\n',
			}, function(context: Rule.Context): ()
				local themes = vocabulary(context.path("examples/themes"))
				if #themes ~= 1 then
					error(("expected one theme, got %d"):format(#themes), 0)
				end
				local names = table.concat(themes[1].names, " | ")
				if names ~= "Sample Theme | sample-theme | sample_theme" then
					error("the vocabulary reads " .. names, 0)
				end
				local problems = inspect(inspection(context, false))
				if #problems ~= 1 or string.find(problems[1], "src/init.luau:1:", 1, true) == nil then
					error("expected exactly the line 1 string finding, got: " .. Rule.describe(problems), 0)
				end
				return
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "library-purity",
	summary = "src/ and the built model name no reference theme package in code.",
	check = function(context: Rule.Context): { string }
		return inspect(inspection(context, true))
	end,
	register = register,
}

local actions: { [string]: Rule.Action } = {
	vocabulary = {
		summary = "Print the forbidden vocabulary.",
		run = function(context: Rule.Context, _invocation: Cli.Invocation): number
			return printVocabulary(context)
		end,
	},
	["skip-build"] = {
		summary = "Scan src/ only, without building the model.",
		run = function(context: Rule.Context, _invocation: Cli.Invocation): number
			return Rule.report(rule, inspect(inspection(context, false)))
		end,
	},
}

rule.actions = actions

return rule
