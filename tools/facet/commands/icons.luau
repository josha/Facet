--!strict

local fs = require("@std/fs")
local process = require("@std/process")
local Media = require("../../vendor/verify/src/codec/image")
local Assets = require("../lib/assets")
local Cli = require("../lib/cli")
local Hash = require("../lib/hash")
local Json = require("../lib/json")

type Object = Json.Object

local UPLOAD_SECONDS = 120

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

local function registryNames(): { [string]: string }
	local source = fs.readFileToString(REGISTRY)
	local at = string.find(source, "standard_icons.ART", 1, true)
	if at == nil then
		error(("%s declares no standard_icons.ART table"):format(REGISTRY), 0)
	end
	local names: { [string]: string } = {}
	local chunks = string.split(string.sub(source, at), '["')
	for index = 2, #chunks do
		local chunk = chunks[index]
		local name = string.split(chunk, '"]')[1]
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

local function writeRegistry(assets: Object, names: { [string]: string }, registry: string, field: string)
	local source = fs.readFileToString(registry)
	for _, iconName in sortedKeys(names) do
		local assetName: string = names[iconName]
		local contentId = Json.stringField(assets[assetName], "contentId")
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
	fs.writeStringToFile(path, Json.encode(manifest, { indent = 2 }) .. "\n")
	print(("manifest -> %s"):format(path))
end

local function sortedObject(object: Object): Object
	local sorted = Json.object()
	for _, key in sortedKeys(object) do
		Json.set(sorted, key, object[key])
	end
	return sorted
end

local function answered(status: number, payload: Object, label: string): Object
	if status < 200 or status >= 300 then
		error(("HTTP %d from %s\n%s"):format(status, label, string.sub(Json.encode(payload), 1, 2000)), 0)
	end
	return payload
end

local function createImage(key: string, body: string, contentType: string): (string, string)
	local status, started = Assets.call(Assets.network, "POST", "/v1/assets", key, body, contentType)
	answered(status, started, Assets.BASE .. "/v1/assets")
	local operation = Json.stringField(started, "operationId") or Json.stringField(started, "path")
	if operation == nil or operation == "" then
		error("the create call returned no operation id", 0)
	end
	local polledStatus, polled = Assets.poll(
		Assets.network,
		operation,
		key,
		Assets.realClock(),
		function() end,
		UPLOAD_SECONDS
	)
	if polledStatus == 408 then
		error(("operation %s never completed"):format(operation), 0)
	end
	answered(polledStatus, polled, Assets.BASE .. "/v1/operations/" .. operation)
	local response = Json.objectField(polled, "response") or Json.object()
	local assetId = Json.field(response, "assetId")
	if type(assetId) ~= "string" and type(assetId) ~= "number" then
		error(("operation %s finished with no assetId"):format(operation), 0)
	end
	local moderation = Json.stringField(Json.field(response, "moderationResult"), "moderationState")
	if moderation == "Rejected" then
		error("moderation rejected the asset", 0)
	end
	local assetType = Json.field(response, "assetType")
	if assetType ~= nil and assetType ~= "Image" then
		error(("the asset came back as %s, not Image"):format(tostring(assetType)), 0)
	end
	return "rbxassetid://" .. tostring(assetId), moderation or "Unknown"
end

local function readAsset(key: string, assetId: string): (string, string)
	local path = "/v1/assets/" .. assetId
	local status, info = Assets.call(Assets.network, "GET", path, key)
	answered(status, info, Assets.BASE .. path)
	local state = Json.stringField(Json.field(info, "moderationResult"), "moderationState")
	return state or "Unknown", Json.stringField(info, "assetType") or "Unknown"
end

