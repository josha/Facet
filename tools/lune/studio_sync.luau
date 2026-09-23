--!strict

local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")
local process = require("@lune/process")
local studio_tree = require("./lib/studio_tree")

local PORT = 8642

type FileEntry = studio_tree.FileEntry

local mode = if process.args[1] == "perf" then "perf" else "gallery"

local entries: { FileEntry } = studio_tree.entries(mode)

local function buildManifest(): any
	entries = studio_tree.entries(mode)
	local stampParts: { string } = {}
	local totalBytes = 0
	for _, e in entries do
		if e.file ~= "" then
			local src = fs.readFile(e.file)
			totalBytes += #src
			table.insert(stampParts, e.path .. ":" .. tostring(#src))
		end
	end

	local stampInput = table.concat(stampParts, ";")
	local hash = 5381
	for i = 1, #stampInput do
		hash = (hash * 33 + string.byte(stampInput, i)) % 4294967296
	end
	return {
		schema = "facet-studio-sync/1",
		stamp = string.format("%08x-%d", hash, totalBytes),
		port = PORT,
		files = entries,
	}
end

local manifest = buildManifest()

fs.writeDir("build")
fs.writeFile("build/studio_manifest.json", serde.encode("json", manifest, true))
print(`studio_sync: [{mode}] manifest {#entries} nodes, stamp {manifest.stamp}`)

if process.args[1] == "manifest" or process.args[2] == "manifest" then
	return
end

net.serve(PORT, function(request)
	local path = request.path
	if path == "/manifest" then
		manifest = buildManifest()
		fs.writeFile("build/studio_manifest.json", serde.encode("json", manifest, true))
		return { status = 200, body = serde.encode("json", manifest) }
	elseif path == "/save" then
		local name = request.query.name or ""
		if not string.match(name, "^[%w%-_]+$") then
			return { status = 400, body = "bad name" }
		end

		local DIRS: { [string]: string } = {
			matrix = "artifacts/cross-platform-proof/rows/matrix",
			perf = "artifacts/performance-stress-places/studio",
		}
		local dir = DIRS[request.query.dir or "matrix"]
		if dir == nil then
			return { status = 400, body = "unknown dir" }
		end
		fs.writeDir(dir)
		local target = `{dir}/{name}.json`
		fs.writeFile(target, request.body)
		print(`studio_sync: saved {target} ({#request.body} bytes)`)
		return { status = 200, body = target }
	elseif path:sub(1, 6) == "/file/" then
		local idx = tonumber(path:sub(7))
		local entry = idx and manifest.files[idx]
		if entry and entry.file ~= "" then
			return { status = 200, body = fs.readFile(entry.file) }
		end
		return { status = 404, body = "no such file index" }
	end
	return { status = 404, body = "unknown route" }
end)
print(`studio_sync: serving on http://127.0.0.1:{PORT} (manifest at /manifest, sources at /file/<index>)`)
