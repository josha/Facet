--!strict

local Files = require("./files")
local Json = require("./json")
local Rojo = require("./rojo")
local Run = require("./run")

export type Listed = { module: string, artifact: string }

local ThemeBuilds = {}

ThemeBuilds.OUTPUT = "build/themes"
ThemeBuilds.MANIFEST = "build/themes/manifest.json"
ThemeBuilds.SCRATCH = ".theme_build.project.json"

function ThemeBuilds.parseListing(listing: string): { Listed }
	local listed: { Listed } = {}
	for line in string.gmatch(listing, "[^\r\n]+") do
		local module, artifact = string.match(line, "^([^\t]+)\t([^\t]+)$")
		if module ~= nil and artifact ~= nil then
			table.insert(listed, { module = module, artifact = artifact })
		end
	end
	return listed
end

function ThemeBuilds.one(root: string, source: string, name: string, output: string, quiet: boolean?): Rojo.Outcome
	local normalized = Files.normalize(source)
	if not Files.isFile(Rojo.locate(root, normalized)) then
		return Rojo.failure(`build themes: no such theme module: {source}`)
	end
	local tree: Json.Object = { ["$path"] = normalized }
	local project: Json.Object = { name = name, tree = tree }
	return Rojo.build(project, output, { cwd = root, scratch = ThemeBuilds.SCRATCH, quiet = quiet })
end

function ThemeBuilds.all(root: string, quiet: boolean?): Rojo.Outcome
	local listing = Run.capture({ Run.lute(), "run", "tools/engine/theme_artifacts.luau", "list" }, { cwd = root })
	local count = 0
	for _, entry in ThemeBuilds.parseListing(if listing.ok then listing.stdout else "") do
		if Files.isDirectory(Files.join(root, `examples/themes/{entry.module}`)) then
			return Rojo.failure(
				`build themes: examples/themes/{entry.module}/ exists — this package now owns runtime data beside its module, and this build only maps the module. Extend the theme build before shipping it.`
			)
		end
		local built = ThemeBuilds.one(
			root,
			`examples/themes/{entry.module}.luau`,
			entry.artifact,
			`{ThemeBuilds.OUTPUT}/{entry.artifact}.rbxm`,
			quiet
		)
		if not built.ok then
			return built
		end
		count += 1
	end
	if count == 0 then
		local detail = if listing.ok then "" else "\n" .. listing.stdout .. listing.stderr
		return Rojo.failure(
			"build themes: the enumerator listed no shippable packages — that is a bug, not an empty product"
				.. detail
		)
	end
	local manifest = Rojo.run(
		{ Run.lute(), "run", "tools/engine/theme_artifacts.luau", "manifest", ThemeBuilds.OUTPUT },
		{ cwd = root, quiet = quiet }
	)
	if not manifest.ok then
		return manifest
	end
	return Rojo.success(`built {count} theme artifacts into {ThemeBuilds.OUTPUT}/`)
end

return table.freeze(ThemeBuilds)
