--!strict
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Lute = require("../../vendor/verify/src/lute")
local Rule = require("../lib/rule")
local Run = require("../lib/run")
local Strip = require("../lib/strip")
local ThemeBuilds = require("../lib/theme_builds")

type Plant = {
	label: string,
	artifact: string,
	module: string,
	anchor: string?,
	replacement: string,
	expect: string,
}

type Options = {
	plant: Plant?,
	keep: boolean?,
	quiet: boolean?,
}

local COPIED_TREES = { "src", "tools/vendor/verify" }
local COPIED_FILES = {
	"rokit.toml",
	"tests/lib/native_engine.luau",
	"tests/lib/loader.luau",
	"tools/engine/theme_artifact_probe.luau",
}
local PROBE = { "lute", "run", "tools/engine/theme_artifact_probe.luau" }

local PLANTS: { Plant } = {
	{
		label = "a package that reaches into examples/ (the gallery's theme picker)",
		artifact = "ClassicDesktop",
		module = "classic_desktop",
		anchor = "local classic_desktop = {}",
		replacement = 'local picker = require("../../examples/gallery/client/theme_picker")\nlocal classic_desktop = {}',
		expect = "calls require()",
	},
	{
		label = "an artifact whose identity stamp drifted from the manifest",
		artifact = "ScifiHud",
		module = "scifi_hud",
		anchor = 'version = "1.0.0"',
		replacement = 'version = "9.9.9"',
		expect = "artifact version",
	},
	{
		label = "an artifact that lost its package body",
		artifact = "PixelQuest",
		module = "pixel_quest",
		anchor = nil,
		replacement = "-- (emptied)\nreturn {}\n",
		expect = "PixelQuest",
	},
	{
		label = "a package whose semantic palette has unreadable text",
		artifact = "ClassicDesktop",
		module = "classic_desktop",
		anchor = "content = rgb(24, 24, 24)",
		replacement = "content = rgb(212, 208, 200)",
		expect = "ClassicDesktop",
	},
}

local function replaceAll(source: string, anchor: string, replacement: string): string
	local parts: { string } = {}
	local cursor = 1
	while true do
		local start, finish = string.find(source, anchor, cursor, true)
		if start == nil or finish == nil then
			break
		end
		table.insert(parts, string.sub(source, cursor, start - 1))
		table.insert(parts, replacement)
		cursor = finish + 1
	end
	table.insert(parts, string.sub(source, cursor))
	return table.concat(parts)
end

local function planted(plant: Plant, name: string, source: string): string
	if name ~= plant.artifact then
		return source
	end
	local anchor = plant.anchor
	if anchor == nil then
		return plant.replacement
	end
	return replaceAll(source, anchor, plant.replacement)
end

local function artifactSource(document: string, name: string, problems: { string }): string?
	local parsed, read: unknown = pcall(Lute.model.read, document)
	if not parsed then
		table.insert(problems, `{name}: the artifact is not readable XML: {tostring(read)}`)
		return nil
	end
	local items = read :: { Lute.ModelInstance }
	if #items ~= 1 then
		table.insert(problems, `{name}: the artifact holds {#items} root objects, expected exactly 1`)
		return nil
	end
	local item = items[1]
	if item.className ~= "ModuleScript" then
		table.insert(problems, `{name}: the artifact's root is a {item.className}, not a ModuleScript`)
		return nil
	end
	if #item.children > 0 then
		table.insert(
			problems,
			`{name}: the artifact's ModuleScript has {#item.children} children — this package grew runtime data and lute run tools/facet build themes has not been taught to map it`
		)
		return nil
	end
	local named = item.properties.Name
	local source = item.properties.Source
	if named == nil or named.value ~= name then
		table.insert(
			problems,
			`{name}: the artifact's ModuleScript is named '{if named ~= nil then named.value else "nil"}'`
		)
	end
	if source == nil or string.match(source.value, "^%s*$") ~= nil then
		table.insert(problems, `{name}: the artifact carries no Source — a consumer would install an empty module`)
		return nil
	end
	return source.value
end

local function requireLines(code: string): { number }
	local lines: { number } = {}
	local cursor = 1
	while true do
		local start = string.find(code, "require%s*[({\"']", cursor)
		if start == nil then
			break
		end
		local before = if start > 1 then string.sub(code, start - 1, start - 1) else ""
		if string.match(before, "[%w_]") == nil then
			local _, count = string.gsub(string.sub(code, 1, start - 1), "\n", "")
			table.insert(lines, count + 1)
		end
		cursor = start + 1
	end
	return lines
