--!strict
-- Studio sync server (native-substrate verification surface, contract §5).
-- Serves the library + gallery sources over local HTTP so the Studio MCP can
-- inject/patch the running place deterministically (tools/studio/inject.luau).
--
--   lune run tools/lune/studio_sync            -- build manifest + serve on :8642
--   lune run tools/lune/studio_sync manifest   -- write build/studio_manifest.json and exit
--
-- Manifest maps repository files onto the gallery Rojo tree
-- (examples/gallery.project.json): src -> ReplicatedStorage.Facet,
-- examples/gallery/examples -> ReplicatedStorage.FacetExamples,
-- examples/gallery/client -> StarterPlayer.StarterPlayerScripts.Gallery.
-- Rojo folding: <dir>/init.luau => ModuleScript named <dir> whose Source is the
-- init file; sibling .luau files => child ModuleScripts. *.spec.luau excluded.
-- The manifest carries a content stamp so a Studio session can prove exactly
-- which source state it runs (contract §4 preflight step 2).

local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")
local process = require("@lune/process")

local PORT = 8642

type FileEntry = {
	path: string, -- dot path under game, e.g. ReplicatedStorage.Facet.layout.solver
	className: string, -- ModuleScript | LocalScript
	file: string, -- repo-relative source file
}

local entries: { FileEntry } = {}

local function addTree(fsDir: string, robloxPath: string, rootClassName: string)
	-- the directory itself: init.luau (or init.client.luau) becomes the node
	local initFile: string? = nil
	local className = rootClassName
	if fs.isFile(fsDir .. "/init.luau") then
		initFile = fsDir .. "/init.luau"
	elseif fs.isFile(fsDir .. "/init.client.luau") then
		initFile = fsDir .. "/init.client.luau"
		className = "LocalScript"
	end
	table.insert(entries, {
		path = robloxPath,
		className = if initFile then className else "Folder",
		file = initFile or "",
	})
	for _, name in fs.readDir(fsDir) do
		local full = fsDir .. "/" .. name
		if fs.isDir(full) then
			addTree(full, robloxPath .. "." .. name, "ModuleScript")
		elseif name:match("%.luau$") and not name:match("%.spec%.luau$") and not name:match("^init%.") then
			table.insert(entries, {
				path = robloxPath .. "." .. name:gsub("%.luau$", ""),
				className = "ModuleScript",
				file = full,
			})
		end
	end
end

-- TWO TREES, ONE AT A TIME (roadmap Step 9). The gallery and the performance lab
-- both mount at `ReplicatedStorage.FacetScenarios`, because the lab REUSES the
-- gallery's scenario runner rather than forking it — so serving both at once
-- would put two different `init.luau` files at the same path and the last writer
-- would win silently. The mode is explicit instead:
--
--   lune run tools/lune/studio_sync            -- the gallery tree (default)
--   lune run tools/lune/studio_sync perf       -- the performance lab tree
--   lune run tools/lune/studio_sync perf manifest
--
-- The perf mapping mirrors examples/performance.project.json exactly, including
-- the gallery runner mapped in as a child of the lab registry.
local mode = if process.args[1] == "perf" then "perf" else "gallery"

addTree("src", "ReplicatedStorage.Facet", "ModuleScript")
addTree("examples/themes", "ReplicatedStorage.FacetThemes", "Folder")
if mode == "perf" then
	addTree("examples/performance/lab", "ReplicatedStorage.FacetScenarios", "ModuleScript")
	table.insert(entries, {
		path = "ReplicatedStorage.FacetScenarios.runner",
		className = "ModuleScript",
		file = "examples/gallery/scenarios/runner.luau",
	})
	addTree("examples/performance/client", "StarterPlayer.StarterPlayerScripts.PerfLab", "ModuleScript")
else
	addTree("examples/gallery/examples", "ReplicatedStorage.FacetExamples", "Folder")
	addTree("examples/gallery/scenarios", "ReplicatedStorage.FacetScenarios", "ModuleScript")
	addTree("examples/gallery/client", "StarterPlayer.StarterPlayerScripts.Gallery", "ModuleScript")
	-- swiftui-reference-app-validation: the five clean-room reference proofs,
	-- mirrored from gallery.project.json's FacetReference mapping
	addTree("examples/reference", "ReplicatedStorage.FacetReference", "Folder")
end
-- vendored Fusion is not needed by the gallery runtime path; skip.

-- content stamp: order-stable concatenated sizes+paths hashed cheaply.
--
-- RECOMPUTED PER REQUEST (2026-07-26). It used to be computed once at server
-- start, so a source file edited while the server ran was SERVED fresh while
-- the stamp still described the old tree — and the stamp is exactly what the
-- Studio preflight uses to certify "the running place carries the source state
-- just built". A stamp that can certify a state it does not describe is worse
-- than no stamp. 123 files is nothing to re-read.
local function buildManifest(): any
	local stampParts: { string } = {}
	local totalBytes = 0
	for _, e in entries do
		if e.file ~= "" then
			local src = fs.readFile(e.file)
			totalBytes += #src
			table.insert(stampParts, e.path .. ":" .. tostring(#src))
		end
	end
	-- djb2 over the parts string (Lune has no crypto in std; determinism is enough)
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
		-- EVIDENCE DROP. A Studio client cannot write files and cannot make HTTP
		-- requests during Play (those are server-only), so a driver row otherwise
		-- has to be copied out by hand — which is slow and, worse, a step where a
		-- record can be edited between the instrument and the artifact. The
		-- client fires a RemoteEvent, the server POSTs here, and the row lands on
		-- disk byte-for-byte as the driver emitted it.
		--
		-- Development-only, bound to 127.0.0.1, and it refuses to write anywhere
		-- but the stage's own row directory.
		local name = request.query.name or ""
		if not string.match(name, "^[%w%-_]+$") then
			return { status = 400, body = "bad name" }
		end
		-- The stage directory is an ALLOWLIST, not a free path: this route exists so
		-- a driver row lands byte-for-byte as the instrument emitted it, and a route
		-- that could write anywhere would be a different kind of tool.
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
	elseif path == "/driver" then
		-- the Studio device-matrix driver, served verbatim so the copy installed
		-- in the open place cannot drift from the repository copy. Deliberately
		-- NOT in the manifest: it is development tooling, not library source and
		-- not a shipped example (studio-device-verification.md).
		return { status = 200, body = fs.readFile("tools/studio/device_matrix.luau") }
	elseif path == "/visual_diff" then
		-- the visual-regression harness, served the same way and for the same reason:
		-- the copy running in the open place must not drift from the repository copy
		return { status = 200, body = fs.readFile("tools/studio/visual_diff.luau") }
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
-- net.serve keeps the process alive until killed
