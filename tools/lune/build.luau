--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local function fail(message: string, code: number?): never
	print(message)
	return process.exit(code or 1)
end

local function run(argv: { string }, cwd: string?)
	local arguments = table.clone(argv)
	local command = table.remove(arguments, 1) :: string
	local result = process.exec(command, arguments, { stdio = "inherit", cwd = cwd })
	if not result.ok then
		process.exit(result.code)
	end
end

local function capture(argv: { string }, cwd: string?): (boolean, string)
	local arguments = table.clone(argv)
	local command = table.remove(arguments, 1) :: string
	local launched, result = pcall(process.exec, command, arguments, { cwd = cwd })
	if not launched then
		return false, ""
	end
	return result.ok, (string.gsub(result.stdout, "%s+$", ""))
end

local function parent(path: string)
	local directory = string.match(path, "^(.*)/[^/]+$")
	if directory then
		fs.writeDir(directory)
	end
end

local function rojo(project: string | { [string]: any }, output: string, scratch: string?, cwd: string?)
	parent(if cwd then `{cwd}/{output}` else output)
	if type(project) == "string" then
		return run({ "rojo", "build", project, "-o", output }, cwd)
	end
	local path = assert(scratch, "a generated project needs a scratch path")
	local written = if cwd then `{cwd}/{path}` else path
	fs.writeFile(written, serde.encode("json", project, true))
	local result = process.exec("rojo", { "build", path, "-o", output }, { stdio = "inherit", cwd = cwd })
	fs.removeFile(written)
	if not result.ok then
		process.exit(result.code)
	end
end

local function files(roots: { string }): { string }
	local found = {}
	local function walk(path: string)
		if fs.isDir(path) then
			for _, name in fs.readDir(path) do
				walk(`{path}/{name}`)
			end
		elseif fs.isFile(path) then
			table.insert(found, path)
		end
	end
	for _, root in roots do
		walk(root)
	end
	table.sort(found)
	return found
end

local function contentHash(roots: { string }, length: number): string
	local lines = {}
	for _, path in files(roots) do
		table.insert(lines, `{serde.hash("sha256", fs.readFile(path))}  {path}`)
	end
	return string.sub(serde.hash("sha256", table.concat(lines, "\n") .. "\n"), 1, length)
end

