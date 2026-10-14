--!strict

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local process = require("@std/process")
local Assets = require("../lib/open-cloud-assets")
local Cli = require("../lib/cli")
local OrderedJson = require("../lib/ordered-json")
local Checksum = require("../lib/raster/checksum")

type Object = OrderedJson.Object

local ICON_DIRECTORY = "assets/icons"
local MANIFEST = ICON_DIRECTORY .. "/upload-manifest.json"
local REGISTRY = "src/ui/icons.luau"
local THEME_ROOT = "assets/themes"
local DEFAULT_CREATOR = "1364639953"
local DESCRIPTION =
	"Facet standard icon set. Near-white silhouette on transparency; colour comes from the theme's tintRole."

local USAGE = [[usage: lute run tools/facet icons upload [--dry-run] [--force] [--recheck]
                                       [--theme=<folder> --registry=<module>]

Upload icon PNGs as Roblox Image assets through Open Cloud. Poll each
operation until it is done. Then write the content ids into the upload
manifest and the Luau registry.

The command reads the API key only from the ROBLOX_API_KEY environment
variable. ROBLOX_CREATOR_USER_ID sets the creator user id.

options:
  --dry-run     print each request and send nothing
  --force       upload assets that already have a content id again
  --recheck     read the moderation state and asset type; upload nothing
  --theme       a theme package folder under assets/themes/
  --registry    the Luau module that receives the ids (needs --theme)]]

local function split(text: string, separator: string): { string }
	local parts: { string } = {}
	local start = 1
	while true do
		local at = string.find(text, separator, start, true)
		if at == nil then
			table.insert(parts, string.sub(text, start))
			return parts
		end
		table.insert(parts, string.sub(text, start, at - 1))
		start = at + #separator
	end
end

local function registryNames(): { [string]: string }
	local source = fs.readFileToString(REGISTRY)
	local at = string.find(source, "standard_icons.ART", 1, true)
	if at == nil then
		error(("%s declares no standard_icons.ART table"):format(REGISTRY), 0)
	end
	local names: { [string]: string } = {}
	local chunks = split(string.sub(source, at), '["')
	for index = 2, #chunks do
		local chunk = chunks[index]
		local name = split(chunk, '"]')[1]
		local asset = string.match(chunk, 'assetName = "([^"]*)"')
		if asset ~= nil then
			names[name] = asset
		end
	end
	return names
end

local function themeNames(directory: string): { [string]: string }
	local names: { [string]: string } = {}
	for _, entry in fs.listDirectory(directory) do
		if entry.type == "file" and string.sub(entry.name, -4) == ".png" then
			local stem = string.sub(entry.name, 1, -5)
			names[stem] = stem
		end
	end
	return names
end

local function sortedKeys<T>(map: { [string]: T }): { string }
	local keys: { string } = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function pngSize(data: string): (number, number)
	local function word(offset: number): number
		local a, b, c, d = string.byte(data, offset, offset + 3)
		return a * 16777216 + b * 65536 + c * 256 + d
	end
	return word(17), word(21)
end

local function writeRegistry(assets: Object, names: { [string]: string }, registry: string, field: string)
	local source = fs.readFileToString(registry)
	for _, iconName in sortedKeys(names) do
		local assetName: string = names[iconName]
		local record = OrderedJson.asObject(OrderedJson.get(assets, assetName))
		local contentId = if record ~= nil then OrderedJson.asString(OrderedJson.get(record, "contentId")) else nil
		if contentId ~= nil and contentId ~= "" then
			local anchorText = if field == "contentId"
				then ('assetName = "%s"'):format(assetName)
				else ("\n\t%s = "):format(assetName)
			local anchor = string.find(source, anchorText, 1, true)
			if anchor == nil then
				error(("%s has no entry for %s"):format(registry, assetName), 0)
			end
			local key = field .. " = "
			local start = string.find(source, key, anchor, true)
			if start == nil then
				error(("%s has no %s after %s"):format(registry, field, assetName), 0)
			end
			start += #key
			local stop = string.find(source, ",", start, true)
			if stop == nil then
				error(("%s has no ',' after %s"):format(registry, field), 0)
			end
			source = string.sub(source, 1, start - 1) .. ('"%s"'):format(contentId) .. string.sub(source, stop)
		end
	end
	fs.writeStringToFile(registry, source)
	print(("registry -> %s"):format(registry))
end

local function writeManifest(path: string, manifest: Object)
	fs.writeStringToFile(path, OrderedJson.dumps(manifest) .. "\n")
	print(("manifest -> %s"):format(path))
end

