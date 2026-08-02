--!strict
-- Client/server boundary static check (UI-BOUND-001, design §4.1): walks the
-- require graph of src/ and fails if
--   (a) any module OUTSIDE src/client requires a module under src/client
--       (the client renderer/platform layer must be unreachable from
--       shared/server-visible code), or
--   (b) any module under src/core, src/replication, or src/shared requires
--       the engine-only areas of the vendored Fusion copy (RobloxExternal,
--       Instances) or the vendor root init (which pulls them in).
-- Writes artifacts/boundary.json. Exit 0 only with zero violations.

local fs = require("@lune/fs")
local process = require("@lune/process")
local artifact = require("./artifact")

local violations: { { file: string, target: string, rule: string } } = {}
local scanned = 0

local function normalize(path: string): string
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function checkFile(filePath: string)
	scanned += 1
	local dir = string.match(filePath, "^(.*)/[^/]+$") or ""
	local isInit = string.match(filePath, "init%.luau$") ~= nil
	local insideClient = string.match(filePath, "^src/client/") ~= nil
	local engineFreeZone = string.match(filePath, "^src/core/") ~= nil
		or string.match(filePath, "^src/replication/") ~= nil
		or string.match(filePath, "^src/shared/") ~= nil
		or string.match(filePath, "^src/preview/") ~= nil
	for target in string.gmatch(fs.readFile(filePath), [[require%(%s*"([^"]+)"%s*%)]]) do
		local resolvedBase: string
		if string.sub(target, 1, 6) == "@self/" then
			resolvedBase = if isInit then dir .. "/" .. string.sub(target, 7) else dir .. "/" .. string.sub(target, 7)
		elseif string.sub(target, 1, 1) == "@" then
			continue -- runtime alias (@lune etc.)
		else
			-- init.luau's "./" means siblings of its directory-module
			local base = if isInit then (string.match(dir, "^(.*)/[^/]+$") or "") else dir
			resolvedBase = base .. "/" .. target
		end
		local resolved = normalize(resolvedBase)
		if not insideClient and string.match(resolved, "^src/client/") then
			table.insert(violations, { file = filePath, target = resolved, rule = "non-client-requires-client" })
		end
		if
			engineFreeZone
			and (
				string.match(resolved, "^vendor/Fusion/RobloxExternal")
				or string.match(resolved, "^vendor/Fusion/Instances/")
				or resolved == "vendor/Fusion"
			)
		then
			table.insert(
				violations,
				{ file = filePath, target = resolved, rule = "engine-free-zone-requires-engine-vendor" }
			)
		end
	end
end

local function walk(dir: string)
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.match(name, "%.luau$") then
			checkFile(path)
		end
	end
end

walk("src")

artifact.writeJson("artifacts/boundary.json", {
	schema = "luauui-boundary/1",
	status = if #violations == 0 then "PASS" else "FAIL",
	requirement = "UI-BOUND-001",
	scannedFiles = scanned,
	rules = { "non-client-requires-client", "engine-free-zone-requires-engine-vendor" },
	violations = violations,
})
for _, v in violations do
	print(`  VIOLATION [{v.rule}] {v.file} -> {v.target}`)
end
print(`boundary: {#violations == 0 and "PASS" or "FAIL"} ({scanned} files) -> artifacts/boundary.json`)
process.exit(if #violations == 0 then 0 else 1)