local function describeRequest(contentType: string, bytes: number, asset: string, size: number, fields: string)
	print(("  would upload  %s"):format(asset))
	print(("    POST %s/v1/assets"):format(Assets.BASE))
	print("    x-api-key: $ROBLOX_API_KEY")
	print(("    Content-Type: %s"):format(contentType))
	print(("    body: multipart/form-data, %d bytes (request field and %d-byte fileContent)"):format(bytes, size))
	print(("    request: %s"):format(fields))
	print(("    then GET %s/v1/operations/<operationId> until done"):format(Assets.BASE))
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
		then Json.asObject(Json.decode(fs.readFileToString(manifestPath)))
		else Json.object()
	if existing == nil then
		print(("%s is not a JSON object"):format(manifestPath))
		return 1
	end
	local manifest = existing :: Object
	local assets = Json.objectField(manifest, "assets") or Json.object()

	if recheck then
		if dryRun then
			for _, name in sortedKeys(assets) do
				print(("  would read  %s"):format(name))
			end
			return 0
		end
		for _, name in sortedKeys(assets) do
			local record = Json.asObject(assets[name])
			local contentId = Json.stringField(record, "contentId")
			local assetId = if contentId ~= nil then string.match(contentId, "([^/]*)$") else nil
			if record ~= nil and assetId ~= nil and assetId ~= "" then
				local state, kind = readAsset(key, assetId)
				Json.set(record, "moderation", state)
				Json.set(record, "assetType", kind)
				local flag = if state == "Approved" and kind == "Image" then "" else "   <-- check"
				print(("  %-32s %-12s %s%s"):format(name, state, kind, flag))
			end
		end
		Json.set(manifest, "assets", sortedObject(assets))
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
		local record = Json.asObject(assets[assetName]) or Json.object()
		local current = Json.stringField(record, "contentId")
		if current ~= nil and current ~= "" and not force then
			print(("  skip   %s  %s"):format(assetName, current))
			continue
		end
		local data = fs.readFileToString(path)
		local digest = Hash.sha256(data)
		local requestFields = Json.object()
		Json.set(requestFields, "assetType", "Image")
		Json.set(requestFields, "displayName", assetName)
		Json.set(requestFields, "description", DESCRIPTION)
		local userId = Json.object()
		Json.set(userId, "userId", creator)
		local creatorObject = Json.object()
		Json.set(creatorObject, "creator", userId)
		Json.set(requestFields, "creationContext", creatorObject)
		local requestJson = Json.encode(requestFields)
		local body, contentType = Assets.form({
			{ name = "request", value = requestJson },
			{ name = "fileContent", value = data, filename = assetName .. ".png", contentType = "image/png" },
		}, "----facet" .. string.sub(digest, 1, 32))
		if dryRun then
			describeRequest(contentType, #body, assetName, #data, requestJson)
			continue
		end
		local contentId, moderation = createImage(key, body, contentType)
		local width, height = Media.pngSize(data)
		if width == nil or height == nil then
			error(("%s is not a PNG"):format(path), 0)
		end
		if theme == nil then
			if record.sliceBorder == nil then
				Json.set(record, "sliceBorder", 0)
			end
			if record.slot == nil then
				Json.set(record, "slot", "icons." .. iconName)
			end
			if record.state == nil then
				Json.set(record, "state", "default")
			end
		end
		Json.set(record, "file", assetName .. ".png")
		Json.set(record, "contentId", contentId)
		Json.set(record, "size", ("%dx%d"):format(width, height))
		Json.set(record, "moderation", moderation)
		Json.set(record, "sha256", digest)
		Json.set(assets, assetName, record)
		print(("  upload %s  %s  (%s)"):format(assetName, contentId, moderation))
	end

	if dryRun then
		return 0
	end
	if theme ~= nil then
		Json.set(manifest, "assets", sortedObject(assets))
		writeManifest(manifestPath, manifest)
		writeRegistry(assets, names, registry, field)
		return 0
	end
	local sorted = sortedObject(assets)
	local out = Json.object()
	Json.set(out, "schema", "facet-theme-assets/1")
	Json.set(out, "package", "facet-standard-icons")
	Json.set(out, "stage", "compact-label")
	Json.set(out, "uploaded", os.date("%Y-%m-%d") :: string)
	Json.set(
		out,
		"method",
		"Roblox Open Cloud POST /assets/v1/assets with assetType=Image, polled to done via "
			.. "/assets/v1/operations/<id>, by lute run tools/facet icons upload. FULLY HEADLESS -- no Studio and no "
			.. "human step, unlike the eleven per-package assets that went up through the Studio MCP "
			.. "upload_image route. assetType=Image (not Decal) returns a real Image asset, AssetTypeId 1."
	)
	Json.set(
		out,
		"note",
		"Framework-owned art, not a theme package: it resolves BELOW a package's own icons and "
			.. "ABOVE the ASCII fallback glyph (src/themes/package.luau resolveIcon). One near-white "
			.. "#F0F0F2 silhouette per name, no per-state variants -- tintRole owns the colour, and "
			.. "ImageColor3 multiplies, so white reaches every palette while black could only darken. "
			.. "Regenerate the PNGs with lute run tools/facet art icons."
	)
	Json.set(out, "assets", sorted)
	Json.set(
		out,
		"uploadedBy",
		"compact-label stage (the standard icon set that makes compactLabel's image form usable)"
	)
	Json.set(out, "uploadedFiles", Json.array(Json.keys(sorted)))
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
