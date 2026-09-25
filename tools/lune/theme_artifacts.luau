--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Facet = require("../../src") :: any
local theme_packages = require("./theme_packages")
local themes = Facet.themes

local argv: { string } = {}
for _, arg in process.args do
	if arg ~= "--" then
		table.insert(argv, arg)
	end
end

local mode = argv[1]
local outDir = argv[2] or "build/themes"

local function fail(message: string, ...: string): never
	stdio.ewrite(`theme_artifacts: {message}\n`)
	for _, path in { ... } do
		if fs.isFile(path) then
			fs.removeFile(path)
			stdio.ewrite(`theme_artifacts: removed {path} — a refused build must not leave an artifact behind\n`)
		end
	end
	process.exit(1)
end

if mode == "list" then
	for _, name in theme_packages.shippable() do
		print(`{name}\t{theme_packages.artifactName(name)}`)
	end
	return nil
end

if mode ~= "manifest" then
	print("usage: lune run tools/lune/theme_artifacts -- list | manifest [<dir>]")
	fail("unknown mode")
end

local MODULES: { [string]: any } = {
	classic_desktop = require("../../examples/themes/classic_desktop"),
	glossy_mobile = require("../../examples/themes/glossy_mobile"),
	scifi_hud = require("../../examples/themes/scifi_hud"),
	fantasy_parchment = require("../../examples/themes/fantasy_parchment"),
	fantasy_ornate = require("../../examples/themes/fantasy_ornate"),
	pixel_quest = require("../../examples/themes/pixel_quest"),
	glossy_touch = require("../../examples/themes/glossy_touch"),
	compact_pointer = require("../../examples/themes/compact_pointer"),
}

local manifestPath = `{outDir}/manifest.json`
local function artifactPath(name: string): string
	return `{outDir}/{theme_packages.artifactName(name)}.rbxm`
end

local shippable = theme_packages.shippable()
for _, name in shippable do
	if MODULES[name] == nil then
		fail(
			`'{name}' is shippable but tools/lune/theme_artifacts.luau does not require it. `
				.. `Add it to MODULES (Lune needs a literal path) — the builder emits an artifact for every `
				.. `shippable package and the manifest has to describe all of them.`,
			artifactPath(name),
			manifestPath
		)
	end
end
for name in MODULES do
	if theme_packages.NOT_SHIPPABLE[name] ~= nil or theme_packages.ROLES[name] == nil then
		fail(`MODULES names '{name}', which is not a shippable package`, artifactPath(name), manifestPath)
	end
end

local function countKeys(value: any): number
	local n = 0
	for _ in value or {} do
		n += 1
	end
	return n
end

local entries: { any } = {}
for _, name in shippable do
	local module = MODULES[name]
	local pkg, report = module.build(themes)
	if pkg == nil then
		local first = report and report.errors and report.errors[1]
		fail(
			`{name} failed its own package gate: {first and first.field} — {first and first.message}`,
			artifactPath(name),
			manifestPath
		)
	end

	local themeNames: { string } = {}
	for _, theme in pkg.style.themes do
		table.insert(themeNames, theme.name)
	end

	local chromeKinds: { [string]: string } = {}
	for slot, recipe in pkg.chrome or {} do
		chromeKinds[slot] = tostring(recipe.kind)
	end

	local artifact = theme_packages.artifactName(name)
	local file = `{outDir}/{artifact}.rbxm`
	local bytes = if fs.isFile(file) then #fs.readFile(file) else 0

	table.insert(entries, {
		module = name,
		artifact = artifact,
		file = file,
		bytes = bytes,
		packageId = pkg.identity.id,
		displayName = pkg.identity.displayName,
		version = pkg.identity.version,
		schemaVersion = pkg.identity.schemaVersion or pkg.schema,
		themes = themeNames,
		defaultTheme = pkg.style.defaultTheme,
		themeClasses = module.themeClasses,
		assetCount = countKeys(pkg.assets),
		chrome = chromeKinds,

		tenFootOverrides = countKeys(pkg.metrics and (pkg.metrics :: any).tenFoot),
	})

	if pkg.identity.version == nil or pkg.identity.schemaVersion == nil then
		fail(
			`{name}: the artifact would ship without its stamp (identity.version / identity.schemaVersion)`,
			artifactPath(name),
			manifestPath
		)
	end
end

if not fs.isDir(outDir) then
	fs.writeDir(outDir)
end
fs.writeFile(
	manifestPath,
	serde.encode("json", {
		schema = "facet-theme-artifacts/1",
		facetVersion = Facet.VERSION,
		themeSchema = themes.SCHEMA,
		packages = entries,
	}, true)
)
print(`wrote {manifestPath} ({#entries} packages, theme schema {themes.SCHEMA})`)
return nil
