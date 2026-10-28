--!strict
local Verify = require("../../vendor/verify/src/core")

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local LabBoundary = require("../lib/lab_boundary")
local Model = require("../lib/model")
local PlaceChecks = require("../lib/place_checks")
local Rojo = require("../lib/rojo")
local Rule = require("../lib/rule")
local Run = require("../lib/run")
local Snapshot = require("../lib/snapshot")
local ThemeBuilds = require("../lib/theme_builds")

local USAGE = [[usage: lute run tools/facet build <target> [arguments]

targets:
  standalone                       places, reference places, consumer, showcase and performance
  places                           examples/places/*.rbxl, then the bootstrap and app place checks
  reference                        artifacts/verify/reference-places/*.rbxl
  themes                           build/themes/<Name>.rbxm and build/themes/manifest.json
  themes --one <source> <Name> <output>
                                   one theme module as one model file
  model [output] [--publisher]     build/Facet.rbxm, its .rbxmx twin and its manifest
  lab                              examples/facet-lab/build/*
  home                             build/Facet-Home.rbxl
  playground                       build/Compose-Design-Playground.rbxl]]

local EXAMPLES = {
	{ "Facet-SettingsDemo", "00_settings_demo" },
	{ "Facet-Ex01-TemperatureConverter", "01_temperature_converter" },
	{ "Facet-Ex02-PlaylistTable", "02_playlist_table" },
	{ "Facet-Ex03-SettingsSync", "03_settings_sync" },
	{ "Facet-Ex04-ConfirmDialog", "04_confirm_dialog" },
	{ "Facet-Ex05-WordGame", "05_word_game" },
	{ "Facet-Ex06-TileGame", "06_tile_game" },
	{ "Facet-Ex07-Match3", "07_match3" },
}

local GALLERY: { [string]: string } = {
	Gallery = "gallery/client",
	Facet = "../src",
	FacetExamples = "gallery/examples",
}

local SHOWCASE: { [string]: string } = {
	Gallery = "gallery/client",
	Facet = "../src",
	FacetExamples = "gallery/examples",
	FacetReference = "reference",
	FacetScenarios = "gallery/scenarios",
	FacetThemes = "themes",
}

local REFERENCE = {
	{ "ref_glade", "Facet-Ref-Glade" },
	{ "ref_cartwheel", "Facet-Ref-Cartwheel" },
	{ "ref_sipworks", "Facet-Ref-Sipworks" },
	{ "ref_foyer", "Facet-Ref-Foyer" },
}

local PLACE_PROJECT = "examples/.place_build.project.json"
local PLACE_CHECKS = "artifacts/verify/places"
local REFERENCE_PROJECT = "examples/.reference_place_build.project.json"
local LAB = "examples/facet-lab"
local LAB_OUTPUTS = { "build/Facet-Lab.rbxl", "build/Foundation-Light.rbxm", "build/Foundation-Dark.rbxm" }
local LAB_CONTENT = {
	`{LAB}/src`,
	`{LAB}/themes`,
	`{LAB}/default.project.json`,
	"src",
	"examples/themes",
	"examples/gallery",
	"tools/studio/live",
}
local PLACE_CONTENT = { "src", "examples/gallery", "examples/reference", "examples/themes" }

local function world(
	name: string,
	attributes: Json.Object,
	replicated: { [string]: string },
	server: boolean?
): Json.Object
	local storage = Json.object()
	local keys: { string } = {}
	for key in replicated do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		Json.set(storage, key, { ["$path"] = replicated[key] })
	end
	local tree: Json.Object = {
		["$className"] = "DataModel",
		Lighting = {
			["$properties"] = { Technology = "Future", LightingStyle = "Soft", PrioritizeLightingQuality = false },
		},
		Workspace = {
			["$attributes"] = attributes,
			["$properties"] = { FilteringEnabled = true, PlayerScriptsUseInputActionSystem = "Enabled" },
			Baseplate = {
				["$className"] = "Part",
				["$properties"] = {
					Anchored = true,
					Locked = true,
					Size = { 512, 20, 512 },
					Position = { 0, -10, 0 },
					Color = { 0.35, 0.37, 0.39 },
					TopSurface = "Smooth",
					BottomSurface = "Smooth",
				},
			},
			SpawnLocation = {
				["$className"] = "SpawnLocation",
				["$properties"] = {
					Anchored = true,
					Size = { 12, 1, 12 },
					Position = { 0, 0.5, 0 },
					Duration = 0,
					Neutral = true,
				},
			},
		},
		Players = { ["$properties"] = { CharacterAutoLoads = false } },
		ReplicatedStorage = storage,
		StarterGui = { ["$properties"] = { ScreenOrientation = "Sensor" } },
		StarterPlayer = Json.object(),
	}
	if server then
		tree.ServerScriptService = { Outpost = { ["$path"] = "gallery/server" } }
	end
	return {
		name = name,
		emitLegacyScripts = false,
		globIgnorePaths = { "**/*.verify.luau" },
		tree = tree,
	}
end

local function report(outcome: Rojo.Outcome): number
	if outcome.message ~= "" then
		print((string.gsub(outcome.message, "%s+$", "")))
	end
	return if outcome.ok then 0 else outcome.code
end

local function step(argv: { string }, cwd: string?): number
	local outcome = Rojo.run(argv, { cwd = cwd })
	if outcome.ok then
		return 0
	end
	return report(outcome)
end

local function rojo(project: Rojo.Project, output: string, scratch: string?, cwd: string?): number
	local outcome = Rojo.build(project, output, { scratch = scratch, cwd = cwd })
	if outcome.ok then
		return 0
	end
	return report(outcome)
end

local function snapshot(name: Snapshot.Name): number
	local ok, message = Snapshot.check(".", name)
	if message ~= "" then
		print(message)
	end
	return if ok then 0 else 1
end

local function places(): number
	local stamp = "content " .. Rojo.contentHash(".", PLACE_CONTENT, 12)
	local function inspected(project: Rojo.Project, name: string, scratch: string?, check: (string) -> string?): number
		local xml = `{PLACE_CHECKS}/{name}.rbxlx`
		local code = rojo(project, xml, scratch)
		if code ~= 0 then
			return code
		end
		local problem = check(xml)
		if problem ~= nil then
			print("FAIL " .. problem)
			return 1
		end
		print(`ok   {name}: the XML build passes its place check`)
		return 0
	end
	for index, example in EXAMPLES do
		local output = `examples/places/{example[2]}.rbxl`
		local project = world(example[1], { Facet_Example = index - 1 }, GALLERY)
		local code = rojo(project, output, PLACE_PROJECT)
		if code ~= 0 then
			return code
		end
		print(`built {output} ({example[1]})`)
		code = inspected(project, example[2], PLACE_PROJECT, PlaceChecks.bootstrap)
		if code ~= 0 then
			return code
		end
	end
	local showcase = "examples/places/Facet-Showcase.rbxl"
	local attributes: Json.Object = { Facet_Showcase = true, Facet_NativeStyle = true, Facet_Build = stamp }
	local showcaseProject = world("Facet-Showcase", attributes, SHOWCASE, true)
	local code = rojo(showcaseProject, showcase, PLACE_PROJECT)
	if code ~= 0 then
		return code
	end
	print(`built {showcase} (Facet-Showcase — in-game demo + theme switching)`)
	code = inspected(showcaseProject, "Facet-Showcase", PLACE_PROJECT, PlaceChecks.bootstrap)
	if code ~= 0 then
		return code
	end
	code = rojo("examples/performance.project.json", "examples/places/Facet-PerformanceLab.rbxl")
	if code ~= 0 then
		return code
	end
	print("built examples/places/Facet-PerformanceLab.rbxl (Facet-PerformanceLab — Step 9 performance lab)")
	for _, app in
		{
			{ name = "Facet-VirtualMonitors", folder = "virtual_monitors", root = "VirtualMonitors" },
			{ name = "Facet-Farm", folder = "facet_farm", root = "FacetFarm" },
		}
	do
		local project = `examples/{app.folder}/default.project.json`
		code = rojo(project, `examples/places/{app.name}.rbxl`)
		if code ~= 0 then
			return code
		end
		code = inspected(project, app.name, nil, function(xml: string): string?
			return PlaceChecks.app(xml, app.folder, app.root)
		end)
		if code ~= 0 then
			return code
		end
	end
	local count = 0
	for _, entry in Files.list("examples/places") do
		count += if string.match(entry.name, "%.rbxl$") then 1 else 0
	end
	print(`done: {count} place files in examples/places/`)
	return 0
end

local function reference(): number
	for _, proof in REFERENCE do
		local output = `artifacts/verify/reference-places/{proof[2]}.rbxl`
		local code = rojo(world(proof[2], { Facet_Scenario = proof[1] }, SHOWCASE), output, REFERENCE_PROJECT)
		if code ~= 0 then
			return code
		end
		print(`built {output} ({proof[1]})`)
	end
	return 0
end

local function standalone(): number
	local code = places()
	code = math.max(code, reference())
	for _, build in
		{
			{ "consumer", "examples/consumer/default.project.json" },
			{ "gallery", "examples/showcase.project.json" },
			{ "performance", "examples/performance.project.json" },
		}
	do
		print(`standalone-builds: {build[1]}`)
		code = math.max(code, rojo(build[2], `artifacts/verify/native/{build[1]}.rbxl`))
	end
	return code
end

local function themes(invocation: Cli.Invocation): number
	local arguments = invocation.positional
	if Cli.switch(invocation, "one") then
		local outcome = ThemeBuilds.one(".", arguments[2], arguments[3], arguments[4])
		if not outcome.ok then
			return report(outcome)
		end
		print(`built {arguments[4]}`)
		return 0
	end
	return report(ThemeBuilds.all("."))
end

local function model(invocation: Cli.Invocation): number
	local output = invocation.positional[2]
	local ok, message = Model.build({ output = output, publisher = Cli.switch(invocation, "publisher") })
	if message ~= "" then
		print(message)
	end
	return if ok then 0 else 1
end

local function lab(): number
	local problems = LabBoundary.check(".", LAB_OUTPUTS)
	if #problems > 0 then
		print("BOUNDARY FAIL\n  " .. table.concat(problems, "\n  "))
		return 1
	end
	print("boundary ok: repository sources, outputs in the lab build directory")
	local code = step({ Run.lute(), "run", "tools/coverage.luau", "check" }, LAB)
	if code ~= 0 then
		return code
	end
	code = step({ Run.lute(), "run", "tools/check_themes.luau" }, LAB)
	if code ~= 0 then
		return code
	end
	local revision = Run.gitOutput({ "rev-parse", "--short=8", "HEAD" }) or ""
	local clean = Run.git({ "diff", "--quiet", "HEAD", "--", "src", "examples", "tests" }).ok
	local hash = Rojo.contentHash(".", LAB_CONTENT, 10)
	local stamp = `lab {hash} / facet {revision}{if clean then "" else "+dirty"}`
	local project, problem = Json.tryDecode(Files.read(`{LAB}/default.project.json`))
	local workspace = Json.objectField(Json.field(project, "tree"), "Workspace")
	if problem ~= nil or workspace == nil then
		print(`build lab: {LAB}/default.project.json has no tree.Workspace{if problem then ": " .. problem else ""}`)
		return 1
	end
	local attributes = Json.object()
	Json.set(attributes, "Facet_Build", stamp)
	Json.set(attributes, "FacetLab", true)
	Json.set(workspace, "$attributes", attributes)
	code = rojo(Json.asObject(project) or {}, LAB_OUTPUTS[1], ".stamped.project.json", LAB)
	if code ~= 0 then
		return code
	end
	code = rojo("theme-light.project.json", LAB_OUTPUTS[2], nil, LAB)
	if code ~= 0 then
		return code
	end
	code = rojo("theme-dark.project.json", LAB_OUTPUTS[3], nil, LAB)
	if code ~= 0 then
		return code
	end
	print("built: " .. table.concat(LAB_OUTPUTS, " "))
	print("stamp: " .. stamp)
	return 0
end

local function playground(): number
	return rojo("tools/design_playground/default.project.json", "build/Compose-Design-Playground.rbxl")
end

local function home(): number
	local code = snapshot("compose")
	if code ~= 0 then
		return code
	end
	return rojo("examples/facet_home/default.project.json", "build/Facet-Home.rbxl")
end

local FLAGS: { [string]: { string } } = {
	themes = { "one" },
	model = { "publisher" },
}

local TARGETS: { [string]: (Cli.Invocation) -> number } = {
	standalone = standalone,
	places = places,
	reference = reference,
	themes = themes,
	model = model,
	lab = lab,
	home = home,
	playground = playground,
}

local function refusal(invocation: Cli.Invocation): string?
	local target = invocation.positional[1]
	if target == nil or TARGETS[target] == nil then
		return USAGE
	end
	local arguments = invocation.positional
	local unknown = Cli.unknownFlags(invocation, FLAGS[target] or {})
	if unknown ~= nil then
		return `build {target}: unknown flags {unknown}`
	elseif target == "themes" and Cli.switch(invocation, "one") then
		if #arguments ~= 4 then
			return "usage: lute run tools/facet build themes --one <source.luau> <Name> <output.rbxm>"
		end
	elseif target == "themes" and #arguments ~= 1 then
		return `build themes: unexpected argument '{arguments[2]}' (expected no arguments, or --one)`
	elseif target == "model" then
		local output = arguments[2]
		if #arguments > 2 then
			return "usage: lute run tools/facet build model [output] [--publisher]"
		elseif output ~= nil and string.match(output, "^(.*)%.(rbxmx?)$") == nil then
			return `build model: output '{output}' must end in .rbxm or .rbxmx (rojo decides the format from the name)`
		end
	elseif FLAGS[target] == nil and #arguments > 1 then
		return `build {target}: unexpected argument '{arguments[2]}'`
	end
	return nil
end

local function run(invocation: Cli.Invocation): number
	local refused = refusal(invocation)
	if refused ~= nil then
		print(refused)
		return 2
	end
	return TARGETS[invocation.positional[1]](invocation)
end

local function invocation(arguments: { string }): Cli.Invocation
	local forwarded = { "build" }
	table.move(arguments, 1, #arguments, 2, forwarded)
	return Cli.parse(forwarded)
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the content hash lists sorted slash paths with their sha256", {
		id = prefix .. "the content hash lists sorted slash paths with their sha256",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["b/z.luau"] = "z",
				["b/a/y.luau"] = "y\r\n",
				["a.json"] = "{}",
			}, function(context: Rule.Context): ()
				local lines = {
					`{Hash.sha256("{}")}  a.json`,
					`{Hash.sha256("y\r\n")}  b/a/y.luau`,
					`{Hash.sha256("z")}  b/z.luau`,
				}
				local expected = string.sub(Hash.sha256(table.concat(lines, "\n") .. "\n"), 1, 12)
				Verify.expect(Rojo.contentFiles(context.root, { "b", "a.json", "missing" }))
					:toEqual({ "a.json", "b/a/y.luau", "b/z.luau" })
				Verify.expect(Rojo.contentHash(context.root, { "b", "a.json" }, 12)):toBe(expected)
			end)
		end,
	})
	harness:case(
		prefix .. "a generated place keeps StarterPlayer an object and maps the server only for the showcase",
		{
			id = prefix .. "a generated place keeps StarterPlayer an object and maps the server only for the showcase",
			run = function(test: Verify.Context)
				local plain = Json.encode(world("Plain", { Facet_Example = 0 }, GALLERY))
				local showcase = Json.encode(world("Showcase", { Facet_Showcase = true }, SHOWCASE, true))
				Verify.expect(string.find(plain, '"StarterPlayer": {}', 1, true) ~= nil)
					:toBeTrueWith("StarterPlayer is not {}")
				Verify.expect(string.find(plain, "ServerScriptService", 1, true) == nil)
					:toBeTrueWith("a plain place maps a server")
				Verify.expect(string.find(showcase, '"Outpost": {"$path": "gallery/server"}', 1, true) ~= nil)
					:toBeTrueWith("the showcase does not map gallery/server")
				Verify.expect(string.find(plain, '"Facet": {"$path": "../src"}', 1, true) ~= nil)
					:toBeTrueWith("the gallery does not map the library")
			end,
		}
	)
	harness:case(prefix .. "an unknown target, a stray flag and a malformed --one are usage errors", {
		id = prefix .. "an unknown target, a stray flag and a malformed --one are usage errors",
		run = function(test: Verify.Context)
			local function refuses(arguments: { string }, fragment: string): ()
				local refused = refusal(invocation(arguments))
				if refused == nil then
					error(`build {table.concat(arguments, " ")} was accepted`, 0)
				end
				Verify.expect(string.find(refused, fragment, 1, true) ~= nil)
					:toBeTrueWith(`build {table.concat(arguments, " ")} refused with '{refused}'`)
			end
			local function accepts(arguments: { string }): ()
				local refused = refusal(invocation(arguments))
				Verify.expect(refused == nil)
					:toBeTrueWith(`build {table.concat(arguments, " ")} was refused: {refused}`)
			end
			refuses({}, "usage: lute run tools/facet build <target>")
			refuses({ "everything" }, "usage: lute run tools/facet build <target>")
			refuses({ "lab", "--publisher" }, "unknown flags --publisher")
			refuses({ "home", "extra" }, "unexpected argument 'extra'")
			refuses({ "themes", "--one", "a.luau" }, "--one <source.luau> <Name> <output.rbxm>")
			refuses({ "themes", "extra" }, "expected no arguments, or --one")
			refuses({ "model", "build/Facet.zip" }, "must end in .rbxm or .rbxmx")
			refuses({ "model", "a.rbxm", "b.rbxm" }, "build model [output] [--publisher]")
			accepts({ "themes" })
			accepts({ "themes", "--one", "a.luau", "A", "a.rbxm" })
			accepts({ "model" })
			accepts({ "model", "build/Other.rbxmx", "--publisher" })
		end,
	})
	harness:case(prefix .. "a missing theme module is refused before rojo runs", {
		id = prefix .. "a missing theme module is refused before rojo runs",
		run = function(test: Verify.Context)
			local outcome = ThemeBuilds.one(".", "examples/themes/does_not_exist.luau", "Missing", "build/x.rbxm")
			Verify.expect(not outcome.ok):toBeTrueWith("the missing module was accepted")
			Verify.expect(string.find(outcome.message, "no such theme module", 1, true) ~= nil)
				:toBeTrueWith("the refusal does not name the module")
		end,
	})
	harness:case(prefix .. "the theme enumerator listing parses module and artifact columns", {
		id = prefix .. "the theme enumerator listing parses module and artifact columns",
		run = function(test: Verify.Context)
			local listed = ThemeBuilds.parseListing("classic_desktop\tClassicDesktop\r\nnoise\n\nscifi_hud\tScifiHud\n")
			Verify.expect(#listed):toBe(2)
			Verify.expect(listed[1] and listed[1].artifact):toBe("ClassicDesktop")
			Verify.expect(listed[2] and listed[2].module):toBe("scifi_hud")
		end,
	})
	LabBoundary.register(harness, prefix .. "lab boundary: ")
end

local command: Cli.Command = {
	name = "build",
	summary = "Build places, reference places, themes, the model, the lab, home, or the design playground.",
	usage = USAGE,
	register = register,
	run = run,
}

return command
