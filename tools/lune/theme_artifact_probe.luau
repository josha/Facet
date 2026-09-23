--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Facet = require("../../src")
local engineLib = require("../../tests/lib/native_engine")
local themes, Compose = Facet.themes, Facet.Compose
local failures, checks = {}, 0
local function check(ok, message)
	checks += 1
	if not ok then
		table.insert(failures, message)
	end
end
if not fs.isFile("installed/expected.json") then
	print("theme_artifact_probe requires the isolated tree from tools/check_theme_artifacts.py")
	process.exit(2)
end
local expected = serde.decode("json", fs.readFile("installed/expected.json"))
local function inspect(entry)
	local name = entry.artifact
	local module = require("../../installed/" .. name)
	assert(type(module) == "table" and type(module.build) == "function", name .. ": artifact exposes no build(themes)")
	local package, report = module.build(themes)
	assert(package and report.ok, name .. ": build() refused the theme package")
	check(package.schema == themes.SCHEMA, name .. ": theme schema mismatch")
	check(package.identity.id == entry.packageId, name .. ": artifact identity differs from manifest")
	check(package.identity.version == entry.version, name .. ": artifact version differs from manifest")
	check(
		package.identity.schemaVersion == entry.schemaVersion,
		name .. ": artifact schemaVersion differs from manifest"
	)
	check(table.isfrozen(package.metrics), name .. ": compiled metrics are mutable")
	check(themes.checkCoverage(package, {}).ok, name .. ": coverage rejected compiled package")
	local missing = themes.checkCoverage(
		package,
		{ { name = "probe:dial", section = "metrics.controlSizes", fields = { "height" } } }
	)
	check(not missing.ok and missing.missing[1].name == "probe:dial", name .. ": missing contribution was accepted")
	for _, palette in entry.themes do
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local Host = runtime.constructors
		local UI = Facet.controls(runtime, { types = engine.types, theme = package })
		local sheet, button
		local stop = runtime.mount(function()
			sheet = themes.createStyleSheet(runtime, package, { types = engine.types, theme = palette })
			button = UI.Button({ label = "Play" })
			return Host.Frame({
				sheet,
				Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				UI.Label({ text = "Theme artifact" }),
				button,
			})
		end, engine.new("Folder"))
		check(
			button:IsA("TextButton") and button.Text == "Play",
			name .. "/" .. palette .. ": native control did not mount"
		)
		check(#sheet:GetChildren() > 30, name .. "/" .. palette .. ": native theme rules are missing")
		check(
			button.Size.Y.Offset == package.metrics.controlSizes.regular.height,
			name .. "/" .. palette .. ": semantic control height was lost"
		)
		stop()
		check(
			button.isDestroyed() and sheet.isDestroyed(),
			name .. "/" .. palette .. ": Compose nodes survived unmount"
		)
		runtime:dispose()
	end
end
for _, entry in expected.packages do
	local ok, failure = pcall(inspect, entry)
	if not ok then
		table.insert(failures, entry.artifact .. ": " .. tostring(failure))
	end
end
if #failures > 0 then
	print(`theme_artifact_probe: {#failures} of {checks} checks FAILED`)
	for _, message in failures do
		print("  - " .. message)
	end
	process.exit(1)
end
print(`theme_artifact_probe: {#expected.packages} isolated theme artifacts, {checks} native structure checks OK`)
