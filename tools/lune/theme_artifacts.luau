--!strict
--[[ WHAT `tools/build_themes.sh` NEEDS TO KNOW ABOUT THE THEME PACKAGES.

	  lune run tools/lune/theme_artifacts -- list
	      one TSV line per SHIPPABLE package: `<module>\t<ArtifactName>`, which is
	      the loop the builder runs. Nothing else in the shell knows the corpus.

	  lune run tools/lune/theme_artifacts -- manifest [<dir>]
	      COMPILE every shippable package through the public `themes.define` and
	      write `<dir>/manifest.json` (default `build/themes`) describing what was
	      built: the identity stamp the schema requires, the themes inside it, the
	      theme classes it exercises, its declared asset count, its chrome kinds
	      and whether it declares any ten-foot metric overrides.

	THE MANIFEST IS WRITTEN FROM THE COMPILED PACKAGE, NOT FROM THE SOURCE TEXT.
	That is the point of doing it in Luau at all: a stamp scraped out of the file
	with a regex records what the author TYPED, and the thing a consumer installs
	is what `themes.define` ACCEPTED. Compiling here also means the builder cannot
	emit an artifact for a package that no longer compiles — the build fails
	instead, which is the only honest order.

	`identity.version` and `identity.schemaVersion` are the stamp the existing
	theme schema already requires of every package (`src/themes/package.luau`
	IDENTITY_FIELDS); this file does not invent a second versioning story.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Facet = require("../../src") :: any
local theme_packages = require("./theme_packages")
local themes = Facet.themes

-- `lune run <script> -- list` passes the separator through as an argument, so it
-- is dropped here rather than at every call site
local argv: { string } = {}
for _, arg in process.args do
	if arg ~= "--" then
		table.insert(argv, arg)
	end
end

local mode = argv[1]
local outDir = argv[2] or "build/themes"

--[[ REFUSE LOUDLY, AND LEAVE NOTHING BEHIND.

	THE MESSAGE COMES FIRST, and that ordering is the whole repair. This function
	read `process.exit(1)` and THEN `error(message)`; `process.exit` does not
	return, so every diagnostic in this file was dead code and a real refusal
	exited 1 with NO OUTPUT AT ALL. `tools/build_themes.sh` propagated the status
	under `set -e` and printed nothing either, so an author who added a package
	and forgot its `require` got a silent failing build and a guess. Found in
	review, 2026-08-21 — the loud-failure doctrine this framework applies to its
	public API applies to its own tools.

	AND THE PARTIAL BUILD GOES WITH IT. The shell builds every `.rbxm` BEFORE
	this file compiles the packages, so a module refused here already has an
	artifact sitting in `build/themes/` that nobody may ship. A refusal that
	leaves a plausible-looking file on disk is worse than no refusal at all: the
	next reader finds `ScifiHud.rbxm`, sees a recent timestamp, and believes it.
	Callers pass the paths their failure invalidates — always the offending
	artifact, and the manifest, which would otherwise describe a build that was
	rejected. Nothing is deleted that the caller did not name. ]]
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

--[[ the reference packages are hand-required because Lune resolves a require
	path at parse time from a LITERAL; the loop below asserts this table is
	exactly `theme_packages.shippable()`, which is the drift a hand list cannot
	catch about itself (the same arrangement `tests/theme_reference_packages.spec`
	uses, for the same reason). ]]
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
		-- wave TEN-FOOT: a package MAY pin absolute ten-foot metrics;
		-- with none declared the ladder derives, and the manifest says which it is
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
