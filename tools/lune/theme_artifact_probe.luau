--!strict
--[[ THE SELF-CONTAINMENT PROOF, RUN INSIDE AN ISOLATED TREE.

	THIS SCRIPT IS NOT RUN FROM THIS REPOSITORY. `tools/check_theme_artifacts.py`
	assembles a throwaway directory that mirrors the library's shape and NOTHING
	ELSE — no `examples/`, no gallery, no fixtures:

	    <T>/src/                      a copy of the library
	    <T>/tests/lib/{world,fake_target}.luau   the headless world
	    <T>/tools/lune/theme_artifact_probe.luau THIS FILE
	    <T>/installed/<Name>.luau     the Source EXTRACTED FROM THE BUILT .rbxm
	    <T>/installed/expected.json   what build/themes/manifest.json claims

	...and runs `lune run tools/lune/theme_artifact_probe` with `<T>` as the
	working directory. Every require below resolves the same way in both trees,
	so the file stays readable and `stylua` still formats it; run it here and it
	fails on the missing `installed/` directory, which is the honest answer.

	WHY THE ISOLATION IS THE WHOLE TEST. A reference package's own header claims
	it touches the framework through `themes.define` and `themes.neutralPackage`
	and nothing else. In-repo that claim is unfalsifiable: `examples/` is one
	directory up, so a package that quietly required the gallery's theme picker
	would compile, pass the suite, and fail only for the first consumer who
	installed the artifact on its own. Here there is nothing above `installed/`
	to reach, so a package that reaches fails AT REQUIRE TIME.

	WHAT EACH PACKAGE HAS TO SURVIVE, per artifact:
	  1. the extracted Source loads and `build(themes)` compiles it;
	  2. its identity STAMP is the one the manifest published (id, version,
	     schemaVersion) — an artifact that lost its stamp in the build is not the
	     package anybody reviewed;
	  3. `themes.checkCoverage` accepts it as a compiled package, and is LIVE
	     rather than always-true (an undeclared namespaced need is reported);
	  4. `theme_controller.install` installs it on a bare adapter and one real
	     control MOUNTS under it, once per theme the package declares;
	  5. the same mount at a TEN-FOOT display class resolves the metric ladder
	     (ADR-0039): every scalable metric moves by `themes.metricScale`, and a
	     package's own `metrics.tenFoot` pins, if it declares any, arrive in the
	     artifact and beat the derivation.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Facet = require("../../src") :: any
local world = require("../../tests/lib/world")
local theme_controller = require("../../src/client/theme_controller")

local themes = Facet.themes

local failures: { string } = {}
local checks = 0

local function check(ok: boolean, message: string)
	checks += 1
	if not ok then
		table.insert(failures, message)
	end
end

if not fs.isFile("installed/expected.json") then
	print("theme_artifact_probe: no installed/expected.json — this script runs inside the isolated tree")
	print("  tools/check_theme_artifacts.py assembles, not from the library repository. See its header.")
	process.exit(2)
end

local expected: any = serde.decode("json", fs.readFile("installed/expected.json"))

-- a real screen, not a marker: a Button is themed on every axis this proves
-- (control size, radius, stroke, palette, typography), so a package that
-- resolves but paints nothing has somewhere to fail
local function screen(): any
	return Facet.UI.Screen({
		id = "S",
		children = {
			Facet.UI.Text({ id = "Title", text = "Theme artifact" }),
			Facet.UI.Button({ id = "Go", label = "Play" }),
		},
	})
end

local function mountedRect(w: any, path: string): any
	local node = w.adapter.node(path)
	return node and node.rect
end

--[[ ONE PACKAGE, EVERY CLAIM — and NOTHING here may throw past this function.
	A probe that stack-traces on the defect it exists to find is a poor
	instrument: the caller gets a Lune traceback instead of the sentence naming
	the package and what it did. So the body runs under `pcall` and an error
	becomes a reported failure like any other. (Measured: the first --selftest
	run crashed on an artifact whose body had been emptied, and reported nothing
	about which artifact it was.) ]]
local function inspect(entry: any)
	local name: string = entry.artifact
	local moduleOk, module = pcall(function(): any
		return (require :: any)(`../../installed/{name}`)
	end)
	if not moduleOk then
		table.insert(
			failures,
			`{name}: the extracted artifact does not even LOAD in a tree with no examples/ above it — `
				.. `{tostring(module)}`
		)
		return
	end
	if type(module) ~= "table" or type((module :: any).build) ~= "function" then
		table.insert(
			failures,
			`{name}: the artifact returns no theme package — a shippable module exposes `
				.. `build(themes) -> (package, report), and this one exposes {typeof(module)}`
		)
		return
	end

	-- (1) compiles through the public surface
	local pkg, report = (module :: any).build(themes)
	if pkg == nil then
		local first = report and report.errors and report.errors[1]
		table.insert(failures, `{name}: build() was refused: {first and first.field} — {first and first.message}`)
		return
	end

	-- (2) the stamp the manifest published rode INTO the artifact
	check(pkg.schema == themes.SCHEMA, `{name}: compiled against schema {tostring(pkg.schema)}, not {themes.SCHEMA}`)
	check(
		pkg.identity.id == entry.packageId,
		`{name}: artifact identity '{tostring(pkg.identity.id)}' != manifest '{entry.packageId}'`
	)
	check(
		pkg.identity.version == entry.version,
		`{name}: artifact version '{tostring(pkg.identity.version)}' != manifest '{entry.version}'`
	)
	check(
		pkg.identity.schemaVersion == entry.schemaVersion,
		`{name}: artifact schemaVersion '{tostring(pkg.identity.schemaVersion)}' != manifest '{entry.schemaVersion}'`
	)

	-- (3) the pre-play gate accepts it, and is live
	local accepted = themes.checkCoverage(pkg, {})
	check(accepted.ok == true, `{name}: checkCoverage refused the artifact as a compiled package`)
	local probed = themes.checkCoverage(pkg, { { name = "probe:dial", kind = "controlSize" } })
	check(
		probed.ok == false and probed.missing[1] ~= nil and probed.missing[1].name == "probe:dial",
		`{name}: checkCoverage reported no gap for a role no package declares — the gate is not live`
	)

	-- (4) install + mount, once per declared theme
	for _, themeName in entry.themes do
		local w = world.new({ viewport = { x = 0, y = 0, w = 960, h = 600 } })
		local installed, controller = pcall(function(): any
			return theme_controller.install(w.adapter, pkg, { env = w.env, theme = themeName })
		end)
		if not installed then
			table.insert(failures, `{name}/{themeName}: install failed — {tostring(controller)}`)
			continue
		end
		check(
			(controller :: any).current() == themeName,
			`{name}/{themeName}: the controller settled on '{tostring((controller :: any).current())}'`
		)
		local snap = w.env:get("themeMetrics"):get()
		check(
			snap.identity.packageId == entry.packageId and snap.identity.themeName == themeName,
			`{name}/{themeName}: the committed snapshot names {tostring(snap.identity.packageId)}/`
				.. `{tostring(snap.identity.themeName)}`
		)
		w.present(screen())
		local rect = mountedRect(w, "/S/Go")
		check(
			rect ~= nil and rect.w > 0 and rect.h > 0,
			`{name}/{themeName}: the button did not mount at a drawable size ({tostring(rect and rect.w)}x`
				.. `{tostring(rect and rect.h)})`
		);
		(controller :: any).uninstall()
	end

	--[[ (5) TEN FOOT (ADR-0039). The environment applies `forDisplay` at its
		`themeMetrics` read, so this needs no theme opt-in beyond the install
		above: a television and a desktop differ by ONE fact. The assertion is the
		IDENTITY, never the number — `metricScale` is the published factor and the
		ladder either follows it or it does not. ]]
	local near = world.new({ viewport = { x = 0, y = 0, w = 1920, h = 1080 } })
	theme_controller.install(near.adapter, pkg, { env = near.env })
	local nearSnap = near.env:get("themeMetrics"):get()

	local far = world.new({ viewport = { x = 0, y = 0, w = 1920, h = 1080 }, displaySize = "Large" })
	theme_controller.install(far.adapter, pkg, { env = far.env })
	local farSnap = far.env:get("themeMetrics"):get()

	local factor = themes.metricScale("Large")
	check(factor > 1, `metricScale reports {factor} at a Large display class — the ladder is inert`)

	local pins: any = (pkg.metrics :: any).tenFoot
	local pinned: { [string]: number } = {}
	for path, value in pins or {} do
		pinned[path] = value
	end

	--[[ THE LADDER MOVED BY THE PUBLISHED FACTOR, WITHIN THE PACKAGE'S OWN PIXEL
		GRID. Not `== near * factor`: a pixel-mode package snaps every resolved
		metric UP to its unit, so `pixel-quest` (unit 4) lands its ten-foot hit
		floor on 68 rather than 66 and that is the package being obeyed, not the
		ladder being wrong — measured here the first time this ran. `pixelUnit` is
		a PUBLISHED field of the resolved snapshot, so naming it as the tolerance
		reads the framework's answer instead of re-deriving its rule. ]]
	local unit: number = if type(nearSnap.pixelUnit) == "number" then nearSnap.pixelUnit else 0
	local function laddered(path: string, nearValue: number, farValue: number)
		if pinned[path] ~= nil then
			check(
				farValue >= pinned[path],
				`{name}: metrics.tenFoot pinned {path} = {pinned[path]}, the artifact resolved {farValue}`
			)
			return
		end
		check(
			farValue >= nearValue * factor and farValue <= nearValue * factor + unit,
			`{name}: the ten-foot {path} is {farValue}; the ladder puts it at {nearValue * factor} `
				.. `(+0..{unit} of this package's pixel grid)`
		)
	end
	laddered("targetSizes.minimum", nearSnap.targetSizes.minimum, farSnap.targetSizes.minimum)
	laddered("controlSizes.regular.height", nearSnap.controlSizes.regular.height, farSnap.controlSizes.regular.height)
	laddered("space.m", nearSnap.space.m, farSnap.space.m)
	-- the manifest count and the artifact agree: a pin that did not survive the
	-- build would leave the manifest claiming declarations that are gone
	local pinCount = 0
	for _ in pinned do
		pinCount += 1
	end
	check(
		pinCount == entry.tenFootOverrides,
		`{name}: the artifact carries {pinCount} metrics.tenFoot pins, the manifest recorded `
			.. `{entry.tenFootOverrides}`
	)

	-- ...and a control still mounts at three metres
	far.present(screen())
	local farRect = mountedRect(far, "/S/Go")
	check(farRect ~= nil and farRect.h > 0, `{name}: the button did not mount at a ten-foot display class`)
	if farRect ~= nil then
		local nearWorld = world.new({ viewport = { x = 0, y = 0, w = 1920, h = 1080 } })
		theme_controller.install(nearWorld.adapter, pkg, { env = nearWorld.env })
		nearWorld.present(screen())
		local nearRect = mountedRect(nearWorld, "/S/Go")
		check(
			nearRect ~= nil and farRect.h > nearRect.h,
			`{name}: the button is {tostring(farRect.h)}px at three metres and `
				.. `{tostring(nearRect and nearRect.h)}px at a desk — the chrome did not grow with the type`
		)
	end
end

for _, entry in expected.packages do
	local ok, err = pcall(inspect, entry)
	if not ok then
		table.insert(failures, `{entry.artifact}: {tostring(err)}`)
	end
end

if #failures > 0 then
	print(`theme_artifact_probe: {#failures} of {checks} checks FAILED`)
	for _, message in failures do
		print(`  - {message}`)
	end
	process.exit(1)
end

print(`theme_artifact_probe: {#expected.packages} artifacts installed against a bare library, {checks} checks OK`)
return nil