end

local function requireProblems(name: string, source: string): { string }
	local code = Strip.luau(source) or source
	local problems: { string } = {}
	for _, line in requireLines(code) do
		table.insert(
			problems,
			`{name}: the artifact's code calls require() at line ~{line}. A theme package is data handed the \`themes\` table by its caller; a require is a dependency the artifact cannot carry, and a consumer installing it alone would fail at that line`
		)
	end
	return problems
end

local function measure(context: Rule.Context, entry: unknown, index: number, problems: { string }): boolean
	local name = Json.stringField(entry, "artifact")
	local file = Json.stringField(entry, "file")
	local module = Json.stringField(entry, "module")
	if name == nil or file == nil or module == nil then
		table.insert(problems, `manifest entry {index} lacks its artifact, file or module`)
		return false
	end
	local path = context.path(file)
	if not Files.isFile(path) then
		table.insert(problems, `{name}: {file} was not built`)
		return false
	end
	local recorded = Json.numberField(entry, "bytes")
	local size = Files.size(path)
	if recorded ~= size then
		table.insert(
			problems,
			`{name}: the manifest records {tostring(recorded)} bytes and the artifact on disk is {size} — the manifest describes a different build`
		)
	end
	return true
end

local function isolate(context: Rule.Context, work: string)
	for _, tree in COPIED_TREES do
		Files.copyTree(context.path(tree), Files.join(work, tree))
	end
	for _, relative in COPIED_FILES do
		Files.copy(context.path(relative), Files.join(work, relative))
	end
	Files.makeDirectory(Files.join(work, "installed"))
end

local function install(context: Rule.Context, work: string, manifest: unknown, options: Options): { string }
	local problems: { string } = {}
	isolate(context, work)
	local installed = Files.join(work, "installed")
	local packages: Json.Array = Json.arrayField(manifest, "packages") or {}
	for index, entry in packages do
		if not measure(context, entry, index, problems) then
			continue
		end
		local name = Json.stringField(entry, "artifact") or ""
		local module = Json.stringField(entry, "module") or ""
		local document = Files.join(work, `{name}.rbxmx`)
		local built = ThemeBuilds.one(context.root, `examples/themes/{module}.luau`, name, document, true)
		if not built.ok then
			table.insert(
				problems,
				`{name}: rojo could not build the isolated artifact: {stringext.trim(built.message)}`
			)
			continue
		end
		local source = artifactSource(Files.read(document), name, problems)
		if source == nil then
			continue
		end
		local plant = options.plant
		if plant ~= nil then
			source = planted(plant, name, source)
		end
		for _, problem in requireProblems(name, source) do
			table.insert(problems, problem)
		end
		Files.write(Files.join(installed, `{name}.luau`), source)
	end
	Files.write(Files.join(installed, "expected.json"), Json.encode(manifest))
	local probe = Run.capture(PROBE, { cwd = work })
	if probe.ok then
		if not options.quiet then
			print(stringext.trim(probe.stdout))
		end
	else
		for _, line in Files.lines(stringext.trim(probe.stdout .. probe.stderr)) do
			if stringext.trim(line) ~= "" then
				table.insert(problems, "probe: " .. stringext.trim(line))
			end
		end
		if probe.stdout == "" and probe.stderr == "" then
			table.insert(problems, ("probe: exited %d without output"):format(probe.code))
		end
	end
	return problems
end

local function inspect(context: Rule.Context, options: Options): { string }
	for _, relative in COPIED_FILES do
		if not Files.isFile(context.path(relative)) then
			return { `{relative} is missing; the isolated probe tree needs it` }
		end
	end
	local built = ThemeBuilds.all(context.root, true)
	if not built.ok then
		return { "lute run tools/facet build themes failed: " .. stringext.trim(built.message) }
	end
	local manifestPath = context.path(ThemeBuilds.MANIFEST)
	if not Files.isFile(manifestPath) then
		return { `{ThemeBuilds.MANIFEST} was not written by the theme build` }
	end
	local manifest, problem = Json.tryDecode(Files.read(manifestPath))
	if problem ~= nil or Json.arrayField(manifest, "packages") == nil then
		return { `{ThemeBuilds.MANIFEST} has no packages list{if problem then ": " .. problem else ""}` }
	end
	local work = Files.temporaryDirectory("facet-theme-artifacts-")
	local ran, result = pcall(install, context, work, manifest, options)
	if options.keep then
		print(`kept the isolated tree at {work}`)
	else
		Files.remove(work)
	end
	if not ran then
		return { "the check raised: " .. tostring(result) }
	end
	return result