local function world(name: string, attributes: { [string]: any }?, replicated: { [string]: string }, server: boolean?)
	local storage = {}
	for key, path in replicated do
		storage[key] = { ["$path"] = path }
	end
	return {
		name = name,
		emitLegacyScripts = false,
		globIgnorePaths = { "**/*.spec.luau" },
		tree = {
			["$className"] = "DataModel",
			Lighting = {
				["$properties"] = { Technology = "Unified", LightingStyle = "Soft", PrioritizeLightingQuality = false },
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
			StarterPlayer = {},
			ServerScriptService = if server then { Outpost = { ["$path"] = "gallery/server" } } else nil,
		},
	}
end

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
local GALLERY = { Gallery = "gallery/client", Facet = "../src", FacetExamples = "gallery/examples" }
local SHOWCASE = {
	Gallery = "gallery/client",
	Facet = "../src",
	FacetExamples = "gallery/examples",
	FacetReference = "reference",
	FacetScenarios = "gallery/scenarios",
	FacetThemes = "themes",
}
local PLACE_PROJECT = "examples/.place_build.project.json"

local commands: { [string]: (arguments: { string }) -> () } = {}

function commands.places()
	local stamp = "content " .. contentHash({ "src", "examples/gallery", "examples/reference", "examples/themes" }, 12)
	local bootstrapped = {}
	for index, example in EXAMPLES do
		local attributes = { Facet_Example = index - 1 }
		local output = `examples/places/{example[2]}.rbxl`
		rojo(world(example[1], attributes, GALLERY), output, PLACE_PROJECT)
		table.insert(bootstrapped, output)
		print(`built {output} ({example[1]})`)
	end
	local showcase = "examples/places/Facet-Showcase.rbxl"
	local attributes = { Facet_Showcase = true, Facet_NativeStyle = true, Facet_Build = stamp }
	rojo(world("Facet-Showcase", attributes, SHOWCASE, true), showcase, PLACE_PROJECT)
	table.insert(bootstrapped, showcase)
	print(`built {showcase} (Facet-Showcase — in-game demo + theme switching)`)
	rojo("examples/performance.project.json", "examples/places/Facet-PerformanceLab.rbxl")
	print("built examples/places/Facet-PerformanceLab.rbxl (Facet-PerformanceLab — Step 9 performance lab)")
	local check = { "lune", "run", "tools/lune/check_place_bootstrap.luau" }
	table.move(bootstrapped, 1, #bootstrapped, #check + 1, check)
	run(check)
	rojo("examples/virtual_monitors/default.project.json", "examples/places/Facet-VirtualMonitors.rbxl")
	rojo("examples/facet_farm/default.project.json", "examples/places/Facet-Farm.rbxl")
	run({ "lune", "run", "tools/lune/check_app_places.luau" })
	local count = 0
	for _, name in fs.readDir("examples/places") do
		count += if string.match(name, "%.rbxl$") then 1 else 0
	end
	print(`done: {count} place files in examples/places/`)
end

local REFERENCE = {
	{ "ref_glade", "Facet-Ref-Glade" },
	{ "ref_cartwheel", "Facet-Ref-Cartwheel" },
	{ "ref_sipworks", "Facet-Ref-Sipworks" },
	{ "ref_foyer", "Facet-Ref-Foyer" },
}

function commands.reference()
	for _, proof in REFERENCE do
		local output = `artifacts/verify/reference-places/{proof[2]}.rbxl`
		local project = world(proof[2], { Facet_Scenario = proof[1] }, SHOWCASE)
		rojo(project, output, "examples/.reference_place_build.project.json")
		print(`built {output} ({proof[1]})`)
	end
end

local function theme(source: string, name: string, output: string)
	if not fs.isFile(source) then
		fail(`build themes: no such theme module: {source}`)
	end
	rojo({ name = name, tree = { ["$path"] = source } }, output, ".theme_build.project.json")
end

function commands.themes(arguments)
	if arguments[1] == "--one" then
		if #arguments ~= 4 then
			fail("usage: lune run tools/lune/build themes --one <source.luau> <Name> <output.rbxm>", 2)
		end
		theme(arguments[2], arguments[3], arguments[4])
		return print(`built {arguments[4]}`)
	elseif #arguments ~= 0 then
		fail(`build themes: unexpected argument '{arguments[1]}' (expected no arguments, or --one)`, 2)
	end
	local listed, listing = capture({ "lune", "run", "tools/lune/theme_artifacts", "--", "list" })
	local count = 0
	for line in string.gmatch(if listed then listing else "", "[^\n]+") do
		local module, artifact = string.match(line, "^([^\t]+)\t([^\t]+)$")
		if module and artifact then
			if fs.isDir(`examples/themes/{module}`) then
				fail(
					`build themes: examples/themes/{module}/ exists — this package now owns runtime data beside its module, and this build only maps the module. Extend the theme build before shipping it.`
				)
			end
			theme(`examples/themes/{module}.luau`, artifact, `build/themes/{artifact}.rbxm`)
			count += 1
		end
	end
	if count == 0 then
		fail("build themes: the enumerator listed no shippable packages — that is a bug, not an empty product")
	end
	run({ "lune", "run", "tools/lune/theme_artifacts", "--", "manifest", "build/themes" })
	print(`built {count} theme artifacts into build/themes/`)
end

function commands.model(arguments)
	run({ "python3", "tools/sync_compose.py", "--check" })
	local output, publisher = "build/Facet.rbxm", false
	for _, argument in arguments do
		if argument == "--publisher" then
			publisher = true
		else
			output = argument
		end
	end
	local base, extension = string.match(output, "^(.*)%.(rbxmx?)$")
	if not base then
		fail(`build model: output '{output}' must end in .rbxm or .rbxmx (rojo decides the format from the name)`, 2)
	end
	local token = `{os.time()}-{math.random(1e9)}`
	local stage = `build/.stage.{token}`
	local project = {
		name = "Facet",
		globIgnorePaths = { "**/*.spec.luau" },
		tree = { ["$path"] = "src", Distribution = { ["$path"] = `{stage}/Distribution` } },
	}
	local scratch = `.model_build.{token}.project.json`
	local built, problem = pcall(function()
		fs.writeDir("build")
		run({ "python3", "tools/package.py", "stage", "--out", stage, "--quiet" })
		local temporary = `{base}.tmp.{token}.{extension}`
		rojo(project, temporary, scratch)
		fs.move(temporary, output, true)
		local twin = `{base}.rbxmx`
		if twin ~= output then
			rojo(project, `{base}.tmp.{token}.rbxmx`, scratch)
			fs.move(`{base}.tmp.{token}.rbxmx`, twin, true)
		end
		run({
			"python3",
			"tools/package.py",
			"manifest",
			"--model",
			twin,
			"--artifact",
			output,
			"--out",
			`{base}.manifest.json`,
		})
		if publisher then
			local place = {
				name = "FacetPublisher",
				tree = {
					["$className"] = "DataModel",
					ReplicatedStorage = { ["$className"] = "ReplicatedStorage", Facet = { ["$path"] = output } },
				},
			}
			rojo(place, `build/FacetPublisher.tmp.{token}.rbxl`, `.model_build.place.{token}.project.json`)
			fs.move(`build/FacetPublisher.tmp.{token}.rbxl`, "build/FacetPublisher.rbxl", true)
			print(`built build/FacetPublisher.rbxl (publisher place, from {output})`)
		end
	end)
	if fs.isDir(stage) then
		fs.removeDir(stage)
	end
	if not built then
		fail(tostring(problem))
	end
	local version = string.match(fs.readFile("src/init.luau"), 'VERSION = "([^"]+)"')
	local modules = 0
	for _, path in files({ "src" }) do
		modules += if string.match(path, "%.luau$") and not string.match(path, "%.spec%.luau$") then 1 else 0
	end
	print(`built {output} (Facet {version}, {modules} modules)`)
end

function commands.lab()
	local lab = "examples/facet-lab"
	local outputs = { "build/Facet-Lab.rbxl", "build/Foundation-Light.rbxm", "build/Foundation-Dark.rbxm" }
	run({ "python3", "tools/check_boundary.py", outputs[1], outputs[2], outputs[3] }, lab)
	run({ "lune", "run", "tools/coverage.luau", "check" }, lab)
	run({ "lune", "run", "tools/check_themes.luau" }, lab)
	local _, revision = capture({ "git", "rev-parse", "--short=8", "HEAD" })
	local clean = capture({ "git", "diff", "--quiet", "HEAD", "--", "src", "examples", "tests" })
	local hash = contentHash({
		`{lab}/src`,
		`{lab}/themes`,
		`{lab}/default.project.json`,
		"src",
		"examples/themes",
		"examples/gallery",
		"tools/studio/live",
	}, 10)
	local stamp = `lab {hash} / facet {revision}{if clean then "" else "+dirty"}`
	local project = serde.decode("json", fs.readFile(`{lab}/default.project.json`))
	project.tree.Workspace["$attributes"] = { Facet_Build = stamp, FacetLab = true }
	rojo(project, outputs[1], ".stamped.project.json", lab)
	rojo("theme-light.project.json", outputs[2], nil, lab)
	rojo("theme-dark.project.json", outputs[3], nil, lab)
	print("built: " .. table.concat(outputs, " "))
	print("stamp: " .. stamp)
end

function commands.designer()
	rojo("tools/designer/default.project.json", "build/Facet-Design.rbxm")
	rojo("tools/designer/smoke.project.json", "build/Facet-Design-Playground.rbxl")
end

function commands.home()
	run({ "python3", "tools/sync_compose.py", "--check" })
	rojo("examples/facet_home/default.project.json", "build/Facet-Home.rbxl")
end

function commands.doctor()
	run({ "python3", "tools/sync_compose.py", "--check" })
	run({ "python3", "tools/sync_verify.py", "--check" })
	fs.writeDir("artifacts")
	fs.writeDir("build")
	local checks = {}
	local failed = false
	local function check(name: string, passed: boolean, detail: string, missing: string)
		failed = failed or not passed
		table.insert(checks, {
			name = name,
			status = if passed then "OK" else "FAIL",
			detail = if passed then detail else missing,
			required = true,
		})
	end
	local lune, luneVersion = capture({ "lune", "--version" })
	local hasRojo, rojoVersion = capture({ "rojo", "--version" })
	check("lune", lune, luneVersion, "lune not on PATH")
	check("rojo", hasRojo, rojoVersion, "rojo not on PATH")
	check("corpus", fs.isFile("tests/plan.json"), "committed Verify plan present", "tests/plan.json missing")
	check("library", fs.isFile("src/init.luau"), "native Facet entry point present", "src/init.luau missing")
	check(
		"verification",
		fs.isFile("tools/lune/gate.luau"),
		"Verify gate definition present",
		"tools/lune/gate.luau missing"
	)
	check(
		"rojo-build",
		(capture({ "rojo", "build", "examples/gallery.project.json", "-o", "build/Facet-Gallery.rbxl" })),
		"gallery place builds",
		"rojo build examples/gallery.project.json failed"
	)
	table.insert(checks, {
		name = "studio-mcp",
		status = "ENV",
		detail = "verified per-session via Studio MCP, not from shell",
		required = false,
	})
	local status = if failed then "FAIL" else "PASS"
	fs.writeFile(
		"artifacts/doctor.json",
		serde.encode(
			"json",
			{ schema = "facet-doctor/1", status = status, requirement = "UI-AGENT-001", checks = checks },
			true
		)
	)
	print(`doctor: {status} (artifacts/doctor.json)`)
	process.exit(if failed then 1 else 0)
end

local arguments = table.clone(process.args)
local command = commands[table.remove(arguments, 1) or ""]
if not command then
	fail("usage: lune run tools/lune/build <places|reference|themes|model|lab|home|designer|doctor> [arguments]", 2)
end
command(arguments)
