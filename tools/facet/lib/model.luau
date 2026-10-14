--!strict

local process = require("@std/process")
local Files = require("./files")
local Hash = require("./hash")
local Json = require("./json")
local Run = require("./run")
local Snapshot = require("./snapshot")
local Xml = require("./xml")

export type Instance = {
	path: string,
	className: string,
	sourceSha256: string?,
}

export type Manifest = {
	schema: string,
	version: string,
	sourceCommit: string,
	sourceHash: string,
	artifact: string,
	artifactSha256: string,
	instanceCount: number,
	moduleCount: number,
	bodyHash: string,
	instances: { Instance },
}

export type Staged = {
	path: string,
	placeholders: { string },
	attributes: { [string]: string },
}

export type Script = {
	name: string,
	source: string,
}

export type Options = {
	output: string?,
	publisher: boolean?,
	root: string?,
}

local Model = {}

Model.BUILD_SCHEMA = "facet-package/1"
Model.MANIFEST_SCHEMA = "facet-package-manifest/1"
Model.DEFAULT_OUTPUT = "build/Facet.rbxm"
Model.PUBLISHER_PLACE = "build/FacetPublisher.rbxl"

local NOTICES: { { string } } = {
	{ "LICENSE", "LICENSE.txt" },
	{ "THIRD_PARTY_NOTICES.md", "THIRD_PARTY_NOTICES.txt" },
}

local sequence = 0