end

local function check(context: Rule.Context): { string }
	return inspect(context, {})
end

local function plantedSelftest(context: Rule.Context): (boolean, { string })
	local lines: { string } = {}
	local clean = inspect(context, { quiet = true })
	if #clean > 0 then
		table.insert(lines, "SELFTEST FAILED: the unplanted tree is already red:")
		for _, problem in clean do
			table.insert(lines, "  - " .. problem)
		end
		return false, lines
	end
	table.insert(lines, "  selftest control: the unplanted tree passes")
	local passed = true
	for _, plant in PLANTS do
		local problems = inspect(context, { plant = plant, quiet = true })
		local matched: { string } = {}
		for _, problem in problems do
			if string.find(problem, plant.expect, 1, true) ~= nil then
				table.insert(matched, problem)
			end
		end
		table.insert(lines, `  [{if #matched > 0 then "BITES" else "MISSED"}] {plant.label}`)
		local shown = if #matched > 0 then matched else problems
		for index = 1, math.min(2, #shown) do
			table.insert(lines, "      -> " .. shown[index])
		end
		if #matched == 0 then
			passed = false
		end
	end
	return passed, lines
end

local function selftest(context: Rule.Context, _invocation: Cli.Invocation): number
	print("theme-artifacts planted selftest")
	local passed, lines = plantedSelftest(context)
	for _, line in lines do
		print(line)
	end
	print(`theme-artifacts planted selftest: {if passed then "PASS" else "FAIL"} ({#PLANTS} plants)`)
	return if passed then 0 else 1
end

local function keep(context: Rule.Context, _invocation: Cli.Invocation): number
	local findings = inspect(context, { keep = true })
	print(("theme-artifacts: %d findings"):format(#findings))
	for _, finding in findings do
		print("  " .. finding)
	end
	return if #findings == 0 then 0 else 1
end

local function artifact(name: string, properties: string, extra: string?): string
	return `<roblox version="4"><Item class="ModuleScript" referent="0"><Properties><string name="Name">{name}</string>{properties}</Properties>{extra or ""}</Item></roblox>`
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "a single named ModuleScript with Source is accepted", {
		id = prefix .. "a single named ModuleScript with Source is accepted",
		run = function(test: Verify.Context)
			local problems: { string } = {}
			local source = artifactSource(
				artifact(
					"ClassicDesktop",
					'<ProtectedString name="Source"><![CDATA[return { build = 1 }\n]]></ProtectedString>'
				),
				"ClassicDesktop",
				problems
			)
			Verify.expect(problems):toEqual({})
			Verify.expect(source):toBe("return { build = 1 }\n")
		end,
	})
	harness:case(
		prefix .. "a second root, a Folder root, child objects, a wrong name and an empty Source are refused",
		{
			id = prefix .. "a second root, a Folder root, child objects, a wrong name and an empty Source are refused",
			run = function(test: Verify.Context)
				local source = '<ProtectedString name="Source"><![CDATA[return {}]]></ProtectedString>'
				local samples = {
					{
						`<roblox><Item class="ModuleScript"></Item><Item class="ModuleScript"></Item></roblox>`,
						"holds 2 root objects",
					},
					{ `<roblox><Item class="Folder"></Item></roblox>`, "root is a Folder, not a ModuleScript" },
					{
						artifact("Theme", source, '<Item class="Folder"><Properties></Properties></Item>'),
						"has 1 children",
					},
					{ artifact("Other", source), "ModuleScript is named 'Other'" },
					{
						artifact("Theme", '<ProtectedString name="Source"><![CDATA[  \n]]></ProtectedString>'),
						"carries no Source",
					},
					{ artifact("Theme", ""), "carries no Source" },
				}
				for _, sample in samples do
					local problems: { string } = {}
					artifactSource(sample[1], "Theme", problems)
					if not Rule.contains(problems, sample[2]) then
						error(`expected '{sample[2]}', got {Rule.describe(problems)}`, 0)
					end
				end
			end,
		}
	)
	harness:case(prefix .. "require calls in code are reported by line and comments and longer names are ignored", {
		id = prefix .. "require calls in code are reported by line and comments and longer names are ignored",
		run = function(test: Verify.Context)
			local source = table.concat({
				"--!strict",
				"-- require('commented')",
				'local picker = require("../../examples/gallery/client/theme_picker")',
				"local requirement = 1",
				"local my_require = function() end",
				"local other = require 'quoted'",
				'--[[ require("block") ]]',
				"return {}",
			}, "\n")
			local problems = requireProblems("ClassicDesktop", source)
			Verify.expect(#problems):toBe(2)
			Verify.expect(Rule.contains(problems, "require() at line ~3.")):toBeTrueWith(Rule.describe(problems))
			Verify.expect(Rule.contains(problems, "require() at line ~6.")):toBeTrueWith(Rule.describe(problems))
		end,
	})
	harness:case(prefix .. "a missing artifact and a size that drifted from the manifest are reported", {
		id = prefix .. "a missing artifact and a size that drifted from the manifest are reported",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["build/themes/Drifted.rbxm"] = "abc",
			}, function(context: Rule.Context): ()
				local problems: { string } = {}
				local drifted = Json.decode(
					'{"artifact": "Drifted", "module": "drifted", "file": "build/themes/Drifted.rbxm", "bytes": 5}'
				)
				local missing = Json.decode(
					'{"artifact": "Missing", "module": "missing", "file": "build/themes/Missing.rbxm", "bytes": 5}'
				)
				local kept = measure(context, drifted, 1, problems)
				local skipped = measure(context, missing, 2, problems)
				Verify.expect(kept):toBeTrueWith("a drifted artifact was skipped")
				Verify.expect(not skipped):toBeTrueWith("a missing artifact was inspected")
				Verify.expect(problems):toEqual({
					"Drifted: the manifest records 5 bytes and the artifact on disk is 3 — the manifest describes a different build",
					"Missing: build/themes/Missing.rbxm was not built",
				})
			end)
		end,
	})
	harness:case(prefix .. "every planted fault still finds its anchor in the shipped theme source", {
		id = prefix .. "every planted fault still finds its anchor in the shipped theme source",
		run = function(test: Verify.Context)
			for _, plant in PLANTS do
				local path = `examples/themes/{plant.module}.luau`
				if not Files.isFile(path) then
					error(`{path} is missing`, 0)
				end
				local source = Files.text(path)
				local changed = planted(plant, plant.artifact, source)
				if changed == source then
					error(`the plant '{plant.label}' no longer changes {path}`, 0)
				end
				if planted(plant, "Other", source) ~= source then
					error(`the plant '{plant.label}' changes another artifact`, 0)
				end
			end
		end,
	})
	harness:case(prefix .. "the shipped artifacts pass the probe and every planted fault bites", {
		id = prefix .. "the shipped artifacts pass the probe and every planted fault bites",
		run = function(test: Verify.Context)
			local passed, lines = plantedSelftest(Rule.context("."))
			if passed then
				return
			end
			Verify.expect(table.concat(lines, "\n")):toBeNil()
		end,
		tags = { "tier:full" },
	})
	harness:case(prefix .. "the planted require is the only require the stripped plant adds", {
		id = prefix .. "the planted require is the only require the stripped plant adds",
		run = function(test: Verify.Context)
			local plant = PLANTS[1]
			local source = "--!strict\nlocal classic_desktop = {}\nreturn classic_desktop\n"
			local problems = requireProblems(plant.artifact, planted(plant, plant.artifact, source))
			Verify.expect(#problems):toBe(1)
			Verify.expect(Rule.contains(problems, "line ~2.")):toBeTrueWith(Rule.describe(problems))
		end,
	})
end

local rule: Rule.Rule = {
	name = "theme-artifacts",
	summary = "Each shipped theme artifact installs and mounts against a bare library surface.",
	check = check,
	register = register,
	actions = {
		planted = {
			summary = "build and probe the real artifacts with each planted fault (needs rojo and lute)",
			run = selftest,
		},
		keep = {
			summary = "run the check and keep the isolated probe tree on disk",
			run = keep,
		},
	},
}

return rule
