--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

local fs = require("@std/fs")
local process = require("@std/process")
local Lute = require("../vendor/verify/src/lute")
local Base64 = require("../facet/lib/base64")
local Files = require("../facet/lib/files")
local Xml = require("../facet/lib/xml")
local Loader = require("../../tests/lib/loader")

type Node = {
	Name: string,
	ClassName: string,
	Source: string?,
	Value: string?,
	attributes: { [string]: unknown },
	children: { Node },
	GetChildren: (Node) -> { Node },
	FindFirstChild: (Node, string) -> Node?,
	GetAttribute: (Node, string) -> unknown,
}

local MODEL_XML = "build/Facet.rbxmx"

local function attributes(encoded: string): { [string]: unknown }
	local data = buffer.fromstring(Base64.decode((string.gsub(encoded, "%s", ""))))
	local cursor = 0
	local function u32(): number
		local value = buffer.readu32(data, cursor)
		cursor += 4
		return value
	end
	local function text(): string
		local length = u32()
		local value = buffer.readstring(data, cursor, length)
		cursor += length
		return value
	end
	local values: { [string]: unknown } = {}
	if buffer.len(data) < 4 then
		return values
	end
	for _ = 1, u32() do
		local name = text()
		local kind = buffer.readu8(data, cursor)
		cursor += 1
		if kind == 0x02 then
			values[name] = text()
		elseif kind == 0x03 then
			values[name] = buffer.readu8(data, cursor) ~= 0
			cursor += 1
		elseif kind == 0x06 then
			values[name] = buffer.readf64(data, cursor)
			cursor += 8
		else
			break
		end
	end
	return values
end

local function node(item: Xml.Element): Node
	local built = {
		Name = "",
		ClassName = item.attributes.class or "",
		attributes = {},
		children = {},
	} :: Node
	local declared = Xml.first(item, "Properties")
	if declared ~= nil then
		for _, property in declared.children do
			local name = property.attributes.name
			if name == "Name" then
				built.Name = property.text
			elseif name == "Source" then
				built.Source = property.text
			elseif name == "Value" then
				built.Value = property.text
			elseif name == "AttributesSerialize" and property.text ~= "" then
				built.attributes = attributes(property.text)
			end
		end
	end
	for _, child in Xml.children(item, "Item") do
		table.insert(built.children, node(child))
	end
	built.GetChildren = function(self: Node): { Node }
		return self.children
	end
	built.FindFirstChild = function(self: Node, name: string): Node?
		for _, child in self.children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	built.GetAttribute = function(self: Node, name: string): unknown
		return self.attributes[name]
	end
	return built
end

local function deserializeModel(text: string): { Node }
	local roots: { Node } = {}
	for _, item in Xml.children(Xml.parse(text), "Item") do
		table.insert(roots, node(item))
	end
	return roots
end

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

if not fs.exists(MODEL_XML) then
	fail(`{MODEL_XML} is missing — run lute run tools/facet package build first`)
end

local roots = deserializeModel(fs.readFileToString(MODEL_XML))
if #roots ~= 1 then
	fail(`the model holds {#roots} root instances; the distribution is exactly one`)
end
local modelRoot = roots[1]
check(modelRoot.Name == "Facet", `the model's one root is named Facet (read {modelRoot.Name})`)
check(modelRoot.ClassName == "ModuleScript", `the root is a ModuleScript (read {modelRoot.ClassName})`)

if Files.isDirectory(EXTRACT_ROOT) then
	Files.remove(EXTRACT_ROOT)
end
Files.makeDirectory(EXTRACT_ROOT)

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
				Files.makeDirectory(dir)
			end
			Files.write(target, instance.Source or "")
			table.insert(extracted, target)
		end
	elseif #instance:GetChildren() > 0 then
		Files.makeDirectory(dir)
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
for path in (Lute.parse(fs.readFileToString("src/vendor/compose/UPSTREAM.lock")) :: any).sha256 do
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
check(
	assert(distribution).ClassName == "Folder",
	`Facet.Distribution is a Folder (read {assert(distribution).ClassName})`
)
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

local loader = Loader.new()
local Facet = loader.require("build/.canary/Facet") :: any
local engines = loader.require("tests/lib/native_engine.luau") :: typeof(require("../../tests/lib/native_engine"))
local engine = engines.new()
local Compose: ComposeModule = Facet.Compose
local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
local Host = (runtime.constructors :: unknown) :: RobloxHost
local UI = Facet.controls(runtime, { types = engine.types })
check(Facet.VERSION == stampedVersion, "artifact version matches its distribution stamp")
local title = Compose.cell("Hello")
local taps = 0
local target = engine.new("ScreenGui")
local function screen()
	local sheet = Facet.themes.createStyleSheet(runtime, Facet.themes.neutralPackage(), { types = engine.types })
	return Host.Frame({
		Name = "Canary",
		sheet :: unknown,
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
	local close, node: any = runtime.mount(screen, target)
	local label = node:FindFirstChild("Title")
	local button = node:FindFirstChild("Go")
	check(label ~= nil and button ~= nil, `lap {lap}: native control tree mounts`)
	button.Activated:Fire()
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
	check(engines.connections(button.Activated) == 0, `lap {lap}: owned input connection is released`)
end
runtime:dispose()
if #failures > 0 then
	for _, message in failures do
		print(`  - {message}`)
	end
	process.exit(1)
end
print("package_canary: PASS — extracted artifact mounts, binds native themes, updates, takes input and tears down")
