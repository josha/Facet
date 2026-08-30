--!strict
--[[ THE PACKAGED-CONSUMER CANARY ────────────────────────────────────────────

	Everything else in this repository tests `src/`. This tests the ARTIFACT.

	`build/Facet.rbxm` is what a consumer without Rojo actually receives, and what
	the official Roblox Package is made of. Between `src/` and that file sit a
	Rojo mapping, a `globIgnorePaths`, a generated staging directory and a
	serializer — four places a module can be dropped, renamed, or quietly added,
	and a suite that requires `../src` cannot see any of them. So this canary
	takes the built model, extracts the scripts back out of it into a directory
	tree, requires THAT, and drives a real screen through it.

	WHAT IT PROVES, in order:
	  1. the extracted tree contains nothing it must not ship (no vendored copy,
	     no rejected bake-off core, no spec files);
	  2. `Facet.VERSION` inside the artifact equals the `Version` attribute the
	     builder stamped on `Facet.Distribution` — the two halves of the release
	     stamp agree, which is the one thing a manifest built from source cannot
	     check (Roblox attributes serialize to a binary blob the XML walk in
	     `tools/package.py` deliberately does not decode);
	  3. a screen mounts, a theme applies and moves geometry, a button fires
	     through the presenter's own input path, a signal update reaches the
	     rendered props, and the viewport and preferred-text facts re-solve;
	  4. two mount/dismiss laps leave the adapter's live instances and the core's
	     observer/scope registries at the same floor — the artifact leaks nothing
	     the source does not.

	The render target is `tests/lib/fake_target.luau` — the same headless adapter
	the suite uses. It reaches the repository's `src/` for the pure paint and
	content resolvers it deliberately shares with the live adapter, so this canary
	is a proof about the PACKAGED FRAMEWORK driving a
	local adapter, not a proof that the artifact is hermetic against every file on
	disk. The tree-hygiene assertions above are what covers that.

	    lune run tools/lune/package_canary

	Exit 0 on success; non-zero with a plain message on any failure.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local MODEL_XML = "build/Facet.rbxmx"
-- A FIXED extraction directory, not a random temp one. Luau's require-by-string
-- takes a literal, so the require below has to name a path that exists at edit
-- time; `build/` is gitignored, so nothing here is ever committed.
local EXTRACT_ROOT = "build/.canary"

local failures: { string } = {}

local function check(ok: boolean, message: string)
	if ok then
		print(`  [ ok ] {message}`)
	else
		table.insert(failures, message)
		print(`  [FAIL] {message}`)
	end
end

local function fail(message: string): never
	print(`  [FAIL] {message}`)
	table.insert(failures, message)
	print("")
	print(`package_canary: FAIL ({#failures} problem(s))`)
	return process.exit(1)
end

print("package_canary")

-- ── 1. read the artifact and extract its scripts ────────────────────────────

if not fs.isFile(MODEL_XML) then
	fail(`{MODEL_XML} is missing — run tools/package.sh build first`)
end

local roots = roblox.deserializeModel(fs.readFile(MODEL_XML))
if #roots ~= 1 then
	fail(`the model holds {#roots} root instances; the distribution is exactly one`)
end
local modelRoot = roots[1]
check(modelRoot.Name == "Facet", `the model's one root is named Facet (read {modelRoot.Name})`)
check(modelRoot.ClassName == "ModuleScript", `the root is a ModuleScript (read {modelRoot.ClassName})`)

if fs.isDir(EXTRACT_ROOT) then
	fs.removeDir(EXTRACT_ROOT)
end
fs.writeDir(EXTRACT_ROOT)

local extracted: { string } = {}

local function isScript(instance: any): boolean
	local class = instance.ClassName
	return class == "ModuleScript" or class == "Script" or class == "LocalScript"
end

--[[ AN INSTANCE WITH CHILDREN BECOMES A DIRECTORY; a script leaf becomes a file.
	That is the inverse of what Rojo did on the way in, which is the point — a
	renamed or relocated module shows up here as a path that does not resolve. ]]
local function extract(instance: any, dir: string)
	if isScript(instance) then
		local target = if #instance:GetChildren() > 0 then `{dir}/init.luau` else `{dir}.luau`
		if #instance:GetChildren() > 0 then
			fs.writeDir(dir)
		end
		fs.writeFile(target, instance.Source)
		table.insert(extracted, target)
	elseif #instance:GetChildren() > 0 then
		fs.writeDir(dir)
	end
	for _, child in instance:GetChildren() do
		extract(child, `{dir}/{child.Name}`)
	end
end

extract(modelRoot, `{EXTRACT_ROOT}/Facet`)
print(`  extracted {#extracted} script(s) to {EXTRACT_ROOT}/Facet`)

-- ── 2. tree hygiene ─────────────────────────────────────────────────────────

local FORBIDDEN = { "vendor", "fusion_adapter", "imperative", ".spec" }
local strays: { string } = {}
for _, path in extracted do
	local lowered = string.lower(path)
	for _, needle in FORBIDDEN do
		if string.find(lowered, needle, 1, true) ~= nil then
			table.insert(strays, `{path} (contains '{needle}')`)
		end
	end
end
check(#strays == 0, `the extracted tree ships no vendor / fusion_adapter / imperative / spec file`)
for _, stray in strays do
	print(`         - {stray}`)
end

-- ── 3. the release stamp agrees with itself ─────────────────────────────────

local distribution = modelRoot:FindFirstChild("Distribution")
if distribution == nil then
	fail("the model carries no Facet.Distribution folder")
end
check(distribution.ClassName == "Folder", `Facet.Distribution is a Folder (read {distribution.ClassName})`)
local stampedVersion = distribution:GetAttribute("Version")
local stampedSchema = distribution:GetAttribute("BuildSchema")
check(
	stampedSchema == "facet-package/1",
	`Distribution.BuildSchema is facet-package/1 (read {tostring(stampedSchema)})`
)
for _, name in { "LICENSE", "THIRD_PARTY_NOTICES" } do
	local value = distribution:FindFirstChild(name)
	check(
		value ~= nil and value.ClassName == "StringValue" and #tostring((value :: any).Value) > 0,
		`Facet.Distribution.{name} is a non-empty StringValue`
	)
end

-- ── 4. require the extracted tree and drive it ──────────────────────────────

local Facet = require("../../build/.canary/Facet") :: any
local fake_target = require("../../tests/lib/fake_target")

check(
	Facet.VERSION == stampedVersion,
	`the packaged Facet.VERSION ({tostring(Facet.VERSION)}) equals Distribution.Version ({tostring(stampedVersion)})`
)

local function newWorld()
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	-- the viewport before the presenter: a first solve against an unset viewport
	-- runs at 1x1 and every measured thing in it is wrong (tests/lib/world.luau)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	local adapter = fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system)
	return core, env, adapter, system, pres
end

local core, env, adapter, _system, pres = newWorld()

local title = core:signal("Hello")
local taps = 0

local function screen(): any
	return Facet.UI.Screen({
		id = "Canary",
		children = {
			Facet.UI.VStack({
				id = "Stack",
				children = {
					Facet.UI.Text({ id = "Title", text = title }),
					Facet.UI.Button({
						id = "Go",
						label = "Go",
						onActivate = function()
							taps += 1
						end,
					}),
				},
			}),
		},
	})
end

local handle = pres.present(screen())
pres.refresh()

local BUTTON = "/Canary/Stack/Go"
local TITLE = "/Canary/Stack/Title"

local function rectOf(path: string): any
	local node = adapter.node(path)
	return if node ~= nil then node.rect else nil
end

check(adapter.node(TITLE) ~= nil and adapter.node(BUTTON) ~= nil, "the screen mounts: Text and Button both exist")

--[[ A THEME, applied through the public path, and MEASURED rather than assumed.
	`typography.body.size` is the lever because it moves BOTH halves of the
	answer: the paint (`textSize` on the rendered node) and the geometry (the
	solved rect). A theme that changed only a colour would prove the call
	succeeded, not that it reached the solver. ]]
local plainSize = (adapter.node(TITLE) or { props = {} }).props.textSize
local plainHeight = (rectOf(TITLE) or {}).h
local themePackage, report = Facet.themes.define({
	base = Facet.themes.neutralPackage(),
	identity = {
		id = "canary-theme",
		displayName = "Canary",
		schemaVersion = Facet.themes.SCHEMA,
		version = "1.0.0",
	},
	metrics = { typography = { body = { size = 30 } } },
})
if themePackage == nil then
	fail(`themes.define refused the canary package: {tostring(report and report.problems and report.problems[1])}`)
end
env:set("themeMetrics", Facet.themes.resolve(themePackage, nil, {}))
pres.refresh()
local themedSize = (adapter.node(TITLE) or { props = {} }).props.textSize
local themedHeight = (rectOf(TITLE) or {}).h
check(
	themedSize == 30 and plainSize ~= 30 and themedHeight ~= nil and themedHeight ~= plainHeight,
	`a theme applies and reaches paint AND geometry: textSize {tostring(plainSize)} -> {tostring(themedSize)}, `
		.. `height {tostring(plainHeight)} -> {tostring(themedHeight)}`
)

-- the public input path: the adapter's activate seam, the same one the live
-- ScreenTarget drives from GuiButton.Activated
local fired = adapter.driveActivate(BUTTON, { source = "pointer", pointer = "touch" })
check(fired and taps == 1, `the button fires through the presenter's input path (taps = {taps})`)

-- a reactive update reaches the rendered props
title:set("Changed")
pres.refresh()
local titleNode = adapter.node(TITLE)
check(
	titleNode ~= nil and titleNode.props.text == "Changed",
	`a signal update reaches the rendered text (read {tostring(titleNode and titleNode.props.text)})`
)

--[[ THE ENVIRONMENT RE-SOLVES: the viewport first, then preferred text.
	Measured on the SCREEN for the viewport (the stack hugs its content, so it is
	the surface that follows the window) and on the TEXT for the preference —
	`preferredTextSize` is a multiplicative RESERVATION, not a paint value: the
	engine adds its own offset at draw time, so the honest observable is the
	reserved height, never the `textSize` prop. ]]
local narrow = (rectOf("/Canary") or {}).w
env:set("viewportRect", { x = 0, y = 0, w = 1180, h = 820 })
pres.refresh()
local wide = (rectOf("/Canary") or {}).w
check(
	narrow == 390 and wide == 1180,
	`a viewport change re-solves the surface ({tostring(narrow)} -> {tostring(wide)} wide)`
)

local reservedBefore = (rectOf(TITLE) or {}).h
env:set("preferredTextSize", 2)
pres.refresh()
local reservedAfter = (rectOf(TITLE) or {}).h
check(
	reservedBefore ~= nil and reservedAfter ~= nil and reservedAfter > reservedBefore,
	`a preferred-text change re-reserves the type ({tostring(reservedBefore)} -> {tostring(reservedAfter)} tall)`
)

-- ── 5. teardown returns the registries to their floor ───────────────────────

pres.dismiss(handle)
pres.refresh()

--[[ THE FLOOR IS MEASURED AFTER ONE FULL LAP, not before the first mount. The
	presenter owns scopes and instances for its own lifetime, so "back to zero" is
	the wrong question; "back to where the previous lap left it" is the one that
	catches a leak (tests/mount_unmount_soak.spec.luau's discipline). ]]
local floorLive = adapter.liveCount()
local floorCounters = core:counters()

for lap = 1, 3 do
	local lapHandle = pres.present(screen())
	pres.refresh()
	pres.dismiss(lapHandle)
	pres.refresh()
	local counters = core:counters()
	check(
		adapter.liveCount() == floorLive,
		`lap {lap}: live instances return to {floorLive} (read {adapter.liveCount()})`
	)
	check(
		counters.observers == floorCounters.observers and counters.scopes == floorCounters.scopes,
		`lap {lap}: core observers/scopes return to {floorCounters.observers}/{floorCounters.scopes} `
			.. `(read {counters.observers}/{counters.scopes})`
	)
end

print("")
if #failures > 0 then
	print(`package_canary: FAIL ({#failures} problem(s))`)
	for _, message in failures do
		print(`  - {message}`)
	end
	process.exit(1)
end
print("package_canary: PASS — the built artifact mounts, themes, takes input, re-solves and tears down clean")
