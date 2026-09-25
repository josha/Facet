--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local MODEL_XML = "build/Facet.rbxmx"

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

local INVALID_NAME_REASONS: { { pattern: string, why: string } } = {
	{ pattern = "/", why = "contains a path separator '/'" },
	{ pattern = "\\", why = "contains a path separator '\\'" },
	{ pattern = "%.%.", why = "contains '..', which can escape the extraction directory" },
}

local nameProblems: { string } = {}
local writtenTargets: { [string]: string } = {}

local function checkName(name: string, parentPath: string): boolean
	if name == "" then
		table.insert(nameProblems, `an instance under {parentPath} has an empty Name`)
		return false
	end
	for _, rule in INVALID_NAME_REASONS do
		if string.find(name, rule.pattern) ~= nil then
			table.insert(nameProblems, `instance name {string.format("%q", name)} under {parentPath} {rule.why}`)
			return false
		end
	end
	return true
end

local function claim(target: string, instancePath: string): boolean
	local owner = writtenTargets[target]
	if owner ~= nil then
		table.insert(nameProblems, `two instances write the same file {target}: {owner} and {instancePath}`)
		return false
	end
	writtenTargets[target] = instancePath
	return true
end

local function extract(instance: any, dir: string, instancePath: string)
	if isScript(instance) then
		local target = if #instance:GetChildren() > 0 then `{dir}/init.luau` else `{dir}.luau`
		if claim(target, instancePath) then
			if #instance:GetChildren() > 0 then
				fs.writeDir(dir)
			end
			fs.writeFile(target, instance.Source)
			table.insert(extracted, target)
		end
	elseif #instance:GetChildren() > 0 then
		fs.writeDir(dir)
	end
	for _, child in instance:GetChildren() do
		if checkName(child.Name, instancePath) then
			extract(child, `{dir}/{child.Name}`, `{instancePath}/{child.Name}`)
		end
	end
end

extract(modelRoot, `{EXTRACT_ROOT}/Facet`, "Facet")
print(`  extracted {#extracted} script(s) to {EXTRACT_ROOT}/Facet`)
check(#nameProblems == 0, `every instance name is a usable, unique single path segment`)
for _, problem in nameProblems do
	print(`         - {problem}`)
end

local FORBIDDEN = { "fusion_adapter", "imperative", ".spec" }
local APPROVED_VENDOR = {}
for path in serde.decode("json", fs.readFile("src/vendor/compose/UPSTREAM.lock")).sha256 do
	if string.match(path, "%.luau$") then
		APPROVED_VENDOR["vendor/compose/" .. path] = true
	end
end
local strays: { string } = {}
for _, path in extracted do
	local lowered = string.lower(path)
	if string.find(lowered, "/vendor/", 1, true) and not APPROVED_VENDOR[string.match(path, "/Facet/(.+)$")] then
		table.insert(strays, path .. " (unapproved vendor)")
	end
	for _, needle in FORBIDDEN do
		if string.find(lowered, needle, 1, true) ~= nil then
			table.insert(strays, `{path} (contains '{needle}')`)
		end
	end
end
check(#strays == 0, `the extracted tree ships only approved Compose vendor files and no rejected core or spec file`)
for _, stray in strays do
	print(`         - {stray}`)
end

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

local Facet = require("../../build/.canary/Facet") :: any
local engine = require("../../tests/lib/native_engine").new()
local Compose = Facet.Compose
local runtime = Facet.Roblox.createRuntime(engine)
local Host = runtime.constructors
local UI = Facet.controls(runtime, { types = engine.types })
check(Facet.VERSION == stampedVersion, "artifact version matches its distribution stamp")
local title = Compose.cell("Hello")
local taps = 0
local target = engine.new("ScreenGui")
local function screen()
	local sheet = Facet.themes.createStyleSheet(runtime, Facet.themes.neutralPackage(), { types = engine.types })
	return Host.Frame({
		Name = "Canary",
		sheet,
		Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
		UI.Text("Title")({ text = title }),
		UI.Button("Go")({
			label = "Go",
			onActivate = function()
				taps += 1
			end,
		}),
	})
end
for lap = 1, 3 do
	local close, node = runtime.mount(screen, target)
	local label = node:FindFirstChild("Title")
	local button = node:FindFirstChild("Go")
	check(label ~= nil and button ~= nil, `lap {lap}: native control tree mounts`)
	button.Activated.fire()
	check(taps == lap, `lap {lap}: native activation reaches the callback`)
	title:set(`Changed {lap}`)
	check(label.Text == `Changed {lap}`, `lap {lap}: Compose updates native text`)
	local link = node:FindFirstChildWhichIsA("StyleLink")
	check(
		link and link.StyleSheet and link.StyleSheet:IsDescendantOf(target) and #link.StyleSheet:GetChildren() > 0,
		`lap {lap}: native theme rules are linked`
	)
	close()
	check(#target:GetChildren() == 0, `lap {lap}: owned scene is removed`)
	check(button.Activated.count() == 0, `lap {lap}: owned input connection is released`)
end
runtime.dispose()
if #failures > 0 then
	for _, message in failures do
		print(`  - {message}`)
	end
	process.exit(1)
end
print("package_canary: PASS — extracted artifact mounts, binds native themes, updates, takes input and tears down")