local function describeRequest(request: Assets.Request, asset: string, size: number, fields: string)
	print(("  would upload  %s"):format(asset))
	print(("    %s %s"):format(request.method, request.url))
	print("    x-api-key: $ROBLOX_API_KEY")
	print(("    Content-Type: %s"):format(request.headers["Content-Type"]))
	print(
		("    body: multipart/form-data, %d bytes (request field and %d-byte fileContent)"):format(
			#(request.body or ""),
			size
		)
	)
	print(("    request: %s"):format(fields))
	print("    then GET " .. Assets.operationUrl("<operationId>") .. " until done")
end

local function upload(invocation: Cli.Invocation): number
	local dryRun = Cli.switch(invocation, "dry-run")
	local force = Cli.switch(invocation, "force")
	local recheck = Cli.switch(invocation, "recheck")
	local key = string.gsub(process.env.ROBLOX_API_KEY or "", "^%s*(.-)%s*$", "%1")
	if key == "" and not dryRun then
		print("ROBLOX_API_KEY is not set in the environment")
		return 1
	end
	local creator = string.gsub(process.env.ROBLOX_CREATOR_USER_ID or DEFAULT_CREATOR, "^%s*(.-)%s*$", "%1")
	local theme = Cli.flag(invocation, "theme")
	local iconDirectory: string, manifestPath: string, registry: string, field: string
	local names: { [string]: string }
	if theme ~= nil then
		iconDirectory = ("%s/%s"):format(THEME_ROOT, theme)
		if not fs.exists(iconDirectory) or fs.type(iconDirectory) ~= "dir" then
			print(("no theme package folder at %s"):format(iconDirectory))
			return 1
		end
		local registryFlag = Cli.flag(invocation, "registry")
		if registryFlag == nil then
			print("--theme needs --registry=<the package's Luau module>")
			return 1
		end
		if not fs.exists(registryFlag) then
			print(("no registry at %s"):format(registryFlag))
			return 1
		end
		registry = registryFlag
		manifestPath = iconDirectory .. "/upload-manifest.json"
		field = "content"
		names = themeNames(iconDirectory)
	else
		iconDirectory, manifestPath, registry, field = ICON_DIRECTORY, MANIFEST, REGISTRY, "contentId"
		names = registryNames()
	end

	local existing = if fs.exists(manifestPath)
		then OrderedJson.asObject(OrderedJson.parse(fs.readFileToString(manifestPath)))
		else OrderedJson.object()
	if existing == nil then
		print(("%s is not a JSON object"):format(manifestPath))
		return 1
	end
	local manifest = existing :: Object
	local assets = OrderedJson.asObject(OrderedJson.get(manifest, "assets")) or OrderedJson.object()
	local options: Assets.Options = { transport = Assets.netTransport(key) }

	if recheck then
		if dryRun then
			for _, name in sortedKeys(assets.map) do
				print(("  would read  %s"):format(name))
			end
			return 0
		end
		for _, name in sortedKeys(assets.map) do
			local record = OrderedJson.asObject(assets.map[name])
			local contentId = if record ~= nil then OrderedJson.asString(OrderedJson.get(record, "contentId")) else nil
			local assetId = if contentId ~= nil then string.match(contentId, "([^/]*)$") else nil
			if record ~= nil and assetId ~= nil and assetId ~= "" then
				local state, kind = Assets.read(options, assetId)
				OrderedJson.set(record, "moderation", OrderedJson.string(state))
				OrderedJson.set(record, "assetType", OrderedJson.string(kind))
				local flag = if state == "Approved" and kind == "Image" then "" else "   <-- check"
				print(("  %-32s %-12s %s%s"):format(name, state, kind, flag))
			end
		end
		OrderedJson.set(manifest, "assets", OrderedJson.sorted(assets))
		writeManifest(manifestPath, manifest)
		writeRegistry(assets, names, registry, field)
		return 0
	end

	for _, iconName in sortedKeys(names) do
		local assetName: string = names[iconName]
		local path = ("%s/%s.png"):format(iconDirectory, assetName)
		if not fs.exists(path) then
			print(("MISSING %s; run lute run tools/facet art"):format(path))
			return 1
		end
		local record = OrderedJson.asObject(assets.map[assetName]) or OrderedJson.object()
		local current = OrderedJson.asString(OrderedJson.get(record, "contentId"))
		if current ~= nil and current ~= "" and not force then
			print(("  skip   %s  %s"):format(assetName, current))
			continue
		end
		local data = fs.readFileToString(path)
		local digest = Checksum.hex(crypto.digest(crypto.hash.sha256, data))
		local requestFields = OrderedJson.object()
		OrderedJson.set(requestFields, "assetType", OrderedJson.string("Image"))
		OrderedJson.set(requestFields, "displayName", OrderedJson.string(assetName))
		OrderedJson.set(requestFields, "description", OrderedJson.string(DESCRIPTION))
		local userId = OrderedJson.object()
		OrderedJson.set(userId, "userId", OrderedJson.string(creator))
		local creatorObject = OrderedJson.object()
		OrderedJson.set(creatorObject, "creator", userId)
		OrderedJson.set(requestFields, "creationContext", creatorObject)
		local requestJson = OrderedJson.compact(requestFields)
		local boundary = "----facet" .. string.sub(digest, 1, 32)
		local request = Assets.createRequest(
			{ { name = "request", value = requestJson } },
			{ name = "fileContent", filename = assetName .. ".png", contentType = "image/png", data = data },
			boundary
		)
		if dryRun then
			describeRequest(request, assetName, #data, requestJson)
			continue
		end
		local result: Assets.Created = Assets.create(options, request)
		local width, height = pngSize(data)
		if theme == nil then
			if OrderedJson.get(record, "sliceBorder") == nil then
				OrderedJson.set(record, "sliceBorder", OrderedJson.int(0))
			end
			if OrderedJson.get(record, "slot") == nil then
				OrderedJson.set(record, "slot", OrderedJson.string("icons." .. iconName))
			end
			if OrderedJson.get(record, "state") == nil then
				OrderedJson.set(record, "state", OrderedJson.string("default"))
			end
		end
		OrderedJson.set(record, "file", OrderedJson.string(assetName .. ".png"))
		OrderedJson.set(record, "contentId", OrderedJson.string(result.contentId))
		OrderedJson.set(record, "size", OrderedJson.string(("%dx%d"):format(width, height)))
		OrderedJson.set(record, "moderation", OrderedJson.string(result.moderation))
		OrderedJson.set(record, "sha256", OrderedJson.string(digest))
		OrderedJson.set(assets, assetName, record)
		print(("  upload %s  %s  (%s)"):format(assetName, result.contentId, result.moderation))
	end

	if dryRun then
		return 0
	end
	if theme ~= nil then
		OrderedJson.set(manifest, "assets", OrderedJson.sorted(assets))
		writeManifest(manifestPath, manifest)
		writeRegistry(assets, names, registry, field)
		return 0
	end
	local sorted = OrderedJson.sorted(assets)
	local files: { OrderedJson.Value } = {}
	for _, name in sorted.keys do
		table.insert(files, OrderedJson.string(name))
	end
	local out = OrderedJson.object()
	OrderedJson.set(out, "schema", OrderedJson.string("facet-theme-assets/1"))
	OrderedJson.set(out, "package", OrderedJson.string("facet-standard-icons"))
	OrderedJson.set(out, "stage", OrderedJson.string("compact-label"))
	OrderedJson.set(out, "uploaded", OrderedJson.string(os.date("%Y-%m-%d") :: string))
	OrderedJson.set(
		out,
		"method",
		OrderedJson.string(
			"Roblox Open Cloud POST /assets/v1/assets with assetType=Image, polled to done via "
				.. "/assets/v1/operations/<id>, by lute run tools/facet icons upload. FULLY HEADLESS -- no Studio and no "
				.. "human step, unlike the eleven per-package assets that went up through the Studio MCP "
				.. "upload_image route. assetType=Image (not Decal) returns a real Image asset, AssetTypeId 1."
		)
	)
	OrderedJson.set(
		out,
		"note",
		OrderedJson.string(
			"Framework-owned art, not a theme package: it resolves BELOW a package's own icons and "
				.. "ABOVE the ASCII fallback glyph (src/themes/package.luau resolveIcon). One near-white "
				.. "#F0F0F2 silhouette per name, no per-state variants -- tintRole owns the colour, and "
				.. "ImageColor3 multiplies, so white reaches every palette while black could only darken. "
				.. "Regenerate the PNGs with lute run tools/facet art icons."
		)
	)
	OrderedJson.set(out, "assets", sorted)
	OrderedJson.set(
		out,
		"uploadedBy",
		OrderedJson.string("compact-label stage (the standard icon set that makes compactLabel's image form usable)")
	)
	OrderedJson.set(out, "uploadedFiles", OrderedJson.array(files))
	writeManifest(manifestPath, out)
	writeRegistry(assets, names, registry, field)
	return 0
end

local function run(invocation: Cli.Invocation): number
	if invocation.positional[1] ~= "upload" then
		print(USAGE)
		return 2
	end
	local ok, result = pcall(upload, invocation)
	if not ok then
		print(("facet icons upload: %s"):format(tostring(result)))
		return 1
	end
	return result
end

local command: Cli.Command = {
	name = "icons",
	summary = "Upload icon PNGs as Roblox Image assets through Open Cloud.",
	usage = USAGE,
	run = run,
}

return command