local function trimmed(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or ""
end

function Model.readVersion(root: string?): string
	local path = Files.join(root or ".", "src/init.luau")
	for _, line in Files.lines(Files.read(path)) do
		local version = string.match(line, 'VERSION%s*=%s*"([^"]+)"')
		if version ~= nil then
			return version
		end
	end
	error("package: src/init.luau declares no VERSION", 0)
end

function Model.sourceFiles(root: string?): { string }
	local found: { string } = {}
	for _, relative in Files.walk(Files.join(root or ".", "src")) do
		local name = Files.name(relative)
		if string.sub(name, -5) == ".luau" and string.sub(name, -10) ~= ".spec.luau" then
			table.insert(found, "src/" .. relative)
		end
	end
	table.sort(found)
	return found
end

function Model.sourceHash(root: string?): string
	local base = root or "."
	local parts: { string } = {}
	for _, relative in Model.sourceFiles(base) do
		table.insert(parts, relative .. "\n")
		local body = string.gsub(Files.read(Files.join(base, relative)), "\r\n", "\n")
		table.insert(parts, body)
	end
	return Hash.sha256(table.concat(parts))
end

function Model.headCommit(root: string?): string?
	local commit = Run.gitOutput({ "rev-parse", "HEAD" }, root or ".")
	if commit == nil then
		return nil
	end
	return trimmed(commit)
end

function Model.sourceCommit(root: string?): string
	local base = root or "."
	local commit = Model.headCommit(base)
	if commit == nil then
		return "unversioned-source"
	end
	local dirty = Run.gitOutput({ "status", "--porcelain", "--", "src" }, base) or ""
	return if trimmed(dirty) ~= "" then commit .. "-dirty" else commit
end

function Model.repositoryUrl(root: string?): string
	local url = trimmed(Run.gitOutput({ "remote", "get-url", "origin" }, root or ".") or "")
	url = string.gsub(url, "^git@([^:]+):", "https://%1/")
	url = string.gsub(url, "^https://[^@/]+@", "https://")
	url = string.gsub(url, "%.git$", "")
	return if url == "" then "unknown" else url
end

function Model.shown(root: string, path: string): string
	local absolute = Files.absolute(path)
	local base = Files.absolute(root)
	if absolute ~= base and Files.within(absolute, base) then
		return Files.relative(absolute, base)
	end
	return absolute
end

function Model.stage(root: string, outRoot: string?, quiet: boolean?): Staged
	local base = outRoot or Files.temporaryDirectory("facet-stage-")
	local target = Files.join(base, "Distribution")
	if Files.isDirectory(target) then
		Files.remove(target)
	end
	Files.makeDirectory(target)
	local attributes: { [string]: string } = {
		Version = Model.readVersion(root),
		SourceCommit = Model.sourceCommit(root),
		SourceHash = Model.sourceHash(root),
		BuildSchema = Model.BUILD_SCHEMA,
		Repository = Model.repositoryUrl(root),
	}
	local meta = { className = "Folder", attributes = attributes }
	Files.writeAtomic(Files.join(target, "init.meta.json"), Json.encode(meta, { indent = 2, sortKeys = true }) .. "\n")
	local placeholders: { string } = {}
	for _, notice in NOTICES do
		local source = Files.join(root, notice[1])
		local staged = Files.join(target, notice[2])
		if Files.isFile(source) then
			Files.copy(source, staged)
		else
			Files.write(staged, notice[1] .. " file pending\n")
			table.insert(placeholders, notice[1])
		end
	end
	if #placeholders > 0 and not quiet then
		print(("  stage: placeholder text for %s (root file not present yet)"):format(table.concat(placeholders, ", ")))
	end
	return { path = target, placeholders = placeholders, attributes = attributes }
end

local function properties(item: Xml.Element): (string, string?)
	local name = item.attributes.class or ""
	local source: string? = nil
	local list = Xml.first(item, "Properties")
	if list ~= nil then
		for _, property in list.children do
			local key = property.attributes.name
			if key == "Name" then
				if property.text ~= "" then
					name = property.text
				end
			elseif key == "Source" then
				source = property.text
			end
		end
	end
	return name, source
end

function Model.walkText(text: string): { Instance }
	local entries: { Instance } = {}
	local function visit(item: Xml.Element, prefix: string)
		local name, source = properties(item)
		local path = if prefix ~= "" then prefix .. "/" .. name else name
		local entry: Instance = { path = path, className = item.attributes.class or "" }
		if source ~= nil then
			entry.sourceSha256 = Hash.sha256(source)
		end
		table.insert(entries, entry)
		for _, child in Xml.children(item, "Item") do
			visit(child, path)
		end
	end
	for _, item in Xml.children(Xml.parse(text), "Item") do
		visit(item, "")
	end
	local order: { [Instance]: number } = {}
	for index, entry in entries do
		order[entry] = index
	end
	table.sort(entries, function(left: Instance, right: Instance): boolean
		if left.path ~= right.path then
			return left.path < right.path
		end
		return order[left] < order[right]
	end)
	return entries
end

function Model.walk(xmlPath: string): { Instance }
	return Model.walkText(Files.read(xmlPath))
end

function Model.scripts(text: string): { Script }
	local found: { Script } = {}
	for _, item in Xml.descendants(Xml.parse(text), "Item") do
		if Xml.first(item, "Properties") == nil then
			continue
		end
		local name, source = properties(item)
		if source ~= nil and source ~= "" then
			table.insert(found, { name = name, source = source })
		end
	end
	return found
end

local function encodeInstances(instances: { Instance }): Json.Array
	local encoded = Json.array()
	for _, instance in instances do
		local object = Json.object()
		Json.set(object, "path", instance.path)
		Json.set(object, "className", instance.className)
		if instance.sourceSha256 ~= nil then
			Json.set(object, "sourceSha256", instance.sourceSha256)
		end
		table.insert(encoded, object)
	end
	return encoded
end

function Model.bodyHash(instances: { Instance }): string
	return Hash.sha256(Json.canonical(encodeInstances(instances)))
end

function Model.encodeManifest(manifest: Manifest): string
	local object = Json.object()
	Json.set(object, "schema", manifest.schema)
	Json.set(object, "version", manifest.version)
	Json.set(object, "sourceCommit", manifest.sourceCommit)
	Json.set(object, "sourceHash", manifest.sourceHash)
	Json.set(object, "artifact", manifest.artifact)
	Json.set(object, "artifactSha256", manifest.artifactSha256)
	Json.set(object, "instanceCount", manifest.instanceCount)
	Json.set(object, "moduleCount", manifest.moduleCount)
	Json.set(object, "bodyHash", manifest.bodyHash)
	Json.set(object, "instances", encodeInstances(manifest.instances))
	return Json.pretty(object)
end

function Model.writeManifest(root: string, xmlPath: string, artifactPath: string, outPath: string): Manifest
	local instances = Model.walk(xmlPath)
	local modules = 0
	for _, instance in instances do
		if instance.className == "ModuleScript" then
			modules += 1
		end
	end
	local manifest: Manifest = {
		schema = Model.MANIFEST_SCHEMA,
		version = Model.readVersion(root),
		sourceCommit = Model.sourceCommit(root),
		sourceHash = Model.sourceHash(root),
		artifact = Model.shown(root, artifactPath),
		artifactSha256 = Hash.sha256(Files.read(artifactPath)),
		instanceCount = #instances,
		moduleCount = modules,
		bodyHash = Model.bodyHash(instances),
		instances = instances,
	}
	Files.writeAtomic(outPath, Model.encodeManifest(manifest))
	return manifest
end

function Model.loadManifest(path: string): Json.Object?
	if not Files.isFile(path) then
		return nil
	end
	local decoded, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		error(("package: %s is not JSON: %s"):format(path, problem), 0)
	end
	return Json.asObject(decoded)
end

local function rojo(project: unknown, output: string, projectPath: string): string?
	Files.makeDirectory(Files.parent(output))
	Files.write(projectPath, Json.pretty(project))
	local result = Run.capture({ "rojo", "build", Files.absolute(projectPath), "-o", Files.absolute(output) })
	Files.remove(projectPath)
	if not result.ok then
		local detail = trimmed(result.stdout .. "\n" .. result.stderr)
		return ("rojo build %s failed (exit %d)%s"):format(
			output,
			result.code,
			if detail ~= "" then ":\n" .. detail else ""
		)
	end
	return nil
end

function Model.build(options: Options?): (boolean, string)
	local root = if options and options.root then options.root else "."
	local output = if options and options.output then options.output else Files.join(root, Model.DEFAULT_OUTPUT)
	local publisher = options ~= nil and options.publisher == true
	local checked, verdict = Snapshot.check(root, "compose")
	if not checked then
		return false, verdict
	end
	local base, extension = string.match(output, "^(.*)%.(rbxmx?)$")
	if base == nil or extension == nil then
		return false,
			("build model: output '%s' must end in .rbxm or .rbxmx (rojo decides the format from the name)"):format(
				output
			)
	end
	sequence += 1
	local token = ("%d-%d-%d"):format(os.time(), process.pid(), sequence)
	local stageRelative = ("build/.stage.%s"):format(token)
	local stage = Files.join(root, stageRelative)
	local project = {
		name = "Facet",
		globIgnorePaths = { "**/*.spec.luau" },
		tree = { ["$path"] = "src", Distribution = { ["$path"] = stageRelative .. "/Distribution" } },
	}
	local scratch = Files.join(root, (".model_build.%s.project.json"):format(token))
	local lines: { string } = { verdict }
	local temporaries: { string } = {}
	local built, problem = pcall(function(): string?
		Files.makeDirectory(Files.join(root, "build"))
		Model.stage(root, stage, true)
		local temporary = ("%s.tmp.%s.%s"):format(base, token, extension)
		table.insert(temporaries, temporary)
		local failure = rojo(project, temporary, scratch)
		if failure ~= nil then
			return failure
		end
		Files.move(temporary, output)
		local twin = base .. ".rbxmx"
		if twin ~= output then
			local twinTemporary = ("%s.tmp.%s.rbxmx"):format(base, token)
			table.insert(temporaries, twinTemporary)
			failure = rojo(project, twinTemporary, scratch)
			if failure ~= nil then
				return failure
			end
			Files.move(twinTemporary, twin)
		end
		local manifestPath = base .. ".manifest.json"
		local manifest = Model.writeManifest(root, twin, output, manifestPath)
		table.insert(
			lines,
			("manifest %s: %d instances (%d modules), body %s"):format(
				Model.shown(root, manifestPath),
				manifest.instanceCount,
				manifest.moduleCount,
				string.sub(manifest.bodyHash, 1, 12)
			)
		)
		if publisher then
			local place = {
				name = "FacetPublisher",
				tree = {
					["$className"] = "DataModel",
					ReplicatedStorage = {
						["$className"] = "ReplicatedStorage",
						Facet = { ["$path"] = Files.absolute(output) },
					},
				},
			}
			local placeTemporary = Files.join(root, ("build/FacetPublisher.tmp.%s.rbxl"):format(token))
			table.insert(temporaries, placeTemporary)
			failure =
				rojo(place, placeTemporary, Files.join(root, (".model_build.place.%s.project.json"):format(token)))
			if failure ~= nil then
				return failure
			end
			Files.move(placeTemporary, Files.join(root, Model.PUBLISHER_PLACE))
			table.insert(lines, ("built %s (publisher place, from %s)"):format(Model.PUBLISHER_PLACE, output))
		end
		return nil
	end)
	if Files.isDirectory(stage) then
		Files.remove(stage)
	end
	for _, temporary in temporaries do
		if Files.exists(temporary) then
			Files.remove(temporary)
		end
	end
	local failure = if built then problem else tostring(problem)
	if failure ~= nil then
		table.insert(lines, failure)
		return false, table.concat(lines, "\n")
	end
	table.insert(
		lines,
		("built %s (Facet %s, %d modules)"):format(output, Model.readVersion(root), #Model.sourceFiles(root))
	)
	return true, table.concat(lines, "\n")
end

return table.freeze(Model)
